classdef ReportService < handle
    % ReportService  Domain service for report generation and distribution.
    %
    %   Wraps the global /api/reports/* endpoints.  Project-scoped report
    %   generation is handled by ProjectService.generateReport.

    properties (Access = private)
        Client FastAPIClient
    end

    methods
        function obj = ReportService(client)
            obj.Client = client;
            Logger.info('ReportService', 'Initialized');
        end

        % Generate a report from the current pipeline state.
        function data = generateReport(obj, title, format, sections, jobId, token)
            Logger.info('ReportService', 'generateReport → POST /api/reports/generate (format: %s  job: %s)', ...
                char(format), char(jobId));
            payload = struct( ...
                'title',    char(title), ...
                'format',   char(format), ...
                'sections', char(sections), ...
                'job_id',   char(jobId));
            try
                data = obj.Client.postAuthJson('/api/reports/generate', payload, token);
                Logger.info('ReportService', 'generateReport → report generation complete');
            catch ME
                Logger.error('ReportService', 'generateReport FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % List all reports accessible to the current user.
        function data = listReports(obj, token)
            Logger.info('ReportService', 'listReports → GET /api/reports');
            try
                data = obj.Client.getAuth('/api/reports', token);
                Logger.info('ReportService', 'listReports → response received');
            catch ME
                Logger.error('ReportService', 'listReports FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Fetch report metadata by ID.
        function data = getReport(obj, reportId, token)
            ep = sprintf('/api/reports/%s', FastAPIClient.encodePathSegment(reportId));
            Logger.info('ReportService', 'getReport → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ReportService', 'getReport → response received for report: %s', char(reportId));
            catch ME
                Logger.error('ReportService', 'getReport FAILED (id: %s): %s', char(reportId), ME.message);
                rethrow(ME);
            end
        end

        % Returns download URL or base64-encoded content depending on server.
        function data = downloadReport(obj, reportId, token)
            ep = sprintf('/api/reports/%s/download', FastAPIClient.encodePathSegment(reportId));
            Logger.info('ReportService', 'downloadReport → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
                Logger.info('ReportService', 'downloadReport → download info received for report: %s', char(reportId));
            catch ME
                Logger.error('ReportService', 'downloadReport FAILED (id: %s): %s', char(reportId), ME.message);
                rethrow(ME);
            end
        end

        % Share a report by email.
        function data = shareReport(obj, reportId, email, token)
            ep = sprintf('/api/reports/%s/share', FastAPIClient.encodePathSegment(reportId));
            Logger.info('ReportService', 'shareReport → POST %s (email: %s)', ep, char(email));
            payload = struct('email', char(email));
            try
                data = obj.Client.postAuthJson(ep, payload, token);
                Logger.info('ReportService', 'shareReport → report shared with: %s', char(email));
            catch ME
                Logger.error('ReportService', 'shareReport FAILED (id: %s): %s', char(reportId), ME.message);
                rethrow(ME);
            end
        end
    end
end
