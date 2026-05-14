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

    g = uigridlayout(t, [3 2]);
    g.RowHeight     = {34, '1.6x', '1x'};
    g.ColumnWidth   = {'1x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Toolbar ──────────────────────────────────────────────────────────
    toolbar = uigridlayout(g, [1 2]);
    toolbar.Layout.Row = 1; toolbar.Layout.Column = [1 2];
    toolbar.ColumnWidth = {'1x', 150};
    toolbar.Padding = [0 0 0 0];
    toolbar.BackgroundColor = Theme.COLOR_BG;

    %  Phase 1+2: extended from 3 → 5 columns to host the new
    %  Circuit + Backend selectors. Backend selection drives the
    %  surface-code lattice distance d (16q→3, 27q→5, 65q→7,
    %  156q→11) so a 156-qubit backend draws the proper lattice
    %  size instead of the d=3 demo.
    leftBtns = uigridlayout(toolbar, [1 5]);
    leftBtns.Layout.Row = 1; leftBtns.Layout.Column = 1;
    %  Order: Circuit dd | Backend dd | Refresh Bloch | Refresh Lattice | Animate Decay
    leftBtns.ColumnWidth = {200, 220, 120, 120, 120};
    leftBtns.Padding = [0 0 0 0]; leftBtns.ColumnSpacing = 8;
    leftBtns.BackgroundColor = Theme.COLOR_BG;

    app.QecRefreshBlochButton = uibutton(leftBtns, 'Text', ...
        [char(8635) ' ' Labels.get('qec_viz_btn_refresh_bloch', 'Refresh Bloch')], ...
        'ButtonPushedFcn', @(~,~)app.QecVisualizationVm.onRefreshBloch());
    app.QecRefreshBlochButton.Layout.Row = 1; app.QecRefreshBlochButton.Layout.Column = 3;
    app.styleBtn(app.QecRefreshBlochButton, 'ghost');
    app.QecRefreshBlochButton.FontSize = 14;

    app.QecRefreshLatticeButton = uibutton(leftBtns, 'Text', ...
        [char(8635) ' ' Labels.get('qec_viz_btn_refresh_lattice', 'Refresh Lattice')], ...
        'ButtonPushedFcn', @(~,~)app.QecVisualizationVm.onRefreshLattice());
    app.QecRefreshLatticeButton.Layout.Row = 1; app.QecRefreshLatticeButton.Layout.Column = 4;
    app.styleBtn(app.QecRefreshLatticeButton, 'ghost');
    app.QecRefreshLatticeButton.FontSize = 14;

    app.QecAnimateButton = uibutton(leftBtns, 'Text', ...
        [char(9654) ' ' Labels.get('qec_viz_btn_animate', 'Animate Decay')], ...
        'ButtonPushedFcn', @(~,~)app.QecVisualizationVm.onAnimateDecay());
    app.QecAnimateButton.Layout.Row = 1; app.QecAnimateButton.Layout.Column = 5;
    app.styleBtn(app.QecAnimateButton, 'secondary');
    app.QecAnimateButton.FontSize = 14;

    %  Phase 1+2 selectors. Backend dropdown's calibration drives
    %  the auto-redraw of the surface-code lattice (distance d
    %  scaled from backend qubit count) and the Bloch sphere /
    %  fidelity-decay envelope. ItemsData carries circuit_id /
    %  backend_name; Items carry friendly labels populated by the
    %  VM after listCircuits / listBackends complete.
    app.QecVizCircuitDropdown = uidropdown(leftBtns, ...
        'Items', {'(loading circuits…)'}, ...
        'ItemsData', {''}, ...
        'Tooltip', 'Pick a circuit — its qubit count scopes the visualization', ...
        'ValueChangedFcn', @(src,~) app.QecVisualizationVm.onCircuitChanged(src.Value));
    app.QecVizCircuitDropdown.Layout.Row = 1; app.QecVizCircuitDropdown.Layout.Column = 1;
    app.QecVizCircuitDropdown.FontSize = 12;

    app.QecVizBackendDropdown = uidropdown(leftBtns, ...
        'Items', {'(loading backends…)'}, ...
        'ItemsData', {''}, ...
        'Tooltip', 'Pick a backend — qubit count drives lattice distance d', ...
        'ValueChangedFcn', @(src,~) app.QecVisualizationVm.onBackendChanged(src.Value));
    app.QecVizBackendDropdown.Layout.Row = 1; app.QecVizBackendDropdown.Layout.Column = 2;
    app.QecVizBackendDropdown.FontSize = 12;

    nextBtn = uibutton(toolbar, 'Text', [char(9636) ' Reports'], ...  % Reports nav icon
        'ButtonPushedFcn', @(~,~)app.onSelectSection('Reports'));
    nextBtn.Layout.Row = 1; nextBtn.Layout.Column = 2;
    app.styleBtn(nextBtn, 'primary');

    % ── Bloch Sphere 3D (left, row 2) ────────────────────────────────────
    blochPanel = uipanel(g, 'Title', Labels.get('qec_viz_panel_bloch', 'Logical Qubit Bloch Sphere'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    blochPanel.Layout.Row = 2; blochPanel.Layout.Column = 1;
    blochPanel.BackgroundColor = Theme.COLOR_CARD;
    bpg = uigridlayout(blochPanel, [1 1]);
    bpg.Padding = [6 6 6 6]; bpg.BackgroundColor = Theme.COLOR_CARD;
    % Lazy uiaxes — drawBlochSphere(WithTrail) materialise via
    % app.ensureLazyAxes(...) on first real paint.
    blochPlaceholder = uilabel(bpg, ...
        'Text', 'Bloch sphere appears here after a simulation step.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.QecBlochGrid        = bpg;
    app.QecBlochPlaceholder = blochPlaceholder;
    app.QecBlochAxes        = [];

    % ── Surface Code Lattice (right, row 2) ──────────────────────────────
    latticePanel = uipanel(g, 'Title', Labels.get('qec_viz_panel_lattice', 'Surface Code Lattice'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    latticePanel.Layout.Row = 2; latticePanel.Layout.Column = 2;
    latticePanel.BackgroundColor = Theme.COLOR_CARD;
    lpg = uigridlayout(latticePanel, [1 1]);
    lpg.Padding = [6 6 6 6]; lpg.BackgroundColor = Theme.COLOR_CARD;
    % Lazy uiaxes — drawLattice materialises via ensureLazyAxes(...).
    latticePlaceholder = uilabel(lpg, ...
        'Text', 'Surface code lattice appears here after a simulation step.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.QecLatticeGrid        = lpg;
    app.QecLatticePlaceholder = latticePlaceholder;
    app.QecLatticeAxes        = [];

    % ── Fidelity Decay Over Rounds (left, row 3) ─────────────────────────
    decayPanel = uipanel(g, 'Title', Labels.get('qec_viz_panel_decay', 'Fidelity Decay Over Rounds'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    decayPanel.Layout.Row = 3; decayPanel.Layout.Column = 1;
    decayPanel.BackgroundColor = Theme.COLOR_CARD;
    dpg = uigridlayout(decayPanel, [1 1]);
    dpg.Padding = [10 10 10 10]; dpg.BackgroundColor = Theme.COLOR_CARD;
    % Lazy uiaxes — see Bloch note.
    decayPlaceholder = uilabel(dpg, ...
        'Text', 'Fidelity-decay chart appears here after a simulation step.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.QecDecayGrid        = dpg;
    app.QecDecayPlaceholder = decayPlaceholder;
    app.QecDecayAxes        = [];

    % ── Error Weight Distribution (right, row 3) ─────────────────────────
    ewPanel = uipanel(g, 'Title', Labels.get('qec_viz_panel_errweight', 'Error Weight Distribution'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    ewPanel.Layout.Row = 3; ewPanel.Layout.Column = 2;
    ewPanel.BackgroundColor = Theme.COLOR_CARD;
    ewpg = uigridlayout(ewPanel, [1 1]);
    ewpg.Padding = [10 10 10 10]; ewpg.BackgroundColor = Theme.COLOR_CARD;
    % Lazy uiaxes — see Bloch note.
    ewPlaceholder = uilabel(ewpg, ...
        'Text', 'Error weight distribution appears here after a simulation step.', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
    app.QecErrorWeightGrid        = ewpg;
    app.QecErrorWeightPlaceholder = ewPlaceholder;
    app.QecErrorWeightAxes        = [];

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
