% DashboardScreen  Populates the Dashboard section panel — Phase 1 refactor.
%
%   Layout (Google/IBM/Microsoft Quantum-style):
%     Row 1 (44 px)     — toolbar: description + Refresh + Export.
%     Row 2 (104 px)    — 4 KPI hero cards: Active Project / Circuit /
%                         Target Backend / Pipeline Stage.
%     Row 3 (88 px)     — Workflow Storyboard: 8-stage horizontal stepper
%                         with completed/active/upcoming dots and labels.
%     Row 4 (220 px)    — split: Run Readiness KPI grid (left) and
%                         Activity Trend bar chart (right).
%     Row 5 ('1x')      — Recent Activity table with pagination footer.
%
%   The previous "Status / Raw JSON" tree and ASCII "[ ]" Storyboard
%   Readiness checklist have been removed — they were placeholder-grade
%   surfaces that didn't match the rest of the app's professional polish.
%   The legacy properties (DashboardStatusArea, DashReadinessArea,
%   DashboardSummaryArea) are kept declared on QTAUWorkbenchApp so the VM
%   can still write to them as a defensive fallback path; this screen
%   simply doesn't construct them anymore.
%
%   All visible strings come from resources/labels.properties via Labels.
function DashboardScreen(app)
    Logger.info('DashboardScreen', 'Building Dashboard tab UI (Phase 1 refactor)');
    t = app.createSectionPage('Dashboard');

    %  Phase 7: rows go 6 → 7 — insert an empty-state row at index 2
    %  between the toolbar and the KPI strip. Height is 0 by default
    %  so the row is invisible until the VM detects a fresh project
    %  (no circuits, no recent jobs) and bumps RowHeight{2} to 110.
    g = uigridlayout(t, [7 2]);
    g.RowHeight     = {Theme.BTN_ROW_HEIGHT, 0, 104, 98, 200, 140, '1x'};
    app.DashOuterGrid = g;   % stash so the VM can toggle empty-state row
    g.ColumnWidth   = {'1.4x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Row 1: Toolbar ───────────────────────────────────────────────────────
    %  Phase 3: extended from 3 → 4 columns to host the project
    %  switcher dropdown at the left edge. Matches the workspace
    %  switcher position used by Azure Quantum / IBM Quantum
    %  Platform (left of the breadcrumb / description).
    toolbar = uigridlayout(g, [1 4]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 2];
    toolbar.ColumnWidth = {260, '1x', Theme.BTN_WIDTH, 100};
    toolbar.Padding = [0 0 0 0]; toolbar.ColumnSpacing = 8;
    toolbar.BackgroundColor = Theme.COLOR_BG;

    app.DashProjectDropdown = uidropdown(toolbar, ...
        'Items',     {'(loading projects…)'}, ...
        'ItemsData', {''}, ...
        'Tooltip',   Labels.get('dashboard_project_switcher_tooltip', ...
            'Switch active project'), ...
        'ValueChangedFcn', @(src,~) app.DashboardVm.onProjectChanged(src.Value));
    app.DashProjectDropdown.Layout.Row = 1; app.DashProjectDropdown.Layout.Column = 1;
    app.DashProjectDropdown.FontSize = 12;

    %  Phase 9: replaced the static meta-jargon subtitle ("Storyboard
    %  landing summary and workflow readiness") with a dynamic greeting
    %  the VM populates per refresh: "Welcome back, {user} · Last
    %  refreshed HH:MM · N projects · M circuits". Matches the IBM
    %  Quantum / Azure Quantum dashboard headers — operator gets useful
    %  status, not internal terminology. Default text is a neutral
    %  fallback that's overwritten on first paint.
    app.DashGreetingLabel = uilabel(toolbar, ...
        'Text', Labels.get('dashboard_toolbar_greeting_default', ...
            'Loading workspace summary…'));
    app.DashGreetingLabel.FontSize  = Theme.FONT_SIZE_MD;
    app.DashGreetingLabel.FontColor = Theme.COLOR_MUTED;
    app.DashGreetingLabel.Layout.Row = 1; app.DashGreetingLabel.Layout.Column = 2;
    app.DashGreetingLabel.VerticalAlignment = 'center';

    app.DashboardRefreshButton = uibutton(toolbar, ...
        'Text', [char(8635) ' ' Labels.get('dashboard_btn_refresh')], ...
        'ButtonPushedFcn', @(~,~)app.DashboardVm.onRefreshDashboard());
    app.DashboardRefreshButton.Layout.Row = 1; app.DashboardRefreshButton.Layout.Column = 3;
    app.styleBtn(app.DashboardRefreshButton, 'primary');
    app.DashboardRefreshButton.FontSize = Theme.FONT_SIZE_LG;
    app.DashboardRefreshButton.Tooltip = 'Pull live project dashboard data';

    exportBtn = uibutton(toolbar, ...
        'Text', [char(8599) ' ' Labels.get('dashboard_btn_export')]);
    exportBtn.Layout.Row = 1; exportBtn.Layout.Column = 4;
    app.styleBtn(exportBtn, 'ghost');
    exportBtn.FontSize = Theme.FONT_SIZE_LG;

    % ── Row 2: Empty State (Phase 7) ─────────────────────────────────────────
    %  Hero card shown ONLY for fresh projects — zero circuits, zero
    %  recent jobs, ActivityLog at the login/logout floor. The VM
    %  (paintEmptyState) detects this state and toggles g.RowHeight{2}
    %  + panel.Visible at runtime. When data starts flowing in, the
    %  panel hides cleanly without a layout re-flow on every refresh.
    app.DashEmptyStatePanel = uipanel(g, ...
        'Title', '', ...
        'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'Visible', 'off');
    app.DashEmptyStatePanel.Layout.Row = 2;
    app.DashEmptyStatePanel.Layout.Column = [1 2];

    esGrid = uigridlayout(app.DashEmptyStatePanel, [3 1]);
    esGrid.RowHeight = {30, 28, '1x'};
    esGrid.RowSpacing = 4;
    esGrid.Padding = [16 12 16 12];
    esGrid.BackgroundColor = Theme.COLOR_CARD;

    esTitle = uilabel(esGrid, ...
        'Text', [char(9670) ' ' Labels.get('dashboard_empty_state_title', ...
            'Welcome to QDash')], ...
        'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment',   'center');
    esTitle.Layout.Row = 1; esTitle.Layout.Column = 1;

    esSub = uilabel(esGrid, ...
        'Text', Labels.get('dashboard_empty_state_subtitle', ...
            'Get started by uploading your first quantum circuit.'), ...
        'FontSize', 12, ...
        'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment',   'center', ...
        'Interpreter', 'none');
    esSub.Layout.Row = 2; esSub.Layout.Column = 1;

    esCtaWrap = uigridlayout(esGrid, [1 2]);
    esCtaWrap.Layout.Row = 3; esCtaWrap.Layout.Column = 1;
    esCtaWrap.ColumnWidth = {200, '1x'};
    esCtaWrap.Padding = [0 0 0 0];
    esCtaWrap.BackgroundColor = Theme.COLOR_CARD;

    esCtaBtn = uibutton(esCtaWrap, ...
        'Text', [char(9650) ' ' Labels.get('dashboard_empty_state_cta', ...
            'Upload a Circuit')], ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'BackgroundColor', Theme.COLOR_PRIMARY, ...
        'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~,~) app.onSelectSection('Upload'));
    esCtaBtn.Layout.Row = 1; esCtaBtn.Layout.Column = 1;

    % ── Row 3: KPI hero strip ────────────────────────────────────────────────
    kpiBar = uipanel(g, 'Title', '');
    kpiBar.Layout.Row = 3; kpiBar.Layout.Column = [1 2];   % Phase 7: shifted +1 for empty-state row
    kpiBar.BackgroundColor = Theme.COLOR_BG;
    kpiBar.BorderType = 'none';

    kb = uigridlayout(kpiBar, [1 4]);
    kb.ColumnWidth = {'1x','1x','1x','1x'};
    kb.Padding = [0 0 0 0]; kb.ColumnSpacing = Theme.GRID_ROW_SPACING;
    kb.BackgroundColor = Theme.COLOR_BG;

    %  Phase 3: KPI 4 (Pipeline Stage) is replaced with the Smart
    %  Next-Step CTA — the workflow stepper already shows the active
    %  stage, so duplicating it as a KPI was redundant. The CTA is a
    %  more useful occupant of that slot. KPIs 1-3 remain text labels
    %  but their value cells become clickable so users can jump to the
    %  related screen without navigating via the sidebar (Q-platform
    %  parity).
    kpiTitles  = { ...
        Labels.get('dashboard_kpi_active_project'), ...
        Labels.get('dashboard_kpi_circuit_version'), ...
        Labels.get('dashboard_kpi_target_backend')};
    kpiAccents = {Theme.COLOR_PURPLE, Theme.COLOR_PRIMARY, Theme.COLOR_PURPLE};
    kpiDefaults = { ...
        Labels.get('dashboard_kpi_default_project'), ...
        Labels.get('dashboard_kpi_default_circuit'), ...
        Labels.get('dashboard_kpi_default_backend')};
    kpiTargets  = {'Welcome', 'Analysis', 'Backends'};

    app.DashKpiLabels = cell(1, 4);
    for i = 1:3
        valBtn = localKpiCardClickable(kb, i, kpiTitles{i}, kpiDefaults{i}, ...
            kpiAccents{i}, app, kpiTargets{i});
        app.DashKpiLabels{i} = valBtn;
    end

    % KPI 4 — Smart Next-Step CTA card. The button itself sits inside
    % a localKpiCard layout so it visually matches the other KPI cards.
    app.DashNextStepButton = localNextStepCard(kb, 4, ...
        Labels.get('dashboard_kpi_next_step', 'Next Step'), Theme.COLOR_AMBER, app);
    % Keep the legacy DashKpiLabels{4} reference pointing at something
    % the VM can write to without crashing — point it at the button so
    % any straggling write that does .Text = '...' still works.
    app.DashKpiLabels{4} = app.DashNextStepButton;

    % ── Row 3: Workflow Storyboard (8-stage stepper) ──────────────────────────
    stepperPanel = uipanel(g, 'Title', Labels.get( ...
        'dashboard_panel_workflow_stepper', 'Workflow Storyboard'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_CARD);
    stepperPanel.Layout.Row = 4; stepperPanel.Layout.Column = [1 2];   % Phase 7: shifted +1

    %  Phase 10: dot row bumped 22→28 so the bigger 18-pt current-step
    %  glyph (●) doesn't clip; smaller completed/upcoming glyphs (12 pt)
    %  still fit comfortably. Visual weight stays on the active dot
    %  while the others recede — IBM Quantum / Material Stepper
    %  proportions.
    sgrid = uigridlayout(stepperPanel, [2 8]);
    sgrid.RowHeight = {28, 28};
    sgrid.ColumnWidth = repmat({'1x'}, 1, 8);
    sgrid.Padding = [12 6 12 6];
    sgrid.RowSpacing = 2;
    sgrid.ColumnSpacing = 6;
    sgrid.BackgroundColor = Theme.COLOR_CARD;

    stageNames = { ...
        Labels.get('dashboard_stepper_welcome',   'Projects'), ...
        Labels.get('dashboard_stepper_upload',    'Circuit'), ...
        Labels.get('dashboard_stepper_analysis',  'Analysis'), ...
        Labels.get('dashboard_stepper_backend',   'Backend'), ...
        Labels.get('dashboard_stepper_benchmark', 'Benchmark'), ...
        Labels.get('dashboard_stepper_predict',   'Predict'), ...
        Labels.get('dashboard_stepper_job',       'Job'), ...
        Labels.get('dashboard_stepper_results',   'Results')};

    %  Phase 2: stage → screen-key map for click-to-jump. Each stage
    %  name is a uibutton wired to app.onSelectSection(...) so the
    %  workflow stepper doubles as a navigation surface (Q-platform
    %  parity: IBM Quantum / Google Cirq dashboards make every
    %  workflow stage clickable).
    stageScreens = {'Welcome','Upload','Analysis','Backends', ...
                    'Benchmark','Prediction','Jobs','Results'};
    app.DashStepperDots  = cell(1, 8);
    app.DashStepperNames = cell(1, 8);
    for i = 1:8
        % Top row: dot/glyph (default to upcoming ○ until VM updates).
        % Phase 10: state-graded glyphs — paintWorkflowStepper sizes
        % each dot per state. Default here is upcoming = small ○ at
        % 12 pt in muted (faint future); completed becomes • at 12 pt
        % in success (quiet done); current becomes ● at 18 pt bold in
        % primary (emphatic HERE). Size + fill encode state, not just
        % colour — readable for colour-blind operators too.
        dotLbl = uilabel(sgrid, ...
            'Text', char(9675), ...   % ○ (outlined circle, upcoming)
            'FontSize', 12, ...
            'FontColor', Theme.COLOR_MUTED, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'center');
        dotLbl.Layout.Row = 1; dotLbl.Layout.Column = i;
        app.DashStepperDots{i} = dotLbl;

        % Bottom row: clickable stage name. Phase 10: explicit
        % BackgroundColor matches the stepper panel so the uibutton's
        % default outline blends in — chip reads as a clickable label,
        % not a tab-button. paintWorkflowStepper inverts FontWeight
        % (bold for current, normal for others) and FontColor so the
        % active stage stands out without 8 outlined boxes competing.
        targetScreen = stageScreens{i};
        nmBtn = uibutton(sgrid, ...
            'Text', stageNames{i}, ...
            'FontSize', 11, ...
            'FontColor', Theme.COLOR_MUTED, ...
            'BackgroundColor', Theme.COLOR_CARD, ...
            'HorizontalAlignment', 'center', ...
            'Tooltip', sprintf('Jump to %s', stageNames{i}), ...
            'ButtonPushedFcn', @(~,~) app.onSelectSection(targetScreen));
        nmBtn.Layout.Row = 2; nmBtn.Layout.Column = i;
        app.DashStepperNames{i} = nmBtn;
    end

    % ── Row 4: Run Readiness (left) + Activity Trend (right) ──────────────────
    readinessPanel = uipanel(g, 'Title', Labels.get( ...
        'dashboard_panel_run_readiness', 'Run Readiness'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_CARD);
    readinessPanel.Layout.Row = 5; readinessPanel.Layout.Column = 1;   % Phase 7: shifted +1

    rg = uigridlayout(readinessPanel, [2 2]);
    rg.RowHeight = {'1x', '1x'};
    rg.ColumnWidth = {'1x', '1x'};
    rg.Padding = [16 14 16 14];
    rg.RowSpacing = 12; rg.ColumnSpacing = 14;
    rg.BackgroundColor = Theme.COLOR_CARD;

    readyTitles = { ...
        Labels.get('dashboard_readiness_qubits',   'Qubits'), ...
        Labels.get('dashboard_readiness_fidelity', 'Predicted fidelity'), ...
        Labels.get('dashboard_readiness_match',    'Similarity score'), ...
        Labels.get('dashboard_readiness_queue',    'Expected queue')};
    readyAccents = {Theme.COLOR_PRIMARY, Theme.COLOR_SUCCESS, ...
                    Theme.COLOR_PURPLE,  Theme.COLOR_AMBER};
    %  Phase 9: switched from localKpiCard (caption + value) to
    %  localReadinessCard (caption + value + hint). When the value is
    %  the em-dash empty placeholder, the hint label spells out the
    %  next concrete action ("Upload a circuit" / "Run prediction" /
    %  …) so a fresh project doesn't look like a wall of dashes. The
    %  VM clears the hint as soon as a real value lands.
    app.DashReadinessLabels = cell(1, 4);
    app.DashReadinessHints  = cell(1, 4);
    for i = 1:4
        [valLbl, hintLbl] = localReadinessCard(rg, readyTitles{i}, ...
            char(8212), readyAccents{i});
        cardPanel = valLbl.Parent.Parent.Parent;
        cardPanel.Layout.Row = ceil(i / 2);
        cardPanel.Layout.Column = mod(i - 1, 2) + 1;
        app.DashReadinessLabels{i} = valLbl;
        app.DashReadinessHints{i}  = hintLbl;
    end

    %  Phase 2: row-4 right slot is now Backend Health (was Activity
    %  Trend, which moves to its own full-width row 5 below). Backend
    %  Health is a 1×6 grid of mini-cards; the VM populates them from
    %  BackendsViewModel.fetchBackends so the data is consistent with
    %  the Backends tab.
    healthPanel = uipanel(g, 'Title', Labels.get( ...
        'dashboard_panel_backend_health', 'Backend Health'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_CARD);
    healthPanel.Layout.Row = 5; healthPanel.Layout.Column = 2;   % Phase 7: shifted +1

    %  Phase 9: was a 1×6 row, every card too narrow to render the
    %  backend name + qubit-count + status without aggressive
    %  truncation ("ibm_pitt…", "156q · ONLI…"). Re-flowed to 2×3
    %  so each card gets ~2× width — names and "156q · ONLINE"
    %  fit cleanly. Card content stays the same; only the grid
    %  geometry changed.
    hg = uigridlayout(healthPanel, [2 3]);
    hg.ColumnWidth = repmat({'1x'}, 1, 3);
    hg.RowHeight   = {'1x', '1x'};
    hg.Padding = [10 10 10 10]; hg.ColumnSpacing = 8; hg.RowSpacing = 8;
    hg.BackgroundColor = Theme.COLOR_CARD;

    app.DashBackendHealthCards = cell(1, 6);
    for i = 1:6
        card = localBackendHealthCard(hg);
        card.panel.Layout.Row    = ceil(i / 3);
        card.panel.Layout.Column = mod(i - 1, 3) + 1;
        app.DashBackendHealthCards{i} = card;
    end

    %  Phase 2: Activity Trend (jobs/day) moved to its own row, full
    %  width. Was sharing row 4 with Backend Health; the chart deserves
    %  the horizontal real estate for clean 7-day x-axis labels.
    activityPanel = uipanel(g, 'Title', Labels.get( ...
        'dashboard_panel_activity_trend_jobs', 'Job Submissions (last 7 days)'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_CARD);
    activityPanel.Layout.Row = 6; activityPanel.Layout.Column = [1 2];   % Phase 7: shifted +1

    %  Phase 4: split inner panel into a 2-row layout — stats subline
    %  on top, chart axes below. Stats subline is computed from the
    %  same listJobs response the chart consumes (no extra HTTP).
    apg = uigridlayout(activityPanel, [2 1]);
    apg.RowHeight = {20, '1x'};
    apg.Padding = [10 6 10 10]; apg.RowSpacing = 4;
    apg.BackgroundColor = Theme.COLOR_CARD;

    app.DashStatsSubline = uilabel(apg, ...
        'Text', '', ...
        'FontSize', 11, ...
        'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment',   'center');
    app.DashStatsSubline.Layout.Row = 1; app.DashStatsSubline.Layout.Column = 1;

    app.DashActivityAxes = uiaxes(apg);
    app.DashActivityAxes.Layout.Row = 2; app.DashActivityAxes.Layout.Column = 1;
    app.styleAxes(app.DashActivityAxes);
    app.DashActivityAxes.Title.String  = '';
    app.DashActivityAxes.XLabel.String = '';
    app.DashActivityAxes.YLabel.String = '';

    % ── Row 5: Recent Activity table with pagination ─────────────────────────
    activityTablePanel = uipanel(g, 'Title', Labels.get( ...
        'dashboard_panel_recent_activity', 'Recent Activity'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'FontWeight', 'bold', 'FontSize', 12, ...
        'ForegroundColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_CARD);
    activityTablePanel.Layout.Row = 7; activityTablePanel.Layout.Column = [1 2];   % Phase 7: shifted +1

    atg = uigridlayout(activityTablePanel, [2 1]);
    atg.RowHeight = {'1x', 32};
    atg.RowSpacing = 6;
    atg.Padding = [10 10 10 10];
    atg.BackgroundColor = Theme.COLOR_CARD;

    app.DashActivityTable = uitable(atg, ...
        'ColumnName',  Labels.cols('dashboard_activity_cols', ...
            {'Time', 'Action', 'Status'}), ...
        'ColumnWidth', {220, 700, 160}, ...
        'RowName',     {}, ...
        'SelectionType', 'row', ...
        'Multiselect',   'off');
    app.DashActivityTable.Layout.Row = 1; app.DashActivityTable.Layout.Column = 1;
    app.styleTable(app.DashActivityTable);

    %  Phase 5: right-click context menu on the unified activity feed.
    %  Items 1-2 are only meaningful for job rows (the VM's row-type
    %  metadata is consulted at click time and the action no-ops on UI
    %  rows); item 3 always works (copies job_id for job rows or the
    %  timestamp for UI rows). Selection is the currently right-clicked
    %  row — uitable in R2025+ sets Selection on right-click before
    %  opening the menu.
    activityCtxMenu = uicontextmenu(app.UIFigure);
    uimenu(activityCtxMenu, 'Text', 'View Job', ...
        'MenuSelectedFcn', @(~,~) app.DashboardVm.onActivityViewJob());
    uimenu(activityCtxMenu, 'Text', 'Open Results', ...
        'MenuSelectedFcn', @(~,~) app.DashboardVm.onActivityOpenResults());
    uimenu(activityCtxMenu, 'Text', 'Copy ID', 'Separator', 'on', ...
        'MenuSelectedFcn', @(~,~) app.DashboardVm.onActivityCopyId());
    app.DashActivityTable.ContextMenu = activityCtxMenu;

    pagerGrid = uigridlayout(atg, [1 3]);
    pagerGrid.Layout.Row = 2; pagerGrid.Layout.Column = 1;
    pagerGrid.ColumnWidth = {110, '1x', 110};
    pagerGrid.Padding = [0 0 0 0];
    pagerGrid.BackgroundColor = Theme.COLOR_CARD;

    app.DashActivityPrevBtn = uibutton(pagerGrid, ...
        'Text', [char(9664) ' Prev'], ...
        'ButtonPushedFcn', @(~,~)app.DashboardVm.onActivityPrevPage());
    app.DashActivityPrevBtn.Layout.Row = 1; app.DashActivityPrevBtn.Layout.Column = 1;
    app.styleBtn(app.DashActivityPrevBtn, 'ghost');

    app.DashActivityPageLabel = uilabel(pagerGrid, ...
        'Text', 'Page 1', 'FontSize', 12, ...
        'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment',   'center');
    app.DashActivityPageLabel.Layout.Row = 1; app.DashActivityPageLabel.Layout.Column = 2;

    app.DashActivityNextBtn = uibutton(pagerGrid, ...
        'Text', ['Next ' char(9654)], ...
        'ButtonPushedFcn', @(~,~)app.DashboardVm.onActivityNextPage());
    app.DashActivityNextBtn.Layout.Row = 1; app.DashActivityNextBtn.Layout.Column = 3;
    app.styleBtn(app.DashActivityNextBtn, 'ghost');

    Logger.info('DashboardScreen', 'Dashboard tab UI built successfully');
end

function [valLbl, hintLbl] = localReadinessCard(parent, captionText, valueText, accent)
    % Phase 9 helper: 3-row Run Readiness mini-card — caption / value /
    % hint. The hint label is empty by default and populated by the VM
    % when the value is the em-dash placeholder so a fresh project
    % shows actionable next-steps ("Upload a circuit") instead of a
    % wall of em-dashes. Caller assigns Layout.Row/Column on the
    % returned panel (reachable as valLbl.Parent.Parent.Parent).
    p = uipanel(parent, 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);

    pg = uigridlayout(p, [1 2]);
    pg.ColumnWidth = {6, '1x'};
    pg.RowHeight = {'1x'};
    pg.Padding = [0 6 6 6]; pg.ColumnSpacing = 8;
    pg.BackgroundColor = Theme.COLOR_CARD;

    strip = uipanel(pg, 'BorderType', 'none');
    strip.Layout.Row = 1; strip.Layout.Column = 1;
    strip.BackgroundColor = accent;

    inner = uigridlayout(pg, [3 1]);
    inner.Layout.Row = 1; inner.Layout.Column = 2;
    inner.RowHeight = {14, '1x', 16};
    inner.RowSpacing = 1; inner.Padding = [4 0 0 0];
    inner.BackgroundColor = Theme.COLOR_CARD;

    capLbl = uilabel(inner, 'Text', upper(char(captionText)), ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_LABEL); %#ok<NASGU>
    capLbl.Layout.Row = 1; capLbl.Layout.Column = 1;

    valLbl = uilabel(inner, 'Text', char(valueText), ...
        'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'VerticalAlignment', 'center', ...
        'Interpreter', 'none');
    valLbl.Layout.Row = 2; valLbl.Layout.Column = 1;

    hintLbl = uilabel(inner, 'Text', '', ...
        'FontSize', 10, ...
        'FontColor', Theme.COLOR_MUTED, ...
        'VerticalAlignment', 'top', ...
        'Interpreter', 'none');
    hintLbl.Layout.Row = 3; hintLbl.Layout.Column = 1;
end

function valLbl = localKpiCard(parent, col, captionText, valueText, accent)
    % Local helper for the KPI hero strip + Run Readiness mini-grid.
    % Returns the value uilabel so the caller can stash it for later
    % updates; the parent panel is reachable as valLbl.Parent.Parent.
    p = uipanel(parent, 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    if ~isempty(col)
        p.Layout.Row = 1; p.Layout.Column = col;
    end

    pg = uigridlayout(p, [1 2]);
    pg.ColumnWidth = {6, '1x'};
    pg.RowHeight = {'1x'};
    pg.Padding = [0 6 6 6]; pg.ColumnSpacing = 8;
    pg.BackgroundColor = Theme.COLOR_CARD;

    % Coloured accent strip.
    strip = uipanel(pg, 'BorderType', 'none');
    strip.Layout.Row = 1; strip.Layout.Column = 1;
    strip.BackgroundColor = accent;

    inner = uigridlayout(pg, [2 1]);
    inner.Layout.Row = 1; inner.Layout.Column = 2;
    inner.RowHeight = {16, '1x'};
    inner.RowSpacing = 2; inner.Padding = [4 0 0 0];
    inner.BackgroundColor = Theme.COLOR_CARD;

    capLbl = uilabel(inner, 'Text', upper(char(captionText)), ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_LABEL); %#ok<NASGU>
    capLbl.Layout.Row = 1; capLbl.Layout.Column = 1;

    valLbl = uilabel(inner, 'Text', char(valueText), ...
        'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'Interpreter', 'none');
    valLbl.Layout.Row = 2; valLbl.Layout.Column = 1;
end

function valBtn = localKpiCardClickable(parent, col, captionText, valueText, accent, app, targetScreen)
    % Phase 3 helper: same visual as localKpiCard but the value cell
    % is a uibutton wired to app.onSelectSection(targetScreen). Used
    % for KPIs 1-3 so the operator can click "Active Project" etc.
    % to jump to the related screen.
    p = uipanel(parent, 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    p.Layout.Row = 1; p.Layout.Column = col;

    pg = uigridlayout(p, [1 2]);
    pg.ColumnWidth = {6, '1x'};
    pg.RowHeight = {'1x'};
    pg.Padding = [0 6 6 6]; pg.ColumnSpacing = 8;
    pg.BackgroundColor = Theme.COLOR_CARD;

    strip = uipanel(pg, 'BorderType', 'none');
    strip.Layout.Row = 1; strip.Layout.Column = 1;
    strip.BackgroundColor = accent;

    inner = uigridlayout(pg, [2 1]);
    inner.Layout.Row = 1; inner.Layout.Column = 2;
    inner.RowHeight = {16, '1x'};
    inner.RowSpacing = 2; inner.Padding = [4 0 0 0];
    inner.BackgroundColor = Theme.COLOR_CARD;

    capLbl = uilabel(inner, 'Text', upper(char(captionText)), ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_LABEL); %#ok<NASGU>
    capLbl.Layout.Row = 1; capLbl.Layout.Column = 1;

    valBtn = uibutton(inner, ...
        'Text', char(valueText), ...
        'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'HorizontalAlignment', 'left', ...
        'Tooltip', sprintf('Jump to %s', targetScreen), ...
        'ButtonPushedFcn', @(~,~) app.onSelectSection(targetScreen));
    valBtn.Layout.Row = 2; valBtn.Layout.Column = 1;
end

function btn = localNextStepCard(parent, col, captionText, accent, app)
    % Phase 3 helper: the Smart Next-Step KPI card — caption + a single
    % large action button. The VM's paintNextStep updates the button
    % Text + ButtonPushedFcn per pipeline_stage so the same widget
    % adapts (e.g. "▲ Upload a circuit" vs "▶ Submit to IBM").
    p = uipanel(parent, 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    p.Layout.Row = 1; p.Layout.Column = col;

    pg = uigridlayout(p, [1 2]);
    pg.ColumnWidth = {6, '1x'};
    pg.RowHeight = {'1x'};
    pg.Padding = [0 6 6 6]; pg.ColumnSpacing = 8;
    pg.BackgroundColor = Theme.COLOR_CARD;

    strip = uipanel(pg, 'BorderType', 'none');
    strip.Layout.Row = 1; strip.Layout.Column = 1;
    strip.BackgroundColor = accent;

    inner = uigridlayout(pg, [2 1]);
    inner.Layout.Row = 1; inner.Layout.Column = 2;
    inner.RowHeight = {16, '1x'};
    inner.RowSpacing = 4; inner.Padding = [4 4 0 4];
    inner.BackgroundColor = Theme.COLOR_CARD;

    capLbl = uilabel(inner, 'Text', upper(char(captionText)), ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_LABEL); %#ok<NASGU>
    capLbl.Layout.Row = 1; capLbl.Layout.Column = 1;

    %  Phase 9: stripped the filled-button background entirely so
    %  the Next-Step card visually matches the other 3 KPI cards
    %  (caption + heading-styled value). The accent strip on the
    %  left already signals the CTA-ness of the card, and the
    %  text remains clickable. Was a giant purple button that
    %  dominated the row; now it's a uniform value-link slot.
    btn = uibutton(inner, ...
        'Text', '—', ...
        'FontSize', 18, 'FontWeight', 'bold', ...
        'BackgroundColor', Theme.COLOR_CARD, ...
        'FontColor', Theme.COLOR_HEADING, ...
        'HorizontalAlignment', 'left', ...
        'Tooltip', 'Adapts to the current pipeline stage', ...
        'ButtonPushedFcn', @(~,~) app.onSelectSection('Projects'));
    btn.Layout.Row = 2; btn.Layout.Column = 1;
end

function card = localBackendHealthCard(parent)
    % Phase 2 helper: compact backend mini-card. Phase 9 layout is a
    % 2-column row so the status dot sits left of the name (chip-style)
    % rather than stacked above it — fits the wider 2×3 cells better
    % and matches IBM Quantum's backend chip pattern. Caller assigns
    % card.panel.Layout.Row/Column themselves.
    p = uipanel(parent, 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);

    %  Outer 1×2: [dot 22px][text col 1x]
    pg = uigridlayout(p, [1 2]);
    pg.ColumnWidth = {22, '1x'};
    pg.RowHeight   = {'1x'};
    pg.ColumnSpacing = 6; pg.Padding = [10 6 10 6];
    pg.BackgroundColor = Theme.COLOR_CARD;

    dotLbl = uilabel(pg, ...
        'Text', char(9679), ...           % ● placeholder
        'FontSize', 16, ...
        'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment',   'center');
    dotLbl.Layout.Row = 1; dotLbl.Layout.Column = 1;

    %  Inner 2×1: [name][qubit/status subtitle]
    txtCol = uigridlayout(pg, [2 1]);
    txtCol.Layout.Row = 1; txtCol.Layout.Column = 2;
    txtCol.RowHeight = {'1x', '1x'};
    txtCol.RowSpacing = 0; txtCol.Padding = [0 0 0 0];
    txtCol.BackgroundColor = Theme.COLOR_CARD;

    nameLbl = uilabel(txtCol, ...
        'Text', char(8212), ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment',   'bottom', ...
        'Interpreter', 'none');
    nameLbl.Layout.Row = 1; nameLbl.Layout.Column = 1;

    qubitsLbl = uilabel(txtCol, ...
        'Text', '', ...
        'FontSize', 11, ...
        'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment',   'top');
    qubitsLbl.Layout.Row = 2; qubitsLbl.Layout.Column = 1;

    card = struct('panel', p, 'dotLbl', dotLbl, ...
                  'nameLbl', nameLbl, 'qubitsLbl', qubitsLbl);
end
