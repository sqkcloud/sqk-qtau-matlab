classdef BackendService < handle
    % BackendService  Domain service for IBM Quantum backend operations.
    %
    %   Wraps /api/backends/* endpoints.  All methods return raw decoded
    %   structs; DTO transformation is handled by JsonHelper or the caller.

    properties (Access = private)
        Client  % FastAPIClient instance (relaxed from typed property so tests can inject a StubFastAPIClient)
    end

    methods
        function obj = BackendService(client)
            obj.Client = client;
            Logger.info('BackendService', 'Initialized');
        end

        % List available backends.  When circuitId is given, the API returns
        % an enriched list with predicted fidelity, queue status, etc.
        % Without circuitId, returns only backends stored in the project DB.
        function data = listBackends(obj, token, circuitId)
            if nargin >= 3 && strlength(string(circuitId)) > 0
                ep = sprintf('/api/backends?circuit_id=%s', char(circuitId));
            else
                ep = '/api/backends';
            end
            Logger.info('BackendService', 'listBackends → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('BackendService', 'listBackends → response received');
            catch ME
                Logger.error('BackendService', 'listBackends FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Fetch detailed information for one backend by name.
        function data = getBackend(obj, backendName, token)
            ep = sprintf('/api/backends/%s', FastAPIClient.encodePathSegment(backendName));
            Logger.info('BackendService', 'getBackend → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('BackendService', 'getBackend → response received for: %s', char(backendName));
            catch ME
                Logger.error('BackendService', 'getBackend FAILED (backend: %s): %s', char(backendName), ME.message);
                rethrow(ME);
            end
        end

        % Retrieve the latest calibration data (gate errors, T1/T2, etc.).
        function data = getCalibration(obj, backendName, token)
            ep = sprintf('/api/backends/%s/calibration', FastAPIClient.encodePathSegment(backendName));
            Logger.info('BackendService', 'getCalibration → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('BackendService', 'getCalibration → response received for: %s', char(backendName));
            catch ME
                Logger.error('BackendService', 'getCalibration FAILED (backend: %s): %s', char(backendName), ME.message);
                rethrow(ME);
            end
        end

        % Time-sorted (newest first) per-qubit calibration samples within
        % the last `days` (1..30, default 7) for the named backend. Each
        % record is written through by a successful getCalibration call
        % on the server side and evicted by a 7-day Mongo TTL. Pass
        % `qubitIndex=[]` for all qubits, or a 0-based int to filter.
        function data = getCalibrationHistory(obj, backendName, days, token, qubitIndex)
            if nargin < 3 || isempty(days); days = 7; end
            if nargin < 5; qubitIndex = []; end
            qs = sprintf('?days=%d', round(double(days)));
            if ~isempty(qubitIndex)
                qs = sprintf('%s&qubit_index=%d', qs, round(double(qubitIndex)));
            end
            ep = sprintf('/api/backends/%s/calibration_history%s', ...
                FastAPIClient.encodePathSegment(backendName), qs);
            Logger.info('BackendService', 'getCalibrationHistory → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
            catch ME
                Logger.error('BackendService', ...
                    'getCalibrationHistory FAILED (backend: %s): %s', ...
                    char(backendName), ME.message);
                rethrow(ME);
            end
        end

        % Fetch the hardware connectivity topology.
        function data = getTopology(obj, backendName, token)
            ep = sprintf('/api/backends/%s/topology', FastAPIClient.encodePathSegment(backendName));
            Logger.info('BackendService', 'getTopology → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('BackendService', 'getTopology → response received for: %s', char(backendName));
            catch ME
                Logger.error('BackendService', 'getTopology FAILED (backend: %s): %s', char(backendName), ME.message);
                rethrow(ME);
            end
        end

        % Compare a set of backends.  backendNames is a cell array of strings.
        function data = compareBackends(obj, backendNames, circuitId, token)
            Logger.info('BackendService', 'compareBackends → POST /api/backends/compare (circuit: %s, count: %d)', ...
                char(circuitId), numel(backendNames));
            payload = struct( ...
                'backend_names', {backendNames}, ...
                'circuit_id',    char(circuitId));
            try
                data = obj.Client.postAuthJson('/api/backends/compare', payload, token);
                Logger.info('BackendService', 'compareBackends → comparison complete');
            catch ME
                Logger.error('BackendService', 'compareBackends FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Persist the primary / backup backend selection for a project.
        function data = saveSelection(obj, projectId, primaryName, backupName, token)
            ep = sprintf('/api/projects/%s/backend-selection', FastAPIClient.encodePathSegment(projectId));
            Logger.info('BackendService', 'saveSelection → POST %s (primary: %s, backup: %s)', ...
                ep, char(primaryName), char(backupName));
            payload = struct( ...
                'primary_backend', char(primaryName), ...
                'backup_backend',  char(backupName));
            try
                data = obj.Client.postAuthJson(ep, payload, token);
                Logger.info('BackendService', 'saveSelection → saved for project: %s', char(projectId));
            catch ME
                Logger.error('BackendService', 'saveSelection FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Retrieve the previously saved backend selection for a project.
        function data = getSelection(obj, projectId, token)
            ep = sprintf('/api/projects/%s/backend-selection', FastAPIClient.encodePathSegment(projectId));
            Logger.info('BackendService', 'getSelection → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('BackendService', 'getSelection → response received for project: %s', char(projectId));
            catch ME
                Logger.error('BackendService', 'getSelection FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end
    end
end
