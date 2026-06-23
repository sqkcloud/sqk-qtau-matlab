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
