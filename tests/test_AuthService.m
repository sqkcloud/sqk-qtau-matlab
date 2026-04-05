classdef test_AuthService < matlab.unittest.TestCase
    % test_AuthService  Unit tests for the AuthService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_AuthService')

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
            testCase.Service = AuthService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorAcceptsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'AuthService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'));
        end

        % ── login ────────────────────────────────────────────────────────

        function testLoginDelegatesToClient(testCase)
            testCase.Stub.Response = struct('access_token', 'tok123');
            data = testCase.Service.login('alice', 'pass');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'login');
            testCase.verifyEqual(data.access_token, 'tok123');
        end

        function testLoginIncrementsCallCount(testCase)
            before = testCase.Stub.CallCount;
            testCase.Service.login('bob', 'pass');
            testCase.verifyEqual(testCase.Stub.CallCount, before + 1);
        end

        % ── logout ───────────────────────────────────────────────────────

        function testLogoutDelegatesToClient(testCase)
            testCase.Service.logout('mytoken');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'logout');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'mytoken');
        end

        % ── getMe ────────────────────────────────────────────────────────

        function testGetMeDelegatesToClient(testCase)
            testCase.Stub.Response = struct('username', 'alice', 'role', 'admin');
            data = testCase.Service.getMe('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getMe');
            testCase.verifyEqual(data.username, 'alice');
        end

        % ── listProjects ─────────────────────────────────────────────────

        function testListProjectsDelegatesToClient(testCase)
            testCase.Stub.Response = struct('projects', struct('name', 'P1'));
            data = testCase.Service.listProjects('tok', 0, 50);
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'listProjects');
            testCase.verifyTrue(isstruct(data));
        end

    end
end
