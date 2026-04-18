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
            if ~app.State.isAuthenticated() || ~app.State.hasJob()
                uialert(app.UIFigure, Labels.get('error_no_job'), 'Results', 'Icon', 'warning'); return;
            end
            jobId = app.State.selectedJobId;
            app.logEvent('API', sprintf('GET /api/jobs/%s/results', jobId));
            app.showLoading(Labels.get('loading_results', 'Loading results...'));
            svc   = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getResults(jobId, token), ...
                @(data) obj.onRefreshResultsComplete(app, jobId, data), ...
                @(ME)   obj.onRefreshResultsError(app, jobId, ME));
        end
    end

    methods (Access = private)
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
