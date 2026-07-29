classdef SimulationService < handle
    % SimulationService  Provider router for MATLAB-native and QTAU local simulation.
    %
    % The MATLAB execution path deliberately does not require the optional
    % MatlabCircuitAdapter class to be resolved at runtime.  This prevents
    % stale MATLAB Project paths/class caches from blocking offline
    % simulation.  Adapter-based import/export remains available elsewhere.
    properties
        MatlabQuantum
    end

    methods
        function obj = SimulationService(matlabQuantum)
            if nargin < 1 || isempty(matlabQuantum)
                matlabQuantum = MatlabQuantumService();
            end
            obj.MatlabQuantum = matlabQuantum;
        end

        function result = simulate(obj, circuit, engine, shots)
            if nargin < 3 || isempty(engine); engine = 'auto'; end
            if nargin < 4 || isempty(shots); shots = 0; end

            engine = lower(strtrim(char(engine)));
            valid = {'auto','matlab','qtau'};
            if ~ismember(engine, valid)
                error('SimulationService:UnknownEngine', ...
                    'Engine must be auto, matlab, or qtau.');
            end

            matlabAvailable = MatlabQuantumService.isAvailable();
            if strcmp(engine, 'matlab') && ~matlabAvailable
                cap = obj.MatlabQuantum.capability();
                error('SimulationService:MatlabUnavailable', '%s', cap.message);
            end

            if strcmp(engine, 'matlab') || ...
                    (strcmp(engine, 'auto') && matlabAvailable)
                quantumCircuitValue = obj.ensureQuantumCircuit(circuit);
                result = obj.MatlabQuantum.simulateCircuit(quantumCircuitValue, shots);
                result.requestedEngine = engine;
                return;
            end

            circuitModel = obj.ensureCircuitModel(circuit);
            steps = StatevectorSimulator.simulate(circuitModel);

            % Normalize the QTAU local result to the same public result
            % contract used by MATLAB Quantum Computing simulation.  UI,
            % Workspace export and customer-demo code can therefore consume
            % result.states/result.probabilities without provider-specific
            % branching.
            finalPsi = steps(end).psi;
            probabilities = abs(finalPsi(:)).^2;
            keep = probabilities > 1e-12;
            basis = find(keep) - 1;
            nQubits = circuitModel.NumQubits;
            states = strings(numel(basis),1);
            for stateIdx = 1:numel(basis)
                states(stateIdx) = string(dec2bin(basis(stateIdx), nQubits));
            end
            probabilities = probabilities(keep);
            [probabilities, order] = sort(probabilities, 'descend');
            states = states(order);

            result = struct( ...
                'engine', 'QTAU Lightweight Local', ...
                'provider', 'qtau-matlab-statevector', ...
                'steps', steps, ...
                'states', states, ...
                'probabilities', probabilities, ...
                'shots', shots, ...
                'requestedEngine', engine, ...
                'warnings', strings(0,1));
        end

        function providers = providers(obj)
            cap = obj.MatlabQuantum.capability();
            providers = table(["matlab";"qtau"], ...
                [cap.available;true], ...
                ["MATLAB Support Package local simulator"; ...
                 "QTAU lightweight statevector"], ...
                'VariableNames', {'Provider','Available','Description'});
        end
    end

    methods (Access = private)
        function qc = ensureQuantumCircuit(~, circuit)
            if MatlabQuantumService.isQuantumCircuit(circuit)
                qc = circuit;
                return;
            end
            if ~isa(circuit, 'CircuitModel')
                error('SimulationService:UnsupportedCircuit', ...
                    'Expected CircuitModel or MATLAB quantumCircuit, got %s.', ...
                    class(circuit));
            end

            % MATLAB quantumCircuit does not import QASM through its
            % constructor. Convert Composer gates directly to MATLAB gate
            % objects, using MATLAB's one-based qubit numbering.
            gates = [];
            for i = 1:numel(circuit.Gates)
                g = circuit.Gates(i);
                kind = lower(char(g.kind));
                q = double(g.qubits) + 1;
                params = double(g.params);

                switch kind
                    case 'h'
                        mg = hGate(q(1));
                    case 'x'
                        mg = xGate(q(1));
                    case 'y'
                        mg = yGate(q(1));
                    case 'z'
                        mg = zGate(q(1));
                    case 's'
                        mg = sGate(q(1));
                    case 't'
                        mg = tGate(q(1));
                    case 'sdg'
                        mg = inv(sGate(q(1)));
                    case 'tdg'
                        mg = inv(tGate(q(1)));
                    case 'rx'
                        SimulationService.requireParameter(kind, params);
                        mg = rxGate(q(1), params(1));
                    case 'ry'
                        SimulationService.requireParameter(kind, params);
                        mg = ryGate(q(1), params(1));
                    case 'rz'
                        SimulationService.requireParameter(kind, params);
                        mg = rzGate(q(1), params(1));
                    case 'cx'
                        mg = cxGate(q(1), q(2));
                    case 'cz'
                        mg = czGate(q(1), q(2));
                    case 'swap'
                        mg = swapGate(q(1), q(2));
                    case 'ccx'
                        mg = ccxGate(q(1), q(2), q(3));
                    case 'barrier'
                        % Barrier has no effect on local state simulation.
                        continue;
                    case 'measure'
                        % simulate() returns a QuantumState. Sampling is
                        % performed afterwards by MatlabQuantumService.
                        continue;
                    case 'reset'
                        error('SimulationService:UnsupportedMatlabGate', ...
                            ['Composer reset operations cannot be converted ' ...
                             'to a unitary MATLAB quantumCircuit. Remove the ' ...
                             'reset gate before local state simulation.']);
                    otherwise
                        error('SimulationService:UnsupportedMatlabGate', ...
                            'MATLAB local simulation does not support Composer gate: %s', kind);
                end

                if isempty(gates)
                    gates = mg;
                else
                    gates(end+1,1) = mg; %#ok<AGROW>
                end
            end

            if isempty(gates)
                qc = quantumCircuit(circuit.NumQubits);
            else
                qc = quantumCircuit(gates, circuit.NumQubits);
            end
        end

        function model = ensureCircuitModel(~, circuit)
            if isa(circuit, 'CircuitModel')
                model = circuit;
                return;
            end
            if ~MatlabQuantumService.isQuantumCircuit(circuit)
                error('SimulationService:UnsupportedCircuit', ...
                    'Expected CircuitModel or MATLAB quantumCircuit, got %s.', ...
                    class(circuit));
            end

            qasm = char(generateQASM(circuit));
            qasm = SimulationService.normalizeQasm3ForModel(qasm);
            model = CircuitModel.fromQasm(qasm);
        end
    end

    methods (Static, Access = private)
        function qasm = normalizeQasm3ForModel(qasm)
            qasm = regexprep(qasm, 'OPENQASM\s+3(?:\.0)?', ...
                'OPENQASM 2.0', 'ignorecase');
            qasm = regexprep(qasm, ...
                'qubit\s*\[\s*(\d+)\s*\]\s+(\w+)\s*;', ...
                'qreg $2[$1];', 'ignorecase');
            qasm = regexprep(qasm, ...
                'bit\s*\[\s*(\d+)\s*\]\s+(\w+)\s*;', ...
                'creg $2[$1];', 'ignorecase');
            qasm = regexprep(qasm, ...
                'include\s+"stdgates.inc"\s*;', ...
                'include "qelib1.inc";', 'ignorecase');
            qasm = regexprep(qasm, ...
                '(?m)^\s*barrier\b[^;]*;\s*$', '', 'ignorecase');
        end

        function requireParameter(kind, params)
            if isempty(params) || ~isfinite(params(1))
                error('SimulationService:MissingGateParameter', ...
                    'Gate %s requires a finite rotation angle.', kind);
            end
        end

        function deleteIfExists(pathValue)
            if exist(pathValue, 'file')
                delete(pathValue);
            end
        end
    end
end
