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
        CurrentMode    = "assisted"
        CurrentPreset  = "generic"
        LastAnalyze    = []
        ActiveBatchId  = ''
        PollTimer      = []
        LastRefresh    = []
    end

    methods
        function obj = CircuitCuttingViewModel(app)
            obj.App = app;
        end

        % ── Entry hook ───────────────────────────────────────────────────
        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            obj.loadPresets();
            obj.refreshStatus();
            obj.LastRefresh = tic;
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
            % IMPORTANT: bind svc + token to LOCAL variables before the
            % lambda. Referencing `app.CuttingSvc` inside the closure would
            % capture the entire QTAUWorkbenchApp (which holds uifigure +
            % uihtml components) — parfeval then serializes it to the
            % worker, which fails with MATLAB:class:InvalidSuperClass on
            % matlab.ui.control.WebComponent. Matches the pattern used by
            % BenchmarkDashboardViewModel.onRefreshAll.
            svc   = app.CuttingSvc;
            token = app.State.authToken;
            app.showLoading();
            AsyncRunner.run( ...
                @() svc.analyzeCuts(cid, [], token), ...
                @(r) obj.applyAnalyze(r), ...
                @(ME) obj.onError(ME));
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
            body = obj.buildCreateBody();
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

        function body = buildCreateBody(obj)
            candidates = JsonHelper.pick(obj.LastAnalyze, 'candidates', {});
            c = candidates(1); if iscell(candidates); c = candidates{1}; end
            body = struct();
            body.mode = char(obj.CurrentMode);
            body.preset = char(obj.CurrentPreset);
            body.cut_plan = c;
            body.backend_assignments = obj.collectBackends(c);
            body.observables = {};
            body.opt_in_distribution = false;
            try
                body.opt_in_distribution = logical( ...
                    obj.App.CuttingDistCheckbox.Value);
            catch; end
            body.timeout_hours = 6.0;
            body.retry_strategy = 'none';
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
            try
                lines = {};
                lines{end+1} = sprintf('k = %d subcircuits', ...
                    double(JsonHelper.pick(plan, 'k', 0)));
                lines{end+1} = sprintf('sampling overhead = %s', ...
                    obj.formatOverhead(JsonHelper.pick(plan, 'sampling_overhead', 1)));
                per = JsonHelper.pick(plan, 'per_subcircuit_qubits', {});
                lines{end+1} = sprintf('per-subcircuit qubits: %s', ...
                    obj.formatPerSub(per));
                cuts = JsonHelper.pick(plan, 'cuts', {});
                lines{end+1} = sprintf('cuts detected: %d', numel(cuts));
                obj.App.CuttingPlanText.Value = lines;

                assns = obj.collectBackends(plan);
                bLines = cell(1, numel(assns));
                for i = 1:numel(assns)
                    a = assns{i};
                    bLines{i} = sprintf('subcircuit %d  ->  %s  (%d shots)', ...
                        a.subcircuit_idx, a.backend_name, a.shots);
                end
                obj.App.CuttingBackendText.Value = bLines;
            catch ME
                Logger.warn('CircuitCuttingViewModel', ...
                    'renderCutPlan: %s', ME.message);
            end
        end

        function renderResult(obj, r)
            try
                st  = char(JsonHelper.pick(r, 'status', ''));
                exps = JsonHelper.pick(r, 'expectations', {});
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
            if isempty(v) || ~isnumeric(v) || any(isnan(v))
                s = '--'; return;
            end
            s = sprintf('%.1fx', double(v));
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
end
