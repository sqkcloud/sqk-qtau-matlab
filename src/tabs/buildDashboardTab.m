% buildDashboardTab  Populates the Dashboard section panel.
%
%   Layout follows a Google Analytics-style hierarchy:
%     Row 1 (toolbar, 44 px)  — description text + Refresh + Export buttons.
%     Row 2 (KPI bar, 104 px) — 4 metric cards spanning all columns.
%     Row 3 ('1x')            — Executive Summary (left) | Status (right).
%     Row 4 ('1x')            — Storyboard Readiness (left) | Recent Activity (right).
%     Column 2 (6 px divider) — drag to redistribute left/right panel widths.
%
%   Each content panel is placed directly into the root grid — no invisible
%   wrapper panels — giving consistent card spacing on all four sides.
function buildDashboardTab(app)
    t = app.createSectionPage('Dashboard');

    % ── Root grid: 4 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [4 3]);
    g.RowHeight     = {44, 72, '1x', '1x'};    % toolbar | KPI bar | content rows
    g.ColumnWidth   = {'1.4x', 6, '1x'};         % wider left; 6 px divider
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Toolbar row (full width) ──────────────────────────────────────────────
    % Mirrors the Google Analytics pattern: description on the left, action
    % buttons right-aligned so they never crowd the content below.
    toolbar = uigridlayout(g, [1 3]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {'1x', 190, 120};
    toolbar.Padding = [0 0 0 0];
    toolbar.BackgroundColor = [0.96 0.97 0.99];

    desc = uilabel(toolbar, 'Text', 'Pipeline workflow summary and real-time backend status');
    desc.FontSize = 13; desc.FontColor = [0.38 0.46 0.58];
    desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center';

    app.DashboardRefreshButton = uibutton(toolbar, 'Text', 'Refresh Dashboard', ...
        'ButtonPushedFcn', @(~,~)app.onRefreshDashboard());
    app.DashboardRefreshButton.Layout.Row = 1; app.DashboardRefreshButton.Layout.Column = 2;
    app.styleBtn(app.DashboardRefreshButton, 'primary');
    app.DashboardRefreshButton.Tooltip = 'Pull live data and update all KPI cards';

    exportBtn = uibutton(toolbar, 'Text', 'Export');
    exportBtn.Layout.Row = 1; exportBtn.Layout.Column = 3;
    app.styleBtn(exportBtn, 'ghost');

    % ── KPI card bar (full width) ─────────────────────────────────────────────
    % Four equal-width metric cards give an at-a-glance workflow snapshot.
    % Each card: white background, 6 px coloured left accent strip, label + value.
    kpiBar = uipanel(g, 'Title', '');
    kpiBar.Layout.Row = 2; kpiBar.Layout.Column = [1 3];
    kpiBar.BackgroundColor = [0.96 0.97 0.99];
    kpiBar.BorderType = 'none';

    kb = uigridlayout(kpiBar, [1 4]);
    kb.ColumnWidth = {'1x','1x','1x','1x'};
    kb.Padding = [0 0 0 0]; kb.ColumnSpacing = 12;
    kb.BackgroundColor = [0.96 0.97 0.99];

    labels  = {'Active Project','Circuit Version','Target Backend','Pipeline Stage'};
    values  = {'sqkadmin''s project','bernstein_vazirani_27.qasm','ibm_brisbane','Ready for upload'};
    accents = {[0.18 0.45 0.82],[0.10 0.54 0.36],[0.62 0.38 0.82],[0.75 0.48 0.10]};
    for i = 1:4
        p = uipanel(kb,'Title',''); p.Layout.Row=1; p.Layout.Column=i; p.BackgroundColor=[1 1 1];
        pg = uigridlayout(p,[1 2]); pg.ColumnWidth={6,'1x'}; pg.Padding=[0 0 0 0];
        pg.ColumnSpacing=0; pg.BackgroundColor=[1 1 1];
        strip = uipanel(pg,'Title',''); strip.Layout.Row=1; strip.Layout.Column=1;
        strip.BackgroundColor = accents{i};
        inner = uigridlayout(pg,[2 1]); inner.Layout.Row=1; inner.Layout.Column=2;
        inner.RowHeight={18,'1x'}; inner.Padding=[10 8 10 8]; inner.BackgroundColor=[1 1 1];
        l1 = uilabel(inner,'Text',labels{i});
        l1.FontColor=[0.38 0.46 0.58]; l1.FontSize=12; l1.Layout.Row=1; l1.Layout.Column=1;
        l2 = uilabel(inner,'Text',values{i});
        l2.FontSize=15; l2.FontWeight='bold'; l2.WordWrap='on'; l2.Layout.Row=2; l2.Layout.Column=1;
    end

    % ── Column divider (spans rows 3-4) ──────────────────────────────────────
    div = uipanel(g,'Title','');
    div.Layout.Row=[3 4]; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Executive Summary (left, row 3) ──────────────────────────────────────
    % Each panel is placed directly into the root grid — no extra wrapper —
    % so the card edges align consistently on all four sides.
    summaryPanel = uipanel(g,'Title','Executive Summary');
    summaryPanel.Layout.Row=3; summaryPanel.Layout.Column=1; summaryPanel.BackgroundColor=[1 1 1];
    gp1 = uigridlayout(summaryPanel,[1 1]); gp1.BackgroundColor=[1 1 1]; gp1.Padding=[14 12 14 12];
    app.DashboardSummaryArea = uitextarea(gp1,'Editable','off'); app.DashboardSummaryArea.FontSize=13;
    app.DashboardSummaryArea.Value={ ...
        'Circuit family: Bernstein-Vazirani / 27 qubits', ...
        'Latest similarity score vs QASMBench: 0.91', ...
        'Recommended backend: ibm_brisbane', ...
        'Predicted fidelity: 0.963 ± 0.012', ...
        'Expected queue duration: 7-12 min', ...
        'Run readiness: All required storyboard inputs available'};

    % ── Storyboard Readiness (left, row 4) ───────────────────────────────────
    pipeline = uipanel(g,'Title','Storyboard Readiness');
    pipeline.Layout.Row=4; pipeline.Layout.Column=1; pipeline.BackgroundColor=[1 1 1];
    pg = uigridlayout(pipeline,[1 1]); pg.BackgroundColor=[1 1 1]; pg.Padding=[14 12 14 12];
    area1 = uitextarea(pg,'Editable','off'); area1.FontSize=12;
    area1.Value={ ...
        'Current stage map', ...
        '[done]  Welcome / account setup', ...
        '[ready] Upload and metadata', ...
        '[ready] Analysis and similarity review', ...
        '[ready] Backend exploration', ...
        '[ready] Benchmark parameter planning', ...
        '[ready] Prediction and job submission demo'};

    % ── Status / Raw (right, row 3) ───────────────────────────────────────────
    rawPanel = uipanel(g,'Title','Status / Raw');
    rawPanel.Layout.Row=3; rawPanel.Layout.Column=3; rawPanel.BackgroundColor=[1 1 1];
    gp2 = uigridlayout(rawPanel,[1 1]); gp2.BackgroundColor=[1 1 1]; gp2.Padding=[14 12 14 12];
    app.DashboardStatusArea = uitextarea(gp2,'Editable','off'); app.DashboardStatusArea.FontSize=12;
    app.DashboardStatusArea.Value={ ...
        'API health: OK', ...
        'Auth token: available', ...
        'Project count loaded: 2', ...
        'Latest result package: result-001', ...
        'Last refresh: 2026-03-16 15:12:04'};

    % ── Recent Activity (right, row 4) ───────────────────────────────────────
    activity = uipanel(g,'Title','Recent Activity');
    activity.Layout.Row=4; activity.Layout.Column=3; activity.BackgroundColor=[1 1 1];
    ag = uigridlayout(activity,[1 1]); ag.Padding=[14 12 14 12]; ag.BackgroundColor=[1 1 1];
    tbl = uitable(ag);
    tbl.ColumnName={'Time','Action','Status'};
    tbl.Data={ ...
        '15:12','Loaded storyboard build','done'; ...
        '15:10','Fetched project list','done'; ...
        '15:05','Prepared demo report template','done'; ...
        '15:01','Updated navigation layout','done'};
    app.styleTable(tbl);
end
