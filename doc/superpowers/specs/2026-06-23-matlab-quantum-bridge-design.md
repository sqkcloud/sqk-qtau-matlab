# MATLAB Quantum Bridge — Design Spec (Phase 1)

**Date:** 2026-06-23
**Status:** Draft — pending user review
**Branch:** `feature/feedback`
**Strategy context:** [`../../feedbacks/2026-06-23-feedback-response-strategy.md`](../../feedbacks/2026-06-23-feedback-response-strategy.md)
**Source feedback:** [`../../feedbacks/feedback.md`](../../feedbacks/feedback.md)

---

## 1. Problem & motivation

The MathWorks review found the toolbox has **no linkage to the MATLAB Quantum Computing Support
Package**: circuits enter only via QASM upload or the in-app Composer, local simulation runs on a
hand-rolled engine, and export targets are external (QASM, Qiskit, Cirq, Braket) — nothing flows
back into MATLAB. As a result the toolbox offers no advantage over a web/Python interface.

This spec defines the **spine** that fixes it: a bridge so a MATLAB user can take a `quantumCircuit`
they already built, work with it in the app, simulate it with MATLAB's own engine, export it back
as a `quantumCircuit`, and push results into the base workspace — and do all of that **offline,
without backend login.**

## 2. Goals / non-goals

**Goals (Phase 1)**

- G1. Import a `quantumCircuit` object from the base workspace into the Composer's `CircuitModel`.
- G2. Export the current `CircuitModel` as runnable MATLAB code (`quantumCircuit` constructor script)
  and as a live `quantumCircuit` object pushed to the workspace.
- G3. Use MATLAB's native `simulate()` as the authoritative final-state/counts engine, with a
  parity check against the existing hand-rolled simulator.
- G4. Push simulation/analysis results (counts, statevector) to the base workspace as MATLAB-native
  values.
- G5. The build / import / simulate / template / export paths work **offline** (no auth token).
- G6. Degrade gracefully when the Support Package add-on is not installed.

**Non-goals (deferred)**

- N1. `generateQASM` passthrough + an OpenQASM 3.0 parser (Phase 2).
- N2. `.mat` / `table` / numeric data import for parametric circuits (Phase 2).
- N3. The quant-finance QMC-on-MATLAB-data vertical (Phase 2).
- N4. UX consolidation — Prediction↔Run Planner merge, templates discoverability, export demotion,
  progressive disclosure (Phase 3).
- N5. Any change to the FastAPI backend. This phase is **client-side MATLAB only.**

## 3. Background — the two data models

**Internal (`src/domain/models/CircuitModel.m`)**
- `Gates`: struct array `{kind (char), qubits (row vector, 0-indexed), params (row vector)}`.
- `NumQubits` (cap 16).
- Supported kinds: `h x y z s t sdg tdg rx ry rz cx cz swap ccx measure barrier reset`.
- Qubits are **0-indexed** (QASM convention).

**MATLAB Support Package (`quantumCircuit`)**
- `quantumCircuit(numQubits)` | `quantumCircuit(gates)` | `quantumCircuit(gates, numQubits)`.
- `.NumQubits`, `.Gates` (`N×1 quantum.gate.SimpleGate`).
- Each gate: `.Type` (e.g. `"h"`, `"rx"`, `"si"`), `.ControlQubits`, `.TargetQubits`, `.Angles`.
- Qubits are **1-indexed**.
- `simulate(circ[, inState])` → `quantum.gate.quantumState` with `.Amplitudes` (complex column),
  `probability(s, qubit, "0"|"1")`, `randsample(s, numShots)` for sampled counts.
- **No `reset`, `measure`, or `barrier` gate exists in `quantumCircuit`** — measurement is terminal
  and implicit.

> **The trap:** `quantumCircuit.generateQASM` emits **OpenQASM 3.0**; `CircuitModel.fromQasm` is a
> strict **2.0** parser and would reject the 3.0 header (`qubit[N] q`) and measurement
> (`c = measure q`). Phase 1 therefore maps gates **directly** instead of round-tripping QASM.

## 4. Gate mapping (single source of truth)

Index conversion: **internal `q` ↔ MATLAB `q+1`** (both directions).

| Internal kind | MATLAB constructor | MATLAB `.Type` | Notes |
|---|---|---|---|
| `h` | `hGate(q)` | `"h"` | |
| `x` | `xGate(q)` | `"x"` | |
| `y` | `yGate(q)` | `"y"` | |
| `z` | `zGate(q)` | `"z"` | |
| `s` | `sGate(q)` | `"s"` | |
| `sdg` | `siGate(q)` | `"si"` | inverse S |
| `t` | `tGate(q)` | `"t"` | |
| `tdg` | `tiGate(q)` | `"ti"` | inverse T |
| `rx` | `rxGate(q, θ)` | `"rx"` | `.Angles` → `params(1)` |
| `ry` | `ryGate(q, θ)` | `"ry"` | |
| `rz` | `rzGate(q, θ)` | `"rz"` | |
| `cx` | `cxGate(c, t)` | `"cx"` | `cnotGate` also maps in (`.Type` `"cx"`) |
| `cz` | `czGate(c, t)` | `"cz"` | |
| `swap` | `swapGate(a, b)` | `"swap"` | |
| `ccx` | `ccxGate(c1, c2, t)` | `"ccx"` | |
| `measure` | — | — | dropped on `toQuantumCircuit` (no equivalent) |
| `barrier` | — | — | dropped on `toQuantumCircuit` (no equivalent) |
| `reset` | — | — | **unsupported natively** — see §6 |

**Inbound (MATLAB → internal):** any `.Type` not in this table → `MException`
`MatlabQuantumBridge:UnsupportedGate` naming the gate + the supported set. MATLAB gates outside the
palette (`id`, `cy`, `ch`, `r1`, `rxx`/`ryy`/`rzz`, `qft`, `mcx`, `unitary`, composite, …) hit this
path in Phase 1; Phase 2's `generateQASM` passthrough handles them.

> **Implementation note (verify on impl):** the constructor names and `.Type` strings above are from
> the R2025b Support Package docs. The implementer MUST confirm `.Type` for `siGate`/`tiGate` is
> `"si"`/`"ti"` on the installed release and that `cnotGate` collapses to `.Type` `"cx"`; adjust the
> map if a release differs. The map is the only place these strings appear.

## 5. Components

### 5.1 `src/domain/services/MatlabQuantumBridge.m` (new)

The **only** module that references Support-Package API. Static methods:

```
isAvailable()                  -> tf      % add-on installed?  (see §6)
fromQuantumCircuit(qc)         -> CircuitModel
toQuantumCircuit(model)        -> quantumCircuit
simulateNative(model)          -> struct{amplitudes, probs, counts?}
listWorkspaceCircuits()        -> string array of base-workspace var names of class quantumCircuit
importByName(name)             -> CircuitModel       % evalin('base',name) + fromQuantumCircuit
pushToWorkspace(name, value)   -> (void)             % assignin('base', name, value)
```

- `fromQuantumCircuit`: validate `isa(qc,'quantumCircuit')`; read `qc.NumQubits`; build a fresh
  `CircuitModel(n)`; iterate `qc.Gates`, map `.Type` → kind (§4), `TargetQubits`/`ControlQubits`
  `−1` → internal qubits, `.Angles` → params; `addGate`.
- `toQuantumCircuit`: build a `quantum.gate.SimpleGate` column from `model.Gates` (skip
  `measure`/`barrier`; **error on `reset`** per §6), `+1` index shift, then
  `quantumCircuit(gates, model.NumQubits)`.
- `simulateNative`: `s = simulate(toQuantumCircuit(model))`; return `s.Amplitudes`; counts via
  `randsample` only when requested (sampling is non-deterministic — keep out of the parity test).
- `listWorkspaceCircuits`: `vars = evalin('base','whos'); names = {vars(strcmp({vars.class},'quantumCircuit')).name}`.

### 5.2 `CircuitModel.toMatlabScript(obj)` (new emitter)

Sits beside `toQiskitPython` / `toCirqPython` / `toBraketPython`, same style. Emits:

```matlab
% Generated by QTAU: Hardware-Agnostic Execution
gates = [
    hGate(1)
    cxGate(1, 2)
    rxGate(1, pi/2)
];
qc = quantumCircuit(gates, 3);
% measure / barrier omitted — no quantumCircuit equivalent
```

Reuses `formatTheta` for π-rational angles (bare `pi`, not `np.pi`). `measure`/`barrier`/`reset`
emitted as trailing comment lines so the user sees what was dropped.

### 5.3 UI wiring (Composer)

- **Import from MATLAB** toolbar button → modal listing `listWorkspaceCircuits()` (uidropdown +
  Import/Cancel). On import: `importByName` → load into the Composer model via the existing
  set-model/render path → QASM mirror + canvas refresh.
- **Export dialog** (`ComposerViewModel.openExportDialog`): add one row
  `{'matlab', Labels.get('composer_export_fmt_matlab'), 'm'}` → `CircuitModel.toMatlabScript`.
  Plus a **"Push `quantumCircuit` to workspace"** action (prompts for a var name → `toQuantumCircuit`
  → `pushToWorkspace`).
- **Inspect footer:** native-sim **parity badge** — runs `simulateNative` once, compares
  `|amplitudes|` against the final hand-rolled `psi` within tolerance, shows
  `MATLAB simulate ✓` / `⚠ mismatch`. (Decision 1A — hand-rolled keeps driving per-step animation.)
- All new labels go through `Labels.get()` (new keys in `resources/labels.properties`).

### 5.4 Auth-decouple (`OverlayManager` / `NavigationManager`)

- Add a screen classification: `offlineCapable = {'Composer'}` (the only screen whose core surface —
  build / import / simulate / export — is fully local) vs the default `backendRequired` for every
  screen that calls `FastAPIClient` (Circuits, Upload, Backends, Jobs, Prediction, …).
- `AuthOverlay` is shown only when `~isAuthenticated()` **and** the active screen is
  `backendRequired`. Offline-capable screens render with no overlay; their backend-touching actions
  (e.g. Composer's Save-to-server, which POSTs the QASM) remain individually guarded and prompt for
  login on demand.
- Boot lands on Composer in offline mode when no token is present (instead of the login wall),
  so the app is explorable immediately. *(Confirm landing-screen choice with the team — see §9.)*

## 6. Capability detection & degradation

- `isAvailable()` = `exist('quantumCircuit','class') == 8`. (A license/add-on probe may be added if
  the class shadows; keep the check in one method.)
- When `false`: Import-from-MATLAB, native-sim parity badge, MATLAB-export, and push-to-workspace
  are **disabled with a one-line hint** ("Requires the MATLAB Support Package for Quantum
  Computing"). The Composer, hand-rolled simulator, and all other exports are unaffected.
- **`reset` gate:** `quantumCircuit` has no reset. `toQuantumCircuit`/`simulateNative` raise
  `MatlabQuantumBridge:UnsupportedNativeOp` ("circuits with reset can only run on the local
  simulator"). The hand-rolled simulator continues to handle reset, so Inspect still works — only the
  native parity badge is suppressed for such circuits.

## 7. Error handling

| Condition | Behavior |
|---|---|
| Add-on absent | features disabled + hint (§6); no error dialog |
| Unsupported gate on import | `MatlabQuantumBridge:UnsupportedGate`, message lists gate + supported set; **nothing partially loaded** |
| `reset`/native-only-incapable op | `MatlabQuantumBridge:UnsupportedNativeOp`; fall back to hand-rolled, suppress parity badge |
| Bad/missing workspace var, wrong class | guarded `evalin`/`isa`; friendly `uialert`, no crash |
| `> 16` qubits (model cap) / `> 14` (parity via hand-rolled) | reuse existing cap errors |
| Parity mismatch beyond tol | badge shows `⚠`, logs both vectors at DEBUG; does not block the user |

Errors propagate as `MException` (project convention) and surface via `uialert`.

## 8. Testing — `tests/test_MatlabQuantumBridge.m`

All Support-Package-dependent cases gate on `assumeTrue(MatlabQuantumBridge.isAvailable())` so CI
without the add-on still passes.

- **T1 round-trip identity** — `model → toQuantumCircuit → fromQuantumCircuit → model'`; assert
  equal kinds/qubits/params for a circuit covering every mapped gate.
- **T2 index shift** — cx/ccx: internal `q[0]`→MATLAB `1`, and back.
- **T3 unsupported gate** — `fromQuantumCircuit` on a circuit with `cyGate`/`r1Gate` raises
  `MatlabQuantumBridge:UnsupportedGate`.
- **T4 sim parity** — Bell, GHZ-3, `rx(π/3)`: `abs(simulateNative.amplitudes)` vs hand-rolled
  `abs(psi)` within `1e-9` (compare magnitudes — global phase convention may differ).
- **T5 reset path** — model with `reset` → `simulateNative` raises `UnsupportedNativeOp`; hand-rolled
  still simulates.
- **T6 `toMatlabScript` snapshot** — Bell-state model emits expected `hGate(1); cxGate(1,2);
  quantumCircuit(gates, 2)`.
- **T7 no-addon degradation** — when `isAvailable()` is false (mock), UI helpers report disabled
  rather than throwing. *(May be covered by a thin seam rather than a full UI harness.)*

No `StubFastAPIClient` needed — the bridge is purely local.

## 9. Open questions / risks

1. **Gate `.Type` exact strings** (`"si"`/`"ti"`, `cnotGate`→`"cx"`) — verify on the installed
   R2025b before relying on the §4 map. Single point of change.
2. **Global-phase convention** — MATLAB `simulate` may differ from the hand-rolled engine by a
   global phase; T4 compares magnitudes to stay convention-independent. If per-amplitude (signed)
   parity is wanted, normalize phase on the first nonzero amplitude.
3. **Offline landing screen** — defaulting boot to Composer when logged out is a UX change; confirm
   with the team vs. a lighter "explore offline" entry on the existing welcome screen.
4. **`randsample` availability / signature** for native counts — confirm on impl; counts are optional
   in Phase 1 (amplitudes are the primary native output).

## 10. Acceptance criteria

- A user with the Support Package installed can: pick a workspace `quantumCircuit` → see it render in
  the Composer; export the Composer circuit as a `.m` script that reconstructs an identical
  `quantumCircuit`; push a `quantumCircuit` and a results struct to the base workspace; see the
  native-`simulate` parity badge on a reset-free circuit.
- With no token, the Composer + import + simulate + export paths are reachable with no `AuthOverlay`.
- With no add-on, the app runs unchanged except the four native features are disabled with a hint.
- `runtests('tests/test_MatlabQuantumBridge')` passes (Support-Package cases skipped when absent).
- No backend/API change; no edits under `samples/`.

## 11. Phasing recap

| Phase | Content |
|---|---|
| **1 (this spec)** | bridge service · MATLAB export target · native sim + parity · workspace import/push · auth-decouple · tests |
| 2 | `generateQASM` passthrough + QASM-3 parser · `.mat`/table import · QMC-on-MATLAB-data vertical |
| 3 | UX: Prediction↔Run Planner merge · templates discoverability · export demotion · progressive disclosure |
| 4 | example Live Scripts · sandbox/demo mode |
