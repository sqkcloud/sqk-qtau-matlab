# C1 + C2 Design — Visual Composer, Inspect Mode, Templates, Calibration Sparklines, Compare Mode

- **Date:** 2026-05-09
- **Scope:** Two sub-clusters of features identified during the post-async competitor-gap analysis. C1 = in-app circuit authoring (Templates + Composer + Inspect). C2 = operational maturity (Calibration Sparklines + Job Compare mode).
- **Status:** Design approved by user across four section reviews. Pending spec self-review and user spec review before writing the implementation plan.
- **Out of scope:** Multi-vendor backend support (cluster C3 — AWS Braket gateway), AI result interpretation, cost estimator, notifications, audit log. To be specced separately.

---

## 1 Overview

The async migration completed in the prior workstream eliminated UI freezes across all 18 ViewModels. With responsiveness solved, the next professional gaps versus the 2026 quantum-platform field are (a) **in-app circuit authoring** (IBM Composer parity for novice users + step-through statevector inspection for debuggers) and (b) **operational maturity polish** (calibration drift visibility and side-by-side run comparison). C1 + C2 together close those gaps without touching the existing async architecture or any of the converted call sites.

## 2 Discovery summary — user decisions

Each row was an explicit multiple-choice user pick during brainstorming.

| # | Decision | Choice |
|---|---|---|
| 1 | Cluster scope | C1 + C2 together |
| 2 | Composer target user | **Both** — Pro / Beginner mode toggle |
| 3 | Composer integration | **New top-level "Composer" screen**, sidebar after Circuits |
| 4 | Inspect simulator placement | **Hybrid** — local MATLAB ≤14 q, server-side Aer for >14 q |
| 5 | Template gallery scope | **12 curated** (Beginner card grid) **+ Browse-all-QASMBench** link in Pro mode |
| 6 | Composer save destination | **New endpoint** `POST /api/circuits/inline` (JSON body, no temp-file dance) |
| 7 | Job comparison UI placement | **Compare-mode toggle on Results screen**, 2-up split, synced X-axes |
| 8 | Build order | **Approach 1** — C2 first (weeks 1–1.5), C1 after (weeks 2–4) |

## 3 Architecture overview

```
                      ┌──────────────────── existing ────────────────────┐
                      │  AsyncRunner  ·  FastAPIClient  ·  AppState      │
                      │  18 VMs · timer-driven polling · NavigationMgr   │
                      └──────────────────────────────────────────────────┘
                                       ▲                  ▲
                                       │ reuse            │ reuse
                                       │                  │
   ┌──────── C2 ───────┐   ┌──────────────── C1 ─────────────────────┐
   │ BackendsScreen+   │   │  Composer screen (new sidebar entry)    │
   │  sparkline col    │   │   ├─ Pro/Beginner mode toggle           │
   │  Telemetry tabs   │   │   ├─ Gate palette (click-to-place)      │
   │                   │   │   ├─ Canvas (qubit-wire grid)           │
   │ ResultsScreen+    │   │   ├─ OpenQASM mirror (bidir in Pro)     │
   │  Compare button   │   │   ├─ Templates gallery (12 + QASMBench) │
   │  2-up split       │   │   └─ Inspect footer                     │
   │  diff strip       │   │        ├─ local StatevectorSimulator    │
   └────────┬──────────┘   │        └─ server Aer fallback           │
            │              └────────────────┬────────────────────────┘
            │                               │
   ┌────────▼───────────────────────────────▼─────────────────────────┐
   │  Backend (FastAPI) additions:                                    │
   │   ▸ CalibrationHistoryDocument (Beanie, 7-day TTL)               │
   │   ▸ GET /api/backends/{name}/calibration_history                 │
   │   ▸ POST /api/circuits/inline                                    │
   │   ▸ POST /api/circuits/inspect (Qiskit Aer)                      │
   └──────────────────────────────────────────────────────────────────┘
```

## 4 C2 — Operational maturity

### 4.1 Calibration sparklines (B1)

**Server-side change.** Add a Beanie document `CalibrationHistoryDocument` storing one record per `(backend_name, qubit_index, sampled_at)`. Existing IBM-calibration GETs from `BackendService.getCalibration(...)` are intercepted to write through to history. Mongo TTL index removes records older than 7 days. New endpoint `GET /api/backends/{name}/calibration_history?days=7&qubit_index?` returns time-series data.

Document schema (one row per sample):

| Field | Type | Notes |
|---|---|---|
| `backend_name` | str | indexed |
| `qubit_index` | int | indexed (compound with backend_name) |
| `sampled_at` | datetime (UTC, ISO-8601) | TTL index, 7-day expiry |
| `T1` | float | seconds |
| `T2` | float | seconds |
| `frequency` | float | Hz |
| `gate_error` | float | per-qubit single-qubit error |
| `readout_error` | float | per-qubit |
| `two_q_error` | float \| null | nullable for non-2Q-eligible qubits |
| `anharmonicity` | float | Hz |

**Client-side change on `BackendsScreen`:**

1. **Inline sparkline column** — each backend table row gets a tiny ~80×20 px `uiaxes` painted by `BackendsViewModel.paintInlineSparkline` (reuses chart helpers from `Dashboard.paintActivityTrend`).
2. **Telemetry tab strip** added to the existing `BackendStatusArea`: `Overview | Per-Qubit | History`.
   - **Per-Qubit** tab — heat-grid (qubits × {T1, T2, frequency, gate_error, readout_error}) color-coded by health thresholds: >95 % Optimal (green), 70-95 % Watch (amber), <70 % Critical (red). Matches the Quantum-Insider 2026 dashboard study.
   - **History** tab — three large sparklines (T1 average, T2 average, 2Q error) over 7 days plus per-qubit small-multiples grid for drill-down.

**Data flow.**
```
IBM API ─► BackendService.getCalibration ─┬─► response (existing path)
                                          └─► CalibrationHistoryDocument.insert (write-through)

Backends onEnter ─► AsyncRunner.run(@() svc.listBackends + getCalibrationHistory)
                  ─► paintInlineSparklines + populateTelemetryPanel
```

**Error handling.** Sparkline render is best-effort: empty / failed history GET → em-dash, never blocks table. Write-through failures log at `Logger.debug` and don't fail the original calibration response.

**Testing.** `test_BackendsViewModel_sparklines.m` (empty / partial / full history); server `test_calibration_history_writethrough.py` and `test_calibration_history_router.py`.

### 4.2 Compare mode on Results (B5)

**Pure client-side, no server change.** Results screen toolbar gains `⇄ Compare with…` button. Click → `JobPickerDialog` modal listing completed jobs (sortable by submitted_at desc, filterable by backend) → user picks a second job → `ResultsScreen` re-lays-out from 1-column to 2-column, both jobs' charts side-by-side with synced X-axes.

**Implementation.** 2-up layout via `uigridlayout` with `ColumnWidth = {'1x', '1x'}`. Existing single-column rendering becomes the left column; right column duplicates the render path with the second job's data. Chart helpers (`renderResultsHistogram`, `renderFidelityCard`, `renderErrorBudgetWaterfall`) all already accept a `parent` parameter — pass the right-column grid handle.

**Diff strip** above the charts shows numeric diffs: Δfidelity, Δshot count, ΔKL-divergence, Δsuccess-rate. Color-coded green/red/muted by direction.

**Data loading.** Two parallel `AsyncRunner.run` dispatches (one per `job_id`) using existing `JobService.getJobResult`. Both must complete before right column renders (track via two flags, finalize when both arrive).

**Exit.** `×` close affordance on right column → grid collapses to 1-column; second job dropped.

**Feature-flag** via `app.properties` `feature_compare_mode_enabled=true` (defensive — easy to roll back if Results regressions appear).

**Testing.** `test_CompareMode.m` — toggle 2-up; diff strip math; close restores 1-column.

## 5 C1 — In-app circuit authoring

### 5.1 Template gallery (A3)

**12 curated templates** stored as parameterized OpenQASM in `resources/templates/*.qasm.tmpl` with `{n}`, `{theta}`, `{hidden_string}`-style placeholders.

| # | Template | Qubits | Parameterized |
|---|---|---|---|
| 1 | Bell state | 2 | no |
| 2 | GHZ_n | n (3, 4, 5, 8) | n |
| 3 | QFT_n | n (3, 4, 5, 8) | n |
| 4 | Grover (k-bit oracle) | k+1 | k, marked-bitstring |
| 5 | Bernstein-Vazirani | n+1 | n, hidden-string |
| 6 | Deutsch-Jozsa | n+1 | n, balanced/constant |
| 7 | Phase Estimation (toy 2×2) | 4 | unitary preset |
| 8 | VQE H₂ ansatz | 2 | θ |
| 9 | QAOA Max-Cut (3-node) | 3 | γ, β |
| 10 | Trotter-step (XY model) | 4 | dt, steps |
| 11 | Quantum teleportation | 3 | no |
| 12 | Superdense coding | 2 | message bitstring |

`TemplateRegistry.m` static class loads the template, fills placeholders from a parameter dialog, and returns OpenQASM text. Beginner mode shows a 4×3 card grid (~96 % of canvas) on first entry. Pro mode keeps the canvas blank and exposes templates via a `📋 Templates ▾` toolbar dropdown that includes a `Browse QASMBench (252 circuits) →` modal.

### 5.2 Composer screen (A1)

**New files:**

| File | Purpose | LOC est. |
|---|---|---|
| `src/presentation/screens/ComposerScreen.m` | UI build | ~300 |
| `src/presentation/viewmodels/ComposerViewModel.m` | State + callbacks | ~400 |
| `src/domain/models/CircuitModel.m` | In-memory circuit data, toQasm/fromQasm | ~250 |
| `src/domain/models/TemplateRegistry.m` | Template loader | ~150 |
| `src/presentation/screens/components/GatePaletteWidget.m` | Palette panel | ~120 |
| `src/presentation/screens/components/CircuitCanvasWidget.m` | Qubit-wire grid | ~200 |

**Layout (Pro mode):**

```
┌─ Toolbar ───────────────────────────────────────────────────────────┐
│ [Beginner | ✓Pro]  📋Templates▾  💾Save  ✓Validate  ▶Run/Inspect    │
├─ Palette (left) ┬─ Canvas (center) ──────────────┬─ Params (right) ─┤
│ H  X  Y  Z      │ q[0] ──■──H──●──────────       │ Selected: Rx     │
│ S  T  Rx Ry Rz  │ q[1] ──H──┼──┼──Rx────         │ θ = π/2  [edit]  │
│ CX CZ CCX SWAP  │ q[2] ─────────X──Rx────M       │                  │
│ M  Barrier      │                                │                  │
├─────────────────┴────────────────────────────────┴──────────────────┤
│ OpenQASM mirror (uitextarea, bidir-sync in Pro mode, 400 ms debounce)│
├─────────────────────────────────────────────────────────────────────┤
│ Inspect footer (collapsed) — expands to step-through + Bloch        │
└─────────────────────────────────────────────────────────────────────┘
```

**Layout (Beginner mode):** palette shrinks to {H, X, CX, measure, "+ More"}, OpenQASM mirror collapsed (toggle to view), Inspect footer hidden until "Visualize" clicked, parameter panel hidden, template gallery occupies main canvas until a template is chosen.

**Interaction model — click-to-place** (MATLAB has no native drag-drop in `uifigure`):

1. Click a gate in the palette → "armed" state (border highlight).
2. Click any empty cell in the canvas → gate placed at `(qubit, time-step)`.
3. For 2-qubit gates: first canvas click sets control, second sets target (visual hint connects them).
4. Click an existing gate → opens parameter panel (if parameterized) or shows a delete affordance.
5. Drag the time-step ruler to insert a column between existing gates.

**Bidirectional sync (Pro mode):**
- Canvas edit → `CircuitModel.toQasm()` → mirror updated immediately.
- Mirror edit (debounce 400 ms) → `CircuitModel.fromQasm(text)` → canvas re-rendered. Parse failure → mirror border red, error label below; canvas keeps last-good state. Save disabled until mirror parses cleanly.

**Save flow:**
1. 💾 Save → name dialog (default `Untitled-{timestamp}`).
2. `ComposerViewModel.onSave` builds `{name, format='qasm2', category, source='composer', raw_content=qasm}`.
3. `AsyncRunner.run(@() circSvc.createInline(...))` → POST `/api/circuits/inline`.
4. Success → toast "Saved · 7-qubit GHZ" + offer to navigate to Analysis with the new circuit selected.
5. Failure → red status label below toolbar.

**Cross-cutting touches in existing files:**
- `NavigationManager.m` — add `'Composer'` between `'Circuits'` and `'Notes'` in `navNames` / `navLabels` / `navIcons`.
- `QTAUWorkbenchApp.m` — instantiate `ComposerVm = ComposerViewModel(app)`, call `ComposerScreen(app)` in `buildUI()`, add `autoLoadScreen('Composer')` no-op case.
- `resources/labels.properties` — ~45 new keys (gate tooltips, template descriptions, mode toggle, error messages).
- Server: 1 new router function in `circuit.py`, 1 schema (`CreateInlineRequest`), 1 service method (`CircuitService.create_inline`).

### 5.3 Inspect mode (A2)

**Routing decision:**

```
n_qubits = CircuitModel.qubitCount(obj.Circuit)
if n_qubits <= 14:    runLocalSimulator()                    % StatevectorSimulator.m
elif n_qubits <= 20:  runServerInspect(full=true)            % POST /api/circuits/inspect
else:                 runServerInspect(aggregates_only=true) % aggregates only
```

**Local MATLAB simulator — `src/domain/services/StatevectorSimulator.m`** (~280 LOC). `2^n` complex doubles. n=14 = 256 KB. Single-qubit gate application uses the index-slicing trick (no Kronecker products): for gate U on qubit q, iterate over `2^(n-1)` index pairs `(i, i + 2^q)` and apply the 2×2 in place. Two-qubit gates (CX/CZ/SWAP) use the same pattern over 4-dim subspaces. Total: O(g · 2^n) for g gates. Per-step statevectors cached so the slider doesn't recompute on drag.

**Server-side path — `POST /api/circuits/inspect`:**

Request: `{qasm: str, step_indices: list[int] | "all", aggregates_only: bool}`. `aggregates_only=true` is forced when n > 20.

Response (full): `{steps: [{step_index, statevector: list[{re, im}], bloch_per_qubit, top_amplitudes}]}`. n=20 ≈ 16 MB, streamed via `StreamingResponse` for n ≥ 18.

Response (aggregates only): `{steps: [{step_index, bloch_per_qubit, top_amplitudes_K=64}]}`. ~50 KB regardless of n.

**Server impl files:**
- `src/qdash/api/routers/inspect.py` (~40 LOC)
- `src/qdash/api/services/inspect_service.py` (Aer wrapper, ~80 LOC)
- `src/qdash/api/schemas/inspect.py` (~30 LOC)

**UI — Inspect footer panel inside Composer:**

Collapsed by default. Expands to ~30 % vertical canvas when open.

```
┌─ Inspect ──────────────────────────────────────── [⌃ collapse] ──┐
│ Step: 0 ────●─────────────────── 12   ◀ ▶  [▶ Auto-step]         │
│ Currently after gate 4 of 12: Rx(π/2) on q[1]   (local · ≤14 q)  │
├─ Qubits ─┬─ Amplitudes ─┬─ Phase ──────────────────────────────────┤
│ Bloch sphere small-multiples (one per qubit, max 16 visible)      │
│   [q0]   [q1]   [q2]   [q3]                                       │
│   [q4]   [q5]   [q6]   [q7]                                       │
└───────────────────────────────────────────────────────────────────┘
```

- **Slider** maps to gate index 0..N. Click advances; drag jumps; ▶ Auto-step plays at 1 step / 600 ms.
- **Currently after gate** caption shows gate kind, qubits, parameters.
- **Tab "Qubits"** — Bloch per qubit (≤16 shown; paginate for 17-20). Bloch math: trace out other qubits → reduced density matrix → Bloch vector. Reuse `QecVisualizationScreen` Bloch render helper.
- **Tab "Amplitudes"** — horizontal bar chart of `|a_i|²` for top-K states (default K=16, configurable to 64).
- **Tab "Phase"** *(Pro only)* — phase wheel showing argument of each top-K amplitude.

**Edge cases:**
- **Measurements mid-circuit:** simulator stops at first `measure` and shows pre-measurement statevector + classical branch probabilities. Slider can't step past. Tooltip: "Inspect ends at measurement; rerun via Run for shot results."
- **Classical conditionals:** treated as unconditional branch (we don't fork the world). Annotated on gate.
- **Circuit edits while Inspect open:** every canvas edit invalidates cache; slider snaps to step 0; user re-visualizes.
- **Server timeout for n > 14 path:** client falls back to aggregates-only. On second failure, surface "Statevector too large to ship — showing Bloch only."

## 6 Cross-cutting concerns

### 6.1 Testing

| Test | Scope | What it asserts |
|---|---|---|
| `test_BackendsViewModel_sparklines.m` | C2 | empty/partial/full history; em-dash on empty; axes set correctly |
| `test_CompareMode.m` | C2 | toolbar toggles 2-up; diff math; close restores 1-column |
| `test_CircuitModel.m` | C1 | toQasm ↔ fromQasm round-trip on 12 templates; rejects malformed QASM |
| `test_TemplateRegistry.m` | C1 | each template parameterizes with default + edge args, produces parser-valid QASM |
| `test_ComposerViewModel.m` | C1 | save dispatches via AsyncRunner; mirror debounce 400 ms |
| `test_StatevectorSimulator.m` | C1 | Bell, GHZ_3, GHZ_5, QFT_3 produce reference statevectors; cache hit-rate = 1.0 on re-visit |
| `test_InspectViewModel.m` | C1 | routing decision (≤14 / ≤20 / >20); measurement halts slider; canvas edit invalidates cache |
| `test_circuit_inline_router.py` | server | POST /api/circuits/inline inserts CircuitDocument; rejects oversize 413 |
| `test_inspect_router.py` | server | step-indexed statevector for n=4; aggregates-only for n=21 |
| `test_calibration_history_writethrough.py` | server | first getCalibration creates row; TTL eviction at 7 days |
| `test_calibration_history_router.py` | server | time-sorted records; qubit_index filter |

**Manual smoke checklist** (post-merge):
1. Backends sparklines render (em-dashes initially, populate over usage).
2. Backends row click → Telemetry → Per-Qubit heat-grid + History sparklines.
3. Composer (Beginner) gallery → GHZ template → param dialog → canvas populated.
4. Pro toggle → palette → click H → click q[0] cell → mirror updates.
5. Edit mirror → canvas re-renders after 400 ms.
6. 💾 Save → toast "Saved" → "Open in Analysis" navigates with new circuit pre-selected.
7. Expand Inspect footer → drag slider → Bloch + amplitudes update → measurement gate halts.
8. Run two jobs → Results → ⇄ Compare with… → 2-up split with diff strip.

### 6.2 Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Click-to-place UX hated | Medium | Medium | Watch session feedback after week 4; uihtml drag-drop fallback design ready (CircuitModel unchanged). |
| Bidirectional QASM sync edge syntax | High | Medium | Pro mirror sends to existing server `/api/circuits/validate` for parse; canvas only updates on parser success. Strict client-side parser handles only palette-emitted gates. |
| Aer-on-server timeout for n=20 | Medium | Low | Client timeout 30 s; on miss retry with aggregates-only; on second miss surface graceful message. |
| Calibration write-through floods Mongo | Low | Medium | One row per (backend, qubit) per call. ≤ 1/min/backend × 6 backends = 8.6 K rows/day worst case. TTL caps total. |
| Compare mode regression on single-job render | Low | High | Feature flag `feature_compare_mode_enabled=true`; default true but easy to roll back. Existing single-job path unchanged unless Compare invoked. |
| qiskit-aer not installed on server | Medium | High (Inspect breaks for >14) | Server adds `qiskit-aer>=0.13` to `pyproject.toml`; CI verifies; client surfaces "Inspect requires server upgrade". |

### 6.3 Performance budgets

| Path | Budget |
|---|---|
| Composer onEnter | < 200 ms |
| Template card click → canvas render | < 150 ms |
| Mirror edit → canvas re-render | 400 ms debounce + < 100 ms parse + paint |
| Local Inspect step (n=14, cache miss) | < 50 ms per gate |
| Server Inspect step (n=18) | < 800 ms |
| Calibration sparkline row | < 30 ms |
| Compare mode entry (2 jobs) | < 1 s |

### 6.4 Instrumentation

`app.logEvent` categories:
- `'COMPOSE'` — gate added/removed/parameterized, mode toggled, template loaded, save attempted.
- `'INSPECT'` — simulator chosen (local|server|aggregate), step requested, cache hit/miss.
- `'COMPARE'` — enter/exit, jobs picked, diff metrics computed.
- `'TELEMETRY'` — history fetch, sparkline render, drill-down opened.

These flow into the existing Activity Log shown on the Dashboard's activity feed (`paintLocalActivity`).

### 6.5 Documentation updates

- `CLAUDE.md` — Composer added to screen table; Pro/Beginner toggle documented; new endpoints noted; screen count 17 → 18.
- `resources/labels.properties` — ~45 new keys.
- `docs/fastapi_contract.md` and `docs/openapi.json` — auto-update via FastAPI's OpenAPI export.

## 7 Rollout sequence

1. **Server changes first** (backwards-compatible):
   1. Add `CalibrationHistoryDocument` Beanie model + TTL index.
   2. Wrap `BackendService.getCalibration` with write-through.
   3. Add `GET /api/backends/{name}/calibration_history` router.
   4. Add `POST /api/circuits/inline` router + schema + service.
   5. Add `POST /api/circuits/inspect` router + Aer service.
   6. Bump `qiskit-aer` in `pyproject.toml`.
2. **MATLAB client changes** (in build order):
   1. C2.B1 sparklines on Backends (week 1).
   2. C2.B5 Compare mode on Results (week 1.5).
   3. C1.A3 Template Registry + gallery card grid (week 2-3).
   4. C1.A1 Composer screen + Pro/Beginner toggle (week 2-3).
   5. C1.A2 Inspect footer + local sim + server fallback (week 4).
3. **Smoke testing** in user environment.
4. **No global feature flag** — additive throughout. The single guarded surface is Compare mode (`feature_compare_mode_enabled=true`).

## 8 Files inventory (cumulative)

### New MATLAB client files

```
src/presentation/screens/ComposerScreen.m
src/presentation/screens/components/GatePaletteWidget.m
src/presentation/screens/components/CircuitCanvasWidget.m
src/presentation/screens/components/InspectFooter.m
src/presentation/viewmodels/ComposerViewModel.m
src/presentation/viewmodels/InspectViewModel.m
src/domain/models/CircuitModel.m
src/domain/models/TemplateRegistry.m
src/domain/services/StatevectorSimulator.m
resources/templates/bell.qasm.tmpl
resources/templates/ghz.qasm.tmpl
resources/templates/qft.qasm.tmpl
resources/templates/grover.qasm.tmpl
resources/templates/bernstein_vazirani.qasm.tmpl
resources/templates/deutsch_jozsa.qasm.tmpl
resources/templates/phase_estimation_toy.qasm.tmpl
resources/templates/vqe_h2.qasm.tmpl
resources/templates/qaoa_maxcut.qasm.tmpl
resources/templates/trotter_xy.qasm.tmpl
resources/templates/teleportation.qasm.tmpl
resources/templates/superdense_coding.qasm.tmpl
tests/test_BackendsViewModel_sparklines.m
tests/test_CompareMode.m
tests/test_CircuitModel.m
tests/test_TemplateRegistry.m
tests/test_ComposerViewModel.m
tests/test_StatevectorSimulator.m
tests/test_InspectViewModel.m
```

### Modified MATLAB client files

```
src/presentation/app/QTAUWorkbenchApp.m         (add ComposerVm, ComposerScreen call, autoLoad case)
src/presentation/app/NavigationManager.m         (add Composer to nav arrays)
src/presentation/screens/BackendsScreen.m        (sparkline column, Telemetry tabs)
src/presentation/viewmodels/BackendsViewModel.m  (paintInlineSparkline, populateTelemetryPanel, history fetch dispatcher)
src/presentation/screens/ResultsScreen.m         (Compare button, 2-up grid scaffolding)
src/presentation/viewmodels/ResultsViewModel.m   (compare mode state, diff strip math, parallel job-load)
src/infrastructure/http/FastAPIClient.m          (createInline, getCalibrationHistory, inspectCircuit endpoints)
resources/labels.properties                      (~45 new keys)
resources/app.properties                         (feature_compare_mode_enabled=true)
CLAUDE.md                                        (Composer screen, new endpoints, screen count 17 → 18)
```

### New server files

```
src/qdash/dbmodel/calibration_history.py
src/qdash/api/routers/inspect.py
src/qdash/api/services/inspect_service.py
src/qdash/api/schemas/inspect.py
tests/test_circuit_inline_router.py
tests/test_inspect_router.py
tests/test_calibration_history_writethrough.py
tests/test_calibration_history_router.py
```

### Modified server files

```
src/qdash/api/routers/circuit.py                   (add /inline POST)
src/qdash/api/schemas/circuit.py                   (add CreateInlineRequest)
src/qdash/api/routers/backend.py                   (add /calibration_history GET)
src/qdash/api/schemas/backend.py                   (add CalibrationHistoryResponse)
src/qdash/api/services/circuit_service.py          (create_inline method)
src/qdash/api/services/backend_service.py          (write-through wrap of getCalibration)
src/qdash/api/dependencies.py                      (wire inspect_service)
src/qdash/api/main.py                              (register inspect router)
src/qdash/dbmodel/document_models.py               (register CalibrationHistoryDocument)
pyproject.toml                                     (qiskit-aer >= 0.13)
```
