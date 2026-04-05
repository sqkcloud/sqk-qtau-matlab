% CircuitsScreen  Populates the Circuits section panel.
%
%   Layout:
%     Row 1 (flex):  Circuits table — paginated list of project circuits.
%     Row 2 (48px):  Pagination bar — Prev / Page label / Next + Upload button.
%
%   All visible strings come from resources/labels.properties via Labels.
function CircuitsScreen(app)
    Logger.info('CircuitsScreen', 'Building Circuits tab UI');
    t = app.createSectionPage('Circuits');

    g = uigridlayout(t, [2 1]);
    g.RowHeight     = {'1x', 48};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 10;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Circuits table (full width) ───────────────────────────────────────
    tablePanel = uipanel(g, 'Title', Labels.get('circuits_panel_table', 'Project Circuits'));
    tablePanel.Layout.Row = 1; tablePanel.Layout.Column = 1;
    tablePanel.BackgroundColor = [1 1 1];

    tg = uigridlayout(tablePanel, [1 1]);
    tg.Padding = [10 8 10 8]; tg.BackgroundColor = [1 1 1];

    app.CircuitsTable = uitable(tg, ...
        'ColumnName', { ...
            Labels.get('circuits_col_id',       'Circuit ID'), ...
            Labels.get('circuits_col_name',     'Circuit Name'), ...
            Labels.get('circuits_col_format',   'Format'), ...
            Labels.get('circuits_col_version',  'OpenQASM'), ...
            Labels.get('circuits_col_category', 'Category'), ...
            Labels.get('circuits_col_qubits',   'Qubits'), ...
            Labels.get('circuits_col_depth',    'Depth'), ...
            Labels.get('circuits_col_created',  'Created')}, ...
        'ColumnWidth', {'auto', 'auto', 'auto', 'auto', 'auto', 'auto', 'auto', 'auto'}, ...
        'RowName', {});
    app.CircuitsTable.Layout.Row = 1; app.CircuitsTable.Layout.Column = 1;
    app.CircuitsTable.FontSize = 12;
    app.CircuitsTable.ColumnSortable = true;

    % ── Pagination + Upload bar ───────────────────────────────────────────
    barPanel = uipanel(g, 'Title', '');
    barPanel.Layout.Row = 2; barPanel.Layout.Column = 1;
    barPanel.BackgroundColor = [0.94 0.97 1.00];
    barPanel.BorderType = 'none';

    bg = uigridlayout(barPanel, [1 5]);
    bg.ColumnWidth = {'1x', 80, 90, 80, 140};
    bg.Padding = [10 4 10 4]; bg.ColumnSpacing = 8;
    bg.BackgroundColor = [0.94 0.97 1.00];

    % Spacer
    spacer = uilabel(bg, 'Text', '');
    spacer.Layout.Row = 1; spacer.Layout.Column = 1;

    % Prev button
    app.CircuitsPrevBtn = uibutton(bg, 'Text', ...
        [char(9664) ' ' Labels.get('circuits_btn_prev', 'Prev')], ...
        'ButtonPushedFcn', @(~,~)app.CircuitsVm.onPrevPage());
    app.CircuitsPrevBtn.Layout.Row = 1; app.CircuitsPrevBtn.Layout.Column = 2;
    app.styleBtn(app.CircuitsPrevBtn, 'ghost');
    app.CircuitsPrevBtn.Enable = false;

    % Page label
    app.CircuitsPageLabel = uilabel(bg, 'Text', 'Page 1');
    app.CircuitsPageLabel.Layout.Row = 1; app.CircuitsPageLabel.Layout.Column = 3;
    app.CircuitsPageLabel.HorizontalAlignment = 'center';
    app.CircuitsPageLabel.FontSize = 13; app.CircuitsPageLabel.FontWeight = 'bold';
    app.CircuitsPageLabel.FontColor = [0.20 0.30 0.55];

    % Next button
    app.CircuitsNextBtn = uibutton(bg, 'Text', ...
        [Labels.get('circuits_btn_next', 'Next') ' ' char(9654)], ...
        'ButtonPushedFcn', @(~,~)app.CircuitsVm.onNextPage());
    app.CircuitsNextBtn.Layout.Row = 1; app.CircuitsNextBtn.Layout.Column = 4;
    app.styleBtn(app.CircuitsNextBtn, 'ghost');

    % Upload button with icon
    app.CircuitsUploadBtn = uibutton(bg, 'Text', ...
        [char(8593) ' ' Labels.get('circuits_btn_upload', 'Upload')], ...
        'ButtonPushedFcn', @(~,~)app.CircuitsVm.onGoToUpload());
    app.CircuitsUploadBtn.Layout.Row = 1; app.CircuitsUploadBtn.Layout.Column = 5;
    app.styleBtn(app.CircuitsUploadBtn, 'primary');
    app.CircuitsUploadBtn.FontSize = 14;
    app.CircuitsUploadBtn.Tooltip = 'Navigate to Upload screen';

    Logger.info('CircuitsScreen', 'Circuits tab UI built successfully');
end
