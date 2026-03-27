classdef JobsViewModel < handle
    % JobsViewModel  Callback handlers for the Jobs screen.
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
            try
                data = app.JobSvc.listJobs(app.State.authToken);
                rows = JsonHelper.jobsToRows(data);
                if ~isempty(rows)
                    app.JobsTable.Data = rows;
                    app.State.selectedJobId = string(rows{1,1});
                    app.logEvent('UI', sprintf('Auto-selected first job: %s', app.State.selectedJobId));
                end
                app.setStatus(app.JobStatusArea, {sprintf('Jobs loaded: %d', size(rows,1))});
                app.logEvent('API', sprintf('Jobs loaded — %d rows returned', size(rows,1)));
            catch ME
                app.logEvent('ERROR', sprintf('Jobs FAILED: %s', ME.message));
                app.setStatus(app.JobStatusArea, {'Jobs refresh failed.', ME.message});
                app.showError('Refresh Jobs', ME);
            end
        end

        function onCancelJob(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                uialert(app.UIFigure, Labels.get('error_no_job'), 'Cancel Job', 'Icon', 'warning'); return;
            end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('POST /api/jobs/%s/cancel', jobId));
            try
                app.JobSvc.cancelJob(jobId, app.State.authToken);
                app.setStatus(app.JobStatusArea, {sprintf('Cancel request sent for job: %s', jobId)});
                app.logEvent('API', sprintf('Cancel request sent — job: %s', jobId));
                obj.onRefreshJobs();
            catch ME
                app.logEvent('ERROR', sprintf('Cancel FAILED (job: %s): %s', jobId, ME.message));
                app.showError('Cancel Job', ME);
            end
        end

        function onJobTableSelect(obj, src)
            app = obj.App;
            try
                row = src.Selection(1);
                data = src.Data;
                if ~isempty(data) && row <= size(data,1)
                    app.State.selectedJobId = string(data{row, 1});
                    app.logEvent('UI', sprintf('Job selected from table — row: %d  id: %s', ...
                        row, app.State.selectedJobId));
                    try
                        app.logEvent('API', sprintf('GET /api/jobs/%s/status', app.State.selectedJobId));
                        stat = app.JobSvc.getStatus(app.State.selectedJobId, app.State.authToken);
                        statusStr = char(JsonHelper.pick(stat, {'status','job_status'}));
                        progress  = char(JsonHelper.pick(stat, {'progress_pct','progress'}));
                        app.setStatus(app.JobStatusArea, { ...
                            sprintf('Job ID: %s', app.State.selectedJobId), ...
                            sprintf('Status: %s', statusStr), ...
                            sprintf('Progress: %s', progress)});
                        app.logEvent('API', sprintf('Job status fetched — job: %s  status: %s  progress: %s', ...
                            app.State.selectedJobId, statusStr, progress));
                    catch ME
                        app.logEvent('WARN', sprintf('Could not fetch job status (job: %s): %s', ...
                            app.State.selectedJobId, ME.message));
                    end
                end
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
            try
                app.JobSvc.pauseJob(jobId, app.State.authToken);
                app.setStatus(app.JobStatusArea, {sprintf('Pause request sent for job: %s', jobId)});
                app.logEvent('API', sprintf('Pause request sent — job: %s', jobId));
            catch ME
                app.logEvent('ERROR', sprintf('Pause FAILED (job: %s): %s', jobId, ME.message));
                app.showError('Pause Job', ME);
            end
        end
    end
end
