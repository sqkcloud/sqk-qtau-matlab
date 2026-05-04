% ResultsTab  Populates the Results section panel.
%
%   Layout:
%     Row 1 ('1x'):   Measured vs Predicted table + execution notes (left) |
%                     Distribution Review table + action notes (right).
%     Row 2 (210 px): Circuit Cutting Batches list — completed cutting batches
%                     for the current project; click-to-load reconstruction.
%     Row 3 (72 px):  Action bar — Refresh / View Reconstruction /
%                     Detailed Analysis / Jobs.
%
%   All visible strings come from resources/labels.properties via Labels.
function ResultsScreen(app)
    Logger.info('ResultsScreen', 'Building Results tab UI');
    t = app.createSectionPage('Results');

    g = uigridlayout(t, [3 2]);
    g.RowHeight     = {'1x', 210, 72};
    g.ColumnWidth   = {'1.15x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Measured vs Predicted Summary (left) ──────────────────────────────────
    summaryPanel = uipanel(g, 'Title', Labels.get('results_panel_summary'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    summaryPanel.Layout.Row = 1; summaryPanel.Layout.Column = 1; summaryPanel.BackgroundColor = Theme.COLOR_CARD;

    sg = uigridlayout(summaryPanel, [3 1]);
    %  Three-row inner grid: (1) Mitigated/Raw toggle (Phase 4.2,
    %  hidden by default — only visible when the loaded batch carries
    %  sibling_group_id), (2) summary table, (3) result-text area.
    %  The toggle row uses a fixed 32px height; when its parent panel
    %  is Visible='off' the row collapses visually so the table +
    %  textarea retain their existing 2:1 proportional split.
    sg.RowHeight = {32, '2x', '1x'};
    sg.Padding = [12 10 12 10]; sg.BackgroundColor = Theme.COLOR_CARD;

    %  Phase 4.2 — Mitigated/Raw segmented control.
    %  Two buttons share a 4-column grid; ResultsViewModel toggles
    %  styles ('primary' for active / 'ghost' for inactive) and
    %  Visible on the parent panel based on the loaded batch's
    %  mitigation_role + sibling_group_id.
    app.ResultsMitigationToggleGrid = uipanel(sg, ...
        'BorderType', 'none', ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'Visible', 'off');
    app.ResultsMitigationToggleGrid.Layout.Row = 1;
    tg = uigridlayout(app.ResultsMitigationToggleGrid, [1 4]);
    tg.ColumnWidth = {'fit', 130, 130, '1x'};
    tg.Padding = [0 0 0 0]; tg.ColumnSpacing = 6;
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
        'Text', 'Raw (level 0)', ...
        'Tooltip', ['Show the raw level-0 sibling batch spawned by ' ...
                    'also_run_raw at submit time. Same circuit, ' ...
                    'no mitigation — useful for direct comparison.'], ...
        'ButtonPushedFcn', @(~,~) app.ResultsVm.onMitigationToggleClicked('raw'));
    app.ResultsRawToggleBtn.Layout.Column = 3;
    app.styleBtn(app.ResultsRawToggleBtn, 'ghost');

    app.ResultsTable = uitable(sg);
    app.ResultsTable.Layout.Row = 2;
    app.ResultsTable.ColumnName = Labels.cols('results_table_cols_summary', {'Metric','Measured','Predicted','Ideal','Notes'});
    app.ResultsTable.Data = {};
    app.styleTable(app.ResultsTable);

    app.ResultJsonArea = uitextarea(sg, 'Editable', 'off');
    app.ResultJsonArea.Layout.Row = 3; app.ResultJsonArea.FontSize = 12;
    app.ResultJsonArea.Value = {Labels.get('results_summary_initial')};

    % ── Distribution Review (right) ───────────────────────────────────────────
    comparePanel = uipanel(g, 'Title', Labels.get('results_panel_dist'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    comparePanel.Layout.Row = 1; comparePanel.Layout.Column = 2; comparePanel.BackgroundColor = Theme.COLOR_CARD;

    cg = uigridlayout(comparePanel, [2 1]);
    % Same proportional fix as the Summary panel above — the 100-px
    % fixed notes textarea was squeezing the Distribution table out
    % of view at smaller window heights.
    cg.RowHeight = {'2x','1x'}; cg.Padding = [12 10 12 10]; cg.BackgroundColor = Theme.COLOR_CARD;

    app.ResultsDistTable = uitable(cg);
    app.ResultsDistTable.ColumnName = Labels.cols('results_table_cols_dist', {'State','Measured','Predicted','Ideal'});
    % State holds bitstrings that can be 27+ chars on IBM backends;
    % the default auto width clipped them to "00000000...". Pin a
    % comfortable fixed width and let the numeric columns auto-size.
    app.ResultsDistTable.ColumnWidth = {240, 'auto', 'auto', 'auto'};
    app.ResultsDistTable.Data = {};
    app.styleTable(app.ResultsDistTable);

    notes = uitextarea(cg, 'Editable', 'off'); notes.Layout.Row = 2; notes.FontSize = 12;
    notes.Value = { ...
        'Storyboard actions:', ...
        '- Review execution summary', ...
        '- Compare measured vs ideal distributions', ...
        '- Validate against prior predictions'};

    % ── Circuit Cutting Batches (Row 2, full width) ──────────────────────────
    %  Completed cutting batches surface here so reconstructed expectation
    %  values are visible alongside regular IBM job results. Populated by
    %  ResultsViewModel.onRefreshResults via /api/cutting/batches; clicking
    %  a row loads the reconstruction summary into the ResultJsonArea
    %  textarea above.
    cutPanel = uipanel(g, 'Title', Labels.get('results_panel_cutting_batches', 'Circuit Cutting Batches'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    cutPanel.Layout.Row = 2; cutPanel.Layout.Column = [1 2];
    cutPanel.BackgroundColor = Theme.COLOR_CARD;

    cpg = uigridlayout(cutPanel, [1 1]);
    cpg.RowHeight = {'1x'}; cpg.Padding = [12 10 12 10];
    cpg.BackgroundColor = Theme.COLOR_CARD;

    app.CuttingBatchesTable = uitable(cpg);
    app.CuttingBatchesTable.ColumnName = Labels.cols('results_table_cols_cutting_batches', ...
        {'Batch ID', 'Mode', 'k', 'Status', 'Observables', 'Created'});
    app.CuttingBatchesTable.Data = {};
    app.CuttingBatchesTable.SelectionType = 'row';
    app.CuttingBatchesTable.CellSelectionCallback = ...
        @(src, evt) app.ResultsVm.onCuttingBatchSelected(src, evt);
    app.styleTable(app.CuttingBatchesTable);

    % ── Action bar ────────────────────────────────────────────────────────────
    bottom = uipanel(g, 'Title', Labels.get('results_panel_action'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    bottom.Layout.Row = 3; bottom.Layout.Column = [1 2];
    bottom.BackgroundColor = Theme.COLOR_ACCENT_BG;

    bg = uigridlayout(bottom, [1 6]);
    bg.ColumnWidth = {'1x', 110, 180, 195, 170, 110};
    bg.Padding = [14 8 14 8]; bg.BackgroundColor = Theme.COLOR_ACCENT_BG;
    desc = uilabel(bg, 'Text', Labels.get('results_action_msg'));
    desc.FontSize = 13; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    refreshBtn = uibutton(bg, 'Text', [char(8635) ' ' Labels.get('results_btn_refresh', 'Refresh')], ...
        'ButtonPushedFcn', @(~,~)app.ResultsVm.onRefreshResults());
    refreshBtn.Layout.Row = 1; refreshBtn.Layout.Column = 2;
    app.styleBtn(refreshBtn, 'primary');
    refreshBtn.Tooltip = 'GET /api/jobs/{id}/results';
    tmp = uibutton(bg, 'Text', [char(9986) ' ' Labels.get('results_btn_view_reconstruction', 'View Reconstruction')], ...
        'ButtonPushedFcn', @(~,~)app.ResultsVm.onViewReconstruction());
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'secondary');
    tmp = uibutton(bg, 'Text', [char(9651) ' Detailed Analysis'], ...  % Detailed Analysis nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Detailed Analysis'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 4; app.styleBtn(tmp, 'primary');
    % P3: Generate Report bridge — pre-fills title via Reports'
    % loadReportsList → seedReportTitle and lets the operator confirm
    % format / sections without retyping the run identity.
    tmp = uibutton(bg, 'Text', [char(128196) ' Generate Report'], ...  % 📄
        'ButtonPushedFcn', @(~,~)app.ResultsVm.onGenerateReportFromResults());
    tmp.Layout.Row = 1; tmp.Layout.Column = 5; app.styleBtn(tmp, 'secondary');
    tmp.Tooltip = 'Open Reports with the title pre-filled for the active job.';
    tmp = uibutton(bg, 'Text', [char(9635) ' Jobs'], ...  % Jobs nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Jobs'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 6; app.styleBtn(tmp, 'ghost');

    Logger.info('ResultsScreen', 'Results tab UI built successfully');
end
