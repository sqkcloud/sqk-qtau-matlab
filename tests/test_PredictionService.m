classdef test_PredictionService < matlab.unittest.TestCase
    % test_PredictionService  Unit tests for the PredictionService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_PredictionService')

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
            testCase.Service = PredictionService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorAcceptsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'PredictionService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'));
        end

        % ── predict ──────────────────────────────────────────────────────

        function testPredictPostsToCorrectEndpoint(testCase)
            testCase.Service.predict('circ1', 'ibm_brisbane', 4096, 3, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/predict'));
        end

        function testPredictPayloadContainsAllFields(testCase)
            testCase.Service.predict('circ2', 'backend1', 1024, 2, 'tok');
            p = testCase.Stub.LastPayload;
            testCase.verifyEqual(p.circuit_id, 'circ2');
            testCase.verifyEqual(p.backend_name, 'backend1');
            testCase.verifyEqual(p.shots, 1024);
            testCase.verifyEqual(p.optimization_level, 2);
        end

        function testPredictRoundsShots(testCase)
            testCase.Service.predict('c', 'b', 1024.7, 2.9, 'tok');
            testCase.verifyEqual(testCase.Stub.LastPayload.shots, 1025);
            testCase.verifyEqual(testCase.Stub.LastPayload.optimization_level, 3);
        end

        % ── getPrediction ────────────────────────────────────────────────

        function testGetPredictionUsesGetAuth(testCase)
            testCase.Service.getPrediction('pred_abc', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/predict/pred_abc'));
        end

        % ── optimizeCircuit ──────────────────────────────────────────────

        function testOptimizeCircuitPosts(testCase)
            testCase.Service.optimizeCircuit('c1', 'be1', 3, 'heavy', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/optimize'));
        end

        function testOptimizeCircuitPayloadContainsStrategy(testCase)
            testCase.Service.optimizeCircuit('c2', 'be2', 1, 'light', 'tok');
            p = testCase.Stub.LastPayload;
            testCase.verifyEqual(p.circuit_id, 'c2');
            testCase.verifyEqual(p.backend_name, 'be2');
            testCase.verifyEqual(p.optimization_level, 1);
            testCase.verifyEqual(p.transpilation_strategy, 'light');
        end

        % ── Return value comes from stub ─────────────────────────────────

        function testReturnValueFromStub(testCase)
            testCase.Stub.Response = struct('predicted_fidelity', 0.95);
            data = testCase.Service.predict('c', 'b', 1024, 3, 'tok');
            testCase.verifyEqual(data.predicted_fidelity, 0.95);
        end

        % ── Token forwarding ─────────────────────────────────────────────

        function testTokenIsForwarded(testCase)
            testCase.Service.predict('c', 'b', 100, 1, 'my_token');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'my_token');
        end

    end
end
