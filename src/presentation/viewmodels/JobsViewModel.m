classdef JobsViewModel < handle
    % JobsViewModel  Callback handlers for the Jobs screen.
    properties
        LastRefresh = []        % tic value — used by autoLoadScreen for freshness caching
        LastSelectFetch = []    % tic value — debounce per-row status fetch
        AutoRefreshTimer = []   % MATLAB timer polling GET /api/jobs while the Jobs screen is visible
        LastRefreshWasSilent = false  % true when the most recent onRefreshJobs was auto-poll triggered
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = JobsViewModel(app)
            obj.App = app;
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
                app.logEvent('API', 'GET /api/jobs (+ /api/circuits for name lookup)');
                app.showLoading(Labels.get('loading_jobs', 'Loading jobs...'));
            end
            obj.LastRefreshWasSilent = silent;
            svc     = app.JobSvc;
            circSvc = app.CircuitSvc;
            token   = app.State.authToken;
            % Fetch jobs and circuits together so we can join circuit_id
            % → circuit name for the new Circuit column on the dashboard.
            AsyncRunner.run( ...
                @() JobsViewModel.fetchJobsAndCircuits(svc, circSvc, token), ...
                @(result) obj.onRefreshJobsComplete(app, result), ...
                @(ME)     obj.onRefreshJobsError(app, ME));
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
            app.logEvent('API', sprintf('POST /api/jobs/%s/cancel', jobId));
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
                app.logEvent('API', sprintf('GET /api/jobs/%s', jobId));
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
            app.logEvent('API', sprintf('POST /api/jobs/%s/pause', jobId));
            svc = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.pauseJob(jobId, token), ...
                @(~) obj.onPauseJobComplete(app, jobId), ...
                @(ME) obj.onPauseJobError(app, jobId, ME));
        end
    end

    methods (Access = private)
        function onRefreshJobsComplete(obj, app, result)
            % `result` is the struct produced by fetchJobsAndCircuits:
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

            nameMap = JobsViewModel.buildCircuitNameMap(circList);
            rows = JsonHelper.jobsToRows(data, nameMap);
            if ~isempty(rows)
                app.JobsTable.Data = rows;
                firstId = string(rows{1,1});
                app.State.selectedJobId = firstId;
                app.logEvent('UI', sprintf('Auto-selected first job: %s', firstId));

                % Auto-fetch the first job's detail so the Detailed Job
                % Logs panel is populated without the user having to
                % click a row.
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

            app.setStatus(app.JobStatusArea, { ...
                sprintf('Job ID: %s', jobId), ...
                sprintf('Backend: %s', backendStr), ...
                sprintf('Status: %s', statusStr), ...
                sprintf('Progress: %s', progressTxt), ...
                sprintf('Step: %s', curStep)});

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
        function result = fetchJobsAndCircuits(jobSvc, circSvc, token)
            % Pull jobs (required) and circuits (best-effort) so the
            % ViewModel can join circuit_id → name. If the circuits call
            % fails we still return the jobs so the dashboard renders
            % with raw IDs in the Circuit column.
            result = struct('jobs', [], 'circuits', []);
            result.jobs = jobSvc.listJobs(token);
            try
                result.circuits = circSvc.listCircuits(token);
            catch ME
                Logger.warn('JobsViewModel', ...
                    'Circuit list fetch failed (jobs still shown): %s', ME.message);
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
