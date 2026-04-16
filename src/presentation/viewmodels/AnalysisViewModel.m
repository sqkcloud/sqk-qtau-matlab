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
                dlg = uifigure('Name', 'QASMBench Similarity Visualization', ...
                    'Position', [dlgX dlgY dlgW dlgH], ...
                    'Resize', 'on', 'Color', [1 1 1]);

                rootGrid = uigridlayout(dlg, [3 1]);
                rootGrid.RowHeight = {'1x', 1, 40};
                rootGrid.Padding = [0 0 0 0]; rootGrid.RowSpacing = 0;
                rootGrid.BackgroundColor = [1 1 1];

                % ── Tab group ───────────────────────────────────────────────
                tg = uitabgroup(rootGrid);
                tg.Layout.Row = 1; tg.Layout.Column = 1;

                % ══════════════════════════════════════════════════════════════
                % Tab 1: QASMBench Similarity Visualization
                %   Single focused ranked-bar chart with auto-scaled X axis
                %   (tight similarity bands of 97–98% become visually
                %   differentiated) + a Match Profile side panel that
                %   surfaces the current circuit, category breakdown, and
                %   a calibrated interpretation of the top match.
                % ══════════════════════════════════════════════════════════════
                tab1 = uitab(tg, 'Title', 'QASMBench Similarity Visualization');
                tab1.BackgroundColor = [1 1 1];

                dg = uigridlayout(tab1, [2 2]);
                dg.RowHeight = {40, '1x'};
                dg.ColumnWidth = {'2x', '1x'};
                dg.Padding = [18 14 18 12]; dg.RowSpacing = 8; dg.ColumnSpacing = 16;
                dg.BackgroundColor = [1 1 1];

                % ── Header: current circuit + headline summary ──────────────
                curCircName = char(app.State.selectedCircuitName);
                if isempty(curCircName); curCircName = 'current circuit'; end
                [topSim, topIdx] = max(sims);
                headerLbl = uilabel(dg, ...
                    'Text', sprintf(['Circuit:  %s      ' ...
                                     'Closest of %d matches:  %s  (%.1f%%)'], ...
                                    curCircName, n, dispNames{topIdx}, topSim*100), ...
                    'FontSize', 13, 'FontWeight', 'bold', ...
                    'FontColor', [0.15 0.22 0.38], ...
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
                    'FontWeight', 'bold', 'BackgroundColor', [0.98 0.99 1.00], ...
                    'ForegroundColor', [0.20 0.28 0.45]);
                profilePanel.Layout.Row = 2; profilePanel.Layout.Column = 2;

                ppg = uigridlayout(profilePanel, [1 1]);
                ppg.Padding = [12 10 12 10];
                ppg.BackgroundColor = [0.98 0.99 1.00];

                profileArea = uitextarea(ppg, 'Editable', 'off');
                profileArea.FontSize = 12;
                profileArea.FontColor = [0.18 0.22 0.30];
                profileArea.Value = AnalysisViewModel.buildMatchProfileText( ...
                    curCircName, dispNames, sims, cats, notes, uniqueCats, topIdx);

                % ══════════════════════════════════════════════════════════════
                % Tab 2: Circuit Diagram
                % ══════════════════════════════════════════════════════════════
                tab2 = uitab(tg, 'Title', 'Circuit Diagram');
                tab2.BackgroundColor = [1 1 1];

                tab2Grid = uigridlayout(tab2, [1 1]);
                tab2Grid.Padding = [16 14 16 10]; tab2Grid.BackgroundColor = [1 1 1];
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
                sep.BackgroundColor = [0.85 0.87 0.90];

                % ── Close button (right-aligned) ───────────────────────────
                btnGrid = uigridlayout(rootGrid, [1 2]);
                btnGrid.Layout.Row = 3; btnGrid.Layout.Column = 1;
                btnGrid.ColumnWidth = {'1x', 140};
                btnGrid.Padding = [16 4 16 4]; btnGrid.BackgroundColor = [1 1 1];
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
                interp = 'Moderate match — broadly comparable to QASMBench peers.';
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

    end

    methods (Access = private)
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
                catch ME; Logger.debug('AnalysisViewModel', 'buildFeatureSummary QASMBench similarity: %s', ME.message); end

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
                app.QVInfoLabel.FontColor = [0.22 0.27 0.35];

                Logger.info('AnalysisViewModel', ...
                    'Complexity landscape rendered — %s d=%d w=%d fid=%.2f', ...
                    curName, round(curDepth), round(curWidth), curFid);
            catch ME
                Logger.warn('AnalysisViewModel', 'buildQVHeatmap failed: %s', ME.message);
            end
        end
    end
end
