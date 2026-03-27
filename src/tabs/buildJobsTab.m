% buildJobsTab  Populates the Jobs section panel.
%
%   Layout (3-column grid, 3 rows):
%     Row 1:      Full-width toolbar (Refresh Jobs / Cancel / Pause).
%     Row 2, Col 1: Job Monitoring table.
%     Row 2, Col 2: 6 px resizable divider.
%     Row 2, Col 3: Live Monitor Notes text area.
%     Row 3:      Full-width Detailed Job Logs panel.
function buildJobsTab(app)
    t = app.createSectionPage('Jobs');

    % ── Root grid: 3 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {44, '1x', 190};
    g.ColumnWidth   = {'1.2x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Top toolbar — Refresh / Cancel / Pause (full width) ───────────────────
    top=uigridlayout(g,[1 3]);
    top.Layout.Row=1; top.Layout.Column=[1 3];
    top.ColumnWidth={'1x','1x','1x'};
    top.Padding=[0 0 0 0];
    top.BackgroundColor=[0.96 0.97 0.99];

    app.JobsRefreshButton=uibutton(top,'Text','Refresh Jobs', ...
        'ButtonPushedFcn',@(~,~)app.onRefreshJobs());
    app.styleBtn(app.JobsRefreshButton,'primary');
    app.JobsRefreshButton.Tooltip='Reload all jobs from /api/jobs';

    app.CancelJobButton=uibutton(top,'Text','Cancel Selected Job', ...
        'ButtonPushedFcn',@(~,~)app.onCancelJob());
    app.styleBtn(app.CancelJobButton,'danger');
    app.CancelJobButton.Tooltip='Send cancel request for the highlighted job';

    pauseBtn=uibutton(top,'Text','Pause Job'); app.styleBtn(pauseBtn,'ghost');

    % ── Column divider ────────────────────────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=2; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Job Monitoring table (left panel) ─────────────────────────────────────
    jobPanel=uipanel(g,'Title','Job Monitoring Dashboard');
    jobPanel.Layout.Row=2; jobPanel.Layout.Column=1; jobPanel.BackgroundColor=[1 1 1];

    jg=uigridlayout(jobPanel,[1 1]);
    jg.Padding=[12 10 12 10];
    jg.BackgroundColor=[1 1 1];
    app.JobsTable=uitable(jg);
    app.JobsTable.ColumnName={'Job ID','Backend','Status','Progress','Created'};
    app.JobsTable.Data={ ...
        'job-001','ibm_brisbane','running','67%','2026-03-16 15:14'; ...
        'job-002','ibm_kyiv','queued','12%','2026-03-16 15:10'; ...
        'job-000','ibm_brisbane','completed','100%','2026-03-16 14:40'};
    app.styleTable(app.JobsTable);

    % ── Live Monitor Notes (right panel) ─────────────────────────────────────
    trendPanel=uipanel(g,'Title','Live Monitor Notes');
    trendPanel.Layout.Row=2; trendPanel.Layout.Column=3; trendPanel.BackgroundColor=[1 1 1];

    tg=uigridlayout(trendPanel,[1 1]);
    tg.Padding=[12 10 12 10];
    tg.BackgroundColor=[1 1 1];
    app.JobStatusArea=uitextarea(tg,'Editable','off'); app.JobStatusArea.FontSize=12;
    app.JobStatusArea.Value={ ...
        'Real-time monitoring', ...
        '- Current job progress: 67 %', ...
        '- Partial results packet count: 9', ...
        '- Error trend: stable', ...
        '- Readout warnings: none', ...
        '- Pause and cancel controls shown as storyboard placeholders', ...
        '- Detailed job logs available below'};

    % ── Detailed Job Logs (full width) ────────────────────────────────────────
    % Timestamped log lines from the backend — dark terminal style matches the
    % Developer Event Console in the Settings tab for visual consistency.
    logPanel=uipanel(g,'Title','Detailed Job Logs');
    logPanel.Layout.Row=3; logPanel.Layout.Column=[1 3];
    logPanel.BackgroundColor=[0.06 0.08 0.12];  % dark panel background

    lg=uigridlayout(logPanel,[1 1]);
    lg.Padding=[12 10 12 10];
    lg.BackgroundColor=[0.06 0.08 0.12];
    logs=uitextarea(lg,'Editable','off');
    logs.FontName='Courier New'; logs.FontSize=12;
    logs.BackgroundColor=[0.06 0.08 0.12];  % same dark background as EventLogArea
    logs.FontColor=[0.72 0.94 0.64];        % same green text as EventLogArea
    logs.Value={ ...
        '[15:14:02] job-001 submitted to ibm_brisbane', ...
        '[15:14:31] queue accepted', ...
        '[15:15:08] execution phase started', ...
        '[15:15:40] partial counts packet 1 received', ...
        '[15:16:15] partial counts packet 2 received', ...
        '[15:16:52] confidence trend remains within expected range'};
end
