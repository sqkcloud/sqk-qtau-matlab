% UploadTab  Populates the Upload section panel.
%
%   Layout:
%     Row 1 (flex):  Circuit Upload & Manager — file picker + editable preview.
%     Row 2 (fixed): Format & Metadata form (left) | Circuit Statistics (right).
%     Row 3 (fixed): Action bar — Next: Analysis / Back: Welcome.
%
%   All visible strings come from resources/labels.properties via Labels.
function UploadScreen(app)
    Logger.info('UploadScreen', 'Building Upload tab UI');
    t = app.createSectionPage('Upload');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {'1x', 200, 72};
    g.ColumnWidth   = {'1.15x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Circuit upload + preview (full width) ─────────────────────────────────
    dropPanel = uipanel(g, 'Title', Labels.get('upload_panel_upload_manager'));
    dropPanel.Layout.Row = 1; dropPanel.Layout.Column = [1 3]; dropPanel.BackgroundColor = [1 1 1];

    dg = uigridlayout(dropPanel, [3 4]);
    dg.RowHeight   = {26, 34, '1x'};
    dg.ColumnWidth = {110, '1x', 100, 110};
    dg.Padding = [16 12 16 12]; dg.RowSpacing = 8; dg.BackgroundColor = [1 1 1];

    info = uilabel(dg, 'Text', Labels.get('upload_hero_title'));
    info.FontSize = 14; info.FontWeight = 'bold';
    info.Layout.Row = 1; info.Layout.Column = [1 4]; info.WordWrap = 'on';

    lbl = uilabel(dg, 'Text', Labels.get('upload_label_file'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.UploadFileField = uieditfield(dg, 'text', 'Value', '');
    app.UploadFileField.Layout.Row = 2; app.UploadFileField.Layout.Column = 2;
    app.UploadFileField.Placeholder = Labels.get('upload_placeholder_file');

    app.BrowseButton = uibutton(dg, 'Text', [char(9776) ' ' Labels.get('upload_btn_browse')], ...
        'ButtonPushedFcn', @(~,~)app.UploadVm.onBrowseCircuit());
    app.BrowseButton.Layout.Row = 2; app.BrowseButton.Layout.Column = 3;
    app.styleBtn(app.BrowseButton, 'ghost');
    app.BrowseButton.FontSize = 14;

    app.UploadButton = uibutton(dg, 'Text', [char(8593) ' ' Labels.get('upload_btn_upload')], ...
        'ButtonPushedFcn', @(~,~)app.UploadVm.onUploadCircuit());
    app.UploadButton.Layout.Row = 2; app.UploadButton.Layout.Column = 4;
    app.styleBtn(app.UploadButton, 'primary');
    app.UploadButton.FontSize = 14;
    app.UploadButton.Tooltip = 'POST /api/circuits/upload';

    app.CircuitPreviewArea = uitextarea(dg, 'Editable', 'on');
    app.CircuitPreviewArea.Layout.Row = 3; app.CircuitPreviewArea.Layout.Column = [1 4];
    app.CircuitPreviewArea.FontName = 'Courier New'; app.CircuitPreviewArea.FontSize = 13;
    app.CircuitPreviewArea.BackgroundColor = [0.97 0.98 1.00];
    app.CircuitPreviewArea.FontColor = [0.14 0.18 0.26];
    app.CircuitPreviewArea.Value = { ...
        'OPENQASM 2.0;', 'include "qelib1.inc";', '', ...
        'qreg q[27];', 'creg c[27];', '', ...
        '// Load a circuit file to see its content here.', ...
        'measure q -> c;'};

    % ── Column divider ────────────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Format and Metadata (left) ────────────────────────────────────────────
    metaPanel = uipanel(g, 'Title', Labels.get('upload_panel_format_meta'));
    metaPanel.Layout.Row = 2; metaPanel.Layout.Column = 1; metaPanel.BackgroundColor = [1 1 1];

    mg = uigridlayout(metaPanel, [4 4]);
    mg.RowHeight   = {28, 28, 28, '1x'};
    mg.ColumnWidth = {100, '1x', 80, '1x'};
    mg.Padding = [16 12 16 12]; mg.RowSpacing = 6; mg.ColumnSpacing = 8;
    mg.BackgroundColor = [1 1 1];

    % Row 1 — Input Format (left) + Category (right)
    lbl = uilabel(mg, 'Text', Labels.get('upload_label_format'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.UploadFormatDropdown = uidropdown(mg, ...
        'Items', {'OpenQASM 2.0','OpenQASM 3','Qiskit JSON','MATLAB struct'}, ...
        'Value', 'OpenQASM 2.0');
    app.UploadFormatDropdown.Layout.Row = 1; app.UploadFormatDropdown.Layout.Column = 2;

    lbl = uilabel(mg, 'Text', Labels.get('upload_label_category'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 3;
    app.CircuitCategoryDropdown = uidropdown(mg, ...
        'Items', {'Oracle','Fourier','Sampling','Optimization','Search','Simulation','Other'}, ...
        'Value', 'Oracle');
    app.CircuitCategoryDropdown.Layout.Row = 1; app.CircuitCategoryDropdown.Layout.Column = 4;

    % Row 2 — Circuit Name (full width)
    lbl = uilabel(mg, 'Text', Labels.get('upload_label_name'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.CircuitNameField = uieditfield(mg, 'text', 'Value', '');
    app.CircuitNameField.Layout.Row = 2; app.CircuitNameField.Layout.Column = [2 4];
    app.CircuitNameField.Placeholder = Labels.get('upload_placeholder_name');

    % Row 3 — Metadata label
    lbl = uilabel(mg, 'Text', Labels.get('upload_label_metadata'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    app.CircuitMetadataArea = uitextarea(mg, 'Value', {'Source: QASMBench', 'Owner: '});
    app.CircuitMetadataArea.FontSize = 12;
    app.CircuitMetadataArea.Layout.Row = [3 4]; app.CircuitMetadataArea.Layout.Column = [2 4];

    % ── Circuit Statistics (right) ────────────────────────────────────────────
    statsPanel = uipanel(g, 'Title', Labels.get('upload_panel_stats'));
    statsPanel.Layout.Row = 2; statsPanel.Layout.Column = 3; statsPanel.BackgroundColor = [1 1 1];

    pg = uigridlayout(statsPanel, [1 1]);
    pg.Padding = [12 10 12 10]; pg.BackgroundColor = [1 1 1];
    app.CircuitStatsArea = uitextarea(pg, 'Editable', 'off'); app.CircuitStatsArea.FontSize = 12;
    app.CircuitStatsArea.Value = {Labels.get('upload_stats_initial')};

    % ── Action bar ────────────────────────────────────────────────────────────
    actionPanel = uipanel(g, 'Title', Labels.get('upload_panel_action'));
    actionPanel.Layout.Row = 3; actionPanel.Layout.Column = [1 3];
    actionPanel.BackgroundColor = [0.94 0.97 1.00];

    ag = uigridlayout(actionPanel, [1 3]); ag.ColumnWidth = {'1x',170,150};
    ag.Padding = [14 8 14 8]; ag.BackgroundColor = [0.94 0.97 1.00];
    msg = uilabel(ag, 'Text', Labels.get('upload_action_msg'));
    msg.FontSize = 13; msg.FontWeight = 'bold'; msg.Layout.Row = 1; msg.Layout.Column = 1;
    msg.VerticalAlignment = 'center'; msg.WordWrap = 'on';
    tmp = uibutton(ag, 'Text', Labels.get('upload_btn_next'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Analysis'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'primary');
    tmp = uibutton(ag, 'Text', Labels.get('upload_btn_back'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Welcome'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');

    Logger.info('UploadScreen', 'Upload tab UI built successfully');
end
