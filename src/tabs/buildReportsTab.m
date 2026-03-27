% buildReportsTab  Populates the Reports section panel.
%
%   Layout (3-column grid, 3 rows):
%     Rows 1-2, Col 1: Report Generator form (title, format, sections, generate).
%     Rows 1-2, Col 2: 6 px resizable divider.
%     Rows 1-2, Col 3: Report Preview — open button + file list.
%     Row 2:          Full-width Distribution Actions bar.
%     Row 3:          Full-width Workflow Complete action bar.
function buildReportsTab(app)
    t = app.createSectionPage('Reports');

    % ── Root grid: 3 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {'1x', 72, 72};
    g.ColumnWidth   = {'1.05x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Column divider (spans rows 1-2) ───────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=[1 2]; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Report Generator form (left panel) ────────────────────────────────────
    genPanel=uipanel(g,'Title','Report Generator');
    genPanel.Layout.Row=1; genPanel.Layout.Column=1; genPanel.BackgroundColor=[1 1 1];

    gg=uigridlayout(genPanel,[5 2]);
    gg.RowHeight={36,36,36,36,'1x'};
    gg.ColumnWidth={160,'1x'};
    gg.Padding=[16 12 16 12];
    gg.RowSpacing=8;
    gg.BackgroundColor=[1 1 1];

    % Report title
    tmp=uilabel(gg,'Text','Project Title'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=1; tmp.Layout.Column=1;
    app.ReportTitleField=uieditfield(gg,'text','Value','BV-27 Quantum Run — March 2026');
    app.ReportTitleField.Layout.Row=1; app.ReportTitleField.Layout.Column=2;

    % Output format selection
    tmp=uilabel(gg,'Text','Report Format'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=2; tmp.Layout.Column=1;
    app.ReportFormatDropdown=uidropdown(gg, ...
        'Items',{'PDF','Word (docx)','HTML','MATLAB Live Script'},'Value','PDF');
    app.ReportFormatDropdown.Layout.Row=2; app.ReportFormatDropdown.Layout.Column=2;

    % Section filter — which analysis sections to include
    tmp=uilabel(gg,'Text','Include sections'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=3; tmp.Layout.Column=1;
    secField=uieditfield(gg,'text','Value','all');
    secField.Layout.Row=3; secField.Layout.Column=2;
    secField.Tooltip='all | analysis,results,plots | results';

    % Generate action
    app.GenerateReportButton=uibutton(gg,'Text','Generate Report', ...
        'ButtonPushedFcn',@(~,~)app.onGenerateReport());
    app.GenerateReportButton.Layout.Row=4; app.GenerateReportButton.Layout.Column=[1 2];
    app.styleBtn(app.GenerateReportButton,'primary');

    % Inline status feedback area
    app.ReportStatusArea=uitextarea(gg,'Editable','off');
    app.ReportStatusArea.FontSize=12;
    app.ReportStatusArea.Layout.Row=5; app.ReportStatusArea.Layout.Column=[1 2];
    app.ReportStatusArea.Value={ ...
        'Storyboard mode: report template available', ...
        'All section inputs have been reviewed', ...
        'Click Generate Report to create the PDF export'};

    % ── Report Preview (right panel) ─────────────────────────────────────────
    previewPanel=uipanel(g,'Title','Report Preview');
    previewPanel.Layout.Row=1; previewPanel.Layout.Column=3; previewPanel.BackgroundColor=[1 1 1];

    pvg=uigridlayout(previewPanel,[2 1]);
    pvg.RowHeight={44,'1x'};
    pvg.Padding=[12 10 12 10];
    pvg.BackgroundColor=[1 1 1];

    % Open the last generated report in the OS default viewer
    app.OpenReportButton=uibutton(pvg,'Text','Open Generated View', ...
        'ButtonPushedFcn',@(~,~)app.onOpenReport());
    app.styleBtn(app.OpenReportButton,'ghost');
    app.OpenReportButton.Tooltip='Open the previously generated report file';

    % List of all generated report files for this project
    app.GeneratedReportList=uilistbox(pvg, ...
        'Items',{'BV-27_March2026.pdf','BV-27_March2026_draft.pdf','BV-26_Feb2026.pdf'}, ...
        'Tooltip','Generated report files');

    % ── Distribution download actions (full width) ────────────────────────────
    actionPanel=uipanel(g,'Title','Distribution Actions');
    actionPanel.Layout.Row=2; actionPanel.Layout.Column=[1 3]; actionPanel.BackgroundColor=[1 1 1];

    ag=uigridlayout(actionPanel,[1 4]);
    ag.RowHeight={36};                          % lock buttons to standard 36 px height
    ag.ColumnWidth={'1x', 150, 150, 100};
    ag.Padding=[14 10 14 10];
    ag.BackgroundColor=[1 1 1];

    desc=uilabel(ag,'Text','Distribute the generated report via the channels below:');
    desc.FontSize=13; desc.FontColor=[0.28 0.36 0.48]; desc.Layout.Row=1; desc.Layout.Column=1; desc.WordWrap='on';
    b=uibutton(ag,'Text','Download PDF'); b.Layout.Row=1; b.Layout.Column=2; app.styleBtn(b,'primary');
    b=uibutton(ag,'Text','Share by Email'); b.Layout.Row=1; b.Layout.Column=3; app.styleBtn(b,'secondary');
    b=uibutton(ag,'Text','Print'); b.Layout.Row=1; b.Layout.Column=4; app.styleBtn(b,'ghost');

    % ── Action bar — end of workflow ──────────────────────────────────────────
    bottom=uipanel(g,'Title','Workflow Complete');
    bottom.Layout.Row=3; bottom.Layout.Column=[1 3];
    bottom.BackgroundColor=[0.94 0.97 1.00];

    bg=uigridlayout(bottom,[1 3]);
    bg.ColumnWidth={'1x',170,170};
    bg.Padding=[14 8 14 8];
    bg.BackgroundColor=[0.94 0.97 1.00];

    desc=uilabel(bg,'Text','Generate, preview, and distribute your analysis report, or restart the pipeline.');
    desc.FontSize=13; desc.FontWeight='bold'; desc.Layout.Row=1; desc.Layout.Column=1;
    desc.VerticalAlignment='center'; desc.WordWrap='on';
    tmp=uibutton(bg,'Text','Back: Detailed Analysis', ...
        'ButtonPushedFcn',@(~,~)app.onSelectSection('Detailed Analysis'));
    tmp.Layout.Row=1; tmp.Layout.Column=2; app.styleBtn(tmp,'ghost');
    tmp=uibutton(bg,'Text','Restart Pipeline', ...
        'ButtonPushedFcn',@(~,~)app.onSelectSection('Welcome'));
    tmp.Layout.Row=1; tmp.Layout.Column=3; app.styleBtn(tmp,'primary');
end
