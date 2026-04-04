% PredictionTab  Populates the Prediction section panel.
%
%   Layout:
%     Row 1 (44 px):   Full-width Run Prediction button.
%     Row 2 ('1x'):    Prediction Summary table (left) | Distribution & Error Budget (right).
%     Row 3 (72 px):   Action bar — Submit Job / Back: Benchmark / Save Prediction.
%
%   All visible strings come from resources/labels.properties via Labels.
function PredictionScreen(app)
    Logger.info('PredictionScreen', 'Building Prediction tab UI');
    t = app.createSectionPage('Prediction');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {34, '1x', 72};
    g.ColumnWidth   = {'1x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    toolbar = uigridlayout(g, [1 2]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {'1x', 110};
    toolbar.Padding = [0 0 0 0]; toolbar.BackgroundColor = [0.96 0.97 0.99];

    app.PredictButton = uibutton(toolbar, 'Text', [char(9881) ' ' Labels.get('prediction_btn_run')], ...
        'ButtonPushedFcn', @(~,~)app.PredictionVm.onRunPrediction());
    app.PredictButton.Layout.Row = 1; app.PredictButton.Layout.Column = 2;
    app.styleBtn(app.PredictButton, 'primary');
    app.PredictButton.FontSize = 14;
    app.PredictButton.Tooltip = 'POST /api/predict with current circuit + backend + benchmark config';

    % ── Column divider ────────────────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = 2; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Prediction Summary table (left) ──────────────────────────────────────
    metricPanel = uipanel(g, 'Title', Labels.get('prediction_panel_summary'));
    metricPanel.Layout.Row = 2; metricPanel.Layout.Column = 1; metricPanel.BackgroundColor = [1 1 1];

    mpg = uigridlayout(metricPanel, [1 1]);
    mpg.Padding = [12 10 12 10]; mpg.BackgroundColor = [1 1 1];
    app.PredictionTable = uitable(mpg);
    app.PredictionTable.ColumnName = Labels.cols('prediction_table_cols', {'Metric','Value'});
    app.PredictionTable.Data = { ...
        Labels.get('prediction_table_row_fidelity',  'Predicted fidelity'),              '—'; ...
        Labels.get('prediction_table_row_prob',      'Expected success probability'),    '—'; ...
        Labels.get('prediction_table_row_queue',     'Expected queue time'),             '—'; ...
        Labels.get('prediction_table_row_runtime',   'Estimated runtime'),               '—'; ...
        Labels.get('prediction_table_row_notify',    'Notification mode'),               ...
            Labels.get('prediction_table_default_notify', 'Email + in-app')};
    app.styleTable(app.PredictionTable);

    % ── Distribution and Error Budget (right) ─────────────────────────────────
    detailPanel = uipanel(g, 'Title', Labels.get('prediction_panel_detail'));
    detailPanel.Layout.Row = 2; detailPanel.Layout.Column = 3; detailPanel.BackgroundColor = [1 1 1];

    dpg = uigridlayout(detailPanel, [1 1]);
    dpg.Padding = [12 10 12 10]; dpg.BackgroundColor = [1 1 1];
    app.PredictionTextArea = uitextarea(dpg, 'Editable', 'off'); app.PredictionTextArea.FontSize = 12;
    app.PredictionTextArea.Value = { ...
        'Run prediction to see:', ...
        '  - Expected probability distribution', ...
        '  - Error budget breakdown', ...
        '    (Readout / 2Q gates / Decoherence / Crosstalk)'};

    % ── Action bar ────────────────────────────────────────────────────────────
    submitPanel = uipanel(g, 'Title', Labels.get('prediction_panel_action'));
    submitPanel.Layout.Row = 3; submitPanel.Layout.Column = [1 3];
    submitPanel.BackgroundColor = [0.94 0.97 1.00];

    sg = uigridlayout(submitPanel, [1 4]);
    sg.ColumnWidth = {'1x', 110, 130, 120};
    sg.Padding = [14 8 14 8]; sg.BackgroundColor = [0.94 0.97 1.00];
    desc = uilabel(sg, 'Text', Labels.get('prediction_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(sg, 'Text', [char(9654) ' ' Labels.get('prediction_btn_submit')], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Jobs'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'success');
    tmp.FontSize = 14;
    tmp.Tooltip = 'Navigate to Jobs to submit';
    tmp = uibutton(sg, 'Text', Labels.get('prediction_btn_back'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Benchmark'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');
    tmp = uibutton(sg, 'Text', Labels.get('prediction_btn_save'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 4; app.styleBtn(tmp, 'secondary');

    Logger.info('PredictionScreen', 'Prediction tab UI built successfully');
end
