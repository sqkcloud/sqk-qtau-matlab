% BenchmarkTab  Populates the Benchmark section panel.
%
%   Layout:
%     Row 1, Col 1:  Benchmark Configuration form (shots, opt, mitigation, strategy).
%     Row 1, Col 3:  Execution Plan summary.
%     Row 2:         Full-width Transpilation Strategy Comparison table.
%     Row 3:         Action bar — Next: Prediction / Back: Backends.
%
%   All visible strings come from resources/labels.properties via Labels.
function BenchmarkScreen(app)
    Logger.info('BenchmarkScreen', 'Building Benchmark tab UI');
    t = app.createSectionPage('Benchmark');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {280, '1x', 72};
    g.ColumnWidth   = {'1.05x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Column divider (row 1) ────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 1; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Configuration form (left) ─────────────────────────────────────────────
    config = uipanel(g, 'Title', Labels.get('benchmark_panel_config'));
    config.Layout.Row = 1; config.Layout.Column = 1; config.BackgroundColor = [1 1 1];

    cg = uigridlayout(config, [5 2]);
    cg.RowHeight = {40, 40, 40, 40, 36};
    cg.ColumnWidth = {180, '1x'};
    cg.Padding = [16 12 16 12]; cg.RowSpacing = 8; cg.BackgroundColor = [1 1 1];

    lbl = uilabel(cg, 'Text', Labels.get('benchmark_label_shots'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.BenchmarkShotsField = uieditfield(cg, 'numeric', 'Value', 4096);
    app.BenchmarkShotsField.Layout.Row = 1; app.BenchmarkShotsField.Layout.Column = 2;

    lbl = uilabel(cg, 'Text', Labels.get('benchmark_label_opt_level'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.BenchmarkOptField = uieditfield(cg, 'numeric', 'Value', 3);
    app.BenchmarkOptField.Layout.Row = 2; app.BenchmarkOptField.Layout.Column = 2;
    app.BenchmarkOptField.Limits = [0 3];

    lbl = uilabel(cg, 'Text', Labels.get('benchmark_label_mitigation'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    mitigItems = Labels.items('benchmark_mitigation_items', ...
        {'None','Measurement mitigation','Zero-noise extrapolation','Readout calibration'});
    mitigDefault = Labels.get('benchmark_mitigation_default', 'Measurement mitigation');
    app.BenchmarkMitigationDropdown = uidropdown(cg, 'Items', mitigItems, 'Value', mitigDefault);
    app.BenchmarkMitigationDropdown.Layout.Row = 3; app.BenchmarkMitigationDropdown.Layout.Column = 2;

    lbl = uilabel(cg, 'Text', Labels.get('benchmark_label_strategy'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 4; lbl.Layout.Column = 1;
    stratItems   = Labels.items('benchmark_strategy_items', {'Balanced','Depth optimized','Fidelity optimized','Queue aware'});
    stratDefault = Labels.get('benchmark_strategy_default', 'Fidelity optimized');
    app.BenchmarkStrategyDropdown = uidropdown(cg, 'Items', stratItems, 'Value', stratDefault);
    app.BenchmarkStrategyDropdown.Layout.Row = 4; app.BenchmarkStrategyDropdown.Layout.Column = 2;

    app.BenchmarkRunButton = uibutton(cg, 'Text', Labels.get('benchmark_btn_run'), ...
        'ButtonPushedFcn', @(~,~)app.BenchmarkVm.onRunBenchmark());
    app.BenchmarkRunButton.Layout.Row = 5; app.BenchmarkRunButton.Layout.Column = [1 2];
    app.styleBtn(app.BenchmarkRunButton, 'primary');
    app.BenchmarkRunButton.Tooltip = 'Save config and compare transpilation strategies';

    % ── Execution Plan (right) ────────────────────────────────────────────────
    estimate = uipanel(g, 'Title', Labels.get('benchmark_panel_plan'));
    estimate.Layout.Row = 1; estimate.Layout.Column = 3; estimate.BackgroundColor = [1 1 1];

    eg = uigridlayout(estimate, [1 1]);
    eg.Padding = [16 12 16 12]; eg.BackgroundColor = [1 1 1];
    app.BenchmarkStatusArea = uitextarea(eg, 'Editable', 'off'); app.BenchmarkStatusArea.FontSize = 12;
    app.BenchmarkStatusArea.Value = {Labels.get('benchmark_status_initial')};

    % ── Strategy comparison table (full width) ────────────────────────────────
    comparePanel = uipanel(g, 'Title', Labels.get('benchmark_panel_compare'));
    comparePanel.Layout.Row = 2; comparePanel.Layout.Column = [1 3]; comparePanel.BackgroundColor = [1 1 1];
    comparePanel.Scrollable = 'on';

    comp = uigridlayout(comparePanel, [1 1]);
    comp.Padding = [12 10 12 10]; comp.BackgroundColor = [1 1 1];
    app.BenchmarkStrategyTable = uitable(comp);
    app.BenchmarkStrategyTable.ColumnName = Labels.cols('benchmark_table_cols_strategy', ...
        {'Strategy','Depth','2Q gates','Predicted fidelity','Comment'});
    app.BenchmarkStrategyTable.Data = {};
    app.styleTable(app.BenchmarkStrategyTable);

    % ── Action bar ────────────────────────────────────────────────────────────
    nextPanel = uipanel(g, 'Title', Labels.get('benchmark_panel_action'));
    nextPanel.Layout.Row = 3; nextPanel.Layout.Column = [1 3];
    nextPanel.BackgroundColor = [0.94 0.97 1.00];

    ng = uigridlayout(nextPanel, [1 3]);
    ng.ColumnWidth = {'1x', 165, 165};
    ng.Padding = [14 8 14 8]; ng.BackgroundColor = [0.94 0.97 1.00];
    desc = uilabel(ng, 'Text', Labels.get('benchmark_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(ng, 'Text', Labels.get('benchmark_btn_next'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Prediction'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'primary');
    tmp = uibutton(ng, 'Text', Labels.get('benchmark_btn_back'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Backends'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');

    Logger.info('BenchmarkScreen', 'Benchmark tab UI built successfully');
end
