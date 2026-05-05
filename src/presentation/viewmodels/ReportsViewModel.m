classdef ReportsViewModel < handle
    % ReportsViewModel  Callback handlers for the Reports screen.
    %
    %   Phase 6.6 — pagination + right-click context menu, no Selected line.
    %
    %   Drives:
    %     - 4-card KPI strip   (Total / PDF / HTML / Latest) — cumulative
    %       across loaded pages so paging doesn't make the totals shrink.
    %     - uitable library    (Format / Title / Created / Status)
    %     - search field       (client-side filter against the cumulative
    %                           ReportsCachedItems cache)
    %     - pagination footer  (Prev · "Page N · Y items" · Next)
    %     - right-click popup  (Open / Download / Email / Print) via
    %                           PopupMenuManager.buildReportsPopup

    properties (Access = private)
        App  % QTAUWorkbenchApp
    end

    properties (Access = private)
        LastPageItemCount = 0   % items returned by the most recent fetch
                                % (used to know whether Next has more pages)
    end

    methods
        function obj = ReportsViewModel(app)
            obj.App = app;
        end

        % ── Tab open / Refresh ────────────────────────────────────────
        function loadReportsList(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            if ~ReportsViewModel.tableValid(app); return; end
            obj.fetchPage(app, app.ReportsCurrentPage, false);
            % Pre-seed the report title so the operator doesn't have to
            % retype it every visit. Skipped when the field already has
            % content so existing typing is preserved.
            ReportsViewModel.seedReportTitle(app);
        end

        function onRefreshList(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, ...
                    Labels.get('error_not_authenticated'), ...
                    'Reports', 'Icon', 'warning');
                return;
            end
            % Refresh stays on the current page so the user's place
            % isn't lost.
            obj.fetchPage(app, app.ReportsCurrentPage, true);
        end

        function onPrevPage(obj)
            app = obj.App;
            if app.ReportsCurrentPage <= 1; return; end
            obj.fetchPage(app, app.ReportsCurrentPage - 1, true);
        end

        function onNextPage(obj)
            app = obj.App;
            % Next is enabled only when the previous page filled to
            % page-size — i.e. there's at least one more page available.
            if obj.LastPageItemCount < app.ReportsPageSize; return; end
            obj.fetchPage(app, app.ReportsCurrentPage + 1, true);
        end

        function onSearchChanged(obj, query)
            app = obj.App;
            if ~ReportsViewModel.tableValid(app); return; end
            obj.applyFilter(app, char(query));
        end

        function onTableSelection(obj, evt)
            % Sticky selection for downstream Open / context menu.
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
            if isnan(row); return; end
            try
                ids = app.ReportsTable.UserData.ids;
                if iscell(ids) && row >= 1 && row <= numel(ids)
                    app.State.reportId = string(ids{row});
                end
            catch
            end
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

        % ── Open + distribution ───────────────────────────────────────
        function onOpenReport(obj)
            app = obj.App;
            rid = ReportsViewModel.currentReportId(app);
            if isempty(rid)
                app.setStatus(app.ReportStatusArea, { ...
                    [char(9888) ' No report selected'], ...
                    '   Pick a row in the library or click Generate first.'});
                return;
            end
            obj.dispatchDownload(app, rid, char(app.ReportTitleField.Value));
        end

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
        % ── Pagination dispatch ───────────────────────────────────────
        function fetchPage(obj, app, page, withOverlay)
            page = max(1, round(page));
            skip  = (page - 1) * app.ReportsPageSize;
            limit = app.ReportsPageSize;
            svc   = app.ReportSvc;
            token = app.State.authToken;
            if withOverlay
                app.showLoading(Labels.get('loading_reports_list', ...
                    'Refreshing reports...'));
            end
            AsyncRunner.run( ...
                @() svc.listReports(token, skip, limit), ...
                @(data) obj.onPageLoaded(app, data, page, withOverlay), ...
                @(ME)   obj.onListLoadError(app, ME, withOverlay));
        end

        % ── Generate continuation ─────────────────────────────────────
        function onGenerateComplete(obj, app, fmt, title, data)
            reportId = char(JsonHelper.pick(data, {'report_id','id'}, ''));
            status   = lower(char(JsonHelper.pick(data, {'status'}, '')));
            if isempty(reportId)
                app.hideLoading();
                app.setStatus(app.ReportStatusArea, { ...
                    [char(10007) ' Failed'], ...
                    '   Server did not return a report_id.', ...
                    '   See the event log for details.'});
                app.logEvent('ERROR', 'Report generation: no report_id in response');
                return;
            end
            app.State.reportId = string(reportId);
            % Insert a synthetic metadata row so the new report shows
            % up at the top of the cumulative cache + table immediately.
            newMeta = struct( ...
                'report_id', reportId, ...
                'title',     title, ...
                'format',    fmt, ...
                'status',    status, ...
                'created_at', char(datetime('now', ...
                    'TimeZone','UTC', 'Format','yyyy-MM-dd''T''HH:mm:ss')));
            obj.upsertCachedItem(app, newMeta);
            obj.paintKpis(app, app.ReportsCachedItems);
            obj.applyFilter(app, char(app.ReportsSearchField.Value));
            obj.selectByReportId(app, reportId);
            app.setStatus(app.ReportStatusArea, { ...
                sprintf('%s Generated  ·  %s  ·  %s', char(9679), upper(fmt), status), ...
                sprintf('   id  %s', reportId), ...
                '   Streaming the rendered file...'});
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
                [char(10007) ' Generation failed'], ...
                ['   ' char(ME.message)], ...
                '   See the event log for details.'});
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
                    [char(10007) ' Download incomplete'], ...
                    '   Download finished but the local file is missing.'});
                return;
            end
            [~, ~, ext] = fileparts(tmpPath);
            if isempty(ext); ext = '.pdf'; end
            safeName = regexprep(char(title), '[^A-Za-z0-9_\-]', '_');
            if isempty(safeName); safeName = 'report'; end
            % Operator filename rule for generic PDF reports:
            %   Report_<title>_<YYYYMMDD_HHMM>.pdf
            defaultName = sprintf('Report_%s_%s%s', ...
                safeName, Exporter.minuteStamp(), ext);
            % Default to the OS Downloads folder — see Exporter.defaultDir.
            [fileName, pathName] = uiputfile( ...
                {['*' ext], ['Report (' ext ')']; '*.*', 'All Files (*.*)'}, ...
                'Save report', Exporter.savePath(defaultName));
            if isequal(fileName, 0)
                app.setStatus(app.ReportStatusArea, { ...
                    [char(9679) ' Cached'], ...
                    sprintf('   %s', tmpPath), ...
                    '   Click Open in the library to re-download.'});
                Logger.info('ReportsViewModel', ...
                    'Save cancelled; temp file: %s', tmpPath);
                return;
            end
            target = fullfile(pathName, fileName);
            try
                copyfile(tmpPath, target, 'f');
                app.logEvent('API', sprintf('Report %s saved to %s', reportId, target));
                app.setStatus(app.ReportStatusArea, { ...
                    [char(10003) ' Saved'], ...
                    sprintf('   %s', target), ...
                    '   Opened in your default viewer.'});
                try; web(target, '-browser'); catch; end
            catch ME
                Logger.warn('ReportsViewModel', ...
                    'Copy to user path failed: %s', ME.message);
                app.setStatus(app.ReportStatusArea, { ...
                    [char(10007) ' Save failed'], ...
                    sprintf('   Cached at: %s', tmpPath), ...
                    sprintf('   %s', ME.message)});
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
                [char(10007) ' Download failed'], ...
                ['   ' char(ME.message)], ...
                '   See the event log for details.'});
            app.showError('Download Report', ME);
        end

        function onMissingFileRegenerate(obj, app, reportId)
            Logger.warn('ReportsViewModel', ...
                'Report file missing on server (id=%s) — offering regenerate', ...
                reportId);
            app.setStatus(app.ReportStatusArea, { ...
                [char(9888) ' Server file missing'], ...
                sprintf('   id  %s', reportId), ...
                '   /tmp/qdash_reports was cleared by an api restart.', ...
                '   Click Re-generate in the prompt to refresh it.'});
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
                [char(10003) ' Shared'], ...
                sprintf('   Sent to %s.', email), ...
                '   Recipient will receive a download link.'});
            app.logEvent('API', sprintf('Report shared with %s', email));
        end

        function onShareError(~, app, email, ME)
            app.hideLoading();
            app.setStatus(app.ReportStatusArea, { ...
                [char(10007) ' Share failed'], ...
                sprintf('   Recipient: %s', email), ...
                ['   ' char(ME.message)]});
            app.showError('Share Report', ME);
        end

        % ── List load continuation ────────────────────────────────────
        function onPageLoaded(obj, app, data, page, hideOverlay)
            if hideOverlay; app.hideLoading(); end
            if ~ReportsViewModel.tableValid(app); return; end
            items = JsonHelper.extractList(data, 'reports');
            if isempty(items); items = JsonHelper.asList(data); end
            % Normalize to a cell array of structs.
            pageItems = {};
            for i = 1:numel(items)
                if iscell(items)
                    pageItems{end+1} = items{i}; %#ok<AGROW>
                else
                    pageItems{end+1} = items(i); %#ok<AGROW>
                end
            end
            obj.LastPageItemCount = numel(pageItems);
            % Merge into the cumulative cache (de-duped by report_id).
            obj.mergeIntoCache(app, pageItems);
            app.ReportsCurrentPage = page;
            obj.updatePagerControls(app);
            obj.paintKpis(app, app.ReportsCachedItems);
            % Repaint the table to show only the current page's items
            % (filtered by the current search query).
            q = char(app.ReportsSearchField.Value);
            if isempty(strtrim(q))
                obj.paintTable(app, pageItems);
            else
                obj.applyFilter(app, q);
            end
        end

        function onListLoadError(~, app, ME, hideOverlay)
            if hideOverlay; app.hideLoading(); end
            Logger.warn('ReportsViewModel', ...
                'listReports failed: %s', ME.message);
            app.setStatus(app.ReportStatusArea, { ...
                [char(10007) ' Failed to load reports'], ...
                ['   ' char(ME.message)], ...
                '   Click the refresh button to try again.'});
        end

        % ── Cache + render helpers ────────────────────────────────────
        function applyFilter(obj, app, query)
            % When a search query is active, search filters across the
            % cumulative cache (all loaded pages). When empty, the
            % active page determines what shows — page navigation
            % takes over and the most recent fetch is what's displayed.
            cache = app.ReportsCachedItems;
            if ~iscell(cache); cache = {}; end
            q = lower(strtrim(char(query)));
            if isempty(q)
                % Show *only* current page from cumulative cache. The
                % cumulative cache may contain rows from other pages
                % the user has visited; filter to current-page IDs.
                obj.repaintCurrentPage(app);
                return;
            end
            keep = true(1, numel(cache));
            for i = 1:numel(cache)
                title = lower(char(JsonHelper.pick(cache{i}, {'title'}, '')));
                fmt   = lower(char(JsonHelper.pick(cache{i}, {'format'}, '')));
                if isempty(strfind(title, q)) && isempty(strfind(fmt, q))
                    keep(i) = false;
                end
            end
            obj.paintTable(app, cache(keep));
        end

        function repaintCurrentPage(obj, app)
            % Best-effort: re-fetch the current page (debounced — if
            % the search clears via `loadReportsList`, this fires
            % naturally). For the no-overlay path on search clear we
            % just repaint the cache subset whose page we know.
            % Simplest correct behaviour: leave the table as the most
            % recent page paint (already in place).
            if isempty(app.ReportsTable.Data); return; end
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

        function updatePagerControls(obj, app)
            try
                app.ReportsPageIndicator.Text = sprintf('Page %d · %d items', ...
                    app.ReportsCurrentPage, obj.LastPageItemCount);
            catch
            end
            try
                if app.ReportsCurrentPage > 1
                    app.ReportsPrevBtn.Enable = 'on';
                else
                    app.ReportsPrevBtn.Enable = 'off';
                end
            catch
            end
            try
                % Heuristic: if the page filled to page-size, assume
                % there's at least one more page available.
                if obj.LastPageItemCount >= app.ReportsPageSize
                    app.ReportsNextBtn.Enable = 'on';
                else
                    app.ReportsNextBtn.Enable = 'off';
                end
            catch
            end
        end

        function mergeIntoCache(~, app, pageItems)
            % De-dupe by report_id; new pageItems always win (replace
            % older snapshots with the same id).
            cache = app.ReportsCachedItems;
            if ~iscell(cache); cache = {}; end
            newIds = cell(1, numel(pageItems));
            for i = 1:numel(pageItems)
                newIds{i} = char(JsonHelper.pick(pageItems{i}, {'report_id','id'}, ''));
            end
            keep = true(1, numel(cache));
            for i = 1:numel(cache)
                cid = char(JsonHelper.pick(cache{i}, {'report_id','id'}, ''));
                if any(strcmp(newIds, cid)); keep(i) = false; end
            end
            cache = cache(keep);
            app.ReportsCachedItems = [pageItems, cache];
        end

        function upsertCachedItem(~, app, newMeta)
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

        function seedReportTitle(app)
            % Pre-seed app.ReportTitleField with a sensible default
            % derived from the current run context. Format:
            %   "<circuit> on <backend> — <YYYY-MM-DD>"
            % Falls back to a date-only template when no run context
            % is available. Skipped when the field already has
            % non-whitespace content so existing operator typing is
            % preserved across screen visits.
            try
                if ~isprop(app, 'ReportTitleField') ...
                        || isempty(app.ReportTitleField) ...
                        || ~isvalid(app.ReportTitleField)
                    return;
                end
                cur = char(app.ReportTitleField.Value);
                if ~isempty(strtrim(cur)); return; end

                circuit = '';
                backend = '';
                try; circuit = strtrim(char(app.State.selectedCircuitName)); catch; end
                try; backend = strtrim(char(app.State.selectedBackend));    catch; end
                today = char(datetime('now', 'Format', 'yyyy-MM-dd'));

                if ~isempty(circuit) && ~isempty(backend)
                    seed = sprintf('%s on %s %c %s', ...
                        circuit, backend, char(8212), today);
                elseif ~isempty(circuit)
                    seed = sprintf('%s %c %s', circuit, char(8212), today);
                else
                    seed = sprintf('Quantum Run Report %c %s', ...
                        char(8212), today);
                end
                app.ReportTitleField.Value = seed;
            catch ME
                Logger.debug('ReportsViewModel', ...
                    'seedReportTitle: %s', ME.message);
            end
        end

        function rid = currentReportId(app)
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
