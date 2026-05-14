% AnalysisTab  Populates the Analysis section panel.
%
%   Layout:
%     Row 1 (34 px):   Circuit selector + Analyze + Quantum Amplitude
%                      Estimation launcher button.
%     Row 2 ('1x'):    Extracted Features tree + annotation (left) |
%                      QTAUBench Similarity table + comparison notes (right).
%     Row 3 ('1x'):    Quantum Volume heatmap (full width).
%     Row 4 (72 px):   Action bar — Next: Backends / Back: Upload.
%
%   The Quantum Monte Carlo Simulation (Quantum Amplitude Estimation)
%   UI lives in a modal popup (see DialogBuilder.buildQmcDialog) so the
%   main Analysis screen stays focused on feature extraction and
%   similarity review.
%
%   All visible strings come from resources/labels.properties via Labels.
function AnalysisScreen(app)
    Logger.info('AnalysisScreen', 'Building Analysis tab UI');
    t = app.createSectionPage('Analysis');

    g = uigridlayout(t, [5 2]);
    %  M3 Tier C — KPI strip lives in row 2 between the toolbar and
    %  the existing 2-row content area. Total fixed cost: 34 + 96 +
    %  72 = 202 px, leaving ~668 px of flex content rows in the
    %  default 870 px figure.
    g.RowHeight     = {34, 96, '1x', '1x', 72};
    g.ColumnWidth   = {'1x', '1.15x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Circuit selector + Analyze + QMC launcher + Error Mitigation launcher
    topBar = uigridlayout(g, [1 6]);
    topBar.Layout.Row = 1; topBar.Layout.Column = [1 2];
    %  Order: Circuit-label / dropdown / Upload / Analyze / QMC / EM.
    %  Upload sits before Analyze so the operator's natural flow is
    %  pick-circuit → upload-if-needed → analyze. Download JSON +
    %  Generate Report moved to the bottom Decision row, gated by
    %  applyAnalysisData (only enabled after a successful analyze).
    topBar.ColumnWidth = {90, '1x', 110, 110, 260, 220};
    topBar.Padding = [0 0 0 0]; topBar.ColumnSpacing = 8;
    topBar.BackgroundColor = Theme.COLOR_BG;

    circLbl = uilabel(topBar, 'Text', Labels.get('analysis_label_circuit', 'Circuit'), ...
        'FontSize', 13, 'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    circLbl.Layout.Row = 1; circLbl.Layout.Column = 1;

    app.AnalysisCircuitDropdown = uidropdown(topBar, ...
        'Items', {'(none)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~)app.AnalysisVm.onCircuitSelected(src.Value));
    app.AnalysisCircuitDropdown.Layout.Row = 1; app.AnalysisCircuitDropdown.Layout.Column = 2;

    %  Upload bridge — pre-Analyze step. Lets the operator switch to
    %  the Upload screen without having to navigate via the sidebar
    %  when the currently-selected circuit isn't the one they want.
    app.AnalysisUploadBtn = uibutton(topBar, ...
        'Text', [char(8593) ' Upload'], ...  % ↑
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Upload'));
    app.AnalysisUploadBtn.Layout.Row = 1; app.AnalysisUploadBtn.Layout.Column = 3;
    app.styleBtn(app.AnalysisUploadBtn, 'ghost');
    app.AnalysisUploadBtn.FontSize = 14;
    app.AnalysisUploadBtn.Tooltip = ...
        'Open the Upload screen to add a new circuit.';

    app.AnalyzeButton = uibutton(topBar, 'Text', [char(9881) ' ' Labels.get('analysis_btn_analyze')], ...
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onAnalyzeCircuit());
    app.AnalyzeButton.Layout.Row = 1; app.AnalyzeButton.Layout.Column = 4;
    app.styleBtn(app.AnalyzeButton, 'primary');
    app.AnalyzeButton.FontSize = 14;
    app.AnalyzeButton.Tooltip = 'POST /api/circuits/{id}/analyze + match-benchmarks';

    % Launcher for the Quantum Monte Carlo Simulation (Quantum Amplitude
    % Estimation) popup. The full control + plot UI lives in the modal
    % dialog built by DialogBuilder.buildQmcDialog.
    app.QmcOpenButton = uibutton(topBar, ...
        'Text', [char(9883) ' Quantum Monte Carlo'], ...
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onOpenQmcDialog());
    app.QmcOpenButton.Layout.Row = 1; app.QmcOpenButton.Layout.Column = 5;
    app.styleBtn(app.QmcOpenButton, 'secondary');
    app.QmcOpenButton.FontSize = 14;
    app.QmcOpenButton.Tooltip = ...
        'Open the Quantum Monte Carlo Simulation popup';

    % Launcher for the Quantum Error Mitigation Analysis popup. The full
    % control + plot UI lives in the modal dialog built by
    % DialogBuilder.buildErrorMitigationDialog. Reads cached QAE, cutting
    % and mitigation-estimate data — no async-job submission of its own.
    app.EmOpenButton = uibutton(topBar, ...
        'Text', [char(9881) ' ' ...
                 Labels.get('analysis_btn_error_mitigation', 'Error Mitigation')], ...
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onOpenEmDialog());
    app.EmOpenButton.Layout.Row = 1; app.EmOpenButton.Layout.Column = 6;
    app.styleBtn(app.EmOpenButton, 'secondary');
    app.EmOpenButton.FontSize = 14;
    app.EmOpenButton.Tooltip = ...
        'Open the Quantum Error Mitigation Analysis popup';

    % ── KPI strip (M3 — populated by AnalysisVm.applyAnalysisData) ────────────
    %  5 cards: Qubits / Depth / Total gates / 2Q ratio / Parallelism.
    %  Mirrors the Results screen's KPI row pattern from M2 so the
    %  visual language is consistent across the workflow.
    kpis = uigridlayout(g, [1 5]);
    kpis.Layout.Row = 2; kpis.Layout.Column = [1 2];
    kpis.ColumnWidth = {'1x', '1x', '1x', '1x', '1x'};
    kpis.ColumnSpacing = 10; kpis.Padding = [0 0 0 0];
    kpis.BackgroundColor = Theme.COLOR_BG;
    [app.AnalysisKpiQubitsVal, app.AnalysisKpiQubitsSub] = ...
        localAnalysisKpiCard(kpis, 1, 'QUBITS',       Theme.COLOR_PRIMARY);
    [app.AnalysisKpiDepthVal,  app.AnalysisKpiDepthSub]  = ...
        localAnalysisKpiCard(kpis, 2, 'DEPTH',        Theme.COLOR_PURPLE);
    [app.AnalysisKpiGatesVal,  app.AnalysisKpiGatesSub]  = ...
        localAnalysisKpiCard(kpis, 3, 'TOTAL GATES',  Theme.COLOR_AMBER);
    [app.AnalysisKpiTwoQVal,   app.AnalysisKpiTwoQSub]   = ...
        localAnalysisKpiCard(kpis, 4, '2Q RATIO',     Theme.COLOR_DANGER);
    [app.AnalysisKpiParaVal,   app.AnalysisKpiParaSub]   = ...
        localAnalysisKpiCard(kpis, 5, 'PARALLELISM',  Theme.COLOR_SUCCESS);

    % ── Extracted Features (left) ─────────────────────────────────────────────
    p1 = uipanel(g, 'Title', Labels.get('analysis_panel_features'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    p1.Layout.Row = 3; p1.Layout.Column = 1; p1.BackgroundColor = Theme.COLOR_CARD;

    g1 = uigridlayout(p1, [1 2]);
    g1.ColumnWidth = {'1x', 200}; g1.Padding = [12 10 12 10]; g1.BackgroundColor = Theme.COLOR_CARD;

    app.FeatureTree = uitree(g1); app.FeatureTree.FontSize = 12;
    root = uitreenode(app.FeatureTree, 'Text', '(no circuit analyzed)');
    expand(root); %#ok

    app.AnalysisFeatureArea = uitextarea(g1, 'Editable', 'off'); app.AnalysisFeatureArea.FontSize = 12;
    app.AnalysisFeatureArea.Value = { ...
        Labels.get('analysis_feature_title'), ...
        'Analyze a circuit to see', ...
        'feature extraction results.'};

    % ── QTAUBench Similarity (right) ─────────────────────────────────────────
    p2 = uipanel(g, 'Title', Labels.get('analysis_panel_similarity'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    p2.Layout.Row = 3; p2.Layout.Column = 2; p2.BackgroundColor = Theme.COLOR_CARD;

    g2 = uigridlayout(p2, [1 1]);
    g2.RowHeight = {'1x'}; g2.Padding = [12 10 12 10]; g2.BackgroundColor = Theme.COLOR_CARD;

    app.SimilarityTable = uitable(g2);
    app.SimilarityTable.ColumnName = Labels.cols('analysis_table_cols_similarity', ...
        {'Benchmark','Similarity','Category','Notes'});
    app.SimilarityTable.Data = {};
    app.SimilarityTable.Layout.Row = 1; app.SimilarityTable.Layout.Column = 1;
    app.styleTable(app.SimilarityTable);

    % ── Quantum Volume heatmap (full width) ──────────────────────────────────
    qvPanel = uipanel(g, 'Title', Labels.get('analysis_panel_qv', ...
        'Quantum Volume — Circuit Depth vs Width'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    qvPanel.Layout.Row = 4; qvPanel.Layout.Column = [1 2];
    qvPanel.BackgroundColor = Theme.COLOR_CARD;

    qvGrid = uigridlayout(qvPanel, [1 2]);
    qvGrid.ColumnWidth = {'1x', 220};
    qvGrid.RowHeight   = {'1x'};
    qvGrid.Padding = Theme.KPI_INNER_PAD; qvGrid.BackgroundColor = Theme.COLOR_CARD;

    % Lazy uiaxes — eager construction costs ~0.5–1.5 s cold-paint just
    % to host a blank heatmap. AnalysisViewModel.buildQVHeatmap promotes
    % this label to a real uiaxes when the analysis payload lands.
    qvPlaceholder = uilabel(qvGrid, ...
        'Text', Labels.get('analysis_qv_initial', ...
            'Run analysis to populate the Quantum Volume chart.'), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    qvPlaceholder.Layout.Row = 1; qvPlaceholder.Layout.Column = 1;
    app.QVHeatmapGrid        = qvGrid;
    app.QVHeatmapPlaceholder = qvPlaceholder;
    app.QVHeatmapAxes        = [];

    app.QVInfoLabel = uilabel(qvGrid, ...
        'Text', Labels.get('analysis_qv_initial', ...
            'Run analysis to populate the Quantum Volume chart.'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on', 'VerticalAlignment', 'top');
    app.QVInfoLabel.Layout.Row = 1; app.QVInfoLabel.Layout.Column = 2;

    % ── Action bar ────────────────────────────────────────────────────────────
    exportPanel = uipanel(g, 'Title', Labels.get('analysis_panel_decision'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    exportPanel.Layout.Row = 5; exportPanel.Layout.Column = [1 2];
    exportPanel.BackgroundColor = Theme.COLOR_ACCENT_BG;

    eg = uigridlayout(exportPanel, [1 6]);
    eg.ColumnWidth = {'1x', 150, 170, 170, 150, 170};
    eg.Padding = [14 8 14 8]; eg.BackgroundColor = Theme.COLOR_ACCENT_BG;
    desc = uilabel(eg, 'Text', Labels.get('analysis_action_msg'));
    desc.FontSize = 13; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(eg, 'Text', [char(9638) ' Visualize'], ...
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onVisualizeSimilarity());
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'secondary');
    % Bridge to the Circuit Cutting screen — propagates the Analysis
    % screen's currently-selected circuit so the user lands on Circuit
    % Cutting with the right input already picked.
    tmp = uibutton(eg, 'Text', ...
        [char(9986) ' ' Labels.get('analysis_btn_circuit_cutting', 'Circuit Cutting')], ...
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onCircuitCuttingBridge());
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'secondary');
    tmp = uibutton(eg, 'Text', [char(9004) ' ' Labels.get('analysis_btn_next', ...
            'Select Backend')], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Backends'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 4; app.styleBtn(tmp, 'primary');
    % Tier B exports — Download JSON dumps the analyze response to a
    % user-chosen .json file; Generate Report bridges to the Reports
    % screen with the title pre-filled. Both start disabled and are
    % toggled on by AnalysisVm.applyAnalysisData after a successful
    % analyze (and back off when the circuit selection changes — see
    % AnalysisVm.onCircuitSelected). This prevents the operator from
    % exporting stale or never-fetched data.
    app.AnalysisDownloadJsonBtn = uibutton(eg, ...
        'Text', [char(8681) ' Download JSON'], ...  % ⬇
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onDownloadAnalysisJson());
    app.AnalysisDownloadJsonBtn.Layout.Row = 1;
    app.AnalysisDownloadJsonBtn.Layout.Column = 5;
    app.styleBtn(app.AnalysisDownloadJsonBtn, 'ghost');
    app.AnalysisDownloadJsonBtn.Enable = 'off';
    app.AnalysisDownloadJsonBtn.Tooltip = ...
        'Run Analyze first; this saves the response as a .json file.';

    app.AnalysisGeneratePdfBtn = uibutton(eg, ...
        'Text', [char(9636) ' Generate Report'], ...    % ▤ (BMP — char(128196) renders tofu on macOS)
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onGenerateRunReport());
    app.AnalysisGeneratePdfBtn.Layout.Row = 1;
    app.AnalysisGeneratePdfBtn.Layout.Column = 6;
    app.styleBtn(app.AnalysisGeneratePdfBtn, 'secondary');
    app.AnalysisGeneratePdfBtn.Enable = 'off';
    app.AnalysisGeneratePdfBtn.Tooltip = ...
        'Run Analyze first; this opens Reports with the title pre-filled.';

    Logger.info('AnalysisScreen', 'Analysis tab UI built successfully');
end


% ── Local helpers (file-private — not on the class) ────────────────────────
function [valLbl, subLbl] = localAnalysisKpiCard(parent, col, captionText, accent)
    %  KPI tile mirroring ResultsScreen.localKpiCard. Returns the value
    %  and sub-label uilabel handles so the VM can update them.
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
