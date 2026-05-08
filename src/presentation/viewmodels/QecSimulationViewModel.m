classdef QecSimulationViewModel < handle
    % QecSimulationViewModel  Callback handlers for the QEC Simulation screen.

    properties
        % Public so NavigationManager.isScreenFresh can read it. Stamped
        % in onEnter once the dropdowns have been populated.
        LastRefresh = []
    end

    properties (Access = private)
        App  % QTAUWorkbenchApp
        % Phase 1+2 caches:
        %   SelectedCircuit     last picked circuit struct (id, name, num_qubits, depth)
        %   SelectedBackend     last picked backend struct (name, num_qubits, gate_err mean,
        %                       t1_us mean, t2_us mean) — populated when calibration fetch lands
        %   CalibrationCache    containers.Map<backendName, raw calibration response> so
        %                       swapping back to a previously-selected backend doesn't refetch
        SelectedCircuit  = struct('id', '', 'name', '', 'num_qubits', 0, 'depth', 0);
        SelectedBackend  = struct('name', '', 'num_qubits', 0, 'gate_err', NaN, ...
                                  't1_us', NaN, 't2_us', NaN);
        CalibrationCache
    end

    methods
        function obj = QecSimulationViewModel(app)
            obj.App = app;
            obj.CalibrationCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        % ── Phase 1+2: selectors + per-backend calibration ──────────────
        function onEnter(obj)
            % Populate the Circuit + Backend dropdowns when the user
            % first lands on QEC Simulation. Both lists are async; the
            % VM doesn't block on them. NavigationManager calls this
            % via the auto-load path with the standard cache TTL gate.
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
                @(ME)   Logger.warn('QecSimulationViewModel', ...
                    'circuits load: %s', ME.message));
        end

        function loadBackends(obj)
            % Use the same enrichment chain as BackendsViewModel so the
            % dropdown carries real qubit counts. The bare
            % `listBackends(token, '')` server response only has
            % `name`+`username` (per ListBackendsResponse schema); the
            % enriched response only fires when a circuit_id is passed.
            % BackendsViewModel.fetchBackends already implements the
            % "pick any project circuit as the seed" fallback chain,
            % so reusing it avoids a second copy of that logic.
            app = obj.App;
            token      = app.State.authToken;
            backendSvc = app.BackendSvc;
            circuitSvc = app.CircuitSvc;
            AsyncRunner.run( ...
                @() BackendsViewModel.fetchBackends(backendSvc, circuitSvc, token, ''), ...
                @(data) obj.onBackendsLoaded(app, data), ...
                @(ME)   Logger.warn('QecSimulationViewModel', ...
                    'backends load: %s', ME.message));
        end

        function onCircuitsLoaded(obj, app, data)
            if isempty(app.QecCircuitDropdown) || ~isvalid(app.QecCircuitDropdown)
                return;
            end
            items = JsonHelper.extractListSafe(data, 'circuits');
            n = numel(items);
            if n == 0
                app.QecCircuitDropdown.Items     = {'(no circuits)'};
                app.QecCircuitDropdown.ItemsData = {''};
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
            app.QecCircuitDropdown.Items     = names;
            app.QecCircuitDropdown.ItemsData = ids;
        end

        function onBackendsLoaded(obj, app, data)
            if isempty(app.QecBackendDropdown) || ~isvalid(app.QecBackendDropdown)
                return;
            end
            items = JsonHelper.extractListSafe(data, 'backends');
            n = numel(items);
            if n == 0
                app.QecBackendDropdown.Items     = {'(no backends)'};
                app.QecBackendDropdown.ItemsData = {''};
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
            app.QecBackendDropdown.Items     = names;
            app.QecBackendDropdown.ItemsData = ids;
        end

        function onCircuitChanged(obj, circuitId)
            app = obj.App;
            if isempty(circuitId); return; end
            try
                ids = app.QecCircuitDropdown.ItemsData;
                k = find(strcmp(ids, char(circuitId)), 1);
                if ~isempty(k)
                    label = char(app.QecCircuitDropdown.Items{k});
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
            app.logEvent('QEC', sprintf('Circuit selected: %s (%dq)', ...
                obj.SelectedCircuit.name, nq));
        end

        function onBackendChanged(obj, backendName)
            app = obj.App;
            if isempty(backendName); return; end
            obj.SelectedBackend.name = char(backendName);
            if isKey(obj.CalibrationCache, char(backendName))
                obj.applyCalibration(obj.CalibrationCache(char(backendName)));
                return;
            end
            backendSvc = app.BackendSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() backendSvc.getCalibration(char(backendName), token), ...
                @(cal) obj.onCalibrationFetched(char(backendName), cal), ...
                @(ME)  Logger.warn('QecSimulationViewModel', ...
                    'getCalibration(%s): %s', char(backendName), ME.message));
        end

        function onCalibrationFetched(obj, backendName, cal)
            obj.CalibrationCache(char(backendName)) = cal;
            obj.applyCalibration(cal);
        end

        function applyCalibration(obj, cal)
            % Compute aggregate stats and seed the Error Probability
            % slider. Per-qubit detail is consumed later in
            % buildErrorProbVec when Run Simulation fires.
            app = obj.App;
            qubits = JsonHelper.extractListSafe(cal, 'qubits');
            n = numel(qubits);
            if n == 0
                obj.SelectedBackend.gate_err = NaN;
                return;
            end
            geSum = 0; t1Sum = 0; t2Sum = 0; geN = 0; t1N = 0; t2N = 0;
            for i = 1:n
                if iscell(qubits); q = qubits{i}; else; q = qubits(i); end
                ge = JsonHelper.toDouble(JsonHelper.pick(q, ...
                    {'gate_error_2q','gate_error_cx','gate_error','gate_error_1q'}));
                t1 = JsonHelper.toDouble(JsonHelper.pick(q, {'t1_us','t1','T1'}));
                t2 = JsonHelper.toDouble(JsonHelper.pick(q, {'t2_us','t2','T2'}));
                if isfinite(ge) && ge > 0; geSum = geSum + ge; geN = geN + 1; end
                if isfinite(t1) && t1 > 0; t1Sum = t1Sum + t1; t1N = t1N + 1; end
                if isfinite(t2) && t2 > 0; t2Sum = t2Sum + t2; t2N = t2N + 1; end
            end
            geMean = NaN; if geN > 0; geMean = geSum / geN; end
            t1Mean = NaN; if t1N > 0; t1Mean = t1Sum / t1N; end
            t2Mean = NaN; if t2N > 0; t2Mean = t2Sum / t2N; end
            obj.SelectedBackend.num_qubits = n;
            obj.SelectedBackend.gate_err   = geMean;
            obj.SelectedBackend.t1_us      = t1Mean;
            obj.SelectedBackend.t2_us      = t2Mean;
            try
                if isfinite(geMean)
                    seed = max(0, min(0.5, geMean));
                    app.QecErrorProbSlider.Value = seed;
                    app.logEvent('QEC', sprintf( ...
                        'Auto-seeded p=%.4f from %s mean gate error', ...
                        seed, obj.SelectedBackend.name));
                end
            catch
            end
        end

        function vec = buildErrorProbVec(obj, nQubits)
            % Build a per-qubit error-rate vector from the cached
            % calibration of the SelectedBackend, sliced to the
            % SelectedCircuit's qubit count (or to nQubits when no
            % circuit was picked). Returns [] when no backend is
            % selected — the engine will fall back to the scalar
            % Error Probability slider value.
            vec = [];
            if isempty(obj.SelectedBackend.name); return; end
            if ~isKey(obj.CalibrationCache, obj.SelectedBackend.name); return; end
            cal = obj.CalibrationCache(obj.SelectedBackend.name);
            qubits = JsonHelper.extractListSafe(cal, 'qubits');
            m = numel(qubits);
            if m == 0; return; end
            sliceN = nQubits;
            if obj.SelectedCircuit.num_qubits > 0
                sliceN = obj.SelectedCircuit.num_qubits;
            end
            sliceN = min(sliceN, m);
            v = zeros(1, sliceN);
            for i = 1:sliceN
                if iscell(qubits); q = qubits{i}; else; q = qubits(i); end
                ge = JsonHelper.toDouble(JsonHelper.pick(q, ...
                    {'gate_error_2q','gate_error_cx','gate_error','gate_error_1q'}));
                if ~isfinite(ge) || ge <= 0; ge = 0.01; end
                v(i) = ge;
            end
            vec = v;
        end

        function onRunSimulation(obj)
            app = obj.App;
            app.logEvent('QEC', 'Running single QEC simulation');
            app.showLoading(Labels.get('qec_loading_simulation', 'Running QEC simulation...'));
            try
                params = obj.readParams();
                % Phase 2: thread the per-qubit error vector into the
                % engine when a backend is selected. Engine falls back
                % to the scalar params.errorProb when errorProbVec is
                % empty (uniform behaviour preserved). Mirrors the
                % qubit count map in QecEngineService.qubitCount;
                % covers the codes the dropdown exposes.
                switch lower(char(params.codeType))
                    case 'bitflip3';     nQubits = 3;
                    case 'phaseflip3';   nQubits = 3;
                    case 'shor9';        nQubits = 9;
                    case 'steane7';      nQubits = 7;
                    case 'perfect5';     nQubits = 5;
                    case 'surface';      nQubits = 9;
                    otherwise;           nQubits = 5;
                end
                errorProbVec = obj.buildErrorProbVec(nQubits);
                result = app.QecEngine.simulate( ...
                    params.codeType, params.noiseModel, params.errorProb, ...
                    params.initialState, params.nRounds, errorProbVec);

                obj.plotSingleResult(result);
                obj.updateResultsTable(result);
                app.logEvent('QEC', sprintf('Simulation complete — Fidelity: %.4f', result.fidelity));
                app.State.logActivity(sprintf('QEC simulation — fidelity: %.4f', result.fidelity), 'Success');
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('QEC simulation failed: %s', ME.message));
                app.showError('QEC Simulation', ME);
            end
        end

        function onSweepErrorRates(obj)
            app = obj.App;
            nPoints = round(AppConfig.getDouble('qec_sweep_points', 50));
            app.logEvent('QEC', sprintf('Sweeping error rates (%d points)', nPoints));
            app.showLoading(Labels.get('qec_loading_sweep', 'Sweeping error rates...'));

            % Capture parameters on the UI thread before dispatching —
            % the background task can't touch app.* safely.
            params = obj.readParams();
            pRange = linspace(0, 0.5, nPoints);
            engine = app.QecEngine;

            AsyncRunner.run( ...
                @() engine.sweepErrorRate(params.codeType, params.noiseModel, pRange, ...
                                          params.initialState, params.nRounds), ...
                @(sweep) obj.onSweepComplete(sweep, nPoints), ...
                @(ME)    obj.onSweepError(ME));
        end

        function onCompareCodes(obj)
            app = obj.App;
            % Phase A+B+C: Compare formerly ran (5 codes × 20 p × 100
            % MC trials = 10 000 simulate iterations). Density-matrix
            % simulation is O(4^N) per gate-application, so Shor(9)
            % alone took ~16 minutes for the full sweep. The new path:
            %
            %   B  Code list comes from AppConfig (`qec_compare_codes`)
            %      so operators can opt-out of heavy codes via the
            %      properties file without UI changes. Default is all
            %      five since C makes them all instant.
            %   C  Use compareCodesAnalytical: closed-form binomial
            %      decoder-success formulas. ~1 ms total instead of 16
            %      minutes. Curves match the MC simulator's leading-
            %      order behaviour for matched noise/code pairs.
            %   A  qec_compare_trials config is declared (default 20)
            %      for any future MC-mode toggle that wants the old
            %      slow-but-statistically-thicker behaviour.
            app.logEvent('QEC', 'Comparing QEC codes (analytical)');
            app.showLoading(Labels.get('qec_loading_compare', 'Comparing QEC codes...'));

            params  = obj.readParams();
            codes   = QecSimulationViewModel.parseCompareCodes(AppConfig.get( ...
                'qec_compare_codes', 'bitflip3,phaseflip3,shor9,steane7,perfect5'));
            codeLabels = QecSimulationViewModel.compareCodeLabels(codes);
            nPoints = round(AppConfig.getDouble('qec_compare_points', 20));
            pRange  = linspace(0, 0.5, nPoints);
            engine  = app.QecEngine;

            AsyncRunner.run( ...
                @() engine.compareCodesAnalytical(codes, params.noiseModel, pRange), ...
                @(results) obj.onCompareComplete(results, codeLabels, pRange, codes), ...
                @(ME)      obj.onCompareError(ME));
        end

        function onSweepComplete(obj, sweep, nPoints)
            app = obj.App;
            try
                obj.plotSweep(sweep);
                app.logEvent('QEC', sprintf('Sweep complete — %d data points', nPoints));
            catch ME
                app.logEvent('ERROR', sprintf('Sweep render failed: %s', ME.message));
            end
            app.hideLoading();
        end

        function onSweepError(obj, ME)
            app = obj.App;
            app.hideLoading();
            app.logEvent('ERROR', sprintf('QEC sweep failed: %s', ME.message));
            app.showError('QEC Sweep', ME);
        end

        function onCompareComplete(obj, results, codeLabels, pRange, codes)
            app = obj.App;
            try
                obj.plotComparison(results, codeLabels, pRange);
                app.logEvent('QEC', sprintf('Comparison complete — %d codes evaluated', numel(codes)));
                app.State.logActivity(sprintf('QEC compare — %d codes', numel(codes)), 'Success');
            catch ME
                app.logEvent('ERROR', sprintf('Compare render failed: %s', ME.message));
            end
            app.hideLoading();
        end

        function onCompareError(obj, ME)
            app = obj.App;
            app.hideLoading();
            app.logEvent('ERROR', sprintf('QEC compare failed: %s', ME.message));
            app.showError('QEC Compare', ME);
        end

        function onClear(obj)
            app = obj.App;
            obj.plotFidelityDemo();
            obj.plotSyndromeDemo();
            obj.plotSuccessDemo();
            app.QecResultsTable.Data = {'Bit-Flip(3)', 'Bit-Flip', '0.05', '0.987', '97.0%', '[0.00, 0.00, 0.97]'};
            app.logEvent('QEC', 'QEC Simulation panels cleared to demo');
        end

        function onCodeTypeChanged(obj)
            app = obj.App;
            codeType = app.QecCodeDropdown.Value;
            isSurface = strcmp(codeType, 'surface') || strcmp(codeType, 'repetition');
            if isSurface
                app.QecDistanceLabel.Visible   = 'on';
                app.QecDistanceSpinner.Visible = 'on';
            else
                app.QecDistanceLabel.Visible   = 'off';
                app.QecDistanceSpinner.Visible = 'off';
            end
        end

        function onInitialStateChanged(obj)
            app = obj.App;
            isCustom = strcmp(app.QecInitialStateDropdown.Value, 'custom');
            vis = 'off'; if isCustom; vis = 'on'; end
            app.QecThetaLabel.Visible   = vis;
            app.QecThetaSpinner.Visible = vis;
            app.QecPhiLabel.Visible     = vis;
            app.QecPhiSpinner.Visible   = vis;
        end
    end

    methods (Static, Access = private)
        function codes = parseCompareCodes(csvStr)
            % Phase B: parse a comma-separated list of code IDs from
            % the qec_compare_codes config. Trims whitespace, drops
            % empties, lowercases for canonicalisation.
            csvStr = char(string(csvStr));
            parts = strsplit(csvStr, ',');
            codes = {};
            for i = 1:numel(parts)
                p = strtrim(parts{i});
                if isempty(p); continue; end
                codes{end+1} = lower(p); %#ok<AGROW>
            end
            % Fallback to the canonical 5 if the operator misconfigured.
            if isempty(codes)
                codes = {'bitflip3','phaseflip3','shor9','steane7','perfect5'};
            end
        end

        function labels = compareCodeLabels(codes)
            % Map code IDs to friendly display labels for the legend.
            labels = cell(1, numel(codes));
            for i = 1:numel(codes)
                switch lower(char(codes{i}))
                    case 'bitflip3';   labels{i} = 'Bit-Flip(3)';
                    case 'phaseflip3'; labels{i} = 'Phase-Flip(3)';
                    case 'shor9';      labels{i} = 'Shor(9)';
                    case 'steane7';    labels{i} = 'Steane(7)';
                    case 'perfect5';   labels{i} = 'Perfect(5)';
                    case 'surface';    labels{i} = 'Surface(d=3)';
                    otherwise;         labels{i} = char(codes{i});
                end
            end
        end
    end

    methods (Access = private)

        function params = readParams(obj)
            app = obj.App;
            params.codeType   = char(app.QecCodeDropdown.Value);
            params.noiseModel = char(app.QecNoiseDropdown.Value);
            params.errorProb  = app.QecErrorProbSlider.Value;
            params.nRounds    = round(app.QecRoundsSpinner.Value);
            params.nTrials    = round(app.QecTrialsSpinner.Value);

            stateVal = char(app.QecInitialStateDropdown.Value);
            if strcmp(stateVal, 'custom')
                theta = app.QecThetaSpinner.Value;
                phi   = app.QecPhiSpinner.Value;
                params.initialState = sprintf('%.4f,%.4f', theta, phi);
            else
                params.initialState = stateVal;
            end
        end

        function plotSingleResult(obj, result)
            app = obj.App;

            % Syndrome histogram
            cla(app.QecSyndromeAxes);
            synMap = result.syndromeHistogram;
            keys = synMap.keys; vals = cell2mat(synMap.values);
            if ~isempty(keys)
                bar(app.QecSyndromeAxes, 1:numel(keys), vals, 'FaceColor', [0.56 0.27 0.68]);
                app.QecSyndromeAxes.XTickLabel = keys;
                app.QecSyndromeAxes.XTickLabelRotation = 45;
            end
            app.styleAxes(app.QecSyndromeAxes);
            app.QecSyndromeAxes.Title.String  = Labels.get('qec_sim_plot_syndrome_title', 'Syndrome Measurement Distribution');
            app.QecSyndromeAxes.XLabel.String = Labels.get('qec_sim_plot_syndrome_x', 'Syndrome Pattern');
            app.QecSyndromeAxes.YLabel.String = Labels.get('qec_sim_plot_syndrome_y', 'Frequency');

            % Success rate bar
            cla(app.QecSuccessAxes);
            successPct = result.correctionSuccess;
            barh(app.QecSuccessAxes, 1, successPct, 'FaceColor', Theme.COLOR_SUCCESS);
            app.QecSuccessAxes.XLim = [0 1];
            app.QecSuccessAxes.YTickLabel = {sprintf('%.1f%%', successPct*100)};
            app.styleAxes(app.QecSuccessAxes);
            app.QecSuccessAxes.Title.String = sprintf('Correction Success Rate: %.1f%%', successPct*100);

            % Update fidelity plot with single point highlighted
            hold(app.QecFidelityAxes, 'on');
            scatter(app.QecFidelityAxes, result.errorProb, result.fidelity, 100, ...
                [0.85 0.20 0.20], 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
            hold(app.QecFidelityAxes, 'off');
            app.styleAxes(app.QecFidelityAxes);
        end

        function updateResultsTable(obj, result)
            app = obj.App;
            bv = result.blochVector;
            row = {result.codeType, result.noiseModel, ...
                   sprintf('%.3f', result.errorProb), ...
                   sprintf('%.4f', result.fidelity), ...
                   sprintf('%.1f%%', result.correctionSuccess*100), ...
                   sprintf('[%.2f, %.2f, %.2f]', bv(1), bv(2), bv(3))};

            existingData = app.QecResultsTable.Data;
            if iscell(existingData) && size(existingData, 1) >= 1
                % Check if first row is demo data
                if strcmp(existingData{1,1}, 'Bit-Flip(3)') && strcmp(existingData{1,3}, '0.05')
                    app.QecResultsTable.Data = row;
                    return;
                end
                app.QecResultsTable.Data = [existingData; row];
            else
                app.QecResultsTable.Data = row;
            end
        end

        function plotSweep(obj, sweep)
            app = obj.App;
            cla(app.QecFidelityAxes);
            plot(app.QecFidelityAxes, sweep.errorRates, sweep.fidelities, ...
                '-o', 'Color', Theme.COLOR_PRIMARY, 'LineWidth', 1.8, 'MarkerSize', 3);
            app.styleAxes(app.QecFidelityAxes);
            app.QecFidelityAxes.Title.String  = Labels.get('qec_sim_plot_fidelity_title', 'Fidelity vs Physical Error Rate');
            app.QecFidelityAxes.XLabel.String = Labels.get('qec_sim_plot_fidelity_x', 'Physical Error Probability (p)');
            app.QecFidelityAxes.YLabel.String = Labels.get('qec_sim_plot_fidelity_y', 'Logical Qubit Fidelity');
            app.QecFidelityAxes.YLim = [0 1.05];
        end

        function plotComparison(obj, results, codeLabels, pRange)
            app = obj.App;
            cla(app.QecFidelityAxes);
            colors = [
                0.18 0.45 0.82;
                0.85 0.33 0.10;
                0.47 0.67 0.19;
                0.56 0.27 0.68;
                0.93 0.69 0.13];
            hold(app.QecFidelityAxes, 'on');
            for c = 1:numel(results)
                sweep = results{c};
                cidx = mod(c-1, size(colors,1)) + 1;
                plot(app.QecFidelityAxes, sweep.errorRates, sweep.fidelities, ...
                    '-o', 'Color', colors(cidx,:), 'LineWidth', 1.8, 'MarkerSize', 2, ...
                    'DisplayName', codeLabels{c});
            end
            hold(app.QecFidelityAxes, 'off');
            legend(app.QecFidelityAxes, 'Location', 'southwest', 'FontSize', 10);
            app.styleAxes(app.QecFidelityAxes);
            app.QecFidelityAxes.Title.String  = 'QEC Code Comparison';
            app.QecFidelityAxes.XLabel.String = Labels.get('qec_sim_plot_fidelity_x', 'Physical Error Probability (p)');
            app.QecFidelityAxes.YLabel.String = Labels.get('qec_sim_plot_fidelity_y', 'Logical Qubit Fidelity');
            app.QecFidelityAxes.YLim = [0 1.05];
        end

        function plotFidelityDemo(obj)
            app = obj.App;
            cla(app.QecFidelityAxes);
            pDemo = linspace(0, 0.5, 30);
            fDemo = 1 - 1.5*pDemo.^2;
            plot(app.QecFidelityAxes, pDemo, fDemo, '-o', 'Color', Theme.COLOR_PRIMARY, ...
                'LineWidth', 1.6, 'MarkerSize', 3);
            app.styleAxes(app.QecFidelityAxes);
            app.QecFidelityAxes.Title.String = 'Fidelity vs Physical Error Rate (demo)';
            app.QecFidelityAxes.XLabel.String = 'Physical Error Probability (p)';
            app.QecFidelityAxes.YLabel.String = 'Logical Qubit Fidelity';
        end

        function plotSyndromeDemo(obj)
            app = obj.App;
            cla(app.QecSyndromeAxes);
            bar(app.QecSyndromeAxes, 1:4, [65 20 10 5], 'FaceColor', [0.56 0.27 0.68]);
            app.styleAxes(app.QecSyndromeAxes);
            app.QecSyndromeAxes.Title.String = 'Syndrome Measurement Distribution (demo)';
            app.QecSyndromeAxes.XLabel.String = 'Syndrome Pattern';
            app.QecSyndromeAxes.YLabel.String = 'Frequency';
        end

        function plotSuccessDemo(obj)
            app = obj.App;
            cla(app.QecSuccessAxes);
            barh(app.QecSuccessAxes, 1, 0.95, 'FaceColor', Theme.COLOR_SUCCESS);
            app.QecSuccessAxes.XLim = [0 1];
            app.QecSuccessAxes.YTickLabel = {'Success Rate'};
            app.styleAxes(app.QecSuccessAxes);
            app.QecSuccessAxes.Title.String = 'Correction Success Rate (demo)';
        end
    end
end
