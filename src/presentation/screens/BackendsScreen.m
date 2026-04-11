% BackendsScreen  Populates the Backends section panel.
%
%   Layout:
%     Row 1 (118 px):  Backend Explorer hero card with 4 live KPI cards.
%     Row 2 ('1x'):    Available Backends table (left) | Calibration notes (right).
%     Row 3 (72 px):   Action bar with navigation buttons.
%
%   All visible strings come from resources/labels.properties via Labels.
function BackendsScreen(app)
    Logger.info('BackendsScreen', 'Building Backends tab UI');
    t = app.createSectionPage('Backends');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {118, '1x', 72};
    g.ColumnWidth   = {'1.3x', 6, '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Backend KPI cards (full width) ────────────────────────────────────────
    cards = uipanel(g, 'Title', Labels.get('backends_panel_explorer'));
    cards.Layout.Row = 1; cards.Layout.Column = [1 3]; cards.BackgroundColor = Theme.COLOR_CARD;

    cg = uigridlayout(cards, [2 4]);
    cg.RowHeight = {26,'1x'};
    cg.ColumnWidth = {'1x','1x','1x','1x'};
    cg.Padding = [16 12 16 12]; cg.BackgroundColor = Theme.COLOR_CARD;

    ttl = uilabel(cg, 'Text', Labels.get('backends_hero_title'));
    ttl.FontSize = 15; ttl.FontWeight = 'bold'; ttl.Layout.Row = 1; ttl.Layout.Column = [1 4]; ttl.WordWrap = 'on';

    cardNames   = { ...
        Labels.get('backends_kpi_recommended_primary', 'Recommended Primary'), ...
        Labels.get('backends_kpi_recommended_backup',  'Recommended Backup'), ...
        Labels.get('backends_kpi_best_fidelity',       'Best Predicted Fidelity'), ...
        Labels.get('backends_kpi_cal_age',             'Current Calibration Age')};
    cardDefault = {'—','—','—','—'};
    cardAccents = {[0.18 0.45 0.82],[0.28 0.48 0.72],[0.10 0.54 0.36],[0.62 0.38 0.82]};

    app.BackendKpiLabels = cell(1, 4);
    for i = 1:4
        p = uipanel(cg, 'Title', ''); p.Layout.Row = 2; p.Layout.Column = i;
        p.BackgroundColor = Theme.COLOR_BG;
        pg = uigridlayout(p, [1 2]); pg.ColumnWidth = {5,'1x'}; pg.Padding = [0 0 0 0];
        pg.ColumnSpacing = 0; pg.BackgroundColor = Theme.COLOR_BG;
        strip = uipanel(pg, 'Title', ''); strip.Layout.Row = 1; strip.Layout.Column = 1;
        strip.BackgroundColor = cardAccents{i};
        inner = uigridlayout(pg, [2 1]); inner.Layout.Row = 1; inner.Layout.Column = 2;
        inner.RowHeight = {18,'1x'}; inner.Padding = [8 8 8 8]; inner.BackgroundColor = Theme.COLOR_BG;
        l1 = uilabel(inner, 'Text', cardNames{i}, 'FontColor', Theme.COLOR_MUTED, 'FontSize', 11);
        l1.Layout.Row = 1; l1.Layout.Column = 1;
        l2 = uilabel(inner, 'Text', cardDefault{i}, 'FontWeight', 'bold', 'FontSize', 17, 'WordWrap', 'on');
        l2.Layout.Row = 2; l2.Layout.Column = 1;
        app.BackendKpiLabels{i} = l2;
    end

    % ── Column divider ────────────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = Theme.COLOR_DIVIDER; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Available Backends table (left) ──────────────────────────────────────
    tablePanel = uipanel(g, 'Title', Labels.get('backends_panel_table'));
    tablePanel.Layout.Row = 2; tablePanel.Layout.Column = 1; tablePanel.BackgroundColor = Theme.COLOR_CARD;

    tg = uigridlayout(tablePanel, [3 1]);
    tg.RowHeight = {34, '1x', 34}; tg.Padding = [12 10 12 10]; tg.RowSpacing = 6;
    tg.BackgroundColor = Theme.COLOR_CARD;

    % Toolbar row: Search + Refresh + Select (all on one line)
    top = uigridlayout(tg, [1 4]);
    top.ColumnWidth = {'1x', 90, 110, 110}; top.Padding = [0 0 0 0]; top.ColumnSpacing = 6;
    top.BackgroundColor = Theme.COLOR_CARD;

    % Search field
    app.BackendsSearchField = uieditfield(top, 'text', ...
        'Placeholder', 'Search by name, status, role...', ...
        'ValueChangedFcn', @(src,~)app.BackendsVm.onSearch(src.Value));
    app.BackendsSearchField.Layout.Row = 1; app.BackendsSearchField.Layout.Column = 1;
    app.BackendsSearchField.FontSize = 12;

    % Search button (char(8981) — same as Circuits)
    searchBtn = uibutton(top, 'Text', [char(8981) ' Search'], ...
        'ButtonPushedFcn', @(~,~)app.BackendsVm.onSearch(app.BackendsSearchField.Value));
    searchBtn.Layout.Row = 1; searchBtn.Layout.Column = 2;
    app.styleBtn(searchBtn, 'ghost');

    % Refresh button (char(8635) — same as Dashboard, Circuits, etc.)
    app.RefreshBackendsButton = uibutton(top, 'Text', [char(8635) ' ' Labels.get('backends_btn_refresh')], ...
        'ButtonPushedFcn', @(~,~)app.BackendsVm.onRefreshBackends());
    app.RefreshBackendsButton.Layout.Row = 1; app.RefreshBackendsButton.Layout.Column = 3;
    app.styleBtn(app.RefreshBackendsButton, 'ghost');
    app.RefreshBackendsButton.FontSize = 14;

    % Select button (char(9745) — check mark)
    app.SelectBackendButton = uibutton(top, 'Text', [char(9745) ' ' Labels.get('backends_btn_select')], ...
        'ButtonPushedFcn', @(~,~)app.BackendsVm.onSelectBackend());
    app.SelectBackendButton.Layout.Row = 1; app.SelectBackendButton.Layout.Column = 4;
    app.styleBtn(app.SelectBackendButton, 'primary');
    app.SelectBackendButton.FontSize = 14;
    app.SelectBackendButton.Tooltip = 'Set selected row as primary backend';

    % Table (with index column)
    app.BackendTable = uitable(tg, ...
        'ColumnName', [{''}, Labels.cols('backends_table_cols', {'Name','Qubits','Status','Pred Fidelity','Queue','Role'})], ...
        'ColumnWidth', {36, 'auto', 'auto', 'auto', 'auto', 'auto', 'auto'}, ...
        'RowName', {}, ...
        'SelectionType', 'row');
    app.BackendTable.Layout.Row = 2; app.BackendTable.Layout.Column = 1;
    app.BackendTable.Data = {};
    app.styleTable(app.BackendTable);
    addStyle(app.BackendTable, uistyle('HorizontalAlignment','center', 'FontColor', [0.55 0.55 0.55]), 'column', 1);

    % Pagination row (inside table panel, under the table)
    pagGrid = uigridlayout(tg, [1 3]);
    pagGrid.Layout.Row = 3; pagGrid.Layout.Column = 1;
    pagGrid.ColumnWidth = {80, '1x', 80}; pagGrid.Padding = [0 0 0 0]; pagGrid.ColumnSpacing = 6;
    pagGrid.BackgroundColor = Theme.COLOR_CARD;

    % Prev (char(9664) — same as Circuits)
    app.BackendsPrevBtn = uibutton(pagGrid, 'Text', [char(9664) ' Prev'], ...
        'ButtonPushedFcn', @(~,~)app.BackendsVm.onPrevPage());
    app.BackendsPrevBtn.Layout.Row = 1; app.BackendsPrevBtn.Layout.Column = 1;
    app.styleBtn(app.BackendsPrevBtn, 'ghost');
    app.BackendsPrevBtn.Enable = false;

    % Page label
    app.BackendsPageLabel = uilabel(pagGrid, 'Text', 'Page 1');
    app.BackendsPageLabel.Layout.Row = 1; app.BackendsPageLabel.Layout.Column = 2;
    app.BackendsPageLabel.HorizontalAlignment = 'center';
    app.BackendsPageLabel.FontSize = 12; app.BackendsPageLabel.FontWeight = 'bold';
    app.BackendsPageLabel.FontColor = [0.20 0.30 0.55];

    % Next (char(9654) — same as Circuits)
    app.BackendsNextBtn = uibutton(pagGrid, 'Text', ['Next ' char(9654)], ...
        'ButtonPushedFcn', @(~,~)app.BackendsVm.onNextPage());
    app.BackendsNextBtn.Layout.Row = 1; app.BackendsNextBtn.Layout.Column = 3;
    app.styleBtn(app.BackendsNextBtn, 'ghost');

    % Context menu (right-click, same pattern as Welcome/Circuits)
    app.buildBackendsPopupMenu();
    prevFcn = app.UIFigure.WindowButtonDownFcn;
    app.UIFigure.WindowButtonDownFcn = @(src, evt) handleBackendsMouseDown(app, prevFcn, src, evt);

    % ── Calibration notes (right) ─────────────────────────────────────────────
    detailPanel = uipanel(g, 'Title', Labels.get('backends_panel_notes'));
    detailPanel.Layout.Row = 2; detailPanel.Layout.Column = 3; detailPanel.BackgroundColor = Theme.COLOR_CARD;

    dg2 = uigridlayout(detailPanel, [1 1]);
    dg2.Padding = [12 10 12 10]; dg2.BackgroundColor = Theme.COLOR_CARD;
    app.BackendStatusArea = uitextarea(dg2, 'Editable', 'off'); app.BackendStatusArea.FontSize = 12;
    app.BackendStatusArea.Value = {Labels.get('backends_status_initial')};

    % ── Action bar ────────────────────────────────────────────────────────────
    nextPanel = uipanel(g, 'Title', Labels.get('backends_panel_action'));
    nextPanel.Layout.Row = 3; nextPanel.Layout.Column = [1 3];
    nextPanel.BackgroundColor = [0.94 0.97 1.00];

    ng = uigridlayout(nextPanel, [1 3]);
    ng.ColumnWidth = {'1x', 150, 150};
    ng.Padding = [14 8 14 8]; ng.BackgroundColor = [0.94 0.97 1.00];
    desc = uilabel(ng, 'Text', Labels.get('backends_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';

    % Benchmark button — uses Benchmark nav icon (char(9678) = ◎)
    tmp = uibutton(ng, 'Text', [char(9678) ' Benchmark'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Benchmark'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'primary');

    % Analysis button — uses Analysis nav icon (char(8981) = ⌕)
    tmp = uibutton(ng, 'Text', [char(8981) ' Analysis'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Analysis'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');

    Logger.info('BackendsScreen', 'Backends tab UI built successfully');
end

% ── Local helper: figure-level mouse-down handler for right-click popup ──
function handleBackendsMouseDown(app, prevFcn, src, evt)
    if ~isempty(prevFcn)
        try prevFcn(src, evt); catch; end
    end
    cp = app.UIFigure.CurrentPoint;
    if ~isempty(app.BackendsPopupPanel) && isvalid(app.BackendsPopupPanel) ...
            && strcmp(app.BackendsPopupPanel.Visible, 'on')
        pp = app.BackendsPopupPanel.Position;
        insidePopup = cp(1) >= pp(1) && cp(1) <= pp(1)+pp(3) && ...
                      cp(2) >= pp(2) && cp(2) <= pp(2)+pp(4);
        if insidePopup; return; end
        app.hideBackendsPopupMenu();
    end
    try; selType = app.UIFigure.SelectionType; catch; selType = 'normal'; end
    if ~strcmp(selType, 'alt'); return; end
    sel = app.BackendTable.Selection;
    if isempty(sel); return; end
    app.showBackendsPopupMenu(cp(1), cp(2));
end
