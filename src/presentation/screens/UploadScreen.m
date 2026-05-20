% UploadScreen  Populates the Upload section panel.
%
%   Layout:
%     Row 1 (0px):   Active Project indicator — hidden (state kept internally).
%     Row 2 (flex):  Circuit Upload & Manager — file picker + editable preview.
%     Row 3 (200px): Format & Metadata form (left) | Circuit Statistics (right).
%     Row 4 (180px): Project Circuits table — circuits already in this project.
%     Row 5 (72px):  Action bar — Next: Analysis / Back: Welcome.
%
%   All visible strings come from resources/labels.properties via Labels.
function UploadScreen(app)
    Logger.info('UploadScreen', 'Building Upload tab UI');
    t = app.createSectionPage('Upload');

    g = uigridlayout(t, [5 2]);
    g.RowHeight     = {0, '1x', 200, 0, 72};
    g.ColumnWidth   = {'1.15x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Active Project indicator (full width) — hidden from UI ─────────
    projPanel = uipanel(g, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER);
    projPanel.Layout.Row = 1; projPanel.Layout.Column = [1 2];
    projPanel.BackgroundColor = Theme.COLOR_CARD;
    projPanel.Visible = 'off';

    pg = uigridlayout(projPanel, [1 2]);
    pg.ColumnWidth = {120, '1x'};
    pg.Padding = [14 4 14 4]; pg.ColumnSpacing = 8;
    pg.BackgroundColor = Theme.COLOR_CARD;

    lbl = uilabel(pg, 'Text', Labels.get('upload_label_active_project'));
    lbl.FontSize = 13; lbl.FontWeight = 'bold';
    lbl.FontColor = Theme.COLOR_PRIMARY;
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;

    projName = app.State.currentProjectName;
    if strlength(projName) == 0
        projName = Labels.get('upload_label_no_project');
    end
    app.UploadActiveProjectLabel = uilabel(pg, 'Text', char(projName));
    app.UploadActiveProjectLabel.FontSize = 13;
    app.UploadActiveProjectLabel.FontColor = Theme.COLOR_HEADING;
    app.UploadActiveProjectLabel.Layout.Row = 1;
    app.UploadActiveProjectLabel.Layout.Column = 2;

    % ── Circuit upload + preview (full width) ─────────────────────────────
    dropPanel = uipanel(g, 'Title', Labels.get('upload_panel_upload_manager'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    dropPanel.Layout.Row = 2; dropPanel.Layout.Column = [1 2]; dropPanel.BackgroundColor = Theme.COLOR_CARD;

    dg = uigridlayout(dropPanel, [4 4]);
    dg.RowHeight   = {26, 34, 4, '1x'};
    dg.ColumnWidth = {110, '1x', 100, 110};
    dg.Padding = [16 12 16 12]; dg.RowSpacing = 0; dg.BackgroundColor = Theme.COLOR_CARD;

    info = uilabel(dg, 'Text', Labels.get('upload_hero_title'));
    info.FontSize = 14; info.FontWeight = 'bold';
    info.Layout.Row = 1; info.Layout.Column = [1 4]; info.WordWrap = 'on';

    lbl = uilabel(dg, 'Text', Labels.get('upload_label_file'));
    lbl.FontColor = Theme.COLOR_LABEL;
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.UploadFileField = uieditfield(dg, 'text', 'Value', '');
    app.UploadFileField.Layout.Row = 2; app.UploadFileField.Layout.Column = 2;
    app.UploadFileField.Placeholder = Labels.get('upload_placeholder_file');

    app.BrowseButton = uibutton(dg, 'Text', [char(9776) ' ' Labels.get('upload_btn_browse')], ...
        'ButtonPushedFcn', @(~,~)app.UploadVm.onBrowseCircuit());
    app.BrowseButton.Layout.Row = 2; app.BrowseButton.Layout.Column = 3;
    app.styleBtn(app.BrowseButton, 'ghost');
    app.BrowseButton.FontSize = 14;

    app.UploadButton = uibutton(dg, 'Text', [char(10004) ' ' Labels.get('upload_btn_upload')], ...
        'ButtonPushedFcn', @(~,~)app.UploadVm.onUploadCircuit());
    app.UploadButton.Layout.Row = 2; app.UploadButton.Layout.Column = 4;
    app.styleBtn(app.UploadButton, 'primary');
    app.UploadButton.FontSize = 14;
    app.UploadButton.Tooltip = 'Upload the selected QASM file';

    app.CircuitPreviewArea = uitextarea(dg, 'Editable', 'on');
    app.CircuitPreviewArea.Layout.Row = 4; app.CircuitPreviewArea.Layout.Column = [1 4];
    app.CircuitPreviewArea.FontName = 'Courier New'; app.CircuitPreviewArea.FontSize = 13;
    app.CircuitPreviewArea.BackgroundColor = Theme.COLOR_CARD;
    app.CircuitPreviewArea.FontColor = Theme.COLOR_HEADING;
    app.CircuitPreviewArea.Value = { ...
        'OPENQASM 2.0;', 'include "qelib1.inc";', '', ...
        'qreg q[27];', 'creg c[27];', '', ...
        '// Load a circuit file to see its content here.', ...
        'measure q -> c;'};

    % ── Format and Metadata (left) ────────────────────────────────────────
    metaPanel = uipanel(g, 'Title', Labels.get('upload_panel_format_meta'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    metaPanel.Layout.Row = 3; metaPanel.Layout.Column = 1; metaPanel.BackgroundColor = Theme.COLOR_CARD;

    mg = uigridlayout(metaPanel, [3 4]);
    mg.RowHeight   = {28, 28, 28};
    mg.ColumnWidth = {100, '1x', 80, '1x'};
    mg.Padding = [16 12 16 12]; mg.RowSpacing = 6; mg.ColumnSpacing = 8;
    mg.BackgroundColor = Theme.COLOR_CARD;

    % Row 1 — Input Format (left) + Category (right)
    lbl = uilabel(mg, 'Text', Labels.get('upload_label_format'));
    lbl.FontColor = Theme.COLOR_LABEL;
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.UploadFormatDropdown = uidropdown(mg, ...
        'Items', {'OpenQASM 2.0','OpenQASM 3','Qiskit JSON','MATLAB struct'}, ...
        'ItemsData', {'qasm2','qasm3','json','matlab'}, ...
        'Value', 'qasm2');
    app.UploadFormatDropdown.Layout.Row = 1; app.UploadFormatDropdown.Layout.Column = 2;

    lbl = uilabel(mg, 'Text', Labels.get('upload_label_category'));
    lbl.FontColor = Theme.COLOR_LABEL;
    lbl.Layout.Row = 1; lbl.Layout.Column = 3;
    app.CircuitCategoryDropdown = uidropdown(mg, ...
        'Items', {'Oracle','Fourier','Sampling','Optimization','Search','Simulation','Other'}, ...
        'Value', 'Oracle');
    app.CircuitCategoryDropdown.Layout.Row = 1; app.CircuitCategoryDropdown.Layout.Column = 4;

    % Row 2 — Circuit Name (full width)
    lbl = uilabel(mg, 'Text', Labels.get('upload_label_name'));
    lbl.FontColor = Theme.COLOR_LABEL;
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.CircuitNameField = uieditfield(mg, 'text', 'Value', '');
    app.CircuitNameField.Layout.Row = 2; app.CircuitNameField.Layout.Column = [2 4];
    app.CircuitNameField.Placeholder = Labels.get('upload_placeholder_name');

    % Row 3 — Metadata label
    lbl = uilabel(mg, 'Text', Labels.get('upload_label_metadata'));
    lbl.FontColor = Theme.COLOR_LABEL;
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    app.CircuitMetadataArea = uieditfield(mg, 'text', 'Value', 'QTAUBench');
    app.CircuitMetadataArea.FontSize = 12;
    app.CircuitMetadataArea.Layout.Row = 3; app.CircuitMetadataArea.Layout.Column = [2 4];

    % ── Circuit Statistics (right) ────────────────────────────────────────
    statsPanel = uipanel(g, 'Title', Labels.get('upload_panel_stats'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    statsPanel.Layout.Row = 3; statsPanel.Layout.Column = 2; statsPanel.BackgroundColor = Theme.COLOR_CARD;

    spg = uigridlayout(statsPanel, [1 1]);
    spg.Padding = [4 4 4 4]; spg.BackgroundColor = Theme.COLOR_CARD;
    app.CircuitStatsArea = uihtml(spg);
    app.CircuitStatsArea.HTMLSource = CircuitDiagram.wrapHtml(Labels.get('upload_stats_initial'));

    % ── Project Circuits table (full width) — hidden ─────────────────────
    circPanel = uipanel(g, 'Title', Labels.get('upload_panel_project_circuits'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    circPanel.Layout.Row = 4; circPanel.Layout.Column = [1 2];
    circPanel.BackgroundColor = Theme.COLOR_CARD;
    circPanel.Visible = 'off';

    cg = uigridlayout(circPanel, [1 2]);
    cg.ColumnWidth = {'1x', 100};
    cg.Padding = [10 6 10 6]; cg.ColumnSpacing = 8;
    cg.BackgroundColor = Theme.COLOR_CARD;

    app.UploadCircuitsTable = uitable(cg, ...
        'ColumnName', {'Circuit ID', 'Name', 'Format', 'Qubits', 'Depth', 'Valid', 'Created'}, ...
        'ColumnWidth', {180, 160, 70, 60, 60, 50, 140}, ...
        'RowName', {});
    app.UploadCircuitsTable.Layout.Row = 1; app.UploadCircuitsTable.Layout.Column = 1;
    app.UploadCircuitsTable.FontSize = 11;

    btnGrid = uigridlayout(cg, [3 1]);
    btnGrid.RowHeight = {30, 30, '1x'};
    btnGrid.Padding = [0 0 0 0]; btnGrid.RowSpacing = 6;
    btnGrid.BackgroundColor = Theme.COLOR_CARD;

    app.UploadRefreshCircuitsBtn = uibutton(btnGrid, 'Text', Labels.get('upload_btn_refresh_circuits'), ...
        'ButtonPushedFcn', @(~,~)app.UploadVm.onRefreshCircuits());
    app.UploadRefreshCircuitsBtn.Layout.Row = 1; app.UploadRefreshCircuitsBtn.Layout.Column = 1;
    app.styleBtn(app.UploadRefreshCircuitsBtn, 'ghost');

    app.UploadDeleteCircuitBtn = uibutton(btnGrid, 'Text', Labels.get('upload_btn_delete_circuit'), ...
        'ButtonPushedFcn', @(~,~)app.UploadVm.onDeleteCircuit());
    app.UploadDeleteCircuitBtn.Layout.Row = 2; app.UploadDeleteCircuitBtn.Layout.Column = 1;
    app.styleBtn(app.UploadDeleteCircuitBtn, 'ghost');

    % ── Action bar ────────────────────────────────────────────────────────
    actionPanel = uipanel(g, 'Title', Labels.get('upload_panel_action'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    actionPanel.Layout.Row = 5; actionPanel.Layout.Column = [1 2];
    actionPanel.BackgroundColor = Theme.COLOR_CARD;

    ag = uigridlayout(actionPanel, [1 3]); ag.ColumnWidth = {'1x',170,150};
    ag.Padding = [14 8 14 8]; ag.BackgroundColor = Theme.COLOR_CARD;
    msg = uilabel(ag, 'Text', Labels.get('upload_action_msg'));
    msg.FontSize = 13; msg.FontWeight = 'bold'; msg.Layout.Row = 1; msg.Layout.Column = 1;
    msg.VerticalAlignment = 'center'; msg.WordWrap = 'on';
    tmp = uibutton(ag, 'Text', [char(8981) ' ' Labels.get('upload_btn_next')], ...
        'ButtonPushedFcn', @(~,~)app.UploadVm.onGoToAnalyze());
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'primary');
    tmp = uibutton(ag, 'Text', [char(8962) ' ' Labels.get('upload_btn_back')], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Welcome'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');

    Logger.info('UploadScreen', 'Upload tab UI built successfully');
end
