classdef QecSimulationViewModel < handle
    % QecSimulationViewModel  Callback handlers for the QEC Simulation screen.

    properties (Access = private)
        App  % QTAUWorkbenchApp
    end

    methods
        function obj = QecSimulationViewModel(app)
            obj.App = app;
        end

        function onRunSimulation(obj)
            app = obj.App;
            app.logEvent('QEC', 'Running single QEC simulation');
            app.showLoading(Labels.get('qec_loading_simulation', 'Running QEC simulation...'));
            try
                params = obj.readParams();
                result = app.QecEngine.simulate( ...
                    params.codeType, params.noiseModel, params.errorProb, ...
                    params.initialState, params.nRounds);

                obj.plotSingleResult(result);
                obj.updateResultsTable(result);
                app.logEvent('QEC', sprintf('Simulation complete — Fidelity: %.4f', result.fidelity));
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
            try
                params = obj.readParams();
                pRange = linspace(0, 0.5, nPoints);
                sweep = app.QecEngine.sweepErrorRate( ...
                    params.codeType, params.noiseModel, pRange, ...
                    params.initialState, params.nRounds);

                obj.plotSweep(sweep);
                app.logEvent('QEC', sprintf('Sweep complete — %d data points', nPoints));
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('QEC sweep failed: %s', ME.message));
                app.showError('QEC Sweep', ME);
            end
        end

        function onCompareCodes(obj)
            app = obj.App;
            app.logEvent('QEC', 'Comparing all QEC codes');
            app.showLoading(Labels.get('qec_loading_compare', 'Comparing QEC codes...'));
            try
                params = obj.readParams();
                codes = {'bitflip3', 'phaseflip3', 'shor9', 'steane7', 'perfect5'};
                codeLabels = {'Bit-Flip(3)', 'Phase-Flip(3)', 'Shor(9)', 'Steane(7)', 'Perfect(5)'};
                nPoints = round(AppConfig.getDouble('qec_sweep_points', 50));
                pRange = linspace(0, 0.5, nPoints);

                results = app.QecEngine.compareCodes( ...
                    codes, params.noiseModel, pRange, params.initialState, params.nRounds);

                obj.plotComparison(results, codeLabels, pRange);
                app.logEvent('QEC', sprintf('Comparison complete — %d codes evaluated', numel(codes)));
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('QEC compare failed: %s', ME.message));
                app.showError('QEC Compare', ME);
            end
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
            barh(app.QecSuccessAxes, 1, successPct, 'FaceColor', [0.10 0.54 0.36]);
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
                '-o', 'Color', [0.18 0.45 0.82], 'LineWidth', 1.8, 'MarkerSize', 3);
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
            plot(app.QecFidelityAxes, pDemo, fDemo, '-o', 'Color', [0.18 0.45 0.82], ...
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
            barh(app.QecSuccessAxes, 1, 0.95, 'FaceColor', [0.10 0.54 0.36]);
            app.QecSuccessAxes.XLim = [0 1];
            app.QecSuccessAxes.YTickLabel = {'Success Rate'};
            app.styleAxes(app.QecSuccessAxes);
            app.QecSuccessAxes.Title.String = 'Correction Success Rate (demo)';
        end
    end
end
