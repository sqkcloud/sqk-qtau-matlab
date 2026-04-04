classdef BenchmarkDashboardViewModel < handle
    % BenchmarkDashboardViewModel  Callbacks for the Benchmark Dashboard tab.
    %
    %   Fetches volumetric data, system metrics, scorecard, prediction
    %   calibration, and benchmark regression from the API and renders
    %   the corresponding charts on the dashboard.

    properties
        App  % Reference to QTAUWorkbenchApp
    end

    methods
        function obj = BenchmarkDashboardViewModel(app)
            obj.App = app;
        end

        % ── Refresh All ──────────────────────────────────────────────────
        function onRefreshAll(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, 'Please login first.', 'Auth Required');
                return;
            end
            app.showLoading();
            try
                obj.refreshSystemMetrics();
                obj.refreshVolumetric();
                obj.refreshScorecard();
                obj.refreshCalibration();
                obj.refreshRegression();
                app.logEvent('BENCH', 'All benchmark data refreshed');
            catch ex
                app.logEvent('ERROR', ['Benchmark refresh failed: ' ex.message]);
                app.showError('Benchmark Refresh', ex);
            end
            app.hideLoading();
        end

        % ── Export Data (placeholder) ────────────────────────────────────
        function onExportData(obj)
            app = obj.App;
            app.logEvent('BENCH', 'Export benchmark data requested');
            uialert(app.UIFigure, ...
                'Benchmark data export will be available in a future release.', ...
                'Export');
        end

        % ── System Metrics ───────────────────────────────────────────────
        function refreshSystemMetrics(obj)
            app = obj.App;
            backendName = app.BenchmarkBackendDropdown.Value;
            if isempty(backendName) || strcmp(backendName, '')
                backendName = app.State.selectedBackend;
            end
            if isempty(char(backendName))
                return;
            end
            try
                svc = BenchmarkService(app.Client);
                data = svc.getSystemMetrics(backendName, app.State.bearerHeader());
                qv = JsonHelper.pick(data, 'quantum_volume', '--');
                clops = JsonHelper.pick(data, 'clops', '--');
                lf = JsonHelper.pick(data, 'layer_fidelity', '--');
                eplg = JsonHelper.pick(data, 'eplg', '--');

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
                app.logEvent('BENCH', ['System metrics loaded for ' char(backendName)]);
            catch ex
                app.logEvent('WARN', ['System metrics failed: ' ex.message]);
            end
        end

        % ── Volumetric Heatmap ───────────────────────────────────────────
        function refreshVolumetric(obj)
            app = obj.App;
            if ~app.State.hasProject(); return; end
            try
                svc = BenchmarkService(app.Client);
                data = svc.getVolumetricData(app.State.currentProjectId, ...
                    app.State.bearerHeader());
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
                caxis(ax, [0 1]);  %#ok<CAXIS>
                title(ax, 'Volumetric Fidelity Map');
                xlabel(ax, 'Circuit Depth');
                ylabel(ax, 'Circuit Width');
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Volumetric refresh failed: ' ex.message]);
            end
        end

        % ── Backend Scorecard (Radar Chart) ──────────────────────────────
        function refreshScorecard(obj)
            app = obj.App;
            backendName = app.BenchmarkBackendDropdown.Value;
            if isempty(char(backendName)); backendName = app.State.selectedBackend; end
            if isempty(char(backendName)) || ~app.State.hasProject(); return; end
            try
                svc = BenchmarkService(app.Client);
                data = svc.getBackendScorecard(app.State.currentProjectId, ...
                    backendName, app.State.bearerHeader());

                cap  = JsonHelper.pick(JsonHelper.pick(data, 'capacity', struct()), 'score', 5);
                scl  = JsonHelper.pick(JsonHelper.pick(data, 'scalability', struct()), 'score', 5);
                acc  = JsonHelper.pick(JsonHelper.pick(data, 'accuracy', struct()), 'score', 5);
                rtm  = JsonHelper.pick(JsonHelper.pick(data, 'runtime', struct()), 'score', 5);

                ax = app.ScorecardAxes;
                cla(ax);
                angles = linspace(0, 2*pi, 5);
                values = [cap scl acc rtm cap];
                polarplot(ax, angles, values, '-o', 'LineWidth', 2, ...
                    'Color', [0.18 0.45 0.82], 'MarkerFaceColor', [0.18 0.45 0.82]);
                ax.ThetaTick = [0 90 180 270];
                ax.ThetaTickLabel = {'Capacity','Scalability','Accuracy','Runtime'};
                ax.RLim = [0 10];
                title(ax, ['Scorecard: ' char(backendName)]);
            catch ex
                app.logEvent('WARN', ['Scorecard refresh failed: ' ex.message]);
            end
        end

        % ── Prediction Calibration (Scatter) ─────────────────────────────
        function refreshCalibration(obj)
            app = obj.App;
            if ~app.State.hasProject(); return; end
            try
                svc = BenchmarkService(app.Client);
                data = svc.getPredictionCalibration(app.State.currentProjectId, ...
                    app.State.bearerHeader());
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

                scatter(ax, preds, actuals, 36, [0.18 0.45 0.82], 'filled');
                hold(ax, 'on');
                plot(ax, [0 1], [0 1], '--', 'Color', [0.62 0.38 0.82], 'LineWidth', 1.2);
                hold(ax, 'off');
                title(ax, sprintf('Pred vs Actual (MAE=%.3f, r=%.2f)', mae, corr));
                xlabel(ax, 'Predicted Fidelity');
                ylabel(ax, 'Actual Fidelity');
                xlim(ax, [0 1]); ylim(ax, [0 1]);
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Calibration refresh failed: ' ex.message]);
            end
        end

        % ── Benchmark Regression (Time Series) ──────────────────────────
        function refreshRegression(obj)
            app = obj.App;
            backendName = app.BenchmarkBackendDropdown.Value;
            if isempty(char(backendName)); backendName = app.State.selectedBackend; end
            if isempty(char(backendName)) || ~app.State.hasProject(); return; end
            try
                svc = BenchmarkService(app.Client);
                data = svc.getBenchmarkRegression(app.State.currentProjectId, ...
                    backendName, app.State.bearerHeader());
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
                    'Color', [0.18 0.45 0.82], 'LineWidth', 1.4, 'MarkerSize', 4);
                title(ax, ['Fidelity Trend: ' char(backendName)]);
                xlabel(ax, 'Job Index');
                ylabel(ax, 'Fidelity');
                ylim(ax, [0 1]);
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Regression refresh failed: ' ex.message]);
            end
        end
    end
end
