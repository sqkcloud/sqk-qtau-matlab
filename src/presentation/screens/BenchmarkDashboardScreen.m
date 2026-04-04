% BenchmarkDashboardScreen  Populates the Benchmark Dashboard section panel.
%
%   Layout:
%     Row 1 (34 px):   Toolbar — Backend selector + Refresh All + Export Data.
%     Row 2 (120 px):  System Metrics KPI cards (5 cards, full width).
%     Row 3 ('1.2x'):  Volumetric Fidelity Heatmap (left) |
%                       Backend Scorecard Radar Chart (right).
%     Row 4 ('1x'):    Prediction Calibration scatter (left) |
%                       Benchmark Regression time-series (right).
function BenchmarkDashboardScreen(app)
    Logger.info('BenchmarkDashboardScreen', 'Building Benchmark Dashboard tab UI');
    t = app.createSectionPage('Benchmark Dashboard');

    g = uigridlayout(t, [4 3]);
    g.RowHeight     = {34, 120, '1.2x', '1x'};
    g.ColumnWidth   = {'1x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 0;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Row 1: Toolbar ───────────────────────────────────────────────────
    toolbar = uigridlayout(g, [1 4]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {90, '1x', 110, 110};
    toolbar.Padding = [0 0 0 0]; toolbar.ColumnSpacing = 8;
    toolbar.BackgroundColor = [0.96 0.97 0.99];

    backLbl = uilabel(toolbar, 'Text', 'Backend', ...
        'FontSize', 13, 'FontColor', [0.35 0.42 0.52], ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    backLbl.Layout.Row = 1; backLbl.Layout.Column = 1;

    app.BenchmarkBackendDropdown = uidropdown(toolbar, ...
        'Items', {'(none)'}, 'ItemsData', {''}, 'Value', '');
    app.BenchmarkBackendDropdown.Layout.Row = 1;
    app.BenchmarkBackendDropdown.Layout.Column = 2;

    app.BenchmarkRefreshButton = uibutton(toolbar, 'Text', ...
        [char(8635) ' Refresh All'], ...
        'ButtonPushedFcn', @(~,~) app.BenchmarkDashboardVm.onRefreshAll());
    app.BenchmarkRefreshButton.Layout.Row = 1;
    app.BenchmarkRefreshButton.Layout.Column = 3;
    app.styleBtn(app.BenchmarkRefreshButton, 'primary');

    exportBtn = uibutton(toolbar, 'Text', [char(8681) ' Export Data'], ...
        'ButtonPushedFcn', @(~,~) app.BenchmarkDashboardVm.onExportData());
    exportBtn.Layout.Row = 1; exportBtn.Layout.Column = 4;
    app.styleBtn(exportBtn, 'ghost');

    % ── Row 2: System Metrics KPI cards ──────────────────────────────────
    kpiPanel = uipanel(g, 'Title', 'System Benchmark Metrics');
    kpiPanel.Layout.Row = 2; kpiPanel.Layout.Column = [1 3];
    kpiPanel.BackgroundColor = [1 1 1];

    kg = uigridlayout(kpiPanel, [1 5]);
    kg.ColumnWidth = {'1x','1x','1x','1x','1x'};
    kg.Padding = [12 10 12 10]; kg.ColumnSpacing = 10;
    kg.BackgroundColor = [1 1 1];

    cardNames   = {'Quantum Volume', 'CLOPS', 'Layer Fidelity', 'EPLG', 'Overall Score'};
    cardDefault = {'--','--','--','--','--'};
    cardAccents = {[0.18 0.45 0.82], [0.10 0.54 0.36], ...
                   [0.50 0.25 0.72], [0.80 0.50 0.10], [0.10 0.58 0.56]};

    app.BenchmarkKpiLabels = cell(1, 5);
    for i = 1:5
        p = uipanel(kg, 'Title', '');
        p.Layout.Row = 1; p.Layout.Column = i;
        p.BackgroundColor = [0.96 0.97 0.99];

        pg = uigridlayout(p, [1 2]);
        pg.ColumnWidth = {5, '1x'}; pg.Padding = [0 0 0 0];
        pg.ColumnSpacing = 0; pg.BackgroundColor = [0.96 0.97 0.99];

        strip = uipanel(pg, 'Title', '');
        strip.Layout.Row = 1; strip.Layout.Column = 1;
        strip.BackgroundColor = cardAccents{i};

        inner = uigridlayout(pg, [2 1]);
        inner.Layout.Row = 1; inner.Layout.Column = 2;
        inner.RowHeight = {18, '1x'}; inner.Padding = [8 8 8 8];
        inner.BackgroundColor = [0.96 0.97 0.99];

        l1 = uilabel(inner, 'Text', cardNames{i}, ...
            'FontColor', [0.38 0.46 0.58], 'FontSize', 11);
        l1.Layout.Row = 1; l1.Layout.Column = 1;

        l2 = uilabel(inner, 'Text', cardDefault{i}, ...
            'FontWeight', 'bold', 'FontSize', 17, 'WordWrap', 'on');
        l2.Layout.Row = 2; l2.Layout.Column = 1;
        app.BenchmarkKpiLabels{i} = l2;
    end

    % ── Column divider (rows 3-4) ────────────────────────────────────────
    div = uipanel(g, 'Title', '');
    div.Layout.Row = [3 4]; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Row 3 Left: Volumetric Fidelity Heatmap ─────────────────────────
    volPanel = uipanel(g, 'Title', 'Volumetric Fidelity Map');
    volPanel.Layout.Row = 3; volPanel.Layout.Column = 1;
    volPanel.BackgroundColor = [1 1 1];
    vpg = uigridlayout(volPanel, [1 1]);
    vpg.Padding = [10 10 10 10]; vpg.BackgroundColor = [1 1 1];
    app.VolumetricAxes = uiaxes(vpg);
    title(app.VolumetricAxes, 'Volumetric Fidelity Map');
    xlabel(app.VolumetricAxes, 'Circuit Depth');
    ylabel(app.VolumetricAxes, 'Circuit Width');
    app.styleAxes(app.VolumetricAxes);

    % ── Row 3 Right: Backend Scorecard Radar Chart ───────────────────────
    radarPanel = uipanel(g, 'Title', 'Backend Scorecard');
    radarPanel.Layout.Row = 3; radarPanel.Layout.Column = 3;
    radarPanel.BackgroundColor = [1 1 1];
    rpg = uigridlayout(radarPanel, [1 1]);
    rpg.Padding = [10 10 10 10]; rpg.BackgroundColor = [1 1 1];
    app.ScorecardAxes = polaraxes(rpg);
    app.ScorecardAxes.ThetaTick = [0 90 180 270];
    app.ScorecardAxes.ThetaTickLabel = {'Capacity','Scalability','Accuracy','Runtime'};
    app.ScorecardAxes.RLim = [0 10];
    title(app.ScorecardAxes, 'Backend Scorecard');

    % ── Row 4 Left: Prediction Calibration scatter ───────────────────────
    calPanel = uipanel(g, 'Title', 'Prediction Calibration');
    calPanel.Layout.Row = 4; calPanel.Layout.Column = 1;
    calPanel.BackgroundColor = [1 1 1];
    cpg = uigridlayout(calPanel, [1 1]);
    cpg.Padding = [10 10 10 10]; cpg.BackgroundColor = [1 1 1];
    app.CalibrationAxes = uiaxes(cpg);
    title(app.CalibrationAxes, 'Predicted vs Actual Fidelity');
    xlabel(app.CalibrationAxes, 'Predicted Fidelity');
    ylabel(app.CalibrationAxes, 'Actual Fidelity');
    app.styleAxes(app.CalibrationAxes);

    % ── Row 4 Right: Benchmark Regression time-series ────────────────────
    regPanel = uipanel(g, 'Title', 'Benchmark Regression');
    regPanel.Layout.Row = 4; regPanel.Layout.Column = 3;
    regPanel.BackgroundColor = [1 1 1];
    rrpg = uigridlayout(regPanel, [1 1]);
    rrpg.Padding = [10 10 10 10]; rrpg.BackgroundColor = [1 1 1];
    app.RegressionAxes = uiaxes(rrpg);
    title(app.RegressionAxes, 'Fidelity over Time');
    xlabel(app.RegressionAxes, 'Time');
    ylabel(app.RegressionAxes, 'Fidelity');
    app.styleAxes(app.RegressionAxes);

    Logger.info('BenchmarkDashboardScreen', 'Benchmark Dashboard tab built');
end
