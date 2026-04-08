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

        function src = wrapHtml(text)
            % wrapHtml  Wrap plain text or HTML body in a styled HTML page
            %           suitable for uihtml.HTMLSource.
            if iscell(text)
                text = strjoin(text, newline);
            end
            src = [ ...
                '<html><head><style>' ...
                'html,body{height:100%;margin:0;padding:0;}' ...
                'body{display:flex;align-items:center;justify-content:center;overflow:auto;}' ...
                'pre{font-family:"Courier New",monospace;font-size:11px;' ...
                'color:#232a36;line-height:1.6;margin:0;}' ...
                '</style></head><body><pre>' ...
                char(text) ...
                '</pre></body></html>'];
        end

        function src = buildStatsHtml(infoLines, diagramHtml)
            % buildStatsHtml  Combine info lines + colored diagram into HTML.
            escaped = cell(size(infoLines));
            for i = 1:numel(infoLines)
                escaped{i} = strrep(strrep(char(infoLines{i}), '&', '&amp;'), '<', '&lt;');
            end
            body = strjoin(escaped, newline);
            if ~isempty(diagramHtml)
                if ~isempty(body)
                    body = [body, newline, newline];
                end
                body = [body, diagramHtml];
            end
            src = CircuitDiagram.wrapHtml(body);
        end

    end

    methods (Static, Access = private)

        function [nQubits, gates] = parseGates(content)
            % Parse qubit declarations and gate operations from QASM text.
            nQubits = 0;
            gates = {};  % each entry: struct with .name, .qubits (0-based indices)
            lines = strsplit(content, newline);
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
                tok1 = regexp(ln, '^\s*(h|x|y|z|s|t|sdg|tdg|rx|ry|rz|u[123]?|id|sx|measure)\s*(?:\([^)]*\))?\s+\w+\[(\d+)\]', 'tokens');
                if ~isempty(tok1)
                    gName = upper(tok1{1}{1});
                    qIdx = str2double(tok1{1}{2});
                    if strcmp(gName, 'MEASURE'); gName = 'M'; end
                    gates{end+1} = struct('name', gName, 'qubits', qIdx); %#ok<AGROW>
                    continue;
                end

                % Bulk measure: c = measure q;
                if ~isempty(regexp(ln, '=\s*measure\s+\w+\s*;', 'once'))
                    for qi = 0:max(nQubits-1, 0)
                        gates{end+1} = struct('name', 'M', 'qubits', qi); %#ok<AGROW>
                    end
                    continue;
                end

                % Three-qubit gates: ccx q[0], q[1], q[2]; (must match before two-qubit)
                tok3 = regexp(ln, '^\s*(ccx|cswap)\s*(?:\([^)]*\))?\s+\w+\[(\d+)\]\s*,\s*\w+\[(\d+)\]\s*,\s*\w+\[(\d+)\]', 'tokens');
                if ~isempty(tok3)
                    gName = upper(tok3{1}{1});
                    q1 = str2double(tok3{1}{2});
                    q2 = str2double(tok3{1}{3});
                    q3 = str2double(tok3{1}{4});
                    gates{end+1} = struct('name', gName, 'qubits', [q1, q2, q3]); %#ok<AGROW>
                    continue;
                end

                % Two-qubit gates: cx q[0], q[1]; cz q[0], q[1]; swap q[0], q[1];
                tok2 = regexp(ln, '^\s*(cx|cz|cy|ch|cu1|cu2|cu3|swap)\s*(?:\([^)]*\))?\s+\w+\[(\d+)\]\s*,\s*\w+\[(\d+)\]', 'tokens');
                if ~isempty(tok2)
                    gName = upper(tok2{1}{1});
                    q1 = str2double(tok2{1}{2});
                    q2 = str2double(tok2{1}{3});
                    gates{end+1} = struct('name', gName, 'qubits', [q1, q2]); %#ok<AGROW>
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

        function [grid, nQubits, displayCols, cellWidth, truncated, nGatesTotal] = buildGrid(nQubits, gates)
            % Shared grid-building logic used by both drawDiagram and drawHtmlDiagram.
            maxCols = 20;
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

    end
end
