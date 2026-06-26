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

% ── MATLAB data import (numeric / table → parametric circuit) ─────────────────
% These need no Support Package — pure base-workspace I/O + CircuitModel.
function test_listWorkspaceData_filters_numeric_and_table(testCase)
    assignin('base', 'qtau_d_vec', [0.1 0.2 0.3]);
    assignin('base', 'qtau_d_tbl', table([1; 2; 3]));
    assignin('base', 'qtau_d_txt', 'not data');
    names = MatlabQuantumBridge.listWorkspaceData();
    testCase.assertTrue(any(names == "qtau_d_vec"));
    testCase.assertTrue(any(names == "qtau_d_tbl"));
    testCase.assertFalse(any(names == "qtau_d_txt"));
    evalin('base', 'clear qtau_d_vec qtau_d_tbl qtau_d_txt');
end

function test_importAnglesByName_flattens_vector(testCase)
    assignin('base', 'qtau_ang', [0.5 1.0 1.5]);
    a = MatlabQuantumBridge.importAnglesByName('qtau_ang');
    testCase.assertEqual(a, [0.5 1.0 1.5], 'AbsTol', 1e-12);
    testCase.assertEqual(size(a, 1), 1);   % row vector
    evalin('base', 'clear qtau_ang');
end

function test_importAnglesByName_reads_table_numeric(testCase)
    assignin('base', 'qtau_angt', table([0.2; 0.4]));
    a = MatlabQuantumBridge.importAnglesByName('qtau_angt');
    testCase.assertEqual(numel(a), 2);
    testCase.assertEqual(a(1), 0.2, 'AbsTol', 1e-12);
    evalin('base', 'clear qtau_angt');
end

function test_importAnglesByName_rejects_non_numeric(testCase)
    assignin('base', 'qtau_bad', 'hello');
    testCase.verifyError(@() MatlabQuantumBridge.importAnglesByName('qtau_bad'), ...
        'MatlabQuantumBridge:NotNumeric');
    evalin('base', 'clear qtau_bad');
end

function test_importAnglesByName_missing_var_errors(testCase)
    testCase.verifyError(@() MatlabQuantumBridge.importAnglesByName('qtau_absent_xyz'), ...
        'MatlabQuantumBridge:NotFound');
end

function test_importAnglesByName_rejects_mixed_type_table(testCase)
    assignin('base', 'qtau_mixtbl', table([1; 2], ["a"; "b"]));
    testCase.verifyError(@() MatlabQuantumBridge.importAnglesByName('qtau_mixtbl'), ...
        'MatlabQuantumBridge:NotNumeric');
    evalin('base', 'clear qtau_mixtbl');
end

function test_circuitFromAngles_builds_ry_and_cx_chain(testCase)
    m = MatlabQuantumBridge.circuitFromAngles([0.3 0.6 0.9]);
    testCase.assertEqual(m.NumQubits, 3);
    testCase.assertEqual(numel(m.Gates), 5);    % 3 Ry + 2 CX
    testCase.assertEqual(m.Gates(1).kind, 'ry');
    testCase.assertEqual(m.Gates(1).params, 0.3, 'AbsTol', 1e-12);
    testCase.assertEqual(m.Gates(4).kind, 'cx');
    testCase.assertEqual(m.Gates(4).qubits, [0 1]);
end

function test_circuitFromAngles_caps_at_max_qubits(testCase)
    m = MatlabQuantumBridge.circuitFromAngles(0.1 * ones(1, 40));
    testCase.assertEqual(m.NumQubits, CircuitModel.MAX_QUBITS);
end

function test_circuitFromAngles_rejects_empty(testCase)
    testCase.verifyError(@() MatlabQuantumBridge.circuitFromAngles([]), ...
        'MatlabQuantumBridge:NotFiniteReal');
end
