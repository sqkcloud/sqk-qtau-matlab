classdef test_ServiceContainer < matlab.unittest.TestCase
    % test_ServiceContainer  Unit tests for the ServiceContainer class.
    %
    % Run from the project root:
    %   >> runtests('tests/test_ServiceContainer')

    properties
        Container
    end

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'http'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure'));
            addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
            addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
            AppConfig.reload();
        end
    end

    methods (TestMethodSetup)
        function createFreshContainer(testCase)
            testCase.Container = ServiceContainer('http://localhost:9999');
        end
    end

    methods (Test)

        % -- Constructor creates the container ---------------------------------

        function testConstructorReturnsServiceContainer(testCase)
            testCase.verifyTrue(isa(testCase.Container, 'ServiceContainer'));
        end

        function testContainerIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Container, 'handle'));
        end

        % -- All 10 service properties are populated ---------------------------

        function testClientNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.Client, ...
                'Client should not be empty after construction');
        end

        function testAuthSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.AuthSvc, ...
                'AuthSvc should not be empty after construction');
        end

        function testCircuitSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.CircuitSvc, ...
                'CircuitSvc should not be empty after construction');
        end

        function testBackendSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.BackendSvc, ...
                'BackendSvc should not be empty after construction');
        end

        function testJobSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.JobSvc, ...
                'JobSvc should not be empty after construction');
        end

        function testProjectSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.ProjectSvc, ...
                'ProjectSvc should not be empty after construction');
        end

        function testPredictionSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.PredictionSvc, ...
                'PredictionSvc should not be empty after construction');
        end

        function testReportSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.ReportSvc, ...
                'ReportSvc should not be empty after construction');
        end

        function testSettingsSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.SettingsSvc, ...
                'SettingsSvc should not be empty after construction');
        end

        function testQecEngineNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.QecEngine, ...
                'QecEngine should not be empty after construction');
        end

        function testBenchmarkSvcNotEmpty(testCase)
            testCase.verifyNotEmpty(testCase.Container.BenchmarkSvc, ...
                'BenchmarkSvc should not be empty after construction');
        end

        % -- Service types are correct -----------------------------------------

        function testClientIsFastAPIClient(testCase)
            testCase.verifyTrue(isa(testCase.Container.Client, 'FastAPIClient'));
        end

        function testAuthSvcIsAuthService(testCase)
            testCase.verifyTrue(isa(testCase.Container.AuthSvc, 'AuthService'));
        end

        function testCircuitSvcIsCircuitService(testCase)
            testCase.verifyTrue(isa(testCase.Container.CircuitSvc, 'CircuitService'));
        end

        function testQecEngineIsQecEngineService(testCase)
            testCase.verifyTrue(isa(testCase.Container.QecEngine, 'QecEngineService'));
        end

        function testBenchmarkSvcIsBenchmarkService(testCase)
            testCase.verifyTrue(isa(testCase.Container.BenchmarkSvc, 'BenchmarkService'));
        end

    end
end
