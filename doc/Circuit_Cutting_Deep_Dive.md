# Circuit Cutting — Deep Dive (Architecture + Formulas)

**Audience:** developers who need to understand *exactly* how Circuit Cutting works in QDash — the QPD math, the sampling-overhead (γ) formula, `target_k` selection, the five pipeline stages, backend assignment, reconstruction, and which layer each piece runs in.

**Scope note.** Same two-repo split as the error-mitigation system:

| Repo | Role | What lives here |
|---|---|---|
| `sqk-qtau-matlab` (this repo) | **Front-end** | HTTP wrapper, 3-mode UI, width validation, result rendering. **No cutting math.** |
| `sqk-qtau` (backend, Python pkg `qtau`) | **Back-end** | The real cutting math via `qiskit-addon-cutting`: cut search, QPD expansion, reconstruction. |

All backend citations are `file:line` under `sqk-qtau/src/qtau/api/services/`. Every formula was verified against source on 2026-05-27. Discrepancies with the older doc (`doc/circuit_cutting_algorithm.md`) are flagged ⚠️.

---

## 1. Why cut at all

A QPU has fixed width (`ibm_marrakesh` 156q, `ibm_kingston` 156q, `ibm_miami` 127q). A circuit wider than the widest QPU cannot run. Circuit cutting splits it into subcircuits that each fit, runs them in parallel, and statistically re-stitches the result.

The catch: cutting is **never free**. Each cut multiplies the shot budget by the *sampling overhead* γ. Cutting a circuit that already fits is strictly worse than not cutting — the smart-analyze recommendation gate (§10) prevents that mistake.

---

## 2. The library — `qiskit-addon-cutting` 0.10.x

Four entry points carry the math:

| Function | Role | Pipeline stage |
|---|---|---|
| `find_cuts(circuit, OptimizationParameters, DeviceConstraints)` | search for cut locations; returns `(cut_circuit, metadata)` where `metadata["sampling_overhead"]` is γ | `analyze_cuts` |
| `partition_problem(circuit, partition_labels, observables)` | apply labels → `PartitionedCuttingProblem` with `.subcircuits`, `.subobservables`, `.bases` | `plan_execution` |
| `generate_cutting_experiments(circuits, observables, num_samples)` | expand QPD instructions into hardware-ready measure-and-prepare sub-experiments; returns `(subexperiments_by_label, coefficients)` | `plan_execution` |
| `reconstruct_expectation_values(results_by_label, coefficients, obs_by_label)` | QPD weighted sum back to expectation values | `reconstruct_expectations` |

The `coefficients` are **batch-global** — one per sub-experiment across all labels; `reconstruct_expectation_values` aligns them with each label's primitive result internally.

---

## 3. The sampling overhead γ — the key formula

This is the formula operators most often ask about, and the place the older doc was slightly wrong.

**Primary path** (`cutting/base.py:447-460`): γ is **read directly from the addon metadata**, *not* recomputed locally as `4^k`:

```python
overhead = float(metadata.get("sampling_overhead", 1.0))      # ← addon gamma_UB upper bound
...
"sampling_overhead":       overhead,
"sampling_overhead_log10": float(f"{_safe_log10(overhead):.3f}") if overhead > 0 else 0.0,
```

`_safe_log10` (`base.py:917-924`) = `math.log10(x)`, clamped to 0 for `x ≤ 0`.

The addon's `sampling_overhead` is the **product of per-cut γ factors** (its internal `gamma_UB` upper bound), which for the standard QPD basis is roughly `4^(number of cuts)` but is computed exactly by the addon — it is *not* a local power-of-4.

⚠️ **Discrepancy with `circuit_cutting_algorithm.md`:** that doc states γ ≈ `4^k`. That is true only as a rough docstring approximation (`base.py:378`) and as the *literal* formula in the **overflow fallback** (§8), where `big_overhead = 4 ** n_boundary`. On the normal path γ comes from the addon, so trust `metadata["sampling_overhead"]`, not `4^k`.

**Feasibility** (`base.py:393, 449`):

```python
MAX_OVERHEAD = 1.0e6
feasible = overhead <= MAX_OVERHEAD          # operator can override with feasibility_override=true
```

Beyond 1e6, reconstruction variance dominates any signal regardless of shot count.

---

## 4. `target_k` selection + subcircuit width

Two formulas, in two files:

**Smart `target_k` default** (`cutting_service.py:55-60`) — fires only when the caller didn't pin `target_k` *and* `n > widest`:

```python
if target_k is None and widest > 0 and n > widest:
    target_k = max(2, math.ceil(n / widest))
```

`widest` = max `num_qubits` across the configured IBM pool. So a 250q circuit on a 156q-widest fleet auto-picks `target_k = ⌈250/156⌉ = 2` (two ~125q halves, both fit).

**Subcircuit width** (`base.py:407-410`):

```python
if target_k and target_k > 1:
    qubits_per_qpu = max(1, ceil(n / target_k))   # -(-n // target_k)
else:
    qubits_per_qpu = max(1, n // 2 or 1)          # legacy default
```

⚠️ Note the *legacy* default (no `target_k`) is `n // 2`, which on a wide circuit would produce a catastrophic `target_k ≈ n/2` and γ in the `4^(n/2)` range. The smart default in `cutting_service.py` is what prevents this — it must run upstream of `analyze_cuts`.

---

## 5. The five pipeline stages

`CuttingPipeline` (abstract) → `GenericPipeline` (only concrete impl). Stages are **pure** — no Mongo I/O, no IBM Runtime calls (those live in `CuttingBatchService`, §7).

```
analyze_cuts → plan_execution → select_backends → reconstruct_expectations → post_process
```

### 5.1 `analyze_cuts(circuit, target_k)` (`base.py:395`)
1. **Prepare** the circuit — `_prepare_circuit_for_cutting = _decompose_to_1q_2q(_strip_measurements(circuit))`. The addon refuses classical bits or 3+ qubit gates. Decomposition uses `transpile(basis_gates=_CUTTING_BASIS_GATES, optimization_level=0)`, applied only when max gate arity > 2 (`base.py:144-158`):
   ```
   _CUTTING_BASIS_GATES = (u, u1, u2, u3, cx, rx, ry, rz, h, x, y, z,
                           s, sdg, t, tdg, sx, sxdg, id)
   ```
2. Compute `qubits_per_qpu` (§4).
3. `find_cuts(cut_circuit, OptimizationParameters(), DeviceConstraints(qubits_per_subcircuit=qubits_per_qpu))` → `(cut_circuit, metadata)`.
4. **Derive partition labels** from the cut circuit's connectivity graph (§6).
5. Compute γ + feasibility (§3).
6. Return the cut-plan dict: `cuts, k, target_k, sampling_overhead, sampling_overhead_log10, per_subcircuit_qubits, qubits_per_qpu, feasible, feasibility_reason`, plus a hidden `_partition_labels` cache.

### 5.2 `plan_execution` / `partition` (`base.py:554, 611-631`)
1. Re-prepare + re-`find_cuts` (cheap; labels reused).
2. Build a `PauliList` from `observables` (default: all-`Z` over the full width — `base.py:608`).
3. `partition_problem(cut_circuit, partition_labels, pauli_obs)` → `.subcircuits` (dict), `.subobservables` (dict).
4. `generate_cutting_experiments(subcircuits, subobservables, num_samples=DEFAULT_NUM_SAMPLES)` → `(subexperiments_by_label, coefficients)`.
   ```
   DEFAULT_NUM_SAMPLES = 1000          # base.py:385
   ```
5. Return the execution plan: `partition_subcircuits` (QPD-decorated, NOT runnable — for visualization), `subexperiments_by_label` (the actual hardware circuits), `coefficients`, `subobservables_by_label`, `label_order`.

⚠️ **Sub-experiments per partition** — the older doc says "6^cuts". That is **a docstring approximation only** (`cutting_batch_service.py:287`). The real count is whatever `generate_cutting_experiments(num_samples=1000)` returns, persisted as `subexperiments_count_by_label = {label: len(circuits)}`. No `6**cuts` formula exists in code.

### 5.3 `select_backends(subcircuits, pool, mode)` (`base.py:661`)
Width-aware greedy, **fit-decreasing + distinct-first**:

```python
order = sorted(indices, key=lambda i: subcircuits[i].num_qubits, reverse=True)
used = []
for i in order:                                  # widest subcircuit first
    fitting = [b for b in pool if b.num_qubits >= sub_width]
    if not fitting: raise ValueError("no backend wide enough")
    unused_fitting = [b for b in fitting if b.name not in used]
    if unused_fitting:
        chosen = min(unused_fitting, key=num_qubits)   # smallest unused fit
    else:
        smallest = min(b.num_qubits for b in fitting)
        tier     = [b for b in fitting if b.num_qubits == smallest]
        chosen   = tier[i % len(tier)]                 # round-robin within tier
    used.append(chosen.name)
    out[i] = {subcircuit_idx: i, backend_name: chosen.name, shots: 4096}
```

- **Fit-decreasing**: the widest subcircuit claims a wide backend before narrower siblings can hog it.
- **Smallest-unused-fitting**: leaves wide backends free for any wider sibling not yet placed.
- **Distinct-first**: maximises real fleet parallelism — a 3-cut batch goes to 3 different QPUs. Default `shots = 4096`. Falls back to plain round-robin when widths are unknown.

### 5.4 `reconstruct_expectations(subcircuit_results, observables, cut_plan)` (`base.py:772`)
Reads persisted `coefficients`, `label_order`, `subobservables_by_label`; calls `reconstruct_expectation_values(primitive_results_by_label, coefficients, obs_by_label)` (`base.py:895-899`). Returns one row per observable: `{observable, value, std_err, status}`.

⚠️ **`std_err` is never computed.** Successful reconstructions hardcode `"std_err": 0.0` (`base.py:900-907`); missing-data / no-coefficients / no-observables paths return `value = std_err = NaN` with `status = "unreconstructed"` (`base.py:810-816, 872-880`). Do not present the reported `std_err` as a real uncertainty.

### 5.5 `post_process(reconstruction, context)` (`base.py:364-366`)
Identity by default. Domain presets (`cutting/presets.py`) override for image/distribution outputs.

---

## 6. Partition-label derivation + singleton packing

`_labels_from_cut_circuit` (`base.py:1042-1091`): builds a networkx graph of the cut circuit, treating cut markers as non-edges:

```
_CUT_OP_NAMES = {qpd_2q, TwoQubitQPDGate, cut_wire, move, Move, barrier}
```

Each connected component (sorted by `min(qubit_index)`) becomes one label `s0, s1, …`.

`_pack_singletons` (`base.py:1154-1201`), invoked when `qubits_per_qpu > 1`: qubits with no 2-qubit gates after the cut would otherwise produce a degenerate `73 + 1 + 1 + 1 + …` partition (common in Bernstein-Vazirani oracle circuits). Packing: split into groups (size ≥ 2) and singletons; sort groups by size desc; greedily fill each up to `qubits_per_qpu`; leftover singletons become fresh chunks; re-sort by `min(qubit index)`. Safe because a singleton's action is identity, so reconstruction factorises through it cleanly.

---

## 7. Batch lifecycle — `CuttingBatchService`

Owns all Mongo + IBM Runtime I/O. The pipeline stays pure; side effects live here.

```
POST /api/circuits/{cid}/cutting/batches
   body = {mode, preset, cut_plan, backend_assignments, observables,
           mitigation_level, also_run_raw, …}
   │
   ▼ create_batch                         status = "queued"   (cutting_batch_service.py:207)
   │   • resolve MitigationPlan (see Error_Mitigation_Deep_Dive.md)
   │   • if also_run_raw: mint sibling_group_id + spawn a level-0 sibling batch ("queued")
   │
   ▼ dispatch                             status = "partitioning"  (:299)
   │   • plan = plan_execution(circuit, cut_plan, observables)
   │   • enrich cut_plan with coefficients + label_order + subobservables
   │   • if backend_assignments empty: assignments = select_backends(subs, live_pool, mode)
   │   • per label: JobService.submit_cutting_subcircuit(
   │         subcircuit=sub_experiments, cut_role="label=s0",
   │         cutting_overhead_qubits=n_eff)   ← one SamplerV2.run([...]) per label
   │                                          status = "executing" + submitted_at  (:384)
   ▼ HTTP 202 {batch_id}
```

### 7.1 Polling — `poll_batch` (`:393-426`)
```
GET /api/cutting/batches/{batch_id}        ← client every 3 s
   terminal = {completed, failed, cancelled, partial_failure}  → short-circuit
   progress = int(mean(child.progress_pct))
   all_done & no failures → _reconstruct_and_complete
   all_done & any failed  → status = "partial_failure", progress = 100
   otherwise              → persist progress_pct only
```

### 7.2 Reconstruction — `_reconstruct_and_complete` (`:751-816`)
```
status = "reconstructing"
group children by cut_role ("label=sN")
expectations = reconstruct_expectations(subcircuit_results, observables, cut_plan)
post         = post_process(reconstruction, context)
status = "completed"   (mark_completed)
on exception → persist raw subcircuit_measurements + mark_failed
              (operator can retry reconstruction without re-running hardware)
```

### 7.3 Cancel (`:430-443`)
Cancels each child via `JobService.cancel_job`, then `status = "cancelled"` + `completed_at`.

**State machine:** `queued → partitioning → executing → reconstructing → completed` (happy path); `executing → partial_failure`; reconstruction error → `failed`; any → `cancelled`.

---

## 8. QPD shot floor + overflow fallback

**QPD shot floor** — `_cutting_qpd_shot_floor` (`job_service.py:86-100`):

```python
_CUTTING_QPD_THRESHOLD  = 50
_CUTTING_QPD_SHOT_FLOOR = 16384

def _cutting_qpd_shot_floor(shots, n_qubits):
    return max(int(shots or 0), 16384) if n_qubits >= 50 else int(shots or 0)
```

This is the QPD variance-amplification floor: a subcircuit at `n ≥ 50` always runs ≥ 16384 shots, *independent of mitigation level* (a level-0 cutting submit still pays it). It is plumbed via `MitigationService.resolve(cutting_overhead_qubits=n_eff)`, and the aggressive level floor (also 16384) stacks on top through `_build_sampler_v2_options`. The per-subcircuit submit passes `cutting_overhead_qubits = transpiled_width` (`job_service.py:589-598`).

**Overflow fallback** — `_build_overflow_fallback_plan` (`base.py:482-539`):
- **Trigger** (`base.py:434-445`): `find_cuts` raises `OverflowError` when the addon's float64 `gamma_UB` overflows to inf (very wide / densely-entangling circuits like `qugan_n395`).
- **Behavior**: `_fallback_balanced_partition` (`base.py:1094-1151`) splits `[0..n-1]` into `k = ⌈n/qubits_per_qpu⌉` contiguous chunks (`base = n//k`, `extra = n%k`), counts cross-boundary multi-qubit gates as `n_boundary`, and sets `overhead = 4 ** n_boundary` (arbitrary-precision, clamped to `1e308`), `log10 = n_boundary · log10(4)`. The plan is flagged `feasible=False`, `_addon_overflowed=True`. `plan_execution` **refuses** such plans with a `ValueError` (`base.py:584-592`).

This is the **only** place the literal `4^k` appears in execution code.

---

## 9. The MATLAB front-end — three modes

`CircuitCuttingViewModel` is the orchestrator. The Mode dropdown:

| Mode | Backend-assignment rows | Sent to server |
|---|---|---|
| **Automatic** | locked `(auto)` rows, pre-filled smallest-fit preview | `backend_assignments = []` → server calls `select_backends` |
| **Assisted** | editable dropdown + shots per row | the user's rows |
| **Manual** | editable, pre-filled smallest-fit | the user's rows |

Client-side details:
- **`validateAssignmentWidths()`** runs at click-time in Assisted/Manual: blocks Run if any subcircuit width exceeds the picked backend, catching `CircuitTooWideForTarget` before the round-trip.
- **`sanitizeCutPlan()`** strips `feasibility_reason` + `feasible` before POSTing (defence-in-depth against a historical em-dash UTF-8 round-trip bug; `FastAPIClient.postAuthJson` now uses `unicode2native(..., 'UTF-8')`).
- **Sub-experiment vs partition subcircuit**: the QPD-decorated `partition_subcircuit` is not hardware-runnable; only `subexperiments_by_label` is. The client never sees this — it ships the cut plan and the server's dispatch picks the right list.
- **OversizeDetector** (`infrastructure/config/OversizeDetector.m`) flags circuits wider than the widest backend to surface the cut/skip recommendation.

The Results screen renders the Cutting Batches table + **View Reconstruction** button (disabled when batches are empty), which calls `GET /api/cutting/batches/{id}/result` and renders the `{observable, value, std_err, status}` expectations table. The Mitigated/Raw toggle appears when `sibling_group_id` is non-empty.

---

## 10. Smart-analyze recommendation gate

`CuttingService.analyze_cuts` (backend `cutting_service.py`) wraps the pipeline with a policy check:

```
n = circuit.num_qubits;  widest = max(pool widths)
if n <= widest:
    cutting_recommended = False
    direct_run_backend  = smallest fitting backend
    reason = "Circuit fits on … (Xq). Cutting would only add sampling overhead — submit directly."
```

The MATLAB UI surfaces this as a `uiconfirm` modal: **Submit Directly** (bridges to Backends with the backend pre-selected on `AppState.selectedBackend`), **Proceed with Cutting**, or **Cancel**.

---

## 11. Formula quick-reference card

| Quantity | Formula | Source |
|---|---|---|
| Sampling overhead γ | `metadata["sampling_overhead"]` (addon gamma_UB) | `base.py:447` |
| γ log scale | `log10(γ)`, clamped ≥ 0 | `base.py:917-924` |
| Feasibility | `γ ≤ MAX_OVERHEAD = 1e6` | `base.py:393, 449` |
| Smart target_k | `max(2, ⌈n / widest⌉)` (when n > widest) | `cutting_service.py:55-60` |
| Subcircuit width | `⌈n / target_k⌉`, else `n // 2` | `base.py:407-410` |
| QPD sub-experiments | `num_samples = 1000` (not 6^cuts) | `base.py:385` |
| Backend assignment shots | `4096` default | `base.py:661+` |
| QPD shot floor | `max(shots, 16384)` iff `n ≥ 50` | `job_service.py:86-100` |
| Overflow γ (fallback only) | `4 ** n_boundary`, clamp 1e308 | `base.py:506-511` |
| std_err | always `0.0` (or `NaN` if unreconstructed) | `base.py:900-907` |
| Batch progress | `int(mean(child.progress_pct))` | `cutting_batch_service.py:411` |

---

## 12. Known gaps / discrepancies (verified 2026-05-27)

1. ⚠️ **γ is the addon `gamma_UB`, not local `4^k`.** `4^k` is only a docstring approximation and the overflow-fallback formula. Trust `metadata["sampling_overhead"]`.
2. ⚠️ **"6^cuts sub-experiments per partition" is a docstring approximation only.** The real count is `len(generate_cutting_experiments(num_samples=1000))` per label.
3. ⚠️ **`std_err` is never computed** — hardcoded `0.0` on success, `NaN` on failure. Not a real uncertainty estimate.
4. The legacy `qubits_per_qpu = n // 2` default is dangerous on wide circuits; the smart `target_k` default in `cutting_service.py` must run upstream to avoid `4^(n/2)`-scale overhead.

---

## 13. Source map

| Concern | File |
|---|---|
| Pipeline stages (analyze, plan_execution, select_backends, reconstruct, post_process) | `sqk-qtau/src/qtau/api/services/cutting/base.py` |
| Domain presets | `sqk-qtau/src/qtau/api/services/cutting/presets.py` |
| Smart-analyze + smart target_k | `sqk-qtau/src/qtau/api/services/cutting_service.py` |
| Batch lifecycle (create/dispatch/poll/reconstruct/cancel) | `sqk-qtau/src/qtau/api/services/cutting_batch_service.py` |
| QPD shot floor + subcircuit submit | `sqk-qtau/src/qtau/api/services/job_service.py` |
| HTTP routes `/api/cutting/*` | `sqk-qtau/src/qtau/api/routers/cutting.py` |
| MATLAB HTTP wrapper | `src/domain/services/CuttingService.m` |
| MATLAB orchestrator (3 modes, width validation) | `src/presentation/viewmodels/CircuitCuttingViewModel.m` |
| MATLAB screen builder | `src/presentation/screens/CircuitCuttingScreen.m` |
| Oversize detection | `src/infrastructure/config/OversizeDetector.m` |
| Results reconstruction view | `src/presentation/viewmodels/ResultsViewModel.m` |

**Related docs:** `doc/circuit_cutting_algorithm.md` (original operator-facing algorithm doc), `doc/Error_Mitigation_Deep_Dive.md` (mitigation math, incl. the QPD/aggressive shot-floor interaction), `doc/superpowers/specs/2026-04-24-circuit-cutting-design.md`.
