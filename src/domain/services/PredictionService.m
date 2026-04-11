classdef PredictionService < handle
    % PredictionService  Domain service for circuit performance prediction.
    %
    %   Uses the /api/predict and /api/optimize endpoints to forecast
    %   fidelity, queue times, and distribution outcomes before job submission.

    properties (Access = private)
        Client FastAPIClient
    end

    methods
        function obj = PredictionService(client)
            obj.Client = client;
            Logger.info('PredictionService', 'Initialized');
        end

        % Run a global (non-project-scoped) fidelity prediction.
        function data = predict(obj, circuitId, backendName, shots, optLevel, token)
            Logger.info('PredictionService', 'predict → POST /api/predict');
            Logger.info('PredictionService', '  circuit: %s  backend: %s  shots: %d  opt: %d', ...
                char(circuitId), char(backendName), round(shots), round(optLevel));
            payload = struct( ...
                'circuit_id',         char(circuitId), ...
                'backend_name',       char(backendName), ...
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
end
