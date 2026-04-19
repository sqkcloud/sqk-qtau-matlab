classdef PredictionViewModel < handle
    % PredictionViewModel  Callback handlers for the Prediction screen.
    %
    %   Drives POST /api/predict via the PredictionService, then populates:
    %     - Summary table (top backend, fidelity, success prob, confidence,
    %       queue time, runtime, cost, risk, prediction id)
    %     - Headline callout (one-liner recommendation)
    %     - Probability distribution bar chart (top 8 measurement outcomes)
    %     - Error budget breakdown bar chart (gate/readout/decoherence/crosstalk)
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = PredictionViewModel(app)
            obj.App = app;
        end

        % Populate the Circuit + Backend dropdowns on the toolbar from
        % the live API. Called by NavigationManager.autoLoadScreen when
        % the user opens the Prediction tab.
        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            obj.loadCircuits();
            obj.loadBackends();
            obj.LastRefresh = tic;
        end

        function loadCircuits(obj)
            app = obj.App;
            token = app.State.authToken;
            circSvc = app.CircuitSvc;
            AsyncRunner.run( ...
                @() circSvc.listCircuits(token), ...
                @(data) obj.onCircuitsLoaded(app, data), ...
                @(ME)   obj.onDropdownLoadError(app, 'circuits', ME));
        end

        function loadBackends(obj)
            app = obj.App;
            token = app.State.authToken;
            backendSvc = app.BackendSvc;
            circSvc    = app.CircuitSvc;
            cid = '';
            if app.State.hasCircuit(); cid = char(app.State.selectedCircuitId); end
            AsyncRunner.run( ...
                @() PredictionViewModel.fetchBackendList(backendSvc, circSvc, cid, token), ...
                @(data) obj.onBackendsLoaded(app, data), ...
                @(ME)   obj.onDropdownLoadError(app, 'backends', ME));
        end

        function onCircuitSelected(obj, circuitId)
            app = obj.App;
            if isempty(circuitId); return; end
            app.State.selectedCircuitId = string(circuitId);
            % Update the circuit name for logging / UI too.
            try
                items = app.PredictionCircuitDropdown.Items;
                ids   = app.PredictionCircuitDropdown.ItemsData;
                k = find(strcmp(ids, char(circuitId)), 1);
                if ~isempty(k)
                    app.State.selectedCircuitName = string(items{k});
                end
            catch; end
            app.logEvent('UI', sprintf('Prediction circuit selected: %s', ...
                char(app.State.selectedCircuitName)));
            % Backend fidelity depends on the circuit — refresh the list.
            obj.loadBackends();
        end

        function onBackendSelected(obj, backendName)
            app = obj.App;
            if isempty(backendName); return; end
            app.State.selectedBackend = string(backendName);
            app.logEvent('UI', sprintf('Prediction backend selected: %s', char(backendName)));
        end

        function onRunPrediction(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Prediction', 'Icon', 'warning'); return;
            end
            if ~app.State.hasCircuit()
                uialert(app.UIFigure, Labels.get('error_no_circuit'), 'Prediction', 'Icon', 'warning');
                return;
            end
            backend = char(app.State.selectedBackend);
            if isempty(strtrim(backend))
                uialert(app.UIFigure, ...
                    Labels.get('error_no_backend', 'Select a backend on the Backends screen first.'), ...
                    'Prediction', 'Icon', 'warning');
                return;
            end
            cid   = char(app.State.selectedCircuitId);
            shots = app.State.benchmarkShots;
            opt   = app.State.benchmarkOptLevel;
            app.logEvent('API', sprintf('POST /api/predict — circuit: %s  backend: %s  shots: %d  opt: %d', ...
                cid, backend, shots, opt));
            app.showLoading(Labels.get('loading_prediction', 'Running prediction...'));
            predSvc = app.PredictionSvc;
            token   = app.State.authToken;
            AsyncRunner.run( ...
                @() predSvc.predict(cid, backend, shots, opt, token), ...
                @(data) obj.onPredictComplete(app, cid, backend, data), ...
                @(ME)   obj.onPredictError(app, cid, backend, ME));
        end

        function onPredictComplete(obj, app, cid, backend, data)
            app.State.predictionId = string(JsonHelper.pick(data, {'prediction_id','id'}));
            obj.applyPredictionData(data);
            app.logEvent('API', sprintf('Prediction complete — id: %s  circuit: %s  backend: %s', ...
                app.State.predictionId, cid, backend));
            app.State.logActivity(sprintf('Run prediction — %s', char(app.State.selectedCircuitName)), 'Success');
            app.hideLoading();
        end

        function onPredictError(~, app, cid, backend, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Prediction FAILED (circuit: %s  backend: %s): %s', cid, backend, ME.message));
            app.showError('Run Prediction', ME);
        end

        % onSubmitToIbm  POST /api/jobs/submit with the current circuit +
        %   backend + shots/opt, then navigate to the Jobs screen.
        %   Mirrors the notebook's SamplerV2(mode=session).run() call path —
        %   the server holds the IBM credentials and does the transpile/submit.
        function onSubmitToIbm(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Submit', 'Icon', 'warning'); return;
            end
            if ~app.State.hasCircuit()
                uialert(app.UIFigure, Labels.get('error_no_circuit'), 'Submit', 'Icon', 'warning'); return;
            end
            backend = char(app.State.selectedBackend);
            if isempty(strtrim(backend))
                uialert(app.UIFigure, ...
                    Labels.get('error_no_backend', 'Select a backend on the Backends screen first.'), ...
                    'Submit', 'Icon', 'warning');
                return;
            end
            % Surface clear errors if we already know the server state —
            % ServerIbmConfig is populated by WelcomeViewModel.prefetchServerIbmConfig
            % at login (and refreshed on the Settings screen). An empty
            % `channel` means the prefetch hasn't completed; in that case
            % skip the pre-check and let the server return 503 if needed
            % (never block on stale default state).
            cfg = app.ServerIbmConfig;
            if isstruct(cfg) && isfield(cfg, 'channel') && strlength(string(cfg.channel)) > 0
                if isfield(cfg, 'runtime_broken') && logical(cfg.runtime_broken)
                    reason = '';
                    if isfield(cfg, 'runtime_broken_reason')
                        reason = char(string(cfg.runtime_broken_reason));
                    end
                    uialert(app.UIFigure, ...
                        sprintf('IBM runtime unavailable on server:\n%s', reason), ...
                        'Submit', 'Icon', 'warning');
                    return;
                end
                if isfield(cfg, 'has_token') && ~logical(cfg.has_token)
                    uialert(app.UIFigure, ...
                        Labels.get('error_no_server_token', ...
                            'Server is not configured with an IBM token.'), ...
                        'Submit', 'Icon', 'warning');
                    return;
                end
            end
            cid   = char(app.State.selectedCircuitId);
            shots = app.State.benchmarkShots;
            opt   = app.State.benchmarkOptLevel;
            mitig = char(app.State.benchmarkMitigation);
            payload = struct( ...
                'circuit_id',         cid, ...
                'backend_name',       backend, ...
                'shots',              shots, ...
                'optimization_level', opt);
            if ~isempty(mitig) && ~strcmp(mitig, 'none')
                payload.error_mitigation = mitig;
            end
            app.logEvent('API', sprintf('POST /api/jobs/submit — circuit: %s  backend: %s  shots: %d  opt: %d', ...
                cid, backend, shots, opt));
            app.showLoading(Labels.get('loading_submitting', 'Submitting job to IBM Quantum...'));
            jobSvc = app.JobSvc;
            token  = app.State.authToken;
            AsyncRunner.run( ...
                @() jobSvc.submitJob(payload, token), ...
                @(data) obj.onSubmitComplete(app, cid, backend, data), ...
                @(ME)   obj.onSubmitError(app, cid, backend, ME));
        end

        function onSubmitComplete(~, app, cid, backend, data)
            app.hideLoading();
            recordId = char(JsonHelper.pick(data, {'job_record_id','id'}));
            ibmJobId = char(JsonHelper.pick(data, {'ibm_job_id'}));
            status   = char(JsonHelper.pick(data, {'status'}));
            if ~isempty(recordId)
                app.State.selectedJobId = string(recordId);
            end
            app.logEvent('API', sprintf('Job submitted — record: %s  ibm_job_id: %s  status: %s', ...
                recordId, ibmJobId, status));
            app.State.logActivity(sprintf('Submit job — %s → %s', char(app.State.selectedCircuitName), backend), 'Success');
            % Navigate to Jobs so the user sees the new record.
            app.onSelectSection('Jobs');
            uialert(app.UIFigure, ...
                sprintf(Labels.get('submit_job_success', 'Job submitted. IBM job id: %s'), ibmJobId), ...
                'Submit to IBM', 'Icon', 'success');
        end

        function onSubmitError(~, app, cid, backend, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Submit job FAILED (circuit: %s  backend: %s): %s', cid, backend, ME.message));
            % A 503 almost always means the server marked its IBM runtime
            % broken after the ServerIbmConfig cache was last refreshed.
            % Refetch once and surface the real reason so the user doesn't
            % think the MATLAB client is wrong.
            if contains(ME.message, '503') || contains(ME.message, 'Service Unavailable')
                settSvc = app.SettingsSvc;
                tok     = app.State.authToken;
                AsyncRunner.run( ...
                    @() settSvc.getIbmConfig(tok), ...
                    @(cfg) PredictionViewModel.explain503(app, cfg, cid, backend), ...
                    @(~)   app.showError('Submit to IBM', ME));
                return;
            end
            app.showError('Submit to IBM', ME);
        end

        function onCircuitsLoaded(~, app, data)
            if isempty(app.PredictionCircuitDropdown) ...
                    || ~isvalid(app.PredictionCircuitDropdown); return; end
            items = JsonHelper.extractList(data, 'circuits');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0
                app.PredictionCircuitDropdown.Items     = {'(no circuits)'};
                app.PredictionCircuitDropdown.ItemsData = {''};
                app.PredictionCircuitDropdown.Value     = '';
                return;
            end
            names = cell(1, n); ids = cell(1, n);
            for i = 1:n
                ids{i}   = char(JsonHelper.pick(items(i), {'circuit_id','id'}));
                nm       = char(JsonHelper.pick(items(i), {'name','circuit_name'}));
                if isempty(nm); nm = ids{i}; end
                names{i} = nm;
            end
            app.PredictionCircuitDropdown.Items     = names;
            app.PredictionCircuitDropdown.ItemsData = ids;
            selId = char(app.State.selectedCircuitId);
            match = find(strcmp(ids, selId), 1);
            if ~isempty(match)
                app.PredictionCircuitDropdown.Value = ids{match};
            else
                app.PredictionCircuitDropdown.Value = ids{1};
                app.State.selectedCircuitId   = string(ids{1});
                app.State.selectedCircuitName = string(names{1});
            end
            app.logEvent('LOAD', sprintf('Loaded %d circuits into Prediction dropdown', n));
        end

        function onBackendsLoaded(~, app, data)
            if isempty(app.PredictionBackendDropdown) ...
                    || ~isvalid(app.PredictionBackendDropdown); return; end
            items = JsonHelper.extractList(data, 'backends');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0
                app.PredictionBackendDropdown.Items     = {'(no backends)'};
                app.PredictionBackendDropdown.ItemsData = {''};
                app.PredictionBackendDropdown.Value     = '';
                return;
            end
            names = cell(1, n);
            for i = 1:n
                names{i} = char(JsonHelper.pick(items(i), {'name','backend_name'}));
            end
            app.PredictionBackendDropdown.Items     = names;
            app.PredictionBackendDropdown.ItemsData = names;
            sel = char(app.State.selectedBackend);
            match = find(strcmp(names, sel), 1);
            if ~isempty(match)
                app.PredictionBackendDropdown.Value = names{match};
            else
                app.PredictionBackendDropdown.Value = names{1};
                app.State.selectedBackend = string(names{1});
            end
            app.logEvent('LOAD', sprintf('Loaded %d backends into Prediction dropdown', n));
        end

        function onDropdownLoadError(~, app, which, ME)
            Logger.warn('PredictionViewModel', ...
                'Failed to load %s: %s', which, ME.message);
            if strcmp(which, 'circuits') ...
                    && ~isempty(app.PredictionCircuitDropdown) ...
                    && isvalid(app.PredictionCircuitDropdown)
                app.PredictionCircuitDropdown.Items     = {'(load failed)'};
                app.PredictionCircuitDropdown.ItemsData = {''};
                app.PredictionCircuitDropdown.Value     = '';
            elseif strcmp(which, 'backends') ...
                    && ~isempty(app.PredictionBackendDropdown) ...
                    && isvalid(app.PredictionBackendDropdown)
                app.PredictionBackendDropdown.Items     = {'(load failed)'};
                app.PredictionBackendDropdown.ItemsData = {''};
                app.PredictionBackendDropdown.Value     = '';
            end
        end
    end

    methods (Static, Access = private)
        function data = fetchBackendList(backendSvc, circSvc, cid, token)
            % 3-tier fallback: circuit-scoped list → first circuit → unscoped.
            if ~isempty(cid) && strlength(string(cid)) > 0
                try
                    data = backendSvc.listBackends(token, cid);
                    if isstruct(data) && isfield(data, 'backends') ...
                            && ~isempty(data.backends)
                        return;
                    end
                catch
                end
            end
            try
                circList = circSvc.listCircuits(token);
                items = JsonHelper.extractList(circList, 'circuits');
                if ~isempty(items)
                    fallbackCid = char(JsonHelper.pick(items(1), {'circuit_id','id'}));
                    if ~isempty(fallbackCid)
                        data = backendSvc.listBackends(token, fallbackCid);
                        if isstruct(data) && isfield(data, 'backends') ...
                                && ~isempty(data.backends)
                            return;
                        end
                    end
                end
            catch
            end
            data = backendSvc.listBackends(token, '');
        end

        function explain503(app, cfg, cid, backend)
            broken = logical(JsonHelper.safeField(cfg, 'runtime_broken', false));
            reason = char(JsonHelper.safeField(cfg, 'runtime_broken_reason', ''));
            hasToken = logical(JsonHelper.safeField(cfg, 'has_token', false));
            % Refresh session cache so subsequent actions see the real state.
            backends = JsonHelper.safeField(cfg, 'backends', {});
            if ischar(backends); backends = {backends}; end
            if ~iscell(backends); backends = num2cell(string(backends)); end
            app.ServerIbmConfig = struct( ...
                'channel',  string(JsonHelper.safeField(cfg, 'channel', '')), ...
                'instance', string(JsonHelper.safeField(cfg, 'instance', '')), ...
                'backends', {backends}, ...
                'has_token', hasToken, ...
                'runtime_broken', broken, ...
                'runtime_broken_reason', string(reason));
            if broken
                uialert(app.UIFigure, ...
                    sprintf(['IBM runtime is currently unavailable on the server.\n\n' ...
                            'Backend: %s\nReason: %s\n\nFix the IBM credentials in the server ' ...
                            '.env and restart the API, then try again.'], backend, reason), ...
                    'Submit to IBM', 'Icon', 'error');
            elseif ~hasToken
                uialert(app.UIFigure, ...
                    'The server has no IBM_QUANTUM_TOKEN configured. Ask the operator to set it in .env and restart.', ...
                    'Submit to IBM', 'Icon', 'error');
            else
                uialert(app.UIFigure, ...
                    sprintf('Server returned 503 for circuit %s / backend %s but reports IBM runtime as healthy. Try again in a moment.', cid, backend), ...
                    'Submit to IBM', 'Icon', 'warning');
            end
        end
    end

    methods (Access = private)
        function applyPredictionData(obj, data)
            app = obj.App;
            try
                data = JsonHelper.decodeIfJson(data);

                % ── Pull the top backend's prediction entry ─────────────
                topBackend = char(JsonHelper.pick(data, {'top_backend'}));
                predList   = JsonHelper.extractList(data, 'backend_predictions');
                topEntry   = PredictionViewModel.findTopBackendEntry(predList, topBackend);

                % ── Extract scalar metrics (with fallback chains) ───────
                fid   = PredictionViewModel.pickNumber(data, topEntry, ...
                    {'predicted_fidelity','fidelity'});
                prob  = PredictionViewModel.pickNumber(data, topEntry, ...
                    {'expected_success_probability','success_probability','prob_success'});
                conf  = PredictionViewModel.pickNumber(data, topEntry, ...
                    {'confidence'});
                ci    = PredictionViewModel.pickArray(topEntry, {'confidence_interval'});
                queue = char(JsonHelper.pick(data, ...
                    {'expected_queue_time_range','queue_time','expected_queue_time'}));
                rtMs  = PredictionViewModel.pickNumber(data, topEntry, ...
                    {'estimated_runtime_ms'});
                rtSec = PredictionViewModel.pickNumber(data, topEntry, ...
                    {'runtime_seconds','runtime','estimated_runtime'});
                cost  = PredictionViewModel.pickNumber(data, topEntry, ...
                    {'estimated_cost'});
                risk  = PredictionViewModel.pickNumber(data, topEntry, ...
                    {'risk_score'});
                predId = char(JsonHelper.pick(data, {'prediction_id','id'}));

                % ── Summary table ───────────────────────────────────────
                rows = { ...
                    'Top backend',                   PredictionViewModel.fmtStr(topBackend); ...
                    'Predicted fidelity',            PredictionViewModel.fmtPct(fid); ...
                    'Expected success probability',  PredictionViewModel.fmtPct(prob); ...
                    'Confidence',                    PredictionViewModel.fmtPct(conf); ...
                    'Confidence interval',           PredictionViewModel.fmtInterval(ci); ...
                    'Expected queue time',           PredictionViewModel.fmtStr(queue); ...
                    'Estimated runtime',             PredictionViewModel.fmtRuntime(rtMs, rtSec); ...
                    'Estimated cost',                PredictionViewModel.fmtCost(cost); ...
                    'Risk score',                    PredictionViewModel.fmtNum(risk, 2); ...
                    'Prediction ID',                 PredictionViewModel.fmtStr(predId)};
                app.PredictionTable.Data = rows;

                % ── Headline callout ────────────────────────────────────
                app.PredictionHeadlineLabel.Text = ...
                    PredictionViewModel.buildHeadline(topBackend, fid, prob, queue);

                % ── Probability distribution chart ──────────────────────
                distMap = JsonHelper.safeField(data, 'probability_distribution', struct());
                obj.renderDistributionChart(distMap);

                % ── Error budget chart ──────────────────────────────────
                budgetMap = JsonHelper.safeField(data, 'error_budget_breakdown', ...
                    JsonHelper.safeField(data, 'error_budget', struct()));
                obj.renderBudgetChart(budgetMap);

            catch ME
                Logger.warn('PredictionViewModel', 'applyPredictionData failed: %s', ME.message);
                app.PredictionHeadlineLabel.Text = ...
                    sprintf('Prediction returned, but display failed: %s', ME.message);
            end
        end

        function renderDistributionChart(obj, distMap)
            ax = obj.App.PredictionDistAxes;
            cla(ax, 'reset');
            obj.App.styleAxes(ax);
            if ~isstruct(distMap) || isempty(fieldnames(distMap))
                PredictionViewModel.paintPlaceholder(ax, ...
                    'No distribution data in response');
                return;
            end
            fns  = fieldnames(distMap);
            vals = zeros(numel(fns), 1);
            for i = 1:numel(fns)
                v = distMap.(fns{i});
                if ~isnumeric(v); v = str2double(char(string(v))); end
                if isnan(v); v = 0; end
                vals(i) = v;
            end
            % Top 8 states by probability
            [sortedVals, si] = sort(vals, 'descend');
            keep  = min(8, numel(sortedVals));
            names = fns(si(1:keep));
            probs = sortedVals(1:keep);

            % Unmangle MATLAB-mangled field names — when the backend sends
            % a key like "0000" JSON decode maps it to something like
            % x0000 after makeValidName. Strip the leading x_? or x if
            % followed by digits.
            displayNames = cellfun(@PredictionViewModel.unmangleStateLabel, ...
                names, 'UniformOutput', false);
            % Wide circuits (QMC is 156 qubits) produce bitstrings that
            % are 100+ characters long; a 30° tick rotation spills the
            % text off the axes and the bars disappear behind them.
            % Collapse runs (e.g. "0000…0000") and truncate to something
            % readable.
            displayNames = cellfun(@PredictionViewModel.shortenBitstring, ...
                displayNames, 'UniformOutput', false);

            hold(ax, 'on');
            barColor = [0.22 0.48 0.78];
            topColor = [0.12 0.40 0.68];
            for i = 1:keep
                clr = barColor;
                if i == 1; clr = topColor; end
                bar(ax, i, probs(i), 'FaceColor', clr, ...
                    'EdgeColor', 'none', 'BarWidth', 0.7);
                text(ax, i, probs(i), sprintf(' %.1f%%', probs(i)*100), ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'bottom', ...
                    'FontSize', 9, 'Color', [0.22 0.27 0.35], ...
                    'Interpreter', 'none');
            end
            hold(ax, 'off');
            ax.XTick = 1:keep;
            ax.XTickLabel = displayNames;
            ax.TickLabelInterpreter = 'none';
            ax.XTickLabelRotation = 45;
            ax.FontSize = 9;
            ax.XLim = [0.4, keep + 0.6];
            ax.YLim = [0, max(probs) * 1.22];
            ax.YTick = 0:0.2:1;
            ax.YTickLabel = arrayfun(@(v) sprintf('%.0f%%', v*100), ...
                ax.YTick, 'UniformOutput', false);
            title(ax, sprintf('Top %d measurement outcomes', keep));
            xlabel(ax, 'Bitstring');
            ylabel(ax, 'Probability');
            ax.Box = 'on';
        end

        function renderBudgetChart(obj, budgetMap)
            ax = obj.App.PredictionBudgetAxes;
            cla(ax, 'reset');
            obj.App.styleAxes(ax);
            if ~isstruct(budgetMap) || isempty(fieldnames(budgetMap))
                PredictionViewModel.paintPlaceholder(ax, ...
                    'No error budget in response');
                return;
            end
            fns  = fieldnames(budgetMap);
            vals = zeros(numel(fns), 1);
            for i = 1:numel(fns)
                v = budgetMap.(fns{i});
                if ~isnumeric(v); v = str2double(char(string(v))); end
                if isnan(v); v = 0; end
                vals(i) = v;
            end
            % Sort descending so largest contributor sits at the top
            [sortedVals, si] = sort(vals, 'descend');
            names = fns(si);
            n = numel(names);

            % Palette keyed to canonical error sources
            palette = containers.Map( ...
                {'gate','readout','decoherence','crosstalk','other'}, ...
                {[0.85 0.33 0.10], [0.47 0.67 0.19], [0.49 0.18 0.56], ...
                 [0.93 0.69 0.13], [0.50 0.50 0.55]});

            total = sum(sortedVals);
            if total <= 0; total = 1; end

            hold(ax, 'on');
            for i = 1:n
                key = lower(strtrim(char(names{i})));
                if palette.isKey(key)
                    clr = palette(key);
                else
                    clr = palette('other');
                end
                barh(ax, n - i + 1, sortedVals(i), ...
                    'FaceColor', clr, 'EdgeColor', 'none', 'BarWidth', 0.62);
                pctOfTotal = sortedVals(i) / total * 100;
                text(ax, sortedVals(i), n - i + 1, ...
                    sprintf('  %.1f%%  (%.0f%% of total)', ...
                            sortedVals(i)*100, pctOfTotal), ...
                    'FontSize', 10, 'VerticalAlignment', 'middle', ...
                    'Color', [0.22 0.27 0.35], 'Interpreter', 'none');
            end
            hold(ax, 'off');

            ax.YTick = 1:n;
            ax.YTickLabel = flipud(names);
            ax.TickLabelInterpreter = 'none';
            ax.YLim = [0.3, n + 0.7];
            ax.XLim = [0, max(sortedVals) * 1.6];
            ax.XTickLabel = arrayfun(@(v) sprintf('%.0f%%', v*100), ...
                ax.XTick, 'UniformOutput', false);
            title(ax, 'Error budget breakdown');
            xlabel(ax, 'Contribution to total error');
            ax.Box = 'on';
        end
    end

    methods (Static, Access = private)

        function paintPlaceholder(ax, msg)
            text(ax, 0.5, 0.5, msg, 'Units', 'normalized', ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'Color', [0.55 0.60 0.68], 'FontSize', 11, 'Interpreter', 'none');
        end

        function entry = findTopBackendEntry(predList, topBackendName)
            % Scan backend_predictions for the entry matching top_backend.
            % Falls back to rank==1, then the first entry.
            entry = struct();
            if isempty(predList) || numel(predList) == 0; return; end
            n = numel(predList);
            if ~isempty(topBackendName)
                for i = 1:n
                    nm = char(JsonHelper.pick(predList(i), {'backend_name','name'}));
                    if strcmpi(nm, topBackendName); entry = predList(i); return; end
                end
            end
            for i = 1:n
                rk = str2double(char(string(JsonHelper.pick(predList(i), {'rank'}))));
                if ~isnan(rk) && rk == 1; entry = predList(i); return; end
            end
            entry = predList(1);
        end

        function v = pickNumber(top, nested, paths)
            % Try the top-level object first, then the nested entry.
            raw = JsonHelper.pick(top, paths);
            if strlength(strtrim(string(raw))) == 0
                raw = JsonHelper.pick(nested, paths);
            end
            v = JsonHelper.toDouble(raw);
            if v == 0 && strlength(strtrim(string(raw))) == 0
                v = NaN;
            end
        end

        function arr = pickArray(obj, paths)
            % Return a numeric row vector or [] if the field is absent.
            arr = [];
            if ~isstruct(obj); return; end
            for k = 1:numel(paths)
                fn = paths{k};
                if isfield(obj, fn)
                    raw = obj.(fn);
                    if isnumeric(raw) && numel(raw) >= 1
                        arr = double(raw(:)');
                        return;
                    elseif iscell(raw)
                        arr = cellfun(@(x) JsonHelper.toDouble(x), raw);
                        arr = arr(:)';
                        return;
                    end
                end
            end
        end

        function s = fmtStr(val)
            v = strtrim(char(string(val)));
            if isempty(v); s = '—'; else; s = v; end
        end

        function s = fmtPct(val)
            if isempty(val) || (isnumeric(val) && (isnan(val) || val <= 0))
                s = '—';
            else
                s = sprintf('%.1f%%', double(val) * 100);
            end
        end

        function s = fmtNum(val, nDecimals)
            if isempty(val) || (isnumeric(val) && isnan(val))
                s = '—';
            else
                s = sprintf(['%.' num2str(nDecimals) 'f'], double(val));
            end
        end

        function s = fmtCost(val)
            if isempty(val) || (isnumeric(val) && (isnan(val) || val < 0))
                s = '—';
            else
                s = sprintf('$%.2f', double(val));
            end
        end

        function s = fmtInterval(arr)
            if numel(arr) < 2
                s = '—';
            else
                s = sprintf('[%.3f, %.3f]', arr(1), arr(2));
            end
        end

        function s = fmtRuntime(rtMs, rtSec)
            % Prefer ms if present; fall back to seconds.
            if ~isempty(rtMs) && ~isnan(rtMs) && rtMs > 0
                secs = rtMs / 1000;
            elseif ~isempty(rtSec) && ~isnan(rtSec) && rtSec > 0
                secs = rtSec;
            else
                s = '—'; return;
            end
            if secs < 60
                s = sprintf('%.1f s', secs);
            elseif secs < 3600
                s = sprintf('%.1f min', secs / 60);
            else
                s = sprintf('%.1f h', secs / 3600);
            end
        end

        function text = buildHeadline(topBackend, fid, prob, queue)
            if isempty(topBackend)
                text = 'Prediction complete. See the summary below.';
                return;
            end
            parts = {sprintf('Recommended backend: %s', topBackend)};
            if ~isempty(fid) && isnumeric(fid) && ~isnan(fid) && fid > 0
                parts{end+1} = sprintf('predicted fidelity %.1f%%', fid*100);
            end
            if ~isempty(prob) && isnumeric(prob) && ~isnan(prob) && prob > 0
                parts{end+1} = sprintf('success probability %.1f%%', prob*100);
            end
            if ~isempty(queue) && ischar(queue) && ~strcmp(queue, '')
                parts{end+1} = sprintf('queue %s', queue);
            end
            text = strjoin(parts, '   ·   ');
        end

        function s = unmangleStateLabel(name)
            % JSON → MATLAB struct field names are run through
            % matlab.lang.makeValidName which prefixes leading-digit
            % keys like "0000" with "x" (→ "x0000"). Undo that so the
            % chart shows the original bitstring.
            c = char(name);
            if numel(c) >= 2 && c(1) == 'x' && all(c(2:end) >= '0' & c(2:end) <= '1')
                s = c(2:end);
            elseif numel(c) >= 3 && startsWith(c, 'x_') && all(c(3:end) >= '0' & c(3:end) <= '1')
                s = c(3:end);
            else
                s = c;
            end
        end

        function s = shortenBitstring(label)
            % Keep short bitstrings as-is. For long ones (>14 chars),
            % collapse long runs of identical bits and ellipsise the
            % middle so a 156-bit string like "00000…00000" becomes
            % something readable like "0000…(152)…0000".
            c = char(label);
            n = numel(c);
            if n <= 14
                s = c;
                return;
            end
            % If the bitstring is all 0s / all 1s, describe it compactly.
            if all(c == c(1))
                s = sprintf('%c×%d', c(1), n);
                return;
            end
            % Otherwise keep the first 6 and last 6 bits, note length.
            s = sprintf('%s…(%d)…%s', c(1:6), n - 12, c(end-5:end));
        end

    end
end
