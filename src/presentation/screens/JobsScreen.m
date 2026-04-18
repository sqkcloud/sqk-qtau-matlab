% JobsTab  Populates the Jobs section panel.
%
%   Layout:
%     Row 1 (44 px):   Toolbar — Refresh Jobs / Cancel Selected / Pause Job.
%     Row 2 ('1x'):    Job Monitoring table (left) | Live Monitor Notes (right).
%     Row 3 (190 px):  Full-width dark Detailed Job Logs console.
%
%   All visible strings come from resources/labels.properties via Labels.
function JobsScreen(app)
    Logger.info('JobsScreen', 'Building Jobs tab UI');
    t = app.createSectionPage('Jobs');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {34, '1x', 190};
    g.ColumnWidth   = {'1.2x', 6, '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Toolbar ──────────────────────────────────────────────────────────────
    top = uigridlayout(g, [1 4]);
    top.Layout.Row = 1; top.Layout.Column = [1 3];
    top.ColumnWidth = {'1x', 110, 110, 100};
    top.Padding = [0 0 0 0]; top.BackgroundColor = Theme.COLOR_BG;

    app.JobsRefreshButton = uibutton(top, 'Text', [char(8635) ' ' Labels.get('jobs_btn_refresh')], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onRefreshJobs());
    app.JobsRefreshButton.Layout.Row = 1; app.JobsRefreshButton.Layout.Column = 2;
    app.styleBtn(app.JobsRefreshButton, 'primary');
    app.JobsRefreshButton.FontSize = 14;
    app.JobsRefreshButton.Tooltip = 'GET /api/jobs';

    app.CancelJobButton = uibutton(top, 'Text', [char(10005) ' ' Labels.get('jobs_btn_cancel')], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onCancelJob());
    app.CancelJobButton.Layout.Row = 1; app.CancelJobButton.Layout.Column = 3;
    app.styleBtn(app.CancelJobButton, 'danger');
    app.CancelJobButton.FontSize = 14;
    app.CancelJobButton.Tooltip = 'POST /api/jobs/{id}/cancel';

    app.PauseJobButton = uibutton(top, 'Text', [char(9208) ' ' Labels.get('jobs_btn_pause')], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onPauseJob());
    app.PauseJobButton.Layout.Row = 1; app.PauseJobButton.Layout.Column = 4;
    app.styleBtn(app.PauseJobButton, 'ghost');
    app.PauseJobButton.FontSize = 14;
    app.PauseJobButton.Tooltip = 'POST /api/jobs/{id}/pause';

    % ── Column divider ────────────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = Theme.COLOR_DIVIDER; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Job Monitoring table (left) ───────────────────────────────────────────
    jobPanel = uipanel(g, 'Title', Labels.get('jobs_panel_monitoring'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    jobPanel.Layout.Row = 2; jobPanel.Layout.Column = 1; jobPanel.BackgroundColor = Theme.COLOR_CARD;

    jg = uigridlayout(jobPanel, [1 1]);
    jg.Padding = [12 10 12 10]; jg.BackgroundColor = Theme.COLOR_CARD;
    app.JobsTable = uitable(jg);
    app.JobsTable.ColumnName = Labels.cols('jobs_table_cols', {'Job ID','Backend','Status','Progress','Created'});
    app.JobsTable.Data = {};
    app.JobsTable.SelectionChangedFcn = @(src,~)app.JobsVm.onJobTableSelect(src);
    app.styleTable(app.JobsTable);

    % ── Live Monitor Notes (right) ────────────────────────────────────────────
    trendPanel = uipanel(g, 'Title', Labels.get('jobs_panel_live_notes'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    trendPanel.Layout.Row = 2; trendPanel.Layout.Column = 3; trendPanel.BackgroundColor = Theme.COLOR_CARD;

    tg = uigridlayout(trendPanel, [1 1]);
    tg.Padding = [12 10 12 10]; tg.BackgroundColor = Theme.COLOR_CARD;
    app.JobStatusArea = uitextarea(tg, 'Editable', 'off'); app.JobStatusArea.FontSize = 12;
    app.JobStatusArea.Value = { ...
        Labels.get('jobs_status_initial'), ...
        '', ...
        'Select a row to set the active job for Cancel/Pause/Results.'};

    % ── Detailed Job Logs (full width, dark terminal) ─────────────────────────
    logPanel = uipanel(g, 'Title', Labels.get('jobs_panel_logs'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    logPanel.Layout.Row = 3; logPanel.Layout.Column = [1 3];
    logPanel.BackgroundColor = Theme.CONSOLE_BG;

    lg = uigridlayout(logPanel, [1 1]);
    lg.Padding = [12 10 12 10]; lg.BackgroundColor = Theme.CONSOLE_BG;
    app.JobLogsArea = uitextarea(lg, 'Editable', 'off');
    app.JobLogsArea.FontName = 'Courier New'; app.JobLogsArea.FontSize = 12;
    app.JobLogsArea.BackgroundColor = Theme.CONSOLE_BG;
    app.JobLogsArea.FontColor = Theme.CONSOLE_FG;
    app.JobLogsArea.Value = {Labels.get('jobs_logs_initial', '[awaiting job data…]')};

    Logger.info('JobsScreen', 'Jobs tab UI built successfully');
end
