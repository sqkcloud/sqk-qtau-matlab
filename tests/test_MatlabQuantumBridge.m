% test_MatlabQuantumBridge.m ──────────────────────────────────────────────────
% Unit tests for the MATLAB Support Package interop bridge.
% Support-Package-dependent cases assumeTrue(isAvailable) so CI without the
% add-on reports them Incomplete (skipped), not failed.
%
% Run from the project root:
%   >> runtests('tests/test_MatlabQuantumBridge')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_MatlabQuantumBridge
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
end

function test_isAvailable_returns_scalar_logical(testCase)
    tf = MatlabQuantumBridge.isAvailable();
    testCase.assertTrue(islogical(tf) && isscalar(tf));
end

function test_toQuantumCircuit_index_shift_cx(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    m = CircuitModel(2);
    m.addGate('cx', [0 1]);
    qc = MatlabQuantumBridge.toQuantumCircuit(m);
    testCase.assertEqual(qc.NumQubits, 2);
    g = qc.Gates(1);
    testCase.assertEqual(double(g.ControlQubits), 1);  % internal 0 -> matlab 1
    testCase.assertEqual(double(g.TargetQubits),  2);  % internal 1 -> matlab 2
end

function test_toQuantumCircuit_empty_gates_uses_n_only_ctor(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    m = CircuitModel(3);
    m.addGate('measure', 0);   % dropped -> no gates
    qc = MatlabQuantumBridge.toQuantumCircuit(m);
    testCase.assertEqual(qc.NumQubits, 3);
    testCase.assertEqual(numel(qc.Gates), 0);
end

function test_toQuantumCircuit_rejects_reset(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    m = CircuitModel(1);
    m.addGate('h', 0); m.addGate('reset', 0);
    testCase.verifyError(@() MatlabQuantumBridge.toQuantumCircuit(m), ...
        'MatlabQuantumBridge:UnsupportedNativeOp');
end

function test_roundtrip_identity_all_mapped_gates(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    m = CircuitModel(3);
    m.addGate('h', 0);
    m.addGate('cx', [0 1]);
    m.addGate('ccx', [0 1 2]);
    m.addGate('rx', 2, pi/3);
    m.addGate('sdg', 1);
    m.addGate('swap', [0 2]);
    qc = MatlabQuantumBridge.toQuantumCircuit(m);
    m2 = MatlabQuantumBridge.fromQuantumCircuit(qc);
    testCase.assertEqual(m2.NumQubits, m.NumQubits);
    testCase.assertEqual(numel(m2.Gates), numel(m.Gates));
    for i = 1:numel(m.Gates)
        testCase.assertEqual(m2.Gates(i).kind,   m.Gates(i).kind);
        testCase.assertEqual(m2.Gates(i).qubits, m.Gates(i).qubits);
    end
    % rotation param preserved within tolerance
    testCase.assertEqual(m2.Gates(4).params(1), pi/3, 'AbsTol', 1e-12);
end

% isa() returns false for unknown classes, so this passes with or without the add-on - no assumeTrue needed.
function test_fromQuantumCircuit_rejects_non_circuit(testCase)
    testCase.verifyError(@() MatlabQuantumBridge.fromQuantumCircuit(42), ...
        'MatlabQuantumBridge:NotAQuantumCircuit');
end

function test_fromQuantumCircuit_errors_on_unsupported_gate(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    qc = quantumCircuit(cyGate(1, 2));   % cy is outside the Composer palette
    testCase.verifyError(@() MatlabQuantumBridge.fromQuantumCircuit(qc), ...
        'MatlabQuantumBridge:UnsupportedGate');
end

function test_simulateNative_matches_handrolled_per_qubit(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    m = CircuitModel(2);
    m.addGate('x', 0);   % q0 -> |1>  => P(0)=0
    m.addGate('h', 1);   % q1 -> |+>  => P(0)=0.5
    out = MatlabQuantumBridge.simulateNative(m);
    steps = StatevectorSimulator.simulate(m);
    bloch = steps(end).blochPerQubit;          % n x 3, column 3 is <Z>
    expectedP0 = (1 + bloch(:, 3)') / 2;       % row vector, endianness/phase-safe
    testCase.assertEqual(out.zeroProbs, expectedP0, 'AbsTol', 1e-9);
end

function test_simulateNative_bell_marginals(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    out = MatlabQuantumBridge.simulateNative(m);
    testCase.assertEqual(out.zeroProbs, [0.5 0.5], 'AbsTol', 1e-9);
end

function test_simulateNative_rejects_reset(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    m = CircuitModel(1);
    m.addGate('h', 0); m.addGate('reset', 0);
    testCase.verifyError(@() MatlabQuantumBridge.simulateNative(m), ...
        'MatlabQuantumBridge:UnsupportedNativeOp');
end

function test_pushToWorkspace_roundtrip(testCase)
    MatlabQuantumBridge.pushToWorkspace('qtau_test_push', 42);
    got = evalin('base', 'qtau_test_push');
    testCase.assertEqual(got, 42);
    evalin('base', 'clear qtau_test_push');
end

function test_pushToWorkspace_rejects_bad_name(testCase)
    testCase.verifyError(@() MatlabQuantumBridge.pushToWorkspace('2bad name', 1), ...
        'MatlabQuantumBridge:BadName');
end

function test_listWorkspaceCircuits_filters_by_class(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    assignin('base', 'qtau_qc_a',  quantumCircuit(2));
    assignin('base', 'qtau_not_qc', 7);
    names = MatlabQuantumBridge.listWorkspaceCircuits();
    testCase.assertTrue(any(names == "qtau_qc_a"));
    testCase.assertFalse(any(names == "qtau_not_qc"));
    evalin('base', 'clear qtau_qc_a qtau_not_qc');
end

function test_importByName_roundtrips_through_model(testCase)
    testCase.assumeTrue(MatlabQuantumBridge.isAvailable());
    assignin('base', 'qtau_imp_qc', quantumCircuit([hGate(1); cxGate(1, 2)], 2));
    model = MatlabQuantumBridge.importByName('qtau_imp_qc');
    testCase.assertEqual(model.NumQubits, 2);
    testCase.assertEqual(model.Gates(1).kind, 'h');
    testCase.assertEqual(model.Gates(2).kind, 'cx');
    evalin('base', 'clear qtau_imp_qc');
end

function test_importByName_missing_var_errors(testCase)
    testCase.verifyError(@() MatlabQuantumBridge.importByName('qtau_nope_xyz'), ...
        'MatlabQuantumBridge:NotFound');
end
