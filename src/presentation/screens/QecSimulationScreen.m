% QecSimulationScreen  Populates the QEC Simulation section panel.
%
%   Layout:
%     Row 1 (toolbar, 34 px): Run | Sweep | Compare | Clear  +  Next: QEC Viz (right).
%     Row 2 (config, 260 px): Code Config (left) | Noise Config (right).
%     Row 3 ('1.4x'):         Fidelity vs Error Rate (left) | Syndrome Distribution (right).
%     Row 4 ('0.8x'):         Correction Success (left)     | Results Table (right).
%
%   All visible strings come from resources/labels.properties via Labels.
function QecSimulationScreen(app)
    Logger.info('QecSimulationScreen', 'Building QEC Simulation tab UI');
    t = app.createSectionPage('QEC Simulation');

    g = uigridlayout(t, [4 3]);
    g.RowHeight     = {34, 260, '1.4x', '0.8x'};
    g.ColumnWidth   = {'1x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Toolbar ──────────────────────────────────────────────────────────
    toolbar = uigridlayout(g, [1 2]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {'1x', 180};
    toolbar.Padding = [0 0 0 0];
    toolbar.BackgroundColor = [0.96 0.97 0.99];

    leftBtns = uigridlayout(toolbar, [1 4]);
    leftBtns.Layout.Row = 1; leftBtns.Layout.Column = 1;
    leftBtns.ColumnWidth = {130, 140, 130, 70};
    leftBtns.Padding = [0 0 0 0]; leftBtns.ColumnSpacing = 8;
    leftBtns.BackgroundColor = [0.96 0.97 0.99];

    app.QecRunButton = uibutton(leftBtns, 'Text', Labels.get('qec_sim_btn_run', 'Run Simulation'), ...
        'ButtonPushedFcn', @(~,~)app.QecSimulationVm.onRunSimulation());
    app.QecRunButton.Layout.Row = 1; app.QecRunButton.Layout.Column = 1;
    app.styleBtn(app.QecRunButton, 'primary');
    app.QecRunButton.FontSize = 14;

    app.QecSweepButton = uibutton(leftBtns, 'Text', Labels.get('qec_sim_btn_sweep', 'Sweep Error Rates'), ...
        'ButtonPushedFcn', @(~,~)app.QecSimulationVm.onSweepErrorRates());
    app.QecSweepButton.Layout.Row = 1; app.QecSweepButton.Layout.Column = 2;
    app.styleBtn(app.QecSweepButton, 'secondary');
    app.QecSweepButton.FontSize = 14;

    app.QecCompareButton = uibutton(leftBtns, 'Text', Labels.get('qec_sim_btn_compare', 'Compare Codes'), ...
        'ButtonPushedFcn', @(~,~)app.QecSimulationVm.onCompareCodes());
    app.QecCompareButton.Layout.Row = 1; app.QecCompareButton.Layout.Column = 3;
    app.styleBtn(app.QecCompareButton, 'secondary');
    app.QecCompareButton.FontSize = 14;

    app.QecClearButton = uibutton(leftBtns, 'Text', Labels.get('qec_sim_btn_clear', 'Clear'), ...
        'ButtonPushedFcn', @(~,~)app.QecSimulationVm.onClear());
    app.QecClearButton.Layout.Row = 1; app.QecClearButton.Layout.Column = 4;
    app.styleBtn(app.QecClearButton, 'ghost');
    app.QecClearButton.FontSize = 14;

    nextBtn = uibutton(toolbar, 'Text', Labels.get('qec_sim_btn_next', 'Next: QEC Visualization'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('QEC Visualization'));
    nextBtn.Layout.Row = 1; nextBtn.Layout.Column = 2;
    app.styleBtn(nextBtn, 'primary');

    % ── Column divider (rows 2-4) ────────────────────────────────────────
    div = uipanel(g, 'Title', '');
    div.Layout.Row = [2 4]; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Code Configuration Panel (left, row 2) ──────────────────────────
    codePanel = uipanel(g, 'Title', Labels.get('qec_sim_panel_code', 'Code Configuration'));
    codePanel.Layout.Row = 2; codePanel.Layout.Column = 1;
    codePanel.BackgroundColor = [1 1 1];
    codePanel.FontWeight = 'bold';
    cpg = uigridlayout(codePanel, [5 2]);
    cpg.RowHeight = {28, 28, 28, 28, 28};
    cpg.ColumnWidth = {140, '1x'};
    cpg.Padding = [12 10 12 10]; cpg.RowSpacing = 8;
    cpg.BackgroundColor = [1 1 1];

    uilabel(cpg, 'Text', Labels.get('qec_sim_label_code_type', 'QEC Code'), ...
        'FontWeight', 'bold', 'FontSize', 12);
    app.QecCodeDropdown = uidropdown(cpg, 'Items', { ...
        Labels.get('qec_code_bitflip3',  '3-Qubit Bit-Flip'), ...
        Labels.get('qec_code_phaseflip3','3-Qubit Phase-Flip'), ...
        Labels.get('qec_code_shor9',     'Shor 9-Qubit'), ...
        Labels.get('qec_code_steane7',   'Steane 7-Qubit'), ...
        Labels.get('qec_code_perfect5',  '5-Qubit Perfect'), ...
        Labels.get('qec_code_surface',   'Surface Code'), ...
        Labels.get('qec_code_repetition','Repetition Code')}, ...
        'ItemsData', {'bitflip3','phaseflip3','shor9','steane7','perfect5','surface','repetition'}, ...
        'Value', 'bitflip3', ...
        'ValueChangedFcn', @(~,~)app.QecSimulationVm.onCodeTypeChanged());

    uilabel(cpg, 'Text', Labels.get('qec_sim_label_initial_state', 'Initial Logical State'), ...
        'FontWeight', 'bold', 'FontSize', 12);
    app.QecInitialStateDropdown = uidropdown(cpg, 'Items', { ...
        Labels.get('qec_state_0',     '|0> (Computational Zero)'), ...
        Labels.get('qec_state_1',     '|1> (Computational One)'), ...
        Labels.get('qec_state_plus',  '|+> (Hadamard Plus)'), ...
        Labels.get('qec_state_minus', '|-> (Hadamard Minus)'), ...
        Labels.get('qec_state_i',     '|i> (Y-basis Plus)'), ...
        Labels.get('qec_state_mi',    '|-i> (Y-basis Minus)'), ...
        Labels.get('qec_state_custom','Custom (theta, phi)')}, ...
        'ItemsData', {'0','1','+','-','i','-i','custom'}, ...
        'Value', '0', ...
        'ValueChangedFcn', @(~,~)app.QecSimulationVm.onInitialStateChanged());

    app.QecThetaLabel = uilabel(cpg, 'Text', Labels.get('qec_sim_label_custom_theta', 'Theta (0 to pi)'), ...
        'FontSize', 12, 'Visible', 'off');
    app.QecThetaSpinner = uispinner(cpg, 'Value', 0, 'Limits', [0 pi], 'Step', 0.1, ...
        'ValueDisplayFormat', '%.2f', 'Visible', 'off');

    app.QecPhiLabel = uilabel(cpg, 'Text', Labels.get('qec_sim_label_custom_phi', 'Phi (0 to 2pi)'), ...
        'FontSize', 12, 'Visible', 'off');
    app.QecPhiSpinner = uispinner(cpg, 'Value', 0, 'Limits', [0 2*pi], 'Step', 0.1, ...
        'ValueDisplayFormat', '%.2f', 'Visible', 'off');

    app.QecDistanceLabel = uilabel(cpg, 'Text', Labels.get('qec_sim_label_distance', 'Code Distance'), ...
        'FontSize', 12, 'Visible', 'off');
    app.QecDistanceSpinner = uispinner(cpg, 'Value', 3, 'Limits', [3 7], 'Step', 2, ...
        'Visible', 'off');

    % ── Noise Configuration Panel (right, row 2) ─────────────────────────
    noisePanel = uipanel(g, 'Title', Labels.get('qec_sim_panel_noise', 'Noise Configuration'));
    noisePanel.Layout.Row = 2; noisePanel.Layout.Column = 3;
    noisePanel.BackgroundColor = [1 1 1];
    noisePanel.FontWeight = 'bold';
    npg = uigridlayout(noisePanel, [4 2]);
    npg.RowHeight = {28, 36, 28, 28};
    npg.ColumnWidth = {140, '1x'};
    npg.Padding = [12 10 12 10]; npg.RowSpacing = 8;
    npg.BackgroundColor = [1 1 1];

    uilabel(npg, 'Text', Labels.get('qec_sim_label_noise_model', 'Noise Model'), ...
        'FontWeight', 'bold', 'FontSize', 12);
    app.QecNoiseDropdown = uidropdown(npg, 'Items', { ...
        Labels.get('qec_noise_bitflip',      'Bit-Flip Channel'), ...
        Labels.get('qec_noise_phaseflip',    'Phase-Flip Channel'), ...
        Labels.get('qec_noise_depolarizing', 'Depolarizing Channel'), ...
        Labels.get('qec_noise_amplitude',    'Amplitude Damping')}, ...
        'ItemsData', {'bitflip','phaseflip','depolarizing','amplitude_damping'}, ...
        'Value', 'bitflip');

    uilabel(npg, 'Text', Labels.get('qec_sim_label_error_prob', 'Error Probability (p)'), ...
        'FontWeight', 'bold', 'FontSize', 12);
    sliderGrid = uigridlayout(npg, [1 2]);
    sliderGrid.ColumnWidth = {'1x', 50};
    sliderGrid.Padding = [0 0 0 0]; sliderGrid.ColumnSpacing = 6;
    sliderGrid.BackgroundColor = [1 1 1];
    app.QecErrorProbSlider = uislider(sliderGrid, 'Limits', [0 0.5], ...
        'Value', AppConfig.getDouble('qec_default_error_prob', 0.05), ...
        'ValueChangedFcn', @(src,~)set(app.QecErrorProbLabel, 'Text', sprintf('%.3f', src.Value)));
    app.QecErrorProbLabel = uilabel(sliderGrid, 'Text', ...
        sprintf('%.3f', AppConfig.getDouble('qec_default_error_prob', 0.05)), ...
        'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    uilabel(npg, 'Text', Labels.get('qec_sim_label_rounds', 'Correction Rounds'), ...
        'FontWeight', 'bold', 'FontSize', 12);
    app.QecRoundsSpinner = uispinner(npg, ...
        'Value', AppConfig.getDouble('qec_default_rounds', 1), ...
        'Limits', [1 20], 'Step', 1);

    uilabel(npg, 'Text', Labels.get('qec_sim_label_trials', 'Monte Carlo Trials'), ...
        'FontWeight', 'bold', 'FontSize', 12);
    app.QecTrialsSpinner = uispinner(npg, ...
        'Value', AppConfig.getDouble('qec_default_trials', 1000), ...
        'Limits', [100 10000], 'Step', 100);

    % ── Fidelity vs Error Rate chart (left, row 3) ───────────────────────
    fidPanel = uipanel(g, 'Title', Labels.get('qec_sim_panel_fidelity', 'Fidelity vs Error Rate'));
    fidPanel.Layout.Row = 3; fidPanel.Layout.Column = 1;
    fidPanel.BackgroundColor = [1 1 1];
    fpg = uigridlayout(fidPanel, [1 1]);
    fpg.Padding = [10 10 10 10]; fpg.BackgroundColor = [1 1 1];
    app.QecFidelityAxes = uiaxes(fpg);
    % Demo data
    pDemo = linspace(0, 0.5, 30);
    fDemo = 1 - 1.5*pDemo.^2;
    plot(app.QecFidelityAxes, pDemo, fDemo, '-o', 'Color', [0.18 0.45 0.82], ...
        'LineWidth', 1.6, 'MarkerSize', 3);
    app.styleAxes(app.QecFidelityAxes);
    app.QecFidelityAxes.Title.String  = Labels.get('qec_sim_plot_fidelity_title', 'Fidelity vs Physical Error Rate (demo)');
    app.QecFidelityAxes.XLabel.String = Labels.get('qec_sim_plot_fidelity_x', 'Physical Error Probability (p)');
    app.QecFidelityAxes.YLabel.String = Labels.get('qec_sim_plot_fidelity_y', 'Logical Qubit Fidelity');

    % ── Syndrome Distribution chart (right, row 3) ───────────────────────
    synPanel = uipanel(g, 'Title', Labels.get('qec_sim_panel_syndrome', 'Syndrome Distribution'));
    synPanel.Layout.Row = 3; synPanel.Layout.Column = 3;
    synPanel.BackgroundColor = [1 1 1];
    spg = uigridlayout(synPanel, [1 1]);
    spg.Padding = [10 10 10 10]; spg.BackgroundColor = [1 1 1];
    app.QecSyndromeAxes = uiaxes(spg);
    % Demo data
    bar(app.QecSyndromeAxes, 1:4, [65 20 10 5], 'FaceColor', [0.56 0.27 0.68]);
    app.styleAxes(app.QecSyndromeAxes);
    app.QecSyndromeAxes.Title.String  = Labels.get('qec_sim_plot_syndrome_title', 'Syndrome Measurement Distribution (demo)');
    app.QecSyndromeAxes.XLabel.String = Labels.get('qec_sim_plot_syndrome_x', 'Syndrome Pattern');
    app.QecSyndromeAxes.YLabel.String = Labels.get('qec_sim_plot_syndrome_y', 'Frequency');

    % ── Correction Success (left, row 4) ──────────────────────────────────
    successPanel = uipanel(g, 'Title', Labels.get('qec_sim_panel_success', 'Correction Success Rate'));
    successPanel.Layout.Row = 4; successPanel.Layout.Column = 1;
    successPanel.BackgroundColor = [1 1 1];
    scpg = uigridlayout(successPanel, [1 1]);
    scpg.Padding = [10 10 10 10]; scpg.BackgroundColor = [1 1 1];
    app.QecSuccessAxes = uiaxes(scpg);
    barh(app.QecSuccessAxes, 1, 0.95, 'FaceColor', [0.10 0.54 0.36]);
    app.QecSuccessAxes.XLim = [0 1];
    app.QecSuccessAxes.YTickLabel = {'Success Rate'};
    app.styleAxes(app.QecSuccessAxes);
    app.QecSuccessAxes.Title.String = 'Correction Success Rate (demo)';

    % ── Results Table (right, row 4) ──────────────────────────────────────
    resultsPanel = uipanel(g, 'Title', Labels.get('qec_sim_panel_results', 'Simulation Results'));
    resultsPanel.Layout.Row = 4; resultsPanel.Layout.Column = 3;
    resultsPanel.BackgroundColor = [1 1 1];
    rpg = uigridlayout(resultsPanel, [1 1]);
    rpg.Padding = [10 10 10 10]; rpg.BackgroundColor = [1 1 1];
    app.QecResultsTable = uitable(rpg, ...
        'ColumnName', {'Code', 'Noise', 'p', 'Fidelity', 'Success%', 'Bloch [x,y,z]'}, ...
        'ColumnWidth', {100, 90, 50, 70, 70, 120}, ...
        'Data', {'Bit-Flip(3)', 'Bit-Flip', '0.05', '0.987', '97.0%', '[0.00, 0.00, 0.97]'});

    Logger.info('QecSimulationScreen', 'QEC Simulation tab UI built successfully');
end
