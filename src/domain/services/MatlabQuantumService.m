classdef MatlabQuantumService < handle
    % MatlabQuantumService  Runtime-safe integration with MATLAB Support
    % Package for Quantum Computing. Capability detection probes class and
    % method dispatch instead of relying only on exist(...,'file').
    methods
        function info = capability(~)
            info = MatlabQuantumService.probeCapability();
        end

        function qasm = generateQasm(~, circuit)
            MatlabQuantumService.requireQuantumCircuit(circuit);
            try
                qasm = string(generateQASM(circuit));
            catch ME
                error('MatlabQuantumService:GenerateQASMFailed', ...
                    'MATLAB generateQASM failed: %s', ME.message);
            end
        end

        function result = simulateCircuit(~, circuit, shots)
            if nargin < 3 || isempty(shots); shots = 0; end
            validateattributes(shots, {'numeric'}, {'scalar','integer','nonnegative'});
            MatlabQuantumService.requireQuantumCircuit(circuit);
            try
                state = simulate(circuit);
            catch ME
                error('MatlabQuantumService:SimulationFailed', ...
                    'MATLAB quantum simulation failed: %s', ME.message);
            end
            result = struct('engine','MATLAB Quantum Computing', ...
                'provider','matlab-support-package', 'state',state, ...
                'measurement',[], 'states',strings(0,1), ...
                'probabilities',zeros(0,1), 'shots',shots, ...
                'warnings',strings(0,1));
            try
                [states, probabilities] = querystates(state);
                result.states = string(states(:));
                result.probabilities = double(probabilities(:));
            catch ME
                result.warnings(end+1) = "State probabilities unavailable: " + string(ME.message);
            end
            if shots > 0
                try
                    result.measurement = randsample(state, shots);
                catch ME
                    result.warnings(end+1) = "Sampling unavailable: " + string(ME.message);
                end
            end
        end
    end

    methods (Static)
        function info = probeCapability()
            info = struct('available',false,'quantumCircuitClass',false, ...
                'generateQASM',false,'simulate',false,'querystates',false, ...
                'randsample',false,'message','');
            info.quantumCircuitClass = exist('quantumCircuit','class') == 8 || ...
                exist('quantumCircuit','file') ~= 0;
            info.generateQASM = exist('generateQASM','file') ~= 0 || ...
                exist('generateQASM','builtin') ~= 0;
            info.simulate = exist('simulate','file') ~= 0 || exist('simulate','builtin') ~= 0;
            info.querystates = exist('querystates','file') ~= 0 || exist('querystates','builtin') ~= 0;
            info.randsample = exist('randsample','file') ~= 0 || exist('randsample','builtin') ~= 0;
            if ~info.quantumCircuitClass
                info.message = 'MATLAB Support Package for Quantum Computing was not detected.';
                return;
            end
            % Methods can be package-dispatched and not appear as standalone files.
            try
                mc = meta.class.fromName('quantumCircuit');
                names = string({mc.MethodList.Name});
                info.generateQASM = info.generateQASM || any(strcmpi(names,'generateQASM'));
                info.simulate = info.simulate || any(strcmpi(names,'simulate'));
            catch
            end
            info.available = info.quantumCircuitClass && info.simulate;
            if info.available
                info.message = 'MATLAB quantum circuit and local simulation are available.';
            else
                info.message = 'quantumCircuit exists, but simulate() is unavailable in this MATLAB installation.';
            end
        end

        function tf = isAvailable()
            info = MatlabQuantumService.probeCapability();
            tf = info.available;
        end

        function tf = isQuantumCircuit(value)
            tf = false;
            try
                tf = isa(value,'quantumCircuit') || endsWith(string(class(value)),'.quantumCircuit');
            catch
            end
        end

        function requireQuantumCircuit(value)
            if ~MatlabQuantumService.isQuantumCircuit(value)
                error('MatlabQuantumService:InvalidCircuit', ...
                    'Input must be a MATLAB quantumCircuit; received %s.', class(value));
            end
        end
    end
end
