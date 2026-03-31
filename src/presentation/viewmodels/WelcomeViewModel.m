classdef WelcomeViewModel < handle
    % WelcomeViewModel  Callback handlers for the Welcome screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    properties
        CurrentPage  double = 1
        TotalItems   double = 0
        ItemsPerPage double = 10
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
            app.showNewProjectDialog();
        end

        function onCreateProject(obj)
            app = obj.App;

            % Read fields from the dialog
            if isempty(app.NewProjectDialog) || ~isvalid(app.NewProjectDialog)
                return;
            end
            projName = strtrim(string(app.NewProjNameField.Value));
            projDesc = strtrim(strjoin(string(app.NewProjDescField.Value), newline));
            tagsRaw  = strtrim(string(app.NewProjTagsField.Value));

            if strlength(projName) == 0
                app.NewProjStatusLabel.Text = Labels.get('new_proj_error_name_required', 'Project name is required.');
                return;
            end
            if strlength(projName) > 100
                app.NewProjStatusLabel.Text = Labels.get('new_proj_error_name_long', 'Project name must be 100 characters or fewer.');
                return;
            end

            % Parse tags
            tags = {};
            if strlength(tagsRaw) > 0
                parts = strsplit(char(tagsRaw), ',');
                tags = strtrim(parts);
                tags = tags(~cellfun(@isempty, tags));
            end

            app.logEvent('API', sprintf('Creating project: "%s"', projName));
            try
                data = app.ProjectSvc.createProject(char(projName), char(projDesc), tags, app.State.authToken);
                app.State.currentProjectId = string(JsonHelper.pick(data, {'project_id','id'}));
                app.logEvent('API', sprintf('Project created successfully — id: %s  name: %s', ...
                    app.State.currentProjectId, char(projName)));

                % Close dialog
                if ~isempty(app.NewProjectDialog) && isvalid(app.NewProjectDialog)
                    delete(app.NewProjectDialog);
                    app.NewProjectDialog = [];
                end

                obj.CurrentPage = 1;
                obj.onFetchProjects();
            catch ME
                if ~isempty(app.NewProjectDialog) && isvalid(app.NewProjectDialog)
                    app.NewProjStatusLabel.Text = ME.message;
                end
                app.logEvent('ERROR', sprintf('Create project FAILED: %s', ME.message));
            end
        end

        function onLoadProject(obj)
            obj.CurrentPage = 1;
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
                    app.UserInfoArea.Text = sprintf('Active project: %s  |  Name: %s', ...
                        char(app.State.currentProjectId), char(data{row,2}));
                end
            catch; end
        end

        function onLogin(obj)
            app = obj.App;

            % Read fields from the login dialog
            if isempty(app.LoginDialog) || ~isvalid(app.LoginDialog)
                return;
            end
            baseUrl  = string(app.LoginDlgBaseUrlField.Value);
            username = string(app.LoginDlgUsernameField.Value);
            password = string(app.LoginDlgPasswordReal);

            if strlength(strtrim(username)) == 0 || strlength(password) == 0
                app.LoginDlgStatusLabel.Text = Labels.get('error_missing_credentials', 'Enter username and password first.');
                return;
            end

            % Set base URL from dialog and sync client
            app.State.baseUrl = strtrim(baseUrl);
            app.syncClient();

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
                    app.LoginDlgStatusLabel.Text = Labels.get('error_login_no_token', 'No token in response.');
                    return;
                end
                if strlength(strtrim(app.State.tokenType)) == 0
                    app.State.tokenType = "Bearer";
                end

                app.logEvent('AUTH', sprintf('Login OK — user: %s  token_type: %s  default_project: %s', ...
                    app.State.currentUser, app.State.tokenType, app.State.defaultProjectId));

                % Close the login dialog
                if ~isempty(app.LoginDialog) && isvalid(app.LoginDialog)
                    delete(app.LoginDialog);
                    app.LoginDialog = [];
                end

                % Update Welcome screen
                app.updateWelcomeAuthButtons();
                app.UserInfoArea.Text = sprintf('Logged in as: %s  |  Default project: %s', ...
                    char(app.State.currentUser), char(app.State.defaultProjectId));

                % Auto-fetch projects
                obj.CurrentPage = 1;
                obj.onFetchProjects();

            catch ME
                if ~isempty(app.LoginDialog) && isvalid(app.LoginDialog)
                    if contains(ME.message, '401')
                        app.LoginDlgStatusLabel.Text = Labels.get('error_login_unauthorized', 'Invalid credentials.');
                    else
                        app.LoginDlgStatusLabel.Text = ME.message;
                    end
                end
                app.logEvent('ERROR', sprintf('Login FAILED (user: %s): %s', username, ME.message));
            end
        end

        function onLogout(obj)
            app = obj.App;
            app.logEvent('AUTH', sprintf('Logout requested — user: %s', app.State.currentUser));
            if ~app.State.isAuthenticated()
                app.updateWelcomeAuthButtons();
                return;
            end
            try
                prevUser = app.State.currentUser;
                app.Client.logout(app.State.authToken);
                app.State.authToken = "";
                app.State.currentUser = "";
                app.logEvent('AUTH', sprintf('Logout OK — user: %s', prevUser));
                app.updateWelcomeAuthButtons();
                app.UserInfoArea.Text = Labels.get('welcome_user_info_hint');
                app.ProjectsTable.Data = {};
                app.ProjectsPageLabel.Text = '';
                app.ProjectsPrevButton.Enable = 'off';
                app.ProjectsNextButton.Enable = 'off';
                obj.CurrentPage = 1;
                obj.TotalItems = 0;
            catch ME
                app.showError('Logout', ME);
            end
        end

        function onFetchProjects(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                return;
            end
            skip  = (obj.CurrentPage - 1) * obj.ItemsPerPage;
            limit = obj.ItemsPerPage;
            app.logEvent('API', sprintf('GET /api/admin/projects — skip=%d  limit=%d', skip, limit));
            try
                data = app.Client.listProjects(app.State.authToken, skip, limit);
                rows = JsonHelper.projectsToRows(data);
                app.ProjectsTable.Data = rows;

                if isstruct(data) && isfield(data, 'total')
                    obj.TotalItems = double(data.total);
                else
                    obj.TotalItems = size(rows, 1);
                end

                nRows = size(rows, 1);
                app.logEvent('API', sprintf('GET /api/admin/projects → %d row(s) returned (total: %d)', nRows, obj.TotalItems));
                obj.updatePagination();
            catch ME
                app.UserInfoArea.Text = sprintf('Project fetch failed: %s', ME.message);
                app.showError('Fetch Projects', ME);
            end
        end

        function onPrevPage(obj)
            if obj.CurrentPage > 1
                obj.CurrentPage = obj.CurrentPage - 1;
                obj.onFetchProjects();
            end
        end

        function onNextPage(obj)
            totalPages = ceil(obj.TotalItems / obj.ItemsPerPage);
            if obj.CurrentPage < totalPages
                obj.CurrentPage = obj.CurrentPage + 1;
                obj.onFetchProjects();
            end
        end
    end

    methods (Access = private)
        function updatePagination(obj)
            app = obj.App;
            totalPages = max(1, ceil(obj.TotalItems / obj.ItemsPerPage));
            app.ProjectsPageLabel.Text = sprintf('Page %d of %d  (%d items)', ...
                obj.CurrentPage, totalPages, obj.TotalItems);
            if obj.CurrentPage > 1
                app.ProjectsPrevButton.Enable = 'on';
            else
                app.ProjectsPrevButton.Enable = 'off';
            end
            if obj.CurrentPage < totalPages
                app.ProjectsNextButton.Enable = 'on';
            else
                app.ProjectsNextButton.Enable = 'off';
            end
        end
    end
end
