# MATLAB Quantum Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a MATLAB user import a workspace `quantumCircuit` into the app, simulate it with MATLAB's native engine, export the Composer circuit back as a `quantumCircuit` script, push results to the base workspace, and reach the Composer offline (no backend login).

**Architecture:** A single static service `MatlabQuantumBridge` is the *only* module that touches the MATLAB Support Package for Quantum Computing API; it converts between the app's `CircuitModel` (0-indexed gate structs) and `quantumCircuit` (1-indexed gate objects). A new `CircuitModel.toMatlabScript` emitter mirrors the existing Qiskit/Cirq/Braket emitters. UI wiring adds a MATLAB export target, an import dialog, a push-to-workspace action, and a native-`simulate` parity flash. Auth is decoupled by classifying the Composer as offline-capable so the `AuthOverlay` no longer covers it.

**Tech Stack:** MATLAB R2025b, MATLAB Support Package for Quantum Computing (`quantumCircuit`, `simulate`, gate constructors), `matlab.unittest` function-based tests (`functiontests`).

**Spec:** [`../specs/2026-06-23-matlab-quantum-bridge-design.md`](../specs/2026-06-23-matlab-quantum-bridge-design.md)

---

## Conventions for this plan

- Run all tests **from the project root** in MATLAB: `runtests('tests/<file>')`.
- Tests that need the Support Package call `testCase.assumeTrue(MatlabQuantumBridge.isAvailable())` — on a machine without the add-on they report **Incomplete** (skipped), not failed. That is the expected pass state in CI-without-add-on.
- Index convention everywhere: **internal qubit `q` (0-based) ↔ MATLAB qubit `q+1` (1-based)**.
- Commits: Conventional Commits; **no AI-attribution footer**.
- The gate knowledge appears in three layers by design — `CircuitModel.gateToMatlabLine` (source-text emit), `MatlabQuantumBridge.kindToGate` (object build), `MatlabQuantumBridge.typeToKind` (object parse). The spec §4 table is the conceptual source of truth; keep all three in sync.

## File structure

| File | Responsibility | Action |
|---|---|---|
| `src/domain/services/MatlabQuantumBridge.m` | All Support-Package interop (convert / simulate / workspace I/O) | Create |
| `src/domain/models/CircuitModel.m` | Add `toMatlabScript` + private `gateToMatlabLine` | Modify |
| `resources/labels.properties` | New UI strings | Modify |
| `src/presentation/viewmodels/ComposerViewModel.m` | Export MATLAB target, import dialog, push action, parity flash | Modify |
| `src/presentation/screens/ComposerScreen.m` | "Import from MATLAB" toolbar button | Modify |
| `src/presentation/app/NavigationManager.m` | `isOfflineCapable` + `refreshAuthOverlay` + wire in `onSelectSection` | Modify |
| `src/presentation/screens/WelcomeScreen.m` | "Explore offline →" hero button | Modify |
| `tests/test_MatlabQuantumBridge.m` | Bridge unit tests | Create |
| `tests/test_CircuitModel_export.m` | `toMatlabScript` emitter tests | Modify |
| `tests/test_NavigationManager.m` | `isOfflineCapable` unit test | Create |

---

## Task 1: Scaffold MatlabQuantumBridge + isAvailable()

**Files:**
- Create: `src/domain/services/MatlabQuantumBridge.m`
- Create: `tests/test_MatlabQuantumBridge.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_MatlabQuantumBridge.m`:

```matlab
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: FAIL — `Unrecognized function or variable 'MatlabQuantumBridge'`.

- [ ] **Step 3: Write minimal implementation**

Create `src/domain/services/MatlabQuantumBridge.m`:

```matlab
classdef MatlabQuantumBridge
    % MatlabQuantumBridge  Interop between the app's CircuitModel and the
    %   MATLAB Support Package for Quantum Computing (`quantumCircuit`).
    %   The ONLY module that references Support-Package API — every other
    %   feature degrades gracefully when the add-on is absent.
    %
    %   Index convention: internal CircuitModel qubits are 0-indexed
    %   (QASM style); quantumCircuit qubits are 1-indexed. The ±1 shift is
    %   applied in fromQuantumCircuit / kindToGate only.

    methods (Static)
        function tf = isAvailable()
            tf = exist('quantumCircuit', 'class') == 8;
        end
    end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: PASS (1 passed).

- [ ] **Step 5: Commit**

```bash
git add src/domain/services/MatlabQuantumBridge.m tests/test_MatlabQuantumBridge.m
git commit -m "feat(bridge): scaffold MatlabQuantumBridge with add-on capability check"
```

---

## Task 2: CircuitModel.toMatlabScript emitter

**Files:**
- Modify: `src/domain/models/CircuitModel.m` (add public `toMatlabScript`, private `gateToMatlabLine`)
- Test: `tests/test_CircuitModel_export.m`

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_CircuitModel_export.m` (add these functions among the existing ones):

```matlab
% ── MATLAB (quantumCircuit) ───────────────────────────────────────────────────
function test_matlab_emits_gate_array_and_constructor(testCase)
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    txt = m.toMatlabScript();
    testCase.assertSubstring(txt, 'hGate(1)');
    testCase.assertSubstring(txt, 'cxGate(1, 2)');
    testCase.assertSubstring(txt, 'quantumCircuit(gates, 2)');
end

function test_matlab_rotation_uses_bare_pi(testCase)
    m = CircuitModel(1);
    m.addGate('rx', 0, pi/2);
    txt = m.toMatlabScript();
    testCase.assertSubstring(txt, 'rxGate(1, pi/2)');
end

function test_matlab_renames_sdg_tdg_and_shifts_ccx(testCase)
    m = CircuitModel(3);
    m.addGate('sdg', 0); m.addGate('tdg', 1); m.addGate('ccx', [0 1 2]);
    txt = m.toMatlabScript();
    testCase.assertSubstring(txt, 'siGate(1)');
    testCase.assertSubstring(txt, 'tiGate(2)');
    testCase.assertSubstring(txt, 'ccxGate(1, 2, 3)');
end

function test_matlab_drops_measure_to_comment_and_uses_n_only_ctor(testCase)
    m = CircuitModel(1);
    m.addGate('measure', 0);
    txt = m.toMatlabScript();
    testCase.assertSubstring(txt, '% measure');
    testCase.assertSubstring(txt, 'quantumCircuit(1);');  % empty-gates branch
end

function test_matlab_carries_header_comment(testCase)
    m = CircuitModel(1);
    m.addGate('h', 0);
    testCase.assertSubstring(m.toMatlabScript(), 'QTAU');
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `runtests('tests/test_CircuitModel_export')`
Expected: FAIL — `Unrecognized method 'toMatlabScript' for class 'CircuitModel'`.

- [ ] **Step 3: Write minimal implementation**

In `src/domain/models/CircuitModel.m`, add a public method after `toBraketPython` (ends ~line 190, inside the first `methods` block):

```matlab
        % ── MATLAB (quantumCircuit) ──────────────────────────────────────
        function txt = toMatlabScript(obj)
            % Emits a script that reconstructs this circuit as a MATLAB
            % `quantumCircuit` object (1-indexed). measure / barrier /
            % reset have no quantumCircuit equivalent and are emitted as
            % trailing comments. Requires the Support Package to RUN, but
            % emitting the text does not.
            n = max(1, obj.NumQubits);
            lines = {
                sprintf('%% Generated by %s', AppConfig.get('app_name', 'QTAU: Hardware-Agnostic Execution'))
                '% Requires the MATLAB Support Package for Quantum Computing.'
            };
            gateLines = {};
            dropLines = {};
            for i = 1:numel(obj.Gates)
                [ln, isDrop] = CircuitModel.gateToMatlabLine(obj.Gates(i));
                if isDrop
                    dropLines{end+1} = ln; %#ok<AGROW>
                else
                    gateLines{end+1} = sprintf('    %s', ln); %#ok<AGROW>
                end
            end
            if isempty(gateLines)
                lines{end+1} = sprintf('qc = quantumCircuit(%d);', n);
            else
                lines{end+1} = 'gates = [';
                for i = 1:numel(gateLines)
                    lines{end+1} = gateLines{i}; %#ok<AGROW>
                end
                lines{end+1} = '];';
                lines{end+1} = sprintf('qc = quantumCircuit(gates, %d);', n);
            end
            for i = 1:numel(dropLines)
                lines{end+1} = dropLines{i}; %#ok<AGROW>
            end
            txt = strjoin(lines, sprintf('\n'));
        end
```

Then add a private static helper after `gateToBraketLine` (inside the `methods (Static, Access = private)` block):

```matlab
        function [line, isDrop] = gateToMatlabLine(g)
            isDrop = false;
            % 0-indexed internal qubit -> 1-indexed MATLAB qubit.
            q = @(idx) g.qubits(idx) + 1;
            switch lower(g.kind)
                case 'h';    line = sprintf('hGate(%d)',  q(1));
                case 'x';    line = sprintf('xGate(%d)',  q(1));
                case 'y';    line = sprintf('yGate(%d)',  q(1));
                case 'z';    line = sprintf('zGate(%d)',  q(1));
                case 's';    line = sprintf('sGate(%d)',  q(1));
                case 't';    line = sprintf('tGate(%d)',  q(1));
                case 'sdg';  line = sprintf('siGate(%d)', q(1));
                case 'tdg';  line = sprintf('tiGate(%d)', q(1));
                case {'rx','ry','rz'}
                    line = sprintf('%sGate(%d, %s)', g.kind, q(1), ...
                        CircuitModel.formatTheta(g.params(1)));
                case 'cx';   line = sprintf('cxGate(%d, %d)',   q(1), q(2));
                case 'cz';   line = sprintf('czGate(%d, %d)',   q(1), q(2));
                case 'swap'; line = sprintf('swapGate(%d, %d)', q(1), q(2));
                case 'ccx';  line = sprintf('ccxGate(%d, %d, %d)', q(1), q(2), q(3));
                case 'reset'
                    line = sprintf('%% reset q[%d] — no quantumCircuit equivalent', g.qubits(1));
                    isDrop = true;
                case 'measure'
                    line = sprintf('%% measure q[%d] — implicit in simulate()', g.qubits(1));
                    isDrop = true;
                case 'barrier'
                    line = '% barrier — no quantumCircuit equivalent';
                    isDrop = true;
                otherwise
                    line = sprintf('%% unsupported gate: %s', g.kind);
                    isDrop = true;
            end
        end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `runtests('tests/test_CircuitModel_export')`
Expected: PASS (all, including the 5 new MATLAB cases).

- [ ] **Step 5: Commit**

```bash
git add src/domain/models/CircuitModel.m tests/test_CircuitModel_export.m
git commit -m "feat(composer): add toMatlabScript quantumCircuit code emitter"
```

---

## Task 3: MatlabQuantumBridge.toQuantumCircuit

**Files:**
- Modify: `src/domain/services/MatlabQuantumBridge.m`
- Test: `tests/test_MatlabQuantumBridge.m`

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_MatlabQuantumBridge.m`:

```matlab
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: FAIL — `Unrecognized method 'toQuantumCircuit'` (Incomplete instead, if no add-on; on a dev machine WITH the add-on, FAIL).

- [ ] **Step 3: Write minimal implementation**

Add to the `methods (Static)` block of `MatlabQuantumBridge`:

```matlab
        function qc = toQuantumCircuit(model)
            if ~MatlabQuantumBridge.isAvailable()
                error('MatlabQuantumBridge:NotAvailable', ...
                    'MATLAB Support Package for Quantum Computing is not installed.');
            end
            gates = [];
            for i = 1:numel(model.Gates)
                g = model.Gates(i);
                switch g.kind
                    case {'measure', 'barrier'}
                        continue;  % no quantumCircuit equivalent
                    case 'reset'
                        error('MatlabQuantumBridge:UnsupportedNativeOp', ...
                            ['Circuits with reset cannot be converted to a ' ...
                             'quantumCircuit; use the local simulator.']);
                end
                gates = [gates; MatlabQuantumBridge.kindToGate(g)]; %#ok<AGROW>
            end
            if isempty(gates)
                qc = quantumCircuit(model.NumQubits);
            else
                qc = quantumCircuit(gates, model.NumQubits);
            end
        end
```

And a private helper in a new `methods (Static, Access = private)` block:

```matlab
    methods (Static, Access = private)
        function gate = kindToGate(g)
            q = g.qubits + 1;  % 0-indexed internal -> 1-indexed MATLAB
            switch g.kind
                case 'h';    gate = hGate(q(1));
                case 'x';    gate = xGate(q(1));
                case 'y';    gate = yGate(q(1));
                case 'z';    gate = zGate(q(1));
                case 's';    gate = sGate(q(1));
                case 't';    gate = tGate(q(1));
                case 'sdg';  gate = siGate(q(1));
                case 'tdg';  gate = tiGate(q(1));
                case 'rx';   gate = rxGate(q(1), g.params(1));
                case 'ry';   gate = ryGate(q(1), g.params(1));
                case 'rz';   gate = rzGate(q(1), g.params(1));
                case 'cx';   gate = cxGate(q(1), q(2));
                case 'cz';   gate = czGate(q(1), q(2));
                case 'swap'; gate = swapGate(q(1), q(2));
                case 'ccx';  gate = ccxGate(q(1), q(2), q(3));
                otherwise
                    error('MatlabQuantumBridge:UnsupportedGate', ...
                        'Gate kind "%s" has no quantumCircuit mapping', g.kind);
            end
        end
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: PASS (or Incomplete for the assumed cases if no add-on installed).

- [ ] **Step 5: Commit**

```bash
git add src/domain/services/MatlabQuantumBridge.m tests/test_MatlabQuantumBridge.m
git commit -m "feat(bridge): convert CircuitModel to quantumCircuit (1-indexed, reset-guarded)"
```

---

## Task 4: MatlabQuantumBridge.fromQuantumCircuit

**Files:**
- Modify: `src/domain/services/MatlabQuantumBridge.m`
- Test: `tests/test_MatlabQuantumBridge.m`

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_MatlabQuantumBridge.m`:

```matlab
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: FAIL — `Unrecognized method 'fromQuantumCircuit'`.

- [ ] **Step 3: Write minimal implementation**

Add to the `methods (Static)` block:

```matlab
        function model = fromQuantumCircuit(qc)
            if ~(isscalar(qc) && isa(qc, 'quantumCircuit'))
                error('MatlabQuantumBridge:NotAQuantumCircuit', ...
                    'Expected a scalar quantumCircuit, got %s', class(qc));
            end
            model = CircuitModel(qc.NumQubits);
            gates = qc.Gates;
            for i = 1:numel(gates)
                g = gates(i);
                kind = MatlabQuantumBridge.typeToKind(g.Type);
                % MATLAB order is [control(s) target(s)]; the internal
                % model uses the same order. Shift 1-indexed -> 0-indexed.
                qubits = [double(g.ControlQubits(:)'), double(g.TargetQubits(:)')] - 1;
                if any(strcmp(kind, {'rx', 'ry', 'rz'}))
                    model.addGate(kind, qubits, double(g.Angles(1)));
                else
                    model.addGate(kind, qubits);
                end
            end
        end
```

Add to the `methods (Static, Access = private)` block:

```matlab
        function kind = typeToKind(t)
            t = char(t);
            map = { ...
                'h','h'; 'x','x'; 'y','y'; 'z','z'; ...
                's','s'; 'si','sdg'; 't','t'; 'ti','tdg'; ...
                'rx','rx'; 'ry','ry'; 'rz','rz'; ...
                'cx','cx'; 'cz','cz'; 'swap','swap'; 'ccx','ccx'};
            idx = find(strcmpi(map(:, 1), t), 1);
            if isempty(idx)
                error('MatlabQuantumBridge:UnsupportedGate', ...
                    ['quantumCircuit gate "%s" is not supported by the Composer. ' ...
                     'Supported: h x y z s t (and inverses si/ti) rx ry rz ' ...
                     'cx cz swap ccx.'], t);
            end
            kind = map{idx, 2};
        end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: PASS (assumed cases Incomplete if no add-on).

- [ ] **Step 5: Commit**

```bash
git add src/domain/services/MatlabQuantumBridge.m tests/test_MatlabQuantumBridge.m
git commit -m "feat(bridge): import quantumCircuit to CircuitModel with gate-type mapping"
```

---

## Task 5: MatlabQuantumBridge.simulateNative + parity

**Files:**
- Modify: `src/domain/services/MatlabQuantumBridge.m`
- Test: `tests/test_MatlabQuantumBridge.m`

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_MatlabQuantumBridge.m`:

```matlab
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: FAIL — `Unrecognized method 'simulateNative'`.

- [ ] **Step 3: Write minimal implementation**

Add to the `methods (Static)` block:

```matlab
        function out = simulateNative(model)
            % Runs MATLAB's native simulate() on the circuit. Returns the
            % final-state amplitudes plus per-qubit P(|0>) marginals
            % (endianness- and global-phase-independent — used for the
            % parity check against the local hand-rolled simulator).
            qc = MatlabQuantumBridge.toQuantumCircuit(model);  % errors on reset / no add-on
            s = simulate(qc);
            n = model.NumQubits;
            zeroProbs = zeros(1, n);
            for q = 1:n
                zeroProbs(q) = probability(s, q, "0");
            end
            out = struct('amplitudes', s.Amplitudes, ...
                         'zeroProbs',  zeroProbs, ...
                         'numQubits',  n);
        end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: PASS (assumed cases Incomplete if no add-on).

- [ ] **Step 5: Commit**

```bash
git add src/domain/services/MatlabQuantumBridge.m tests/test_MatlabQuantumBridge.m
git commit -m "feat(bridge): native simulate() with per-qubit parity marginals"
```

---

## Task 6: Workspace I/O (list / import / push)

**Files:**
- Modify: `src/domain/services/MatlabQuantumBridge.m`
- Test: `tests/test_MatlabQuantumBridge.m`

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_MatlabQuantumBridge.m`:

```matlab
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: FAIL — `Unrecognized method 'pushToWorkspace'`.

- [ ] **Step 3: Write minimal implementation**

Add to the `methods (Static)` block:

```matlab
        function names = listWorkspaceCircuits()
            names = string.empty(1, 0);
            try
                vars = evalin('base', 'whos');
            catch
                return;
            end
            if isempty(vars); return; end
            isQc = strcmp({vars.class}, 'quantumCircuit');
            if any(isQc)
                names = string({vars(isQc).name});
            end
        end

        function model = importByName(name)
            name = char(name);
            if ~isvarname(name)
                error('MatlabQuantumBridge:BadName', ...
                    'Not a valid variable name: %s', name);
            end
            if ~evalin('base', sprintf('exist(''%s'', ''var'')', name))
                error('MatlabQuantumBridge:NotFound', ...
                    'No workspace variable named %s', name);
            end
            qc = evalin('base', name);
            model = MatlabQuantumBridge.fromQuantumCircuit(qc);
        end

        function pushToWorkspace(name, value)
            name = char(name);
            if ~isvarname(name)
                error('MatlabQuantumBridge:BadName', ...
                    'Not a valid variable name: %s', name);
            end
            assignin('base', name, value);
        end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `runtests('tests/test_MatlabQuantumBridge')`
Expected: PASS (assumed cases Incomplete if no add-on).

- [ ] **Step 5: Commit**

```bash
git add src/domain/services/MatlabQuantumBridge.m tests/test_MatlabQuantumBridge.m
git commit -m "feat(bridge): base-workspace list/import/push helpers"
```

---

## Task 7: Add UI label strings

**Files:**
- Modify: `resources/labels.properties`

- [ ] **Step 1: Add keys**

Append to the composer section of `resources/labels.properties` (after the `composer_export_fmt_braket` line, ~line 1139):

```properties
composer_export_fmt_matlab  = MATLAB (quantumCircuit)
composer_btn_import_matlab  = Import MATLAB
composer_import_title       = Import — MATLAB quantumCircuit
composer_import_var_lbl     = Workspace variable
composer_import_btn         = Import
composer_export_btn_push    = Push to workspace
composer_matlab_unavailable = MATLAB Support Package for Quantum Computing is not installed.
composer_matlab_no_circuits = No quantumCircuit variables found in the base workspace.
composer_toast_matlab_imported = Imported quantumCircuit: %s
composer_push_default_name  = qtau_circuit
composer_push_done_fmt      = Pushed quantumCircuit -> base workspace as '%s'
composer_inspect_parity_ok   = MATLAB simulate() matches local simulator
composer_inspect_parity_warn = MATLAB simulate() differs from local simulator
welcome_btn_explore_offline  = Explore offline
```

- [ ] **Step 2: Verify it loads**

Run: `Labels.reload(); disp(Labels.get('composer_export_fmt_matlab'))`
Expected: prints `MATLAB (quantumCircuit)`.

- [ ] **Step 3: Commit**

```bash
git add resources/labels.properties
git commit -m "feat(labels): add MATLAB bridge UI strings"
```

---

## Task 8: Export dialog — MATLAB target

**Files:**
- Modify: `src/presentation/viewmodels/ComposerViewModel.m` (`openExportDialog` formats cell ~line 1067; `emitForFormat` ~line 1188)

- [ ] **Step 1: Add the MATLAB format row**

In `openExportDialog`, extend the `formats` cell (after the `'braket'` row):

```matlab
            formats = {
                'qasm2',  Labels.get('composer_export_fmt_qasm2'),  'qasm';
                'qasm3',  Labels.get('composer_export_fmt_qasm3'),  'qasm';
                'qiskit', Labels.get('composer_export_fmt_qiskit'), 'py';
                'cirq',   Labels.get('composer_export_fmt_cirq'),   'py';
                'braket', Labels.get('composer_export_fmt_braket'), 'py';
                'matlab', Labels.get('composer_export_fmt_matlab'), 'm';
            };
```

- [ ] **Step 2: Add the emit case**

In `emitForFormat`, add a case before `otherwise`:

```matlab
                case 'matlab'; txt = obj.Model.toMatlabScript();
```

- [ ] **Step 3: Verify (covered by unit test + manual)**

`toMatlabScript` is already unit-tested (Task 2). Manual check:
1. Launch: `run('QTAUWorkbenchLauncher.m')`
2. Go to **Composer**, drop H on q0 and CX(0,1).
3. Toolbar → **Export** → format dropdown shows **MATLAB (quantumCircuit)**.
4. Select it → preview shows `gates = [ hGate(1) cxGate(1, 2) ];` and `qc = quantumCircuit(gates, 2);`.
5. **Save** → file saved with `.m` extension.

Expected: preview renders MATLAB code; save uses `.m`.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/viewmodels/ComposerViewModel.m
git commit -m "feat(composer): add MATLAB quantumCircuit export target"
```

---

## Task 9: Import-from-MATLAB toolbar button + dialog

**Files:**
- Modify: `src/presentation/screens/ComposerScreen.m` (`buildToolbar` ~line 59)
- Modify: `src/presentation/viewmodels/ComposerViewModel.m` (new `onImportFromMatlab` + `openImportDialog`)

- [ ] **Step 1: Add the toolbar button**

In `ComposerScreen.m` `buildToolbar`, widen the grid to 12 columns and insert the import button after `btnBundle`.

Change the grid declaration (~line 59-62):

```matlab
    grid = uigridlayout(bar, [1 12]);
    grid.Padding = [10 6 10 6];
    grid.ColumnSpacing = 8;
    grid.ColumnWidth = {120, 90, 100, 100, 100, 110, 90, 90, 90, 100, '1x', 160};
    grid.BackgroundColor = Theme.COLOR_CARD;
```

Insert immediately after the `btnBundle` block (after `vm.BtnBundle = btnBundle;`, ~line 85):

```matlab
    btnImport = uibutton(grid, 'Text', Labels.get('composer_btn_import_matlab'), ...
        'ButtonPushedFcn', @(~,~) vm.onImportFromMatlab());
    StyleHelper.styleBtn(btnImport, 'ghost');
```

- [ ] **Step 2: Add the VM methods**

In `ComposerViewModel.m`, add to the public `methods` block (near `onOpenExport`, ~line 146):

```matlab
        function onImportFromMatlab(obj)
            if ~MatlabQuantumBridge.isAvailable()
                obj.flashStatus(Labels.get('composer_matlab_unavailable'), 'danger');
                return;
            end
            names = MatlabQuantumBridge.listWorkspaceCircuits();
            if isempty(names)
                obj.flashStatus(Labels.get('composer_matlab_no_circuits'), 'info');
                return;
            end
            obj.openImportDialog(names);
        end

        function openImportDialog(obj, names)
            fig = uifigure('Name', Labels.get('composer_import_title'), ...
                'Position', [320 280 440 180], 'WindowStyle', 'modal', ...
                'Color', Theme.COLOR_BG);
            try; Theme.applyFigureMode(fig, Theme.activeName()); catch; end

            g = uigridlayout(fig, [3 2]);
            g.RowHeight = {30, 30, 50}; g.ColumnWidth = {140, '1x'};
            g.Padding = [16 16 16 16]; g.RowSpacing = 10;

            uilabel(g, 'Text', Labels.get('composer_import_var_lbl'), ...
                'FontColor', Theme.COLOR_LABEL);
            dd = uidropdown(g, 'Items', cellstr(names), 'Value', char(names(1)));

            blank1 = uilabel(g, 'Text', ''); %#ok<NASGU>
            blank2 = uilabel(g, 'Text', ''); %#ok<NASGU>

            bar = uigridlayout(g, [1 3]);
            bar.Layout.Row = 3; bar.Layout.Column = [1 2];
            bar.ColumnWidth = {'1x', 120, 120}; bar.Padding = [0 6 0 0];
            bar.BackgroundColor = Theme.COLOR_BG;
            sp = uilabel(bar, 'Text', ''); sp.Layout.Column = 1; %#ok<NASGU>

            cancelBtn = uibutton(bar, 'Text', Labels.get('composer_param_cancel'), ...
                'ButtonPushedFcn', @(~,~) close(fig));
            cancelBtn.Layout.Column = 2;
            StyleHelper.styleBtn(cancelBtn, 'ghost');

            importBtn = uibutton(bar, 'Text', Labels.get('composer_import_btn'), ...
                'ButtonPushedFcn', @(~,~) doImport());
            importBtn.Layout.Column = 3;
            StyleHelper.styleBtn(importBtn, 'primary');

            function doImport()
                name = dd.Value;
                close(fig);
                try
                    obj.Model = MatlabQuantumBridge.importByName(name);
                    obj.afterModelEdit(sprintf( ...
                        Labels.get('composer_toast_matlab_imported'), name));
                    obj.App.logEvent('COMPOSE', ...
                        sprintf('Import quantumCircuit: %s', name));
                catch ME
                    obj.flashStatus(ME.message, 'danger');
                end
            end
        end
```

- [ ] **Step 3: Verify (manual)**

1. In the MATLAB console (with the Support Package): `qc = quantumCircuit([hGate(1); cxGate(1,2)], 2);`
2. Launch: `run('QTAUWorkbenchLauncher.m')`; go to **Composer**.
3. Toolbar → **Import MATLAB** → dialog lists `qc` → select → **Import**.
4. Canvas renders H on q0 + CX(0,1); QASM mirror shows the matching QASM; status toast "Imported quantumCircuit: qc".
5. With no `quantumCircuit` var in the workspace → status shows "No quantumCircuit variables found...".

Expected: imported circuit renders correctly; empty-workspace path shows the info message.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/screens/ComposerScreen.m src/presentation/viewmodels/ComposerViewModel.m
git commit -m "feat(composer): import workspace quantumCircuit into the canvas"
```

---

## Task 10: Push quantumCircuit to workspace

**Files:**
- Modify: `src/presentation/viewmodels/ComposerViewModel.m` (`openExportDialog` footer ~line 1111; new `doPushWorkspace` nested fn)

- [ ] **Step 1: Add the push button to the export footer**

In `openExportDialog`, change the footer grid from `[1 4]` to `[1 5]` and widen the column list (~line 1111-1116):

```matlab
            footer = uigridlayout(outer, [1 5]);
            footer.Layout.Row = 4; footer.Layout.Column = 1;
            footer.ColumnWidth = {120, 120, 150, '1x', 100};
            footer.RowHeight = {36};
            footer.Padding = [0 0 0 0]; footer.ColumnSpacing = 8;
            footer.BackgroundColor = Theme.COLOR_BG;
```

Insert a push button after `btnSave` and before the `spacer` (~line 1124):

```matlab
            btnPush = uibutton(footer, 'Text', Labels.get('composer_export_btn_push'), ...
                'ButtonPushedFcn', @(~,~) doPushWorkspace());
            StyleHelper.styleBtn(btnPush, 'secondary');
```

Update the spacer column index (it was column 3, now column 4):

```matlab
            spacer = uilabel(footer, 'Text', ''); spacer.Layout.Column = 4; %#ok<NASGU>
```

And the close button moves to column 5:

```matlab
            btnClose.Layout.Column = 5;
```

- [ ] **Step 2: Add the nested handler**

Add a nested function inside `openExportDialog` (next to `doSave`):

```matlab
            function doPushWorkspace()
                if ~MatlabQuantumBridge.isAvailable()
                    statusLbl.Text = Labels.get('composer_matlab_unavailable');
                    statusLbl.FontColor = Theme.COLOR_DANGER;
                    return;
                end
                varName = Labels.get('composer_push_default_name');
                try
                    qc = MatlabQuantumBridge.toQuantumCircuit(obj.Model);
                    MatlabQuantumBridge.pushToWorkspace(varName, qc);
                    statusLbl.Text = sprintf( ...
                        Labels.get('composer_push_done_fmt'), varName);
                    statusLbl.FontColor = Theme.COLOR_SUCCESS;
                    obj.App.logEvent('COMPOSE', ...
                        sprintf('Push quantumCircuit -> base.%s', varName));
                catch ME
                    statusLbl.Text = ME.message;
                    statusLbl.FontColor = Theme.COLOR_DANGER;
                end
            end
```

(Phase-1 scope: pushes to the fixed name `qtau_circuit`. A name prompt is deferred per spec §5.3.)

- [ ] **Step 3: Verify (manual)**

1. Launch; Composer → build H(0) + CX(0,1).
2. **Export** → **Push to workspace** → status shows "Pushed quantumCircuit -> base workspace as 'qtau_circuit'".
3. In the MATLAB console: `qtau_circuit` → displays a `quantumCircuit` with 2 qubits, 2 gates.
4. A circuit containing `reset` → status shows the reset error message (UnsupportedNativeOp).

Expected: workspace variable `qtau_circuit` exists and matches.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/viewmodels/ComposerViewModel.m
git commit -m "feat(composer): push current circuit to base workspace as quantumCircuit"
```

---

## Task 11: Native-simulate parity flash in Inspect

**Files:**
- Modify: `src/presentation/viewmodels/ComposerViewModel.m` (`refreshInspect` ~line 1358; new `flashNativeParity`)

- [ ] **Step 1: Call the parity check at the end of refreshInspect**

In `refreshInspect`, after the final `obj.paintInspectStep();` (last line of the method, ~line 1381):

```matlab
            obj.paintInspectStep();
            obj.flashNativeParity();
```

- [ ] **Step 2: Add the method**

Add to the public `methods` block of `ComposerViewModel`:

```matlab
        function flashNativeParity(obj)
            % After a local-simulator refresh, cross-check the final state
            % against MATLAB's native simulate() per-qubit marginals and
            % flash the result. No-op without the add-on, on empty
            % circuits, or on circuits containing reset (no native path).
            if ~MatlabQuantumBridge.isAvailable(); return; end
            if isempty(obj.InspectSteps); return; end
            if any(strcmp({obj.Model.Gates.kind}, 'reset')); return; end
            try
                out = MatlabQuantumBridge.simulateNative(obj.Model);
                bloch = obj.InspectSteps(end).blochPerQubit;
                expectedP0 = (1 + bloch(:, 3)') / 2;
                if max(abs(out.zeroProbs - expectedP0)) < 1e-6
                    obj.flashStatus(Labels.get('composer_inspect_parity_ok'), 'success');
                else
                    obj.flashStatus(Labels.get('composer_inspect_parity_warn'), 'danger');
                end
            catch
                % Native simulation unavailable for this circuit — leave the
                % existing Inspect status untouched.
            end
        end
```

- [ ] **Step 3: Verify (manual; logic covered by Task 5 parity test)**

1. Launch (with the Support Package); Composer → build H(0) + CX(0,1) (Inspect is pinned open).
2. Status flashes "MATLAB simulate() matches local simulator".
3. Without the add-on installed → no parity flash, Inspect otherwise unchanged.

Expected: green parity flash on a reset-free circuit when the add-on is present.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/viewmodels/ComposerViewModel.m
git commit -m "feat(composer): cross-check Inspect against native simulate()"
```

---

## Task 12: Auth-decouple the Composer (offline access)

**Files:**
- Modify: `src/presentation/app/NavigationManager.m` (new `isOfflineCapable` + `refreshAuthOverlay`; wire in `onSelectSection` ~line 91)
- Create: `tests/test_NavigationManager.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_NavigationManager.m`:

```matlab
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
    addpath(fullfile(projectRoot, 'src', 'presentation', 'app'));
end

function test_composer_is_offline_capable(testCase)
    testCase.assertTrue(NavigationManager.isOfflineCapable('Composer'));
end

function test_dashboard_is_not_offline_capable(testCase)
    testCase.assertFalse(NavigationManager.isOfflineCapable('Dashboard'));
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `runtests('tests/test_NavigationManager')`
Expected: FAIL — `Unrecognized method 'isOfflineCapable'`.

- [ ] **Step 3: Add the classification + overlay decision**

In `NavigationManager.m`, add two static methods (anywhere in the `methods (Static)` block):

```matlab
        function tf = isOfflineCapable(key)
            % Screens whose core surface is fully local (no FastAPIClient)
            % and therefore usable without a backend login.
            tf = any(strcmp(char(key), {'Composer'}));
        end

        function refreshAuthOverlay(app, key)
            % Show the auth overlay only when logged out AND the active
            % screen needs the backend. Offline-capable screens render
            % with no overlay.
            if app.State.isAuthenticated() || NavigationManager.isOfflineCapable(key)
                OverlayManager.hideAuthOverlay(app);
            else
                OverlayManager.showAuthOverlay(app);
            end
            OverlayManager.fitAuthOverlay(app);
        end
```

In `onSelectSection`, replace the existing line 91:

```matlab
            OverlayManager.fitAuthOverlay(app);
```

with:

```matlab
            NavigationManager.refreshAuthOverlay(app, key);
```

- [ ] **Step 4: Run test + manual check**

Run: `runtests('tests/test_NavigationManager')`
Expected: PASS.

Manual:
1. Ensure logged out (no token). Launch `run('QTAUWorkbenchLauncher.m')`.
2. Boot lands on Dashboard → auth overlay covers content (unchanged).
3. Click **Composer** in the sidebar → overlay disappears; the Composer is fully usable (build, templates, import, export, simulate).
4. Click **Backends** → overlay returns.

Expected: only the Composer is reachable offline; backend screens still gated.

- [ ] **Step 5: Commit**

```bash
git add src/presentation/app/NavigationManager.m tests/test_NavigationManager.m
git commit -m "feat(nav): make Composer offline-capable; gate auth overlay per screen"
```

---

## Task 13: "Explore offline →" entry on Welcome

**Files:**
- Modify: `src/presentation/screens/WelcomeScreen.m` (hero grid ~line 27)

- [ ] **Step 1: Add the hero button**

In `WelcomeScreen.m`, widen the hero grid from `[1 5]` to `[1 6]` and add a column (~line 27-29):

```matlab
    hg = uigridlayout(hero, [1 6]);
    hg.RowHeight   = {34};
    hg.ColumnWidth = {'1x', 110, 110, 110, 110, 140};
```

Add a fifth button after `btn4` (wire it to `app.onSelectSection('Composer')` — the same `app` handle the New Project / Documentation hero buttons in this function use):

```matlab
    btn5 = uibutton(hg, 'Text', [char(9658) ' ' Labels.get('welcome_btn_explore_offline')], ...
        'ButtonPushedFcn', @(~,~) app.onSelectSection('Composer'));
    StyleHelper.styleBtn(btn5, 'secondary');
```

- [ ] **Step 2: Verify (manual)**

1. Logged out. Launch; the Projects (Welcome) screen shows an **▶ Explore offline** hero button.
2. Click it → navigates to the Composer with no auth overlay.

Expected: one-click offline entry from the landing screen.

- [ ] **Step 3: Commit**

```bash
git add src/presentation/screens/WelcomeScreen.m
git commit -m "feat(welcome): add Explore offline entry routing to Composer"
```

---

## Final verification

- [ ] **Run the full suite**

Run: `runtests('tests')`
Expected: all pass; Support-Package-dependent cases in `test_MatlabQuantumBridge` show as **Incomplete** (skipped) on a machine without the add-on, **Passed** with it. No regressions in `test_CircuitModel_export` or `test_NavigationManager`.

- [ ] **Acceptance walkthrough (with the add-on installed)**

1. Logged out → Welcome → **Explore offline** → Composer renders, no overlay.
2. Build a Bell circuit → Inspect flashes native-`simulate` parity.
3. Console `qc = quantumCircuit([hGate(1); cxGate(1,2)], 2)` → **Import MATLAB** → canvas matches.
4. **Export** → **MATLAB (quantumCircuit)** preview is valid MATLAB; **Push to workspace** creates `qtau_circuit`.
5. Backend screens still show the auth overlay when logged out.

---

## Self-review checklist (completed by plan author)

- **Spec coverage:** G1 import (Tasks 4, 6, 9) · G2 export script + push (Tasks 2, 8, 10) · G3 native simulate + parity (Tasks 5, 11) · G4 push results (Task 10 pushes the circuit; result-struct push reuses the same `pushToWorkspace` from Task 6) · G5 offline (Tasks 12, 13) · G6 graceful degrade (Task 1 `isAvailable` + guards in Tasks 9–11). Error handling §7 → Tasks 3/4/5/6 error paths + tests.
- **Deferred (per spec non-goals):** generateQASM passthrough, QASM-3 parser, `.mat`/table import, QMC vertical, UX consolidation — not in this plan.
- **Placeholders:** none — every code step is complete.
- **Type/name consistency:** `MatlabQuantumBridge` static API (`isAvailable`/`toQuantumCircuit`/`fromQuantumCircuit`/`simulateNative`/`listWorkspaceCircuits`/`importByName`/`pushToWorkspace`) used identically across service, VM, and tests; error IDs (`UnsupportedGate`, `UnsupportedNativeOp`, `NotAQuantumCircuit`, `NotAvailable`, `BadName`, `NotFound`) consistent between implementation and `verifyError` assertions; `out.zeroProbs` shape (1×n row) consistent between `simulateNative` and both the parity test and `flashNativeParity`.
- **Known impl-time verification (spec §9):** confirm `.Type` strings `"si"`/`"ti"` and that `cyGate` lands outside the map on the installed R2025b; the `typeToKind`/`kindToGate` maps are the single change point if a release differs.
```

