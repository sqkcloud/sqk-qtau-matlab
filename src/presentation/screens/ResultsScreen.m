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

    sg = uigridlayout(summaryPanel, [2 1]);
    % Proportional row sizing (was '1x',120). The fixed 120-px textarea
    % squeezed the table's '1x' allocation to ~0 at smaller window
    % heights — the table headers literally fell off-screen. With
    % '2x','1x' both rows scale together: table gets 2/3, textarea
    % gets 1/3. Always visible at any window size.
    sg.RowHeight = {'2x','1x'}; sg.Padding = [12 10 12 10]; sg.BackgroundColor = Theme.COLOR_CARD;

    app.ResultsTable = uitable(sg);
    app.ResultsTable.ColumnName = Labels.cols('results_table_cols_summary', {'Metric','Measured','Predicted','Ideal','Notes'});
    app.ResultsTable.Data = {};
    app.styleTable(app.ResultsTable);

    app.ResultJsonArea = uitextarea(sg, 'Editable', 'off');
    app.ResultJsonArea.Layout.Row = 2; app.ResultJsonArea.FontSize = 12;
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

    bg = uigridlayout(bottom, [1 5]);
    bg.ColumnWidth = {'1x', 110, 180, 195, 150};
    bg.Padding = [14 8 14 8]; bg.BackgroundColor = Theme.COLOR_ACCENT_BG;
    desc = uilabel(bg, 'Text', Labels.get('results_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
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
    tmp = uibutton(bg, 'Text', [char(9635) ' Jobs'], ...  % Jobs nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Jobs'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 5; app.styleBtn(tmp, 'ghost');

    Logger.info('ResultsScreen', 'Results tab UI built successfully');
end
