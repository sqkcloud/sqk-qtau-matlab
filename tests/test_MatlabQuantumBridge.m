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
