# Circuit Cutting

Cross-link: an algorithm-level deep dive lives in
[`../circuit_cutting_algorithm.md`](../circuit_cutting_algorithm.md);
the operator-facing surface is documented here.

## 1. What it is

Circuit Cutting is a workflow that takes a single wide quantum circuit,
**cuts** it at strategically-chosen 2-qubit gates, runs the resulting
subcircuits in parallel on multiple QPUs (or one QPU repeatedly), and
**reconstructs** the original Pauli expectation values via a quasi-
probability decomposition (QPD). It is the key technique for running
N-qubit circuits on devices that physically have fewer than N usable
qubits, at the cost of a sampling-overhead multiplier.

## 2. Purpose

- Run circuits **wider than the largest available QPU** — the headline
  use case is a 160-qubit cat-state demonstration on a 156-qubit IBM
  Pittsburgh.
- Provide three modes (Automatic, Assisted, Manual) so operators with
  varying domain knowledge can pick the right level of automation:
  automatic = one click, assisted = review the suggestion, manual =
  enter the cut plan by hand.
- Phase 2 will add **domain presets** (e.g. CT Imaging 160Q) so common
  cutting topologies don't need to be re-derived every time.

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Screen | `CircuitCuttingScreen` | `src/presentation/screens/CircuitCuttingScreen.m` |
| ViewModel | `CircuitCuttingViewModel` | `src/presentation/viewmodels/CircuitCuttingViewModel.m` |
| Service | `CuttingService` | `src/domain/services/CuttingService.m` |
| Backend router | `cutting` router (`/api/cutting/*` and `/api/circuits/{id}/cutting/*`) | `qdash/api/routers/cutting.py` |

## 4. Algorithm

### Cut detection — `qiskit-addon-cutting.find_cuts`

The backend wraps qiskit-addon-cutting's `find_cuts` to choose where to
sever 2-qubit gates. The output is a `CutPlan`:

```
CutPlan = {
  k:                    int,    # number of subcircuits
  cuts:                 [ ... ], # list of cut points
  per_subcircuit_qubits:[ ... ],
  sampling_overhead:    float,  # γ^k where γ ≥ 2 per cut
  feasibility:          bool,   # γ^k under feasibility threshold?
}
```

`target_k` lets the operator override the addon's automatic choice when
`find_cuts` overflows float64 on a very wide / densely-entangling
circuit (e.g. `qugan_n395.qasm`).

### QPD reconstruction

Each cut is replaced by an instruction that resolves into a finite set
of operations weighted by signed coefficients. After running each
subcircuit `M` shots and computing per-subcircuit Pauli expectation
values, the original observable is reconstructed as a weighted sum.
The variance of this estimate is `γ^k × σ²(M)` — i.e. the **sampling
overhead** is exponential in the number of cuts.

### Mode behaviour

- **Automatic** — one click runs Analyze → Run; the operator just
  picks Mitigation level and (optional) Target k.
- **Assisted** (default) — Analyze populates KPIs and the cut plan;
  the operator reviews, then clicks Run.
- **Manual** — Phase 2 surface that lets the operator type the cut
  plan into a textbox.

## 5. Workflow

1. Open Circuit Cutting screen → **Circuit dropdown** auto-populates
   from `GET /api/circuits` (project-scoped).
2. **Mode** dropdown picks Automatic / Assisted / Manual. Hint line
   below ("Mode: assisted  Preset: generic  Press Analyze Cuts to
   begin") confirms the active mode.
3. **Target k** spinner forces a specific number of subcircuits. `0` =
   let the addon decide.
4. **Mitigation** dropdown — same ladder as the QEM popup. Default
   pulled from `app.State.preferredMitigationLevel` (persisted in
   Settings).
5. **Preset** dropdown — Generic today; Phase 2 will add CT Imaging
   160Q etc.
6. Click **⌕ Analyze** — `onAnalyzeCuts` POSTs `/api/cutting/analyze`
   with `{circuit_id, target_k?}`. The cut-plan KPIs (Subcircuits,
   Sampling Overhead, Per-subcircuit qubits, Feasibility) populate.
   Backend assignments table lists each subcircuit's chosen QPU.
7. Click **▶ Run** — `onRunCutting` POSTs
   `/api/circuits/{circuit_id}/cutting/batches` with the full body
   (mode, target_k, mitigation_level, preset, observables, also_run_raw).
   Returns `HTTP 202 {batch_id}`.
8. ViewModel polls `GET /api/cutting/batches/{batch_id}` every few
   seconds; `Pending → Running → Complete`. Live status renders in the
   FEASIBILITY KPI card.
9. On completion, fetch `GET /api/cutting/batches/{batch_id}/result`
   for the reconstructed Pauli expectation values and render under
   **Reconstructed Results**.
10. Click **✕ Cancel** to flip the batch state to `cancelled`
    (`DELETE /api/cutting/batches/{batch_id}`).

## 6. Data flow

```
Open screen:
   GET /api/circuits                                  (Circuit dropdown)
   GET /api/cutting/presets                           (Preset dropdown)
   GET /api/backends                                  (Backend assignments)

Analyze Cuts:
   POST /api/cutting/analyze
        body = { circuit_id, target_k? }
        → CutPlan { k, cuts, per_subcircuit_qubits, sampling_overhead, feasibility }

Run Cutting:
   POST /api/circuits/{circuit_id}/cutting/batches
        body = { mode, target_k, mitigation_level, preset,
                 observables: ["ZIZ...", ...] | null,
                 also_run_raw: bool, ... }
        → { batch_id, status: "queued" }

Poll:
   GET /api/cutting/batches/{batch_id}
        → { batch_id, status, progress, sibling_group_id?, ... }

Result:
   GET /api/cutting/batches/{batch_id}/result
        → { reconstructed: { observables, expectation_values, ... },
            shots_per_subcircuit, gamma_overhead, ... }

Sibling lookup (Phase 4):
   GET /api/cutting/sibling/{sibling_group_id}
        → { sibling_group_id, primary_batch_id, raw_batch_id, ... }

History:
   GET /api/cutting/batches                          (browse all)
```

## 7. Business logic

- **Mitigation default** — `app.State.preferredMitigationLevel`,
  defaulting to 1 (Standard) when AppState is unset.
- **`target_k = 0`** is the "auto" sentinel; the backend treats it as
  "let the addon decide".
- **Async batch lifecycle** — `queued → running → complete | failed | cancelled`.
- **Sibling groups** — when `also_run_raw: true`, the server spawns a
  level-0 sibling batch alongside the primary one. The Results screen
  uses `GET /api/cutting/sibling/{group_id}` to resolve the partner
  batch for the Mitigated/Raw toggle.
- **Auth + project context** — required.
- **Heron-r2 fractional gates** — same conflict surface as QEM popup;
  twirling / ZNE-PEA disabled when the backend uses fractional gates.

## 8. Reference

- Screen: `src/presentation/screens/CircuitCuttingScreen.m`
- ViewModel: `src/presentation/viewmodels/CircuitCuttingViewModel.m`
- Service: `src/domain/services/CuttingService.m`
- Backend router: `qdash/api/routers/cutting.py`
- Algorithm doc: [`../circuit_cutting_algorithm.md`](../circuit_cutting_algorithm.md)
- Phase 1 plan: `../superpowers/plans/2026-04-24-circuit-cutting-phase1.md`
- Design spec: `../superpowers/specs/2026-04-24-circuit-cutting-design.md`
