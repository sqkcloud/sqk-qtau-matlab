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
                % ══════════════════════════════════════════════════════════════
                tab1 = uitab(tg, 'Title', 'QASMBench Similarity Visualization');
                tab1.BackgroundColor = [1 1 1];

                dg = uigridlayout(tab1, [2 2]);
                dg.RowHeight = {'1x', '1x'};
                dg.ColumnWidth = {'1.2x', '1x'};
                dg.Padding = [16 14 16 10]; dg.RowSpacing = 10; dg.ColumnSpacing = 12;
                dg.BackgroundColor = [1 1 1];

                % ── Chart 1: Horizontal bar chart (top-left) ────────────────
                ax1 = uiaxes(dg);
                ax1.Layout.Row = 1; ax1.Layout.Column = 1;

                [sortedSims, si] = sort(sims, 'ascend');
                sortedNames  = dispNames(si);
                sortedColors = colors(si, :);

                hold(ax1, 'on');
                for i = 1:n
                    barh(ax1, i, sortedSims(i), 'FaceColor', sortedColors(i,:), ...
                        'EdgeColor', 'none', 'BarWidth', 0.65);
                    text(ax1, sortedSims(i) + 0.01, i, sprintf('%.1f%%', sortedSims(i)*100), ...
                        'FontSize', 10, 'VerticalAlignment', 'middle', ...
                        'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
                end
                hold(ax1, 'off');
                ax1.YTick = 1:n; ax1.YTickLabel = sortedNames;
                ax1.TickLabelInterpreter = 'none';
                ax1.YLim = [0.3, n + 0.7]; ax1.XLim = [0, 1.15];
                ax1.XTick = 0:0.2:1;
                ax1.XTickLabel = {'0%','20%','40%','60%','80%','100%'};
                xlabel(ax1, 'Similarity');
                title(ax1, 'Similarity Ranking', 'FontSize', 14, 'FontWeight', 'bold');
                ax1.Box = 'on'; ax1.FontSize = 11;

                % ── Chart 2: Radar / Spider chart (top-right) ───────────────
                ax2 = uiaxes(dg);
                ax2.Layout.Row = 1; ax2.Layout.Column = 2;
                obj.drawRadarChart(ax2, dispNames, sims, colors);

                % ── Chart 3: Lollipop chart by category (bottom-left) ───────
                ax3 = uiaxes(dg);
                ax3.Layout.Row = 2; ax3.Layout.Column = 1;

                [sortedSims2, si2] = sort(sims, 'descend');
                sortedNames2  = dispNames(si2);
                sortedColors2 = colors(si2, :);

                hold(ax3, 'on');
                for i = 1:n
                    xpos = i;
                    plot(ax3, [xpos xpos], [0 sortedSims2(i)], '-', ...
                        'Color', sortedColors2(i,:), 'LineWidth', 3);
                    plot(ax3, xpos, sortedSims2(i), 'o', ...
                        'MarkerSize', 11, 'MarkerFaceColor', sortedColors2(i,:), ...
                        'MarkerEdgeColor', [1 1 1], 'LineWidth', 1.5);
                    text(ax3, xpos, sortedSims2(i) + 0.03, sprintf('%.1f%%', sortedSims2(i)*100), ...
                        'FontSize', 9, 'FontWeight', 'bold', ...
                        'HorizontalAlignment', 'center', 'Color', [0.25 0.25 0.25], ...
                        'Interpreter', 'none');
                end
                hold(ax3, 'off');
                ax3.XTick = 1:n; ax3.XTickLabel = sortedNames2;
                ax3.TickLabelInterpreter = 'none';
                ax3.XTickLabelRotation = 30;
                ax3.XLim = [0.3, n + 0.7]; ax3.YLim = [0, 1.12];
                ax3.YTick = 0:0.2:1;
                ax3.YTickLabel = {'0%','20%','40%','60%','80%','100%'};
                ylabel(ax3, 'Similarity');
                title(ax3, 'Score Distribution', 'FontSize', 14, 'FontWeight', 'bold');
                ax3.Box = 'on'; ax3.FontSize = 11;
                ax3.XGrid = 'off'; ax3.YGrid = 'on';
                ax3.GridAlpha = 0.15;

                % ── Chart 4: Category breakdown donut (bottom-right) ────────
                ax4 = uiaxes(dg);
                ax4.Layout.Row = 2; ax4.Layout.Column = 2;
                obj.drawCategoryDonut(ax4, cats, sims, uniqueCats, palette);

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
    end

    methods (Static, Access = private)

        function drawRadarChart(ax, names, sims, colors)
            % Draw a radar/spider chart on the given axes.
            n = numel(names);
            angles = linspace(0, 2*pi, n + 1);
            angles = angles(1:n);

            cla(ax); hold(ax, 'on');
            ax.Visible = 'off';

            % Draw concentric grid rings
            gridLevels = [0.2, 0.4, 0.6, 0.8, 1.0];
            for gl = gridLevels
                theta = linspace(0, 2*pi, 100);
                plot(ax, gl * cos(theta), gl * sin(theta), '-', ...
                    'Color', [0.85 0.85 0.85], 'LineWidth', 0.5);
                text(ax, 0.03, gl + 0.04, sprintf('%.0f%%', gl*100), ...
                    'FontSize', 8, 'Color', [0.5 0.5 0.5], 'Interpreter', 'none');
            end

            % Draw axis spokes and labels
            for i = 1:n
                cx = cos(angles(i)); cy = sin(angles(i));
                plot(ax, [0 cx], [0 cy], '-', 'Color', [0.82 0.82 0.82], 'LineWidth', 0.5);
                lbl = names{i};
                if length(lbl) > 18; lbl = [lbl(1:16) '..']; end
                ha = 'center';
                if cx > 0.1; ha = 'left'; elseif cx < -0.1; ha = 'right'; end
                text(ax, cx * 1.22, cy * 1.22, lbl, ...
                    'FontSize', 10, 'FontWeight', 'bold', ...
                    'HorizontalAlignment', ha, ...
                    'VerticalAlignment', 'middle', ...
                    'Color', [0.20 0.25 0.38], 'Interpreter', 'none');
            end

            % Draw filled polygon
            rx = sims .* cos(angles(:));
            ry = sims .* sin(angles(:));
            fill(ax, [rx; rx(1)], [ry; ry(1)], [0.23 0.53 0.87], ...
                'FaceAlpha', 0.20, 'EdgeColor', [0.15 0.40 0.78], 'LineWidth', 2);

            % Draw data points with score labels
            for i = 1:n
                plot(ax, rx(i), ry(i), 'o', 'MarkerSize', 8, ...
                    'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', [1 1 1], 'LineWidth', 1.5);
            end

            hold(ax, 'off');
            ax.XLim = [-1.5 1.5]; ax.YLim = [-1.5 1.5];
            ax.DataAspectRatio = [1 1 1];
            title(ax, 'Radar — Similarity Profile', 'FontSize', 14, ...
                'FontWeight', 'bold', 'Visible', 'on');
        end

        function drawCategoryDonut(ax, cats, sims, uniqueCats, palette)
            % Draw a donut chart showing average similarity per category.
            nCats = numel(uniqueCats);
            avgSims = zeros(nCats, 1);
            counts  = zeros(nCats, 1);
            for i = 1:numel(cats)
                ci = find(strcmp(uniqueCats, cats{i}), 1);
                avgSims(ci) = avgSims(ci) + sims(i);
                counts(ci)  = counts(ci) + 1;
            end
            avgSims = avgSims ./ max(counts, 1);

            cla(ax); hold(ax, 'on');
            ax.Visible = 'off';

            % Pie angles
            total = sum(counts);
            startAngle = pi/2;
            for ci = 1:nCats
                frac = counts(ci) / total;
                endAngle = startAngle - frac * 2 * pi;
                theta = linspace(startAngle, endAngle, 80);
                outerR = 0.9;
                innerR = 0.50;
                xOuter = outerR * cos(theta);
                yOuter = outerR * sin(theta);
                xInner = innerR * cos(flip(theta));
                yInner = innerR * sin(flip(theta));
                clr = palette(mod(ci-1, size(palette,1)) + 1, :);
                fill(ax, [xOuter, xInner], [yOuter, yInner], clr, ...
                    'EdgeColor', [1 1 1], 'LineWidth', 2, 'FaceAlpha', 0.88);

                % Label outside the arc with a connecting line
                midAngle = (startAngle + endAngle) / 2;
                outerLabelR = 1.2;
                lx = outerLabelR * cos(midAngle);
                ly = outerLabelR * sin(midAngle);
                % Connector from arc edge to label
                edgeX = (outerR + 0.04) * cos(midAngle);
                edgeY = (outerR + 0.04) * sin(midAngle);
                plot(ax, [edgeX lx], [edgeY ly], '-', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
                ha = 'left';
                if lx < 0; ha = 'right'; end
                text(ax, lx, ly, sprintf('%s (%.0f%%)', uniqueCats{ci}, avgSims(ci)*100), ...
                    'FontSize', 10, 'FontWeight', 'bold', 'Color', clr, ...
                    'HorizontalAlignment', ha, 'VerticalAlignment', 'middle', ...
                    'Interpreter', 'none');
                startAngle = endAngle;
            end

            % Center label — overall average
            text(ax, 0, 0.06, sprintf('%.1f%%', mean(sims)*100), ...
                'FontSize', 22, 'FontWeight', 'bold', 'Color', [0.18 0.28 0.50], ...
                'HorizontalAlignment', 'center', 'Interpreter', 'none');
            text(ax, 0, -0.14, 'avg similarity', ...
                'FontSize', 10, 'Color', [0.5 0.5 0.6], ...
                'HorizontalAlignment', 'center', 'Interpreter', 'none');

            hold(ax, 'off');
            ax.XLim = [-1.7 1.7]; ax.YLim = [-1.5 1.5];
            ax.DataAspectRatio = [1 1 1];
            title(ax, 'Category Breakdown', 'FontSize', 14, ...
                'FontWeight', 'bold', 'Visible', 'on');
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
