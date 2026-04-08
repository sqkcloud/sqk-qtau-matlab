classdef test_BenchmarkService < matlab.unittest.TestCase
    % test_BenchmarkService  Unit tests for the BenchmarkService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_BenchmarkService')

    properties
        Stub
        Service
    end

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'http'));
            addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
            addpath(fullfile(projectRoot, 'tests'));
        end
    end

    methods (TestMethodSetup)
        function createService(testCase)
            testCase.Stub = StubFastAPIClient();
            testCase.Service = BenchmarkService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorSetsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'BenchmarkService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'), ...
                'BenchmarkService should be a handle class');
        end

        % ── getVolumetricData ────────────────────────────────────────────

        function testGetVolumetricDataUsesGetAuth(testCase)
            testCase.Service.getVolumetricData('proj1', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/benchmark/volumetric'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj1'));
        end

        % ── getSystemMetrics ─────────────────────────────────────────────

        function testGetSystemMetricsUsesBackendName(testCase)
            testCase.Service.getSystemMetrics('ibm_brisbane', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), ...
                '/api/benchmark/system-metrics/ibm_brisbane'));
        end

        % ── getBackendScorecard ──────────────────────────────────────────

        function testGetBackendScorecardUsesProjectAndBackend(testCase)
            testCase.Service.getBackendScorecard('proj2', 'ibm_osaka', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/benchmark/scorecard'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj2'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'ibm_osaka'));
        end

        % ── getBenchmarkRegression ───────────────────────────────────────

        function testGetBenchmarkRegressionUsesCorrectEndpoint(testCase)
            testCase.Service.getBenchmarkRegression('proj3', 'ibm_kyoto', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/benchmark/regression'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj3'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'ibm_kyoto'));
        end

        % ── getCircuitClassification ─────────────────────────────────────

        function testGetCircuitClassificationUsesCircuitId(testCase)
            testCase.Service.getCircuitClassification('circ1', 'proj4', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/benchmark/classify/circ1'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj4'));
        end

        % ── getPredictionCalibration ─────────────────────────────────────

        function testGetPredictionCalibrationUsesProjectId(testCase)
            testCase.Service.getPredictionCalibration('proj5', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), ...
                '/api/benchmark/prediction-calibration'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj5'));
        end

        % ── Token forwarding ─────────────────────────────────────────────

        function testTokenIsForwarded(testCase)
            testCase.Service.getVolumetricData('p', 'my_secret');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'my_secret');
        end

        % ── Return value is from stub ────────────────────────────────────

        function testReturnValueComesFromStub(testCase)
            testCase.Stub.Response = struct('qv', 64, 'clops', 1200);
            data = testCase.Service.getSystemMetrics('be', 'tok');
            testCase.verifyEqual(data.qv, 64);
            testCase.verifyEqual(data.clops, 1200);
        end

    end
end
