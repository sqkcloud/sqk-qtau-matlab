classdef test_BenchmarkDashboardViewModel < matlab.unittest.TestCase
    % test_BenchmarkDashboardViewModel  Unit tests for the reset-first rendering
    % and KPI formatting logic added to fix the "refresh does nothing" bug.
    %
    % The ViewModel's public surface is tightly coupled to an app handle and
    % a live uifigure, which is impractical in batch mode. These tests exercise
    % the small private helpers via a lightweight stub that mirrors the
    % API shape — the same paths the real UI takes when rendering metrics.

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'presentation', 'viewmodels'));
        end
    end

    methods (Test)

        % pick() should return [] (→ '--' card) for missing fields, real
        % numbers for present fields, and default for JSON null (decoded as []).
        function testPickHandlesMissingAndPresentNumerics(testCase)
            payload = struct( ...
                'backend_name', 'ibm_miami', ...
                'layer_fidelity', 0.9412, ...
                'quantum_volume', [] ); % JSON null decodes to []

            lf = JsonHelper.pick(payload, 'layer_fidelity', []);
            testCase.verifyEqual(lf, 0.9412, 'AbsTol', 1e-9);

            qv = JsonHelper.pick(payload, 'quantum_volume', []);
            testCase.verifyEmpty(qv, ...
                'JSON null must round-trip to [] so the KPI card reads --');

            missing = JsonHelper.pick(payload, 'clops', []);
            testCase.verifyEmpty(missing, ...
                'Missing fields must also return the default, not crash');
        end

        % The `source` string is how the UI decides whether to tint the
        % badge green (live), orange (stub), or grey (n/a). Missing field
        % must default to 'unavailable'.
        function testPickSourceStringFallback(testCase)
            payload = struct('backend_name', 'ibm_miami');
            src = char(JsonHelper.pick(payload, 'source', 'unavailable'));
            testCase.verifyEqual(src, 'unavailable');

            payload2 = struct('source', 'ibm_runtime');
            src2 = char(JsonHelper.pick(payload2, 'source', 'unavailable'));
            testCase.verifyEqual(src2, 'ibm_runtime');
        end

        % The VM's formatKpi accepts numeric or empty and always produces a
        % displayable char. Reach it through a minimal subclass since the
        % method is private.
        function testFormatKpiReturnsDashForEmpty(testCase)
            vm = TestBenchmarkDashboardVmProbe();
            testCase.verifyEqual(vm.probeFormat([], '%.4f'), '--');
            testCase.verifyEqual(vm.probeFormat(NaN, '%.4f'), '--');
            testCase.verifyEqual(vm.probeFormat(0.9412, '%.4f'), '0.9412');
            testCase.verifyEqual(vm.probeFormat(64, '%d'), '64');
            % Non-integer coerced to int when %d is used
            testCase.verifyEqual(vm.probeFormat(63.6, '%d'), '64');
        end

    end
end
