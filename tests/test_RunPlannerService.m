% test_RunPlannerService.m ───────────────────────────────────────────────────
% Unit tests for the cost-aware run-planner math.
%
% Run from the project root:
%   >> runtests('tests/test_RunPlannerService')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_RunPlannerService
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
end

% ── applyMitigationFactor ───────────────────────────────────────────────────
function test_factor_table_levels(testCase)
    testCase.assertEqual(RunPlannerService.applyMitigationFactor(0.5, '0'), 0.50, 'AbsTol', 1e-9);
    testCase.assertEqual(RunPlannerService.applyMitigationFactor(0.5, '1'), 0.525, 'AbsTol', 1e-9);
    testCase.assertEqual(RunPlannerService.applyMitigationFactor(0.5, '2'), 0.575, 'AbsTol', 1e-9);
    testCase.assertEqual(RunPlannerService.applyMitigationFactor(0.5, '3'), 0.65, 'AbsTol', 1e-9);
end

function test_factor_caps_at_99(testCase)
    out = RunPlannerService.applyMitigationFactor(0.95, '3');
    testCase.assertEqual(out, RunPlannerService.FIDELITY_CAP, 'AbsTol', 1e-9);
end

function test_unknown_level_factor_one(testCase)
    out = RunPlannerService.applyMitigationFactor(0.7, 'custom');
    testCase.assertEqual(out, 0.7, 'AbsTol', 1e-9);
end

function test_factor_handles_nan(testCase)
    out = RunPlannerService.applyMitigationFactor(NaN, '2');
    testCase.assertTrue(isnan(out));
end

% ── computeParetoFrontier ───────────────────────────────────────────────────
function test_frontier_empty_input(testCase)
    f = RunPlannerService.computeParetoFrontier([]);
    testCase.assertEmpty(f);
end

function test_frontier_single_point(testCase)
    p = makePoint('A', 0.05, 0.80);
    f = RunPlannerService.computeParetoFrontier(p);
    testCase.assertEqual(numel(f), 1);
    testCase.assertEqual(f(1).cost, 0.05);
end

function test_frontier_drops_dominated_points(testCase)
    pts = [makePoint('A',0.10,0.80), ...
           makePoint('B',0.10,0.85), ...
           makePoint('C',0.20,0.90), ...
           makePoint('D',0.15,0.82)];
    f = RunPlannerService.computeParetoFrontier(pts);
    testCase.assertEqual(numel(f), 2);
    fids = [f.fidelity];
    testCase.assertEqual(sort(fids), [0.85 0.90], 'AbsTol', 1e-9);
end

function test_frontier_drops_nonfinite_points(testCase)
    pts = [makePoint('A',0.10,0.80), makePoint('B',NaN,0.85), makePoint('C',0.20,Inf)];
    f = RunPlannerService.computeParetoFrontier(pts);
    testCase.assertEqual(numel(f), 1);
    testCase.assertEqual(f(1).backend, 'A');
end

% ── pickOptimal ─────────────────────────────────────────────────────────────
function test_optimal_returns_cheapest_hitting_target(testCase)
    pts = [makePoint('cheap-low',0.05,0.80), ...
           makePoint('cheap-mid',0.08,0.91), ...
           makePoint('mid-high', 0.12,0.93), ...
           makePoint('exp-high', 0.50,0.95)];
    f = RunPlannerService.computeParetoFrontier(pts);
    r = RunPlannerService.pickOptimal(pts, f, 0.90);
    testCase.assertTrue(r.metTarget);
    testCase.assertEqual(r.point.backend, 'cheap-mid');
end

function test_optimal_falls_back_when_no_target_hit(testCase)
    pts = [makePoint('A',0.05,0.80), makePoint('B',0.10,0.85), makePoint('C',0.20,0.88)];
    f = RunPlannerService.computeParetoFrontier(pts);
    r = RunPlannerService.pickOptimal(pts, f, 0.95);
    testCase.assertFalse(r.metTarget);
    testCase.assertEqual(r.point.backend, 'C');  % highest-fidelity overall
end

% ── makePoint sanity ────────────────────────────────────────────────────────
function test_makePoint_round_trip(testCase)
    p = RunPlannerService.makePoint('be', '2', 'Standard', 0.85, 0.92, 0.04, 3.2, 4710, 1.15);
    testCase.assertEqual(p.backend,    'be');
    testCase.assertEqual(p.level,      '2');
    testCase.assertEqual(p.fidelity,   0.92, 'AbsTol', 1e-9);
    testCase.assertEqual(p.cost,       0.04, 'AbsTol', 1e-9);
    testCase.assertEqual(p.totalShots, 4710);
end

% ── helper ──────────────────────────────────────────────────────────────────
function p = makePoint(name, cost, fid)
    p = RunPlannerService.makePoint(name, '0', 'None', fid, fid, cost, 1.0, 4096, 1.0);
end
