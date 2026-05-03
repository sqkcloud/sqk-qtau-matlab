% CircuitCuttingScreen  Builds the Circuit Cutting tab UI.
%
%   Modern IBM-Quantum / Google-Quantum-AI inspired layout — at-a-glance KPI
%   tiles on top, a dedicated status line, structured metric rows in the
%   Cut Plan card, a row-per-subcircuit Backend Assignments card, and a
%   polished empty state for the results panel.
%
%   Layout (rows top-down) — sized for the default 1600×870 figure where
%   the screen body is ~669 px tall (figure 870 minus app header 52, the
%   shellGrid header card 82, separator 1, padding 32, spacing 24):
%     Row 1 (40 px):   Toolbar — Circuit / Mode / Target k / Preset /
%                       Analyze / Run / Cancel
%     Row 2 (22 px):   Status line (full-width muted, written by VM.setStatus —
%                       sits directly under the toolbar so the "Mode / Preset /
%                       Press Analyze Cuts to begin" hint reads as a toolbar tail)
%     Row 3 (108 px):  KPI strip (4 tiles: k, overhead, qubits, feasibility)
%     Row 4 (210 px):  Cut Plan card (left) | Backend Assignments card (right)
%                       — fits the wrapped feasibility-reason warning (3 lines
%                         at 1600 px) plus the override-confirmation line.
%     Row 5 (130 px):  Observables card (left) | Options card (right)
%                       — keeps the textarea at ~3 visible rows and the
%                         Options hint fully readable.
%     Row 6 ('1x'):    Reconstructed Results card — absorbs leftover space
%                       (~95 px at default size, room for the 2-paragraph
%                         empty-state copy; grows freely when enlarged).
%
%   Outer grid Padding 12 / RowSpacing 8 (instead of Theme.GRID_PADDING 16
%   / Theme.GRID_ROW_SPACING 12) reclaims ~28 px to make the row budget
%   fit the 669 px body. Card-internal vertical padding is also trimmed
%   from 12 → 8 so the reason text, textarea, hint, and empty-state copy
%   all retain enough room within the tighter row heights.
%
%   The long descriptive sentence ("Cut wide circuits into k subcircuits,
%   dispatch them across multiple QPUs in parallel, then reconstruct Pauli
%   expectation values via qiskit-addon-cutting.") lives in the screen
%   header subtitle slot via Labels.get('subtitle_circuit_cutting'), wired
%   up in NavigationManager.sectionSubtitleFor — not as a row inside the
%   screen body.
%
%   Compatibility verdicts (mid-circuit measurements, classical-controlled
%   gates, resets) are surfaced as a modal uialert popup fired by
%   CircuitCuttingViewModel.maybeAlertCuttability — no inline banner.
%
%   No new uihtml widgets — only standard MATLAB controls — to avoid the
%   stale-handle peerEvent class of bug we hit in the LoadingOverlay/Login
%   dialog flows.
function CircuitCuttingScreen(app)
    Logger.info('CircuitCuttingScreen', 'Building Circuit Cutting tab UI');
    t = app.createSectionPage('Circuit Cutting');

    g = uigridlayout(t, [6 2]);
    %  Row sizing strategy: pin the two content-heavy card rows
    %  (Cut Plan / Backend Assignments and Observables / Options) to fixed
    %  pixel heights large enough for the worst-case content at the
    %  default 1600×940 window. The Reconstructed Results row uses '1x'
    %  so it absorbs any leftover vertical space when the operator
    %  enlarges the window. On smaller windows the section panel itself
    %  is Scrollable='on' (NavigationManager.createSectionPage), so the
    %  whole screen scrolls instead of clipping cards.
    %
    %  Why fixed (not flex) for rows 4-5: with flex weights, MATLAB
    %  squeezes the Cut Plan card below the height needed for the wrapped
    %  feasibility-reason warning (5+ lines) plus the override-confirmation
    %  line. uilabel WordWrap='on' under-reports its natural height to the
    %  layout engine, so 'fit' rows do not always paint a scrollbar — they
    %  just clip. Fixed pixels avoid that whole class of bug.
    %
    %  Sized to fit at the default 1800×870 figure where the screen body is
    %  only ~669 px (after the 52 px app header, the 82 px section-title
    %  card, the 1 px separator, and shellGrid padding 32 + spacing 24).
    %
    %  Outer overhead is trimmed (Padding 12 instead of 16, RowSpacing 8
    %  instead of 12) to recover ~28 px for the row budget.
    %
    %  Cut Plan budget (210 px): title 30 + inner padding 16 (top+bottom 8
    %  via pg.Padding override below) + metric row 78 + spacing 6 = 130 →
    %  80 px for the wrapped reason label, comfortable for 5-6 lines of
    %  11 pt font including the override-confirmation line.
    %
    %  Observables / Options budget (130 px): title 30 + inner padding 16
    %  (top+bottom 8 via og.Padding override below) + caption 18 + spacing
    %  6 = 70 → 60 px for the textarea, ~3-4 visible lines, plus enough
    %  room for the Options checkbox + 2-line wrapped hint.
    %
    %  Reconstructed Results uses '1x' so it absorbs all leftover space —
    %  ~95 px at 870 figure (room for the 2-paragraph empty-state copy)
    %  and grows freely when the operator enlarges the window.
    g.RowHeight     = {40, 22, 108, 210, 130, '1x'};
    g.ColumnWidth   = {'1x', '1x'};
    g.Padding       = [12 12 12 12];
    g.RowSpacing    = 8;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % Subtitle paragraph is rendered by NavigationManager in the screen
    % header next to the "Circuit Cutting" title via
    % Labels.get('subtitle_circuit_cutting') — no in-screen row.

    % ── Row 1: Toolbar ───────────────────────────────────────────────────
    %   [Circuit ▼] | [Mode ▼] | [Target k spinner] | (flex) | [Preset ▼] |
    %   [Analyze] | [Run] | [Cancel]
    tb = uigridlayout(g, [1 11]);
    tb.Layout.Row = 1; tb.Layout.Column = [1 2];
    tb.ColumnWidth = {60, 180, 50, 110, 56, 80, '1x', 140, 120, 100, 110};
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
        'Items', {'AUTOMATIC','ASSISTED','MANUAL'}, ...
        'ItemsData', {'automatic','assisted','manual'}, ...
        'Value', 'assisted', ...
        'ValueChangedFcn', @(src,~) app.CircuitCuttingVm.onModeChanged(src.Value));
    app.CuttingModeDropdown.Layout.Column = 4;
    app.CuttingModeDropdown.Tooltip = ...
        'Automatic: one-click run. Assisted: review suggestions. Manual: enter everything.';

    %  Target k spinner. 0 = auto (let the addon decide). 2..32 forces a
    %  specific number of subcircuits — the recovery path the server
    %  itself suggests when find_cuts overflows float64 on a very wide
    %  or densely-entangling circuit (e.g. qugan_n395.qasm).
    targetKLbl = uilabel(tb, 'Text', 'Target k', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    targetKLbl.Layout.Column = 5;

    app.CuttingTargetKSpin = uispinner(tb, ...
        'Value', 0, 'Limits', [0 32], 'Step', 1, ...
        'ValueDisplayFormat', '%d', ...
        'Tooltip', sprintf(['Force target_k subcircuits. Leave at 0 to ' ...
                            'let the addon pick automatically. Useful when ' ...
                            'a 100+ qubit circuit overflows the addon''s ' ...
                            'gamma upper bound.']));
    app.CuttingTargetKSpin.Layout.Column = 6;

    app.CuttingPresetDropdown = uidropdown(tb, ...
        'Items', {'Generic'}, 'ItemsData', {'generic'}, ...
        'ValueChangedFcn', @(src,~) app.CircuitCuttingVm.onPresetChanged(src.Value));
    app.CuttingPresetDropdown.Layout.Column = 8;
    app.CuttingPresetDropdown.Tooltip = 'Phase 2 will add domain presets (CT Imaging 160Q, etc.).';

    %  Unicode glyphs as inline icons — keeps the design portable (no
    %  external image assets) and works in every theme. ⌕ = magnifier
    %  for analysis, ▶ = run/dispatch, ✕ = cancel/abort. Analyze/Run
    %  handles are stored on the app so the VM can disable them when
    %  the QASM scanner finds an un-cuttable circuit.
    %  Short labels — context is clear from the screen title above. Tooltip
    %  spells out the full action.
    app.CuttingAnalyzeBtn = uibutton(tb, 'Text', '⌕  Analyze', ...
        'Tooltip', 'Analyze cuts for the selected circuit', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onAnalyzeCuts());
    app.CuttingAnalyzeBtn.Layout.Column = 9;
    app.styleBtn(app.CuttingAnalyzeBtn, 'ghost');

    app.CuttingRunBtn = uibutton(tb, 'Text', '▶  Run', ...
        'Tooltip', 'Dispatch the cut subcircuits to the assigned backends', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onRunCutting());
    app.CuttingRunBtn.Layout.Column = 10;
    app.styleBtn(app.CuttingRunBtn, 'primary');

    cancelBtn = uibutton(tb, 'Text', '✕  Cancel', ...
        'Tooltip', 'Cancel the active cutting batch', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onCancelBatch());
    cancelBtn.Layout.Column = 11;
    app.styleBtn(cancelBtn, 'ghost');

    % ── Row 2: Status line + mitigation cost preview ─────────────────────
    %   Two muted labels share Row 2.
    %     Column 1 — VM-written status banner (analyze/poll progress,
    %                build-time "Mode: assisted  Preset: generic  Press
    %                Analyze Cuts to begin.").
    %     Column 2 — Mitigation cost preview (right-aligned).
    %                Populated by CircuitCuttingViewModel.applyAnalyze
    %                from POST /api/mitigation/estimate. Empty until
    %                Analyze succeeds; format:
    %                "Mitigation: Standard · ~1× shots · est. 2s".
    app.CuttingStatusLabel = uilabel(g, ...
        'Text', '', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center', ...
        'WordWrap', 'off', 'Interpreter', 'none');
    app.CuttingStatusLabel.Layout.Row = 2;
    app.CuttingStatusLabel.Layout.Column = 1;

    app.CuttingMitigationLabel = uilabel(g, ...
        'Text', '', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center', ...
        'WordWrap', 'off', 'Interpreter', 'none', ...
        'Tooltip', ['Mitigation profile applied to this submission. ' ...
                    'Click Analyze Cuts to refresh; level dropdown ' ...
                    'lands in a follow-up.']);
    app.CuttingMitigationLabel.Layout.Row = 2;
    app.CuttingMitigationLabel.Layout.Column = 2;

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

    % ── Row 4 Left: Cut Plan card ────────────────────────────────────────
    %   Scrollable='on' so a long feasibility-reason text (or a small
    %   window) yields a vertical scrollbar instead of clipping rows.
    planPanel = uipanel(g, 'Title', 'Cut Plan', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'Scrollable', 'on');
    planPanel.Layout.Row = 4; planPanel.Layout.Column = 1;
    planPanel.BackgroundColor = Theme.COLOR_CARD;

    %  Two-column metric layout: 2-row × 2-col outer grid where row 1
    %  hosts a left and a right metric sub-grid, and row 2 hosts the
    %  feasibility-reason label spanning both columns.
    %
    %  Left column     Right column
    %  ────────────────────────────────────
    %  k                log₁₀(overhead)
    %  Cuts detected    Per-subcircuit qubits
    %  Sampling overhead   (empty)
    %  ────────────────────────────────────
    %  ⚠  feasibility reason text (spans both columns when shown)
    %
    %  Outer row 2 uses 'fit' so a long wrapped reason makes the grid
    %  taller than the panel and triggers planPanel.Scrollable.
    pg = uigridlayout(planPanel, [2 2]);
    pg.RowHeight   = {78, 'fit'};
    pg.ColumnWidth = {'1x', '1x'};
    %  Top/bottom padding trimmed from 12 → 8 to reclaim ~8 px for the
    %  reason label so the 5-line worst-case wrap (warning + override
    %  confirmation) is fully visible inside the 210 px outer row budget
    %  at the default 1800×870 figure.
    pg.Padding     = [16 8 16 8];
    pg.RowSpacing  = 6;
    pg.ColumnSpacing = 24;
    pg.BackgroundColor = Theme.COLOR_CARD;

    leftCol = uigridlayout(pg, [3 2]);
    leftCol.RowHeight     = {22, 22, 22};
    leftCol.ColumnWidth   = {130, '1x'};
    leftCol.Padding       = [0 0 0 0];
    leftCol.RowSpacing    = 4;
    leftCol.ColumnSpacing = 12;
    leftCol.BackgroundColor = Theme.COLOR_CARD;
    leftCol.Layout.Row = 1; leftCol.Layout.Column = 1;

    app.CuttingPlanKValue        = localBuildPlanRow(leftCol, 1, 'k', '—');
    app.CuttingPlanCutsValue     = localBuildPlanRow(leftCol, 2, 'Cuts detected', '—');
    app.CuttingPlanOverheadValue = localBuildPlanRow(leftCol, 3, 'Sampling overhead', '—');

    rightCol = uigridlayout(pg, [3 2]);
    rightCol.RowHeight     = {22, 22, 22};
    rightCol.ColumnWidth   = {150, '1x'};
    rightCol.Padding       = [0 0 0 0];
    rightCol.RowSpacing    = 4;
    rightCol.ColumnSpacing = 12;
    rightCol.BackgroundColor = Theme.COLOR_CARD;
    rightCol.Layout.Row = 1; rightCol.Layout.Column = 2;

    app.CuttingPlanLog10Value  = localBuildPlanRow(rightCol, 1, 'log₁₀(overhead)', '—');
    app.CuttingPlanPerSubValue = localBuildPlanRow(rightCol, 2, 'Per-subcircuit qubits', '—');
    % Row 3 of the right column is intentionally empty — keeps both columns
    % the same height so the reason text below sits on a clean baseline.

    %  Wrapped feasibility-reason text (hidden until an infeasible plan
    %  arrives). Spans both metric columns.
    app.CuttingPlanReasonLabel = uilabel(pg, ...
        'Text', '', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_DANGER, ...
        'WordWrap', 'on', 'Interpreter', 'none', ...
        'VerticalAlignment', 'top', 'Visible', 'off');
    app.CuttingPlanReasonLabel.Layout.Row = 2;
    app.CuttingPlanReasonLabel.Layout.Column = [1 2];

    % Drop the hidden legacy textarea entirely — was eating a grid slot
    % and the VM no longer writes to it.
    app.CuttingPlanText = [];

    % ── Row 4 Right: Backend Assignments card ────────────────────────────
    %   Scrollable='on' so large k (e.g. k=68 for an unpacked BV-140)
    %   yields a vertical scrollbar instead of capping the visible rows.
    bePanel = uipanel(g, 'Title', 'Backend Assignments', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'Scrollable', 'on');
    bePanel.Layout.Row = 4; bePanel.Layout.Column = 2;
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

    % ── Row 5 Left: Observables card ─────────────────────────────────────
    %   Three-row inner grid: (1) static caption, (2) hardware-aware
    %   coherence warning that VM.applyAnalyze toggles on for n>50
    %   GHZ/cat circuits, (3) the Pauli-string textarea. The warning
    %   row uses 'fit' height so it collapses to zero when the label
    %   is hidden — preserving the 130 px outer Row 5 budget when no
    %   warning is active. obsPanel sets Scrollable='on' as a safety
    %   so an unusually long warning text scrolls inside the panel
    %   rather than clipping the textarea.
    obsPanel = uipanel(g, 'Title', 'Observables', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'Scrollable', 'on');
    obsPanel.Layout.Row = 5; obsPanel.Layout.Column = 1;
    obsPanel.BackgroundColor = Theme.COLOR_CARD;
    og = uigridlayout(obsPanel, [3 1]);
    og.RowHeight = {18, 'fit', '1x'};
    %  Top/bottom padding trimmed (12 → 8) so the textarea keeps ~3-4
    %  visible lines inside the 130 px outer row budget at default size.
    og.Padding = [16 8 16 8]; og.RowSpacing = 6;
    og.BackgroundColor = Theme.COLOR_CARD;

    obsCaption = uilabel(og, ...
        'Text', 'Pauli strings, one per line — leave blank for all-Z over full width.', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on', 'Interpreter', 'none');
    obsCaption.Layout.Row = 1;

    %  Hardware-aware coherence warning. Hidden by default; populated
    %  by CircuitCuttingViewModel.applyAnalyze when the analyze
    %  response carries a non-empty coherence_warning field (n > 50
    %  GHZ/cat on real hardware — weight-N witnesses sit at the noise
    %  floor and static observables can't verify coherence at that
    %  scale). Uses the warning amber so it reads as advisory, not
    %  error. Visible='off' keeps the row collapsed via 'fit' height.
    app.CuttingObservablesWarning = uilabel(og, ...
        'Text', '', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_WARNING, ...
        'WordWrap', 'on', 'Interpreter', 'none', ...
        'Visible', 'off');
    app.CuttingObservablesWarning.Layout.Row = 2;

    app.CuttingObservablesText = uitextarea(og, ...
        'Value', {CircuitCuttingViewModel.OBSERVABLES_PLACEHOLDER}, ...
        'Editable', 'on', 'FontSize', 12);
    app.CuttingObservablesText.Layout.Row = 3;

    % ── Row 5 Right: Options card ────────────────────────────────────────
    %   No more status line inside this card — moved to dedicated Row 4.
    optPanel = uipanel(g, 'Title', 'Options', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING);
    optPanel.Layout.Row = 5; optPanel.Layout.Column = 2;
    optPanel.BackgroundColor = Theme.COLOR_CARD;
    oog = uigridlayout(optPanel, [2 1]);
    oog.RowHeight = {28, '1x'};
    %  Top/bottom padding trimmed (12 → 8) so the wrapped hint fits the
    %  130 px outer row budget without clipping at default size.
    oog.Padding = [16 8 16 8]; oog.RowSpacing = 8;
    oog.BackgroundColor = Theme.COLOR_CARD;

    app.CuttingDistCheckbox = uicheckbox(oog, ...
        'Text', 'Also reconstruct bitstring distribution (extra shots)', ...
        'Value', false, 'FontSize', 12, 'FontColor', Theme.COLOR_LABEL);
    app.CuttingDistCheckbox.Layout.Row = 1;

    hintLbl = uilabel(oog, ...
        'Text', ['All modes share the same pipeline — only UI auto-fill ' ...
                 'differs. Sampling overhead grows ~4ᵏ.'], ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on', 'Interpreter', 'none', ...
        'VerticalAlignment', 'top');
    hintLbl.Layout.Row = 2;

    % ── Row 6: Reconstructed Results card ────────────────────────────────
    %   Scrollable='on' so long expectation-value lists fall back to a
    %   vertical scrollbar instead of clipping the bottom of the card.
    resPanel = uipanel(g, 'Title', 'Reconstructed Results', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'Scrollable', 'on');
    resPanel.Layout.Row = 6; resPanel.Layout.Column = [1 2];
    resPanel.BackgroundColor = Theme.COLOR_CARD;
    rg = uigridlayout(resPanel, [1 1]);
    %  Inner row uses 'fit' so when the empty-state copy (or future
    %  long results display) needs more vertical space than the panel
    %  is allocated, the grid grows past the panel and resPanel.Scrollable
    %  paints a real scrollbar instead of clipping the content.
    rg.RowHeight = {'fit'};
    %  Top/bottom padding trimmed (14 → 10) so the 2-paragraph empty-state
    %  copy fits the ~95 px Row 6 budget at default 1600×870 figure.
    rg.Padding = [18 10 18 10]; rg.BackgroundColor = Theme.COLOR_CARD;

    % Empty state (visible until renderResult writes real values).
    app.CuttingResultsEmptyLabel = uilabel(rg, ...
        'Text', ['⚛  Reconstructed expectation values appear here once ' ...
                 'the batch completes. Press Run Cutting to dispatch all ' ...
                 'k subcircuits in parallel.'], ...
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
