% DetailedAnalysisScreen  Builds the Detailed Analysis section panel.
%
%   Layout (3-row × 3-col grid, no inner divider):
%     Row 1 (toolbar, 42 px):  5 refresh buttons + Next: Reports (pinned right).
%     Row 2 ('1x'):    Distribution Bar | Cross-Qubit Error Heatmap | Temporal + Band
%     Row 3 ('0.82x'): T1/T2 Coherence Scatter | RB Decay Curve | Insight Notes
%
%   This function only builds the UI scaffolding (panels + empty axes).
%   Initial demo rendering happens in DetailedAnalysisViewModel.plotAllDemos(),
%   triggered from NavigationManager.autoLoadScreen on first entry. Refresh
%   buttons swap the demos for live API data.
%
%   All visible strings come from resources/labels.properties via Labels.
function DetailedAnalysisScreen(app)
    Logger.info('DetailedAnalysisScreen', 'Building Detailed Analysis tab UI');
    t = app.createSectionPage('Detailed Analysis');

    BG = Theme.COLOR_BG;       % page background
    PW = Theme.COLOR_CARD;     % panel white

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {42, '1x', '0.82x'};
    g.ColumnWidth   = {'1x', '1x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = 10;
    g.ColumnSpacing = 10;
    g.BackgroundColor = BG;

    % ── Toolbar (row 1, full width) ───────────────────────────────────────────
    toolbar = uigridlayout(g, [1 2]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {'1x', 148};
    toolbar.Padding     = [0 0 0 0];
    toolbar.BackgroundColor = BG;

    leftBtns = uigridlayout(toolbar, [1 5]);
    leftBtns.Layout.Row = 1; leftBtns.Layout.Column = 1;
    leftBtns.ColumnWidth = {108, 126, 108, 96, 120};
    leftBtns.Padding = [0 0 0 0]; leftBtns.ColumnSpacing = 6;
    leftBtns.BackgroundColor = BG;

    app.RefreshCompareButton = uibutton(leftBtns, ...
        'Text', [char(8635) ' ' Labels.get('detailed_btn_refresh_compare')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotComparison());
    app.RefreshCompareButton.Layout.Row = 1; app.RefreshCompareButton.Layout.Column = 1;
    app.styleBtn(app.RefreshCompareButton, 'ghost');
    app.RefreshCompareButton.FontSize = 13;
    app.RefreshCompareButton.Tooltip = 'GET /jobs/{id}/results/detailed — distribution comparison';

    app.RefreshHeatmapButton = uibutton(leftBtns, ...
        'Text', [char(8635) ' ' Labels.get('detailed_btn_refresh_heatmap')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotHeatmap());
    app.RefreshHeatmapButton.Layout.Row = 1; app.RefreshHeatmapButton.Layout.Column = 2;
    app.styleBtn(app.RefreshHeatmapButton, 'ghost');
    app.RefreshHeatmapButton.FontSize = 13;
    app.RefreshHeatmapButton.Tooltip = 'GET /jobs/{id}/results/detailed — cross-qubit error matrix';

    app.RefreshTemporalButton = uibutton(leftBtns, ...
        'Text', [char(8635) ' ' Labels.get('detailed_btn_refresh_temporal')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotTemporal());
    app.RefreshTemporalButton.Layout.Row = 1; app.RefreshTemporalButton.Layout.Column = 3;
    app.styleBtn(app.RefreshTemporalButton, 'ghost');
    app.RefreshTemporalButton.FontSize = 13;
    app.RefreshTemporalButton.Tooltip = 'GET /jobs/{id}/error-trends — temporal stability';

    app.RefreshQubitButton = uibutton(leftBtns, ...
        'Text', [char(8635) ' ' Labels.get('detailed_btn_refresh_qubit')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotQubit());
    app.RefreshQubitButton.Layout.Row = 1; app.RefreshQubitButton.Layout.Column = 4;
    app.styleBtn(app.RefreshQubitButton, 'ghost');
    app.RefreshQubitButton.FontSize = 13;
    app.RefreshQubitButton.Tooltip = 'GET /jobs/{id}/results/detailed — per-qubit T1/T2 coherence';

    app.RefreshRBButton = uibutton(leftBtns, ...
        'Text', [char(8635) ' ' Labels.get('detailed_btn_refresh_rb')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotRBDecay());
    app.RefreshRBButton.Layout.Row = 1; app.RefreshRBButton.Layout.Column = 5;
    app.styleBtn(app.RefreshRBButton, 'ghost');
    app.RefreshRBButton.FontSize = 13;
    app.RefreshRBButton.Tooltip = 'GET /jobs/{id}/rb-decay — randomized benchmarking';

    nextBtn = uibutton(toolbar, 'Text', [char(9636) ' Reports'], ...  % Reports nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Reports'));
    nextBtn.Layout.Row = 1; nextBtn.Layout.Column = 2;
    app.styleBtn(nextBtn, 'primary');

    % ═════════════════════════════════════════════════════════════════════════
    %  ROW 2 — Three tall analysis charts
    % ═════════════════════════════════════════════════════════════════════════

    % ── Row 2, Col 1: Measured vs Ideal State Distribution (bar + errorbar) ──
    comparePanel = uipanel(g, 'Title', Labels.get('detailed_panel_compare'));
    comparePanel.Layout.Row = 2; comparePanel.Layout.Column = 1;
    comparePanel.BackgroundColor = PW;
    cpg = uigridlayout(comparePanel, [1 1]);
    cpg.Padding = Theme.KPI_INNER_PAD; cpg.BackgroundColor = PW;
    app.CompareAxes = uiaxes(cpg);
    app.styleAxes(app.CompareAxes);

    % ── Row 2, Col 2: Cross-Qubit Error Rate Heatmap (imagesc) ───────────────
    heatmapPanel = uipanel(g, 'Title', Labels.get('detailed_panel_heatmap'));
    heatmapPanel.Layout.Row = 2; heatmapPanel.Layout.Column = 2;
    heatmapPanel.BackgroundColor = PW;
    hpg = uigridlayout(heatmapPanel, [1 1]);
    hpg.Padding = Theme.KPI_INNER_PAD; hpg.BackgroundColor = PW;
    app.ErrorHeatmapAxes = uiaxes(hpg);
    app.styleAxes(app.ErrorHeatmapAxes);

    % ── Row 2, Col 3: Temporal Stability with ±1σ Confidence Band ────────────
    temporalPanel = uipanel(g, 'Title', Labels.get('detailed_panel_temporal'));
    temporalPanel.Layout.Row = 2; temporalPanel.Layout.Column = 3;
    temporalPanel.BackgroundColor = PW;
    tpg = uigridlayout(temporalPanel, [1 1]);
    tpg.Padding = Theme.KPI_INNER_PAD; tpg.BackgroundColor = PW;
    app.TemporalAxes = uiaxes(tpg);
    app.styleAxes(app.TemporalAxes);

    % ═════════════════════════════════════════════════════════════════════════
    %  ROW 3 — Three moderate-height diagnostic charts
    % ═════════════════════════════════════════════════════════════════════════

    % ── Row 3, Col 1: T1 vs T2 Coherence Scatter (colour = readout fidelity) ─
    qubitPanel = uipanel(g, 'Title', Labels.get('detailed_panel_qubit'));
    qubitPanel.Layout.Row = 3; qubitPanel.Layout.Column = 1;
    qubitPanel.BackgroundColor = PW;
    qpg = uigridlayout(qubitPanel, [1 1]);
    qpg.Padding = Theme.KPI_INNER_PAD; qpg.BackgroundColor = PW;
    app.QubitAxes = uiaxes(qpg);
    app.styleAxes(app.QubitAxes);

    % ── Row 3, Col 2: Randomized Benchmarking Decay Curve ────────────────────
    rbPanel = uipanel(g, 'Title', Labels.get('detailed_panel_rb'));
    rbPanel.Layout.Row = 3; rbPanel.Layout.Column = 2;
    rbPanel.BackgroundColor = PW;
    rpg = uigridlayout(rbPanel, [1 1]);
    rpg.Padding = Theme.KPI_INNER_PAD; rpg.BackgroundColor = PW;
    app.RBDecayAxes = uiaxes(rpg);
    app.styleAxes(app.RBDecayAxes);

    % ── Row 3, Col 3: Enhanced Interpretation & Diagnostics ──────────────────
    insightPanel = uipanel(g, 'Title', Labels.get('detailed_panel_insight'));
    insightPanel.Layout.Row = 3; insightPanel.Layout.Column = 3;
    insightPanel.BackgroundColor = PW;
    ipg = uigridlayout(insightPanel, [1 1]);
    ipg.Padding = [14 12 14 12]; ipg.BackgroundColor = PW;
    app.DetailedInsightArea = uitextarea(ipg, 'Editable', 'off');
    app.DetailedInsightArea.FontSize = 12;
    app.DetailedInsightArea.Value = { ...
        'Press the Refresh buttons above to load live data.', ...
        '', ...
        'Diagnostics auto-populate after each refresh:', ...
        '', ...
        '[Compare]   KL divergence vs ideal distribution', ...
        '[Heatmap]   Max & mean cross-qubit coupling error', ...
        '[Temporal]  Drift slope · outlier count · run σ', ...
        '[Qubits]    T1/T2 outliers · readout F min/mean', ...
        '[RB Decay]  Error-per-Clifford (EPC) ± confidence', ...
        '', ...
        'Qubit colour:  cool → blue=low F, red=high F', ...
        'Heatmap:       white=0%  →  black=5% error'};

    Logger.info('DetailedAnalysisScreen', 'Detailed Analysis tab UI built successfully');
end
