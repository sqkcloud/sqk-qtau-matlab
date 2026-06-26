classdef MatlabQuantumBridge
    % MatlabQuantumBridge  Interop between the app's CircuitModel and the
    %   MATLAB Support Package for Quantum Computing (`quantumCircuit`).
    %   The ONLY module that references Support-Package API — every other
    %   feature degrades gracefully when the add-on is absent.
    %
    %   Index convention: internal CircuitModel qubits are 0-indexed
    %   (QASM style); quantumCircuit qubits are 1-indexed. The ±1 shift is
    %   applied in fromQuantumCircuit / kindToGate only.

    methods (Static)
        function tf = isAvailable()
            tf = exist('quantumCircuit', 'class') == 8;
        end

        function names = listWorkspaceCircuits()
            names = string.empty(1, 0);
            try
                vars = evalin('base', 'whos');
            catch
                return;
            end
            if isempty(vars); return; end
            isQc = strcmp({vars.class}, 'quantumCircuit');
            if any(isQc)
                names = string({vars(isQc).name});
            end
        end

        function model = importByName(name)
            name = char(name);
            if ~isvarname(name)
                error('MatlabQuantumBridge:BadName', ...
                    'Not a valid variable name: %s', name);
            end
            if ~evalin('base', sprintf('exist(''%s'', ''var'')', name))
                error('MatlabQuantumBridge:NotFound', ...
                    'No workspace variable named %s', name);
            end
            qc = evalin('base', name);
            model = MatlabQuantumBridge.fromQuantumCircuit(qc);
        end

        function pushToWorkspace(name, value)
            name = char(name);
            if ~isvarname(name)
                error('MatlabQuantumBridge:BadName', ...
                    'Not a valid variable name: %s', name);
            end
            assignin('base', name, value);
        end

        % ── MATLAB data import (numeric / table → parametric circuit) ─────
        %   The pathway for bringing MATLAB *data* into the app: a numeric
        %   vector (or a table's numeric columns) becomes the rotation
        %   angles of a parametric circuit. Pure workspace I/O + CircuitModel
        %   construction — no Support Package required.

        function names = listWorkspaceData()
            % Base-workspace numeric arrays and tables — candidate
            % parametric inputs (e.g. a rotation-angle set or a returns
            % series).
            names = string.empty(1, 0);
            try
                vars = evalin('base', 'whos');
            catch
                return;
            end
            if isempty(vars); return; end
            keep = false(1, numel(vars));
            for i = 1:numel(vars)
                cls = vars(i).class;
                isNum = any(strcmp(cls, {'double', 'single'})) && prod(vars(i).size) >= 1;
                keep(i) = isNum || strcmp(cls, 'table');
            end
            if any(keep)
                names = string({vars(keep).name});
            end
        end

        function angles = importAnglesByName(name)
            % Reads a numeric workspace variable (vector/matrix) or the
            % numeric content of a table and returns a finite, real double
            % ROW vector to use as circuit rotation angles. Validates
            % aggressively so the Composer can surface a clear error.
            name = char(name);
            if ~isvarname(name)
                error('MatlabQuantumBridge:BadName', ...
                    'Not a valid variable name: %s', name);
            end
            if ~evalin('base', sprintf('exist(''%s'', ''var'')', name))
                error('MatlabQuantumBridge:NotFound', ...
                    'No workspace variable named %s', name);
            end
            val = evalin('base', name);
            if istable(val)
                try
                    val = table2array(val);
                catch
                    error('MatlabQuantumBridge:NotNumeric', ...
                        ['Table "%s" has mixed or non-numeric columns; only ' ...
                         'all-numeric tables are supported'], name);
                end
            end
            if ~isnumeric(val) || isempty(val)
                error('MatlabQuantumBridge:NotNumeric', ...
                    'Variable "%s" is not a non-empty numeric array', name);
            end
            angles = double(val(:)');   % column-major flatten to a row
            if ~isreal(angles) || ~all(isfinite(angles))
                error('MatlabQuantumBridge:NotFiniteReal', ...
                    'Variable "%s" must contain only finite real values', name);
            end
        end

        function model = circuitFromAngles(angles)
            % Builds a hardware-efficient parametric circuit from imported
            % MATLAB data: one qubit per angle (capped at
            % CircuitModel.MAX_QUBITS), an Ry(angle) on each, then a linear
            % CX entangling chain. Pure CircuitModel construction.
            angles = double(angles(:)');
            if isempty(angles) || ~isreal(angles) || ~all(isfinite(angles))
                error('MatlabQuantumBridge:NotFiniteReal', ...
                    'angles must be a non-empty finite real vector');
            end
            nq = min(numel(angles), CircuitModel.MAX_QUBITS);
            model = CircuitModel(nq);
            for q = 0:nq-1
                model.addGate('ry', q, angles(q+1));
            end
            for q = 0:nq-2
                model.addGate('cx', [q q+1]);
            end
        end

        function model = fromQuantumCircuit(qc)
            if ~(isscalar(qc) && isa(qc, 'quantumCircuit'))
                error('MatlabQuantumBridge:NotAQuantumCircuit', ...
                    'Expected a scalar quantumCircuit, got %s', class(qc));
            end
            model = CircuitModel(qc.NumQubits);
            gates = qc.Gates;
            for i = 1:numel(gates)
                g = gates(i);
                kind = MatlabQuantumBridge.typeToKind(g.Type);
                % MATLAB order is [control(s) target(s)]; the internal
                % model uses the same order. Shift 1-indexed -> 0-indexed.
                qubits = [double(g.ControlQubits(:)'), double(g.TargetQubits(:)')] - 1;
                if any(strcmp(kind, {'rx', 'ry', 'rz'}))
                    model.addGate(kind, qubits, double(g.Angles(1)));
                else
                    model.addGate(kind, qubits);
                end
            end
        end

        function out = simulateNative(model)
            % Runs MATLAB's native simulate() on the circuit. Returns the
            % final-state amplitudes plus per-qubit P(|0>) marginals
            % (endianness- and global-phase-independent — used for the
            % parity check against the local hand-rolled simulator).
            qc = MatlabQuantumBridge.toQuantumCircuit(model);  % errors on reset / no add-on
            s = simulate(qc);
            n = model.NumQubits;
            zeroProbs = zeros(1, n);
            for q = 1:n
                zeroProbs(q) = probability(s, q, "0");
            end
            out = struct('amplitudes', s.Amplitudes, ...
                         'zeroProbs',  zeroProbs, ...
                         'numQubits',  n);
        end

        function qc = toQuantumCircuit(model)
            if ~MatlabQuantumBridge.isAvailable()
                error('MatlabQuantumBridge:NotAvailable', ...
                    'MATLAB Support Package for Quantum Computing is not installed.');
            end
            gateList = {};
            for i = 1:numel(model.Gates)
                g = model.Gates(i);
                switch g.kind
                    case {'measure', 'barrier'}
                        continue;  % no quantumCircuit equivalent
                    case 'reset'
                        error('MatlabQuantumBridge:UnsupportedNativeOp', ...
                            ['Circuits with reset cannot be converted to a ' ...
                             'quantumCircuit; use the local simulator.']);
                end
                gateList{end+1} = MatlabQuantumBridge.kindToGate(g); %#ok<AGROW>
            end
            if isempty(gateList)
                qc = quantumCircuit(model.NumQubits);
            else
                qc = quantumCircuit(vertcat(gateList{:}), model.NumQubits);
            end
        end
    end

    methods (Static, Access = private)
        function kind = typeToKind(t)
            t = char(t);
            map = { ...
                'h','h'; 'x','x'; 'y','y'; 'z','z'; ...
                's','s'; 'si','sdg'; 't','t'; 'ti','tdg'; ...
                'rx','rx'; 'ry','ry'; 'rz','rz'; ...
                'cx','cx'; 'cz','cz'; 'swap','swap'; 'ccx','ccx'};
            % .Type matched case-insensitively; output is always the lowercase internal kind.
            idx = find(strcmpi(map(:, 1), t), 1);
            if isempty(idx)
                error('MatlabQuantumBridge:UnsupportedGate', ...
                    ['quantumCircuit gate "%s" is not supported by the Composer. ' ...
                     'Supported: h x y z s t (and inverses si/ti) rx ry rz ' ...
                     'cx cz swap ccx.'], t);
            end
            kind = map{idx, 2};
        end

        function gate = kindToGate(g)
            q = g.qubits + 1;  % 0-indexed internal -> 1-indexed MATLAB
            switch g.kind
                case 'h';    gate = hGate(q(1));
                case 'x';    gate = xGate(q(1));
                case 'y';    gate = yGate(q(1));
                case 'z';    gate = zGate(q(1));
                case 's';    gate = sGate(q(1));
                case 't';    gate = tGate(q(1));
                case 'sdg';  gate = siGate(q(1));
                case 'tdg';  gate = tiGate(q(1));
                case 'rx';   gate = rxGate(q(1), g.params(1));
                case 'ry';   gate = ryGate(q(1), g.params(1));
                case 'rz';   gate = rzGate(q(1), g.params(1));
                case 'cx';   gate = cxGate(q(1), q(2));
                case 'cz';   gate = czGate(q(1), q(2));
                case 'swap'; gate = swapGate(q(1), q(2));
                case 'ccx';  gate = ccxGate(q(1), q(2), q(3));
                otherwise
                    error('MatlabQuantumBridge:UnsupportedGate', ...
                        'Gate kind "%s" has no quantumCircuit mapping', g.kind);
            end
        end
    end
end
