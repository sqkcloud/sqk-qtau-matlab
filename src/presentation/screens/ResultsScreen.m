% ResultsTab  Populates the Results section panel.
%
%   Layout:
%     Row 1 (120 px): Results Analysis KPI cards (4 live metric cards).
%     Row 2 ('1x'):   Measured vs Predicted table + execution notes (left) |
%                     Distribution Review table + action notes (right).
%     Row 3 (72 px):  Action bar — Next: Detailed Analysis / Back: Jobs.
%
%   All visible strings come from resources/labels.properties via Labels.
function ResultsScreen(app)
    Logger.info('ResultsScreen', 'Building Results tab UI');
    t = app.createSectionPage('Results');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {120, '1x', 72};
    g.ColumnWidth   = {'1.15x', 6, '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Results KPI cards (full width, toolbar-style) ─────────────────────────
    hero = uipanel(g, 'Title', Labels.get('results_panel_hero'));
    hero.Layout.Row = 1; hero.Layout.Column = [1 3]; hero.BackgroundColor = Theme.COLOR_CARD;

    hg = uigridlayout(hero, [2 1]);
    hg.RowHeight = {34, '1x'};
    hg.Padding = [16 12 16 12]; hg.RowSpacing = 8;
    hg.BackgroundColor = Theme.COLOR_CARD;

    % Header row: title (left) + button (right)
    headerRow = uigridlayout(hg, [1 2]);
    headerRow.Layout.Row = 1; headerRow.Layout.Column = 1;
    headerRow.ColumnWidth = {'1x', 110};
    headerRow.Padding = [0 0 0 0]; headerRow.BackgroundColor = Theme.COLOR_CARD;

    titleLabel = uilabel(headerRow, 'Text', Labels.get('results_hero_title'));
    titleLabel.FontSize = 15; titleLabel.FontWeight = 'bold';
    titleLabel.Layout.Row = 1; titleLabel.Layout.Column = 1;
    titleLabel.VerticalAlignment = 'center'; titleLabel.WordWrap = 'on';

    refreshBtn = uibutton(headerRow, 'Text', [char(8635) ' ' Labels.get('results_btn_refresh')], ...
        'ButtonPushedFcn', @(~,~)app.ResultsVm.onRefreshResults());
    refreshBtn.Layout.Row = 1; refreshBtn.Layout.Column = 2;
    app.styleBtn(refreshBtn, 'primary');
    refreshBtn.FontSize = 14;
    refreshBtn.Tooltip = 'GET /api/jobs/{id}/results';

    % Cards row: 4 KPI cards
    cardsRow = uigridlayout(hg, [1 4]);
    cardsRow.Layout.Row = 2; cardsRow.Layout.Column = 1;
    cardsRow.ColumnWidth = {'1x','1x','1x','1x'};
    cardsRow.Padding = [0 0 0 0]; cardsRow.ColumnSpacing = 12;
    cardsRow.BackgroundColor = Theme.COLOR_CARD;

    cards = { ...
        Labels.get('results_kpi_measured',   'Measured fidelity'),   '—', Theme.COLOR_PRIMARY; ...
        Labels.get('results_kpi_predicted',  'Predicted fidelity'),  '—', Theme.COLOR_SUCCESS; ...
        Labels.get('results_kpi_ideal',      'Ideal overlap'),       '—', Theme.COLOR_PURPLE; ...
        Labels.get('results_kpi_validation', 'Validation status'),   '—', Theme.COLOR_AMBER};
    for i = 1:4
        p = uipanel(cardsRow, 'Title', ''); p.Layout.Row = 1; p.Layout.Column = i;
        p.BackgroundColor = Theme.COLOR_BG;
        pg = uigridlayout(p, [1 2]); pg.ColumnWidth = {5,'1x'}; pg.Padding = [0 0 0 0];
        pg.ColumnSpacing = 0; pg.BackgroundColor = Theme.COLOR_BG;
        strip = uipanel(pg, 'Title', ''); strip.Layout.Row = 1; strip.Layout.Column = 1;
        strip.BackgroundColor = cards{i,3};
        inner = uigridlayout(pg, [2 1]); inner.Layout.Row = 1; inner.Layout.Column = 2;
        inner.RowHeight = {18,'1x'}; inner.Padding = [8 8 8 8]; inner.BackgroundColor = Theme.COLOR_BG;
        l1 = uilabel(inner, 'Text', cards{i,1}, 'FontSize', 11, 'FontColor', Theme.COLOR_MUTED);
        l1.Layout.Row = 1; l1.Layout.Column = 1;
        l2 = uilabel(inner, 'Text', cards{i,2}, 'FontWeight', 'bold', 'FontSize', 17, 'WordWrap', 'on');
        l2.Layout.Row = 2; l2.Layout.Column = 1;
    end

    % ── Column divider ────────────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = Theme.COLOR_DIVIDER; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Measured vs Predicted Summary (left) ──────────────────────────────────
    summaryPanel = uipanel(g, 'Title', Labels.get('results_panel_summary'));
    summaryPanel.Layout.Row = 2; summaryPanel.Layout.Column = 1; summaryPanel.BackgroundColor = Theme.COLOR_CARD;

    sg = uigridlayout(summaryPanel, [2 1]);
    sg.RowHeight = {'1x',120}; sg.Padding = [12 10 12 10]; sg.BackgroundColor = Theme.COLOR_CARD;

    app.ResultsTable = uitable(sg);
    app.ResultsTable.ColumnName = Labels.cols('results_table_cols_summary', {'Metric','Measured','Predicted','Ideal','Notes'});
    app.ResultsTable.Data = {};
    app.styleTable(app.ResultsTable);

    app.ResultJsonArea = uitextarea(sg, 'Editable', 'off');
    app.ResultJsonArea.Layout.Row = 2; app.ResultJsonArea.FontSize = 12;
    app.ResultJsonArea.Value = {Labels.get('results_summary_initial')};

    % ── Distribution Review (right) ───────────────────────────────────────────
    comparePanel = uipanel(g, 'Title', Labels.get('results_panel_dist'));
    comparePanel.Layout.Row = 2; comparePanel.Layout.Column = 3; comparePanel.BackgroundColor = Theme.COLOR_CARD;

    cg = uigridlayout(comparePanel, [2 1]);
    cg.RowHeight = {'1x',100}; cg.Padding = [12 10 12 10]; cg.BackgroundColor = Theme.COLOR_CARD;

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

    % ── Action bar ────────────────────────────────────────────────────────────
    bottom = uipanel(g, 'Title', Labels.get('results_panel_action'));
    bottom.Layout.Row = 3; bottom.Layout.Column = [1 3];
    bottom.BackgroundColor = [0.94 0.97 1.00];

    bg = uigridlayout(bottom, [1 3]);
    bg.ColumnWidth = {'1x', 195, 150};
    bg.Padding = [14 8 14 8]; bg.BackgroundColor = [0.94 0.97 1.00];
    desc = uilabel(bg, 'Text', Labels.get('results_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(bg, 'Text', [char(9651) ' Detailed Analysis'], ...  % Detailed Analysis nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Detailed Analysis'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'primary');
    tmp = uibutton(bg, 'Text', [char(9635) ' Jobs'], ...  % Jobs nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Jobs'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');

    Logger.info('ResultsScreen', 'Results tab UI built successfully');
end
