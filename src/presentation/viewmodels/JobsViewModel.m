classdef JobsViewModel < handle
    % JobsViewModel  Callback handlers for the Jobs screen.
    properties
        LastRefresh = []        % tic value — used by autoLoadScreen for freshness caching
        LastSelectFetch = []    % tic value — debounce per-row status fetch
        AutoRefreshTimer = []   % MATLAB timer polling GET /api/jobs while the Jobs screen is visible
        LastRefreshWasSilent = false  % true when the most recent onRefreshJobs was auto-poll triggered
        CachedCircuits = []     % cached /api/circuits response — re-used by auto-refresh ticks
        CachedCircuitsAt = []   % datetime when CachedCircuits was last fetched
        LastDetailFetchId = ''  % id of the job whose detail was last auto-fetched
        LastDetailFetchStatus = ''  % its status at the time — skip re-fetch if unchanged
        CurrentPage = 1         % 1-indexed page index for the paginated job list
        PageSize = 10           % rows fetched per page — keeps initial load fast
        LastPageRowCount = 0    % rows returned on the most recent fetch — drives Next button enable
        FullRows = {}           % unfiltered rows cached from the most recent refresh; the visible
                                % JobsTable.Data may be a filtered subset of this when the search
                                % field is non-empty.
        CurrentQuery = ''       % active substring filter; applied against col 1 (Job ID) and col 2
                                % (Circuit) of FullRows. '' = show every row.
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = JobsViewModel(app)
            obj.App = app;
        end

        function onSearch(obj, query)
            % onSearch  Update the active query string and repaint the
            %   visible rows with the case-insensitive substring filter.
            %   The unfiltered FullRows cache is preserved, so a later
            %   auto-refresh tick re-applies the SAME filter without
            %   the operator having to retype anything.
            if nargin < 2; query = ''; end
            obj.CurrentQuery = strtrim(char(query));
            obj.applyFilter(obj.App);
        end

        function applyFilter(obj, app)
            % applyFilter  Project FullRows through CurrentQuery and
            %   write the resulting subset to app.JobsTable.Data.
            %   Matches case-insensitive substrings of column 1
            %   (Job ID) or column 2 (Circuit / Circuit ID).
            try
                if isempty(app) || isempty(app.JobsTable) || ~isvalid(app.JobsTable)
                    return;
                end
            catch
                return;
            end
            q = lower(char(obj.CurrentQuery));
            if isempty(obj.FullRows)
                app.JobsTable.Data = {};
                return;
            end
            if isempty(q)
                app.JobsTable.Data = obj.FullRows;
                return;
            end
            n = size(obj.FullRows, 1);
            keep = false(n, 1);
            for i = 1:n
                jobId   = lower(char(string(obj.FullRows{i, 1})));
                circuit = lower(char(string(obj.FullRows{i, 2})));
                if contains(jobId, q) || contains(circuit, q)
                    keep(i) = true;
                end
            end
            app.JobsTable.Data = obj.FullRows(keep, :);
        end

        function onRefreshJobs(obj, silent)
            % silent=true omits the loading overlay and is used by the
            % auto-refresh timer so the user doesn't see a flash every
            % 5 seconds. Manual Refresh button clicks use silent=false
            % (default) and show the overlay.
            if nargin < 2 || isempty(silent); silent = false; end
            app = obj.App;
            if ~app.State.isAuthenticated()
                if ~silent
                    uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Jobs', 'Icon', 'warning');
                end
                return;
            end
            if ~silent
                app.logEvent('API', 'Refresh jobs list (with circuit-name lookup)');
                app.showLoading(Labels.get('loading_jobs', 'Loading jobs...'));
            end
            obj.LastRefreshWasSilent = silent;
            svc     = app.JobSvc;
            token   = app.State.authToken;
            % Reuse cached circuits when fresh (60s TTL). The auto-refresh
            % timer fires every 5s and circuits very rarely change inside
            % a session — fetching /api/circuits 12 times per minute just
            % to map circuit_id → name is wasteful. Pass circSvc=[] to
            % the worker to skip that fetch.
            circuitsFresh = ~isempty(obj.CachedCircuits) ...
                && ~isempty(obj.CachedCircuitsAt) ...
                && seconds(datetime('now') - obj.CachedCircuitsAt) < 60;
            if circuitsFresh
                circSvc = [];
            else
                circSvc = app.CircuitSvc;
            end
            skip  = max(0, (obj.CurrentPage - 1) * obj.PageSize);
            limit = obj.PageSize;
            % Parallel dispatch via runMany: listJobs and listCircuits
            % are independent — running them concurrently on
            % backgroundPool saves one full HTTP round-trip vs. the prior
            % serial worker (~300-800 ms on the initial Jobs nav). When
            % circuits cache is fresh (circSvc == []) we dispatch
            % listJobs alone.
            if isempty(circSvc)
                AsyncRunner.runMany( ...
                    {@() svc.listJobs(token, skip, limit)}, ...
                    @(results) obj.onRefreshJobsComplete(app, ...
                        struct('jobs', results{1}, 'circuits', [])), ...
                    @(ME) obj.onRefreshJobsError(app, ME));
            else
                AsyncRunner.runMany( ...
                    { @() svc.listJobs(token, skip, limit), ...
                      @() JobsViewModel.safeListCircuits(circSvc, token) }, ...
                    @(results) obj.onRefreshJobsComplete(app, ...
                        struct('jobs', results{1}, 'circuits', results{2})), ...
                    @(ME) obj.onRefreshJobsError(app, ME));
            end
        end

        function onNextPage(obj)
            % Advance one page when the most recent fetch returned a full
            % page of rows (== PageSize). If the server returned fewer, we
            % know there is nothing past this page so the button stays off.
            if obj.LastPageRowCount < obj.PageSize; return; end
            obj.CurrentPage = obj.CurrentPage + 1;
            obj.LastDetailFetchId = '';   % force detail re-fetch on the new top row
            obj.onRefreshJobs(false);
        end

        function onPrevPage(obj)
            if obj.CurrentPage <= 1; return; end
            obj.CurrentPage = obj.CurrentPage - 1;
            obj.LastDetailFetchId = '';
            obj.onRefreshJobs(false);
        end

        function startAutoRefresh(obj, intervalSec)
            % Begin background polling of GET /api/jobs every intervalSec
            % seconds while the user is on the Jobs screen. The timer
            % self-terminates once the user navigates elsewhere, so we
            % don't burn HTTP calls in the background on other screens.
            if nargin < 2 || isempty(intervalSec); intervalSec = 5; end
            obj.stopAutoRefresh();
            app = obj.App;
            try
                t = timer( ...
                    'ExecutionMode', 'fixedSpacing', ...
                    'Period',        double(intervalSec), ...
                    'StartDelay',    double(intervalSec), ...
                    'BusyMode',      'drop', ...
                    'Name',          'JobsAutoRefresh', ...
                    'TimerFcn',      @(src,~) obj.onAutoRefreshTick(app, src));
                obj.AutoRefreshTimer = t;
                start(t);
                Logger.debug('JobsViewModel', 'Auto-refresh started (every %gs)', intervalSec);
            catch ME
                Logger.warn('JobsViewModel', 'startAutoRefresh: %s', ME.message);
            end
        end

        function stopAutoRefresh(obj)
            try
                if ~isempty(obj.AutoRefreshTimer) && isvalid(obj.AutoRefreshTimer)
                    stop(obj.AutoRefreshTimer);
                    delete(obj.AutoRefreshTimer);
                end
            catch
            end
            obj.AutoRefreshTimer = [];
        end

        function onAutoRefreshTick(obj, app, timerObj)
            % Self-terminating tick: if the user has navigated away from
            % the Jobs screen, drop the timer instead of polling blindly.
            try
                active = strcmp(char(app.NavList.Value), 'Jobs');
            catch
                active = false;
            end
            if ~active
                try; stop(timerObj); delete(timerObj); catch; end
                obj.AutoRefreshTimer = [];
                return;
            end
            obj.onRefreshJobs(true);  % silent refresh — no overlay
        end

        function onCancelJob(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                uialert(app.UIFigure, Labels.get('error_no_job'), 'Cancel Job', 'Icon', 'warning'); return;
            end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('Cancel job — id %s', jobId));
            app.showLoading(Labels.get('loading_cancelling', 'Cancelling job...'));
            svc = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.cancelJob(jobId, token), ...
                @(~) obj.onCancelJobComplete(app, jobId), ...
                @(ME) obj.onCancelJobError(app, jobId, ME));
        end

        function onJobTableSelect(obj, src)
            app = obj.App;
            try
                row = src.Selection(1);
                data = src.Data;
                if isempty(data) || row > size(data,1); return; end
                app.State.selectedJobId = string(data{row, 1});
                app.logEvent('UI', sprintf('Job selected from table — row: %d  id: %s', ...
                    row, app.State.selectedJobId));

                % Debounce: skip refetch if the last status fetch was < 250 ms ago
                if ~isempty(obj.LastSelectFetch) && toc(obj.LastSelectFetch) < 0.25; return; end
                obj.LastSelectFetch = tic;

                jobId = app.State.selectedJobId;
                % Fetch the full job detail (status + progress + logs[] +
                % partial_results) so we can populate both the right-hand
                % Live Monitor Notes panel and the bottom Detailed Job
                % Logs panel in a single round-trip.
                app.logEvent('API', sprintf('Refresh job — id %s', jobId));
                svc = app.JobSvc;
                token = app.State.authToken;
                AsyncRunner.run( ...
                    @() svc.getJob(jobId, token), ...
                    @(job) obj.onSelectJobComplete(app, jobId, job), ...
                    @(ME)  obj.onSelectStatusError(app, jobId, ME));
            catch ME
                app.logEvent('WARN', sprintf('Job table select handler error: %s', ME.message));
            end
        end

        function onPauseJob(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                uialert(app.UIFigure, Labels.get('error_no_job'), 'Pause Job', 'Icon', 'warning'); return;
            end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('Pause job — id %s', jobId));
            svc = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.pauseJob(jobId, token), ...
                @(~) obj.onPauseJobComplete(app, jobId), ...
                @(ME) obj.onPauseJobError(app, jobId, ME));
        end
    end

    methods (Access = private)
        function updatePaginationUi(obj, app, rowCount)
            % Refresh footer label + Prev/Next enable state. Called
            % from onRefreshJobsComplete after each successful fetch.
            try
                page = obj.CurrentPage;
                if rowCount > 0
                    firstIdx = (page - 1) * obj.PageSize + 1;
                    lastIdx  = firstIdx + rowCount - 1;
                    msg = sprintf(Labels.get('jobs_page_info', ...
                        'Page %d  •  Showing %d-%d'), page, firstIdx, lastIdx);
                else
                    msg = sprintf(Labels.get('jobs_page_info_empty', ...
                        'Page %d  •  No jobs'), page);
                end
                if ~isempty(app.JobsPageLabel) && isvalid(app.JobsPageLabel)
                    app.JobsPageLabel.Text = msg;
                end
                if ~isempty(app.JobsPrevButton) && isvalid(app.JobsPrevButton)
                    if page > 1
                        app.JobsPrevButton.Enable = 'on';
                    else
                        app.JobsPrevButton.Enable = 'off';
                    end
                end
                if ~isempty(app.JobsNextButton) && isvalid(app.JobsNextButton)
                    if rowCount >= obj.PageSize
                        app.JobsNextButton.Enable = 'on';
                    else
                        app.JobsNextButton.Enable = 'off';
                    end
                end
            catch ME
                Logger.warn('JobsViewModel', ...
                    'updatePaginationUi failed: %s', ME.message);
            end
        end

        function onRefreshJobsComplete(obj, app, result)
            % `result` is the struct assembled in onRefreshJobs from the
            % parallel runMany batch:
            %   result.jobs     — /api/jobs response
            %   result.circuits — /api/circuits response (may be empty)
            if isstruct(result) && isfield(result, 'jobs')
                data     = result.jobs;
                circList = [];
                if isfield(result, 'circuits'); circList = result.circuits; end
            else
                % Backwards-compatible fallback: caller handed us the raw
                % jobs response directly.
                data     = result;
                circList = [];
            end

            % Hydrate from cache when the worker skipped the circuits
            % fetch (circSvc=[] path). Refresh the cache when a fresh
            % circuit list DID come back from the worker.
            if isempty(circList)
                circList = obj.CachedCircuits;
            else
                obj.CachedCircuits = circList;
                obj.CachedCircuitsAt = datetime('now');
            end
            nameMap = JobsViewModel.buildCircuitNameMap(circList);
            rows = JsonHelper.jobsToRows(data, nameMap);
            obj.LastPageRowCount = size(rows, 1);

            % If the user clicked Next past the last populated page (or
            % jobs were removed since the previous tick), step back to
            % page 1 instead of showing an empty table with no obvious
            % recovery affordance.
            if isempty(rows) && obj.CurrentPage > 1
                obj.CurrentPage = 1;
                obj.updatePaginationUi(app, 0);
                app.hideLoading();
                obj.onRefreshJobs(false);
                return;
            end
            obj.updatePaginationUi(app, size(rows, 1));
            % Auto-stop the 5s polling once every job is terminal so we
            % don't keep hammering the server with /api/jobs requests
            % long after there's nothing left to refresh. The next user
            % nav back into Jobs (or a manual Refresh click) will
            % re-arm the timer if they need fresh data.
            if ~isempty(rows)
                terminal = {'completed','failed','cancelled','done','success'};
                statuses = lower(string(rows(:, 4)));   % col 4 = Status
                allTerminal = all(ismember(statuses, terminal));
                if allTerminal && ~isempty(obj.AutoRefreshTimer) ...
                        && isvalid(obj.AutoRefreshTimer)
                    Logger.info('JobsViewModel', ...
                        ['All %d jobs terminal — stopping the 5s ' ...
                         'auto-refresh timer.'], numel(statuses));
                    obj.stopAutoRefresh();
                end
            end
            if ~isempty(rows)
                % Cache the unfiltered rows and let applyFilter render
                % whichever subset matches the current search query.
                obj.FullRows = rows;
                obj.applyFilter(app);
                firstId = string(rows{1,1});
                firstStatus = char(rows{1,4});   % col 4 = Status
                app.State.selectedJobId = firstId;
                app.logEvent('UI', sprintf('Auto-selected first job: %s', firstId));

                % Auto-fetch the first job's detail so the Detailed Job
                % Logs panel is populated without the user having to
                % click a row. Skip the fetch when the first row's
                % id+status is unchanged from the previous tick — server
                % returns the same payload and the panel already shows
                % it. Saves one API call per tick during a stable queue.
                sameAsLast = strcmp(char(firstId), obj.LastDetailFetchId) ...
                    && strcmp(firstStatus, obj.LastDetailFetchStatus);
                if sameAsLast
                    % Skipping hideLoading here used to leave the overlay
                    % stuck on "Loading jobs…" whenever the user re-entered
                    % the Jobs screen on the same first-row id/status.
                    obj.FullRows = rows;
                    obj.applyFilter(app);
                    obj.LastRefresh = tic;
                    app.hideLoading();
                    return;
                end
                obj.LastDetailFetchId     = char(firstId);
                obj.LastDetailFetchStatus = firstStatus;

                try
                    svc   = app.JobSvc;
                    token = app.State.authToken;
                    AsyncRunner.run( ...
                        @() svc.getJob(char(firstId), token), ...
                        @(job) obj.onSelectJobComplete(app, char(firstId), job), ...
                        @(ME)  obj.onSelectStatusError(app, char(firstId), ME));
                catch ME
                    Logger.warn('JobsViewModel', ...
                        'Auto-detail fetch failed: %s', ME.message);
                end
            end
            app.setStatus(app.JobStatusArea, {sprintf('Jobs loaded: %d', size(rows,1))});
            app.logEvent('API', sprintf('Jobs loaded — %d rows returned', size(rows,1)));
            obj.LastRefresh = tic;
            app.hideLoading();
        end

        function onRefreshJobsError(obj, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Jobs FAILED: %s', ME.message));
            app.setStatus(app.JobStatusArea, {'Jobs refresh failed.', ME.message});
            % Silent auto-refresh swallows errors — we don't want a
            % modal dialog popping up every 5 seconds on a transient
            % network blip. Manual Refresh still shows the dialog.
            if ~obj.LastRefreshWasSilent
                app.showError('Refresh Jobs', ME);
            else
                Logger.debug('JobsViewModel', 'Silent auto-refresh error: %s', ME.message);
            end
        end

        function onCancelJobComplete(obj, app, jobId)
            app.setStatus(app.JobStatusArea, {sprintf('Cancel request sent for job: %s', jobId)});
            app.logEvent('API', sprintf('Cancel request sent — job: %s', jobId));
            app.State.logActivity(sprintf('Cancel job — %s', char(jobId)), 'Success');
            app.hideLoading();
            obj.onRefreshJobs();
        end

        function onCancelJobError(~, app, jobId, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Cancel FAILED (job: %s): %s', jobId, ME.message));
            app.showError('Cancel Job', ME);
        end

        function onSelectJobComplete(~, app, jobId, job)
            % Right panel: Live Monitor Notes (concise status).
            statusStr  = upper(char(JsonHelper.pick(job, {'status','job_status'}, '')));
            progress   = JsonHelper.pickNumeric(job, 'progress_pct', NaN);
            curStep    = char(JsonHelper.pick(job, {'current_step'}, ''));
            backendStr = char(JsonHelper.pick(job, {'backend_name','backend'}, ''));
            shots      = JsonHelper.pickNumeric(job, 'shots', NaN);
            ibmJobId   = char(JsonHelper.pick(job, {'ibm_job_id'}, ''));
            circuitId  = char(JsonHelper.pick(job, {'circuit_id'}, ''));
            submitted  = char(JsonHelper.pick(job, {'submitted_at','created_at'}, ''));
            completed  = char(JsonHelper.pick(job, {'completed_at'}, ''));

            progressTxt = '—';
            if ~isnan(progress); progressTxt = sprintf('%.0f%%', progress); end
            shotsTxt = '—';
            if ~isnan(shots); shotsTxt = sprintf('%d', shots); end

            % M11.2 — surface IBM Quantum's actual error reason in the
            % Live Monitor Notes so a FAILED / CANCELLED job shows the
            % root cause inline rather than a generic "Execution
            % failed". Truncate to ~120 chars for the preview; the
            % full text appears in the Detailed Job Logs textarea
            % below via the server-enriched logs[] array.
            statusLines = { ...
                sprintf('Job ID: %s', jobId), ...
                sprintf('Backend: %s', backendStr), ...
                sprintf('Status: %s', statusStr), ...
                sprintf('Progress: %s', progressTxt), ...
                sprintf('Step: %s', curStep)};
            try
                metaStruct = JsonHelper.safeField(job, 'result_metadata', struct());
                if isstruct(metaStruct)
                    errMsg = char(string(JsonHelper.pick(metaStruct, ...
                        'error_message', '')));
                else
                    errMsg = '';
                end
                if ~isempty(strtrim(errMsg)) && ...
                        any(strcmpi(statusStr, {'FAILED','CANCELLED','CANCELED','ERROR'}))
                    % Collapse newlines + trim for the one-line preview.
                    flat = regexprep(errMsg, '\s+', ' ');
                    if numel(flat) > 120
                        flat = [flat(1:117) '...'];
                    end
                    statusLines{end+1} = '';  %#ok<AGROW>
                    statusLines{end+1} = sprintf('Error: %s', flat); %#ok<AGROW>
                    statusLines{end+1} = ...
                        '(scroll Detailed Job Logs below for full IBM error + log)'; %#ok<AGROW>
                end
            catch ME
                Logger.debug('JobsViewModel', ...
                    'error_message preview render failed: %s', ME.message);
            end
            app.setStatus(app.JobStatusArea, statusLines);

            % Bottom panel: Detailed Job Logs — header block + server logs[].
            lines = { ...
                sprintf('── Job detail ─────────────────────────────'), ...
                sprintf('Local job ID : %s', jobId), ...
                sprintf('IBM job ID   : %s', ibmJobId), ...
                sprintf('Circuit ID   : %s', circuitId), ...
                sprintf('Backend      : %s', backendStr), ...
                sprintf('Shots        : %s', shotsTxt), ...
                sprintf('Status       : %s (%s)', statusStr, progressTxt), ...
                sprintf('Current step : %s', curStep), ...
                sprintf('Submitted    : %s', submitted), ...
                sprintf('Completed    : %s', completed), ...
                '', ...
                '── Server logs ────────────────────────────'};

            try
                logs = JsonHelper.pick(job, {'logs'}, []);
                nLogs = numel(logs);
                if nLogs > 0 && (iscell(logs) || isstring(logs))
                    for i = 1:nLogs
                        if iscell(logs); entry = logs{i}; else; entry = logs(i); end
                        lines{end+1} = char(string(entry)); %#ok<AGROW>
                    end
                else
                    lines{end+1} = '(no log entries from server yet)';
                end
            catch ME
                lines{end+1} = sprintf('(log decode failed: %s)', ME.message);
            end

            if ~isempty(app.JobLogsArea) && isvalid(app.JobLogsArea)
                app.JobLogsArea.Value = lines;
            end

            % Update the clicked row in the Jobs table so the Status and
            % Progress columns reflect the fresh detail. The list endpoint
            % returns cached progress_pct derived from status (queued=10,
            % running=50, completed=100), so a queued job visually stays
            % at 10 % until either its status changes in the DB or we
            % overwrite the row with the per-job detail response.
            try
                if ~isempty(app.JobsTable) && isvalid(app.JobsTable)
                    d = app.JobsTable.Data;
                    for r = 1:size(d, 1)
                        if strcmp(char(string(d{r, 1})), char(jobId))
                            % Column layout (see jobsToRows):
                            %   1 Job ID | 2 Circuit | 3 Backend | 4 Status
                            %   | 5 Progress | 6 Created
                            if size(d, 2) >= 4 && ~isempty(statusStr)
                                d{r, 4} = statusStr;
                            end
                            if size(d, 2) >= 5
                                d{r, 5} = progressTxt;
                            end
                            app.JobsTable.Data = d;
                            break;
                        end
                    end
                end
            catch ME
                Logger.warn('JobsViewModel', ...
                    'Failed to refresh table row %s: %s', jobId, ME.message);
            end

            app.logEvent('API', sprintf('Job detail fetched — job: %s  status: %s  progress: %s  logs: %d', ...
                jobId, statusStr, progressTxt, max(0, numel(lines) - 12)));
        end

        function onSelectStatusError(~, app, jobId, ME)
            app.logEvent('WARN', sprintf('Could not fetch job detail (job: %s): %s', jobId, ME.message));
            if ~isempty(app.JobLogsArea) && isvalid(app.JobLogsArea)
                app.JobLogsArea.Value = { ...
                    sprintf('Failed to load job %s', jobId), ...
                    ME.message};
            end
        end

        function onPauseJobComplete(~, app, jobId)
            app.setStatus(app.JobStatusArea, {sprintf('Pause request sent for job: %s', jobId)});
            app.logEvent('API', sprintf('Pause request sent — job: %s', jobId));
        end

        function onPauseJobError(~, app, jobId, ME)
            app.logEvent('ERROR', sprintf('Pause FAILED (job: %s): %s', jobId, ME.message));
            app.showError('Pause Job', ME);
        end
    end

    methods (Static, Access = private)
        function out = safeListCircuits(circSvc, token)
            % Wraps circSvc.listCircuits in try/catch so a circuits-API
            % failure does NOT poison the parallel batch. The job list
            % is the required result; circuits are only used for the
            % circuit_id → name display lookup, so silencing the error
            % and returning [] preserves the prior best-effort semantic
            % (the table renders with raw circuit_id in that column).
            try
                out = circSvc.listCircuits(token);
            catch ME
                Logger.warn('JobsViewModel', ...
                    'Circuit list fetch failed (jobs still shown): %s', ME.message);
                out = [];
            end
        end

        function map = buildCircuitNameMap(circList)
            % circuit_id → display name lookup. Returns an empty map
            % when the circuit list is unavailable or empty.
            map = containers.Map('KeyType', 'char', 'ValueType', 'char');
            if isempty(circList); return; end
            items = JsonHelper.extractList(circList, 'circuits');
            if isempty(items); items = JsonHelper.asList(circList); end
            for i = 1:numel(items)
                cid  = char(JsonHelper.pick(items(i), {'circuit_id','id'}));
                nm   = char(JsonHelper.pick(items(i), {'name','circuit_name'}));
                if isempty(nm); nm = cid; end
                if ~isempty(cid); map(cid) = nm; end
            end
        end
    end
end
