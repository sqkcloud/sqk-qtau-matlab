% DetailedAnalysisTab  Populates the Detailed Analysis section panel.
%
%   Layout:
%     Row 1 (toolbar, 44 px):  Refresh Compare | Refresh Temporal | Refresh Qubit
%                              + Next: Reports (right-pinned).
%     Row 2 ('1.3x'):          Compare bar chart (left) | Temporal line chart (right).
%     Row 3 ('0.9x'):          Per-Qubit stem chart (left) | Interpretation Notes (right).
%
%   All visible strings come from resources/labels.properties via Labels.
function DetailedAnalysisScreen(app)
    Logger.info('DetailedAnalysisScreen', 'Building Detailed Analysis tab UI');
    t = app.createSectionPage('Detailed Analysis');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {34, '1.3x', '0.9x'};
    g.ColumnWidth   = {'1x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Toolbar ──────────────────────────────────────────────────────────────
    toolbar = uigridlayout(g, [1 2]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {'1x', 150};
    toolbar.Padding = [0 0 0 0];
    toolbar.BackgroundColor = [0.96 0.97 0.99];

    leftBtns = uigridlayout(toolbar, [1 3]);
    leftBtns.Layout.Row = 1; leftBtns.Layout.Column = 1;
    leftBtns.ColumnWidth = {110, 110, 100};
    leftBtns.Padding = [0 0 0 0]; leftBtns.ColumnSpacing = 8;
    leftBtns.BackgroundColor = [0.96 0.97 0.99];

    app.RefreshCompareButton = uibutton(leftBtns, 'Text', [char(8635) ' ' Labels.get('detailed_btn_refresh_compare')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotComparison());
    app.RefreshCompareButton.Layout.Row = 1; app.RefreshCompareButton.Layout.Column = 1;
    app.styleBtn(app.RefreshCompareButton, 'ghost');
    app.RefreshCompareButton.FontSize = 14;
    app.RefreshCompareButton.Tooltip = 'GET /jobs/{id}/results/detailed — distribution comparison';

    app.RefreshTemporalButton = uibutton(leftBtns, 'Text', [char(8635) ' ' Labels.get('detailed_btn_refresh_temporal')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotTemporal());
    app.RefreshTemporalButton.Layout.Row = 1; app.RefreshTemporalButton.Layout.Column = 2;
    app.styleBtn(app.RefreshTemporalButton, 'ghost');
    app.RefreshTemporalButton.FontSize = 14;
    app.RefreshTemporalButton.Tooltip = 'GET /jobs/{id}/error-trends — temporal stability';

    app.RefreshQubitButton = uibutton(leftBtns, 'Text', [char(8635) ' ' Labels.get('detailed_btn_refresh_qubit')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotQubit());
    app.RefreshQubitButton.Layout.Row = 1; app.RefreshQubitButton.Layout.Column = 3;
    app.styleBtn(app.RefreshQubitButton, 'ghost');
    app.RefreshQubitButton.FontSize = 14;
    app.RefreshQubitButton.Tooltip = 'GET /jobs/{id}/results/detailed — per-qubit fidelity';

    tmp = uibutton(toolbar, 'Text', Labels.get('detailed_btn_next'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Reports'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2;
    app.styleBtn(tmp, 'primary');

    % ── Column divider (rows 2-3) ─────────────────────────────────────────────
    div = uipanel(g, 'Title', '');
    div.Layout.Row = [2 3]; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Measured vs Ideal Distribution bar chart (left, row 2) ───────────────
    comparePanel = uipanel(g, 'Title', Labels.get('detailed_panel_compare'));
    comparePanel.Layout.Row = 2; comparePanel.Layout.Column = 1;
    comparePanel.BackgroundColor = [1 1 1];
    cpg = uigridlayout(comparePanel, [1 1]);
    cpg.Padding = [10 10 10 10]; cpg.BackgroundColor = [1 1 1];
    app.CompareAxes = uiaxes(cpg);
    x = 1:10; y1 = 0.76+0.04*randn(1,10); y2 = 0.80+0.03*randn(1,10);
    bar(app.CompareAxes, x, [y1' y2'], 'grouped');
    legend(app.CompareAxes, {'Measured','Ideal'}, 'Location', 'northeast');
    app.styleAxes(app.CompareAxes);
    app.CompareAxes.Title.String = Labels.get('detailed_plot_compare_title');

    % ── Per-Qubit Readout Fidelity stem chart (left, row 3) ──────────────────
    qubitPanel = uipanel(g, 'Title', Labels.get('detailed_panel_qubit'));
    qubitPanel.Layout.Row = 3; qubitPanel.Layout.Column = 1;
    qubitPanel.BackgroundColor = [1 1 1];
    qpg = uigridlayout(qubitPanel, [1 1]);
    qpg.Padding = [10 10 10 10]; qpg.BackgroundColor = [1 1 1];
    app.QubitAxes = uiaxes(qpg);
    q = 1:27; fid = 0.98 - 0.02*rand(1,27);
    stem(app.QubitAxes, q, fid, 'filled', 'Color', [0.18 0.45 0.82], 'LineWidth', 1.4);
    app.QubitAxes.YLim = [0.90 1.00];
    app.styleAxes(app.QubitAxes);
    app.QubitAxes.Title.String  = Labels.get('detailed_plot_qubit_title');
    app.QubitAxes.XLabel.String = Labels.get('detailed_plot_x_qubit');

    % ── Temporal Stability line chart (right, row 2) ──────────────────────────
    temporalPanel = uipanel(g, 'Title', Labels.get('detailed_panel_temporal'));
    temporalPanel.Layout.Row = 2; temporalPanel.Layout.Column = 3;
    temporalPanel.BackgroundColor = [1 1 1];
    tpg = uigridlayout(temporalPanel, [1 1]);
    tpg.Padding = [10 10 10 10]; tpg.BackgroundColor = [1 1 1];
    app.TemporalAxes = uiaxes(tpg);
    t2 = 1:40; conf = 0.94+0.02*randn(1,40);
    plot(app.TemporalAxes, t2, conf, '-o', 'Color', [0.10 0.54 0.36], ...
        'LineWidth', 1.6, 'MarkerSize', 3);
    yline(app.TemporalAxes, 0.94, '--', 'Color', [0.62 0.38 0.82], 'LineWidth', 1.2);
    app.styleAxes(app.TemporalAxes);
    app.TemporalAxes.Title.String  = Labels.get('detailed_plot_temporal_title');
    app.TemporalAxes.XLabel.String = Labels.get('detailed_plot_x_batch');

    % ── Interpretation Notes (right, row 3) ───────────────────────────────────
    insightPanel = uipanel(g, 'Title', Labels.get('detailed_panel_insight'));
    insightPanel.Layout.Row = 3; insightPanel.Layout.Column = 3;
    insightPanel.BackgroundColor = [1 1 1];
    ipg = uigridlayout(insightPanel, [1 1]);
    ipg.Padding = [14 12 14 12]; ipg.BackgroundColor = [1 1 1];
    app.DetailedInsightArea = uitextarea(ipg, 'Editable', 'off'); app.DetailedInsightArea.FontSize = 13;
    app.DetailedInsightArea.Value = { ...
        'Press the Refresh buttons above to load live data.', ...
        '', ...
        'Interpretation will show after data loads:', ...
        '- Temporal confidence trend', ...
        '- Per-qubit fidelity outliers', ...
        '- Distribution overlap vs ideal'};

    Logger.info('DetailedAnalysisScreen', 'Detailed Analysis tab UI built successfully');
end
