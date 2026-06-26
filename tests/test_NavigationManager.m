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

% ── Sidebar nav arrays ────────────────────────────────────────────────────────
function test_nav_arrays_stay_aligned(testCase)
    n  = NavigationManager.navNames();
    ic = NavigationManager.navIcons();
    lb = NavigationManager.navLabels();
    testCase.assertEqual(numel(ic), numel(n));
    testCase.assertEqual(numel(lb), numel(n));
end

function test_prediction_consolidated_out_of_sidebar(testCase)
    % Prediction is folded into Run Planner — it must not appear as a
    % standalone sidebar entry, while Run Planner remains.
    n  = NavigationManager.navNames();
    lb = NavigationManager.navLabels();
    testCase.assertFalse(any(strcmp(n,  'Prediction')));
    testCase.assertFalse(any(strcmp(lb, 'Prediction')));
    testCase.assertTrue(any(strcmp(n, 'Run Planner')));
end

function test_prediction_routing_key_still_resolves(testCase)
    % The routing key stays valid for cross-screen navigation even though
    % it is hidden from the sidebar (falls back to the key as its label).
    testCase.assertEqual(NavigationManager.displayLabelFor('Prediction'), 'Prediction');
end

% ── Progressive disclosure (core vs advanced screens) ─────────────────────────
function test_advanced_screens_classified(testCase)
    adv = {'Circuit Cutting', 'Mitigation Compare', 'Resource Estimator', ...
           'QEC Simulation', 'QEC Visualization'};
    for i = 1:numel(adv)
        testCase.assertTrue(NavigationManager.isAdvancedScreen(adv{i}), adv{i});
    end
end

function test_core_screens_not_advanced(testCase)
    core = {'Dashboard', 'Welcome', 'Circuits', 'Analysis', 'Backends', ...
            'Benchmark', 'Run Planner', 'Jobs', 'Results', 'Reports', 'Settings'};
    for i = 1:numel(core)
        testCase.assertFalse(NavigationManager.isAdvancedScreen(core{i}), core{i});
    end
end

function test_every_advanced_screen_is_a_real_nav_entry(testCase)
    % Guard against typos: every advanced key must exist in navNames.
    n = NavigationManager.navNames();
    adv = n(arrayfun(@(i) NavigationManager.isAdvancedScreen(n{i}), 1:numel(n)));
    testCase.assertEqual(numel(adv), 5);
end
