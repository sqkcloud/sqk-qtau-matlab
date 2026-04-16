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

        % ── Refresh All ──────────────────────────────────────────────────
        function onRefreshAll(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_login_required', 'Please login first.'), 'Auth Required');
                return;
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
            if isempty(data); return; end
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
        function applyVolumetric(~, app, data)
            if isempty(data); return; end
            try
                points = JsonHelper.pick(data, 'data_points', {});
                ax = app.VolumetricAxes;
                cla(ax);
                if isempty(points)
                    text(ax, 0.5, 0.5, 'No data yet', ...
                        'HorizontalAlignment', 'center', 'FontSize', 14, ...
                        'Units', 'normalized');
                    return;
                end
                widths = cellfun(@(p) JsonHelper.pick(p, 'width', 1), points);
                depths = cellfun(@(p) JsonHelper.pick(p, 'depth', 1), points);
                fids   = cellfun(@(p) JsonHelper.pick(p, 'fidelity', 0), points);
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
            if isempty(data); return; end
            try
                cap = JsonHelper.pick(JsonHelper.pick(data, 'capacity', struct()), 'score', 5);
                scl = JsonHelper.pick(JsonHelper.pick(data, 'scalability', struct()), 'score', 5);
                acc = JsonHelper.pick(JsonHelper.pick(data, 'accuracy', struct()), 'score', 5);
                rtm = JsonHelper.pick(JsonHelper.pick(data, 'runtime', struct()), 'score', 5);
                ax = app.ScorecardAxes;
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
        function applyCalibration(~, app, data)
            if isempty(data); return; end
            try
                points = JsonHelper.pick(data, 'data_points', {});
                mae  = JsonHelper.pick(data, 'mean_absolute_error', 0);
                corr = JsonHelper.pick(data, 'correlation', 0);
                ax = app.CalibrationAxes;
                cla(ax);
                if isempty(points)
                    text(ax, 0.5, 0.5, 'No calibration data', ...
                        'HorizontalAlignment', 'center', 'FontSize', 14, ...
                        'Units', 'normalized');
                    return;
                end
                preds   = cellfun(@(p) JsonHelper.pick(p, 'predicted_fidelity', 0), points);
                actuals = cellfun(@(p) JsonHelper.pick(p, 'actual_fidelity', 0), points);
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
        function applyRegression(~, app, backendName, data)
            if isempty(data); return; end
            try
                points = JsonHelper.pick(data, 'data_points', {});
                ax = app.RegressionAxes;
                cla(ax);
                if isempty(points)
                    text(ax, 0.5, 0.5, 'No regression data', ...
                        'HorizontalAlignment', 'center', 'FontSize', 14, ...
                        'Units', 'normalized');
                    return;
                end
                fids = cellfun(@(p) JsonHelper.pick(p, 'fidelity', 0), points);
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
