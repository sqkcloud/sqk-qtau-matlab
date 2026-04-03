% WelcomeTab  Populates the Welcome section panel.
%
%   Layout (single-column grid):
%     Row 1 (136 px): Hero banner — quick-start actions.
%     Row 2 ('1x'):   Recent Projects (full width) with pagination.
%
%   Server/Authentication is handled by the modal login dialog
%   (showLoginDialog in QTAUWorkbenchApp).
%   All visible strings come from resources/labels.properties via Labels.
function WelcomeScreen(app)
    Logger.info('WelcomeScreen', 'Building Welcome tab UI');
    t = app.createSectionPage('Welcome');

    % ── Root grid: 2 rows × 1 col ───────────────────────────────────────────
    g = uigridlayout(t, [2 1]);
    g.RowHeight     = {136, '1x'};
    g.ColumnWidth   = {'1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Hero banner (full width) ─────────────────────────────────────────────
    hero = uipanel(g, 'Title', Labels.get('welcome_panel_project_launch'));
    hero.Layout.Row = 1; hero.Layout.Column = 1;
    hero.BackgroundColor = [1 1 1];
    hero.FontWeight = 'bold';
    hg = uigridlayout(hero, [3 5]);
    hg.RowHeight   = {30, 24, 34};
    hg.ColumnWidth = {'1x', 110, 110, 110, 110};
    hg.Padding     = [18 14 18 14]; hg.RowSpacing = 0; hg.BackgroundColor = [1 1 1];

    titleLabel = uilabel(hg, 'Text', Labels.get('welcome_hero_title'));
    titleLabel.FontSize = 17; titleLabel.FontWeight = 'bold';
    titleLabel.Layout.Row = 1; titleLabel.Layout.Column = [1 5]; titleLabel.WordWrap = 'on';

    btn1 = uibutton(hg, 'Text', [char(10010) ' ' Labels.get('welcome_btn_new_project')]);
    btn1.Layout.Row = 3; btn1.Layout.Column = 2; app.styleBtn(btn1, 'primary');
    btn1.FontSize = 12;
    btn1.ButtonPushedFcn = @(~,~)app.WelcomeVm.onNewProject();

    btn2 = uibutton(hg, 'Text', [char(9776) ' ' Labels.get('welcome_btn_load_project')]);
    btn2.Layout.Row = 3; btn2.Layout.Column = 3; app.styleBtn(btn2, 'ghost');
    btn2.FontSize = 12;
    btn2.ButtonPushedFcn = @(~,~)app.WelcomeVm.onLoadProject();

    btn3 = uibutton(hg, 'Text', [char(8505) ' ' Labels.get('welcome_btn_documentation')]);
    btn3.Layout.Row = 3; btn3.Layout.Column = 4; app.styleBtn(btn3, 'ghost');
    btn3.FontSize = 12;
    btn3.ButtonPushedFcn = @(~,~)web('https://docs.quantum.ibm.com', '-browser');

    btn4 = uibutton(hg, 'Text', [char(9881) ' ' Labels.get('welcome_btn_ibm_account')]);
    btn4.Layout.Row = 3; btn4.Layout.Column = 5; app.styleBtn(btn4, 'secondary');
    btn4.FontSize = 12;
    btn4.ButtonPushedFcn = @(~,~)app.onSelectSection('Settings');

    % ── Recent Projects (full width) ─────────────────────────────────────────
    projPanel = uipanel(g, 'Title', Labels.get('welcome_panel_recent_projects'));
    projPanel.Layout.Row = 2; projPanel.Layout.Column = 1;
    projPanel.BackgroundColor = [1 1 1];
    projPanel.FontWeight = 'bold';

    pg = uigridlayout(projPanel, [4 1]);
    pg.RowHeight = {42, 34, '1x', 34};
    pg.ColumnWidth = {'1x'};
    pg.Padding = [16 12 16 12]; pg.RowSpacing = 8;
    pg.BackgroundColor = [1 1 1];

    % Active Project box
    activeBox = uipanel(pg, 'Title', '');
    activeBox.Layout.Row = 1; activeBox.Layout.Column = 1;
    activeBox.BackgroundColor = [0.93 0.96 1.00];
    activeBox.BorderType = 'line';
    abg = uigridlayout(activeBox, [1 2]);
    abg.ColumnWidth = {'fit', '1x'};
    abg.Padding = [12 6 12 6]; abg.ColumnSpacing = 8;
    abg.BackgroundColor = [0.93 0.96 1.00];
    activeLbl = uilabel(abg, 'Text', Labels.get('welcome_active_project_label', 'Active Project:'), ...
        'FontSize', 13, 'FontWeight', 'bold', 'FontColor', [0.13 0.33 0.73]);
    activeLbl.Layout.Row = 1; activeLbl.Layout.Column = 1;
    activeLbl.VerticalAlignment = 'center';
    app.ActiveProjectLabel = uilabel(abg, 'Text', Labels.get('welcome_active_project_none', 'None'), ...
        'FontSize', 13, 'FontColor', [0.25 0.30 0.40]);
    app.ActiveProjectLabel.Layout.Row = 1; app.ActiveProjectLabel.Layout.Column = 2;
    app.ActiveProjectLabel.VerticalAlignment = 'center';

    % Top bar: user info (full width)
    topBar = uigridlayout(pg, [1 1]);
    topBar.Layout.Row = 2; topBar.Layout.Column = 1;
    topBar.ColumnWidth = {'1x'};
    topBar.Padding = [0 0 0 0]; topBar.BackgroundColor = [1 1 1];

    app.UserInfoArea = uilabel(topBar, 'Text', Labels.get('welcome_user_info_hint'), ...
        'FontSize', 12, 'FontColor', [0.38 0.46 0.58], 'WordWrap', 'on');
    app.UserInfoArea.Layout.Row = 1; app.UserInfoArea.Layout.Column = 1;
    app.UserInfoArea.VerticalAlignment = 'center';

    % Projects table
    app.ProjectsTable = uitable(pg);
    app.ProjectsTable.ColumnName = Labels.cols('welcome_table_cols_projects', ...
        {'Project Id','Name','Member Count','Created At','Description'});
    app.ProjectsTable.Data = {};
    app.ProjectsTable.Layout.Row = 3; app.ProjectsTable.Layout.Column = 1;
    app.ProjectsTable.ColumnWidth = {180, 220, 120, 220, '1x'};
    app.styleTable(app.ProjectsTable);
    % Left-align text columns, centre numeric/date columns
    leftStyle  = uistyle('HorizontalAlignment', 'left');
    centerStyle = uistyle('HorizontalAlignment', 'center');
    addStyle(app.ProjectsTable, leftStyle,   'column', [1 2 5]);
    addStyle(app.ProjectsTable, centerStyle, 'column', [3 4]);
    app.ProjectsTable.SelectionChangedFcn = @(src,~)app.WelcomeVm.onProjectTableSelect(src);

    % Pagination bar: Prev | Page X of Y | Next
    pageBar = uigridlayout(pg, [1 3]);
    pageBar.Layout.Row = 4; pageBar.Layout.Column = 1;
    pageBar.ColumnWidth = {90, '1x', 90};
    pageBar.Padding = [0 0 0 0]; pageBar.BackgroundColor = [1 1 1];

    app.ProjectsPrevButton = uibutton(pageBar, 'Text', Labels.get('welcome_btn_prev', '< Previous'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onPrevPage());
    app.ProjectsPrevButton.Layout.Row = 1; app.ProjectsPrevButton.Layout.Column = 1;
    app.styleBtn(app.ProjectsPrevButton, 'ghost');
    app.ProjectsPrevButton.Enable = 'off';

    app.ProjectsPageLabel = uilabel(pageBar, 'Text', '', ...
        'HorizontalAlignment', 'center', 'FontSize', 12, 'FontColor', [0.38 0.46 0.58]);
    app.ProjectsPageLabel.Layout.Row = 1; app.ProjectsPageLabel.Layout.Column = 2;
    app.ProjectsPageLabel.VerticalAlignment = 'center';

    app.ProjectsNextButton = uibutton(pageBar, 'Text', Labels.get('welcome_btn_next', 'Next >'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onNextPage());
    app.ProjectsNextButton.Layout.Row = 1; app.ProjectsNextButton.Layout.Column = 3;
    app.styleBtn(app.ProjectsNextButton, 'ghost');
    app.ProjectsNextButton.Enable = 'off';

    Logger.info('WelcomeScreen', 'Welcome tab UI built successfully');
end
