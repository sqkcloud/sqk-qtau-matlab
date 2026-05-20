# Cutting + ZNE Pipeline Integration — Design Spec

**Status:** Draft · **Date:** 2026-05-03 · **Repos touched:** `sqk-qtau` (backend), `sqk-qtau-matlab` (UI).

## Background

Phase 3.4 of the QEM rollout shipped working ZNE primitives — `fold_circuit_global` for noise scaling, `extrapolate_zne` for zero-noise extrapolation, and `MitigationService.apply_to_executor` as a Mitiq-style executor wrapper. These primitives work cleanly for any executor that returns scalar or per-Pauli expectation values directly.

The cutting reconstruction pipeline does **not** match that simple shape. It runs in three stages:

1. `partition_problem(circuit, labels)` → `k` partition subcircuits.
2. `generate_cutting_experiments(subcircuits, observables)` → ~6ᵏ measure-and-prepare subexperiments per partition + a global QPD coefficient list.
3. `reconstruct_expectation_values(per_label_results, coefficients, observables)` → final per-Pauli expectation values, computed by a quasi-probability-weighted sum over the entire subexperiment ensemble.

Naively wrapping the executor at the per-subexperiment level breaks the QPD bookkeeping: the coefficient list assumes one execution per subexperiment, not three. Naively wrapping at the reconstruction level requires re-running the entire pipeline three times (once per noise factor) **with consistent QPD samples** — which `generate_cutting_experiments` doesn't expose a hook for.

This spec describes the cleanest way to do it.

## The architectural insight

**Reuse the sibling_group_id machinery from Phase 3.2 (commit `49f3dbbb`).**

When `mitigation_level=2` is requested on a cutting submission, the server spawns **N siblings** — one per noise factor — instead of trying to fold inside the QPD generator:

- **Primary sibling** runs at noise_factor = 1.0 (= the original cutting batch flow, unchanged).
- **ZNE siblings** run at noise_factor ∈ {3.0, 5.0} (or whatever `MitigationPlan.zne_noise_factors` specifies), each with subcircuits pre-folded via `fold_circuit_global` **before** `generate_cutting_experiments` is called.

Each sibling:
- Runs its own dispatch / poll / reconstruction independently.
- Produces a complete `reconstruction.expectations` list with the same observable shape.
- Is bookkept identically to the primary — no special pipeline modifications.

A new **post-process extrapolation step** runs after all siblings reach `'completed'`:
- Pull each sibling's `reconstruction.expectations`.
- Per observable, gather (noise_factor, expectation_value) tuples across siblings.
- Call `extrapolate_zne(values, factors, plan.zne_extrapolator)`.
- Persist the extrapolated values on the **primary** batch's `reconstruction.zne_extrapolated.<observable>` field.

This works because `fold_circuit_global` produces a unitary-equivalent circuit at the elevated noise factor; the QPD decomposition is applied to the folded circuit; the resulting subexperiments are themselves at the elevated noise factor; reconstruction yields a noise-scaled expectation value; extrapolation across siblings recovers the zero-noise value.

The 3× wall-clock cost is the same as Mitiq's standard ZNE protocol. No QPD-coefficient hackery, no per-subexperiment indexing, no shared-state across siblings during execution.

## Why this beats the alternatives

| Approach | LOC estimate | Risk | Notes |
|---|---|---|---|
| **Per-subexperiment folding inside the QPD generator** | ~1500 | High | Requires forking `generate_cutting_experiments` to track noise factors through the coefficient list. One indexing bug silently corrupts every reconstruction. |
| **Run the whole reconstruction 3× with shared QPD samples** | ~800 | High | `generate_cutting_experiments` doesn't expose a "use these QPD draws" hook. Re-implementing the quasi-probability sampler is a research project. |
| **Sibling spawning + post-process extrapolation (this spec)** | ~500 | Low | Each sibling is a regular cutting batch. The extrapolation step is ~50 lines on top of the existing `extrapolate_zne` helper. |

## Schema additions

### `CuttingBatchDocument`

Add **one new optional field**:

```python
zne_noise_factor: float | None = Field(
    default=None,
    description=(
        "Noise factor applied to this batch's subcircuits before "
        "QPD decomposition. None for non-ZNE batches. The primary "
        "in a ZNE sibling group has zne_noise_factor=1.0; siblings "
        "carry 3.0, 5.0, etc."
    ),
)
```

### `IBMJobDocument`

Same field — propagated from the parent batch so the Jobs screen can render "ran at noise factor 3.0" alongside the existing mitigation badge:

```python
zne_noise_factor: float | None = Field(
    default=None,
    description="Noise factor of the parent ZNE sibling, when applicable.",
)
```

### `mitigation_role` enum extension

The Phase 3.2 `mitigation_role` field is already `str | None`. Extend the documented enum to include:

```
'primary'                — operator's chosen level, factor 1.0 (default)
'raw'                    — also_run_raw level-0 sibling, factor 1.0
'zne_factor'             — Phase 5: ZNE noise-factor sibling
                           (the actual factor lives in zne_noise_factor)
```

The role is documentation; the noise factor on `zne_noise_factor` is the source of truth.

### `reconstruction.zne_extrapolated`

The existing `CuttingBatchDocument.reconstruction` field is an unstructured `dict | None`. The post-process step adds a new key on the **primary** batch only:

```python
reconstruction["zne_extrapolated"] = {
    "<pauli_string>": <float>,  # zero-noise extrapolated value per observable
    ...
}
reconstruction["zne_metadata"] = {
    "noise_factors": [1.0, 3.0, 5.0],
    "extrapolator": "exponential",
    "siblings_completed": 3,           # may be < N if partial failure
    "siblings_total": 3,
    "extrapolated_at": "<ISO-8601>",
}
```

No new top-level field; reuses the existing flexible `reconstruction` dict.

### State machine additions

Existing batch states:
```
queued → partitioning → executing → reconstructing → completed
                                                   → failed
                                                   → cancelled
                                                   → partial_failure
```

ZNE-primary siblings get one new transition:
```
... → reconstructing → reconstructing_zne → completed
                                          → partial_zne_failure
```

`reconstructing_zne` fires only when `mitigation_role == 'primary'` and `sibling_group_id` is non-null and `zne_noise_factor` is non-null. A new background poller (or extension of the existing `lazy_poll_non_terminal`) checks "are all my ZNE siblings completed?" and runs the extrapolation when ready.

## Subcircuit folding strategy

Crucial decision: **fold the partition subcircuits before `generate_cutting_experiments`, not the original full circuit before `partition_problem`.**

Reasons:
1. Folding the partition subcircuits keeps the cut graph identical across siblings — same partition labels, same QPD coefficient structure. Reconstruction reads the same observable list per sibling.
2. Folding before `partition_problem` would change the connectivity graph that `find_cuts` uses, producing different cut structures across siblings. The siblings would be incomparable.

Implementation: in `CuttingPipeline.plan_execution()`, after `partition_problem` produces `subcircuits`, but before `generate_cutting_experiments`, apply:

```python
if zne_noise_factor and zne_noise_factor > 1.0:
    subcircuits = {
        label: fold_circuit_global(subc, zne_noise_factor)
        for label, subc in subcircuits.items()
    }
```

The transpiler is then invoked again per sibling backend (each subcircuit is folded → transpiled → submitted). The 3× wall-clock cost dominates; the extra transpile is negligible.

## Post-process extrapolation

A new method on `CuttingBatchService`:

```python
def reconstruct_zne_for_primary(self, primary_batch_id: str) -> None:
    """Run after all ZNE siblings of `primary_batch_id` complete.

    Fetches per-sibling reconstructions, extrapolates per observable,
    persists the result on primary.reconstruction.zne_extrapolated.

    Idempotent — safe to call multiple times. Tolerates partial
    failure: extrapolates with whichever siblings did complete (≥ 2).
    Records sibling status in zne_metadata.siblings_completed.
    """
```

Called from `_reconstruct_and_complete` for the primary, after the primary's own reconstruction finishes:

```python
def _reconstruct_and_complete(self, batch_id: str, ...) -> None:
    # ... existing reconstruction logic ...
    doc.status = "reconstructing"
    doc.save()
    # ... reconstruction runs ...
    doc.reconstruction = {...}

    # Phase 5 — ZNE extrapolation across siblings.
    if (
        doc.mitigation_role == "primary"
        and doc.sibling_group_id
        and doc.zne_noise_factor is not None
    ):
        doc.status = "reconstructing_zne"
        doc.save()
        # Are all ZNE siblings done?
        siblings = self.find_zne_siblings(doc.sibling_group_id)
        if all(s.status == "completed" for s in siblings):
            self.reconstruct_zne_for_primary(batch_id)
            doc.status = "completed"
        # Otherwise leave at reconstructing_zne; the lazy poller
        # checks again next cycle.

    doc.save()
```

The lazy poller (`lazy_poll_non_terminal` already exists for batch state advance) gets a new branch: when it sees a `reconstructing_zne` primary, check sibling completion and finalize when ready.

## Error handling

Three failure modes:

### 1. One sibling fails before reconstruction
- Primary's `zne_extrapolated` runs with the remaining 2 siblings (linear extrapolation).
- `zne_metadata.siblings_completed = 2`.
- Status = `'completed'` with a non-fatal warning in logs.

### 2. Two or three siblings fail
- Insufficient data for extrapolation. Fall back to the primary's own raw reconstruction.
- Primary status = `'partial_zne_failure'`.
- `zne_metadata.error = "Only 1 of 3 siblings completed; cannot extrapolate."`
- The primary's own `reconstruction.expectations` is still valid — operator gets the noise-factor=1.0 results without ZNE.

### 3. Extrapolation itself diverges (rare; numerical instability)
- `extrapolate_zne` already falls back to the smallest-factor value on any failure (Phase 3.4 contract).
- Primary continues to `'completed'` but with a warning entry in `zne_metadata.notes`.

## Behavior across `also_run_raw` × `mitigation_level=2`

When the operator submits with **both** `also_run_raw=true` AND `mitigation_level=2`, the spawned topology becomes:

```
sibling_group_id = G

Primary (zne_factor=1.0, role='primary',  level=2)  ──┐
Sibling (zne_factor=3.0, role='zne_factor', level=2)  ├── ZNE-extrapolate to factor=0
Sibling (zne_factor=5.0, role='zne_factor', level=2)  ──┘

Sibling (zne_factor=1.0, role='raw',       level=0)  ── independent: the Raw comparison batch
```

Total: 4 batches, all sharing the same `sibling_group_id`. The Results screen toggle (Phase 4.2) extends to show three view modes:

- **Mitigated (extrapolated)** — primary's `zne_extrapolated` field
- **Mitigated (factor 1.0 only)** — primary's `reconstruction.expectations`
- **Raw (level 0)** — raw sibling's reconstruction

Three buttons instead of two; same toggle component, just bigger. No other UI changes needed.

The extra cost (4× wall-clock instead of 2×) is documented in the cost preview line.

## Phased delivery

### Phase 5.A — Schema additions (1 day)
- `zne_noise_factor` on `CuttingBatchDocument` and `IBMJobDocument`.
- `mitigation_role` documentation extended to include `'zne_factor'`.
- New status `'reconstructing_zne'` and `'partial_zne_failure'`.
- No behavior change yet — just durable schema.

### Phase 5.B — Sibling spawning (2 days)
- Extend `CuttingBatchService.create_batch` to spawn N-1 ZNE siblings when `mitigation_level=2`.
- Each sibling carries pre-fold metadata (the noise factor) — actual folding happens in `plan_execution`.
- Extend `CuttingPipeline.plan_execution` to fold subcircuits when `zne_noise_factor` is set.
- Tests: end-to-end stub run produces 3 batches with correct `zne_noise_factor` values.

### Phase 5.C — Post-process extrapolation (2 days)
- `CuttingBatchService.find_zne_siblings(group_id)` helper (analog of Phase 3.5's `find_siblings`).
- `CuttingBatchService.reconstruct_zne_for_primary(batch_id)` — runs the cross-sibling extrapolation.
- Hook into `_reconstruct_and_complete` and `lazy_poll_non_terminal` so the primary advances `reconstructing_zne → completed` when siblings catch up.
- Tests: synthetic 3-sibling fixture with linear noise; verify `zne_extrapolated` recovers the zero-noise value within 1e-6.

### Phase 5.D — Results screen ZNE display (1 day, MATLAB)
- Extend the Phase 4.2 toggle from 2 → 3 buttons (Mitigated extrapolated / Mitigated raw / Raw level 0).
- New "ZNE curve" mini-chart in the Reconstruction dialog showing per-noise-factor values + the extrapolated point.
- Tooltip: "Extrapolated from {1.0, 3.0, 5.0} via exponential fit."

### Phase 5.E — Tests + observability (1 day)
- Unit tests for the post-process step at the service layer.
- Integration test: stub `Sampler.run` with synthetic linear-noise model; verify 3-sibling submission + reconstruction recovers the zero-noise value.
- Logger entries at each state transition so the Operator Activity log shows `reconstructing_zne` progress.

Total: ~7 days for the full feature, broken into 5 commits.

## Test strategy

**Unit-level (pure functions):**
- `fold_circuit_global` already tested in Phase 3.4. No change.
- `extrapolate_zne` already tested in Phase 3.4. No change.
- `find_zne_siblings(group_id)` — straightforward CuttingBatchDocument query.
- `reconstruct_zne_for_primary(primary_id)` — feed synthetic per-sibling reconstructions; verify extrapolation result matches `extrapolate_zne` direct call.

**Integration-level (stub Sampler):**
- Construct a 4-qubit cat state; cut into 2 subcircuits.
- Submit at `mitigation_level=2` against a stub Sampler that returns counts with synthetic linear noise (counts decay with circuit depth).
- Verify 3 sibling batches created with correct `zne_noise_factor`.
- Verify each batch's reconstruction completes.
- Verify `_reconstruct_and_complete` for the primary triggers ZNE extrapolation.
- Verify `reconstruction.zne_extrapolated` recovers the noiseless reference value within tolerance.

**End-to-end (real hardware, manual):**
- A 7-qubit GHZ circuit (small enough that the noiseless ZZ correlator is unambiguously +1).
- Submit at `mitigation_level=2 + also_run_raw=true`.
- Verify the Results screen shows all 4 toggle states with sensible numbers.

## Operational considerations

**Cost preview accuracy.** The Phase 2.3 `/api/mitigation/estimate` endpoint should return ~3× wall-clock for level=2; with `also_run_raw` it should add another ×4/3 for the raw sibling = ~4× total. Update `MitigationService.estimate_cost` to incorporate `mitigation_level=2` correctly per partition.

**Backend assignment.** Each sibling gets its own dispatch round. The existing backend-assignment logic runs per-batch — no special handling needed. If the operator's selected backend has 2 free slots, parallelism happens naturally.

**Partial failure UX.** When `partial_zne_failure` is the final state, the Results screen should:
- Show the primary's raw reconstruction (factor=1.0).
- Display a non-blocking notice: "ZNE extrapolation skipped — only N of 3 siblings completed. Showing raw expectations."
- Let the operator click "Retry ZNE" to re-run only the failed siblings (Phase 5.F polish).

**Observability.** Add log-event entries at each transition:
- `CONFIG: ZNE-spawning 2 siblings for batch <primary_id> (factors 3.0, 5.0)`
- `CUT: ZNE primary <primary_id> reached reconstructing_zne (waiting on siblings)`
- `CUT: ZNE extrapolation completed for <primary_id> (siblings=3/3, extrapolator=exponential)`

## Open questions

1. **Per-observable extrapolator.** Today the plan stores a single `zne_extrapolator` for all observables. Should the post-process step pick adaptively (e.g. linear when only 2 points; exponential when 3+; Richardson for {1, 2, 3, ...} grids)? **Proposed:** keep single extrapolator for Phase 5; revisit after operator feedback.

2. **Noise-factor grid customisation.** Currently `_DEFAULT_ZNE_NOISE_FACTORS = (1.0, 3.0, 5.0)` is hardcoded. Should operators be able to configure this on the Settings tab? **Proposed:** defer to Phase 6; the default is fine for early adopters.

3. **TEM (level 3) interaction.** Algorithmiq TEM is post-process tensor-network mitigation (no per-noise-factor sweep). When level 3 lands (Phase 4 of the broader rollout), it bypasses this ZNE pipeline entirely. **Proposed:** spec is correct; level 3 routes to a separate code path.

4. **Reconstruction-plan caching.** Each sibling re-runs `partition_problem` + `generate_cutting_experiments` independently. Could share the QPD coefficient list across siblings since they have identical observables and partition labels. **Proposed:** defer; optimization not correctness.

5. **Cancellation propagation.** If the operator cancels the primary mid-flight, should the ZNE siblings auto-cancel too? **Proposed:** yes — `cancel(primary_id)` cancels all siblings sharing `sibling_group_id`. Mirrors what `also_run_raw` should do for the raw sibling (currently doesn't — separate cleanup task).

## References

### Phase 3 work this spec builds on
- **Phase 3.2** (`49f3dbbb` sqk-qtau) — `sibling_group_id` + `mitigation_role` plumbing on `CuttingBatchDocument`.
- **Phase 3.4** (`30fc2bce` sqk-qtau) — `fold_circuit_global` + `extrapolate_zne` + `apply_to_executor` primitives.
- **Phase 3.5** (`d248f27e` sqk-qtau) — `GET /api/cutting/sibling/{group_id}` endpoint that the Phase 4.2 Results UI uses.
- **Phase 4.2** (`5ffaa78` sqk-qtau-matlab) — Results screen Mitigated/Raw toggle that Phase 5.D extends to 3 modes.

### Related QDash specs
- `2026-04-24-circuit-cutting-design.md` — the original cutting reconstruction architecture.
- `2026-05-03-mitigation-service.md` — the QEM ladder and MitigationService design.

### External references
- **Mitiq ZNE documentation** — [mitiq.readthedocs.io/en/stable/guide/zne-1-intro.html](https://mitiq.readthedocs.io/en/stable/guide/zne-1-intro.html). The `scale_noise=fold_global` + `extrapolate=Linear/Exp/Richardson` pattern this spec mirrors.
- **qiskit-addon-cutting docs** — `partition_problem`, `generate_cutting_experiments`, `reconstruct_expectation_values` API contracts that this design preserves untouched.
- **Filippov et al. 2023** (arXiv 2307.11740) — the "fold + extrapolate per observable" pattern is the same one TEM generalizes.
