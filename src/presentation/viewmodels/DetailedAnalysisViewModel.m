classdef DetailedAnalysisViewModel < handle
    % DetailedAnalysisViewModel  Callback handlers for the Detailed Analysis screen.
    %
    %   Public methods (wired to toolbar buttons):
    %     onPlotComparison  — bar chart: measured vs ideal state distribution
    %     onPlotHeatmap     — imagesc: cross-qubit error rate matrix
    %     onPlotTemporal    — line + band: confidence per shot batch
    %     onPlotQubit       — scatter: T1 vs T2 coloured by readout fidelity
    %     onPlotRBDecay     — errorbar + fit: randomized benchmarking decay
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
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            try
                data = app.JobSvc.getDetailedResults(app.State.selectedJobId, app.State.authToken);
                obj.plotComparisonFromData(data);
                app.logEvent('API', 'Comparison plot updated from live data');
                app.State.logActivity('Detailed analysis — comparison plot', 'Success');
                app.hideLoading();
            catch ME
                app.hideLoading();
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
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            try
                data = app.JobSvc.getErrorTrends(app.State.selectedJobId, app.State.authToken);
                cla(app.TemporalAxes);
                items = JsonHelper.extractList(data, 'trend');
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n > 0
                    conf = zeros(1, n);
                    sig  = zeros(1, n);
                    for i = 1:n
                        conf(i) = JsonHelper.toDouble(JsonHelper.pick(items(i), {'confidence','value','fidelity'}));
                        sig(i)  = JsonHelper.toDouble(JsonHelper.pick(items(i), {'std','uncertainty','sigma'}));
                    end
                    if all(sig == 0); sig = 0.012 * ones(1,n); end
                    t2  = 1:n;
                    GRN = Theme.COLOR_SUCCESS;
                    fill(app.TemporalAxes, [t2 fliplr(t2)], [conf+sig fliplr(conf-sig)], ...
                        GRN, 'FaceAlpha', 0.14, 'EdgeColor', 'none');
                    hold(app.TemporalAxes, 'on');
                    plot(app.TemporalAxes, t2, conf, '-',  'Color', GRN, 'LineWidth', 1.7);
                    plot(app.TemporalAxes, t2, conf, 'o',  'Color', GRN, ...
                        'MarkerSize', 3.5, 'MarkerFaceColor', GRN);
                    confThresh = AppConfig.getDouble('confidence_threshold', 0.94);
                    yline(app.TemporalAxes, confThresh, '--', 'Color', Theme.COLOR_PURPLE, ...
                        'LineWidth', 1.2, 'Label', 'Threshold', 'LabelHorizontalAlignment', 'left');
                    hold(app.TemporalAxes, 'off');
                    app.TemporalAxes.Title.String  = Labels.get('detailed_plot_temporal_title');
                    app.TemporalAxes.XLabel.String = Labels.get('detailed_plot_x_batch');
                    app.TemporalAxes.YLabel.String = 'Confidence';
                    app.TemporalAxes.YLim = [max(0.80, min(conf)-3*max(sig)), 1.01];
                    app.styleAxes(app.TemporalAxes);
                    grid(app.TemporalAxes, 'on');
                    % Drift annotation
                    driftSlope = (conf(end)-conf(1)) / max(n-1,1);
                    nOutliers  = sum(conf < confThresh);
                    obj.appendInsight(sprintf('[Temporal] slope=%.4f/batch · outliers<%0.2f = %d', ...
                        driftSlope, confThresh, nOutliers));
                    app.logEvent('API', 'Temporal plot updated from live data');
                    app.hideLoading();
                    return;
                end
                app.hideLoading();
            catch ME
                app.hideLoading();
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
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
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
                    % Live path: bar chart per qubit coloured by fidelity value
                    b = bar(app.QubitAxes, 1:n, fid, 'FaceColor','flat');
                    cmap = cool(256);
                    for i = 1:n
                        idx = max(1, round((fid(i)-0.90)/0.10 * 255) + 1);
                        b.CData(i,:) = cmap(min(256,idx),:);
                    end
                    colormap(app.QubitAxes, 'cool');
                    app.QubitAxes.CLim = [0.90 1.00];
                    app.QubitAxes.YLim = [max(0, min(fid)-0.05), 1.00];
                    app.QubitAxes.Title.String  = 'Qubit Readout Fidelity';
                    app.QubitAxes.XLabel.String = Labels.get('detailed_plot_x_qubit');
                    app.QubitAxes.YLabel.String = 'Fidelity';
                    app.styleAxes(app.QubitAxes);
                    grid(app.QubitAxes, 'on');
                    obj.appendInsight(sprintf('[Qubits]  Readout F min=%.3f  mean=%.3f  n=%d', ...
                        min(fid), mean(fid), n));
                    app.logEvent('API', 'Qubit plot updated from live data');
                    app.hideLoading();
                    return;
                end
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Qubit data failed: %s', ME.message));
            end
            obj.plotQubitDemo();
        end

        function onPlotHeatmap(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                obj.plotHeatmapDemo(); return;
            end
            app.logEvent('API', sprintf('GET /jobs/%s/results/detailed (heatmap)', app.State.selectedJobId));
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            try
                data  = app.JobSvc.getDetailedResults(app.State.selectedJobId, app.State.authToken);
                items = JsonHelper.extractList(data, 'error_matrix');
                if isempty(items); items = JsonHelper.extractList(data, 'crosstalk_matrix'); end
                n = numel(items);
                if n > 0
                    nQ = round(sqrt(n));
                    if nQ*nQ == n
                        errMat = zeros(nQ, nQ);
                        for i = 1:n
                            r = ceil(i/nQ); c = mod(i-1,nQ)+1;
                            errMat(r,c) = JsonHelper.toDouble(JsonHelper.pick(items(i), {'value','error_rate'}));
                        end
                    else
                        nQ = floor(sqrt(n)); errMat = zeros(nQ,nQ);
                    end
                    cla(app.ErrorHeatmapAxes);
                    imagesc(app.ErrorHeatmapAxes, errMat);
                    colormap(app.ErrorHeatmapAxes, 'hot');
                    colorbar(app.ErrorHeatmapAxes);
                    app.ErrorHeatmapAxes.CLim = [0 max(0.01, max(errMat(:)))];
                    app.ErrorHeatmapAxes.Title.String  = Labels.get('detailed_plot_heatmap_title');
                    app.ErrorHeatmapAxes.XLabel.String = 'Qubit index';
                    app.ErrorHeatmapAxes.YLabel.String = 'Qubit index';
                    app.styleAxes(app.ErrorHeatmapAxes);
                    maxErr = max(errMat(:)); meanErr = mean(errMat(errMat>0));
                    obj.appendInsight(sprintf('[Heatmap] Max error = %.3f%%  mean = %.3f%%', ...
                        maxErr*100, meanErr*100));
                    app.logEvent('API', 'Error heatmap updated from live data');
                    app.hideLoading(); return;
                end
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Error matrix failed: %s', ME.message));
            end
            obj.plotHeatmapDemo();
        end

        function onPlotRBDecay(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                obj.plotRBDecayDemo(); return;
            end
            app.logEvent('API', sprintf('GET /jobs/%s/rb-decay', app.State.selectedJobId));
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            try
                data  = app.JobSvc.getRBDecay(app.State.selectedJobId, app.State.authToken);
                items = JsonHelper.extractList(data, 'rb_data');
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n > 0
                    mPts = zeros(1,n); pMea = zeros(1,n); pErr = zeros(1,n);
                    for i = 1:n
                        mPts(i) = JsonHelper.toDouble(JsonHelper.pick(items(i), {'sequence_length','depth','m'}));
                        pMea(i) = JsonHelper.toDouble(JsonHelper.pick(items(i), {'survival_prob','fidelity','value'}));
                        pErr(i) = JsonHelper.toDouble(JsonHelper.pick(items(i), {'error','std','uncertainty'}));
                    end
                    validMask = mPts > 0 & pMea > 0.5;
                    EPC = NaN;
                    if sum(validMask) >= 3
                        logY  = log(max(pMea(validMask) - 0.5, 1e-9));
                        X_mat = [ones(sum(validMask),1), mPts(validMask)'];
                        coeff = X_mat \ logY';
                        EPC   = max(0, (1 - exp(coeff(2))) / 2);
                    end
                    cla(app.RBDecayAxes);
                    hold(app.RBDecayAxes, 'on');
                    if ~isnan(EPC)
                        A_rb = 0.475; B_rb = 0.500; mDns = 1:max(mPts);
                        plot(app.RBDecayAxes, mDns, A_rb*(1-2*EPC).^mDns+B_rb, '--', ...
                            'Color', Theme.COLOR_PURPLE, 'LineWidth', 1.5);
                    end
                    errorbar(app.RBDecayAxes, mPts, pMea, pErr, ...
                        'o', 'Color', Theme.COLOR_PRIMARY, 'MarkerFaceColor', Theme.COLOR_PRIMARY, ...
                        'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 4);
                    hold(app.RBDecayAxes, 'off');
                    if ~isnan(EPC)
                        legend(app.RBDecayAxes,{'Fit','Data'},'Location','northeast','FontSize',9);
                        app.RBDecayAxes.Title.String = sprintf('%s  —  EPC = %.4f%%', ...
                            Labels.get('detailed_plot_rb_title'), EPC*100);
                        obj.appendInsight(sprintf('[RB Decay] EPC = %.4f%% (%d seq lengths)', EPC*100, n));
                    else
                        app.RBDecayAxes.Title.String = Labels.get('detailed_plot_rb_title');
                    end
                    app.RBDecayAxes.XLabel.String = 'Sequence length (Clifford gates)';
                    app.RBDecayAxes.YLabel.String = 'Survival probability';
                    app.styleAxes(app.RBDecayAxes);
                    grid(app.RBDecayAxes, 'on');
                    app.logEvent('API', 'RB decay updated from live data');
                    app.hideLoading(); return;
                end
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('RB decay failed: %s', ME.message));
            end
            obj.plotRBDecayDemo();
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
            catch ME
                Logger.warn('DetailedAnalysisViewModel', 'plotComparisonFromData failed: %s', ME.message);
                obj.plotComparisonDemo();
            end
        end

        function plotComparisonDemo(obj)
            app = obj.App;
            cla(app.CompareAxes);
            x  = 1:10;
            y1 = 0.73 + 0.06*randn(1,10);
            y2 = 0.78 + 0.03*randn(1,10);
            b  = bar(app.CompareAxes, x, [y1' y2'], 'grouped');
            b(1).FaceColor = [0.20 0.48 0.78]; b(1).FaceAlpha = 0.88;
            b(2).FaceColor = [0.93 0.45 0.18]; b(2).FaceAlpha = 0.88;
            hold(app.CompareAxes, 'on');
            err = 0.018 + 0.008*rand(1,10);
            errorbar(app.CompareAxes, x-0.18, y1, err, '.', ...
                'Color', [0.10 0.22 0.48], 'LineWidth', 1.1, 'CapSize', 3);
            hold(app.CompareAxes, 'off');
            legend(app.CompareAxes, {'Measured','Ideal'}, 'Location','northeast','FontSize',10);
            app.CompareAxes.Title.String  = 'Top-10 State Probabilities (demo)';
            app.CompareAxes.XLabel.String = 'Basis state index';
            app.CompareAxes.YLabel.String = 'Probability';
            app.CompareAxes.YLim = [0 1];
            app.styleAxes(app.CompareAxes);
            grid(app.CompareAxes, 'on');
        end

        function plotTemporalDemo(obj)
            app = obj.App;
            cla(app.TemporalAxes);
            t2   = 1:40;
            conf = 0.940 + 0.018*randn(1,40);
            sig  = 0.012 + 0.004*rand(1,40);
            GRN  = Theme.COLOR_SUCCESS;
            fill(app.TemporalAxes, [t2 fliplr(t2)], [conf+sig fliplr(conf-sig)], ...
                GRN, 'FaceAlpha', 0.14, 'EdgeColor', 'none');
            hold(app.TemporalAxes, 'on');
            plot(app.TemporalAxes, t2, conf, '-',  'Color', GRN, 'LineWidth', 1.7);
            plot(app.TemporalAxes, t2, conf, 'o',  'Color', GRN, ...
                'MarkerSize', 3.5, 'MarkerFaceColor', GRN);
            confThresh = AppConfig.getDouble('confidence_threshold', 0.94);
            yline(app.TemporalAxes, confThresh, '--', 'Color', Theme.COLOR_PURPLE, ...
                'LineWidth', 1.2, 'Label', 'Threshold', 'LabelHorizontalAlignment', 'left');
            hold(app.TemporalAxes, 'off');
            app.TemporalAxes.Title.String  = 'Confidence per Shot Batch (demo)';
            app.TemporalAxes.XLabel.String = 'Batch index';
            app.TemporalAxes.YLabel.String = 'Confidence';
            app.TemporalAxes.YLim = [0.88 1.01];
            app.styleAxes(app.TemporalAxes);
            grid(app.TemporalAxes, 'on');
        end

        function plotQubitDemo(obj)
            app = obj.App;
            cla(app.QubitAxes);
            nQb = 27;
            T1  = 45 + 38*rand(1,nQb);
            T2  = min(35 + 28*rand(1,nQb), 2*T1 - 3);
            fidQ = 0.955 + 0.038*rand(1,nQb);
            scatter(app.QubitAxes, T1, T2, 65, fidQ, 'filled', ...
                'MarkerEdgeColor', [0.3 0.3 0.3], 'LineWidth', 0.5);
            colormap(app.QubitAxes, 'cool');
            cb = colorbar(app.QubitAxes);
            cb.Label.String  = 'Readout fidelity';
            cb.Label.FontSize = 10;
            app.QubitAxes.CLim = [0.95 1.00];
            hold(app.QubitAxes, 'on');
            xlBound = [30 90];
            plot(app.QubitAxes, xlBound, 2*xlBound, '--', ...
                'Color', [0.85 0.33 0.10], 'LineWidth', 1.0);
            hold(app.QubitAxes, 'off');
            app.QubitAxes.Title.String  = 'T1 vs T2 per Qubit (demo)';
            app.QubitAxes.XLabel.String = 'T1 (\mus)';
            app.QubitAxes.YLabel.String = 'T2 (\mus)';
            app.styleAxes(app.QubitAxes);
            grid(app.QubitAxes, 'on');
        end

        function plotHeatmapDemo(obj)
            app = obj.App;
            cla(app.ErrorHeatmapAxes);
            nQ     = 8;
            errMat = 0.015*rand(nQ,nQ);
            errMat = (errMat + errMat') / 2;
            for i = 1:nQ; errMat(i,i) = 0; end
            errMat(2,3) = 0.042; errMat(3,2) = 0.042;
            errMat(5,6) = 0.038; errMat(6,5) = 0.038;
            imagesc(app.ErrorHeatmapAxes, errMat);
            colormap(app.ErrorHeatmapAxes, 'hot');
            cb = colorbar(app.ErrorHeatmapAxes);
            cb.Label.String = 'Error rate'; cb.Label.FontSize = 10;
            app.ErrorHeatmapAxes.CLim  = [0 0.05];
            app.ErrorHeatmapAxes.XTick = 1:nQ;
            app.ErrorHeatmapAxes.YTick = 1:nQ;
            app.ErrorHeatmapAxes.Title.String  = 'Qubit Pair Error Rates (demo)';
            app.ErrorHeatmapAxes.XLabel.String = 'Qubit index';
            app.ErrorHeatmapAxes.YLabel.String = 'Qubit index';
            app.styleAxes(app.ErrorHeatmapAxes);
        end

        function plotRBDecayDemo(obj)
            app = obj.App;
            cla(app.RBDecayAxes);
            mPts  = [1 2 4 8 16 32 64 128 256];
            EPC   = 0.0019;  A_rb = 0.475;  B_rb = 0.500;
            pFit  = A_rb*(1-2*EPC).^mPts + B_rb;
            pMea  = pFit + 0.008*randn(size(pFit));
            pErr  = 0.007 + 0.003*rand(size(pFit));
            mDns  = 1:256;
            PURP  = Theme.COLOR_PURPLE;  BLU = Theme.COLOR_PRIMARY;
            hold(app.RBDecayAxes, 'on');
            fill(app.RBDecayAxes, [mDns fliplr(mDns)], ...
                [A_rb*(1-2*(EPC+0.0003)).^mDns+B_rb, ...
                 fliplr(A_rb*(1-2*(EPC-0.0003)).^mDns+B_rb)], ...
                PURP, 'FaceAlpha', 0.12, 'EdgeColor', 'none');
            plot(app.RBDecayAxes, mDns, A_rb*(1-2*EPC).^mDns+B_rb, '-', ...
                'Color', PURP, 'LineWidth', 1.6);
            errorbar(app.RBDecayAxes, mPts, pMea, pErr, ...
                'o', 'Color', BLU, 'MarkerFaceColor', BLU, ...
                'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 4);
            hold(app.RBDecayAxes, 'off');
            legend(app.RBDecayAxes, {'Fit band','Fit','Data'}, ...
                'Location','northeast','FontSize',9);
            app.RBDecayAxes.Title.String  = sprintf('RB Decay (demo)  —  EPC = %.4f%%', EPC*100);
            app.RBDecayAxes.XLabel.String = 'Sequence length (Clifford gates)';
            app.RBDecayAxes.YLabel.String = 'Survival probability';
            app.styleAxes(app.RBDecayAxes);
            grid(app.RBDecayAxes, 'on');
        end

        function appendInsight(obj, msg)
            % Append a diagnostic line to the insight text area, preserving existing content.
            app = obj.App;
            cur = app.DetailedInsightArea.Value;
            if ischar(cur); cur = {cur}; end
            % Remove the placeholder text on first live update
            if numel(cur) >= 1 && contains(cur{1}, 'Press the Refresh')
                cur = {};
            end
            ts  = char(datetime('now', 'Format', 'HH:mm:ss'));
            cur{end+1} = sprintf('[%s] %s', ts, msg);
            app.DetailedInsightArea.Value = cur;
        end
    end
end
