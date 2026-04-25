% CircuitCuttingScreen  Populates the Circuit Cutting section panel.
%
%   Layout (rows top-down):
%     Row 1 (34 px):    Toolbar — Mode switcher + Preset dropdown +
%                       Analyze Cuts + Run Cutting buttons.
%     Row 2 (22 px):    Status line (wraps if needed).
%     Row 3 ('1.1x'):   Cut Plan panel (left) | Backend Assignments (right).
%     Row 4 ('0.8x'):   Observables panel (left) | Options panel (right).
%     Row 5 (40 px):    Cancel Batch button (right-aligned).
%     Row 6 ('1x'):     Results panel (full width).
function CircuitCuttingScreen(app)
    Logger.info('CircuitCuttingScreen', 'Building Circuit Cutting tab UI');
    t = app.createSectionPage('Circuit Cutting');

    g = uigridlayout(t, [6 2]);
    g.RowHeight     = {34, 22, '1.1x', '0.8x', 40, '1x'};
    g.ColumnWidth   = {'1x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Row 1: Toolbar ───────────────────────────────────────────────────
    %   [Circuit ▼] | [Mode ▼] | (flex) | [Preset ▼] | [Analyze] | [Run]
    %   Circuit dropdown lives on this screen so the user doesn't need to
    %   bounce to Circuits/Upload first. Items are loaded in
    %   CircuitCuttingViewModel.loadCircuits() when the tab is entered.
    tb = uigridlayout(g, [1 8]);
    tb.Layout.Row = 1; tb.Layout.Column = [1 2];
    tb.ColumnWidth = {60, 200, 50, 140, '1x', 180, 120, 120};
    tb.Padding = [0 0 0 0]; tb.ColumnSpacing = 8;
    tb.BackgroundColor = Theme.COLOR_BG;

    circLbl = uilabel(tb, 'Text', 'Circuit', ...
        'FontSize', 13, 'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    circLbl.Layout.Column = 1;

    app.CuttingCircuitDropdown = uidropdown(tb, ...
        'Items', {'(loading...)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~) app.CircuitCuttingVm.onCircuitChanged(src.Value));
    app.CuttingCircuitDropdown.Layout.Column = 2;
    app.CuttingCircuitDropdown.Tooltip = ...
        'Pick the circuit to cut. Populated from the current project on tab open.';

    modeLbl = uilabel(tb, 'Text', 'Mode', ...
        'FontSize', 13, 'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    modeLbl.Layout.Column = 3;

    app.CuttingModeDropdown = uidropdown(tb, ...
        'Items', {'Automatic','Assisted','Manual'}, ...
        'ItemsData', {'automatic','assisted','manual'}, ...
        'Value', 'assisted', ...
        'ValueChangedFcn', @(src,~) app.CircuitCuttingVm.onModeChanged(src.Value));
    app.CuttingModeDropdown.Layout.Column = 4;
    app.CuttingModeDropdown.Tooltip = ...
        'Automatic: one-click run. Assisted: review suggestions. Manual: enter everything.';

    app.CuttingPresetDropdown = uidropdown(tb, ...
        'Items', {'Generic'}, 'ItemsData', {'generic'}, ...
        'ValueChangedFcn', @(src,~) app.CircuitCuttingVm.onPresetChanged(src.Value));
    app.CuttingPresetDropdown.Layout.Column = 6;
    app.CuttingPresetDropdown.Tooltip = 'Phase 2 will add domain presets (CT Imaging 160Q, etc.).';

    analyzeBtn = uibutton(tb, 'Text', 'Analyze Cuts', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onAnalyzeCuts());
    analyzeBtn.Layout.Column = 7;
    app.styleBtn(analyzeBtn, 'ghost');

    runBtn = uibutton(tb, 'Text', 'Run Cutting', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onRunCutting());
    runBtn.Layout.Column = 8;
    app.styleBtn(runBtn, 'primary');

    % ── Row 2: Status line ──────────────────────────────────────────────
    app.CuttingStatusLabel = uilabel(g, ...
        'Text', 'Select a circuit and press Analyze Cuts to begin.', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'WordWrap', 'on', 'Interpreter', 'none');
    app.CuttingStatusLabel.Layout.Row = 2;
    app.CuttingStatusLabel.Layout.Column = [1 2];

    % ── Row 3 Left: Cut Plan ────────────────────────────────────────────
    planPanel = uipanel(g, 'Title', 'Cut Plan', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    planPanel.Layout.Row = 3; planPanel.Layout.Column = 1;
    planPanel.BackgroundColor = Theme.COLOR_CARD;
    pg = uigridlayout(planPanel, [1 1]);
    pg.Padding = [10 10 10 10]; pg.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingPlanText = uitextarea(pg, ...
        'Value', 'Run Analyze Cuts to see candidate cut plans.', ...
        'Editable', 'off', 'FontSize', 12);

    % ── Row 3 Right: Backend Assignments ────────────────────────────────
    bePanel = uipanel(g, 'Title', 'Backend Assignments', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    bePanel.Layout.Row = 3; bePanel.Layout.Column = 2;
    bePanel.BackgroundColor = Theme.COLOR_CARD;
    beg = uigridlayout(bePanel, [1 1]);
    beg.Padding = [10 10 10 10]; beg.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingBackendText = uitextarea(beg, ...
        'Value', 'Backend assignments appear after Analyze Cuts.', ...
        'Editable', 'off', 'FontSize', 12);

    % ── Row 4 Left: Observables ─────────────────────────────────────────
    obsPanel = uipanel(g, 'Title', 'Observables (Pauli strings, one per line)', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    obsPanel.Layout.Row = 4; obsPanel.Layout.Column = 1;
    obsPanel.BackgroundColor = Theme.COLOR_CARD;
    og = uigridlayout(obsPanel, [1 1]);
    og.Padding = [10 10 10 10]; og.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingObservablesText = uitextarea(og, ...
        'Value', {CircuitCuttingViewModel.OBSERVABLES_PLACEHOLDER}, ...
        'Editable', 'on', 'FontSize', 12);

    % ── Row 4 Right: Options ────────────────────────────────────────────
    optPanel = uipanel(g, 'Title', 'Options', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    optPanel.Layout.Row = 4; optPanel.Layout.Column = 2;
    optPanel.BackgroundColor = Theme.COLOR_CARD;
    oog = uigridlayout(optPanel, [2 1]);
    oog.Padding = [10 10 10 10]; oog.RowHeight = {28, '1x'};
    oog.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingDistCheckbox = uicheckbox(oog, ...
        'Text', 'Also reconstruct bitstring distribution (extra shots)', ...
        'Value', false);
    app.CuttingDistCheckbox.Layout.Row = 1;
    hintLbl = uilabel(oog, ...
        'Text', sprintf(['Automatic / Assisted / Manual modes share the same pipeline; ' ...
                         'only UI auto-fill differs. Sampling overhead scales ~4^k for k cuts.']), ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on', 'Interpreter', 'none');
    hintLbl.Layout.Row = 2;

    % ── Row 5: Cancel Batch button ──────────────────────────────────────
    actions = uigridlayout(g, [1 2]);
    actions.Layout.Row = 5; actions.Layout.Column = [1 2];
    actions.ColumnWidth = {'1x', 140};
    actions.Padding = [0 0 0 0];
    actions.BackgroundColor = Theme.COLOR_BG;
    cancelBtn = uibutton(actions, 'Text', 'Cancel Batch', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onCancelBatch());
    cancelBtn.Layout.Column = 2;
    app.styleBtn(cancelBtn, 'ghost');

    % ── Row 6: Results ──────────────────────────────────────────────────
    resPanel = uipanel(g, 'Title', 'Reconstructed Results', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    resPanel.Layout.Row = 6; resPanel.Layout.Column = [1 2];
    resPanel.BackgroundColor = Theme.COLOR_CARD;
    rg = uigridlayout(resPanel, [1 1]);
    rg.Padding = [10 10 10 10]; rg.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingResultsLabel = uitextarea(rg, ...
        'Value', {'Reconstructed expectation values appear here once the batch completes.'}, ...
        'Editable', 'off', 'FontSize', 12);

    Logger.info('CircuitCuttingScreen', 'Circuit Cutting tab built');
end
