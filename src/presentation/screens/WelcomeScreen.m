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
    g.RowHeight     = {72, '1x'};
    g.ColumnWidth   = {'1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Hero banner (full width) ─────────────────────────────────────────────
    hero = uipanel(g, 'Title', Labels.get('welcome_panel_project_launch'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    hero.Layout.Row = 1; hero.Layout.Column = 1;
    hero.BackgroundColor = Theme.COLOR_CARD;
    hg = uigridlayout(hero, [1 5]);
    hg.RowHeight   = {34};
    hg.ColumnWidth = {'1x', 110, 110, 110, 110};
    hg.Padding     = [18 10 18 10]; hg.ColumnSpacing = 8; hg.BackgroundColor = Theme.COLOR_CARD;

    titleLabel = uilabel(hg, 'Text', Labels.get('welcome_hero_title'));
    titleLabel.FontSize = 14;
    titleLabel.Layout.Row = 1; titleLabel.Layout.Column = 1;
    titleLabel.VerticalAlignment = 'center'; titleLabel.WordWrap = 'on';

    btn1 = uibutton(hg, 'Text', [char(10010) ' ' Labels.get('welcome_btn_new_project')]);
    btn1.Layout.Row = 1; btn1.Layout.Column = 2; app.styleBtn(btn1, 'primary');
    btn1.FontSize = 14;
    btn1.ButtonPushedFcn = @(~,~)app.WelcomeVm.onNewProject();

    btn2 = uibutton(hg, 'Text', [char(9776) ' ' Labels.get('welcome_btn_load_project')]);
    btn2.Layout.Row = 1; btn2.Layout.Column = 3; app.styleBtn(btn2, 'ghost');
    btn2.FontSize = 14;
    btn2.ButtonPushedFcn = @(~,~)app.WelcomeVm.onLoadProject();

    btn3 = uibutton(hg, 'Text', [char(8505) ' ' Labels.get('welcome_btn_documentation')]);
    btn3.Layout.Row = 1; btn3.Layout.Column = 4; app.styleBtn(btn3, 'ghost');
    btn3.FontSize = 14;
    btn3.ButtonPushedFcn = @(~,~)web(char(AppConfig.get('docs_url', 'https://docs.quantum.ibm.com')), '-browser');

    btn4 = uibutton(hg, 'Text', [char(9881) ' ' Labels.get('welcome_btn_ibm_account')]);
    btn4.Layout.Row = 1; btn4.Layout.Column = 5; app.styleBtn(btn4, 'secondary');
    btn4.FontSize = 14;
    btn4.ButtonPushedFcn = @(~,~)app.onSelectSection('Settings');

    % ── Recent Projects (full width) ─────────────────────────────────────────
    projPanel = uipanel(g, 'Title', Labels.get('welcome_panel_recent_projects'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    projPanel.Layout.Row = 2; projPanel.Layout.Column = 1;
    projPanel.BackgroundColor = Theme.COLOR_CARD;

    pg = uigridlayout(projPanel, [5 1]);
    pg.RowHeight = {42, 32, '1x', 34};
    pg.ColumnWidth = {'1x'};
    pg.Padding = [16 12 16 12]; pg.RowSpacing = 8;
    pg.BackgroundColor = Theme.COLOR_CARD;

    % Active Project box
    activeBox = uipanel(pg, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER);
    activeBox.Layout.Row = 1; activeBox.Layout.Column = 1;
    activeBox.BackgroundColor = Theme.COLOR_CARD;
    abg = uigridlayout(activeBox, [1 2]);
    abg.ColumnWidth = {'fit', '1x'};
    abg.Padding = [12 6 12 6]; abg.ColumnSpacing = 8;
    abg.BackgroundColor = Theme.COLOR_CARD;
    activeLbl = uilabel(abg, 'Text', Labels.get('welcome_active_project_label', 'Active Project:'), ...
        'FontSize', 13, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_PRIMARY);
    activeLbl.Layout.Row = 1; activeLbl.Layout.Column = 1;
    activeLbl.VerticalAlignment = 'center';
    app.ActiveProjectLabel = uilabel(abg, 'Text', Labels.get('welcome_active_project_none', 'None'), ...
        'FontSize', 13, 'FontColor', Theme.COLOR_HEADING);
    app.ActiveProjectLabel.Layout.Row = 1; app.ActiveProjectLabel.Layout.Column = 2;
    app.ActiveProjectLabel.VerticalAlignment = 'center';

    % Search bar
    searchGrid = uigridlayout(pg, [1 2]);
    searchGrid.Layout.Row = 2; searchGrid.Layout.Column = 1;
    searchGrid.ColumnWidth = {'1x', 90};
    searchGrid.Padding = [0 0 0 0]; searchGrid.ColumnSpacing = 6;
    searchGrid.BackgroundColor = Theme.COLOR_CARD;
    app.ProjectsSearchField = uieditfield(searchGrid, 'text', ...
        'Placeholder', 'Search by name, tags, description...', ...
        'ValueChangedFcn', @(src,~)app.WelcomeVm.onSearchProjects(src.Value));
    app.ProjectsSearchField.FontSize = 12;
    searchBtn = uibutton(searchGrid, 'Text', [char(8981) ' Search'], ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onSearchProjects(app.ProjectsSearchField.Value));
    app.styleBtn(searchBtn, 'ghost');

    % Projects table
    app.ProjectsTable = uitable(pg);
    app.ProjectsTable.ColumnName = Labels.cols('welcome_table_cols_projects', ...
        {'Name','Tags','Member Count','Created At','Description'});
    app.ProjectsTable.Data = {};
    app.ProjectsTable.Layout.Row = 3; app.ProjectsTable.Layout.Column = 1;
    app.ProjectsTable.ColumnWidth = {200, 180, 100, 200, '1x'};
    app.styleTable(app.ProjectsTable);
    % Left-align text columns, centre numeric/date columns
    leftStyle  = uistyle('HorizontalAlignment', 'left');
    centerStyle = uistyle('HorizontalAlignment', 'center');
    addStyle(app.ProjectsTable, leftStyle,   'column', [1 2 5]);
    addStyle(app.ProjectsTable, centerStyle, 'column', [3 4]);
    app.ProjectsTable.SelectionChangedFcn = @(src,~)app.WelcomeVm.onProjectTableSelect(src);

    % Custom right-click popup — built lazily, shown via figure mouse handler.
    % Wire the figure-level click handler to hide popup on outside clicks
    % and detect right-clicks (alt) on the projects table.
    app.buildProjectPopupMenu();
    prevFcn = app.UIFigure.WindowButtonDownFcn;
    LayoutBuilder.setWindowButtonDownFcnSafe(app.UIFigure, ...
        @(src, evt) handleWelcomeMouseDown(app, prevFcn, src, evt));

    % Pagination bar: Prev | Page X of Y | Next
    pageBar = uigridlayout(pg, [1 3]);
    pageBar.Layout.Row = 4; pageBar.Layout.Column = 1;
    pageBar.ColumnWidth = {90, '1x', 90};
    pageBar.Padding = [0 0 0 0]; pageBar.BackgroundColor = Theme.COLOR_CARD;

    app.ProjectsPrevButton = uibutton(pageBar, 'Text', Labels.get('welcome_btn_prev', '< Previous'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onPrevPage());
    app.ProjectsPrevButton.Layout.Row = 1; app.ProjectsPrevButton.Layout.Column = 1;
    app.styleBtn(app.ProjectsPrevButton, 'ghost');
    app.ProjectsPrevButton.Enable = 'off';

    app.ProjectsPageLabel = uilabel(pageBar, 'Text', '', ...
        'HorizontalAlignment', 'center', 'FontSize', 12, 'FontColor', Theme.COLOR_MUTED);
    app.ProjectsPageLabel.Layout.Row = 1; app.ProjectsPageLabel.Layout.Column = 2;
    app.ProjectsPageLabel.VerticalAlignment = 'center';

    app.ProjectsNextButton = uibutton(pageBar, 'Text', Labels.get('welcome_btn_next', 'Next >'), ...
        'ButtonPushedFcn', @(~,~)app.WelcomeVm.onNextPage());
    app.ProjectsNextButton.Layout.Row = 1; app.ProjectsNextButton.Layout.Column = 3;
    app.styleBtn(app.ProjectsNextButton, 'ghost');
    app.ProjectsNextButton.Enable = 'off';

    Logger.info('WelcomeScreen', 'Welcome tab UI built successfully');
end

% ── Local helper: figure-level mouse-down handler for right-click popup ──
function handleWelcomeMouseDown(app, prevFcn, src, evt)
    % Forward to any previously registered handler first
    if ~isempty(prevFcn)
        try prevFcn(src, evt); catch; end
    end

    % Only react while the Welcome panel is the active section.
    if ~isWelcomeSectionVisible(app); return; end

    cp = app.UIFigure.CurrentPoint;

    % If the popup is visible, only hide it when clicking OUTSIDE.
    % Clicking inside (on Edit/Delete buttons) must NOT hide the panel —
    % otherwise the button's ButtonPushedFcn (mouse-up) is swallowed.
    if ~isempty(app.ProjectsPopupPanel) && isvalid(app.ProjectsPopupPanel) ...
            && strcmp(app.ProjectsPopupPanel.Visible, 'on')
        pp = app.ProjectsPopupPanel.Position;
        insidePopup = cp(1) >= pp(1) && cp(1) <= pp(1)+pp(3) && ...
                      cp(2) >= pp(2) && cp(2) <= pp(2)+pp(4);
        if insidePopup
            return;  % let the button handle the click
        end
        app.hideProjectPopupMenu();
    end

    % Detect right-click (SelectionType == 'alt') on the projects table
    try
        selType = app.UIFigure.SelectionType;
    catch
        selType = 'normal';
    end
    if ~strcmp(selType, 'alt'); return; end

    % Check the table has a valid selection
    sel = app.ProjectsTable.Selection;
    if isempty(sel); return; end

    % Show custom popup at the cursor position
    app.showProjectPopupMenu(cp(1), cp(2));
end

function tf = isWelcomeSectionVisible(app)
    tf = false;
    try
        if isstruct(app.SectionPanels) && isfield(app.SectionPanels, 'Welcome') ...
                && isvalid(app.SectionPanels.Welcome)
            tf = strcmp(app.SectionPanels.Welcome.Visible, 'on');
        end
    catch
        tf = false;
    end
end
