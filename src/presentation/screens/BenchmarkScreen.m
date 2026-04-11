% BenchmarkTab  Populates the Benchmark section panel.
%
%   Layout:
%     Row 1, Col 1:  Benchmark Configuration form (circuit, backend, shots+opt, mitigation, strategy).
%     Row 1, Col 3:  Execution Plan summary.
%     Row 2:         Full-width Transpilation Strategy Comparison table.
%     Row 3:         Action bar — Next: Prediction / Back: Backends.
%
%   All visible strings come from resources/labels.properties via Labels.
function BenchmarkScreen(app)
    Logger.info('BenchmarkScreen', 'Building Benchmark tab UI');
    t = app.createSectionPage('Benchmark');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {330, '1x', 72};
    g.ColumnWidth   = {'1.05x', 6, '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Column divider (row 1) ────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 1; div.Layout.Column = 2;
    div.BackgroundColor = Theme.COLOR_DIVIDER; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Configuration form (left) ─────────────────────────────────────────────
    config = uipanel(g, 'Title', Labels.get('benchmark_panel_config'));
    config.Layout.Row = 1; config.Layout.Column = 1; config.BackgroundColor = Theme.COLOR_CARD;

    cg = uigridlayout(config, [6 2]);
    cg.RowHeight = {40, 40, 40, 40, 40, 34};
    cg.ColumnWidth = {180, '1x'};
    cg.Padding = [16 12 16 12]; cg.RowSpacing = 8; cg.BackgroundColor = Theme.COLOR_CARD;

    % Row 1: Circuit selector
    lbl = uilabel(cg, 'Text', Labels.get('benchmark_label_circuit'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.BenchmarkCircuitDropdown = uidropdown(cg, ...
        'Items', {'(select circuit)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~) app.BenchmarkVm.onCircuitSelected(src.Value));
    app.BenchmarkCircuitDropdown.Layout.Row = 1; app.BenchmarkCircuitDropdown.Layout.Column = 2;

    % Row 2: Backend selector
    lbl = uilabel(cg, 'Text', Labels.get('benchmark_label_backend'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.BenchmarkBackendSelect = uidropdown(cg, ...
        'Items', {'(select backend)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~) app.BenchmarkVm.onBackendSelected(src.Value));
    app.BenchmarkBackendSelect.Layout.Row = 2; app.BenchmarkBackendSelect.Layout.Column = 2;

    % Row 3: Shots + Optimization Level (same row, nested grid)
    shotsLbl = uilabel(cg, 'Text', Labels.get('benchmark_label_shots'));
    shotsLbl.FontColor = [0.35 0.42 0.52];
    shotsLbl.Layout.Row = 3; shotsLbl.Layout.Column = 1;
    shotOptGrid = uigridlayout(cg, [1 4]);
    shotOptGrid.Layout.Row = 3; shotOptGrid.Layout.Column = 2;
    shotOptGrid.ColumnWidth = {'1x', 20, 130, 80};
    shotOptGrid.Padding = [0 0 0 0]; shotOptGrid.ColumnSpacing = 8;
    shotOptGrid.BackgroundColor = Theme.COLOR_CARD;

    app.BenchmarkShotsField = uieditfield(shotOptGrid, 'numeric', 'Value', 4096);
    app.BenchmarkShotsField.Layout.Row = 1; app.BenchmarkShotsField.Layout.Column = 1;

    optLbl = uilabel(shotOptGrid, 'Text', Labels.get('benchmark_label_opt_level'));
    optLbl.FontColor = [0.35 0.42 0.52]; optLbl.HorizontalAlignment = 'right';
    optLbl.Layout.Row = 1; optLbl.Layout.Column = 3;

    app.BenchmarkOptField = uieditfield(shotOptGrid, 'numeric', 'Value', 3);
    app.BenchmarkOptField.Layout.Row = 1; app.BenchmarkOptField.Layout.Column = 4;
    app.BenchmarkOptField.Limits = [0 3];

    % Row 4: Error Mitigation
    lbl = uilabel(cg, 'Text', Labels.get('benchmark_label_mitigation'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 4; lbl.Layout.Column = 1;
    mitigItems  = Labels.items('benchmark_mitigation_items', ...
        {'None','Measurement mitigation','Zero-noise extrapolation','Readout calibration','Dynamical decoupling'});
    mitigValues = Labels.items('benchmark_mitigation_values', ...
        {'none','measurement_mitigation','zero_noise_extrapolation','readout_calibration','dynamical_decoupling'});
    mitigDefault = Labels.get('benchmark_mitigation_default', 'measurement_mitigation');
    app.BenchmarkMitigationDropdown = uidropdown(cg, ...
        'Items', mitigItems, 'ItemsData', mitigValues, 'Value', mitigDefault);
    app.BenchmarkMitigationDropdown.Layout.Row = 4; app.BenchmarkMitigationDropdown.Layout.Column = 2;

    % Row 5: Transpilation Strategy
    lbl = uilabel(cg, 'Text', Labels.get('benchmark_label_strategy'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 5; lbl.Layout.Column = 1;
    stratItems   = Labels.items('benchmark_strategy_items', {'SABRE (recommended)','Stochastic','Basic'});
    stratValues  = Labels.items('benchmark_strategy_values', {'sabre','stochastic','basic'});
    stratDefault = Labels.get('benchmark_strategy_default', 'sabre');
    app.BenchmarkStrategyDropdown = uidropdown(cg, ...
        'Items', stratItems, 'ItemsData', stratValues, 'Value', stratDefault);
    app.BenchmarkStrategyDropdown.Layout.Row = 5; app.BenchmarkStrategyDropdown.Layout.Column = 2;

    % Row 6: Run button
    app.BenchmarkRunButton = uibutton(cg, 'Text', [char(9654) ' ' Labels.get('benchmark_btn_run')], ...
        'ButtonPushedFcn', @(~,~)app.BenchmarkVm.onRunBenchmark());
    app.BenchmarkRunButton.Layout.Row = 6; app.BenchmarkRunButton.Layout.Column = [1 2];
    app.styleBtn(app.BenchmarkRunButton, 'primary');
    app.BenchmarkRunButton.FontSize = 14;
    app.BenchmarkRunButton.Tooltip = 'Save config and compare transpilation strategies';

    % ── Execution Plan (right) ────────────────────────────────────────────────
    estimate = uipanel(g, 'Title', Labels.get('benchmark_panel_plan'));
    estimate.Layout.Row = 1; estimate.Layout.Column = 3; estimate.BackgroundColor = Theme.COLOR_CARD;

    eg = uigridlayout(estimate, [1 1]);
    eg.Padding = [16 12 16 12]; eg.BackgroundColor = Theme.COLOR_CARD;
    app.BenchmarkStatusArea = uitextarea(eg, 'Editable', 'off'); app.BenchmarkStatusArea.FontSize = 12;
    app.BenchmarkStatusArea.Value = {Labels.get('benchmark_status_initial')};

    % ── Strategy comparison table (full width) ────────────────────────────────
    comparePanel = uipanel(g, 'Title', Labels.get('benchmark_panel_compare'));
    comparePanel.Layout.Row = 2; comparePanel.Layout.Column = [1 3]; comparePanel.BackgroundColor = Theme.COLOR_CARD;
    comparePanel.Scrollable = 'on';

    comp = uigridlayout(comparePanel, [1 1]);
    comp.Padding = [12 10 12 10]; comp.BackgroundColor = Theme.COLOR_CARD;
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
    % Prediction nav icon (char(9671) = ◇)
    tmp = uibutton(ng, 'Text', [char(9671) ' Prediction'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Prediction'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'primary');
    % Backends nav icon (char(9004) = ⌬)
    tmp = uibutton(ng, 'Text', [char(9004) ' Backends'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Backends'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');

    Logger.info('BenchmarkScreen', 'Benchmark tab UI built successfully');
end
