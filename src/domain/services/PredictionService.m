classdef PredictionService < handle
    % PredictionService  Domain service for circuit performance prediction.
    %
    %   Uses the /api/predict and /api/optimize endpoints to forecast
    %   fidelity, queue times, and distribution outcomes before job submission.

    properties (Access = private)
        Client  % FastAPIClient instance (relaxed from typed property so tests can inject a StubFastAPIClient)
    end

    methods
        function obj = PredictionService(client)
            obj.Client = client;
            Logger.info('PredictionService', 'Initialized');
        end

        % Run a global (non-project-scoped) fidelity prediction.
        %
        %   backendNames  — single backend (char/string) or cell array of
        %                   backends for cross-backend prediction. The API
        %                   requires the plural `backend_names` array form.
        function data = predict(obj, circuitId, backendNames, shots, optLevel, token)
            Logger.info('PredictionService', 'predict → POST /api/predict');
            backends = PredictionService.normalizeBackends(backendNames);
            Logger.info('PredictionService', '  circuit: %s  backends: [%s]  shots: %d  opt: %d', ...
                char(circuitId), strjoin(backends, ', '), round(shots), round(optLevel));
            payload = struct( ...
                'circuit_id',         char(circuitId), ...
                'backend_names',      {backends}, ...
                'shots',              round(shots), ...
                'optimization_level', round(optLevel));
            try
                data = obj.Client.postAuthJson('/api/predict', payload, token);
                Logger.info('PredictionService', 'predict → prediction complete');
            catch ME
                Logger.error('PredictionService', 'predict FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Retrieve a previously generated prediction by ID.
        function data = getPrediction(obj, predictionId, token)
            ep = sprintf('/api/predict/%s', FastAPIClient.encodePathSegment(predictionId));
            Logger.info('PredictionService', 'getPrediction → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('PredictionService', 'getPrediction → response received for id: %s', char(predictionId));
            catch ME
                Logger.error('PredictionService', 'getPrediction FAILED (id: %s): %s', char(predictionId), ME.message);
                rethrow(ME);
            end
        end

        % Optimize circuit transpilation for a specific backend.
        function data = optimizeCircuit(obj, circuitId, backendName, optLevel, strategy, token)
            Logger.info('PredictionService', 'optimizeCircuit → POST /api/optimize');
            Logger.info('PredictionService', '  circuit: %s  backend: %s  opt: %d  strategy: %s', ...
                char(circuitId), char(backendName), round(optLevel), char(strategy));
            payload = struct( ...
                'circuit_id',            char(circuitId), ...
                'backend_name',          char(backendName), ...
                'optimization_level',    round(optLevel), ...
                'transpilation_strategy', char(strategy));
            try
                data = obj.Client.postAuthJson('/api/optimize', payload, token);
                Logger.info('PredictionService', 'optimizeCircuit → optimization complete');
            catch ME
                Logger.error('PredictionService', 'optimizeCircuit FAILED: %s', ME.message);
                rethrow(ME);
            end
        end
    end

    methods (Static, Access = private)
        function backends = normalizeBackends(input)
            % Accept a char/string (single backend) or a cell array of
            % char/string (multi-backend) and return a cell array of char.
            % Empty elements are dropped. Empty input yields {} — the
            % caller / API layer is responsible for validating that.
            if iscell(input)
                backends = cellfun(@(b) char(string(b)), input, 'UniformOutput', false);
            elseif isstring(input) && numel(input) > 1
                backends = arrayfun(@char, input, 'UniformOutput', false);
            else
                backends = {char(string(input))};
            end
            backends = backends(~cellfun(@isempty, backends));
        end
    end
end
