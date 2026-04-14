classdef JobsViewModel < handle
    % JobsViewModel  Callback handlers for the Jobs screen.
    properties
        LastRefresh = []        % tic value — used by autoLoadScreen for freshness caching
        LastSelectFetch = []    % tic value — debounce per-row status fetch
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = JobsViewModel(app)
            obj.App = app;
        end

        function onRefreshJobs(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Jobs', 'Icon', 'warning'); return;
            end
            app.logEvent('API', 'GET /api/jobs');
            app.showLoading(Labels.get('loading_jobs', 'Loading jobs...'));
            AsyncRunner.run( ...
                @() app.JobSvc.listJobs(app.State.authToken), ...
                @(data) obj.onRefreshJobsComplete(app, data), ...
                @(ME)   obj.onRefreshJobsError(app, ME));
        end

        function onCancelJob(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                uialert(app.UIFigure, Labels.get('error_no_job'), 'Cancel Job', 'Icon', 'warning'); return;
            end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('POST /api/jobs/%s/cancel', jobId));
            app.showLoading(Labels.get('loading_cancelling', 'Cancelling job...'));
            AsyncRunner.run( ...
                @() app.JobSvc.cancelJob(jobId, app.State.authToken), ...
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
                app.logEvent('API', sprintf('GET /api/jobs/%s/status', jobId));
                AsyncRunner.run( ...
                    @() app.JobSvc.getStatus(jobId, app.State.authToken), ...
                    @(stat) obj.onSelectStatusComplete(app, jobId, stat), ...
                    @(ME)   obj.onSelectStatusError(app, jobId, ME));
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
            AsyncRunner.run( ...
                @() app.JobSvc.pauseJob(jobId, app.State.authToken), ...
                @(~) obj.onPauseJobComplete(app, jobId), ...
                @(ME) obj.onPauseJobError(app, jobId, ME));
        end
    end

    methods (Access = private)
        function onRefreshJobsComplete(obj, app, data)
            rows = JsonHelper.jobsToRows(data);
            if ~isempty(rows)
                app.JobsTable.Data = rows;
                app.State.selectedJobId = string(rows{1,1});
                app.logEvent('UI', sprintf('Auto-selected first job: %s', app.State.selectedJobId));
            end
            app.setStatus(app.JobStatusArea, {sprintf('Jobs loaded: %d', size(rows,1))});
            app.logEvent('API', sprintf('Jobs loaded — %d rows returned', size(rows,1)));
            obj.LastRefresh = tic;
            app.hideLoading();
        end

        function onRefreshJobsError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Jobs FAILED: %s', ME.message));
            app.setStatus(app.JobStatusArea, {'Jobs refresh failed.', ME.message});
            app.showError('Refresh Jobs', ME);
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

        function onSelectStatusComplete(~, app, jobId, stat)
            statusStr = char(JsonHelper.pick(stat, {'status','job_status'}));
            progress  = char(JsonHelper.pick(stat, {'progress_pct','progress'}));
            app.setStatus(app.JobStatusArea, { ...
                sprintf('Job ID: %s', jobId), ...
                sprintf('Status: %s', statusStr), ...
                sprintf('Progress: %s', progress)});
            app.logEvent('API', sprintf('Job status fetched — job: %s  status: %s  progress: %s', ...
                jobId, statusStr, progress));
        end

        function onSelectStatusError(~, app, jobId, ME)
            app.logEvent('WARN', sprintf('Could not fetch job status (job: %s): %s', jobId, ME.message));
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
end
