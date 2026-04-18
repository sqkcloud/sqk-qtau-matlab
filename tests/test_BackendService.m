classdef test_BackendService < matlab.unittest.TestCase
    % test_BackendService  Unit tests for the BackendService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_BackendService')

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
            testCase.Service = BackendService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorAcceptsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'BackendService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'));
        end

        % ── listBackends ─────────────────────────────────────────────────

        function testListBackendsUsesGetAuth(testCase)
            testCase.Service.listBackends('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/backends'));
        end

        % ── getBackend ───────────────────────────────────────────────────

        function testGetBackendIncludesName(testCase)
            testCase.Service.getBackend('ibm_boston', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'ibm_boston'));
        end

        % ── getCalibration ───────────────────────────────────────────────

        function testGetCalibrationUsesCorrectEndpoint(testCase)
            testCase.Service.getCalibration('ibm_kingston', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'ibm_kingston/calibration'));
        end

        % ── getTopology ──────────────────────────────────────────────────

        function testGetTopologyUsesCorrectEndpoint(testCase)
            testCase.Service.getTopology('ibm_pittsburgh', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'ibm_pittsburgh/topology'));
        end

        % ── compareBackends ──────────────────────────────────────────────

        function testCompareBackendsPosts(testCase)
            testCase.Service.compareBackends({'ibm_boston','ibm_kingston'}, 'circ1', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/backends/compare'));
        end

        function testCompareBackendsPayloadContainsCircuitId(testCase)
            testCase.Service.compareBackends({'b1'}, 'c123', 'tok');
            testCase.verifyEqual(testCase.Stub.LastPayload.circuit_id, 'c123');
        end

        % ── saveSelection ────────────────────────────────────────────────

        function testSaveSelectionPosts(testCase)
            testCase.Service.saveSelection('proj1', 'primary_be', 'backup_be', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj1/backend-selection'));
        end

        function testSaveSelectionPayload(testCase)
            testCase.Service.saveSelection('proj1', 'primary', 'backup', 'tok');
            testCase.verifyEqual(testCase.Stub.LastPayload.primary_backend, 'primary');
            testCase.verifyEqual(testCase.Stub.LastPayload.backup_backend, 'backup');
        end

        % ── getSelection ─────────────────────────────────────────────────

        function testGetSelectionGets(testCase)
            testCase.Service.getSelection('proj2', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj2/backend-selection'));
        end

        % ── Token forwarding ─────────────────────────────────────────────

        function testTokenIsForwarded(testCase)
            testCase.Service.listBackends('my_token');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'my_token');
        end

    end
end
