classdef ReportService < handle
    % ReportService  Domain service for report generation and distribution.
    %
    %   Wraps the global /api/reports/* endpoints.  Project-scoped report
    %   generation is handled by ProjectService.generateReport.

    properties (Access = private)
        Client  % FastAPIClient instance (relaxed from typed property so tests can inject a StubFastAPIClient)
    end

    methods
        function obj = ReportService(client)
            obj.Client = client;
            Logger.info('ReportService', 'Initialized');
        end

        % Generate a report from the current pipeline state.
        %   Backward-compatible 5-arg form kept for ReportsScreen flow:
        %       generateReport(title, format, sections, jobId, token)
        %   Extended 8-arg form for new analyses (e.g. Quantum Monte Carlo):
        %       generateReport(title, reportType, format, circuitId, predictionId, jobId, sections, token)
        %   Extended 9-arg form with metadata (e.g. Quantum Error Mitigation):
        %       generateReport(title, reportType, format, circuitId, predictionId, jobId, sections, token, metadata)
        %     metadata is a struct merged into the request body's
        %     `metadata` field; the QEM popup uses
        %       struct('report_kind','error_mitigation', ...
        %              'em_bundle', {...}, 'em_form', struct(...))
        %     so the backend can route to its dedicated QEM PDF builder.
        function data = generateReport(obj, title, formatOrType, sectionsOrFormat, ...
                                       jobIdOrCircuitId, tokenOrPredictionId, ...
                                       maybeJobId, maybeSections, maybeToken, ...
                                       maybeMetadata)
            metadata = struct();
            if nargin >= 10
                % Extended 9-argument call (with metadata)
                reportType   = char(formatOrType);
                format       = lower(char(sectionsOrFormat));
                circuitId    = char(jobIdOrCircuitId);
                predictionId = char(tokenOrPredictionId);
                jobId        = char(maybeJobId);
                sections     = maybeSections;
                token        = maybeToken;
                if isstruct(maybeMetadata)
                    metadata = maybeMetadata;
                end
            elseif nargin >= 9
                % Extended 8-argument call
                reportType   = char(formatOrType);
                format       = lower(char(sectionsOrFormat));
                circuitId    = char(jobIdOrCircuitId);
                predictionId = char(tokenOrPredictionId);
                jobId        = char(maybeJobId);
                sections     = maybeSections;
                token        = maybeToken;
            else
                reportType   = 'technical';
                format       = lower(char(formatOrType));
                circuitId    = '';
                predictionId = '';
                jobId        = char(jobIdOrCircuitId);
                sections     = sectionsOrFormat;
                token        = tokenOrPredictionId;
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
            % Only attach metadata when the caller actually supplied
            % at least one field — keeps the wire format identical for
            % the legacy 5/8-arg call sites and avoids sending an empty
            % `metadata: {}` that the older deployed server may reject.
            if ~isempty(fieldnames(metadata))
                payload.metadata = metadata;
            end
            try
                data = obj.Client.postAuthJson('/api/reports/generate', payload, token);
                Logger.info('ReportService', 'generateReport → report generation complete');
            catch ME
                Logger.error('ReportService', 'generateReport FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % List all reports accessible to the current user.
        %   Optional `skip` / `limit` enable server-side pagination via
        %   ?skip=&limit= query params. The Reports library uses this
        %   so large report archives don't pull in one giant payload.
        %   1-arg form (`listReports(token)`) preserved for legacy
        %   callers — those send no query string.
        function data = listReports(obj, token, skip, limit)
            if nargin >= 4
                ep = sprintf('/api/reports?skip=%d&limit=%d', ...
                    round(skip), round(limit));
            else
                ep = '/api/reports';
            end
            Logger.info('ReportService', 'listReports → GET %s', ep);
            try
                data = obj.Client.getAuth(ep, token);
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
