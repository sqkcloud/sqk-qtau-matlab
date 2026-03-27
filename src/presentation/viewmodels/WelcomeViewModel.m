classdef WelcomeViewModel < handle
    % WelcomeViewModel  Callback handlers for the Welcome screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = WelcomeViewModel(app)
            obj.App = app;
        end

        function onNewProject(obj)
            app = obj.App;
            app.logEvent('UI', 'New Project dialog opened');
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'New Project', 'Icon', 'warning');
                return;
            end
            answer = inputdlg({'Project name','Description'}, 'New Project', [1 60; 3 60]);
            if isempty(answer)
                app.logEvent('UI', 'New Project dialog cancelled');
                return;
            end
            app.logEvent('API', sprintf('Creating project: "%s"', answer{1}));
            try
                data = app.ProjectSvc.createProject(answer{1}, answer{2}, app.State.authToken);
                app.State.currentProjectId = string(JsonHelper.pick(data, {'project_id','id'}));
                app.logEvent('API', sprintf('Project created successfully — id: %s  name: %s', ...
                    app.State.currentProjectId, answer{1}));
                obj.onFetchProjects();
            catch ME
                app.showError('Create Project', ME);
            end
        end

        function onLoadProject(obj)
            obj.onFetchProjects();
        end

        function onProjectTableSelect(obj, src)
            app = obj.App;
            try
                row = src.Selection(1);
                data = src.Data;
                if ~isempty(data) && row <= size(data,1)
                    app.State.currentProjectId = string(data{row, 1});
                    app.logEvent('UI', sprintf('Project selected: %s', app.State.currentProjectId));
                    app.setStatus(app.UserInfoArea, { ...
                        sprintf('Active project: %s', app.State.currentProjectId), ...
                        sprintf('Name: %s', char(data{row,2})), ...
                        sprintf('Owner: %s', char(data{row,3}))});
                end
            catch; end
        end

        function onApplyUrl(obj)
            app = obj.App;
            app.syncClient();
            app.logEvent('CONFIG', sprintf('Base URL applied: %s', app.State.baseUrl));
            app.setStatus(app.LoginStatusArea, {sprintf('Base URL set to: %s', app.State.baseUrl)});
        end

        function onOpenApiCheck(obj)
            app = obj.App;
            app.syncClient();
            app.logEvent('API', sprintf('OpenAPI check → %s/api/openapi.json', app.State.baseUrl));
            try
                data = app.Client.openApi();
                app.State.lastHealth = "OK";
                apiTitle   = JsonHelper.pick(data, {'info.title'});
                apiVersion = JsonHelper.pick(data, {'info.version'});
                app.setStatus(app.LoginStatusArea, {'OpenAPI check succeeded.', ...
                    sprintf('Title: %s', apiTitle), ...
                    sprintf('Version: %s', apiVersion)});
                app.logEvent('API', sprintf('OpenAPI check OK — title: %s  version: %s', apiTitle, apiVersion));
            catch ME
                app.State.lastHealth = "FAILED";
                app.logEvent('ERROR', sprintf('OpenAPI check FAILED: %s', ME.message));
                app.setStatus(app.LoginStatusArea, {'OpenAPI check failed.', ME.message});
                app.showError('OpenAPI Check', ME);
            end
        end

        function onLogin(obj)
            app = obj.App;
            app.syncClient();
            username = string(app.UsernameField.Value);
            password = string(app.PasswordField.Value);
            if strlength(strtrim(username)) == 0 || strlength(password) == 0
                uialert(app.UIFigure, Labels.get('error_missing_credentials', 'Enter username and password first.'), 'Login', 'Icon', 'warning');
                return;
            end
            app.logEvent('AUTH', sprintf('Login attempt — user: %s  url: %s', username, app.State.baseUrl));
            try
                data = app.Client.login(username, password);
                app.State.authToken        = string(JsonHelper.pick(data, {'access_token','token','data.access_token'}));
                app.State.tokenType        = string(JsonHelper.pick(data, {'token_type','data.token_type'}));
                app.State.currentUser      = string(JsonHelper.pick(data, {'username','user.username','data.username'}));
                app.State.defaultProjectId = string(JsonHelper.pick(data, {'default_project_id','data.default_project_id'}));
                app.State.currentProjectId = app.State.defaultProjectId;

                if strlength(strtrim(app.State.authToken)) == 0
                    app.logEvent('WARN', 'Login response received but no access_token found');
                    app.setStatus(app.LoginStatusArea, {'Login response received — no token found.', JsonHelper.pretty(data)});
                    uialert(app.UIFigure, Labels.get('error_login_no_token'), 'Login', 'Icon', 'warning');
                    return;
                end
                if strlength(strtrim(app.State.tokenType)) == 0
                    app.State.tokenType = "Bearer";
                end
                app.setStatus(app.LoginStatusArea, { ...
                    'Login successful.', ...
                    sprintf('Username: %s', app.State.currentUser), ...
                    sprintf('Token type: %s', app.State.tokenType), ...
                    sprintf('Default project: %s', app.State.defaultProjectId)});
                app.logEvent('AUTH', sprintf('Login OK — user: %s  token_type: %s  default_project: %s', ...
                    app.State.currentUser, app.State.tokenType, app.State.defaultProjectId));
                app.updateWelcomeAuthButtons();
            catch ME
                app.setStatus(app.LoginStatusArea, {'Login failed.', ME.message});
                app.logEvent('ERROR', sprintf('Login FAILED (user: %s): %s', username, ME.message));
                if contains(ME.message, '401')
                    msg = sprintf('%s\n\nTechnical details:\n%s', ...
                        Labels.get('error_login_unauthorized'), ME.message);
                    app.logEvent('ERROR', sprintf('[Login] %s', ME.message));
                    uialert(app.UIFigure, msg, Labels.get('error_title', 'Error'), 'Icon', 'error');
                else
                    app.showError('Login', ME);
                end
            end
        end

        function onGetMe(obj)
            app = obj.App;
            app.logEvent('API', 'GET /api/auth/me — fetching user info');
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'User Info', 'Icon', 'warning'); return;
            end
            try
                data = app.Client.getMe(app.State.authToken);
                app.setStatus(app.UserInfoArea, {JsonHelper.pretty(data)});
                app.logEvent('API', 'GET /api/auth/me → user info received');
            catch ME
                app.setStatus(app.UserInfoArea, {'User info failed.', ME.message});
                app.showError('Get User Info', ME);
            end
        end

        function onLogout(obj)
            app = obj.App;
            app.logEvent('AUTH', sprintf('Logout requested — user: %s', app.State.currentUser));
            if ~app.State.isAuthenticated()
                app.setStatus(app.LoginStatusArea, {'Already logged out.'});
                app.updateWelcomeAuthButtons();
                return;
            end
            try
                prevUser = app.State.currentUser;
                app.Client.logout(app.State.authToken);
                app.State.authToken = "";
                app.State.currentUser = "";
                app.setStatus(app.LoginStatusArea, {'Logout successful.'});
                app.setStatus(app.UserInfoArea, {'Logged out.'});
                app.logEvent('AUTH', sprintf('Logout OK — user: %s', prevUser));
                app.updateWelcomeAuthButtons();
            catch ME
                app.setStatus(app.LoginStatusArea, {'Logout failed.', ME.message});
                app.showError('Logout', ME);
            end
        end

        function onFetchProjects(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Projects', 'Icon', 'warning'); return;
            end
            skip  = max(0, round(app.SkipField.Value));
            limit = max(1, round(app.LimitField.Value));
            app.logEvent('API', sprintf('GET /api/admin/projects — skip=%d  limit=%d', skip, limit));
            try
                data = app.Client.listProjects(app.State.authToken, skip, limit);
                rows = JsonHelper.projectsToRows(data);
                app.ProjectsTable.Data = rows;
                nRows = size(rows, 1);
                app.logEvent('API', sprintf('GET /api/admin/projects → %d row(s) returned', nRows));
                info = sprintf('Fetched %d project row(s).', nRows);
                if isstruct(data) && isfield(data, 'total')
                    info = [info sprintf('  Total on server: %s', string(data.total))];
                end
                app.setStatus(app.UserInfoArea, {info, JsonHelper.pretty(data)});
            catch ME
                app.setStatus(app.UserInfoArea, {'Project fetch failed.', ME.message});
                app.showError('Fetch Projects', ME);
            end
        end
    end
end
