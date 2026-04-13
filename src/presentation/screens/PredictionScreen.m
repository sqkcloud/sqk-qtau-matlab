% PredictionScreen  Populates the Prediction section panel.
%
%   Layout:
%     Row 1 (34 px):   Full-width toolbar with Run Prediction button.
%     Row 2 (40 px):   Headline callout — shows the top backend + predicted fidelity.
%     Row 3 ('1x'):    3-column split:
%                         Col 1: Prediction Summary table (metric/value rows)
%                         Col 2: Probability Distribution bar chart (top 8 states)
%                         Col 3: Error Budget breakdown bar chart
%     Row 4 (72 px):   Action bar — Jobs / Benchmark / Save Prediction.
%
%   All visible strings come from resources/labels.properties via Labels.
function PredictionScreen(app)
    Logger.info('PredictionScreen', 'Building Prediction tab UI');
    t = app.createSectionPage('Prediction');

    g = uigridlayout(t, [4 3]);
    g.RowHeight     = {34, 40, '1x', 72};
    g.ColumnWidth   = {'1x', '1x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = 10;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Row 1: Toolbar ───────────────────────────────────────────────────────
    toolbar = uigridlayout(g, [1 2]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {'1x', 150};
    toolbar.Padding = [0 0 0 0]; toolbar.BackgroundColor = Theme.COLOR_BG;

    app.PredictButton = uibutton(toolbar, 'Text', [char(9881) ' ' Labels.get('prediction_btn_run', 'Run Prediction')], ...
        'ButtonPushedFcn', @(~,~)app.PredictionVm.onRunPrediction());
    app.PredictButton.Layout.Row = 1; app.PredictButton.Layout.Column = 2;
    app.styleBtn(app.PredictButton, 'primary');
    app.PredictButton.FontSize = 14;
    app.PredictButton.Tooltip = 'POST /api/predict with current circuit + backend + benchmark config';

    % ── Row 2: Headline recommendation callout ───────────────────────────────
    app.PredictionHeadlineLabel = uilabel(g, ...
        'Text', Labels.get('prediction_headline_initial', ...
            'Run a prediction to see the recommended backend and expected fidelity.'), ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'FontColor', [0.30 0.36 0.48], ...
        'BackgroundColor', [0.94 0.97 1.00], ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'WordWrap', 'on', 'Interpreter', 'none');
    app.PredictionHeadlineLabel.Layout.Row = 2; app.PredictionHeadlineLabel.Layout.Column = [1 3];

    % ── Row 3, Col 1: Prediction Summary table ───────────────────────────────
    metricPanel = uipanel(g, 'Title', Labels.get('prediction_panel_summary', 'Prediction Summary'));
    metricPanel.Layout.Row = 3; metricPanel.Layout.Column = 1;
    metricPanel.BackgroundColor = Theme.COLOR_CARD;

    mpg = uigridlayout(metricPanel, [1 1]);
    mpg.Padding = [10 10 10 10]; mpg.BackgroundColor = Theme.COLOR_CARD;
    app.PredictionTable = uitable(mpg);
    app.PredictionTable.ColumnName = Labels.cols('prediction_table_cols', {'Metric','Value'});
    app.PredictionTable.Data = { ...
        'Top backend',                   '—'; ...
        'Predicted fidelity',            '—'; ...
        'Expected success probability',  '—'; ...
        'Confidence',                    '—'; ...
        'Confidence interval',           '—'; ...
        'Expected queue time',           '—'; ...
        'Estimated runtime',             '—'; ...
        'Estimated cost',                '—'; ...
        'Risk score',                    '—'; ...
        'Prediction ID',                 '—'};
    app.styleTable(app.PredictionTable);

    % ── Row 3, Col 2: Probability Distribution chart ─────────────────────────
    distPanel = uipanel(g, 'Title', Labels.get('prediction_panel_dist', 'Probability Distribution'));
    distPanel.Layout.Row = 3; distPanel.Layout.Column = 2;
    distPanel.BackgroundColor = Theme.COLOR_CARD;

    dpg = uigridlayout(distPanel, [1 1]);
    dpg.Padding = [10 10 10 10]; dpg.BackgroundColor = Theme.COLOR_CARD;
    app.PredictionDistAxes = uiaxes(dpg);
    app.styleAxes(app.PredictionDistAxes);
    title(app.PredictionDistAxes, ...
        Labels.get('prediction_dist_title', 'Top measurement outcomes'));
    xlabel(app.PredictionDistAxes, 'Bitstring');
    ylabel(app.PredictionDistAxes, 'Probability');
    text(app.PredictionDistAxes, 0.5, 0.5, ...
        Labels.get('prediction_dist_initial', 'Run prediction to populate'), ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'Color', [0.55 0.60 0.68], ...
        'FontSize', 11, 'Interpreter', 'none');

    % ── Row 3, Col 3: Error Budget breakdown chart ───────────────────────────
    budgetPanel = uipanel(g, 'Title', Labels.get('prediction_panel_budget', 'Error Budget'));
    budgetPanel.Layout.Row = 3; budgetPanel.Layout.Column = 3;
    budgetPanel.BackgroundColor = Theme.COLOR_CARD;

    bpg = uigridlayout(budgetPanel, [1 1]);
    bpg.Padding = [10 10 10 10]; bpg.BackgroundColor = Theme.COLOR_CARD;
    app.PredictionBudgetAxes = uiaxes(bpg);
    app.styleAxes(app.PredictionBudgetAxes);
    title(app.PredictionBudgetAxes, ...
        Labels.get('prediction_budget_title', 'Error budget breakdown'));
    xlabel(app.PredictionBudgetAxes, 'Fraction of total error');
    text(app.PredictionBudgetAxes, 0.5, 0.5, ...
        Labels.get('prediction_budget_initial', 'Run prediction to populate'), ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'Color', [0.55 0.60 0.68], ...
        'FontSize', 11, 'Interpreter', 'none');

    % ── Row 4: Action bar ────────────────────────────────────────────────────
    submitPanel = uipanel(g, 'Title', Labels.get('prediction_panel_action'));
    submitPanel.Layout.Row = 4; submitPanel.Layout.Column = [1 3];
    submitPanel.BackgroundColor = [0.94 0.97 1.00];

    sg = uigridlayout(submitPanel, [1 4]);
    sg.ColumnWidth = {'1x', 110, 130, 140};
    sg.Padding = [14 8 14 8]; sg.BackgroundColor = [0.94 0.97 1.00];
    desc = uilabel(sg, 'Text', Labels.get('prediction_action_msg'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(sg, 'Text', [char(9635) ' Jobs'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Jobs'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'success');
    tmp.FontSize = 14;
    tmp.Tooltip = 'Navigate to Jobs to submit';
    tmp = uibutton(sg, 'Text', [char(9678) ' Benchmark'], ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Benchmark'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'ghost');
    tmp = uibutton(sg, 'Text', Labels.get('prediction_btn_save', 'Save Prediction'));
    tmp.Layout.Row = 1; tmp.Layout.Column = 4; app.styleBtn(tmp, 'secondary');

    Logger.info('PredictionScreen', 'Prediction tab UI built successfully');
end
