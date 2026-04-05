% QecVisualizationScreen  Populates the QEC Visualization section panel.
%
%   Layout:
%     Row 1 (toolbar, 34 px): Refresh Bloch | Refresh Lattice | Animate  +  Next: Reports (right).
%     Row 2 ('1.6x'):         Bloch Sphere 3D (left) | Surface Code Lattice (right).
%     Row 3 ('1x'):           Fidelity Decay (left)  | Error Weight Distribution (right).
%
%   All visible strings come from resources/labels.properties via Labels.
function QecVisualizationScreen(app)
    Logger.info('QecVisualizationScreen', 'Building QEC Visualization tab UI');
    t = app.createSectionPage('QEC Visualization');

    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {34, '1.6x', '1x'};
    g.ColumnWidth   = {'1x', 6, '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Toolbar ──────────────────────────────────────────────────────────
    toolbar = uigridlayout(g, [1 2]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 3];
    toolbar.ColumnWidth = {'1x', 150};
    toolbar.Padding = [0 0 0 0];
    toolbar.BackgroundColor = Theme.COLOR_BG;

    leftBtns = uigridlayout(toolbar, [1 3]);
    leftBtns.Layout.Row = 1; leftBtns.Layout.Column = 1;
    leftBtns.ColumnWidth = {120, 120, 120};
    leftBtns.Padding = [0 0 0 0]; leftBtns.ColumnSpacing = 8;
    leftBtns.BackgroundColor = Theme.COLOR_BG;

    app.QecRefreshBlochButton = uibutton(leftBtns, 'Text', ...
        [char(8635) ' ' Labels.get('qec_viz_btn_refresh_bloch', 'Refresh Bloch')], ...
        'ButtonPushedFcn', @(~,~)app.QecVisualizationVm.onRefreshBloch());
    app.QecRefreshBlochButton.Layout.Row = 1; app.QecRefreshBlochButton.Layout.Column = 1;
    app.styleBtn(app.QecRefreshBlochButton, 'ghost');
    app.QecRefreshBlochButton.FontSize = 14;

    app.QecRefreshLatticeButton = uibutton(leftBtns, 'Text', ...
        [char(8635) ' ' Labels.get('qec_viz_btn_refresh_lattice', 'Refresh Lattice')], ...
        'ButtonPushedFcn', @(~,~)app.QecVisualizationVm.onRefreshLattice());
    app.QecRefreshLatticeButton.Layout.Row = 1; app.QecRefreshLatticeButton.Layout.Column = 2;
    app.styleBtn(app.QecRefreshLatticeButton, 'ghost');
    app.QecRefreshLatticeButton.FontSize = 14;

    app.QecAnimateButton = uibutton(leftBtns, 'Text', ...
        [char(9654) ' ' Labels.get('qec_viz_btn_animate', 'Animate Decay')], ...
        'ButtonPushedFcn', @(~,~)app.QecVisualizationVm.onAnimateDecay());
    app.QecAnimateButton.Layout.Row = 1; app.QecAnimateButton.Layout.Column = 3;
    app.styleBtn(app.QecAnimateButton, 'secondary');
    app.QecAnimateButton.FontSize = 14;

    nextBtn = uibutton(toolbar, 'Text', Labels.get('qec_viz_btn_next', 'Next: Reports'), ...
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Reports'));
    nextBtn.Layout.Row = 1; nextBtn.Layout.Column = 2;
    app.styleBtn(nextBtn, 'primary');

    % ── Column divider (rows 2-3) ────────────────────────────────────────
    div = uipanel(g, 'Title', '');
    div.Layout.Row = [2 3]; div.Layout.Column = 2;
    div.BackgroundColor = Theme.COLOR_DIVIDER; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── Bloch Sphere 3D (left, row 2) ────────────────────────────────────
    blochPanel = uipanel(g, 'Title', Labels.get('qec_viz_panel_bloch', 'Logical Qubit Bloch Sphere'));
    blochPanel.Layout.Row = 2; blochPanel.Layout.Column = 1;
    blochPanel.BackgroundColor = Theme.COLOR_CARD;
    bpg = uigridlayout(blochPanel, [1 1]);
    bpg.Padding = [6 6 6 6]; bpg.BackgroundColor = Theme.COLOR_CARD;
    app.QecBlochAxes = uiaxes(bpg);
    % Render initial demo Bloch sphere
    drawBlochSphereDemo(app.QecBlochAxes, [0 0 1]);

    % ── Surface Code Lattice (right, row 2) ──────────────────────────────
    latticePanel = uipanel(g, 'Title', Labels.get('qec_viz_panel_lattice', 'Surface Code Lattice'));
    latticePanel.Layout.Row = 2; latticePanel.Layout.Column = 3;
    latticePanel.BackgroundColor = Theme.COLOR_CARD;
    lpg = uigridlayout(latticePanel, [1 1]);
    lpg.Padding = [6 6 6 6]; lpg.BackgroundColor = Theme.COLOR_CARD;
    app.QecLatticeAxes = uiaxes(lpg);
    % Render initial demo lattice
    drawSurfaceCodeDemo(app.QecLatticeAxes, 3);

    % ── Fidelity Decay Over Rounds (left, row 3) ─────────────────────────
    decayPanel = uipanel(g, 'Title', Labels.get('qec_viz_panel_decay', 'Fidelity Decay Over Rounds'));
    decayPanel.Layout.Row = 3; decayPanel.Layout.Column = 1;
    decayPanel.BackgroundColor = Theme.COLOR_CARD;
    dpg = uigridlayout(decayPanel, [1 1]);
    dpg.Padding = [10 10 10 10]; dpg.BackgroundColor = Theme.COLOR_CARD;
    app.QecDecayAxes = uiaxes(dpg);
    % Demo decay
    rounds = 1:10;
    decayDemo = 1 - 0.02*(rounds-1) - 0.005*randn(1,10);
    plot(app.QecDecayAxes, rounds, decayDemo, '-s', 'Color', Theme.COLOR_SUCCESS, ...
        'LineWidth', 1.8, 'MarkerSize', 5, 'MarkerFaceColor', Theme.COLOR_SUCCESS);
    app.styleAxes(app.QecDecayAxes);
    app.QecDecayAxes.Title.String  = Labels.get('qec_viz_plot_decay_title', 'Fidelity vs Correction Round (demo)');
    app.QecDecayAxes.XLabel.String = Labels.get('qec_viz_plot_decay_x', 'Correction Round');
    app.QecDecayAxes.YLabel.String = Labels.get('qec_viz_plot_decay_y', 'Fidelity');
    app.QecDecayAxes.YLim = [0 1.05];

    % ── Error Weight Distribution (right, row 3) ─────────────────────────
    ewPanel = uipanel(g, 'Title', Labels.get('qec_viz_panel_errweight', 'Error Weight Distribution'));
    ewPanel.Layout.Row = 3; ewPanel.Layout.Column = 3;
    ewPanel.BackgroundColor = Theme.COLOR_CARD;
    ewpg = uigridlayout(ewPanel, [1 1]);
    ewpg.Padding = [10 10 10 10]; ewpg.BackgroundColor = Theme.COLOR_CARD;
    app.QecErrorWeightAxes = uiaxes(ewpg);
    % Demo error weight
    weights = 0:3;
    probs = [0.857 0.135 0.007 0.001];
    bar(app.QecErrorWeightAxes, weights, probs, 'FaceColor', [0.85 0.33 0.10]);
    app.styleAxes(app.QecErrorWeightAxes);
    app.QecErrorWeightAxes.Title.String  = Labels.get('qec_viz_plot_errweight_title', 'Error Weight Distribution (demo)');
    app.QecErrorWeightAxes.XLabel.String = Labels.get('qec_viz_plot_errweight_x', 'Number of Errors');
    app.QecErrorWeightAxes.YLabel.String = Labels.get('qec_viz_plot_errweight_y', 'Probability');

    Logger.info('QecVisualizationScreen', 'QEC Visualization tab UI built successfully');
end

% ── Local helper: draw the Bloch sphere wireframe + vector ────────────────
function drawBlochSphereDemo(ax, blochVec)
    cla(ax); hold(ax, 'on');

    % Wireframe sphere
    [sx, sy, sz] = sphere(30);
    mesh(ax, sx, sy, sz, 'FaceAlpha', 0.04, 'EdgeAlpha', 0.10, ...
        'EdgeColor', [0.7 0.7 0.7], 'FaceColor', [0.9 0.93 0.97]);

    % Great circles (equator + two meridians)
    theta = linspace(0, 2*pi, 100);
    plot3(ax, cos(theta), sin(theta), zeros(size(theta)), '-', ...
        'Color', [0.75 0.75 0.80], 'LineWidth', 0.6);
    plot3(ax, cos(theta), zeros(size(theta)), sin(theta), '-', ...
        'Color', [0.75 0.75 0.80], 'LineWidth', 0.6);
    plot3(ax, zeros(size(theta)), cos(theta), sin(theta), '-', ...
        'Color', [0.75 0.75 0.80], 'LineWidth', 0.6);

    % Coordinate axes
    plot3(ax, [-1.3 1.3], [0 0], [0 0], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
    plot3(ax, [0 0], [-1.3 1.3], [0 0], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);
    plot3(ax, [0 0], [0 0], [-1.3 1.3], '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8);

    % State labels
    text(ax, 0, 0, 1.45, '|0\rangle', 'FontSize', 13, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'Color', [0.15 0.25 0.55]);
    text(ax, 0, 0, -1.45, '|1\rangle', 'FontSize', 13, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'Color', [0.15 0.25 0.55]);
    text(ax, 1.45, 0, 0, '|+\rangle', 'FontSize', 13, 'FontWeight', 'bold', ...
        'Color', [0.15 0.25 0.55]);
    text(ax, -1.45, 0, 0, '|-\rangle', 'FontSize', 13, 'FontWeight', 'bold', ...
        'Color', [0.15 0.25 0.55]);
    text(ax, 0, 1.45, 0, '|i\rangle', 'FontSize', 13, 'FontWeight', 'bold', ...
        'Color', [0.15 0.25 0.55]);
    text(ax, 0, -1.45, 0, '|-i\rangle', 'FontSize', 13, 'FontWeight', 'bold', ...
        'Color', [0.15 0.25 0.55]);

    % Bloch vector arrow
    rx = blochVec(1); ry = blochVec(2); rz = blochVec(3);
    quiver3(ax, 0, 0, 0, rx, ry, rz, 0, 'Color', [0.85 0.20 0.20], ...
        'LineWidth', 2.8, 'MaxHeadSize', 0.5);

    % Vector tip marker
    scatter3(ax, rx, ry, rz, 80, [0.85 0.20 0.20], 'filled', ...
        'MarkerEdgeColor', [0.5 0.1 0.1], 'LineWidth', 1.2);

    hold(ax, 'off');
    view(ax, 135, 25);
    axis(ax, 'equal');
    ax.XLim = [-1.6 1.6]; ax.YLim = [-1.6 1.6]; ax.ZLim = [-1.6 1.6];
    grid(ax, 'on'); ax.GridAlpha = 0.15;
    ax.XTick = []; ax.YTick = []; ax.ZTick = [];
    ax.Color = [1 1 1];
    ax.Title.String = 'Logical Qubit Bloch Sphere';
    ax.Title.FontSize = 12;
end

% ── Local helper: draw the surface code lattice ──────────────────────────
function drawSurfaceCodeDemo(ax, distance)
    cla(ax); hold(ax, 'on');

    % Data qubits on grid vertices
    for row = 1:distance
        for col = 1:distance
            scatter(ax, col, row, 100, Theme.COLOR_PRIMARY, 'filled', ...
                'MarkerEdgeColor', [0.08 0.25 0.52], 'LineWidth', 1.2);
        end
    end

    % Grid lines connecting data qubits
    for row = 1:distance
        plot(ax, [1 distance], [row row], '-', 'Color', [0.8 0.82 0.85], 'LineWidth', 1);
    end
    for col = 1:distance
        plot(ax, [col col], [1 distance], '-', 'Color', [0.8 0.82 0.85], 'LineWidth', 1);
    end

    % X-stabilizers (plaquettes) — colored patches
    for row = 1:(distance-1)
        for col = 1:(distance-1)
            if mod(row + col, 2) == 0
                px = [col col+1 col+1 col];
                py = [row row row+1 row+1];
                patch(ax, px, py, [0.65 0.85 0.65], 'FaceAlpha', 0.25, ...
                    'EdgeColor', [0.3 0.6 0.3], 'LineWidth', 1.2);
                text(ax, col+0.5, row+0.5, 'X', 'FontSize', 10, ...
                    'FontWeight', 'bold', 'Color', [0.2 0.5 0.2], ...
                    'HorizontalAlignment', 'center');
            end
        end
    end

    % Z-stabilizers (vertices) — colored diamonds
    for row = 1:(distance-1)
        for col = 1:(distance-1)
            if mod(row + col, 2) == 1
                px = [col+0.5 col+1 col+0.5 col];
                py = [row row+0.5 row+1 row+0.5];
                patch(ax, px, py, [0.75 0.70 0.90], 'FaceAlpha', 0.25, ...
                    'EdgeColor', [0.45 0.30 0.65], 'LineWidth', 1.2);
                text(ax, col+0.5, row+0.5, 'Z', 'FontSize', 10, ...
                    'FontWeight', 'bold', 'Color', [0.45 0.30 0.65], ...
                    'HorizontalAlignment', 'center');
            end
        end
    end

    % Simulated error on one qubit (demo)
    errRow = 2; errCol = 2;
    scatter(ax, errCol, errRow, 200, [0.85 0.15 0.15], 'x', 'LineWidth', 3);
    text(ax, errCol + 0.15, errRow + 0.15, 'Error', 'FontSize', 9, ...
        'Color', [0.85 0.15 0.15], 'FontWeight', 'bold');

    hold(ax, 'off');
    ax.XLim = [0.3 distance+0.7]; ax.YLim = [0.3 distance+0.7];
    axis(ax, 'equal');
    grid(ax, 'on'); ax.GridAlpha = 0.1;
    ax.Title.String = sprintf('Surface Code d=%d Lattice (demo)', distance);
    ax.Title.FontSize = 12;
    ax.XLabel.String = 'Column';
    ax.YLabel.String = 'Row';
end
