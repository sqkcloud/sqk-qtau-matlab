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
            try
                data = app.JobSvc.getResults(jobId, app.State.authToken);
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
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Results FAILED (job: %s): %s', jobId, ME.message));
                app.setStatus(app.ResultJsonArea, {'Results load failed.', ME.message});
                app.showError('Refresh Results', ME);
            end
        end
    end
end
