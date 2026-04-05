% DashboardTab  Populates the Dashboard section panel.
%
%   Layout (Google Analytics–style):
%     Row 1 (toolbar, 44 px)   — description + Refresh + Export buttons.
%     Row 2 (KPI bar, 104 px)  — 4 live metric cards (active project, circuit,
%                                  backend, pipeline stage).
%     Row 3 ('1x')             — Executive Summary | Status / Raw.
%     Row 4 ('1x')             — Storyboard Readiness | Recent Activity table.
%
%   KPI label handles are saved to app.DashKpiLabels so the refresh callback
%   can update them without rebuilding the layout.
%   All visible strings come from resources/labels.properties via Labels.
function DashboardScreen(app)
    Logger.info('DashboardScreen', 'Building Dashboard tab UI');
    t = app.createSectionPage('Dashboard');

    g = uigridlayout(t, [4 3]);
    g.RowHeight     = {Theme.BTN_ROW_HEIGHT, Theme.ACTION_BAR_HEIGHT, '1x', '1x'};
    g.ColumnWidth   = {'1.4x', Theme.DIVIDER_WIDTH, '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Toolbar ──────────────────────────────────────────────────────────────
    toolbar = uigridlayout(g, [1 3]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {'1x', Theme.BTN_WIDTH, 100};
    toolbar.Padding = [0 0 0 0];
    toolbar.BackgroundColor = Theme.COLOR_BG;

    desc = uilabel(toolbar, 'Text', Labels.get('dashboard_toolbar_desc'));
    desc.FontSize = Theme.FONT_SIZE_MD; desc.FontColor = Theme.COLOR_MUTED;
    desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center';

    app.DashboardRefreshButton = uibutton(toolbar, 'Text', [char(8635) ' ' Labels.get('dashboard_btn_refresh')], ...
        'ButtonPushedFcn', @(~,~)app.DashboardVm.onRefreshDashboard());
    app.DashboardRefreshButton.Layout.Row = 1; app.DashboardRefreshButton.Layout.Column = 2;
    app.styleBtn(app.DashboardRefreshButton, 'primary');
    app.DashboardRefreshButton.FontSize = Theme.FONT_SIZE_LG;
    app.DashboardRefreshButton.Tooltip = 'Pull live project dashboard data';

    exportBtn = uibutton(toolbar, 'Text', [char(8599) ' ' Labels.get('dashboard_btn_export')]);
    exportBtn.Layout.Row = 1; exportBtn.Layout.Column = 3;
    app.styleBtn(exportBtn, 'ghost');
    exportBtn.FontSize = Theme.FONT_SIZE_LG;

    % ── KPI card bar ──────────────────────────────────────────────────────────
    kpiBar = uipanel(g, 'Title', '');
    kpiBar.Layout.Row = 2; kpiBar.Layout.Column = [1 3];
    kpiBar.BackgroundColor = Theme.COLOR_BG;
    kpiBar.BorderType = 'none';

    kb = uigridlayout(kpiBar, [1 4]);
    kb.ColumnWidth = {'1x','1x','1x','1x'};
    kb.Padding = [0 0 0 0]; kb.ColumnSpacing = Theme.GRID_ROW_SPACING;
    kb.BackgroundColor = Theme.COLOR_BG;

    kpiTitles  = { ...
        Labels.get('dashboard_kpi_active_project',  'Active Project'), ...
        Labels.get('dashboard_kpi_circuit_version', 'Circuit Version'), ...
        Labels.get('dashboard_kpi_target_backend',  'Target Backend'), ...
        Labels.get('dashboard_kpi_pipeline_stage',  'Pipeline Stage')};
    kpiDefault = { ...
        Labels.get('dashboard_kpi_default_project', '—'), ...
        Labels.get('dashboard_kpi_default_circuit',  '—'), ...
        Labels.get('dashboard_kpi_default_backend',  '—'), ...
        Labels.get('dashboard_kpi_default_stage',    'Ready for upload')};
    kpiAccents = {Theme.COLOR_PRIMARY, Theme.COLOR_SUCCESS, Theme.COLOR_PURPLE, Theme.COLOR_AMBER};

    app.DashKpiLabels = cell(1, 4);
    for i = 1:4
        p = uipanel(kb, 'Title', ''); p.Layout.Row = 1; p.Layout.Column = i; p.BackgroundColor = Theme.COLOR_CARD;
        pg = uigridlayout(p, [1 2]); pg.ColumnWidth = {Theme.DIVIDER_WIDTH,'1x'}; pg.Padding = [0 0 0 0];
        pg.ColumnSpacing = 0; pg.BackgroundColor = Theme.COLOR_CARD;
        strip = uipanel(pg, 'Title', ''); strip.Layout.Row = 1; strip.Layout.Column = 1;
        strip.BackgroundColor = kpiAccents{i};
        inner = uigridlayout(pg, [2 1]); inner.Layout.Row = 1; inner.Layout.Column = 2;
        inner.RowHeight = {18,'1x'}; inner.Padding = Theme.KPI_INNER_PAD; inner.BackgroundColor = Theme.COLOR_CARD;
        l1 = uilabel(inner, 'Text', kpiTitles{i});
        l1.FontColor = Theme.COLOR_MUTED; l1.FontSize = Theme.FONT_SIZE; l1.Layout.Row = 1; l1.Layout.Column = 1;
        l2 = uilabel(inner, 'Text', kpiDefault{i});
        l2.FontSize = Theme.FONT_SIZE_TITLE; l2.FontWeight = 'bold'; l2.WordWrap = 'on';
        l2.Layout.Row = 2; l2.Layout.Column = 1;
        app.DashKpiLabels{i} = l2;
    end

    % ── Column divider (spans rows 3-4) ──────────────────────────────────────
    div = uipanel(g, 'Title', '');
    div.Layout.Row = [3 4]; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Executive Summary (left, row 3) ──────────────────────────────────────
    summaryPanel = uipanel(g, 'Title', Labels.get('dashboard_panel_executive_summary'));
    summaryPanel.Layout.Row = 3; summaryPanel.Layout.Column = 1; summaryPanel.BackgroundColor = [1 1 1];
    gp1 = uigridlayout(summaryPanel, [1 1]); gp1.BackgroundColor = [1 1 1]; gp1.Padding = [14 12 14 12];
    app.DashboardSummaryArea = uitextarea(gp1, 'Editable', 'off'); app.DashboardSummaryArea.FontSize = 13;
    app.DashboardSummaryArea.Value = {Labels.get('dashboard_status_initial')};

    % ── Storyboard Readiness (left, row 4) ───────────────────────────────────
    pipeline = uipanel(g, 'Title', Labels.get('dashboard_panel_storyboard'));
    pipeline.Layout.Row = 4; pipeline.Layout.Column = 1; pipeline.BackgroundColor = [1 1 1];
    pg = uigridlayout(pipeline, [1 1]); pg.BackgroundColor = [1 1 1]; pg.Padding = [14 12 14 12];
    app.DashReadinessArea = uitextarea(pg, 'Editable', 'off'); app.DashReadinessArea.FontSize = 12;
    app.DashReadinessArea.Value = { ...
        'Stage map (auto-updated on refresh):', ...
        '[ ]  Welcome / account setup', ...
        '[ ]  Upload and metadata', ...
        '[ ]  Analysis and similarity review', ...
        '[ ]  Backend exploration', ...
        '[ ]  Benchmark parameter planning', ...
        '[ ]  Prediction and job submission'};

    % ── Status / Raw (right, row 3) ───────────────────────────────────────────
    rawPanel = uipanel(g, 'Title', Labels.get('dashboard_panel_status_raw'));
    rawPanel.Layout.Row = 3; rawPanel.Layout.Column = 3; rawPanel.BackgroundColor = [1 1 1];
    gp2 = uigridlayout(rawPanel, [1 1]); gp2.BackgroundColor = [1 1 1]; gp2.Padding = [14 12 14 12];
    app.DashboardStatusArea = uitextarea(gp2, 'Editable', 'off'); app.DashboardStatusArea.FontSize = 12;
    app.DashboardStatusArea.Value = {'API health: —', 'Auth token: —', 'Last refresh: —'};

    % ── Recent Activity (right, row 4) ───────────────────────────────────────
    activity = uipanel(g, 'Title', Labels.get('dashboard_panel_recent_activity'));
    activity.Layout.Row = 4; activity.Layout.Column = 3; activity.BackgroundColor = [1 1 1];
    ag = uigridlayout(activity, [1 1]); ag.Padding = [14 12 14 12]; ag.BackgroundColor = [1 1 1];
    app.DashActivityTable = uitable(ag);
    app.DashActivityTable.ColumnName = Labels.cols('dashboard_table_cols_activity', {'Time','Action','Status'});
    app.DashActivityTable.Data = {};
    app.styleTable(app.DashActivityTable);

    Logger.info('DashboardScreen', 'Dashboard tab UI built successfully');
end
