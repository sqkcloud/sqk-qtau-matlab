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

    g = uigridlayout(t, [3 2]);
    g.RowHeight     = {34, '1x', 215};
    g.ColumnWidth   = {'1.2x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Toolbar ──────────────────────────────────────────────────────────────
    %   Layout (matches the Backends / Circuits / Projects / Reports
    %   pattern): search field grows to fill the leftover space; the
    %   Search button hugs it; Refresh / Cancel / Pause sit
    %   right-aligned with fixed widths.
    top = uigridlayout(g, [1 5]);
    top.Layout.Row = 1; top.Layout.Column = [1 2];
    top.ColumnWidth = {'1x', 90, 110, 110, 100};
    top.Padding = [0 0 0 0]; top.ColumnSpacing = 6;
    top.BackgroundColor = Theme.COLOR_BG;

    % Search field — filters the in-memory job list by Job ID or
    % Circuit (case-insensitive substring match on column 1 + 2).
    app.JobsSearchField = uieditfield(top, 'text', ...
        'Placeholder', 'Search by Job ID or Circuit ID...', ...
        'ValueChangedFcn', @(src,~)app.JobsVm.onSearch(src.Value));
    app.JobsSearchField.Layout.Row = 1; app.JobsSearchField.Layout.Column = 1;
    app.JobsSearchField.FontSize = 12;

    % Search button — char(8981) is the same magnifying-glass glyph
    % used by the Backends / Circuits search toolbars.
    searchBtn = uibutton(top, 'Text', [char(8981) ' Search'], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onSearch(app.JobsSearchField.Value));
    searchBtn.Layout.Row = 1; searchBtn.Layout.Column = 2;
    app.styleBtn(searchBtn, 'ghost');

    app.JobsRefreshButton = uibutton(top, 'Text', [char(8635) ' ' Labels.get('jobs_btn_refresh')], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onRefreshJobs());
    app.JobsRefreshButton.Layout.Row = 1; app.JobsRefreshButton.Layout.Column = 3;
    app.styleBtn(app.JobsRefreshButton, 'primary');
    app.JobsRefreshButton.FontSize = 14;
    app.JobsRefreshButton.Tooltip = 'Refresh the jobs list';

    app.CancelJobButton = uibutton(top, 'Text', [char(10005) ' ' Labels.get('jobs_btn_cancel')], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onCancelJob());
    app.CancelJobButton.Layout.Row = 1; app.CancelJobButton.Layout.Column = 4;
    app.styleBtn(app.CancelJobButton, 'danger');
    app.CancelJobButton.FontSize = 14;
    app.CancelJobButton.Tooltip = 'Cancel the selected job';

    app.PauseJobButton = uibutton(top, 'Text', [char(9208) ' ' Labels.get('jobs_btn_pause')], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onPauseJob());
    app.PauseJobButton.Layout.Row = 1; app.PauseJobButton.Layout.Column = 5;
    app.styleBtn(app.PauseJobButton, 'ghost');
    app.PauseJobButton.FontSize = 14;
    app.PauseJobButton.Tooltip = 'Pause the selected job';

    % ── Job Monitoring table (left) ───────────────────────────────────────────
    jobPanel = uipanel(g, 'Title', Labels.get('jobs_panel_monitoring'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    jobPanel.Layout.Row = 2; jobPanel.Layout.Column = 1; jobPanel.BackgroundColor = Theme.COLOR_CARD;

    jg = uigridlayout(jobPanel, [2 1]);
    jg.RowHeight = {'1x', 32};
    jg.RowSpacing = 6;
    jg.Padding = [12 10 12 10]; jg.BackgroundColor = Theme.COLOR_CARD;
    app.JobsTable = uitable(jg);
    app.JobsTable.Layout.Row = 1; app.JobsTable.Layout.Column = 1;
    app.JobsTable.ColumnName = Labels.cols('jobs_table_cols', {'Job ID','Circuit','Backend','Status','Progress','Created','Mitigation'});
    %  Explicit pixel widths (instead of the default ColumnWidth='auto')
    %  so the 7 columns total ~1260 px and overflow narrow windows. With
    %  'auto' MATLAB tries to fit content into the container by squeezing
    %  rightmost columns until they vanish — Status / Progress / Created
    %  / Mitigation were being clipped off-screen entirely. Fixed widths
    %  force the table to render at its intrinsic width and surface a
    %  CEF horizontal scrollbar when it exceeds the panel. Vertical
    %  scrolling between rows is automatic in uitable.
    %    Job ID 280, Circuit 360, Backend 140, Status 110,
    %    Progress 80, Created 180, Mitigation 110
    app.JobsTable.ColumnWidth = {280, 360, 140, 110, 80, 180, 110};
    app.JobsTable.Data = {};
    app.JobsTable.SelectionChangedFcn = @(src,~)app.JobsVm.onJobTableSelect(src);
    app.styleTable(app.JobsTable);

    % Pagination footer ──────────────────────────────────────────────────────
    pg = uigridlayout(jg, [1 3]);
    pg.Layout.Row = 2; pg.Layout.Column = 1;
    pg.ColumnWidth = {90, '1x', 90};
    pg.Padding = [0 0 0 0]; pg.ColumnSpacing = 8;
    pg.BackgroundColor = Theme.COLOR_CARD;

    app.JobsPrevButton = uibutton(pg, 'Text', [char(8592) ' ' Labels.get('jobs_btn_prev', 'Prev')], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onPrevPage());
    app.JobsPrevButton.Layout.Row = 1; app.JobsPrevButton.Layout.Column = 1;
    app.styleBtn(app.JobsPrevButton, 'ghost');
    app.JobsPrevButton.FontSize = 13;
    app.JobsPrevButton.Enable = 'off';

    app.JobsPageLabel = uilabel(pg, 'Text', sprintf(Labels.get('jobs_page_info_empty', 'Page %d  •  No jobs'), 1));
    app.JobsPageLabel.Layout.Row = 1; app.JobsPageLabel.Layout.Column = 2;
    app.JobsPageLabel.HorizontalAlignment = 'center';
    app.JobsPageLabel.FontSize = 12;
    app.JobsPageLabel.FontColor = Theme.COLOR_MUTED;

    app.JobsNextButton = uibutton(pg, 'Text', [Labels.get('jobs_btn_next', 'Next') ' ' char(8594)], ...
        'ButtonPushedFcn', @(~,~)app.JobsVm.onNextPage());
    app.JobsNextButton.Layout.Row = 1; app.JobsNextButton.Layout.Column = 3;
    app.styleBtn(app.JobsNextButton, 'ghost');
    app.JobsNextButton.FontSize = 13;
    app.JobsNextButton.Enable = 'off';

    % ── Live Monitor Notes (right) ────────────────────────────────────────────
    trendPanel = uipanel(g, 'Title', Labels.get('jobs_panel_live_notes'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    trendPanel.Layout.Row = 2; trendPanel.Layout.Column = 2; trendPanel.BackgroundColor = Theme.COLOR_CARD;

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
    logPanel.Layout.Row = 3; logPanel.Layout.Column = [1 2];
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
