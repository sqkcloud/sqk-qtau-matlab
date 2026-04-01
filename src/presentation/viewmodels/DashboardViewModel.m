classdef DashboardViewModel < handle
    % DashboardViewModel  Callback handlers for the Dashboard screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = DashboardViewModel(app)
            obj.App = app;
        end

        function onRefreshDashboard(obj)
            app = obj.App;
            app.logEvent('UI', sprintf('Dashboard refresh triggered — auth: %s  project: %s', ...
                string(app.State.isAuthenticated()), app.State.currentProjectId));
            if app.State.isAuthenticated() && app.State.hasProject()
                app.logEvent('API', sprintf('GET /api/projects/%s/dashboard', app.State.currentProjectId));
                try
                    data = app.ProjectSvc.getDashboard(app.State.currentProjectId, app.State.authToken);
                    obj.applyDashboardData(data);
                    app.logEvent('API', sprintf('Dashboard data loaded for project: %s', app.State.currentProjectId));
                    return;
                catch ME
                    app.logEvent('ERROR', sprintf('Dashboard fetch failed (project: %s): %s', ...
                        app.State.currentProjectId, ME.message));
                    app.showError('Dashboard Refresh', ME);
                end
            end
            app.logEvent('UI', 'Dashboard falling back to session state summary');
            obj.refreshDashboardFromState();
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
                summary = char(JsonHelper.pick(data, {'summary','executive_summary'}));
                if ~isempty(summary)
                    app.setStatus(app.DashboardSummaryArea, {summary});
                end
                app.setStatus(app.DashboardStatusArea, {JsonHelper.pretty(data)});
            catch
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
            app.setStatus(app.DashboardStatusArea, {'Dashboard refreshed from session state.'});
        end
    end
end
