classdef DetailedAnalysisViewModel < handle
    % DetailedAnalysisViewModel  Callback handlers for the Detailed Analysis screen.
    %
    %   Public methods (wired to toolbar buttons):
    %     onPlotComparison  — bar chart: measured vs ideal state distribution
    %     onPlotHeatmap     — imagesc: cross-qubit error rate matrix
    %     onPlotTemporal    — line + band: confidence per shot batch
    %     onPlotQubit       — scatter: T1 vs T2 coloured by readout fidelity
    %     onPlotRBDecay     — errorbar + fit: randomized benchmarking decay
    properties
        % Set on every onEnter() via tic; read externally by
        % NavigationManager.isScreenFresh (cache-TTL gate that skips
        % redundant data fetches when the operator re-enters the screen
        % within the configured ``screen_cache_ttl`` window). Must be
        % publicly readable since the freshness check lives outside the
        % VM. Other VMs (Circuits, Dashboard, Backends, etc.) declare
        % the same field — this one was missing it, so onEnter crashed
        % with "Unrecognized property 'LastRefresh'".
        LastRefresh = []
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = DetailedAnalysisViewModel(app)
            obj.App = app;
        end

        function onDownloadDetailedJson(obj)
            % Fetch /api/jobs/{id}/results/detailed and dump to a
            % user-chosen .json file. Tier B export action.
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, ...
                    Labels.get('error_not_authenticated'), ...
                    'Download JSON', 'Icon', 'warning');
                return;
            end
            jid = char(app.State.selectedJobId);
            if isempty(strtrim(jid))
                uialert(app.UIFigure, ...
                    'Open the Results screen first so a completed job is selected.', ...
                    'Download JSON', 'Icon', 'info');
                return;
            end
            app.logEvent('API', sprintf('GET /api/jobs/%s/results/detailed (export)', jid));
            app.showLoading('Fetching detailed results for export...');
            jobSvc = app.JobSvc;
            token  = app.State.authToken;
            AsyncRunner.run( ...
                @() jobSvc.getDetailedResults(jid, token), ...
                @(data) obj.onDetailedJsonReady(app, data, jid), ...
                @(ME)   obj.onDetailedJsonError(app, ME));
        end

        function onDetailedJsonReady(~, app, data, jid)
            app.hideLoading();
            cname = char(app.State.selectedCircuitName);
            % Operator filename rule: Results_Detailed_<circuit>_<jid>_<YYYYMMDD_HHMM>.json
            fname = Exporter.suggestFilename('Results', { ...
                'Detailed', cname, jid, Exporter.minuteStamp()});
            ok = Exporter.toJsonFile(data, fname, app.UIFigure);
            if ok
                app.logEvent('FILE', sprintf('Detailed JSON saved (job %s)', jid));
                app.State.logActivity( ...
                    sprintf('Download Detailed JSON — %s', cname), 'Success');
            end
        end

        function onDetailedJsonError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Detailed JSON export FAILED: %s', ME.message));
            app.showError('Download JSON', ME);
        end

        function onGenerateRunReport(obj)
            % Bridge from the Detailed Analysis screen to Reports —
            % pre-fills the title via Reports' own loadReportsList →
            % seedReportTitle. Same handover pattern used by Results
            % and Analysis.
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, ...
                    Labels.get('error_not_authenticated'), ...
                    'Generate Report', 'Icon', 'warning');
                return;
            end
            app.logEvent('NAV', 'Detailed Analysis → Reports');
            app.onSelectSection('Reports');
        end

        function onPlotComparison(obj)
            app = obj.App;
            if ~obj.requireLiveJob('Compare'); obj.plotComparisonDemo(); return; end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('GET /jobs/%s/results/detailed', jobId));
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            svc   = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getDetailedResults(jobId, token), ...
                @(data) obj.onPlotComparisonComplete(app, data), ...
                @(ME)   obj.onPlotComparisonError(app, ME));
        end

        function onPlotTemporal(obj)
            app = obj.App;
            if ~obj.requireLiveJob('Temporal'); obj.plotTemporalDemo(); return; end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('GET /jobs/%s/error-trends', jobId));
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            svc   = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getErrorTrends(jobId, token), ...
                @(data) obj.onPlotTemporalComplete(app, data), ...
                @(ME)   obj.onPlotTemporalError(app, ME));
        end

        function onPlotTemporalComplete(obj, app, data)
            try
                cla(app.TemporalAxes);
                items = JsonHelper.extractList(data, 'trend');
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n == 0
                    obj.appendInsight('[Temporal] Backend returned no trend points. (demo shown)');
                    app.hideLoading(); obj.plotTemporalDemo(); return;
                end
                conf = zeros(1, n);
                sig  = zeros(1, n);
                for i = 1:n
                    % Backend shape: {job_record_id, timestamp, error_rate, total_shots}
                    direct = JsonHelper.toDouble(JsonHelper.pick(items(i), {'confidence','value','fidelity'}));
                    if direct > 0
                        conf(i) = direct;
                    else
                        err = JsonHelper.toDouble(JsonHelper.pick(items(i), {'error_rate'}));
                        conf(i) = max(0, min(1, 1 - err));
                    end
                    sig(i) = JsonHelper.toDouble(JsonHelper.pick(items(i), {'std','uncertainty','sigma'}));
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
                obj.appendInsight(sprintf('[Temporal] n=%d · slope=%.4f/batch · outliers<%0.2f = %d', ...
                    n, driftSlope, confThresh, nOutliers));
                app.logEvent('API', 'Temporal plot updated from live data');
                app.hideLoading();
                return;
            catch ME
                app.hideLoading();
                Logger.warn('DetailedAnalysisViewModel', 'plotTemporalComplete failed: %s', ME.message);
                obj.appendInsight(sprintf('[Temporal] Render failed: %s (demo shown)', ME.message));
            end
            obj.plotTemporalDemo();
        end

        function onPlotTemporalError(obj, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Error trends failed: %s', ME.message));
            obj.reportLiveError('Temporal', ME);
            obj.plotTemporalDemo();
        end

        function onPlotQubit(obj)
            app = obj.App;
            if ~obj.requireLiveJob('Qubits'); obj.plotQubitDemo(); return; end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('GET /jobs/%s/results/detailed (qubit)', jobId));
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            svc   = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getDetailedResults(jobId, token), ...
                @(data) obj.onPlotQubitComplete(app, data), ...
                @(ME)   obj.onPlotQubitError(app, ME));
        end

        function onPlotQubitComplete(obj, app, data)
            try
                % Backend: qubit_metrics: [{qubit_index, readout_error, t1_us, t2_us, gate_error_1q, ...}]
                items = JsonHelper.extractList(data, 'qubit_metrics');
                if isempty(items); items = JsonHelper.extractList(data, 'qubit_fidelities'); end
                if isempty(items); items = JsonHelper.extractList(data, 'per_qubit_fidelity'); end
                n = numel(items);
                if n == 0
                    obj.appendInsight('[Qubits] Backend returned no qubit_metrics. (demo shown)');
                    app.hideLoading(); obj.plotQubitDemo(); return;
                end
                T1  = zeros(1, n);
                T2  = zeros(1, n);
                fid = zeros(1, n);
                for i = 1:n
                    T1(i)  = JsonHelper.toDouble(JsonHelper.pick(items(i), {'t1_us','T1','t1'}));
                    T2(i)  = JsonHelper.toDouble(JsonHelper.pick(items(i), {'t2_us','T2','t2'}));
                    ro     = JsonHelper.toDouble(JsonHelper.pick(items(i), {'readout_error'}));
                    direct = JsonHelper.toDouble(JsonHelper.pick(items(i), {'readout_fidelity','fidelity','value'}));
                    if direct > 0; fid(i) = direct; else; fid(i) = 1 - ro; end
                end
                % Keep only rows with valid T1 & T2 so the scatter isn't polluted by zeros.
                mask = (T1 > 0) & (T2 > 0);
                if ~any(mask)
                    obj.appendInsight('[Qubits] Backend returned qubit_metrics but no T1/T2 data. (demo shown)');
                    app.hideLoading(); obj.plotQubitDemo(); return;
                end
                T1 = T1(mask); T2 = T2(mask); fid = fid(mask); m = numel(T1);
                cla(app.QubitAxes);
                scatter(app.QubitAxes, T1, T2, 65, fid, 'filled', ...
                    'MarkerEdgeColor', [0.3 0.3 0.3], 'LineWidth', 0.5);
                colormap(app.QubitAxes, 'cool');
                cb = colorbar(app.QubitAxes);
                cb.Label.String  = 'Readout fidelity';
                cb.Label.FontSize = 10;
                if max(fid) > min(fid)
                    app.QubitAxes.CLim = [max(0, min(fid)-0.005), min(1, max(fid)+0.005)];
                else
                    app.QubitAxes.CLim = [0.95 1.00];
                end
                hold(app.QubitAxes, 'on');
                xBound = [min(T1)*0.9 max(T1)*1.1];
                plot(app.QubitAxes, xBound, 2*xBound, '--', ...
                    'Color', [0.85 0.33 0.10], 'LineWidth', 1.0);  % T2 = 2T1 physical bound
                hold(app.QubitAxes, 'off');
                app.QubitAxes.Title.String  = sprintf('T1 vs T2 per Qubit (n=%d)', m);
                app.QubitAxes.XLabel.String = 'T1 (\mus)';
                app.QubitAxes.YLabel.String = 'T2 (\mus)';
                app.styleAxes(app.QubitAxes);
                grid(app.QubitAxes, 'on');
                % Insight: outliers by T1/T2 and readout fidelity
                t1Thresh = AppConfig.getDouble('qubit_t1_outlier_us', 40);
                nT1Low   = sum(T1 < t1Thresh);
                obj.appendInsight(sprintf( ...
                    '[Qubits] n=%d · T1<%.0fus: %d · readout F min=%.3f mean=%.3f', ...
                    m, t1Thresh, nT1Low, min(fid), mean(fid)));
                app.logEvent('API', 'Qubit plot updated from live data');
                app.hideLoading();
                return;
            catch ME
                app.hideLoading();
                Logger.warn('DetailedAnalysisViewModel', 'plotQubitComplete failed: %s', ME.message);
                obj.appendInsight(sprintf('[Qubits] Render failed: %s (demo shown)', ME.message));
            end
            obj.plotQubitDemo();
        end

        function onPlotQubitError(obj, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Qubit data failed: %s', ME.message));
            obj.reportLiveError('Qubits', ME);
            obj.plotQubitDemo();
        end

        function onPlotHeatmap(obj)
            app = obj.App;
            if ~obj.requireLiveJob('Heatmap'); obj.plotHeatmapDemo(); return; end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('GET /jobs/%s/results/detailed (heatmap)', jobId));
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            svc   = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getDetailedResults(jobId, token), ...
                @(data) obj.onPlotHeatmapComplete(app, data), ...
                @(ME)   obj.onPlotHeatmapError(app, ME));
        end

        function onPlotHeatmapComplete(obj, app, data)
            try
                % Backend: fidelity_heatmap: list[list[float]] (2D grid)
                mat = [];
                if isstruct(data) && isfield(data, 'fidelity_heatmap')
                    mat = obj.toMatrix(data.fidelity_heatmap);
                end
                if isempty(mat)
                    legacy = JsonHelper.extractList(data, 'error_matrix');
                    if isempty(legacy); legacy = JsonHelper.extractList(data, 'crosstalk_matrix'); end
                    n = numel(legacy);
                    if n > 0
                        nQ = round(sqrt(n));
                        if nQ*nQ == n
                            mat = zeros(nQ, nQ);
                            for i = 1:n
                                r = ceil(i/nQ); c = mod(i-1,nQ)+1;
                                mat(r,c) = JsonHelper.toDouble(JsonHelper.pick(legacy(i), {'value','error_rate'}));
                            end
                        end
                    end
                end
                if isempty(mat) || all(mat(:) == 0)
                    obj.appendInsight('[Heatmap] Backend returned no fidelity_heatmap data. (demo shown)');
                    app.hideLoading(); obj.plotHeatmapDemo(); return;
                end
                cla(app.ErrorHeatmapAxes);
                imagesc(app.ErrorHeatmapAxes, mat);
                colormap(app.ErrorHeatmapAxes, 'hot');
                cb = colorbar(app.ErrorHeatmapAxes);
                cb.Label.String = 'Error rate';
                app.ErrorHeatmapAxes.CLim = [0 max(0.01, max(mat(:)))];
                app.ErrorHeatmapAxes.Title.String  = Labels.get('detailed_plot_heatmap_title');
                app.ErrorHeatmapAxes.XLabel.String = 'Qubit index';
                app.ErrorHeatmapAxes.YLabel.String = 'Qubit index';
                app.styleAxes(app.ErrorHeatmapAxes);
                nonzero = mat(mat > 0);
                maxErr = max(mat(:));
                meanErr = 0; if ~isempty(nonzero); meanErr = mean(nonzero); end
                obj.appendInsight(sprintf('[Heatmap] Max error = %.3f%%  mean = %.3f%% (%dx%d)', ...
                    maxErr*100, meanErr*100, size(mat,1), size(mat,2)));
                app.logEvent('API', 'Error heatmap updated from live data');
                app.hideLoading(); return;
            catch ME
                app.hideLoading();
                Logger.warn('DetailedAnalysisViewModel', 'plotHeatmapComplete failed: %s', ME.message);
                obj.appendInsight(sprintf('[Heatmap] Render failed: %s (demo shown)', ME.message));
            end
            obj.plotHeatmapDemo();
        end

        function onPlotHeatmapError(obj, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Error matrix failed: %s', ME.message));
            obj.reportLiveError('Heatmap', ME);
            obj.plotHeatmapDemo();
        end

        function onPlotRBDecay(obj)
            app = obj.App;
            if ~obj.requireLiveJob('RB Decay'); obj.plotRBDecayDemo(); return; end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('GET /jobs/%s/rb-decay', jobId));
            app.showLoading(Labels.get('loading_analysis', 'Loading analysis...'));
            svc   = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getRBDecay(jobId, token), ...
                @(data) obj.onPlotRBDecayComplete(app, data), ...
                @(ME)   obj.onPlotRBDecayError(app, ME));
        end

        function onPlotRBDecayComplete(obj, app, data)
            try
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
                Logger.warn('DetailedAnalysisViewModel', 'plotRBDecayComplete failed: %s', ME.message);
            end
            obj.plotRBDecayDemo();
        end

        function onPlotRBDecayError(obj, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('RB decay failed: %s', ME.message));
            obj.reportLiveError('RB Decay', ME);
            obj.plotRBDecayDemo();
        end

    end

    methods (Access = private)
        function onPlotComparisonComplete(obj, app, data)
            obj.plotComparisonFromData(data);
            app.logEvent('API', 'Comparison plot updated from live data');
            app.State.logActivity('Detailed analysis — comparison plot', 'Success');
            app.hideLoading();
            obj.populateDetailedKpis(app, data);
        end

        function populateDetailedKpis(obj, app, data)
            % Populate the M3 KPI strip from a detailed-results payload.
            % Each card pulls best-effort from the response and shows
            % "—" when the field is absent. Called from the comparison /
            % temporal / qubit plot completion handlers so the strip
            % refreshes as the user explores different views.
            try
                fidVal = JsonHelper.pickNumeric(data, ...
                    {'estimated_fidelity','measured_fidelity','fidelity'}, NaN);
                if isfinite(fidVal)
                    obj.setDetailedKpi(app.DetailedKpiFidelityVal, ...
                        app.DetailedKpiFidelitySub, ...
                        sprintf('%.4f', fidVal), 'measured');
                end
                drift = JsonHelper.pickNumeric(data, ...
                    {'drift_total','drift_score','temporal_drift'}, NaN);
                if isfinite(drift)
                    obj.setDetailedKpi(app.DetailedKpiDriftVal, ...
                        app.DetailedKpiDriftSub, ...
                        sprintf('%.4f', drift), 'across runs');
                end
                nq = JsonHelper.pickNumeric(data, ...
                    {'num_qubits','width','qubit_count'}, NaN);
                if isfinite(nq) && nq > 0
                    obj.setDetailedKpi(app.DetailedKpiQubitsVal, ...
                        app.DetailedKpiQubitsSub, ...
                        sprintf('%d', round(nq)), '');
                end
                rb = JsonHelper.pickNumeric(data, ...
                    {'rb_decay','randomized_benchmark.decay'}, NaN);
                if isfinite(rb)
                    obj.setDetailedKpi(app.DetailedKpiRBVal, ...
                        app.DetailedKpiRBSub, ...
                        sprintf('%.4f', rb), 'avg gate fidelity');
                end
                outliers = JsonHelper.pickNumeric(data, ...
                    {'outlier_count','outliers'}, NaN);
                if isfinite(outliers)
                    obj.setDetailedKpi(app.DetailedKpiOutliersVal, ...
                        app.DetailedKpiOutliersSub, ...
                        sprintf('%d', round(outliers)), 'states beyond 3σ');
                end
            catch ME
                Logger.debug('DetailedAnalysisViewModel', ...
                    'populateDetailedKpis: %s', ME.message);
            end
        end

        function setDetailedKpi(~, valLbl, subLbl, valTxt, subTxt)
            % Sibling of AnalysisViewModel.setAnalysisKpi — tilde first
            % arg so callers can use obj.setDetailedKpi(...) without
            % the helper itself touching obj.
            try
                if ~isempty(valLbl) && isvalid(valLbl)
                    if isempty(strtrim(char(string(valTxt))))
                        valLbl.Text = char(8212);
                    else
                        valLbl.Text = char(string(valTxt));
                    end
                end
                if ~isempty(subLbl) && isvalid(subLbl)
                    subLbl.Text = char(string(subTxt));
                end
            catch
            end
        end

        function onPlotComparisonError(obj, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Detailed results failed: %s', ME.message));
            obj.reportLiveError('Compare', ME);
            obj.plotComparisonDemo();
        end

        function onDetailedCircuitsLoaded(~, app, data)
            try; app.hideLoading(); catch; end
            if isempty(app.DetailedAnalysisCircuitDropdown) ...
                    || ~isvalid(app.DetailedAnalysisCircuitDropdown); return; end
            items = JsonHelper.extractList(data, 'circuits');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0
                app.DetailedAnalysisCircuitDropdown.Items     = {'(no circuits)'};
                app.DetailedAnalysisCircuitDropdown.ItemsData = {''};
                app.DetailedAnalysisCircuitDropdown.Value     = '';
                return;
            end
            names = cell(1, n); ids = cell(1, n);
            for i = 1:n
                ids{i}   = char(JsonHelper.pick(items(i), {'circuit_id','id'}));
                nm       = char(JsonHelper.pick(items(i), {'name','circuit_name'}));
                if isempty(nm); nm = ids{i}; end
                names{i} = nm;
            end
            app.DetailedAnalysisCircuitDropdown.Items     = names;
            app.DetailedAnalysisCircuitDropdown.ItemsData = ids;
            selId = char(app.State.selectedCircuitId);
            match = find(strcmp(ids, selId), 1);
            if ~isempty(match)
                app.DetailedAnalysisCircuitDropdown.Value = ids{match};
            else
                app.DetailedAnalysisCircuitDropdown.Value = ids{1};
                app.State.selectedCircuitId   = string(ids{1});
                app.State.selectedCircuitName = string(names{1});
            end
            app.logEvent('LOAD', sprintf('Loaded %d circuits into Detailed Analysis dropdown', n));
        end

        function onDetailedCircuitsError(~, app, ME)
            try; app.hideLoading(); catch; end
            Logger.warn('DetailedAnalysisViewModel', ...
                'Failed to load circuits: %s', ME.message);
            if ~isempty(app.DetailedAnalysisCircuitDropdown) ...
                    && isvalid(app.DetailedAnalysisCircuitDropdown)
                app.DetailedAnalysisCircuitDropdown.Items     = {'(load failed)'};
                app.DetailedAnalysisCircuitDropdown.ItemsData = {''};
                app.DetailedAnalysisCircuitDropdown.Value     = '';
            end
        end
    end

    methods
        % --- Demo render methods (also called by DetailedAnalysisScreen
        %     at build time so the chart layout has content before any
        %     Refresh button is clicked). RNG is seeded locally so
        %     repeated renders produce pixel-identical output.

        function plotAllDemos(obj)
            % Render all five demo charts in one call. Used by the screen
            % builder for initial paint.
            obj.plotComparisonDemo();
            obj.plotHeatmapDemo();
            obj.plotTemporalDemo();
            obj.plotQubitDemo();
            obj.plotRBDecayDemo();
        end

        % ── Circuit selector wiring ─────────────────────────────────────
        %   The toolbar's Circuit dropdown is populated on screen entry
        %   and on demand. Picking a row updates app.State so every
        %   downstream call (Compare, Heatmap, Temporal, Qubits, RB
        %   Decay) targets the right circuit.

        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            obj.loadCircuits();
            obj.LastRefresh = tic;
        end

        function loadCircuits(obj)
            app = obj.App;
            token   = app.State.authToken;
            circSvc = app.CircuitSvc;
            AsyncRunner.run( ...
                @() circSvc.listCircuits(token), ...
                @(data) obj.onDetailedCircuitsLoaded(app, data), ...
                @(ME)   obj.onDetailedCircuitsError(app, ME));
        end

        function onCircuitSelected(obj, circuitId)
            app = obj.App;
            if isempty(circuitId); return; end
            app.State.selectedCircuitId = string(circuitId);
            try
                items = app.DetailedAnalysisCircuitDropdown.Items;
                ids   = app.DetailedAnalysisCircuitDropdown.ItemsData;
                k = find(strcmp(ids, char(circuitId)), 1);
                if ~isempty(k)
                    app.State.selectedCircuitName = string(items{k});
                end
            catch
            end
            app.logEvent('UI', sprintf('Detailed Analysis circuit selected: %s', ...
                char(app.State.selectedCircuitName)));
        end

        function onAnalyze(obj)
            % Bridge to the Analysis screen: navigate there with the
            % currently-selected Detailed Analysis circuit pre-selected
            % and auto-trigger the analyze POST so the user lands on the
            % result without having to click a second button.
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), ...
                    'Detailed Analysis', 'Icon', 'warning'); return;
            end
            % Read the current selection directly from the dropdown;
            % onCircuitSelected keeps app.State in sync, but be defensive
            % in case the user never touched the dropdown.
            cid = '';
            name = '';
            try
                cid = char(app.DetailedAnalysisCircuitDropdown.Value);
                items = app.DetailedAnalysisCircuitDropdown.Items;
                ids   = app.DetailedAnalysisCircuitDropdown.ItemsData;
                k = find(strcmp(ids, cid), 1);
                if ~isempty(k); name = items{k}; end
            catch
            end
            if isempty(strtrim(cid))
                uialert(app.UIFigure, ...
                    'Pick a circuit from the dropdown before clicking Analyze.', ...
                    'Detailed Analysis', 'Icon', 'warning');
                return;
            end
            % Propagate the selection so the Analysis screen's own
            % onEnter → onEnterCircuitsLoaded path auto-selects it when
            % the dropdown populates, and so onAnalyzeCircuit picks it
            % up even if the Analysis dropdown is still loading.
            app.State.selectedCircuitId   = string(cid);
            if ~isempty(name)
                app.State.selectedCircuitName = string(name);
            end
            app.logEvent('UI', sprintf( ...
                'Detailed Analysis → Analysis (circuit: %s)', ...
                char(app.State.selectedCircuitName)));

            % Navigate. autoLoadScreen on the target 'Analysis' case
            % calls AnalysisVm.onEnter when the cache is stale; when
            % the cache is fresh, the existing dropdown already has
            % our circuit — we just need to nudge it visually and fire
            % onCircuitSelected so dependent state (e.g. backend list)
            % refreshes.
            app.onSelectSection('Analysis');
            try
                if ~isempty(app.AnalysisCircuitDropdown) ...
                        && isvalid(app.AnalysisCircuitDropdown) ...
                        && iscell(app.AnalysisCircuitDropdown.ItemsData) ...
                        && any(strcmp(app.AnalysisCircuitDropdown.ItemsData, cid))
                    app.AnalysisCircuitDropdown.Value = cid;
                    app.AnalysisVm.onCircuitSelected(cid);
                end
            catch ME
                Logger.debug('DetailedAnalysisViewModel', ...
                    'Analysis dropdown sync: %s', ME.message);
            end

            % Kick off the analyze request. onAnalyzeCircuit reads
            % app.State.selectedCircuitId directly — it doesn't depend
            % on whether the Analysis dropdown has repainted yet.
            try
                app.AnalysisVm.onAnalyzeCircuit();
            catch ME
                Logger.warn('DetailedAnalysisViewModel', ...
                    'onAnalyzeCircuit: %s', ME.message);
            end
        end

        function plotComparisonDemo(obj)
            app = obj.App;
            cla(app.CompareAxes);
            rs = RandStream('twister', 'Seed', 1001);
            x  = 1:10;
            y1 = 0.73 + 0.06*randn(rs, 1, 10);
            y2 = 0.78 + 0.03*randn(rs, 1, 10);
            b  = bar(app.CompareAxes, x, [y1' y2'], 'grouped');
            b(1).FaceColor = [0.20 0.48 0.78]; b(1).FaceAlpha = 0.88;
            b(2).FaceColor = [0.93 0.45 0.18]; b(2).FaceAlpha = 0.88;
            hold(app.CompareAxes, 'on');
            err = 0.018 + 0.008*rand(rs, 1, 10);
            errorbar(app.CompareAxes, x-0.18, y1, err, '.', ...
                'Color', [0.10 0.22 0.48], 'LineWidth', 1.1, 'CapSize', 3);
            hold(app.CompareAxes, 'off');
            legend(app.CompareAxes, {'Measured','Ideal'}, 'Location','northeast','FontSize',10);
            app.CompareAxes.Title.String  = Labels.get('detailed_plot_compare_title', 'Top-10 State Probabilities (demo)');
            app.CompareAxes.XLabel.String = 'Basis state index';
            app.CompareAxes.YLabel.String = 'Probability';
            app.CompareAxes.YLim = [0 1];
            app.styleAxes(app.CompareAxes);
            grid(app.CompareAxes, 'on');
            app.CompareAxes.GridAlpha = 0.18;
        end

        function plotTemporalDemo(obj)
            app = obj.App;
            cla(app.TemporalAxes);
            rs   = RandStream('twister', 'Seed', 1002);
            t2   = 1:40;
            conf = 0.940 + 0.018*randn(rs, 1, 40);
            sig  = 0.012 + 0.004*rand(rs, 1, 40);
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
            app.TemporalAxes.Title.String  = Labels.get('detailed_plot_temporal_title', 'Confidence per Shot Batch (demo)');
            app.TemporalAxes.XLabel.String = Labels.get('detailed_plot_x_batch', 'Batch index');
            app.TemporalAxes.YLabel.String = 'Confidence';
            app.TemporalAxes.YLim = [0.88 1.01];
            app.styleAxes(app.TemporalAxes);
            grid(app.TemporalAxes, 'on');
            app.TemporalAxes.GridAlpha = 0.18;
        end

        function plotQubitDemo(obj)
            app = obj.App;
            cla(app.QubitAxes);
            rs   = RandStream('twister', 'Seed', 1003);
            nQb  = 27;
            T1   = 45 + 38*rand(rs, 1, nQb);
            T2   = min(35 + 28*rand(rs, 1, nQb), 2*T1 - 3);   % physical T2 ≤ 2·T1
            fidQ = 0.955 + 0.038*rand(rs, 1, nQb);
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
            app.QubitAxes.Title.String  = Labels.get('detailed_plot_qubit_title', 'T1 vs T2 per Qubit (demo)');
            app.QubitAxes.XLabel.String = 'T1 (\mus)';
            app.QubitAxes.YLabel.String = 'T2 (\mus)';
            app.styleAxes(app.QubitAxes);
            grid(app.QubitAxes, 'on');
            app.QubitAxes.GridAlpha = 0.18;
        end

        function plotHeatmapDemo(obj)
            app = obj.App;
            cla(app.ErrorHeatmapAxes);
            rs     = RandStream('twister', 'Seed', 1004);
            nQ     = 8;
            errMat = 0.015*rand(rs, nQ, nQ);
            errMat = (errMat + errMat') / 2;
            for i = 1:nQ; errMat(i,i) = 0; end
            errMat(2,3) = 0.042; errMat(3,2) = 0.042;  % stronger coupling pairs
            errMat(5,6) = 0.038; errMat(6,5) = 0.038;
            imagesc(app.ErrorHeatmapAxes, errMat);
            colormap(app.ErrorHeatmapAxes, 'hot');
            cb = colorbar(app.ErrorHeatmapAxes);
            cb.Label.String  = 'Error rate';
            cb.Label.FontSize = 10;
            app.ErrorHeatmapAxes.CLim  = [0 0.05];
            app.ErrorHeatmapAxes.XTick = 1:nQ;
            app.ErrorHeatmapAxes.YTick = 1:nQ;
            app.ErrorHeatmapAxes.Title.String  = Labels.get('detailed_plot_heatmap_title', 'Qubit Pair Error Rates (demo)');
            app.ErrorHeatmapAxes.XLabel.String = 'Qubit index';
            app.ErrorHeatmapAxes.YLabel.String = 'Qubit index';
            app.styleAxes(app.ErrorHeatmapAxes);
        end

        function plotRBDecayDemo(obj)
            app = obj.App;
            cla(app.RBDecayAxes);
            rs    = RandStream('twister', 'Seed', 1005);
            mPts  = [1 2 4 8 16 32 64 128 256];
            EPC   = 0.0019;  A_rb = 0.475;  B_rb = 0.500;
            pFit  = A_rb*(1-2*EPC).^mPts + B_rb;
            pMea  = pFit + 0.008*randn(rs, size(pFit));
            pErr  = 0.007 + 0.003*rand(rs, size(pFit));
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
            app.RBDecayAxes.Title.String  = sprintf('%s  —  EPC = %.4f%%', ...
                Labels.get('detailed_plot_rb_title', 'RB Decay (demo)'), EPC*100);
            app.RBDecayAxes.XLabel.String = 'Sequence length (Clifford gates)';
            app.RBDecayAxes.YLabel.String = 'Survival probability';
            app.styleAxes(app.RBDecayAxes);
            grid(app.RBDecayAxes, 'on');
            app.RBDecayAxes.GridAlpha = 0.18;
        end

    end

    methods (Access = private)
        function plotComparisonFromData(obj, data)
            app = obj.App;
            try
                % Backend returns fidelity_comparison:
                %   { outcome_buckets: [int], measured: [float], ideal: [float], predicted: [float] }
                fc = [];
                if isstruct(data) && isfield(data, 'fidelity_comparison')
                    fc = data.fidelity_comparison;
                end
                measArr = [];
                idealArr = [];
                if ~isempty(fc)
                    if isstruct(fc) && isfield(fc, 'measured'); measArr = fc.measured; end
                    if isstruct(fc) && isfield(fc, 'ideal');    idealArr = fc.ideal; end
                end
                % Back-compat with legacy shape {measured_probs, ideal_probs} of objects.
                if isempty(measArr)
                    legacy = JsonHelper.extractList(data, 'measured_probs');
                    if ~isempty(legacy)
                        measArr = arrayfun(@(s) JsonHelper.toDouble(JsonHelper.pick(s, {'prob','value'})), legacy);
                    end
                end
                if isempty(idealArr)
                    legacy = JsonHelper.extractList(data, 'ideal_probs');
                    if ~isempty(legacy)
                        idealArr = arrayfun(@(s) JsonHelper.toDouble(JsonHelper.pick(s, {'prob','value'})), legacy);
                    end
                end
                n = min(10, max(numel(measArr), numel(idealArr)));
                if n == 0
                    obj.appendInsight('[Compare] Backend returned no fidelity_comparison data. (demo shown)');
                    obj.plotComparisonDemo(); return;
                end
                cla(app.CompareAxes);
                y1 = zeros(1, n); y2 = zeros(1, n);
                for i = 1:n
                    if i <= numel(measArr);  y1(i) = double(measArr(i));  end
                    if i <= numel(idealArr); y2(i) = double(idealArr(i)); end
                end
                x = 1:n;
                bar(app.CompareAxes, x, [y1' y2'], 'grouped');
                legend(app.CompareAxes, {'Measured','Ideal'}, 'Location', 'northeast');
                app.CompareAxes.Title.String  = 'Top-10 State Probabilities';
                app.CompareAxes.XLabel.String = 'Basis state index';
                app.CompareAxes.YLabel.String = 'Probability';
                app.CompareAxes.YLim = [0 1];
                app.styleAxes(app.CompareAxes);
                grid(app.CompareAxes, 'on');
                % KL-divergence diagnostic
                eps = 1e-9;
                p = max(y1, eps); q = max(y2, eps);
                kl = sum(p .* log(p ./ q));
                obj.appendInsight(sprintf('[Compare] KL(measured || ideal) = %.4f (n=%d buckets)', kl, n));
            catch ME
                Logger.warn('DetailedAnalysisViewModel', 'plotComparisonFromData failed: %s', ME.message);
                obj.appendInsight(sprintf('[Compare] Render failed: %s (demo shown)', ME.message));
                obj.plotComparisonDemo();
            end
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

        function ok = requireLiveJob(obj, tag)
            % Precondition check before hitting a per-job endpoint. Returns
            % true when a live fetch is viable. Otherwise, explains why in
            % the Interpretation panel and returns false so the caller can
            % fall back to the demo chart.
            app = obj.App;
            ok = false;
            if ~app.State.isAuthenticated()
                obj.appendInsight(sprintf('[%s] Login required — showing demo data.', tag));
                return;
            end
            if ~app.State.hasJob()
                obj.appendInsight(sprintf( ...
                    '[%s] No job selected — open the Jobs screen and pick a completed job first. (demo shown)', tag));
                return;
            end
            ok = true;
        end

        function reportLiveError(obj, tag, ME)
            % Shared 409 / 404 / timeout messaging. Falls back to demo after.
            ident = '';
            try; ident = ME.identifier; catch; end
            if contains(ident, 'HTTP409')
                obj.appendInsight(sprintf( ...
                    '[%s] Job not yet completed (409) — results appear after it finishes. (demo shown)', tag));
            elseif contains(ident, 'HTTP404')
                obj.appendInsight(sprintf( ...
                    '[%s] Endpoint not available on this API build (404) — showing demo.', tag));
            elseif contains(ident, 'HTTP401') || contains(ident, 'HTTP403')
                obj.appendInsight(sprintf( ...
                    '[%s] Not authorized (%s) — re-login and retry. (demo shown)', tag, ident));
            else
                obj.appendInsight(sprintf('[%s] Fetch failed: %s (demo shown)', tag, ME.message));
            end
        end

        function M = toMatrix(~, raw)
            % Coerce a JSON-decoded 2-D array into a MATLAB numeric matrix.
            % webread returns:
            %   - a numeric matrix if rows are uniform length, or
            %   - a cell array of row vectors otherwise.
            M = [];
            if isempty(raw); return; end
            if isnumeric(raw) && ~isvector(raw)
                M = raw; return;
            end
            if iscell(raw)
                nRows = numel(raw);
                if nRows == 0; return; end
                lens = cellfun(@numel, raw);
                if any(lens ~= lens(1)); return; end  % ragged
                M = zeros(nRows, lens(1));
                for i = 1:nRows
                    M(i,:) = double(raw{i}(:))';
                end
            elseif isnumeric(raw) && isvector(raw)
                M = raw(:)';  % 1-row matrix
            end
        end
    end
end
