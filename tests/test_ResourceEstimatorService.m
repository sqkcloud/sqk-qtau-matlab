% test_ResourceEstimatorService.m ────────────────────────────────────────────
% Unit tests for the fault-tolerant resource estimator math.
%
% Run from the project root:
%   >> runtests('tests/test_ResourceEstimatorService')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_ResourceEstimatorService
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
end

% ── codeDistance ─────────────────────────────────────────────────────────────
function test_distance_default_thresholds(testCase)
    % p=1e-3, eps=1e-15: ratio = log(1e-15/0.03)/log(1e-3/1e-2) ≈ 7.85
    % d_raw = 2*7.85 - 1 = 14.7 → ceil = 15 (already odd)
    d = ResourceEstimatorService.codeDistance(1e-3, 1e-15);
    testCase.assertEqual(d, 15);
end

function test_distance_lower_target_grows(testCase)
    d_low  = ResourceEstimatorService.codeDistance(1e-3, 1e-12);
    d_high = ResourceEstimatorService.codeDistance(1e-3, 1e-18);
    testCase.assertGreaterThan(d_high, d_low);
end

function test_distance_above_threshold_caps(testCase)
    d = ResourceEstimatorService.codeDistance(0.05, 1e-15);
    testCase.assertEqual(d, ResourceEstimatorService.D_MAX);
end

function test_distance_always_odd(testCase)
    for p = [1e-2, 5e-3, 1e-3, 1e-4]
        for eps = [1e-6, 1e-12, 1e-18]
            d = ResourceEstimatorService.codeDistance(p, eps);
            testCase.assertTrue(mod(d, 2) == 1, ...
                sprintf('distance %d not odd for p=%.0e eps=%.0e', d, p, eps));
        end
    end
end

% ── isCliffordRotation ───────────────────────────────────────────────────────
function test_pi_over_2_is_clifford(testCase)
    testCase.assertTrue(ResourceEstimatorService.isCliffordRotation(pi/2));
    testCase.assertTrue(ResourceEstimatorService.isCliffordRotation(pi));
    testCase.assertTrue(ResourceEstimatorService.isCliffordRotation(-pi/2));
end

function test_pi_over_4_is_not_clifford(testCase)
    testCase.assertFalse(ResourceEstimatorService.isCliffordRotation(pi/4));
end

% ── tStateBudget ─────────────────────────────────────────────────────────────
function test_clifford_only_circuit_zero_t_states(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    b = ResourceEstimatorService.tStateBudget(m, 1e-15);
    testCase.assertEqual(b.tGates, 0);
    testCase.assertEqual(b.toffolis, 0);
    testCase.assertEqual(b.nonCliffordRotations, 0);
end

function test_t_gate_counted(testCase)
    m = CircuitModel(1);
    m.addGate('t', 0); m.addGate('tdg', 0);
    b = ResourceEstimatorService.tStateBudget(m, 1e-15);
    testCase.assertEqual(b.tGates, 2);
end

function test_toffoli_counted_separately(testCase)
    m = CircuitModel(3);
    m.addGate('ccx', [0 1 2]);
    b = ResourceEstimatorService.tStateBudget(m, 1e-15);
    testCase.assertEqual(b.toffolis, 1);
    testCase.assertEqual(b.tGates, 0);
end

function test_clifford_rotations_excluded(testCase)
    m = CircuitModel(1);
    m.addGate('rx', 0, pi/2);
    b = ResourceEstimatorService.tStateBudget(m, 1e-15);
    testCase.assertEqual(b.nonCliffordRotations, 0);
end

function test_arbitrary_rotation_costs_t_states(testCase)
    m = CircuitModel(1);
    m.addGate('rx', 0, 0.31415);
    b = ResourceEstimatorService.tStateBudget(m, 1e-3);
    testCase.assertEqual(b.nonCliffordRotations, 1);
    testCase.assertGreaterThan(b.tGatesFromRotations, 0);
end

% ── estimate (full pipeline) ─────────────────────────────────────────────────
function test_bell_state_estimate(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    out = ResourceEstimatorService.estimate(m, ResourceEstimatorService.defaultParams());
    testCase.assertEqual(out.logicalQubits, 2);
    testCase.assertTrue(out.cliffordOnly);
    testCase.assertEqual(out.tFactories, 0);
    testCase.assertEqual(out.distance, 15);
    testCase.assertEqual(out.physicalPerLogical, 2*15^2 + 1);
    testCase.assertGreaterThan(out.totalPhysical, out.dataQubits);
end

function test_toffoli_circuit_needs_factory(testCase)
    m = CircuitModel(3);
    m.addGate('ccx', [0 1 2]);
    out = ResourceEstimatorService.estimate(m, ResourceEstimatorService.defaultParams());
    testCase.assertFalse(out.cliffordOnly);
    testCase.assertEqual(out.tFactories, 1);
    testCase.assertGreaterThan(out.factoryQubits, 0);
end

function test_runtime_scales_with_depth(testCase)
    p = ResourceEstimatorService.defaultParams();
    m1 = CircuitModel(1); m1.addGate('h', 0);
    m2 = CircuitModel(1);
    for i = 1:10; m2.addGate('h', 0); end
    out1 = ResourceEstimatorService.estimate(m1, p);
    out2 = ResourceEstimatorService.estimate(m2, p);
    testCase.assertGreaterThan(out2.totalSeconds, out1.totalSeconds);
end

function test_estimate_rejects_bad_params(testCase)
    m = CircuitModel(2);
    badP = ResourceEstimatorService.defaultParams();
    badP.physErr = 0;
    testCase.verifyError(@() ResourceEstimatorService.estimate(m, badP), ...
        'ResourceEstimatorService:BadParam');
end
