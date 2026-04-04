classdef QecVisualizationViewModel < handle
    % QecVisualizationViewModel  Callback handlers for the QEC Visualization screen.

    properties (Access = private)
        App  % QTAUWorkbenchApp
    end

    methods
        function obj = QecVisualizationViewModel(app)
            obj.App = app;
        end

        function onRefreshBloch(obj)
            app = obj.App;
            app.logEvent('QEC', 'Refreshing Bloch sphere visualization');
            try
                params = obj.readSimParams();
                result = app.QecEngine.simulate( ...
                    params.codeType, params.noiseModel, params.errorProb, ...
                    params.initialState, params.nRounds);

                % Also get ideal state Bloch vector (no noise)
                idealResult = app.QecEngine.simulate( ...
                    params.codeType, params.noiseModel, 0, ...
                    params.initialState, 1);

                obj.drawBlochSphere(result.blochVector, idealResult.blochVector);
                app.logEvent('QEC', sprintf('Bloch sphere updated — vector [%.3f, %.3f, %.3f]', ...
                    result.blochVector(1), result.blochVector(2), result.blochVector(3)));
            catch ME
                app.logEvent('ERROR', sprintf('Bloch refresh failed: %s', ME.message));
                uialert(app.UIFigure, ME.message, 'Bloch Sphere Error');
            end
        end

        function onRefreshLattice(obj)
            app = obj.App;
            app.logEvent('QEC', 'Refreshing surface code lattice');
            try
                distance = 3;
                % Read distance from QEC Simulation screen if available
                if ~isempty(app.QecDistanceSpinner) && isvalid(app.QecDistanceSpinner)
                    distance = round(app.QecDistanceSpinner.Value);
                end
                errorProb = 0.05;
                if ~isempty(app.QecErrorProbSlider) && isvalid(app.QecErrorProbSlider)
                    errorProb = app.QecErrorProbSlider.Value;
                end

                % Run surface code simulation
                result = app.QecEngine.simulateSurfaceCode(distance, errorProb, 500);
                lattice = app.QecEngine.surfaceLatticeCoords(distance);

                obj.drawLattice(lattice, errorProb);

                % Update error weight distribution
                nQubits = distance^2;
                dist = app.QecEngine.errorWeightDistribution(nQubits, errorProb);
                obj.plotErrorWeights(dist);

                app.logEvent('QEC', sprintf('Lattice updated — d=%d, logical error rate=%.4f', ...
                    distance, result.logicalErrorRate));
            catch ME
                app.logEvent('ERROR', sprintf('Lattice refresh failed: %s', ME.message));
                uialert(app.UIFigure, ME.message, 'Lattice Error');
            end
        end

        function onAnimateDecay(obj)
            app = obj.App;
            app.logEvent('QEC', 'Animating Bloch vector decay');
            try
                params = obj.readSimParams();
                nSteps = 30;
                pRange = linspace(0, 0.5, nSteps);
                blochTrail = zeros(nSteps, 3);

                % Get ideal vector
                idealResult = app.QecEngine.simulate( ...
                    params.codeType, params.noiseModel, 0, params.initialState, 1);
                idealVec = idealResult.blochVector;

                % Also compute and plot fidelity decay over rounds
                maxRounds = 10;
                decay = app.QecEngine.simulateDecay( ...
                    params.codeType, params.noiseModel, params.errorProb, ...
                    params.initialState, maxRounds);
                obj.plotDecay(decay);

                % Animate Bloch sphere
                for step = 1:nSteps
                    p = pRange(step);
                    result = app.QecEngine.simulate( ...
                        params.codeType, params.noiseModel, p, params.initialState, 1);
                    blochTrail(step, :) = result.blochVector;

                    obj.drawBlochSphereWithTrail(result.blochVector, idealVec, blochTrail(1:step, :));
                    drawnow();
                    pause(0.06);
                end

                app.logEvent('QEC', 'Animation complete');
            catch ME
                app.logEvent('ERROR', sprintf('Animation failed: %s', ME.message));
                uialert(app.UIFigure, ME.message, 'Animation Error');
            end
        end
    end

    methods (Access = private)

        function params = readSimParams(obj)
            app = obj.App;
            % Read from QEC Simulation screen controls
            params.codeType   = 'bitflip3';
            params.noiseModel = 'bitflip';
            params.errorProb  = 0.05;
            params.initialState = '0';
            params.nRounds    = 1;

            if ~isempty(app.QecCodeDropdown) && isvalid(app.QecCodeDropdown)
                params.codeType = char(app.QecCodeDropdown.Value);
            end
            if ~isempty(app.QecNoiseDropdown) && isvalid(app.QecNoiseDropdown)
                params.noiseModel = char(app.QecNoiseDropdown.Value);
            end
            if ~isempty(app.QecErrorProbSlider) && isvalid(app.QecErrorProbSlider)
                params.errorProb = app.QecErrorProbSlider.Value;
            end
            if ~isempty(app.QecInitialStateDropdown) && isvalid(app.QecInitialStateDropdown)
                stateVal = char(app.QecInitialStateDropdown.Value);
                if strcmp(stateVal, 'custom')
                    theta = app.QecThetaSpinner.Value;
                    phi   = app.QecPhiSpinner.Value;
                    params.initialState = sprintf('%.4f,%.4f', theta, phi);
                else
                    params.initialState = stateVal;
                end
            end
            if ~isempty(app.QecRoundsSpinner) && isvalid(app.QecRoundsSpinner)
                params.nRounds = round(app.QecRoundsSpinner.Value);
            end
        end

        function drawBlochSphere(obj, blochVec, idealVec)
            ax = obj.App.QecBlochAxes;
            cla(ax); hold(ax, 'on');
            obj.renderBlochBase(ax);

            % Ideal state (green)
            scatter3(ax, idealVec(1), idealVec(2), idealVec(3), 100, ...
                [0.2 0.75 0.3], 'filled', 'MarkerEdgeColor', [0.1 0.4 0.15], 'LineWidth', 1.5);

            % Noisy state Bloch vector (red arrow)
            rx = blochVec(1); ry = blochVec(2); rz = blochVec(3);
            quiver3(ax, 0, 0, 0, rx, ry, rz, 0, 'Color', [0.85 0.20 0.20], ...
                'LineWidth', 2.8, 'MaxHeadSize', 0.5);
            scatter3(ax, rx, ry, rz, 80, [0.85 0.20 0.20], 'filled', ...
                'MarkerEdgeColor', [0.5 0.1 0.1], 'LineWidth', 1.2);

            hold(ax, 'off');
            obj.styleBlochAxes(ax);
            mag = norm(blochVec);
            ax.Title.String = sprintf('Bloch Sphere — |r| = %.3f', mag);
        end

        function drawBlochSphereWithTrail(obj, currentVec, idealVec, trail)
            ax = obj.App.QecBlochAxes;
            cla(ax); hold(ax, 'on');
            obj.renderBlochBase(ax);

            % Ideal state (green)
            scatter3(ax, idealVec(1), idealVec(2), idealVec(3), 100, ...
                [0.2 0.75 0.3], 'filled', 'MarkerEdgeColor', [0.1 0.4 0.15], 'LineWidth', 1.5);

            % Trail with color gradient (green → red)
            nPts = size(trail, 1);
            if nPts > 1
                for k = 1:(nPts-1)
                    frac = (k-1) / max(1, nPts-2);
                    clr = [frac, 1-frac, 0.1];
                    plot3(ax, trail(k:k+1,1), trail(k:k+1,2), trail(k:k+1,3), ...
                        '-', 'Color', clr, 'LineWidth', 1.5);
                end
                % Trail points
                for k = 1:nPts
                    frac = (k-1) / max(1, nPts-1);
                    clr = [frac, 1-frac, 0.1];
                    scatter3(ax, trail(k,1), trail(k,2), trail(k,3), 20, clr, 'filled');
                end
            end

            % Current vector (red arrow)
            rx = currentVec(1); ry = currentVec(2); rz = currentVec(3);
            quiver3(ax, 0, 0, 0, rx, ry, rz, 0, 'Color', [0.85 0.20 0.20], ...
                'LineWidth', 2.8, 'MaxHeadSize', 0.5);
            scatter3(ax, rx, ry, rz, 100, [0.85 0.20 0.20], 'filled', ...
                'MarkerEdgeColor', [0.5 0.1 0.1], 'LineWidth', 1.5);

            hold(ax, 'off');
            obj.styleBlochAxes(ax);
            mag = norm(currentVec);
            ax.Title.String = sprintf('Bloch Sphere — |r| = %.3f  (p = %.3f)', mag, (nPts-1)*0.5/29);
        end

        function renderBlochBase(~, ax)
            % Wireframe sphere
            [sx, sy, sz] = sphere(30);
            mesh(ax, sx, sy, sz, 'FaceAlpha', 0.04, 'EdgeAlpha', 0.10, ...
                'EdgeColor', [0.7 0.7 0.7], 'FaceColor', [0.9 0.93 0.97]);

            % Great circles
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
        end

        function styleBlochAxes(~, ax)
            view(ax, 135, 25);
            axis(ax, 'equal');
            ax.XLim = [-1.6 1.6]; ax.YLim = [-1.6 1.6]; ax.ZLim = [-1.6 1.6];
            grid(ax, 'on'); ax.GridAlpha = 0.15;
            ax.XTick = []; ax.YTick = []; ax.ZTick = [];
            ax.Color = [1 1 1];
            ax.Title.FontSize = 12;
        end

        function drawLattice(obj, lattice, errorProb)
            ax = obj.App.QecLatticeAxes;
            d = lattice.distance;
            cla(ax); hold(ax, 'on');

            % Grid lines
            for row = 1:d
                plot(ax, [1 d], [row row], '-', 'Color', [0.8 0.82 0.85], 'LineWidth', 1);
            end
            for col = 1:d
                plot(ax, [col col], [1 d], '-', 'Color', [0.8 0.82 0.85], 'LineWidth', 1);
            end

            % X-stabilizer plaquettes
            for row = 1:(d-1)
                for col = 1:(d-1)
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

            % Z-stabilizer diamonds
            for row = 1:(d-1)
                for col = 1:(d-1)
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

            % Data qubits
            for i = 1:lattice.nData
                scatter(ax, lattice.dataX(i), lattice.dataY(i), 100, ...
                    [0.18 0.45 0.82], 'filled', ...
                    'MarkerEdgeColor', [0.08 0.25 0.52], 'LineWidth', 1.2);
            end

            % Simulate random errors for visualization
            nData = d^2;
            errors = rand(1, nData) < errorProb;
            errIdx = find(errors);
            for e = errIdx
                row = ceil(e / d);
                col = e - (row-1)*d;
                scatter(ax, col, row, 200, [0.85 0.15 0.15], 'x', 'LineWidth', 3);
            end

            hold(ax, 'off');
            ax.XLim = [0.3 d+0.7]; ax.YLim = [0.3 d+0.7];
            axis(ax, 'equal');
            grid(ax, 'on'); ax.GridAlpha = 0.1;
            ax.Title.String = sprintf('Surface Code d=%d — p=%.3f (%d errors)', d, errorProb, sum(errors));
            ax.Title.FontSize = 12;
            ax.XLabel.String = 'Column';
            ax.YLabel.String = 'Row';
        end

        function plotDecay(obj, decay)
            ax = obj.App.QecDecayAxes;
            cla(ax);
            plot(ax, decay.rounds, decay.fidelities, '-s', ...
                'Color', [0.10 0.54 0.36], 'LineWidth', 1.8, ...
                'MarkerSize', 5, 'MarkerFaceColor', [0.10 0.54 0.36]);
            ax.YLim = [0 1.05];
            obj.App.styleAxes(ax);
            ax.Title.String  = Labels.get('qec_viz_plot_decay_title', 'Fidelity vs Correction Round');
            ax.XLabel.String = Labels.get('qec_viz_plot_decay_x', 'Correction Round');
            ax.YLabel.String = Labels.get('qec_viz_plot_decay_y', 'Fidelity');
        end

        function plotErrorWeights(obj, dist)
            ax = obj.App.QecErrorWeightAxes;
            cla(ax);
            bar(ax, dist.weights, dist.probs, 'FaceColor', [0.85 0.33 0.10]);
            obj.App.styleAxes(ax);
            ax.Title.String  = Labels.get('qec_viz_plot_errweight_title', 'Error Weight Distribution');
            ax.XLabel.String = Labels.get('qec_viz_plot_errweight_x', 'Number of Errors');
            ax.YLabel.String = Labels.get('qec_viz_plot_errweight_y', 'Probability');
        end
    end
end
