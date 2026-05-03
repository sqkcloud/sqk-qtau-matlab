classdef ReportsViewModel < handle
    % ReportsViewModel  Callback handlers for the Reports screen.
    %
    %   Mirrors the QMC popup's working report flow:
    %     POST /api/reports/generate
    %       → poll  GET /api/reports/{id}   until status='ready'
    %       → stream GET /api/reports/{id}/download to a temp file
    %       → uiputfile + copy + web() to open in OS default viewer
    %
    %   The previous implementation only POSTed and stored report_id;
    %   the Open button then called `downloadReport` which webread's a
    %   binary PDF as JSON and quietly fails. End result: the screen
    %   appeared to "do nothing" once Generate completed. This rewrite
    %   inherits the QMC pattern (which is known-working) and also
    %   wires the Distribution Actions (PDF / Email / Print) that were
    %   previously inert in ReportsScreen.

    properties (Access = private)
        App  % QTAUWorkbenchApp
    end

    methods
        function obj = ReportsViewModel(app)
            obj.App = app;
        end

        % ── Tab open ──────────────────────────────────────────────────
        function loadReportsList(obj)
            % Populate the GeneratedReportList with the user's existing
            % reports (newest first) so Open / PDF / Email work even on
            % a fresh tab visit. Called from QTAUWorkbenchApp.autoLoadScreen.
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            if isempty(app.GeneratedReportList) ...
                    || ~isvalid(app.GeneratedReportList); return; end
            svc   = app.ReportSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.listReports(token), ...
                @(data) obj.onListLoaded(app, data), ...
                @(ME)   Logger.warn('ReportsViewModel', ...
                    'listReports failed: %s', ME.message));
        end

        % ── Generate ──────────────────────────────────────────────────
        function onGenerateReport(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, ...
                    Labels.get('error_not_authenticated'), ...
                    'Reports', 'Icon', 'warning');
                return;
            end
            reportTitle = char(app.ReportTitleField.Value);
            fmt         = lower(char(app.ReportFormatDropdown.Value));
            sections    = char(app.ReportSectionsField.Value);
            token       = app.State.authToken;
            projectSvc  = app.ProjectSvc;
            reportSvc   = app.ReportSvc;
            if app.State.hasProject()
                pid = app.State.currentProjectId;
                app.logEvent('API', sprintf( ...
                    'POST /api/projects/%s/reports — title: %s  format: %s', ...
                    pid, reportTitle, fmt));
                workFcn = @() projectSvc.generateReport( ...
                    pid, reportTitle, fmt, sections, token);
            else
                jobId = app.State.selectedJobId;
                app.logEvent('API', sprintf( ...
                    'POST /api/reports/generate — title: %s  format: %s  job: %s', ...
                    reportTitle, fmt, jobId));
                workFcn = @() reportSvc.generateReport( ...
                    reportTitle, fmt, sections, jobId, token);
            end
            app.showLoading(Labels.get('loading_report', 'Generating report...'));
            AsyncRunner.run(workFcn, ...
                @(data) obj.onGenerateComplete(app, fmt, reportTitle, data), ...
                @(ME)   obj.onGenerateError(app, fmt, ME));
        end

        % ── Open (Report Preview "▶ Open" button) ─────────────────────
        function onOpenReport(obj)
            app = obj.App;
            rid = '';
            try; rid = char(app.GeneratedReportList.Value); catch; end
            if isempty(rid) && app.State.isAuthenticated() ...
                    && strlength(app.State.reportId) > 0
                rid = char(app.State.reportId);
            end
            if isempty(rid)
                app.setStatus(app.ReportStatusArea, { ...
                    'No report selected. Generate one or pick from the list.'});
                return;
            end
            obj.dispatchDownload(app, rid, char(app.ReportTitleField.Value));
        end

        % ── Distribution Actions ──────────────────────────────────────
        function onDownloadPdf(obj)
            % Distribution "↓ PDF" button — same as Open: stream the
            % currently-selected report to disk and open it.
            obj.onOpenReport();
        end

        function onShareEmail(obj)
            % Distribution "✉ Email" button — POST /api/reports/{id}/share.
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, ...
                    Labels.get('error_not_authenticated'), ...
                    'Email', 'Icon', 'warning');
                return;
            end
            rid = ReportsViewModel.currentReportId(app);
            if isempty(rid)
                uialert(app.UIFigure, ...
                    'Generate a report first.', ...
                    'Email', 'Icon', 'warning');
                return;
            end
            answer = inputdlg({'Recipient email address:'}, ...
                'Share Report', [1 50], {''});
            if isempty(answer); return; end
            email = strtrim(answer{1});
            if isempty(email); return; end
            svc   = app.ReportSvc;
            token = app.State.authToken;
            app.showLoading(Labels.get('loading_report_share', ...
                'Sharing report...'));
            AsyncRunner.run( ...
                @() svc.shareReport(rid, email, token), ...
                @(data) obj.onShareSuccess(app, email, data), ...
                @(ME)   obj.onShareError(app, email, ME));
        end

        function onPrintReport(obj)
            % Distribution "⎙ Print" button — MATLAB has no portable
            % print API for arbitrary file types. Open in the OS
            % default viewer; the operator hits Cmd-P / Ctrl-P there.
            obj.onOpenReport();
        end
    end

    methods (Access = private)
        % ── Generate continuation ─────────────────────────────────────
        function onGenerateComplete(obj, app, fmt, title, data)
            reportId = char(JsonHelper.pick(data, {'report_id','id'}, ''));
            status   = lower(char(JsonHelper.pick(data, {'status'}, '')));
            if isempty(reportId)
                app.hideLoading();
                app.setStatus(app.ReportStatusArea, { ...
                    'Server did not return a report_id; cannot continue.'});
                app.logEvent('ERROR', 'Report generation: no report_id in response');
                return;
            end
            app.State.reportId = string(reportId);
            fileName = ReportsViewModel.composeFileName(title, fmt);
            ReportsViewModel.upsertListItem( ...
                app.GeneratedReportList, fileName, reportId);
            app.setStatus(app.ReportStatusArea, { ...
                sprintf('Report generated: %s', reportId), ...
                sprintf('Status:           %s', status), ...
                sprintf('Format:           %s', fmt), ...
                'Downloading file…'});
            app.logEvent('API', sprintf( ...
                'Report generated — id: %s  status: %s  format: %s', ...
                reportId, status, fmt));
            app.State.logActivity( ...
                sprintf('Generate report — %s', fmt), 'Success');
            obj.dispatchDownload(app, reportId, title);
        end

        function onGenerateError(~, app, fmt, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf( ...
                'Report generation FAILED (format: %s): %s', fmt, ME.message));
            app.setStatus(app.ReportStatusArea, { ...
                'Report generation failed.', ME.message});
            app.showError('Generate Report', ME);
        end

        % ── Poll + download dispatcher ────────────────────────────────
        function dispatchDownload(obj, app, reportId, title)
            app.showLoading(Labels.get('loading_report_download', ...
                'Downloading PDF report...'));
            svc   = app.ReportSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() ReportsViewModel.pollAndDownload(svc, reportId, token), ...
                @(savedPath) obj.onReportDownloaded(app, reportId, savedPath, title), ...
                @(ME)        obj.onDownloadError(app, reportId, ME));
        end

        function onReportDownloaded(~, app, reportId, tmpPath, title)
            app.hideLoading();
            if isempty(tmpPath) || exist(tmpPath, 'file') ~= 2
                app.setStatus(app.ReportStatusArea, { ...
                    'Download finished but the local file is missing.'});
                return;
            end
            [~, ~, ext] = fileparts(tmpPath);
            if isempty(ext); ext = '.pdf'; end
            safeName = regexprep(char(title), '[^A-Za-z0-9_\-]', '_');
            if isempty(safeName); safeName = 'report'; end
            stamp = char(datetime('now', 'Format', 'yyyyMMdd'));
            defaultName = sprintf('Report_%s_%s%s', safeName, stamp, ext);
            [fileName, pathName] = uiputfile( ...
                {['*' ext], ['Report (' ext ')']; '*.*', 'All Files (*.*)'}, ...
                'Save report', defaultName);
            if isequal(fileName, 0)
                app.setStatus(app.ReportStatusArea, { ...
                    sprintf('Report cached at:\n%s', tmpPath), ...
                    'Click Open or pick a row from the list to re-download.'});
                Logger.info('ReportsViewModel', ...
                    'Save cancelled; temp file: %s', tmpPath);
                return;
            end
            target = fullfile(pathName, fileName);
            try
                copyfile(tmpPath, target, 'f');
                app.logEvent('API', sprintf('Report %s saved to %s', reportId, target));
                app.setStatus(app.ReportStatusArea, { ...
                    sprintf('Report saved to:\n%s', target), ...
                    'Opening in default viewer…'});
                try; web(target, '-browser'); catch; end
            catch ME
                Logger.warn('ReportsViewModel', ...
                    'Copy to user path failed: %s', ME.message);
                app.setStatus(app.ReportStatusArea, { ...
                    sprintf('Cached at:\n%s', tmpPath), ...
                    sprintf('Could not copy to chosen path: %s', ME.message)});
            end
        end

        function onDownloadError(~, app, ~, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf( ...
                'Report download FAILED: %s', ME.message));
            app.setStatus(app.ReportStatusArea, { ...
                'Download failed.', ME.message});
            app.showError('Download Report', ME);
        end

        % ── Share continuation ────────────────────────────────────────
        function onShareSuccess(~, app, email, ~)
            app.hideLoading();
            app.setStatus(app.ReportStatusArea, { ...
                sprintf('Report shared with %s.', email)});
            app.logEvent('API', sprintf('Report shared with %s', email));
        end

        function onShareError(~, app, email, ME)
            app.hideLoading();
            app.setStatus(app.ReportStatusArea, { ...
                sprintf('Share to %s failed.', email), ME.message});
            app.showError('Share Report', ME);
        end

        % ── List load continuation ────────────────────────────────────
        function onListLoaded(~, app, data)
            if isempty(app.GeneratedReportList) ...
                    || ~isvalid(app.GeneratedReportList); return; end
            items = JsonHelper.extractList(data, 'reports');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0
                app.GeneratedReportList.Items = {};
                app.GeneratedReportList.ItemsData = {};
                return;
            end
            labels  = cell(1, n);
            ids     = cell(1, n);
            for i = 1:n
                rid   = char(JsonHelper.pick(items(i), {'report_id','id'}, ''));
                title = char(JsonHelper.pick(items(i), {'title'}, '(untitled)'));
                fmt   = lower(char(JsonHelper.pick(items(i), {'format'}, 'pdf')));
                created = char(JsonHelper.pick(items(i), {'created_at','createdAt'}, ''));
                stamp = '';
                if numel(created) >= 16
                    stamp = strrep(created(1:min(16, end)), 'T', ' ');
                end
                if isempty(stamp); stamp = ''; else; stamp = [' · ' stamp]; end
                labels{i} = sprintf('%s · %s%s', title, fmt, stamp);
                ids{i}    = rid;
            end
            app.GeneratedReportList.Items     = labels;
            app.GeneratedReportList.ItemsData = ids;
            if ~isempty(ids)
                app.GeneratedReportList.Value = ids{1};
            end
        end
    end

    methods (Static, Access = private)
        function rid = currentReportId(app)
            % Best-effort current report-id: list selection > AppState.reportId.
            rid = '';
            try; rid = char(app.GeneratedReportList.Value); catch; end
            if isempty(rid) ...
                    && isprop(app, 'State') && ~isempty(app.State) ...
                    && strlength(app.State.reportId) > 0
                rid = char(app.State.reportId);
            end
        end

        function name = composeFileName(title, fmt)
            safeName = regexprep(char(title), '[^A-Za-z0-9_\-]', '_');
            if isempty(safeName); safeName = 'report'; end
            stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmm'));
            ext   = lower(char(fmt));
            if isempty(ext); ext = 'pdf'; end
            name = sprintf('%s_%s.%s', safeName, stamp, ext);
        end

        function upsertListItem(listBox, label, reportId)
            % Add (or move-to-top) a list entry whose ItemsData equals
            % reportId, then select it. Existing entries with the same
            % id are de-duplicated.
            if isempty(listBox) || ~isvalid(listBox); return; end
            curItems = listBox.Items;
            curData  = listBox.ItemsData;
            if ~iscell(curItems); curItems = {}; end
            if ~iscell(curData);  curData  = {}; end
            keep = true(1, numel(curData));
            for i = 1:numel(curData)
                if ischar(curData{i}) && strcmp(curData{i}, reportId)
                    keep(i) = false;
                end
            end
            curItems = curItems(keep);
            curData  = curData(keep);
            listBox.Items     = [{char(label)},     curItems];
            listBox.ItemsData = [{char(reportId)},  curData];
            listBox.Value     = char(reportId);
        end

        function savedPath = pollAndDownload(reportSvc, reportId, token)
            % Poll GET /reports/{id} until status='ready' (or 'completed'),
            % then stream the file to a temp path. Mirrors the static
            % helper used by the QMC popup, but uses a 'report_' prefix
            % on the temp filename so concurrent QMC + Reports flows
            % don't collide.
            deadline   = tic;
            maxSeconds = 60;
            pause_s    = 0.75;
            status     = '';
            fmt        = '';
            while toc(deadline) < maxSeconds
                meta   = reportSvc.getReport(reportId, token);
                status = lower(char(JsonHelper.pick(meta, {'status'}, '')));
                fmt    = lower(char(JsonHelper.pick(meta, {'format'}, 'pdf')));
                if any(strcmp(status, {'ready', 'completed', 'success', 'done'}))
                    break;
                elseif any(strcmp(status, {'failed', 'error'}))
                    msg = char(JsonHelper.pick(meta, {'message','error'}, ...
                        'Report generation failed on the server.'));
                    error('QTAU:ReportFailed', '%s', msg);
                end
                pause(pause_s);
            end
            if ~any(strcmp(status, {'ready', 'completed', 'success', 'done'}))
                error('QTAU:ReportTimeout', ...
                    'Report did not reach ready state within %d seconds.', ...
                    maxSeconds);
            end
            if isempty(fmt); fmt = 'pdf'; end
            ext = ['.' fmt];
            if strcmp(ext, '.') || strcmp(ext, '..'); ext = '.pdf'; end
            savedPath = fullfile(tempdir, sprintf('report_%s%s', reportId, ext));
            reportSvc.downloadReportFile(reportId, token, savedPath);
        end
    end
end
