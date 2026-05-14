% test_CircuitModel.m ─────────────────────────────────────────────────────────
% Unit tests for the CircuitModel domain class — gate manipulation,
% qubit-range validation, and round-tripping through OpenQASM 2.0.
%
% Run from the project root:
%   >> runtests('tests/test_CircuitModel')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_CircuitModel
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
end

% ── Construction + basic invariants ──────────────────────────────────────────
function test_default_qubit_count(testCase)
    m = CircuitModel();
    testCase.assertEqual(m.NumQubits, 1);
    testCase.assertTrue(m.isEmpty());
    testCase.assertEqual(m.depth(), 0);
end

function test_clamps_to_max_qubits(testCase)
    m = CircuitModel(99);
    testCase.assertEqual(m.NumQubits, CircuitModel.MAX_QUBITS);
end

% ── addGate ──────────────────────────────────────────────────────────────────
function test_addGate_h_appends(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0);
    testCase.assertEqual(m.depth(), 1);
    testCase.assertEqual(m.Gates(1).kind, 'h');
    testCase.assertEqual(m.Gates(1).qubits, 0);
end

function test_addGate_rejects_unsupported_kind(testCase)
    m = CircuitModel(1);
    testCase.verifyError(@() m.addGate('foobar', 0), 'CircuitModel:UnsupportedGate');
end

function test_addGate_rejects_qubit_out_of_range(testCase)
    m = CircuitModel(2);
    testCase.verifyError(@() m.addGate('h', 5), 'CircuitModel:QubitOutOfRange');
end

% ── setNumQubits drops out-of-range gates ────────────────────────────────────
function test_setNumQubits_drops_out_of_range(testCase)
    m = CircuitModel(3);
    m.addGate('h', 0); m.addGate('h', 2);
    m.setNumQubits(2);
    testCase.assertEqual(m.NumQubits, 2);
    testCase.assertEqual(numel(m.Gates), 1);
    testCase.assertEqual(m.Gates(1).qubits, 0);
end

% ── toQasm ───────────────────────────────────────────────────────────────────
function test_toQasm_emits_header_and_gates(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0);
    m.addGate('cx', [0 1]);
    txt = m.toQasm();
    testCase.assertSubstring(txt, 'OPENQASM 2.0;');
    testCase.assertSubstring(txt, 'qreg q[2];');
    testCase.assertSubstring(txt, 'h q[0];');
    testCase.assertSubstring(txt, 'cx q[0],q[1];');
end

function test_toQasm_renders_pi_rotations_symbolically(testCase)
    m = CircuitModel(1);
    m.addGate('rx', 0, pi/2);
    txt = m.toQasm();
    testCase.assertSubstring(txt, 'rx(pi/2)');
end

% ── fromQasm round-trip ──────────────────────────────────────────────────────
function test_round_trip_bell(testCase)
    src = CircuitModel(2);
    src.addGate('h', 0);
    src.addGate('cx', [0 1]);
    parsed = CircuitModel.fromQasm(src.toQasm());
    testCase.assertEqual(parsed.NumQubits, 2);
    testCase.assertEqual(parsed.depth(), 2);
    testCase.assertEqual(parsed.Gates(1).kind, 'h');
    testCase.assertEqual(parsed.Gates(2).kind, 'cx');
    testCase.assertEqual(parsed.Gates(2).qubits, [0 1]);
end

function test_round_trip_with_rotation(testCase)
    src = CircuitModel(1);
    src.addGate('rz', 0, pi/4);
    parsed = CircuitModel.fromQasm(src.toQasm());
    testCase.assertEqual(parsed.depth(), 1);
    testCase.assertEqual(parsed.Gates(1).kind, 'rz');
    testCase.assertEqual(parsed.Gates(1).params, pi/4, 'AbsTol', 1e-9);
end

function test_fromQasm_rejects_unsupported_statement(testCase)
    qasm = sprintf('OPENQASM 2.0;\nqreg q[1];\nfoobar q[0];');
    testCase.verifyError(@() CircuitModel.fromQasm(qasm), 'CircuitModel:Parse');
end

function test_fromQasm_handles_measurements(testCase)
    qasm = sprintf(['OPENQASM 2.0;\ninclude "qelib1.inc";\n' ...
                    'qreg q[2];\ncreg c[2];\nh q[0];\nmeasure q[0] -> c[0];']);
    m = CircuitModel.fromQasm(qasm);
    testCase.assertEqual(numel(m.Gates), 2);
    testCase.assertEqual(m.Gates(2).kind, 'measure');
end

function test_fromQasm_evals_pi_expressions(testCase)
    qasm = sprintf('OPENQASM 2.0;\nqreg q[1];\nrx(pi/3) q[0];');
    m = CircuitModel.fromQasm(qasm);
    testCase.assertEqual(m.Gates(1).params, pi/3, 'AbsTol', 1e-9);
end
