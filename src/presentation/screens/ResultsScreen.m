% ResultsScreen  Populates the Results section panel with the Tier B/C
%   visual redesign.
%
%   Layout:
%     Row 1 (66 px):   Identity strip — "Quantum Run Report" title +
%                      "<circuit> · <backend> · <shots>" subtitle +
%                      job-id/timestamp line, with a status pill on
%                      the right (and the Mitigated/Raw segmented
%                      control next to it when sibling exists).
%     Row 2 (96 px):   KPI row — 5 cards: Fidelity / Success / Dominant
%                      State / 2Q Error / Readout. Each card shows the
%                      measured value on top and the ideal (or status)
%                      sub-label below.
%     Row 3 (260 px):  Histogram (bar chart, top-5 + other, with ideal
%                      overlay) on the left; existing Distribution
%                      Review table on the right (kept for power-user
%                      drill-down).
%     Row 4 (130 px):  Three tiles — Mitigation applied / Timing
%                      breakdown / Execution context. Each tile is a
%                      key-value list reading off the response.
%     Row 5 (210 px):  Circuit Cutting Batches list (existing).
%     Row 6 (72 px):   Action bar (existing) — Refresh / View
%                      Reconstruction / Detailed Analysis / Download
%                      JSON / Generate Report / Jobs.
%
%   Legacy widgets (ResultsTable summary, ResultJsonArea, the row 1
%   panels of the previous design) are still instantiated under a
%   Visible='off' parent so the VM's renderers can keep populating
%   them; the visible UI now uses the richer KPI row / histogram /
%   tiles instead.
%
%   All visible strings come from resources/labels.properties via
%   Labels.
function ResultsScreen(app)
    Logger.info('ResultsScreen', 'Building Results tab UI (Tier B/C redesign)');
    t = app.createSectionPage('Results');

    g = uigridlayout(t, [6 1]);
    %  Row 1 (identity strip "Quantum Run Report") is collapsed to 0
    %  per operator request — the same identity info already shows on
    %  the cover page of the generated PDF, so duplicating it on the
    %  screen was wasted vertical real estate. The hero widgets are
    %  still instantiated below (so ResultsViewModel.applyHeroAndKpis
    %  and applySiblingToggle can keep writing to them without
    %  crashing) but heroPanel itself is set Visible='off' so nothing
    %  paints.
    %  Row 2 (KPI strip) is also collapsed to 0 per operator request —
    %  Fidelity / Success / Dominant State / 2Q Error / Readout values
    %  are already covered on the cover page of the generated PDF and
    %  in the Distribution Review table on row 3, so the dedicated KPI
    %  cards were duplicating information. The KPI widgets are still
    %  instantiated below (so ResultsViewModel.applyHeroAndKpis can
    %  keep writing to them without crashing) but the kpis grid itself
    %  is set Visible='off' so nothing paints.
    g.RowHeight     = {0, 0, 165, 130, 210, 72};
    g.ColumnWidth   = {'1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;
    %  All rows above use fixed pixel heights summing to ~770 px. At
    %  default window size (and especially on shorter monitors) the
    %  total exceeds the panel viewport, which would otherwise cause
    %  MATLAB to squeeze rows and clip the action bar and Cutting
    %  Batches table. Opting the grid into Scrollable='on' makes it
    %  honour the fixed heights and surface a vertical scrollbar
    %  instead. The hosting section panel is already Scrollable='on'
    %  (NavigationManager.createSectionPage), so this is the inner
    %  hand-off that engages it.
    g.Scrollable = 'on';

    % ── Row 1: Identity strip ────────────────────────────────────────────────
    heroPanel = uipanel(g, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    heroPanel.Layout.Row = 1; heroPanel.Layout.Column = 1;
    %  Hidden per operator request — see the row-1 collapse comment
    %  at the outer grid above. Visible='off' here is belt-and-braces
    %  on top of RowHeight=0 to guarantee zero rendering even on
    %  MATLAB versions where 0-height rows produce a 1-px sliver.
    heroPanel.Visible = 'off';
    %  3-col grid: title + subtitle stack (left) | status pill (mid) |
    %  Mitigated/Raw toggle (right, hidden until sibling exists).
    hg = uigridlayout(heroPanel, [1 3]);
    hg.ColumnWidth = {'1x', 130, 'fit'};
    hg.ColumnSpacing = 10; hg.Padding = [16 8 16 8];
    hg.BackgroundColor = Theme.COLOR_CARD;

    titleStack = uigridlayout(hg, [3 1]);
    titleStack.Layout.Column = 1;
    titleStack.RowHeight = {22, 18, 14};
    titleStack.RowSpacing = 0; titleStack.Padding = [0 0 0 0];
    titleStack.BackgroundColor = Theme.COLOR_CARD;

    app.ResultsHeroTitle = uilabel(titleStack, ...
        'Text', 'Quantum Run Report', ...
        'FontSize', 17, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, 'VerticalAlignment', 'bottom');
    app.ResultsHeroSubtitle = uilabel(titleStack, ...
        'Text', 'Run a job to populate this view.', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, ...
        'VerticalAlignment', 'center', 'Interpreter', 'none');
    app.ResultsHeroJobLine = uilabel(titleStack, ...
        'Text', '', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'VerticalAlignment', 'top', 'Interpreter', 'none');

    %  Status pill (mid column). Coloured uilabel — colour set by VM.
    pillWrap = uigridlayout(hg, [1 1]);
    pillWrap.Layout.Column = 2;
    pillWrap.Padding = [4 14 4 14];
    pillWrap.BackgroundColor = Theme.COLOR_CARD;
    app.ResultsStatusPill = uilabel(pillWrap, ...
        'Text', '—', 'FontSize', 12, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'BackgroundColor', Theme.COLOR_DIVIDER, ...
        'FontColor', Theme.COLOR_HEADING);

    %  Phase 4.2 Mitigated/Raw toggle — re-parented from the legacy
    %  layout into the identity strip's right column. Visibility
    %  toggled by ResultsViewModel.applySiblingToggle when the loaded
    %  batch carries a non-empty sibling_group_id.
    app.ResultsMitigationToggleGrid = uipanel(hg, ...
        'BorderType', 'none', ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'Visible', 'off');
    app.ResultsMitigationToggleGrid.Layout.Column = 3;
    tg = uigridlayout(app.ResultsMitigationToggleGrid, [1 3]);
    tg.ColumnWidth = {'fit', 110, 110};
    tg.Padding = [0 6 0 6]; tg.ColumnSpacing = 6;
    tg.BackgroundColor = Theme.COLOR_CARD;
    toggleLbl = uilabel(tg, 'Text', 'Compare:', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    toggleLbl.Layout.Column = 1;
    app.ResultsMitigatedToggleBtn = uibutton(tg, ...
        'Text', 'Mitigated', ...
        'Tooltip', ['Show the mitigated batch (operator-chosen ' ...
                    'level applied at submit time).'], ...
        'ButtonPushedFcn', @(~,~) app.ResultsVm.onMitigationToggleClicked('primary'));
    app.ResultsMitigatedToggleBtn.Layout.Column = 2;
    app.styleBtn(app.ResultsMitigatedToggleBtn, 'primary');
    app.ResultsRawToggleBtn = uibutton(tg, ...
        'Text', 'Raw (lvl 0)', ...
        'Tooltip', ['Show the raw level-0 sibling batch spawned by ' ...
                    'also_run_raw at submit time.'], ...
        'ButtonPushedFcn', @(~,~) app.ResultsVm.onMitigationToggleClicked('raw'));
    app.ResultsRawToggleBtn.Layout.Column = 3;
    app.styleBtn(app.ResultsRawToggleBtn, 'ghost');

    % ── Row 2: KPI row ───────────────────────────────────────────────────────
    %  5 cards across — each card is a coloured-strip + label-on-top +
    %  big-number-below + small ideal-subtitle pattern (mirrors the
    %  Reconstruction Summary popup's metaCard but with an extra
    %  sub-line for ideal/status).
    kpis = uigridlayout(g, [1 5]);
    kpis.Layout.Row = 2; kpis.Layout.Column = 1;
    kpis.ColumnWidth = {'1x', '1x', '1x', '1x', '1x'};
    kpis.ColumnSpacing = 10; kpis.Padding = [0 0 0 0];
    kpis.BackgroundColor = Theme.COLOR_BG;
    %  Hidden per operator request — see the row-2 collapse comment
    %  on g.RowHeight above. Visible='off' here is belt-and-braces on
    %  top of RowHeight=0 to guarantee zero rendering even on MATLAB
    %  versions where 0-height rows produce a 1-px sliver.
    kpis.Visible = 'off';

    [app.ResultsKpiFidelityVal, app.ResultsKpiFidelitySub] = ...
        localKpiCard(kpis, 1, 'FIDELITY',       Theme.COLOR_PRIMARY);
    [app.ResultsKpiSuccessVal,  app.ResultsKpiSuccessSub]  = ...
        localKpiCard(kpis, 2, 'SUCCESS PROB',   Theme.COLOR_SUCCESS);
    [app.ResultsKpiDominantVal, app.ResultsKpiDominantSub] = ...
        localKpiCard(kpis, 3, 'DOMINANT STATE', Theme.COLOR_PURPLE);
    [app.ResultsKpiTwoQVal,     app.ResultsKpiTwoQSub]     = ...
        localKpiCard(kpis, 4, '2Q ERROR',       Theme.COLOR_AMBER);
    [app.ResultsKpiReadoutVal,  app.ResultsKpiReadoutSub]  = ...
        localKpiCard(kpis, 5, 'READOUT',        Theme.COLOR_DANGER);

    % ── Row 3: Histogram + Distribution table ───────────────────────────────
    distRow = uigridlayout(g, [1 2]);
    distRow.Layout.Row = 3; distRow.Layout.Column = 1;
    distRow.ColumnWidth = {'1.5x', '1x'};
    distRow.ColumnSpacing = Theme.GRID_ROW_SPACING;
    distRow.Padding = [0 0 0 0];
    distRow.BackgroundColor = Theme.COLOR_BG;

    histPanel = uipanel(distRow, 'Title', 'Measurement distribution', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_CARD);
    histPanel.Layout.Column = 1;
    hpg = uigridlayout(histPanel, [1 1]);
    hpg.Padding = [10 8 10 8]; hpg.BackgroundColor = Theme.COLOR_CARD;
    % Lazy uiaxes — eager construction costs ~0.5–1.5 s cold-paint just
    % to host a blank chart. ResultsViewModel.paintResultsHistogram
    % promotes this label to a real uiaxes when a job's measurement
    % distribution lands.
    histPlaceholder = uilabel(hpg, ...
        'Text', 'Run a circuit to see its measurement distribution here.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.ResultsHistogramGrid        = hpg;
    app.ResultsHistogramPlaceholder = histPlaceholder;
    app.ResultsHistogramAxes        = [];

    comparePanel = uipanel(distRow, 'Title', Labels.get('results_panel_dist'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    comparePanel.Layout.Column = 2;
    cg = uigridlayout(comparePanel, [1 1]);
    cg.Padding = [12 10 12 10]; cg.BackgroundColor = Theme.COLOR_CARD;
    app.ResultsDistTable = uitable(cg);
    app.ResultsDistTable.ColumnName = ...
        Labels.cols('results_table_cols_dist', {'State','Measured','Predicted','Ideal'});
    app.ResultsDistTable.ColumnWidth = {180, 'auto', 'auto', 'auto'};
    app.ResultsDistTable.Data = {};
    app.styleTable(app.ResultsDistTable);

    % ── Row 4: Mitigation / Timing / Context tiles ──────────────────────────
    tileRow = uigridlayout(g, [1 3]);
    tileRow.Layout.Row = 4; tileRow.Layout.Column = 1;
    tileRow.ColumnWidth = {'1x', '1x', '1x'};
    tileRow.ColumnSpacing = Theme.GRID_ROW_SPACING;
    tileRow.Padding = [0 0 0 0];
    tileRow.BackgroundColor = Theme.COLOR_BG;

    app.ResultsMitigationLabels = localKvTile(tileRow, 1, ...
        'Mitigation applied', ...
        {'Level','Twirling','DD','ZNE'});
    app.ResultsTimingLabels = localKvTile(tileRow, 2, ...
        'Timing', ...
        {'Queued','Run','Total'});
    app.ResultsContextLabels = localKvTile(tileRow, 3, ...
        'Execution context', ...
        {'Project','Submitted','User'});

    % ── Row 5: Circuit Cutting Batches (existing) ───────────────────────────
    cutPanel = uipanel(g, 'Title', Labels.get('results_panel_cutting_batches', ...
            'Circuit Cutting Batches'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    cutPanel.Layout.Row = 5; cutPanel.Layout.Column = 1;
    cpg = uigridlayout(cutPanel, [1 1]);
    cpg.Padding = [12 10 12 10]; cpg.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingBatchesTable = uitable(cpg);
    app.CuttingBatchesTable.ColumnName = Labels.cols( ...
        'results_table_cols_cutting_batches', ...
        {'Batch ID', 'Mode', 'k', 'Status', 'Observables', 'Created'});
    app.CuttingBatchesTable.Data = {};
    app.CuttingBatchesTable.SelectionType = 'row';
    app.CuttingBatchesTable.CellSelectionCallback = ...
        @(src, evt) app.ResultsVm.onCuttingBatchSelected(src, evt);
    app.styleTable(app.CuttingBatchesTable);

    % ── Row 6: Action bar (existing — Tier B exports already present) ──────
    bottom = uipanel(g, 'Title', Labels.get('results_panel_action'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    bottom.Layout.Row = 6; bottom.Layout.Column = 1;
    bg = uigridlayout(bottom, [1 7]);
    bg.ColumnWidth = {'1x', 110, 180, 195, 160, 130, 110};
    bg.Padding = [14 8 14 8]; bg.BackgroundColor = Theme.COLOR_CARD;
    desc = uilabel(bg, 'Text', Labels.get('results_action_msg'));
    desc.FontSize = 13; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    refreshBtn = uibutton(bg, 'Text', [char(8635) ' ' ...
            Labels.get('results_btn_refresh', 'Refresh')], ...
        'ButtonPushedFcn', @(~,~)app.ResultsVm.onRefreshResults());
    refreshBtn.Layout.Row = 1; refreshBtn.Layout.Column = 2;
    app.styleBtn(refreshBtn, 'primary');
    refreshBtn.Tooltip = 'GET /api/jobs/{id}/results';
    tmp = uibutton(bg, 'Text', [char(9986) ' ' ...
            Labels.get('results_btn_view_reconstruction', 'View Reconstruction')], ...
        'ButtonPushedFcn', @(~,~)app.ResultsVm.onViewReconstruction());
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'secondary');
    tmp = uibutton(bg, 'Text', [char(9651) ' Detailed Analysis'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Detailed Analysis'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 4; app.styleBtn(tmp, 'primary');
    app.ResultsDownloadJsonBtn = uibutton(bg, ...
        'Text', [char(8681) ' Download JSON'], ...
        'ButtonPushedFcn', @(~,~)app.ResultsVm.onDownloadJsonResults());
    app.ResultsDownloadJsonBtn.Layout.Row = 1;
    app.ResultsDownloadJsonBtn.Layout.Column = 5;
    app.styleBtn(app.ResultsDownloadJsonBtn, 'ghost');
    app.ResultsDownloadJsonBtn.Tooltip = ...
        'Save /api/jobs/{id}/results to a .json file.';
    app.ResultsGeneratePdfBtn = uibutton(bg, ...
        'Text', [char(9636) ' Generate Report'], ...                  % ▤ (BMP — char(128196) renders tofu on macOS)
        'ButtonPushedFcn', @(~,~)app.ResultsVm.onGenerateRunReport());
    app.ResultsGeneratePdfBtn.Layout.Row = 1;
    app.ResultsGeneratePdfBtn.Layout.Column = 6;
    app.styleBtn(app.ResultsGeneratePdfBtn, 'secondary');
    app.ResultsGeneratePdfBtn.Tooltip = ...
        'Open Reports with the title pre-filled for this run.';
    tmp = uibutton(bg, 'Text', [char(9635) ' Jobs'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Jobs'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 7; app.styleBtn(tmp, 'ghost');

    % ── Hidden legacy widgets ───────────────────────────────────────────────
    %  ResultsTable (4-row Measured vs Predicted summary) and
    %  ResultJsonArea (status text block) are still populated by the
    %  VM's onRefreshResultsComplete path. Kept as off-screen children
    %  so the renderers don't crash; the new KPI row + tiles supersede
    %  them visually.
    legacyHidden = uipanel(g, 'BorderType', 'none', 'Title', '', ...
        'Visible', 'off', 'BackgroundColor', Theme.COLOR_CARD);
    legacyHidden.Layout.Row = 1; legacyHidden.Layout.Column = 1;
    lhg = uigridlayout(legacyHidden, [2 1]);
    lhg.RowHeight = {'2x', '1x'}; lhg.Padding = [0 0 0 0];
    lhg.BackgroundColor = Theme.COLOR_CARD;
    app.ResultsTable = uitable(lhg);
    app.ResultsTable.ColumnName = Labels.cols( ...
        'results_table_cols_summary', ...
        {'Metric','Measured','Predicted','Ideal','Notes'});
    app.ResultsTable.Data = {};
    app.styleTable(app.ResultsTable);
    app.ResultJsonArea = uitextarea(lhg, 'Editable', 'off', 'FontSize', 12);
    app.ResultJsonArea.Value = {Labels.get('results_summary_initial')};

    Logger.info('ResultsScreen', 'Results tab UI built successfully');
end


% ── Local helpers (file-private) ──────────────────────────────────────────────
function [valLbl, subLbl] = localKpiCard(parent, col, captionText, accent)
    %  KPI tile: coloured strip + caption + big number + small sub-label.
    p = uipanel(parent, 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, 'Title', '');
    p.Layout.Row = 1; p.Layout.Column = col;

    g = uigridlayout(p, [1 2]);
    g.ColumnWidth = {6, '1x'};
    g.Padding = [0 0 0 0]; g.ColumnSpacing = 0;
    g.BackgroundColor = Theme.COLOR_CARD;

    strip = uipanel(g, 'Title', '', 'BorderType', 'none');
    strip.Layout.Column = 1;
    strip.BackgroundColor = accent;

    inner = uigridlayout(g, [3 1]);
    inner.Layout.Column = 2;
    inner.RowHeight = {16, '1x', 14};
    inner.RowSpacing = 0; inner.Padding = [12 8 12 8];
    inner.BackgroundColor = Theme.COLOR_CARD;

    uilabel(inner, 'Text', captionText, ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_MUTED);
    valLbl = uilabel(inner, 'Text', '—', ...
        'FontWeight', 'bold', 'FontSize', 22, ...
        'FontColor', Theme.COLOR_HEADING, ...
        'VerticalAlignment', 'center');
    subLbl = uilabel(inner, 'Text', '', ...
        'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, ...
        'VerticalAlignment', 'top');
end


function valLabels = localKvTile(parent, col, titleText, keys)
    %  Mitigation / Timing / Context tile: titled panel with N
    %  key-value rows. Returns a cell array of value uilabels (one per
    %  key, in the order given) so the VM can update them.
    p = uipanel(parent, 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'Title', titleText, ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_CARD);
    p.Layout.Row = 1; p.Layout.Column = col;

    n = numel(keys);
    g = uigridlayout(p, [n 2]);
    g.RowHeight = repmat({'1x'}, 1, n);
    g.ColumnWidth = {110, '1x'};
    g.Padding = [12 8 12 8]; g.RowSpacing = 2; g.ColumnSpacing = 8;
    g.BackgroundColor = Theme.COLOR_CARD;

    valLabels = cell(1, n);
    for i = 1:n
        keyLbl = uilabel(g, 'Text', sprintf('%s:', char(keys{i})), ...
            'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
            'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
        keyLbl.Layout.Row = i; keyLbl.Layout.Column = 1;
        v = uilabel(g, 'Text', '—', ...
            'FontSize', 12, 'FontColor', Theme.COLOR_HEADING, ...
            'VerticalAlignment', 'center', 'Interpreter', 'none');
        v.Layout.Row = i; v.Layout.Column = 2;
        valLabels{i} = v;
    end
end
