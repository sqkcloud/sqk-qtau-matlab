classdef BenchmarkDashboardViewModel < handle
    % BenchmarkDashboardViewModel  Callbacks for the Benchmark Dashboard tab.
    %
    %   Fetches volumetric data, system metrics, scorecard, prediction
    %   calibration, and benchmark regression from the API and renders
    %   the corresponding charts on the dashboard.

    properties
        App  % Reference to QTAUWorkbenchApp
        LastRefresh = []
    end

    methods
        function obj = BenchmarkDashboardViewModel(app)
            obj.App = app;
        end

        % ── Entry hook (called on screen activation) ─────────────────────
        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            obj.loadBackends();
            obj.onRefreshAll();
        end

        % ── Refresh All ──────────────────────────────────────────────────
        function onRefreshAll(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_login_required', 'Please login first.'), 'Auth Required');
                return;
            end

            % Ensure the backend dropdown is populated before a refresh —
            % protects the Refresh All button when the user skips onEnter.
            try
                items = app.BenchmarkBackendDropdown.Items;
                if isempty(items) || (numel(items) == 1 && strcmp(items{1}, '(none)'))
                    obj.loadBackends();
                end
            catch ME
                Logger.debug('BenchmarkDashboardViewModel', 'dropdown guard: %s', ME.message);
            end

            app.showLoading();

            % Capture parameters on UI thread before dispatching
            backendName = '';
            try backendName = char(app.BenchmarkBackendDropdown.Value); catch; end
            if isempty(backendName); backendName = char(app.State.selectedBackend); end
            pid    = '';
            if app.State.hasProject(); pid = char(app.State.currentProjectId); end
            header = app.State.bearerHeader();
            svc    = app.BenchmarkSvc;

            % Run all 5 API fetches off the UI thread in one async task
            AsyncRunner.run( ...
                @() BenchmarkDashboardViewModel.fetchAllData(svc, backendName, pid, header), ...
                @(results) obj.applyAllData(app, backendName, results), ...
                @(ME)      obj.onRefreshError(app, ME));
        end

        % ── Backend dropdown population ──────────────────────────────────
        function loadBackends(obj)
            % Populate BenchmarkBackendDropdown via BackendService with a
            % 3-tier fallback, mirroring BenchmarkViewModel.loadBackends:
            %   1. list scoped to the currently-selected circuit
            %   2. list for the first circuit in the project
            %   3. basic list without circuit filter
            app = obj.App;
            token = app.State.authToken;

            cid = '';
            if app.State.hasCircuit(); cid = char(app.State.selectedCircuitId); end
            if ~isempty(cid) && strlength(cid) > 0
                try
                    data = app.BackendSvc.listBackends(token, cid);
                    if obj.hasBackendData(data)
                        obj.populateBackendDropdown(data);
                        return;
                    end
                catch ME
                    Logger.debug('BenchmarkDashboardViewModel', 'loadBackends circuit: %s', ME.message);
                end
            end

            try
                circList = app.CircuitSvc.listCircuits(token);
                items = JsonHelper.extractList(circList, 'circuits');
                if ~isempty(items)
                    fallbackCid = char(JsonHelper.pick(items(1), {'circuit_id','id'}));
                    if ~isempty(fallbackCid) && strlength(fallbackCid) > 0
                        data = app.BackendSvc.listBackends(token, fallbackCid);
                        if obj.hasBackendData(data)
                            obj.populateBackendDropdown(data);
                            return;
                        end
                    end
                end
            catch ME
                Logger.debug('BenchmarkDashboardViewModel', 'loadBackends fallback circuit: %s', ME.message);
            end

            try
                data = app.BackendSvc.listBackends(token, '');
                if obj.hasBackendData(data)
                    obj.populateBackendDropdown(data);
                    return;
                end
            catch ME
                Logger.debug('BenchmarkDashboardViewModel', 'loadBackends basic list: %s', ME.message);
            end

            app.BenchmarkBackendDropdown.Items     = {'(no backends)'};
            app.BenchmarkBackendDropdown.ItemsData = {''};
            app.BenchmarkBackendDropdown.Value     = '';
            app.logEvent('WARN', 'No backends found for benchmark dashboard dropdown');
        end

        function tf = hasBackendData(~, data)
            tf = false;
            if isstruct(data) && isfield(data, 'backends')
                tf = ~isempty(data.backends);
            end
        end

        function populateBackendDropdown(obj, data)
            app = obj.App;
            items = JsonHelper.extractList(data, 'backends');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            names = cell(1, n);
            for i = 1:n
                names{i} = char(JsonHelper.pick(items(i), {'name','backend_name'}));
            end
            app.BenchmarkBackendDropdown.Items     = names;
            app.BenchmarkBackendDropdown.ItemsData = names;

            if strlength(app.State.selectedBackend) > 0
                match = find(strcmp(names, char(app.State.selectedBackend)), 1);
                if ~isempty(match)
                    app.BenchmarkBackendDropdown.Value = names{match};
                end
            end
            app.logEvent('LOAD', sprintf('Loaded %d backends into benchmark dashboard dropdown', n));
        end

        % ── Backend dropdown change ──────────────────────────────────────
        function onBackendChanged(obj, backendName)
            app = obj.App;
            bn = char(backendName);
            if isempty(bn); return; end
            % Persist selection so other screens (Benchmark, Backends) pick
            % up the same choice via AppState.selectedBackend.
            app.State.selectedBackend = string(bn);
            app.logEvent('BENCH', sprintf('Backend changed → %s', bn));
            obj.onRefreshAll();
        end

        % ── Export Data (placeholder) ────────────────────────────────────
        function onExportData(obj)
            app = obj.App;
            app.logEvent('BENCH', 'Export benchmark data requested');
            uialert(app.UIFigure, ...
                'Benchmark data export will be available in a future release.', ...
                'Export');
        end
    end

    methods (Access = private)

        % ── Apply fetched data to UI (runs on main thread) ──────────────

        function applyAllData(obj, app, backendName, R)
            try
                obj.applySystemMetrics(app, backendName, R.metrics);
                obj.applyVolumetric(app, R.volumetric);
                obj.applyScorecard(app, backendName, R.scorecard);
                obj.applyCalibration(app, R.calibration);
                obj.applyRegression(app, backendName, R.regression);
                app.logEvent('BENCH', 'All benchmark data refreshed');
                app.State.logActivity('Refresh benchmark dashboard', 'Success');
                obj.LastRefresh = tic;
            catch ex
                app.logEvent('ERROR', ['Benchmark apply failed: ' ex.message]);
            end
            app.hideLoading();
        end

        function onRefreshError(~, app, ME)
            app.logEvent('ERROR', ['Benchmark refresh failed: ' ME.message]);
            app.showError('Benchmark Refresh', ME);
            app.hideLoading();
        end

        % ── System Metrics ───────────────────────────────────────────────
        function applySystemMetrics(~, app, backendName, data)
            if isempty(data)
                % Reset KPI cards when no backend selected so stale values
                % from a previous backend don't linger.
                if ~isempty(app.BenchmarkKpiLabels)
                    for k = 1:numel(app.BenchmarkKpiLabels)
                        app.BenchmarkKpiLabels{k}.Text = '--';
                    end
                end
                return;
            end
            try
                qv    = JsonHelper.pick(data, 'quantum_volume', '--');
                clops = JsonHelper.pick(data, 'clops', '--');
                lf    = JsonHelper.pick(data, 'layer_fidelity', '--');
                eplg  = JsonHelper.pick(data, 'eplg', '--');

                overall = '--';
                if isnumeric(lf) && isnumeric(eplg)
                    overall = sprintf('%.2f', (1 - eplg) * 10);
                end

                if ~isempty(app.BenchmarkKpiLabels)
                    app.BenchmarkKpiLabels{1}.Text = string(qv);
                    app.BenchmarkKpiLabels{2}.Text = string(clops);
                    if isnumeric(lf)
                        app.BenchmarkKpiLabels{3}.Text = sprintf('%.4f', lf);
                    else
                        app.BenchmarkKpiLabels{3}.Text = string(lf);
                    end
                    if isnumeric(eplg)
                        app.BenchmarkKpiLabels{4}.Text = sprintf('%.6f', eplg);
                    else
                        app.BenchmarkKpiLabels{4}.Text = string(eplg);
                    end
                    app.BenchmarkKpiLabels{5}.Text = string(overall);
                end
                app.logEvent('BENCH', ['System metrics loaded for ' backendName]);
            catch ex
                app.logEvent('WARN', ['System metrics apply failed: ' ex.message]);
            end
        end

        % ── Volumetric Heatmap ───────────────────────────────────────────
        function applyVolumetric(obj, app, data)
            if isempty(data); return; end
            try
                points = JsonHelper.pick(data, 'data_points', {});
                ax = app.VolumetricAxes;
                cla(ax);
                if obj.isEmptyList(points)
                    obj.showEmptyAxesMessage(ax, ...
                        'No volumetric data for this project yet.', ...
                        'Submit and complete benchmark jobs to populate this map.');
                    return;
                end
                [widths, depths, fids] = obj.extractFields(points, ...
                    {'width','depth','fidelity'}, [1 1 0]);
                scatter(ax, depths, widths, 50, fids, 'filled');
                colormap(ax, parula);
                colorbar(ax);
                clim(ax, [0 1]);
                title(ax, 'Volumetric Fidelity Map');
                xlabel(ax, 'Circuit Depth');
                ylabel(ax, 'Circuit Width');
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Volumetric apply failed: ' ex.message]);
            end
        end

        % ── Backend Scorecard (Radar Chart) ──────────────────────────────
        function applyScorecard(~, app, backendName, data)
            ax = app.ScorecardAxes;
            if isempty(backendName) || isempty(data)
                cla(ax);
                ax.ThetaTick = [0 90 180 270];
                ax.ThetaTickLabel = {'Capacity','Scalability','Accuracy','Runtime'};
                ax.RLim = [0 10];
                title(ax, 'Backend Scorecard');
                return;
            end
            try
                cap = JsonHelper.pick(JsonHelper.pick(data, 'capacity', struct()), 'score', 5);
                scl = JsonHelper.pick(JsonHelper.pick(data, 'scalability', struct()), 'score', 5);
                acc = JsonHelper.pick(JsonHelper.pick(data, 'accuracy', struct()), 'score', 5);
                rtm = JsonHelper.pick(JsonHelper.pick(data, 'runtime', struct()), 'score', 5);
                cla(ax);
                angles = linspace(0, 2*pi, 5);
                values = [cap scl acc rtm cap];
                polarplot(ax, angles, values, '-o', 'LineWidth', 2, ...
                    'Color', Theme.COLOR_PRIMARY, 'MarkerFaceColor', Theme.COLOR_PRIMARY);
                ax.ThetaTick = [0 90 180 270];
                ax.ThetaTickLabel = {'Capacity','Scalability','Accuracy','Runtime'};
                ax.RLim = [0 10];
                title(ax, ['Scorecard: ' backendName]);
            catch ex
                app.logEvent('WARN', ['Scorecard apply failed: ' ex.message]);
            end
        end

        % ── Prediction Calibration (Scatter) ─────────────────────────────
        function applyCalibration(obj, app, data)
            if isempty(data); return; end
            try
                points = JsonHelper.pick(data, 'data_points', {});
                mae  = JsonHelper.pick(data, 'mean_absolute_error', 0);
                corr = JsonHelper.pick(data, 'correlation', 0);
                ax = app.CalibrationAxes;
                cla(ax);
                if obj.isEmptyList(points)
                    obj.showEmptyAxesMessage(ax, ...
                        'No prediction calibration data yet.', ...
                        'Run predictions and complete the corresponding jobs to populate this chart.');
                    return;
                end
                [preds, actuals] = obj.extractFields(points, ...
                    {'predicted_fidelity','actual_fidelity'}, [0 0]);
                scatter(ax, preds, actuals, 36, Theme.COLOR_PRIMARY, 'filled');
                hold(ax, 'on');
                plot(ax, [0 1], [0 1], '--', 'Color', Theme.COLOR_PURPLE, 'LineWidth', 1.2);
                hold(ax, 'off');
                title(ax, sprintf('Pred vs Actual (MAE=%.3f, r=%.2f)', mae, corr));
                xlabel(ax, 'Predicted Fidelity');
                ylabel(ax, 'Actual Fidelity');
                xlim(ax, [0 1]); ylim(ax, [0 1]);
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Calibration apply failed: ' ex.message]);
            end
        end

        % ── Benchmark Regression (Time Series) ──────────────────────────
        function applyRegression(obj, app, backendName, data)
            ax = app.RegressionAxes;
            if isempty(backendName)
                cla(ax);
                obj.showEmptyAxesMessage(ax, ...
                    'Select a backend to see fidelity regression.', '');
                title(ax, 'Fidelity over Time');
                return;
            end
            if isempty(data); return; end
            try
                points = JsonHelper.pick(data, 'data_points', {});
                cla(ax);
                if obj.isEmptyList(points)
                    obj.showEmptyAxesMessage(ax, ...
                        sprintf('No completed jobs yet on %s.', backendName), ...
                        'Submit and complete benchmark circuits on this backend.');
                    title(ax, ['Fidelity Trend: ' backendName]);
                    return;
                end
                fids = obj.extractFields(points, {'fidelity'}, 0);
                plot(ax, 1:numel(fids), fids, '-o', ...
                    'Color', Theme.COLOR_PRIMARY, 'LineWidth', 1.4, 'MarkerSize', 4);
                title(ax, ['Fidelity Trend: ' backendName]);
                xlabel(ax, 'Job Index');
                ylabel(ax, 'Fidelity');
                ylim(ax, [0 1]);
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Regression apply failed: ' ex.message]);
            end
        end

        % ── Shared helpers ───────────────────────────────────────────────
        function tf = isEmptyList(~, points)
            tf = isempty(points) || (iscell(points) && isempty(points)) ...
                || (isstruct(points) && numel(points) == 0);
        end

        function showEmptyAxesMessage(~, ax, msg, hint)
            cla(ax);
            if strlength(string(hint)) > 0
                text(ax, 0.5, 0.55, msg, ...
                    'HorizontalAlignment', 'center', 'FontSize', 13, ...
                    'FontWeight', 'bold', 'Color', Theme.COLOR_MUTED, ...
                    'Units', 'normalized');
                text(ax, 0.5, 0.42, hint, ...
                    'HorizontalAlignment', 'center', 'FontSize', 11, ...
                    'Color', Theme.COLOR_MUTED, 'Units', 'normalized');
            else
                text(ax, 0.5, 0.5, msg, ...
                    'HorizontalAlignment', 'center', 'FontSize', 13, ...
                    'FontWeight', 'bold', 'Color', Theme.COLOR_MUTED, ...
                    'Units', 'normalized');
            end
        end

        function varargout = extractFields(~, points, fields, defaults)
            % Pull a parallel numeric vector per requested field from either
            % a struct array or cell array of structs.
            n = numel(points);
            varargout = cell(1, numel(fields));
            for k = 1:numel(fields)
                out = zeros(1, n);
                for i = 1:n
                    if iscell(points); p = points{i}; else; p = points(i); end
                    v = JsonHelper.pick(p, fields{k}, defaults(k));
                    if isnumeric(v) && isscalar(v); out(i) = v;
                    else; out(i) = defaults(k); end
                end
                varargout{k} = out;
            end
        end
    end

    methods (Static, Access = private)

        % ── Data fetching (runs off UI thread) ───────────────────────────

        function results = fetchAllData(svc, backendName, pid, header)
            % fetchAllData  Run all 5 API calls and return a struct of
            %   results.  Each call is wrapped in try-catch so a single
            %   failure doesn't abort the others.
            results = struct('metrics', [], 'volumetric', [], ...
                'scorecard', [], 'calibration', [], 'regression', []);

            if ~isempty(backendName)
                try results.metrics = svc.getSystemMetrics(backendName, header);
                catch ME; Logger.debug('BenchmarkDashboardViewModel', 'fetchMetrics: %s', ME.message); end
            end
            if ~isempty(pid)
                try results.volumetric = svc.getVolumetricData(pid, header);
                catch ME; Logger.debug('BenchmarkDashboardViewModel', 'fetchVolumetric: %s', ME.message); end
            end
            if ~isempty(backendName) && ~isempty(pid)
                try results.scorecard = svc.getBackendScorecard(pid, backendName, header);
                catch ME; Logger.debug('BenchmarkDashboardViewModel', 'fetchScorecard: %s', ME.message); end
            end
            if ~isempty(pid)
                try results.calibration = svc.getPredictionCalibration(pid, header);
                catch ME; Logger.debug('BenchmarkDashboardViewModel', 'fetchCalibration: %s', ME.message); end
            end
            if ~isempty(backendName) && ~isempty(pid)
                try results.regression = svc.getBenchmarkRegression(pid, backendName, header);
                catch ME; Logger.debug('BenchmarkDashboardViewModel', 'fetchRegression: %s', ME.message); end
            end
        end
    end
end
