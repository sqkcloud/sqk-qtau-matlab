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

    % Context menu (right-click, same pattern as Welcome/Circuits)
    app.buildBackendsPopupMenu();
    prevFcn = app.UIFigure.WindowButtonDownFcn;
    app.UIFigure.WindowButtonDownFcn = @(src, evt) handleBackendsMouseDown(app, prevFcn, src, evt);

    % ── Calibration notes (right) ─────────────────────────────────────────────
    detailPanel = uipanel(g, 'Title', Labels.get('backends_panel_notes'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    detailPanel.Layout.Row = 2; detailPanel.Layout.Column = 2; detailPanel.BackgroundColor = Theme.COLOR_CARD;

    dg2 = uigridlayout(detailPanel, [1 1]);
    dg2.Padding = [12 10 12 10]; dg2.BackgroundColor = Theme.COLOR_CARD;

    % C2.B1 — Telemetry tab strip: Overview | Per-Qubit | History.
    % Overview hosts the legacy BackendStatusArea uitextarea (kept for
    % app.setStatus back-compat). Per-Qubit hosts a color-coded heat
    % grid; History hosts three sparkline uiaxes (T1/T2/2Q error).
    telemetryTg = uitabgroup(dg2);
    telemetryTg.Layout.Row = 1; telemetryTg.Layout.Column = 1;

    tabOverview = uitab(telemetryTg, 'Title', Labels.get('backends_telemetry_overview', 'Overview'));
    tabOverview.BackgroundColor = Theme.COLOR_CARD;
    overviewGrid = uigridlayout(tabOverview, [2 1]);
    overviewGrid.RowHeight = {64, '1x'};
    overviewGrid.Padding = [12 8 12 8];
    overviewGrid.RowSpacing = 8;
    overviewGrid.BackgroundColor = Theme.COLOR_CARD;

    % KPI strip — 4 mini-cards summarising the loaded backend pool so
    % the Overview tab tells the operator something useful at a glance
    % instead of just echoing "Loaded N backend(s)".
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

    tabPerQubit = uitab(telemetryTg, 'Title', Labels.get('backends_telemetry_perqubit', 'Per-Qubit'));
    tabPerQubit.BackgroundColor = Theme.COLOR_CARD;
    % Widened from [6 16] to [6 17] so the first column can host
    % metric row labels (qubit / T1 / T2 / Gate / Readout / 2Q),
    % which were missing before — the cells were a wall of numbers
    % with no row identifier. paintTelemetryPerQubitHeatGrid in
    % BackendsViewModel fills columns 2-17 with per-qubit values.
    app.TelemetryPerQubitGrid = uigridlayout(tabPerQubit, [6 17]);
    app.TelemetryPerQubitGrid.Padding = [12 8 12 8];
    app.TelemetryPerQubitGrid.RowSpacing = 2;
    app.TelemetryPerQubitGrid.ColumnSpacing = 2;
    app.TelemetryPerQubitGrid.BackgroundColor = Theme.COLOR_CARD;

    tabHistory = uitab(telemetryTg, 'Title', Labels.get('backends_telemetry_history', 'History'));
    tabHistory.BackgroundColor = Theme.COLOR_CARD;
    historyGrid = uigridlayout(tabHistory, [3 1]);
    historyGrid.Padding = [12 8 12 8]; historyGrid.BackgroundColor = Theme.COLOR_CARD;
    historyGrid.RowSpacing = 8;
    historyTitles = { ...
        Labels.get('backends_history_t1_title', 'T1 coherence (µs)'), ...
        Labels.get('backends_history_t2_title', 'T2 coherence (µs)'), ...
        Labels.get('backends_history_2q_title', '2Q gate error')};
    app.TelemetryHistoryAxes = cell(1, 3);
    for k = 1:3
        ax = uiaxes(historyGrid);
        ax.Layout.Row = k;
        ax.Layout.Column = 1;
        ax.Toolbar.Visible = 'off';
        % Theme-aligned sparkline styling. Set on creation so the
        % panel looks intentional even before any calibration data
        % arrives — the user sees three labeled sub-charts instead
        % of three black rectangles.
        ax.Color  = Theme.COLOR_CARD;
        ax.XColor = Theme.COLOR_MUTED;
        ax.YColor = Theme.COLOR_MUTED;
        ax.GridColor     = Theme.COLOR_DIVIDER;
        ax.GridLineStyle = ':';
        ax.GridAlpha     = 0.35;
        ax.Box           = 'off';
        ax.XGrid         = 'on';
        ax.YGrid         = 'on';
        ax.Title.String  = historyTitles{k};
        ax.Title.Color   = Theme.COLOR_LABEL;
        ax.Title.FontSize = 11;
        ax.Title.FontWeight = 'bold';
        try; disableDefaultInteractivity(ax); catch; end
        app.TelemetryHistoryAxes{k} = ax;
    end

    % ── Topology tab — coupling-map graph view ───────────────────────────────
    % Lazy-loaded: when the user activates this tab, BackendsVm dispatches
    % BackendService.getTopology(...) and paints the graph. Force-directed
    % layout via MATLAB's native graph plot. Click a qubit → side panel
    % renders that qubit's calibration.
    tabTopology = uitab(telemetryTg, 'Title', Labels.get('backends_topology_tab_title'));
    tabTopology.BackgroundColor = Theme.COLOR_CARD;
    topoGrid = uigridlayout(tabTopology, [1 2]);
    topoGrid.ColumnWidth = {'1x', 240};
    topoGrid.Padding = [12 8 12 8];
    topoGrid.ColumnSpacing = 10;
    topoGrid.BackgroundColor = Theme.COLOR_CARD;

    % Lazy uiaxes — eager construction costs ~0.5–1.5 s cold-paint just
    % to host a "click a backend" placeholder. BackendsViewModel.paintTopology
    % promotes this label to a real uiaxes when topology data lands.
    topoPlaceholder = uilabel(topoGrid, ...
        'Text', Labels.get('backends_topology_no_selection'), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    topoPlaceholder.Layout.Row = 1; topoPlaceholder.Layout.Column = 1;
    app.TopologyGrid        = topoGrid;
    app.TopologyPlaceholder = topoPlaceholder;
    app.TopologyAxes        = [];

    sideGrid = uigridlayout(topoGrid, [3 1]);
    sideGrid.Layout.Row = 1; sideGrid.Layout.Column = 2;
    sideGrid.RowHeight = {'fit', 'fit', '1x'};
    sideGrid.Padding = [0 0 0 0]; sideGrid.RowSpacing = 8;
    sideGrid.BackgroundColor = Theme.COLOR_CARD;

    legendLbl = uilabel(sideGrid, ...
        'Text', Labels.get('backends_topology_legend'), ...
        'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    legendLbl.Layout.Row = 1;

    metaLbl = uilabel(sideGrid, 'Text', '', ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
    metaLbl.Layout.Row = 2;

    app.TopologyInfoLbl = uilabel(sideGrid, ...
        'Text', Labels.get('backends_topology_no_selection'), ...
        'FontSize', 11, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
    app.TopologyInfoLbl.Layout.Row = 3;
    app.TopologyInfoLbl.UserData = metaLbl;  % stash so VM can update meta line

    % Wire row selection so clicking a backend drills into its
    % Telemetry tabs. SelectionChangedFcn (NOT the legacy
    % CellSelectionChangedFcn — removed for uifigure-hosted uitable in
    % R2025b) fires on every click; onTableRowSelected is idempotent.
    app.BackendTable.SelectionChangedFcn = @(~,~) app.BackendsVm.onTableRowSelected();
    telemetryTg.SelectionChangedFcn = @(s,e) app.BackendsVm.onTelemetryTabChanged(e);

    % ── Action bar ────────────────────────────────────────────────────────────
    nextPanel = uipanel(g, 'Title', Labels.get('backends_panel_action'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    nextPanel.Layout.Row = 3; nextPanel.Layout.Column = [1 2];
    nextPanel.BackgroundColor = Theme.COLOR_ACCENT_BG;

    ng = uigridlayout(nextPanel, [1 4]);
    ng.ColumnWidth = {'1x', 220, 150, 150};
    ng.Padding = [14 8 14 8]; ng.BackgroundColor = Theme.COLOR_ACCENT_BG;
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

% ── Local helper: figure-level mouse-down handler for right-click popup ──
function handleBackendsMouseDown(app, prevFcn, src, evt)
    if ~isempty(prevFcn)
        try prevFcn(src, evt); catch; end
    end
    % Only react while the Backends panel is the active section. Prevents
    % this handler from firing when the user is on another screen and
    % previous-screen popups leaking into the current one.
    if ~isSectionVisible(app, 'Backends'); return; end
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
