classdef test_SettingsService < matlab.unittest.TestCase
    % test_SettingsService  Unit tests for the SettingsService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_SettingsService')

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
            testCase.Service = SettingsService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorAcceptsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'SettingsService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'));
        end

        % ── getPreferences ───────────────────────────────────────────────

        function testGetPreferencesUsesGetAuth(testCase)
            testCase.Service.getPreferences('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/settings/preferences'));
        end

        % ── getServerConfig ──────────────────────────────────────────────

        function testGetServerConfigUsesGetAuth(testCase)
            testCase.Service.getServerConfig('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/settings'));
        end

        % ── savePreferences ──────────────────────────────────────────────

        function testSavePreferencesPosts(testCase)
            prefs = struct('theme', 'dark', 'shots', 1024);
            testCase.Service.savePreferences(prefs, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/settings'));
        end

        function testSavePreferencesForwardsPayload(testCase)
            prefs = struct('theme', 'light');
            testCase.Service.savePreferences(prefs, 'tok');
            testCase.verifyEqual(testCase.Stub.LastPayload.theme, 'light');
        end

        % ── verifyIbmCredentials ─────────────────────────────────────────

        function testVerifyIbmCredentialsPosts(testCase)
            testCase.Service.verifyIbmCredentials('api_key', 'ibm_quantum', 'inst/1', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/settings/verify-ibm'));
        end

        function testVerifyIbmCredentialsPayload(testCase)
            testCase.Service.verifyIbmCredentials('key123', 'ibm_cloud', 'inst/2', 'tok');
            testCase.verifyEqual(testCase.Stub.LastPayload.api_token, 'key123');
            testCase.verifyEqual(testCase.Stub.LastPayload.channel, 'ibm_cloud');
            testCase.verifyEqual(testCase.Stub.LastPayload.instance, 'inst/2');
        end

        % ── clearCache ───────────────────────────────────────────────────

        function testClearCacheUsesDeleteAuth(testCase)
            testCase.Service.clearCache('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'deleteAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/settings/cache'));
        end

        % ── Token forwarding ─────────────────────────────────────────────

        function testTokenIsForwarded(testCase)
            testCase.Service.getPreferences('secret_tok');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'secret_tok');
        end

    end
end
