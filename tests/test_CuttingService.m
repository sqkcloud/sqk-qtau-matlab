classdef test_CuttingService < matlab.unittest.TestCase
    % test_CuttingService  Unit tests for the CuttingService domain service.
    %
    %   Mirrors test_BenchmarkService.m structure. All HTTP work is recorded
    %   by StubFastAPIClient; no real network calls.

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
            testCase.Service = CuttingService(testCase.Stub);
        end
    end

    methods (Test)

        function testConstructorSetsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'CuttingService'));
        end

        function testAnalyzeCutsPostsToAnalyzeEndpoint(testCase)
            testCase.Service.analyzeCuts('c1', 3, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/cutting/analyze'));
        end

        function testAnalyzeCutsOmitsTargetKWhenEmpty(testCase)
            testCase.Service.analyzeCuts('c1', [], 'tok');
            payload = testCase.Stub.LastPayload;
            testCase.verifyTrue(isfield(payload, 'circuit_id'));
            testCase.verifyFalse(isfield(payload, 'target_k'), ...
                'target_k must be omitted when caller passes []');
        end

        function testListPresetsUsesGetAuth(testCase)
            testCase.Service.listPresets('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/cutting/presets'));
        end

        function testCreateBatchHitsCircuitEndpoint(testCase)
            testCase.Service.createBatch('c1', struct('mode','assisted'), 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), ...
                '/api/circuits/c1/cutting/batches'));
        end

        function testPollBatchIncludesBatchIdInPath(testCase)
            testCase.Service.pollBatch('b-xyz', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), ...
                '/api/cutting/batches/b-xyz'));
        end

        function testGetBatchResultSuffixesResult(testCase)
            testCase.Service.getBatchResult('b-xyz', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), ...
                '/api/cutting/batches/b-xyz/result'));
        end

        function testCancelUsesDeleteAuth(testCase)
            testCase.Service.cancelBatch('b-xyz', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'deleteAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), ...
                '/api/cutting/batches/b-xyz'));
        end

        function testListBatchesUsesGetAuth(testCase)
            testCase.Service.listBatches('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), ...
                '/api/cutting/batches'));
        end

        function testTokenIsForwarded(testCase)
            testCase.Service.pollBatch('b', 'my_secret_token');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'my_secret_token');
        end

    end
end
