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
        %   Backward-compatible 6-arg form kept for ReportsScreen flow:
        %       generateReport(title, format, sections, jobId, token)
        %   Extended 8-arg form for new analyses (e.g. Quantum Monte Carlo):
        %       generateReport(title, reportType, format, circuitId, predictionId, jobId, sections, token)
        function data = generateReport(obj, title, formatOrType, sectionsOrFormat, ...
                                       jobIdOrCircuitId, tokenOrPredictionId, ...
                                       maybeJobId, maybeSections, maybeToken)
            if nargin >= 9
                % Extended 8-argument call
                reportType = char(formatOrType);
                format     = lower(char(sectionsOrFormat));
                circuitId  = char(jobIdOrCircuitId);
                predictionId = char(tokenOrPredictionId);
                jobId        = char(maybeJobId);
                sections     = maybeSections;
                token        = maybeToken;
            else
                reportType = 'technical';
                format     = lower(char(formatOrType));
                circuitId  = '';
                predictionId = '';
                jobId      = char(jobIdOrCircuitId);
                sections   = sectionsOrFormat;
                token      = tokenOrPredictionId;
            end
            Logger.info('ReportService', ...
                'generateReport → POST /api/reports/generate (type=%s format=%s job=%s circuit=%s)', ...
                reportType, format, jobId, circuitId);
            if iscell(sections)
                secCell = sections;
            else
                secStr = strtrim(char(sections));
                if isempty(secStr) || strcmpi(secStr, 'all')
                    secCell = {'circuit_summary','feature_analysis','benchmark_comparison', ...
                               'backend_explorer','prediction','optimization','execution_results', ...
                               'detailed_analysis'};
                else
                    secCell = strtrim(strsplit(secStr, ','));
                end
            end
            payload = struct( ...
                'title',       char(title), ...
                'report_type', reportType, ...
                'format',      format, ...
                'sections',    {secCell});
            if ~isempty(jobId);         payload.job_record_id = jobId;       end
            if ~isempty(circuitId);     payload.circuit_id    = circuitId;   end
            if ~isempty(predictionId);  payload.prediction_id = predictionId; end
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

        % Stream the report file to disk. Returns the saved local path.
        % The server responds with a FileResponse (application/pdf etc.);
        % this wrapper handles the binary GET via FastAPIClient.downloadFileAuth.
        function savedPath = downloadReportFile(obj, reportId, token, localPath)
            ep = sprintf('/api/reports/%s/download', FastAPIClient.encodePathSegment(reportId));
            Logger.info('ReportService', 'downloadReportFile → GET %s → %s', ep, char(localPath));
            savedPath = obj.Client.downloadFileAuth(ep, token, localPath);
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
