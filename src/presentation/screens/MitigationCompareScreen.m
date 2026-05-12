function MitigationCompareScreen(app)
    % MitigationCompareScreen  Builds the Mitigation Compare tab UI.
    %
    %   Layout (vertical, 5 rows):
    %     Row 1 — Toolbar (Circuit / Backend / Shots dropdowns + Estimate)
    %     Row 2 — Strategy chip strip
    %     Row 3 — Comparison card grid (one card per selected strategy)
    %     Row 4 — Ranking bar chart
    %     Row 5 — Recommendation strip
    %
    %   The inner hero banner was removed in the layout polish pass —
    %   the outer section header (rendered by NavigationManager) already
    %   shows the title + subtitle ("Mitigation Compare / Strategy
    %   planner · parallel cost preview · …") so an inner hero just
    %   duplicated the same information and consumed ~84 px of
    %   vertical space, while also clipping its own subtitle when its
    %   fixed 72-px row wasn't tall enough for a 2-line wrap.
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

    % Row heights tuned per role:
    %   Toolbar 56  — header label row (18) + input row (30) + 6 inner pad
    %   Chips   56  — same density as Toolbar; chips are 1 row of buttons
    %   Cards   160 — empty state placeholder fits in ~60 px; sized to host
    %                 a single row of strategy cards comfortably. CardPanel
    %                 is Scrollable for the rare 6-strategy case.
    %   Ranking 200 — chart needs vertical room for bars + axis labels
    %   Recco   72  — guaranteed minimum so the strip never collapses to
    %                 a sliver when the body is empty.
    g = uigridlayout(t, [5 1]);
    g.RowHeight    = {56, 56, 160, 200, 72};
    g.Padding      = Theme.GRID_PADDING;
    g.RowSpacing   = 12;
    g.BackgroundColor = Theme.COLOR_BG;
    g.Scrollable   = 'on';

    buildToolbar(g, vm);
    buildChipStrip(g, vm);
    buildCardArea(g, vm);
    buildRanking(g, vm);
    buildRecommendation(g, vm);

    vm.bindRootGrid(g);
    vm.refreshStatus();

    app.logEvent('UI', 'Mitigation Compare screen mounted');
end

% ── Toolbar ──────────────────────────────────────────────────────────────
function buildToolbar(parent, vm)
    bar = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    bar.Layout.Row = 1; bar.Layout.Column = 1;

    g = uigridlayout(bar, [2 8]);
    g.RowHeight    = {18, 30};
    g.ColumnWidth  = {'fit', 220, 'fit', 180, 'fit', 100, 110, '1x'};
    g.Padding      = [16 10 16 10];
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
        'WordWrap', 'on', 'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'center');
    vm.StatusLbl.Layout.Row = 2; vm.StatusLbl.Layout.Column = 8;
end

% ── Chip strip ───────────────────────────────────────────────────────────
function buildChipStrip(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 2; panel.Layout.Column = 1;

    g = uigridlayout(panel, [2 1]);
    g.RowHeight = {16, '1x'};
    g.Padding   = [16 10 16 10]; g.RowSpacing = 2;
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
    panel.Layout.Row = 3; panel.Layout.Column = 1;
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
    panel.Layout.Row = 4; panel.Layout.Column = 1;

    g = uigridlayout(panel, [1 1]);
    g.Padding = [16 10 16 10];
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
    panel.Layout.Row = 5; panel.Layout.Column = 1;

    g = uigridlayout(panel, [1 1]);
    g.Padding = [16 10 16 10];
    g.BackgroundColor = Theme.COLOR_CARD;

    lbl = uilabel(g, 'Text', '', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
    vm.ReccoLbl = lbl;
end
