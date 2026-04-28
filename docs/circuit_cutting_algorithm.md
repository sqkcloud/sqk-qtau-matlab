# Circuit Cutting — Algorithm & Implementation

This doc explains exactly how the Circuit Cutting feature splits a wide quantum circuit into smaller subcircuits, dispatches them across multiple IBM backends in parallel, and reconstructs the final result. It covers the math, the decision tree, the failure modes, and the file paths.

Audience: contributors who need to debug, extend, or audit the cutting pipeline.

---

## 1. Why cut circuits at all

A QPU has a fixed width — `ibm_kingston` has 156 qubits, `ibm_marrakesh` 156, `ibm_miami` 127, etc. A circuit wider than the widest available QPU **cannot run**. Either the operator pre-cuts manually, or this feature handles it.

But cutting is **not free**. Each cut multiplies the shot budget by a factor of `~4–6` (the QPD sampling overhead). The total overhead is `γ ≈ 4^k` for `k` cuts, so a 10-cut plan needs `~10⁶ ×` the shots a direct run would need. Cutting a circuit that already fits is **always strictly worse** than not cutting.

The smart-analyze recommendation in §4 is the gate that prevents that mistake.

---

## 2. The library — `qiskit-addon-cutting`

We wrap [Qiskit Addon: Circuit Cutting](https://github.com/Qiskit/qiskit-addon-cutting) `0.10.x`. The relevant entry points:

| Function | What it does | Used by |
|---|---|---|
| `find_cuts(circuit, OptimizationParameters, DeviceConstraints)` | Searches for cut locations. Returns `(cut_circuit, metadata)`. | `analyze_cuts` |
| `partition_problem(circuit, partition_labels, observables)` | Applies labels to the cut circuit and produces a `PartitionedCuttingProblem` with `subcircuits`, `subobservables`, `bases`. | `plan_execution` |
| `generate_cutting_experiments(circuits, observables, num_samples)` | Expands each partition's QPD instructions into the *measure-and-prepare* sub-experiments that actually run on hardware. Returns `(subexperiments_by_label, coefficients)`. | `plan_execution` |
| `reconstruct_expectation_values(primitive_results_by_label, coefficients, obs_by_label)` | Combines sampler results back into a list of expectation values. | `reconstruct_expectations` |

The `coefficients` returned from `generate_cutting_experiments` are *batch-global* — one per sub-experiment across all labels. `reconstruct_expectation_values` aligns them with each label's primitive result internally.

---

## 3. The pipeline — five pure stages

`CuttingPipeline` (in `sqk-qtau/src/qdash/api/services/cutting/base.py`) is an abstract 5-stage pipeline. `GenericPipeline` is the only concrete implementation today. Domain-specific presets (Phase 2 work) will subclass it.

```
analyze_cuts  →  plan_execution  →  select_backends  →  reconstruct_expectations  →  post_process
   (find       (partition          (assign         (combine                       (preset
    cut         + generate         each sub        sampler                        transform
    locations)  experiments)       to a real       results +                      → image,
                                   IBM backend)    coefficients)                  distribution,
                                                                                  etc.)
```

Stages are **pure** — no Mongo I/O, no IBM Runtime calls. Orchestration lives in `CuttingBatchService`.

### 3.1 `analyze_cuts(circuit, target_k)` — find cuts + check feasibility

`GenericPipeline.analyze_cuts`:

1. **Strip measurements + decompose to ≤2-qubit gates** (`_prepare_circuit_for_cutting`). The addon refuses to operate on circuits with classical bits or 3+ qubit gates; we run Qiskit's `transpile` with a wide basis set (`u`/`u1`/`u2`/`u3`/`cx`/`rx`/`ry`/`rz`/`h`/`x`/`y`/`z`/`s`/`sdg`/`t`/`tdg`/`sx`/`sxdg`/`id`) at `optimization_level=0` to get correctness without optimisation.
2. **Decide `qubits_per_qpu`**:
   - If caller passed `target_k`: `qubits_per_qpu = ⌈n / target_k⌉`.
   - Else: `qubits_per_qpu = ⌈n / 2⌉` (legacy default — overridden upstream by the smart `target_k` default; see § 4).
3. **Call `find_cuts`** with `OptimizationParameters()` + `DeviceConstraints(qubits_per_subcircuit=qubits_per_qpu)`.
4. **Derive partition labels** from the connectivity graph of the cut circuit (`_labels_from_cut_circuit`). Each connected component (treating cut markers `qpd_2q` / `cut_wire` / `move` and `barrier` as boundaries) becomes one subcircuit. Singletons (qubits with no 2-qubit gates after the cut) get *packed* into the largest under-budget subcircuit via `_pack_singletons`. This avoids the degenerate `73 + 1 + 1 + 1 + …` partition that BV-style oracle circuits produce.
5. **Compute feasibility**: `feasible = (sampling_overhead ≤ MAX_OVERHEAD)`. `MAX_OVERHEAD = 1e6` by default — beyond that, the reconstruction variance dominates any signal regardless of shot count.
6. **Return the cut plan dict** with `cuts`, `k`, `target_k`, `sampling_overhead`, `sampling_overhead_log10`, `per_subcircuit_qubits`, `qubits_per_qpu`, `feasible`, `feasibility_reason`, plus a hidden `_partition_labels` list cached for stage 2.

**Overflow fallback** — when the addon's `gamma_UB` accumulator overflows `float64` (which happens on very wide / densely-entangling circuits like `qugan_n395.qasm`), we trap the `OverflowError` and fall through to `_build_overflow_fallback_plan`. That builds a deterministic contiguous-range partition (no addon involvement) and flags the plan as `feasible=False` + `_addon_overflowed=True`. The dispatch path refuses to execute fallback plans — the feasibility_reason explains why.

### 3.2 `plan_execution(circuit, cut_plan, observables)` — expand to hardware-ready experiments

This is where the actual sub-experiments get generated.

1. Re-prepare the circuit (same strip + decompose).
2. Re-call `find_cuts` (cheap re-derivation; cached labels are reused).
3. Build a `PauliList` from the operator's `observables` parameter (default: all-Z over the full width).
4. Call `partition_problem(cut_circuit, partition_labels, pauli_obs)` → `PartitionedCuttingProblem` with `.subcircuits` (one per label) and `.subobservables`.
5. Call `generate_cutting_experiments(subcircuits, subobservables, num_samples=DEFAULT_NUM_SAMPLES=1000)` → returns the dict `subexperiments_by_label[label]` (a *list* of hardware-ready `QuantumCircuit` objects per label) plus a flat `coefficients` list.
6. Return the execution plan dict with:
   - `partition_subcircuits`: `[subcircuits[k] for k in sorted_labels]` — one QPD-decorated subcircuit per label (NOT directly runnable; included for visualisation / debugging).
   - `subexperiments_by_label`: `{label: [QuantumCircuit, …]}` — the actual circuits hardware will see.
   - `coefficients`: `[(weight, WeightType), …]` — QPD coefficients aligned with the sub-experiment enumeration.
   - `subobservables_by_label`: serialised Pauli strings per label.
   - `label_order`: deterministic sort of label keys (`s0`, `s1`, …).

### 3.3 `select_backends(subcircuits, pool, mode)` — size-aware, parallelism-preferring

```
Sort subcircuit indices by width DESCENDING.
For each subcircuit (widest first):
    fitting    = [b in pool : b.num_qubits ≥ sub.num_qubits]
    if fitting is empty:
        raise ValueError("no backend wide enough")
    unused_fitting = [b in fitting : b.name not in used_names]
    if unused_fitting non-empty:
        chosen = smallest by num_qubits   ← distinct-first
    else:
        smallest_fit_q = min num_qubits in fitting
        tier            = backends in fitting with that exact width
        chosen          = tier[i % len(tier)]   ← round-robin within tier
    used_names.append(chosen.name)
```

Why fit-decreasing greedy with distinct-first:
- **Fit-decreasing**: the widest subcircuit must claim a wide backend before narrower siblings can hog it.
- **Smallest unused fitting**: leaves the widest backends free for any wider sibling we haven't placed yet.
- **Distinct-first**: maximises actual parallelism on the IBM fleet — a 3-cut batch goes to 3 different QPUs and runs in parallel rather than queuing serially behind one backend.

Falls back to plain round-robin when widths are unknown (legacy `pool: list[str]` path).

When the operator picked `mode='automatic'`, `CuttingBatchService.dispatch` invokes this with the live IBM pool from `ibm_runtime.get_configured_backends_with_widths()`. When mode is `'assisted'` or `'manual'`, the MATLAB UI sends explicit per-row assignments and this method is bypassed entirely.

### 3.4 `reconstruct_expectations(subcircuit_results, observables, cut_plan)` — combine

Reads the persisted `coefficients`, `label_order`, and `subobservables_by_label` from the cut plan, then calls `reconstruct_expectation_values` from the addon. Returns one row per observable: `{observable, value, std_err, status}`.

When sampler results are missing or the cached coefficients aren't present (simulator path / older batch docs), returns the observables with `value=NaN, std_err=NaN, status="unreconstructed"` so the UI marks them clearly instead of lying with zeros.

### 3.5 `post_process(reconstruction, context)` — preset-specific transform

Identity by default. Phase 2 presets will override this for image-domain or distribution-domain outputs.

---

## 4. Smart-analyze — the recommendation gate

`CuttingService.analyze_cuts` in `sqk-qtau/src/qdash/api/services/cutting_service.py` wraps the pipeline call with two policy checks:

### 4.1 Skip-cutting recommendation (Phase 1)

```
n      = circuit.num_qubits
pool   = get_configured_backends_with_widths()   # [{name, num_qubits}, …]
widest = max(b.num_qubits for b in pool)

if n ≤ widest:
    cutting_recommended       = False
    direct_run_backend        = smallest fitting backend
    cutting_recommendation_reason = "Circuit fits on … (Xq). Cutting would only add 4^k sampling overhead — submit directly via the Backends tab."
```

The MATLAB UI surfaces this as a modal `uiconfirm` with three options: **Submit Directly** (bridges to Backends with the suggested backend pre-selected on `AppState.selectedBackend`), **Proceed with Cutting** (research / curiosity path), **Cancel** (drop the analysis).

### 4.2 Smart `target_k` default (Phase 2)

When the caller doesn't pin `target_k` AND `n > widest`:

```
target_k = max(2, ⌈n / widest⌉)
```

So a 250q circuit on a 156q-widest fleet auto-picks `target_k=2` (two ~125q halves, both fit on a 156q device). The legacy default of `n // 2` would have picked `target_k=125` and produced sampling overhead in the `4^125` range — utterly infeasible.

When the smart default kicks in, `cutting_recommendation_reason` reads:

> "Circuit width Nq exceeds the widest configured backend (Xq). Cutting into K subcircuits is recommended."

---

## 5. The batch lifecycle

`CuttingBatchService` (`sqk-qtau/src/qdash/api/services/cutting_batch_service.py`) owns Mongo + IBM Runtime I/O. The pipeline stays pure; this is where the side effects live.

```
POST /api/circuits/{cid}/cutting/batches
  │  body = {mode, preset, cut_plan, backend_assignments, observables, ...}
  ▼
CuttingBatchService.create_batch
  │  • Materialise CuttingBatchDocument
  │  • status = "queued"
  │  • Persist
  ▼
CuttingBatchService.dispatch                                        ← still synchronous in the request
  │  • status = "partitioning"
  │  • plan = pipeline.plan_execution(circuit, cut_plan, observables)
  │  • Enrich cut_plan with coefficients + label_order + subobservables
  │  • If backend_assignments empty:
  │      pool        = get_configured_backends_with_widths()
  │      assignments = pipeline.select_backends(partition_subs, pool, mode)
  │  • For each (label, sub_experiments) in subexperiments_by_label:
  │      JobService.submit_cutting_subcircuit(   ← single SamplerV2.run([…]) per label
  │          subcircuit  = sub_experiments,      ← list of hardware-ready circuits
  │          batch_id    = …,
  │          cut_role    = "label=s0")
  │  • status = "executing"
  ▼
HTTP 202 with batch_id
```

### 5.1 Polling

```
GET /api/cutting/batches/{batch_id}        ← every 3 s while the dialog is open
  ▼
CuttingBatchService.poll_batch
  │  • child_states = [JobService.get_job_status(project_id, cid)
  │                    for cid in doc.child_job_ids]
  │  • all_done    = all child status ∈ {completed, failed}
  │  • progress    = mean(child.progress_pct)   ← server-side aggregation
  │
  ├─ all_done & no failures → _reconstruct_and_complete
  ├─ all_done & any failed  → status = "partial_failure"
  └─ otherwise              → just persist progress_pct
```

The polling endpoint passes `project_id` through to `JobService.get_job_status` because the job repo's index requires both fields. (An earlier bug duck-typed a `get_job(record_id)` single-arg hook that didn't exist on `JobService` — fixed; see git history.)

### 5.2 Reconstruction

```
_reconstruct_and_complete:
  • status = "reconstructing"
  • For each child:
      role = JobService.get_job_status(project_id, cid).cut_role   # "label=s0"
      result = child.raw_counts → SamplerResult
  • subcircuit_results = [{label, primitive_result}, …]
  • expectations = pipeline.reconstruct_expectations(...)
  • post = pipeline.post_process(reconstruction, context)
  • status = "completed"
  • Persist reconstruction
```

If reconstruction throws, the batch transitions to `failed` AND `subcircuit_measurements` is preserved so the operator can retry reconstruction without re-running the children on hardware.

### 5.3 Cancel

```
DELETE /api/cutting/batches/{batch_id}
  ▼
CuttingBatchService.cancel
  │  For each cid in doc.child_job_ids:
  │      JobService.cancel_job(doc.project_id, cid)
  │  status = "cancelled"
```

---

## 6. The MATLAB front-end — three modes

`CircuitCuttingViewModel` (`src/presentation/viewmodels/CircuitCuttingViewModel.m`) is the orchestrator. The Circuit Cutting screen has a Mode dropdown with three options:

| Mode | Backend Assignments rows | What gets sent to server |
|---|---|---|
| **Automatic** | Locked label rows with `(auto)` tag; pre-filled via the smallest-fit preview. | `backend_assignments=[]` → server calls `select_backends` |
| **Assisted** | Editable `uidropdown` + numeric shots field per row. Pre-filled with smallest-fit. | What the user has in the rows |
| **Manual** | Editable per-row, pre-filled with smallest-fit. | What the user has in the rows |

`onModeChanged` re-renders the rows so the locked/editable state follows the dropdown immediately.

### 6.1 Pre-flight width validation

In Assisted/Manual modes, `validateAssignmentWidths()` runs at click-time before the POST. If any subcircuit's width exceeds the picked backend's qubit count, Run is blocked with a clear error pointing at the offending row — catches the same class of error IBM would otherwise raise as `CircuitTooWideForTarget` after the round-trip.

### 6.2 Sub-experiment vs partition subcircuit

A subtle but critical detail: each partition's *partition_subcircuit* is QPD-decorated (contains `qpd_2q` / `cut_wire` instructions IBM hardware can't run). Only `subexperiments_by_label[label]` is hardware-ready. The MATLAB client doesn't see this distinction — it sends the cut plan, the server's dispatch path picks the right list.

### 6.3 The `cut_plan` round-trip — what NOT to echo back

`CircuitCuttingViewModel.sanitizeCutPlan` strips two server-generated descriptive fields (`feasibility_reason`, `feasible`) before POSTing. The dispatch path never reads them; echoing them back used to round-trip through MATLAB's `jsonencode` and produced non-UTF-8 bytes for em-dashes, triggering an HTTP 400 from FastAPI's body parser. The single-line UTF-8 fix in `FastAPIClient.postAuthJson` (`unicode2native(..., 'UTF-8')` instead of `uint8(...)`) eliminated the underlying byte-cast issue, but the strip stays as defence in depth.

---

## 7. Where the data flows — the full diagram

```
                        operator picks circuit + Mode + (optional) target_k
                                                │
                                                ▼
              ┌─────────────────────────────────────────────────────┐
              │ POST /api/cutting/analyze                           │
              │   CuttingService.analyze_cuts                       │
              │   • Smart target_k default if needed                │
              │   • Recommendation: cut or skip?                    │
              │   • GenericPipeline.analyze_cuts                    │
              │     → cut_plan + _partition_labels                  │
              └─────────────────────────────────────────────────────┘
                                                │
                                cutting_recommended=False?
                                                │
                          ┌─────────────────────┴────────────────────┐
                          ▼                                          ▼
                  modal: Submit Directly                operator clicks Run
                          │                                          │
                  navigate to Backends                ┌──────────────┴──────────────┐
                  with backend pre-set                │                             │
                                                      ▼                             │
           ┌────────────────────────────────────────────────────────┐               │
           │ POST /api/circuits/{cid}/cutting/batches               │               │
           │   CuttingBatchService.create_batch + dispatch          │               │
           │   • plan_execution → subexperiments_by_label           │               │
           │   • select_backends (size-aware, distinct-first)       │               │
           │   • k × JobService.submit_cutting_subcircuit           │               │
           │     → k IBM jobs in parallel, one per partition label  │               │
           └────────────────────────────────────────────────────────┘               │
                                                │                                   │
                                            HTTP 202 batch_id                       │
                                                │                                   │
                                                ▼                                   │
                               ┌──────────────────────────────────────┐             │
                               │ Client polls every 3s:               │             │
                               │ GET /api/cutting/batches/{id}        │             │
                               │   poll_batch → mean child progress   │             │
                               └──────────────────────────────────────┘             │
                                                │                                   │
                                       all children terminal                        │
                                                │                                   │
                                                ▼                                   │
                                  _reconstruct_and_complete                         │
                                                │                                   │
                                                ▼                                   │
                                       status="completed"                           │
                                                │                                   │
                                                ▼                                   │
                       ┌────────────────────────────────────────────┐               │
                       │ GET /api/cutting/batches/{id}/result       │               │
                       │   {expectations: [{observable, value,      │               │
                       │                    std_err, status}, …]}   │               │
                       └────────────────────────────────────────────┘               │
                                                │                                   │
                              Results screen Cutting Batches table ◄────────────────┘
                                  + View Reconstruction button
```

---

## 8. Failure modes and what produces what

| Symptom | Where to look |
|---|---|
| HTTP 400 "There was an error parsing the body" on POST `/cutting/batches` | UTF-8 round-trip — `FastAPIClient.postAuthJson` now uses `unicode2native(...)`. If it returns, check `sanitizeCutPlan` is still stripping `feasibility_reason`. |
| HTTP 502 "IBM job submission failed: 'Number of qubits (X) is greater than maximum (Y)'" | A subcircuit was wider than the chosen backend. Mode=Assisted/Manual: `validateAssignmentWidths` should catch this client-side. Mode=Automatic: `select_backends` should raise `ValueError` with a clear message *before* submission. |
| Sampling overhead `1e+308` / `Infinity` | Addon `gamma_UB` overflowed float64. `analyze_cuts` returned a fallback plan with `_addon_overflowed=True`. `plan_execution` will refuse to dispatch this. The operator needs a domain-specific preset (Phase 2) or manual pre-cutting. |
| Batch stuck at `executing 0%` despite IBM jobs completing | `_get_child` was returning `{status:"unknown"}` for all children. Fixed — now passes `project_id` through to `JobService.get_job_status`. |
| Results screen Cutting Batches table empty | Either the parfeval worker can't load the closure (capture-app bug — fixed), or `list_batches` returned an empty list, or one batch doc failed `BatchResponse` validation. The list endpoint now skip-and-logs per-doc rather than 500ing the whole response. |
| QMC report HTTP 400 | Same UTF-8 root cause as the cutting one — fixed by `unicode2native`. |
| MATLAB error `'matlab.ui.control.WebComponent' contains a parse error` | A parfeval closure captured the entire `app` object, dragging uihtml class definitions into a worker process that can't load them. Fix: capture `app.SomeSvc` to a local variable BEFORE the closure (see `loadCuttingBatches`). |

---

## 9. Quick-reference file map

| Concern | File |
|---|---|
| Pipeline stages (analyze, plan_execution, select_backends, reconstruct) | `sqk-qtau/src/qdash/api/services/cutting/base.py` |
| Preset registry & domain-specific overrides | `sqk-qtau/src/qdash/api/services/cutting/presets.py` |
| Smart-analyze recommendation + smart target_k | `sqk-qtau/src/qdash/api/services/cutting_service.py` |
| Batch lifecycle (create, dispatch, poll, reconstruct, cancel) | `sqk-qtau/src/qdash/api/services/cutting_batch_service.py` |
| HTTP routes (`/api/cutting/*` + circuit-nested batches) | `sqk-qtau/src/qdash/api/routers/cutting.py` |
| Pydantic schemas (`CutPlan`, `BatchResponse`, etc.) | `sqk-qtau/src/qdash/api/schemas/cutting.py` |
| Backend pool resolver (names + widths) | `sqk-qtau/src/qdash/api/services/ibm_runtime.py` (`get_configured_backends_with_widths`) |
| MATLAB orchestrator | `sqk-qtau-matlab/src/presentation/viewmodels/CircuitCuttingViewModel.m` |
| MATLAB HTTP client | `sqk-qtau-matlab/src/domain/services/CuttingService.m` |
| MATLAB screen builder | `sqk-qtau-matlab/src/presentation/screens/CircuitCuttingScreen.m` |
| MATLAB Results integration | `sqk-qtau-matlab/src/presentation/viewmodels/ResultsViewModel.m` (Cutting Batches table) |

---

## 10. Glossary

| Term | Meaning |
|---|---|
| **k** | Number of subcircuits the cutter produced. Not the same as `target_k` — `find_cuts` size-constrains rather than partition-counts, so a `target_k=4` request might still produce `k=3` if connectivity allows. |
| **target_k** | Operator's preferred subcircuit count (input). |
| **Partition** | One subcircuit produced by `partition_problem`. Identified by a label like `s0`, `s1`. |
| **Sub-experiment** | One concrete measure-and-prepare circuit produced by `generate_cutting_experiments` for a partition. A partition typically has 6^(cuts_in_partition) sub-experiments. |
| **Cut role** | The string stamped on each child IBM job (`label=s0`) so reconstruction can group results by partition. |
| **QPD** | Quasi-probability decomposition — the technique that lets `qiskit-addon-cutting` re-stitch sub-experiment results into the original expectation value. The `coefficients` are the QPD weights. |
| **γ (gamma) / sampling_overhead** | Multiplier on the shot budget needed to recover signal at the same precision. Grows ~4^k. The 1e+06 ceiling is enforced as `feasible=False`. |
| **Distinct-first** | The `select_backends` policy of preferring an unused backend over re-using one — maximises real fleet parallelism. |
| **Fallback partition** | Plan emitted when `find_cuts` overflows float64 internally. Structural decomposition only; `feasible=False`, `_addon_overflowed=True`. Cannot be executed. |
