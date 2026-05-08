classdef DashboardViewModel < handle
    % DashboardViewModel  Callback handlers for the Dashboard screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
        ActivityPageSkip double = 0
        ActivityPageLimit double = 15
        % Phase 5: cached job-event rows built from the same listJobs
        % response that feeds the Activity Trend bar chart. paintLocalActivity
        % merges these with the in-memory UI ActivityLog so the Recent
        % Activity table shows a unified history (UI events + job
        % submissions/completions/failures), sorted by timestamp DESC.
        LastJobEvents = {};   % {n×3} cell: {timestamp, action, status}
        LastJobIds    = {};   % {n×1} cell: parallel job_id per LastJobEvents row
    end
    methods
        function obj = DashboardViewModel(app)
            obj.App = app;
        end

        function onRefreshDashboard(obj, silent)
            % Phase 8: optional `silent` flag. The 30 s auto-refresh
            % tick passes silent=true so the loading overlay doesn't
            % flash every 30 seconds — that flicker was reported as
            % distracting. Manual Refresh button click stays silent=
            % false so the user gets feedback for their explicit
            % action. Data fetches and panel repaints fire either way.
            if nargin < 2 || isempty(silent); silent = false; end
            app = obj.App;
            app.logEvent('UI', sprintf('Dashboard refresh triggered (silent=%d) — auth: %s  project: %s', ...
                double(silent), string(app.State.isAuthenticated()), app.State.currentProjectId));
            % Phase 3: keep the toolbar's project switcher populated.
            % Async fire-and-forget — independent of the dashboard fetch.
            obj.populateProjectsDropdown();
            % Phase 4: arm the 30 s live auto-refresh timer. Idempotent —
            % the next tick checks visibility and self-terminates when
            % the user navigates away. Doesn't hammer when the user
            % stays put on Dashboard.
            obj.startAutoRefresh(30);
            if app.State.isAuthenticated() && app.State.hasProject()
                pid = app.State.currentProjectId;
                app.logEvent('API', sprintf('GET /api/projects/%s/dashboard', pid));
                if ~silent
                    app.showLoading(Labels.get('loading_dashboard', 'Loading dashboard...'));
                end
                svc   = app.ProjectSvc;
                token = app.State.authToken;
                AsyncRunner.run( ...
                    @() svc.getDashboard(pid, token), ...
                    @(data) obj.onDashboardComplete(app, pid, data, silent), ...
                    @(ME)   obj.onDashboardError(app, pid, ME, silent));
                return;
            end
            app.logEvent('UI', 'Dashboard falling back to session state summary');
            obj.refreshDashboardFromState();
            obj.refreshActivityTable();
        end

        function onDashboardComplete(obj, app, pid, data, silent)
            % Phase 8: silent param threads through the no-overlay path.
            if nargin < 5 || isempty(silent); silent = false; end
            obj.applyDashboardData(data);
            app.logEvent('API', sprintf('Dashboard data loaded for project: %s', pid));
            obj.LastRefresh = tic;
            if ~silent
                app.hideLoading();
            end
        end

        function onDashboardError(obj, app, pid, ME, silent)
            if nargin < 5 || isempty(silent); silent = false; end
            if ~silent
                app.hideLoading();
            end
            app.logEvent('ERROR', sprintf('Dashboard fetch failed (project: %s): %s', pid, ME.message));
            app.showError('Dashboard Refresh', ME);
            obj.refreshDashboardFromState();
            obj.refreshActivityTable();
        end

        function onActivityNextPage(obj)
            obj.ActivityPageSkip = obj.ActivityPageSkip + obj.ActivityPageLimit;
            obj.refreshActivityTable();
        end

        function onActivityPrevPage(obj)
            obj.ActivityPageSkip = max(0, obj.ActivityPageSkip - obj.ActivityPageLimit);
            obj.refreshActivityTable();
        end

        function refreshActivityTable(obj)
            app = obj.App;
            if isempty(app.DashActivityTable) || ~isvalid(app.DashActivityTable)
                return;
            end
            % Paint local ActivityLog immediately for instant feedback,
            % then async-fetch the server-side log to overwrite when ready.
            obj.paintLocalActivity(app);
            if app.State.isAuthenticated() && app.State.hasProject()
                pid   = app.State.currentProjectId;
                skip  = obj.ActivityPageSkip;
                limit = obj.ActivityPageLimit;
                svc   = app.ProjectSvc;
                token = app.State.authToken;
                AsyncRunner.run( ...
                    @() svc.getActivities(pid, skip, limit, token), ...
                    @(data) obj.onActivitiesComplete(app, data), ...
                    @(~)   [] );  % silent failure — local fallback already showing
            end
        end

        function onActivitiesComplete(obj, app, data)
            if ~(isstruct(data) && isfield(data, 'items')); return; end
            items = JsonHelper.extractList(data, 'items');
            totalRows = 0;
            if isfield(data, 'total'); totalRows = data.total; end
            n = numel(items);
            rows = cell(n, 3);
            for i = 1:n
                rows{i,1} = char(JsonHelper.pick(items(i), {'timestamp','time'}));
                rows{i,2} = char(JsonHelper.pick(items(i), {'action','description'}));
                rows{i,3} = char(JsonHelper.pick(items(i), {'status'}));
            end
            if isvalid(app.DashActivityTable)
                app.DashActivityTable.Data = rows;
            end
            obj.updateActivityPageLabel(totalRows);
        end

        function paintLocalActivity(obj, app)
            % Phase 5: merge UI activity log + cached job events so the
            % feed shows a unified history. Rows are sorted by
            % timestamp DESC (newest first); per-row metadata
            % (type=ui|job, optional job_id) is stored in
            % DashActivityTable.UserData so the right-click context
            % menu callbacks can navigate or copy correctly.
            uiRows  = app.State.ActivityLog;
            jobRows = obj.LastJobEvents;
            jobIds  = obj.LastJobIds;
            if isempty(uiRows);  uiRows  = cell(0, 3); end
            if isempty(jobRows); jobRows = cell(0, 3); end
            % Tag each source's rows with its origin type and (for
            % jobs) the matching job_id; UI rows have empty job_ids.
            mUi  = size(uiRows, 1);
            mJob = size(jobRows, 1);
            allRows = cell(mUi + mJob, 3);
            allTypes = cell(mUi + mJob, 1);
            allJobIds = cell(mUi + mJob, 1);
            for r = 1:mUi
                allRows(r, :) = uiRows(r, :);
                allTypes{r}   = 'ui';
                allJobIds{r}  = '';
            end
            for r = 1:mJob
                allRows(mUi + r, :) = jobRows(r, :);
                allTypes{mUi + r}   = 'job';
                if r <= numel(jobIds)
                    allJobIds{mUi + r} = jobIds{r};
                else
                    allJobIds{mUi + r} = '';
                end
            end
            % Sort by timestamp DESC (string sort works for ISO 8601).
            tsCol = string(allRows(:, 1));
            [~, order] = sort(tsCol, 'descend');
            allRows   = allRows(order, :);
            allTypes  = allTypes(order);
            allJobIds = allJobIds(order);

            totalRows = size(allRows, 1);
            if totalRows == 0
                app.DashActivityTable.Selection = [];
                app.DashActivityTable.Data     = {};
                app.DashActivityTable.UserData = struct('types', {{}}, 'jobIds', {{}});
                obj.updateActivityPageLabel(0);
                return;
            end
            if obj.ActivityPageSkip >= totalRows
                obj.ActivityPageSkip = max(0, totalRows - obj.ActivityPageLimit);
            end
            startIdx = obj.ActivityPageSkip + 1;
            endIdx   = min(obj.ActivityPageSkip + obj.ActivityPageLimit, totalRows);
            % Reset selection before swapping data so a stale row index
            % from the previous page doesn't point to the wrong job.
            app.DashActivityTable.Selection = [];
            app.DashActivityTable.Data      = allRows(startIdx:endIdx, :);
            app.DashActivityTable.UserData  = struct( ...
                'types',  {allTypes(startIdx:endIdx)}, ...
                'jobIds', {allJobIds(startIdx:endIdx)});
            obj.updateActivityPageLabel(totalRows);
            % Phase 6: color-coded status badges on the Status column.
            obj.applyStatusBadges(app);
        end

        function applyStatusBadges(~, app)
            % Phase 6: per-cell uistyle on the Status column of the
            % Recent Activity table — green Completed / red Failed /
            % amber Running / blue Queued / gray Cancelled / pale
            % Success / pale Info. Wipes prior styles first so paging
            % through the feed doesn't accumulate stale colors on
            % cells whose underlying status has changed.
            tbl = app.DashActivityTable;
            if isempty(tbl) || ~isvalid(tbl); return; end
            data = tbl.Data;
            if isempty(data); return; end
            try
                removeStyle(tbl);
            catch
            end
            for r = 1:size(data, 1)
                st = lower(strtrim(char(string(data{r, 3}))));
                bg = []; fg = [];
                switch st
                    case {'completed','done','success'}
                        bg = [0.20 0.65 0.40]; fg = [1 1 1];
                    case {'failed','error'}
                        bg = [0.80 0.25 0.25]; fg = [1 1 1];
                    case {'cancelled','canceled'}
                        bg = [0.45 0.45 0.45]; fg = [1 1 1];
                    case {'queued','pending'}
                        bg = [0.30 0.50 0.85]; fg = [1 1 1];
                    case {'running','initializing'}
                        bg = [0.90 0.65 0.20]; fg = [0.10 0.10 0.10];
                    case {'info','—',''}
                        % no badge — leave default styling
                end
                if ~isempty(bg)
                    try
                        s = uistyle('BackgroundColor', bg, ...
                                    'FontColor',       fg, ...
                                    'FontWeight',      'bold');
                        addStyle(tbl, s, 'cell', [r 3]);
                    catch ME
                        Logger.debug('DashboardViewModel', ...
                            'applyStatusBadges row %d: %s', r, ME.message);
                    end
                end
            end
        end

        % ── Phase 5: right-click context-menu actions ───────────────────
        function onActivityViewJob(obj)
            app = obj.App;
            [type, jobId, ts] = DashboardViewModel.readSelectedRow( ...
                app.DashActivityTable);  %#ok<ASGLU>
            if ~strcmp(type, 'job') || isempty(jobId); return; end
            app.State.selectedJobId = string(jobId);
            app.logEvent('UI', sprintf('Activity feed → Jobs (job: %s)', jobId));
            app.onSelectSection('Jobs');
        end

        function onActivityOpenResults(obj)
            app = obj.App;
            [type, jobId, ts] = DashboardViewModel.readSelectedRow( ...
                app.DashActivityTable);  %#ok<ASGLU>
            if ~strcmp(type, 'job') || isempty(jobId); return; end
            app.State.selectedJobId = string(jobId);
            app.logEvent('UI', sprintf('Activity feed → Results (job: %s)', jobId));
            app.onSelectSection('Results');
        end

        function onActivityCopyId(obj)
            app = obj.App;
            [type, jobId, ts] = DashboardViewModel.readSelectedRow( ...
                app.DashActivityTable);
            if strcmp(type, 'job') && ~isempty(jobId)
                payload = char(jobId);
                msg = sprintf('Copied job_id: %s', payload);
            else
                payload = char(string(ts));
                msg = sprintf('Copied timestamp: %s', payload);
            end
            try
                clipboard('copy', payload);
                app.logEvent('UI', msg);
            catch ME
                Logger.debug('DashboardViewModel', ...
                    'onActivityCopyId clipboard: %s', ME.message);
            end
        end
    end

    methods (Static, Access = private)
        function [rows, jobIds] = buildJobEventRows(items)
            % Phase 5: turn a listJobs response into Recent Activity
            % rows. One row per job, current status. Returned in the
            % same {timestamp, action, status} shape as ActivityLog
            % so paintLocalActivity can simply concatenate.
            n = numel(items);
            rows   = cell(n, 3);
            jobIds = cell(n, 1);
            k = 0;
            for i = 1:n
                if iscell(items); it = items{i}; else; it = items(i); end
                ts = char(JsonHelper.pick(it, ...
                    {'submitted_at','created_at','timestamp'}, ''));
                if isempty(ts); continue; end
                jid = char(JsonHelper.pick(it, ...
                    {'job_record_id','job_id','id'}, ''));
                cn  = char(JsonHelper.pick(it, ...
                    {'circuit_name','circuit'}, '?'));
                bn  = char(JsonHelper.pick(it, ...
                    {'backend_name','backend'}, '?'));
                st  = upper(char(JsonHelper.pick(it, {'status'}, 'UNKNOWN')));
                action = sprintf('Job %s on %s', cn, bn);
                statusText = DashboardViewModel.jobStatusLabel(st);
                k = k + 1;
                rows(k, :)  = {ts, action, statusText};
                jobIds{k}   = jid;
            end
            rows   = rows(1:k, :);
            jobIds = jobIds(1:k);
        end

        function s = jobStatusLabel(rawStatus)
            % Map raw IBM job status strings to short Activity-feed
            % labels. Falls through with the upper-cased raw value
            % when the status is unfamiliar — better than dropping it.
            switch lower(strtrim(char(string(rawStatus))))
                case 'completed';     s = 'Completed';
                case 'done';          s = 'Completed';
                case 'success';       s = 'Completed';
                case 'failed';        s = 'Failed';
                case 'cancelled';     s = 'Cancelled';
                case 'canceled';      s = 'Cancelled';
                case 'queued';        s = 'Queued';
                case 'running';       s = 'Running';
                case 'initializing';  s = 'Initializing';
                otherwise;            s = upper(char(string(rawStatus)));
            end
        end

        function [type, jobId, ts] = readSelectedRow(tbl)
            % Phase 5 helper: pull row metadata for the currently-
            % selected row in DashActivityTable. Returns ('','','')
            % if no selection or the metadata sidecar is missing.
            type = ''; jobId = ''; ts = '';
            try
                sel = tbl.Selection;
                if isempty(sel); return; end
                row = sel(1);
                meta = tbl.UserData;
                if ~isstruct(meta) || ~isfield(meta, 'types'); return; end
                if row > numel(meta.types); return; end
                type  = char(string(meta.types{row}));
                jobId = char(string(meta.jobIds{row}));
                d = tbl.Data;
                if ~isempty(d) && row <= size(d, 1)
                    ts = char(string(d{row, 1}));
                end
            catch
            end
        end

        function [color, dotChar] = statusVisuals(status)
            % Phase 2 helper: map a backend status string to a coloured
            % dot for the Backend Health panel. Mirrors the colour
            % palette used elsewhere in the app for status pills.
            s = upper(strtrim(char(string(status))));
            dotChar = char(9679);  % ● filled circle by default
            switch s
                case {'ONLINE','READY','OPERATIONAL','ACTIVE'}
                    color = Theme.COLOR_SUCCESS;
                case {'MAINTENANCE','PAUSED','DEGRADED'}
                    color = Theme.COLOR_AMBER;
                case {'OFFLINE','RETIRED','UNAVAILABLE','ERROR'}
                    color = Theme.COLOR_DANGER;
                otherwise
                    color = Theme.COLOR_MUTED;
            end
        end

        function s = fmtIntOrDash(n)
            % Phase 1 readiness KPI formatter. NaN/empty → em-dash.
            if isempty(n) || ~isfinite(n) || n <= 0
                s = char(8212);
            else
                s = sprintf('%d', round(n));
            end
        end

        function s = fmtFidelity(f, std)
            if isempty(f) || ~isfinite(f); s = char(8212); return; end
            if isfinite(std) && std > 0
                s = sprintf('%.3f ±%.3f', f, std);
            else
                s = sprintf('%.3f', f);
            end
        end

        function s = fmtPctOrDash(v)
            if isempty(v) || ~isfinite(v); s = char(8212); return; end
            if v <= 1; v = v * 100; end
            s = sprintf('%.1f%%', v);
        end

        function s = fmtTextOrDash(t)
            t = strtrim(char(string(t)));
            if isempty(t); s = char(8212); else; s = t; end
        end

        function rgb = toRGB(c)
            % Phase 9 helper: normalize a Theme color (already an RGB
            % triplet in this codebase) into a guaranteed 1x3 double
            % so bar() CData accepts it. If anything weird gets passed,
            % fall back to the primary brand color.
            try
                if isnumeric(c) && numel(c) == 3
                    rgb = double(c(:)');
                    return;
                end
            catch
            end
            rgb = [0.49 0.36 0.85];   % fallback ~ Theme.COLOR_PRIMARY
        end

        function s = fmtDelta(today, yesterday)
            % Phase 7 helper: format a today-vs-yesterday delta badge.
            %   ▲ +N% vs yesterday   when today > yesterday
            %   ▼ -N% vs yesterday   when today < yesterday
            %   · flat               when today == yesterday > 0
            %   · new today          when today > 0 but yesterday = 0
            %   ''                   when today == yesterday == 0
            if today == 0 && yesterday == 0
                s = '';
                return;
            end
            if yesterday == 0
                s = [char(9650) ' new today'];
                return;
            end
            if today == yesterday
                s = [char(183) ' flat vs yesterday'];
                return;
            end
            pct = round(100 * (today - yesterday) / yesterday);
            if pct >= 0
                s = sprintf('%c +%d%% vs yesterday', char(9650), pct);
            else
                s = sprintf('%c %d%% vs yesterday', char(9660), pct);
            end
        end
    end

    methods (Access = private)
        function applyDashboardData(obj, data)
            app = obj.App;
            try
                % Prefer stored project name over API ID fields
                if strlength(app.State.currentProjectName) > 0
                    proj = char(app.State.currentProjectName);
                else
                    proj = char(JsonHelper.pick(data, {'project_name','project.name','active_project','project_id'}));
                end
                circ   = char(JsonHelper.pick(data, {'circuit_name','circuit.name','circuit_version'}));
                bknd   = char(JsonHelper.pick(data, {'backend_name','selected_backend','target_backend'}));
                stage  = char(JsonHelper.pick(data, {'pipeline_stage','stage'}));
                if ~isempty(app.DashKpiLabels) && numel(app.DashKpiLabels) >= 4
                    vals = {proj, circ, bknd, stage};
                    for i = 1:4
                        if ~isempty(vals{i}) && isvalid(app.DashKpiLabels{i})
                            app.DashKpiLabels{i}.Text = vals{i};
                        end
                    end
                end
                % Phase 1 refactor: populate the workflow stepper, run
                % readiness KPI grid, and activity trend chart instead
                % of the legacy multi-line summary text + raw JSON tree.
                obj.paintWorkflowStepper(stage);
                obj.paintRunReadiness(data);
                obj.paintActivityTrend();
                obj.paintBackendHealth();
                obj.paintNextStep(stage);
                obj.paintEmptyState(data);
                obj.paintGreeting(data);   % Phase 9
                % Legacy summary text fallback — only updated if the
                % screen still has the area (kept for back-compat with
                % any future variant that re-introduces it).
                summary = char(JsonHelper.pick(data, {'summary','executive_summary'}));
                if ~isempty(summary) && ~isempty(app.DashboardSummaryArea) ...
                        && isvalid(app.DashboardSummaryArea)
                    app.setStatus(app.DashboardSummaryArea, {summary});
                end

                % Refresh activity table from local log (pagination-aware)
                obj.ActivityPageSkip = 0;
                obj.refreshActivityTable();
            catch ME
                Logger.warn('DashboardViewModel', 'applyDashboardData failed: %s', ME.message);
            end
        end

        % ── Phase 1 refactor: stepper + readiness + activity trend ──────
        function paintWorkflowStepper(obj, currentStage)
            % Paint the 8-stage horizontal stepper. Stages strictly
            % before the current one are marked completed (✓), the
            % current stage is active (●), and later stages are
            % upcoming (◯). Stage IDs are matched case-insensitively
            % against the dashboard payload's pipeline_stage value.
            app = obj.App;
            if isempty(app.DashStepperDots) || numel(app.DashStepperDots) < 8
                return;
            end
            stages = {'welcome','upload','analysis','backend', ...
                      'benchmark','predict','job','results'};
            curIdx = find(strcmpi(stages, char(currentStage)), 1);
            if isempty(curIdx); curIdx = 1; end
            for i = 1:8
                dot = app.DashStepperDots{i};
                if isempty(dot) || ~isvalid(dot); continue; end
                if i < curIdx
                    dot.Text      = char(10003);   % ✓ completed
                    dot.FontColor = Theme.COLOR_SUCCESS;
                elseif i == curIdx
                    dot.Text      = char(9679);    % ● active
                    dot.FontColor = Theme.COLOR_PRIMARY;
                else
                    dot.Text      = char(9675);    % ◯ upcoming
                    dot.FontColor = Theme.COLOR_MUTED;
                end
                if ~isempty(app.DashStepperNames) && i <= numel(app.DashStepperNames)
                    nm = app.DashStepperNames{i};
                    if ~isempty(nm) && isvalid(nm)
                        if i == curIdx
                            nm.FontColor  = Theme.COLOR_HEADING;
                            nm.FontWeight = 'bold';
                        else
                            nm.FontColor  = Theme.COLOR_LABEL;
                            nm.FontWeight = 'normal';
                        end
                    end
                end
            end
        end

        function paintRunReadiness(obj, data)
            % Populate the 4-cell Run Readiness KPI grid. Reads from
            % the dashboard payload with sensible fallbacks (em-dash)
            % when fields are missing — typical for a freshly-created
            % project that hasn't run a circuit yet.
            app = obj.App;
            if isempty(app.DashReadinessLabels) || numel(app.DashReadinessLabels) < 4
                return;
            end
            % Qubit count — try several likely fields on the payload.
            nq = JsonHelper.pickNumeric(data, 'circuit.num_qubits', NaN);
            if ~isfinite(nq); nq = JsonHelper.pickNumeric(data, 'circuit_qubits', NaN); end
            if ~isfinite(nq); nq = JsonHelper.pickNumeric(data, 'num_qubits', NaN); end
            % Predicted fidelity (with optional ± std)
            f  = JsonHelper.pickNumeric(data, 'predicted_fidelity', NaN);
            fs = JsonHelper.pickNumeric(data, 'fidelity_std', NaN);
            % Similarity score (QTAUBench top match)
            ss = JsonHelper.pickNumeric(data, 'similarity_score', NaN);
            if ~isfinite(ss); ss = JsonHelper.pickNumeric(data, 'top_similarity', NaN); end
            % Expected queue duration
            q  = char(JsonHelper.pick(data, {'expected_queue_duration','queue_eta','queue_status'}));

            vals = { ...
                DashboardViewModel.fmtIntOrDash(nq), ...
                DashboardViewModel.fmtFidelity(f, fs), ...
                DashboardViewModel.fmtPctOrDash(ss), ...
                DashboardViewModel.fmtTextOrDash(q)};
            % Phase 9: hint each card's empty state with the next
            % concrete action so a fresh project doesn't show 4 dashes.
            % Cleared once a real value lands.
            emDash = char(8212);
            hints = { ...
                'Upload a circuit', ...
                'Run prediction', ...
                'Analyze the circuit', ...
                'Pick a backend'};
            for i = 1:4
                lbl = app.DashReadinessLabels{i};
                if ~isempty(lbl) && isvalid(lbl)
                    lbl.Text = vals{i};
                end
                if ~isempty(app.DashReadinessHints) ...
                        && i <= numel(app.DashReadinessHints) ...
                        && ~isempty(app.DashReadinessHints{i}) ...
                        && isvalid(app.DashReadinessHints{i})
                    if strcmp(vals{i}, emDash)
                        app.DashReadinessHints{i}.Text = hints{i};
                    else
                        app.DashReadinessHints{i}.Text = '';
                    end
                end
            end
        end

        function paintActivityTrend(obj)
            % Phase 2: bar chart of REAL job submissions per day for the
            % last 7 days, fetched from JobService.listJobs. Replaces
            % the Phase 1 ActivityLog-driven version which only showed
            % UI-side actions (logins / nav clicks). The async fetch
            % runs in parallel with the dashboard payload load; failure
            % falls back to an all-zero chart with a debug log.
            app = obj.App;
            if isempty(app.DashActivityAxes) || ~isvalid(app.DashActivityAxes)
                return;
            end
            if ~app.State.isAuthenticated() || ~app.State.hasProject()
                return;
            end
            jobSvc = app.JobSvc;
            token  = app.State.authToken;
            AsyncRunner.run( ...
                @() jobSvc.listJobs(token, 0, 100), ...
                @(data) obj.onJobsForTrend(app, data), ...
                @(ME)   Logger.debug('DashboardViewModel', ...
                    'paintActivityTrend listJobs: %s', ME.message));
        end

        function onJobsForTrend(obj, app, data)
            if isempty(app.DashActivityAxes) || ~isvalid(app.DashActivityAxes)
                return;
            end
            ax = app.DashActivityAxes;
            cla(ax);
            try
                items = JsonHelper.extractListSafe(data, 'jobs');
                today  = floor(datenum(datetime('now')));
                days   = today - 6 : today;
                counts = zeros(1, 7);
                % Phase 4: also accumulate today-only stats for the
                % subline label inside the panel (jobs submitted today,
                % failed jobs today, total compute hours today).
                jobsToday   = 0;
                failedToday = 0;
                computeSecToday = 0;
                % Phase 7: yesterday counters for the delta indicator.
                jobsYesterday = 0;
                for i = 1:numel(items)
                    if iscell(items); it = items{i}; else; it = items(i); end
                    ts = char(JsonHelper.pick(it, ...
                        {'submitted_at','created_at','timestamp'}, ''));
                    d = NaN;
                    try
                        if ~isempty(ts)
                            d = floor(datenum(datetime(ts, ...
                                'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS', ...
                                'TimeZone', 'local')));
                        end
                    catch
                        try; d = floor(datenum(ts)); catch; end
                    end
                    if isfinite(d)
                        ix = find(days == d, 1);
                        if ~isempty(ix); counts(ix) = counts(ix) + 1; end
                        if d == today - 1
                            jobsYesterday = jobsYesterday + 1;
                        end
                        if d == today
                            jobsToday = jobsToday + 1;
                            stat = lower(char(JsonHelper.pick(it, {'status'}, '')));
                            if strcmp(stat, 'failed'); failedToday = failedToday + 1; end
                            % Compute time = completed_at - submitted_at
                            % when both timestamps exist on a finished
                            % job. In-flight jobs (no completed_at)
                            % contribute nothing — correct behaviour.
                            ce = char(JsonHelper.pick(it, ...
                                {'completed_at','finished_at'}, ''));
                            if ~isempty(ce) && ~isempty(ts)
                                try
                                    sd = datetime(ts, ...
                                        'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSSSS', ...
                                        'TimeZone','local');
                                    ed = datetime(ce, ...
                                        'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSSSS', ...
                                        'TimeZone','local');
                                    secs = seconds(ed - sd);
                                    if isfinite(secs) && secs > 0
                                        computeSecToday = computeSecToday + secs;
                                    end
                                catch
                                end
                            end
                        end
                    end
                end
                %  Phase 9: per-bar coloring — "today" (last bar)
                %  rendered in COLOR_PRIMARY (full saturation), other
                %  six days rendered in a muted tone so the eye lands
                %  on today first. CData is an Nx3 RGB matrix; we set
                %  FaceColor 'flat' to enable per-bar coloring.
                primaryRGB = DashboardViewModel.toRGB(Theme.COLOR_PRIMARY);
                mutedRGB   = primaryRGB * 0.45 + [0.55 0.55 0.55] * 0.55;
                cdata = repmat(mutedRGB, 7, 1);
                cdata(7, :) = primaryRGB;   % today is index 7
                b = bar(ax, 1:7, counts, ...
                    'FaceColor', 'flat', ...
                    'EdgeColor', 'none', ...
                    'BarWidth', 0.65);
                b.CData = cdata;
                app.DashActivityBars = b;
                ax.XLim = [0.5 7.5];
                ax.XTick = 1:7;
                xLbls = cell(1, 7);
                for i = 1:7
                    xLbls{i} = datestr(days(i), 'ddd');
                end
                ax.XTickLabel = xLbls;
                ax.YLim = [0 max(1, max(counts) * 1.2)];
                grid(ax, 'on');
                ax.GridLineStyle = ':';
                ax.GridAlpha = 0.35;
                ax.Title.String  = '';
                ax.XLabel.String = '';
                ax.YLabel.String = 'Jobs';
                % Phase 4 + 7: write today's stats into the subline,
                % suffixed with the today-vs-yesterday delta indicator
                % (▲ +N% / ▼ -N% / · flat / · new today).
                if ~isempty(app.DashStatsSubline) && isvalid(app.DashStatsSubline)
                    deltaTxt = DashboardViewModel.fmtDelta(jobsToday, jobsYesterday);
                    app.DashStatsSubline.Text = sprintf( ...
                        'Today: %d jobs  ·  %.1f h compute  ·  %d failed   %s', ...
                        jobsToday, computeSecToday / 3600, failedToday, deltaTxt);
                end
                % Phase 5: build job-event rows from the same response
                % and merge them into the activity feed. One row per
                % job, current status, with parallel job_ids cached so
                % the right-click context menu can navigate or copy.
                [obj.LastJobEvents, obj.LastJobIds] = ...
                    DashboardViewModel.buildJobEventRows(items);
                obj.refreshActivityTable();
            catch ME
                Logger.debug('DashboardViewModel', ...
                    'onJobsForTrend: %s', ME.message);
            end
        end

        % ── Phase 4: auto-refresh timer ────────────────────────────────
        function startAutoRefresh(obj, periodSec)
            % Phase 4: kick a periodic timer that re-fetches the
            % dashboard while the operator is on the screen. Mirrors
            % the JobsViewModel pattern (5s there, 30s here — Dashboard
            % data changes more slowly). Each tick checks whether the
            % Dashboard panel is still visible and self-terminates if
            % the user has navigated away. Idempotent — calling twice
            % stops the prior timer first so we never stack timers.
            obj.stopAutoRefresh();
            try
                t = timer( ...
                    'ExecutionMode', 'fixedSpacing', ...
                    'Period',        max(5, periodSec), ...
                    'StartDelay',    max(5, periodSec), ...
                    'BusyMode',      'drop', ...
                    'Name',          'DashAutoRefresh', ...
                    'TimerFcn',      @(src,~) obj.onAutoRefreshTick(src));
                obj.App.DashAutoRefreshTimer = t;
                start(t);
            catch ME
                Logger.debug('DashboardViewModel', ...
                    'startAutoRefresh: %s', ME.message);
            end
        end

        function stopAutoRefresh(obj)
            try
                t = obj.App.DashAutoRefreshTimer;
                if ~isempty(t) && isvalid(t)
                    stop(t); delete(t);
                end
            catch
            end
            try; obj.App.DashAutoRefreshTimer = []; catch; end
        end

        function onAutoRefreshTick(obj, timerObj)
            % Self-terminate if the Dashboard panel is no longer the
            % visible section. Otherwise silently re-fire the refresh.
            try
                app = obj.App;
                visible = false;
                if isfield(app.SectionPanels, 'Dashboard') && ...
                        ~isempty(app.SectionPanels.Dashboard) && ...
                        isvalid(app.SectionPanels.Dashboard)
                    visible = strcmp(app.SectionPanels.Dashboard.Visible, 'on');
                end
                if ~visible
                    try; stop(timerObj); delete(timerObj); catch; end
                    try; obj.App.DashAutoRefreshTimer = []; catch; end
                    return;
                end
                % Phase 8: silent=true so the user-visible loading
                % overlay doesn't flash every 30 s during background
                % refresh. The data still updates; the user just
                % doesn't see the spinner-flicker.
                obj.onRefreshDashboard(true);
            catch ME
                Logger.debug('DashboardViewModel', ...
                    'onAutoRefreshTick: %s', ME.message);
            end
        end

        function paintBackendHealth(obj)
            % Phase 2: live backend status panel. Reuses
            % BackendsViewModel.fetchBackends so the data is identical
            % to what the Backends tab shows — including the qubit
            % count enrichment. Fires async; the response handler
            % updates the 6 mini-cards via paintBackendHealthCards.
            app = obj.App;
            if isempty(app.DashBackendHealthCards); return; end
            if ~app.State.isAuthenticated(); return; end
            backendSvc = app.BackendSvc;
            circuitSvc = app.CircuitSvc;
            token      = app.State.authToken;
            AsyncRunner.run( ...
                @() BackendsViewModel.fetchBackends(backendSvc, circuitSvc, token, ''), ...
                @(data) obj.onBackendsForHealth(app, data), ...
                @(ME)   Logger.debug('DashboardViewModel', ...
                    'paintBackendHealth fetch: %s', ME.message));
        end

        function onBackendsForHealth(obj, app, data)
            cards = app.DashBackendHealthCards;
            if isempty(cards); return; end
            items = JsonHelper.extractListSafe(data, 'backends');
            n = min(numel(items), numel(cards));
            for i = 1:numel(cards)
                c = cards{i};
                if isempty(c) || ~isvalid(c.panel); continue; end
                if i <= n
                    if iscell(items); it = items{i}; else; it = items(i); end
                    bn = char(JsonHelper.pick(it, {'name','backend_name'}));
                    nq = JsonHelper.toDouble(JsonHelper.pick(it, ...
                        {'num_qubits','qubits','n_qubits'}));
                    if isnan(nq); nq = 0; end
                    st = upper(char(JsonHelper.pick(it, ...
                        {'status','operational_status'}, 'UNKNOWN')));
                    [dotColor, dotChar] = DashboardViewModel.statusVisuals(st);
                    c.dotLbl.Text      = dotChar;
                    c.dotLbl.FontColor = dotColor;
                    c.nameLbl.Text     = bn;
                    if nq > 0
                        c.qubitsLbl.Text = sprintf('%dq · %s', int32(nq), st);
                    else
                        c.qubitsLbl.Text = st;
                    end
                else
                    % Empty slot
                    c.dotLbl.Text      = '';
                    c.nameLbl.Text     = char(8212);
                    c.qubitsLbl.Text   = '';
                end
            end
        end

        % ── Phase 3: project switcher + Smart Next-Step CTA ────────────
        function populateProjectsDropdown(obj)
            % Fire-and-forget fetch of /api/projects to populate the
            % toolbar's Project Switcher. Skipped silently when not
            % authenticated. Cached behaviour matches WelcomeViewModel
            % since both tap the same endpoint.
            app = obj.App;
            if isempty(app.DashProjectDropdown) || ~isvalid(app.DashProjectDropdown)
                return;
            end
            if ~app.State.isAuthenticated(); return; end
            projSvc = app.ProjectSvc;
            token   = app.State.authToken;
            AsyncRunner.run( ...
                @() projSvc.listProjects(token), ...
                @(data) obj.onProjectsLoaded(app, data), ...
                @(ME)   Logger.debug('DashboardViewModel', ...
                    'populateProjectsDropdown: %s', ME.message));
        end

        function onProjectsLoaded(obj, app, data)
            if isempty(app.DashProjectDropdown) || ~isvalid(app.DashProjectDropdown)
                return;
            end
            items = JsonHelper.extractListSafe(data, 'projects');
            n = numel(items);
            if n == 0
                app.DashProjectDropdown.Items     = {'(no projects)'};
                app.DashProjectDropdown.ItemsData = {''};
                return;
            end
            names = cell(1, n); ids = cell(1, n);
            for i = 1:n
                if iscell(items); it = items{i}; else; it = items(i); end
                ids{i}   = char(JsonHelper.pick(it, {'project_id','id'}));
                nm       = char(JsonHelper.pick(it, {'name','project_name'}));
                if isempty(nm); nm = ids{i}; end
                names{i} = nm;
            end
            app.DashProjectDropdown.Items     = names;
            app.DashProjectDropdown.ItemsData = ids;
            % Keep the dropdown selection in sync with the active project
            curId = char(app.State.currentProjectId);
            match = find(strcmp(ids, curId), 1);
            if ~isempty(match)
                app.DashProjectDropdown.Value = ids{match};
            else
                app.DashProjectDropdown.Value = ids{1};
            end
        end

        function onProjectChanged(obj, projectId)
            % When the operator picks a different project from the
            % toolbar dropdown, update the global app state and refire
            % the dashboard refresh so every panel repaints with the
            % new project's data. The display name is read back from
            % the dropdown so we don't need a separate lookup.
            app = obj.App;
            if isempty(projectId); return; end
            try
                ids   = app.DashProjectDropdown.ItemsData;
                names = app.DashProjectDropdown.Items;
                k = find(strcmp(ids, char(projectId)), 1);
                projName = '';
                if ~isempty(k); projName = names{k}; end
            catch
                projName = '';
            end
            app.State.currentProjectId   = string(projectId);
            if ~isempty(projName)
                app.State.currentProjectName = string(projName);
            end
            app.logEvent('UI', sprintf('Active project switched to: %s', ...
                char(app.State.currentProjectName)));
            obj.onRefreshDashboard();
        end

        function paintNextStep(obj, stage)
            % Phase 3: pick the action button text + click target based
            % on the active pipeline_stage. The button visually replaces
            % the old "Pipeline Stage" KPI, giving the operator a single
            % adaptive CTA for "what should I do next?" — matches the
            % "Next step" pattern used by IBM Quantum / Azure Quantum.
            app = obj.App;
            if isempty(app.DashNextStepButton) || ~isvalid(app.DashNextStepButton)
                return;
            end
            s = lower(strtrim(char(string(stage))));
            switch s
                case 'welcome'
                    txt = [char(9650) ' ' Labels.get('dashboard_next_step_welcome', 'Upload a circuit')];
                    target = 'Upload';
                case 'upload'
                    txt = [char(8853) ' ' Labels.get('dashboard_next_step_upload', 'Analyze the circuit')];
                    target = 'Analysis';
                case 'analysis'
                    txt = [char(9670) ' ' Labels.get('dashboard_next_step_analysis', 'Pick a backend')];
                    target = 'Backends';
                case 'backend'
                    txt = [char(8646) ' ' Labels.get('dashboard_next_step_backend', 'Configure benchmark')];
                    target = 'Benchmark';
                case 'benchmark'
                    txt = [char(8978) ' ' Labels.get('dashboard_next_step_benchmark', 'Predict fidelity')];
                    target = 'Prediction';
                case 'predict'
                    % Phase 6: navigate to Prediction (not Jobs). The
                    % Prediction screen is where the actual Submit
                    % button lives; navigating to Jobs first was a
                    % dead-end UX since Jobs is for monitoring
                    % already-submitted runs.
                    txt = [char(9654) ' ' Labels.get('dashboard_next_step_predict', 'Submit to IBM')];
                    target = 'Prediction';
                case 'job'
                    txt = [char(8987) ' ' Labels.get('dashboard_next_step_job', 'View job status')];
                    target = 'Jobs';
                case 'results'
                    txt = [char(9636) ' ' Labels.get('dashboard_next_step_results', 'Open results')];
                    target = 'Results';
                otherwise
                    txt = [char(9650) ' ' Labels.get('dashboard_next_step_welcome', 'Upload a circuit')];
                    target = 'Upload';
            end
            app.DashNextStepButton.Text          = txt;
            app.DashNextStepButton.ButtonPushedFcn = @(~,~) app.onSelectSection(target);
        end

        function paintEmptyState(obj, data)
            % Phase 7: detect a fresh project (zero circuits AND zero
            % recent jobs) and surface the welcome hero card. The
            % toolbar / KPI strip / stepper / readiness / health /
            % activity panels stay built — the empty-state row sits
            % above them and just calls them out as "no data yet".
            % We detect via two signals from the existing fetches:
            %   1. Server's dashboard payload reports circuit_count = 0
            %      (or doesn't report circuits at all)
            %   2. LastJobEvents is empty (no jobs in last 100)
            % Both must be true to show the hero — a project with
            % circuits but no jobs is still "started", not "fresh".
            app = obj.App;
            if isempty(app.DashEmptyStatePanel) || ~isvalid(app.DashEmptyStatePanel)
                return;
            end
            if isempty(app.DashOuterGrid) || ~isvalid(app.DashOuterGrid)
                return;
            end
            % Read circuit count from the dashboard payload. Fall back
            % to "unknown" when the server doesn't report it (treat as
            % non-empty so we don't false-positive the welcome card).
            cc = JsonHelper.pickNumeric(data, 'circuit_count', NaN);
            if ~isfinite(cc)
                cc = JsonHelper.pickNumeric(data, 'num_circuits', NaN);
            end
            hasCircuits = ~isfinite(cc) || cc > 0;
            hasJobs     = ~isempty(obj.LastJobEvents);

            isEmpty = ~hasCircuits && ~hasJobs;
            try
                rh = app.DashOuterGrid.RowHeight;
                if isEmpty
                    rh{2} = 110;
                    app.DashEmptyStatePanel.Visible = 'on';
                else
                    rh{2} = 0;
                    app.DashEmptyStatePanel.Visible = 'off';
                end
                app.DashOuterGrid.RowHeight = rh;
            catch ME
                Logger.debug('DashboardViewModel', ...
                    'paintEmptyState toggle: %s', ME.message);
            end
        end

        function paintGreeting(obj, data)
            % Phase 9: replace the static "Storyboard landing summary…"
            % toolbar text with a live "Welcome back, {user} · Last
            % refreshed HH:MM · N projects · M circuits" line. Gives
            % the operator concrete status (who am I, when did this
            % data arrive, how big is my workspace) instead of internal
            % product copy. Counts are read out of the dashboard
            % payload with sensible fallbacks; the VM's onProjectsLoaded
            % cached count is reused when the payload doesn't carry it.
            app = obj.App;
            if isempty(app.DashGreetingLabel) || ~isvalid(app.DashGreetingLabel)
                return;
            end
            try
                user = char(app.State.currentUser);
                if isempty(user); user = 'operator'; end
                ts   = datestr(now, 'HH:MM');
                nProj = JsonHelper.pickNumeric(data, 'project_count', NaN);
                if ~isfinite(nProj) && ~isempty(app.DashProjectDropdown) ...
                        && isvalid(app.DashProjectDropdown)
                    try; nProj = numel(app.DashProjectDropdown.ItemsData); catch; end
                end
                nCirc = JsonHelper.pickNumeric(data, 'circuit_count', NaN);
                if ~isfinite(nCirc)
                    nCirc = JsonHelper.pickNumeric(data, 'num_circuits', NaN);
                end
                parts = {sprintf('Welcome back, %s', user), ...
                         sprintf('Last refreshed %s', ts)};
                if isfinite(nProj) && nProj > 0
                    if nProj == 1; sfx = ''; else; sfx = 's'; end
                    parts{end+1} = sprintf('%d project%s', int32(nProj), sfx);
                end
                if isfinite(nCirc) && nCirc > 0
                    if nCirc == 1; sfx = ''; else; sfx = 's'; end
                    parts{end+1} = sprintf('%d circuit%s', int32(nCirc), sfx);
                end
                app.DashGreetingLabel.Text = strjoin(parts, '  ·  ');
            catch ME
                Logger.debug('DashboardViewModel', ...
                    'paintGreeting: %s', ME.message);
            end
        end

        function refreshDashboardFromState(obj)
            app = obj.App;
            % Update KPI labels from session state
            if ~isempty(app.DashKpiLabels) && numel(app.DashKpiLabels) >= 4
                projText = char(app.State.currentProjectName);
                if isempty(projText)
                    projText = char(app.State.currentProjectId);
                end
                kpiVals = {projText, ...
                           char(app.State.selectedCircuitName), ...
                           char(app.State.selectedBackend), ...
                           ''};
                for i = 1:4
                    if ~isempty(kpiVals{i}) && isvalid(app.DashKpiLabels{i})
                        app.DashKpiLabels{i}.Text = kpiVals{i};
                    end
                end
            end
            summary = { ...
                sprintf('Base URL: %s',        app.State.baseUrl), ...
                sprintf('Current user: %s',     app.State.currentUser), ...
                sprintf('Project: %s',          app.State.currentProjectId), ...
                sprintf('Authenticated: %s',    string(app.State.isAuthenticated())), ...
                sprintf('Health: %s',           app.State.lastHealth), ...
                sprintf('Selected backend: %s', app.State.selectedBackend), ...
                sprintf('Circuit ID: %s',       app.State.selectedCircuitId)};
            app.DashboardSummaryArea.Value = summary;
            JsonTreeView.setMessage(app.DashboardStatusArea, 'Dashboard refreshed from session state.');
        end

        function updateActivityPageLabel(obj, totalRows)
            app = obj.App;
            pageNum   = floor(obj.ActivityPageSkip / obj.ActivityPageLimit) + 1;
            totalPages = max(1, ceil(totalRows / obj.ActivityPageLimit));
            if ~isempty(app.DashActivityPageLabel) && isvalid(app.DashActivityPageLabel)
                app.DashActivityPageLabel.Text = sprintf('Page %d / %d', pageNum, totalPages);
            end
            if ~isempty(app.DashActivityPrevBtn) && isvalid(app.DashActivityPrevBtn)
                app.DashActivityPrevBtn.Enable = obj.ActivityPageSkip > 0;
            end
            if ~isempty(app.DashActivityNextBtn) && isvalid(app.DashActivityNextBtn)
                app.DashActivityNextBtn.Enable = (obj.ActivityPageSkip + obj.ActivityPageLimit) < totalRows;
            end
        end
    end
end
