function ComposerScreen(app)
    % ComposerScreen  Builds the full Composer tab UI.
    %
    %   Layout (vertical):
    %     Row 1 — Toolbar (Templates / Save / Validate / Clear / + qubit /
    %             − qubit / Inspect toggle / status label / Open-in-Analysis)
    %     Row 2 — Hero strip (visible only when the circuit is empty)
    %     Row 3 — Body — three-column: Palette | Canvas | Selection panel
    %     Row 4 — OpenQASM mirror (collapsible)
    %     Row 5 — Inspect footer (collapsible)
    %
    %   UI handles are stored on the ViewModel (`app.ComposerVm`) so
    %   callbacks own their state without polluting QTAUWorkbenchApp.

    Logger.info('ComposerScreen', 'Building Composer tab UI');
    t = app.createSectionPage('Composer');

    vm = app.ComposerVm;
    if isempty(vm)
        vm = ComposerViewModel(app);
        app.ComposerVm = vm;
    end

    % The section page (`t`) is already Scrollable=on (set by
    % NavigationManager.createSectionPage), so once the inner content has
    % a known minimum intrinsic height the whole-screen scrollbar kicks
    % in automatically whenever the viewport is shorter than that
    % minimum (or whenever the user expands the mirror + inspect rows).
    % Pinning row 3 to a fixed pixel height instead of '1x' is the
    % single change that makes that minimum predictable.
    g = uigridlayout(t, [5 1]);
    g.RowHeight    = {50, 'fit', 460, 36, 360};
    g.Padding      = Theme.GRID_PADDING;
    g.RowSpacing   = 8;
    g.BackgroundColor = Theme.COLOR_BG;
    g.Scrollable   = 'on';

    buildToolbar(g, vm);
    buildHero(g, vm);
    buildBody(g, vm);
    buildMirror(g, vm);
    buildInspect(g, vm);

    vm.bindRootGrid(g);
    vm.repaintCanvas();
    vm.repaintMirror();
    vm.refreshStatus();
    vm.applyHeroVisibility();

    app.logEvent('UI', 'Composer screen mounted');
end

% ── Toolbar ──────────────────────────────────────────────────────────────
function buildToolbar(parent, vm)
    bar = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    bar.Layout.Row = 1; bar.Layout.Column = 1;

    grid = uigridlayout(bar, [1 12]);
    grid.Padding = [10 6 10 6];
    grid.ColumnSpacing = 8;
    grid.ColumnWidth = {120, 90, 100, 100, 100, 110, 90, 90, 90, 100, '1x', 160};
    grid.BackgroundColor = Theme.COLOR_CARD;

    btnTemplates = uibutton(grid, 'Text', Labels.get('composer_btn_templates'), ...
        'ButtonPushedFcn', @(~,~) vm.onOpenTemplatesDialog());
    StyleHelper.styleBtn(btnTemplates, 'primary');

    btnSave = uibutton(grid, 'Text', Labels.get('composer_btn_save'), ...
        'ButtonPushedFcn', @(~,~) vm.onSave());
    StyleHelper.styleBtn(btnSave, 'success');

    btnValidate = uibutton(grid, 'Text', Labels.get('composer_btn_validate'), ...
        'ButtonPushedFcn', @(~,~) vm.onValidate());
    StyleHelper.styleBtn(btnValidate, 'secondary');

    btnExport = uibutton(grid, 'Text', Labels.get('composer_export_btn'), ...
        'ButtonPushedFcn', @(~,~) vm.onOpenExport());
    StyleHelper.styleBtn(btnExport, 'ghost');
    vm.BtnExport = btnExport;

    btnBundle = uibutton(grid, 'Text', Labels.get('bundle_btn'), ...
        'ButtonPushedFcn', @(~,~) vm.onOpenBundle());
    StyleHelper.styleBtn(btnBundle, 'ghost');
    vm.BtnBundle = btnBundle;

    btnImport = uibutton(grid, 'Text', Labels.get('composer_btn_import_matlab'), ...
        'ButtonPushedFcn', @(~,~) vm.onImportFromMatlab());
    StyleHelper.styleBtn(btnImport, 'ghost');

    btnAddQ = uibutton(grid, 'Text', Labels.get('composer_btn_add_qubit'), ...
        'ButtonPushedFcn', @(~,~) vm.onAddQubit());
    StyleHelper.styleBtn(btnAddQ, 'ghost');

    btnRmQ = uibutton(grid, 'Text', Labels.get('composer_btn_remove_qubit'), ...
        'ButtonPushedFcn', @(~,~) vm.onRemoveQubit());
    StyleHelper.styleBtn(btnRmQ, 'ghost');

    btnClear = uibutton(grid, 'Text', Labels.get('composer_btn_clear'), ...
        'ButtonPushedFcn', @(~,~) vm.onClear());
    StyleHelper.styleBtn(btnClear, 'danger');

    btnInspect = uibutton(grid, 'Text', Labels.get('composer_btn_inspect'), ...
        'ButtonPushedFcn', @(~,~) vm.onToggleInspect());
    StyleHelper.styleBtn(btnInspect, 'secondary');

    statusLbl = uilabel(grid, ...
        'Text', Labels.get('composer_status_idle'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, ...
        'WordWrap', 'on', 'HorizontalAlignment', 'left');

    btnOpenAnalysis = uibutton(grid, 'Text', Labels.get('composer_btn_open_analysis'), ...
        'ButtonPushedFcn', @(~,~) vm.onOpenAnalysis(), 'Enable', 'off');
    StyleHelper.styleBtn(btnOpenAnalysis, 'ghost');

    vm.BtnInspect      = btnInspect;
    vm.BtnOpenAnalysis = btnOpenAnalysis;
    vm.StatusLbl       = statusLbl;
end

% ── Hero / template prompt strip ─────────────────────────────────────────
function buildHero(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 2; panel.Layout.Column = 1;

    g = uigridlayout(panel, [3 1]);
    g.RowHeight   = {28, 22, 'fit'};
    g.Padding     = [18 12 18 12];
    g.RowSpacing  = 6;
    g.BackgroundColor = Theme.COLOR_CARD;

    titleLbl = uilabel(g, 'Text', Labels.get('composer_hero_title'), ...
        'FontSize', 17, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
    titleLbl.Layout.Row = 1;

    sublineLbl = uilabel(g, 'Text', Labels.get('composer_hero_subtitle'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
    sublineLbl.Layout.Row = 2;

    statusLbl = uilabel(g, 'Text', Labels.get('composer_hero_status'), ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    statusLbl.Layout.Row = 3;

    vm.HeroPanel = panel;
end

% ── Body — palette | canvas | selection ──────────────────────────────────
function buildBody(parent, vm)
    bodyGrid = uigridlayout(parent, [1 3]);
    bodyGrid.Layout.Row = 3; bodyGrid.Layout.Column = 1;
    bodyGrid.ColumnWidth = {180, '1x', 240};
    bodyGrid.ColumnSpacing = 10;
    bodyGrid.Padding = [0 0 0 0];
    bodyGrid.BackgroundColor = Theme.COLOR_BG;

    buildPalette(bodyGrid, vm);
    buildCanvas(bodyGrid,  vm);
    buildSelection(bodyGrid, vm);
end

function buildPalette(parent, vm)
    panel = uipanel(parent, 'Title', Labels.get('composer_palette_title'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold', ...
        'Scrollable', 'on');
    panel.Layout.Row = 1; panel.Layout.Column = 1;

    g = uigridlayout(panel, [16 2]);
    g.Padding     = [10 8 10 8];
    g.RowSpacing  = 4;
    g.ColumnSpacing = 4;
    g.RowHeight   = repmat({30}, 1, 16);
    g.ColumnWidth = {'1x', '1x'};
    g.BackgroundColor = Theme.COLOR_CARD;

    vm.PaletteButtons = containers.Map('KeyType','char','ValueType','any');

    addPaletteHeader(g, 1, 1, 2, Labels.get('composer_palette_section_1q'));
    place(addGateBtn(g, 'h',    'H',   Labels.get('composer_gate_h_tip'),    vm), 2, 1);
    place(addGateBtn(g, 'x',    'X',   Labels.get('composer_gate_x_tip'),    vm), 2, 2);
    place(addGateBtn(g, 'y',    'Y',   Labels.get('composer_gate_y_tip'),    vm), 3, 1);
    place(addGateBtn(g, 'z',    'Z',   Labels.get('composer_gate_z_tip'),    vm), 3, 2);
    place(addGateBtn(g, 's',    'S',   Labels.get('composer_gate_s_tip'),    vm), 4, 1);
    place(addGateBtn(g, 't',    'T',   Labels.get('composer_gate_t_tip'),    vm), 4, 2);
    place(addGateBtn(g, 'sdg',  'S†',  Labels.get('composer_gate_sdg_tip'),  vm), 5, 1);
    place(addGateBtn(g, 'tdg',  'T†',  Labels.get('composer_gate_tdg_tip'),  vm), 5, 2);
    place(addGateBtn(g, 'rx',   'Rx',  Labels.get('composer_gate_rx_tip'),   vm), 6, 1);
    place(addGateBtn(g, 'ry',   'Ry',  Labels.get('composer_gate_ry_tip'),   vm), 6, 2);
    place(addGateBtn(g, 'rz',   'Rz',  Labels.get('composer_gate_rz_tip'),   vm), 7, 1);
    place(addGateBtn(g, 'reset','|0⟩', Labels.get('composer_gate_reset_tip'),vm), 7, 2);

    addPaletteHeader(g, 8, 1, 2, Labels.get('composer_palette_section_2q'));
    place(addGateBtn(g, 'cx',   'CX',   Labels.get('composer_gate_cx_tip'),   vm), 9,  1);
    place(addGateBtn(g, 'cz',   'CZ',   Labels.get('composer_gate_cz_tip'),   vm), 9,  2);
    place(addGateBtn(g, 'swap', 'SWAP', Labels.get('composer_gate_swap_tip'), vm), 10, 1);
    place(addGateBtn(g, 'ccx',  'CCX',  Labels.get('composer_gate_ccx_tip'),  vm), 10, 2);

    addPaletteHeader(g, 11, 1, 2, Labels.get('composer_palette_section_meas'));
    place(addGateBtn(g, 'measure', 'M', Labels.get('composer_gate_meas_tip'),    vm), 12, 1);
    place(addGateBtn(g, 'barrier', '|', Labels.get('composer_gate_barrier_tip'), vm), 12, 2);

    hint = uilabel(g, 'Text', Labels.get('composer_palette_hint'), ...
        'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on', 'HorizontalAlignment', 'left');
    hint.Layout.Row = [14 16]; hint.Layout.Column = [1 2];
end

function addPaletteHeader(g, row, col, span, text)
    lbl = uilabel(g, 'Text', text, ...
        'FontSize', 10, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_MUTED);
    lbl.Layout.Row = row; lbl.Layout.Column = [col, col+span-1];
end

function btn = addGateBtn(parent, kind, label, tooltip, vm)
    btn = uibutton(parent, 'Text', label, 'Tooltip', tooltip, ...
        'ButtonPushedFcn', @(~,~) vm.onArmGate(kind));
    StyleHelper.styleBtn(btn, 'ghost');
    btn.FontWeight = 'bold';
    vm.PaletteButtons(kind) = btn;
end

function place(btn, row, col)
    btn.Layout.Row = row; btn.Layout.Column = col;
end

function buildCanvas(parent, vm)
    panel = uipanel(parent, 'Title', Labels.get('composer_canvas_title'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');
    panel.Layout.Row = 1; panel.Layout.Column = 2;

    % Three-row layout: axes (pixel-fixed at 25 px per qubit) + empty-state
    % caption + spacer ('1x'). The spacer absorbs leftover container
    % height so the axes never stretches — wire-to-wire spacing stays at
    % exactly 25 px regardless of body-row size, matching the rest of
    % the app's circuit-diagram surfaces. ComposerViewModel.repaintCanvas
    % resizes RowHeight{1} as the qubit count grows.
    g = uigridlayout(panel, [3 1]);
    g.RowHeight   = {50, 22, '1x'};
    g.Padding     = [10 10 10 6];
    g.RowSpacing  = 4;
    g.BackgroundColor = Theme.COLOR_CARD;
    vm.CanvasInnerGrid = g;

    ax = uiaxes(g);
    ax.Layout.Row = 1;
    ax.Toolbar.Visible = 'off';
    ax.Color = Theme.COLOR_CARD;
    ax.XColor = 'none'; ax.YColor = 'none';
    ax.XTick = []; ax.YTick = [];
    ax.Box = 'off';
    try; disableDefaultInteractivity(ax); catch; end
    ax.ButtonDownFcn = @(src,evt) vm.onCanvasClick(evt);
    ax.HitTest = 'on';
    ax.PickableParts = 'all';

    emptyLbl = uilabel(g, 'Text', Labels.get('composer_canvas_empty'), ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'center');
    emptyLbl.Layout.Row = 2;

    vm.CanvasAxes  = ax;
    vm.CanvasEmpty = emptyLbl;
end

function buildSelection(parent, vm)
    panel = uipanel(parent, 'Title', 'Selection', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');
    panel.Layout.Row = 1; panel.Layout.Column = 3;

    g = uigridlayout(panel, [4 1]);
    g.RowHeight   = {28, 'fit', 'fit', '1x'};
    g.Padding     = [10 8 10 8];
    g.RowSpacing  = 6;
    g.BackgroundColor = Theme.COLOR_CARD;

    title = uilabel(g, 'Text', 'Selected: (none)', ...
        'FontSize', 12, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);

    detail = uilabel(g, 'Text', '', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');

    btnDelete = uibutton(g, 'Text', 'Delete last gate', ...
        'ButtonPushedFcn', @(~,~) vm.onDeleteLast());
    StyleHelper.styleBtn(btnDelete, 'danger');

    spacer = uilabel(g, 'Text', ''); %#ok<NASGU>

    vm.SelectionTitle  = title;
    vm.SelectionDetail = detail;
end

% ── Mirror ───────────────────────────────────────────────────────────────
function buildMirror(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'none', ...
        'BackgroundColor', Theme.COLOR_BG, 'Scrollable', 'on');
    panel.Layout.Row = 4; panel.Layout.Column = 1;

    g = uigridlayout(panel, [2 1]);
    g.RowHeight = {28, '1x'};
    g.Padding = [0 0 0 0];
    g.RowSpacing = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    bar = uigridlayout(g, [1 3]);
    bar.Layout.Row = 1;
    bar.ColumnWidth = {30, '1x', 240};
    bar.Padding = [0 0 0 0];
    bar.BackgroundColor = Theme.COLOR_BG;

    toggle = uibutton(bar, 'Text', char(8964), ...
        'ButtonPushedFcn', @(~,~) vm.onToggleMirror());
    StyleHelper.styleBtn(toggle, 'ghost');

    titleLbl = uilabel(bar, 'Text', Labels.get('composer_mirror_title'), ...
        'FontSize', 11, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_LABEL);
    titleLbl.Layout.Column = 2;

    errorLbl = uilabel(bar, 'Text', '', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_DANGER, ...
        'HorizontalAlignment', 'right');
    errorLbl.Layout.Column = 3;

    ta = uitextarea(g, ...
        'ValueChangedFcn', @(~,~) vm.onMirrorEdited(), ...
        'WordWrap', 'off');
    ta.Layout.Row = 2;
    ta.FontName = 'Menlo';
    ta.FontSize = 11;
    ta.BackgroundColor = Theme.COLOR_CARD;
    ta.FontColor       = Theme.COLOR_LABEL;
    ta.Editable = 'on';

    vm.MirrorTextarea  = ta;
    vm.MirrorErrorLbl  = errorLbl;
    vm.MirrorToggleBtn = toggle;
    vm.MirrorPanel     = panel;
end

% ── Inspect footer ───────────────────────────────────────────────────────
function buildInspect(parent, vm)
    panel = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
    panel.Layout.Row = 5; panel.Layout.Column = 1;

    g = uigridlayout(panel, [2 1]);
    g.RowHeight = {32, '1x'};
    g.Padding = [10 6 10 6];
    g.RowSpacing = 4;
    g.BackgroundColor = Theme.COLOR_CARD;

    bar = uigridlayout(g, [1 7]);
    bar.Layout.Row = 1;
    bar.ColumnWidth = {30, 'fit', 36, '1x', 36, 110, 90};
    bar.Padding = [0 0 0 0];
    bar.BackgroundColor = Theme.COLOR_CARD;

    toggle = uibutton(bar, 'Text', char(8964), ...
        'ButtonPushedFcn', @(~,~) vm.onToggleInspect());
    StyleHelper.styleBtn(toggle, 'ghost');

    titleLbl = uilabel(bar, 'Text', Labels.get('composer_inspect_title'), ...
        'FontSize', 12, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
    titleLbl.Layout.Column = 2;

    btnPrev = uibutton(bar, 'Text', Labels.get('composer_inspect_prev'), ...
        'ButtonPushedFcn', @(~,~) vm.onInspectStepDelta(-1));
    StyleHelper.styleBtn(btnPrev, 'ghost');
    btnPrev.Layout.Column = 3;

    sld = uislider(bar, 'Value', 0, 'Limits', [0 1], 'MajorTicks', [], ...
        'ValueChangingFcn', @(s,e) vm.onInspectSliderChanging(e), ...
        'ValueChangedFcn',  @(s,e) vm.onInspectSliderChanged(e));
    sld.Layout.Column = 4;

    btnNext = uibutton(bar, 'Text', Labels.get('composer_inspect_next'), ...
        'ButtonPushedFcn', @(~,~) vm.onInspectStepDelta(+1));
    StyleHelper.styleBtn(btnNext, 'ghost');
    btnNext.Layout.Column = 5;

    btnPlay = uibutton(bar, 'Text', Labels.get('composer_inspect_play'), ...
        'ButtonPushedFcn', @(~,~) vm.onInspectPlayToggle());
    StyleHelper.styleBtn(btnPlay, 'secondary');
    btnPlay.Layout.Column = 6;

    stepLbl = uilabel(bar, 'Text', '', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'right');
    stepLbl.Layout.Column = 7;

    body = uigridlayout(g, [2 1]);
    body.Layout.Row = 2;
    body.RowHeight = {26, '1x'};
    body.Padding = [0 0 0 0];
    body.BackgroundColor = Theme.COLOR_CARD;

    tabBar = uigridlayout(body, [1 4]);
    tabBar.Layout.Row = 1;
    tabBar.ColumnWidth = {120, 130, '1x', 'fit'};
    tabBar.Padding = [0 0 0 0];
    tabBar.BackgroundColor = Theme.COLOR_CARD;

    btnTabBloch = uibutton(tabBar, 'Text', Labels.get('composer_inspect_tab_bloch'), ...
        'ButtonPushedFcn', @(~,~) vm.onInspectTab('bloch'));
    StyleHelper.styleBtn(btnTabBloch, 'primary');

    btnTabAmps = uibutton(tabBar, 'Text', Labels.get('composer_inspect_tab_amps'), ...
        'ButtonPushedFcn', @(~,~) vm.onInspectTab('amps'));
    StyleHelper.styleBtn(btnTabAmps, 'ghost');

    captionLbl = uilabel(tabBar, 'Text', '', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
    captionLbl.Layout.Column = 3;

    contentPanel = uipanel(body, 'Title', '', 'BorderType', 'none', ...
        'BackgroundColor', Theme.COLOR_CARD);
    contentPanel.Layout.Row = 2;

    vm.InspectPanel       = panel;
    vm.InspectToggleBtn   = toggle;
    vm.InspectSlider      = sld;
    vm.InspectStepLbl     = stepLbl;
    vm.InspectPlayBtn     = btnPlay;
    vm.InspectCaptionLbl  = captionLbl;
    vm.InspectContent     = contentPanel;
    vm.InspectTabBlochBtn = btnTabBloch;
    vm.InspectTabAmpsBtn  = btnTabAmps;
end
