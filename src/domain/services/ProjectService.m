classdef ProjectService < handle
    % ProjectService  Domain service for project lifecycle and configuration.
    %
    %   Covers project CRUD, notes, dashboard snapshots, benchmark
    %   configuration, and transpilation strategy comparison.

    properties (Access = private)
        Client FastAPIClient
    end

    methods
        function obj = ProjectService(client)
            obj.Client = client;
            Logger.info('ProjectService', 'Initialized');
        end

        % List all projects for the current user.
        function data = listProjects(obj, token)
            Logger.info('ProjectService', 'listProjects → GET /api/projects');
            try
                data = obj.Client.getAuth('/api/projects', token);
                Logger.info('ProjectService', 'listProjects → response received');
            catch ME
                Logger.error('ProjectService', 'listProjects FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Create a new project.
        function data = createProject(obj, name, description, tags, token)
            Logger.info('ProjectService', 'createProject → POST /api/projects (name: %s)', char(name));
            payload = struct('name', char(name), 'description', char(description));
            if ~isempty(tags)
                payload.tags = tags;
            end
            try
                data = obj.Client.postAuthJson('/api/projects', payload, token);
                Logger.info('ProjectService', 'createProject → project created: %s', char(name));
            catch ME
                Logger.error('ProjectService', 'createProject FAILED (name: %s): %s', char(name), ME.message);
                rethrow(ME);
            end
        end

        % Update an existing project (PATCH with all editable fields).
        function data = updateProject(obj, projectId, name, description, tags, token)
            ep = sprintf('/api/projects/%s', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'updateProject → PATCH %s (name: %s)', ep, char(name));
            if nargin < 5; tags = {}; end
            if isempty(tags); tags = {}; end
            % Build JSON manually to guarantee tags serializes as an array.
            % MATLAB jsonencode({'one'}) produces "one" instead of ["one"].
            tagJson = jsonencode(string(tags));
            if ~startsWith(tagJson, '['); tagJson = ['[' tagJson ']']; end
            body = sprintf('{"name":%s,"description":%s,"tags":%s}', ...
                jsonencode(char(name)), jsonencode(char(description)), tagJson);
            try
                data = obj.Client.patchAuthRaw(ep, body, token);
                Logger.info('ProjectService', 'updateProject → project updated: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'updateProject FAILED (id: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Permanently delete a project.
        function data = deleteProject(obj, projectId, token)
            ep = sprintf('/api/projects/%s', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'deleteProject → DELETE %s', ep);
            try
                data = obj.Client.deleteAuth(ep, token);
                Logger.info('ProjectService', 'deleteProject → project deleted: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'deleteProject FAILED (id: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Fetch a single project record.
        function data = getProject(obj, projectId, token)
            ep = sprintf('/api/projects/%s', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'getProject → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ProjectService', 'getProject → response received for: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'getProject FAILED (id: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Retrieve the dashboard snapshot (KPI cards, pipeline status).
        function data = getDashboard(obj, projectId, token)
            ep = sprintf('/api/projects/%s/dashboard', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'getDashboard → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ProjectService', 'getDashboard → dashboard data received for project: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'getDashboard FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Fetch paginated activity log for a project.
        function data = getActivities(obj, projectId, skip, limit, token)
            ep = sprintf('/api/projects/%s/activities?skip=%d&limit=%d', FastAPIClient.encodePathSegment(projectId), skip, limit);
            Logger.info('ProjectService', 'getActivities → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ProjectService', 'getActivities → response received');
            catch ME
                Logger.error('ProjectService', 'getActivities FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Fetch the markdown notes for a project.
        function data = getNotes(obj, projectId, token)
            ep = sprintf('/api/projects/%s/notes', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'getNotes → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ProjectService', 'getNotes → notes received for project: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'getNotes FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Persist updated notes (full replace via PUT).
        function data = saveNotes(obj, projectId, content, token)
            ep = sprintf('/api/projects/%s/notes', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'saveNotes → PUT %s (length: %d chars)', ep, numel(char(content)));
            payload = struct('content', char(content));
            try
                data = obj.Client.putAuthJson(ep, payload, token);
                Logger.info('ProjectService', 'saveNotes → notes saved for project: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'saveNotes FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Save the benchmark configuration (shots, opt level, mitigation, strategy).
        function data = saveBenchmarkConfig(obj, projectId, circuitId, backendName, shots, optLevel, mitigation, strategy, token)
            ep = sprintf('/api/projects/%s/benchmark-config', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'saveBenchmarkConfig → POST %s', ep);
            Logger.info('ProjectService', '  circuit: %s  backend: %s  shots: %d  opt: %d  mitigation: %s  strategy: %s', ...
                char(circuitId), char(backendName), round(shots), round(optLevel), char(mitigation), char(strategy));
            payload = struct( ...
                'circuit_id',             char(circuitId), ...
                'backend_name',           char(backendName), ...
                'shots',                  round(shots), ...
                'optimization_level',     round(optLevel), ...
                'error_mitigation',       char(mitigation), ...
                'transpilation_strategy', char(strategy));
            try
                data = obj.Client.postAuthJson(ep, payload, token);
                Logger.info('ProjectService', 'saveBenchmarkConfig → config saved for project: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'saveBenchmarkConfig FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Retrieve the current benchmark configuration.
        function data = getBenchmarkConfig(obj, projectId, token)
            ep = sprintf('/api/projects/%s/benchmark-config', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'getBenchmarkConfig → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ProjectService', 'getBenchmarkConfig → config received for project: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'getBenchmarkConfig FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Compare transpilation strategies for a project's circuit + backend.
        function data = compareStrategies(obj, projectId, circuitId, backendName, strategies, token)
            ep = sprintf('/api/projects/%s/benchmark-config/compare-strategies', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'compareStrategies → POST %s (circuit: %s  backend: %s)', ...
                ep, char(circuitId), char(backendName));
            payload = struct('circuit_id',   char(circuitId), ...
                             'backend_name', char(backendName));
            if ~isempty(strategies)
                payload.strategies = strategies;
            end
            try
                data = obj.Client.postAuthJson(ep, payload, token);
                Logger.info('ProjectService', 'compareStrategies → strategy comparison complete');
            catch ME
                Logger.error('ProjectService', 'compareStrategies FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Run fidelity prediction (project-scoped).
        function data = predict(obj, projectId, circuitId, backendName, shots, optLevel, token)
            ep = sprintf('/api/projects/%s/predict', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'predict → POST %s', ep);
            Logger.info('ProjectService', '  circuit: %s  backend: %s  shots: %d  opt: %d', ...
                char(circuitId), char(backendName), round(shots), round(optLevel));
            payload = struct( ...
                'circuit_id',         char(circuitId), ...
                'backend_name',       char(backendName), ...
                'shots',              round(shots), ...
                'optimization_level', round(optLevel));
            try
                data = obj.Client.postAuthJson(ep, payload, token);
                Logger.info('ProjectService', 'predict → project prediction complete for: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'predict FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Retrieve the latest prediction result for a project.
        function data = getLatestPrediction(obj, projectId, token)
            ep = sprintf('/api/projects/%s/predict/latest', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'getLatestPrediction → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ProjectService', 'getLatestPrediction → response received for project: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'getLatestPrediction FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % List project-scoped reports.
        function data = listReports(obj, projectId, token)
            ep = sprintf('/api/projects/%s/reports', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'listReports → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ProjectService', 'listReports → response received for project: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'listReports FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Generate a project-scoped report.
        function data = generateReport(obj, projectId, title, format, sections, token)
            ep = sprintf('/api/projects/%s/reports', FastAPIClient.encodePathSegment(projectId));
            Logger.info('ProjectService', 'generateReport → POST %s (format: %s)', ep, char(format));
            % API expects 'sections' as an array of strings, not a plain string.
            secStr = strtrim(char(sections));
            if isempty(secStr) || strcmpi(secStr, 'all')
                secCell = {'circuit_summary','feature_analysis','benchmark_comparison', ...
                           'backend_explorer','prediction','optimization','execution_results', ...
                           'detailed_analysis'};
            else
                secCell = strtrim(strsplit(secStr, ','));
            end
            payload = struct( ...
                'title',    char(title), ...
                'format',   lower(char(format)), ...
                'sections', {secCell});
            try
                data = obj.Client.postAuthJson(ep, payload, token);
                Logger.info('ProjectService', 'generateReport → report generated for project: %s', char(projectId));
            catch ME
                Logger.error('ProjectService', 'generateReport FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end
    end
end
