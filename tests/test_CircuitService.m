classdef test_CircuitService < matlab.unittest.TestCase
    % test_CircuitService  Unit tests for the CircuitService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_CircuitService')

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
            testCase.Service = CircuitService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorAcceptsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'CircuitService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'));
        end

        % ── listCircuits ─────────────────────────────────────────────────

        function testListCircuitsDelegatesToGetAuth(testCase)
            testCase.Stub.Response = struct('circuits', []);
            testCase.Service.listCircuits('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/circuits'));
        end

        % ── listCircuitsPaged ────────────────────────────────────────────

        function testListCircuitsPagedBuildsQueryParams(testCase)
            testCase.Service.listCircuitsPaged(10, 25, 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'skip=10'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'limit=25'));
        end

        % ── getCircuit ───────────────────────────────────────────────────

        function testGetCircuitUsesCircuitId(testCase)
            testCase.Service.getCircuit('circ_abc', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'circ_abc'));
        end

        % ── analyzeCircuit ───────────────────────────────────────────────

        function testAnalyzeCircuitPostsToCorrectEndpoint(testCase)
            testCase.Service.analyzeCircuit('circ_1', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'circ_1/analyze'));
        end

        % ── getAnalysis ──────────────────────────────────────────────────

        function testGetAnalysisUsesCorrectEndpoint(testCase)
            testCase.Service.getAnalysis('circ_2', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'circ_2/analysis'));
        end

        % ── matchBenchmarks ──────────────────────────────────────────────

        function testMatchBenchmarksPostsCorrectly(testCase)
            testCase.Service.matchBenchmarks('circ_3', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'circ_3/match-benchmarks'));
        end

        % ── previewCircuit ───────────────────────────────────────────────

        function testPreviewCircuitGetsCorrectEndpoint(testCase)
            testCase.Service.previewCircuit('circ_4', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'circ_4/preview'));
        end

        % ── updateCircuit ────────────────────────────────────────────────

        function testUpdateCircuitPatchesCorrectly(testCase)
            patch = struct('name', 'NewName');
            testCase.Service.updateCircuit('circ_5', patch, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'patchAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'circ_5'));
        end

        % ── deleteCircuit ────────────────────────────────────────────────

        function testDeleteCircuitDeletesCorrectly(testCase)
            testCase.Service.deleteCircuit('circ_6', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'deleteAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'circ_6'));
        end

        % ── uploadCircuit ────────────────────────────────────────────────

        function testUploadCircuitDelegatesToUploadFileAuth(testCase)
            testCase.Service.uploadCircuit('/tmp/test.qasm', 'MyCircuit', 'qasm', 'algo', 5, 10, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'uploadFileAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'upload/file'));
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'tok');
        end

        % ── Token is forwarded ───────────────────────────────────────────

        function testTokenIsForwarded(testCase)
            testCase.Service.listCircuits('my_secret_token');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'my_secret_token');
        end

    end
end
