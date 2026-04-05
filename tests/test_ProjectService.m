classdef test_ProjectService < matlab.unittest.TestCase
    % test_ProjectService  Unit tests for the ProjectService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_ProjectService')

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
            testCase.Service = ProjectService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorAcceptsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'ProjectService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'));
        end

        % ── listProjects ─────────────────────────────────────────────────

        function testListProjectsUsesGetAuth(testCase)
            testCase.Service.listProjects('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/projects'));
        end

        % ── createProject ────────────────────────────────────────────────

        function testCreateProjectPostsCorrectly(testCase)
            testCase.Service.createProject('Test', 'A test project', {'tag1'}, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/projects'));
        end

        function testCreateProjectPayloadContainsName(testCase)
            testCase.Service.createProject('MyProj', 'desc', {}, 'tok');
            testCase.verifyEqual(testCase.Stub.LastPayload.name, 'MyProj');
        end

        % ── updateProject ────────────────────────────────────────────────

        function testUpdateProjectUsesPatchAuthRaw(testCase)
            testCase.Service.updateProject('p1', 'New', 'Desc', {'a'}, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'patchAuthRaw');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p1'));
        end

        % ── deleteProject ────────────────────────────────────────────────

        function testDeleteProjectUsesDeleteAuth(testCase)
            testCase.Service.deleteProject('p2', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'deleteAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p2'));
        end

        % ── getProject ───────────────────────────────────────────────────

        function testGetProjectUsesGetAuth(testCase)
            testCase.Service.getProject('p3', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p3'));
        end

        % ── getDashboard ─────────────────────────────────────────────────

        function testGetDashboardUsesCorrectEndpoint(testCase)
            testCase.Service.getDashboard('p4', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p4/dashboard'));
        end

        % ── getNotes / saveNotes ─────────────────────────────────────────

        function testGetNotesUsesGetAuth(testCase)
            testCase.Service.getNotes('p5', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p5/notes'));
        end

        function testSaveNotesUsesPutAuthJson(testCase)
            testCase.Service.saveNotes('p6', 'Some notes', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'putAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p6/notes'));
        end

        % ── saveBenchmarkConfig / getBenchmarkConfig ─────────────────────

        function testSaveBenchmarkConfigPosts(testCase)
            testCase.Service.saveBenchmarkConfig('p7', 4096, 3, 'Measurement', 'Fidelity', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p7/benchmark-config'));
        end

        function testGetBenchmarkConfigGets(testCase)
            testCase.Service.getBenchmarkConfig('p8', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p8/benchmark-config'));
        end

        % ── compareStrategies ────────────────────────────────────────────

        function testCompareStrategiesPosts(testCase)
            testCase.Service.compareStrategies('p9', 'c1', 'ibm_brisbane', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'compare-strategies'));
        end

        % ── predict ──────────────────────────────────────────────────────

        function testPredictPosts(testCase)
            testCase.Service.predict('p10', 'c2', 'backend', 1024, 2, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p10/predict'));
        end

        % ── getLatestPrediction ──────────────────────────────────────────

        function testGetLatestPredictionGets(testCase)
            testCase.Service.getLatestPrediction('p11', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p11/predict/latest'));
        end

        % ── listReports / generateReport ─────────────────────────────────

        function testListReportsGets(testCase)
            testCase.Service.listReports('p12', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p12/reports'));
        end

        function testGenerateReportPosts(testCase)
            testCase.Service.generateReport('p13', 'Report Title', 'pdf', 'all', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'p13/reports'));
        end

        % ── Token forwarding ─────────────────────────────────────────────

        function testTokenIsForwarded(testCase)
            testCase.Service.listProjects('secret_token');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'secret_token');
        end

    end
end
