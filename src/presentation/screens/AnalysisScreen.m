% AnalysisTab  Populates the Analysis section panel.
%
%   Layout:
%     Row 1 (34 px):   Circuit selector + Analyze button.
%     Row 2 ('1x'):    Extracted Features tree + annotation (left) |
%                      QASMBench Similarity table + comparison notes (right).
%     Row 3 ('1x'):    Quantum Volume heatmap (full width).
%     Row 4 (72 px):   Action bar — Next: Backends / Back: Upload.
%
%   All visible strings come from resources/labels.properties via Labels.
function AnalysisScreen(app)
    Logger.info('AnalysisScreen', 'Building Analysis tab UI');
    t = app.createSectionPage('Analysis');

    g = uigridlayout(t, [4 3]);
    g.RowHeight     = {34, '1x', '1x', 72};
    g.ColumnWidth   = {'1x', 6, '1.15x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Circuit selector + Analyze button ────────────────────────────────────
    topBar = uigridlayout(g, [1 3]);
    topBar.Layout.Row = 1; topBar.Layout.Column = [1 3];
    topBar.ColumnWidth = {90, '1x', 110};
    topBar.Padding = [0 0 0 0]; topBar.ColumnSpacing = 8;
    topBar.BackgroundColor = Theme.COLOR_BG;

    circLbl = uilabel(topBar, 'Text', Labels.get('analysis_label_circuit', 'Circuit'), ...
        'FontSize', 13, 'FontColor', [0.35 0.42 0.52], ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    circLbl.Layout.Row = 1; circLbl.Layout.Column = 1;

    app.AnalysisCircuitDropdown = uidropdown(topBar, ...
        'Items', {'(none)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~)app.AnalysisVm.onCircuitSelected(src.Value));
    app.AnalysisCircuitDropdown.Layout.Row = 1; app.AnalysisCircuitDropdown.Layout.Column = 2;

    app.AnalyzeButton = uibutton(topBar, 'Text', [char(9881) ' ' Labels.get('analysis_btn_analyze')], ...
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onAnalyzeCircuit());
    app.AnalyzeButton.Layout.Row = 1; app.AnalyzeButton.Layout.Column = 3;
    app.styleBtn(app.AnalyzeButton, 'primary');
    app.AnalyzeButton.FontSize = 14;
    app.AnalyzeButton.Tooltip = 'POST /api/circuits/{id}/analyze + match-benchmarks';

    % ── Column divider ────────────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = Theme.COLOR_DIVIDER; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Extracted Features (left) ─────────────────────────────────────────────
    p1 = uipanel(g, 'Title', Labels.get('analysis_panel_features'));
    p1.Layout.Row = 2; p1.Layout.Column = 1; p1.BackgroundColor = Theme.COLOR_CARD;

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

    % ── QASMBench Similarity (right) ─────────────────────────────────────────
    p2 = uipanel(g, 'Title', Labels.get('analysis_panel_similarity'));
    p2.Layout.Row = 2; p2.Layout.Column = 3; p2.BackgroundColor = Theme.COLOR_CARD;

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
        'Quantum Volume — Circuit Depth vs Width'));
    qvPanel.Layout.Row = 3; qvPanel.Layout.Column = [1 3];
    qvPanel.BackgroundColor = Theme.COLOR_CARD;
    qvPanel.Scrollable = 'on';

    qvGrid = uigridlayout(qvPanel, [1 2]);
    qvGrid.ColumnWidth = {'1x', 160};
    qvGrid.RowHeight   = {190};
    qvGrid.Padding = Theme.KPI_INNER_PAD; qvGrid.BackgroundColor = Theme.COLOR_CARD;

    app.QVHeatmapAxes = uiaxes(qvGrid);
    app.QVHeatmapAxes.Layout.Row = 1; app.QVHeatmapAxes.Layout.Column = 1;
    app.styleAxes(app.QVHeatmapAxes);
    title(app.QVHeatmapAxes, Labels.get('analysis_qv_title', ...
        'Circuit Depth vs Width (Avg Result Fidelity)'));
    xlabel(app.QVHeatmapAxes, Labels.get('analysis_qv_xlabel', 'Circuit Depth'));
    ylabel(app.QVHeatmapAxes, Labels.get('analysis_qv_ylabel', 'Circuit Width (Qubits)'));

    app.QVInfoLabel = uilabel(qvGrid, ...
        'Text', Labels.get('analysis_qv_initial', ...
            'Run analysis to populate the Quantum Volume chart.'), ...
        'FontSize', 12, 'FontColor', [0.45 0.50 0.58], ...
        'WordWrap', 'on', 'VerticalAlignment', 'top');
    app.QVInfoLabel.Layout.Row = 1; app.QVInfoLabel.Layout.Column = 2;

    % ── Action bar ────────────────────────────────────────────────────────────
    exportPanel = uipanel(g, 'Title', Labels.get('analysis_panel_decision'));
    exportPanel.Layout.Row = 4; exportPanel.Layout.Column = [1 3];
    exportPanel.BackgroundColor = [0.94 0.97 1.00];

    eg = uigridlayout(exportPanel, [1 4]);
    eg.ColumnWidth = {'1x', 150, 170, 120};
    eg.Padding = [14 8 14 8]; eg.BackgroundColor = [0.94 0.97 1.00];
    desc = uilabel(eg, 'Text', Labels.get('analysis_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(eg, 'Text', [char(9638) ' Visualize'], ...
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onVisualizeSimilarity());
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'secondary');
    tmp = uibutton(eg, 'Text', [char(9004) ' ' Labels.get('analysis_btn_next')], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Backends'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'primary');
    tmp = uibutton(eg, 'Text', [char(8593) ' Upload'], ...  % Upload nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Upload'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 4; app.styleBtn(tmp, 'ghost');

    Logger.info('AnalysisScreen', 'Analysis tab UI built successfully');
end
