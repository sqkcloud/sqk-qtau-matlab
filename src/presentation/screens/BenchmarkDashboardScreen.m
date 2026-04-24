% BenchmarkDashboardScreen  Populates the Benchmark Dashboard section panel.
%
%   Layout:
%     Row 1 (34 px):   Toolbar — Backend selector + source badge + Refresh All + Export Data.
%     Row 2 (22 px):   Status line — "N jobs · M predictions · cal 18 h · source: ibm_runtime".
%     Row 3 (130 px):  System Metrics KPI cards (5 cards, full width, with secondary unit line).
%     Row 4 ('1.2x'):  Volumetric Fidelity Heatmap (left) | Backend Scorecard Radar (right).
%     Row 5 ('1x'):    Prediction Calibration scatter (left) | Benchmark Regression line (right).
function BenchmarkDashboardScreen(app)
    Logger.info('BenchmarkDashboardScreen', 'Building Benchmark Dashboard tab UI');
    t = app.createSectionPage('Benchmark Dashboard');

    g = uigridlayout(t, [5 2]);
    g.RowHeight     = {34, 22, 130, '1.2x', '1x'};
    g.ColumnWidth   = {'1x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Row 1: Toolbar ───────────────────────────────────────────────────
    toolbar = uigridlayout(g, [1 5]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 2];
    toolbar.ColumnWidth = {90, '1x', 120, 110, 110};
    toolbar.Padding = [0 0 0 0]; toolbar.ColumnSpacing = 8;
    toolbar.BackgroundColor = Theme.COLOR_BG;

    backLbl = uilabel(toolbar, 'Text', 'Backend', ...
        'FontSize', 13, 'FontColor', Theme.COLOR_LABEL, ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
    backLbl.Layout.Row = 1; backLbl.Layout.Column = 1;

    app.BenchmarkBackendDropdown = uidropdown(toolbar, ...
        'Items', {'(none)'}, 'ItemsData', {''}, 'Value', '', ...
        'ValueChangedFcn', @(src,~) app.BenchmarkDashboardVm.onBackendChanged(src.Value));
    app.BenchmarkBackendDropdown.Layout.Row = 1;
    app.BenchmarkBackendDropdown.Layout.Column = 2;
    app.BenchmarkBackendDropdown.Tooltip = 'Select a backend to update per-backend metrics, scorecard, and regression charts.';

    % Source badge — tinted label showing where system-metrics data came from
    % (ibm_runtime / stub / unavailable). Hidden until first refresh populates it.
    app.BenchmarkSourceBadge = uilabel(toolbar, ...
        'Text', '', 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'center', 'FontSize', 11, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_LABEL, 'BackgroundColor', Theme.COLOR_CARD, ...
        'Tooltip', 'Data source for System Benchmark Metrics.');
    app.BenchmarkSourceBadge.Layout.Row = 1;
    app.BenchmarkSourceBadge.Layout.Column = 3;

    app.BenchmarkRefreshButton = uibutton(toolbar, 'Text', ...
        [char(8635) ' Refresh All'], ...
        'ButtonPushedFcn', @(~,~) app.BenchmarkDashboardVm.onRefreshAll());
    app.BenchmarkRefreshButton.Layout.Row = 1;
    app.BenchmarkRefreshButton.Layout.Column = 4;
    app.styleBtn(app.BenchmarkRefreshButton, 'primary');

    exportBtn = uibutton(toolbar, 'Text', [char(8681) ' Export Data'], ...
        'ButtonPushedFcn', @(~,~) app.BenchmarkDashboardVm.onExportData());
    exportBtn.Layout.Row = 1; exportBtn.Layout.Column = 5;
    app.styleBtn(exportBtn, 'ghost');

    % ── Row 2: Status line ──────────────────────────────────────────────
    app.BenchmarkStatusLabel = uilabel(g, ...
        'Text', 'Select a backend and press Refresh All to load data.', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'center');
    app.BenchmarkStatusLabel.Layout.Row = 2;
    app.BenchmarkStatusLabel.Layout.Column = [1 2];

    % ── Row 3: System Metrics KPI cards ──────────────────────────────────
    kpiPanel = uipanel(g, 'Title', 'System Benchmark Metrics', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    kpiPanel.Layout.Row = 3; kpiPanel.Layout.Column = [1 2];
    kpiPanel.BackgroundColor = Theme.COLOR_CARD;

    kg = uigridlayout(kpiPanel, [1 5]);
    kg.ColumnWidth = {'1x','1x','1x','1x','1x'};
    kg.Padding = [12 10 12 10]; kg.ColumnSpacing = 10;
    kg.BackgroundColor = Theme.COLOR_CARD;

    cardNames   = {'Quantum Volume', 'CLOPS', 'Layer Fidelity', 'EPLG', 'Overall Score'};
    cardUnits   = {'log₂', 'kilo ops/s', '0 – 1', '0 – 1', '0 – 10'};
    cardDefault = {'--','--','--','--','--'};
    cardAccents = {Theme.COLOR_PRIMARY, Theme.COLOR_SUCCESS, ...
                   [0.50 0.25 0.72], [0.80 0.50 0.10], [0.10 0.58 0.56]};

    app.BenchmarkKpiLabels = cell(1, 5);
    app.BenchmarkKpiUnits  = cell(1, 5);
    for i = 1:5
        p = uipanel(kg, 'Title', '', 'BorderType', 'line', ...
            'BorderColor', Theme.COLOR_DIVIDER);
        p.Layout.Row = 1; p.Layout.Column = i;
        p.BackgroundColor = Theme.COLOR_CARD;

        pg = uigridlayout(p, [1 2]);
        pg.ColumnWidth = {5, '1x'}; pg.Padding = [0 0 0 0];
        pg.ColumnSpacing = 0; pg.BackgroundColor = Theme.COLOR_CARD;

        strip = uipanel(pg, 'Title', '', 'BorderType', 'none');
        strip.Layout.Row = 1; strip.Layout.Column = 1;
        strip.BackgroundColor = cardAccents{i};

        inner = uigridlayout(pg, [3 1]);
        inner.Layout.Row = 1; inner.Layout.Column = 2;
        inner.RowHeight = {18, '1x', 16}; inner.Padding = [8 8 8 6];
        inner.BackgroundColor = Theme.COLOR_CARD;

        l1 = uilabel(inner, 'Text', cardNames{i}, ...
            'FontColor', Theme.COLOR_MUTED, 'FontSize', 11);
        l1.Layout.Row = 1; l1.Layout.Column = 1;

        l2 = uilabel(inner, 'Text', cardDefault{i}, ...
            'FontWeight', 'bold', 'FontSize', 17, 'WordWrap', 'on');
        l2.Layout.Row = 2; l2.Layout.Column = 1;
        app.BenchmarkKpiLabels{i} = l2;

        l3 = uilabel(inner, 'Text', cardUnits{i}, ...
            'FontColor', Theme.COLOR_MUTED, 'FontSize', 10);
        l3.Layout.Row = 3; l3.Layout.Column = 1;
        app.BenchmarkKpiUnits{i} = l3;
    end

    % ── Row 4 Left: Volumetric Fidelity Heatmap ─────────────────────────
    volPanel = uipanel(g, 'Title', 'Volumetric Fidelity Map', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    volPanel.Layout.Row = 4; volPanel.Layout.Column = 1;
    volPanel.BackgroundColor = Theme.COLOR_CARD;
    vpg = uigridlayout(volPanel, [1 1]);
    vpg.Padding = [10 10 10 10]; vpg.BackgroundColor = Theme.COLOR_CARD;
    app.VolumetricAxes = uiaxes(vpg);
    title(app.VolumetricAxes, 'Volumetric Fidelity Map', 'Interpreter', 'none');
    xlabel(app.VolumetricAxes, 'Circuit Depth', 'Interpreter', 'none');
    ylabel(app.VolumetricAxes, 'Circuit Width', 'Interpreter', 'none');
    app.styleAxes(app.VolumetricAxes);

    % ── Row 4 Right: Backend Scorecard Radar Chart ───────────────────────
    radarPanel = uipanel(g, 'Title', 'Backend Scorecard', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    radarPanel.Layout.Row = 4; radarPanel.Layout.Column = 2;
    radarPanel.BackgroundColor = Theme.COLOR_CARD;
    rpg = uigridlayout(radarPanel, [1 1]);
    rpg.Padding = [10 10 10 10]; rpg.BackgroundColor = Theme.COLOR_CARD;
    app.ScorecardAxes = polaraxes(rpg);
    app.ScorecardAxes.ThetaTick = [0 90 180 270];
    app.ScorecardAxes.ThetaTickLabel = {'Capacity','Scalability','Accuracy','Runtime'};
    app.ScorecardAxes.RLim = [0 10];
    title(app.ScorecardAxes, 'Backend Scorecard', 'Interpreter', 'none');

    % ── Row 5 Left: Prediction Calibration scatter ───────────────────────
    calPanel = uipanel(g, 'Title', 'Prediction Calibration', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    calPanel.Layout.Row = 5; calPanel.Layout.Column = 1;
    calPanel.BackgroundColor = Theme.COLOR_CARD;
    cpg = uigridlayout(calPanel, [1 1]);
    cpg.Padding = [10 10 10 10]; cpg.BackgroundColor = Theme.COLOR_CARD;
    app.CalibrationAxes = uiaxes(cpg);
    title(app.CalibrationAxes, 'Predicted vs Actual Fidelity', 'Interpreter', 'none');
    xlabel(app.CalibrationAxes, 'Predicted Fidelity', 'Interpreter', 'none');
    ylabel(app.CalibrationAxes, 'Actual Fidelity', 'Interpreter', 'none');
    app.styleAxes(app.CalibrationAxes);

    % ── Row 5 Right: Benchmark Regression time-series ────────────────────
    regPanel = uipanel(g, 'Title', 'Benchmark Regression', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    regPanel.Layout.Row = 5; regPanel.Layout.Column = 2;
    regPanel.BackgroundColor = Theme.COLOR_CARD;
    rrpg = uigridlayout(regPanel, [1 1]);
    rrpg.Padding = [10 10 10 10]; rrpg.BackgroundColor = Theme.COLOR_CARD;
    app.RegressionAxes = uiaxes(rrpg);
    title(app.RegressionAxes, 'Fidelity over Time', 'Interpreter', 'none');
    xlabel(app.RegressionAxes, 'Time', 'Interpreter', 'none');
    ylabel(app.RegressionAxes, 'Fidelity', 'Interpreter', 'none');
    app.styleAxes(app.RegressionAxes);

    Logger.info('BenchmarkDashboardScreen', 'Benchmark Dashboard tab built');
end
