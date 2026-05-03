classdef CircuitCuttingViewModel < handle
    % CircuitCuttingViewModel  Callbacks + state for the Circuit Cutting tab.
    %
    %   Three modes share one backend pipeline; only the UI auto-fill differs:
    %     * Automatic — one-click run, everything auto-selected.
    %     * Assisted  — defaults pre-filled via /api/cutting/analyze, user
    %                   can override any field. Default mode.
    %     * Manual    — blank form, user enters cuts/backends/observables.
    %
    %   The batch lifecycle is async: create → 202 → poll every 3 s until
    %   a terminal status ('completed', 'failed', 'cancelled',
    %   'partial_failure'), then fetch the reconstructed result.

    properties
        App
        CurrentMode               = "assisted"
        CurrentPreset             = "generic"
        LastAnalyze               = []
        ActiveBatchId             = ''
        PollTimer                 = []
        LastRefresh               = []
        LastCuttabilityCircuitId  = ''   % Cache key for the QASM scan
        LastCuttabilityResult     = []   % Cached struct from checkQasmCuttable
        BackendPool               = {}   % cached cell of struct {name, num_qubits} from /api/backends
        RowControls               = {}   % per-row {nameDropdown, shotsField} for editable assignments
    end

    properties (Constant)
        % Single source of truth for the Observables textarea placeholder.
        % Screen uses it to seed the widget; parseObservables uses it to
        % recognize and drop the line so it never gets sent as a Pauli string.
        OBSERVABLES_PLACEHOLDER = '(auto: per-qubit Z + nearest-neighbor ZZ)'
    end

    methods
        function obj = CircuitCuttingViewModel(app)
            obj.App = app;
        end

        function delete(obj)
            % Stop the poll timer when the VM is destroyed (e.g. app close)
            % so MATLAB does not keep firing pollTick against a dead handle.
            obj.stopPolling();
        end

        % ── Entry hook ───────────────────────────────────────────────────
        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            obj.loadCircuits();
            obj.loadPresets();
            obj.loadBackendPool();
            obj.refreshStatus();
            obj.LastRefresh = tic;
        end

        % ── Backend pool ─────────────────────────────────────────────────
        function loadBackendPool(obj)
            % Pull the live IBM fleet (with widths) from /api/backends so
            % the Backend Assignments rows can render real per-row pickers
            % and the pre-flight check can validate width vs subcircuit.
            %
            % Reuses the session-level cache on AppState (5 min TTL) when
            % fresh — the same /api/backends response is also consumed by
            % the Backends, Benchmark Dashboard, and Prediction screens,
            % so caching once saves 0.3–0.5 s per subsequent screen entry.
            % The cache is invalidated when the AppState is destroyed
            % (logout / app close) or by writing [] to BackendPoolCache.
            app = obj.App;
            try
                cached   = app.State.BackendPoolCache;
                cachedAt = app.State.BackendPoolCacheAt;
                fresh = ~isempty(cached) && ~isempty(cachedAt) ...
                    && seconds(datetime('now') - cachedAt) < 300;
                if fresh
                    obj.BackendPool = cached;
                    Logger.info('CircuitCuttingViewModel', ...
                        'Backend pool: %d entries (cached)', numel(cached));
                    return;
                end
                data = app.BackendSvc.listBackends(app.State.authToken, '');
                items = JsonHelper.pick(data, 'backends', {});
                pool = {};
                if iscell(items)
                    arr = items;
                elseif isstruct(items)
                    arr = num2cell(items);
                else
                    arr = {};
                end
                for i = 1:numel(arr)
                    e = arr{i};
                    name = char(string(JsonHelper.pick(e, 'name', '')));
                    if isempty(strtrim(name)); continue; end
                    nq = JsonHelper.pick(e, 'num_qubits', NaN);
                    if ~isnumeric(nq) || isnan(nq); nq = []; end
                    sim = JsonHelper.pick(e, 'simulator', false);
                    pool{end+1} = struct( ...
                        'name', name, ...
                        'num_qubits', nq, ...
                        'simulator', logical(sim)); %#ok<AGROW>
                end
                obj.BackendPool = pool;
                % Write through to the session-level cache so other
                % screens (Backends, Benchmark Dashboard, Prediction)
                % can reuse this pool without their own /api/backends
                % round-trip when they wire the cache in turn.
                app.State.BackendPoolCache   = pool;
                app.State.BackendPoolCacheAt = datetime('now');
                Logger.info('CircuitCuttingViewModel', ...
                    'Backend pool loaded: %d entries', numel(pool));
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'loadBackendPool failed: %s', ME.message);
                obj.BackendPool = {};
            end
        end

        % ── Circuit dropdown ─────────────────────────────────────────────
        function onCircuitChanged(obj, circuitId)
            app = obj.App;
            cid = char(circuitId);
            if isempty(cid); return; end
            app.State.selectedCircuitId = string(cid);
            app.logEvent('CUT', sprintf('Circuit selected: %s', cid));
            obj.LastAnalyze = [];  % stale analysis — force re-run for the new circuit
            obj.refreshStatus();
            obj.checkCuttability(cid);
        end

        % ── Mode / preset dropdowns ──────────────────────────────────────
        function onModeChanged(obj, mode)
            obj.CurrentMode = string(mode);
            obj.App.logEvent('CUT', sprintf('Mode changed to %s', mode));
            obj.refreshStatus();
            % Re-render Backend Assignments so the locked/editable rows
            % follow the new mode (Automatic locks, Assisted/Manual edit).
            try
                if ~isempty(obj.LastAnalyze)
                    obj.renderBackendCards(obj.firstCandidate());
                end
            catch ME
                Logger.debug('CircuitCuttingViewModel', ...
                    'mode-change re-render: %s', ME.message);
            end
        end

        function onPresetChanged(obj, preset)
            obj.CurrentPreset = string(preset);
            obj.refreshStatus();
        end

        function onMitigationLevelChanged(obj, ~)
            % Toolbar dropdown change handler. Re-triggers the cost-
            % preview line so the operator sees the new shots / wall-
            % clock / IQP estimate immediately. The dropdown's value
            % flows into the create-batch body at Run time via
            % buildCreateBody — no other state needs updating here.
            try
                obj.applyMitigationPreview(obj.LastAnalyze);
            catch ME
                Logger.debug('CircuitCuttingViewModel', ...
                    'onMitigationLevelChanged → applyMitigationPreview: %s', ...
                    ME.message);
            end
        end

        % ── Analyze ──────────────────────────────────────────────────────
        function onAnalyzeCuts(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            cid = char(app.State.selectedCircuitId);
            if isempty(cid)
                uialert(app.UIFigure, 'Select a circuit first.', ...
                    'Circuit Cutting');
                return;
            end
            % Read the toolbar spinner; 0 = auto (server picks k), >=2
            % = force that many subcircuits. When the addon's automated
            % cut finder overflows float64 on a wide / densely-entangling
            % circuit (qugan_n395, BV-140 packed, etc.), dispatchAnalyze
            % auto-escalates target_k 4 → 8 → 16 → 32 until one succeeds —
            % the recovery path the server's own error message suggests,
            % made automatic so the operator does not have to babysit it.
            targetK = [];
            try
                v = double(app.CuttingTargetKSpin.Value);
                if v >= 2 && v <= 32
                    targetK = v;
                end
            catch; end

            app.showLoading();
            obj.dispatchAnalyze(targetK, false);
        end

        % ── Run ──────────────────────────────────────────────────────────
        function onRunCutting(obj)
            app = obj.App;
            if isempty(obj.LastAnalyze)
                uialert(app.UIFigure, 'Press Analyze Cuts first.', ...
                    'Circuit Cutting');
                return;
            end

            % Pre-flight: when the user assigned backends manually
            % (assisted/manual), refuse the run if any subcircuit's width
            % exceeds the chosen backend's qubit count. Catches the same
            % class of error IBM would otherwise raise as
            % CircuitTooWideForTarget after the round-trip — but here we
            % point at the offending row so the operator can fix it.
            try
                msg = obj.validateAssignmentWidths();
                if ~isempty(msg)
                    uialert(app.UIFigure, msg, 'Circuit Cutting', ...
                        'Icon', 'error');
                    return;
                end
            catch ME
                Logger.debug('CircuitCuttingViewModel', ...
                    'pre-flight width check: %s', ME.message);
            end

            cid = char(app.State.selectedCircuitId);

            % Server rejects infeasible cut plans (sampling overhead above
            % its 1e+06 ceiling) with HTTP 422 unless the body carries
            % feasibility_override=true. Surface the reason to the operator
            % and require an explicit confirmation before forcing the run.
            override = false;
            c = obj.firstCandidate();
            feasible = JsonHelper.pick(c, 'feasible', true);
            if isequal(feasible, false)
                reason = char(JsonHelper.pick(c, 'feasibility_reason', ...
                    'Cut plan flagged as infeasible by the server.'));
                sel = uiconfirm(app.UIFigure, ...
                    sprintf(['This cut plan is flagged as infeasible.\n\n%s\n\n' ...
                             'Run anyway?'], reason), ...
                    'Circuit Cutting', ...
                    'Options', {'Run Anyway', 'Cancel'}, ...
                    'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
                if ~strcmp(sel, 'Run Anyway')
                    obj.setStatus('Run cancelled: cut plan is infeasible.');
                    return;
                end
                override = true;
            end

            body = obj.buildCreateBody(override);

            % Pre-flight: warn the operator before submitting a batch
            % with no observables. AUTOMATIC mode skips this check
            % because the server auto-derives per-qubit Z observables
            % when none are submitted (matches the Qiskit cutting
            % tutorial default of PauliList(["ZIIII","IZIII",...])).
            % ASSISTED / MANUAL still require an explicit list since
            % those modes are the "I am driving" workflows.
            isAutoMode = strcmpi(char(obj.CurrentMode), 'automatic');
            obsEmpty = isempty(body.observables) || ...
                (iscell(body.observables) && all(cellfun('isempty', body.observables)));
            if obsEmpty && ~isAutoMode
                sel = uiconfirm(app.UIFigure, ...
                    ['No observables were entered for this cutting ' ...
                     'batch. Reconstruction needs at least one Pauli ' ...
                     'string (e.g. "Z", "ZZ", "X") aligned with the ' ...
                     'circuit width to produce a meaningful expectation ' ...
                     'value. Submitting now will run the subcircuits ' ...
                     'on hardware but the reconstruction step will ' ...
                     'return no usable values. (Switch to AUTOMATIC ' ...
                     'mode to let the system derive per-qubit Z ' ...
                     'observables for you.)'], ...
                    'Circuit Cutting', ...
                    'Options', {'Add Observables', 'Submit Anyway'}, ...
                    'DefaultOption', 1, 'CancelOption', 1, 'Icon', 'warning');
                if ~strcmp(sel, 'Submit Anyway')
                    obj.setStatus( ...
                        'Run cancelled: add observables (e.g. "Z") and try again.');
                    return;
                end
            end

            % Same capture-rule as onAnalyzeCuts — never reference app.*
            % inside the background-task closure.
            svc   = app.CuttingSvc;
            token = app.State.authToken;
            app.showLoading();
            AsyncRunner.run( ...
                @() svc.createBatch(cid, body, token), ...
                @(r) obj.startPolling(r), ...
                @(ME) obj.onError(ME));
        end

        % ── Cancel ───────────────────────────────────────────────────────
        function onCancelBatch(obj)
            if isempty(obj.ActiveBatchId); return; end
            try
                obj.App.CuttingSvc.cancelBatch( ...
                    obj.ActiveBatchId, obj.App.State.authToken);
            catch ME
                obj.App.logEvent('WARN', ['Cancel failed: ' ME.message]);
            end
            obj.stopPolling();
            obj.refreshStatus();
        end

        % ── Circuits ─────────────────────────────────────────────────────
        function loadCircuits(obj)
            % Populate the Circuit dropdown with the current project's
            % circuits. Matches the pattern used by BenchmarkViewModel /
            % PredictionViewModel. Pulls selected circuit id from AppState
            % if one is already set, so navigating over from another
            % screen preserves the user's selection.
            app = obj.App;
            try
                data = app.CircuitSvc.listCircuits(app.State.authToken);
                items = JsonHelper.extractList(data, 'circuits');
                n = numel(items);
                if n == 0
                    if ~isempty(app.CuttingCircuitDropdown)
                        app.CuttingCircuitDropdown.Items     = {'(no circuits)'};
                        app.CuttingCircuitDropdown.ItemsData = {''};
                        app.CuttingCircuitDropdown.Value     = '';
                    end
                    return;
                end
                ids   = cell(1, n);
                names = cell(1, n);
                for i = 1:n
                    it = items(i);
                    if iscell(items); it = items{i}; end
                    ids{i}   = char(JsonHelper.pick(it, {'circuit_id','id'}));
                    nm = char(JsonHelper.pick(it, {'name','circuit_id','id'}));
                    if isempty(nm); nm = ids{i}; end
                    names{i} = nm;
                end
                if ~isempty(app.CuttingCircuitDropdown)
                    app.CuttingCircuitDropdown.Items     = names;
                    app.CuttingCircuitDropdown.ItemsData = ids;
                    sel = char(app.State.selectedCircuitId);
                    match = find(strcmp(ids, sel), 1);
                    if ~isempty(match)
                        app.CuttingCircuitDropdown.Value = ids{match};
                    else
                        app.CuttingCircuitDropdown.Value = ids{1};
                        app.State.selectedCircuitId = string(ids{1});
                    end
                end
                app.logEvent('LOAD', sprintf('Loaded %d circuits into Circuit Cutting dropdown', n));
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'loadCircuits failed: %s', ME.message);
                if ~isempty(app.CuttingCircuitDropdown)
                    app.CuttingCircuitDropdown.Items     = {'(load failed)'};
                    app.CuttingCircuitDropdown.ItemsData = {''};
                    app.CuttingCircuitDropdown.Value     = '';
                end
            end
        end

        % ── Presets ──────────────────────────────────────────────────────
        function loadPresets(obj)
            app = obj.App;
            try
                data = app.CuttingSvc.listPresets(app.State.authToken);
                items = JsonHelper.extractList(data, 'presets');
                n = numel(items);
                names = cell(1, n);
                ids   = cell(1, n);
                for i = 1:n
                    it = items(i);
                    if iscell(items); it = items{i}; end
                    ids{i}   = char(JsonHelper.pick(it, 'id', 'generic'));
                    names{i} = char(JsonHelper.pick(it, 'name', 'Generic'));
                end
                if ~isempty(app.CuttingPresetDropdown)
                    app.CuttingPresetDropdown.Items     = names;
                    app.CuttingPresetDropdown.ItemsData = ids;
                end
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'loadPresets failed: %s', ME.message);
                if ~isempty(app.CuttingPresetDropdown)
                    app.CuttingPresetDropdown.Items     = {'Generic'};
                    app.CuttingPresetDropdown.ItemsData = {'generic'};
                end
            end
        end
    end

    methods (Access = private)

        % ── Analyze dispatch + auto-fallback ─────────────────────────────
        function dispatchAnalyze(obj, targetK, isAutoRetry)
            % Single-source analyze submitter. onAnalyzeCuts calls this
            % with whatever target_k the user picked; the auto-fallback
            % path also calls it with the next-larger forced target_k
            % when the addon overflows float64.
            %
            % IMPORTANT: bind svc + token to LOCAL variables before the
            % closure. Referencing `app.CuttingSvc` inside the lambda
            % would capture the entire QTAUWorkbenchApp (which holds
            % uifigure + uihtml components) — parfeval then serializes
            % it to the worker, which fails with
            % MATLAB:class:InvalidSuperClass on
            % matlab.ui.control.WebComponent. Matches the pattern used
            % by BenchmarkDashboardViewModel.onRefreshAll.
            app   = obj.App;
            cid   = char(app.State.selectedCircuitId);
            svc   = app.CuttingSvc;
            token = app.State.authToken;
            if isAutoRetry
                Logger.info('CircuitCuttingViewModel', ...
                    'Auto-retrying analyze with forced target_k=%d (addon overflowed)', ...
                    targetK);
                obj.setStatus(sprintf(['Auto-retry analyze with forced ' ...
                    'target_k=%d (qiskit-addon-cutting overflowed in ' ...
                    'auto mode — escalating)…'], targetK));
                % Mirror the value into the toolbar spinner so the
                % operator sees what we are trying. If a later retry
                % succeeds, the spinner is left at that value as the
                % suggested setting for future runs of this circuit.
                try
                    if ~isempty(app.CuttingTargetKSpin) && ...
                            isvalid(app.CuttingTargetKSpin)
                        app.CuttingTargetKSpin.Value = targetK;
                    end
                catch; end
            end
            AsyncRunner.run( ...
                @() svc.analyzeCuts(cid, targetK, token), ...
                @(r) obj.applyAnalyze(r), ...
                @(ME) obj.onAnalyzeError(ME, targetK));
        end

        function onAnalyzeError(obj, ME, prevTargetK)
            % Analyze-flow error handler with auto-fallback. The
            % qiskit-addon-cutting find_cuts() routine overflows float64
            % on circuits that are too wide or too densely entangling
            % (e.g. qugan_n395, BV-140 packed) when target_k is auto.
            % The server returns 422 with a body that includes phrases
            % like "Automated cut finding could not handle" and
            % "overflowed float64". On that signature we step the forced
            % target_k up the [4, 8, 16, 32] ladder until one succeeds —
            % otherwise we surface the original error.
            msg = '';
            try; msg = char(ME.message); catch; end
            isOverflow = contains(msg, 'overflowed float64', ...
                                  'IgnoreCase', true) || ...
                         contains(msg, 'Automated cut finding could not handle', ...
                                  'IgnoreCase', true) || ...
                         contains(msg, 'gamma upper bound', ...
                                  'IgnoreCase', true);
            nextK = obj.nextAutoFallbackK(prevTargetK);
            if isOverflow && ~isempty(nextK)
                obj.dispatchAnalyze(nextK, true);
                return;
            end
            obj.onError(ME);
        end

        function k = nextAutoFallbackK(~, prevTargetK)
            % Pick the next forced target_k after the addon overflowed.
            % Ladder: <empty/0/2/3> → 4 → 8 → 16 → 32 → (give up).
            ladder = [4, 8, 16, 32];
            if isempty(prevTargetK) || prevTargetK <= 0
                k = ladder(1);
                return;
            end
            idx = find(ladder > prevTargetK, 1, 'first');
            if isempty(idx)
                k = [];
            else
                k = ladder(idx);
            end
        end

        % ── Response handlers ────────────────────────────────────────────
        function applyAnalyze(obj, r)
            app = obj.App;
            app.hideLoading();
            obj.LastAnalyze = r;
            candidates = JsonHelper.pick(r, 'candidates', {});
            if isempty(candidates) || (iscell(candidates) && isempty(candidates))
                obj.setStatus('No cut candidates found.');
                return;
            end
            c = candidates(1); if iscell(candidates); c = candidates{1}; end
            k   = JsonHelper.pick(c, 'k', 0);
            oh  = JsonHelper.pick(c, 'sampling_overhead', 1.0);
            ohL = JsonHelper.pick(c, 'sampling_overhead_log10', NaN);
            per = JsonHelper.pick(c, 'per_subcircuit_qubits', {});
            obj.setStatus(sprintf( ...
                '%d subcircuits   %s   overhead %s', ...
                k, obj.formatPerSub(per), obj.formatOverhead(oh, ohL)));
            obj.renderCutPlan(c);

            % Pre-fill the Observables textarea with the server-suggested
            % defaults (per-qubit Z + nearest-neighbor ZZ for circuits
            % <=30 qubits). The operator can edit them before submit in
            % ASSISTED mode; AUTOMATIC mode ignores the textarea entirely
            % and the server applies the same defaults internally. We
            % only prefill when the textarea is empty or still shows the
            % placeholder, so we never silently overwrite an operator's
            % typed input from a prior session.
            try
                obj.prefillObservablesFromAnalyze(r);
            catch ME
                Logger.debug('CircuitCuttingViewModel', ...
                    'prefillObservablesFromAnalyze: %s', ME.message);
            end

            % Hardware-aware coherence warning. For n>50 GHZ/cat
            % circuits the server-side observable generator drops
            % weight-N witnesses (X⊗ⁿ, Z⊗ⁿ) because they decay below
            % the noise floor on real IBM hardware; the analyze
            % response carries a non-empty coherence_warning string
            % explaining that static observables can't verify
            % coherence at this scale. Surface it inline above the
            % Observables textarea so the operator sees it next to
            % the AUTOMATIC defaults instead of discovering it after
            % a wasted run. Empty string clears any stale warning
            % left from a prior analyze.
            try
                obj.applyCoherenceWarning(r);
            catch ME
                Logger.debug('CircuitCuttingViewModel', ...
                    'applyCoherenceWarning: %s', ME.message);
            end

            % Mitigation cost preview. Hits POST /api/mitigation/estimate
            % so the operator sees "Mitigation: Standard · ~Nx shots ·
            % est. Hms" inline on the toolbar's Row 2 right side. Driven
            % by the freshly-resolved cut plan (per-subcircuit qubits)
            % so the QPD shot floor is reflected in the cost. Best-
            % effort: any HTTP failure just leaves the label blank.
            try
                obj.applyMitigationPreview(r);
            catch ME
                Logger.debug('CircuitCuttingViewModel', ...
                    'applyMitigationPreview: %s', ME.message);
            end

            % Smart-analyze recommendation. The server compares circuit
            % width against the configured IBM fleet; if at least one
            % backend fits, cutting is strictly worse than a direct
            % submission. Surface that as a modal so the operator makes
            % an informed choice instead of stumbling into a 4^k cut
            % plan that nobody asked for.
            recommended = JsonHelper.pick(r, 'cutting_recommended', true);
            if isequal(recommended, false)
                obj.promptDirectRunRecommendation(r);
            end
        end

        function prefillObservablesFromAnalyze(obj, r)
            % Populate the Observables textarea with the server's
            % default_observables field unless the operator has already
            % typed their own list. Keeps the placeholder semantics
            % working: if the field is empty or matches the placeholder
            % text, replace it with one Pauli string per line.
            app = obj.App;
            if isempty(app.CuttingObservablesText) || ...
                    ~isvalid(app.CuttingObservablesText)
                return;
            end
            defaults = JsonHelper.pick(r, 'default_observables', {});
            if isempty(defaults); return; end
            if isstruct(defaults); defaults = num2cell(defaults); end
            if ~iscell(defaults); return; end
            defaults = defaults(~cellfun('isempty', defaults));
            if isempty(defaults); return; end

            current = app.CuttingObservablesText.Value;
            if ischar(current); current = {current}; end
            if isstring(current); current = cellstr(current); end
            current = current(~cellfun('isempty', strtrim(string(current))));

            placeholder = CircuitCuttingViewModel.OBSERVABLES_PLACEHOLDER;
            isEmpty = isempty(current);
            isPlaceholder = ~isEmpty && numel(current) == 1 && ...
                strcmp(strtrim(char(current{1})), placeholder);
            if ~(isEmpty || isPlaceholder)
                return;
            end

            lines = cellfun(@(s) char(string(s)), defaults, ...
                'UniformOutput', false);
            app.CuttingObservablesText.Value = lines(:).';
        end

        function applyCoherenceWarning(obj, r)
            % Toggle the Observables-card warning label based on the
            % analyze response's coherence_warning field.
            %
            % The server emits a non-empty string only when n exceeds
            % the hardware noise-dominated threshold (~50q) AND the
            % cut plan is non-trivial — i.e. when AUTOMATIC just
            % produced a focused weight-2 ZZ set instead of the
            % standard per-qubit Z + nearest-neighbor ZZ default.
            % Hiding the label otherwise keeps the small-circuit UI
            % uncluttered. Always clears stale text from a prior
            % analyze so re-analyzing a small circuit doesn't show
            % a leftover large-circuit warning.
            app = obj.App;
            if isempty(app.CuttingObservablesWarning) || ...
                    ~isvalid(app.CuttingObservablesWarning)
                return;
            end
            warningText = char(JsonHelper.pick(r, ...
                'coherence_warning', ''));
            if isempty(warningText)
                app.CuttingObservablesWarning.Text = '';
                app.CuttingObservablesWarning.Visible = 'off';
                return;
            end
            app.CuttingObservablesWarning.Text = warningText;
            app.CuttingObservablesWarning.Visible = 'on';
        end

        function applyMitigationPreview(obj, r)
            % Fetch a CostEstimate from POST /api/mitigation/estimate
            % and populate the toolbar's mitigation cost-preview label.
            %
            % Request shape mirrors EstimateRequest in
            % src/qdash/api/routers/mitigation.py:
            %   {primitive: 'sampler', backend_name, base_shots,
            %    circuit_qubits, cutting_overhead_qubits}
            %
            % Best-effort: any HTTP failure clears the label rather
            % than surfacing an error modal — the cost preview is
            % advisory, not a blocker. The level dropdown lands in a
            % follow-up; for now this always asks the server for the
            % default (Standard) so the operator sees what's actually
            % running today.
            app = obj.App;
            if isempty(app.CuttingMitigationLabel) || ...
                    ~isvalid(app.CuttingMitigationLabel)
                return;
            end
            % Reset label first so a stale preview from a prior
            % analyze doesn't linger when the new request fails.
            app.CuttingMitigationLabel.Text = '';

            svc = app.MitigationSvc;
            if isempty(svc); return; end
            token = '';
            try
                token = char(app.State.authToken);
            catch
                return;  % no auth, can't preview
            end
            if isempty(token); return; end

            % Pull partition shape off the analyze response so the
            % QPD shot floor is reflected in the cost.
            candidates = JsonHelper.pick(r, 'candidates', {});
            cutPlan = struct();
            if ~isempty(candidates)
                cutPlan = candidates(1);
                if iscell(candidates); cutPlan = candidates{1}; end
            end
            perSub = JsonHelper.pick(cutPlan, 'per_subcircuit_qubits', {});
            % Largest subcircuit drives the per-child mitigation
            % regime (matches the cutting service's own resolve call).
            maxSub = 0;
            try
                vals = double(cell2mat(perSub));
                if ~isempty(vals); maxSub = max(vals); end
            catch
                % perSub may already be numeric — fall through
                try
                    vals = double(perSub);
                    if ~isempty(vals); maxSub = max(vals); end
                catch; end
            end

            n = double(JsonHelper.pick(r, 'circuit_width', 0));

            % Backend: prefer the user's currently selected backend
            % from State; fall back to the first auto-assigned one in
            % the cut plan; finally to empty (server treats as non-IBM
            % and omits the IQP figure).
            backendName = '';
            try
                backendName = char(app.State.selectedBackend);
            catch; end
            if isempty(backendName)
                assigns = JsonHelper.pick(cutPlan, 'backend_assignments', {});
                if ~isempty(assigns)
                    a = assigns(1);
                    if iscell(assigns); a = assigns{1}; end
                    try
                        backendName = char(JsonHelper.pick(a, 'backend_name', ''));
                    catch; end
                end
            end

            % Read the operator's chosen ladder level off the toolbar
            % dropdown. Falls back to system default (None ⇒ Standard
            % at the server) when the dropdown isn't built yet.
            mitigLevel = [];
            try
                mitigLevel = app.CuttingMitigationDropdown.Value;
            catch; end

            body = struct( ...
                'primitive', 'sampler', ...
                'backend_name', backendName, ...
                'base_shots', int32(4096), ...
                'circuit_qubits', int32(n), ...
                'cutting_overhead_qubits', int32(maxSub));
            if ~isempty(mitigLevel) && isnumeric(mitigLevel)
                body.mitigation_level = int32(mitigLevel);
            end

            try
                resp = svc.estimate(body, token);
            catch ME
                Logger.debug('CircuitCuttingViewModel', ...
                    'applyMitigationPreview: estimate failed: %s', ...
                    ME.message);
                return;
            end

            summary = char(JsonHelper.pick(resp, 'summary', ''));
            if ~isempty(summary)
                app.CuttingMitigationLabel.Text = summary;
            end
        end

        function promptDirectRunRecommendation(obj, r)
            % Shown after analyze when the server says cutting is not
            % useful for this circuit (it fits on a single backend).
            % Three options:
            %   * Submit Directly → bridge to Backends screen with the
            %     suggested backend pre-selected.
            %   * Proceed with Cutting → keep the cut plan visible so the
            %     operator can still run it (research / curiosity).
            %   * Cancel → drop the cut plan; user picks again.
            app = obj.App;
            reason = char(JsonHelper.pick(r, ...
                'cutting_recommendation_reason', ''));
            if isempty(reason)
                reason = Labels.get('cutting_recommendation_skip', ...
                    'This circuit fits on a single backend — cutting is unnecessary.');
            end
            directBackend = char(JsonHelper.pick(r, ...
                'direct_run_backend', ''));
            opts = { ...
                Labels.get('cutting_recommendation_skip_btn', 'Submit Directly'), ...
                'Proceed with Cutting', ...
                'Cancel'};
            sel = uiconfirm(app.UIFigure, reason, ...
                'Cutting Recommendation', ...
                'Options', opts, ...
                'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'info');
            switch sel
                case opts{1}   % Submit Directly
                    if ~isempty(directBackend)
                        try
                            app.State.selectedBackend = string(directBackend);
                        catch; end
                    end
                    app.logEvent('CUT', sprintf( ...
                        'Direct-run bridge → Backends (suggested: %s)', ...
                        directBackend));
                    app.onSelectSection('Backends');
                case opts{2}   % Proceed with Cutting
                    obj.setStatus(sprintf( ...
                        'Proceeding with cutting despite recommendation. (%s)', ...
                        reason));
                otherwise      % Cancel
                    obj.LastAnalyze = [];
                    obj.setStatus('Analysis dismissed.');
                    try
                        obj.renderCutPlan(struct( ...
                            'k', 0, 'cuts', {{}}, ...
                            'sampling_overhead', 1.0, ...
                            'sampling_overhead_log10', 0.0, ...
                            'per_subcircuit_qubits', {{}}));
                    catch; end
            end
        end

        function body = buildCreateBody(obj, overrideFeasibility)
            if nargin < 2 || isempty(overrideFeasibility)
                overrideFeasibility = false;
            end
            c = obj.firstCandidate();
            body = struct();
            body.mode = char(obj.CurrentMode);
            body.preset = char(obj.CurrentPreset);
            body.cut_plan = obj.sanitizeCutPlan(c);
            body.backend_assignments = obj.collectBackends(c);
            body.observables = obj.parseObservables();
            body.opt_in_distribution = false;
            try
                body.opt_in_distribution = logical( ...
                    obj.App.CuttingDistCheckbox.Value);
            catch; end
            body.timeout_hours = 6.0;
            body.retry_strategy = 'none';
            if overrideFeasibility
                body.feasibility_override = true;
            end
            % Phase 3.1: thread the toolbar's chosen mitigation level
            % into the create-batch body. Server reads
            % req.get('mitigation_level', ...) → MitigationService.
            % resolve(...) so the resolved plan reflects the operator's
            % choice. Empty / non-numeric ⇒ omit the field so the
            % server falls back to its default (Standard).
            try
                lvl = obj.App.CuttingMitigationDropdown.Value;
                if isnumeric(lvl)
                    body.mitigation_level = int32(lvl);
                end
            catch; end
            % Phase 3.3: also_run_raw checkbox → server-side sibling
            % Raw batch via CuttingBatchService.create_batch's Phase
            % 3.2 plumbing. Only sets the field when explicitly
            % checked so the doc-create payload stays minimal.
            try
                if logical(obj.App.CuttingAlsoRunRawCheckbox.Value)
                    body.also_run_raw = true;
                end
            catch; end
        end

        function c = firstCandidate(obj)
            % Extract the first candidate from the cached Analyze response.
            % Throws a typed MException when no candidates are available so
            % the caller can surface a real error instead of sending an
            % empty cut_plan and letting the server 422.
            candidates = JsonHelper.pick(obj.LastAnalyze, 'candidates', {});
            if isempty(candidates)
                error('QTAU:NoCutCandidate', ...
                    'No cut candidates available — rerun Analyze Cuts.');
            end
            if iscell(candidates)
                c = candidates{1};
            else
                c = candidates(1);
            end
        end

        function plan = sanitizeCutPlan(~, c)
            % Normalise the analyze-response candidate so the
            % create-batch endpoint accepts it. MATLAB's jsondecode has
            % two well-known round-trip bugs that 422 the server's
            % Pydantic CutPlan validator:
            %
            %   * JSON ``null`` decodes to ``[]`` and re-encodes as ``[]``
            %     instead of ``null`` — server's ``int | None`` field
            %     rejects an array.
            %   * JSON ``[17]`` (single-element array) decodes to scalar
            %     ``17`` and re-encodes as ``17`` instead of ``[17]`` —
            %     server's ``list[int]`` field rejects a scalar.
            %
            % Hit on qec9xz_n17.qasm where the analyze response had
            % ``"target_k": null`` and ``"per_subcircuit_qubits": [17]``;
            % MATLAB sent them back as ``"target_k": []`` and
            % ``"per_subcircuit_qubits": 17``, triggering 422.
            plan = c;

            % target_k: int | None — drop the field entirely when empty
            % or zero so the server's None default kicks in. (Sending
            % ``null`` from MATLAB requires NaN, but absent-field has the
            % same effect on Pydantic and is more robust.)
            if isfield(plan, 'target_k')
                v = plan.target_k;
                drop = isempty(v) || ...
                    (isnumeric(v) && isscalar(v) && (isnan(v) || v == 0));
                if drop
                    plan = rmfield(plan, 'target_k');
                else
                    plan.target_k = double(v);
                end
            end

            % qubits_per_qpu: int | None — same treatment.
            if isfield(plan, 'qubits_per_qpu')
                v = plan.qubits_per_qpu;
                drop = isempty(v) || ...
                    (isnumeric(v) && isscalar(v) && isnan(v));
                if drop
                    plan = rmfield(plan, 'qubits_per_qpu');
                else
                    plan.qubits_per_qpu = double(v);
                end
            end

            % per_subcircuit_qubits: list[int] — wrap scalars / empties
            % in a cell array so jsonencode always emits a JSON array,
            % never a bare number or [].
            if isfield(plan, 'per_subcircuit_qubits')
                v = plan.per_subcircuit_qubits;
                if isempty(v)
                    plan.per_subcircuit_qubits = {};
                elseif isnumeric(v)
                    plan.per_subcircuit_qubits = num2cell(double(v(:).'));
                elseif iscell(v)
                    plan.per_subcircuit_qubits = v(:).';
                end
            end

            % cuts: list[CutPoint] — same array-shape guard. A single
            % cut decodes to a struct rather than a 1-element struct
            % array; wrap in a cell so the JSON shape stays an array.
            if isfield(plan, 'cuts')
                v = plan.cuts;
                if isempty(v)
                    plan.cuts = {};
                elseif isstruct(v) && isscalar(v)
                    plan.cuts = {v};
                elseif isstruct(v)
                    plan.cuts = arrayfun(@(s) s, v(:).', ...
                        'UniformOutput', false);
                end
                % iscell(v) — already a list, leave alone.
            end

            % Drop server-generated descriptive fields the dispatch path
            % does NOT need. Echoing them back round-trips through MATLAB
            % jsonencode, which on some platforms emits non-UTF-8 bytes
            % for em-dashes / smart quotes — Pydantic's body parser then
            % rejects the request with HTTP 400 "There was an error
            % parsing the body". The user already saw these on the
            % analyze response; the server doesn't need them re-asserted.
            for fld = {'feasibility_reason', 'feasible'}
                if isfield(plan, fld{1})
                    plan = rmfield(plan, fld{1});
                end
            end
        end

        function obs = parseObservables(obj)
            % Pull Pauli strings from the Observables textarea, drop the
            % placeholder and blank lines. Empty result -> {}; the
            % onRunBatch pre-flight surfaces a Submit-Anyway confirm so
            % the operator never silently submits a batch the server
            % cannot reconstruct. (The old "server falls back to all-Z"
            % behaviour was removed; the server now returns a
            % "no_observables_submitted" sentinel that the Reconstruction
            % Summary popup renders as a tailored diagnostic.)
            lines = {};
            try
                raw = obj.App.CuttingObservablesText.Value;
                if ischar(raw); raw = {raw}; end
                if isstring(raw); raw = cellstr(raw); end
                if iscell(raw); lines = raw; end
            catch; end
            obs = CircuitCuttingViewModel.parseObservableLines(lines, ...
                CircuitCuttingViewModel.OBSERVABLES_PLACEHOLDER);
        end

        function assns = collectBackends(obj, cutPlan)
            % Build the backend_assignments payload for POST /cutting/batches.
            %
            %   * Automatic mode → return {} so the server's size-aware
            %     select_backends fills the assignments based on the live
            %     IBM pool.
            %   * Assisted/Manual → read each row's dropdown + shots field
            %     from RowControls (populated by renderBackendCards).
            %
            % Falls back to a defensive smallest-fit auto-pick when the
            % rows are missing or partially populated (e.g. caller forgot
            % to render the cards before pressing Run).
            mode = char(obj.CurrentMode);
            if strcmp(mode, 'automatic')
                assns = {};
                return;
            end

            k = JsonHelper.pick(cutPlan, 'k', 1);
            if ~isnumeric(k); k = str2double(k); end
            k = max(1, double(k));

            per = obj.perSubcircuitQubits(cutPlan);
            assns = cell(1, k);
            for i = 1:k
                name  = '';
                shots = 4096;
                if i <= numel(obj.RowControls)
                    rc = obj.RowControls{i};
                    try
                        if ~isempty(rc) && isfield(rc, 'nameDropdown') ...
                                && isvalid(rc.nameDropdown)
                            name = char(string(rc.nameDropdown.Value));
                        end
                    catch; end
                    try
                        if ~isempty(rc) && isfield(rc, 'shotsField') ...
                                && isvalid(rc.shotsField)
                            shots = double(rc.shotsField.Value);
                            if ~isfinite(shots) || shots < 1
                                shots = 4096;
                            end
                        end
                    catch; end
                end
                if isempty(strtrim(name))
                    width = 0;
                    if i <= numel(per); width = double(per(i)); end
                    name = obj.bestFitBackendName(width);
                end
                if isempty(strtrim(name))
                    name = 'ibm_miami';   % last-resort default
                end
                assns{i} = struct( ...
                    'subcircuit_idx', int32(i - 1), ...
                    'backend_name', name, ...
                    'shots', int32(round(shots)));
            end
        end

        function msg = validateAssignmentWidths(obj)
            % Returns '' when every (subcircuit, backend) pair fits, or a
            % human-readable error listing the bad rows otherwise. Skipped
            % entirely in automatic mode (server picks size-aware), and
            % when the backend pool didn't load (we can't validate).
            msg = '';
            if strcmp(char(obj.CurrentMode), 'automatic'); return; end
            if isempty(obj.BackendPool); return; end
            try
                c = obj.firstCandidate();
            catch
                return;
            end
            per = obj.perSubcircuitQubits(c);
            assns = obj.collectBackends(c);
            bad = {};
            for i = 1:numel(assns)
                a = assns{i};
                width = 0;
                if i <= numel(per); width = double(per(i)); end
                nq = obj.lookupQubits(a.backend_name);
                if isempty(nq) || width <= nq; continue; end
                bad{end+1} = sprintf('  • #%d (%dq) → %s (%dq)', ...
                    double(a.subcircuit_idx), int32(width), ...
                    char(a.backend_name), int32(nq)); %#ok<AGROW>
            end
            if ~isempty(bad)
                msg = sprintf([ ...
                    'Some subcircuits are wider than the backend you ' ...
                    'picked. IBM will reject these with ' ...
                    'CircuitTooWideForTarget.\n\n%s\n\nFix the row(s) ' ...
                    'or switch Mode to Automatic to let the server ' ...
                    'pick a fitting backend.'], strjoin(bad, sprintf('\n')));
            end
        end

        function name = bestFitBackendName(obj, width)
            % Return the smallest backend in BackendPool whose num_qubits
            % >= width. Falls back to '' when nothing fits or the pool is
            % empty — caller decides how to handle that case.
            name = '';
            pool = obj.BackendPool;
            if isempty(pool); return; end
            best = [];
            bestQubits = Inf;
            for i = 1:numel(pool)
                e = pool{i};
                nq = e.num_qubits;
                if isempty(nq); continue; end
                if e.simulator; continue; end   % prefer real hardware
                if nq >= width && nq < bestQubits
                    best = e;
                    bestQubits = nq;
                end
            end
            if ~isempty(best); name = char(best.name); end
        end

        function arr = perSubcircuitQubits(~, cutPlan)
            v = JsonHelper.pick(cutPlan, 'per_subcircuit_qubits', []);
            if iscell(v)
                arr = zeros(1, numel(v));
                for i = 1:numel(v)
                    x = v{i}; if ~isnumeric(x); x = str2double(x); end
                    arr(i) = double(x);
                end
            elseif isnumeric(v)
                arr = double(v(:)).';
            else
                arr = [];
            end
        end

        % ── Poll lifecycle ───────────────────────────────────────────────
        function startPolling(obj, batchResp)
            obj.App.hideLoading();
            obj.ActiveBatchId = char(JsonHelper.pick(batchResp, 'batch_id', ''));
            if isempty(obj.ActiveBatchId); return; end
            obj.stopPolling();
            obj.PollTimer = timer('Period', 3, ...
                'ExecutionMode', 'fixedRate', ...
                'TimerFcn', @(~,~) obj.pollTick());
            start(obj.PollTimer);
            obj.App.logEvent('CUT', sprintf('Batch %s dispatched', obj.ActiveBatchId));
        end

        function pollTick(obj)
            % Timer callback — runs on the MATLAB main thread, not via
            % parfeval, so touching obj.App.* here is safe. The "never
            % reference app.*" rule in onRunCutting/onAnalyzeCuts applies
            % only to AsyncRunner closures that get serialized to workers.
            %
            % Skip polls when the user has navigated away from Circuit
            % Cutting. Otherwise the 3-second timer keeps hitting
            % /api/cutting/batches/{id} every tick from the Welcome /
            % Jobs / Results screens — burning bandwidth, racing with
            % the UI event loop, and giving the operator no visible
            % benefit (they're not looking at the cutting screen). The
            % timer is preserved across navigation so re-entering the
            % screen via onEnter resumes polling without losing
            % ActiveBatchId.
            try
                active = false;
                try
                    active = strcmp(char(obj.App.NavList.Value), 'Circuit Cutting');
                catch
                end
                if ~active
                    return;
                end

                r = obj.App.CuttingSvc.pollBatch( ...
                    obj.ActiveBatchId, obj.App.State.authToken);
                st  = char(JsonHelper.pick(r, 'status', ''));
                pct = JsonHelper.pick(r, 'progress_pct', 0);
                if ~isnumeric(pct); pct = 0; end
                obj.setStatus(sprintf('Batch %s   status=%s   %d%%', ...
                    obj.ActiveBatchId, st, int32(pct)));
                terminal = ismember(st, ...
                    {'completed','failed','cancelled','partial_failure'});
                if terminal
                    obj.stopPolling();
                    obj.fetchResult();
                end
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'pollTick: %s', ME.message);
            end
        end

        function fetchResult(obj)
            try
                r = obj.App.CuttingSvc.getBatchResult( ...
                    obj.ActiveBatchId, obj.App.State.authToken);
                obj.renderResult(r);
                obj.App.logEvent('CUT', sprintf('Batch %s result fetched', ...
                    obj.ActiveBatchId));
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'fetchResult: %s', ME.message);
            end
        end

        function stopPolling(obj)
            if ~isempty(obj.PollTimer)
                try stop(obj.PollTimer); delete(obj.PollTimer); catch; end
                obj.PollTimer = [];
            end
        end

        % ── Renderers ────────────────────────────────────────────────────
        function renderCutPlan(obj, plan)
            % Populate the modern structured layout: KPI strip, Cut Plan
            % card rows, Backend Assignments rows. Legacy text-areas are
            % left in place (hidden) for back-compat handle stability.
            try
                obj.renderKpiStrip(plan);
                obj.renderPlanCard(plan);
                obj.renderBackendCards(plan);
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'renderCutPlan: %s', ME.message);
            end
        end

        function renderKpiStrip(obj, plan)
            app = obj.App;
            k = double(JsonHelper.pick(plan, 'k', 0));
            obj.setLabelSafe(app.CuttingKpiKValue, sprintf('%d', k));

            overhead   = JsonHelper.pick(plan, 'sampling_overhead', 1);
            log10Hint  = JsonHelper.pick(plan, 'sampling_overhead_log10', NaN);
            obj.setLabelSafe(app.CuttingKpiOverheadValue, ...
                CircuitCuttingViewModel.formatOverheadShort(overhead, log10Hint));

            per = JsonHelper.pick(plan, 'per_subcircuit_qubits', {});
            perStr = obj.formatPerSub(per);
            % Strip outer parens for a cleaner KPI tile (caption is above it).
            if numel(perStr) >= 2 && perStr(1) == '(' && perStr(end) == ')'
                perStr = perStr(2:end-1);
            end
            obj.setLabelSafe(app.CuttingKpiQubitsValue, perStr);

            % Feasibility chip — recolor the pill based on state.
            %   _addon_overflowed=True → amber "Fallback" (the addon
            %                            couldn't propose cuts; structural
            %                            partition shown — visualization
            %                            only, run will fail clearly)
            %   feasible=false         → red "Override required" (real cut
            %                            plan, sampling overhead above the
            %                            ceiling, run needs explicit override)
            %   feasible=true          → green "OK"
            feasible   = JsonHelper.pick(plan, 'feasible', true);
            isFallback = isequal( ...
                JsonHelper.pick(plan, '_addon_overflowed', false), true);
            chip = app.CuttingKpiFeasibilityChip;
            if isempty(chip) || ~isvalid(chip); return; end
            if isFallback
                chip.Text = '  ●  Fallback  ';
                chip.BackgroundColor = Theme.COLOR_AMBER;
                chip.FontColor = [1 1 1];
            elseif isequal(feasible, false)
                chip.Text = '  ●  Override required  ';
                chip.BackgroundColor = Theme.COLOR_DANGER;
                chip.FontColor = [1 1 1];
            else
                chip.Text = '  ●  OK  ';
                chip.BackgroundColor = Theme.COLOR_SUCCESS;
                chip.FontColor = [1 1 1];
            end
        end

        function renderPlanCard(obj, plan)
            app = obj.App;
            k = double(JsonHelper.pick(plan, 'k', 0));
            cuts = JsonHelper.pick(plan, 'cuts', {});
            overhead = JsonHelper.pick(plan, 'sampling_overhead', 1);
            log10v = JsonHelper.pick(plan, 'sampling_overhead_log10', NaN);
            per = JsonHelper.pick(plan, 'per_subcircuit_qubits', {});

            obj.setLabelSafe(app.CuttingPlanKValue, sprintf('%d', k));
            obj.setLabelSafe(app.CuttingPlanCutsValue, sprintf('%d', numel(cuts)));
            obj.setLabelSafe(app.CuttingPlanOverheadValue, ...
                CircuitCuttingViewModel.formatOverheadShort(overhead, log10v));
            if isnumeric(log10v) && ~any(isnan(log10v))
                obj.setLabelSafe(app.CuttingPlanLog10Value, sprintf('%.2f', double(log10v)));
            else
                obj.setLabelSafe(app.CuttingPlanLog10Value, '—');
            end
            obj.setLabelSafe(app.CuttingPlanPerSubValue, obj.formatPerSub(per));

            % Reason text — only when the server flagged the plan infeasible
            % or supplied a fallback structural partition. The reason colour
            % matches the feasibility chip: amber for the fallback path
            % (informational — the addon couldn't propose cuts), red for a
            % genuine infeasibility (real cut plan with overhead above the
            % ceiling, needs explicit override to run).
            reasonLbl = app.CuttingPlanReasonLabel;
            if isempty(reasonLbl) || ~isvalid(reasonLbl); return; end
            feasible   = JsonHelper.pick(plan, 'feasible', true);
            isFallback = isequal( ...
                JsonHelper.pick(plan, '_addon_overflowed', false), true);
            if isequal(feasible, false)
                reason = char(JsonHelper.pick(plan, 'feasibility_reason', ...
                    'Cut plan flagged as infeasible by the server.'));
                reasonLbl.Text = sprintf( ...
                    '⚠  %s\n\nRun Cutting will ask for override confirmation.', reason);
                if isFallback
                    reasonLbl.FontColor = Theme.COLOR_AMBER;
                else
                    reasonLbl.FontColor = Theme.COLOR_DANGER;
                end
                reasonLbl.Visible = 'on';
            else
                reasonLbl.Text = '';
                reasonLbl.Visible = 'off';
            end
        end

        function renderBackendCards(obj, plan)
            % Rebuild the Backend Assignments rows from scratch on each
            % render. Mode shapes the row:
            %   * automatic            → locked label rows (server picks)
            %   * assisted / manual    → editable backend dropdown + shots
            %                            edit field per row, pre-filled
            %                            via a smallest-fit best guess
            app = obj.App;
            grid = app.CuttingBackendGrid;
            if isempty(grid) || ~isvalid(grid); return; end

            kids = grid.Children;
            for i = 1:numel(kids)
                c = kids(i);
                if isvalid(c)
                    delete(c);
                end
            end
            obj.RowControls = {};

            display = obj.displayAssignments(plan);
            n = numel(display);
            if n == 0
                grid.RowHeight = {'1x'};
                app.CuttingBackendEmptyLabel = uilabel(grid, ...
                    'Text', 'Run Analyze Cuts to assign each subcircuit to a backend.', ...
                    'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
                    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
                    'WordWrap', 'on', 'Interpreter', 'none');
                app.CuttingBackendEmptyLabel.Layout.Row = 1;
                app.CuttingBackendEmptyLabel.Layout.Column = 1;
                return;
            end

            mode = char(obj.CurrentMode);
            isLocked = strcmp(mode, 'automatic');
            poolNames = obj.poolNamesForDropdown();
            heights = num2cell(repmat(38, 1, n));
            grid.RowHeight = [heights, {'1x'}];
            obj.RowControls = cell(1, n);

            for i = 1:n
                a = display{i};
                row = uigridlayout(grid, [1 4]);
                row.RowHeight = {'1x'};
                row.ColumnWidth = {54, '1x', 100, 70};
                row.Padding = [10 4 12 4];
                row.ColumnSpacing = 10;
                row.BackgroundColor = Theme.COLOR_ACCENT_BG;
                row.Layout.Row = i;
                row.Layout.Column = 1;

                chipCell = uigridlayout(row, [3 1]);
                chipCell.RowHeight = {'1x', 22, '1x'};
                chipCell.ColumnWidth = {'1x'};
                chipCell.Padding = [0 0 0 0];
                chipCell.RowSpacing = 0;
                chipCell.BackgroundColor = Theme.COLOR_ACCENT_BG;
                chipCell.Layout.Column = 1;

                chip = uilabel(chipCell, ...
                    'Text', sprintf('#%d', a.subcircuit_idx), ...
                    'FontSize', 11, 'FontWeight', 'bold', ...
                    'FontColor', [1 1 1], ...
                    'BackgroundColor', Theme.COLOR_PRIMARY, ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
                    'Interpreter', 'none');
                chip.Layout.Row = 2;

                rc = struct('nameDropdown', [], 'shotsField', []);

                if isLocked || isempty(poolNames)
                    % Locked label row — automatic mode (server fills),
                    % or fallback when /api/backends did not return a pool
                    % we could populate dropdowns from.
                    nameTxt = char(a.backend_name);
                    if isLocked
                        nameTxt = sprintf('%s   (auto)', nameTxt);
                    end
                    nameLbl = uilabel(row, ...
                        'Text', nameTxt, ...
                        'FontSize', 13, 'FontWeight', 'bold', ...
                        'FontColor', Theme.COLOR_HEADING, ...
                        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
                        'Interpreter', 'none');
                    nameLbl.Layout.Column = 2;

                    shotsLbl = uilabel(row, ...
                        'Text', sprintf('%d shots', double(a.shots)), ...
                        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
                        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center', ...
                        'Interpreter', 'none');
                    shotsLbl.Layout.Column = 3;
                else
                    % Editable row — assisted / manual mode.
                    initialName = char(a.backend_name);
                    if ~any(strcmp(poolNames, initialName))
                        % Pre-filled name isn't in the live pool (stale
                        % default) — fall back to the first pool entry so
                        % uidropdown.Value is always one of its Items.
                        initialName = poolNames{1};
                    end
                    nameDd = uidropdown(row, ...
                        'Items', poolNames, ...
                        'ItemsData', poolNames, ...
                        'Value', initialName, ...
                        'FontSize', 12);
                    nameDd.Layout.Column = 2;
                    nameDd.Tooltip = ['Pick the backend that will run this ' ...
                        'subcircuit. Smallest-fit pre-selected; widths shown ' ...
                        'in the dropdown items.'];
                    rc.nameDropdown = nameDd;

                    shotsField = uieditfield(row, 'numeric', ...
                        'Value', double(a.shots), ...
                        'Limits', [1, 1e9], ...
                        'RoundFractionalValues', 'on', ...
                        'FontSize', 12, ...
                        'HorizontalAlignment', 'right');
                    shotsField.Layout.Column = 3;
                    shotsField.Tooltip = 'Shots per sub-experiment for this subcircuit.';
                    rc.shotsField = shotsField;

                    % Decorate dropdown items with backend qubit count so
                    % the user can pick fittingly without leaving the row.
                    nameDd.Items = obj.poolDisplayItems();
                end

                qubitLbl = uilabel(row, ...
                    'Text', obj.qubitsForSubcircuit(plan, a.subcircuit_idx), ...
                    'FontSize', 11, 'FontWeight', 'bold', ...
                    'FontColor', Theme.COLOR_LABEL, ...
                    'HorizontalAlignment', 'right', 'VerticalAlignment', 'center', ...
                    'Interpreter', 'none');
                qubitLbl.Layout.Column = 4;

                obj.RowControls{i} = rc;
            end
        end

        function names = poolNamesForDropdown(obj)
            % Plain backend-name list for the dropdown ItemsData. Filters
            % simulators out so dispatch always targets real hardware.
            names = {};
            pool = obj.BackendPool;
            for i = 1:numel(pool)
                e = pool{i};
                if isfield(e, 'simulator') && e.simulator; continue; end
                if isempty(strtrim(char(e.name))); continue; end
                names{end+1} = char(e.name); %#ok<AGROW>
            end
        end

        function items = poolDisplayItems(obj)
            % Items for the dropdown labels — "ibm_kingston (156q)". Same
            % order as poolNamesForDropdown so positional match holds.
            names = obj.poolNamesForDropdown();
            items = cell(1, numel(names));
            for i = 1:numel(names)
                nq = obj.lookupQubits(names{i});
                if isempty(nq)
                    items{i} = names{i};
                else
                    items{i} = sprintf('%s (%dq)', names{i}, nq);
                end
            end
        end

        function nq = lookupQubits(obj, name)
            nq = [];
            pool = obj.BackendPool;
            for i = 1:numel(pool)
                if strcmp(char(pool{i}.name), char(name))
                    nq = pool{i}.num_qubits;
                    return;
                end
            end
        end

        function display = displayAssignments(obj, plan)
            % What to render in the Backend Assignments panel — always k
            % entries, even when collectBackends returns {} (automatic).
            % Picks smallest-fit per row when the pool has widths;
            % otherwise round-robins over the pool ordering.
            k = JsonHelper.pick(plan, 'k', 1);
            if ~isnumeric(k); k = str2double(k); end
            k = max(1, double(k));
            per = obj.perSubcircuitQubits(plan);
            display = cell(1, k);
            for i = 1:k
                width = 0;
                if i <= numel(per); width = double(per(i)); end
                name = obj.bestFitBackendName(width);
                if isempty(strtrim(name))
                    if ~isempty(obj.BackendPool)
                        name = char(obj.BackendPool{mod(i-1, numel(obj.BackendPool))+1}.name);
                    else
                        name = 'ibm_miami';
                    end
                end
                display{i} = struct( ...
                    'subcircuit_idx', int32(i - 1), ...
                    'backend_name', name, ...
                    'shots', int32(4096));
            end
        end

        function s = qubitsForSubcircuit(~, plan, idx)
            per = JsonHelper.pick(plan, 'per_subcircuit_qubits', {});
            if iscell(per); arr = per; elseif isnumeric(per); arr = num2cell(per); else; arr = {}; end
            i = double(idx) + 1;   % subcircuit_idx is 0-based
            if i >= 1 && i <= numel(arr)
                v = arr{i}; if ~isnumeric(v); v = str2double(v); end
                s = sprintf('%dq', int32(v));
            else
                s = '—';
            end
        end

        function setLabelSafe(~, lbl, txt)
            if isempty(lbl) || ~isvalid(lbl); return; end
            lbl.Text = char(txt);
        end

        function checkCuttability(obj, circuitId)
            % Fetch the circuit's QASM source and scan it for patterns
            % qiskit-addon-cutting cannot handle (mid-circuit measurements,
            % classical-controlled gates, resets). Cached by circuitId so
            % rapid dropdown toggling doesn't refetch. The fetch runs
            % silently — no on-screen "Checking compatibility..." status;
            % a modal uialert pops only when the verdict is incompatible.
            if strcmp(circuitId, obj.LastCuttabilityCircuitId) && ...
                    ~isempty(obj.LastCuttabilityResult)
                obj.applyCuttability(obj.LastCuttabilityResult);
                return;
            end

            app = obj.App;
            svc   = app.CircuitSvc;
            token = app.State.authToken;
            cid   = char(circuitId);

            AsyncRunner.run( ...
                @() svc.getCircuit(cid, token), ...
                @(r) obj.onCuttabilityFetched(cid, r), ...
                @(ME) obj.onCuttabilityFetchFailed(cid, ME));
        end

        function onCuttabilityFetched(obj, circuitId, response)
            qasm = char(JsonHelper.pick(response, 'raw_content', ''));
            if isempty(qasm)
                qasm = char(JsonHelper.pick(response, 'content', ''));
            end
            res = CircuitCuttingViewModel.checkQasmCuttable(qasm);
            obj.LastCuttabilityCircuitId = circuitId;
            obj.LastCuttabilityResult = res;
            obj.applyCuttability(res);
            % Pop a modal alert *only* on a fresh fetch — the cached path
            % in checkCuttability skips this so re-selecting the same
            % circuit doesn't re-pop the dialog. Covers both QASM-scanner
            % verdicts (classical-controlled gates + mid-circuit measure)
            % since both produce severity='error'. The persistent banner
            % and disabled Analyze/Run buttons remain as ongoing context.
            obj.maybeAlertCuttability(res);
        end

        function maybeAlertCuttability(obj, res)
            sev = '';
            try; sev = char(res.severity); catch; end
            if ~strcmp(sev, 'error') && ~strcmp(sev, 'warning')
                return;
            end
            reason = '';
            try; reason = char(res.reason); catch; end
            if isempty(reason); return; end
            if strcmp(sev, 'error')
                icon = 'error';
            else
                icon = 'warning';
            end
            try
                uialert(obj.App.UIFigure, reason, 'Circuit Cutting', ...
                    'Icon', icon);
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'maybeAlertCuttability uialert failed: %s', ME.message);
            end
        end

        function onCuttabilityFetchFailed(obj, circuitId, ME)
            % If we can't fetch the QASM (offline, 404, etc.) don't block
            % the user — just hide the banner and let them try analyze.
            % The server-side scanner will still catch incompatible
            % circuits via the 422 path we already handle.
            Logger.warn('CircuitCuttingViewModel', ...
                'Cuttability fetch failed for %s: %s', circuitId, ME.message);
            obj.applyCuttability(struct('ok', true, 'severity', 'ok', 'reason', ''));
        end

        function applyCuttability(obj, res)
            % Toggle the Analyze / Run button enable state based on the
            % QASM-scanner verdict. The verdict itself is communicated
            % to the user via a modal uialert popup fired by
            % maybeAlertCuttability — there is no inline banner anymore.
            app = obj.App;
            analyzeBtn = app.CuttingAnalyzeBtn;
            runBtn = app.CuttingRunBtn;

            sev = '';
            try; sev = char(res.severity); catch; end

            if strcmp(sev, 'error')
                enableState = 'off';
            else
                enableState = 'on';
            end

            if ~isempty(analyzeBtn) && isvalid(analyzeBtn)
                analyzeBtn.Enable = enableState;
            end
            if ~isempty(runBtn) && isvalid(runBtn)
                runBtn.Enable = enableState;
            end
        end

        function renderResult(obj, r)
            try
                st  = char(JsonHelper.pick(r, 'status', ''));
                exps = JsonHelper.pick(r, 'expectations', {});

                % Hide the empty state and show the real-results textarea.
                if ~isempty(obj.App.CuttingResultsEmptyLabel) && ...
                        isvalid(obj.App.CuttingResultsEmptyLabel)
                    obj.App.CuttingResultsEmptyLabel.Visible = 'off';
                end
                if ~isempty(obj.App.CuttingResultsLabel) && ...
                        isvalid(obj.App.CuttingResultsLabel)
                    obj.App.CuttingResultsLabel.Visible = 'on';
                end

                if isempty(exps) || (iscell(exps) && isempty(exps))
                    obj.App.CuttingResultsLabel.Value = sprintf( ...
                        'Batch %s finished with status=%s (no reconstructed values).', ...
                        obj.ActiveBatchId, st);
                    return;
                end
                lines = {sprintf('Batch %s  -  %s', obj.ActiveBatchId, st), ''};
                for i = 1:numel(exps)
                    e = exps(i); if iscell(exps); e = exps{i}; end
                    obsName = char(JsonHelper.pick(e, 'observable', '?'));
                    val = JsonHelper.pick(e, 'value', NaN);
                    err = JsonHelper.pick(e, 'std_err', 0);
                    if isnumeric(val)
                        lines{end+1} = sprintf('  %s  =  %.4f  (std_err %.4f)', ...
                            obsName, double(val), double(err)); %#ok<AGROW>
                    else
                        lines{end+1} = sprintf('  %s  =  %s', ...
                            obsName, string(val)); %#ok<AGROW>
                    end
                end
                obj.App.CuttingResultsLabel.Value = lines;
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'renderResult: %s', ME.message);
            end
        end

        function refreshStatus(obj)
            obj.setStatus(sprintf( ...
                'Mode: %s   Preset: %s   Press Analyze Cuts to begin.', ...
                obj.CurrentMode, obj.CurrentPreset));
        end

        function setStatus(obj, msg)
            try
                obj.App.CuttingStatusLabel.Text = msg;
            catch
                % label not yet built (first call from constructor)
            end
        end

        % ── Formatters ───────────────────────────────────────────────────
        function s = formatOverhead(~, v, log10Hint)
            % Compact human-readable overhead. Defers to the static
            % formatOverheadShort which falls back to scientific notation
            % with Unicode superscripts so values like γ=3.23e+114 don't
            % spill 110 digits across the status line. The optional
            % log10Hint kicks in when v has been clamped to the float64-
            % safe sentinel (1e308) by the server's overflow-fallback
            % path — see formatOverheadShort for details.
            if nargin < 3; log10Hint = []; end
            s = CircuitCuttingViewModel.formatOverheadShort(v, log10Hint);
        end

        function s = formatPerSub(~, per)
            if isempty(per); s = '(unknown)'; return; end
            if iscell(per)
                parts = cellfun(@(x) sprintf('%d', int32(x)), per, ...
                    'UniformOutput', false);
            else
                parts = arrayfun(@(x) sprintf('%d', int32(x)), per, ...
                    'UniformOutput', false);
            end
            s = ['(' strjoin(parts, '+') ')'];
        end

        function onError(obj, ME)
            % Errors surface as a popup only — never as inline status
            % text. The status label is for live progress ("Batch xxx
            % running 50%"), not for failure messages, which would
            % otherwise leak HTTP details + the internal server URL
            % into the screen body.
            obj.App.hideLoading();
            obj.App.showError('Circuit Cutting', ME);
            obj.setStatus('');
        end
    end

    methods (Static)
        function res = checkQasmCuttable(qasm)
            % Scan QASM source for patterns qiskit-addon-cutting refuses
            % (it requires a purely-unitary input). Returns a struct:
            %   .ok        — boolean, true = safe to attempt cutting
            %   .severity  — 'ok' | 'warning' | 'error'
            %   .reason    — short human-readable explanation for the banner
            % Catches the common BB84-class cases without a full QASM
            % parser; the server's strip-and-validate pass is still the
            % authoritative check, this is just a fast pre-filter so the
            % operator gets immediate feedback when they pick a circuit
            % that obviously can't be cut.
            res = struct('ok', true, 'severity', 'ok', 'reason', '');
            if isempty(qasm); return; end
            txt = char(qasm);

            % Strip line comments (// ...) so they don't trigger false
            % positives in the regex checks below.
            txt = regexprep(txt, '//[^\n\r]*', '');

            % Classical-controlled operations — the addon cannot cut a
            % circuit that branches on a classical bit value.
            if ~isempty(regexp(txt, '\<if\s*\(', 'once'))
                res.ok = false;
                res.severity = 'error';
                res.reason = ['Circuit has classical-controlled gates (if statements). ' ...
                              'qiskit-addon-cutting cannot cut measurement-based protocols ' ...
                              'like BB84 — run on a single backend instead.'];
                return;
            end

            % Reset operations imply mid-circuit re-initialisation, which
            % the addon also rejects.
            if ~isempty(regexp(txt, '\<reset\s', 'once'))
                res.ok = false;
                res.severity = 'error';
                res.reason = ['Circuit has reset operations — cuts cannot preserve ' ...
                              'mid-circuit re-initialisation semantics.'];
                return;
            end

            % Mid-circuit measurement detector: for each qubit, if a
            % measure instruction appears before any non-measure / non-
            % barrier op on the same qubit, that qubit has a real mid-
            % circuit measurement.
            lines = strsplit(txt, char(10));
            firstMeasureLine = containers.Map('KeyType', 'int32', ...
                                              'ValueType', 'int32');
            for i = 1:numel(lines)
                ln = strtrim(lines{i});
                if isempty(ln); continue; end
                tok = regexp(ln, '^measure\s+\w+\[(\d+)\]\s*->', ...
                             'tokens', 'once');
                if ~isempty(tok)
                    qIdx = int32(str2double(tok{1}));
                    if ~isKey(firstMeasureLine, qIdx)
                        firstMeasureLine(qIdx) = int32(i);
                    end
                end
            end

            if firstMeasureLine.Count == 0; return; end

            keys = cell2mat(firstMeasureLine.keys);
            for k = 1:numel(keys)
                qIdx = keys(k);
                firstLine = firstMeasureLine(qIdx);
                qPattern = sprintf('\\<q\\[%d\\]', qIdx);
                for j = firstLine + 1 : numel(lines)
                    ln = strtrim(lines{j});
                    if isempty(ln); continue; end
                    if startsWith(ln, 'barrier'); continue; end
                    if startsWith(ln, 'measure'); continue; end
                    if startsWith(ln, 'OPENQASM') || startsWith(ln, 'include'); continue; end
                    if startsWith(ln, 'qreg')   || startsWith(ln, 'creg');     continue; end
                    if ~isempty(regexp(ln, qPattern, 'once'))
                        res.ok = false;
                        res.severity = 'error';
                        res.reason = sprintf( ...
                            ['Mid-circuit measurement detected — qubit q[%d] ' ...
                             'is measured at line %d and then operated on at ' ...
                             'line %d. Cuts cannot preserve mid-circuit ' ...
                             'measurement semantics.'], ...
                             qIdx, firstLine, j);
                        return;
                    end
                end
            end
        end

        function s = formatOverheadShort(v, log10Hint)
            % Compact human-readable sampling overhead.
            %   v < 1e4           → "3.2x"
            %   1e4 ≤ v < 1e16    → "3.23×10⁹"   (Unicode superscript exponent)
            %   v ≥ 1e16          → same scientific form, exponent up to ~10³⁰⁸
            %   Inf / NaN / empty → "—"
            % Avoids dumping 110-digit decimal text for values like
            % γ=3.23e+114 produced by qiskit-addon-cutting on huge circuits.
            %
            % Optional ``log10Hint`` — when provided AND > 308, the float
            % ``v`` was clamped to the JSON-safe 1e308 sentinel by the
            % server (the real magnitude is too big for float64). Format
            % from the hint instead so "1×10³⁰⁸" doesn't get displayed
            % alongside a contradicting "log₁₀(overhead) 717.66". Output
            % uses a leading "~" tilde to flag the value as estimated.
            if nargin < 2; log10Hint = []; end
            if ~isempty(log10Hint) && isnumeric(log10Hint) && isscalar(log10Hint) ...
                    && ~isnan(double(log10Hint)) && double(log10Hint) > 308
                L = double(log10Hint);
                e = floor(L);
                m = 10 ^ (L - e);
                s = sprintf('~%.2f×10%s', m, ...
                    CircuitCuttingViewModel.unicodeSuperscript(e));
                return;
            end
            if isempty(v) || ~isnumeric(v) || any(isnan(v(:)))
                s = '—'; return;
            end
            v = double(v);
            if any(isinf(v)); s = '∞'; return; end
            if v <= 0
                s = sprintf('%.2fx', v); return;
            end
            if v < 1e4
                s = sprintf('%.2fx', v); return;
            end
            e = floor(log10(v));
            m = v / (10 ^ e);
            s = sprintf('%.2f×10%s', m, CircuitCuttingViewModel.unicodeSuperscript(e));
        end

        function s = unicodeSuperscript(n)
            % Convert an integer to a Unicode superscript string,
            % e.g. 114 → '¹¹⁴', -3 → '⁻³'. Used for compact scientific
            % notation in the KPI tile and Cut Plan card.
            n = round(double(n));
            digits = '0123456789';
            sup    = {'⁰','¹','²','³','⁴','⁵','⁶','⁷','⁸','⁹'};
            if n < 0
                neg = '⁻'; n = -n;
            else
                neg = '';
            end
            d = sprintf('%d', n);
            parts = cell(1, numel(d));
            for i = 1:numel(d)
                idx = strfind(digits, d(i));
                parts{i} = sup{idx};
            end
            s = [neg strjoin(parts, '')];
        end

        function obs = parseObservableLines(lines, placeholder)
            % Normalize a cell/string array of textarea lines into a cell
            % of trimmed Pauli strings, dropping blanks and the placeholder
            % sentinel. Returns {} when the user typed nothing meaningful.
            %
            % What happens server-side when this returns {}:
            %   AUTOMATIC mode: server derives per-qubit Z +
            %     nearest-neighbor ZZ from the circuit width
            %     (default_observables_for_circuit), then runs.
            %   ASSISTED / MANUAL: server stores observables as [] and
            %     reconstruction returns one sentinel entry with status
            %     "no_observables_submitted". The Reconstruction
            %     Summary popup renders that as a tailored diagnostic
            %     instead of a meaningless number. The onRunBatch
            %     pre-flight surfaces a warning before submit so this
            %     case is rare in practice.
            obs = {};
            if nargin < 2; placeholder = ''; end
            if isempty(lines); return; end
            if ischar(lines); lines = {lines}; end
            if isstring(lines); lines = cellstr(lines); end
            if ~iscell(lines); return; end
            ph = strtrim(char(placeholder));
            for i = 1:numel(lines)
                s = strtrim(char(lines{i}));
                if isempty(s); continue; end
                if ~isempty(ph) && strcmp(s, ph); continue; end
                obs{end+1} = s; %#ok<AGROW>
            end
        end
    end
end
