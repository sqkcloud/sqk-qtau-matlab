function MitigationCompareScreen(app)
    % MitigationCompareScreen  Builds the Mitigation Compare tab UI.
    %
    %   Layout (vertical):
    %     Row 1 — Hero banner (purpose + subtitle)
    %     Row 2 — Toolbar (Circuit / Backend / Shots dropdowns + Estimate)
    %     Row 3 — Strategy chip strip
    %     Row 4 — Comparison card grid (one card per selected strategy)
    %     Row 5 — Ranking bar chart
    %     Row 6 — Recommendation strip
    %
    %   UI handles flow into the MitigationCompareViewModel so callbacks
    %   own their state without polluting QTAUWorkbenchApp.

    Logger.info('MitigationCompareScreen', 'Building Mitigation Compare tab UI');
    t = app.createSectionPage('Mitigation Compare');

    vm = app.MitigationCompareVm;
    if isempty(vm)
        vm = MitigationCompareViewModel(app);
        app.MitigationCompareVm = vm;
    end

    % Tightened row heights + uniform 12-px spacing so the screen reads
    % as evenly-rhythmed even before Estimate runs. Card / chart rows
    % include explicit empty-state placeholders (built below) instead of
    % leaving gaping voids.
    g = uigridlayout(t, [6 1]);
    g.RowHeight    = {72, 56, 56, 200, 180, 'fit'};
    g.Padding      = Theme.GRID_PADDING;
    g.RowSpacing   = 12;
    g.BackgroundColor = Theme.COLOR_BG;
    g.Scrollable   = 'on';

    buildHero(g, vm);
    buildToolbar(g, vm);
    buildChipStrip(g, vm);
    buildCardArea(g, vm);
    buildRanking(g, vm);
    buildRecommendation(g, vm);

    vm.bindRootGrid(g);
    vm.refreshStatus();

    app.logEvent('UI', 'Mitigation Compare screen mounted');
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

    titleLbl = uilabel(g, 'Text', Labels.get('mitigation_compare_hero_title'), ...
        'FontSize', 17, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
    titleLbl.Layout.Row = 1;

    subLbl = uilabel(g, 'Text', Labels.get('mitigation_compare_hero_subtitle'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
    subLbl.Layout.Row = 2;
end

% ── Toolbar ──────────────────────────────────────────────────────────────
function buildToolbar(parent, vm)
    bar = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    bar.Layout.Row = 2; bar.Layout.Column = 1;

    g = uigridlayout(bar, [2 8]);
    g.RowHeight    = {18, 30};
    g.ColumnWidth  = {'fit', 220, 'fit', 180, 'fit', 100, 110, '1x'};
    g.Padding      = [12 6 12 6];
    g.RowSpacing   = 2; g.ColumnSpacing = 8;
    g.BackgroundColor = Theme.COLOR_CARD;

    headers = {Labels.get('mitigation_compare_picker_circuit'), ...
               Labels.get('mitigation_compare_picker_backend'), ...
               Labels.get('mitigation_compare_picker_shots')};
    cols = [2, 4, 6];
    for i = 1:numel(headers)
        h = uilabel(g, 'Text', headers{i}, ...
            'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, 'FontWeight', 'bold');
        h.Layout.Row = 1; h.Layout.Column = cols(i);
    end

    iconLbl = uilabel(g, 'Text', '⚖', 'FontSize', 18);
    iconLbl.Layout.Row = [1 2]; iconLbl.Layout.Column = 1;

    vm.CircuitDropdown = uidropdown(g, 'Items', {' (loading)'}, 'Value', ' (loading)', ...
        'ValueChangedFcn', @(s,e) vm.onPickCircuit(e));
    vm.CircuitDropdown.Layout.Row = 2; vm.CircuitDropdown.Layout.Column = 2;

    spacer1 = uilabel(g, 'Text', ''); spacer1.Layout.Row = 1; spacer1.Layout.Column = 3; %#ok<NASGU>
    vm.BackendDropdown = uidropdown(g, 'Items', {' (loading)'}, 'Value', ' (loading)', ...
        'ValueChangedFcn', @(s,e) vm.onPickBackend(e));
    vm.BackendDropdown.Layout.Row = 2; vm.BackendDropdown.Layout.Column = 4;

    spacer2 = uilabel(g, 'Text', ''); spacer2.Layout.Row = 1; spacer2.Layout.Column = 5; %#ok<NASGU>
    vm.ShotsField = uieditfield(g, 'numeric', 'Value', 4096, ...
        'Limits', [1 1e7], 'RoundFractionalValues', 'on');
    vm.ShotsField.Layout.Row = 2; vm.ShotsField.Layout.Column = 6;

    vm.EstimateBtn = uibutton(g, 'Text', Labels.get('mitigation_compare_btn_estimate'), ...
        'ButtonPushedFcn', @(~,~) vm.onEstimate());
    vm.EstimateBtn.Layout.Row = 2; vm.EstimateBtn.Layout.Column = 7;
    StyleHelper.styleBtn(vm.EstimateBtn, 'primary');

    vm.StatusLbl = uilabel(g, 'Text', '', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, ...
        'WordWrap', 'on', 'HorizontalAlignment', 'left');
    vm.StatusLbl.Layout.Row = 2; vm.StatusLbl.Layout.Column = 8;
end

% ── Chip strip ───────────────────────────────────────────────────────────
function buildChipStrip(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 3; panel.Layout.Column = 1;

    g = uigridlayout(panel, [2 1]);
    g.RowHeight = {16, '1x'};
    g.Padding   = [12 6 12 6]; g.RowSpacing = 2;
    g.BackgroundColor = Theme.COLOR_CARD;

    titleLbl = uilabel(g, 'Text', Labels.get('mitigation_compare_chip_title'), ...
        'FontSize', 11, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_LABEL);
    titleLbl.Layout.Row = 1;

    chipPanel = uipanel(g, 'Title', '', 'BorderType', 'none', ...
        'BackgroundColor', Theme.COLOR_CARD);
    chipPanel.Layout.Row = 2;
    vm.ChipPanel = chipPanel;
end

% ── Card area ────────────────────────────────────────────────────────────
function buildCardArea(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'none', ...
        'BackgroundColor', Theme.COLOR_BG, 'Scrollable', 'on');
    panel.Layout.Row = 4; panel.Layout.Column = 1;
    vm.CardPanel = panel;

    % Empty-state placeholder — replaced by paintCardsLoading via
    % delete(obj.CardPanel.Children) when the user clicks Estimate.
    placeholder = uigridlayout(panel, [1 1]);
    placeholder.Padding = [16 16 16 16];
    placeholder.BackgroundColor = Theme.COLOR_BG;
    uilabel(placeholder, 'Text', ...
        'Pick at least one strategy chip above and click ▶ Estimate to compare configurations side-by-side.', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'center', 'WordWrap', 'on');
end

% ── Ranking bar chart ────────────────────────────────────────────────────
function buildRanking(parent, vm)
    panel = uipanel(parent, 'Title', Labels.get('mitigation_compare_chart_title'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');
    panel.Layout.Row = 5; panel.Layout.Column = 1;

    g = uigridlayout(panel, [1 1]);
    g.Padding = [12 8 12 8];
    g.BackgroundColor = Theme.COLOR_CARD;

    ax = uiaxes(g);
    ax.Toolbar.Visible = 'off';
    ax.Color = Theme.COLOR_CARD;
    ax.XColor = Theme.COLOR_MUTED; ax.YColor = Theme.COLOR_MUTED;
    ax.FontSize = 10;
    ax.Box = 'off';
    ax.XTick = []; ax.YTick = [];
    try; disableDefaultInteractivity(ax); catch; end

    % Empty-state caption centered on the axes via normalized units.
    % cla(ax) inside repaintRanking removes this when the bars draw.
    emptyT = text(ax, 0.5, 0.5, ...
        'Awaiting estimate — strategy ranking will appear here.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontSize', 11, 'Color', Theme.COLOR_MUTED);
    emptyT.Units = 'normalized';
    emptyT.Position = [0.5, 0.5, 0];

    vm.RankAxes = ax;
end

% ── Recommendation strip ─────────────────────────────────────────────────
function buildRecommendation(parent, vm)
    panel = uipanel(parent, 'Title', Labels.get('mitigation_compare_recco_title'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');
    panel.Layout.Row = 6; panel.Layout.Column = 1;

    g = uigridlayout(panel, [1 1]);
    g.Padding = [16 12 16 12];
    g.BackgroundColor = Theme.COLOR_CARD;

    lbl = uilabel(g, 'Text', '', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
    vm.ReccoLbl = lbl;
end
