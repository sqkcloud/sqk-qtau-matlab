% buildWelcomeTab  Populates the Welcome section panel.
%
%   Layout (3-column grid):
%     Row 1: Hero banner spanning all 3 columns — quick-start actions.
%     Row 2, Col 1: Server / Authentication form (URL, credentials, login).
%     Row 2, Col 2: 6 px resizable column divider.
%     Row 2, Col 3: Recent Projects table with pagination controls.
%
%   The hero banner gives immediate orientation; the two-column lower area
%   mirrors Google Workspace's "setup + recent work" landing pattern.
function buildWelcomeTab(app)
    % Create the section panel container (scrollable, fills ContentContainer).
    t = app.createSectionPage('Welcome');

    % ── Root grid: 2 rows × 3 cols (left | divider | right) ─────────────────
    g = uigridlayout(t, [2 3]);
    g.RowHeight     = {136, '1x'};      % hero bar fixed height; panels fill remainder
    g.ColumnWidth   = {'1.15x', 6, '1x'};  % left wider; centre is the 6 px divider
    g.Padding       = [16 16 16 16];    % 16 px outer margin on all sides (8-pt grid)
    g.RowSpacing    = 12;               % breathing room between hero and panels
    g.ColumnSpacing = 4;                % tight gap around the divider
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Hero banner — spans full width ───────────────────────────────────────
    hero = uipanel(g, 'Title', 'Project Launch');
    hero.Layout.Row    = 1;
    hero.Layout.Column = [1 3];         % span all three columns
    hero.BackgroundColor = [1 1 1];
    hg = uigridlayout(hero, [2 4]);
    hg.RowHeight   = {30, '1x'};
    hg.ColumnWidth = {'1x','1x','1x','1x'};
    hg.Padding     = [18 14 18 14];     % generous horizontal padding for breathing room
    hg.BackgroundColor = [1 1 1];

    % Descriptive tagline at the top of the hero
    titleLabel = uilabel(hg, 'Text', ...
        'Start fresh, resume work, or configure your IBM Quantum connection');
    titleLabel.FontSize = 17; titleLabel.FontWeight = 'bold';
    titleLabel.Layout.Row = 1; titleLabel.Layout.Column = [1 4]; titleLabel.WordWrap = 'on';

    % Quick-action buttons across the bottom row of the hero
    btn1 = uibutton(hg, 'Text', 'New Project');
    btn1.Layout.Row = 2; btn1.Layout.Column = 1; app.styleBtn(btn1, 'primary');
    btn2 = uibutton(hg, 'Text', 'Load Project');
    btn2.Layout.Row = 2; btn2.Layout.Column = 2; app.styleBtn(btn2, 'ghost');
    btn3 = uibutton(hg, 'Text', 'Documentation');
    btn3.Layout.Row = 2; btn3.Layout.Column = 3; app.styleBtn(btn3, 'ghost');
    btn4 = uibutton(hg, 'Text', 'IBM Account Setup');
    btn4.Layout.Row = 2; btn4.Layout.Column = 4; app.styleBtn(btn4, 'secondary');

    % ── Column divider — drag to resize left vs right panel width ────────────
    div = uipanel(g, 'Title', '');
    div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93];     % subtle neutral strip
    div.BorderType = 'none';
    app.attachColumnDivider(div, g);             % registers drag-to-resize behaviour

    % ── Server / Authentication (left panel) ─────────────────────────────────
    left = uipanel(g, 'Title', 'Server / Authentication');
    left.Layout.Row = 2; left.Layout.Column = 1; left.BackgroundColor = [1 1 1];
    lg = uigridlayout(left, [7 2]);
    lg.RowHeight = {36,36,36,36,36,36,'1x'};
    lg.ColumnWidth = {130,'1x'};
    lg.Padding = [16 12 16 12];         % 16 px left/right; 12 px top/bottom
    lg.RowSpacing = 8;
    lg.BackgroundColor = [1 1 1];

    % Base URL input and action buttons
    lbl = uilabel(lg,'Text','Base URL'); lbl.FontColor=[0.35 0.42 0.52]; lbl.Layout.Row=1; lbl.Layout.Column=1;
    app.BaseUrlField = uieditfield(lg,'text','Value','http://34.42.87.190:5715');
    app.BaseUrlField.Layout.Row=1; app.BaseUrlField.Layout.Column=2;
    app.BaseUrlField.Tooltip='FastAPI backend base URL';

    app.ApplyUrlButton = uibutton(lg,'Text','Apply URL','ButtonPushedFcn',@(~,~)app.onApplyUrl());
    app.ApplyUrlButton.Layout.Row=2; app.ApplyUrlButton.Layout.Column=1; app.styleBtn(app.ApplyUrlButton,'ghost');
    app.OpenApiCheckButton = uibutton(lg,'Text','OpenAPI Check','ButtonPushedFcn',@(~,~)app.onOpenApiCheck());
    app.OpenApiCheckButton.Layout.Row=2; app.OpenApiCheckButton.Layout.Column=2; app.styleBtn(app.OpenApiCheckButton,'ghost');

    % Credentials fields
    lbl = uilabel(lg,'Text','Username'); lbl.FontColor=[0.35 0.42 0.52]; lbl.Layout.Row=3; lbl.Layout.Column=1;
    app.UsernameField = uieditfield(lg,'text','Value','sqkadmin');
    app.UsernameField.Layout.Row=3; app.UsernameField.Layout.Column=2;

    lbl = uilabel(lg,'Text','Password'); lbl.FontColor=[0.35 0.42 0.52]; lbl.Layout.Row=4; lbl.Layout.Column=1;
    app.PasswordField = uieditfield(lg,'text','Value','Sqkcloud2022!');
    app.PasswordField.Layout.Row=4; app.PasswordField.Layout.Column=2;

    % Auth action buttons
    app.LoginButton = uibutton(lg,'Text','Login','ButtonPushedFcn',@(~,~)app.onLogin());
    app.LoginButton.Layout.Row=5; app.LoginButton.Layout.Column=1; app.styleBtn(app.LoginButton,'primary');
    app.MeButton = uibutton(lg,'Text','Get User Info','ButtonPushedFcn',@(~,~)app.onGetMe());
    app.MeButton.Layout.Row=5; app.MeButton.Layout.Column=2; app.styleBtn(app.MeButton,'ghost');
    app.LogoutButton = uibutton(lg,'Text','Logout','ButtonPushedFcn',@(~,~)app.onLogout());
    app.LogoutButton.Layout.Row=6; app.LogoutButton.Layout.Column=[1 2]; app.styleBtn(app.LogoutButton,'danger');

    % Status / feedback text area
    app.LoginStatusArea = uitextarea(lg,'Editable','off');
    app.LoginStatusArea.Value={'Storyboard demo mode is pre-filled with representative data.', ...
        'Use Login to switch from dummy state to live API state.'};
    app.LoginStatusArea.Layout.Row=7; app.LoginStatusArea.Layout.Column=[1 2];
    app.LoginStatusArea.FontSize=12;

    % ── Recent Projects (right panel) ────────────────────────────────────────
    right = uipanel(g, 'Title', 'Recent Projects');
    right.Layout.Row = 2; right.Layout.Column = 3; right.BackgroundColor = [1 1 1];
    rg = uigridlayout(right, [4 4]);
    rg.RowHeight={36,36,80,'1x'};
    rg.ColumnWidth={60,90,'1x','1x'};
    rg.Padding=[16 12 16 12];
    rg.RowSpacing=8;
    rg.BackgroundColor=[1 1 1];

    % Pagination controls (skip / limit)
    lbl=uilabel(rg,'Text','skip'); lbl.FontColor=[0.35 0.42 0.52]; lbl.Layout.Row=1; lbl.Layout.Column=1;
    app.SkipField=uieditfield(rg,'numeric','Value',0); app.SkipField.Layout.Row=1; app.SkipField.Layout.Column=2;
    lbl=uilabel(rg,'Text','limit'); lbl.FontColor=[0.35 0.42 0.52]; lbl.Layout.Row=1; lbl.Layout.Column=3;
    app.LimitField=uieditfield(rg,'numeric','Value',100); app.LimitField.Layout.Row=1; app.LimitField.Layout.Column=4;

    % Fetch button
    app.FetchProjectsButton=uibutton(rg,'Text','Fetch /admin/projects', ...
        'ButtonPushedFcn',@(~,~)app.onFetchProjects());
    app.FetchProjectsButton.Layout.Row=2; app.FetchProjectsButton.Layout.Column=[1 4];
    app.styleBtn(app.FetchProjectsButton,'secondary');

    % User info summary text area
    app.UserInfoArea=uitextarea(rg,'Editable','off');
    app.UserInfoArea.Value={'User: sqkadmin (Administrator)', ...
        'Workspace: sqkadmin''s project', ...
        'Default backend family: IBM heavy-hex systems'};
    app.UserInfoArea.Layout.Row=3; app.UserInfoArea.Layout.Column=[1 4];
    app.UserInfoArea.FontSize=12;

    % Projects table
    app.ProjectsTable=uitable(rg);
    app.ProjectsTable.ColumnName={'project_id','name','owner_username','member_count','created_at','description'};
    app.ProjectsTable.Data={ ...
        'cb8385d4-76d0-4a10-b7c4-19e144140441','admin''s project','admin',1,'2026-03-07','Reference system project'; ...
        '710b1a4c-d441-40f9-b50f-ae9e474c3e1d','sqkadmin''s project','sqkadmin',1,'2026-03-09','Current demo workspace'};
    app.ProjectsTable.Layout.Row=4; app.ProjectsTable.Layout.Column=[1 4];
    app.styleTable(app.ProjectsTable);
end
