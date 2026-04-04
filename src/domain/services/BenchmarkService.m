classdef BenchmarkService
    % BenchmarkService  Domain service for quantum benchmarking features.
    %
    %   Wraps the /api/benchmark/* endpoints exposed by the FastAPI backend.
    %   Provides volumetric fidelity data, system metrics, backend scorecards,
    %   benchmark regression tracking, circuit classification, and prediction
    %   calibration analysis.
    %
    %   All methods delegate HTTP work to FastAPIClient and return raw structs
    %   (decoded JSON) so the presentation layer can pick the fields it needs.

    properties
        Client  % FastAPIClient instance
    end

    methods
        function obj = BenchmarkService(client)
            % BenchmarkService  Construct with a configured FastAPIClient.
            obj.Client = client;
        end

        % ── Volumetric Fidelity Map ──────────────────────────────────────────
        function result = getVolumetricData(obj, projectId, token)
            % GET /api/benchmark/volumetric?project_id={projectId}
            %   Returns a grid of (width, depth) -> fidelity values for
            %   building the QED-C-style volumetric heatmap.
            endpoint = sprintf('/api/benchmark/volumetric?project_id=%s', ...
                char(projectId));
            result = obj.Client.getAuth(endpoint, token);
        end

        % ── System Benchmark Metrics ─────────────────────────────────────────
        function result = getSystemMetrics(obj, backendName, token)
            % GET /api/benchmark/system-metrics/{backendName}
            %   Returns Quantum Volume, CLOPS, Layer Fidelity, EPLG and
            %   other standard system-level benchmarks.
            endpoint = sprintf('/api/benchmark/system-metrics/%s', ...
                char(backendName));
            result = obj.Client.getAuth(endpoint, token);
        end

        % ── Backend Scorecard (QPack-inspired) ───────────────────────────────
        function result = getBackendScorecard(obj, projectId, backendName, token)
            % GET /api/benchmark/scorecard?project_id=...&backend_name=...
            %   Returns multi-dimensional scoring: capacity, scalability,
            %   accuracy, runtime sub-scores and overall score.
            endpoint = sprintf( ...
                '/api/benchmark/scorecard?project_id=%s&backend_name=%s', ...
                char(projectId), char(backendName));
            result = obj.Client.getAuth(endpoint, token);
        end

        % ── Benchmark Regression Tracking ────────────────────────────────────
        function result = getBenchmarkRegression(obj, projectId, backendName, token)
            % GET /api/benchmark/regression?project_id=...&backend_name=...
            %   Returns time-series fidelity data for standard benchmark
            %   circuits, enabling calibration drift detection.
            endpoint = sprintf( ...
                '/api/benchmark/regression?project_id=%s&backend_name=%s', ...
                char(projectId), char(backendName));
            result = obj.Client.getAuth(endpoint, token);
        end

        % ── Circuit Classification ───────────────────────────────────────────
        function result = getCircuitClassification(obj, circuitId, projectId, token)
            % GET /api/benchmark/classify/{circuitId}?project_id={projectId}
            %   Classifies the circuit into QV depth class (QV-1 .. QV-5),
            %   algorithm domain, and complexity tier.
            endpoint = sprintf( ...
                '/api/benchmark/classify/%s?project_id=%s', ...
                char(circuitId), char(projectId));
            result = obj.Client.getAuth(endpoint, token);
        end

        % ── Prediction Calibration ───────────────────────────────────────────
        function result = getPredictionCalibration(obj, projectId, token)
            % GET /api/benchmark/prediction-calibration?project_id={projectId}
            %   Compares predicted vs actual fidelity for completed jobs,
            %   returning scatter data and accuracy metrics (MAE, correlation).
            endpoint = sprintf( ...
                '/api/benchmark/prediction-calibration?project_id=%s', ...
                char(projectId));
            result = obj.Client.getAuth(endpoint, token);
        end
    end
end
