% test_AppConfig.m ─────────────────────────────────────────────────────────────
% Smoke tests for the AppConfig utility class.
%
% Run from the project root:
%   >> runtests('tests/test_AppConfig')
%
% Or run the full test suite:
%   >> runtests('tests')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_AppConfig
    tests = functiontests(localfunctions);
end

% ── Setup / teardown ──────────────────────────────────────────────────────────

function setupOnce(~)
    % Ensure the project root and utils are on the path before any test runs.
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'utils'));
    AppConfig.reload();   % clear any cached state from a previous session
end

% ── Tests ─────────────────────────────────────────────────────────────────────

function test_base_url_is_present(testCase)
    val = AppConfig.get('base_url', '');
    testCase.assertNotEmpty(val, 'base_url should be defined in app.properties');
end

function test_base_url_starts_with_http(testCase)
    val = AppConfig.get('base_url', '');
    testCase.assertTrue(startsWith(val, 'http'), ...
        'base_url should start with http');
end

function test_http_timeout_is_positive(testCase)
    val = AppConfig.getDouble('http_timeout', 30);
    testCase.assertGreaterThan(val, 0, 'http_timeout should be a positive number');
end

function test_app_name_is_present(testCase)
    val = AppConfig.get('app_name', '');
    testCase.assertNotEmpty(val, 'app_name should be defined in app.properties');
end

function test_login_path_is_present(testCase)
    val = AppConfig.get('login_path', '');
    testCase.assertNotEmpty(val, 'login_path should be defined in app.properties');
    testCase.assertEqual(val(1), '/', 'login_path should start with /');
end

function test_missing_key_returns_default(testCase)
    sentinel = 'my_default_12345';
    val = AppConfig.get('this_key_does_not_exist_xyz', sentinel);
    testCase.assertEqual(val, sentinel, ...
        'AppConfig.get should return the default for an unknown key');
end

function test_missing_key_getDouble_returns_default(testCase)
    val = AppConfig.getDouble('this_key_does_not_exist_xyz', 99.9);
    testCase.assertEqual(val, 99.9, ...
        'AppConfig.getDouble should return the default for an unknown key');
end

function test_reload_does_not_crash(testCase)
    testCase.assertWarningFree(@() AppConfig.reload());
end
