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

    g = uigridlayout(t, [3 2]);
    g.RowHeight     = {118, '1x', 72};
    g.ColumnWidth   = {'1.3x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Backend KPI cards (full width) ────────────────────────────────────────
    cards = uipanel(g, 'Title', Labels.get('backends_panel_explorer'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    cards.Layout.Row = 1; cards.Layout.Column = [1 2]; cards.BackgroundColor = Theme.COLOR_CARD;

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
    cardAccents = {Theme.COLOR_PRIMARY,[0.28 0.48 0.72],Theme.COLOR_SUCCESS,Theme.COLOR_PURPLE};

    app.BackendKpiLabels = cell(1, 4);
    for i = 1:4
        p = uipanel(cg, 'Title', '', 'BorderType', 'line', ...
            'BorderColor', Theme.COLOR_DIVIDER);
        p.Layout.Row = 2; p.Layout.Column = i;
        p.BackgroundColor = Theme.COLOR_CARD;
        pg = uigridlayout(p, [1 2]); pg.ColumnWidth = {5,'1x'}; pg.Padding = [0 0 0 0];
        pg.ColumnSpacing = 0; pg.BackgroundColor = Theme.COLOR_CARD;
        strip = uipanel(pg, 'Title', '', 'BorderType', 'none');
        strip.Layout.Row = 1; strip.Layout.Column = 1;
        strip.BackgroundColor = cardAccents{i};
        inner = uigridlayout(pg, [2 1]); inner.Layout.Row = 1; inner.Layout.Column = 2;
        inner.RowHeight = {18,'1x'}; inner.Padding = [8 8 8 8]; inner.BackgroundColor = Theme.COLOR_CARD;
        l1 = uilabel(inner, 'Text', cardNames{i}, 'FontColor', Theme.COLOR_MUTED, 'FontSize', 11);
        l1.Layout.Row = 1; l1.Layout.Column = 1;
        l2 = uilabel(inner, 'Text', cardDefault{i}, 'FontWeight', 'bold', 'FontSize', 17, 'WordWrap', 'on');
        l2.Layout.Row = 2; l2.Layout.Column = 1;
        app.BackendKpiLabels{i} = l2;
    end

    % ── Available Backends table (left) ──────────────────────────────────────
    tablePanel = uipanel(g, 'Title', Labels.get('backends_panel_table'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    tablePanel.Layout.Row = 2; tablePanel.Layout.Column = 1; tablePanel.BackgroundColor = Theme.COLOR_CARD;

    tg = uigridlayout(tablePanel, [3 1]);
    tg.RowHeight = {34, '1x', 34}; tg.Padding = [12 10 12 10]; tg.RowSpacing = 6;
    tg.BackgroundColor = Theme.COLOR_CARD;

    % Toolbar row: Search + Refresh + Select (all on one line)
    top = uigridlayout(tg, [1 4]);
    top.ColumnWidth = {'1x', 90, 110, 110}; top.Padding = [0 0 0 0]; top.ColumnSpacing = 6;
    top.BackgroundColor = Theme.COLOR_CARD;

    % Search field — wrapped so we can SEE whether ValueChangedFcn
    % fires at all. The prior bare anonymous-function ate exceptions
    % and produced no log on Enter, making it impossible to tell from
    % outside whether the field's event reached MATLAB.
    app.BackendsSearchField = uieditfield(top, 'text', ...
        'Placeholder', 'Search by name, status, role...', ...
        'ValueChangedFcn', @(src,evt) onSearchFieldValueChanged(app, src, evt));
    app.BackendsSearchField.Layout.Row = 1; app.BackendsSearchField.Layout.Column = 1;
    app.BackendsSearchField.FontSize = 12;

    % Search button (char(8981) — same as Circuits) — wrapped for the
    % same reason as the Select button below.
    searchBtn = uibutton(top, 'Text', [char(8981) ' Search'], ...
        'ButtonPushedFcn', @(src,evt) onSearchButtonPushed(app, src, evt));
    searchBtn.Layout.Row = 1; searchBtn.Layout.Column = 2;
    app.styleBtn(searchBtn, 'ghost');

    % Refresh button (char(8635) — same as Dashboard, Circuits, etc.)
    app.RefreshBackendsButton = uibutton(top, 'Text', [char(8635) ' ' Labels.get('backends_btn_refresh')], ...
        'ButtonPushedFcn', @(src,evt) onRefreshButtonPushed(app, src, evt));
    app.RefreshBackendsButton.Layout.Row = 1; app.RefreshBackendsButton.Layout.Column = 3;
    app.styleBtn(app.RefreshBackendsButton, 'ghost');
    app.RefreshBackendsButton.FontSize = 14;

    % Select button (char(9745) — check mark)
    % Wrapped in a log-everything handler so we can SEE whether the
    % click event is reaching the screen layer at all. The previous
    % anonymous-function callback (@(~,~)app.BackendsVm.onSelectBackend())
    % silently swallowed any exception from the VM call AND produced
    % no log if the click was eaten by an overlay — making it
    % impossible to diagnose from outside.
    app.SelectBackendButton = uibutton(top, 'Text', [char(9745) ' ' Labels.get('backends_btn_select')], ...
        'ButtonPushedFcn', @(src,evt) onSelectButtonPushed(app, src, evt));
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
    % CRITICAL: disable ColumnSortable on this specific table. The
    % global StyleHelper.styleTable turns ColumnSortable=true on every
    % uitable, which in MATLAB R2025b uifigure breaks row-click
    % dispatch on tables whose Data is re-assigned (applyPage /
    % onSearch / updateRolesInTable all do this). Symptom is an
    % internal exception inside
    %   WebMWTableController.getSourceRowFromDisplayRow
    %   ("Index exceeds the number of array elements. Index must not
    %    exceed 1") followed by
    %   TableSelectionValidator.validateRowSelection
    %   ("Selection indices are out of data boundary")
    % thrown BEFORE SelectionChangedFcn / ContextMenu can fire. Net
    % result for the user: row visually highlights (CEF local paint)
    % but MATLAB never accepts the new selection; right-click menu
    % never appears; Select button operates on whatever row was
    % programmatically selected last (typically row 1). Disabling
    % sort indirection bypasses the broken SortedRowOrder path.
    app.BackendTable.ColumnSortable = false;
    addStyle(app.BackendTable, uistyle('HorizontalAlignment','center', 'FontColor', Theme.COLOR_MUTED), 'column', 1);

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
    app.BackendsPageLabel.FontColor = Theme.COLOR_PRIMARY;

    % Next (char(9654) — same as Circuits)
    app.BackendsNextBtn = uibutton(pagGrid, 'Text', ['Next ' char(9654)], ...
        'ButtonPushedFcn', @(~,~)app.BackendsVm.onNextPage());
    app.BackendsNextBtn.Layout.Row = 1; app.BackendsNextBtn.Layout.Column = 3;
    app.styleBtn(app.BackendsNextBtn, 'ghost');

    % Right-click context menu — themed uipanel popup matching the
    % visual style used across Welcome / Circuits / Reports (built
    % by PopupMenuManager.buildBackendsPopup). The figure-level
    % chained WindowButtonDownFcn that drives it is now safe to use
    % on Backends because the heavy-paint failure modes that
    % previously clobbered it are eliminated:
    %   - Per-Qubit heat grid is one uihtml (no uigridlayout DOM blast)
    %   - History / Topology uiaxes call BackendsViewModel.makeAxesInert
    %     (Interactions=[], Toolbar=[], disableDefaultInteractivity),
    %     so the R2025b axes manager no longer installs figure-wide
    %     pointer-capture hooks that overwrite WindowButtonDownFcn.
    %   - OverlayManager.showLoading defers Position=[0 0 figW figH]
    %     until immediately before Visible='on', so a zombie overlay
    %     can't sit over the figure swallowing right-clicks.
    app.buildBackendsPopupMenu();
    prevFcn = app.UIFigure.WindowButtonDownFcn;
    app.UIFigure.WindowButtonDownFcn = ...
        @(src, evt) handleBackendsMouseDown(app, prevFcn, src, evt);

    % ── Calibration notes (right) ─────────────────────────────────────────────
    detailPanel = uipanel(g, 'Title', Labels.get('backends_panel_notes'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    detailPanel.Layout.Row = 2; detailPanel.Layout.Column = 2; detailPanel.BackgroundColor = Theme.COLOR_CARD;

    dg2 = uigridlayout(detailPanel, [1 1]);
    dg2.Padding = [12 10 12 10]; dg2.BackgroundColor = Theme.COLOR_CARD;

    % Overview content rendered DIRECTLY into the panel — no
    % uitabgroup. Per-Qubit / History / Topology tabs have been
    % removed: in R2025b uifigure macOS, activating any tab in this
    % uitabgroup reproducibly broke CEF click dispatch for the rest
    % of the screen (Search / Refresh / Select / right-click /
    % sidebar nav all silently failed). The bug is independent of
    % what is painted into the tab — even after migrating Per-Qubit
    % to one uihtml and History/Topology to inline SVG, the act of
    % switching tabs alone was enough to break dispatch. Dropping
    % the uitabgroup eliminates the failure mode entirely.
    overviewGrid = uigridlayout(dg2, [2 1]);
    overviewGrid.Layout.Row = 1; overviewGrid.Layout.Column = 1;
    overviewGrid.RowHeight = {64, '1x'};
    overviewGrid.Padding = [12 8 12 8];
    overviewGrid.RowSpacing = 8;
    overviewGrid.BackgroundColor = Theme.COLOR_CARD;

    % KPI strip — 4 mini-cards summarising the loaded backend pool.
    kpiStrip = uigridlayout(overviewGrid, [1 4]);
    kpiStrip.Layout.Row = 1; kpiStrip.Layout.Column = 1;
    kpiStrip.ColumnWidth = {'1x','1x','1x','1x'};
    kpiStrip.ColumnSpacing = 6;
    kpiStrip.Padding = [0 0 0 0];
    kpiStrip.BackgroundColor = Theme.COLOR_CARD;
    kpiTitles = { ...
        Labels.get('backends_overview_kpi_total',       'Total backends'), ...
        Labels.get('backends_overview_kpi_operational', 'Operational'), ...
        Labels.get('backends_overview_kpi_top_qubits',  'Top width (qubits)'), ...
        Labels.get('backends_overview_kpi_selected',    'Selected backend')};
    app.OverviewKpiLabels = cell(1, 4);
    for kpiIdx = 1:4
        card = uipanel(kpiStrip, 'Title', '', 'BorderType', 'line', ...
            'BorderColor', Theme.COLOR_DIVIDER, ...
            'BackgroundColor', Theme.COLOR_CARD);
        card.Layout.Row = 1; card.Layout.Column = kpiIdx;
        cg = uigridlayout(card, [2 1]);
        cg.RowHeight = {16, '1x'};
        cg.Padding = [8 4 8 4];
        cg.BackgroundColor = Theme.COLOR_CARD;
        uilabel(cg, 'Text', kpiTitles{kpiIdx}, 'FontSize', 10, ...
            'FontColor', Theme.COLOR_MUTED);
        app.OverviewKpiLabels{kpiIdx} = uilabel(cg, 'Text', char(8212), ...
            'FontSize', 16, 'FontWeight', 'bold', ...
            'FontColor', Theme.COLOR_HEADING, ...
            'VerticalAlignment', 'center');
    end

    app.BackendStatusArea = uitextarea(overviewGrid, 'Editable', 'off');
    app.BackendStatusArea.Layout.Row = 2; app.BackendStatusArea.Layout.Column = 1;
    app.BackendStatusArea.FontSize = 12;
    app.BackendStatusArea.Value = {Labels.get('backends_status_initial')};

    % Wire row selection — onTableRowSelected updates KPI 4 (selected
    % backend) and refreshes the status area. No tabgroup callback
    % anymore since tabs are gone.
    app.BackendTable.SelectionChangedFcn = @(src,evt) onTableSelectionChanged(app, src, evt);

    % ── Action bar ────────────────────────────────────────────────────────────
    nextPanel = uipanel(g, 'Title', Labels.get('backends_panel_action'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    nextPanel.Layout.Row = 3; nextPanel.Layout.Column = [1 2];
    nextPanel.BackgroundColor = Theme.COLOR_CARD;

    ng = uigridlayout(nextPanel, [1 4]);
    ng.ColumnWidth = {'1x', 220, 150, 150};
    ng.Padding = [14 8 14 8]; ng.BackgroundColor = Theme.COLOR_CARD;
    desc = uilabel(ng, 'Text', Labels.get('backends_action_msg'));
    desc.FontSize = 13; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';

    % Submit to IBM pool (fan-out across IBM_BACKENDS list — char(9889) = ⚡)
    app.SubmitPoolButton = uibutton(ng, 'Text', [char(9889) ' ' Labels.get('backends_btn_submit_pool', 'Submit to IBM pool')], ...
        'ButtonPushedFcn', @(~,~)app.BackendsVm.onSubmitToPool());
    app.SubmitPoolButton.Layout.Row = 1; app.SubmitPoolButton.Layout.Column = 2;
    app.styleBtn(app.SubmitPoolButton, 'primary');
    app.SubmitPoolButton.FontSize = 14;
    app.SubmitPoolButton.Tooltip = 'Submit the current circuit concurrently to every backend in IBM_BACKENDS';

    % Benchmark button — uses Benchmark nav icon (char(9678) = ◎)
    tmp = uibutton(ng, 'Text', [char(9678) ' Benchmark'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Benchmark'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'secondary');

    % Analysis button — uses Analysis nav icon (char(8981) = ⌕)
    tmp = uibutton(ng, 'Text', [char(8981) ' Analysis'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Analysis'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 4; app.styleBtn(tmp, 'ghost');

    Logger.info('BackendsScreen', 'Backends tab UI built successfully');
end

% ── Diagnostic wrappers — every toolbar handler logs UNCONDITIONALLY
% on its first line so we can tell from the event log whether the
% click reached MATLAB at all. The bare anonymous-function form
% silently swallows any exception thrown from the VM call AND
% produces no log when the click never arrives — making it
% impossible to distinguish a dead-callback bug from a VM-side bug.

function onSearchFieldValueChanged(app, src, ~)
    try
        Logger.info('BackendsScreen', 'Search field ValueChanged: "%s"', ...
            char(string(src.Value)));
    catch; end
    try
        if isempty(app.BackendsVm) || ~isvalid(app.BackendsVm)
            Logger.error('BackendsScreen', 'SearchField: BackendsVm empty/invalid');
            return;
        end
        app.BackendsVm.onSearch(src.Value);
    catch ME
        try; Logger.error('BackendsScreen', 'SearchField handler: %s', ME.message); catch; end
    end
end

function onSearchButtonPushed(app, ~, ~)
    try; Logger.info('BackendsScreen', 'Search button pushed'); catch; end
    try
        if isempty(app.BackendsVm) || ~isvalid(app.BackendsVm)
            Logger.error('BackendsScreen', 'Search: BackendsVm empty/invalid');
            return;
        end
        app.BackendsVm.onSearch(app.BackendsSearchField.Value);
    catch ME
        try; Logger.error('BackendsScreen', 'Search handler: %s', ME.message); catch; end
    end
end

function onRefreshButtonPushed(app, ~, ~)
    try; Logger.info('BackendsScreen', 'Refresh button pushed'); catch; end
    try
        if isempty(app.BackendsVm) || ~isvalid(app.BackendsVm)
            Logger.error('BackendsScreen', 'Refresh: BackendsVm empty/invalid');
            return;
        end
        app.BackendsVm.onRefreshBackends();
    catch ME
        try; Logger.error('BackendsScreen', 'Refresh handler: %s', ME.message); catch; end
    end
end

function onTableSelectionChanged(app, src, evt)
    % Logs both the new Selection on the source and the event's
    % Selection so we can see if a) SelectionChangedFcn fires at all
    % on row click, and b) whether the property is in sync with the
    % event payload. Then dispatches to onTableRowSelected exactly
    % as before.
    try
        newSel = src.Selection;
        evtSel = [];
        try; evtSel = evt.Selection; catch; end
        Logger.info('BackendsScreen', ...
            'Table SelectionChanged — src.Selection=[%s] evt.Selection=[%s]', ...
            mat2str(newSel), mat2str(evtSel));
    catch; end
    try
        if isempty(app.BackendsVm) || ~isvalid(app.BackendsVm)
            Logger.error('BackendsScreen', 'TableSel: BackendsVm empty/invalid');
            return;
        end
        app.BackendsVm.onTableRowSelected();
    catch ME
        try; Logger.error('BackendsScreen', 'TableSel handler: %s', ME.message); catch; end
    end
end

function onSelectButtonPushed(app, ~, ~)
    % Log-everything wrapper so we can SEE that the click reached
    % MATLAB, then dispatch into the VM under a try/catch. Errors
    % thrown by the VM previously vanished into MATLAB's silent
    % ButtonPushedFcn error handler.
    try
        Logger.info('BackendsScreen', 'Select button pushed');
    catch; end
    try
        if isempty(app.BackendsVm) || ~isvalid(app.BackendsVm)
            Logger.error('BackendsScreen', 'Select: BackendsVm is empty / invalid');
            return;
        end
        app.BackendsVm.onSelectBackend();
    catch ME
        try
            Logger.error('BackendsScreen', ...
                'Select handler error: %s', ME.message);
        catch; end
    end
end

function handleBackendsMouseDown(app, prevFcn, src, evt)
    % Chained WindowButtonDownFcn — mirrors handleReportsMouseDown.
    % Forwards to any prior handler first, then reacts only when
    % Backends is the visible section and the click is a right-click
    % over a selected BackendTable row.
    if ~isempty(prevFcn); try prevFcn(src, evt); catch; end; end
    if ~isSectionVisible(app, 'Backends'); return; end
    cp = app.UIFigure.CurrentPoint;
    % Click outside an open popup → dismiss it.
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
    if isempty(app.BackendTable) || ~isvalid(app.BackendTable); return; end
    sel = app.BackendTable.Selection;
    if isempty(sel); return; end
    app.showBackendsPopupMenu(cp(1), cp(2));
end

function tf = isSectionVisible(app, key)
    tf = false;
    try
        if isstruct(app.SectionPanels) && isfield(app.SectionPanels, key) ...
                && isvalid(app.SectionPanels.(key))
            tf = strcmp(app.SectionPanels.(key).Visible, 'on');
        end
    catch
        tf = false;
    end
end

