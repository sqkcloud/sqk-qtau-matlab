classdef CircuitService < handle
    % CircuitService  Domain service for quantum circuit operations.
    %
    %   Wraps all /api/circuits/* endpoints and transforms raw JSON responses
    %   into MATLAB-friendly structs.  No UI logic lives here.

    properties (Access = private)
        Client FastAPIClient
    end

    methods
        function obj = CircuitService(client)
            obj.Client = client;
            Logger.info('CircuitService', 'Initialized');
        end

        % Upload a circuit file.  Returns the created circuit record struct.
        function data = uploadCircuit(obj, filePath, name, format, category, token)
            Logger.info('CircuitService', 'uploadCircuit → POST /api/circuits/upload');
            Logger.info('CircuitService', '  file: %s  name: %s  format: %s  category: %s', ...
                filePath, char(name), char(format), char(category));
            fields = struct( ...
                'circuit_name', char(name), ...
                'format',       char(format), ...
                'category',     char(category));
            try
                data = obj.Client.uploadFileAuth('/api/circuits/upload', filePath, fields, token);
                Logger.info('CircuitService', 'uploadCircuit → upload complete');
            catch ME
                Logger.error('CircuitService', 'uploadCircuit FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % List circuits accessible to the current user.
        function data = listCircuits(obj, token)
            Logger.info('CircuitService', 'listCircuits → GET /api/circuits');
            try
                data = obj.Client.getAuth('/api/circuits', token);
                Logger.info('CircuitService', 'listCircuits → response received');
            catch ME
                Logger.error('CircuitService', 'listCircuits FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Fetch a single circuit by ID.
        function data = getCircuit(obj, circuitId, token)
            ep = sprintf('/api/circuits/%s', char(circuitId));
            Logger.info('CircuitService', 'getCircuit → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('CircuitService', 'getCircuit → response received for circuit: %s', char(circuitId));
            catch ME
                Logger.error('CircuitService', 'getCircuit FAILED (circuit: %s): %s', char(circuitId), ME.message);
                rethrow(ME);
            end
        end

        % Trigger feature extraction on a previously uploaded circuit.
        function data = analyzeCircuit(obj, circuitId, token)
            ep = sprintf('/api/circuits/%s/analyze', char(circuitId));
            Logger.info('CircuitService', 'analyzeCircuit → POST %s', ep);
            try
                data = obj.Client.postAuthJson(ep, struct(), token);
                Logger.info('CircuitService', 'analyzeCircuit → analysis complete for circuit: %s', char(circuitId));
            catch ME
                Logger.error('CircuitService', 'analyzeCircuit FAILED (circuit: %s): %s', char(circuitId), ME.message);
                rethrow(ME);
            end
        end

        % Retrieve the stored analysis for a circuit (no re-computation).
        function data = getAnalysis(obj, circuitId, token)
            ep = sprintf('/api/circuits/%s/analysis', char(circuitId));
            Logger.info('CircuitService', 'getAnalysis → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('CircuitService', 'getAnalysis → response received for circuit: %s', char(circuitId));
            catch ME
                Logger.error('CircuitService', 'getAnalysis FAILED (circuit: %s): %s', char(circuitId), ME.message);
                rethrow(ME);
            end
        end

        % Run QASMBench similarity matching for a circuit.
        function data = matchBenchmarks(obj, circuitId, token)
            ep = sprintf('/api/circuits/%s/match-benchmarks', char(circuitId));
            Logger.info('CircuitService', 'matchBenchmarks → POST %s', ep);
            try
                data = obj.Client.postAuthJson(ep, struct(), token);
                Logger.info('CircuitService', 'matchBenchmarks → matching complete for circuit: %s', char(circuitId));
            catch ME
                Logger.error('CircuitService', 'matchBenchmarks FAILED (circuit: %s): %s', char(circuitId), ME.message);
                rethrow(ME);
            end
        end

        % Get a preview diagram of the circuit (returns image URL or base64).
        function data = previewCircuit(obj, circuitId, token)
            ep = sprintf('/api/circuits/%s/preview', char(circuitId));
            Logger.info('CircuitService', 'previewCircuit → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('CircuitService', 'previewCircuit → preview received for circuit: %s', char(circuitId));
            catch ME
                Logger.error('CircuitService', 'previewCircuit FAILED (circuit: %s): %s', char(circuitId), ME.message);
                rethrow(ME);
            end
        end

        % Permanently delete a circuit.
        function data = deleteCircuit(obj, circuitId, token)
            ep = sprintf('/api/circuits/%s', char(circuitId));
            Logger.info('CircuitService', 'deleteCircuit → DELETE %s', ep);
            try
                data = obj.Client.deleteAuth(ep, token);
                Logger.info('CircuitService', 'deleteCircuit → circuit deleted: %s', char(circuitId));
            catch ME
                Logger.error('CircuitService', 'deleteCircuit FAILED (circuit: %s): %s', char(circuitId), ME.message);
                rethrow(ME);
            end
        end
    end
end
