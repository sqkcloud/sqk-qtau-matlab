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

function test_intermediate_steps_release_psi(testCase)
    % Memory contract: only the FINAL step keeps the full statevector;
    % intermediate steps drop psi so retained memory is O(2^n), not
    % O(g·2^n). Derived summaries stay on every step.
    m = CircuitModel(2);
    m.addGate('h', 0);
    m.addGate('cx', [0 1]);
    steps = StatevectorSimulator.simulate(m);
    testCase.assertNotEmpty(steps(end).psi);
    for k = 1:numel(steps)-1
        testCase.assertEmpty(steps(k).psi);
    end
    testCase.assertSize(steps(1).blochPerQubit, [2 3]);
end

function test_maxSteps_bounds_step_count(testCase)
    % The Inspect footer passes a step budget; unset ⇒ no cap.
    m = CircuitModel(2);
    for k = 1:10; m.addGate('x', 0); end
    capped = StatevectorSimulator.simulate(m, struct('maxSteps', 4));
    testCase.assertLessThanOrEqual(numel(capped), 4);
    full = StatevectorSimulator.simulate(m);
    testCase.assertEqual(numel(full), 11);   % 1 initial + 10 gates
end

function test_budgeted_walkthrough_ends_at_the_true_final_state(testCase)
    % A step budget samples checkpoints — it must NEVER stop applying
    % gates and present a prefix as the circuit's end state. 11 X gates
    % on |0⟩ end at |1⟩; a truncated prefix would land on |0⟩.
    m = CircuitModel(1);
    for k = 1:11; m.addGate('x', 0); end
    steps = StatevectorSimulator.simulate(m, struct('maxSteps', 4));
    testCase.assertLessThanOrEqual(numel(steps), 4);
    testCase.assertEqual(steps(end).psi, [0; 1], 'AbsTol', 1e-9);
    testCase.assertEqual(steps(end).gateIndex, 11);
    testCase.assertEqual(steps(end).totalGates, 11);
end

function test_steps_carry_gate_index_and_total(testCase)
    % The Inspect footer reports progress in GATES, not retained steps,
    % so a sampled walkthrough can't misreport "255 / 255" as complete.
    m = CircuitModel(1);
    m.addGate('h', 0);
    m.addGate('x', 0);
    steps = StatevectorSimulator.simulate(m);
    testCase.assertEqual(steps(1).gateIndex, 0);      % initial state
    testCase.assertEqual(steps(1).totalGates, 2);
    testCase.assertEqual(steps(end).gateIndex, 2);
    testCase.assertEqual(steps(end).totalGates, 2);
end

function test_bloch_of_entangled_qubit_is_maximally_mixed(testCase)
    % Reduced-density math on a genuinely entangled state — the case a
    % vectorised partial trace is most likely to get wrong. Each half of
    % a Bell pair has ⟨X⟩=⟨Y⟩=⟨Z⟩=0.
    m = CircuitModel(2);
    m.addGate('h', 0);
    m.addGate('cx', [0 1]);
    steps = StatevectorSimulator.simulate(m);
    bloch = steps(end).blochPerQubit;
    testCase.assertEqual(bloch, zeros(2, 3), 'AbsTol', 1e-9);
end

function test_bloch_tracks_the_untouched_qubit(testCase)
    % Asymmetric state: q0 = |+⟩, q1 = |1⟩. Catches a partial trace that
    % reshapes on the wrong bit (the two qubits would swap answers).
    m = CircuitModel(2);
    m.addGate('h', 0);
    m.addGate('x', 1);
    steps = StatevectorSimulator.simulate(m);
    bloch = steps(end).blochPerQubit;
    testCase.assertEqual(bloch(1, :), [1 0  0], 'AbsTol', 1e-9);   % q0 = |+⟩
    testCase.assertEqual(bloch(2, :), [0 0 -1], 'AbsTol', 1e-9);   % q1 = |1⟩
end

function test_swap_exchanges_qubit_states(testCase)
    % SWAP + CCX are the index-arithmetic-heaviest gates; verify against
    % an analytic reference so a vectorised rewrite can't drift.
    m = CircuitModel(2);
    m.addGate('x', 0);
    m.addGate('swap', [0 1]);
    steps = StatevectorSimulator.simulate(m);
    expected = zeros(4, 1);
    expected(3) = 1;    % |10⟩ — bit 1 set, bit 0 clear
    testCase.assertEqual(steps(end).psi, expected, 'AbsTol', 1e-9);
end

function test_ccx_flips_target_only_when_both_controls_set(testCase)
    m = CircuitModel(3);
    m.addGate('x', 0);
    m.addGate('ccx', [0 1 2]);   % q1 is |0⟩ ⇒ no flip
    noFlip = StatevectorSimulator.simulate(m);
    expected = zeros(8, 1); expected(2) = 1;   % |001⟩
    testCase.assertEqual(noFlip(end).psi, expected, 'AbsTol', 1e-9);

    m2 = CircuitModel(3);
    m2.addGate('x', 0);
    m2.addGate('x', 1);
    m2.addGate('ccx', [0 1 2]);
    flip = StatevectorSimulator.simulate(m2);
    expected2 = zeros(8, 1); expected2(8) = 1; % |111⟩
    testCase.assertEqual(flip(end).psi, expected2, 'AbsTol', 1e-9);
end

function test_reset_projects_onto_zero(testCase)
    m = CircuitModel(1);
    m.addGate('x', 0);
    m.addGate('reset', 0);
    steps = StatevectorSimulator.simulate(m);
    testCase.assertEqual(steps(end).psi, [1; 0], 'AbsTol', 1e-9);
end
