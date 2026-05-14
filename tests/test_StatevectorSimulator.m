% test_StatevectorSimulator.m ─────────────────────────────────────────────────
% Unit tests for the local statevector simulator — verifies Bell + GHZ
% states match analytic reference, halt-on-measure semantics, and
% reduced-density Bloch math.
%
% Run from the project root:
%   >> runtests('tests/test_StatevectorSimulator')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_StatevectorSimulator
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
end

function test_canSimulate_caps_at_14(testCase)
    m = CircuitModel(8);
    testCase.assertTrue(StatevectorSimulator.canSimulate(m));
    m15 = CircuitModel();
    m15.NumQubits = 15;  % bypass clamp for the test
    testCase.assertFalse(StatevectorSimulator.canSimulate(m15));
end

function test_bell_state_matches_reference(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0);
    m.addGate('cx', [0 1]);
    steps = StatevectorSimulator.simulate(m);
    psi = steps(end).psi;
    expected = [1; 0; 0; 1] / sqrt(2);
    testCase.assertEqual(psi, expected, 'AbsTol', 1e-9);
end

function test_ghz3_matches_reference(testCase)
    m = CircuitModel(3);
    m.addGate('h', 0);
    m.addGate('cx', [0 1]);
    m.addGate('cx', [0 2]);
    steps = StatevectorSimulator.simulate(m);
    psi = steps(end).psi;
    expected = zeros(8, 1);
    expected(1) = 1/sqrt(2);   % |000⟩
    expected(8) = 1/sqrt(2);   % |111⟩
    testCase.assertEqual(psi, expected, 'AbsTol', 1e-9);
end

function test_plus_state_bloch(testCase)
    m = CircuitModel(1);
    m.addGate('h', 0);
    steps = StatevectorSimulator.simulate(m);
    bloch = steps(end).blochPerQubit;
    % |+⟩ has ⟨X⟩=+1, ⟨Y⟩=0, ⟨Z⟩=0
    testCase.assertEqual(bloch(1, :), [1 0 0], 'AbsTol', 1e-9);
end

function test_measure_halts_subsequent_gates(testCase)
    m = CircuitModel(1);
    m.addGate('h', 0);
    m.addGate('measure', 0);
    m.addGate('x', 0);   % should be ignored after measurement
    steps = StatevectorSimulator.simulate(m);
    expected = [1; 1] / sqrt(2);
    testCase.assertEqual(steps(end).psi, expected, 'AbsTol', 1e-9);
    testCase.assertTrue(steps(end).halted);
end

function test_top_amplitudes_sorted(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0);
    steps = StatevectorSimulator.simulate(m);
    top = steps(end).topAmps;
    testCase.assertGreaterThanOrEqual(top(1).prob, top(2).prob);
end

function test_rx_pi_rotates_to_minus_i(testCase)
    m = CircuitModel(1);
    m.addGate('rx', 0, pi);
    steps = StatevectorSimulator.simulate(m);
    psi = steps(end).psi;
    % Rx(pi) |0⟩ = -i |1⟩
    expected = [0; -1i];
    testCase.assertEqual(psi, expected, 'AbsTol', 1e-9);
end
