% WelcomeTab  Populates the Welcome section panel.
%
%   Layout (3-column grid):
%     Row 1: Hero banner spanning all 3 columns — quick-start actions.
%     Row 2, Col 1: Server / Authentication form (URL, credentials, login).
%     Row 2, Col 2: 6 px resizable column divider.
%     Row 2, Col 3: Recent Projects table with pagination controls.
%
%   The API base URL is read from resources/app.properties via AppConfig.
%   All visible strings are loaded from resources/labels.properties via Labels.
function WelcomeScreen(app)
    Logger.info('WelcomeScreen', 'Building Welcome tab UI');
    t = app.createSectionPage('Welcome');

    % ── Root grid: 2 rows × 3 cols (left | divider | right) ─────────────────
    g = uigridlayout(t, [2 3]);
    g.RowHeight     = {136, '1x'};
    g.ColumnWidth   = {'1.15x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Hero banner (full width) ──────────────────────────────────────────────
    hero = uipanel(g, 'Title', Labels.get('welcome_panel_project_launch'));
    hero.Layout.Row = 1; hero.Layout.Column = [1 3];
    hero.BackgroundColor = [1 1 1];
    hg = uigridlayout(hero, [2 4]);
    hg.RowHeight   = {30, '1x'};
    hg.ColumnWidth = {'1x','1x','1x','1x'};
    hg.Padding     = [18 14 18 14]; hg.BackgroundColor = [1 1 1];

    titleLabel = uilabel(hg, 'Text', Labels.get('welcome_hero_title'));
    titleLabel.FontSize = 17; titleLabel.FontWeight = 'bold';
    titleLabel.Layout.Row = 1; titleLabel.Layout.Column = [1 4]; titleLabel.WordWrap = 'on';

    btn1 = uibutton(hg, 'Text', Labels.get('welcome_btn_new_project'));
    btn1.Layout.Row = 2; btn1.Layout.Column = 1; app.styleBtn(btn1, 'primary');
    btn1.ButtonPushedFcn = @(~,~)app.WelcomeVm.onNewProject();

    btn2 = uibutton(hg, 'Text', Labels.get('welcome_btn_load_project'));
    btn2.Layout.Row = 2; btn2.Layout.Column = 2; app.styleBtn(btn2, 'ghost');
    btn2.ButtonPushedFcn = @(~,~)app.WelcomeVm.onLoadProject();

    btn3 = uibutton(hg, 'Text', Labels.get('welcome_btn_documentation'));
    btn3.Layout.Row = 2; btn3.Layout.Column = 3; app.styleBtn(btn3, 'ghost');
    btn3.ButtonPushedFcn = @(~,~)web('https://docs.quantum.ibm.com', '-browser');

    btn4 = uibutton(hg, 'Text', Labels.get('welcome_btn_ibm_account'));
    btn4.Layout.Row = 2; btn4.Layout.Column = 4; app.styleBtn(btn4, 'secondary');
    btn4.ButtonPushedFcn = @(~,~)app.onSelectSection('Settings');

    % ── Column divider ────────────────────────────────────────────────────────
    div = uipanel(g, 'Title', '');
    div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Server / Authentication (left panel) ─────────────────────────────────
    left = uipanel(g, 'Title', Labels.get('welcome_panel_server_auth'));
    left.Layout.Row = 2; left.Layout.Column = 1; left.BackgroundColor = [1 1 1];
    lg = uigridlayout(left, [7 2]);
    lg.RowHeight = {36, 36, 36, 36, 36, 36, '1x'};
    lg.ColumnWidth = {130,'1x'};
    lg.Padding = [16 12 16 12]; lg.RowSpacing = 8; lg.BackgroundColor = [1 1 1];

    lbl = uilabel(lg, 'Text', Labels.get('welcome_label_base_url'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;

    % Base URL loaded from app.properties — never hardcoded here
    app.BaseUrlField = uieditfield(lg, 'text', 'Value', AppConfig.get('base_url', 'http://34.42.87.190:5715'));
    app.BaseUrlField.Layout.Row = 1; app.BaseUrlField.Layout.Column = 2;
    app.BaseUrlField.Tooltip = 'FastAPI backend base URL (no trailing slash)';

    app.ApplyUrlButton = uibutton(lg, 'Text', Labels.get('welcome_btn_apply_url'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onApplyUrl());
    app.ApplyUrlButton.Layout.Row = 2; app.ApplyUrlButton.Layout.Column = 1;
    app.styleBtn(app.ApplyUrlButton, 'ghost');

    app.OpenApiCheckButton = uibutton(lg, 'Text', Labels.get('welcome_btn_openapi_check'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onOpenApiCheck());
    app.OpenApiCheckButton.Layout.Row = 2; app.OpenApiCheckButton.Layout.Column = 2;
    app.styleBtn(app.OpenApiCheckButton, 'ghost');
    app.OpenApiCheckButton.Tooltip = 'GET /api/openapi.json — confirm server is reachable';

    lbl = uilabel(lg, 'Text', Labels.get('welcome_label_username'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    app.UsernameField = uieditfield(lg, 'text', 'Value', 'sqkadmin');
    app.UsernameField.Layout.Row = 3; app.UsernameField.Layout.Column = 2;

    lbl = uilabel(lg, 'Text', Labels.get('welcome_label_password'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 4; lbl.Layout.Column = 1;
    app.PasswordField = uieditfield(lg, 'text', 'Value', 'Sqkcloud2022!');
    app.PasswordField.Layout.Row = 4; app.PasswordField.Layout.Column = 2;

    app.LoginButton = uibutton(lg, 'Text', Labels.get('welcome_btn_login'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onLogin());
    app.LoginButton.Layout.Row = 5; app.LoginButton.Layout.Column = 1;
    app.styleBtn(app.LoginButton, 'primary');
    app.LoginButton.Tooltip = 'POST /api/auth/login';

    app.MeButton = uibutton(lg, 'Text', Labels.get('welcome_btn_get_user_info'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onGetMe());
    app.MeButton.Layout.Row = 5; app.MeButton.Layout.Column = 2;
    app.styleBtn(app.MeButton, 'ghost');
    app.MeButton.Tooltip = 'GET /api/auth/me';

    app.LogoutButton = uibutton(lg, 'Text', Labels.get('welcome_btn_logout'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onLogout());
    app.LogoutButton.Layout.Row = 6; app.LogoutButton.Layout.Column = [1 2];
    app.styleBtn(app.LogoutButton, 'danger');

    app.LoginStatusArea = uitextarea(lg, 'Editable', 'off');
    app.LoginStatusArea.Value = { ...
        'Demo credentials are pre-filled.', ...
        'Click Login to authenticate against the live server.'};
    app.LoginStatusArea.Layout.Row = 7; app.LoginStatusArea.Layout.Column = [1 2];
    app.LoginStatusArea.FontSize = 12;

    % ── Recent Projects (right panel) ────────────────────────────────────────
    right = uipanel(g, 'Title', Labels.get('welcome_panel_recent_projects'));
    right.Layout.Row = 2; right.Layout.Column = 3; right.BackgroundColor = [1 1 1];
    rg = uigridlayout(right, [4 4]);
    rg.RowHeight = {36, 36, 80, '1x'};
    rg.ColumnWidth = {60, 90, '1x', '1x'};
    rg.Padding = [16 12 16 12]; rg.RowSpacing = 8; rg.BackgroundColor = [1 1 1];

    lbl = uilabel(rg, 'Text', Labels.get('welcome_label_skip'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.SkipField = uieditfield(rg, 'numeric', 'Value', 0);
    app.SkipField.Layout.Row = 1; app.SkipField.Layout.Column = 2;

    lbl = uilabel(rg, 'Text', Labels.get('welcome_label_limit'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 3;
    app.LimitField = uieditfield(rg, 'numeric', 'Value', 100);
    app.LimitField.Layout.Row = 1; app.LimitField.Layout.Column = 4;

    app.FetchProjectsButton = uibutton(rg, 'Text', Labels.get('welcome_btn_fetch_projects'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onFetchProjects());
    app.FetchProjectsButton.Layout.Row = 2; app.FetchProjectsButton.Layout.Column = [1 4];
    app.styleBtn(app.FetchProjectsButton, 'secondary');
    app.FetchProjectsButton.Tooltip = 'GET /api/admin/projects?skip=…&limit=…';

    app.UserInfoArea = uitextarea(rg, 'Editable', 'off');
    app.UserInfoArea.Value = {Labels.get('welcome_user_info_hint')};
    app.UserInfoArea.Layout.Row = 3; app.UserInfoArea.Layout.Column = [1 4];
    app.UserInfoArea.FontSize = 12;

    app.ProjectsTable = uitable(rg);
    app.ProjectsTable.ColumnName = Labels.cols('welcome_table_cols_projects', ...
        {'project_id','name','owner_username','member_count','created_at','description'});
    app.ProjectsTable.Data = {};
    app.ProjectsTable.Layout.Row = 4; app.ProjectsTable.Layout.Column = [1 4];
    app.styleTable(app.ProjectsTable);
    app.ProjectsTable.SelectionChangedFcn = @(src,~)app.WelcomeVm.onProjectTableSelect(src);

    Logger.info('WelcomeScreen', 'Welcome tab UI built successfully');
end
