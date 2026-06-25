% test_NavigationManager.m ─────────────────────────────────────────────────────
% Unit test for the offline-capable screen classification used to decide
% whether the auth overlay covers a screen.
%
% Run from the project root:
%   >> runtests('tests/test_NavigationManager')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_NavigationManager
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(genpath(fullfile(projectRoot, 'src')));
end

function test_composer_is_offline_capable(testCase)
    testCase.assertTrue(NavigationManager.isOfflineCapable('Composer'));
end

function test_dashboard_is_not_offline_capable(testCase)
    testCase.assertFalse(NavigationManager.isOfflineCapable('Dashboard'));
end
