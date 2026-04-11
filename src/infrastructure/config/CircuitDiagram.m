classdef CircuitDiagram
    % CircuitDiagram  Generate ASCII/HTML circuit diagrams from QASM content.
    %
    %   Usage:  lines = CircuitDiagram.render(qasmText)       % plain text
    %           html  = CircuitDiagram.renderHtml(qasmText)   % colored HTML
    %           src   = CircuitDiagram.wrapHtml(text)         % wrap in page

    methods (Static)

        function lines = render(content)
            % render  Parse QASM content and produce ASCII circuit diagram lines.
            try
                [nQubits, gates] = CircuitDiagram.parseGates(content);
                if nQubits == 0 || isempty(gates)
                    lines = {'(No gates detected)'};
                    return;
                end
                lines = CircuitDiagram.drawDiagram(nQubits, gates);
            catch ME
                Logger.warn('CircuitDiagram', 'render failed: %s', ME.message);
                lines = {'(Unable to render circuit diagram)'};
            end
        end

        function html = renderHtml(content)
            % renderHtml  Parse QASM and produce a colored HTML circuit diagram.
            try
                [nQubits, gates] = CircuitDiagram.parseGates(content);
                if nQubits == 0 || isempty(gates)
                    html = '<span style="color:#888">(No gates detected)</span>';
                    return;
                end
                html = CircuitDiagram.drawHtmlDiagram(nQubits, gates);
            catch ME
                Logger.warn('CircuitDiagram', 'renderHtml failed: %s', ME.message);
                html = '<span style="color:#888">(Unable to render circuit diagram)</span>';
            end
        end

        function svg = renderSvg(content)
            % renderSvg  Parse QASM and produce a graphical SVG circuit diagram
            %            with colored gate boxes, wires, control dots, measurements,
            %            per-qubit probabilities, and a probability distribution chart.
            %
            %            For large circuits, parsing is capped at 200 gates to keep
            %            the preview responsive.  A truncation notice is shown.
            maxGatesForPreview = 2000;
            try
                [nQubits, gates, wasTruncated] = CircuitDiagram.parseGates(content, maxGatesForPreview);
                if nQubits == 0 || isempty(gates)
                    svg = '<p style="color:#888;font-family:sans-serif">(No gates detected)</p>';
                    return;
                end
                % Simulate circuit to get state vector and probabilities
                % (only for small qubit counts AND when we have the full circuit)
                stateVec = [];
                if nQubits <= 16 && ~wasTruncated
                    try
                        stateVec = CircuitDiagram.simulateCircuit(nQubits, gates);
                    catch ME2
                        Logger.warn('CircuitDiagram', 'simulation failed: %s', ME2.message);
                    end
                end
                circuitSvg = CircuitDiagram.drawSvgDiagram(nQubits, gates, stateVec);
                parts = {'<div style="display:flex;flex-direction:column;align-items:center;gap:16px;">'};
                parts{end+1} = circuitSvg;
                if wasTruncated
                    parts{end+1} = ['<p style="color:#8b95a8;font-family:-apple-system,sans-serif;' ...
                        'font-size:11px;margin:4px 0 0 0;text-align:center;">' ...
                        sprintf('Showing first %d gates (circuit truncated for preview)', numel(gates)) ...
                        '</p>'];
                end
                if ~isempty(stateVec)
                    parts{end+1} = CircuitDiagram.drawProbDistSvg(nQubits, stateVec);
                end
                parts{end+1} = '</div>';
                svg = strjoin(parts, '');
            catch ME
                Logger.warn('CircuitDiagram', 'renderSvg failed: %s', ME.message);
                svg = '<p style="color:#888;font-family:sans-serif">(Unable to render diagram)</p>';
            end
        end

        function s = escapeHtml(text)
            % escapeHtml  Encode &, <, >, ", ' for safe insertion into HTML.
            s = char(string(text));
            s = strrep(s, '&', '&amp;');
            s = strrep(s, '<', '&lt;');
            s = strrep(s, '>', '&gt;');
            s = strrep(s, '"', '&quot;');
            s = strrep(s, '''', '&#39;');
        end

        function src = wrapHtml(text)
            % wrapHtml  Wrap plain text or HTML body in a styled HTML page
            %           suitable for uihtml.HTMLSource.
            if iscell(text)
                text = strjoin(text, newline);
            end
            safeText = CircuitDiagram.escapeHtml(text);
            src = [ ...
                '<html><head><style>' ...
                'html,body{height:100%;margin:0;padding:0;}' ...
                'body{display:flex;align-items:center;justify-content:center;overflow:auto;}' ...
                'pre{font-family:"Courier New",monospace;font-size:11px;' ...
                'color:#232a36;line-height:1.6;margin:0;}' ...
                '</style></head><body><pre>' ...
                safeText ...
                '</pre></body></html>'];
        end

        function src = buildStatsHtml(infoLines, diagramHtml)
            % buildStatsHtml  Wrap SVG or HTML diagram for uihtml display.
            %   Uses a wrapper div for centering so that overflow scrolling
            %   works correctly for large diagrams (many qubits / columns).
            src = [ ...
                '<html><head><style>' ...
                'html,body{width:100%;height:100%;margin:0;padding:0;overflow:auto;' ...
                'background:#111827;}' ...
                '.wrap{display:inline-flex;flex-direction:column;align-items:center;' ...
                'min-width:100%;min-height:100%;padding:12px;box-sizing:border-box;}' ...
                '</style></head><body>' ...
                '<div class="wrap">' char(diagramHtml) '</div>' ...
                '</body></html>'];
        end

    end

    methods (Static, Access = private)

        function [nQubits, gates, wasTruncated] = parseGates(content, maxGates)
            % Parse qubit declarations and gate operations from QASM text.
            % maxGates: stop after this many gates (default unlimited).
            if nargin < 2; maxGates = inf; end
            nQubits = 0;
            gates = {};  % each entry: struct with .name, .qubits (0-based indices)
            wasTruncated = false;
            % For large content with a gate limit, only split the first
            % portion to avoid creating a huge cell array.
            if isfinite(maxGates) && numel(content) > 500000
                % Keep header + enough lines for maxGates (generous 10x factor)
                maxChars = min(numel(content), maxGates * 200);
                truncContent = content(1:maxChars);
                lastNL = find(truncContent == newline, 1, 'last');
                if ~isempty(lastNL); truncContent = truncContent(1:lastNL); end
                % Also scan full content for qreg declarations (usually in first 1KB)
                headerEnd = min(numel(content), 2000);
                headerPart = content(1:headerEnd);
                headerTok = regexp(headerPart, '(?:qreg\s+\w+\[(\d+)\]|qubit\[(\d+)\])', 'tokens');
                for j = 1:numel(headerTok)
                    vals = headerTok{j};
                    for m = 1:numel(vals)
                        if ~isempty(vals{m}); nQubits = nQubits + str2double(vals{m}); end
                    end
                end
                lines = strsplit(truncContent, newline);
            else
                lines = strsplit(content, newline);
            end
            for k = 1:numel(lines)
                ln = strtrim(lines{k});
                if isempty(ln) || startsWith(ln, '//') || startsWith(ln, 'OPENQASM') ...
                        || startsWith(ln, 'include') || startsWith(ln, 'creg') ...
                        || startsWith(ln, 'bit[') || startsWith(ln, 'const ') ...
                        || startsWith(ln, 'float[') || startsWith(ln, 'for ') ...
                        || startsWith(ln, '}')
                    continue;
                end

                % qreg q[N]; or qubit[N] name;
                tok = regexp(ln, '(?:qreg\s+\w+\[(\d+)\]|qubit\[(\d+)\])', 'tokens');
                for j = 1:numel(tok)
                    vals = tok{j};
                    for m = 1:numel(vals)
                        if ~isempty(vals{m}); nQubits = nQubits + str2double(vals{m}); end
                    end
                end

                % Single-qubit gates: h q[0]; rx(0.5) q[1]; measure q[0] -> c[0];
                tok1 = regexp(ln, '^\s*(h|x|y|z|s|t|sdg|tdg|rx|ry|rz|u[123]?|id|sx|measure)\s*(?:\(([^)]*)\))?\s+\w+\[(\d+)\]', 'tokens');
                if ~isempty(tok1)
                    toks = tok1{1};
                    gName = upper(toks{1});
                    if numel(toks) == 3
                        paramStr = toks{2};
                        qIdx = str2double(toks{3});
                    else
                        paramStr = '';
                        qIdx = str2double(toks{2});
                    end
                    if strcmp(gName, 'MEASURE'); gName = 'M'; end
                    gates{end+1} = struct('name', gName, 'qubits', qIdx, 'params', paramStr); %#ok<AGROW>
                    if numel(gates) >= maxGates; wasTruncated = true; break; end
                    continue;
                end

                % Bulk measure: c = measure q;
                if ~isempty(regexp(ln, '=\s*measure\s+\w+\s*;', 'once'))
                    for qi = 0:max(nQubits-1, 0)
                        gates{end+1} = struct('name', 'M', 'qubits', qi, 'params', ''); %#ok<AGROW>
                    end
                    if numel(gates) >= maxGates; wasTruncated = true; break; end
                    continue;
                end

                % Three-qubit gates: ccx q[0], q[1], q[2]; (must match before two-qubit)
                tok3 = regexp(ln, '^\s*(ccx|cswap)\s*(?:\([^)]*\))?\s+\w+\[(\d+)\]\s*,\s*\w+\[(\d+)\]\s*,\s*\w+\[(\d+)\]', 'tokens');
                if ~isempty(tok3)
                    gName = upper(tok3{1}{1});
                    q1 = str2double(tok3{1}{2});
                    q2 = str2double(tok3{1}{3});
                    q3 = str2double(tok3{1}{4});
                    gates{end+1} = struct('name', gName, 'qubits', [q1, q2, q3], 'params', ''); %#ok<AGROW>
                    if numel(gates) >= maxGates; wasTruncated = true; break; end
                    continue;
                end

                % Two-qubit gates: cx q[0], q[1]; cz q[0], q[1]; swap q[0], q[1];
                tok2 = regexp(ln, '^\s*(cx|cz|cy|ch|cu1|cu2|cu3|swap)\s*(?:\([^)]*\))?\s+\w+\[(\d+)\]\s*,\s*\w+\[(\d+)\]', 'tokens');
                if ~isempty(tok2)
                    gName = upper(tok2{1}{1});
                    q1 = str2double(tok2{1}{2});
                    q2 = str2double(tok2{1}{3});
                    gates{end+1} = struct('name', gName, 'qubits', [q1, q2], 'params', ''); %#ok<AGROW>
                    if numel(gates) >= maxGates; wasTruncated = true; break; end
                    continue;
                end
            end
            % Ensure nQubits covers all referenced qubit indices
            maxRef = 0;
            for gi = 1:numel(gates)
                maxRef = max(maxRef, max(gates{gi}.qubits));
            end
            nQubits = max(nQubits, maxRef + 1);
            nQubits = max(nQubits, 1);
        end

        function lines = drawDiagram(nQubits, gates)
            % Build ASCII diagram from parsed gates.
            % Each qubit gets a wire. Gates are placed in columns.
            % Limit display to first 20 gate columns for readability.
            maxCols = 20;
            nGates = numel(gates);

            % Assign each gate to a time column (greedy left-packing)
            colAssign = zeros(1, nGates);
            qubitNextFree = zeros(1, nQubits);  % next free column per qubit
            for gi = 1:nGates
                qIdxs = gates{gi}.qubits + 1;  % 1-based
                earliest = max(qubitNextFree(qIdxs));
                colAssign(gi) = earliest;
                % For multi-qubit gates, block all wires between min and max qubit
                if numel(qIdxs) > 1
                    minQ = min(qIdxs); maxQ = max(qIdxs);
                    qubitNextFree(minQ:maxQ) = earliest + 1;
                else
                    qubitNextFree(qIdxs) = earliest + 1;
                end
            end

            totalCols = max(colAssign) + 1;
            truncated = totalCols > maxCols;
            displayCols = min(totalCols, maxCols);

            % Build a grid: each cell is the symbol for that qubit/column
            % Default is wire segment '---'
            cellWidth = 5;
            grid = repmat({''}, nQubits, displayCols);

            for gi = 1:nGates
                col = colAssign(gi) + 1;  % 1-based
                if col > displayCols; continue; end
                g = gates{gi};
                qIdxs = g.qubits + 1;  % 1-based

                if numel(qIdxs) == 1
                    % Single-qubit gate
                    grid{qIdxs, col} = g.name;
                elseif numel(qIdxs) == 2
                    q1 = qIdxs(1); q2 = qIdxs(2);
                    if strcmpi(g.name, 'CX')
                        grid{q1, col} = '@';   % control
                        grid{q2, col} = 'X';   % target
                    elseif strcmpi(g.name, 'CZ')
                        grid{q1, col} = '@';
                        grid{q2, col} = 'Z';
                    elseif strcmpi(g.name, 'SWAP')
                        grid{q1, col} = 'x';
                        grid{q2, col} = 'x';
                    elseif startsWith(g.name, 'CU') || strcmpi(g.name, 'CH') || strcmpi(g.name, 'CY')
                        grid{q1, col} = '@';
                        grid{q2, col} = g.name(2:end);
                    else
                        grid{q1, col} = '@';
                        grid{q2, col} = g.name;
                    end
                    % Mark intermediate qubits with vertical connector
                    minQ = min(q1, q2); maxQ = max(q1, q2);
                    for qi = minQ+1:maxQ-1
                        if isempty(grid{qi, col})
                            grid{qi, col} = '|';
                        end
                    end
                elseif numel(qIdxs) == 3
                    grid{qIdxs(1), col} = '@';
                    grid{qIdxs(2), col} = '@';
                    grid{qIdxs(3), col} = 'X';
                    minQ = min(qIdxs); maxQ = max(qIdxs);
                    for qi = minQ+1:maxQ-1
                        if isempty(grid{qi, col})
                            grid{qi, col} = '|';
                        end
                    end
                end
            end

            % Render lines
            labelWidth = length(sprintf('q[%d]', nQubits - 1)) + 2;
            lines = cell(1, nQubits);
            for qi = 1:nQubits
                label = sprintf('q[%d]', qi - 1);
                label = [label, repmat(' ', 1, labelWidth - length(label))]; %#ok<AGROW>
                wire = '';
                for ci = 1:displayCols
                    sym = grid{qi, ci};
                    if isempty(sym)
                        seg = repmat('-', 1, cellWidth);
                    else
                        symLen = length(sym);
                        padTotal = max(cellWidth - symLen, 0);
                        padL = floor(padTotal / 2);
                        padR = padTotal - padL;
                        seg = [repmat('-', 1, padL), sym, repmat('-', 1, padR)];
                    end
                    wire = [wire, seg]; %#ok<AGROW>
                end
                if truncated
                    wire = [wire, '--...']; %#ok<AGROW>
                else
                    wire = [wire, '--']; %#ok<AGROW>
                end
                lines{qi} = [label, wire];
            end

            % Add legend line
            if truncated
                lines{end+1} = '';
                lines{end+1} = sprintf('(%d gates shown of %d total)', displayCols, numel(gates));
            end
        end

        function html = drawHtmlDiagram(nQubits, gates)
            % Build colored HTML circuit diagram using the same layout as drawDiagram.
            [grid, nQubits2, displayCols, cellWidth, truncated, nGatesTotal] = ...
                CircuitDiagram.buildGrid(nQubits, gates);

            wireColor   = '#94a3b8';  % gray wire
            labelColor  = '#6366f1';  % indigo qubit labels

            labelWidth = length(sprintf('q[%d]', nQubits2 - 1)) + 2;
            htmlLines = cell(1, nQubits2);
            for qi = 1:nQubits2
                label = sprintf('q[%d]', qi - 1);
                label = [label, repmat(' ', 1, labelWidth - length(label))]; %#ok<AGROW>
                labelHtml = sprintf('<span style="color:%s;font-weight:bold">%s</span>', labelColor, label);

                wire = '';
                for ci = 1:displayCols
                    sym = grid{qi, ci};
                    if isempty(sym)
                        seg = sprintf('<span style="color:%s">%s</span>', wireColor, repmat('-', 1, cellWidth));
                    else
                        symLen = length(sym);
                        padTotal = max(cellWidth - symLen, 0);
                        padL = floor(padTotal / 2);
                        padR = padTotal - padL;
                        clr = CircuitDiagram.gateColor(sym);
                        dashL = sprintf('<span style="color:%s">%s</span>', wireColor, repmat('-', 1, padL));
                        dashR = sprintf('<span style="color:%s">%s</span>', wireColor, repmat('-', 1, padR));
                        gateSym = sprintf('<span style="color:%s;font-weight:bold">%s</span>', clr, sym);
                        seg = [dashL, gateSym, dashR];
                    end
                    wire = [wire, seg]; %#ok<AGROW>
                end
                if truncated
                    wire = [wire, sprintf('<span style="color:%s">--...</span>', wireColor)]; %#ok<AGROW>
                else
                    wire = [wire, sprintf('<span style="color:%s">--</span>', wireColor)]; %#ok<AGROW>
                end
                htmlLines{qi} = [labelHtml, wire];
            end

            html = strjoin(htmlLines, newline);
            if truncated
                html = [html, newline, newline, ...
                    sprintf('<span style="color:#888">(%d columns shown of %d total)</span>', ...
                    displayCols, nGatesTotal)];
            end
        end

        function [grid, nQubits, displayCols, cellWidth, truncated, nGatesTotal] = buildGrid(nQubits, gates, maxCols)
            % Shared grid-building logic used by both drawDiagram and drawHtmlDiagram.
            if nargin < 3; maxCols = 20; end
            nGates = numel(gates);
            nGatesTotal = nGates;
            colAssign = zeros(1, nGates);
            qubitNextFree = zeros(1, nQubits);
            for gi = 1:nGates
                qIdxs = gates{gi}.qubits + 1;
                earliest = max(qubitNextFree(qIdxs));
                colAssign(gi) = earliest;
                if numel(qIdxs) > 1
                    minQ = min(qIdxs); maxQ = max(qIdxs);
                    qubitNextFree(minQ:maxQ) = earliest + 1;
                else
                    qubitNextFree(qIdxs) = earliest + 1;
                end
            end
            totalCols = max(colAssign) + 1;
            truncated = totalCols > maxCols;
            displayCols = min(totalCols, maxCols);
            cellWidth = 5;
            grid = repmat({''}, nQubits, displayCols);
            for gi = 1:nGates
                col = colAssign(gi) + 1;
                if col > displayCols; continue; end
                g = gates{gi};
                qIdxs = g.qubits + 1;
                if numel(qIdxs) == 1
                    grid{qIdxs, col} = g.name;
                elseif numel(qIdxs) == 2
                    q1 = qIdxs(1); q2 = qIdxs(2);
                    if strcmpi(g.name, 'CX')
                        grid{q1, col} = '@'; grid{q2, col} = 'X';
                    elseif strcmpi(g.name, 'CZ')
                        grid{q1, col} = '@'; grid{q2, col} = 'Z';
                    elseif strcmpi(g.name, 'SWAP')
                        grid{q1, col} = 'x'; grid{q2, col} = 'x';
                    elseif startsWith(g.name, 'CU') || strcmpi(g.name, 'CH') || strcmpi(g.name, 'CY')
                        grid{q1, col} = '@'; grid{q2, col} = g.name(2:end);
                    else
                        grid{q1, col} = '@'; grid{q2, col} = g.name;
                    end
                    minQ = min(q1, q2); maxQ = max(q1, q2);
                    for qi = minQ+1:maxQ-1
                        if isempty(grid{qi, col}); grid{qi, col} = '|'; end
                    end
                elseif numel(qIdxs) == 3
                    grid{qIdxs(1), col} = '@'; grid{qIdxs(2), col} = '@'; grid{qIdxs(3), col} = 'X';
                    minQ = min(qIdxs); maxQ = max(qIdxs);
                    for qi = minQ+1:maxQ-1
                        if isempty(grid{qi, col}); grid{qi, col} = '|'; end
                    end
                end
            end
        end

        function svg = drawSvgDiagram(nQubits, gates, stateVec)
            % drawSvgDiagram  Render a graphical SVG circuit diagram
            %   with dark theme, blue gate boxes, wires, control dots, measurements,
            %   and per-qubit measurement probabilities.
            if nargin < 3, stateVec = []; end

            % Layout constants
            gateW   = 38;   % gate box width
            gateH   = 32;   % gate box height
            colW    = 52;   % column spacing
            rowH    = 54;   % row spacing (qubit wire spacing)
            labelW  = 80;   % left margin for qubit labels
            padR    = 24;   % right padding
            padT    = 16;   % top padding
            padB    = 16;   % bottom padding
            maxCols = 10000; % max gate columns to display
            probW   = 110;  % width reserved for probability labels on the right

            % Dark theme colors
            bgColor     = '#111827';  % dark charcoal background
            wireColor   = '#4B5563';  % subtle gray wires
            labelColor  = '#D1D5DB';  % light gray labels
            ctrlDot     = '#93C5FD';  % light blue control dot
            ctrlLine    = '#60A5FA';  % blue connector lines
            cnotFill    = '#2563EB';  % blue CNOT target
            cnotStroke  = '#3B82F6';
            swapColor   = '#F59E0B';  % amber SWAP
            measFill    = '#1E293B';  % dark slate measurement box
            measStroke  = '#475569';
            truncColor  = '#6B7280';  % muted text
            probColor   = '#34D399';  % emerald green for probability text
            probBarBg   = '#1F2937';  % dark bar background
            probBarFill = '#10B981';  % emerald bar fill

            hasProbs = ~isempty(stateVec);

            % Build the grid using existing buildGrid
            [grid, ~, displayCols, ~, truncated, ~] = ...
                CircuitDiagram.buildGrid(nQubits, gates, maxCols);

            % Compute per-qubit P(|1>) if we have state vector
            qubitProbs = zeros(1, nQubits);
            if hasProbs
                N = length(stateVec);
                probs = abs(stateVec).^2;
                allIdx = (0:N-1);
                for qi = 0:nQubits-1
                    mask1 = bitand(allIdx, (2^qi)) > 0;
                    qubitProbs(qi+1) = sum(probs(mask1));
                end
            end

            circuitEndX = labelW + displayCols * colW;
            extraRight = 0;
            if hasProbs; extraRight = probW; end
            svgW = circuitEndX + padR + extraRight;
            svgH = padT + nQubits * rowH + padB;

            parts = {};
            parts{end+1} = sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', ...
                svgW, svgH, svgW, svgH);
            parts{end+1} = '<style>text{font-family:"Segoe UI",Arial,sans-serif;}</style>';

            % Dark background
            parts{end+1} = sprintf('<rect width="%d" height="%d" rx="8" fill="%s"/>', svgW, svgH, bgColor);

            % Draw qubit wires and per-qubit probability labels
            wireEndX = circuitEndX + 5;
            if hasProbs
                % Draw a dashed separator line before probability section
                sepX = circuitEndX + 12;
                parts{end+1} = sprintf('<line x1="%.0f" y1="%d" x2="%.0f" y2="%.0f" stroke="%s" stroke-width="1" stroke-dasharray="4,4"/>', ...
                    sepX, padT + 4, sepX, padT + nQubits * rowH - 4, '#374151');
            end
            for qi = 1:nQubits
                wy = padT + (qi - 0.5) * rowH;
                parts{end+1} = sprintf('<line x1="%d" y1="%.0f" x2="%.0f" y2="%.0f" stroke="%s" stroke-width="1.2"/>', ...
                    labelW - 5, wy, wireEndX, wy, wireColor);
                % Qubit label
                parts{end+1} = sprintf('<text x="%d" y="%.0f" font-size="12" font-weight="600" fill="%s" text-anchor="end" dominant-baseline="middle">q[%d]</text>', ...
                    labelW - 12, wy, labelColor, qi - 1);
                % Ket label (right side of qubit name)
                parts{end+1} = sprintf('<text x="%d" y="%.0f" font-size="10" fill="%s" text-anchor="end" dominant-baseline="middle" opacity="0.5">|0&#x27E9;</text>', ...
                    labelW - 1, wy, labelColor);

                % Per-qubit probability bar + label
                if hasProbs
                    pVal = qubitProbs(qi) * 100;
                    barX = circuitEndX + 20;
                    barW = 52;
                    barH = 12;
                    barY = wy - barH/2;
                    % Background bar
                    parts{end+1} = sprintf('<rect x="%.0f" y="%.0f" width="%d" height="%d" rx="3" fill="%s"/>', ...
                        barX, barY, barW, barH, probBarBg);
                    % Filled bar (proportional to probability)
                    fillW = max(round(barW * qubitProbs(qi)), 0);
                    if fillW > 0
                        parts{end+1} = sprintf('<rect x="%.0f" y="%.0f" width="%d" height="%d" rx="3" fill="%s" opacity="0.8"/>', ...
                            barX, barY, fillW, barH, probBarFill);
                    end
                    % Percentage text
                    parts{end+1} = sprintf('<text x="%.0f" y="%.0f" font-size="10" font-weight="600" fill="%s" dominant-baseline="middle">%.1f%%</text>', ...
                        barX + barW + 6, wy, probColor, pVal);
                end
            end

            % Draw gates
            for ci = 1:displayCols
                cx = labelW + (ci - 0.5) * colW;  % center x of this column
                for qi = 1:nQubits
                    sym = grid{qi, ci};
                    if isempty(sym); continue; end
                    cy = padT + (qi - 0.5) * rowH;  % center y of this qubit

                    if strcmp(sym, '@')
                        % Control dot — light blue filled circle
                        parts{end+1} = sprintf('<circle cx="%.0f" cy="%.0f" r="6" fill="%s" stroke="%s" stroke-width="1.5"/>', ...
                            cx, cy, ctrlDot, bgColor);
                    elseif strcmp(sym, '|')
                        % Vertical connector (drawn below with multi-qubit lines)
                    elseif strcmp(sym, 'X') && CircuitDiagram.isTarget(grid, qi, ci)
                        % CNOT target — circled plus
                        parts{end+1} = sprintf('<circle cx="%.0f" cy="%.0f" r="13" fill="%s" stroke="%s" stroke-width="1.5"/>', ...
                            cx, cy, cnotFill, cnotStroke);
                        parts{end+1} = sprintf('<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="white" stroke-width="2"/>', cx-8, cy, cx+8, cy);
                        parts{end+1} = sprintf('<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="white" stroke-width="2"/>', cx, cy-8, cx, cy+8);
                    elseif strcmp(sym, 'M')
                        % Measurement — dark slate box with meter icon
                        bx = cx - gateW/2; by = cy - gateH/2;
                        parts{end+1} = sprintf('<rect x="%.0f" y="%.0f" width="%d" height="%d" rx="4" fill="%s" stroke="%s" stroke-width="1.2"/>', ...
                            bx, by, gateW, gateH, measFill, measStroke);
                        % Meter arc
                        parts{end+1} = sprintf('<path d="M%.0f,%.0f A8,8 0 0,1 %.0f,%.0f" fill="none" stroke="#93C5FD" stroke-width="1.5"/>', ...
                            cx-7, cy+4, cx+7, cy+4);
                        % Meter needle
                        parts{end+1} = sprintf('<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="#93C5FD" stroke-width="1.5"/>', ...
                            cx, cy+4, cx+5, cy-6);
                    elseif strcmp(sym, 'x')
                        % SWAP — X mark in amber
                        parts{end+1} = sprintf('<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="%s" stroke-width="2.5"/>', cx-7, cy-7, cx+7, cy+7, swapColor);
                        parts{end+1} = sprintf('<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="%s" stroke-width="2.5"/>', cx+7, cy-7, cx-7, cy+7, swapColor);
                    else
                        % Standard gate box — blue theme
                        clr = CircuitDiagram.svgGateColor(sym);
                        bx = cx - gateW/2; by = cy - gateH/2;
                        parts{end+1} = sprintf('<rect x="%.0f" y="%.0f" width="%d" height="%d" rx="5" fill="%s" stroke="%s" stroke-width="1.2"/>', ...
                            bx, by, gateW, gateH, clr.bg, clr.border);
                        fs = 13;
                        if length(sym) > 2; fs = 10; end
                        if length(sym) > 3; fs = 9; end
                        parts{end+1} = sprintf('<text x="%.0f" y="%.0f" font-size="%d" font-weight="bold" fill="white" text-anchor="middle" dominant-baseline="central">%s</text>', ...
                            cx, cy, fs, sym);
                    end
                end

                % Draw vertical connectors for multi-qubit gates in this column
                qubitsInCol = [];
                for qi = 1:nQubits
                    sym = grid{qi, ci};
                    if ~isempty(sym)
                        qubitsInCol(end+1) = qi; %#ok<AGROW>
                    end
                end
                if numel(qubitsInCol) >= 2
                    minQ = min(qubitsInCol); maxQ = max(qubitsInCol);
                    y1 = padT + (minQ - 0.5) * rowH;
                    y2 = padT + (maxQ - 0.5) * rowH;
                    parts{end+1} = sprintf('<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="%s" stroke-width="2"/>', ...
                        cx, y1, cx, y2, ctrlLine);
                end
            end

            if truncated
                tx = svgW - padR - 5;
                ty = padT + nQubits * rowH + 2;
                parts{end+1} = sprintf('<text x="%.0f" y="%.0f" font-size="10" fill="%s" text-anchor="end">(...truncated)</text>', tx, ty, truncColor);
            end

            parts{end+1} = '</svg>';
            svg = strjoin(parts, newline);
        end

        function tf = isTarget(grid, qi, ci)
            % Check if there is a control dot (@) in the same column on another qubit
            tf = false;
            for r = 1:size(grid, 1)
                if r ~= qi && strcmp(grid{r, ci}, '@')
                    tf = true; return;
                end
            end
        end

        function clr = svgGateColor(sym)
            % Return background and border colors for SVG gate boxes (dark theme).
            switch sym
                case {'H','S','T','SDG','TDG','ID','SX'}
                    clr = struct('bg', '#1D4ED8', 'border', '#3B82F6');  % blue — basis gates
                case {'X','Y','Z'}
                    clr = struct('bg', '#1E40AF', 'border', '#2563EB');  % deep blue — Pauli
                case {'RX','RY','RZ'}
                    clr = struct('bg', '#1E3A8A', 'border', '#3B82F6');  % navy — rotation
                case {'U1','U2','U3'}
                    clr = struct('bg', '#1E3A8A', 'border', '#3B82F6');  % navy — unitary
                case {'CCX','CSWAP'}
                    clr = struct('bg', '#312E81', 'border', '#6366F1');  % indigo — 3-qubit
                otherwise
                    clr = struct('bg', '#1D4ED8', 'border', '#3B82F6');  % blue default
            end
        end

        function clr = gateColor(sym)
            % Return a CSS color for a gate symbol.
            switch sym
                case {'H','S','T','SDG','TDG','ID','SX'}
                    clr = '#2563EB';  % blue — single-qubit basis
                case {'X','Y','Z'}
                    clr = '#DC2626';  % red — Pauli gates
                case {'RX','RY','RZ'}
                    clr = '#D97706';  % amber — rotation gates
                case {'@'}
                    clr = '#7C3AED';  % purple — control dot
                case {'|'}
                    clr = '#7C3AED';  % purple — vertical connector
                case {'M'}
                    clr = '#059669';  % green — measurement
                case {'x'}
                    clr = '#EA580C';  % orange — swap
                otherwise
                    clr = '#2563EB';  % blue — default gate
            end
        end

        % ── Statevector simulator ─────────────────────────────────────

        function stateVec = simulateCircuit(nQubits, gates)
            % simulateCircuit  Lightweight statevector simulation of a quantum circuit.
            %   Returns the state vector (complex column, length 2^nQubits).
            %   Skips measurement gates; supports up to 16 qubits.
            N = 2^nQubits;
            sv = zeros(N, 1);
            sv(1) = 1;  % |00...0>

            for gi = 1:numel(gates)
                g = gates{gi};
                if strcmp(g.name, 'M'); continue; end  % skip measurements

                qs = g.qubits;  % 0-based qubit indices
                if numel(qs) == 1
                    U = CircuitDiagram.gateMatrix(g.name, g.params);
                    if ~isempty(U)
                        sv = CircuitDiagram.applySingleGate(sv, nQubits, qs(1), U);
                    end
                elseif numel(qs) == 2
                    sv = CircuitDiagram.applyTwoQubitGate(sv, nQubits, qs, g.name);
                elseif numel(qs) == 3
                    sv = CircuitDiagram.applyThreeQubitGate(sv, nQubits, qs, g.name);
                end
            end
            stateVec = sv;
        end

        function sv = applySingleGate(sv, nQubits, q, U)
            % Apply a 2x2 unitary U to qubit q (0-based) in the state vector.
            N = 2^nQubits;
            allIdx = (0:N-1);
            mask0 = bitand(allIdx, (2^q)) == 0;
            idx0 = find(mask0);        % 1-based indices where qubit q = 0
            idx1 = idx0 + (2^q); % corresponding indices where qubit q = 1
            a = sv(idx0);
            b = sv(idx1);
            sv(idx0) = U(1,1)*a + U(1,2)*b;
            sv(idx1) = U(2,1)*a + U(2,2)*b;
        end

        function sv = applyTwoQubitGate(sv, nQubits, qs, name)
            % Apply a two-qubit gate. qs = [control, target] (0-based).
            ctrl = qs(1); tgt = qs(2);
            N = 2^nQubits;
            allIdx = (0:N-1);

            switch name
                case 'CX'
                    % CNOT: flip target when control = 1
                    mask = (bitand(allIdx, (2^ctrl)) > 0) & ...
                           (bitand(allIdx, (2^tgt)) == 0);
                    idx0 = find(mask);
                    idx1 = idx0 + (2^tgt);
                    temp = sv(idx0); sv(idx0) = sv(idx1); sv(idx1) = temp;
                case 'CZ'
                    % CZ: phase-flip when both qubits = 1
                    mask = (bitand(allIdx, (2^ctrl)) > 0) & ...
                           (bitand(allIdx, (2^tgt)) > 0);
                    idxBoth = find(mask);
                    sv(idxBoth) = -sv(idxBoth);
                case 'CY'
                    % CY: apply Y to target when control = 1
                    Y = [0 -1i; 1i 0];
                    mask = (bitand(allIdx, (2^ctrl)) > 0) & ...
                           (bitand(allIdx, (2^tgt)) == 0);
                    idx0 = find(mask);
                    idx1 = idx0 + (2^tgt);
                    a = sv(idx0); b = sv(idx1);
                    sv(idx0) = Y(1,1)*a + Y(1,2)*b;
                    sv(idx1) = Y(2,1)*a + Y(2,2)*b;
                case 'CH'
                    % CH: apply H to target when control = 1
                    H = [1 1; 1 -1]/sqrt(2);
                    mask = (bitand(allIdx, (2^ctrl)) > 0) & ...
                           (bitand(allIdx, (2^tgt)) == 0);
                    idx0 = find(mask);
                    idx1 = idx0 + (2^tgt);
                    a = sv(idx0); b = sv(idx1);
                    sv(idx0) = H(1,1)*a + H(1,2)*b;
                    sv(idx1) = H(2,1)*a + H(2,2)*b;
                case 'SWAP'
                    % SWAP: swap two qubits
                    q1 = qs(1); q2 = qs(2);
                    mask = (bitand(allIdx, (2^q1)) > 0) & ...
                           (bitand(allIdx, (2^q2)) == 0);
                    idx_10 = find(mask);   % q1=1, q2=0
                    idx_01 = idx_10 - (2^q1) + (2^q2);  % q1=0, q2=1
                    temp = sv(idx_10); sv(idx_10) = sv(idx_01); sv(idx_01) = temp;
                otherwise
                    % Controlled-U variants (CU1, CU2, CU3): skip for now
            end
        end

        function sv = applyThreeQubitGate(sv, nQubits, qs, name)
            % Apply a three-qubit gate. For CCX (Toffoli): flip target when both controls = 1.
            N = 2^nQubits;
            allIdx = (0:N-1);
            if strcmp(name, 'CCX')
                c1 = qs(1); c2 = qs(2); tgt = qs(3);
                mask = (bitand(allIdx, (2^c1)) > 0) & ...
                       (bitand(allIdx, (2^c2)) > 0) & ...
                       (bitand(allIdx, (2^tgt)) == 0);
                idx0 = find(mask);
                idx1 = idx0 + (2^tgt);
                temp = sv(idx0); sv(idx0) = sv(idx1); sv(idx1) = temp;
            end
            % CSWAP: skip for simplicity
        end

        function U = gateMatrix(name, paramStr)
            % Return 2x2 unitary matrix for single-qubit gates.
            if nargin < 2, paramStr = ''; end
            switch name
                case 'H';   U = [1 1; 1 -1]/sqrt(2);
                case 'X';   U = [0 1; 1 0];
                case 'Y';   U = [0 -1i; 1i 0];
                case 'Z';   U = [1 0; 0 -1];
                case 'S';   U = [1 0; 0 1i];
                case 'SDG'; U = [1 0; 0 -1i];
                case 'T';   U = [1 0; 0 exp(1i*pi/4)];
                case 'TDG'; U = [1 0; 0 exp(-1i*pi/4)];
                case 'SX';  U = [1+1i 1-1i; 1-1i 1+1i]/2;
                case 'ID';  U = eye(2);
                case 'RX'
                    theta = CircuitDiagram.parseParam(paramStr);
                    U = [cos(theta/2), -1i*sin(theta/2); -1i*sin(theta/2), cos(theta/2)];
                case 'RY'
                    theta = CircuitDiagram.parseParam(paramStr);
                    U = [cos(theta/2), -sin(theta/2); sin(theta/2), cos(theta/2)];
                case 'RZ'
                    theta = CircuitDiagram.parseParam(paramStr);
                    U = [exp(-1i*theta/2), 0; 0, exp(1i*theta/2)];
                case 'U1'
                    lam = CircuitDiagram.parseParam(paramStr);
                    U = [1 0; 0 exp(1i*lam)];
                otherwise
                    U = [];  % unknown gate — skip
            end
        end

        function val = parseParam(paramStr)
            % Parse a numeric parameter string, supporting pi expressions.
            % Uses safe arithmetic evaluation — never eval() — to prevent
            % code injection from malicious QASM gate parameters.
            val = 0;
            if isempty(paramStr); return; end
            paramStr = strtrim(char(paramStr));
            % Substitute 'pi' with its numeric value
            paramStr = strrep(paramStr, 'pi', num2str(pi, '%.15g'));
            % Reject anything that isn't a safe arithmetic expression
            if ~isempty(regexp(paramStr, '[^0-9eE.+\-*/() ]', 'once'))
                return;
            end
            % Try str2num for simple arithmetic (runs in a restricted
            % numeric context — no function calls or variable access).
            try
                result = str2num(paramStr); %#ok<ST2NM>
                if ~isempty(result) && isscalar(result) && isfinite(result)
                    val = result;
                end
            catch
                val = 0;
            end
        end

        % ── Probability distribution bar chart ────────────────────────

        function svg = drawProbDistSvg(nQubits, stateVec)
            % drawProbDistSvg  Render an SVG bar chart of measurement probabilities.
            %   X-axis: computational basis states
            %   Y-axis: measurement probability (%)

            bgColor    = '#111827';
            barFill    = '#3B82F6';
            barHover   = '#60A5FA';
            gridColor  = '#1F2937';
            axisColor  = '#374151';
            textColor  = '#9CA3AF';
            labelColor = '#D1D5DB';
            titleColor = '#E5E7EB';

            probs = abs(stateVec).^2;
            N = length(probs);

            % For large state spaces, show only top-K most probable states
            maxBars = 32;
            if N > maxBars
                [sortedP, sortedI] = sort(probs, 'descend');
                showIdx = sort(sortedI(1:maxBars));  % keep sorted by index
                showProbs = probs(showIdx);
                showLabels = cell(1, maxBars);
                for k = 1:maxBars
                    showLabels{k} = CircuitDiagram.basisLabel(showIdx(k)-1, nQubits);
                end
                isFiltered = true;
            else
                showIdx = 1:N;
                showProbs = probs(:)';
                showLabels = cell(1, N);
                for k = 1:N
                    showLabels{k} = CircuitDiagram.basisLabel(k-1, nQubits);
                end
                isFiltered = false;
            end

            nBars = numel(showProbs);
            maxProb = max(showProbs) * 100;
            if maxProb == 0; maxProb = 1; end
            % Round up y-axis max to nice value
            if maxProb <= 5;      yMax = 5;
            elseif maxProb <= 10; yMax = 10;
            elseif maxProb <= 25; yMax = 25;
            elseif maxProb <= 50; yMax = 50;
            else;                 yMax = 100;
            end

            % Chart dimensions
            marginL = 65;   % left margin for y-axis labels
            marginR = 20;
            marginT = 40;   % top margin for title
            marginB = 55;   % bottom for x-axis labels
            barSpacing = 2;
            minBarW = 12;
            maxBarW = 36;
            barW = max(minBarW, min(maxBarW, floor(600 / nBars) - barSpacing));
            chartAreaW = nBars * (barW + barSpacing);
            chartH = 180;
            minSvgW = 320;  % enough width for the title text
            naturalW = marginL + chartAreaW + marginR;
            svgW = max(minSvgW, naturalW);
            % Center chart area when SVG is wider than needed
            if svgW > naturalW
                marginL = marginL + floor((svgW - naturalW) / 2);
            end
            svgH = marginT + chartH + marginB;

            parts = {};
            parts{end+1} = sprintf('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', ...
                svgW, svgH, svgW, svgH);
            parts{end+1} = '<style>text{font-family:"Segoe UI",Arial,sans-serif;}</style>';
            parts{end+1} = sprintf('<rect width="%d" height="%d" rx="8" fill="%s"/>', svgW, svgH, bgColor);

            % Title
            titleStr = 'Measurement Probability Distribution';
            if isFiltered
                titleStr = sprintf('Measurement Probability Distribution (top %d of %d states)', maxBars, N);
            end
            parts{end+1} = sprintf('<text x="%.0f" y="%d" font-size="13" font-weight="600" fill="%s" text-anchor="middle">%s</text>', ...
                svgW/2, 22, titleColor, titleStr);

            % Y-axis gridlines and labels
            nYTicks = 5;
            for k = 0:nYTicks
                yVal = yMax * k / nYTicks;
                yPos = marginT + chartH - (chartH * k / nYTicks);
                % Grid line
                parts{end+1} = sprintf('<line x1="%d" y1="%.0f" x2="%.0f" y2="%.0f" stroke="%s" stroke-width="0.5"/>', ...
                    marginL, yPos, marginL + chartAreaW, yPos, gridColor);
                % Label
                parts{end+1} = sprintf('<text x="%d" y="%.0f" font-size="10" fill="%s" text-anchor="end" dominant-baseline="middle">%.0f%%</text>', ...
                    marginL - 8, yPos, textColor, yVal);
            end

            % Y-axis title (rotated)
            parts{end+1} = sprintf('<text x="14" y="%.0f" font-size="10" fill="%s" text-anchor="middle" transform="rotate(-90, 14, %.0f)">Probability (%%)</text>', ...
                marginT + chartH/2, textColor, marginT + chartH/2);

            % X-axis line
            parts{end+1} = sprintf('<line x1="%d" y1="%.0f" x2="%.0f" y2="%.0f" stroke="%s" stroke-width="1"/>', ...
                marginL, marginT + chartH, marginL + chartAreaW, marginT + chartH, axisColor);

            % Bars and x-axis labels
            for k = 1:nBars
                bx = marginL + (k-1) * (barW + barSpacing);
                pct = showProbs(k) * 100;
                bh = max(round(chartH * pct / yMax), 0);
                by = marginT + chartH - bh;

                if bh > 0
                    parts{end+1} = sprintf('<rect x="%.0f" y="%.0f" width="%d" height="%d" rx="2" fill="%s"><title>%s: %.2f%%</title></rect>', ...
                        bx, by, barW, bh, barFill, showLabels{k}, pct);
                end

                % Value label above bar (only if significant)
                if pct >= 1
                    parts{end+1} = sprintf('<text x="%.0f" y="%.0f" font-size="8" fill="%s" text-anchor="middle">%.1f</text>', ...
                        bx + barW/2, by - 4, labelColor, pct);
                end

                % X-axis label (basis state)
                lx = bx + barW/2;
                ly = marginT + chartH + 10;
                labelStr = showLabels{k};
                fs = 9;
                if nQubits > 4; fs = 7; end
                if nBars > 20
                    % Rotate labels for many bars
                    parts{end+1} = sprintf('<text x="%.0f" y="%.0f" font-size="%d" fill="%s" text-anchor="end" transform="rotate(-45, %.0f, %.0f)">%s</text>', ...
                        lx, ly, fs, textColor, lx, ly, labelStr);
                else
                    parts{end+1} = sprintf('<text x="%.0f" y="%.0f" font-size="%d" fill="%s" text-anchor="middle">%s</text>', ...
                        lx, ly + 2, fs, textColor, labelStr);
                end
            end

            % X-axis title
            parts{end+1} = sprintf('<text x="%.0f" y="%d" font-size="10" fill="%s" text-anchor="middle">Computational basis states</text>', ...
                marginL + chartAreaW/2, svgH - 6, textColor);

            parts{end+1} = '</svg>';
            svg = strjoin(parts, newline);
        end

        function lbl = basisLabel(idx, nQubits)
            % Format a basis state label: |001&#x27E9; for index in SVG text.
            bits = dec2bin(idx, nQubits);
            lbl = ['|' bits '&#x27E9;'];
        end

    end
end
