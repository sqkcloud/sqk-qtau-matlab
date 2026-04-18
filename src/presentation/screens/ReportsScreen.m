% ReportsTab  Populates the Reports section panel.
%
%   Layout:
%     Row 1 ('1x'):    Report Generator form (left) | Report Preview list (right).
%     Row 2 (72 px):   Distribution Actions bar (full width).
%     Row 3 (72 px):   Workflow Complete action bar.
%
%   All visible strings come from resources/labels.properties via Labels.
function ReportsScreen(app)
    Logger.info('ReportsScreen', 'Building Reports tab UI');
    t = app.createSectionPage('Reports');

    g = uigridlayout(t, [3 2]);
    g.RowHeight     = {'1x', 72, 72};
    g.ColumnWidth   = {'1.05x', '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Report Generator (left) ───────────────────────────────────────────────
    genPanel = uipanel(g, 'Title', Labels.get('reports_panel_generator'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    genPanel.Layout.Row = 1; genPanel.Layout.Column = 1; genPanel.BackgroundColor = Theme.COLOR_CARD;

    gg = uigridlayout(genPanel, [5 2]);
    gg.RowHeight = {34, 34, 34, 34, '1x'};
    gg.ColumnWidth = {160,'1x'};
    gg.Padding = [16 12 16 12]; gg.RowSpacing = 8; gg.BackgroundColor = Theme.COLOR_CARD;

    lbl = uilabel(gg, 'Text', Labels.get('reports_label_title'));
    lbl.FontColor = Theme.COLOR_LABEL;
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.ReportTitleField = uieditfield(gg, 'text', 'Value', Labels.get('reports_title_default', 'Quantum Run Report'));
    app.ReportTitleField.Layout.Row = 1; app.ReportTitleField.Layout.Column = 2;

    lbl = uilabel(gg, 'Text', Labels.get('reports_label_format'));
    lbl.FontColor = Theme.COLOR_LABEL;
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    fmtItems   = Labels.items('reports_format_items', {'PDF','Word (docx)','HTML','MATLAB Live Script'});
    fmtDefault = Labels.get('reports_format_default', 'PDF');
    app.ReportFormatDropdown = uidropdown(gg, 'Items', fmtItems, 'Value', fmtDefault);
    app.ReportFormatDropdown.Layout.Row = 2; app.ReportFormatDropdown.Layout.Column = 2;

    lbl = uilabel(gg, 'Text', Labels.get('reports_label_sections'));
    lbl.FontColor = Theme.COLOR_LABEL;
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    app.ReportSectionsField = uieditfield(gg, 'text', 'Value', Labels.get('reports_sections_default', 'all'));
    app.ReportSectionsField.Layout.Row = 3; app.ReportSectionsField.Layout.Column = 2;
    app.ReportSectionsField.Tooltip = Labels.get('reports_placeholder_sections');

    app.GenerateReportButton = uibutton(gg, 'Text', [char(9881) ' ' Labels.get('reports_btn_generate')], ...
        'ButtonPushedFcn', @(~,~)app.ReportsVm.onGenerateReport());
    app.GenerateReportButton.Layout.Row = 4; app.GenerateReportButton.Layout.Column = [1 2];
    app.styleBtn(app.GenerateReportButton, 'primary');
    app.GenerateReportButton.FontSize = 14;
    app.GenerateReportButton.Tooltip = 'POST /api/reports/generate (or /api/projects/{id}/reports)';

    app.ReportStatusArea = uitextarea(gg, 'Editable', 'off');
    app.ReportStatusArea.FontSize = 12;
    app.ReportStatusArea.Layout.Row = 5; app.ReportStatusArea.Layout.Column = [1 2];
    app.ReportStatusArea.Value = strsplit(Labels.get('reports_status_initial'), '\n');

    % ── Report Preview (right) ────────────────────────────────────────────────
    previewPanel = uipanel(g, 'Title', Labels.get('reports_panel_preview'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    previewPanel.Layout.Row = 1; previewPanel.Layout.Column = 2; previewPanel.BackgroundColor = Theme.COLOR_CARD;

    pvg = uigridlayout(previewPanel, [2 1]);
    pvg.RowHeight = {34,'1x'}; pvg.Padding = [12 10 12 10]; pvg.BackgroundColor = Theme.COLOR_CARD;

    app.OpenReportButton = uibutton(pvg, 'Text', [char(9654) ' ' Labels.get('reports_btn_open')], ...
        'ButtonPushedFcn', @(~,~)app.ReportsVm.onOpenReport());
    app.styleBtn(app.OpenReportButton, 'ghost');
    app.OpenReportButton.FontSize = 14;
    app.OpenReportButton.Tooltip = 'GET /api/reports/{id}/download';

    app.GeneratedReportList = uilistbox(pvg, 'Items', {}, ...
        'Tooltip', 'Generated report files (newest first)');

    % ── Distribution actions (full width) ────────────────────────────────────
    actionPanel = uipanel(g, 'Title', Labels.get('reports_panel_distribute'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    actionPanel.Layout.Row = 2; actionPanel.Layout.Column = [1 2]; actionPanel.BackgroundColor = Theme.COLOR_CARD;

    ag = uigridlayout(actionPanel, [1 4]);
    ag.RowHeight = {34}; ag.ColumnWidth = {'1x', 110, 110, 100};
    ag.Padding = [14 10 14 10]; ag.BackgroundColor = Theme.COLOR_CARD;
    desc = uilabel(ag, 'Text', Labels.get('reports_distribute_desc'));
    desc.FontSize = 13; desc.FontColor = Theme.COLOR_LABEL;
    desc.Layout.Row = 1; desc.Layout.Column = 1; desc.WordWrap = 'on';
    b = uibutton(ag, 'Text', [char(8595) ' ' Labels.get('reports_btn_download_pdf')]);
    b.Layout.Row = 1; b.Layout.Column = 2; app.styleBtn(b, 'primary');
    b.FontSize = 14;
    b = uibutton(ag, 'Text', [char(9993) ' ' Labels.get('reports_btn_share_email')]);
    b.Layout.Row = 1; b.Layout.Column = 3; app.styleBtn(b, 'secondary');
    b.FontSize = 14;
    b = uibutton(ag, 'Text', [char(9113) ' ' Labels.get('reports_btn_print')]);
    b.Layout.Row = 1; b.Layout.Column = 4; app.styleBtn(b, 'ghost');
    b.FontSize = 14;

    % ── Workflow Complete action bar ───────────────────────────────────────────
    bottom = uipanel(g, 'Title', Labels.get('reports_panel_workflow'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    bottom.Layout.Row = 3; bottom.Layout.Column = [1 2];
    bottom.BackgroundColor = Theme.COLOR_ACCENT_BG;

    bg = uigridlayout(bottom, [1 3]);
    bg.ColumnWidth = {'1x', 170, 170};
    bg.Padding = [14 8 14 8]; bg.BackgroundColor = Theme.COLOR_ACCENT_BG;
    desc = uilabel(bg, 'Text', Labels.get('reports_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(bg, 'Text', [char(9651) ' Detailed Analysis'], ...  % Detailed Analysis nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Detailed Analysis'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'ghost');
    tmp = uibutton(bg, 'Text', Labels.get('reports_btn_restart'), ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.onRestartPipeline());
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'primary');

    Logger.info('ReportsScreen', 'Reports tab UI built successfully');
end
