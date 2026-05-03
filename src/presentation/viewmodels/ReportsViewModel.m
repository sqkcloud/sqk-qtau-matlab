classdef ReportsViewModel < handle
    % ReportsViewModel  Callback handlers for the Reports screen.
    %
    %   Phase 6.5 redesign — drives the new screen layout:
    %     - 4-card KPI strip   (Total / PDF / HTML / Latest)
    %     - uitable library    (Format / Title / Created / Status)
    %     - search field       (client-side filter against ReportsCachedItems)
    %     - selected detail    (sections / status / id below the table)
    %     - distribution row   (Open / Download / Email / Print)
    %     - workflow row       (Detailed Analysis / Restart Pipeline)
    %
    %   Mirrors the QMC popup's working report flow:
    %     POST /api/reports/generate
    %       → poll  GET /api/reports/{id}   until status='ready'
    %       → stream GET /api/reports/{id}/download to a temp file
    %       → uiputfile + copy + web() to open in OS default viewer
    %
    %   On HTTP 404 from /download, prompts the operator to re-generate
    %   from the still-extant MongoDB metadata (file went missing
    %   because /tmp/qdash_reports inside the api container is
    %   ephemeral; the deployment fix mounts it as a persistent volume).

    properties (Access = private)
        App  % QTAUWorkbenchApp
    end

    methods
        function obj = ReportsViewModel(app)
            obj.App = app;
        end

        % ── Tab open ──────────────────────────────────────────────────
        function loadReportsList(obj)
            % Populate the cache + KPIs + table from GET /api/reports.
            % Called from QTAUWorkbenchApp.autoLoadScreen on tab open
            % and from the Refresh button.
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            if ~ReportsViewModel.tableValid(app); return; end
            svc   = app.ReportSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.listReports(token), ...
                @(data) obj.onListLoaded(app, data), ...
                @(ME)   obj.onListLoadError(app, ME));
        end

        function onRefreshList(obj)
            % Manual refresh button — same as auto-load, with overlay.
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, ...
                    Labels.get('error_not_authenticated'), ...
                    'Reports', 'Icon', 'warning');
                return;
            end
            app.showLoading(Labels.get('loading_reports_list', ...
                'Refreshing reports...'));
            svc   = app.ReportSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.listReports(token), ...
                @(data) obj.onListLoaded(app, data, true), ...
                @(ME)   obj.onListLoadError(app, ME));
        end

        function onSearchChanged(obj, query)
            % Client-side filter against ReportsCachedItems.
            app = obj.App;
            if ~ReportsViewModel.tableValid(app); return; end
            obj.applyFilter(app, char(query));
        end

        function onTableSelection(obj, evt)
            % uitable CellSelectionCallback — paint the detail line.
            app = obj.App;
            if ~ReportsViewModel.tableValid(app); return; end
            row = NaN;
            try
                if ~isempty(evt) && isprop(evt, 'Indices') ...
                        && ~isempty(evt.Indices)
                    row = evt.Indices(1, 1);
                end
            catch
            end
            if isnan(row); obj.clearDetail(app); return; end
            obj.paintDetail(app, row);
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

        % ── Open (table or AppState fallback) ─────────────────────────
        function onOpenReport(obj)
            app = obj.App;
            rid = ReportsViewModel.currentReportId(app);
            if isempty(rid)
                app.setStatus(app.ReportStatusArea, { ...
                    'No report selected.', ...
                    'Pick a row from the library or click Generate first.'});
                return;
            end
            obj.dispatchDownload(app, rid, char(app.ReportTitleField.Value));
        end

        % ── Distribution ──────────────────────────────────────────────
        function onDownloadPdf(obj)
            obj.onOpenReport();
        end

        function onShareEmail(obj)
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
                    'Pick a report first.', ...
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
            app.showLoading(Labels.get('loading_report_share', 'Sharing report...'));
            AsyncRunner.run( ...
                @() svc.shareReport(rid, email, token), ...
                @(data) obj.onShareSuccess(app, email, data), ...
                @(ME)   obj.onShareError(app, email, ME));
        end

        function onPrintReport(obj)
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
            % Insert a synthetic metadata row so the new report appears
            % at the top of the table immediately, even before the next
            % full list refresh.
            newMeta = struct( ...
                'report_id', reportId, ...
                'title',     title, ...
                'format',    fmt, ...
                'status',    status, ...
                'created_at', char(datetime('now', ...
                    'TimeZone','UTC', 'Format','yyyy-MM-dd''T''HH:mm:ss')));
            obj.upsertCachedItem(app, newMeta);
            obj.applyFilter(app, char(app.ReportsSearchField.Value));
            obj.selectByReportId(app, reportId);
            app.setStatus(app.ReportStatusArea, { ...
                sprintf('✔ Generated %s · status: %s', upper(fmt), status), ...
                sprintf('id: %s', reportId), ...
                'Downloading file...'});
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
                '✗ Generation failed.', ME.message});
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
                    '✗ Download finished but the local file is missing.'});
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
                    sprintf('• Cached at: %s', tmpPath), ...
                    'Click Open from the library to re-download.'});
                Logger.info('ReportsViewModel', ...
                    'Save cancelled; temp file: %s', tmpPath);
                return;
            end
            target = fullfile(pathName, fileName);
            try
                copyfile(tmpPath, target, 'f');
                app.logEvent('API', sprintf('Report %s saved to %s', reportId, target));
                app.setStatus(app.ReportStatusArea, { ...
                    sprintf('✔ Saved: %s', target), ...
                    '• Opening in default viewer...'});
                try; web(target, '-browser'); catch; end
            catch ME
                Logger.warn('ReportsViewModel', ...
                    'Copy to user path failed: %s', ME.message);
                app.setStatus(app.ReportStatusArea, { ...
                    sprintf('• Cached at: %s', tmpPath), ...
                    sprintf('✗ Could not copy to chosen path: %s', ME.message)});
            end
        end

        function onDownloadError(obj, app, reportId, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf( ...
                'Report download FAILED: %s', ME.message));
            isMissingFile = contains(string(ME.message), 'HTTP404') ...
                || contains(string(ME.message), 'status 404') ...
                || contains(string(ME.identifier), 'HTTP404');
            if isMissingFile && ~isempty(reportId)
                obj.onMissingFileRegenerate(app, reportId);
                return;
            end
            app.setStatus(app.ReportStatusArea, { ...
                '✗ Download failed.', ME.message});
            app.showError('Download Report', ME);
        end

        function onMissingFileRegenerate(obj, app, reportId)
            Logger.warn('ReportsViewModel', ...
                'Report file missing on server (id=%s) — offering regenerate', ...
                reportId);
            app.setStatus(app.ReportStatusArea, { ...
                '✗ Report file missing on server.', ...
                sprintf('id: %s', reportId), ...
                '• Cause: api container restart cleared /tmp/qdash_reports.', ...
                '• Mount that path as a docker volume to persist files.'});
            choice = uiconfirm(app.UIFigure, ...
                sprintf(['The rendered report file for this entry is no longer ' ...
                         'on the server (HTTP 404). The metadata still ' ...
                         'exists in MongoDB.\n\nRe-generate this report ' ...
                         'from its existing metadata?']), ...
                'Report file missing', ...
                'Options', {'Re-generate', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 2, ...
                'Icon', 'warning');
            if ~strcmp(choice, 'Re-generate')
                return;
            end
            svc   = app.ReportSvc;
            token = app.State.authToken;
            try
                meta = svc.getReport(reportId, token);
            catch ME2
                app.showError('Re-generate Report', ME2);
                return;
            end
            title    = char(JsonHelper.pick(meta, {'title'}, ...
                            char(app.ReportTitleField.Value)));
            fmt      = lower(char(JsonHelper.pick(meta, {'format'}, 'pdf')));
            sections = JsonHelper.extractList(meta, 'sections');
            if isempty(sections); sections = {'all'}; end
            if ~iscell(sections); sections = {char(sections)}; end
            cid      = char(JsonHelper.pick(meta, {'circuit_id'},    ''));
            pid      = char(JsonHelper.pick(meta, {'prediction_id'}, ''));
            jid      = char(JsonHelper.pick(meta, {'job_record_id'}, ''));
            app.showLoading(Labels.get('loading_report', 'Generating report...'));
            workFcn = @() svc.generateReport(title, 'technical', fmt, ...
                cid, pid, jid, sections, token);
            AsyncRunner.run(workFcn, ...
                @(data) obj.onGenerateComplete(app, fmt, title, data), ...
                @(ME3)  obj.onGenerateError(app, fmt, ME3));
        end

        % ── Share continuation ────────────────────────────────────────
        function onShareSuccess(~, app, email, ~)
            app.hideLoading();
            app.setStatus(app.ReportStatusArea, { ...
                sprintf('✔ Shared with %s.', email)});
            app.logEvent('API', sprintf('Report shared with %s', email));
        end

        function onShareError(~, app, email, ME)
            app.hideLoading();
            app.setStatus(app.ReportStatusArea, { ...
                sprintf('✗ Share to %s failed.', email), ME.message});
            app.showError('Share Report', ME);
        end

        % ── List load continuation ────────────────────────────────────
        function onListLoaded(obj, app, data, hideOverlay)
            if nargin < 4; hideOverlay = false; end
            if hideOverlay; app.hideLoading(); end
            if ~ReportsViewModel.tableValid(app); return; end
            items = JsonHelper.extractList(data, 'reports');
            if isempty(items); items = JsonHelper.asList(data); end
            % Normalize to a cell array of structs so search/filter can
            % iterate it without struct-array vs cell branching.
            cache = {};
            for i = 1:numel(items)
                if iscell(items)
                    cache{end+1} = items{i}; %#ok<AGROW>
                else
                    cache{end+1} = items(i); %#ok<AGROW>
                end
            end
            app.ReportsCachedItems = cache;
            obj.paintKpis(app, cache);
            obj.applyFilter(app, char(app.ReportsSearchField.Value));
        end

        function onListLoadError(~, app, ME)
            app.hideLoading();
            Logger.warn('ReportsViewModel', ...
                'listReports failed: %s', ME.message);
            app.setStatus(app.ReportStatusArea, { ...
                '✗ Failed to load reports.', ME.message});
        end

        % ── Cache + render helpers ────────────────────────────────────
        function applyFilter(obj, app, query)
            % Filter ReportsCachedItems by case-insensitive substring
            % match on title or format. Repaints the table and the KPI
            % "matching" hint.
            cache = app.ReportsCachedItems;
            if ~iscell(cache); cache = {}; end
            q = lower(strtrim(char(query)));
            keep = true(1, numel(cache));
            if ~isempty(q)
                for i = 1:numel(cache)
                    title = lower(char(JsonHelper.pick(cache{i}, {'title'}, '')));
                    fmt   = lower(char(JsonHelper.pick(cache{i}, {'format'}, '')));
                    if isempty(strfind(title, q)) && isempty(strfind(fmt, q))
                        keep(i) = false;
                    end
                end
            end
            obj.paintTable(app, cache(keep));
        end

        function paintTable(~, app, items)
            if ~ReportsViewModel.tableValid(app); return; end
            n = numel(items);
            if n == 0
                app.ReportsTable.Data     = {};
                app.ReportsTable.UserData = struct('ids', {{}}, 'metas', {{}});
                return;
            end
            data = cell(n, 4);
            ids  = cell(1, n);
            metas = cell(1, n);
            for i = 1:n
                m = items{i};
                fmt   = lower(char(JsonHelper.pick(m, {'format'}, 'pdf')));
                title = char(JsonHelper.pick(m, {'title'},  '(untitled)'));
                created = char(JsonHelper.pick(m, {'created_at','createdAt'}, ''));
                stamp = '';
                if numel(created) >= 16
                    stamp = strrep(created(1:min(16, end)), 'T', ' ');
                end
                status = char(JsonHelper.pick(m, {'status'}, '—'));
                data{i, 1} = sprintf('%s %s', ...
                    ReportsViewModel.formatGlyph(fmt), upper(fmt));
                data{i, 2} = title;
                data{i, 3} = stamp;
                data{i, 4} = status;
                ids{i}   = char(JsonHelper.pick(m, {'report_id','id'}, ''));
                metas{i} = m;
            end
            app.ReportsTable.Data = data;
            app.ReportsTable.UserData = struct('ids', {ids}, 'metas', {metas});
        end

        function paintKpis(~, app, cache)
            n = numel(cache);
            pdfN = 0; htmlN = 0;
            latestEpoch = -inf;
            for i = 1:n
                fmt = lower(char(JsonHelper.pick(cache{i}, {'format'}, '')));
                if strcmp(fmt, 'pdf');  pdfN  = pdfN  + 1; end
                if strcmp(fmt, 'html'); htmlN = htmlN + 1; end
                created = char(JsonHelper.pick(cache{i}, {'created_at','createdAt'}, ''));
                ts = ReportsViewModel.parseIsoSeconds(created);
                if ~isnan(ts) && ts > latestEpoch; latestEpoch = ts; end
            end
            try
                app.ReportsKpiTotal.Text  = sprintf('%d', n);
                app.ReportsKpiPdf.Text    = sprintf('%d', pdfN);
                app.ReportsKpiHtml.Text   = sprintf('%d', htmlN);
                if isinf(latestEpoch)
                    app.ReportsKpiLatest.Text = '—';
                else
                    app.ReportsKpiLatest.Text = ReportsViewModel.humanizeAge(latestEpoch);
                end
            catch ME
                Logger.debug('ReportsViewModel', 'paintKpis: %s', ME.message);
            end
        end

        function paintDetail(~, app, row)
            ud = app.ReportsTable.UserData;
            if ~isstruct(ud) || ~isfield(ud, 'metas') || ...
                    row < 1 || row > numel(ud.metas)
                return;
            end
            m = ud.metas{row};
            sections = JsonHelper.extractList(m, 'sections');
            if isempty(sections); sections = {}; end
            if ~iscell(sections); sections = num2cell(sections); end
            secStrs = cell(1, numel(sections));
            for i = 1:numel(sections); secStrs{i} = char(string(sections{i})); end
            try
                rid = ud.ids{row};
            catch
                rid = char(JsonHelper.pick(m, {'report_id','id'}, ''));
            end
            status = char(JsonHelper.pick(m, {'status'}, '—'));
            fmt    = lower(char(JsonHelper.pick(m, {'format'}, 'pdf')));
            title  = char(JsonHelper.pick(m, {'title'}, '(untitled)'));
            secLine = strjoin(secStrs, ', ');
            if isempty(secLine); secLine = '(default)'; end
            app.ReportsDetailLabel.Text = sprintf( ...
                'Selected · %s · %s · status %s · sections: %s · id: %s', ...
                title, upper(fmt), status, secLine, rid);
            % Sticky reportId for downstream Open / Email / Print.
            app.State.reportId = string(rid);
        end

        function clearDetail(~, app)
            try
                app.ReportsDetailLabel.Text = Labels.get( ...
                    'reports_detail_empty', ...
                    'Pick a row to see its sections, status, and id.');
            catch
            end
        end

        function upsertCachedItem(~, app, newMeta)
            % Insert (or move-to-front) the metadata struct keyed by
            % report_id. Used after a successful generate so the new
            % row appears at top of the table immediately.
            cache = app.ReportsCachedItems;
            if ~iscell(cache); cache = {}; end
            newId = char(JsonHelper.pick(newMeta, {'report_id','id'}, ''));
            keep = true(1, numel(cache));
            for i = 1:numel(cache)
                cid = char(JsonHelper.pick(cache{i}, {'report_id','id'}, ''));
                if strcmp(cid, newId); keep(i) = false; end
            end
            cache = cache(keep);
            app.ReportsCachedItems = [{newMeta}, cache];
        end

        function selectByReportId(~, app, reportId)
            try
                ids = app.ReportsTable.UserData.ids;
            catch
                return;
            end
            if ~iscell(ids); return; end
            for i = 1:numel(ids)
                if strcmp(ids{i}, char(reportId))
                    try
                        app.ReportsTable.Selection = i;
                    catch
                    end
                    return;
                end
            end
        end
    end

    methods (Static, Access = private)
        function tf = tableValid(app)
            tf = isprop(app, 'ReportsTable') ...
                && ~isempty(app.ReportsTable) ...
                && isvalid(app.ReportsTable);
        end

        function rid = currentReportId(app)
            % Best-effort current report-id:
            %   1. table selection,
            %   2. AppState.reportId (set after Generate or last selection).
            rid = '';
            try
                if isprop(app, 'ReportsTable') ...
                        && ~isempty(app.ReportsTable) ...
                        && isvalid(app.ReportsTable) ...
                        && ~isempty(app.ReportsTable.Selection)
                    sel = app.ReportsTable.Selection(1);
                    ids = app.ReportsTable.UserData.ids;
                    if iscell(ids) && sel >= 1 && sel <= numel(ids)
                        rid = char(ids{sel});
                    end
                end
            catch
            end
            if isempty(rid) ...
                    && isprop(app, 'State') && ~isempty(app.State) ...
                    && strlength(app.State.reportId) > 0
                rid = char(app.State.reportId);
            end
        end

        function g = formatGlyph(fmt)
            switch lower(char(fmt))
                case 'pdf';  g = char(128196);  % 📄
                case 'html'; g = char(127760);  % 🌐
                case 'json'; g = char(128203);  % 📋
                otherwise;   g = char(128196);
            end
        end

        function ts = parseIsoSeconds(iso)
            % Parse "YYYY-MM-DDTHH:MM:SS[.fff]" or "YYYY-MM-DD HH:MM:SS"
            % to MATLAB datenum-style epoch seconds. Returns NaN on parse
            % failure. We only need monotonic ordering and "minutes ago"
            % humanisation, so a single best-effort pattern is enough.
            ts = NaN;
            if isempty(iso); return; end
            try
                s = strrep(char(iso), 'T', ' ');
                if numel(s) >= 19
                    s = s(1:19);
                    dt = datetime(s, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                    ts = posixtime(dt);
                end
            catch
            end
        end

        function txt = humanizeAge(epoch)
            now_s = posixtime(datetime('now','TimeZone','UTC'));
            delta = max(now_s - epoch, 0);
            if delta < 60
                txt = sprintf('%ds ago',  round(delta));
            elseif delta < 3600
                txt = sprintf('%dm ago',  round(delta / 60));
            elseif delta < 86400
                txt = sprintf('%dh ago',  round(delta / 3600));
            else
                txt = sprintf('%dd ago',  round(delta / 86400));
            end
        end

        function savedPath = pollAndDownload(reportSvc, reportId, token)
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
