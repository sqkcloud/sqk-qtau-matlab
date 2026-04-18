% CircuitsScreen  Populates the Circuits section panel.
%
%   Layout:
%     Row 1 (flex):  Circuits table — paginated list of project circuits.
%     Row 2 (48px):  Pagination bar — Prev / Page label / Next + Upload button.
%
%   All visible strings come from resources/labels.properties via Labels.
function CircuitsScreen(app)
    Logger.info('CircuitsScreen', 'Building Circuits tab UI');
    t = app.createSectionPage('Circuits');

    g = uigridlayout(t, [2 1]);
    g.RowHeight     = {'1x', 48};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = 10;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Circuits table (full width) ───────────────────────────────────────
    tablePanel = uipanel(g, 'Title', Labels.get('circuits_panel_table', 'Project Circuits'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    tablePanel.Layout.Row = 1; tablePanel.Layout.Column = 1;
    tablePanel.BackgroundColor = Theme.COLOR_CARD;

    tg = uigridlayout(tablePanel, [2 1]);
    tg.RowHeight = {32, '1x'};
    tg.Padding = Theme.KPI_INNER_PAD; tg.RowSpacing = 6; tg.BackgroundColor = Theme.COLOR_CARD;

    % Search bar
    searchGrid = uigridlayout(tg, [1 2]);
    searchGrid.Layout.Row = 1; searchGrid.Layout.Column = 1;
    searchGrid.ColumnWidth = {'1x', 90};
    searchGrid.Padding = [0 0 0 0]; searchGrid.ColumnSpacing = 6;
    searchGrid.BackgroundColor = Theme.COLOR_CARD;
    app.CircuitsSearchField = uieditfield(searchGrid, 'text', ...
        'Placeholder', 'Search by name, category, format...', ...
        'ValueChangedFcn', @(src,~)app.CircuitsVm.onSearch(src.Value));
    app.CircuitsSearchField.FontSize = 12;
    searchBtn = uibutton(searchGrid, 'Text', [char(8981) ' Search'], ...
        'ButtonPushedFcn', @(~,~)app.CircuitsVm.onSearch(app.CircuitsSearchField.Value));
    app.styleBtn(searchBtn, 'ghost');

    app.CircuitsTable = uitable(tg, ...
        'ColumnName', { ...
            '', ...
            Labels.get('circuits_col_name',     'Circuit Name'), ...
            Labels.get('circuits_col_format',   'Format'), ...
            Labels.get('circuits_col_version',  'OpenQASM'), ...
            Labels.get('circuits_col_category', 'Category'), ...
            Labels.get('circuits_col_qubits',   'Qubits'), ...
            Labels.get('circuits_col_depth',    'Depth'), ...
            Labels.get('circuits_col_created',  'Created')}, ...
        'ColumnWidth', {36, 'auto', 'auto', 'auto', 'auto', 'auto', 'auto', 'auto'}, ...
        'RowName', {}, ...
        'SelectionType', 'row', ...
        'CellSelectionCallback', @(src,evt)app.CircuitsVm.onCellSelected(src, evt));
    app.CircuitsTable.Layout.Row = 2; app.CircuitsTable.Layout.Column = 1;
    app.CircuitsTable.FontSize = 12;
    app.CircuitsTable.ColumnSortable = true;
    addStyle(app.CircuitsTable, uistyle('HorizontalAlignment','center'), 'column', 1);

    % Custom right-click popup (same pattern as Welcome/Projects)
    app.buildCircuitsPopupMenu();
    prevFcn = app.UIFigure.WindowButtonDownFcn;
    app.UIFigure.WindowButtonDownFcn = @(src, evt) handleCircuitsMouseDown(app, prevFcn, src, evt);

    % ── Pagination + Upload bar ───────────────────────────────────────────
    barPanel = uipanel(g, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER);
    barPanel.Layout.Row = 2; barPanel.Layout.Column = 1;
    barPanel.BackgroundColor = Theme.COLOR_ACCENT_BG;

    bg = uigridlayout(barPanel, [1 5]);
    bg.ColumnWidth = {'1x', 80, 90, 80, 140};
    bg.Padding = [10 4 10 4]; bg.ColumnSpacing = 8;
    bg.BackgroundColor = Theme.COLOR_ACCENT_BG;

    % Spacer
    spacer = uilabel(bg, 'Text', '');
    spacer.Layout.Row = 1; spacer.Layout.Column = 1;

    % Prev button
    app.CircuitsPrevBtn = uibutton(bg, 'Text', ...
        [char(9664) ' ' Labels.get('circuits_btn_prev', 'Prev')], ...
        'ButtonPushedFcn', @(~,~)app.CircuitsVm.onPrevPage());
    app.CircuitsPrevBtn.Layout.Row = 1; app.CircuitsPrevBtn.Layout.Column = 2;
    app.styleBtn(app.CircuitsPrevBtn, 'ghost');
    app.CircuitsPrevBtn.Enable = false;

    % Page label
    app.CircuitsPageLabel = uilabel(bg, 'Text', 'Page 1');
    app.CircuitsPageLabel.Layout.Row = 1; app.CircuitsPageLabel.Layout.Column = 3;
    app.CircuitsPageLabel.HorizontalAlignment = 'center';
    app.CircuitsPageLabel.FontSize = 13; app.CircuitsPageLabel.FontWeight = 'bold';
    app.CircuitsPageLabel.FontColor = Theme.COLOR_PRIMARY;

    % Next button
    app.CircuitsNextBtn = uibutton(bg, 'Text', ...
        [Labels.get('circuits_btn_next', 'Next') ' ' char(9654)], ...
        'ButtonPushedFcn', @(~,~)app.CircuitsVm.onNextPage());
    app.CircuitsNextBtn.Layout.Row = 1; app.CircuitsNextBtn.Layout.Column = 4;
    app.styleBtn(app.CircuitsNextBtn, 'ghost');

    % Upload button with icon
    app.CircuitsUploadBtn = uibutton(bg, 'Text', ...
        [char(8593) ' ' Labels.get('circuits_btn_upload', 'Upload')], ...
        'ButtonPushedFcn', @(~,~)app.CircuitsVm.onGoToUpload());
    app.CircuitsUploadBtn.Layout.Row = 1; app.CircuitsUploadBtn.Layout.Column = 5;
    app.styleBtn(app.CircuitsUploadBtn, 'primary');
    app.CircuitsUploadBtn.FontSize = 14;
    app.CircuitsUploadBtn.Tooltip = 'Navigate to Upload screen';

    Logger.info('CircuitsScreen', 'Circuits tab UI built successfully');
end

% ── Local helper: figure-level mouse-down handler for right-click popup ──
function handleCircuitsMouseDown(app, prevFcn, src, evt)
    % Forward to any previously registered handler first
    if ~isempty(prevFcn)
        try prevFcn(src, evt); catch; end
    end

    % Only react while the Circuits panel is the active section. Other
    % screens also chain their WindowButtonDownFcn through this one, so
    % without the guard this handler would fire on e.g. Backends clicks
    % and show the Circuits popup on top of an unrelated table.
    if ~isCircuitsSectionVisible(app); return; end

    cp = app.UIFigure.CurrentPoint;

    % If the popup is visible, only hide it when clicking OUTSIDE
    if ~isempty(app.CircuitsPopupPanel) && isvalid(app.CircuitsPopupPanel) ...
            && strcmp(app.CircuitsPopupPanel.Visible, 'on')
        pp = app.CircuitsPopupPanel.Position;
        insidePopup = cp(1) >= pp(1) && cp(1) <= pp(1)+pp(3) && ...
                      cp(2) >= pp(2) && cp(2) <= pp(2)+pp(4);
        if insidePopup
            return;  % let the button handle the click
        end
        app.hideCircuitsPopupMenu();
    end

    % Detect right-click (SelectionType == 'alt') on the circuits table
    try
        selType = app.UIFigure.SelectionType;
    catch
        selType = 'normal';
    end
    if ~strcmp(selType, 'alt'); return; end

    % Check the table has a valid selection
    sel = app.CircuitsTable.Selection;
    if isempty(sel); return; end

    % Show custom popup at the cursor position
    app.showCircuitsPopupMenu(cp(1), cp(2));
end

function tf = isCircuitsSectionVisible(app)
    tf = false;
    try
        if isstruct(app.SectionPanels) && isfield(app.SectionPanels, 'Circuits') ...
                && isvalid(app.SectionPanels.Circuits)
            tf = strcmp(app.SectionPanels.Circuits.Visible, 'on');
        end
    catch
        tf = false;
    end
end
