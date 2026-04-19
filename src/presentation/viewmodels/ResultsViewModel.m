classdef ResultsViewModel < handle
    % ResultsViewModel  Callback handlers for the Results screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = ResultsViewModel(app)
            obj.App = app;
        end

        function onRefreshResults(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), ...
                    'Results', 'Icon', 'warning');
                return;
            end
            app.logEvent('API', 'GET /api/jobs — hunting for a completed job to display');
            app.showLoading(Labels.get('loading_results', 'Loading results...'));
            jobSvc = app.JobSvc;
            token  = app.State.authToken;
            % Ask the jobs list for a completed job first, then fetch its
            % results. Relying on State.selectedJobId (typically the first
            % row in the Jobs table, which is usually queued/running) gave
            % us HTTP 409 every time and left this screen blank.
            AsyncRunner.run( ...
                @() jobSvc.listJobs(token, 0, 100), ...
                @(list) obj.onJobsListedForResults(app, list), ...
                @(ME)   obj.onRefreshResultsError(app, char(app.State.selectedJobId), ME));
        end
    end

    methods (Access = private)
        function onJobsListedForResults(obj, app, list)
            items = JsonHelper.extractList(list, 'jobs');
            if isempty(items); items = JsonHelper.asList(list); end
            completedId = '';
            for i = 1:numel(items)
                status = lower(char(string(JsonHelper.pick(items(i), {'status'}))));
                if any(strcmp(status, {'completed', 'done', 'success'}))
                    completedId = char(string(JsonHelper.pick(items(i), ...
                        {'job_record_id','job_id','id'})));
                    if ~isempty(completedId); break; end
                end
            end

            % Fall back to whatever is currently selected if no completed
            % job exists — at least the user will still see the "not
            % ready" message explaining why.
            if isempty(completedId)
                if strlength(app.State.selectedJobId) > 0
                    completedId = char(app.State.selectedJobId);
                else
                    app.hideLoading();
                    app.setStatus(app.ResultJsonArea, { ...
                        'No jobs have completed yet.', ...
                        'Results will appear here after at least one job reaches status = completed.', ...
                        'Tip: open the Jobs screen to monitor live progress.'});
                    return;
                end
            else
                % Keep global state in sync so e.g. the Detailed Analysis
                % screen — which also reads app.State.selectedJobId — shows
                % the same job the Results screen is displaying.
                app.State.selectedJobId = string(completedId);
            end

            app.logEvent('API', sprintf('GET /api/jobs/%s/results', completedId));
            svc   = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getResults(completedId, token), ...
                @(data) obj.onRefreshResultsComplete(app, completedId, data), ...
                @(ME)   obj.onRefreshResultsError(app, completedId, ME));
        end

        function onRefreshResultsComplete(obj, app, jobId, data)
            rows = JsonHelper.resultsToRows(data);
            if ~isempty(rows)
                app.ResultsTable.Data = rows;
            end
            statusStr  = char(JsonHelper.pick(data, {'status'}));
            backendStr = char(JsonHelper.pick(data, {'backend_name','backend'}));
            fidelity   = char(JsonHelper.pick(data, {'measured_fidelity','fidelity'}));
            summary = { ...
                sprintf('Job: %s', jobId), ...
                sprintf('Backend: %s', backendStr), ...
                sprintf('Status: %s',  statusStr), ...
                sprintf('Fidelity: %s', fidelity)};
            app.setStatus(app.ResultJsonArea, summary);
            app.logEvent('API', sprintf('Results loaded — job: %s  status: %s  fidelity: %s  rows: %d', ...
                jobId, statusStr, fidelity, size(rows,1)));
            app.State.logActivity(sprintf('View results — job: %s', char(jobId)), 'Success');
            obj.LastRefresh = tic;
            app.hideLoading();
        end

        function onRefreshResultsError(~, app, jobId, ME)
            app.hideLoading();
            % The backend returns 409 Conflict when the job has not reached
            % the `completed` state yet — that's a normal condition for
            % queued/running jobs, not an error. Show an informative note
            % in the status pane instead of a red alert modal.
            if contains(ME.identifier, 'HTTP409')
                app.logEvent('API', sprintf('Results not ready (job: %s) — job not yet completed', jobId));
                app.setStatus(app.ResultJsonArea, { ...
                    sprintf('Job: %s', jobId), ...
                    'Results are not available yet.', ...
                    'The job is still queued or running — results appear after completion.', ...
                    'Tip: check the Jobs screen for live status and use Refresh once status = completed.'});
                return;
            end
            app.logEvent('ERROR', sprintf('Results FAILED (job: %s): %s', jobId, ME.message));
            app.setStatus(app.ResultJsonArea, {'Results load failed.', ME.message});
            app.showError('Refresh Results', ME);
        end
    end
end
