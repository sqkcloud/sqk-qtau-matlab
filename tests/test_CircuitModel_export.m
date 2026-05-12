% test_CircuitModel_export.m ─────────────────────────────────────────────────
% Tests for the multi-target export emitters on CircuitModel:
%   toQasm3 · toQiskitPython · toCirqPython · toBraketPython
%
% Run from the project root:
%   >> runtests('tests/test_CircuitModel_export')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_CircuitModel_export
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
end

% ── OpenQASM 3 ──────────────────────────────────────────────────────────────
function test_qasm3_uses_qubit_array_decl(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    txt = m.toQasm3();
    testCase.assertSubstring(txt, 'OPENQASM 3.0;');
    testCase.assertSubstring(txt, 'qubit[2] q;');
    testCase.assertSubstring(txt, 'bit[2] c;');
end

function test_qasm3_measure_uses_assignment_form(testCase)
    m = CircuitModel(1);
    m.addGate('measure', 0);
    txt = m.toQasm3();
    testCase.assertSubstring(txt, 'c[0] = measure q[0];');
end

% ── Qiskit Python ───────────────────────────────────────────────────────────
function test_qiskit_emits_imports_and_constructor(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    txt = m.toQiskitPython();
    testCase.assertSubstring(txt, 'from qiskit import QuantumCircuit');
    testCase.assertSubstring(txt, 'qc = QuantumCircuit(2, 2)');
    testCase.assertSubstring(txt, 'qc.h(0)');
    testCase.assertSubstring(txt, 'qc.cx(0, 1)');
end

function test_qiskit_emits_np_pi_for_rotations(testCase)
    m = CircuitModel(1);
    m.addGate('rx', 0, pi/2);
    txt = m.toQiskitPython();
    testCase.assertSubstring(txt, 'qc.rx(np.pi/2, 0)');
end

function test_qiskit_emits_measure_and_barrier(testCase)
    m = CircuitModel(2);
    m.addGate('barrier', []);
    m.addGate('measure', 0);
    txt = m.toQiskitPython();
    testCase.assertSubstring(txt, 'qc.barrier()');
    testCase.assertSubstring(txt, 'qc.measure(0, 0)');
end

% ── Cirq Python ─────────────────────────────────────────────────────────────
function test_cirq_emits_line_qubits_and_circuit(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    txt = m.toCirqPython();
    testCase.assertSubstring(txt, 'cirq.LineQubit.range(2)');
    testCase.assertSubstring(txt, 'cirq.H(q[0])');
    testCase.assertSubstring(txt, 'cirq.CNOT(q[0], q[1])');
end

function test_cirq_renames_ccx_to_toffoli(testCase)
    m = CircuitModel(3);
    m.addGate('ccx', [0 1 2]);
    txt = m.toCirqPython();
    testCase.assertSubstring(txt, 'cirq.TOFFOLI(q[0], q[1], q[2])');
end

function test_cirq_uses_measurement_keys(testCase)
    m = CircuitModel(1);
    m.addGate('measure', 0);
    txt = m.toCirqPython();
    testCase.assertSubstring(txt, "key='c0'");
end

% ── Braket Python ───────────────────────────────────────────────────────────
function test_braket_emits_circuit_constructor(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    txt = m.toBraketPython();
    testCase.assertSubstring(txt, 'from braket.circuits import Circuit');
    testCase.assertSubstring(txt, 'circuit = Circuit()');
    testCase.assertSubstring(txt, 'circuit.h(0)');
    testCase.assertSubstring(txt, 'circuit.cnot(0, 1)');
end

function test_braket_renames_ccx_to_ccnot(testCase)
    m = CircuitModel(3);
    m.addGate('ccx', [0 1 2]);
    txt = m.toBraketPython();
    testCase.assertSubstring(txt, 'circuit.ccnot(0, 1, 2)');
end

function test_braket_renames_sdg_tdg(testCase)
    m = CircuitModel(1);
    m.addGate('sdg', 0); m.addGate('tdg', 0);
    txt = m.toBraketPython();
    testCase.assertSubstring(txt, 'circuit.si(0)');
    testCase.assertSubstring(txt, 'circuit.ti(0)');
end

% ── Cross-cutting ────────────────────────────────────────────────────────────
function test_all_emitters_carry_header_comment(testCase)
    m = CircuitModel(1);
    m.addGate('h', 0);
    targets = {m.toQiskitPython(), m.toCirqPython(), m.toBraketPython()};
    for i = 1:numel(targets)
        testCase.assertSubstring(targets{i}, 'QTAU Connector Workspace');
    end
end

function test_empty_circuit_still_emits_scaffold(testCase)
    m = CircuitModel(2);
    testCase.assertSubstring(m.toQasm3(),        'qubit[2] q;');
    testCase.assertSubstring(m.toQiskitPython(), 'qc = QuantumCircuit(2, 2)');
    testCase.assertSubstring(m.toCirqPython(),   'cirq.LineQubit.range(2)');
    testCase.assertSubstring(m.toBraketPython(), 'circuit = Circuit()');
end
