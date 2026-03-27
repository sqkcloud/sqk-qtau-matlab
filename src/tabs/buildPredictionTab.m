% buildPredictionTab  Populates the Prediction section panel.
%
%   Layout (3-column grid, 3 rows):
%     Row 1:      Full-width Run Prediction button.
%     Row 2, Col 1: Prediction Summary table (metrics + values).
%     Row 2, Col 2: 6 px resizable divider.
%     Row 2, Col 3: Distribution and Error Budget text area.
%     Row 3:      Full-width action bar (Submit Job / Back: Benchmark / Save).
function buildPredictionTab(app)
    t = app.createSectionPage('Prediction');

    % ── Root grid: 3 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {44, '1x', 72};
    g.ColumnWidth   = {'1x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % Primary action button — triggers /api/predictions POST
    app.PredictButton=uibutton(g,'Text','Run Prediction', ...
        'ButtonPushedFcn',@(~,~)app.onRunPrediction());
    app.PredictButton.Layout.Row=1; app.PredictButton.Layout.Column=[1 3];
    app.styleBtn(app.PredictButton,'primary');
    app.PredictButton.Tooltip='POST to /api/predictions with current benchmark settings';

    % ── Column divider ────────────────────────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=2; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Prediction Summary table (left panel) ─────────────────────────────────
    % Compact key-value table of the most important prediction outputs.
    metricPanel=uipanel(g,'Title','Prediction Summary');
    metricPanel.Layout.Row=2; metricPanel.Layout.Column=1; metricPanel.BackgroundColor=[1 1 1];

    mpg=uigridlayout(metricPanel,[1 1]);
    mpg.Padding=[12 10 12 10];
    mpg.BackgroundColor=[1 1 1];
    app.PredictionTable=uitable(mpg);
    app.PredictionTable.ColumnName={'Metric','Value'};
    app.PredictionTable.Data={ ...
        'Predicted fidelity','0.963 ± 0.012'; ...
        'Expected success probability','0.941'; ...
        'Expected queue time','7-12 min'; ...
        'Estimated runtime','18 s'; ...
        'Notification mode','Email + in-app'};
    app.styleTable(app.PredictionTable);

    % ── Distribution and Error Budget (right panel) ───────────────────────────
    % Top-N state probabilities and a percentage breakdown of error contributors.
    detailPanel=uipanel(g,'Title','Distribution and Error Budget');
    detailPanel.Layout.Row=2; detailPanel.Layout.Column=3; detailPanel.BackgroundColor=[1 1 1];

    dpg=uigridlayout(detailPanel,[1 1]);
    dpg.Padding=[12 10 12 10];
    dpg.BackgroundColor=[1 1 1];
    app.PredictionTextArea=uitextarea(dpg,'Editable','off'); app.PredictionTextArea.FontSize=12;
    app.PredictionTextArea.Value={ ...
        'Expected probability distribution:', ...
        '  state 0000000... : 0.76', ...
        '  state 0000001... : 0.08', ...
        '  state 1000000... : 0.05', ...
        '', ...
        'Error budget breakdown:', ...
        '  - Readout: 34 %', ...
        '  - 2Q gate infidelity: 41 %', ...
        '  - Decoherence: 17 %', ...
        '  - Crosstalk and routing overhead: 8 %'};

    % ── Action bar ────────────────────────────────────────────────────────────
    submitPanel=uipanel(g,'Title','Submit Job');
    submitPanel.Layout.Row=3; submitPanel.Layout.Column=[1 3];
    submitPanel.BackgroundColor=[0.94 0.97 1.00];

    sg=uigridlayout(submitPanel,[1 4]);
    sg.ColumnWidth={'1x',140,165,155};
    sg.Padding=[14 8 14 8];
    sg.BackgroundColor=[0.94 0.97 1.00];

    desc=uilabel(sg,'Text','Review fidelity, distribution, and error budget before submitting the job to IBM Quantum.');
    desc.FontSize=13; desc.FontWeight='bold'; desc.Layout.Row=1; desc.Layout.Column=1;
    desc.VerticalAlignment='center'; desc.WordWrap='on';

    % Submit navigates to Jobs screen and triggers the submission workflow
    tmp=uibutton(sg,'Text','Submit Job','ButtonPushedFcn',@(~,~)app.onSelectSection('Jobs'));
    tmp.Layout.Row=1; tmp.Layout.Column=2; app.styleBtn(tmp,'success');
    tmp=uibutton(sg,'Text','Back: Benchmark','ButtonPushedFcn',@(~,~)app.onSelectSection('Benchmark'));
    tmp.Layout.Row=1; tmp.Layout.Column=3; app.styleBtn(tmp,'ghost');
    tmp=uibutton(sg,'Text','Save Prediction');
    tmp.Layout.Row=1; tmp.Layout.Column=4; app.styleBtn(tmp,'secondary');
end
