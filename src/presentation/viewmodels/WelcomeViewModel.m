classdef WelcomeViewModel < handle
    % WelcomeViewModel  Callback handlers for the Welcome screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
        FullProjectRows  cell = {}   % unfiltered table rows
        FullProjectIds   cell = {}   % unfiltered project IDs
        FilteredRows     cell = {}   % after search filter (or same as Full)
        FilteredIds      cell = {}
    end
    properties
        CurrentPage  double = 1
        TotalItems   double = 0
        ItemsPerPage double = 15
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
            app.showLoading(Labels.get('loading_creating_project', 'Creating project...'));
            AsyncRunner.run( ...
                @() app.ProjectSvc.createProject(char(projName), char(projDesc), tags, app.State.authToken), ...
                @(data) obj.onCreateProjectComplete(app, projName, data), ...
                @(ME)   obj.onCreateProjectError(app, ME));
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
                ids  = src.UserData;
                if ~isempty(data) && row <= size(data,1) && ~isempty(ids) && row <= numel(ids)
                    app.State.currentProjectId   = string(ids{row});
                    app.State.currentProjectName = string(data{row, 1});
                    app.Client.ProjectId = app.State.currentProjectId;
                    app.logEvent('UI', sprintf('Project selected: %s', app.State.currentProjectId));
                    app.ActiveProjectLabel.Text = char(app.State.currentProjectName);
                    if ~isempty(app.UploadActiveProjectLabel) && isvalid(app.UploadActiveProjectLabel)
                        app.UploadActiveProjectLabel.Text = char(app.State.currentProjectName);
                    end
                end
            catch ME
                Logger.warn('WelcomeViewModel', 'onProjectTableSelect failed: %s', ME.message);
            end
        end

        function onEditProject(obj)
            app = obj.App;
            app.hideProjectPopupMenu();
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Edit Project', 'Icon', 'warning'); return;
            end
            sel = app.ProjectsTable.Selection;
            if isempty(sel); return; end
            row = sel(1);
            data = app.ProjectsTable.Data;
            ids  = app.ProjectsTable.UserData;
            if isempty(data) || row > size(data,1) || isempty(ids) || row > numel(ids)
                return;
            end
            projectId = ids{row};
            projName  = char(string(data{row, 1}));
            projTags  = char(string(data{row, 2}));
            projDesc  = data{row, 5};
            if isempty(projDesc) || (isnumeric(projDesc) && numel(projDesc)==0)
                projDesc = '';
            else
                projDesc = char(string(projDesc));
            end
            app.logEvent('UI', sprintf('Edit project dialog opened for: %s (%s)', projName, projectId));
            app.showEditProjectDialog(projectId, projName, projDesc, projTags);
        end

        function onSaveProject(obj)
            app = obj.App;
            projectId = app.EditProjId;
            if isempty(projectId); return; end

            projName = string(app.EditProjNameField.Value);
            projDesc = string(strjoin(string(app.EditProjDescField.Value), newline));
            tagsRaw  = string(app.EditProjTagsField.Value);

            if strlength(strtrim(projName)) == 0
                app.EditProjStatusLabel.Text = Labels.get('edit_proj_error_name_required', 'Project name is required.');
                return;
            end
            if strlength(projName) > 100
                app.EditProjStatusLabel.Text = Labels.get('edit_proj_error_name_long', 'Project name must be 100 characters or fewer.');
                return;
            end

            tags = {};
            if strlength(tagsRaw) > 0
                parts = strsplit(char(tagsRaw), ',');
                tags = strtrim(parts);
                tags = tags(~cellfun(@isempty, tags));
            end

            app.logEvent('API', sprintf('Updating project: %s (%s)', projName, projectId));
            AsyncRunner.run( ...
                @() app.ProjectSvc.updateProject(char(projectId), char(projName), char(projDesc), tags, app.State.authToken), ...
                @(~) obj.onSaveProjectComplete(app, projectId, projName), ...
                @(ME) obj.onSaveProjectError(app, ME));
        end

        function onDeleteProject(obj)
            app = obj.App;
            app.hideProjectPopupMenu();
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Delete Project', 'Icon', 'warning'); return;
            end
            sel = app.ProjectsTable.Selection;
            if isempty(sel); return; end
            row = sel(1);
            data = app.ProjectsTable.Data;
            ids  = app.ProjectsTable.UserData;
            if isempty(data) || row > size(data,1) || isempty(ids) || row > numel(ids)
                return;
            end
            projectId = ids{row};
            projName  = data{row, 1};

            msg = sprintf(Labels.get('project_delete_confirm_msg', ...
                'Are you sure you want to delete project "%s"? This action cannot be undone.'), projName);
            answer = uiconfirm(app.UIFigure, msg, ...
                Labels.get('project_delete_confirm_title', 'Delete Project'), ...
                'Options', {[char(10006) ' ' Labels.get('project_delete_btn_delete', 'Delete')], ...
                            [char(10004) ' ' Labels.get('project_delete_btn_cancel', 'Cancel')]}, ...
                'DefaultOption', 2, ...
                'Icon', 'warning');

            if ~startsWith(answer, char(10006))
                return;
            end

            app.logEvent('API', sprintf('DELETE /api/projects/%s', projectId));
            app.showLoading('Deleting project...');
            AsyncRunner.run( ...
                @() app.ProjectSvc.deleteProject(char(projectId), app.State.authToken), ...
                @(~) obj.onDeleteProjectComplete(app, projectId, projName), ...
                @(ME) obj.onDeleteProjectError(app, ME));
        end

        function onLogin(obj)
            app = obj.App;

            % Read fields from the login dialog
            if isempty(app.LoginDialog) || ~isvalid(app.LoginDialog)
                return;
            end
            baseUrl  = string(app.LoginDlgBaseUrlValue);
            username = string(app.LoginDlgUsernameValue);
            password = string(app.LoginDlgPasswordReal);

            if strlength(strtrim(username)) == 0 || strlength(password) == 0
                app.LoginDlgStatusLabel.Text = Labels.get('error_missing_credentials', 'Enter username and password first.');
                return;
            end

            % Set base URL from dialog and sync client.
            % FastAPIClient.setBaseUrl rejects non-HTTPS URLs that aren't
            % loopback (S2). Surface that error to the dialog instead of
            % crashing the login flow.
            app.State.baseUrl = strtrim(baseUrl);
            try
                app.syncClient();
            catch urlErr
                if strcmp(urlErr.identifier, 'FastAPIClient:insecureBaseUrl') || ...
                   strcmp(urlErr.identifier, 'FastAPIClient:invalidBaseUrl')
                    app.LoginDlgStatusLabel.FontColor = [0.851 0.188 0.145];
                    app.LoginDlgStatusLabel.Text = Labels.get('error_login_insecure_url', ...
                        'Base URL must use https:// (or http://localhost for development).');
                    return;
                end
                rethrow(urlErr);
            end

            app.logEvent('AUTH', sprintf('Login attempt — user: %s  url: %s', username, app.State.baseUrl));
            try
                data = app.AuthSvc.login(username, password);
                app.State.authToken        = string(JsonHelper.pick(data, {'access_token','token','data.access_token'}));
                app.State.tokenType        = string(JsonHelper.pick(data, {'token_type','data.token_type'}));
                app.State.currentUser      = string(JsonHelper.pick(data, {'username','user.username','data.username'}));
                app.State.defaultProjectId = string(JsonHelper.pick(data, {'default_project_id','data.default_project_id'}));
                app.State.currentProjectId = app.State.defaultProjectId;
                app.Client.ProjectId = app.State.currentProjectId;

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
                app.State.logActivity(sprintf('Login — user: %s', app.State.currentUser), 'Success');

                % Clear password from memory
                app.LoginDlgPasswordReal = '';
                if ~isempty(app.LoginDlgPasswordField) && isvalid(app.LoginDlgPasswordField)
                    app.LoginDlgPasswordField.Data = struct('a', 'clear');
                end

                % Close the login dialog
                if ~isempty(app.LoginDialog) && isvalid(app.LoginDialog)
                    delete(app.LoginDialog);
                    app.LoginDialog = [];
                end

                % Update Welcome screen and hide auth overlay
                app.updateWelcomeAuthButtons();
                app.hideAuthOverlay();
                if ~isempty(app.UserInfoArea) && isvalid(app.UserInfoArea); app.UserInfoArea.Text = ''; end

                % Auto-fetch projects
                obj.CurrentPage = 1;
                obj.onFetchProjects();

                % Populate server IBM config silently so downstream screens
                % (Prediction's "Submit to IBM" button, Backends pool, etc.)
                % can gate on the real server state instead of the default
                % ServerIbmConfig struct (which has_token=false until set).
                obj.prefetchServerIbmConfig(app);

            catch ME
                if ~isempty(app.LoginDialog) && isvalid(app.LoginDialog)
                    app.LoginDlgStatusLabel.FontColor = [0.851 0.188 0.145];
                    if contains(ME.message, '401')
                        app.LoginDlgStatusLabel.Text = Labels.get('error_login_unauthorized', 'The Username or Password is incorrect.');
                    elseif contains(ME.message, {'connection','connect','timeout','Timeout','Send failure','Broken pipe','refused'}, 'IgnoreCase', true)
                        app.LoginDlgStatusLabel.Text = Labels.get('error_login_connection', ...
                            'Unable to connect to server. Please check the Base URL and try again.');
                    else
                        app.LoginDlgStatusLabel.Text = Labels.get('error_login_generic', ...
                            'Login failed. Please try again.');
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
                app.AuthSvc.logout(app.State.authToken);
                app.State.authToken = "";
                app.State.currentUser = "";
                % Reset cached server state so the next login's prefetch
                % takes effect before the Submit button gets hit again.
                app.ServerIbmConfig = struct('channel','','instance','', ...
                    'backends',{{}},'has_token',false, ...
                    'runtime_broken',false,'runtime_broken_reason','');
                app.logEvent('AUTH', sprintf('Logout OK — user: %s', prevUser));
                app.State.logActivity(sprintf('Logout — user: %s', prevUser), 'Success');
                app.updateWelcomeAuthButtons();
                app.showAuthOverlay();
                if ~isempty(app.UserInfoArea) && isvalid(app.UserInfoArea); app.UserInfoArea.Text = ''; end
                app.ActiveProjectLabel.Text = Labels.get('welcome_active_project_none', 'None');
                if ~isempty(app.UploadActiveProjectLabel) && isvalid(app.UploadActiveProjectLabel)
                    app.UploadActiveProjectLabel.Text = Labels.get('upload_label_no_project');
                end
                if ~isempty(app.UploadCircuitsTable) && isvalid(app.UploadCircuitsTable)
                    app.UploadCircuitsTable.Data = {};
                end
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
            app.logEvent('API', 'GET /api/projects');
            app.showLoading(Labels.get('loading_projects', 'Loading projects...'));
            AsyncRunner.run( ...
                @() app.AuthSvc.listProjects(app.State.authToken, 0, 0), ...
                @(data) obj.onFetchProjectsComplete(app, data), ...
                @(ME)   obj.onFetchProjectsError(app, ME));
        end

        function onSearchProjects(obj, query)
            % Filter the projects table by search query (matches any column)
            if isempty(obj.FullProjectRows); return; end
            q = lower(strtrim(query));
            if isempty(q)
                obj.FilteredRows = obj.FullProjectRows;
                obj.FilteredIds  = obj.FullProjectIds;
            else
                nRows = size(obj.FullProjectRows, 1);
                keep = false(nRows, 1);
                for i = 1:nRows
                    for j = 1:size(obj.FullProjectRows, 2)
                        val = obj.FullProjectRows{i, j};
                        if ischar(val) && contains(lower(val), q)
                            keep(i) = true; break;
                        elseif isnumeric(val) && contains(num2str(val), q)
                            keep(i) = true; break;
                        end
                    end
                end
                obj.FilteredRows = obj.FullProjectRows(keep, :);
                obj.FilteredIds  = obj.FullProjectIds(keep);
            end
            obj.TotalItems  = size(obj.FilteredRows, 1);
            obj.CurrentPage = 1;
            obj.displayCurrentPage();
        end

        function onPrevPage(obj)
            if obj.CurrentPage > 1
                obj.CurrentPage = obj.CurrentPage - 1;
                obj.displayCurrentPage();
            end
        end

        function onNextPage(obj)
            totalPages = ceil(obj.TotalItems / obj.ItemsPerPage);
            if obj.CurrentPage < totalPages
                obj.CurrentPage = obj.CurrentPage + 1;
                obj.displayCurrentPage();
            end
        end
    end

    methods (Access = private)
        function onCreateProjectComplete(obj, app, projName, data)
            app.State.currentProjectId   = string(JsonHelper.pick(data, {'project_id','id'}));
            app.State.currentProjectName = string(projName);
            app.Client.ProjectId = app.State.currentProjectId;
            app.logEvent('API', sprintf('Project created successfully — id: %s  name: %s', ...
                app.State.currentProjectId, char(projName)));
            app.State.logActivity(sprintf('Create project — %s', char(projName)), 'Success');
            if ~isempty(app.ActiveProjectLabel) && isvalid(app.ActiveProjectLabel)
                app.ActiveProjectLabel.Text = char(projName);
            end
            if ~isempty(app.UploadActiveProjectLabel) && isvalid(app.UploadActiveProjectLabel)
                app.UploadActiveProjectLabel.Text = char(projName);
            end
            if ~isempty(app.NewProjectDialog) && isvalid(app.NewProjectDialog)
                delete(app.NewProjectDialog);
                app.NewProjectDialog = [];
            end
            obj.CurrentPage = 1;
            obj.onFetchProjects();
            app.hideLoading();
        end

        function onCreateProjectError(~, app, ME)
            app.hideLoading();
            if ~isempty(app.NewProjectDialog) && isvalid(app.NewProjectDialog)
                app.NewProjStatusLabel.Text = ME.message;
            end
            app.logEvent('ERROR', sprintf('Create project FAILED: %s', ME.message));
        end

        function onSaveProjectComplete(obj, app, projectId, projName)
            app.logEvent('API', sprintf('Project updated successfully — id: %s', char(projectId)));
            app.State.logActivity(sprintf('Edit project — %s', char(projName)), 'Success');
            if strcmp(char(app.State.currentProjectId), char(projectId))
                app.State.currentProjectName = projName;
                app.ActiveProjectLabel.Text = char(projName);
                if ~isempty(app.UploadActiveProjectLabel) && isvalid(app.UploadActiveProjectLabel)
                    app.UploadActiveProjectLabel.Text = char(projName);
                end
            end
            if ~isempty(app.EditProjectDialog) && isvalid(app.EditProjectDialog)
                delete(app.EditProjectDialog);
                app.EditProjectDialog = [];
            end
            obj.onFetchProjects();
        end

        function onSaveProjectError(~, app, ME)
            if ~isempty(app.EditProjectDialog) && isvalid(app.EditProjectDialog)
                app.EditProjStatusLabel.Text = ME.message;
            end
            app.logEvent('ERROR', sprintf('Update project FAILED: %s', ME.message));
        end

        function onDeleteProjectComplete(obj, app, projectId, projName)
            app.logEvent('API', sprintf('Project deleted: %s (%s)', projName, projectId));
            app.State.logActivity(sprintf('Delete project — %s', projName), 'Success');
            if strcmp(char(app.State.currentProjectId), char(projectId))
                app.State.currentProjectId   = "";
                app.State.currentProjectName = "";
                app.Client.ProjectId = "";
                app.ActiveProjectLabel.Text = Labels.get('welcome_active_project_none', 'None');
                if ~isempty(app.UploadActiveProjectLabel) && isvalid(app.UploadActiveProjectLabel)
                    app.UploadActiveProjectLabel.Text = Labels.get('upload_label_no_project');
                end
            end
            app.hideLoading();
            obj.onFetchProjects();
        end

        function onDeleteProjectError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Delete project FAILED: %s', ME.message));
            app.showError('Delete Project', ME);
        end

        function onFetchProjectsComplete(obj, app, data)
            [rows, ids] = JsonHelper.projectsToRows(data);
            obj.FullProjectRows = rows;
            obj.FullProjectIds  = ids;
            obj.FilteredRows    = rows;
            obj.FilteredIds     = ids;
            obj.TotalItems = size(rows, 1);
            nRows = size(rows, 1);
            app.logEvent('API', sprintf('GET /api/projects → %d row(s) returned (total: %d)', nRows, obj.TotalItems));
            if app.State.hasProject() && nRows > 0
                for r = 1:nRows
                    if strcmp(ids{r}, char(app.State.currentProjectId))
                        app.State.currentProjectName = string(rows{r,1});
                        app.ActiveProjectLabel.Text = char(rows{r,1});
                        if ~isempty(app.UploadActiveProjectLabel) && isvalid(app.UploadActiveProjectLabel)
                            app.UploadActiveProjectLabel.Text = char(rows{r,1});
                        end
                        break;
                    end
                end
            end
            obj.displayCurrentPage();
            obj.LastRefresh = tic;
            app.hideLoading();
        end

        function onFetchProjectsError(~, app, ME)
            app.hideLoading();
            if ~isempty(app.UserInfoArea) && isvalid(app.UserInfoArea); app.UserInfoArea.Text = ''; end
            app.showError('Fetch Projects', ME);
        end

        function prefetchServerIbmConfig(~, app)
            % Fire-and-forget fetch of /settings/ibm-config so downstream
            % screens can gate on the real server state instead of the
            % default ServerIbmConfig struct (has_token=false). Silent on
            % failure — Settings screen will still surface the fresh state
            % when the user visits it.
            AsyncRunner.run( ...
                @() app.SettingsSvc.getIbmConfig(app.State.authToken), ...
                @(cfg) WelcomeViewModel.storeIbmConfig(app, cfg), ...
                @(ME)  Logger.debug('WelcomeViewModel', ...
                    'IBM config prefetch skipped: %s', ME.message));
        end
    end

    methods (Static, Access = private)
        function storeIbmConfig(app, cfg)
            % Central helper used by both login-prefetch and the Settings
            % screen to populate app.ServerIbmConfig consistently.
            backends = JsonHelper.safeField(cfg, 'backends', {});
            if ischar(backends); backends = {backends}; end
            if ~iscell(backends); backends = num2cell(string(backends)); end
            app.ServerIbmConfig = struct( ...
                'channel',  string(JsonHelper.safeField(cfg, 'channel', '')), ...
                'instance', string(JsonHelper.safeField(cfg, 'instance', '')), ...
                'backends', {backends}, ...
                'has_token', logical(JsonHelper.safeField(cfg, 'has_token', false)), ...
                'runtime_broken', logical(JsonHelper.safeField(cfg, 'runtime_broken', false)), ...
                'runtime_broken_reason', string(JsonHelper.safeField(cfg, 'runtime_broken_reason', '')));
        end
    end

    methods (Access = private)
        function displayCurrentPage(obj)
            app = obj.App;
            startIdx = (obj.CurrentPage - 1) * obj.ItemsPerPage + 1;
            endIdx   = min(obj.CurrentPage * obj.ItemsPerPage, obj.TotalItems);

            if startIdx > obj.TotalItems
                app.ProjectsTable.Data     = {};
                app.ProjectsTable.UserData = {};
            else
                app.ProjectsTable.Data     = obj.FilteredRows(startIdx:endIdx, :);
                app.ProjectsTable.UserData = obj.FilteredIds(startIdx:endIdx);
            end

            obj.updatePagination();
        end

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
