% AnalysisTab  Populates the Analysis section panel.
%
%   Layout:
%     Row 1 (44 px):   Full-width Analyze Circuit button.
%     Row 2 ('1x'):    Extracted Features tree + annotation (left) |
%                      QASMBench Similarity table + comparison notes (right).
%     Row 3 (72 px):   Action bar — Next: Backends / Back: Upload.
%
%   All visible strings come from resources/labels.properties via Labels.
function AnalysisScreen(app)
    Logger.info('AnalysisScreen', 'Building Analysis tab UI');
    t = app.createSectionPage('Analysis');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {44, '1x', 72};
    g.ColumnWidth   = {'1x', 6, '1.15x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Circuit selector + Analyze button ────────────────────────────────────
    topBar = uigridlayout(g, [1 3]);
    topBar.Layout.Row = 1; topBar.Layout.Column = [1 3];
    topBar.ColumnWidth = {90, '1x', 160};
    topBar.Padding = [0 0 0 0]; topBar.ColumnSpacing = 8;
    topBar.BackgroundColor = [0.96 0.97 0.99];

    circLbl = uilabel(topBar, 'Text', Labels.get('analysis_label_circuit', 'Circuit'), ...
        'FontSize', 13, 'FontColor', [0.35 0.42 0.52], ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    circLbl.Layout.Row = 1; circLbl.Layout.Column = 1;

    app.AnalysisCircuitDropdown = uidropdown(topBar, ...
        'Items', {'(none)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~)app.AnalysisVm.onCircuitSelected(src.Value));
    app.AnalysisCircuitDropdown.Layout.Row = 1; app.AnalysisCircuitDropdown.Layout.Column = 2;

    app.AnalyzeButton = uibutton(topBar, 'Text', Labels.get('analysis_btn_analyze'), ...
        'ButtonPushedFcn', @(~,~)app.AnalysisVm.onAnalyzeCircuit());
    app.AnalyzeButton.Layout.Row = 1; app.AnalyzeButton.Layout.Column = 3;
    app.styleBtn(app.AnalyzeButton, 'primary');
    app.AnalyzeButton.Tooltip = 'POST /api/circuits/{id}/analyze + match-benchmarks';

    % ── Column divider ────────────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Extracted Features (left) ─────────────────────────────────────────────
    p1 = uipanel(g, 'Title', Labels.get('analysis_panel_features'));
    p1.Layout.Row = 2; p1.Layout.Column = 1; p1.BackgroundColor = [1 1 1];

    g1 = uigridlayout(p1, [1 2]);
    g1.ColumnWidth = {'1x', 200}; g1.Padding = [12 10 12 10]; g1.BackgroundColor = [1 1 1];

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
    p2.Layout.Row = 2; p2.Layout.Column = 3; p2.BackgroundColor = [1 1 1];

    g2 = uigridlayout(p2, [2 1]);
    g2.RowHeight = {'1x', 96}; g2.Padding = [12 10 12 10]; g2.BackgroundColor = [1 1 1];

    app.SimilarityTable = uitable(g2);
    app.SimilarityTable.ColumnName = Labels.cols('analysis_table_cols_similarity', ...
        {'Benchmark','Similarity','Category','Notes'});
    app.SimilarityTable.Data = {};
    app.SimilarityTable.Layout.Row = 1; app.SimilarityTable.Layout.Column = 1;
    app.styleTable(app.SimilarityTable);

    app.AnalysisCompareArea = uitextarea(g2, 'Editable', 'off');
    app.AnalysisCompareArea.Layout.Row = 2; app.AnalysisCompareArea.FontSize = 12;
    app.AnalysisCompareArea.Value = {Labels.get('analysis_similarity_initial')};

    % ── Action bar ────────────────────────────────────────────────────────────
    exportPanel = uipanel(g, 'Title', Labels.get('analysis_panel_decision'));
    exportPanel.Layout.Row = 3; exportPanel.Layout.Column = [1 3];
    exportPanel.BackgroundColor = [0.94 0.97 1.00];

    eg = uigridlayout(exportPanel, [1 3]);
    eg.ColumnWidth = {'1x', 160, 150};
    eg.Padding = [14 8 14 8]; eg.BackgroundColor = [0.94 0.97 1.00];
    desc = uilabel(eg, 'Text', Labels.get('analysis_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(eg, 'Text', Labels.get('analysis_btn_next'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Backends'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'primary');
    tmp = uibutton(eg, 'Text', Labels.get('analysis_btn_back'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Upload'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');

    Logger.info('AnalysisScreen', 'Analysis tab UI built successfully');
end
