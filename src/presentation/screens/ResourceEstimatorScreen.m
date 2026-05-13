function ResourceEstimatorScreen(app)
    % ResourceEstimatorScreen  Builds the Resource Estimator tab UI.
    %
    %   Layout (vertical):
    %     Row 1 — Hero banner
    %     Row 2 — Toolbar (circuit / code / phys err / log err / cycle / Estimate)
    %     Row 3 — Three result cards (Logical / Physical / Runtime)
    %     Row 4 — Pie chart (data / ancilla / factory)
    %     Row 5 — Insight strip

    Logger.info('ResourceEstimatorScreen', 'Building Resource Estimator tab UI');
    t = app.createSectionPage('Resource Estimator');

    vm = app.ResourceEstimatorVm;
    if isempty(vm)
        vm = ResourceEstimatorViewModel(app);
        app.ResourceEstimatorVm = vm;
    end

    g = uigridlayout(t, [5 1]);
    g.RowHeight    = {76, 70, 180, 180, 'fit'};
    g.Padding      = Theme.GRID_PADDING;
    g.RowSpacing   = 10;
    g.BackgroundColor = Theme.COLOR_BG;
    g.Scrollable   = 'on';

    buildHero(g, vm);
    buildToolbar(g, vm);
    buildCards(g, vm);
    buildPie(g, vm);
    buildInsights(g, vm);

    vm.bindRootGrid(g);

    app.logEvent('UI', 'Resource Estimator screen mounted');
end

% ── Hero banner ──────────────────────────────────────────────────────────
function buildHero(parent, vm) %#ok<INUSD>
    panel = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 1; panel.Layout.Column = 1;
    g = uigridlayout(panel, [2 1]);
    g.RowHeight  = {28, 'fit'};
    g.Padding    = [18 12 18 12]; g.RowSpacing = 4;
    g.BackgroundColor = Theme.COLOR_CARD;

    uilabel(g, 'Text', Labels.get('resource_estimator_hero_title'), ...
        'FontSize', 17, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
    uilabel(g, 'Text', Labels.get('resource_estimator_hero_subtitle'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
end

% ── Toolbar ──────────────────────────────────────────────────────────────
function buildToolbar(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 2; panel.Layout.Column = 1;

    g = uigridlayout(panel, [2 12]);
    g.RowHeight    = {18, 30};
    g.ColumnWidth  = {'fit', 220, 'fit', 140, 'fit', 90, 'fit', 90, 'fit', 100, 110, '1x'};
    g.Padding      = [12 6 12 6];
    g.RowSpacing   = 2; g.ColumnSpacing = 8;
    g.BackgroundColor = Theme.COLOR_CARD;

    iconLbl = uilabel(g, 'Text', '⌬', 'FontSize', 18);
    iconLbl.Layout.Row = [1 2]; iconLbl.Layout.Column = 1;

    headers = { ...
        Labels.get('resource_estimator_picker_circuit'),  2; ...
        Labels.get('resource_estimator_picker_code'),     4; ...
        Labels.get('resource_estimator_picker_phys_err'), 6; ...
        Labels.get('resource_estimator_picker_log_err'),  8; ...
        Labels.get('resource_estimator_picker_cycle'),    10};
    for i = 1:size(headers, 1)
        h = uilabel(g, 'Text', headers{i, 1}, ...
            'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, 'FontWeight', 'bold');
        h.Layout.Row = 1; h.Layout.Column = headers{i, 2};
    end

    vm.CircuitDropdown = uidropdown(g, 'Items', {' (loading)'}, 'Value', ' (loading)', ...
        'ValueChangedFcn', @(s,e) vm.onPickCircuit(e));
    vm.CircuitDropdown.Layout.Row = 2; vm.CircuitDropdown.Layout.Column = 2;

    vm.CodeDropdown = uidropdown(g, ...
        'Items',     {Labels.get('resource_estimator_code_surface'), Labels.get('resource_estimator_code_steane')}, ...
        'ItemsData', {'surface', 'steane'}, ...
        'Value', 'surface', ...
        'ValueChangedFcn', @(s,e) vm.onPickCode(e));
    vm.CodeDropdown.Layout.Row = 2; vm.CodeDropdown.Layout.Column = 4;

    vm.PhysErrField = uieditfield(g, 'numeric', 'Value', 1e-3, ...
        'Limits', [1e-7 1e-1], 'ValueDisplayFormat', '%.0e');
    vm.PhysErrField.Layout.Row = 2; vm.PhysErrField.Layout.Column = 6;

    vm.LogErrField = uieditfield(g, 'numeric', 'Value', 1e-15, ...
        'Limits', [1e-30 0.5], 'ValueDisplayFormat', '%.0e');
    vm.LogErrField.Layout.Row = 2; vm.LogErrField.Layout.Column = 8;

    cycleGrid = uigridlayout(g, [1 2]);
    cycleGrid.Layout.Row = 2; cycleGrid.Layout.Column = 10;
    cycleGrid.ColumnWidth = {'1x', 30}; cycleGrid.Padding = [0 0 0 0];
    cycleGrid.ColumnSpacing = 2;
    cycleGrid.BackgroundColor = Theme.COLOR_CARD;
    vm.CycleField = uieditfield(cycleGrid, 'numeric', 'Value', 1, 'Limits', [1e-3 1e6]);
    uilabel(cycleGrid, 'Text', Labels.get('resource_estimator_unit_us'), ...
        'FontSize', 10, 'FontColor', Theme.COLOR_MUTED);

    vm.EstimateBtn = uibutton(g, 'Text', Labels.get('resource_estimator_btn_estimate'), ...
        'ButtonPushedFcn', @(~,~) vm.onEstimate());
    vm.EstimateBtn.Layout.Row = 2; vm.EstimateBtn.Layout.Column = 11;
    StyleHelper.styleBtn(vm.EstimateBtn, 'primary');

    vm.StatusLbl = uilabel(g, 'Text', Labels.get('resource_estimator_status_idle'), ...
        'FontSize', 11, 'FontColor', Theme.COLOR_LABEL, ...
        'WordWrap', 'on', 'VerticalAlignment', 'center');
    vm.StatusLbl.Layout.Row = [1 2]; vm.StatusLbl.Layout.Column = 12;
end

% ── Three result cards ───────────────────────────────────────────────────
function buildCards(parent, vm)
    g = uigridlayout(parent, [1 3]);
    g.Layout.Row = 3; g.Layout.Column = 1;
    g.ColumnWidth = {'1x','1x','1x'}; g.ColumnSpacing = 10;
    g.Padding = [0 0 0 0];
    g.BackgroundColor = Theme.COLOR_BG;

    [vm.LblLogicalQubits, vm.LblTGates, vm.LblToffolis, vm.LblRotations, vm.LblClifford] = ...
        buildLogicalCard(g, 1);

    [vm.LblDistance, vm.LblPerLogical, vm.LblTotalPhys, vm.LblFactories] = ...
        buildPhysicalCard(g, 2);

    [vm.LblLayers, vm.LblLatticeCycles, vm.LblTotalRuntime] = ...
        buildRuntimeCard(g, 3);
end

function [lqL, tgL, tfL, rotL, clL] = buildLogicalCard(parent, col)
    [card, cg] = newCard(parent, col, Labels.get('resource_estimator_card_logical'), 6);
    [~, lqL]  = pair(cg, 1, Labels.get('resource_estimator_lbl_logical_qubits'));
    [~, tgL]  = pair(cg, 2, Labels.get('resource_estimator_lbl_t_gates'));
    [~, tfL]  = pair(cg, 3, Labels.get('resource_estimator_lbl_toffolis'));
    [~, rotL] = pair(cg, 4, Labels.get('resource_estimator_lbl_rotations'));
    [~, clL]  = pair(cg, 5, Labels.get('resource_estimator_lbl_clifford'));
    spacer = uilabel(cg, 'Text', ''); spacer.Layout.Row = 6; spacer.Layout.Column = [1 2]; %#ok<NASGU>
    card.AutoResizeChildren = 'on';
end

function [dL, plL, tpL, fL] = buildPhysicalCard(parent, col)
    [card, cg] = newCard(parent, col, Labels.get('resource_estimator_card_physical'), 5);
    [~, dL]  = pair(cg, 1, Labels.get('resource_estimator_lbl_distance'));
    [~, plL] = pair(cg, 2, Labels.get('resource_estimator_lbl_per_logical'));
    [~, tpL] = pair(cg, 3, Labels.get('resource_estimator_lbl_total_phys'));
    [~, fL]  = pair(cg, 4, Labels.get('resource_estimator_lbl_factories'));
    spacer = uilabel(cg, 'Text', ''); spacer.Layout.Row = 5; spacer.Layout.Column = [1 2]; %#ok<NASGU>
    card.AutoResizeChildren = 'on';
end

function [layL, lcL, trL] = buildRuntimeCard(parent, col)
    [card, cg] = newCard(parent, col, Labels.get('resource_estimator_card_runtime'), 4);
    [~, layL] = pair(cg, 1, Labels.get('resource_estimator_lbl_layers'));
    [~, lcL]  = pair(cg, 2, Labels.get('resource_estimator_lbl_lattice'));
    [~, trL]  = pair(cg, 3, Labels.get('resource_estimator_lbl_total_time'));
    spacer = uilabel(cg, 'Text', ''); spacer.Layout.Row = 4; spacer.Layout.Column = [1 2]; %#ok<NASGU>
    card.AutoResizeChildren = 'on';
end

function [card, cg] = newCard(parent, col, title, rows)
    card = uipanel(parent, 'Title', title, ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');
    card.Layout.Column = col;
    cg = uigridlayout(card, [rows 2]);
    cg.RowHeight   = repmat({24}, 1, rows);
    cg.ColumnWidth = {130, '1x'};
    cg.Padding     = [12 10 12 10]; cg.RowSpacing = 4;
    cg.BackgroundColor = Theme.COLOR_CARD;
end

function [keyLbl, valLbl] = pair(cg, row, key)
    keyLbl = uilabel(cg, 'Text', key, ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED);
    keyLbl.Layout.Row = row; keyLbl.Layout.Column = 1;
    valLbl = uilabel(cg, 'Text', '—', ...
        'FontSize', 12, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
    valLbl.Layout.Row = row; valLbl.Layout.Column = 2;
end

% ── Pie chart ────────────────────────────────────────────────────────────
function buildPie(parent, vm)
    panel = uipanel(parent, 'Title', '', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 4; panel.Layout.Column = 1;

    g = uigridlayout(panel, [1 1]);
    g.Padding = [12 8 12 8];
    g.BackgroundColor = Theme.COLOR_CARD;

    ax = uiaxes(g);
    ax.Toolbar.Visible = 'off';
    ax.Color = Theme.COLOR_CARD;
    ax.XColor = Theme.COLOR_MUTED; ax.YColor = Theme.COLOR_MUTED;
    ax.Box = 'off'; ax.XTick = []; ax.YTick = [];
    try; disableDefaultInteractivity(ax); catch; end
    vm.PieAxes = ax;
end

% ── Insight strip ────────────────────────────────────────────────────────
function buildInsights(parent, vm)
    panel = uipanel(parent, 'Title', Labels.get('resource_estimator_insight_title'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');
    panel.Layout.Row = 5; panel.Layout.Column = 1;

    g = uigridlayout(panel, [1 1]);
    g.Padding = [16 12 16 12];
    g.BackgroundColor = Theme.COLOR_CARD;

    vm.InsightLbl = uilabel(g, 'Text', '', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
end
