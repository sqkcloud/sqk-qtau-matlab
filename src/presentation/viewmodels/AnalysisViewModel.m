classdef AnalysisViewModel < handle
    % AnalysisViewModel  Callback handlers for the Analysis screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = AnalysisViewModel(app)
            obj.App = app;
        end

        function onEnter(obj)
            % Called when navigating to the Analysis screen — load circuits
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            app.logEvent('API', 'GET /api/circuits — loading circuit list for Analysis');
            app.showLoading(Labels.get('loading_circuits', 'Loading circuits...'));
            circSvc = app.CircuitSvc;
            token   = app.State.authToken;
            AsyncRunner.run( ...
                @() circSvc.listCircuits(token), ...
                @(data) obj.onEnterCircuitsLoaded(data), ...
                @(ME)   obj.onEnterCircuitsError(ME));
        end

        function onEnterCircuitsLoaded(obj, data)
            app = obj.App;
            try
                items = JsonHelper.extractList(data, 'circuits');
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n == 0
                    app.AnalysisCircuitDropdown.Items     = {'(no circuits)'};
                    app.AnalysisCircuitDropdown.ItemsData = {''};
                    app.hideLoading();
                    return;
                end
                names = cell(1, n);
                ids   = cell(1, n);
                for i = 1:n
                    cid  = char(JsonHelper.pick(items(i), {'circuit_id','id'}));
                    cname = char(JsonHelper.pick(items(i), {'name','circuit_name'}));
                    if isempty(cname); cname = cid; end
                    names{i} = cname;
                    ids{i}   = cid;
                end
                app.AnalysisCircuitDropdown.Items     = names;
                app.AnalysisCircuitDropdown.ItemsData = ids;
                selId = char(app.State.selectedCircuitId);
                idx   = find(strcmp(ids, selId), 1);
                if ~isempty(idx)
                    app.AnalysisCircuitDropdown.Value = ids{idx};
                    obj.onCircuitSelected(ids{idx});
                else
                    app.AnalysisCircuitDropdown.Value = ids{1};
                    obj.onCircuitSelected(ids{1});
                end
                app.logEvent('API', sprintf('Circuit list loaded — %d circuit(s), selected: %s', ...
                    n, char(app.AnalysisCircuitDropdown.Value)));
                obj.LastRefresh = tic;
            catch ME
                app.logEvent('WARN', sprintf('Failed to populate circuits: %s', ME.message));
            end
            app.hideLoading();
        end

        function onEnterCircuitsError(obj, ME)
            app = obj.App;
            app.hideLoading();
            app.logEvent('WARN', sprintf('Failed to load circuits: %s', ME.message));
        end

        function onCircuitSelected(obj, circuitId)
            app = obj.App;
            if isempty(circuitId); return; end
            app.State.selectedCircuitId   = string(circuitId);
            app.State.selectedCircuitName = string(app.AnalysisCircuitDropdown.Value);
            % Find display name from Items
            idx = find(strcmp(app.AnalysisCircuitDropdown.ItemsData, circuitId), 1);
            if ~isempty(idx)
                app.State.selectedCircuitName = string(app.AnalysisCircuitDropdown.Items{idx});
            end
            app.logEvent('UI', sprintf('Circuit selected: %s (%s)', ...
                char(app.State.selectedCircuitName), circuitId));
        end

        function onAnalyzeCircuit(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Analyze', 'Icon', 'warning'); return;
            end
            if ~app.State.hasCircuit()
                uialert(app.UIFigure, Labels.get('error_no_circuit'), 'Analyze', 'Icon', 'warning'); return;
            end
            cid = app.State.selectedCircuitId;
            app.logEvent('API', sprintf('POST /api/circuits/%s/analyze — circuit: %s  name: %s', ...
                cid, cid, app.State.selectedCircuitName));
            app.showLoading(Labels.get('loading_analyzing', 'Analyzing circuit...'));
            circSvc = app.CircuitSvc;
            token   = app.State.authToken;
            AsyncRunner.run( ...
                @() circSvc.analyzeCircuit(cid, token), ...
                @(data) obj.onAnalyzeComplete(app, cid, data), ...
                @(ME) obj.onAnalyzeError(app, cid, ME));
        end

        % Open the Quantum Monte Carlo Simulation (Quantum Amplitude
        % Estimation) popup. Fetches any previously cached result for the
        % selected circuit so the dialog opens with data already shown.
        function onOpenQmcDialog(obj)
            app = obj.App;
            if ~isempty(app.QmcDialog) && isvalid(app.QmcDialog)
                figure(app.QmcDialog);  % bring existing dialog to front
                return;
            end
            DialogBuilder.buildQmcDialog(app);
            % Populate the backend dropdown from BackendService so the
            % popup mirrors the Backends screen's list.
            obj.loadQmcBackends();
            % Best-effort: pre-populate with the last cached result for
            % this circuit so returning users see data immediately.
            try
                if app.State.isAuthenticated() && app.State.hasCircuit()
                    cid = app.State.selectedCircuitId;
                    token = app.State.authToken;
                    cached = app.QmcSvc.getLast(cid, token);
                    app.QmcLastResult = cached;
                    obj.renderQmcResult(app, cached);
                    AnalysisViewModel.toggleIbmLogButton(app, cached);
                end
            catch ME
                Logger.debug('AnalysisViewModel', 'No cached QMC result: %s', ME.message);
                AnalysisViewModel.toggleIbmLogButton(app, []);
            end
        end

        % Populate app.QmcBackendField (uidropdown) using BackendService,
        % mirroring BenchmarkDashboardViewModel.loadBackends' 3-tier
        % fallback (selected circuit → first circuit → unscoped list).
        function loadQmcBackends(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            token = app.State.authToken;

            cid = '';
            if app.State.hasCircuit(); cid = char(app.State.selectedCircuitId); end

            backendSvc = app.BackendSvc;
            circSvc    = app.CircuitSvc;
            AsyncRunner.run( ...
                @() AnalysisViewModel.fetchBackendList(backendSvc, circSvc, cid, token), ...
                @(data) obj.onQmcBackendsLoaded(app, data), ...
                @(ME)   obj.onQmcBackendsError(app, ME));
        end

        function onQmcBackendsLoaded(~, app, data)
            if isempty(app.QmcBackendField) || ~isvalid(app.QmcBackendField); return; end
            items = JsonHelper.extractList(data, 'backends');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0
                app.QmcBackendField.Items     = {'(no backends)'};
                app.QmcBackendField.ItemsData = {''};
                app.QmcBackendField.Value     = '';
                return;
            end
            names = cell(1, n);
            for i = 1:n
                names{i} = char(JsonHelper.pick(items(i), {'name','backend_name'}));
            end
            app.QmcBackendField.Items     = names;
            app.QmcBackendField.ItemsData = names;
            % Prefer the currently-selected backend if present, else first.
            sel = char(app.State.selectedBackend);
            match = find(strcmp(names, sel), 1);
            if ~isempty(match)
                app.QmcBackendField.Value = names{match};
            else
                app.QmcBackendField.Value = names{1};
            end
            app.logEvent('LOAD', sprintf('Loaded %d backends into QMC dropdown', n));
        end

        function onQmcBackendsError(~, app, ME)
            if ~isempty(app.QmcBackendField) && isvalid(app.QmcBackendField)
                app.QmcBackendField.Items     = {'(load failed)'};
                app.QmcBackendField.ItemsData = {''};
                app.QmcBackendField.Value     = '';
            end
            Logger.warn('AnalysisViewModel', 'QMC backend load failed: %s', ME.message);
        end

        % Quantum Monte Carlo Simulation (Quantum Amplitude Estimation)
        %   Runs a QMC analysis on the selected circuit via the FastAPI
        %   backend and refreshes the Analysis screen's QMC section.
        function onRunQmcAnalysis(obj)
            app = obj.App;
            alertParent = AnalysisViewModel.qmcAlertParent(app);
            if ~app.State.isAuthenticated()
                uialert(alertParent, Labels.get('error_not_authenticated'), ...
                    'Quantum Monte Carlo', 'Icon', 'warning');
                return;
            end
            if ~app.State.hasCircuit()
                uialert(alertParent, ...
                    'Select an uploaded circuit first (e.g. an AQS-QMC VaR circuit).', ...
                    'Quantum Monte Carlo', 'Icon', 'warning');
                return;
            end
            cid = app.State.selectedCircuitId;
            mode = char(app.QmcModeDropdown.Value);
            backend = char(app.QmcBackendField.Value);
            if strcmp(mode, 'statevector'); backend = ''; end
            shots = double(app.QmcShotsField.Value);
            epsilon = double(app.QmcEpsilonField.Value);
            confidence = double(app.QmcConfidenceField.Value);
            risk = char(app.QmcRiskDropdown.Value);
            % Map the shot/epsilon-derived path register width.
            n = 7;
            try; n = max(2, min(12, app.State.selectedCircuitQubits)); catch; end

            % Advanced controls (mitigation + real-time market params).
            opts = struct();
            try
                if ~isempty(app.QmcMitigationDropdown) && isvalid(app.QmcMitigationDropdown)
                    opts.mitigation = char(app.QmcMitigationDropdown.Value);
                end
            catch; end
            try
                opts.market = struct( ...
                    'spot',              double(app.QmcSpotField.Value), ...
                    'strike',            double(app.QmcStrikeField.Value), ...
                    'volatility',        double(app.QmcVolField.Value), ...
                    'risk_free_rate',    double(app.QmcRateField.Value), ...
                    'time_to_maturity',  double(app.QmcTenorField.Value), ...
                    'option_type',       char(app.QmcOptionTypeDropdown.Value), ...
                    'notional',          double(app.QmcNotionalField.Value));
            catch
                % Market controls not yet built — server uses defaults.
            end
            opts.compute_greeks = true;

            if isfield(opts,'mitigation'); mitLog = opts.mitigation; else; mitLog = 'none'; end
            app.logEvent('API', sprintf('POST /api/circuits/%s/qae/analyze — mode=%s shots=%d mitig=%s', ...
                cid, mode, shots, mitLog));
            % Wipe every KPI / Greek / chart on the popup so the user sees
            % empty controls while the server is running rather than stale
            % values from a previous run.
            obj.resetQmcUi(app);
            app.showLoading('Running Quantum Monte Carlo simulation...');

            qaeSvc = app.QmcSvc;
            token  = app.State.authToken;
            % Submit the async job. The server enqueues the work and
            % returns {job_id, status:"queued"} in a few hundred ms;
            % long IBM waits happen inside the poll loop, not on this
            % HTTP call.
            try
                envelope = qaeSvc.submitAnalyze(cid, mode, shots, epsilon, ...
                    confidence, n, risk, backend, opts, token);
            catch ME
                obj.onQmcError(app, ME);
                return;
            end
            jobId = char(JsonHelper.pick(envelope, {'job_id'}, ''));
            if isempty(jobId)
                obj.onQmcError(app, MException('QTAU:QmcSubmit', ...
                    'Server did not return a job_id.'));
                return;
            end
            app.QmcActiveJobId = jobId;
            app.logEvent('API', sprintf('QMC job %s queued (mode=%s) — polling every 3s', jobId, mode));
            obj.startQmcPoll(app, jobId);
        end

        function onCloseQmcDialog(obj)
            % Teardown: stop polling timer, hide overlay, destroy dialog.
            % The async QMC job (if any) is left running on the server;
            % the user can reopen the popup and getLast will show the
            % result when it completes.
            app = obj.App;
            try; obj.stopQmcPoll(app); catch; end
            try; app.hideLoading(); catch; end
            app.QmcActiveJobId = '';
            try
                if ~isempty(app.QmcDialog) && isvalid(app.QmcDialog)
                    delete(app.QmcDialog);
                end
            catch
            end
        end

        function onDownloadIbmLog(obj)
            app = obj.App;
            alertParent = AnalysisViewModel.qmcAlertParent(app);
            if ~app.State.isAuthenticated()
                uialert(alertParent, Labels.get('error_not_authenticated'), ...
                    'Download IBM Log', 'Icon', 'warning');
                return;
            end
            if ~app.State.hasCircuit()
                uialert(alertParent, 'Select a circuit first.', ...
                    'Download IBM Log', 'Icon', 'warning');
                return;
            end
            runtimeJobId = '';
            if ~isempty(app.QmcLastResult)
                runtimeJobId = char(JsonHelper.pick(app.QmcLastResult, ...
                    {'runtime_job_id'}, ''));
            end
            if isempty(runtimeJobId)
                uialert(alertParent, ...
                    ['No IBM Runtime job is associated with the cached QMC result. ' ...
                     'Switch Execution Mode to "IBM Runtime" and Run QMC first.'], ...
                    'Download IBM Log', 'Icon', 'warning');
                return;
            end
            cid      = char(app.State.selectedCircuitId);
            circName = char(app.State.selectedCircuitName);
            token    = app.State.authToken;
            qaeSvc   = app.QmcSvc;
            % JSONL matches the reference schema in
            % samples/aqs-qmc/outputs_hybrid_mc_qdist_stable/quantum_exec_log.jsonl —
            % one record per IBM job submission with the keys
            % subcircuit_id/backend/shots/status/job_id/counts/error.
            fmt      = 'jsonl';
            tmpPath  = fullfile(tempdir, sprintf('quantum_exec_log_%s.%s', runtimeJobId, fmt));
            app.logEvent('API', sprintf('GET /api/circuits/%s/qae/ibm-log (job=%s)', cid, runtimeJobId));
            app.showLoading('Fetching IBM Runtime log...');
            AsyncRunner.run( ...
                @() qaeSvc.downloadIbmLog(cid, token, fmt, tmpPath), ...
                @(savedPath) obj.onIbmLogDownloaded(app, savedPath, runtimeJobId, circName, fmt), ...
                @(ME)        obj.onIbmLogError(app, ME));
        end

        function onGenerateQmcReport(obj)
            app = obj.App;
            alertParent = AnalysisViewModel.qmcAlertParent(app);
            if ~app.State.isAuthenticated()
                uialert(alertParent, Labels.get('error_not_authenticated'), ...
                    'Generate Report', 'Icon', 'warning');
                return;
            end
            if ~app.State.hasCircuit()
                uialert(alertParent, 'Select a circuit before generating the report.', ...
                    'Generate Report', 'Icon', 'warning');
                return;
            end
            cid = app.State.selectedCircuitId;
            if isempty(app.QmcLastResult)
                choice = uiconfirm(alertParent, ...
                    'No QMC analysis has been run on this circuit yet. Run it now with current settings before generating the PDF?', ...
                    'Generate Report', 'Options', {'Run and generate', 'Cancel'}, ...
                    'DefaultOption', 1, 'CancelOption', 2);
                if strcmp(choice, 'Cancel'); return; end
                obj.onRunQmcAnalysis();
                return;  % report will be requested after analyze completes (user clicks again)
            end
            app.showLoading('Generating PDF report...');
            sections = { ...
                'executive_summary', 'circuit_summary', 'feature_analysis', ...
                'quantum_monte_carlo', 'key_insights'};
            title = sprintf('Quantum Monte Carlo VaR Report — %s', char(app.State.selectedCircuitName));
            reportSvc = app.ReportSvc;
            token     = app.State.authToken;
            AsyncRunner.run( ...
                @() reportSvc.generateReport(title, 'technical', 'pdf', cid, '', '', sections, token), ...
                @(data) obj.onQmcReportGenerated(app, data), ...
                @(ME)   obj.onQmcReportError(app, ME));
        end

        function onCircuitCuttingBridge(obj)
            % Bridge: Analysis → Circuit Cutting with the currently-selected
            % circuit pre-applied. Mirrors the Detailed Analysis → Analysis
            % bridge so the user does not have to re-pick the circuit on
            % the Cutting screen.
            app = obj.App;
            cid = '';
            try
                if ~isempty(app.AnalysisCircuitDropdown) ...
                        && isvalid(app.AnalysisCircuitDropdown)
                    cid = char(string(app.AnalysisCircuitDropdown.Value));
                end
            catch
            end
            if isempty(strtrim(cid))
                cid = char(app.State.selectedCircuitId);
            end
            if isempty(strtrim(cid))
                uialert(app.UIFigure, ...
                    'Pick a circuit from the dropdown before opening Circuit Cutting.', ...
                    'Circuit Cutting', 'Icon', 'warning');
                return;
            end

            % Resolve display name from the dropdown so the activity log
            % and the target screen's status line stay consistent with
            % what the user just saw on Analysis.
            name = '';
            try
                items = app.AnalysisCircuitDropdown.Items;
                ids   = app.AnalysisCircuitDropdown.ItemsData;
                k = find(strcmp(ids, cid), 1);
                if ~isempty(k); name = items{k}; end
            catch
            end

            app.State.selectedCircuitId = string(cid);
            if ~isempty(name)
                app.State.selectedCircuitName = string(name);
            end
            app.logEvent('UI', sprintf( ...
                'Analysis → Circuit Cutting (circuit: %s)', ...
                char(app.State.selectedCircuitName)));

            app.onSelectSection('Circuit Cutting');

            % Nudge the Cutting screen's dropdown if it is already loaded;
            % otherwise loadCircuits / onEnter will pick the cached
            % selectedCircuitId on first refresh.
            try
                if ~isempty(app.CuttingCircuitDropdown) ...
                        && isvalid(app.CuttingCircuitDropdown) ...
                        && iscell(app.CuttingCircuitDropdown.ItemsData) ...
                        && any(strcmp(app.CuttingCircuitDropdown.ItemsData, cid))
                    app.CuttingCircuitDropdown.Value = cid;
                    app.CircuitCuttingVm.onCircuitChanged(cid);
                end
            catch ME
                Logger.debug('AnalysisViewModel', ...
                    'Cutting bridge nudge: %s', ME.message);
            end
        end

        function onVisualizeSimilarity(obj)
            app = obj.App;
            try
                tData = app.SimilarityTable.Data;
                if isempty(tData)
                    uialert(app.UIFigure, Labels.get('error_run_analysis_first', 'Run analysis first to get similarity results.'), ...
                        'No Data', 'Icon', 'info');
                    return;
                end
                n = size(tData, 1);
                names = cell(n, 1);
                sims  = zeros(n, 1);
                cats  = cell(n, 1);
                notes = cell(n, 1);
                for i = 1:n
                    names{i} = char(string(tData{i, 1}));
                    sims(i)  = double(tData{i, 2});
                    cats{i}  = char(string(tData{i, 3}));
                    if size(tData, 2) >= 4
                        notes{i} = char(string(tData{i, 4}));
                    else
                        notes{i} = '';
                    end
                end

                % Color palette by category
                uniqueCats = unique(cats, 'stable');
                palette = [
                    0.15 0.46 0.84;   % blue
                    0.09 0.55 0.36;   % green
                    0.85 0.47 0.12;   % orange
                    0.56 0.22 0.72;   % purple
                    0.82 0.20 0.20;   % red
                    0.20 0.60 0.76;   % teal
                    0.55 0.55 0.55    % gray
                ];
                colors = zeros(n, 3);
                catIdx = zeros(n, 1);
                for i = 1:n
                    ci = find(strcmp(uniqueCats, cats{i}), 1);
                    catIdx(i) = ci;
                    colors(i, :) = palette(mod(ci-1, size(palette,1)) + 1, :);
                end

                % Escape underscores for display (prevent TeX subscripts)
                dispNames = strrep(names, '_', ' ');

                % Create popup dialog — large, centered
                figPos = app.UIFigure.Position;
                dlgW = 1100; dlgH = 650;
                dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
                dlgY = figPos(2) + (figPos(4) - dlgH) / 2;
                dlg = uifigure('Name', 'QTAUBench Similarity Visualization', ...
                    'Position', [dlgX dlgY dlgW dlgH], ...
                    'Resize', 'on', 'Color', Theme.COLOR_BG);
                Theme.applyFigureMode(dlg, Theme.activeName());

                rootGrid = uigridlayout(dlg, [3 1]);
                rootGrid.RowHeight = {'1x', 1, 40};
                rootGrid.Padding = [0 0 0 0]; rootGrid.RowSpacing = 0;
                rootGrid.BackgroundColor = Theme.COLOR_BG;

                % ── Tab group ───────────────────────────────────────────────
                tg = uitabgroup(rootGrid);
                tg.Layout.Row = 1; tg.Layout.Column = 1;

                % ══════════════════════════════════════════════════════════════
                % Tab 1: QTAUBench Similarity Visualization
                %   Single focused ranked-bar chart with auto-scaled X axis
                %   (tight similarity bands of 97–98% become visually
                %   differentiated) + a Match Profile side panel that
                %   surfaces the current circuit, category breakdown, and
                %   a calibrated interpretation of the top match.
                % ══════════════════════════════════════════════════════════════
                tab1 = uitab(tg, 'Title', 'QTAUBench Similarity Visualization');
                tab1.BackgroundColor = Theme.COLOR_CARD;

                dg = uigridlayout(tab1, [2 2]);
                dg.RowHeight = {40, '1x'};
                dg.ColumnWidth = {'2x', '1x'};
                dg.Padding = [18 14 18 12]; dg.RowSpacing = 8; dg.ColumnSpacing = 16;
                dg.BackgroundColor = Theme.COLOR_CARD;

                % ── Header: current circuit + headline summary ──────────────
                curCircName = char(app.State.selectedCircuitName);
                if isempty(curCircName); curCircName = 'current circuit'; end
                [topSim, topIdx] = max(sims);
                headerLbl = uilabel(dg, ...
                    'Text', sprintf(['Circuit:  %s      ' ...
                                     'Closest of %d matches:  %s  (%.1f%%)'], ...
                                    curCircName, n, dispNames{topIdx}, topSim*100), ...
                    'FontSize', 13, 'FontWeight', 'bold', ...
                    'FontColor', Theme.COLOR_HEADING, ...
                    'VerticalAlignment', 'center', ...
                    'Interpreter', 'none');
                headerLbl.Layout.Row = 1; headerLbl.Layout.Column = [1 2];

                % ── Left: Ranked similarity bars (auto-scaled X) ────────────
                ax1 = uiaxes(dg);
                ax1.Layout.Row = 2; ax1.Layout.Column = 1;

                % Sort worst→best so highest bar sits at the TOP in barh
                [sortedSims, si] = sort(sims, 'ascend');
                sortedNames  = dispNames(si);
                sortedColors = colors(si, :);
                sortedCats   = cats(si);

                % Auto-scale X axis so tight bands (e.g. 97–98%) are visible.
                % Anchor right edge at 1.0 so "room to grow" is meaningful.
                simSpread = max(sims) - min(sims);
                if simSpread < 0.02
                    xMin = max(0, min(sims) - 0.05);
                elseif simSpread < 0.10
                    xMin = max(0, min(sims) - 0.03);
                else
                    xMin = max(0, min(sims) - simSpread * 0.15);
                end
                xMax = 1.0;
                xLabelPad = (xMax - xMin) * 0.012;

                hold(ax1, 'on');
                for i = 1:n
                    isTop = (si(i) == topIdx);
                    faceAlpha = 0.92;
                    edgeClr   = 'none';
                    edgeWidth = 0.1;
                    if isTop
                        edgeClr   = [0.12 0.14 0.20];
                        edgeWidth = 1.5;
                    end
                    barh(ax1, i, sortedSims(i), ...
                        'FaceColor', sortedColors(i,:), ...
                        'FaceAlpha', faceAlpha, ...
                        'EdgeColor', edgeClr, 'LineWidth', edgeWidth, ...
                        'BarWidth', 0.62);
                    % Similarity % label at end of bar
                    text(ax1, sortedSims(i) + xLabelPad, i, ...
                        sprintf('%.1f%%', sortedSims(i)*100), ...
                        'FontSize', 11, 'FontWeight', 'bold', ...
                        'VerticalAlignment', 'middle', ...
                        'Color', [0.18 0.22 0.30], 'Interpreter', 'none');
                    % Category badge just past the percent label
                    if ~isempty(sortedCats{i})
                        catLabel = sortedCats{i};
                        if isTop; catLabel = ['★ ' catLabel]; end %#ok<AGROW>
                        text(ax1, xMin + (xMax-xMin)*0.012, i + 0.33, ...
                            catLabel, ...
                            'FontSize', 9, 'FontAngle', 'italic', ...
                            'Color', sortedColors(i,:) * 0.55 + [0.3 0.3 0.3], ...
                            'VerticalAlignment', 'middle', ...
                            'Interpreter', 'none');
                    end
                end
                hold(ax1, 'off');
                ax1.YTick = 1:n; ax1.YTickLabel = sortedNames;
                ax1.TickLabelInterpreter = 'none';
                ax1.YLim = [0.3, n + 0.7];
                ax1.XLim = [xMin, xMax + (xMax - xMin) * 0.09];
                % Dynamic tick density + label precision based on zoom level
                tickStep = AnalysisViewModel.niceTickStep(xMax - xMin, 6);
                ax1.XTick = xMin:tickStep:xMax;
                if tickStep < 0.01
                    labelFmt = '%.1f%%';
                else
                    labelFmt = '%.0f%%';
                end
                ax1.XTickLabel = arrayfun(@(v) sprintf(labelFmt, v*100), ...
                    ax1.XTick, 'UniformOutput', false);
                xlabel(ax1, sprintf('Similarity  (zoomed to %.0f%%–100%% to show differentiation)', xMin*100));
                title(ax1, 'Benchmark Similarity Ranking', 'FontSize', 14, 'FontWeight', 'bold');
                ax1.Box = 'on'; ax1.FontSize = 11;
                ax1.XGrid = 'on'; ax1.YGrid = 'off';
                ax1.GridColor = [0.85 0.88 0.92]; ax1.GridAlpha = 0.8;
                ax1.XColor = [0.35 0.42 0.52]; ax1.YColor = [0.22 0.28 0.40];

                % ── Right: Match Profile side panel ────────────────────────
                profilePanel = uipanel(dg, 'Title', 'Match Profile', ...
                    'FontWeight', 'bold', 'BackgroundColor', Theme.COLOR_ACCENT_BG, ...
                    'ForegroundColor', [0.20 0.28 0.45]);
                profilePanel.Layout.Row = 2; profilePanel.Layout.Column = 2;

                ppg = uigridlayout(profilePanel, [1 1]);
                ppg.Padding = [12 10 12 10];
                ppg.BackgroundColor = Theme.COLOR_ACCENT_BG;

                profileArea = uitextarea(ppg, 'Editable', 'off');
                profileArea.FontSize = 12;
                profileArea.FontColor = Theme.COLOR_HEADING;
                profileArea.Value = AnalysisViewModel.buildMatchProfileText( ...
                    curCircName, dispNames, sims, cats, notes, uniqueCats, topIdx);

                % ══════════════════════════════════════════════════════════════
                % Tab 2: Circuit Diagram
                % ══════════════════════════════════════════════════════════════
                tab2 = uitab(tg, 'Title', 'Circuit Diagram');
                tab2.BackgroundColor = Theme.COLOR_CARD;

                tab2Grid = uigridlayout(tab2, [1 1]);
                tab2Grid.Padding = [16 14 16 10]; tab2Grid.BackgroundColor = Theme.COLOR_CARD;
                diagramHtml = uihtml(tab2Grid);
                diagramHtml.Layout.Row = 1; diagramHtml.Layout.Column = 1;

                % Fetch circuit diagram — prefer server-rendered SVG (Qiskit, all gates)
                % with client-side renderSvg as fallback
                svgContent = '<p style="color:#888;font-family:sans-serif">Loading circuit diagram...</p>';
                diagramHtml.HTMLSource = CircuitDiagram.buildStatsHtml({}, svgContent);
                try
                    if app.State.hasCircuit() && app.State.isAuthenticated()
                        cid = app.State.selectedCircuitId;
                        tok = app.State.authToken;
                        % 1) Try server-side Qiskit preview (complete, all gates)
                        serverOk = false;
                        try
                            prevData = app.CircuitSvc.previewCircuit(cid, tok);
                            serverSvg = char(JsonHelper.pick(prevData, {'svg'}));
                            if ~isempty(serverSvg) && startsWith(strtrim(serverSvg), '<svg')
                                svgContent = serverSvg;
                                serverOk = true;
                            end
                        catch ME
                            Logger.debug('AnalysisViewModel', 'loadDiagram serverPreview: %s', ME.message);
                        end
                        % 2) Fallback: client-side rendering (truncated for large circuits)
                        if ~serverOk
                            circData = app.CircuitSvc.getCircuit(cid, tok);
                            qasmText = char(JsonHelper.pick(circData, {'content','raw_content','qasm_content','source'}));
                            if ~isempty(qasmText)
                                svgContent = CircuitDiagram.renderSvg(qasmText);
                            else
                                svgContent = '<p style="color:#888;font-family:sans-serif">No circuit content available.</p>';
                            end
                        end
                    else
                        svgContent = '<p style="color:#888;font-family:sans-serif">No circuit selected.</p>';
                    end
                catch ME
                    svgContent = sprintf('<p style="color:#DC2626;font-family:sans-serif">Failed to load diagram: %s</p>', CircuitDiagram.escapeHtml(ME.message));
                end
                diagramHtml.HTMLSource = CircuitDiagram.buildStatsHtml({}, svgContent);

                % ── Separator line ─────────────────────────────────────────
                sep = uipanel(rootGrid, 'Title', '', 'BorderType', 'none');
                sep.Layout.Row = 2; sep.Layout.Column = 1;
                sep.BackgroundColor = Theme.COLOR_DIVIDER;

                % ── Close button (right-aligned) ───────────────────────────
                btnGrid = uigridlayout(rootGrid, [1 2]);
                btnGrid.Layout.Row = 3; btnGrid.Layout.Column = 1;
                btnGrid.ColumnWidth = {'1x', 140};
                btnGrid.Padding = [16 4 16 4]; btnGrid.BackgroundColor = Theme.COLOR_CARD;
                closeBtn = uibutton(btnGrid, 'Text', 'Close', ...
                    'FontSize', 13, ...
                    'ButtonPushedFcn', @(~,~) delete(dlg));
                closeBtn.Layout.Row = 1; closeBtn.Layout.Column = 2;
                app.State.logActivity('Visualize similarity', 'Success');
            catch ME
                Logger.warn('AnalysisViewModel', 'onVisualizeSimilarity failed: %s', ME.message);
            end
        end

        function renderComplexityLandscape(obj, data)
            % Public entry point for the Circuit Complexity Landscape chart.
            % Delegates to the internal renderer; exposed for unit tests and
            % for any future caller that wants to repaint without going
            % through the full analyze pipeline.
            obj.buildQVHeatmap(data);
        end

        % ── Quantum Error Mitigation Analysis popup (Phase 6.x) ───────────
        %   Reads /api/mitigation/levels + /api/mitigation/estimate +
        %   cached QAE result + /api/cutting/analyze and renders the
        %   results into the dialog built by
        %   DialogBuilder.buildErrorMitigationDialog.  No async-job
        %   submission; every endpoint returns synchronously.

        function onOpenEmDialog(obj)
            app = obj.App;
            if ~isempty(app.EmDialog) && isvalid(app.EmDialog)
                figure(app.EmDialog); return;
            end
            DialogBuilder.buildErrorMitigationDialog(app);
            obj.loadEmBackendsForDialog(app);
            obj.loadEmInitialData(app);
        end

        function onCloseEmDialog(obj)
            app = obj.App;
            try
                if ~isempty(app.EmDialog) && isvalid(app.EmDialog)
                    delete(app.EmDialog);
                end
            catch
            end
            app.EmDialog = [];
        end

        function onEmFormChanged(obj)
            % Form-tweak handler -- refresh /api/mitigation/estimate sweep
            % and re-render the technique table + cost summary.
            obj.refreshEmEstimateBundle(obj.App);
        end

        function onEmRefreshEstimate(obj)
            % Explicit "Estimate" button click: same as form-change but
            % also re-renders the gamma-vs-depth and cutting overhead
            % charts so live backend choice is reflected everywhere.
            app = obj.App;
            obj.refreshEmEstimateBundle(app);
            obj.renderEmKpis(app);
            obj.renderEmGammaDepthCurve(app);
            obj.renderEmOverheadCutsCurve(app);
        end

        function onEmApplyToBenchmark(obj)
            app = obj.App;
            if isempty(app.EmEstimateBundle)
                uialert(AnalysisViewModel.emAlertParent(app), ...
                    'Run Estimate first to populate the technique comparison.', ...
                    'Apply', 'Icon', 'warning');
                return;
            end
            pick = AnalysisViewModel.bestRecommendation(app.EmEstimateBundle);
            if isempty(pick)
                uialert(AnalysisViewModel.emAlertParent(app), ...
                    'No recommendation available - pick a different backend.', ...
                    'Apply', 'Icon', 'warning');
                return;
            end
            targetValue = AnalysisViewModel.mapEmTechniqueToBenchmark(pick.levelId);
            try
                if ~isempty(app.BenchmarkMitigationDropdown) && ...
                        isvalid(app.BenchmarkMitigationDropdown)
                    items = app.BenchmarkMitigationDropdown.ItemsData;
                    idx = find(strcmp(items, targetValue), 1);
                    if ~isempty(idx)
                        app.BenchmarkMitigationDropdown.Value = items{idx};
                    end
                end
            catch
            end
            obj.onCloseEmDialog();
            app.onSelectSection('Benchmark');
            app.logEvent('UI', sprintf( ...
                'Error Mitigation -> Benchmark (level=%d, target=%s)', ...
                pick.levelId, targetValue));
        end

        function onEmExportJson(obj)
            app = obj.App;
            alertParent = AnalysisViewModel.emAlertParent(app);
            if isempty(app.EmEstimateBundle)
                uialert(alertParent, ...
                    'Run Estimate first to produce the bundle.', ...
                    'Export JSON', 'Icon', 'warning');
                return;
            end
            out = struct();
            out.circuit_id = char(app.State.selectedCircuitId);
            out.circuit_name = char(app.State.selectedCircuitName);
            try; out.backend = char(app.EmBackendDropdown.Value); catch; out.backend = ''; end
            out.bundle = app.EmEstimateBundle;
            out.qae_cached = ~isempty(app.EmQaeCached);
            out.cutting_cached = ~isempty(app.EmCuttingCached);
            try
                payload = jsonencode(out, 'PrettyPrint', true);
            catch
                payload = jsonencode(out);
            end
            safeName = regexprep(char(app.State.selectedCircuitName), '[^A-Za-z0-9_\-]', '_');
            if isempty(safeName); safeName = 'circuit'; end
            stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmm'));
            defaultName = sprintf('EmAnalysis_%s_%s.json', safeName, stamp);
            [fileName, pathName] = uiputfile( ...
                {'*.json', 'JSON (*.json)'}, ...
                'Export Error Mitigation Analysis', defaultName);
            if isequal(fileName, 0); return; end
            target = fullfile(pathName, fileName);
            try
                fid = fopen(target, 'w');
                fprintf(fid, '%s', payload);
                fclose(fid);
                uialert(alertParent, ...
                    sprintf('Exported to:\n%s', target), ...
                    'Export JSON', 'Icon', 'success');
                app.logEvent('API', sprintf('EM bundle exported to %s', target));
            catch ME
                uialert(alertParent, ME.message, 'Export JSON', 'Icon', 'error');
            end
        end

        function onEmGenerateReport(obj)
            app = obj.App;
            alertParent = AnalysisViewModel.emAlertParent(app);
            if ~app.State.isAuthenticated()
                uialert(alertParent, Labels.get('error_not_authenticated'), ...
                    'Generate Report', 'Icon', 'warning'); return;
            end
            if ~app.State.hasCircuit()
                uialert(alertParent, ...
                    'Select a circuit before generating the report.', ...
                    'Generate Report', 'Icon', 'warning'); return;
            end
            cid = app.State.selectedCircuitId;
            app.showLoading('Generating Error Mitigation report...');
            sections = { ...
                'executive_summary', 'circuit_summary', 'feature_analysis', ...
                'error_mitigation', 'key_insights'};
            reportTitle = sprintf('Quantum Error Mitigation Report - %s', ...
                char(app.State.selectedCircuitName));
            reportSvc = app.ReportSvc;
            token     = app.State.authToken;
            AsyncRunner.run( ...
                @() reportSvc.generateReport(reportTitle, 'technical', 'pdf', ...
                                             cid, '', '', sections, token), ...
                @(data) obj.onQmcReportGenerated(app, data), ...
                @(ME)   obj.onQmcReportError(app, ME));
        end
    end

    methods (Static, Access = private)

        function step = niceTickStep(range, targetTicks)
            % Pick a human-readable tick step for the given numeric range.
            if range <= 0 || ~isfinite(range)
                step = 0.1; return;
            end
            raw = range / max(1, targetTicks);
            mag = 10^floor(log10(raw));
            normalized = raw / mag;
            if     normalized < 1.5; step = 1 * mag;
            elseif normalized < 3.5; step = 2 * mag;
            elseif normalized < 7.5; step = 5 * mag;
            else;                    step = 10 * mag;
            end
        end

        function lines = buildMatchProfileText(curName, dispNames, sims, cats, notes, uniqueCats, topIdx)
            % Build the Match Profile sidebar — derived from real
            % per-circuit analysis data so it genuinely changes as the
            % user analyzes different circuits.
            n = numel(sims);
            topSim  = sims(topIdx);
            topName = dispNames{topIdx};
            topCat  = cats{topIdx};
            meanSim = mean(sims);
            spread  = max(sims) - min(sims);

            % Calibrated interpretation based on top similarity
            if topSim > 0.95
                interp = 'Strong structural match — a well-characterised benchmark class.';
            elseif topSim > 0.85
                interp = 'Good match — similar structure to a known benchmark.';
            elseif topSim > 0.70
                interp = 'Moderate match — broadly comparable to QTAUBench peers.';
            else
                interp = 'Weak match — novel structure with limited benchmark reference.';
            end

            lines = {};
            lines{end+1} = sprintf('Circuit');
            lines{end+1} = sprintf('  %s', curName);
            lines{end+1} = '';
            lines{end+1} = sprintf('Top match');
            lines{end+1} = sprintf('  %s', topName);
            lines{end+1} = sprintf('  similarity: %.1f%%', topSim*100);
            lines{end+1} = sprintf('  category:   %s', topCat);
            lines{end+1} = '';
            lines{end+1} = interp;
            lines{end+1} = '';
            lines{end+1} = sprintf('All %d matches', n);
            lines{end+1} = sprintf('  mean similarity: %.1f%%', meanSim*100);
            lines{end+1} = sprintf('  spread:          %.1f pp', spread*100);
            lines{end+1} = '';
            lines{end+1} = 'Category breakdown';
            for ci = 1:numel(uniqueCats)
                mask = strcmp(cats, uniqueCats{ci});
                k    = sum(mask);
                catAvg = mean(sims(mask));
                lines{end+1} = sprintf('  %s — %d (avg %.1f%%)', ...
                    uniqueCats{ci}, k, catAvg*100); %#ok<AGROW>
            end

            % Top match notes if present
            tnote = '';
            if numel(notes) >= topIdx
                tnote = strtrim(notes{topIdx});
            end
            if ~isempty(tnote)
                lines{end+1} = '';
                lines{end+1} = 'Notes on top match';
                % Split long notes into wrapped lines (soft 32-char wrap)
                wrapped = AnalysisViewModel.softWrap(tnote, 32);
                for wi = 1:numel(wrapped)
                    lines{end+1} = sprintf('  %s', wrapped{wi}); %#ok<AGROW>
                end
            end
        end

        function parts = softWrap(text, width)
            % Break a string into whitespace-bounded lines no wider than
            % `width` chars (best effort; doesn't split words).
            parts = {};
            if isempty(text); return; end
            words = strsplit(char(text));
            cur = '';
            for wi = 1:numel(words)
                w = words{wi};
                if isempty(cur)
                    cur = w;
                elseif length(cur) + 1 + length(w) <= width
                    cur = [cur ' ' w]; %#ok<AGROW>
                else
                    parts{end+1} = cur; %#ok<AGROW>
                    cur = w;
                end
            end
            if ~isempty(cur); parts{end+1} = cur; end
        end

        function data = fetchBackendList(backendSvc, circSvc, cid, token)
            % 3-tier fallback for populating the QMC Backend dropdown:
            %   1. list scoped to the currently-selected circuit
            %   2. list scoped to the first circuit in the project
            %   3. basic unscoped list
            if ~isempty(cid) && strlength(string(cid)) > 0
                try
                    data = backendSvc.listBackends(token, cid);
                    if AnalysisViewModel.hasBackends(data); return; end
                catch
                end
            end
            try
                circList = circSvc.listCircuits(token);
                items = JsonHelper.extractList(circList, 'circuits');
                if ~isempty(items)
                    fallbackCid = char(JsonHelper.pick(items(1), {'circuit_id','id'}));
                    if ~isempty(fallbackCid) && strlength(string(fallbackCid)) > 0
                        data = backendSvc.listBackends(token, fallbackCid);
                        if AnalysisViewModel.hasBackends(data); return; end
                    end
                end
            catch
            end
            data = backendSvc.listBackends(token, '');
        end

        function tf = hasBackends(data)
            tf = isstruct(data) && isfield(data, 'backends') && ~isempty(data.backends);
        end

        function s = prettyJobStatus(status, serverMessage)
            % Convert a raw status+message into something user-friendly
            % for the loading overlay.
            if ~isempty(serverMessage)
                s = serverMessage;
                return;
            end
            switch lower(char(status))
                case 'queued';    s = 'Queued — waiting for backend';
                case 'running';   s = 'Running Quantum Monte Carlo simulation';
                case 'completed'; s = 'Completed';
                case 'failed';    s = 'Failed';
                case 'cancelled'; s = 'Cancelled';
                otherwise;        s = char(status);
            end
        end

        function toggleIbmLogButton(app, data)
            % Enable the Download IBM Log button only when the cached
            % QMC result carries a non-empty runtime_job_id (set by the
            % server when execution_mode='runtime'). Statevector runs
            % leave the field empty → keep the button disabled.
            try
                if ~isprop(app, 'QmcDownloadLogButton') || ...
                        isempty(app.QmcDownloadLogButton) || ...
                        ~isvalid(app.QmcDownloadLogButton)
                    return;
                end
                jobId = '';
                if ~isempty(data)
                    jobId = char(JsonHelper.pick(data, {'runtime_job_id'}, ''));
                end
                if ~isempty(jobId)
                    app.QmcDownloadLogButton.Enable = 'on';
                else
                    app.QmcDownloadLogButton.Enable = 'off';
                end
            catch
            end
        end

        function parent = qmcAlertParent(app)
            % Pick the right uialert parent so the alert draws on top
            % of the Quantum Monte Carlo modal popup when it is open —
            % parenting to app.UIFigure leaves the alert behind the
            % popup because the popup is its own uifigure window.
            parent = app.UIFigure;
            try
                if ~isempty(app.QmcDialog) && isvalid(app.QmcDialog) ...
                        && strcmp(app.QmcDialog.Visible, 'on')
                    parent = app.QmcDialog;
                end
            catch
            end
        end

        function savedPath = pollAndDownloadReport(reportSvc, reportId, token)
            % Poll GET /reports/{id} until status='ready' (or 'completed'),
            % then stream the file to a temp path and return it. Caller
            % can uiputfile and copy to the user's chosen destination.
            deadline = tic;
            maxSeconds = 60;
            pause_s = 0.75;
            status = '';
            fmt = '';
            while toc(deadline) < maxSeconds
                meta = reportSvc.getReport(reportId, token);
                status = lower(char(JsonHelper.pick(meta, {'status'}, '')));
                fmt    = lower(char(JsonHelper.pick(meta, {'format'}, 'pdf')));
                if any(strcmp(status, {'ready', 'completed', 'success', 'done'}))
                    break;
                elseif any(strcmp(status, {'failed', 'error'}))
                    msg = char(JsonHelper.pick(meta, {'message','error'}, ...
                        'Report generation failed on the server.'));
                    error('QTAU:ReportFailed', '%s', msg);
                end
                pause(pause_s);
            end
            if ~any(strcmp(status, {'ready', 'completed', 'success', 'done'}))
                error('QTAU:ReportTimeout', ...
                    'Report did not reach ready state within %d seconds.', maxSeconds);
            end
            if isempty(fmt); fmt = 'pdf'; end
            ext = ['.' fmt];
            if strcmp(ext, '.') || strcmp(ext, '..'); ext = '.pdf'; end
            savedPath = fullfile(tempdir, sprintf('qmc_report_%s%s', reportId, ext));
            reportSvc.downloadReportFile(reportId, token, savedPath);
        end

        % ── Quantum Error Mitigation helpers (Phase 6.x) ────────────────
        function parent = emAlertParent(app)
            % Pick the right uialert parent so the alert draws on top of
            % the Quantum Error Mitigation modal popup when it is open.
            parent = app.UIFigure;
            try
                if ~isempty(app.EmDialog) && isvalid(app.EmDialog) ...
                        && strcmp(app.EmDialog.Visible, 'on')
                    parent = app.EmDialog;
                end
            catch
            end
        end

        function eplg = extractEplg(cal)
            % Try multiple field names; fall back to avg 2Q gate error.
            eplg = JsonHelper.pickNumeric(cal, 'eplg', NaN);
            if ~isnan(eplg) && eplg > 0; return; end
            eplg = JsonHelper.pickNumeric(cal, 'epc', NaN);
            if ~isnan(eplg) && eplg > 0; return; end
            eplg = JsonHelper.pickNumeric(cal, 'avg_2q_gate_error', NaN);
            if ~isnan(eplg) && eplg > 0; return; end
            eplg = JsonHelper.pickNumeric(cal, 'two_q_error_avg', NaN);
        end

        function gb = computeGammaBar(eplg)
            % gammabar = (1 - EPLG)^(-2). Returns NaN for invalid input.
            if isnan(eplg) || eplg <= 0 || eplg >= 1
                gb = NaN; return;
            end
            gb = (1 - eplg)^(-2);
        end

        function ovh = computeGammaBarOverhead(gammaBar, depth)
            % PEC sampling overhead = gammabar^depth.  Capped at 1e30
            % for plotting stability on log axes.
            if isnan(gammaBar) || isnan(depth) || depth <= 0
                ovh = NaN; return;
            end
            ovh = gammaBar^depth;
            if isinf(ovh) || ovh > 1e30; ovh = 1e30; end
        end

        function q = pickQubits(meta)
            q = JsonHelper.pickNumeric(meta, 'num_qubits', NaN);
            if isnan(q); q = JsonHelper.pickNumeric(meta, 'qubits', NaN); end
            if isnan(q); q = JsonHelper.pickNumeric(meta, 'width', NaN); end
        end

        function d = pickDepth(meta)
            d = JsonHelper.pickNumeric(meta, 'depth', NaN);
            if isnan(d); d = JsonHelper.pickNumeric(meta, 'circuit_depth', NaN); end
        end

        function n2q = pickTwoQGates(meta)
            n2q = JsonHelper.pickNumeric(meta, 'num_2q_gates', NaN);
            if isnan(n2q); n2q = JsonHelper.pickNumeric(meta, 'two_qubit_gates', NaN); end
            if isnan(n2q); n2q = JsonHelper.pickNumeric(meta, 'cnot_count', NaN); end
        end

        function s = fmtIntKpi(v)
            if isnan(v); s = '-'; else; s = sprintf('%d', round(v)); end
        end

        function biasReduction = estimateBiasReduction(levelId)
            % Heuristic mapping from MitigationService level id to a
            % rough bias-reduction factor.  Operator-facing only -- the
            % UI labels these as "estimated".
            switch double(levelId)
                case 0;  biasReduction = 1.0;   % Raw
                case 1;  biasReduction = 1.6;   % Standard
                case 2;  biasReduction = 2.8;   % Aggressive
                case 3;  biasReduction = 2.5;   % Custom (depends on options)
                case 4;  biasReduction = 3.5;   % TEM
                otherwise; biasReduction = 1.0;
            end
        end

        function pick = bestRecommendation(bundle)
            % Heuristic ranking: maximise biasReduction / log(1+shotMul).
            pick = [];
            bestScore = -Inf;
            for i = 1:numel(bundle)
                b = bundle{i};
                if isempty(b.estimate); continue; end
                cost = JsonHelper.pick(b.estimate, {'cost'}, struct());
                shotMul = JsonHelper.pickNumeric(cost, 'shot_multiplier', 1.0);
                bias = AnalysisViewModel.estimateBiasReduction(b.levelId);
                score = bias / log(1 + max(shotMul, 1.0));
                if score > bestScore
                    bestScore = score; pick = b;
                end
            end
        end

        function targetValue = mapEmTechniqueToBenchmark(levelId)
            % Map MitigationService level id to BenchmarkScreen
            % mitigation dropdown ItemsData.
            switch double(levelId)
                case 0;  targetValue = 'none';
                case 1;  targetValue = 'measurement_mitigation';
                case 2;  targetValue = 'zero_noise_extrapolation';
                case 3;  targetValue = 'zero_noise_extrapolation';
                case 4;  targetValue = 'readout_calibration';
                otherwise; targetValue = 'none';
            end
        end

        function factors = parseZneFactors(s)
            % Parse "1.0, 3.0, 5.0" -> [1.0 3.0 5.0]; defaults on parse fail.
            factors = [1.0 3.0 5.0];
            try
                parts = strsplit(strtrim(char(s)), ',');
                out = [];
                for i = 1:numel(parts)
                    v = str2double(strtrim(parts{i}));
                    if ~isnan(v) && v > 0
                        out(end+1) = v; %#ok<AGROW>
                    end
                end
                if ~isempty(out); factors = out; end
            catch
            end
        end

        function opts = currentEmOptions(app)
            % Snapshot the form's advanced controls into a struct that
            % matches the MitigationPlan options schema.
            opts = struct();
            try
                opts.zne_noise_factors = AnalysisViewModel.parseZneFactors( ...
                    app.EmZneFactorsField.Value);
                opts.zne_extrapolator  = char(app.EmExtrapolatorDropdown.Value);
                opts.dd_sequence       = char(app.EmDdSequenceDropdown.Value);
                opts.twirling_gates    = logical(app.EmTwirlGatesCheckbox.Value);
                opts.twirling_measure  = logical(app.EmTwirlMeasureCheckbox.Value);
                opts.tem_enable        = logical(app.EmTemCheckbox.Value);
                opts.also_run_raw      = logical(app.EmAlsoRunRawCheckbox.Value);
            catch
            end
        end

        function [labels, vals] = pickTopBitstrings(counts, n)
            % Convert a struct of bitstring->count into the top-n
            % normalised probabilities, ordered by descending magnitude.
            labels = {}; vals = [];
            if ~isstruct(counts); return; end
            f = fieldnames(counts);
            if isempty(f); return; end
            nums = zeros(1, numel(f));
            for i = 1:numel(f)
                nums(i) = double(counts.(f{i}));
            end
            [nums, idx] = sort(nums, 'descend');
            keys = f(idx);
            take = min(n, numel(nums));
            total = sum(nums);
            if total <= 0; return; end
            labels = cell(1, take);
            vals = zeros(1, take);
            for i = 1:take
                labels{i} = keys{i};
                vals(i)   = nums(i) / total;
            end
        end

    end

    methods (Access = private)
        function onQmcComplete(obj, app, data)
            app.hideLoading();
            app.QmcLastResult = data;
            obj.renderQmcResult(app, data);
            AnalysisViewModel.toggleIbmLogButton(app, data);
            app.logEvent('API', sprintf('QMC complete — amp=%.4f speedup=%.1fx', ...
                JsonHelper.pickNumeric(data, 'amplitude_estimate', 0.0), ...
                JsonHelper.pickNumeric(data, 'quadratic_speedup', 1.0)));
            app.State.logActivity('Quantum Monte Carlo simulation', 'Success');
        end

        function startQmcPoll(obj, app, jobId)
            % Kick off a 3s MATLAB timer that polls GET /api/qae/jobs/{id}
            % until the job reaches a terminal state. UI work happens on
            % the main thread so we don't need AsyncRunner here — each
            % tick does one fast HTTP GET.
            obj.stopQmcPoll(app);
            app.showLoading('Queued — waiting for backend...');
            t = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period',        3.0, ...
                'StartDelay',    0.0, ...
                'BusyMode',      'drop', ...
                'Name',          ['QmcPoll-' char(jobId)], ...
                'TimerFcn',      @(src,~) obj.onQmcPollTick(app, jobId, src));
            app.QmcPollTimer = t;
            start(t);
        end

        function stopQmcPoll(~, app)
            try
                if ~isempty(app.QmcPollTimer) && isvalid(app.QmcPollTimer)
                    stop(app.QmcPollTimer);
                    delete(app.QmcPollTimer);
                end
            catch
            end
            app.QmcPollTimer = [];
        end

        function onQmcPollTick(obj, app, jobId, timerObj)
            % One poll iteration. Swallows transient HTTP errors and
            % lets the timer try again on the next tick.
            if isempty(app.QmcActiveJobId) || ~strcmp(app.QmcActiveJobId, jobId)
                % Job was superseded or cancelled; stop this timer.
                try; stop(timerObj); delete(timerObj); catch; end
                return;
            end
            try
                state = app.QmcSvc.getAnalyzeJob(jobId, app.State.authToken);
            catch ME
                Logger.debug('AnalysisViewModel', 'QMC poll transient: %s', ME.message);
                return;
            end
            status = lower(char(JsonHelper.pick(state, {'status'}, 'queued')));
            progress = JsonHelper.pickNumeric(state, 'progress_pct', 0);
            msg = char(JsonHelper.pick(state, {'message'}, ''));
            % Refresh the loading overlay with the latest step.
            displayMsg = sprintf('%s (%d%%)', AnalysisViewModel.prettyJobStatus(status, msg), round(progress));
            try; app.showLoading(displayMsg); catch; end

            switch status
                case {'completed'}
                    obj.stopQmcPoll(app);
                    app.QmcActiveJobId = '';
                    result = JsonHelper.pick(state, {'result'}, []);
                    if isempty(result)
                        obj.onQmcError(app, MException('QTAU:QmcEmpty', ...
                            'Job completed but server returned no result payload.'));
                        return;
                    end
                    obj.onQmcComplete(app, result);
                case {'failed'}
                    obj.stopQmcPoll(app);
                    app.QmcActiveJobId = '';
                    errMsg = char(JsonHelper.pick(state, {'error'}, ''));
                    if isempty(errMsg); errMsg = msg; end
                    if isempty(errMsg); errMsg = 'QMC job failed on the server.'; end
                    obj.onQmcError(app, MException('QTAU:QmcFailed', '%s', errMsg));
                case {'cancelled'}
                    obj.stopQmcPoll(app);
                    app.QmcActiveJobId = '';
                    app.hideLoading();
                    uialert(AnalysisViewModel.qmcAlertParent(app), ...
                        'Quantum Monte Carlo job was cancelled.', ...
                        'Quantum Monte Carlo', 'Icon', 'info');
                otherwise
                    % queued / running — keep polling.
            end
        end

        function onIbmLogDownloaded(~, app, tmpPath, runtimeJobId, circName, fmt)
            app.hideLoading();
            alertParent = AnalysisViewModel.qmcAlertParent(app);
            if isempty(tmpPath) || exist(tmpPath, 'file') ~= 2
                uialert(alertParent, 'IBM log download finished but the local file is missing.', ...
                    'Download IBM Log', 'Icon', 'error');
                return;
            end
            if isempty(fmt); fmt = 'jsonl'; end
            ext = ['.' char(fmt)];
            safeName = regexprep(char(circName), '[^A-Za-z0-9_\-]', '_');
            if isempty(safeName); safeName = 'circuit'; end
            backendName = '';
            try
                if ~isempty(app.QmcLastResult)
                    backendName = char(JsonHelper.pick(app.QmcLastResult, {'backend'}, ''));
                end
            catch
            end
            safeBackend = regexprep(char(backendName), '[^A-Za-z0-9_\-]', '_');
            if isempty(safeBackend); safeBackend = 'ibm_backend'; end
            stamp = char(datetime('now', 'Format', 'yyyyMMdd'));
            defaultName = sprintf('ExecLog_%s_%s_%s%s', safeBackend, safeName, stamp, ext);
            [fileName, pathName] = uiputfile( ...
                {'*.jsonl', 'JSON Lines (*.jsonl)'; ...
                 '*.json',  'JSON (*.json)'; ...
                 '*.*',     'All Files (*.*)'}, ...
                'Save IBM Runtime log', defaultName);
            if isequal(fileName, 0)
                uialert(alertParent, ...
                    sprintf('IBM log downloaded to:\n%s', tmpPath), ...
                    'Download IBM Log', 'Icon', 'success');
                return;
            end
            target = fullfile(pathName, fileName);
            try
                copyfile(tmpPath, target, 'f');
                app.logEvent('API', sprintf('IBM log %s saved to %s', runtimeJobId, target));
                uialert(alertParent, ...
                    sprintf('IBM Runtime log saved to:\n%s', target), ...
                    'Download IBM Log', 'Icon', 'success');
            catch ME
                Logger.warn('AnalysisViewModel', 'IBM log copy failed: %s', ME.message);
                uialert(alertParent, ...
                    sprintf('IBM log downloaded to:\n%s\n\nCould not copy to chosen path: %s', ...
                            tmpPath, ME.message), ...
                    'Download IBM Log', 'Icon', 'warning');
            end
        end

        function onIbmLogError(~, app, ME)
            app.hideLoading();
            uialert(AnalysisViewModel.qmcAlertParent(app), ME.message, ...
                'Download IBM Log', 'Icon', 'error');
            Logger.error('AnalysisViewModel', 'IBM log download failed: %s', ME.message);
        end

        function onQmcError(~, app, ME)
            app.hideLoading();
            alertParent = AnalysisViewModel.qmcAlertParent(app);
            isRuntime503 = contains(string(ME.message), '503') || ...
                           contains(lower(string(ME.message)), 'runtime is not configured');
            if isRuntime503
                uialert(alertParent, ...
                    sprintf(['IBM Qiskit Runtime is not configured on the server.\n' ...
                             'Switch Execution Mode to "Statevector (local)" and try again.\n\n%s'], ...
                             ME.message), ...
                    'Quantum Monte Carlo', 'Icon', 'warning');
            else
                uialert(alertParent, ME.message, 'Quantum Monte Carlo', 'Icon', 'error');
            end
            Logger.error('AnalysisViewModel', 'QMC failed: %s', ME.message);
        end

        function onQmcReportGenerated(obj, app, data)
            reportId = char(JsonHelper.pick(data, {'report_id'}, ''));
            status   = char(JsonHelper.pick(data, {'status'}, 'unknown'));
            app.logEvent('API', sprintf('Report generated — id=%s status=%s', reportId, status));
            if isempty(reportId)
                app.hideLoading();
                uialert(AnalysisViewModel.qmcAlertParent(app), ...
                    'The server did not return a report_id; cannot download.', ...
                    'Generate Report', 'Icon', 'error');
                return;
            end

            % Poll until status='ready', then stream the file to disk.
            % Generation is synchronous in the current backend but we
            % poll defensively in case it flips to async in the future.
            app.showLoading('Downloading PDF report...');
            reportSvc = app.ReportSvc;
            token     = app.State.authToken;
            circName  = char(app.State.selectedCircuitName);
            AsyncRunner.run( ...
                @() AnalysisViewModel.pollAndDownloadReport(reportSvc, reportId, token), ...
                @(savedPath) obj.onQmcReportDownloaded(app, reportId, savedPath, circName), ...
                @(ME)        obj.onQmcReportError(app, ME));
        end

        function onQmcReportDownloaded(~, app, reportId, tmpPath, circName)
            app.hideLoading();
            alertParent = AnalysisViewModel.qmcAlertParent(app);
            % Ask the user where to save the final copy; default to a
            % filename that includes the circuit name for findability.
            if ~isempty(tmpPath) && exist(tmpPath, 'file') == 2
                [~, ~, ext] = fileparts(tmpPath);
                if isempty(ext); ext = '.pdf'; end
                safeName = regexprep(char(circName), '[^A-Za-z0-9_\-]', '_');
                if isempty(safeName); safeName = 'report'; end
                stamp = char(datetime('now', 'Format', 'yyyyMMdd'));
                defaultName = sprintf('Report_%s_%s%s', safeName, stamp, ext);
                [fileName, pathName] = uiputfile( ...
                    {['*' ext], ['Report (' ext ')']; '*.*', 'All Files (*.*)'}, ...
                    'Save QMC report', defaultName);
                if isequal(fileName, 0)
                    Logger.info('AnalysisViewModel', 'Save cancelled; temp file: %s', tmpPath);
                    uialert(alertParent, ...
                        sprintf('Report downloaded to:\n%s\n\nOpen the Reports screen any time to re-download.', tmpPath), ...
                        'Generate Report', 'Icon', 'success');
                    return;
                end
                target = fullfile(pathName, fileName);
                try
                    copyfile(tmpPath, target, 'f');
                    app.logEvent('API', sprintf('Report %s saved to %s', reportId, target));
                    uialert(alertParent, ...
                        sprintf('Quantum Monte Carlo report saved to:\n%s', target), ...
                        'Generate Report', 'Icon', 'success');
                catch ME
                    Logger.warn('AnalysisViewModel', 'Copy to user path failed: %s', ME.message);
                    uialert(alertParent, ...
                        sprintf('Report downloaded to:\n%s\n\nCould not copy to chosen path: %s', ...
                                tmpPath, ME.message), ...
                        'Generate Report', 'Icon', 'warning');
                end
            else
                uialert(alertParent, ...
                    'Download finished but the local file is missing.', ...
                    'Generate Report', 'Icon', 'error');
            end
        end

        function onQmcReportError(~, app, ME)
            app.hideLoading();
            uialert(AnalysisViewModel.qmcAlertParent(app), ME.message, ...
                'Generate Report', 'Icon', 'error');
            Logger.error('AnalysisViewModel', 'QMC report failed: %s', ME.message);
        end

        function resetQmcUi(~, app)
            % Clear all KPI / Greek text and all plot axes on the QMC
            % popup. Called at the start of each Run QMC so the user
            % sees blanks while the API call is in flight rather than
            % stale values from the previous analysis.
            try
                if ~isempty(app.QmcKpiLabels)
                    for i = 1:numel(app.QmcKpiLabels)
                        try; app.QmcKpiLabels{i}.Text = '—'; catch; end
                    end
                end
            catch; end
            try
                if ~isempty(app.QmcGreeksLabels)
                    for i = 1:numel(app.QmcGreeksLabels)
                        try; app.QmcGreeksLabels{i}.Text = '—'; catch; end
                    end
                end
            catch; end
            axesHandles = {app.QmcPathAxes, app.QmcCdfAxes, ...
                           app.QmcConvergenceAxes, app.QmcAmpAxes, ...
                           app.QmcZneAxes};
            for k = 1:numel(axesHandles)
                ax = axesHandles{k};
                try
                    if ~isempty(ax) && isvalid(ax)
                        cla(ax);
                        lg = get(ax, 'Legend'); if ~isempty(lg); delete(lg); end
                        ax.XGrid = 'off'; ax.YGrid = 'off';
                        ax.XScale = 'linear'; ax.YScale = 'linear';
                        ax.XTick = []; ax.YTick = [];
                        title(ax, '');
                        xlabel(ax, ''); ylabel(ax, '');
                    end
                catch; end
            end
            app.QmcLastResult = [];
            AnalysisViewModel.toggleIbmLogButton(app, []);
        end

        function renderQmcResult(~, app, data)
            % KPI strip: amplitude | expected payoff | VaR95 | VaR99 | speedup
            try
                amp     = JsonHelper.pickNumeric(data, 'amplitude_estimate', NaN);
                ampLo   = JsonHelper.pickNumeric(data, 'amplitude_ci_low',   NaN);
                ampHi   = JsonHelper.pickNumeric(data, 'amplitude_ci_high',  NaN);
                payoff  = JsonHelper.pickNumeric(data, 'expected_payoff',    NaN);
                var95   = JsonHelper.pickNumeric(data, 'var_95',             NaN);
                var99   = JsonHelper.pickNumeric(data, 'var_99',             NaN);
                speedup = JsonHelper.pickNumeric(data, 'quadratic_speedup',  NaN);

                labels = app.QmcKpiLabels;
                labels{1}.Text = sprintf('%.4f\n[%.3f, %.3f]', amp, ampLo, ampHi);
                labels{2}.Text = sprintf('%.2f', payoff);
                labels{3}.Text = sprintf('%.2f', var95);
                labels{4}.Text = sprintf('%.2f', var99);
                labels{5}.Text = sprintf('%.1fx', speedup);
            catch ME
                Logger.warn('AnalysisViewModel', 'QMC KPI render: %s', ME.message);
            end

            % Extract path_distribution once; used by both the loss
            % histogram and the CDF overlay. jsondecode returns a
            % homogeneous JSON array of objects as a *struct array*
            % (not a cell array), so accept both shapes here.
            xs = []; ps = []; losses = [];
            try
                pdf = JsonHelper.pick(data, {'path_distribution'}, []);
                n = numel(pdf);
                if n > 0 && (iscell(pdf) || isstruct(pdf))
                    xs = zeros(n, 1);
                    ps = zeros(n, 1);
                    for i = 1:n
                        if iscell(pdf); item = pdf{i}; else; item = pdf(i); end
                        xs(i) = JsonHelper.pickNumeric(item, 'value', i);
                        ps(i) = JsonHelper.pickNumeric(item, 'probability', 0);
                    end
                    % Convert log-return buckets into mark-to-market loss
                    % using a $100 notional so the axes read in dollars,
                    % matching the expected_payoff / VaR units.
                    losses = -xs * 100.0;
                end
            catch ME
                Logger.warn('AnalysisViewModel', 'Path PDF decode: %s', ME.message);
            end

            var95 = JsonHelper.pickNumeric(data, 'var_95', NaN);
            var99 = JsonHelper.pickNumeric(data, 'var_99', NaN);

            % (1) Loss distribution with VaR threshold lines
            try
                if ~isempty(losses)
                    cla(app.QmcPathAxes);
                    bar(app.QmcPathAxes, losses, ps, 'FaceColor', Theme.COLOR_PRIMARY, ...
                        'EdgeColor', 'none', 'FaceAlpha', 0.85, 'DisplayName', 'Loss PDF');
                    hold(app.QmcPathAxes, 'on');
                    yLim = ylim(app.QmcPathAxes);
                    if ~isnan(var95)
                        plot(app.QmcPathAxes, [var95 var95], yLim, '--', ...
                            'Color', Theme.COLOR_WARNING, 'LineWidth', 1.6, ...
                            'DisplayName', sprintf('VaR 95%% (%.1f)', var95));
                    end
                    if ~isnan(var99)
                        plot(app.QmcPathAxes, [var99 var99], yLim, '--', ...
                            'Color', Theme.COLOR_DANGER, 'LineWidth', 1.6, ...
                            'DisplayName', sprintf('VaR 99%% (%.1f)', var99));
                    end
                    hold(app.QmcPathAxes, 'off');
                    app.QmcPathAxes.XGrid = 'on'; app.QmcPathAxes.YGrid = 'on';
                    legend(app.QmcPathAxes, 'Location', 'northwest', 'Box', 'off');
                    title(app.QmcPathAxes, 'Loss distribution with VaR thresholds');
                    xlabel(app.QmcPathAxes, 'Loss (negative = P&L down)');
                    ylabel(app.QmcPathAxes, 'Probability');
                end
            catch ME
                Logger.warn('AnalysisViewModel', 'Loss-distribution render: %s', ME.message);
            end

            % (2) Cumulative loss distribution (CDF)
            try
                if ~isempty(losses)
                    [sortedLoss, idx] = sort(losses, 'ascend');
                    cdf = cumsum(ps(idx));
                    cla(app.QmcCdfAxes);
                    stairs(app.QmcCdfAxes, sortedLoss, cdf, ...
                        'Color', Theme.COLOR_SUCCESS, 'LineWidth', 2.0, ...
                        'DisplayName', 'Cumulative P(loss \leq x)');
                    hold(app.QmcCdfAxes, 'on');
                    if ~isnan(var95)
                        plot(app.QmcCdfAxes, [var95 var95], [0 1], '--', ...
                            'Color', Theme.COLOR_WARNING, 'LineWidth', 1.4, ...
                            'DisplayName', 'VaR 95%');
                    end
                    if ~isnan(var99)
                        plot(app.QmcCdfAxes, [var99 var99], [0 1], '--', ...
                            'Color', Theme.COLOR_DANGER, 'LineWidth', 1.4, ...
                            'DisplayName', 'VaR 99%');
                    end
                    hold(app.QmcCdfAxes, 'off');
                    app.QmcCdfAxes.YLim = [0 1.05];
                    app.QmcCdfAxes.XGrid = 'on'; app.QmcCdfAxes.YGrid = 'on';
                    legend(app.QmcCdfAxes, 'Location', 'southeast', 'Box', 'off');
                    title(app.QmcCdfAxes, 'Cumulative loss distribution (CDF)');
                    xlabel(app.QmcCdfAxes, 'Loss (negative = P&L down)');
                    ylabel(app.QmcCdfAxes, 'P(loss \leq x)');
                end
            catch ME
                Logger.warn('AnalysisViewModel', 'CDF render: %s', ME.message);
            end

            % (3) QMC vs classical MC convergence (log-log). Same
            % cell-vs-struct-array caveat as path_distribution above.
            try
                conv = JsonHelper.pick(data, {'convergence'}, []);
                nConv = numel(conv);
                if nConv > 0 && (iscell(conv) || isstruct(conv))
                    ns   = zeros(nConv, 1);
                    qae  = zeros(nConv, 1);
                    mc   = zeros(nConv, 1);
                    for i = 1:nConv
                        if iscell(conv); item = conv{i}; else; item = conv(i); end
                        ns(i)  = JsonHelper.pickNumeric(item, 'samples',             1);
                        qae(i) = JsonHelper.pickNumeric(item, 'qae_error',           NaN);
                        mc(i)  = JsonHelper.pickNumeric(item, 'classical_mc_error',  NaN);
                    end
                    cla(app.QmcConvergenceAxes);
                    hold(app.QmcConvergenceAxes, 'on');
                    plot(app.QmcConvergenceAxes, ns, qae, '-o', ...
                        'Color', Theme.COLOR_PRIMARY, 'LineWidth', 1.8, ...
                        'MarkerSize', 4, 'DisplayName', 'QMC ~ 1/N');
                    plot(app.QmcConvergenceAxes, ns, mc, '-s', ...
                        'Color', Theme.COLOR_DANGER, 'LineWidth', 1.8, ...
                        'MarkerSize', 4, 'DisplayName', 'Classical MC ~ 1/\surd{N}');
                    hold(app.QmcConvergenceAxes, 'off');
                    app.QmcConvergenceAxes.XScale = 'log';
                    app.QmcConvergenceAxes.YScale = 'log';
                    app.QmcConvergenceAxes.XGrid  = 'on';
                    app.QmcConvergenceAxes.YGrid  = 'on';
                    legend(app.QmcConvergenceAxes, 'Location', 'northeast', 'Box', 'off');
                    title(app.QmcConvergenceAxes, 'Convergence: QMC 1/N vs classical MC 1/\surd{N}');
                    xlabel(app.QmcConvergenceAxes, 'Samples (log scale)');
                    ylabel(app.QmcConvergenceAxes, 'Estimation error (log scale)');
                end
            catch ME
                Logger.warn('AnalysisViewModel', 'Convergence render: %s', ME.message);
            end

            % Greeks KPI row (Delta / Gamma / Vega / Theta / Rho)
            try
                g = JsonHelper.pick(data, {'greeks'}, []);
                if isstruct(g) && ~isempty(app.QmcGreeksLabels)
                    vals = [ ...
                        JsonHelper.pickNumeric(g, 'delta', NaN), ...
                        JsonHelper.pickNumeric(g, 'gamma', NaN), ...
                        JsonHelper.pickNumeric(g, 'vega',  NaN), ...
                        JsonHelper.pickNumeric(g, 'theta', NaN), ...
                        JsonHelper.pickNumeric(g, 'rho',   NaN)];
                    for i = 1:5
                        if isnan(vals(i))
                            app.QmcGreeksLabels{i}.Text = '—';
                        else
                            app.QmcGreeksLabels{i}.Text = sprintf('%.4f', vals(i));
                        end
                    end
                end
            catch ME
                Logger.warn('AnalysisViewModel', 'Greeks render: %s', ME.message);
            end

            % (5) Zero-Noise Extrapolation curve (amplitude vs noise factor)
            try
                if ~isempty(app.QmcZneAxes) && isvalid(app.QmcZneAxes)
                    cla(app.QmcZneAxes);
                    curve = JsonHelper.pick(data, {'mitigation_curve'}, []);
                    mit   = JsonHelper.pick(data, {'mitigation'}, 'none');
                    nCurve = numel(curve);
                    if nCurve > 0 && (iscell(curve) || isstruct(curve))
                        nf = zeros(nCurve, 1);
                        amps = zeros(nCurve, 1);
                        for i = 1:nCurve
                            if iscell(curve); item = curve{i}; else; item = curve(i); end
                            nf(i)   = JsonHelper.pickNumeric(item, 'noise_factor', i - 1);
                            amps(i) = JsonHelper.pickNumeric(item, 'amplitude',    NaN);
                        end
                        hold(app.QmcZneAxes, 'on');
                        plot(app.QmcZneAxes, nf(nf > 0), amps(nf > 0), '-s', ...
                            'Color', Theme.COLOR_DANGER, 'LineWidth', 1.6, ...
                            'MarkerFaceColor', Theme.COLOR_DANGER, 'MarkerSize', 6, ...
                            'DisplayName', 'Noisy samples');
                        zeroIdx = find(nf == 0, 1);
                        if ~isempty(zeroIdx)
                            plot(app.QmcZneAxes, nf(zeroIdx), amps(zeroIdx), 'p', ...
                                'MarkerSize', 14, 'LineWidth', 2.0, ...
                                'Color', Theme.COLOR_SUCCESS, ...
                                'MarkerFaceColor', Theme.COLOR_SUCCESS, ...
                                'DisplayName', 'Extrapolated zero-noise');
                        end
                        hold(app.QmcZneAxes, 'off');
                        app.QmcZneAxes.XGrid = 'on'; app.QmcZneAxes.YGrid = 'on';
                        app.QmcZneAxes.XLim = [-0.3, max(nf) + 0.3];
                        legend(app.QmcZneAxes, 'Location', 'northeast', 'Box', 'off');
                    else
                        text(app.QmcZneAxes, 0.5, 0.5, ...
                            sprintf('Mitigation = %s.\nEnable ZNE or PEC for the extrapolation curve.', upper(string(mit))), ...
                            'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                            'Color', Theme.COLOR_MUTED, 'FontSize', 12);
                        app.QmcZneAxes.XTick = []; app.QmcZneAxes.YTick = [];
                    end
                    title(app.QmcZneAxes, 'Zero-Noise Extrapolation — amplitude vs noise factor');
                    xlabel(app.QmcZneAxes, 'Noise factor (1.0 = native hardware)');
                    ylabel(app.QmcZneAxes, 'Amplitude estimate');
                end
            catch ME
                Logger.warn('AnalysisViewModel', 'ZNE render: %s', ME.message);
            end

            % (4) Amplitude-estimation bar chart — the "objective qubit"
            % measured in |0> / |1>, plus the classical-MC baseline of
            % the same expectation for visual reference. This is what
            % QMC is actually solving for (P(objective = 1) = a).
            try
                amp = JsonHelper.pickNumeric(data, 'amplitude_estimate', NaN);
                if ~isnan(amp)
                    cla(app.QmcAmpAxes);
                    bar(app.QmcAmpAxes, [1 2], [1 - amp, amp], ...
                        'FaceColor', Theme.COLOR_PRIMARY, 'EdgeColor', 'none', ...
                        'FaceAlpha', 0.85);
                    app.QmcAmpAxes.XTick = [1 2];
                    app.QmcAmpAxes.XTickLabel = {'|0\rangle', '|1\rangle'};
                    app.QmcAmpAxes.YLim = [0 1];
                    app.QmcAmpAxes.XGrid = 'off'; app.QmcAmpAxes.YGrid = 'on';
                    title(app.QmcAmpAxes, ...
                        sprintf('Objective-qubit amplitude estimate (a = %.4f)', amp));
                    xlabel(app.QmcAmpAxes, 'Measured basis state');
                    ylabel(app.QmcAmpAxes, 'Probability');
                end
            catch ME
                Logger.warn('AnalysisViewModel', 'Amplitude chart render: %s', ME.message);
            end
        end

        function onAnalyzeComplete(obj, app, cid, data)
            obj.applyAnalysisData(data);
            obj.applyBenchmarkMatches(data);
            obj.buildQVHeatmap(data);
            app.logEvent('API', sprintf('Circuit analysis complete — circuit: %s', cid));
            app.State.logActivity(sprintf('Analyze circuit — %s', char(app.State.selectedCircuitName)), 'Success');
            app.hideLoading();
            obj.LastRefresh = tic;
        end

        function onAnalyzeError(~, app, cid, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Analysis FAILED (circuit: %s): %s', cid, ME.message));
            app.showError('Analyze Circuit', ME);
        end

        function applyAnalysisData(obj, data)
            app = obj.App;
            delete(app.FeatureTree.Children);
            try
                data = JsonHelper.decodeIfJson(data);
                name  = char(JsonHelper.pick(data, {'circuit_name','name'}));
                depth = char(JsonHelper.pick(data, {'depth'}));
                width = char(JsonHelper.pick(data, {'num_qubits','width'}));

                % Extract gate counts from gate_counts map or fallback fields
                gcMap = JsonHelper.safeField(data, 'gate_counts', struct());
                totalGates = 0; sq = 0; tq = 0; meas = 0;
                gateLines = {};
                if isstruct(gcMap)
                    fns = fieldnames(gcMap);
                    for gi = 1:numel(fns)
                        gn = fns{gi}; cnt = gcMap.(gn);
                        if ~isnumeric(cnt); cnt = str2double(char(string(cnt))); end
                        totalGates = totalGates + cnt;
                        if ismember(gn, {'cx','cz','cy','swap','cswap','ccx','cu1','cu2','cu3','ch','ecr','rzz','rxx','ryy'})
                            tq = tq + cnt;
                        elseif ismember(gn, {'measure','measurement'})
                            meas = meas + cnt;
                        else
                            sq = sq + cnt;
                        end
                        gateLines{end+1} = sprintf('%s: %d', gn, cnt); %#ok<AGROW>
                    end
                end
                % Fallback to flat fields if gate_counts was empty
                if totalGates == 0
                    sq   = JsonHelper.toDouble(JsonHelper.pick(data, {'single_qubit_gates','num_1q'}));
                    tq   = JsonHelper.toDouble(JsonHelper.pick(data, {'two_qubit_gates','num_2q','cx_count'}));
                    meas = JsonHelper.toDouble(JsonHelper.pick(data, {'measurements','num_measurements'}));
                    totalGates = sq + tq + meas;
                end

                tqRatio = JsonHelper.toDouble(JsonHelper.pick(data, {'two_qubit_gate_ratio'}));
                tCount  = JsonHelper.toDouble(JsonHelper.pick(data, {'t_count'}));
                par     = char(JsonHelper.pick(data, {'parallelism_score','parallelism','features.parallelism_score'}));
                coup    = char(JsonHelper.pick(data, {'coupling_pressure','features.coupling_pressure'}));

                % Build tree
                root = uitreenode(app.FeatureTree, 'Text', name);
                arch = uitreenode(root, 'Text', 'Structure');
                    uitreenode(arch, 'Text', sprintf('Depth: %s', depth));
                    uitreenode(arch, 'Text', sprintf('Width: %s qubits', width));
                gc = uitreenode(root, 'Text', 'Gate counts');
                    uitreenode(gc, 'Text', sprintf('Single-qubit: %d', sq));
                    uitreenode(gc, 'Text', sprintf('Two-qubit: %d', tq));
                    uitreenode(gc, 'Text', sprintf('Measurement: %d', meas));
                    uitreenode(gc, 'Text', sprintf('Total: %d', totalGates));
                    if ~isempty(gateLines)
                        gd = uitreenode(gc, 'Text', 'Gate detail');
                        for gi = 1:numel(gateLines)
                            uitreenode(gd, 'Text', gateLines{gi});
                        end
                    end
                qf = uitreenode(root, 'Text', 'Quantum features');
                    if ~isnan(tqRatio); uitreenode(qf, 'Text', sprintf('Two-qubit ratio: %.1f%%', tqRatio * 100)); end
                    if ~isnan(tCount) && tCount > 0; uitreenode(qf, 'Text', sprintf('T-count: %d', tCount)); end
                    uitreenode(qf, 'Text', sprintf('Parallelism score: %s', par));
                    uitreenode(qf, 'Text', sprintf('Coupling pressure: %s', coup));
                expand(root); expand(arch); expand(gc); expand(qf);

                % Build Feature Summary text
                obj.buildFeatureSummary(data, name, depth, width, sq, tq, meas, totalGates, tqRatio, tCount);
            catch ME
                Logger.warn('AnalysisViewModel', 'applyAnalysisData tree build failed: %s', ME.message);
                uitreenode(app.FeatureTree, 'Text', JsonHelper.pretty(data));
            end
        end

        function buildFeatureSummary(obj, data, name, depth, width, sq, tq, meas, totalGates, tqRatio, tCount)
            % Build a human-readable feature summary for the AnalysisFeatureArea.
            app = obj.App;
            try
                depthN = str2double(depth);
                widthN = str2double(width);
                lines = {};
                lines{end+1} = sprintf('Circuit: %s', name);
                lines{end+1} = sprintf('%s qubits, depth %s', width, depth);
                lines{end+1} = sprintf('%d gates total (%d 1Q, %d 2Q, %d meas)', totalGates, sq, tq, meas);
                lines{end+1} = '';

                % Circuit complexity assessment
                if ~isnan(tqRatio) && tqRatio > 0
                    if tqRatio > 0.5
                        lines{end+1} = sprintf('High 2Q ratio (%.0f%%) — entanglement-heavy.', tqRatio*100);
                    elseif tqRatio > 0.2
                        lines{end+1} = sprintf('Moderate 2Q ratio (%.0f%%).', tqRatio*100);
                    else
                        lines{end+1} = sprintf('Low 2Q ratio (%.0f%%) — mostly local gates.', tqRatio*100);
                    end
                end

                if ~isnan(tCount) && tCount > 0
                    lines{end+1} = sprintf('T-count: %d (fault-tolerant cost).', tCount);
                end

                % Size/depth insight
                if ~isnan(depthN) && ~isnan(widthN)
                    if depthN > 100
                        lines{end+1} = 'Deep circuit — consider transpiler optimization.';
                    elseif depthN <= 10
                        lines{end+1} = 'Shallow circuit — good for NISQ execution.';
                    end
                    if widthN > 20
                        lines{end+1} = 'Wide circuit — requires large-qubit backend.';
                    end
                end

                % Benchmark match summary
                try
                    items = JsonHelper.extractList(data, 'benchmark_matches');
                    if isempty(items); items = JsonHelper.extractList(data, 'matches'); end
                    if ~isempty(items) && numel(items) > 0
                        topName = char(JsonHelper.pick(items(1), {'benchmark_name','name'}));
                        topSim  = JsonHelper.toDouble(JsonHelper.pick(items(1), {'similarity','score'}));
                        lines{end+1} = '';
                        lines{end+1} = sprintf('Closest match: %s (%.1f%%)', topName, topSim*100);
                        if topSim > 0.95
                            lines{end+1} = 'Very high similarity — well-characterized circuit class.';
                        elseif topSim > 0.8
                            lines{end+1} = 'Good match — similar structure to known benchmarks.';
                        else
                            lines{end+1} = 'Novel structure — limited benchmark reference data.';
                        end
                    end
                catch ME; Logger.debug('AnalysisViewModel', 'buildFeatureSummary QTAUBench similarity: %s', ME.message); end

                app.AnalysisFeatureArea.Value = lines;
            catch ME
                Logger.warn('AnalysisViewModel', 'buildFeatureSummary failed: %s', ME.message);
                app.AnalysisFeatureArea.Value = {'Feature summary unavailable.'};
            end
        end

        function applyBenchmarkMatches(obj, data)
            app = obj.App;
            try
                items = JsonHelper.extractList(data, 'benchmark_matches');
                if isempty(items); items = JsonHelper.extractList(data, 'matches'); end
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n == 0; return; end
                rows = cell(n, 4);
                for i = 1:n
                    rows{i,1} = char(JsonHelper.pick(items(i), {'benchmark_name','name'}));
                    rows{i,2} = JsonHelper.toDouble(JsonHelper.pick(items(i), {'similarity','score'}));
                    rows{i,3} = char(JsonHelper.pick(items(i), {'category'}));
                    rows{i,4} = char(JsonHelper.pick(items(i), {'notes','comment'}));
                end
                app.SimilarityTable.Data = rows;
            catch ME
                Logger.warn('AnalysisViewModel', 'applyBenchmarkMatches failed: %s', ME.message);
            end
        end

        function buildQVHeatmap(obj, data)
            % buildQVHeatmap  Renders the Circuit Complexity Landscape —
            %   a clean scatter of Circuit Depth (log) vs Width (qubits)
            %   with the current circuit as the hero marker against a
            %   reference backdrop of well-known quantum algorithms.
            %
            %   Fidelity is estimated deterministically from the current
            %   circuit's actual gate counts using typical NISQ error
            %   rates (1Q: 0.1%, 2Q: 1%, meas: 2%) — so the visualization
            %   genuinely updates every time the circuit changes.
            app = obj.App;
            ax  = app.QVHeatmapAxes;
            try
                % --- Extract current circuit metrics ----------------------
                curDepth = JsonHelper.toDouble(JsonHelper.pick(data, {'depth'}));
                curWidth = JsonHelper.toDouble(JsonHelper.pick(data, {'num_qubits','width'}));
                curName  = char(JsonHelper.pick(data, {'circuit_name','name'}));
                if isempty(curName); curName = 'current circuit'; end
                if isnan(curDepth) || curDepth <= 0; curDepth = 1; end
                if isnan(curWidth) || curWidth <= 0; curWidth = 1; end

                % Gate counts drive the deterministic fidelity estimate
                sq = 0; tq = 0; meas = 0;
                gcMap = JsonHelper.safeField(data, 'gate_counts', struct());
                if isstruct(gcMap)
                    fns = fieldnames(gcMap);
                    twoQ = {'cx','cz','cy','swap','cswap','ccx','cu1','cu2','cu3','ch','ecr','rzz','rxx','ryy'};
                    for gi = 1:numel(fns)
                        gn = fns{gi}; cnt = gcMap.(gn);
                        if ~isnumeric(cnt); cnt = str2double(char(string(cnt))); end
                        if isnan(cnt); continue; end
                        if ismember(gn, twoQ)
                            tq = tq + cnt;
                        elseif ismember(gn, {'measure','measurement'})
                            meas = meas + cnt;
                        else
                            sq = sq + cnt;
                        end
                    end
                end
                if sq + tq + meas == 0
                    sq   = JsonHelper.toDouble(JsonHelper.pick(data, {'single_qubit_gates','num_1q'}));
                    tq   = JsonHelper.toDouble(JsonHelper.pick(data, {'two_qubit_gates','num_2q','cx_count'}));
                    meas = JsonHelper.toDouble(JsonHelper.pick(data, {'measurements','num_measurements'}));
                    if isnan(sq);   sq   = 0; end
                    if isnan(tq);   tq   = 0; end
                    if isnan(meas); meas = 0; end
                end

                apiFid = JsonHelper.toDouble(JsonHelper.pick(data, ...
                    {'result_fidelity','fidelity','expected_fidelity'}));
                if ~isnan(apiFid) && apiFid > 0 && apiFid <= 1
                    curFid = apiFid;
                else
                    curFid = 0.999^sq * 0.99^tq * 0.98^meas;
                    curFid = max(0.02, min(0.999, curFid));
                end

                % Top benchmark match (from real analysis data)
                topMatchName = ''; topMatchSim = NaN;
                try
                    mItems = JsonHelper.extractList(data, 'benchmark_matches');
                    if isempty(mItems); mItems = JsonHelper.extractList(data, 'matches'); end
                    if ~isempty(mItems) && numel(mItems) > 0
                        topMatchName = char(JsonHelper.pick(mItems(1), {'benchmark_name','name'}));
                        topMatchSim  = JsonHelper.toDouble(JsonHelper.pick(mItems(1), {'similarity','score'}));
                    end
                catch; end

                % --- Reference backdrop (well-known algorithms) -----------
                refNames  = {'Bell', 'GHZ-7', 'BV-5', 'DJ-5', 'Grover', ...
                             'Simon', 'Hidden-Shift', 'QFT-11', 'QPE', 'VQE-5', ...
                             'QAOA', 'Shor', 'MC-Sim', 'Ham-Sim', 'Rand-4', 'Supremacy'};
                refDepths = [5, 3, 7, 7, 23, 17, 10, 43, 69, 53, ...
                             27, 113, 69, 281, 450, 1000];
                refWidths = [2, 7, 5, 5, 8, 6, 12, 11, 12, 5, ...
                             6, 7, 5, 13, 4, 53];
                % Deterministic reference fidelities using the same model
                refFids = 0.999.^(refDepths.*1.2) .* 0.99.^(refDepths.*0.3);
                refFids = max(0.05, min(0.995, refFids));

                % --- Axis bounds ------------------------------------------
                allD = [refDepths, round(curDepth)];
                allW = [refWidths, round(curWidth)];
                xMax = max(2000, max(allD) * 1.8);
                yMax = max(32, max(allW) + 6);

                % --- Render -----------------------------------------------
                cla(ax, 'reset');
                app.styleAxes(ax);
                hold(ax, 'on');

                % Soft regime bands (NISQ / Mid-depth / Fault-tolerant)
                patch(ax, [1 50 50 1],           [0 0 yMax yMax], ...
                      [0.94 0.97 1.00], 'EdgeColor', 'none', 'FaceAlpha', 0.55);
                patch(ax, [50 500 500 50],       [0 0 yMax yMax], ...
                      [1.00 0.99 0.93], 'EdgeColor', 'none', 'FaceAlpha', 0.55);
                patch(ax, [500 xMax xMax 500],   [0 0 yMax yMax], ...
                      [1.00 0.94 0.93], 'EdgeColor', 'none', 'FaceAlpha', 0.55);

                % Regime labels at top of chart
                text(ax, 7,   yMax - 1.2, 'NISQ',           ...
                    'FontSize', 9.5, 'FontWeight', 'bold', ...
                    'Color', [0.35 0.50 0.72], 'Interpreter', 'none');
                text(ax, 130, yMax - 1.2, 'Mid-depth',      ...
                    'FontSize', 9.5, 'FontWeight', 'bold', ...
                    'Color', [0.72 0.58 0.25], 'Interpreter', 'none');
                text(ax, 800, yMax - 1.2, 'Fault-tolerant', ...
                    'FontSize', 9.5, 'FontWeight', 'bold', ...
                    'Color', [0.75 0.40 0.36], 'Interpreter', 'none');

                % Diagonal n × n reference line (quantum volume region)
                nGrid = 1:ceil(yMax);
                plot(ax, nGrid, nGrid, '--', ...
                    'Color', [0.45 0.48 0.58], 'LineWidth', 1.1);
                labY = min(yMax - 2, max(allW) - 1);
                labX = max(1.2, labY * 1.15);
                text(ax, labX, labY, ' n × n  (depth = width)', ...
                    'FontSize', 9, 'FontAngle', 'italic', ...
                    'Color', [0.40 0.45 0.55], ...
                    'BackgroundColor', [1 1 1 0.75], ...
                    'Margin', 2, 'Interpreter', 'none');

                % Reference benchmark dots
                scatter(ax, refDepths, refWidths, 48, refFids, 'filled', ...
                    'MarkerEdgeColor', [0.35 0.38 0.45], ...
                    'MarkerFaceAlpha', 0.85, 'LineWidth', 0.5);
                for k = 1:numel(refDepths)
                    text(ax, refDepths(k)*1.10, refWidths(k), refNames{k}, ...
                        'FontSize', 8.5, 'Color', [0.28 0.32 0.40], ...
                        'VerticalAlignment', 'middle', ...
                        'Interpreter', 'none');
                end

                % --- Current circuit — hero star with halo ---------------
                scatter(ax, curDepth, curWidth, 480, [1 1 1], 'p', 'filled', ...
                    'MarkerEdgeColor', [1 1 1], 'LineWidth', 0.1);  % halo
                scatter(ax, curDepth, curWidth, 300, curFid, 'p', 'filled', ...
                    'MarkerEdgeColor', [0.08 0.10 0.14], 'LineWidth', 1.8);

                % Hero callout — offset intelligently to stay inside plot
                annoText = sprintf('%s\ndepth %d  ·  %d qubits\nest. fidelity %.1f%%', ...
                    curName, round(curDepth), round(curWidth), curFid*100);
                if curDepth * 2.2 < xMax
                    xAnno = curDepth * 1.35;
                    haAnno = 'left';
                else
                    xAnno = curDepth / 1.35;
                    haAnno = 'right';
                end
                yAnno = min(yMax - 0.5, curWidth + 2);
                text(ax, xAnno, yAnno, annoText, ...
                    'FontSize', 10, 'FontWeight', 'bold', ...
                    'Color', [0.10 0.14 0.22], ...
                    'BackgroundColor', [1 1 1 0.92], ...
                    'EdgeColor', [0.22 0.34 0.56], ...
                    'Margin', 6, 'HorizontalAlignment', haAnno, ...
                    'VerticalAlignment', 'bottom', 'Interpreter', 'none');

                % Connector line from annotation back to the star
                plot(ax, [curDepth xAnno], [curWidth yAnno], ':', ...
                    'Color', [0.22 0.34 0.56], 'LineWidth', 0.9);

                % --- Colormap & axes -------------------------------------
                colormap(ax, parula(256));
                ax.CLim = [0 1];
                cb = colorbar(ax);
                cb.Label.String = Labels.get('analysis_qv_colorbar', ...
                    'Estimated Result Fidelity');
                cb.Label.FontSize = 10;

                ax.XScale = 'log';
                ax.XLim   = [1, xMax];
                ax.YLim   = [0, yMax];
                ax.XGrid  = 'on'; ax.YGrid = 'on';
                ax.GridColor = [0.80 0.84 0.90];
                ax.GridAlpha = 0.7;
                ax.Box    = 'on';

                title(ax, Labels.get('analysis_qv_title', ...
                    'Circuit Depth vs Width (Est. Result Fidelity)'));
                xlabel(ax, Labels.get('analysis_qv_xlabel', ...
                    'Circuit Depth (log scale)'));
                ylabel(ax, Labels.get('analysis_qv_ylabel', ...
                    'Circuit Width (Qubits)'));

                hold(ax, 'off');

                % --- Side info panel -------------------------------------
                if curDepth < 50
                    regime = 'NISQ (near-term)';
                elseif curDepth < 500
                    regime = 'Mid-depth';
                else
                    regime = 'Fault-tolerant';
                end

                matchLine = '';
                if ~isempty(topMatchName) && ~isnan(topMatchSim)
                    matchLine = sprintf('Closest benchmark:\n  %s (%.0f%%)\n\n', ...
                        topMatchName, topMatchSim*100);
                end

                app.QVInfoLabel.Text = sprintf([ ...
                    'Current circuit\n' ...
                    '  %s\n\n' ...
                    '  depth: %d\n' ...
                    '  width: %d qubits\n' ...
                    '  gates: %d (1Q) + %d (2Q)\n' ...
                    '  est. fidelity: %.1f%%\n\n' ...
                    'Regime: %s\n\n' ...
                    '%s' ...
                    'Fidelity is estimated\n' ...
                    'from gate counts using\n' ...
                    'typical NISQ error rates\n' ...
                    '(1Q: 0.1%%, 2Q: 1%%,\n' ...
                    ' meas: 2%%).'], ...
                    curName, round(curDepth), round(curWidth), ...
                    sq, tq, curFid*100, regime, matchLine);
                app.QVInfoLabel.FontColor = Theme.COLOR_HEADING;

                Logger.info('AnalysisViewModel', ...
                    'Complexity landscape rendered — %s d=%d w=%d fid=%.2f', ...
                    curName, round(curDepth), round(curWidth), curFid);
            catch ME
                Logger.warn('AnalysisViewModel', 'buildQVHeatmap failed: %s', ME.message);
            end
        end

        % ── Quantum Error Mitigation private renderers (Phase 6.x) ──────

        function loadEmBackendsForDialog(obj, app)
            if ~app.State.isAuthenticated(); return; end
            token = app.State.authToken;
            cid = '';
            if app.State.hasCircuit(); cid = char(app.State.selectedCircuitId); end
            backendSvc = app.BackendSvc;
            circSvc    = app.CircuitSvc;
            AsyncRunner.run( ...
                @() AnalysisViewModel.fetchBackendList(backendSvc, circSvc, cid, token), ...
                @(data) obj.onEmBackendsLoaded(app, data), ...
                @(ME)   obj.onEmBackendsError(app, ME));
        end

        function onEmBackendsLoaded(obj, app, data)
            if isempty(app.EmBackendDropdown) || ~isvalid(app.EmBackendDropdown); return; end
            items = JsonHelper.extractList(data, 'backends');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0
                app.EmBackendDropdown.Items = {'(no backends)'};
                app.EmBackendDropdown.ItemsData = {''};
                app.EmBackendDropdown.Value = '';
                return;
            end
            names = cell(1, n);
            for i = 1:n
                names{i} = char(JsonHelper.pick(items(i), {'name','backend_name'}));
            end
            app.EmBackendDropdown.Items     = names;
            app.EmBackendDropdown.ItemsData = names;
            sel = '';
            try; sel = char(app.State.selectedBackend); catch; end
            match = find(strcmp(names, sel), 1);
            if ~isempty(match)
                app.EmBackendDropdown.Value = names{match};
            else
                app.EmBackendDropdown.Value = names{1};
            end
            obj.refreshEmEstimateBundle(app);
            obj.renderEmKpis(app);
            obj.renderEmGammaDepthCurve(app);
        end

        function onEmBackendsError(~, app, ME)
            if ~isempty(app.EmBackendDropdown) && isvalid(app.EmBackendDropdown)
                app.EmBackendDropdown.Items = {'(load failed)'};
                app.EmBackendDropdown.ItemsData = {''};
                app.EmBackendDropdown.Value = '';
            end
            Logger.warn('AnalysisViewModel', 'EM backend load failed: %s', ME.message);
        end

        function loadEmInitialData(obj, app)
            % Fan-out parallel fetches: levels, cached QAE, circuit meta.
            % Each callback paints its panel independently.
            if ~app.State.isAuthenticated(); return; end
            token = app.State.authToken;

            mitSvc = app.MitigationSvc;
            AsyncRunner.run( ...
                @() mitSvc.listLevels(token), ...
                @(data) obj.onEmLevelsLoaded(app, data), ...
                @(ME)   Logger.warn('AnalysisViewModel', ...
                    'EM levels load failed: %s', ME.message));

            if app.State.hasCircuit()
                qmcSvc = app.QmcSvc;
                cid = char(app.State.selectedCircuitId);
                AsyncRunner.run( ...
                    @() qmcSvc.getLast(cid, token), ...
                    @(data) obj.onEmQaeLoaded(app, data), ...
                    @(ME)   obj.onEmQaeMissing(app, ME));

                circSvc = app.CircuitSvc;
                AsyncRunner.run( ...
                    @() circSvc.getCircuit(cid, token), ...
                    @(data) obj.onEmCircuitMetaLoaded(app, data), ...
                    @(ME)   Logger.debug('AnalysisViewModel', ...
                        'EM circuit meta load: %s', ME.message));
            else
                obj.applyEmStatusBanner(app, false);
            end
            obj.renderEmOverheadCutsCurve(app);
        end

        function onEmLevelsLoaded(obj, app, data)
            if isempty(app.EmLevelDropdown) || ~isvalid(app.EmLevelDropdown); return; end
            levels = JsonHelper.extractList(data, 'levels');
            if isempty(levels); levels = JsonHelper.asList(data); end
            if isempty(levels); return; end
            n = numel(levels);
            items = cell(1, n);
            itemsData = cell(1, n);
            for i = 1:n
                lid = JsonHelper.pickNumeric(levels(i), 'id', i-1);
                lab = char(JsonHelper.pick(levels(i), {'label','name'}));
                if isempty(lab); lab = sprintf('Level %d', lid); end
                items{i}     = lab;
                itemsData{i} = double(lid);
            end
            app.EmLevelDropdown.Items     = items;
            app.EmLevelDropdown.ItemsData = itemsData;
            % Default to "Standard" (id=1) when present, else first.
            if any(cellfun(@(x)isequal(x, 1), itemsData))
                app.EmLevelDropdown.Value = 1;
            else
                app.EmLevelDropdown.Value = itemsData{1};
            end
            app.EmLevels = levels;
            obj.refreshEmEstimateBundle(app);
        end

        function onEmQaeLoaded(obj, app, data)
            app.EmQaeCached = data;
            obj.renderEmZneCurve(app, data);
            obj.renderEmRawMitigatedHistogram(app, data);
            obj.applyEmStatusBanner(app, true);
        end

        function onEmQaeMissing(obj, app, ~)
            app.EmQaeCached = [];
            obj.applyEmStatusBanner(app, false);
        end

        function onEmCircuitMetaLoaded(obj, app, data)
            app.EmCircuitMeta = data;
            obj.renderEmKpis(app);
            obj.renderEmGammaDepthCurve(app);
        end

        function refreshEmEstimateBundle(obj, app)
            % Sweep /api/mitigation/estimate over every published level
            % so the technique table + recommendation card reflect the
            % current backend / shots / primitive.
            if isempty(app.EmLevelDropdown) || ~isvalid(app.EmLevelDropdown); return; end
            if ~app.State.isAuthenticated(); return; end
            backend = char(app.EmBackendDropdown.Value);
            if isempty(backend); return; end

            token = app.State.authToken;
            mitSvc = app.MitigationSvc;
            primitive = char(app.EmPrimitiveDropdown.Value);
            baseShots = double(app.EmBaseShotsField.Value);
            qubits = AnalysisViewModel.pickQubits(app.EmCircuitMeta);
            if isnan(qubits); qubits = 5; end

            sweepLevels = app.EmLevels;
            if isempty(sweepLevels); return; end
            n = numel(sweepLevels);
            bundle = cell(1, n);
            currentLid = double(app.EmLevelDropdown.Value);
            for i = 1:n
                lid = JsonHelper.pickNumeric(sweepLevels(i), 'id', i-1);
                body = struct( ...
                    'mitigation_level',         double(lid), ...
                    'primitive',                primitive, ...
                    'backend_name',             backend, ...
                    'base_shots',               baseShots, ...
                    'circuit_qubits',           round(qubits), ...
                    'cutting_overhead_qubits',  0);
                if currentLid == lid && lid == 3
                    body.mitigation_options = AnalysisViewModel.currentEmOptions(app);
                end
                est = [];
                try
                    est = mitSvc.estimate(body, token);
                catch ME
                    Logger.debug('AnalysisViewModel', ...
                        'EM estimate fail (lid=%d): %s', lid, ME.message);
                end
                bundle{i} = struct( ...
                    'levelId',  double(lid), ...
                    'label',    char(JsonHelper.pick(sweepLevels(i), ...
                        {'label','name'}, sprintf('Level %d', lid))), ...
                    'estimate', est);
            end
            app.EmEstimateBundle = bundle;
            obj.renderEmTechniqueTable(app, bundle);
            obj.renderEmRecommendation(app, bundle);
            obj.refreshEmCostSummary(app, bundle);
        end

        function refreshEmCostSummary(~, app, bundle)
            if isempty(app.EmCostSummaryLabel) || ~isvalid(app.EmCostSummaryLabel); return; end
            selLid = double(app.EmLevelDropdown.Value);
            found = [];
            for i = 1:numel(bundle)
                if bundle{i}.levelId == selLid
                    found = bundle{i}; break;
                end
            end
            if isempty(found) || isempty(found.estimate)
                app.EmCostSummaryLabel.Text = '-';
                app.EmConflictLabel.Text = '';
                return;
            end
            summary = char(JsonHelper.pick(found.estimate, {'summary'}, ''));
            if isempty(summary)
                cost = JsonHelper.pick(found.estimate, {'cost'}, struct());
                eff  = JsonHelper.pickNumeric(cost, 'effective_shots', NaN);
                wall = JsonHelper.pickNumeric(cost, 'est_wall_seconds', NaN);
                if isnan(eff);  shotS = '?'; else; shotS = sprintf('%d', round(eff)); end
                if isnan(wall); wallS = '?'; else; wallS = sprintf('%.1fs', wall); end
                summary = sprintf('Effective shots: %s ; est. wall: %s', shotS, wallS);
            end
            app.EmCostSummaryLabel.Text = summary;
            plan = JsonHelper.pick(found.estimate, {'plan'}, struct());
            notes = JsonHelper.extractList(plan, 'conflicts');
            if isempty(notes); notes = JsonHelper.extractList(plan, 'notes'); end
            if iscell(notes) && ~isempty(notes)
                strs = cell(1, numel(notes));
                for k = 1:numel(notes); strs{k} = char(string(notes{k})); end
                app.EmConflictLabel.Text = strjoin(strs, ' ; ');
            else
                app.EmConflictLabel.Text = '';
            end
        end

        function renderEmKpis(~, app)
            if isempty(app.EmKpiLabels); return; end
            qubits = AnalysisViewModel.pickQubits(app.EmCircuitMeta);
            depth  = AnalysisViewModel.pickDepth(app.EmCircuitMeta);
            twoq   = AnalysisViewModel.pickTwoQGates(app.EmCircuitMeta);
            app.EmKpiLabels{1}.Text = AnalysisViewModel.fmtIntKpi(qubits);
            app.EmKpiLabels{2}.Text = AnalysisViewModel.fmtIntKpi(depth);
            app.EmKpiLabels{3}.Text = AnalysisViewModel.fmtIntKpi(twoq);

            gammaTxt = '-';
            advTxt   = Labels.get('em_advantage_unknown', '-');
            advColor = Theme.COLOR_MUTED;
            try
                backend = char(app.EmBackendDropdown.Value);
                if ~isempty(backend) && app.State.isAuthenticated()
                    cal = app.BackendSvc.getCalibration(backend, app.State.authToken);
                    eplg = AnalysisViewModel.extractEplg(cal);
                    if ~isnan(eplg) && eplg > 0
                        gammaBar = AnalysisViewModel.computeGammaBar(eplg);
                        if ~isnan(gammaBar)
                            gammaTxt = sprintf('%.3f', gammaBar);
                            if ~isnan(depth) && depth > 0
                                ovh = AnalysisViewModel.computeGammaBarOverhead(gammaBar, depth);
                                if ~isnan(ovh) && ovh < 1e4
                                    advTxt   = Labels.get('em_advantage_yes', 'feasible');
                                    advColor = Theme.COLOR_SUCCESS;
                                elseif ~isnan(ovh)
                                    advTxt   = Labels.get('em_advantage_no', 'infeasible');
                                    advColor = Theme.COLOR_DANGER;
                                end
                            end
                        end
                    end
                end
            catch ME
                Logger.debug('AnalysisViewModel', ...
                    'EM gammabar compute failed: %s', ME.message);
            end
            app.EmKpiLabels{4}.Text = gammaTxt;
            app.EmKpiLabels{5}.Text = advTxt;
            try; app.EmKpiLabels{5}.FontColor = advColor; catch; end
        end

        function renderEmZneCurve(~, app, qae)
            ax = app.EmZneAxes;
            if isempty(ax) || ~isvalid(ax); return; end
            cla(ax);
            ax.XGrid = 'on'; ax.YGrid = 'on';
            if isempty(qae); return; end
            curve = JsonHelper.extractList(qae, 'mitigation_curve');
            if isempty(curve); return; end
            n = numel(curve);
            nf = zeros(1, n); val = zeros(1, n);
            for i = 1:n
                nf(i)  = JsonHelper.pickNumeric(curve(i), 'noise_factor', NaN);
                val(i) = JsonHelper.pickNumeric(curve(i), 'amplitude', NaN);
            end
            valid = ~isnan(nf) & ~isnan(val);
            nf = nf(valid); val = val(valid);
            if isempty(nf); return; end
            [nf, idx] = sort(nf); val = val(idx);
            hold(ax, 'on');
            plot(ax, nf, val, '-o', 'LineWidth', 2, 'MarkerSize', 7, ...
                'MarkerFaceColor', Theme.COLOR_PRIMARY, ...
                'Color', Theme.COLOR_PRIMARY);
            mitVal = JsonHelper.pickNumeric(qae, 'mitigated_amplitude', NaN);
            if ~isnan(mitVal)
                scatter(ax, 0, mitVal, 90, 'filled', ...
                    'MarkerFaceColor', Theme.COLOR_SUCCESS, ...
                    'MarkerEdgeColor', 'none');
                text(ax, 0.05, mitVal, ' c=0 (mitigated)', ...
                    'FontSize', 9, 'Color', Theme.COLOR_SUCCESS, ...
                    'Interpreter', 'none');
            end
            hold(ax, 'off');
        end

        function renderEmGammaDepthCurve(~, app)
            ax = app.EmGammaDepthAxes;
            if isempty(ax) || ~isvalid(ax); return; end
            cla(ax);
            ax.XGrid = 'on'; ax.YGrid = 'on';
            ax.XScale = 'log'; ax.YScale = 'log';
            eplg = NaN;
            try
                backend = char(app.EmBackendDropdown.Value);
                if ~isempty(backend) && app.State.isAuthenticated()
                    cal = app.BackendSvc.getCalibration(backend, app.State.authToken);
                    eplg = AnalysisViewModel.extractEplg(cal);
                end
            catch ME
                Logger.debug('AnalysisViewModel', ...
                    'EM gamma curve calibration miss: %s', ME.message);
            end
            if isnan(eplg) || eplg <= 0
                text(ax, 0.5, 0.5, ...
                    'EPLG / 2Q error not available for this backend', ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                    'Color', Theme.COLOR_MUTED, 'Interpreter', 'none');
                return;
            end
            gammaBar = AnalysisViewModel.computeGammaBar(eplg);
            if isnan(gammaBar); return; end
            depthRange = logspace(0, 4, 60);
            overhead = arrayfun(@(d) AnalysisViewModel.computeGammaBarOverhead(gammaBar, d), depthRange);
            hold(ax, 'on');
            plot(ax, depthRange, overhead, '-', 'LineWidth', 2, ...
                'Color', Theme.COLOR_PRIMARY);
            yline(ax, 1e4, '--', 'classical-sim threshold', ...
                'Color', Theme.COLOR_DANGER, ...
                'LabelHorizontalAlignment', 'left', ...
                'Interpreter', 'none');
            curDepth = AnalysisViewModel.pickDepth(app.EmCircuitMeta);
            if ~isnan(curDepth) && curDepth > 0
                xline(ax, curDepth, ':', ...
                    sprintf('this circuit (depth=%d)', round(curDepth)), ...
                    'Color', Theme.COLOR_HEADING, ...
                    'LabelHorizontalAlignment', 'center', ...
                    'Interpreter', 'none');
            end
            hold(ax, 'off');
        end

        function renderEmOverheadCutsCurve(obj, app)
            ax = app.EmOverheadCutsAxes;
            if isempty(ax) || ~isvalid(ax); return; end
            cla(ax);
            ax.XGrid = 'on'; ax.YGrid = 'on';
            ax.XScale = 'linear'; ax.YScale = 'log';
            % Theoretical 4^k baseline always renders, even before async lands.
            kRange = 0:8;
            theoretical = 4 .^ kRange;
            hold(ax, 'on');
            plot(ax, kRange, theoretical, '--', ...
                'Color', Theme.COLOR_MUTED, 'LineWidth', 1.5);
            yline(ax, 1e4, '--', 'feasibility', ...
                'Color', Theme.COLOR_DANGER, ...
                'Interpreter', 'none');
            hold(ax, 'off');
            if ~app.State.isAuthenticated() || ~app.State.hasCircuit(); return; end
            cid = char(app.State.selectedCircuitId);
            cuttingSvc = app.CuttingSvc;
            token      = app.State.authToken;
            AsyncRunner.run( ...
                @() cuttingSvc.analyzeCuts(cid, [], token), ...
                @(data) obj.onEmCuttingAnalyzed(app, data), ...
                @(ME)   Logger.debug('AnalysisViewModel', ...
                    'EM cutting analyze: %s', ME.message));
        end

        function onEmCuttingAnalyzed(~, app, data)
            ax = app.EmOverheadCutsAxes;
            if isempty(ax) || ~isvalid(ax); return; end
            app.EmCuttingCached = data;
            k = JsonHelper.pickNumeric(data, 'k', NaN);
            overhead = JsonHelper.pickNumeric(data, 'sampling_overhead', NaN);
            overheadLog = JsonHelper.pickNumeric(data, 'sampling_overhead_log10', NaN);
            if (isnan(overhead) || overhead <= 0) && ~isnan(overheadLog)
                overhead = 10^overheadLog;
            end
            if isnan(k) || isnan(overhead) || overhead <= 0; return; end
            hold(ax, 'on');
            scatter(ax, k, overhead, 120, 'filled', ...
                'MarkerFaceColor', Theme.COLOR_PRIMARY, ...
                'MarkerEdgeColor', 'none');
            text(ax, k+0.2, overhead, sprintf(' k=%d, %.1fx', round(k), overhead), ...
                'FontSize', 10, 'Color', Theme.COLOR_PRIMARY, ...
                'Interpreter', 'none');
            hold(ax, 'off');
        end

        function renderEmTechniqueTable(~, app, bundle)
            if isempty(app.EmTechniqueTable) || ~isvalid(app.EmTechniqueTable); return; end
            n = numel(bundle);
            rows = cell(n, 5);
            for i = 1:n
                b = bundle{i};
                est = b.estimate;
                if isempty(est)
                    rows(i,:) = {b.label, '-', '-', '-', ''};
                    continue;
                end
                cost = JsonHelper.pick(est, {'cost'}, struct());
                shotMul = JsonHelper.pickNumeric(cost, 'shot_multiplier', 1.0);
                wall    = JsonHelper.pickNumeric(cost, 'est_wall_seconds', NaN);
                bias    = AnalysisViewModel.estimateBiasReduction(b.levelId);
                rows{i,1} = b.label;
                rows{i,2} = sprintf('%.1fx', bias);
                rows{i,3} = sprintf('%.2fx', shotMul);
                if isnan(wall); rows{i,4} = '-'; else; rows{i,4} = sprintf('%.1f', wall); end
                rows{i,5} = '';
            end
            pick = AnalysisViewModel.bestRecommendation(bundle);
            if ~isempty(pick)
                for i = 1:n
                    if bundle{i}.levelId == pick.levelId
                        rows{i,5} = char(10003);   % checkmark
                        break;
                    end
                end
            end
            app.EmTechniqueTable.Data = rows;
        end

        function renderEmRecommendation(~, app, bundle)
            if isempty(app.EmRecommendationLabel) || ~isvalid(app.EmRecommendationLabel); return; end
            pick = AnalysisViewModel.bestRecommendation(bundle);
            if isempty(pick) || isempty(pick.estimate)
                app.EmRecommendationLabel.Text = Labels.get('em_recommendation_empty', ...
                    'Pick a backend and circuit to see a recommendation.');
                return;
            end
            cost = JsonHelper.pick(pick.estimate, {'cost'}, struct());
            shotMul = JsonHelper.pickNumeric(cost, 'shot_multiplier', 1.0);
            wall    = JsonHelper.pickNumeric(cost, 'est_wall_seconds', NaN);
            bias    = AnalysisViewModel.estimateBiasReduction(pick.levelId);
            if isnan(wall); wallS = '?'; else; wallS = sprintf('%.1fs', wall); end
            txt = sprintf(['Pick: %s\n' ...
                           '  est. bias reduction: %.1fx\n' ...
                           '  shot overhead:       %.2fx\n' ...
                           '  est. wall-clock:     %s\n\n' ...
                           'Heuristic ranking - review the table for full tradeoffs.'], ...
                pick.label, bias, shotMul, wallS);
            app.EmRecommendationLabel.Text = txt;
        end

        function renderEmRawMitigatedHistogram(~, app, qae)
            ax = app.EmHistogramAxes;
            if isempty(ax) || ~isvalid(ax); return; end
            cla(ax);
            if isempty(qae); return; end
            counts = JsonHelper.pick(qae, {'raw_counts','counts'}, []);
            if isempty(counts); return; end
            [labels, vals] = AnalysisViewModel.pickTopBitstrings(counts, 8);
            if isempty(labels); return; end
            bar(ax, vals, 'FaceColor', Theme.COLOR_PRIMARY, 'EdgeColor', 'none');
            ax.XTick = 1:numel(labels);
            ax.XTickLabel = labels;
            ax.XTickLabelRotation = 45;
            ax.TickLabelInterpreter = 'none';
            ax.XGrid = 'off'; ax.YGrid = 'on';
        end

        function applyEmStatusBanner(~, app, hasQae)
            if isempty(app.EmStatusBanner) || ~isvalid(app.EmStatusBanner); return; end
            if hasQae
                app.EmStatusBanner.Text = Labels.get('em_footer_hint', '');
                app.EmStatusBanner.FontColor = Theme.COLOR_MUTED;
            else
                app.EmStatusBanner.Text = Labels.get('em_status_no_qae_result', ...
                    'No measured QMC result yet on this circuit.');
                app.EmStatusBanner.FontColor = Theme.COLOR_WARNING;
            end
        end
    end
end
