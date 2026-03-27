classdef DetailedAnalysisViewModel < handle
    % DetailedAnalysisViewModel  Callback handlers for the Detailed Analysis screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = DetailedAnalysisViewModel(app)
            obj.App = app;
        end

        function onPlotComparison(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                obj.plotComparisonDemo(); return;
            end
            app.logEvent('API', sprintf('GET /jobs/%s/results/detailed', app.State.selectedJobId));
            try
                data = app.JobSvc.getDetailedResults(app.State.selectedJobId, app.State.authToken);
                obj.plotComparisonFromData(data);
                app.logEvent('API', 'Comparison plot updated from live data');
            catch ME
                app.logEvent('ERROR', sprintf('Detailed results failed: %s', ME.message));
                obj.plotComparisonDemo();
            end
        end

        function onPlotTemporal(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                obj.plotTemporalDemo(); return;
            end
            app.logEvent('API', sprintf('GET /jobs/%s/error-trends', app.State.selectedJobId));
            try
                data = app.JobSvc.getErrorTrends(app.State.selectedJobId, app.State.authToken);
                cla(app.TemporalAxes);
                items = JsonHelper.extractList(data, 'trend');
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n > 0
                    conf = zeros(1, n);
                    for i = 1:n
                        conf(i) = JsonHelper.toDouble(JsonHelper.pick(items(i), {'confidence','value','fidelity'}));
                    end
                    plot(app.TemporalAxes, 1:n, conf, '-o', 'Color', [0.10 0.54 0.36], 'LineWidth', 1.6, 'MarkerSize', 3);
                    yline(app.TemporalAxes, 0.94, '--', 'Color', [0.62 0.38 0.82], 'LineWidth', 1.2);
                    app.TemporalAxes.Title.String = 'Confidence per Shot Batch';
                    app.TemporalAxes.XLabel.String = 'Batch index';
                    app.styleAxes(app.TemporalAxes);
                    app.logEvent('API', 'Temporal plot updated from live data');
                    return;
                end
            catch ME
                app.logEvent('ERROR', sprintf('Error trends failed: %s', ME.message));
            end
            obj.plotTemporalDemo();
        end

        function onPlotQubit(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                obj.plotQubitDemo(); return;
            end
            app.logEvent('API', sprintf('GET /jobs/%s/results/detailed (qubit)', app.State.selectedJobId));
            try
                data  = app.JobSvc.getDetailedResults(app.State.selectedJobId, app.State.authToken);
                items = JsonHelper.extractList(data, 'qubit_fidelities');
                if isempty(items); items = JsonHelper.extractList(data, 'per_qubit_fidelity'); end
                n = numel(items);
                if n > 0
                    cla(app.QubitAxes);
                    fid = zeros(1, n);
                    for i = 1:n
                        fid(i) = JsonHelper.toDouble(JsonHelper.pick(items(i), {'fidelity','readout_fidelity','value'}));
                    end
                    stem(app.QubitAxes, 1:n, fid, 'filled', 'Color', [0.18 0.45 0.82], 'LineWidth', 1.4);
                    app.QubitAxes.YLim = [max(0, min(fid)-0.05), 1.00];
                    app.QubitAxes.Title.String  = 'Qubit Readout Fidelity';
                    app.QubitAxes.XLabel.String = 'Qubit index';
                    app.styleAxes(app.QubitAxes);
                    app.logEvent('API', 'Qubit plot updated from live data');
                    return;
                end
            catch ME
                app.logEvent('ERROR', sprintf('Qubit data failed: %s', ME.message));
            end
            obj.plotQubitDemo();
        end
    end

    methods (Access = private)
        function plotComparisonFromData(obj, data)
            app = obj.App;
            cla(app.CompareAxes);
            try
                meas  = JsonHelper.extractList(data, 'measured_probs');
                ideal = JsonHelper.extractList(data, 'ideal_probs');
                n     = min(10, max(numel(meas), numel(ideal)));
                if n == 0; obj.plotComparisonDemo(); return; end
                x = 1:n;
                y1 = zeros(1, n); y2 = zeros(1, n);
                for i = 1:n
                    if i <= numel(meas);  y1(i) = JsonHelper.toDouble(JsonHelper.pick(meas(i),  {'prob','value'})); end
                    if i <= numel(ideal); y2(i) = JsonHelper.toDouble(JsonHelper.pick(ideal(i), {'prob','value'})); end
                end
                bar(app.CompareAxes, x, [y1' y2'], 'grouped');
                legend(app.CompareAxes, {'Measured','Ideal'}, 'Location', 'northeast');
                app.CompareAxes.Title.String = 'Top-10 State Probabilities';
                app.styleAxes(app.CompareAxes);
            catch
                obj.plotComparisonDemo();
            end
        end

        function plotComparisonDemo(obj)
            app = obj.App;
            cla(app.CompareAxes);
            x = 1:10; y1 = 0.76+0.04*randn(1,10); y2 = 0.80+0.03*randn(1,10);
            bar(app.CompareAxes, x, [y1' y2'], 'grouped');
            legend(app.CompareAxes, {'Measured','Ideal'}, 'Location', 'northeast');
            app.CompareAxes.Title.String = 'Top-10 State Probabilities (demo)';
            app.styleAxes(app.CompareAxes);
        end

        function plotTemporalDemo(obj)
            app = obj.App;
            cla(app.TemporalAxes);
            t2 = 1:40; conf = 0.94+0.02*randn(1,40);
            plot(app.TemporalAxes, t2, conf, '-o', 'Color', [0.10 0.54 0.36], 'LineWidth', 1.6, 'MarkerSize', 3);
            yline(app.TemporalAxes, 0.94, '--', 'Color', [0.62 0.38 0.82], 'LineWidth', 1.2);
            app.TemporalAxes.Title.String  = 'Confidence per Shot Batch (demo)';
            app.TemporalAxes.XLabel.String = 'Batch index';
            app.styleAxes(app.TemporalAxes);
        end

        function plotQubitDemo(obj)
            app = obj.App;
            cla(app.QubitAxes);
            q = 1:27; fid = 0.98 - 0.02*rand(1,27);
            stem(app.QubitAxes, q, fid, 'filled', 'Color', [0.18 0.45 0.82], 'LineWidth', 1.4);
            app.QubitAxes.YLim = [0.90 1.00];
            app.QubitAxes.Title.String  = 'Qubit Readout Fidelity (demo)';
            app.QubitAxes.XLabel.String = 'Qubit index';
            app.styleAxes(app.QubitAxes);
        end
    end
end
