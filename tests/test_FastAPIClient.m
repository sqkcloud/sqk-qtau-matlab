classdef test_FastAPIClient < matlab.unittest.TestCase
    % test_FastAPIClient  Unit tests for FastAPIClient construction and URL building.
    %
    % These tests verify constructor behaviour, URL assembly, and header
    % construction without making any real HTTP calls.
    %
    % Run from the project root:
    %   >> runtests('tests/test_FastAPIClient')

    properties
        Client
    end

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'http'));
        end
    end

    methods (TestMethodSetup)
        function createClient(testCase)
            testCase.Client = FastAPIClient('http://localhost:5715');
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorSetsBaseUrl(testCase)
            testCase.verifyEqual(char(testCase.Client.BaseUrl), ...
                'http://localhost:5715');
        end

        function testConstructorDefaultTimeout(testCase)
            testCase.verifyEqual(testCase.Client.Timeout, 30);
        end

        function testConstructorDefaultProjectIdEmpty(testCase)
            testCase.verifyEqual(strlength(strtrim(testCase.Client.ProjectId)), 0);
        end

        function testConstructorAcceptsStringUrl(testCase)
            c = FastAPIClient("https://example.com:8080");
            testCase.verifyEqual(char(c.BaseUrl), 'https://example.com:8080');
        end

        % ── Handle semantics ─────────────────────────────────────────────

        function testFastAPIClientIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Client, 'handle'), ...
                'FastAPIClient should be a handle class');
        end

        % ── setBaseUrl ───────────────────────────────────────────────────

        function testSetBaseUrlChangesUrl(testCase)
            testCase.Client.setBaseUrl('https://newhost:9090');
            testCase.verifyEqual(char(testCase.Client.BaseUrl), ...
                'https://newhost:9090');
        end

        function testSetBaseUrlAcceptsString(testCase)
            testCase.Client.setBaseUrl("https://string.url:1234");
            testCase.verifyEqual(char(testCase.Client.BaseUrl), ...
                'https://string.url:1234');
        end

        % ── Base URL safety guard ────────────────────────────────────────

        function testHttpsBaseUrlAccepted(testCase)
            testCase.verifyWarningFree( ...
                @() FastAPIClient.assertSafeBaseUrl('https://api.example.com'));
        end

        function testHttpLoopbackAccepted(testCase)
            % Plain HTTP is accepted only for loopback aliases (local
            % development convenience). Everything else must be HTTPS.
            testCase.verifyWarningFree( ...
                @() FastAPIClient.assertSafeBaseUrl('http://localhost:5715'));
            testCase.verifyWarningFree( ...
                @() FastAPIClient.assertSafeBaseUrl('http://127.0.0.1:5715'));
            testCase.verifyWarningFree( ...
                @() FastAPIClient.assertSafeBaseUrl('http://[::1]:5715'));
        end

        function testHttpRemoteRejected(testCase)
            testCase.verifyError( ...
                @() FastAPIClient.assertSafeBaseUrl('http://api.example.com'), ...
                'FastAPIClient:insecureBaseUrl');
        end

        function testEmptyBaseUrlRejected(testCase)
            testCase.verifyError( ...
                @() FastAPIClient.assertSafeBaseUrl(''), ...
                'FastAPIClient:invalidBaseUrl');
        end

        function testSetBaseUrlRejectsInsecureRemote(testCase)
            testCase.verifyError( ...
                @() testCase.Client.setBaseUrl('http://attacker.example.com'), ...
                'FastAPIClient:insecureBaseUrl');
        end

        % ── ProjectId assignment ─────────────────────────────────────────

        function testProjectIdCanBeSet(testCase)
            testCase.Client.ProjectId = "proj_abc";
            testCase.verifyEqual(char(testCase.Client.ProjectId), 'proj_abc');
        end

        % ── Timeout assignment ───────────────────────────────────────────

        function testTimeoutCanBeChanged(testCase)
            testCase.Client.Timeout = 60;
            testCase.verifyEqual(testCase.Client.Timeout, 60);
        end

        % ── Multiple instances are independent ───────────────────────────

        function testMultipleInstancesAreIndependent(testCase)
            c1 = FastAPIClient('https://host1:1111');
            c2 = FastAPIClient('https://host2:2222');
            testCase.verifyNotEqual(char(c1.BaseUrl), char(c2.BaseUrl));
        end

    end
end
