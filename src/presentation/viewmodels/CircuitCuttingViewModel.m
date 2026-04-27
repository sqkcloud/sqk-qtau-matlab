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
    end

    properties (Constant)
        % Single source of truth for the Observables textarea placeholder.
        % Screen uses it to seed the widget; parseObservables uses it to
        % recognize and drop the line so it never gets sent as a Pauli string.
        OBSERVABLES_PLACEHOLDER = '(default: all-Z over full circuit width)'
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
            obj.refreshStatus();
            obj.LastRefresh = tic;
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
        end

        function onPresetChanged(obj, preset)
            obj.CurrentPreset = string(preset);
            obj.refreshStatus();
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
            k  = JsonHelper.pick(c, 'k', 0);
            oh = JsonHelper.pick(c, 'sampling_overhead', 1.0);
            per = JsonHelper.pick(c, 'per_subcircuit_qubits', {});
            obj.setStatus(sprintf( ...
                '%d subcircuits   %s   overhead %s', ...
                k, obj.formatPerSub(per), obj.formatOverhead(oh)));
            obj.renderCutPlan(c);
        end

        function body = buildCreateBody(obj, overrideFeasibility)
            if nargin < 2 || isempty(overrideFeasibility)
                overrideFeasibility = false;
            end
            c = obj.firstCandidate();
            body = struct();
            body.mode = char(obj.CurrentMode);
            body.preset = char(obj.CurrentPreset);
            body.cut_plan = c;
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

        function obs = parseObservables(obj)
            % Pull Pauli strings from the Observables textarea, drop the
            % placeholder and blank lines. Empty result → {} so the server
            % falls back to its default all-Z over full circuit width.
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

        function assns = collectBackends(~, cutPlan)
            k = JsonHelper.pick(cutPlan, 'k', 1);
            if ~isnumeric(k); k = str2double(k); end
            assns = cell(1, k);
            for i = 1:k
                assns{i} = struct( ...
                    'subcircuit_idx', int32(i - 1), ...
                    'backend_name', 'ibm_miami', ...
                    'shots', int32(4096));
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
            try
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

            overhead = JsonHelper.pick(plan, 'sampling_overhead', 1);
            obj.setLabelSafe(app.CuttingKpiOverheadValue, ...
                CircuitCuttingViewModel.formatOverheadShort(overhead));

            per = JsonHelper.pick(plan, 'per_subcircuit_qubits', {});
            perStr = obj.formatPerSub(per);
            % Strip outer parens for a cleaner KPI tile (caption is above it).
            if numel(perStr) >= 2 && perStr(1) == '(' && perStr(end) == ')'
                perStr = perStr(2:end-1);
            end
            obj.setLabelSafe(app.CuttingKpiQubitsValue, perStr);

            % Feasibility chip — recolor the pill based on state.
            feasible = JsonHelper.pick(plan, 'feasible', true);
            chip = app.CuttingKpiFeasibilityChip;
            if isempty(chip) || ~isvalid(chip); return; end
            if isequal(feasible, false)
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
                CircuitCuttingViewModel.formatOverheadShort(overhead));
            if isnumeric(log10v) && ~any(isnan(log10v))
                obj.setLabelSafe(app.CuttingPlanLog10Value, sprintf('%.2f', double(log10v)));
            else
                obj.setLabelSafe(app.CuttingPlanLog10Value, '—');
            end
            obj.setLabelSafe(app.CuttingPlanPerSubValue, obj.formatPerSub(per));

            % Reason text — only when the server flagged the plan infeasible.
            reasonLbl = app.CuttingPlanReasonLabel;
            if isempty(reasonLbl) || ~isvalid(reasonLbl); return; end
            feasible = JsonHelper.pick(plan, 'feasible', true);
            if isequal(feasible, false)
                reason = char(JsonHelper.pick(plan, 'feasibility_reason', ...
                    'Cut plan flagged as infeasible by the server.'));
                reasonLbl.Text = sprintf( ...
                    '⚠  %s\n\nRun Cutting will ask for override confirmation.', reason);
                reasonLbl.Visible = 'on';
            else
                reasonLbl.Text = '';
                reasonLbl.Visible = 'off';
            end
        end

        function renderBackendCards(obj, plan)
            % Rebuild the Backend Assignments rows from scratch on each
            % render — one styled row per subcircuit:
            %   [#N chip]  backend_name           4096 shots   19q
            app = obj.App;
            grid = app.CuttingBackendGrid;
            if isempty(grid) || ~isvalid(grid); return; end

            % Tear down existing children before rebuilding from the
            % candidate plan. The legacy CuttingBackendText was dropped in
            % the screen refactor, so we delete every valid child.
            kids = grid.Children;
            for i = 1:numel(kids)
                c = kids(i);
                if isvalid(c)
                    delete(c);
                end
            end

            assns = obj.collectBackends(plan);
            n = numel(assns);
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

            % n × 38 px rows + a flex spacer so cards don't stretch when k
            % is small.
            heights = num2cell(repmat(38, 1, n));
            grid.RowHeight = [heights, {'1x'}];

            for i = 1:n
                a = assns{i};
                row = uigridlayout(grid, [1 4]);
                row.RowHeight = {'1x'};
                row.ColumnWidth = {54, '1x', 100, 70};
                row.Padding = [10 4 12 4];
                row.ColumnSpacing = 10;
                row.BackgroundColor = Theme.COLOR_ACCENT_BG;
                row.Layout.Row = i;
                row.Layout.Column = 1;

                % Chip lives inside a 3-row centering grid so it renders
                % as a fixed 22-px pill (instead of stretching to the full
                % row height, which makes it look like a tall rectangle).
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

                nameLbl = uilabel(row, ...
                    'Text', char(a.backend_name), ...
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

                qubitLbl = uilabel(row, ...
                    'Text', obj.qubitsForSubcircuit(plan, a.subcircuit_idx), ...
                    'FontSize', 11, 'FontWeight', 'bold', ...
                    'FontColor', Theme.COLOR_LABEL, ...
                    'HorizontalAlignment', 'right', 'VerticalAlignment', 'center', ...
                    'Interpreter', 'none');
                qubitLbl.Layout.Column = 4;
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
        function s = formatOverhead(~, v)
            % Compact human-readable overhead. Defers to the static
            % formatOverheadShort which falls back to scientific notation
            % with Unicode superscripts so values like γ=3.23e+114 don't
            % spill 110 digits across the status line.
            s = CircuitCuttingViewModel.formatOverheadShort(v);
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
            obj.App.hideLoading();
            obj.App.showError('Circuit Cutting', ME);
            obj.setStatus(sprintf('Error: %s', ME.message));
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

        function s = formatOverheadShort(v)
            % Compact human-readable sampling overhead.
            %   v < 1e4           → "3.2x"
            %   1e4 ≤ v < 1e16    → "3.23×10⁹"   (Unicode superscript exponent)
            %   v ≥ 1e16          → same scientific form, exponent up to ~10³⁰⁸
            %   Inf / NaN / empty → "—"
            % Avoids dumping 110-digit decimal text for values like
            % γ=3.23e+114 produced by qiskit-addon-cutting on huge circuits.
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
            % sentinel. Returns {} when the user typed nothing meaningful
            % so the server defaults to all-Z over full circuit width.
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
