% ReportsScreen  Redesigned Reports tab UI (Phase 6.5).
%
%   Layout (4 rows):
%     Row 1 (92 px):  KPI strip  → Total / PDF / HTML / Latest
%     Row 2 ('1x'):   Body       → Generator (left, 380 px) | Library (right, '1x')
%     Row 3 (60 px):  Distribution row (Open / PDF / Email / Print)
%     Row 4 (60 px):  Workflow row    (Detailed Analysis / Restart Pipeline)
%
%   Replaces the old 3-box layout that had:
%     - oversized empty boxes
%     - raw-text status area exposing /private/var/folders paths
%     - uilistbox of unstyled formatted strings (no columns, no sort, no search)
%     - no summary KPIs, no refresh button
%     - inert PDF / Email / Print buttons (now wired)
%     - a Restart Pipeline button that crashed when SettingsVm was lazy
%
%   All visible strings come from resources/labels.properties via Labels.

function ReportsScreen(app)
    Logger.info('ReportsScreen', 'Building Reports tab UI');
    t = app.createSectionPage('Reports');

    g = uigridlayout(t, [4 1]);
    g.RowHeight     = {92, '1x', 60, 60};
    g.ColumnWidth   = {'1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Row 1 — KPI strip ───────────────────────────────────────────────────
    kpiStrip = uigridlayout(g, [1 4]);
    kpiStrip.Layout.Row = 1; kpiStrip.Layout.Column = 1;
    kpiStrip.ColumnWidth = {'1x','1x','1x','1x'};
    kpiStrip.Padding = [0 0 0 0]; kpiStrip.ColumnSpacing = 12;
    kpiStrip.BackgroundColor = Theme.COLOR_BG;

    app.ReportsKpiTotal  = kpiCard(kpiStrip, ...
        Labels.get('reports_kpi_total',  'Total reports'),  '—');
    app.ReportsKpiPdf    = kpiCard(kpiStrip, ...
        Labels.get('reports_kpi_pdf',    'PDF reports'),    '—');
    app.ReportsKpiHtml   = kpiCard(kpiStrip, ...
        Labels.get('reports_kpi_html',   'HTML reports'),   '—');
    app.ReportsKpiLatest = kpiCard(kpiStrip, ...
        Labels.get('reports_kpi_latest', 'Latest activity'), '—');

    % ── Row 2 — Body (Generator | Library) ──────────────────────────────────
    body = uigridlayout(g, [1 2]);
    body.Layout.Row = 2; body.Layout.Column = 1;
    body.ColumnWidth = {380, '1x'};
    body.Padding = [0 0 0 0]; body.ColumnSpacing = 12;
    body.BackgroundColor = Theme.COLOR_BG;

    % ── Generator (left) ────────────────────────────────────────────────────
    genPanel = uipanel(body, 'Title', Labels.get('reports_panel_generator'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    genPanel.Layout.Row = 1; genPanel.Layout.Column = 1;
    genPanel.BackgroundColor = Theme.COLOR_CARD;

    gg = uigridlayout(genPanel, [6 2]);
    gg.RowHeight   = {30, 30, 30, 38, 16, '1x'};
    gg.ColumnWidth = {110, '1x'};
    gg.Padding = [16 12 16 12];
    gg.RowSpacing = 8; gg.ColumnSpacing = 8;
    gg.BackgroundColor = Theme.COLOR_CARD;

    lblTitle = uilabel(gg, 'Text', Labels.get('reports_label_title'), ...
        'FontColor', Theme.COLOR_LABEL, 'VerticalAlignment', 'center');
    lblTitle.Layout.Row = 1; lblTitle.Layout.Column = 1;
    app.ReportTitleField = uieditfield(gg, 'text', ...
        'Value', Labels.get('reports_title_default', 'Quantum Run Report'));
    app.ReportTitleField.Layout.Row = 1; app.ReportTitleField.Layout.Column = 2;

    lblFmt = uilabel(gg, 'Text', Labels.get('reports_label_format'), ...
        'FontColor', Theme.COLOR_LABEL, 'VerticalAlignment', 'center');
    lblFmt.Layout.Row = 2; lblFmt.Layout.Column = 1;
    app.ReportFormatDropdown = uidropdown(gg, ...
        'Items',     {'PDF', 'HTML', 'JSON'}, ...
        'ItemsData', {'pdf', 'html', 'json'}, ...
        'Value',     'pdf');
    app.ReportFormatDropdown.Layout.Row = 2; app.ReportFormatDropdown.Layout.Column = 2;

    lblSec = uilabel(gg, 'Text', Labels.get('reports_label_sections'), ...
        'FontColor', Theme.COLOR_LABEL, 'VerticalAlignment', 'center');
    lblSec.Layout.Row = 3; lblSec.Layout.Column = 1;
    app.ReportSectionsField = uieditfield(gg, 'text', ...
        'Value', Labels.get('reports_sections_default', 'all'));
    app.ReportSectionsField.Layout.Row = 3; app.ReportSectionsField.Layout.Column = 2;
    app.ReportSectionsField.Tooltip = Labels.get('reports_placeholder_sections', ...
        'Comma-separated section keys, or "all" for the default section set.');

    app.GenerateReportButton = uibutton(gg, ...
        'Text', [char(9881) ' ' Labels.get('reports_btn_generate', 'Generate Report')], ...
        'ButtonPushedFcn', @(~,~) app.ReportsVm.onGenerateReport());
    app.GenerateReportButton.Layout.Row = 4; app.GenerateReportButton.Layout.Column = [1 2];
    app.styleBtn(app.GenerateReportButton, 'primary');
    app.GenerateReportButton.FontSize = 14;
    app.GenerateReportButton.Tooltip = ...
        'POST /api/reports/generate — polls until ready, downloads, opens.';

    statusHeader = uilabel(gg, ...
        'Text', Labels.get('reports_status_header', 'Last action'), ...
        'FontColor', Theme.COLOR_MUTED, 'FontSize', 11, ...
        'VerticalAlignment', 'center');
    statusHeader.Layout.Row = 5; statusHeader.Layout.Column = [1 2];

    app.ReportStatusArea = uitextarea(gg, 'Editable', 'off');
    app.ReportStatusArea.FontSize = 12;
    app.ReportStatusArea.Layout.Row = 6; app.ReportStatusArea.Layout.Column = [1 2];
    app.ReportStatusArea.Value = strsplit(Labels.get('reports_status_initial', ...
        ['Set report title and format, then click Generate.\n' ...
         'Requires authentication and a completed analysis.']), '\n');

    % ── Library (right) ─────────────────────────────────────────────────────
    libPanel = uipanel(body, ...
        'Title', Labels.get('reports_panel_library', 'Reports library'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    libPanel.Layout.Row = 1; libPanel.Layout.Column = 2;
    libPanel.BackgroundColor = Theme.COLOR_CARD;

    lg = uigridlayout(libPanel, [3 1]);
    lg.RowHeight = {32, '1x', 'fit'};
    lg.ColumnWidth = {'1x'};
    lg.Padding = [12 10 12 10]; lg.RowSpacing = 8;
    lg.BackgroundColor = Theme.COLOR_CARD;

    % Toolbar: search + open + refresh
    tb = uigridlayout(lg, [1 3]);
    tb.Layout.Row = 1; tb.Layout.Column = 1;
    tb.ColumnWidth = {'1x', 110, 40};
    tb.Padding = [0 0 0 0]; tb.ColumnSpacing = 8;
    tb.BackgroundColor = Theme.COLOR_CARD;

    app.ReportsSearchField = uieditfield(tb, 'text', ...
        'Placeholder', Labels.get('reports_search_placeholder', ...
            'Filter by title or format…'), ...
        'ValueChangedFcn', @(src,~) app.ReportsVm.onSearchChanged(src.Value));
    app.ReportsSearchField.Layout.Row = 1; app.ReportsSearchField.Layout.Column = 1;

    openBtn = uibutton(tb, ...
        'Text', [char(9654) ' ' Labels.get('reports_btn_open', 'Open')], ...
        'ButtonPushedFcn', @(~,~) app.ReportsVm.onOpenReport());
    openBtn.Layout.Row = 1; openBtn.Layout.Column = 2;
    app.styleBtn(openBtn, 'primary');
    openBtn.Tooltip = 'Stream the selected report and open it in the OS default viewer.';
    app.OpenReportButton = openBtn;

    app.ReportsRefreshBtn = uibutton(tb, ...
        'Text', char(8634), ...   % ⟲ refresh glyph
        'ButtonPushedFcn', @(~,~) app.ReportsVm.onRefreshList());
    app.ReportsRefreshBtn.Layout.Row = 1; app.ReportsRefreshBtn.Layout.Column = 3;
    app.styleBtn(app.ReportsRefreshBtn, 'ghost');
    app.ReportsRefreshBtn.Tooltip = 'Refresh from GET /api/reports';

    % Table
    app.ReportsTable = uitable(lg, ...
        'ColumnName',    Labels.cols('reports_table_cols', ...
            {'Format', 'Title', 'Created', 'Status'}), ...
        'ColumnWidth',   {70, '1x', 160, 90}, ...
        'RowName',       {}, ...
        'SelectionType', 'row', ...
        'Multiselect',   'off', ...
        'CellSelectionCallback', @(src,evt) app.ReportsVm.onTableSelection(evt));
    app.ReportsTable.Layout.Row = 2; app.ReportsTable.Layout.Column = 1;
    app.styleTable(app.ReportsTable);

    % Selected detail
    app.ReportsDetailLabel = uilabel(lg, ...
        'Text', Labels.get('reports_detail_empty', ...
            'Pick a row to see its sections, status, and id.'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on');
    app.ReportsDetailLabel.Layout.Row = 3; app.ReportsDetailLabel.Layout.Column = 1;

    % Legacy: GeneratedReportList is no longer rendered, but stale code
    % paths might dereference it. Keep at [] so VM lookup paths
    % (currentReportId / loadReportsList) short-circuit safely via their
    % isvalid / try-catch guards.
    app.GeneratedReportList = [];

    % ── Row 3 — Distribution ────────────────────────────────────────────────
    actionPanel = uipanel(g, ...
        'Title', Labels.get('reports_panel_distribute', 'Distribution'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    actionPanel.Layout.Row = 3; actionPanel.Layout.Column = 1;
    actionPanel.BackgroundColor = Theme.COLOR_CARD;

    ag = uigridlayout(actionPanel, [1 4]);
    ag.RowHeight = {34};
    ag.ColumnWidth = {'1x', 130, 130, 110};
    ag.Padding = [14 8 14 8]; ag.ColumnSpacing = 10;
    ag.BackgroundColor = Theme.COLOR_CARD;

    desc = uilabel(ag, ...
        'Text', Labels.get('reports_distribute_desc', ...
            'Distribute the selected report via the channels below.'), ...
        'FontSize', 13, 'FontColor', Theme.COLOR_LABEL, ...
        'VerticalAlignment', 'center', 'WordWrap', 'on');
    desc.Layout.Row = 1; desc.Layout.Column = 1;

    btnPdf = uibutton(ag, ...
        'Text', [char(8595) ' ' Labels.get('reports_btn_download_pdf', 'Download')], ...
        'ButtonPushedFcn', @(~,~) app.ReportsVm.onDownloadPdf());
    btnPdf.Layout.Row = 1; btnPdf.Layout.Column = 2;
    app.styleBtn(btnPdf, 'secondary'); btnPdf.FontSize = 14;
    btnPdf.Tooltip = 'Stream the selected report and open it locally.';

    btnEmail = uibutton(ag, ...
        'Text', [char(9993) ' ' Labels.get('reports_btn_share_email', 'Email')], ...
        'ButtonPushedFcn', @(~,~) app.ReportsVm.onShareEmail());
    btnEmail.Layout.Row = 1; btnEmail.Layout.Column = 3;
    app.styleBtn(btnEmail, 'secondary'); btnEmail.FontSize = 14;
    btnEmail.Tooltip = 'POST /api/reports/{id}/share with a recipient address.';

    btnPrint = uibutton(ag, ...
        'Text', [char(9113) ' ' Labels.get('reports_btn_print', 'Print')], ...
        'ButtonPushedFcn', @(~,~) app.ReportsVm.onPrintReport());
    btnPrint.Layout.Row = 1; btnPrint.Layout.Column = 4;
    app.styleBtn(btnPrint, 'ghost'); btnPrint.FontSize = 14;
    btnPrint.Tooltip = 'Open in OS default viewer (use Cmd-P / Ctrl-P from there).';

    % ── Row 4 — Workflow ────────────────────────────────────────────────────
    bottom = uipanel(g, ...
        'Title', Labels.get('reports_panel_workflow', 'Workflow'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    bottom.Layout.Row = 4; bottom.Layout.Column = 1;
    bottom.BackgroundColor = Theme.COLOR_ACCENT_BG;

    bg = uigridlayout(bottom, [1 3]);
    bg.RowHeight = {34};
    bg.ColumnWidth = {'1x', 170, 170};
    bg.Padding = [14 8 14 8]; bg.ColumnSpacing = 10;
    bg.BackgroundColor = Theme.COLOR_ACCENT_BG;

    flowDesc = uilabel(bg, ...
        'Text', Labels.get('reports_action_msg', ...
            'Generate, preview, and distribute your analysis report — or restart the pipeline.'), ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'VerticalAlignment', 'center', 'WordWrap', 'on');
    flowDesc.Layout.Row = 1; flowDesc.Layout.Column = 1;

    btnDA = uibutton(bg, ...
        'Text', [char(9651) ' Detailed Analysis'], ...
        'ButtonPushedFcn', @(~,~) app.onSelectSection('Detailed Analysis'));
    btnDA.Layout.Row = 1; btnDA.Layout.Column = 2;
    app.styleBtn(btnDA, 'ghost');

    btnRestart = uibutton(bg, ...
        'Text', Labels.get('reports_btn_restart', 'Restart Pipeline'), ...
        'ButtonPushedFcn', @(~,~) restartPipelineSafely(app));
    btnRestart.Layout.Row = 1; btnRestart.Layout.Column = 3;
    app.styleBtn(btnRestart, 'primary');
    btnRestart.Tooltip = ['Reset selectedCircuitId / selectedJobId / predictionId ' ...
                          'and return to the Welcome screen.'];

    Logger.info('ReportsScreen', 'Reports tab UI built successfully');
end

% ── Local helpers ───────────────────────────────────────────────────────────

function valueLabel = kpiCard(parent, title, initialValue)
    % KPI card: small grey title + large primary value. Returns the
    % value uilabel handle so the VM can update its Text.
    panel = uipanel(parent, 'Title', '', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
        'BackgroundColor', Theme.COLOR_CARD);
    pg = uigridlayout(panel, [2 1]);
    pg.RowHeight = {16, '1x'};
    pg.ColumnWidth = {'1x'};
    pg.Padding = [12 8 12 8]; pg.RowSpacing = 4;
    pg.BackgroundColor = Theme.COLOR_CARD;
    uilabel(pg, 'Text', char(title), ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'VerticalAlignment', 'center');
    valueLabel = uilabel(pg, 'Text', char(initialValue), ...
        'FontSize', 22, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING, ...
        'VerticalAlignment', 'center');
end

function restartPipelineSafely(app)
    % Lazy-init SettingsVm. NavigationManager.autoLoadScreen would
    % create it on Settings nav, but if the operator hits Restart on
    % the Reports screen *before* visiting Settings, app.SettingsVm is
    % [] and the original `app.SettingsVm.onRestartPipeline()` direct
    % callback throws "Dot indexing is not supported for variables of
    % this type." This guard creates the VM on demand.
    if isempty(app.SettingsVm)
        app.SettingsVm = SettingsViewModel(app);
    end
    app.SettingsVm.onRestartPipeline();
end
