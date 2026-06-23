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
            gates = [];
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
                gates = [gates; MatlabQuantumBridge.kindToGate(g)]; %#ok<AGROW>
            end
            if isempty(gates)
                qc = quantumCircuit(model.NumQubits);
            else
                qc = quantumCircuit(gates, model.NumQubits);
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
