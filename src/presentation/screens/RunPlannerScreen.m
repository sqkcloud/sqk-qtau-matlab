function RunPlannerScreen(app)
    % RunPlannerScreen  Builds the Run Planner tab UI.
    %
    %   Layout (vertical):
    %     Row 1 — Hero banner
    %     Row 2 — Toolbar (circuit / target slider / shots / Plan)
    %     Row 3 — Body — left scatter + right recommendation card
    %     Row 4 — Status / disclaimer strip

    Logger.info('RunPlannerScreen', 'Building Run Planner tab UI');
    t = app.createSectionPage('Run Planner');

    vm = app.RunPlannerVm;
    if isempty(vm)
        vm = RunPlannerViewModel(app);
        app.RunPlannerVm = vm;
    end

    % Row 2 (toolbar): +20 px to give the dropdown / slider / shots /
    % Plan controls more breathing room (60 → 80).
    % Row 3 (body): switched from flex '1x' to a fixed 500 px so the
    % body block stops stretching to fill empty viewport space (~50 px
    % shorter than the previous '1x' resolution on a typical desktop).
    g = uigridlayout(t, [4 1]);
    g.RowHeight    = {76, 80, 385, 'fit'};
    g.Padding      = Theme.GRID_PADDING;
    g.RowSpacing   = 10;
    g.BackgroundColor = Theme.COLOR_BG;
    g.Scrollable   = 'on';

    buildHero(g, vm);
    buildToolbar(g, vm);
    buildBody(g, vm);
    buildStatusStrip(g, vm);

    vm.bindRootGrid(g);

    app.logEvent('UI', 'Run Planner screen mounted');
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

    uilabel(g, 'Text', Labels.get('run_planner_hero_title'), ...
        'FontSize', 17, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
    uilabel(g, 'Text', Labels.get('run_planner_hero_subtitle'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
end

% ── Toolbar ──────────────────────────────────────────────────────────────
function buildToolbar(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 2; panel.Layout.Column = 1;

    g = uigridlayout(panel, [2 9]);
    g.RowHeight   = {18, 30};
    g.ColumnWidth = {'fit', 220, 'fit', 200, 50, 'fit', 90, 110, '1x'};
    g.Padding     = [12 6 12 6];
    g.RowSpacing  = 2; g.ColumnSpacing = 8;
    g.BackgroundColor = Theme.COLOR_CARD;

    iconLbl = uilabel(g, 'Text', '⚙', 'FontSize', 18);
    iconLbl.Layout.Row = [1 2]; iconLbl.Layout.Column = 1;

    headers = { ...
        Labels.get('run_planner_picker_circuit'), 2; ...
        Labels.get('run_planner_target_lbl'),     4; ...
        Labels.get('run_planner_shots_lbl'),      7};
    for i = 1:size(headers, 1)
        h = uilabel(g, 'Text', headers{i, 1}, ...
            'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, 'FontWeight', 'bold');
        h.Layout.Row = 1; h.Layout.Column = headers{i, 2};
    end

    vm.CircuitDropdown = uidropdown(g, 'Items', {' (loading)'}, 'Value', ' (loading)', ...
        'ValueChangedFcn', @(s,e) vm.onPickCircuit(e));
    vm.CircuitDropdown.Layout.Row = 2; vm.CircuitDropdown.Layout.Column = 2;

    spacer1 = uilabel(g, 'Text', ''); spacer1.Layout.Row = 1; spacer1.Layout.Column = 3; %#ok<NASGU>

    vm.TargetSlider = uislider(g, ...
        'Limits', [0.5 0.99], 'Value', 0.90, ...
        'MajorTicks', [0.5 0.7 0.9], ...
        'ValueChangingFcn', @(s,e) vm.onTargetChanged(e), ...
        'ValueChangedFcn',  @(s,e) vm.onTargetChanged(e));
    vm.TargetSlider.Layout.Row = 2; vm.TargetSlider.Layout.Column = 4;

    vm.TargetValueLbl = uilabel(g, 'Text', '0.90', ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, 'HorizontalAlignment', 'center');
    vm.TargetValueLbl.Layout.Row = 2; vm.TargetValueLbl.Layout.Column = 5;

    spacer2 = uilabel(g, 'Text', ''); spacer2.Layout.Row = 1; spacer2.Layout.Column = 6; %#ok<NASGU>

    vm.ShotsField = uieditfield(g, 'numeric', 'Value', 4096, ...
        'Limits', [1 1e7], 'RoundFractionalValues', 'on');
    vm.ShotsField.Layout.Row = 2; vm.ShotsField.Layout.Column = 7;

    vm.PlanBtn = uibutton(g, 'Text', Labels.get('run_planner_btn_plan'), ...
        'ButtonPushedFcn', @(~,~) vm.onPlan());
    vm.PlanBtn.Layout.Row = 2; vm.PlanBtn.Layout.Column = 8;
    StyleHelper.styleBtn(vm.PlanBtn, 'primary');

    spacer3 = uilabel(g, 'Text', ''); spacer3.Layout.Row = 2; spacer3.Layout.Column = 9; %#ok<NASGU>
end

% ── Body — scatter + recommendation card ─────────────────────────────────
function buildBody(parent, vm)
    g = uigridlayout(parent, [1 2]);
    g.Layout.Row = 3; g.Layout.Column = 1;
    g.ColumnWidth = {'1x', 320}; g.ColumnSpacing = 10;
    g.Padding = [0 0 0 0];
    g.BackgroundColor = Theme.COLOR_BG;

    buildScatter(g, vm);
    buildRecommendCard(g, vm);
end

function buildScatter(parent, vm)
    panel = uipanel(parent, 'Title', '', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Column = 1;

    g = uigridlayout(panel, [1 1]);
    g.Padding = [12 8 12 8];
    g.BackgroundColor = Theme.COLOR_CARD;

    ax = uiaxes(g);
    ax.Toolbar.Visible = 'off';
    ax.Color = Theme.COLOR_CARD;
    ax.XColor = Theme.COLOR_MUTED; ax.YColor = Theme.COLOR_MUTED;
    ax.FontSize = 10;
    ax.Box = 'off';
    try; disableDefaultInteractivity(ax); catch; end
    vm.ScatterAxes = ax;
end

function buildRecommendCard(parent, vm)
    card = uipanel(parent, 'Title', Labels.get('run_planner_card_title'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');
    card.Layout.Column = 2;

    g = uigridlayout(card, [9 2]);
    g.RowHeight   = {24, 24, 24, 24, 24, 24, 'fit', 36, 36};
    g.ColumnWidth = {130, '1x'};
    g.Padding     = [12 10 12 10]; g.RowSpacing = 4;
    g.BackgroundColor = Theme.COLOR_CARD;

    vm.LblBackend    = pair(g, 1, Labels.get('run_planner_card_backend'));
    vm.LblMitigation = pair(g, 2, Labels.get('run_planner_card_mitigation'));
    vm.LblShots      = pair(g, 3, Labels.get('run_planner_card_shots'));
    vm.LblFidelity   = pair(g, 4, Labels.get('run_planner_card_fidelity'));
    vm.LblCost       = pair(g, 5, Labels.get('run_planner_card_cost'));
    vm.LblRuntime    = pair(g, 6, Labels.get('run_planner_card_runtime'));

    vm.LblFactorNote = uilabel(g, 'Text', Labels.get('run_planner_card_factor_note'), ...
        'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    vm.LblFactorNote.Layout.Row = 7; vm.LblFactorNote.Layout.Column = [1 2];

    vm.SubmitBtn = uibutton(g, 'Text', Labels.get('run_planner_btn_submit'), ...
        'ButtonPushedFcn', @(~,~) vm.onSubmit());
    vm.SubmitBtn.Layout.Row = 8; vm.SubmitBtn.Layout.Column = [1 2];
    StyleHelper.styleBtn(vm.SubmitBtn, 'success');

    vm.BundleBtn = uibutton(g, 'Text', Labels.get('run_planner_btn_bundle'), ...
        'ButtonPushedFcn', @(~,~) vm.onBundle());
    vm.BundleBtn.Layout.Row = 9; vm.BundleBtn.Layout.Column = [1 2];
    StyleHelper.styleBtn(vm.BundleBtn, 'ghost');
end

function valLbl = pair(g, row, key)
    keyLbl = uilabel(g, 'Text', key, ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED);
    keyLbl.Layout.Row = row; keyLbl.Layout.Column = 1;
    valLbl = uilabel(g, 'Text', '—', ...
        'FontSize', 12, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
    valLbl.Layout.Row = row; valLbl.Layout.Column = 2;
end

% ── Status strip ─────────────────────────────────────────────────────────
function buildStatusStrip(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 4; panel.Layout.Column = 1;

    g = uigridlayout(panel, [1 1]);
    g.Padding = [16 10 16 10];
    g.BackgroundColor = Theme.COLOR_CARD;

    vm.StatusLbl = uilabel(g, 'Text', Labels.get('run_planner_status_idle'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
end
