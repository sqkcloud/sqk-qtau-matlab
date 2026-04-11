% DetailedAnalysisScreen  Builds the Detailed Analysis section panel.
%
%   Layout (3-row × 3-col grid, no inner divider):
%     Row 1 (toolbar, 42 px):  5 refresh buttons + Next: Reports (pinned right).
%     Row 2 ('1x'):    Distribution Bar | Cross-Qubit Error Heatmap | Temporal + Band
%     Row 3 ('0.82x'): T1/T2 Coherence Scatter | RB Decay Curve | Insight Notes
%
%   Professional quantum visualisations:
%     - Grouped bar + measurement error-bar overlays   (distribution comparison)
%     - imagesc 'hot' colourmap + colorbar              (cross-qubit error matrix)
%     - Line + ±1σ shaded fill + threshold yline        (temporal stability)
%     - Scatter coloured by readout fidelity + T2≤2T1 bound line (qubit coherence)
%     - Errorbar data + exponential fit + uncertainty band (RB decay, EPC annotation)
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

    x  = 1:10;
    y1 = 0.73 + 0.06*randn(1,10);
    y2 = 0.78 + 0.03*randn(1,10);
    b  = bar(app.CompareAxes, x, [y1' y2'], 'grouped');
    b(1).FaceColor  = [0.20 0.48 0.78]; b(1).FaceAlpha = 0.88;
    b(2).FaceColor  = [0.93 0.45 0.18]; b(2).FaceAlpha = 0.88;
    hold(app.CompareAxes, 'on');
    err = 0.018 + 0.008*rand(1,10);
    errorbar(app.CompareAxes, x - 0.18, y1, err, '.', ...
        'Color', [0.10 0.22 0.48], 'LineWidth', 1.1, 'CapSize', 3);
    hold(app.CompareAxes, 'off');
    legend(app.CompareAxes, {'Measured','Ideal'}, ...
        'Location', 'northeast', 'FontSize', 10);
    app.styleAxes(app.CompareAxes);
    app.CompareAxes.Title.String  = Labels.get('detailed_plot_compare_title');
    app.CompareAxes.XLabel.String = 'Basis state index';
    app.CompareAxes.YLabel.String = 'Probability';
    app.CompareAxes.YLim = [0 1];
    grid(app.CompareAxes, 'on');
    app.CompareAxes.GridAlpha = 0.18;

    % ── Row 2, Col 2: Cross-Qubit Error Rate Heatmap (imagesc) ───────────────
    heatmapPanel = uipanel(g, 'Title', Labels.get('detailed_panel_heatmap'));
    heatmapPanel.Layout.Row = 2; heatmapPanel.Layout.Column = 2;
    heatmapPanel.BackgroundColor = PW;
    hpg = uigridlayout(heatmapPanel, [1 1]);
    hpg.Padding = Theme.KPI_INNER_PAD; hpg.BackgroundColor = PW;
    app.ErrorHeatmapAxes = uiaxes(hpg);

    nQ     = 8;
    errMat = 0.015 * rand(nQ, nQ);
    errMat = (errMat + errMat') / 2;
    for i = 1:nQ; errMat(i,i) = 0; end
    errMat(2,3) = 0.042; errMat(3,2) = 0.042;  % stronger coupling pairs
    errMat(5,6) = 0.038; errMat(6,5) = 0.038;
    imagesc(app.ErrorHeatmapAxes, errMat);
    colormap(app.ErrorHeatmapAxes, 'hot');
    cb1 = colorbar(app.ErrorHeatmapAxes);
    cb1.Label.String  = 'Error rate';
    cb1.Label.FontSize = 10;
    app.styleAxes(app.ErrorHeatmapAxes);
    app.ErrorHeatmapAxes.Title.String  = Labels.get('detailed_plot_heatmap_title');
    app.ErrorHeatmapAxes.XLabel.String = 'Qubit index';
    app.ErrorHeatmapAxes.YLabel.String = 'Qubit index';
    app.ErrorHeatmapAxes.XTick = 1:nQ;
    app.ErrorHeatmapAxes.YTick = 1:nQ;
    app.ErrorHeatmapAxes.CLim  = [0 0.05];

    % ── Row 2, Col 3: Temporal Stability with ±1σ Confidence Band ────────────
    temporalPanel = uipanel(g, 'Title', Labels.get('detailed_panel_temporal'));
    temporalPanel.Layout.Row = 2; temporalPanel.Layout.Column = 3;
    temporalPanel.BackgroundColor = PW;
    tpg = uigridlayout(temporalPanel, [1 1]);
    tpg.Padding = Theme.KPI_INNER_PAD; tpg.BackgroundColor = PW;
    app.TemporalAxes = uiaxes(tpg);

    t2   = 1:40;
    conf = 0.940 + 0.018*randn(1,40);
    sig  = 0.012 + 0.004*rand(1,40);
    GRN  = Theme.COLOR_SUCCESS;
    fill(app.TemporalAxes, ...
        [t2 fliplr(t2)], [conf+sig fliplr(conf-sig)], ...
        GRN, 'FaceAlpha', 0.14, 'EdgeColor', 'none');
    hold(app.TemporalAxes, 'on');
    plot(app.TemporalAxes, t2, conf, '-', 'Color', GRN, 'LineWidth', 1.7);
    plot(app.TemporalAxes, t2, conf, 'o', 'Color', GRN, ...
        'MarkerSize', 3.5, 'MarkerFaceColor', GRN);
    yline(app.TemporalAxes, 0.94, '--', ...
        'Color', Theme.COLOR_PURPLE, 'LineWidth', 1.2, ...
        'Label', 'Threshold', 'LabelHorizontalAlignment', 'left');
    hold(app.TemporalAxes, 'off');
    app.styleAxes(app.TemporalAxes);
    app.TemporalAxes.Title.String  = Labels.get('detailed_plot_temporal_title');
    app.TemporalAxes.XLabel.String = Labels.get('detailed_plot_x_batch');
    app.TemporalAxes.YLabel.String = 'Confidence';
    app.TemporalAxes.YLim = [0.88 1.01];
    grid(app.TemporalAxes, 'on');
    app.TemporalAxes.GridAlpha = 0.18;

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

    nQb = 27;
    T1  = 45 + 38*rand(1,nQb);
    T2  = min(35 + 28*rand(1,nQb), 2*T1 - 3);   % physical T2 ≤ 2·T1
    fidQ = 0.955 + 0.038*rand(1,nQb);
    scatter(app.QubitAxes, T1, T2, 65, fidQ, 'filled', ...
        'MarkerEdgeColor', [0.3 0.3 0.3], 'LineWidth', 0.5);
    colormap(app.QubitAxes, 'cool');
    cb2 = colorbar(app.QubitAxes);
    cb2.Label.String  = 'Readout fidelity';
    cb2.Label.FontSize = 10;
    app.QubitAxes.CLim = [0.95 1.00];
    hold(app.QubitAxes, 'on');
    xlBound = [30 90];
    plot(app.QubitAxes, xlBound, 2*xlBound, '--', ...
        'Color', [0.85 0.33 0.10], 'LineWidth', 1.0);   % T2 = 2·T1 bound
    hold(app.QubitAxes, 'off');
    app.styleAxes(app.QubitAxes);
    app.QubitAxes.Title.String  = Labels.get('detailed_plot_qubit_title');
    app.QubitAxes.XLabel.String = 'T1 (\mus)';
    app.QubitAxes.YLabel.String = 'T2 (\mus)';
    grid(app.QubitAxes, 'on');
    app.QubitAxes.GridAlpha = 0.18;

    % ── Row 3, Col 2: Randomized Benchmarking Decay Curve ────────────────────
    rbPanel = uipanel(g, 'Title', Labels.get('detailed_panel_rb'));
    rbPanel.Layout.Row = 3; rbPanel.Layout.Column = 2;
    rbPanel.BackgroundColor = PW;
    rpg = uigridlayout(rbPanel, [1 1]);
    rpg.Padding = Theme.KPI_INNER_PAD; rpg.BackgroundColor = PW;
    app.RBDecayAxes = uiaxes(rpg);

    mPts  = [1 2 4 8 16 32 64 128 256];
    EPC   = 0.0019;  A_rb = 0.475;  B_rb = 0.500;
    pFit  = A_rb*(1-2*EPC).^mPts + B_rb;
    pMea  = pFit + 0.008*randn(size(pFit));
    pErr  = 0.007 + 0.003*rand(size(pFit));
    mDns  = 1:256;
    PURP  = Theme.COLOR_PURPLE;
    BLU   = Theme.COLOR_PRIMARY;
    hold(app.RBDecayAxes, 'on');
    fill(app.RBDecayAxes, ...
        [mDns fliplr(mDns)], ...
        [A_rb*(1-2*(EPC+0.0003)).^mDns+B_rb, ...
         fliplr(A_rb*(1-2*(EPC-0.0003)).^mDns+B_rb)], ...
        PURP, 'FaceAlpha', 0.12, 'EdgeColor', 'none');
    plot(app.RBDecayAxes, mDns, A_rb*(1-2*EPC).^mDns+B_rb, '-', ...
        'Color', PURP, 'LineWidth', 1.6);
    errorbar(app.RBDecayAxes, mPts, pMea, pErr, ...
        'o', 'Color', BLU, 'MarkerFaceColor', BLU, ...
        'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 4);
    hold(app.RBDecayAxes, 'off');
    legend(app.RBDecayAxes, {'Fit band','Fit','Data'}, ...
        'Location', 'northeast', 'FontSize', 9);
    app.styleAxes(app.RBDecayAxes);
    app.RBDecayAxes.Title.String  = sprintf('%s  —  EPC = %.4f%%', ...
        Labels.get('detailed_plot_rb_title'), EPC*100);
    app.RBDecayAxes.XLabel.String = 'Sequence length (Clifford gates)';
    app.RBDecayAxes.YLabel.String = 'Survival probability';
    grid(app.RBDecayAxes, 'on');
    app.RBDecayAxes.GridAlpha = 0.18;

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
