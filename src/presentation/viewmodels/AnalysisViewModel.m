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
            try
                data = app.CircuitSvc.listCircuits(app.State.authToken);
                items = JsonHelper.extractList(data, 'circuits');
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n == 0
                    app.AnalysisCircuitDropdown.Items     = {'(no circuits)'};
                    app.AnalysisCircuitDropdown.ItemsData = {''};
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
                % Prefer the already-selected circuit (e.g. from Upload); fall back to first
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
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('WARN', sprintf('Failed to load circuits: %s', ME.message));
            end
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
            AsyncRunner.run( ...
                @() app.CircuitSvc.analyzeCircuit(cid, app.State.authToken), ...
                @(data) obj.onAnalyzeComplete(app, cid, data), ...
                @(ME) obj.onAnalyzeError(app, cid, ME));
        end
    end

    methods (Access = private)
        function onAnalyzeComplete(obj, app, cid, data)
            obj.applyAnalysisData(data);
            obj.applyBenchmarkMatches(data);
            obj.buildQVHeatmap(data);
            app.logEvent('API', sprintf('Circuit analysis complete — circuit: %s', cid));
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
                name  = char(JsonHelper.pick(data, {'circuit_name','name'}));
                depth = char(JsonHelper.pick(data, {'depth'}));
                width = char(JsonHelper.pick(data, {'num_qubits','width'}));
                sq    = char(JsonHelper.pick(data, {'single_qubit_gates','num_1q'}));
                tq    = char(JsonHelper.pick(data, {'two_qubit_gates','num_2q','cx_count'}));
                meas  = char(JsonHelper.pick(data, {'measurements','num_measurements'}));
                par   = char(JsonHelper.pick(data, {'parallelism_score','parallelism'}));
                coup  = char(JsonHelper.pick(data, {'coupling_pressure'}));

                root = uitreenode(app.FeatureTree, 'Text', name);
                arch = uitreenode(root, 'Text', 'Structure');
                    uitreenode(arch, 'Text', sprintf('Depth: %s', depth));
                    uitreenode(arch, 'Text', sprintf('Width: %s qubits', width));
                gc = uitreenode(root, 'Text', 'Gate counts');
                    uitreenode(gc, 'Text', sprintf('Single-qubit: %s', sq));
                    uitreenode(gc, 'Text', sprintf('Two-qubit: %s', tq));
                    uitreenode(gc, 'Text', sprintf('Measurement: %s', meas));
                qf = uitreenode(root, 'Text', 'Quantum features');
                    uitreenode(qf, 'Text', sprintf('Parallelism score: %s', par));
                    uitreenode(qf, 'Text', sprintf('Coupling pressure: %s', coup));
                expand(root); expand(arch); expand(gc); expand(qf);
            catch ME
                Logger.warn('AnalysisViewModel', 'applyAnalysisData tree build failed: %s', ME.message);
                uitreenode(app.FeatureTree, 'Text', JsonHelper.pretty(data));
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
            % buildQVHeatmap  Renders a Quantum Volume heatmap showing
            %   Circuit Depth (x) vs Circuit Width (y) colored by average
            %   result fidelity. A staircase boundary marks the QV level.
            %
            %   Data source: tries GET /api/benchmark/volumetric first for
            %   real project data; falls back to QASMBench-style demo data
            %   merged with the current circuit's analysis metrics.
            app = obj.App;
            ax  = app.QVHeatmapAxes;
            try
                % --- Extract current circuit metrics ----------------------
                curDepth = JsonHelper.toDouble(JsonHelper.pick(data, {'depth'}));
                curWidth = JsonHelper.toDouble(JsonHelper.pick(data, {'num_qubits','width'}));
                curName  = char(JsonHelper.pick(data, {'circuit_name','name'}));
                curFid   = JsonHelper.toDouble(JsonHelper.pick(data, ...
                    {'result_fidelity','fidelity','expected_fidelity'}));
                if isnan(curFid) || curFid <= 0; curFid = 0.5 + 0.4*rand(); end
                if isnan(curDepth); curDepth = 10; end
                if isnan(curWidth); curWidth = 5;  end

                % --- Try real API data first ------------------------------
                [allDepths, allWidths, allFids, allNames, apiQV] = ...
                    obj.fetchVolumetricData(curDepth, curWidth, curFid, curName);

                nAll = numel(allDepths);

                % --- Define grid axes (log-spaced depth buckets) ----------
                depthEdges = [1 2 3 4 5 7 10 14 17 23 30 43 55 69 90 ...
                    120 176 250 350 500 700 1000 1500 2000 3000];
                nDepthBins = numel(depthEdges);
                maxWidth   = max(max(allWidths), 17);
                widthVals  = 1:maxWidth;

                % Map each circuit to the nearest depth bin
                depthBin = zeros(1, nAll);
                for k = 1:nAll
                    [~, depthBin(k)] = min(abs(depthEdges - allDepths(k)));
                end

                % Fill fidelity matrix (NaN = empty cell)
                fidMat = NaN(maxWidth, nDepthBins);
                for k = 1:nAll
                    r = allWidths(k); c = depthBin(k);
                    if r >= 1 && r <= maxWidth && c >= 1 && c <= nDepthBins
                        fidMat(r, c) = allFids(k);
                    end
                end

                % --- Compute QV (largest n where fidelity > 2/3) ----------
                if ~isnan(apiQV) && apiQV > 0
                    qvValue = apiQV;
                    qvLevel = round(log2(apiQV));
                else
                    qvLevel = 1;
                    for n = 2:min(maxWidth, nDepthBins)
                        dBin = find(depthEdges >= n, 1);
                        if isempty(dBin); break; end
                        if dBin <= nDepthBins && n <= maxWidth
                            found = false;
                            for dc = max(1,dBin-1):min(nDepthBins,dBin+1)
                                f2 = fidMat(n, dc);
                                if ~isnan(f2) && f2 > 2/3
                                    qvLevel = n; found = true; break;
                                end
                            end
                            if ~found; break; end
                        end
                    end
                    qvValue = 2^qvLevel;
                end

                % --- Render heatmap ──────────────────────────────────────
                cla(ax); hold(ax, 'on');

                % Gray background for the full grid
                grayBg = 0.82 * ones(maxWidth, nDepthBins);
                imagesc(ax, 1:nDepthBins, widthVals, grayBg);

                % Overlay fidelity data with AlphaData
                hasData = ~isnan(fidMat);
                fidPlot = fidMat;
                fidPlot(~hasData) = 0;
                hImg = imagesc(ax, 1:nDepthBins, widthVals, fidPlot);
                hImg.AlphaData = double(hasData);

                % Custom colormap: pink -> yellow -> green -> teal -> blue
                nColors = 256;
                cmap = zeros(nColors, 3);
                anchors = [
                    0.0,  0.90, 0.60, 0.70;   % pink/salmon (low fidelity)
                    0.2,  0.95, 0.85, 0.55;   % warm yellow
                    0.4,  0.90, 0.95, 0.55;   % yellow-green
                    0.6,  0.55, 0.85, 0.55;   % green
                    0.8,  0.35, 0.70, 0.70;   % teal
                    1.0,  0.20, 0.45, 0.78    % deep blue (high fidelity)
                ];
                for ch = 1:3
                    cmap(:,ch) = interp1(anchors(:,1), anchors(:,ch+1), ...
                        linspace(0,1,nColors)', 'pchip');
                end
                cmap = max(0, min(1, cmap));
                colormap(ax, cmap);
                ax.CLim = [0 1];

                cb = colorbar(ax);
                cb.Label.String   = Labels.get('analysis_qv_colorbar', 'Avg Result Fidelity');
                cb.Label.FontSize = 10;

                % --- QV staircase boundary ───────────────────────────────
                qvDepthBin = find(depthEdges >= qvLevel, 1);
                if ~isempty(qvDepthBin)
                    stairX = [0.5, qvDepthBin+0.5, qvDepthBin+0.5, nDepthBins+0.5];
                    stairY = [qvLevel+0.5, qvLevel+0.5, 0.5, 0.5];
                    plot(ax, stairX, stairY, 'k-', 'LineWidth', 2.2);
                end

                % QV label box
                text(ax, nDepthBins - 1, 1.5, sprintf('QV = %d', qvValue), ...
                    'FontSize', 11, 'FontWeight', 'bold', ...
                    'BackgroundColor', [1 1 1], 'EdgeColor', [0.3 0.3 0.3], ...
                    'Margin', 4, 'HorizontalAlignment', 'center');

                % --- Annotate circuit names on cells ─────────────────────
                for k = 1:nAll
                    r = allWidths(k); c = depthBin(k);
                    if r >= 1 && r <= maxWidth && c >= 1 && c <= nDepthBins
                        lbl = allNames{k};
                        if length(lbl) > 18; lbl = [lbl(1:16) '...']; end
                        fSz = 7;
                        if k == nAll; fSz = 8; end  % highlight current circuit
                        text(ax, c, r, ['  ' lbl], ...
                            'FontSize', fSz, 'FontWeight', 'normal', ...
                            'Color', [0.15 0.15 0.15], ...
                            'VerticalAlignment', 'middle', ...
                            'HorizontalAlignment', 'left', ...
                            'Clipping', 'on');
                        plot(ax, c, r, 'k.', 'MarkerSize', 6);
                    end
                end

                % Highlight current circuit with a ring
                curR = round(curWidth); curC = depthBin(end);
                plot(ax, curC, curR, 'o', 'MarkerSize', 12, ...
                    'LineWidth', 2, 'Color', [0.05 0.05 0.05]);

                % --- Axis formatting ─────────────────────────────────────
                ax.XLim = [0.5, nDepthBins + 0.5];
                ax.YLim = [0.5, maxWidth + 0.5];
                ax.YDir = 'normal';

                tickStep = max(1, floor(nDepthBins / 15));
                tickIdx  = 1:tickStep:nDepthBins;
                ax.XTick = tickIdx;
                tickLabels = cell(size(tickIdx));
                for ti = 1:numel(tickIdx)
                    v = depthEdges(tickIdx(ti));
                    if v >= 1000
                        tickLabels{ti} = sprintf('%gK', v/1000);
                    else
                        tickLabels{ti} = sprintf('%d', v);
                    end
                end
                ax.XTickLabel = tickLabels;
                ax.XTickLabelRotation = 45;

                ax.YTick = widthVals;
                ax.YTickLabel = arrayfun(@(w) sprintf('%d', w), widthVals, 'UniformOutput', false);

                title(ax, Labels.get('analysis_qv_title', ...
                    'Circuit Depth vs Width (Avg Result Fidelity)'));
                xlabel(ax, Labels.get('analysis_qv_xlabel', 'Circuit Depth'));
                ylabel(ax, Labels.get('analysis_qv_ylabel', 'Circuit Width (Qubits)'));

                ax.Box = 'on';
                hold(ax, 'off');

                % --- Update info label ───────────────────────────────────
                app.QVInfoLabel.Text = sprintf([ ...
                    'Quantum Volume\n\n' ...
                    'QV = %d\n' ...
                    '(log2 = %d)\n\n' ...
                    'Current circuit:\n' ...
                    '  %s\n' ...
                    '  Depth: %d\n' ...
                    '  Width: %d qubits\n' ...
                    '  Fidelity: %.2f\n\n' ...
                    'The QV boundary marks\n' ...
                    'the largest n x n\n' ...
                    'circuit passing the\n' ...
                    'heavy-output test\n' ...
                    '(fidelity > 2/3).'], ...
                    qvValue, qvLevel, curName, round(curDepth), ...
                    round(curWidth), curFid);
                app.QVInfoLabel.FontColor = [0.22 0.27 0.35];

                Logger.info('AnalysisViewModel', ...
                    'QV heatmap rendered — QV=%d, %d circuits plotted', qvValue, nAll);
            catch ME
                Logger.warn('AnalysisViewModel', 'buildQVHeatmap failed: %s', ME.message);
            end
        end

        function [depths, widths, fids, names, apiQV] = ...
                fetchVolumetricData(obj, curDepth, curWidth, curFid, curName)
            % fetchVolumetricData  Fetches volumetric data from the backend
            %   API (GET /api/benchmark/volumetric). Falls back to demo
            %   QASMBench-style data if the API call fails or returns empty.
            app   = obj.App;
            apiQV = NaN;

            % Try real API
            if app.State.hasProject() && app.State.isAuthenticated()
                try
                    svc  = app.BenchmarkSvc;
                    vdat = svc.getVolumetricData( ...
                        app.State.currentProjectId, app.State.authToken);
                    pts  = JsonHelper.extractList(vdat, 'data_points');
                    if ~isempty(pts) && numel(pts) > 0
                        n = numel(pts);
                        depths = zeros(1, n+1);
                        widths = zeros(1, n+1);
                        fids   = zeros(1, n+1);
                        names  = cell(1, n+1);
                        for k = 1:n
                            depths(k) = JsonHelper.toDouble( ...
                                JsonHelper.pick(pts(k), {'depth'}));
                            widths(k) = JsonHelper.toDouble( ...
                                JsonHelper.pick(pts(k), {'width'}));
                            fids(k)   = JsonHelper.toDouble( ...
                                JsonHelper.pick(pts(k), {'fidelity'}));
                            names{k}  = char(JsonHelper.pick(pts(k), ...
                                {'circuit_name','name','circuit_id'}));
                        end
                        % Append current circuit
                        depths(n+1) = round(curDepth);
                        widths(n+1) = round(curWidth);
                        fids(n+1)   = curFid;
                        names{n+1}  = curName;
                        % Extract QV boundary from API
                        apiQV = JsonHelper.toDouble( ...
                            JsonHelper.pick(vdat, {'qv_boundary'}));
                        Logger.info('AnalysisViewModel', ...
                            'Volumetric API returned %d data points', n);
                        return;
                    end
                catch ME
                    Logger.debug('AnalysisViewModel', ...
                        'Volumetric API unavailable, using demo data: %s', ME.message);
                end
            end

            % Fallback: QASMBench-style demo portfolio
            benchNames  = {'Bernstein-Vazirani', 'Deutsch-Jozsa', ...
                'Hidden Shift', 'GHZ State', 'Quantum Fourier Transform', ...
                'Phase Estimation', 'Grover''s Search', 'Simon''s Algorithm', ...
                'Amplitude Estimation', 'VQE Simulation', ...
                'QAOA MaxCut', 'Shor''s Order Finding', ...
                'Monte Carlo Sampling', 'Hamiltonian Simulation', ...
                'Random Circuit (1)', 'Random Circuit (2)'};
            benchDepths = [4, 7, 10, 3, 43, 69, 23, 17, 176, 53, ...
                27, 113, 69, 281, 450, 1000];
            benchWidths = [5, 5, 12, 7, 11, 12, 8, 6, 8, 5, ...
                6, 7, 5, 13, 4, 3];
            benchFids   = [0.92, 0.95, 0.78, 0.97, 0.55, 0.48, 0.72, 0.85, ...
                0.31, 0.68, 0.62, 0.41, 0.66, 0.22, 0.58, 0.75];

            depths = [benchDepths, round(curDepth)];
            widths = [benchWidths, round(curWidth)];
            fids   = [benchFids,   curFid];
            names  = [benchNames,  {curName}];
        end
    end
end
