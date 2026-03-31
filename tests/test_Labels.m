% test_Labels.m ────────────────────────────────────────────────────────────────
% Smoke tests for the Labels utility class.
%
% Run from the project root:
%   >> runtests('tests/test_Labels')
%
% Or run the full test suite:
%   >> runtests('tests')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_Labels
    tests = functiontests(localfunctions);
end

% ── Setup ─────────────────────────────────────────────────────────────────────

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'utils'));
    Labels.reload();   % clear any cached state
end

% ── Tests ─────────────────────────────────────────────────────────────────────

function test_error_title_is_error(testCase)
    val = Labels.get('error_title', '');
    testCase.assertNotEmpty(val, 'error_title should be defined in labels.properties');
end

function test_nav_welcome_is_present(testCase)
    val = Labels.get('nav_welcome', '');
    testCase.assertNotEmpty(val, 'nav_welcome should be defined in labels.properties');
end

function test_missing_key_returns_default(testCase)
    sentinel = 'fallback_label_xyz';
    val = Labels.get('this_key_does_not_exist_xyz', sentinel);
    testCase.assertEqual(val, sentinel, ...
        'Labels.get should return the default for an unknown key');
end

function test_cols_returns_cell_array(testCase)
    val = Labels.cols('welcome_table_cols_projects', {'a','b','c'});
    testCase.assertClass(val, 'cell', 'Labels.cols should return a cell array');
    testCase.assertGreaterThan(numel(val), 0, 'Cell array should not be empty');
end

function test_cols_falls_back_gracefully(testCase)
    fallback = {'col1','col2'};
    val = Labels.cols('nonexistent_cols_key_xyz', fallback);
    testCase.assertEqual(val, fallback, ...
        'Labels.cols should return the fallback for an unknown key');
end

function test_items_returns_cell_array(testCase)
    val = Labels.items('settings_alert_items', {'A','B'});
    testCase.assertClass(val, 'cell', 'Labels.items should return a cell array');
    testCase.assertGreaterThan(numel(val), 0, 'Items cell array should not be empty');
end

function test_reload_does_not_crash(testCase)
    testCase.assertWarningFree(@() Labels.reload());
end
