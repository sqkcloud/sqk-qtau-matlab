classdef test_AnalysisViewModel < matlab.unittest.TestCase
    % test_AnalysisViewModel  Smoke tests for AnalysisViewModel rendering.
    %
    %   First viewmodel test in the repo. The QV chart had a silent
    %   regression (hardcoded demo backdrop + random fidelity → chart
    %   never changed when the circuit changed). These tests guard
    %   against recurrence by asserting the deterministic fidelity
    %   model produces different output for different circuits and
    %   the info panel reflects the active circuit's metrics.
    %
    %   Uses a minimal stub "app" so the viewmodel can be exercised
    %   without constructing the full QTAUWorkbenchApp. Headless
    %   uifigure is created once per test class and torn down at the
    %   end.
    %
    %   Run from the project root:
    %     >> runtests('tests/test_AnalysisViewModel')

    properties
        Fig
    end

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'http'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure'));
            addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
            addpath(fullfile(projectRoot, 'src', 'presentation', 'app'));
            addpath(fullfile(projectRoot, 'src', 'presentation', 'viewmodels'));
            addpath(fullfile(projectRoot, 'tests'));
        end

        function createHeadlessFigure(testCase)
            testCase.Fig = uifigure('Visible', 'off');
        end
    end

    methods (TestClassTeardown)
        function closeHeadlessFigure(testCase)
            if ~isempty(testCase.Fig) && isvalid(testCase.Fig)
                delete(testCase.Fig);
            end
        end
    end

    methods (Test)

        function testRenderComplexityLandscapePopulatesInfoLabel(testCase)
            % The info panel must contain the circuit name and its
            % extracted depth + width after rendering.
            [vm, app] = testCase.makeVm();

            data = struct( ...
                'circuit_name', 'bell_pair_test', ...
                'depth', 5, ...
                'num_qubits', 2, ...
                'gate_counts', struct('h', 1, 'cx', 1, 'measure', 2));

            vm.renderComplexityLandscape(data);

            txt = testCase.joinText(app.QVInfoLabel.Text);
            testCase.verifyTrue(contains(txt, 'bell_pair_test'), ...
                'Info label should contain the circuit name');
            testCase.verifyTrue(contains(txt, 'depth: 5'), ...
                'Info label should show the circuit depth');
            testCase.verifyTrue(contains(txt, '2 qubits'), ...
                'Info label should show the qubit width');
        end

        function testRenderPaintsAxesChildren(testCase)
            % After rendering, the axes must contain drawn children
            % (regime bands, reference dots, hero marker, etc.).
            % The previous broken implementation painted only a flat
            % teal background — this catches a regression to that.
            [vm, app] = testCase.makeVm();

            data = struct('circuit_name', 'x', 'depth', 10, ...
                'num_qubits', 5, 'gate_counts', struct('h', 3, 'cx', 2));
            vm.renderComplexityLandscape(data);

            nChildren = numel(app.QVHeatmapAxes.Children);
            testCase.verifyGreaterThan(nChildren, 5, ...
                'Complexity landscape should render multiple graphical children');
        end

        function testRegimeClassification(testCase)
            % Info panel should classify the circuit into a regime based
            % on depth. This is the core per-circuit behavior that the
            % original bug masked (same text regardless of input).
            [vm, app] = testCase.makeVm();

            % Shallow circuit → NISQ
            vm.renderComplexityLandscape(struct('circuit_name','a', ...
                'depth', 8, 'num_qubits', 3, ...
                'gate_counts', struct('h', 2)));
            testCase.verifyTrue(contains(testCase.joinText(app.QVInfoLabel.Text), 'NISQ'));

            % Mid-depth circuit
            vm.renderComplexityLandscape(struct('circuit_name','b', ...
                'depth', 200, 'num_qubits', 6, ...
                'gate_counts', struct('cx', 100)));
            testCase.verifyTrue(contains(testCase.joinText(app.QVInfoLabel.Text), 'Mid-depth'));

            % Deep circuit → Fault-tolerant
            vm.renderComplexityLandscape(struct('circuit_name','c', ...
                'depth', 2000, 'num_qubits', 30, ...
                'gate_counts', struct('cx', 500)));
            testCase.verifyTrue(contains(testCase.joinText(app.QVInfoLabel.Text), 'Fault-tolerant'));
        end

        function testFidelityEstimateReactsToTwoQubitGates(testCase)
            % A circuit with many 2Q gates should report a lower
            % estimated fidelity than one with only 1Q gates at the
            % same depth. This is the bug the original rand() hid.
            [vm, app] = testCase.makeVm();

            vm.renderComplexityLandscape(struct('circuit_name','light', ...
                'depth', 20, 'num_qubits', 4, ...
                'gate_counts', struct('h', 10, 'rz', 10)));
            lightTxt = testCase.joinText(app.QVInfoLabel.Text);
            lightFid = testCase.extractFidelityPct(lightTxt);

            vm.renderComplexityLandscape(struct('circuit_name','heavy', ...
                'depth', 20, 'num_qubits', 4, ...
                'gate_counts', struct('cx', 200)));
            heavyTxt = testCase.joinText(app.QVInfoLabel.Text);
            heavyFid = testCase.extractFidelityPct(heavyTxt);

            testCase.verifyGreaterThan(lightFid, heavyFid, ...
                '2Q-heavy circuit should report lower est. fidelity than 1Q-only');
        end

        function testRenderFallsBackWhenDataIsEmpty(testCase)
            % Hardening: the renderer defaults missing fields rather
            % than throwing. Empty input should still produce a
            % populated info label using the "current circuit"
            % fallback name.
            [vm, app] = testCase.makeVm();
            vm.renderComplexityLandscape(struct());
            txt = testCase.joinText(app.QVInfoLabel.Text);
            testCase.verifyTrue(contains(txt, 'current circuit'), ...
                'Empty data should fall back to the default circuit name');
        end

    end

    methods (Access = private)
        function [vm, app] = makeVm(testCase)
            app = StubAnalysisApp();
            app.QVHeatmapAxes = uiaxes(testCase.Fig);
            app.QVInfoLabel   = uilabel(testCase.Fig);
            vm = AnalysisViewModel(app);
        end
    end

    methods (Static, Access = private)
        function s = joinText(val)
            if iscell(val); s = strjoin(val, newline);
            elseif isstring(val); s = char(strjoin(val, newline));
            else; s = char(val);
            end
        end

        function pct = extractFidelityPct(txt)
            % Parse "est. fidelity: NN.N%" out of the info label.
            m = regexp(txt, 'est\. fidelity:\s*([\d.]+)%', 'tokens', 'once');
            if isempty(m)
                pct = NaN;
            else
                pct = str2double(m{1});
            end
        end
    end
end
