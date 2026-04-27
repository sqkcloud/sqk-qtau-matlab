% CircuitCuttingScreen  Builds the Circuit Cutting tab UI.
%
%   Modern IBM-Quantum / Google-Quantum-AI inspired layout — at-a-glance KPI
%   tiles on top, a dedicated status line, structured metric rows in the
%   Cut Plan card, a row-per-subcircuit Backend Assignments card, and a
%   polished empty state for the results panel.
%
%   Layout (rows top-down):
%     Row 1 (24 px):   Subtitle line
%     Row 2 (40 px):   Toolbar — Circuit / Mode / Preset / Analyze / Run / Cancel
%     Row 3 (108 px):  KPI strip (4 tiles: k, overhead, qubits, feasibility)
%     Row 4 (22 px):   Status line (full-width muted, written by VM.setStatus)
%     Row 5 ('1.3x'):  Cut Plan card (left) | Backend Assignments card (right)
%     Row 6 ('0.7x'):  Observables card (left) | Options card (right)
%     Row 7 ('1x'):    Reconstructed Results card
%
%   No new uihtml widgets — only standard MATLAB controls — to avoid the
%   stale-handle peerEvent class of bug we hit in the LoadingOverlay/Login
%   dialog flows.
function CircuitCuttingScreen(app)
    Logger.info('CircuitCuttingScreen', 'Building Circuit Cutting tab UI');
    t = app.createSectionPage('Circuit Cutting');

    g = uigridlayout(t, [7 2]);
    g.RowHeight     = {24, 40, 108, 22, '1.3x', '0.7x', '1x'};
    g.ColumnWidth   = {'1x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Row 1: Subtitle ──────────────────────────────────────────────────
    app.CuttingSubtitleLabel = uilabel(g, ...
        'Text', ['Cut wide circuits into k subcircuits, dispatch them across ' ...
                 'multiple QPUs in parallel, then reconstruct Pauli ' ...
                 'expectation values via qiskit-addon-cutting.'], ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'WordWrap', 'on', 'Interpreter', 'none');
    app.CuttingSubtitleLabel.Layout.Row = 1;
    app.CuttingSubtitleLabel.Layout.Column = [1 2];

    % ── Row 2: Toolbar ───────────────────────────────────────────────────
    %   [Circuit ▼] | [Mode ▼] | (flex) | [Preset ▼] | [Analyze] | [Run] | [Cancel]
    tb = uigridlayout(g, [1 9]);
    tb.Layout.Row = 2; tb.Layout.Column = [1 2];
    tb.ColumnWidth = {60, 220, 50, 140, '1x', 180, 140, 140, 140};
    tb.Padding = [0 0 0 0]; tb.ColumnSpacing = 8;
    tb.BackgroundColor = Theme.COLOR_BG;

    circLbl = uilabel(tb, 'Text', 'Circuit', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    circLbl.Layout.Column = 1;

    app.CuttingCircuitDropdown = uidropdown(tb, ...
        'Items', {'(loading...)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~) app.CircuitCuttingVm.onCircuitChanged(src.Value));
    app.CuttingCircuitDropdown.Layout.Column = 2;
    app.CuttingCircuitDropdown.Tooltip = ...
        'Pick the circuit to cut. Populated from the current project on tab open.';

    modeLbl = uilabel(tb, 'Text', 'Mode', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, ...
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

    %  Unicode glyphs as inline icons — keeps the design portable (no
    %  external image assets) and works in every theme. ⌕ = magnifier
    %  for analysis, ▶ = run/dispatch, ✕ = cancel/abort.
    analyzeBtn = uibutton(tb, 'Text', '⌕  Analyze Cuts', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onAnalyzeCuts());
    analyzeBtn.Layout.Column = 7;
    app.styleBtn(analyzeBtn, 'ghost');

    runBtn = uibutton(tb, 'Text', '▶  Run Cutting', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onRunCutting());
    runBtn.Layout.Column = 8;
    app.styleBtn(runBtn, 'primary');

    cancelBtn = uibutton(tb, 'Text', '✕  Cancel Batch', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onCancelBatch());
    cancelBtn.Layout.Column = 9;
    app.styleBtn(cancelBtn, 'ghost');

    % ── Row 3: KPI strip ─────────────────────────────────────────────────
    kpiRow = uigridlayout(g, [1 4]);
    kpiRow.Layout.Row = 3; kpiRow.Layout.Column = [1 2];
    kpiRow.ColumnWidth = {'1x', '1x', '1x', '1x'};
    kpiRow.Padding = [0 0 0 0]; kpiRow.ColumnSpacing = 12;
    kpiRow.BackgroundColor = Theme.COLOR_BG;

    app.CuttingKpiKValue        = localBuildKpiTile(kpiRow, 1, 'SUBCIRCUITS', '—');
    app.CuttingKpiOverheadValue = localBuildKpiTile(kpiRow, 2, 'SAMPLING OVERHEAD', '—');
    app.CuttingKpiQubitsValue   = localBuildKpiTile(kpiRow, 3, 'PER-SUBCIRCUIT QUBITS', '—');
    [app.CuttingKpiFeasibilityChip, app.CuttingKpiFeasibilityPanel] = ...
        localBuildFeasibilityTile(kpiRow, 4);

    % ── Row 4: Status line ───────────────────────────────────────────────
    %   Single-line, full-width muted label. Written by VM.setStatus()
    %   during analyze/poll flows ("Batch xxx status=running 50%").
    app.CuttingStatusLabel = uilabel(g, ...
        'Text', '', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'WordWrap', 'off', 'Interpreter', 'none');
    app.CuttingStatusLabel.Layout.Row = 4;
    app.CuttingStatusLabel.Layout.Column = [1 2];

    % ── Row 5 Left: Cut Plan card ────────────────────────────────────────
    planPanel = uipanel(g, 'Title', 'Cut Plan', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING);
    planPanel.Layout.Row = 5; planPanel.Layout.Column = 1;
    planPanel.BackgroundColor = Theme.COLOR_CARD;

    pg = uigridlayout(planPanel, [6 2]);
    pg.RowHeight   = {22, 22, 22, 22, 22, '1x'};
    pg.ColumnWidth = {180, '1x'};
    pg.Padding     = [16 12 16 12];
    pg.RowSpacing  = 4; pg.ColumnSpacing = 14;
    pg.BackgroundColor = Theme.COLOR_CARD;

    app.CuttingPlanKValue        = localBuildPlanRow(pg, 1, 'k', '—');
    app.CuttingPlanCutsValue     = localBuildPlanRow(pg, 2, 'Cuts detected', '—');
    app.CuttingPlanOverheadValue = localBuildPlanRow(pg, 3, 'Sampling overhead', '—');
    app.CuttingPlanLog10Value    = localBuildPlanRow(pg, 4, 'log₁₀(overhead)', '—');
    app.CuttingPlanPerSubValue   = localBuildPlanRow(pg, 5, 'Per-subcircuit qubits', '—');

    % Wrapped feasibility-reason text (hidden until an infeasible plan arrives).
    app.CuttingPlanReasonLabel = uilabel(pg, ...
        'Text', '', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_DANGER, ...
        'WordWrap', 'on', 'Interpreter', 'none', ...
        'VerticalAlignment', 'top', 'Visible', 'off');
    app.CuttingPlanReasonLabel.Layout.Row = 6;
    app.CuttingPlanReasonLabel.Layout.Column = [1 2];

    % Drop the hidden legacy textarea entirely — was eating a grid slot
    % and the VM no longer writes to it.
    app.CuttingPlanText = [];

    % ── Row 5 Right: Backend Assignments card ────────────────────────────
    bePanel = uipanel(g, 'Title', 'Backend Assignments', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING);
    bePanel.Layout.Row = 5; bePanel.Layout.Column = 2;
    bePanel.BackgroundColor = Theme.COLOR_CARD;

    app.CuttingBackendGrid = uigridlayout(bePanel, [1 1]);
    app.CuttingBackendGrid.RowHeight = {'1x'};
    app.CuttingBackendGrid.ColumnWidth = {'1x'};
    app.CuttingBackendGrid.Padding = [16 12 16 12];
    app.CuttingBackendGrid.RowSpacing = 6;
    app.CuttingBackendGrid.BackgroundColor = Theme.COLOR_CARD;

    app.CuttingBackendEmptyLabel = uilabel(app.CuttingBackendGrid, ...
        'Text', 'Run Analyze Cuts to assign each subcircuit to a backend.', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'WordWrap', 'on', 'Interpreter', 'none');
    app.CuttingBackendEmptyLabel.Layout.Row = 1;
    app.CuttingBackendEmptyLabel.Layout.Column = 1;

    % Drop the hidden legacy textarea — was occupying a grid cell and
    % capping the number of backend rows that could fit.
    app.CuttingBackendText = [];

    % ── Row 6 Left: Observables card ─────────────────────────────────────
    obsPanel = uipanel(g, 'Title', 'Observables', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING);
    obsPanel.Layout.Row = 6; obsPanel.Layout.Column = 1;
    obsPanel.BackgroundColor = Theme.COLOR_CARD;
    og = uigridlayout(obsPanel, [2 1]);
    og.RowHeight = {18, '1x'};
    og.Padding = [16 12 16 12]; og.RowSpacing = 6;
    og.BackgroundColor = Theme.COLOR_CARD;

    obsCaption = uilabel(og, ...
        'Text', 'Pauli strings, one per line — leave blank for all-Z over full width.', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on', 'Interpreter', 'none');
    obsCaption.Layout.Row = 1;

    app.CuttingObservablesText = uitextarea(og, ...
        'Value', {CircuitCuttingViewModel.OBSERVABLES_PLACEHOLDER}, ...
        'Editable', 'on', 'FontSize', 12);
    app.CuttingObservablesText.Layout.Row = 2;

    % ── Row 6 Right: Options card ────────────────────────────────────────
    %   No more status line inside this card — moved to dedicated Row 4.
    optPanel = uipanel(g, 'Title', 'Options', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING);
    optPanel.Layout.Row = 6; optPanel.Layout.Column = 2;
    optPanel.BackgroundColor = Theme.COLOR_CARD;
    oog = uigridlayout(optPanel, [2 1]);
    oog.RowHeight = {28, '1x'};
    oog.Padding = [16 12 16 12]; oog.RowSpacing = 8;
    oog.BackgroundColor = Theme.COLOR_CARD;

    app.CuttingDistCheckbox = uicheckbox(oog, ...
        'Text', 'Also reconstruct bitstring distribution (extra shots)', ...
        'Value', false, 'FontSize', 12, 'FontColor', Theme.COLOR_LABEL);
    app.CuttingDistCheckbox.Layout.Row = 1;

    hintLbl = uilabel(oog, ...
        'Text', sprintf(['Automatic / Assisted / Manual modes share the same pipeline; ' ...
                         'only UI auto-fill differs. Sampling overhead grows ~4ᵏ with k cuts, ' ...
                         'so a smaller k means a tighter shot budget.']), ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on', 'Interpreter', 'none', ...
        'VerticalAlignment', 'top');
    hintLbl.Layout.Row = 2;

    % ── Row 7: Reconstructed Results card ────────────────────────────────
    resPanel = uipanel(g, 'Title', 'Reconstructed Results', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING);
    resPanel.Layout.Row = 7; resPanel.Layout.Column = [1 2];
    resPanel.BackgroundColor = Theme.COLOR_CARD;
    rg = uigridlayout(resPanel, [1 1]);
    rg.Padding = [18 14 18 14]; rg.BackgroundColor = Theme.COLOR_CARD;

    % Empty state (visible until renderResult writes real values).
    app.CuttingResultsEmptyLabel = uilabel(rg, ...
        'Text', sprintf(['⚛  Reconstructed expectation values land here when ' ...
                         'the batch finishes.\n\n' ...
                         'Press Run Cutting to dispatch k subcircuits to your ' ...
                         'assigned backends. Once every child job completes, ' ...
                         'qiskit-addon-cutting reconstructs the full-circuit ' ...
                         'observable expectations from the partial results.']), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'WordWrap', 'on', 'Interpreter', 'none');

    % Real-results textarea — created hidden, made visible by renderResult.
    app.CuttingResultsLabel = uitextarea(rg, ...
        'Value', '', 'Editable', 'off', 'FontSize', 12, ...
        'Visible', 'off');

    Logger.info('CircuitCuttingScreen', 'Circuit Cutting tab built');
end


% ── Local helpers (file-private — not on the class) ────────────────────────
function valueLbl = localBuildKpiTile(parent, col, captionText, initialValue)
    %  Build one neutral KPI tile: small uppercase caption above a large
    %  value. Returns the value uilabel handle so the VM can update it.
    panel = uipanel(parent, ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, 'Title', '');
    panel.Layout.Column = col;

    grid = uigridlayout(panel, [2 1]);
    grid.RowHeight = {16, '1x'};
    grid.Padding = [18 14 18 14]; grid.RowSpacing = 4;
    grid.BackgroundColor = Theme.COLOR_CARD;

    caption = uilabel(grid, ...
        'Text', captionText, ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'Interpreter', 'none');
    caption.Layout.Row = 1;

    valueLbl = uilabel(grid, ...
        'Text', initialValue, ...
        'FontSize', 22, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'Interpreter', 'none');
    valueLbl.Layout.Row = 2;
end


function [chip, panel] = localBuildFeasibilityTile(parent, col)
    %  Special KPI tile whose value is a colored pill ("● OK" / "● Override
    %  required"). Returns both the chip uilabel and its backing panel so
    %  the VM can recolor the pill background based on feasibility state.
    panel = uipanel(parent, ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, 'Title', '');
    panel.Layout.Column = col;

    grid = uigridlayout(panel, [2 1]);
    grid.RowHeight = {16, '1x'};
    grid.Padding = [18 14 18 14]; grid.RowSpacing = 6;
    grid.BackgroundColor = Theme.COLOR_CARD;

    caption = uilabel(grid, ...
        'Text', 'FEASIBILITY', ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'Interpreter', 'none');
    caption.Layout.Row = 1;

    % Wrap the chip in a 2-col x 3-row inner grid so it stays a fixed-size
    % pill (180×26) anchored to the left edge instead of stretching to the
    % full tile area.
    chipOuter = uigridlayout(grid, [3 2]);
    chipOuter.RowHeight   = {'1x', 26, '1x'};
    chipOuter.ColumnWidth = {180, '1x'};
    chipOuter.Padding = [0 0 0 0];
    chipOuter.RowSpacing = 0; chipOuter.ColumnSpacing = 0;
    chipOuter.BackgroundColor = Theme.COLOR_CARD;
    chipOuter.Layout.Row = 2;

    chip = uilabel(chipOuter, ...
        'Text', '  —  Pending  ', ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_ACCENT_BG, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'Interpreter', 'none');
    chip.Layout.Row = 2; chip.Layout.Column = 1;

    % Right-side spacer so the chip stays left-aligned.
    spacer = uilabel(chipOuter, 'Text', '', 'BackgroundColor', Theme.COLOR_CARD);
    spacer.Layout.Row = 2; spacer.Layout.Column = 2;
end


function valueLbl = localBuildPlanRow(parent, row, labelText, initialValue)
    %  One label/value row inside the Cut Plan card. Returns the value
    %  label so the VM can update it on render.
    keyLbl = uilabel(parent, ...
        'Text', labelText, ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'Interpreter', 'none');
    keyLbl.Layout.Row = row; keyLbl.Layout.Column = 1;

    valueLbl = uilabel(parent, ...
        'Text', initialValue, ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'Interpreter', 'none');
    valueLbl.Layout.Row = row; valueLbl.Layout.Column = 2;
end
