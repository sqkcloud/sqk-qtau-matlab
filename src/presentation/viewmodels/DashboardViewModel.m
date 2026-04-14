classdef DashboardViewModel < handle
    % DashboardViewModel  Callback handlers for the Dashboard screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
        ActivityPageSkip double = 0
        ActivityPageLimit double = 15
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
                pid = app.State.currentProjectId;
                app.logEvent('API', sprintf('GET /api/projects/%s/dashboard', pid));
                app.showLoading(Labels.get('loading_dashboard', 'Loading dashboard...'));
                AsyncRunner.run( ...
                    @() app.ProjectSvc.getDashboard(pid, app.State.authToken), ...
                    @(data) obj.onDashboardComplete(app, pid, data), ...
                    @(ME)   obj.onDashboardError(app, pid, ME));
                return;
            end
            app.logEvent('UI', 'Dashboard falling back to session state summary');
            obj.refreshDashboardFromState();
            obj.refreshActivityTable();
        end

        function onDashboardComplete(obj, app, pid, data)
            obj.applyDashboardData(data);
            app.logEvent('API', sprintf('Dashboard data loaded for project: %s', pid));
            obj.LastRefresh = tic;
            app.hideLoading();
        end

        function onDashboardError(obj, app, pid, ME)
            app.hideLoading();
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
                AsyncRunner.run( ...
                    @() app.ProjectSvc.getActivities(pid, skip, limit, app.State.authToken), ...
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
            allRows = app.State.ActivityLog;
            totalRows = size(allRows, 1);
            if totalRows == 0
                app.DashActivityTable.Data = {};
                obj.updateActivityPageLabel(0);
                return;
            end
            if obj.ActivityPageSkip >= totalRows
                obj.ActivityPageSkip = max(0, totalRows - obj.ActivityPageLimit);
            end
            startIdx = obj.ActivityPageSkip + 1;
            endIdx   = min(obj.ActivityPageSkip + obj.ActivityPageLimit, totalRows);
            app.DashActivityTable.Data = allRows(startIdx:endIdx, :);
            obj.updateActivityPageLabel(totalRows);
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

                % Refresh activity table from local log (pagination-aware)
                obj.ActivityPageSkip = 0;
                obj.refreshActivityTable();
            catch ME
                Logger.warn('DashboardViewModel', 'applyDashboardData failed: %s', ME.message);
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
