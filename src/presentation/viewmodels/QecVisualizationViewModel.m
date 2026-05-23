classdef QecVisualizationViewModel < handle
    % QecVisualizationViewModel  Callback handlers for the QEC Visualization screen.

    properties
        % Public so NavigationManager.isScreenFresh can read it.
        LastRefresh = []
    end

    properties (Access = private)
        App  % QTAUWorkbenchApp
        % Phase 1+2: same selector pattern as QecSimulationViewModel —
        % independent state per the operator spec ("Circuit selector
        % default: be independent" — does not sync with QEC Simulation
        % or with app.State.selectedCircuitId).
        SelectedCircuit = struct('id', '', 'name', '', 'num_qubits', 0);
        SelectedBackend = struct('name', '', 'num_qubits', 0);
        % Bloch decay animation runs via a fixedSpacing timer instead of
        % a blocking for/pause loop so the UI stays responsive between
        % ticks (nav clicks, slider drags, window close all fire while
        % the animation runs).
        AnimationTimer = []
        AnimationState = struct()
    end

    methods
        function obj = QecVisualizationViewModel(app)
            obj.App = app;
        end

        % ── Phase 1+2: selectors + lattice scaling ─────────────────────
        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            obj.loadCircuits();
            obj.loadBackends();
            obj.LastRefresh = tic;
        end

        function loadCircuits(obj)
            app = obj.App;
            token = app.State.authToken;
            circSvc = app.CircuitSvc;
            AsyncRunner.run( ...
                @() circSvc.listCircuits(token), ...
                @(data) obj.onCircuitsLoaded(app, data), ...
                @(ME)   Logger.warn('QecVisualizationViewModel', ...
                    'circuits load: %s', ME.message));
        end

        function loadBackends(obj)
            % Use BackendsViewModel.fetchBackends so the dropdown
            % carries real qubit counts. See identical comment in
            % QecSimulationViewModel.loadBackends — bare listBackends
            % returns only `name`+`username`; enrichment requires a
            % circuit_id seed which fetchBackends supplies via its
            % "any project circuit" fallback chain.
            app = obj.App;
            token      = app.State.authToken;
            backendSvc = app.BackendSvc;
            circuitSvc = app.CircuitSvc;
            AsyncRunner.run( ...
                @() BackendsViewModel.fetchBackends(backendSvc, circuitSvc, token, ''), ...
                @(data) obj.onBackendsLoaded(app, data), ...
                @(ME)   Logger.warn('QecVisualizationViewModel', ...
                    'backends load: %s', ME.message));
        end

        function onCircuitsLoaded(obj, app, data)
            if isempty(app.QecVizCircuitDropdown) || ~isvalid(app.QecVizCircuitDropdown)
                return;
            end
            items = JsonHelper.extractListSafe(data, 'circuits');
            n = numel(items);
            if n == 0
                app.QecVizCircuitDropdown.Items     = {'(no circuits)'};
                app.QecVizCircuitDropdown.ItemsData = {''};
                return;
            end
            names = cell(1, n); ids = cell(1, n);
            for i = 1:n
                if iscell(items); it = items{i}; else; it = items(i); end
                ids{i}  = char(JsonHelper.pick(it, {'circuit_id','id'}));
                nm      = char(JsonHelper.pick(it, {'name','circuit_name'}));
                nq      = JsonHelper.toDouble(JsonHelper.pick(it, {'num_qubits','n_qubits'}));
                if isnan(nq); nq = 0; end
                if isempty(nm); nm = ids{i}; end
                names{i} = sprintf('%s · %dq', nm, int32(nq));
            end
            app.QecVizCircuitDropdown.Items     = names;
            app.QecVizCircuitDropdown.ItemsData = ids;
        end

        function onBackendsLoaded(obj, app, data)
            if isempty(app.QecVizBackendDropdown) || ~isvalid(app.QecVizBackendDropdown)
                return;
            end
            items = JsonHelper.extractListSafe(data, 'backends');
            n = numel(items);
            if n == 0
                app.QecVizBackendDropdown.Items     = {'(no backends)'};
                app.QecVizBackendDropdown.ItemsData = {''};
                return;
            end
            names = cell(1, n); ids = cell(1, n);
            for i = 1:n
                if iscell(items); it = items{i}; else; it = items(i); end
                bn   = char(JsonHelper.pick(it, {'name','backend_name'}));
                nq   = JsonHelper.toDouble(JsonHelper.pick(it, {'num_qubits','qubits','n_qubits'}));
                if isnan(nq); nq = 0; end
                ids{i}   = bn;
                names{i} = sprintf('%s · %dq', bn, int32(nq));
            end
            app.QecVizBackendDropdown.Items     = names;
            app.QecVizBackendDropdown.ItemsData = ids;
        end

        function onCircuitChanged(obj, circuitId)
            app = obj.App;
            if isempty(circuitId); return; end
            try
                ids = app.QecVizCircuitDropdown.ItemsData;
                k = find(strcmp(ids, char(circuitId)), 1);
                if ~isempty(k)
                    label = char(app.QecVizCircuitDropdown.Items{k});
                else
                    label = char(circuitId);
                end
            catch
                label = char(circuitId);
            end
            tok = regexp(label, '·\s*(\d+)q', 'tokens', 'once');
            nq = 0;
            if ~isempty(tok); nq = str2double(tok{1}); end
            obj.SelectedCircuit.id         = char(circuitId);
            obj.SelectedCircuit.name       = strtrim(regexprep(label, '·\s*\d+q.*$', ''));
            obj.SelectedCircuit.num_qubits = nq;
            app.logEvent('QEC', sprintf('Viz circuit selected: %s (%dq)', ...
                obj.SelectedCircuit.name, nq));
        end

        function onBackendChanged(obj, backendName)
            app = obj.App;
            if isempty(backendName); return; end
            try
                ids = app.QecVizBackendDropdown.ItemsData;
                k = find(strcmp(ids, char(backendName)), 1);
                if ~isempty(k)
                    label = char(app.QecVizBackendDropdown.Items{k});
                else
                    label = char(backendName);
                end
            catch
                label = char(backendName);
            end
            tok = regexp(label, '·\s*(\d+)q', 'tokens', 'once');
            nq = 0;
            if ~isempty(tok); nq = str2double(tok{1}); end
            obj.SelectedBackend.name       = char(backendName);
            obj.SelectedBackend.num_qubits = nq;
            d = QecVisualizationViewModel.qubitCountToDistance(nq);
            app.logEvent('QEC', sprintf('Viz backend selected: %s (%dq) → lattice d=%d', ...
                char(backendName), nq, d));
            % Auto-redraw the lattice with the scaled distance so the
            % user sees immediate effect of the backend selection.
            try
                obj.onRefreshLattice();
            catch ME
                Logger.debug('QecVisualizationViewModel', ...
                    'auto-redraw lattice on backend change: %s', ME.message);
            end
        end
    end

    methods (Static)
        function d = qubitCountToDistance(nQubits)
            % Map a backend's physical qubit count to a representative
            % surface code distance d. Distances are odd to admit a
            % unique majority decoder (d=2k+1 corrects k errors).
            % A surface code at distance d uses ~2d²−1 physical qubits
            % (d² data + (d²−1) measure). We pick the largest odd d
            % that fits — matches the framing in real Qiskit / Cirq
            % tooling ("what's the most this device could host?").
            %     16 → 3   (uses ~17 qubits)
            %     27 → 5   (uses ~49 qubits, fits with router ancillas)
            %     65 → 7   (uses ~97 qubits — borderline)
            %    127 → 9
            %    156 → 11
            %    433+ → 13 or larger
            if isempty(nQubits) || ~isfinite(nQubits) || nQubits <= 0
                d = 3; return;
            end
            n = double(nQubits);
            if     n >= 433; d = 13;
            elseif n >= 156; d = 11;
            elseif n >= 127; d = 9;
            elseif n >= 65;  d = 7;
            elseif n >= 27;  d = 5;
            else;            d = 3;
            end
        end
    end

    methods
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
                app.showError('Bloch Sphere', ME);
            end
        end

        function onRefreshLattice(obj)
            app = obj.App;
            app.logEvent('QEC', 'Refreshing surface code lattice');
            try
                distance = AppConfig.getDouble('qec_viz_default_distance', 3);
                % Read distance from QEC Simulation screen if available
                if ~isempty(app.QecDistanceSpinner) && isvalid(app.QecDistanceSpinner)
                    distance = round(app.QecDistanceSpinner.Value);
                end
                % Phase 1+2: backend selection on this screen overrides
                % the distance so the lattice reflects the device's
                % capacity (16q→3, 27q→5, 65q→7, 127q→9, 156q→11). The
                % manual spinner from QEC Simulation still wins if the
                % user explicitly picked a different d there.
                if obj.SelectedBackend.num_qubits > 0
                    distance = QecVisualizationViewModel.qubitCountToDistance( ...
                        obj.SelectedBackend.num_qubits);
                end
                errorProb = AppConfig.getDouble('qec_viz_default_error_prob', 0.05);
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
                app.showError('Surface Code Lattice', ME);
            end
        end

        function onAnimateDecay(obj)
            app = obj.App;
            app.logEvent('QEC', 'Animating Bloch vector decay');
            try
                obj.stopAnimationTimer();

                params = obj.readSimParams();
                nSteps = AppConfig.getDouble('qec_viz_decay_steps', 30);
                pRange = linspace(0, AppConfig.getDouble('qec_viz_decay_max_prob', 0.5), nSteps);

                idealResult = app.QecEngine.simulate( ...
                    params.codeType, params.noiseModel, 0, params.initialState, 1);

                maxRounds = AppConfig.getDouble('qec_viz_max_rounds', 10);
                decay = app.QecEngine.simulateDecay( ...
                    params.codeType, params.noiseModel, params.errorProb, ...
                    params.initialState, maxRounds);
                obj.plotDecay(decay);

                obj.AnimationState = struct( ...
                    'step',       0, ...
                    'nSteps',     nSteps, ...
                    'pRange',     pRange, ...
                    'blochTrail', zeros(nSteps, 3), ...
                    'idealVec',   idealResult.blochVector, ...
                    'params',     params);

                obj.AnimationTimer = timer( ...
                    'ExecutionMode',   'fixedSpacing', ...
                    'Period',          0.06, ...
                    'TasksToExecute',  nSteps, ...
                    'TimerFcn',        @(src,~) obj.onAnimationTick(src), ...
                    'StopFcn',         @(src,~) obj.onAnimationStop(src), ...
                    'ErrorFcn',        @(src,~) obj.onAnimationStop(src));
                start(obj.AnimationTimer);
            catch ME
                app.logEvent('ERROR', sprintf('Animation failed: %s', ME.message));
                app.showError('Bloch Animation', ME);
            end
        end

        function onAnimationTick(obj, src)
            app = obj.App;
            if isempty(app) || ~isvalid(app) || ~isvalid(app.UIFigure)
                stop(src); return;
            end
            try
                st = obj.AnimationState;
                st.step = st.step + 1;
                p = st.pRange(st.step);
                result = app.QecEngine.simulate( ...
                    st.params.codeType, st.params.noiseModel, p, ...
                    st.params.initialState, 1);
                st.blochTrail(st.step, :) = result.blochVector;
                obj.drawBlochSphereWithTrail(result.blochVector, st.idealVec, ...
                    st.blochTrail(1:st.step, :));
                obj.AnimationState = st;
            catch ME
                Logger.warn('QecVisualizationViewModel', 'tick failed: %s', ME.message);
                stop(src);
            end
        end

        function onAnimationStop(obj, src)
            try; if isvalid(src); delete(src); end; catch; end
            obj.AnimationTimer = [];
            app = obj.App;
            if isempty(app) || ~isvalid(app); return; end
            st = obj.AnimationState;
            if isfield(st, 'step') && isfield(st, 'nSteps') && st.step >= st.nSteps
                app.logEvent('QEC', 'Animation complete');
                try app.State.logActivity('QEC visualize — Bloch decay animation', 'Success'); catch; end
            end
        end

        function stopAnimationTimer(obj)
            if ~isempty(obj.AnimationTimer) && isvalid(obj.AnimationTimer)
                try; stop(obj.AnimationTimer); catch; end
                try; delete(obj.AnimationTimer); catch; end
            end
            obj.AnimationTimer = [];
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
            ax = obj.App.ensureLazyAxes('QecBlochAxes', 'QecBlochGrid', 'QecBlochPlaceholder');
            if isempty(ax); return; end
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
            ax = obj.App.ensureLazyAxes('QecBlochAxes', 'QecBlochGrid', 'QecBlochPlaceholder');
            if isempty(ax); return; end
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
            ax = obj.App.ensureLazyAxes('QecLatticeAxes', 'QecLatticeGrid', 'QecLatticePlaceholder');
            if isempty(ax); return; end
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
                    Theme.COLOR_PRIMARY, 'filled', ...
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
            ax = obj.App.ensureLazyAxes('QecDecayAxes', 'QecDecayGrid', 'QecDecayPlaceholder');
            if isempty(ax); return; end
            cla(ax);
            plot(ax, decay.rounds, decay.fidelities, '-s', ...
                'Color', Theme.COLOR_SUCCESS, 'LineWidth', 1.8, ...
                'MarkerSize', 5, 'MarkerFaceColor', Theme.COLOR_SUCCESS);
            ax.YLim = [0 1.05];
            obj.App.styleAxes(ax);
            ax.Title.String  = Labels.get('qec_viz_plot_decay_title', 'Fidelity vs Correction Round');
            ax.XLabel.String = Labels.get('qec_viz_plot_decay_x', 'Correction Round');
            ax.YLabel.String = Labels.get('qec_viz_plot_decay_y', 'Fidelity');
        end

        function plotErrorWeights(obj, dist)
            ax = obj.App.ensureLazyAxes('QecErrorWeightAxes', 'QecErrorWeightGrid', 'QecErrorWeightPlaceholder');
            if isempty(ax); return; end
            cla(ax);
            bar(ax, dist.weights, dist.probs, 'FaceColor', [0.85 0.33 0.10]);
            obj.App.styleAxes(ax);
            ax.Title.String  = Labels.get('qec_viz_plot_errweight_title', 'Error Weight Distribution');
            ax.XLabel.String = Labels.get('qec_viz_plot_errweight_x', 'Number of Errors');
            ax.YLabel.String = Labels.get('qec_viz_plot_errweight_y', 'Probability');
        end
    end
end
