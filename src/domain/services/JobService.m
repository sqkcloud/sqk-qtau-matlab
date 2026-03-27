classdef JobService < handle
    % JobService  Domain service for IBM Quantum job lifecycle management.
    %
    %   Covers submission, monitoring, cancellation, and result retrieval
    %   via the /api/jobs/* endpoints.

    properties (Access = private)
        Client FastAPIClient
    end

    methods
        function obj = JobService(client)
            obj.Client = client;
            Logger.info('JobService', 'Initialized');
        end

        % Submit a new job.  payload should contain circuit_id, backend_name,
        % shots, optimization_level, and error_mitigation fields.
        function data = submitJob(obj, payload, token)
            Logger.info('JobService', 'submitJob → POST /api/jobs/submit');
            try
                data = obj.Client.postAuthJson('/api/jobs/submit', payload, token);
                Logger.info('JobService', 'submitJob → job submitted successfully');
            catch ME
                Logger.error('JobService', 'submitJob FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % List all jobs (global view); supports optional skip/limit query params.
        function data = listJobs(obj, token, skip, limit)
            if nargin < 3; skip  = 0;  end
            if nargin < 4; limit = 50; end
            ep = sprintf('/api/jobs?skip=%d&limit=%d', round(skip), round(limit));
            Logger.info('JobService', 'listJobs → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('JobService', 'listJobs → response received');
            catch ME
                Logger.error('JobService', 'listJobs FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Fetch the full record for one job.
        function data = getJob(obj, jobId, token)
            ep = sprintf('/api/jobs/%s', char(jobId));
            Logger.info('JobService', 'getJob → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('JobService', 'getJob → response received for job: %s', char(jobId));
            catch ME
                Logger.error('JobService', 'getJob FAILED (job: %s): %s', char(jobId), ME.message);
                rethrow(ME);
            end
        end

        % Poll the lightweight status endpoint (faster than getJob).
        function data = getStatus(obj, jobId, token)
            ep = sprintf('/api/jobs/%s/status', char(jobId));
            Logger.debug('JobService', 'getStatus → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.debug('JobService', 'getStatus → response received for job: %s', char(jobId));
            catch ME
                Logger.error('JobService', 'getStatus FAILED (job: %s): %s', char(jobId), ME.message);
                rethrow(ME);
            end
        end

        % Cancel a running or queued job.
        function data = cancelJob(obj, jobId, token)
            ep = sprintf('/api/jobs/%s/cancel', char(jobId));
            Logger.info('JobService', 'cancelJob → POST %s', ep);
            try
                data = obj.Client.postAuthJson(ep, struct(), token);
                Logger.info('JobService', 'cancelJob → cancel request sent for job: %s', char(jobId));
            catch ME
                Logger.error('JobService', 'cancelJob FAILED (job: %s): %s', char(jobId), ME.message);
                rethrow(ME);
            end
        end

        % Pause a running job.
        function data = pauseJob(obj, jobId, token)
            ep = sprintf('/api/jobs/%s/pause', char(jobId));
            Logger.info('JobService', 'pauseJob → POST %s', ep);
            try
                data = obj.Client.postAuthJson(ep, struct(), token);
                Logger.info('JobService', 'pauseJob → pause request sent for job: %s', char(jobId));
            catch ME
                Logger.error('JobService', 'pauseJob FAILED (job: %s): %s', char(jobId), ME.message);
                rethrow(ME);
            end
        end

        % Fetch the results summary for a completed job.
        function data = getResults(obj, jobId, token)
            ep = sprintf('/api/jobs/%s/results', char(jobId));
            Logger.info('JobService', 'getResults → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('JobService', 'getResults → results received for job: %s', char(jobId));
            catch ME
                Logger.error('JobService', 'getResults FAILED (job: %s): %s', char(jobId), ME.message);
                rethrow(ME);
            end
        end

        % Fetch the detailed analysis (distributions, per-qubit metrics).
        function data = getDetailedResults(obj, jobId, token)
            ep = sprintf('/api/jobs/%s/results/detailed', char(jobId));
            Logger.info('JobService', 'getDetailedResults → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('JobService', 'getDetailedResults → detailed results received for job: %s', char(jobId));
            catch ME
                Logger.error('JobService', 'getDetailedResults FAILED (job: %s): %s', char(jobId), ME.message);
                rethrow(ME);
            end
        end

        % Retrieve error-rate trend history for a job.
        function data = getErrorTrends(obj, jobId, token)
            ep = sprintf('/api/jobs/%s/error-trends', char(jobId));
            Logger.info('JobService', 'getErrorTrends → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('JobService', 'getErrorTrends → error trends received for job: %s', char(jobId));
            catch ME
                Logger.error('JobService', 'getErrorTrends FAILED (job: %s): %s', char(jobId), ME.message);
                rethrow(ME);
            end
        end

        % Project-scoped job list.
        function data = listProjectJobs(obj, projectId, token, skip, limit)
            if nargin < 4; skip  = 0;  end
            if nargin < 5; limit = 50; end
            ep = sprintf('/api/projects/%s/jobs?skip=%d&limit=%d', ...
                char(projectId), round(skip), round(limit));
            Logger.info('JobService', 'listProjectJobs → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('JobService', 'listProjectJobs → response received for project: %s', char(projectId));
            catch ME
                Logger.error('JobService', 'listProjectJobs FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end

        % Project-scoped job submission.
        function data = submitProjectJob(obj, projectId, payload, token)
            ep = sprintf('/api/projects/%s/jobs', char(projectId));
            Logger.info('JobService', 'submitProjectJob → POST %s', ep);
            try
                data = obj.Client.postAuthJson(ep, payload, token);
                Logger.info('JobService', 'submitProjectJob → project job submitted for project: %s', char(projectId));
            catch ME
                Logger.error('JobService', 'submitProjectJob FAILED (project: %s): %s', char(projectId), ME.message);
                rethrow(ME);
            end
        end
    end
end
