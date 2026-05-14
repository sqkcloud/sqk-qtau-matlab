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

    g = uigridlayout(t, [4 3]);
    %  M3 Tier C — KPI strip lives in row 2 between the toolbar and
    %  the existing 2-row chart area. Mirrors the AnalysisScreen and
    %  ResultsScreen visual language.
    %  Row 2 (KPI strip — Fidelity / Drift / Qubits / RB Decay /
    %  Outliers) is collapsed to 0 per operator request. The KPI
    %  widgets are still instantiated below (so DetailedAnalysisVm can
    %  keep writing to them without crashing) but the kpis grid
    %  itself is set Visible='off' so nothing paints.
    g.RowHeight     = {42, 0, '1x', '0.82x'};
    g.ColumnWidth   = {'1x', '1x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = 10;
    g.ColumnSpacing = 10;
    g.BackgroundColor = BG;

    % ── Row 1: Single-row toolbar ───────────────────────────────────────────
    %   Circuit label | dropdown | Analyze | Compare | Error Matrix |
    %   Temporal | Qubits | RB Decay | Reports
    %
    %   Circuit comes first so the user immediately sees which circuit
    %   the charts below relate to; the chart-refresh buttons sit beside
    %   it and Reports anchors the far right.
    toolbar = uigridlayout(g, [1 8]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    %  Trailing Download JSON / Generate Report / Reports buttons
    %  removed per operator request — Detailed Analysis is a
    %  diagnostic surface, not an export surface, and the same
    %  destinations are reachable from the Results screen toolbar.
    toolbar.ColumnWidth = {60, '1x', 150, 108, 126, 108, 96, 120};
    toolbar.Padding = [0 0 0 0]; toolbar.ColumnSpacing = 6;
    toolbar.BackgroundColor = BG;

    % Left-aligned so the 'C' of 'Circuit' sits flush against the
    % toolbar's left edge — same X as the 'Measured vs Ideal
    % Distribution' panel title on the row below (both panel and toolbar
    % are children of the same parent grid and share GRID_PADDING).
    circLbl = uilabel(toolbar, 'Text', 'Circuit', ...
        'FontSize', 13, 'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center');
    circLbl.Layout.Row = 1; circLbl.Layout.Column = 1;

    app.DetailedAnalysisCircuitDropdown = uidropdown(toolbar, ...
        'Items', {'(loading...)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~)app.DetailedAnalysisVm.onCircuitSelected(src.Value));
    app.DetailedAnalysisCircuitDropdown.Layout.Row = 1;
    app.DetailedAnalysisCircuitDropdown.Layout.Column = 2;

    app.DetailedAnalysisAnalyzeButton = uibutton(toolbar, ...
        'Text', [char(9881) ' Analyze'], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onAnalyze());
    app.DetailedAnalysisAnalyzeButton.Layout.Row = 1;
    app.DetailedAnalysisAnalyzeButton.Layout.Column = 3;
    app.styleBtn(app.DetailedAnalysisAnalyzeButton, 'primary');
    app.DetailedAnalysisAnalyzeButton.FontSize = 13;
    app.DetailedAnalysisAnalyzeButton.Tooltip = ...
        'Jump to the Analysis screen with the selected circuit and run a fresh analyze';

    app.RefreshCompareButton = uibutton(toolbar, ...
        'Text', [char(8644) ' ' Labels.get('detailed_btn_refresh_compare')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotComparison());
    app.RefreshCompareButton.Layout.Row = 1; app.RefreshCompareButton.Layout.Column = 4;
    app.styleBtn(app.RefreshCompareButton, 'ghost');
    app.RefreshCompareButton.FontSize = 13;
    app.RefreshCompareButton.Tooltip = 'GET /jobs/{id}/results/detailed — distribution comparison';

    app.RefreshHeatmapButton = uibutton(toolbar, ...
        'Text', [char(9641) ' ' Labels.get('detailed_btn_refresh_heatmap')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotHeatmap());
    app.RefreshHeatmapButton.Layout.Row = 1; app.RefreshHeatmapButton.Layout.Column = 5;
    app.styleBtn(app.RefreshHeatmapButton, 'ghost');
    app.RefreshHeatmapButton.FontSize = 13;
    app.RefreshHeatmapButton.Tooltip = 'GET /jobs/{id}/results/detailed — cross-qubit error matrix';

    app.RefreshTemporalButton = uibutton(toolbar, ...
        'Text', [char(8987) ' ' Labels.get('detailed_btn_refresh_temporal')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotTemporal());
    app.RefreshTemporalButton.Layout.Row = 1; app.RefreshTemporalButton.Layout.Column = 6;
    app.styleBtn(app.RefreshTemporalButton, 'ghost');
    app.RefreshTemporalButton.FontSize = 13;
    app.RefreshTemporalButton.Tooltip = 'GET /jobs/{id}/error-trends — temporal stability';

    app.RefreshQubitButton = uibutton(toolbar, ...
        'Text', [char(9898) ' ' Labels.get('detailed_btn_refresh_qubit')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotQubit());
    app.RefreshQubitButton.Layout.Row = 1; app.RefreshQubitButton.Layout.Column = 7;
    app.styleBtn(app.RefreshQubitButton, 'ghost');
    app.RefreshQubitButton.FontSize = 13;
    app.RefreshQubitButton.Tooltip = 'GET /jobs/{id}/results/detailed — per-qubit T1/T2 coherence';

    app.RefreshRBButton = uibutton(toolbar, ...
        'Text', [char(8600) ' ' Labels.get('detailed_btn_refresh_rb')], ...
        'ButtonPushedFcn', @(~,~)app.DetailedAnalysisVm.onPlotRBDecay());
    app.RefreshRBButton.Layout.Row = 1; app.RefreshRBButton.Layout.Column = 8;
    app.styleBtn(app.RefreshRBButton, 'ghost');
    app.RefreshRBButton.FontSize = 13;
    app.RefreshRBButton.Tooltip = 'GET /jobs/{id}/rb-decay — randomized benchmarking';

    %  Download JSON / Generate Report / Reports navigation buttons
    %  removed per operator request — Detailed Analysis is a
    %  diagnostic surface, not an export surface. The matching
    %  property declarations on QTAUWorkbenchApp
    %  (DetailedDownloadJsonBtn, DetailedGeneratePdfBtn) and the
    %  matching VM methods (onDownloadDetailedJson,
    %  onGenerateRunReport) remain instantiated as harmless dead
    %  code so removing them doesn't ripple into the rest of the
    %  app — re-adding the buttons here is a one-block edit if the
    %  preference flips later.

    % ═════════════════════════════════════════════════════════════════════════
    %  ROW 2 — KPI strip (M3, populated by DetailedAnalysisVm) ───────────────
    %  5 cards: Fidelity / Drift / Qubits / RB Decay / Outliers.
    %  Mirrors the Results + Analysis screen KPI rows for visual
    %  consistency across the workflow.
    % ═════════════════════════════════════════════════════════════════════════
    kpis = uigridlayout(g, [1 5]);
    kpis.Layout.Row = 2; kpis.Layout.Column = [1 3];
    kpis.ColumnWidth = {'1x', '1x', '1x', '1x', '1x'};
    kpis.ColumnSpacing = 10; kpis.Padding = [0 0 0 0];
    kpis.BackgroundColor = BG;
    %  Hidden per operator request — see the row-2 collapse comment
    %  on g.RowHeight above. Visible='off' here is belt-and-braces on
    %  top of RowHeight=0 to guarantee zero rendering even on MATLAB
    %  versions where 0-height rows produce a 1-px sliver.
    kpis.Visible = 'off';
    [app.DetailedKpiFidelityVal, app.DetailedKpiFidelitySub] = ...
        localDetailedKpiCard(kpis, 1, 'FIDELITY',  Theme.COLOR_PRIMARY);
    [app.DetailedKpiDriftVal,    app.DetailedKpiDriftSub]    = ...
        localDetailedKpiCard(kpis, 2, 'DRIFT',     Theme.COLOR_AMBER);
    [app.DetailedKpiQubitsVal,   app.DetailedKpiQubitsSub]   = ...
        localDetailedKpiCard(kpis, 3, 'QUBITS',    Theme.COLOR_PURPLE);
    [app.DetailedKpiRBVal,       app.DetailedKpiRBSub]       = ...
        localDetailedKpiCard(kpis, 4, 'RB DECAY',  Theme.COLOR_SUCCESS);
    [app.DetailedKpiOutliersVal, app.DetailedKpiOutliersSub] = ...
        localDetailedKpiCard(kpis, 5, 'OUTLIERS',  Theme.COLOR_DANGER);

    % ═════════════════════════════════════════════════════════════════════════
    %  ROW 3 — Three tall analysis charts
    % ═════════════════════════════════════════════════════════════════════════

    % ── Row 2, Col 1: Measured vs Ideal State Distribution (bar + errorbar) ──
    comparePanel = uipanel(g, 'Title', Labels.get('detailed_panel_compare'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    comparePanel.Layout.Row = 3; comparePanel.Layout.Column = 1;
    comparePanel.BackgroundColor = PW;
    cpg = uigridlayout(comparePanel, [1 1]);
    cpg.Padding = Theme.KPI_INNER_PAD; cpg.BackgroundColor = PW;
    % Lazy uiaxes — VM paint methods materialise via app.ensureLazyAxes(...).
    cmpPlaceholder = uilabel(cpg, ...
        'Text', 'Measured vs ideal distribution appears here after a run.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.CompareGrid        = cpg;
    app.ComparePlaceholder = cmpPlaceholder;
    app.CompareAxes        = [];

    % ── Row 2, Col 2: Cross-Qubit Error Rate Heatmap (imagesc) ───────────────
    heatmapPanel = uipanel(g, 'Title', Labels.get('detailed_panel_heatmap'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    heatmapPanel.Layout.Row = 3; heatmapPanel.Layout.Column = 2;
    heatmapPanel.BackgroundColor = PW;
    hpg = uigridlayout(heatmapPanel, [1 1]);
    hpg.Padding = Theme.KPI_INNER_PAD; hpg.BackgroundColor = PW;
    % Lazy uiaxes — see Compare note.
    heatPlaceholder = uilabel(hpg, ...
        'Text', 'Cross-qubit error rate heatmap appears here after a run.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.ErrorHeatmapGrid        = hpg;
    app.ErrorHeatmapPlaceholder = heatPlaceholder;
    app.ErrorHeatmapAxes        = [];

    % ── Row 2, Col 3: Temporal Stability with ±1σ Confidence Band ────────────
    temporalPanel = uipanel(g, 'Title', Labels.get('detailed_panel_temporal'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    temporalPanel.Layout.Row = 3; temporalPanel.Layout.Column = 3;
    temporalPanel.BackgroundColor = PW;
    tpg = uigridlayout(temporalPanel, [1 1]);
    tpg.Padding = Theme.KPI_INNER_PAD; tpg.BackgroundColor = PW;
    % Lazy uiaxes — see Compare note.
    tempPlaceholder = uilabel(tpg, ...
        'Text', 'Temporal stability appears here after a run.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.TemporalGrid        = tpg;
    app.TemporalPlaceholder = tempPlaceholder;
    app.TemporalAxes        = [];

    % ═════════════════════════════════════════════════════════════════════════
    %  ROW 3 — Three moderate-height diagnostic charts
    % ═════════════════════════════════════════════════════════════════════════

    % ── Row 3, Col 1: T1 vs T2 Coherence Scatter (colour = readout fidelity) ─
    qubitPanel = uipanel(g, 'Title', Labels.get('detailed_panel_qubit'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    qubitPanel.Layout.Row = 4; qubitPanel.Layout.Column = 1;
    qubitPanel.BackgroundColor = PW;
    qpg = uigridlayout(qubitPanel, [1 1]);
    qpg.Padding = Theme.KPI_INNER_PAD; qpg.BackgroundColor = PW;
    % Lazy uiaxes — see Compare note.
    qubitPlaceholder = uilabel(qpg, ...
        'Text', 'T1 vs T2 per-qubit scatter appears here after a run.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.QubitGrid        = qpg;
    app.QubitPlaceholder = qubitPlaceholder;
    app.QubitAxes        = [];

    % ── Row 3, Col 2: Randomized Benchmarking Decay Curve ────────────────────
    rbPanel = uipanel(g, 'Title', Labels.get('detailed_panel_rb'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    rbPanel.Layout.Row = 4; rbPanel.Layout.Column = 2;
    rbPanel.BackgroundColor = PW;
    rpg = uigridlayout(rbPanel, [1 1]);
    rpg.Padding = Theme.KPI_INNER_PAD; rpg.BackgroundColor = PW;
    % Lazy uiaxes — see Compare note.
    rbPlaceholder = uilabel(rpg, ...
        'Text', 'Randomized benchmarking decay appears here after a run.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.RBDecayGrid        = rpg;
    app.RBDecayPlaceholder = rbPlaceholder;
    app.RBDecayAxes        = [];

    % ── Row 3, Col 3: Enhanced Interpretation & Diagnostics ──────────────────
    insightPanel = uipanel(g, 'Title', Labels.get('detailed_panel_insight'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    insightPanel.Layout.Row = 4; insightPanel.Layout.Column = 3;
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


% ── Local helpers (file-private — not on the class) ────────────────────────
function [valLbl, subLbl] = localDetailedKpiCard(parent, col, captionText, accent)
    %  KPI tile mirroring the Results + Analysis screens. Returns the
    %  value and sub-label uilabel handles so the VM can update them.
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
    valLbl = uilabel(inner, 'Text', char(8212), ...
        'FontWeight', 'bold', 'FontSize', 22, ...
        'FontColor', Theme.COLOR_HEADING, ...
        'VerticalAlignment', 'center');
    subLbl = uilabel(inner, 'Text', '', ...
        'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, ...
        'VerticalAlignment', 'top');
end
