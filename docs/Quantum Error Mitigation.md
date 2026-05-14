# Quantum Error Mitigation in QDash

**Status:** Operator-complete · **Last updated:** 2026-05-03 · **Version:** Phase 5.2

This document explains the Quantum Error Mitigation (QEM) system in QTAU Connector Workbench — what it does, how it works, how operators interact with it, and how the data flows from a submit-button click to a persisted result snapshot. It is the canonical entry point for anyone — operator, developer, or future-self — who needs to understand or extend QDash's QEM rollout.

For deeper technical detail on specific phases:

- `docs/superpowers/specs/2026-05-03-mitigation-service.md` — the Phase 2 service-architecture spec.
- `docs/superpowers/specs/2026-05-03-cutting-zne-integration.md` — the Phase 5+ cutting-pipeline integration spec (forward-looking).

---

## 1. Why QEM exists

Quantum hardware in 2026 is noisy. Two-qubit gate errors hover around 3×10⁻³ on Heron r2; readout error is 1–2×10⁻²; T₁/T₂ dephasing eats into long-idle qubits. For a circuit with depth `D` running on `N` qubits, the per-shot fidelity decays roughly as `(1-ε)^(N·D)` — for the cat-state circuits in QDash's QASMBench at ~260 qubits and ~130 depth, that's well below 1 % effective fidelity.

Operators want to extract **expectation values** of Pauli observables (e.g. `<Z₀ Z₂₅₉>` for a 260-qubit cat state) from this noisy data. Without mitigation, the measured value is biased — sometimes by tens of percent — relative to the noiseless target.

**Quantum Error Mitigation** is the family of techniques that un-bias these expectation values **after** the noisy hardware run. It cannot make the underlying quantum state less noisy (that is **Quantum Error Correction**'s job, and current QEC overhead is ~1000:1 physical:logical qubits — out of reach until at least 2030). What QEM can do is take noisy counts → run statistical / sampling techniques → recover an estimate of what the noiseless expectation value would have been.

The fundamental cost: QEM's sample complexity grows exponentially with circuit depth and width. By ~50 qubits and ~100 depth, even mitigated expectation values are dominated by sampling noise. QDash's `coherence_warning` (Phase 0) tells operators when they have crossed that line.

---

## 2. What QEM does for QDash operators

When an operator submits any circuit through QDash today (after Phase 5.2), the following happens automatically — no operator action required to opt in:

- **Twirling, dynamical decoupling, and TREX measurement-error mitigation** are applied by default to every Sampler V2 submission. These three techniques have ~0× shot multiplier (they're free on IBM Runtime), so there's no reason not to.
- The **mitigation level** (Raw / Standard / Aggressive / TEM / Custom) is selectable from the Cutting-screen toolbar dropdown, with a live cost-preview line below.
- The operator's **default level** is persisted per-user via the Settings → Defaults dialog, so the dropdown remembers their preference across sessions.
- At submit time, a **`MitigationPlan` snapshot** is written to the result document so post-hoc analysis can see exactly what mitigation was applied (Phase 2.2).
- **`also_run_raw`** spawns a parallel level-0 sibling batch alongside the operator's chosen mitigation, so the Results screen can render a Mitigated/Raw toggle for direct comparison (Phase 3.2 + 3.3 + 4.2).
- **Heron r2 fractional gates** auto-downgrade: when the target backend uses continuous-angle 2q rotations, twirling and ZNE-PEA are auto-disabled with an inline conflict notice (those techniques are mutually exclusive with fractional gates per IBM Runtime docs).

The Jobs Monitoring Dashboard renders a **Mitigation column** showing what was applied to each historical job (Phase 5.2). The Results screen renders a **Mitigated/Raw toggle** when the loaded batch was submitted with `also_run_raw=true` (Phase 4.2).

---

## 3. The numbered ladder (the operator's mental model)

QDash exposes a **single primary knob** — a numbered level from 0 to 3 (plus -1 for Custom) — mirroring the convergent UX pattern across IBM Quantum, IBM Circuit Function, Amazon Braket, and IonQ Cloud:

| Level | Name | Stack | When to use | Wall-clock cost vs Raw |
|:---:|---|---|---|:---:|
| **0** | Raw | bare primitive — no mitigation | hardware benchmarks; raw-noise reference | 1× |
| **1** | Standard | TREX + Pauli twirling + DD (XpXm) | **default for every submission** | ~1× |
| **2** | Aggressive | Standard + ZNE (3 noise factors, exponential extrapolator) | expectation-value workloads with budget for 3× wall-clock | ~3× |
| **3** | TEM | Standard + Algorithmiq Tensor-Network Error Mitigation via IBM Functions | 100q+ utility-scale; Estimator-shape workloads | ~5–15× (Phase 4 — currently downgrades to Standard with a note) |
| **-1** | Custom | operator-supplied per-technique override dict | research; PEC, mthree, layer-noise overrides | varies |

The defaults that fall out of this ladder:

- A new submission with no `mitigation_level` set → **level 1 (Standard)**.
- The operator's persisted Settings preference seeds the Cutting toolbar dropdown's initial value.
- Per-submission override on the toolbar always wins.

The non-obvious property: **Standard is essentially free**. Pauli twirling does not multiply shots — it splits the existing shot budget across `num_randomizations` random Pauli instances, then averages. Dynamical decoupling is pure pulse scheduling — no extra shots. TREX measurement twirling is the same. So enabling Standard everywhere has ~0× cost and meaningfully reduces coherent error bias on the recovered expectation values. There is no operational reason to ever submit at level 0 except for explicit hardware-benchmark workflows.

Level 2 (Aggressive) costs ~3× wall-clock because ZNE runs the same circuit at 3 noise factors {1.0, 3.0, 5.0}. The **cost-preview line** below the toolbar tells the operator this before they hit Run.

---

## 4. Architecture

### 4.1 The MitigationService at the center

```
                     ┌─────────────────────────────────────┐
                     │        MitigationService            │
                     │  (sqk-qtau/.../mitigation_service)  │
                     │                                     │
                     │   ┌───────────────────────────┐     │
                     │   │   .resolve(level, custom, │     │
                     │   │     primitive, backend,   │     │
                     │   │     base_shots,           │     │
                     │   │     cutting_overhead_qbs) │     │
                     │   │           │               │     │
                     │   │           ▼               │     │
                     │   │     MitigationPlan        │     │
                     │   │     (frozen dataclass)    │     │
                     │   └───────────┬───────────────┘     │
                     │               │                     │
                     │  ┌────────────┼─────────────┐       │
                     │  │            │             │       │
                     │  ▼            ▼             ▼       │
                     │ build_      build_       estimate_  │
                     │ sampler_    estimator_   cost(plan) │
                     │ options     options                 │
                     │  │            │             │       │
                     │  ▼            ▼             ▼       │
                     │ SamplerOpts EstimatorOpts CostEst   │
                     │                                     │
                     │   .apply_to_executor(executor, plan)│
                     │      → ZNE-wrapped executor         │
                     │        (fold_circuit_global +       │
                     │         extrapolate_zne)            │
                     └─────────────────┬───────────────────┘
                                       │
                                       │ called by
            ┌──────────────┬───────────┼────────────┬──────────────┐
            │              │           │            │              │
            ▼              ▼           ▼            ▼              ▼
      submit_job   submit_cutting_  qae_       Celery task    POST /api/
      (sync)      _subcircuit     _service    job_tasks.py    mitigation/
                                  ._run_                       estimate
                                  runtime                      (router)
```

Every place that talks to IBM Runtime goes through `MitigationService` for the resolve step. The service is **stateless** — backed by frozen dataclasses, no Mongo dependency, no shared state across calls. It is dependency-light by design so unit tests can exercise the resolution logic without an IBM Runtime account.

### 4.2 Key dataclasses

`MitigationPlan` (frozen dataclass in `services/mitigation_service.py`):

```python
@dataclass(frozen=True)
class MitigationPlan:
    level: int                  # -1, 0, 1, 2, 3
    name: str                   # "raw" | "standard" | "aggressive" | "tem" | "custom"
    primitive: str              # "sampler" | "estimator"
    backend_name: str

    # Resolved per-technique flags
    twirling_gates: bool
    twirling_measure: bool
    dd_enable: bool
    dd_sequence: str            # "XpXm" | "XY4" | "XY8" | ""
    zne_enable: bool
    zne_noise_factors: tuple[float, ...]
    zne_extrapolator: str       # "linear" | "exponential" | "polynomial"
    tem_enable: bool

    effective_shots: int        # after level + QPD floor + custom overrides

    # Pre-flight diagnostics
    conflicts: tuple[str, ...]  # Heron r2 fractional gate notes etc.
    notes: tuple[str, ...]

    # Resolver provenance
    resolved_at: str            # ISO-8601 UTC
    resolver_version: str       # "phase-2.1"

    def to_snapshot(self) -> dict[str, Any]: ...
```

`CostEstimate`:

```python
@dataclass(frozen=True)
class CostEstimate:
    effective_shots: int
    est_wall_seconds: float
    est_iqp_units: float | None
    shot_multiplier: float
    wall_multiplier: float
    notes: tuple[str, ...]
```

Both are frozen — the resolver builds them, callers consume them, no mutation. Snapshot serialisation flattens tuples to lists for Mongo / JSON friendliness.

### 4.3 The five hardware-execution surfaces

Quantum hardware actually runs in five places. Each routes through MitigationService:

| Surface | File | Primitive | Mitigation routing |
|---|---|---|---|
| **Direct jobs (sync)** | `services/job_service.py:submit_job` | SamplerV2 | resolve → build_sampler_options → Sampler(options=…) |
| **Direct jobs (Celery)** | `tasks/job_tasks.py:submit_ibm_job_task` | SamplerV2 | parent dispatches with mitigation kwargs; worker re-resolves on the worker side |
| **Cutting subcircuits** | `services/job_service.py:submit_cutting_subcircuit` | SamplerV2 | resolve with `cutting_overhead_qubits=n_eff` for the QPD shot floor |
| **QAE / QMC** | `services/qae_service.py:_run_runtime` | SamplerV2 | resolve → returns `mitigation_plan` in result dict; `qae_job_service._finalize` lifts it onto QaeJobDocument |
| **Benchmarks** | `services/benchmark_service.py` | (read-only today) | not yet wired — benchmarks should default to level 0 (Raw) |

---

## 5. Data flow — life of a submission

This is the canonical flow for a cutting submission with `mitigation_level=2 + also_run_raw=true` — exercises every part of the system.

### Stage 1 — Operator picks parameters

```
  Cutting screen toolbar
  ┌───────────────────────────────────────────────────────────────┐
  │ Circuit ▾  Mode ▾  Target k  (flex)  Mitigation: Aggressive ▾ │
  │                                       Preset ▾  Analyze  Run  │
  │                                                              │
  │ Status: ...    Mitigation: Aggressive · ~3× shots · est. 5s  │
  │                                       · ~0.08 IQP units      │
  └──────────────────────────────────────────────────────────────┘

  Options card
  ┌─────────────────────────────────────────────────┐
  │ ☐ Also reconstruct bitstring distribution       │
  │ ☑ Also run raw (level-0 sibling) for comparison │
  └─────────────────────────────────────────────────┘
```

The toolbar dropdown's `Value=2` was seeded from `app.State.preferredMitigationLevel` (Phase 3.6 — read from the user_preferences endpoint at login). The cost-preview label was populated by `CircuitCuttingViewModel.applyMitigationPreview` after the most recent Analyze response — it called `POST /api/mitigation/estimate` with the analyze response's partition shape.

### Stage 2 — Run Cutting click → request body

`CircuitCuttingViewModel.buildCreateBody()` assembles:

```json
{
  "mode": "automatic",
  "preset": "generic",
  "cut_plan": { ... analyze response ... },
  "backend_assignments": [ ... ],
  "observables": ["ZIIIIIZ..."],
  "opt_in_distribution": false,
  "timeout_hours": 6.0,
  "retry_strategy": "none",
  "mitigation_level": 2,
  "also_run_raw": true
}
```

POSTed to `/api/circuits/{circuit_id}/cutting/batches`.

### Stage 3 — Server-side resolve + sibling spawn

`CuttingBatchService.create_batch(req)`:

1. **Auto-derive observables** (Phase 0.5) when in AUTOMATIC mode and the operator didn't type any — produces a hardware-aware ZZ correlator set for n>50 cat circuits.

2. **Resolve the batch-level MitigationPlan** via `MitigationService.resolve(level=2, primitive="sampler", base_shots=4096, cutting_overhead_qubits=130)`:
   - Level 2 → Aggressive → twirling + DD + TREX + ZNE enabled.
   - Effective shots = max(4096, _AGGRESSIVE_SHOT_FLOOR=16384) = 16384 (the Aggressive shot floor).
   - QPD shot floor independently bumps to 16384 because cutting_overhead_qubits=130 ≥ 50.
   - `zne_noise_factors = (1.0, 3.0, 5.0)`, extrapolator = "exponential".

3. **Mint sibling_group_id** = uuid4 (because also_run_raw=true).

4. **Persist primary CuttingBatchDocument**:
   - `mitigation_role = "primary"`, `sibling_group_id = <uuid>`,
   - `mitigation_plan = <Aggressive snapshot>`,
   - `status = "queued"`.

5. **Spawn raw sibling**:
   - Resolve a separate plan at level 0.
   - Persist a second `CuttingBatchDocument` with `mitigation_role = "raw"`, the same `sibling_group_id`, and the level-0 snapshot.

6. Return the **primary** batch to the client.

### Stage 4 — Dispatch each batch's subcircuits

When the operator's MATLAB client polls or triggers `dispatch(batch_id)`:

`CuttingBatchService.dispatch(batch_id)`:

1. `pipeline.plan_execution(circuit, cut_plan, observables)` runs `partition_problem` + `generate_cutting_experiments` to produce per-label subexperiment lists + QPD coefficients.

2. For each backend_assignment, call `JobService.submit_cutting_subcircuit`:
   - **Per-child resolve** via `MitigationService` against the actual transpiled width and backend instance. This is where Heron r2 fractional-gate detection runs — a per-child plan can be different from the batch-level plan if the assigned backend is a Heron r2.
   - `MitigationService.build_sampler_options(child_plan)` produces a `SamplerOptions` with:
     ```python
     opts.default_shots = 16384
     opts.twirling.enable_gates = True
     opts.twirling.enable_measure = True
     opts.dynamical_decoupling.enable = True
     opts.dynamical_decoupling.sequence_type = "XpXm"
     ```
   - `Sampler(mode=backend, options=opts).run([sub_experiments], shots=16384)` dispatches.
   - Persist child IBMJobDocument with `mitigation_plan = <child snapshot>`, `batch_id = <primary>`, `cut_role = "label=s0"`.

3. Same flow runs for the **raw sibling batch** in parallel — its level-0 plan produces `options=None` → bare `Sampler(mode=backend)` call.

### Stage 5 — Reconstruction and persistence

When all subcircuits of a batch reach `'completed'`:

`CuttingBatchService.poll_batch(batch_id)` triggers `_reconstruct_and_complete`:

1. Fetch each child's primitive result.
2. `pipeline.reconstruct_expectations(subcircuit_results, observables, cut_plan)` runs the QPD weighted-sum via `qiskit-addon-cutting.reconstruct_expectation_values`.
3. Persist `reconstruction = { expectations: [...], distribution: {...}, ... }` on the batch doc.
4. Status → `'completed'`.

**Phase 5+ extension** (future, see `2026-05-03-cutting-zne-integration.md`): when the primary's `zne_noise_factor` is set and ZNE siblings exist, transition through `'reconstructing_zne'` → call `extrapolate_zne` per observable across siblings → persist `reconstruction.zne_extrapolated.<observable>`.

### Stage 6 — Operator views the result

Operator navigates to Results screen, clicks the cutting batch row, clicks **View Reconstruction**:

`ResultsViewModel.onViewReconstruction()`:

1. `GET /api/cutting/batches/{primary_id}/result` returns the BatchResultResponse including (Phase 4.1):
   ```json
   {
     "batch_id": "<primary>",
     "status": "completed",
     "expectations": [...],
     "sibling_group_id": "<uuid>",
     "mitigation_role": "primary"
   }
   ```

2. The reconstruction dialog renders the expectations table.

3. `applySiblingToggle(data)` sees `sibling_group_id` is non-empty → calls `GET /api/cutting/sibling/{group_id}` (Phase 3.5 endpoint) → caches `{primary_batch_id, raw_batch_id}`.

4. Toggle row above the result table becomes visible:
   ```
   Compare:  [ Mitigated ]  [ Raw (level 0) ]
   ```
   Mitigated is highlighted (primary view).

5. Click "Raw (level 0)" → `onMitigationToggleClicked('raw')` → re-fetches the raw batch's result → re-renders. Toggle stays visible; clicking back uses the cached pair (no extra HTTP).

### Data-flow summary

```
  ┌──────────┐    POST    ┌────────────┐   resolve    ┌─────────────────┐
  │ Operator │ ─────────► │ CuttingBatch │──────────► │ MitigationSvc  │
  │ (MATLAB) │            │ Service      │            │ → MitigationPlan│
  └──────────┘            └─────┬────────┘            └────┬────────────┘
        ▲                       │ persist                   │
        │                       ▼                           │ build_sampler_options
        │                ┌────────────────────┐             │
        │                │ CuttingBatchDocument│             ▼
        │                │ + mitigation_plan   │     ┌──────────────┐
        │                │ + sibling_group_id  │     │ SamplerOptions│
        │                │ + mitigation_role   │     └──────┬───────┘
        │                └─────┬───────────────┘            │
        │                      │ dispatch                   │
        │                      ▼                            │
        │              ┌────────────────────┐               │
        │              │ JobService.        │ ◄─────────────┘
        │              │ submit_cutting_    │
        │              │ subcircuit         │
        │              └─────┬───────────────┘
        │                    │ SamplerV2.run + IBM Runtime
        │                    ▼
        │              ┌────────────────────┐
        │              │ IBMJobDocument     │
        │              │ + mitigation_plan  │
        │              │ + batch_id+cut_role│
        │              └─────┬───────────────┘
        │                    │ poll → reconstruct
        │                    ▼
        │              ┌────────────────────┐
        │              │ reconstruction.    │
        │              │   expectations     │
        │              └─────┬───────────────┘
        │       GET /api/cutting/batches/{id}/result
        └────────────────────┘
```

---

## 6. The submission paths in detail

### 6.1 Direct jobs — sync path

`JobService.submit_job(...)` (file `services/job_service.py`):

```python
mitigation_plan = MitigationService().resolve(
    level=mitigation_level,           # from request body
    custom=mitigation_options,
    primitive="sampler",
    backend=backend,                  # actual Backend instance
    backend_name=backend_name,
    base_shots=shots,
)
mitigation_plan_snapshot = mitigation_plan.to_snapshot()
sampler_opts = mitigation_svc.build_sampler_options(mitigation_plan)
shots = mitigation_plan.effective_shots

sampler = (
    Sampler(mode=backend, options=sampler_opts)
    if sampler_opts is not None
    else Sampler(mode=backend)
)
job = sampler.run([transpiled], shots=shots)
```

The persisted `IBMJobDocument` carries `mitigation_plan_snapshot` so the Jobs screen renders the badge.

### 6.2 Direct jobs — Celery path

`JobService.submit_job` (Path 1 in `submit_job`): pre-resolves the plan **at dispatch time**, persists the snapshot on the queued doc, forwards `mitigation_level` and `mitigation_options` to `submit_ibm_job_task` via Celery args:

```python
_celery_submit.apply_async(
    args=[job_record_id, project_id, circuit_doc["raw_content"],
          circuit_doc["format"], backend_name,
          effective_shots_at_dispatch, optimization_level],
    kwargs={
        "mitigation_level": mitigation_level,
        "mitigation_options": mitigation_options,
    },
    queue="submission",
)
```

`tasks/job_tasks.py:submit_ibm_job_task` re-resolves on the worker side (the worker has the actual `Backend` instance, not the dispatcher) and uses the same MitigationService API.

### 6.3 Cutting subcircuits

`JobService.submit_cutting_subcircuit(...)`: same pattern as `submit_job` plus `cutting_overhead_qubits=n_eff` so the QPD shot floor (16384 at n≥50) applies independently of mitigation level.

A level-0 (Raw) cutting submission still pays the QPD shot floor — the floor is a property of the QPD reconstruction's variance amplification, not the noise mitigation stack. This is enforced by the `_cutting_qpd_shot_floor` helper at the top of `services/job_service.py`.

### 6.4 QAE / QMC

`qae_service.py:_run_runtime`: uses MitigationService.resolve, returns `{"mitigation_plan": snapshot, ...}` in the result dict. `qae_job_service._finalize` lifts the snapshot onto `QaeJobDocument.mitigation_plan` (mirrors the existing `runtime_job_id` lift). The legacy `mitigation: "zne"|"pec"` field on `QaeAnalyzeRequest` continues to drive executor-layer ZNE for the QMC popup separately.

### 6.5 Benchmarks (intentionally not yet wired)

Benchmarks measure raw hardware behavior — the mitigation stack would invalidate the comparison. The intended Phase 6 wiring is to default `mitigation_level=0` (Raw) for all benchmark submissions and add an explicit "Mitigated benchmark" alternate mode that runs the same volumetric set under level 1 for cost-vs-fidelity comparison.

---

## 7. Persistence

### 7.1 Document fields

The `mitigation_plan` field lands on three documents — all with `dict | None` type and `default=None` so legacy submissions persisted before Phase 2.2 keep loading without migration.

`IBMJobDocument` (`dbmodel/ibm_job.py`):

```python
mitigation_plan: dict[str, Any] | None = Field(
    None,
    description=(
        "Resolved MitigationPlan snapshot at submit time. "
        "Schema: {level, name, primitive, backend_name, "
        "twirling_gates, twirling_measure, dd_enable, dd_sequence, "
        "zne_enable, zne_noise_factors, zne_extrapolator, "
        "tem_enable, effective_shots, conflicts, notes, "
        "resolved_at (ISO-8601 UTC), resolver_version}."
    ),
)
sibling_group_id: str | None = Field(None, description="...")
mitigation_role: str | None = Field(None, description="'primary' | 'raw'")
```

`CuttingBatchDocument` (`dbmodel/cutting_batch.py`): same three fields. Captures the **batch-level** snapshot (the per-child IBMJobDocument snapshots may differ if a child landed on a Heron r2 backend that triggered a different downgrade).

`QaeJobDocument` (`dbmodel/qae_job.py`): same three fields.

### 7.2 Snapshot schema (the body of `mitigation_plan`)

```json
{
  "level": 2,
  "name": "aggressive",
  "primitive": "sampler",
  "backend_name": "ibm_marrakesh",
  "twirling_gates": true,
  "twirling_measure": true,
  "dd_enable": true,
  "dd_sequence": "XpXm",
  "zne_enable": true,
  "zne_noise_factors": [1.0, 3.0, 5.0],
  "zne_extrapolator": "exponential",
  "tem_enable": false,
  "effective_shots": 16384,
  "conflicts": [],
  "notes": [],
  "resolved_at": "2026-05-03T12:34:56.789012+00:00",
  "resolver_version": "phase-2.1"
}
```

The resolver writes this snapshot at submit time. Future-you can replay exactly what ran by reading it back.

### 7.3 Sibling pairing

When `also_run_raw=true`:

| Field | Primary | Sibling |
|---|---|---|
| `batch_id` | `<uuid_primary>` | `<uuid_sibling>` |
| `sibling_group_id` | `<uuid_group>` | `<uuid_group>` *(same)* |
| `mitigation_role` | `"primary"` | `"raw"` |
| `mitigation_plan.level` | 2 (operator's choice) | 0 (forced) |
| `cut_plan` | `<same>` | `<same>` |
| `backend_assignments` | `<same>` | `<same>` |
| `observables` | `<same>` | `<same>` |

The Phase 5+ ZNE extension (when implemented) extends this table with two more rows for `mitigation_role="zne_factor"` siblings carrying `zne_noise_factor` 3.0 and 5.0.

---

## 8. The cost-preview endpoint

`POST /api/mitigation/estimate` (file `routers/mitigation.py`):

Request body (matches `EstimateRequest` Pydantic shape):

```json
{
  "mitigation_level": 2,
  "mitigation_options": null,
  "primitive": "sampler",
  "backend_name": "ibm_marrakesh",
  "base_shots": 4096,
  "circuit_qubits": 260,
  "cutting_overhead_qubits": 130
}
```

Response:

```json
{
  "plan": { ... full MitigationPlan snapshot ... },
  "cost": {
    "effective_shots": 16384,
    "est_wall_seconds": 4.915,
    "est_iqp_units": 0.0819,
    "shot_multiplier": 3.0,
    "wall_multiplier": 3.0,
    "notes": []
  },
  "summary": "Mitigation: Aggressive · ~3× shots · est. 5s · ~0.08 IQP units"
}
```

The MATLAB `MitigationService` HTTP wrapper consumes this. The `summary` string is the operator-facing one-liner the Cutting toolbar's cost-preview label renders directly — the UI doesn't compose the cost description itself.

A sibling endpoint `GET /api/mitigation/levels` returns the ordered ladder (Raw / Standard / Aggressive / TEM / Custom) with id + label + one-line description + overhead hint, so the dropdown can render itself dynamically. Today the MATLAB dropdown still uses a hardcoded list as a fallback; the future Settings dialog refresh path will replace it with the live list.

---

## 9. The sibling machinery

### 9.1 `also_run_raw` — running a raw sibling alongside

**Operator flow**: Cutting Options card has the checkbox **"Also run raw (level-0 sibling) for comparison"**. When checked, on Run:

1. Server creates the primary batch (operator's chosen level).
2. Server creates a **second** CuttingBatchDocument at `mitigation_level=0` with the same circuit, cut_plan, backend_assignments, observables.
3. Both share `sibling_group_id`. Primary has `mitigation_role="primary"`; sibling has `mitigation_role="raw"`.

Each batch runs through dispatch → reconstruction independently. They share **nothing at execution time** — separate IBM job records, separate poll cycles, separate reconstruction calls.

**Cost**: 2× IBM shot budget (two batches running the same circuit pair). The cost-preview line should reflect this (`also_run_raw=true` doubles the wall-clock estimate); today the preview only accounts for the primary's level multiplier, so this is a documented gap.

### 9.2 The pair-lookup endpoint

`GET /api/cutting/sibling/{sibling_group_id}` returns:

```json
{
  "sibling_group_id": "<uuid>",
  "primary_batch_id": "<uuid_primary>",
  "raw_batch_id": "<uuid_sibling>",
  "primary_status": "completed",
  "raw_status": "completed"
}
```

Either batch field can be `null` when only one sibling exists in the group (e.g. raw sibling persistence failed at submit time — primary still runs alone).

### 9.3 The Results screen toggle

`ResultsScreen.m` summary panel grew from 2 rows to 3 rows in Phase 4.2 — row 1 is a 4-column toggle grid, hidden by default. When the loaded batch has `sibling_group_id ≠ null`, `ResultsViewModel.applySiblingToggle` calls the pair endpoint, caches the result, and shows:

```
Compare:  [ Mitigated ]  [ Raw (level 0) ]
```

with the active role highlighted. Clicking the inactive button re-fetches the alternate batch's result, re-renders the dialog, flips the styles. The pair is cached on the VM so a back-and-forth toggle doesn't re-hit the sibling endpoint.

### 9.4 Why this generalises to ZNE

The future Phase 5 cutting+ZNE integration **reuses** this exact machinery. At `mitigation_level=2 + cutting`, the server spawns N siblings (one per noise factor) instead of 1. Reconstruction extrapolates across siblings via the existing `extrapolate_zne` helper. **No QPD-coefficient bookkeeping changes required.** This is the architectural insight captured in `docs/superpowers/specs/2026-05-03-cutting-zne-integration.md`.

---

## 10. The ZNE primitives

`fold_circuit_global(circuit, noise_factor)` (in `services/mitigation_service.py`):

Implements canonical global folding — replaces `U` with `U (U^† U)^k` where `k = (noise_factor - 1) / 2`. Conserves the unitary (so the noiseless expectation value is unchanged) but exposes each gate to `noise_factor` × the baseline noise per shot.

Smoke test in this session showed:
- `noise_factor=1.0` → 2 gates (no folding)
- `noise_factor=3.0` → 6 gates (one fold)
- `noise_factor=5.0` → 10 gates (two folds)

`extrapolate_zne(values, noise_factors, extrapolator)` — four extrapolators:

- `"linear"` / `"polynomial"`: `numpy.polyfit` deg 1, intercept at x=0.
- `"richardson"`: closed-form Richardson coefficients (exact for linear noise channels).
- `"exponential"`: `scipy.optimize.curve_fit` on `y = a·exp(-b·x) + c`.

All four exactly recover the linear-model intercept on synthetic test data. On real noisy data, `"exponential"` is the IBM Runtime default for moderately-deep circuits because incoherent noise produces approximately exponential decay.

`MitigationService.apply_to_executor(executor, plan)`:

```python
def wrapped(circuit, *args, **kwargs):
    per_factor = []
    for nf in noise_factors:
        folded = fold_circuit_global(circuit, nf)
        per_factor.append(executor(folded, *args, **kwargs))

    if all(isinstance(v, (int, float)) for v in per_factor):
        return extrapolate_zne(per_factor, noise_factors, extrapolator)

    if all(isinstance(v, dict) for v in per_factor):
        # Per-Pauli-string extrapolation across noise factors.
        return {key: extrapolate_zne(...) for key in per_factor[0]}

    return per_factor[0]  # unknown shape; pass through
```

Handles two output shapes from the inner executor: scalar (single expectation value) or `dict[pauli_string → float]` (per-observable values, e.g. cutting reconstruction output). When `plan.zne_enable=False`, returns the executor unchanged — no-op for level 0/1, level-3 TEM (downgraded), or Heron r2 fractional-gate downgrades.

**Today's call status**: the wrapper is implemented and tested. It is not yet called from the cutting reconstruction path — that integration is what the Phase 5 spec covers. Any future direct-Estimator submission can wire it cleanly today.

---

## 11. Heron r2 fractional-gate handling

IBM Heron r2 (Marrakesh, Fez, Torino) supports continuous-angle 2q rotations (`rzz`, `rxx`, `ryy`, `rzx`) — these are **mutually exclusive** with PEC, ZNE-PEA, and Pauli twirling per IBM Runtime docs.

`MitigationService.resolve()` checks the target backend's `target.operation_names` for the canonical fractional gate names. When detected:

| Requested level | Effective level | Conflict note added to plan.conflicts |
|---|---|---|
| 0 (Raw) | 0 | (none) |
| 1 (Standard) | DD + measurement TREX only (twirling disabled) | `"Heron r2 fractional gates are mutually exclusive with Pauli gate twirling — twirling disabled. DD + measurement TREX still active."` |
| 2 (Aggressive) | DD + measurement TREX only (twirling + ZNE disabled) | `"... ZNE-PEA. Falling back to DD + TREX. To enable ZNE, switch to a non-fractional backend."` |
| 3 (TEM) | TEM (no change — TEM operates at post-process layer) | (none — TEM is not primitive-level) |
| -1 (Custom) | passes through; conflicts surfaced as plan.notes | (none — operator's responsibility) |

The MATLAB UI renders `plan.conflicts` as an amber inline notice next to the level dropdown — same visual pattern as the Cutting screen's `coherence_warning`.

---

## 12. UI surfaces — every place QEM appears

| Surface | Repo / file | What the operator sees |
|---|---|---|
| **Cutting toolbar dropdown** | `screens/CircuitCuttingScreen.m` | "Mitigation: Aggressive ▾" — picks the level for this submission |
| **Cutting cost-preview line** | `screens/CircuitCuttingScreen.m` (Row 2) | "Mitigation: Aggressive · ~3× shots · est. 5s · ~0.08 IQP units" |
| **Cutting Options card** | `screens/CircuitCuttingScreen.m` | "Also run raw (level-0 sibling) for comparison" checkbox |
| **Cutting coherence warning** | `screens/CircuitCuttingScreen.m` | Inline amber note above Observables when `n>50` (Phase 0) |
| **Settings → Defaults dialog** | `viewmodels/SettingsViewModel.m` | "Default mitigation level" dropdown, persisted to user_preferences |
| **Results screen toggle** | `screens/ResultsScreen.m` | "Compare: [Mitigated] [Raw (level 0)]" buttons (when sibling exists) |
| **Jobs Monitoring Dashboard** | `screens/JobsScreen.m` | New "Mitigation" column 7 showing the level name per job |

A complete operator pipeline that exercises every surface:

1. Login → Settings → Defaults → "Default mitigation level: Aggressive" → Save. (Persists via `POST /api/settings`.)
2. Open Cutting tab → toolbar dropdown auto-selects Aggressive. Cost preview line populates after Analyze.
3. Check "Also run raw" → click Run.
4. Server creates 2 batches (primary + raw sibling), each 130-qubit subcircuits dispatched in parallel.
5. Open Jobs tab → Mitigation column shows "aggressive" on the primary's child rows and "raw" on the sibling's children.
6. Wait for both batches to reach `'completed'`.
7. Open Results tab → click the primary batch → click View Reconstruction → dialog shows the expectations table.
8. Toggle row appears: click "Raw (level 0)" → re-fetches the raw sibling's result → operator sees the un-mitigated values for direct comparison.

---

## 13. Backwards compatibility

Submissions persisted **before Phase 2.2** (commit `c008d2f8`) have `mitigation_plan = null`. The system handles these gracefully:

- **Documents load without migration** — the field is `Optional[dict]` with default None on the Pydantic model.
- **Jobs table column** renders empty cell for legacy rows — `JsonHelper.jobsToRows` falls through the empty-string fallback.
- **Results screen toggle** never appears for legacy batches — `sibling_group_id` is null, `applySiblingToggle` hides the toggle row.
- **Re-running a legacy circuit** today picks up the new system from scratch — operator's level selection, the resolved plan persists.

No schema migration is required.

---

## 14. Phased rollout — the 16 commits

The QEM rollout shipped across 16 commits over 4 days:

### Phase 2 — Backend foundation

| Phase | Commit | Repo | Description |
|---|---|---|---|
| 0 | `a2049dcc` | sqk-qtau | Pre-rollout: Sampler V2 mitigation in cutting submit path |
| 0.5 | `892c73e` | sqk-qtau-matlab | Coherence warning above Observables textarea |
| 1 | `e0476158` | sqk-qtau | Universal mitigation-level Standard defaults |
| 2.1 | `e6177be3` | sqk-qtau | MitigationService skeleton + dataclasses |
| 2.2 | `c008d2f8` | sqk-qtau | Persist mitigation_plan snapshot on result docs |
| 2.3 | `5fc1a12c` | sqk-qtau | Schema fields + cost-preview endpoint |
| 2.4 | `38b0d835` | sqk-qtau | Plumb mitigation_level through submit paths |
| 2.5 | `29fc188`  | sqk-qtau-matlab | Cost-preview line on Cutting toolbar |

### Phase 3 — Operator-visible controls

| Phase | Commit | Repo | Description |
|---|---|---|---|
| 3.1 | `48d89bd`  | sqk-qtau-matlab | Mitigation level dropdown on Cutting toolbar |
| 3.2 | `49f3dbbb` | sqk-qtau | also_run_raw sibling-batch server plumbing |
| 3.3 | `588c1b2`  | sqk-qtau-matlab | also_run_raw checkbox on Options card |
| 3.4 | `30fc2bce` | sqk-qtau | ZNE primitives + working apply_to_executor |
| 3.5 | `d248f27e` | sqk-qtau | Sibling lookup endpoint |
| 3.6 | `6baa619`  | sqk-qtau-matlab | Default-level picker on Settings dialog |

### Phase 4 — Mitigated-vs-raw comparison

| Phase | Commit | Repo | Description |
|---|---|---|---|
| 4.1 | `9668754d` | sqk-qtau | Sibling info on BatchResultResponse |
| 4.2 | `5ffaa78`  | sqk-qtau-matlab | Mitigated/Raw toggle on Results screen |

### Phase 5 — Polish + design for the next sprint

| Phase | Commit | Repo | Description |
|---|---|---|---|
| 5.1 | `55b3aee`  | sqk-qtau-matlab | Cutting+ZNE integration design spec |
| 5.2 | `26877dd`+`d3d5ba6c` | both | Mitigation badge on Jobs table |

Total: ~3500 LOC across both repos plus ~600 LOC of design specs and overview documentation (this file).

---

## 15. What's not yet implemented

These are the **deferred items** with clear paths forward:

1. **Cutting+ZNE pipeline integration** — fully specified in `docs/superpowers/specs/2026-05-03-cutting-zne-integration.md`. The architectural insight (reuse sibling_group_id machinery + post-process extrapolation across siblings, instead of per-subexperiment folding) is captured. ~7 days, 5 sub-commits.

2. **M3 calibration cache** — `mthree` library integration. Per-backend readout calibration matrix with TTL (~2 hours), applied as post-processing to Sampler counts. ~300 LOC, separate sprint.

3. **Level 3 TEM routing** — Algorithmiq Tensor-Network Error Mitigation via the IBM Functions catalog. Today the resolver downgrades level 3 to Standard with a note. Implementation requires IBM Functions auth + the function's input/output contract.

4. **Side-by-side Mitigated/Raw layout** — current toggle swaps between views; v2 would render both columns with deltas highlighted. UI polish.

5. **Jobs/QAE sibling-spawn** — `also_run_raw` is plumbed for cutting only today. Mirroring the same pattern in `JobService.submit_job` and `QaeService.analyze` is ~30 LOC each — but most operators care most about cutting, so this is low priority.

6. **Settings tab cost-preview integration** — when the operator changes the default level on the Settings dialog, the cost-preview should update live. Today the dialog only shows the dropdown.

7. **Benchmarks default-to-Raw** — Benchmarks haven't been wired through MitigationService yet. Should default to level 0 (Raw) since they measure raw hardware, with an alternate "Mitigated benchmark" mode for cost-vs-fidelity comparison.

8. **Cancellation propagation across siblings** — cancelling a primary batch should auto-cancel its raw sibling. Today they cancel independently.

---

## 16. Reference

### External

- **Mitiq library** (Unitary Foundation) — [mitiq.readthedocs.io](https://mitiq.readthedocs.io/en/stable/guide/guide.html). The executor-callable pattern + global folding + extrapolator catalogue this rollout's primitives mirror.
- **Qiskit Runtime V2** — `SamplerV2.options` reference: [SamplerOptions](https://quantum.cloud.ibm.com/docs/en/api/qiskit-ibm-runtime/options-sampler-options-v2), [TwirlingOptions](https://docs.quantum.ibm.com/api/qiskit-ibm-runtime/options-twirling-options), [DynamicalDecouplingOptions](https://quantum.cloud.ibm.com/docs/en/api/qiskit-ibm-runtime/options-dynamical-decoupling-options).
- **IBM Functions catalog** — [Algorithmiq TEM](https://quantum.cloud.ibm.com/functions?id=algorithmiq-tem) (level 3 target).
- **Filippov et al. 2023** — *Scalable tensor-network error mitigation* (arXiv 2307.11740) — the technique behind level 3 TEM.
- **IBM Heron r2 fractional gates** — [IBM Quantum blog](https://www.ibm.com/quantum/blog/fractional-gates).

### Internal

- **`docs/superpowers/specs/2026-05-03-mitigation-service.md`** — the Phase 2 service-architecture spec.
- **`docs/superpowers/specs/2026-05-03-cutting-zne-integration.md`** — the Phase 5+ cutting-pipeline integration spec.
- **`docs/superpowers/specs/2026-04-24-circuit-cutting-design.md`** — the original cutting reconstruction architecture (foundation this builds on).
- **`docs/architecture.md`** — high-level system architecture; QEM is one subsystem.
- **`docs/workflow.md`** — operator workflow guide.

### Source-code entry points

| Component | File |
|---|---|
| MitigationService | `sqk-qtau/src/qdash/api/services/mitigation_service.py` |
| Estimate endpoint | `sqk-qtau/src/qdash/api/routers/mitigation.py` |
| Cutting batch + sibling spawn | `sqk-qtau/src/qdash/api/services/cutting_batch_service.py` |
| Sibling lookup endpoint | `sqk-qtau/src/qdash/api/routers/cutting.py` (`get_sibling_pair`) |
| MATLAB MitigationService client | `sqk-qtau-matlab/src/domain/services/MitigationService.m` |
| Cutting screen | `sqk-qtau-matlab/src/presentation/screens/CircuitCuttingScreen.m` |
| Cutting VM (mitigation logic) | `sqk-qtau-matlab/src/presentation/viewmodels/CircuitCuttingViewModel.m` |
| Results screen toggle | `sqk-qtau-matlab/src/presentation/viewmodels/ResultsViewModel.m` |
| Settings default picker | `sqk-qtau-matlab/src/presentation/viewmodels/SettingsViewModel.m` |
| Jobs table mitigation column | `sqk-qtau-matlab/src/infrastructure/config/JsonHelper.m` (`jobsToRows`) |

---

*This document is the canonical operator-and-developer overview of QEM in QDash. When extending the system, update this doc + the relevant phase-specific spec — the phased commit log captures history; this doc captures the current shape.*
