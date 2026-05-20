# Mitigation Service — Phase 2 Design Spec

**Status:** Draft · **Date:** 2026-05-03 · **Repos touched:** `sqk-qtau` (backend), `sqk-qtau-matlab` (UI).

## Background

Quantum Error Mitigation (QEM) is the dominant noise-reduction tool in 2026. It cannot make quantum *states* less noisy — that's QEC's job and remains 5+ years away — but it can un-bias scalar expectation values from noisy hardware at the cost of more shots, more circuits, and more classical compute. Every production quantum cloud platform ships some form of QEM; QDash currently ships an inconsistent subset.

This spec defines the unified system that replaces today's scattered mitigation logic.

### Current state (after Phase 0 + Phase 1)

| Surface | Phase 0 | Phase 1 (commit `e0476158`) | Gap |
|---|---|---|---|
| Direct jobs | none | level 1 (twirling + DD + TREX) | no operator override |
| Circuit cutting | level 1 + 16384-shot floor at n≥50q (commit `a2049dcc`) | level 1 + dedicated QPD shot floor | no level 2 (Sampler-side ZNE) |
| QAE / QMC | ZNE-via-dropdown | level 1 + ZNE dropdown | profile registry; ZNE noise factors not configurable per submission |
| Benchmarks | none | not yet wired (intentional — benchmarks measure raw HW) | needs an explicit "Raw" profile and a "Mitigated benchmark" alternate |
| Detailed Analysis / heatmaps | n/a | n/a | no per-qubit mitigation efficacy heatmap |

What's missing: a **single authority** for translating "what the operator wants" into "what the primitives get configured with", plus the UX surface that lets the operator make that choice intelligently before submit and audit it after the run.

### Research grounding

Phase 1 was informed by four parallel research forks:

- **Mitiq 1.0** (Unitary Fund, March 2025) — exposes ZNE / PEC / CDR / DDD / LRE / REM / TREX / QSE / PT through an executor-callable abstraction. Composition is by nesting executors, not config flags. Layer order is not commutative (Pauli twirling must precede ZNE / PEC for the noise model to be valid).
- **Qiskit Runtime V2** — `SamplerV2.options` exposes only `twirling`, `dynamical_decoupling`, `execution`. There is no `resilience_level` on Sampler — that field lives on `EstimatorV2` only (RL0 = none, RL1 = TREX, RL2 = TREX + gate twirling + ZNE, RL3 removed). ZNE on Sampler workloads must therefore be done by wrapping the executor at the call site.
- **IBM Functions catalog** — `algorithmiq-tem` (Tensor-Network Error Mitigation) saturates the universal sampling lower bound and beats ZNE-PEA by 100–1000× at 100q+. Available as a managed-service call, not a primitive option.
- **Production platform UX** — IBM Composer, Braket, Azure Quantum, Quantinuum Nexus, IonQ, Pennylane, Classiq. Universal pattern: a single numbered ladder is the primary user knob; advanced overrides are an expander. Braket's "return raw + mitigated together" is the killer post-run UX feature; Classiq's pre-submit cost preview is the killer pre-submit feature.

### Hard constraints from the platform research

1. **Sampler V2 has no native ZNE.** ZNE for cutting reconstruction and QAE must wrap the executor at the call site (Mitiq pattern).
2. **Heron r2 fractional gates are mutually exclusive with PEC / ZNE-PEA / Pauli twirling.** Detect this combination and downgrade to a fractional-compatible profile.
3. **Twirling and DD are free.** Twirling splits the shot budget across `num_randomizations`; DD is pulse scheduling. Treat them as default-on at level ≥ 1, never as cost-bearing options.
4. **TEM is the new heavyweight.** PEC has retired above ~30q due to the γ wall. Level 3 should route to `algorithmiq-tem`, not PEC.
5. **Layer order matters.** When level ≥ 2 wraps an executor with ZNE, the inner level-1 stack (twirling) must be applied first or the noise model assumption breaks.

## Goal

Ship a `MitigationService` that:

1. Owns the translation from a numbered `mitigation_level` (or named profile) to concrete primitive options.
2. Detects backend-specific conflicts (fractional gates, deprecated DD sequences) and downgrades or warns.
3. Estimates pre-submit cost (effective shots, wall-clock seconds, IQP units) per submission.
4. Persists a `MitigationPlan` snapshot on every result document so post-hoc analysis can reproduce what was applied.
5. Supports the "return raw + mitigated together" pattern via dual-run plumbing.

## Non-goals

- Phase 2 does **not** ship custom user-defined profiles (CRUD on saved profiles). The numbered ladder + per-submission custom override covers ~95 % of operator value.
- Phase 2 does **not** ship the per-qubit mitigation-efficacy heatmap (research-grade; defer to Phase 4).
- Phase 2 does **not** ship M3 calibration cache (Phase 3); for Phase 2, M3 stays disabled and TREX is the readout-mitigation path.
- Phase 2 does **not** migrate cutting reconstruction to EstimatorV2. That migration is its own design exercise; Sampler-side ZNE (Phase 3) is the cheaper path and unblocks level 2 for cutting earlier.

## The numbered ladder

| Level | Name | Stack | When | Overhead |
|---|---|---|---|---|
| **0** | Raw | bare primitive | benchmarks, raw-noise reference | 1× |
| **1** | Standard | TREX + Pauli twirling + DD (XpXm; XY4 for long idles) | **default for every submission** | ~1× |
| **2** | Aggressive | Standard + ZNE (3 noise factors; exponential extrapolator) | expectation-value workloads with budget for 3× | ~3× |
| **3** | TEM | Standard + Algorithmiq TEM via IBM Functions | 100q+ utility-scale; Estimator-shape workloads | ~5–15× |
| **C** | Custom | operator-supplied options dict | research; PEC, mthree, layer-noise overrides | varies |

**Mapping to IBM Runtime:**

- Level 0 → `Sampler(mode=backend)` (no options).
- Level 1 → `Sampler(mode=backend, options=SamplerOptions(twirling=on, dynamical_decoupling=on))`. On EstimatorV2 paths: `Estimator(options=EstimatorOptions(resilience_level=1))`.
- Level 2 (Sampler) → wrap executor with Mitiq-style ZNE folding around level-1 Sampler. Level 2 (Estimator) → native `resilience_level=2`.
- Level 3 → call `quantum.cloud.ibm.com/functions/algorithmiq-tem` instead of the local primitive; consume the function's mitigated result.
- Level C → the request body's `mitigation_options` dict is splatted onto the primitive's options object after level resolution; conflicts logged + warned.

## API

### MitigationPlan dataclass

```python
@dataclass(frozen=True)
class MitigationPlan:
    level: int                     # 0..3, or -1 for Custom
    name: str                      # "raw"|"standard"|"aggressive"|"tem"|"custom"
    primitive: Literal["sampler","estimator"]
    backend_name: str

    # Resolved per-technique flags (read-only snapshot of what will run)
    twirling_gates: bool
    twirling_measure: bool
    dd_enable: bool
    dd_sequence: str               # "XpXm"|"XY4"|"XY8"|""
    zne_enable: bool
    zne_noise_factors: tuple[float, ...]
    zne_extrapolator: str          # "linear"|"exponential"|"polynomial"
    tem_enable: bool

    # Effective shot budget (after level + QPD floor + custom overrides)
    effective_shots: int

    # Pre-flight diagnostics
    conflicts: tuple[str, ...]     # e.g. ("Heron r2 fractional gates conflict with twirling — twirling disabled.",)
    notes: tuple[str, ...]
```

### MitigationService methods

```python
class MitigationService:
    def resolve(
        self,
        *,
        level: int | None = None,
        custom: dict | None = None,
        primitive: Literal["sampler","estimator"],
        backend: Backend,
        base_shots: int,
        cutting_overhead_qubits: int = 0,
    ) -> MitigationPlan: ...

    def apply_to_executor(
        self,
        executor: Callable[[Any, int], Any],
        plan: MitigationPlan,
    ) -> Callable[[Any, int], Any]:
        """Wrap a Sampler-shape executor with level-2/3 logic when
        primitive options can't express it natively (Sampler ZNE,
        TEM via IBM Functions)."""

    def build_sampler_options(self, plan: MitigationPlan) -> SamplerOptions | None: ...
    def build_estimator_options(self, plan: MitigationPlan) -> EstimatorOptions | None: ...

    def estimate_cost(
        self,
        plan: MitigationPlan,
        backend: Backend,
    ) -> CostEstimate: ...
```

### CostEstimate dataclass

```python
@dataclass(frozen=True)
class CostEstimate:
    effective_shots: int
    est_wall_seconds: float        # backend.queue + run estimate
    est_iqp_units: float | None    # IBM IQP billing (None for non-IBM)
    shot_multiplier: float         # vs level=0 baseline
    wall_multiplier: float
    notes: tuple[str, ...]
```

### Request body addition

Every submit endpoint that produces hardware execution gains the same field shape:

```json
{
  "mitigation_level": 1,
  "mitigation_options": null,
  "also_run_raw": false
}
```

- `mitigation_level: int = 1` — the ladder level. `0`–`3` map to named levels; `-1` ⇒ use `mitigation_options`.
- `mitigation_options: dict | None = null` — operator override (Custom level). Shape mirrors `MitigationPlan` field names.
- `also_run_raw: bool = false` — when true, the server submits a **second** sibling job at level 0 alongside the primary so the Results screen can render mitigated-vs-raw side-by-side.

The router applies sensible per-endpoint defaults (e.g. Benchmarks defaults to `mitigation_level=0`; Cutting / Jobs / QAE default to `mitigation_level=1`).

## Persistence

Every result document gains a `mitigation_plan` field holding the resolved `MitigationPlan` as a JSON snapshot. Field paths added to existing documents:

- `IBMJobDocument.mitigation_plan: MitigationPlanSnapshot`
- `CuttingBatchDocument.mitigation_plan: MitigationPlanSnapshot`
- `QaeJobDocument.mitigation_plan: MitigationPlanSnapshot`

A `MitigationPlanSnapshot` is a `dict` with the `MitigationPlan` field shape above, an ISO-8601 `resolved_at` timestamp, and the resolver's library-version stamp (`qiskit_ibm_runtime`, `mitiq` if used) so future-you can replay exactly what ran.

The snapshot is **the** source of truth for the Results-screen "what mitigation was applied?" panel and for any future mitigation-efficacy comparison work.

## Pre-submit cost preview

A new endpoint `POST /api/mitigation/estimate` accepts:

```json
{ "mitigation_level": 1,
  "mitigation_options": null,
  "primitive": "sampler",
  "backend_name": "ibm_marrakesh",
  "base_shots": 4096,
  "circuit_qubits": 130,
  "cutting_overhead_qubits": 130 }
```

…and returns a `CostEstimate` plus a human-readable summary string the UI renders below every submit dialog. Live-updates as the operator changes the level dropdown.

UI placement (MATLAB):

- **Jobs screen submit dialog** — one new line: `"Mitigation: Standard ▾   ~1× shots · est. 2m 15s"`.
- **Cutting screen** — same line below the Run / Cancel toolbar; hot-swaps as the operator changes level.
- **QMC popup** — extends the existing "Mitigation Strategy" dropdown to include the four ladder levels alongside ZNE / etc.

## Heron fractional-gate handling

The resolver checks the target backend's gate set at `resolve()` time. Heron r2 with fractional gates triggers the following downgrade table:

| Requested level | Effective level | Conflict note |
|---|---|---|
| 0 (Raw) | 0 | (none) |
| 1 (Standard) | 1 minus twirling | "Heron r2 fractional gates incompatible with Pauli twirling — twirling disabled. DD + TREX still active." |
| 2 (Aggressive) | 1 minus twirling | "Heron r2 fractional gates incompatible with ZNE-PEA. Falling back to DD + TREX. To enable ZNE, switch to a non-fractional backend." |
| 3 (TEM) | 3 (no change) | TEM operates at the post-processing layer, no primitive-level conflict. |
| C (Custom) | passes through; conflicts surfaced as `notes` | (none) |

The MATLAB UI renders `conflicts` as an amber inline notice next to the level dropdown — same pattern as the cutting `coherence_warning` we shipped today.

## Raw + mitigated dual-run

When `also_run_raw=true`, the server:

1. Resolves the operator's chosen plan (level ≥ 1).
2. Resolves a sibling level-0 plan with identical shots / backend / circuit.
3. Submits both as a parent batch (new `MitigationBatchDocument` analogue to `CuttingBatchDocument`).
4. Reconstruction / results rendering aligns the two by observable, computes the delta, and renders a toggle in the Results screen: **Mitigated** ⇄ **Raw**.

This is the killer feature for operator confidence in QEM: instead of "trust us, the mitigated number is closer to truth," the operator sees the raw number too and can judge the magnitude of the correction directly.

## Phased rollout

### Phase 2 (this spec) — 3–5 days
- `MitigationService` skeleton with `resolve()` + `build_sampler_options()` + `build_estimator_options()`.
- Numbered-ladder request-body field on Jobs / Cutting / QMC submit endpoints.
- Settings tab in MATLAB: pick system-wide default level per user.
- `mitigation_plan` snapshot persisted on result documents.
- Pre-submit `/api/mitigation/estimate` endpoint + UI line.
- Heron fractional-gate detection + downgrade.

### Phase 3 — 5 days
- Mitiq-style executor wrapping for level 2 on Sampler paths (Cutting + QAE).
- M3 calibration cache (mthree integration); per-backend, ~2-hour TTL, with a "force refresh" button in Settings.
- "Also run raw" checkbox; sibling-batch plumbing; Results screen toggle.

### Phase 4 — research-grade, on-demand
- Level 3 (Algorithmiq TEM via IBM Functions catalog).
- Per-qubit mitigation efficacy heatmap on Detailed Analysis.
- Custom mitigation options textbox for research users.
- Mitigation A/B comparison mode (operator picks two levels, batch runs both).
- Emulator-paired A/B (run on noisy emulator + real HW for divergence).

## Open questions

1. **Estimator vs Sampler for cutting.** qiskit-addon-cutting consumes Sampler results today. Estimator V2 has native ZNE, which would simplify level 2 for cutting. Migration is non-trivial — should it stay in Phase 4 or be elevated?

2. **Profile-system registry.** Phase 2 ships only the numbered ladder + per-submission Custom override. Should we ever add saved-profile CRUD? Counter-evidence: every production platform that ships QEM uses a numbered ladder, not profiles. Recommend deferring indefinitely unless a concrete user request arrives.

3. **TEM cost surfacing.** Algorithmiq TEM is billed separately from raw IBM IQP. The cost preview needs a separate line for IBM Functions billing.

4. **Default level per workload.** Today's plan defaults Cutting / Jobs / QAE to level 1 and Benchmarks to level 0. Should QMC default higher (level 2) given its expectation-value shape and existing ZNE expectation? Counter-argument: QMC already wires its own ZNE at the executor layer; doubling up via level 2 would waste shots.

5. **EstimatorV2 surface.** Today QDash has zero EstimatorV2 callers. If level-2 cutting requires Estimator (open Q1), this becomes a primary surface. Otherwise, EstimatorV2 only shows up if/when QDash adds a "Direct expectation value" submission shape.

## References

### Research forks (May 2026)

- **Mitiq library** — [mitiq.readthedocs.io](https://mitiq.readthedocs.io/en/stable/guide/guide.html), [v1.0.0 changelog](https://mitiq.readthedocs.io/en/stable/changelog.html)
- **IBM Qiskit Runtime V2 options** — [Configure error mitigation](https://docs.quantum.ibm.com/guides/configure-error-mitigation), [SamplerOptions](https://quantum.cloud.ibm.com/docs/en/api/qiskit-ibm-runtime/options-sampler-options-v2), [EstimatorOptions](https://quantum.cloud.ibm.com/docs/en/api/qiskit-ibm-runtime/options-estimator-options-v2)
- **IBM Functions catalog** — [Algorithmiq TEM](https://quantum.cloud.ibm.com/functions?id=algorithmiq-tem), [IBM Circuit Function](https://docs.quantum.ibm.com/guides/ibm-circuit-function)
- **QEM SOTA** — Filippov et al. *Scalable tensor-network error mitigation* (arXiv 2307.11740), Filippov et al. *QEM scalability: utility to advantage* (arXiv 2403.13542), Quek et al. *Exponentially tighter bounds on QEM* (arXiv 2210.11505), *EM for partially error-corrected computers* (arXiv 2510.10905, Oct 2025).
- **Production platform UX** — IBM Quantum Composer, [Braket error mitigation on IonQ Aria](https://docs.aws.amazon.com/braket/latest/developerguide/error-mitigation-ionq.html), [IonQ debiasing](https://docs.ionq.com/sdks/qiskit/error-mitigation-qiskit), [Quantinuum Qermit](https://github.com/Quantinuum/Qermit), [Classiq overview](https://quantumzeitgeist.com/classiq-quantum-computing-quantum-engineering/).

### Related QDash specs

- `2026-04-24-circuit-cutting-design.md` — circuit cutting + distributed reconstruction (Phase 0 of the QEM rollout overlapped with the cutting work that introduced the Phase-1 helper).

### QDash commits referenced

- `a2049dcc` — `feat(cutting): hardware-aware AUTOMATIC observables + Sampler V2 mitigation` (Phase 0).
- `e0476158` — `feat(mitigation): Phase 1 — universal mitigation-level Standard defaults`.
- `892c73e` (matlab) — `feat(cutting): surface server coherence_warning above Observables textarea`.
