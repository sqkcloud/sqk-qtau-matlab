# Error Mitigation — Deep Dive (Architecture + Formulas)

**Audience:** developers who need to understand *exactly* how Quantum Error Mitigation (QEM) works in QDash — the math, the constants, the ZNE noise factors, the extrapolators, and which layer each piece actually runs in.

**Scope note — read this first.** QDash is split across two repos:

| Repo | Role | What lives here |
|---|---|---|
| `sqk-qtau-matlab` (this repo) | **Front-end** | HTTP wrappers, UI heuristics, chart rendering. **No quantum math.** |
| `sqk-qtau` (backend, Python pkg `qtau`) | **Back-end** | The real mitigation math: level resolution, ZNE folding, extrapolators, cost model. |

So when this document gives a *formula*, it almost always lives in the **backend**. The MATLAB side either (a) POSTs parameters and renders the JSON that comes back, or (b) applies its own *UI-only* heuristics (color grading, planner fidelity factors) that are explicitly labelled as heuristics in the code.

All backend citations are `file:line` in `sqk-qtau/src/qtau/api/…`. Every formula below was verified against source on 2026-05-27 — where the source contradicts the older operator doc (`doc/Quantum Error Mitigation.md`), the contradiction is flagged with ⚠️.

---

## 1. The mental model — a numbered ladder

QEM exposes a single knob: an integer **level** from 0 to 3, plus −1 for Custom.

| Level | Name | Techniques enabled | Wall-clock cost factor |
|:---:|---|---|:---:|
| **0** | Raw | none (bare primitive) | 1.0× |
| **1** | Standard | gate twirling + measure twirling (TREX) + dynamical decoupling (XpXm) | 1.05× |
| **2** | Aggressive | Standard **+ ZNE** (3 noise factors, exponential fit) | 3.0× |
| **3** | TEM | *intended:* tensor-network EM. **Currently downgrades to Standard** + a note. | 5.0× (preview only) |
| **−1** | Custom | Standard baseline + per-technique overrides | varies |

The cost factors are the wall-clock multipliers from the cost model (§5), not shot multipliers — see the ⚠️ in §5.

---

## 2. Architecture — where each piece runs

```
┌─────────────────────────── sqk-qtau-matlab (front-end) ───────────────────────────┐
│                                                                                    │
│  MitigationService.m            ── thin HTTP wrapper ──┐                            │
│    .listLevels(token)   GET  /api/mitigation/levels    │                            │
│    .estimate(body,tok)  POST /api/mitigation/estimate  │                            │
│                                                        │                            │
│  MitigationCompareViewModel.m   ── N parallel estimate calls, one per chip ──┐      │
│    gradeColor / recommendation / card rendering        │                     │      │
│                                                        │                     │      │
│  AnalysisViewModel.m (QMC + EM dialog)                 │   renders            │      │
│    parseZneFactors, currentEmOptions, biasReduction    │   mitigation_curve   │      │
│                                                        │                     │      │
│  RunPlannerService.m            ── UI-only fidelity heuristic ──┐             │      │
│    mitigationFactorTable / Pareto frontier / pickOptimal        │             │      │
└──────────────────────────────────┼─────────────────────────────┼─────────────┼─────┘
                                    │ HTTP (Bearer)               │             │
┌──────────────────────────────────▼─────────────────────────────▼─────────────▼─────┐
│                          sqk-qtau (backend, pkg `qtau`)                              │
│                                                                                      │
│   routers/mitigation.py        /levels  +  /estimate                                 │
│   services/mitigation_service.py                                                     │
│       resolve(...)            → MitigationPlan        (frozen dataclass)              │
│       estimate_cost(plan)     → CostEstimate         (frozen dataclass)              │
│       fold_circuit_global()   → ZNE noise scaling     (see §6)  ⚠️ not in submit path │
│       extrapolate_zne()       → 4 extrapolators       (see §7)  ⚠️ not in submit path │
│       apply_to_executor()     → ZNE wrapper           (see §8)  ⚠️ not in submit path │
│   services/job_service.py      level constants, shot floors, _build_sampler_v2_options│
└──────────────────────────────────────────────────────────────────────────────────┘
```

**The single most important fact in this document:** the ZNE folding + extrapolation code (`fold_circuit_global`, `extrapolate_zne`, `apply_to_executor`) is **not wired into the production submit path**. The three real call sites — `job_service.py` (`submit_job`, `submit_cutting_subcircuit`) and `qae_service.py` (`_run_runtime`) — only call `resolve()` and `build_sampler_options()`. They never call the folding/extrapolation helpers. (Confirmed against source; the helpers' own docstrings describe them as Phase-3 "no-op today" primitives.)

What actually ships at level 2 today is therefore: **twirling + DD + the larger shot floor**, plus the `zne_enable=true` flag and `zne_noise_factors` recorded in the plan snapshot for provenance. Any expectation-value un-biasing via folding is **not yet executed server-side**. The QMC popup's ZNE curve is a *separate* visualization fed by a `mitigation_curve` the backend QMC pipeline produces independently (§9).

---

## 3. The two dataclasses (backend)

`MitigationPlan` (frozen) — `mitigation_service.py:107-150`:

```python
@dataclass(frozen=True)
class MitigationPlan:
    level: int                         # -1, 0, 1, 2, 3
    name: str                          # raw | standard | aggressive | tem | custom
    primitive: str                     # "sampler" | "estimator"
    backend_name: str
    twirling_gates: bool
    twirling_measure: bool
    dd_enable: bool
    dd_sequence: str                   # "XpXm" | "XY4" | "XY8" | ""
    zne_enable: bool
    zne_noise_factors: tuple[float, ...]
    zne_extrapolator: str              # "linear"|"polynomial"|"richardson"|"exponential"
    tem_enable: bool
    effective_shots: int
    conflicts: tuple[str, ...] = ()    # Heron r2 fractional-gate notes etc.
    notes: tuple[str, ...] = ()
    resolved_at: str = ""              # ISO-8601 UTC
    resolver_version: str = "phase-2.1"
```

`CostEstimate` (frozen) — `mitigation_service.py:153-167`:

```python
@dataclass(frozen=True)
class CostEstimate:
    effective_shots: int
    est_wall_seconds: float
    est_iqp_units: float | None
    shot_multiplier: float
    wall_multiplier: float
    notes: tuple[str, ...] = ()
```

`to_snapshot()` flattens the tuple fields to lists for Mongo/JSON. The snapshot is persisted on `IBMJobDocument`, `CuttingBatchDocument`, and `QaeJobDocument`.

---

## 4. `resolve()` — how a level becomes a set of flags

Constants (`job_service.py:62-87`, `mitigation_service.py:54-72`):

```
RAW=0  STANDARD=1  AGGRESSIVE=2  TEM=3  CUSTOM=-1
MITIGATION_LEVEL_DEFAULT       = STANDARD (1)
_AGGRESSIVE_SHOT_FLOOR         = 16384
_CUTTING_QPD_THRESHOLD         = 50
_CUTTING_QPD_SHOT_FLOOR        = 16384
_DEFAULT_ZNE_NOISE_FACTORS     = (1.0, 3.0, 5.0)
_DEFAULT_ZNE_EXTRAPOLATOR      = "exponential"
_WALL_MULTIPLIER_BY_LEVEL      = {0:1.0, 1:1.05, 2:3.0, 3:5.0}
_DEFAULT_SECONDS_PER_SHOT      = 1.0e-4
```

**Level canonicalization** (`mitigation_service.py:234-262`):
- `level is None` and a `custom` dict was supplied → Custom (−1).
- `level is None` → Standard (1).
- `level < 0` → Custom if a `custom` dict is present, else Standard.
- **TEM (3) downgrades** to an `effective_for_options = STANDARD` for option-building and appends a "TEM not yet implemented" note. `tem_enable` is still set `True` on the plan when the requested level was 3.
- Custom also builds off the Standard baseline, then applies per-key overrides.

**Per-technique flags** are pure threshold comparisons against `effective_for_options` (`:265-269`):

```python
twirling_gates   = effective_for_options >= STANDARD   # ≥1
twirling_measure = effective_for_options >= STANDARD
dd_enable        = effective_for_options >= STANDARD
dd_sequence      = "XpXm" if dd_enable else ""
zne_enable       = effective_for_options >= AGGRESSIVE  # ≥2
```

So the technique matrix is:

| Level (effective) | twirl_gates | twirl_measure | dd (XpXm) | zne_enable |
|:---:|:---:|:---:|:---:|:---:|
| 0 Raw | ✗ | ✗ | ✗ | ✗ |
| 1 Standard | ✓ | ✓ | ✓ | ✗ |
| 2 Aggressive | ✓ | ✓ | ✓ | ✓ |
| 3 TEM → Standard | ✓ | ✓ | ✓ | ✗ |
| −1 Custom (baseline 1) | ✓* | ✓* | ✓* | ✗* |

\* Custom values start from the Standard baseline and are then overridden per supplied key.

**ZNE defaults** only populate when `zne_enable` is true (`:288-291`):

```python
zne_noise_factors = _DEFAULT_ZNE_NOISE_FACTORS if zne_enable else ()   # (1.0, 3.0, 5.0)
zne_extrapolator  = _DEFAULT_ZNE_EXTRAPOLATOR if zne_enable else ""    # "exponential"
```

**Effective shots** (`:312-325`): the QPD floor applies first *only* when `cutting_overhead_qubits > 0`, then the level floor applies:

```python
shots_with_qpd = _cutting_qpd_shot_floor(base_shots, cutting_overhead_qubits) \
                 if cutting_overhead_qubits > 0 else int(base_shots or 0)
_opts, effective_shots = _build_sampler_v2_options(
    cutting_overhead_qubits, shots_with_qpd, mitigation_level=effective_for_options)
```

`_cutting_qpd_shot_floor` (`job_service.py:90-100`): `max(shots, 16384)` iff `n_qubits >= 50`, else passthrough.

`_build_sampler_v2_options` floor (`job_service.py:158-163`):
- `level ≤ RAW` → `(None, base_shots)` (no options object, no floor).
- `level ≥ AGGRESSIVE` → `target_shots = max(base_shots, 16384)`.
- **Standard (1) has no shot floor.**

⚠️ **Consequence:** because TEM and Custom resolve to `effective_for_options = STANDARD`, neither receives the aggressive 16384 shot floor, even though the cost preview shows TEM at a 5.0× wall multiplier.

---

## 5. The cost model — `estimate_cost(plan)`

`mitigation_service.py:460-516`. This is what fills the cost-preview line and the MitigationCompare cards.

```python
wall_mult = _WALL_MULTIPLIER_BY_LEVEL.get(plan.level, 1.0)   # {0:1.0,1:1.05,2:3.0,3:5.0}

if plan.level == CUSTOM:                          # custom recomputes wall_mult
    wall_mult = 1.0
    if twirling_gates or twirling_measure or dd_enable:
        wall_mult *= 1.05
    if zne_enable:
        wall_mult *= float(len(zne_noise_factors) or 3)

seconds_per_shot = _DEFAULT_SECONDS_PER_SHOT       # 1.0e-4, or backend cx gate_length floored at 1e-4

est_wall_seconds = effective_shots * seconds_per_shot * wall_mult
est_iqp_units    = est_wall_seconds / 60.0  if backend_name.startswith("ibm_") else None
baseline_shots   = max(int(effective_shots / max(wall_mult, 1.0)), 1)
shot_multiplier  = effective_shots / baseline_shots          # rounded to 2 dp on return
```

Formulas, stated plainly:

- **est_wall_seconds** = `effective_shots × seconds_per_shot × wall_mult`
- **est_iqp_units** = `est_wall_seconds / 60` (IBM backends only; else `null`)
- **shot_multiplier** = `effective_shots / max(1, ⌊effective_shots / wall_mult⌋)` — i.e. it is *derived from the wall multiplier*, not from the real shot floor.

⚠️ **Two honesty flags:**
1. The reported `shot_multiplier ≈ 3.0` for Aggressive is a wall-clock *proxy*. The real effective-shots bump at `base_shots = 4096` is `16384 / 4096 = 4×`, not 3×.
2. The `/estimate` endpoint passes `backend = None` (`mitigation.py:165`), so the cost preview always uses the `1e-4` baseline `seconds_per_shot` and never the live backend gate length. Heron r2 downgrade (§10) also never fires on the preview — only on real submits.

---

## 6. ZNE noise scaling — `fold_circuit_global`

`mitigation_service.py:634-681`. Global unitary folding: replace `U` with `U (U†U)^k`. The folded circuit is logically identical (so the *noiseless* expectation value is unchanged) but each gate is exposed to `noise_factor ×` the baseline noise.

```python
if noise_factor <= 1.0 + 1e-9:
    return circuit                           # nf = 1 → no folding
folds = int(round((noise_factor - 1.0) / 2.0))   # ← k
if folds <= 0:
    return circuit
folded = circuit.copy()
inv = circuit.inverse()
for _ in range(folds):
    folded.compose(inv, inplace=True)        # U†
    folded.compose(circuit, inplace=True)    # U
return folded
```

**Formula:** `k = round((noise_factor − 1) / 2)`, with `noise_factor = 1 + 2k`.

| noise_factor | k (folds) | gate count |
|:---:|:---:|:---:|
| 1.0 | 0 | 1× (passthrough) |
| 3.0 | 1 | 3× |
| 5.0 | 2 | 5× |

The default factor set `(1.0, 3.0, 5.0)` is exactly the `k = 0, 1, 2` sequence. The original circuit object is never mutated.

---

## 7. The extrapolators — `extrapolate_zne(values, noise_factors, extrapolator)`

`mitigation_service.py:684-792`. Given the measured observable at each noise factor `xᵢ`, extrapolate to the **zero-noise** value (`x = 0`). Guards: mismatched lengths raise `ValueError`; empty → `0.0`; single value → that value. `method = extrapolator.lower()`.

Let `x = noise_factors`, `y = values`. The four branches:

### 7.1 `"linear"` / `"polynomial"` (`:733-735`)
Degree-1 least-squares fit; return the intercept.

```
coeffs = np.polyfit(x, y, 1)        # [slope, intercept]
return coeffs[1]                    # value at x = 0
```
⚠️ `"polynomial"` is **identical to** `"linear"` — both are degree 1. There is no higher-degree polynomial branch.

### 7.2 `"richardson"` (`:737-755`)
Closed-form Lagrange-interpolation-at-zero. The zero-noise estimate is

```
ŷ₀ = Σᵢ yᵢ · ∏_{j≠i} (−xⱼ) / (xᵢ − xⱼ)
```

```python
for i in range(n):
    num, den = 1.0, 1.0
    for j in range(n):
        if j == i: continue
        num *= -x[j]
        den *= (x[i] - x[j])
    if abs(den) < 1e-12: raise ValueError(...)   # coincident factors
    result += y[i] * num / den
```
Exact for a polynomial noise model of degree `n−1`.

### 7.3 `"exponential"` (default for Aggressive) (`:757-778`)
Fit `y = a·exp(−b·t) + c` via `scipy.optimize.curve_fit`, then evaluate at `t = 0` (which gives `a + c`).

```python
def _model(t, a, b, c):
    return a * np.exp(-b * t) + c

p0 = (y[0] - y[-1], 1.0 / max(median(x), 1.0), y[-1])    # initial guess
popt, _ = curve_fit(_model, x, y, p0=p0, maxfev=2000)
a, b, c = popt
return a * exp(-b * 0.0) + c                              # = a + c
```
On fit failure → falls back to linear (`:777`). This is the IBM-Runtime default for moderately deep circuits because incoherent noise decays approximately exponentially.

### 7.4 Fallbacks
- Unknown `method` → linear (`:781-782`).
- Any outer exception → return the value at the *smallest* noise factor (`:783-792`).

---

## 8. `apply_to_executor(executor, plan)` — the ZNE wrapper

`mitigation_service.py:518-600`. Wraps an executor callable so that ZNE runs transparently. **No-op** when `not plan.zne_enable or not plan.zne_noise_factors` (returns the executor unchanged — true for levels 0/1, TEM, Custom-without-ZNE, and Heron r2 downgrades).

```python
def wrapped(circuit, *args, **kwargs):
    per_factor = [executor(fold_circuit_global(circuit, nf), *args, **kwargs)
                  for nf in plan.zne_noise_factors]

    if all numeric:                         # scalar expectation value
        return extrapolate_zne(per_factor, noise_factors, extrapolator)
    if all dict:                            # {pauli_string -> float}
        return {key: extrapolate_zne(series_for(key), …) for key in per_factor[0]}
    return per_factor[0]                    # unknown shape → 1.0× result, logged
```

The dict path is per-Pauli-string extrapolation (e.g. cutting reconstruction output). ⚠️ As noted in §2, `wrapped` is **never invoked by the production submit path** today.

---

## 9. The QMC popup's ZNE — a different layer entirely

The Quantum Monte Carlo dialog (Analysis screen) has its *own* mitigation dropdown — `{none, zne, pec}` (`DialogBuilder.m:662-664`) — independent of the 0–3 ladder. The MATLAB side here is **pure visualization**:

`AnalysisViewModel.m:2980-3019` reads `data.mitigation_curve` (a list of `{noise_factor, amplitude}` records produced by the backend QMC pipeline) and plots:
- noisy samples at `noise_factor > 0` (red squares),
- the extrapolated zero-noise estimate at `noise_factor == 0` (green star).

No folding, no curve fitting happens in MATLAB — it draws whatever points the backend returns. The dedicated **Error Mitigation** dialog (separate from QMC) collects advanced options client-side:

```matlab
% AnalysisViewModel.parseZneFactors — default if the field is unparseable
factors = [1.0 3.0 5.0];                              % :2317-2332

% AnalysisViewModel.currentEmOptions — snapshot of the advanced form  :2334-2349
opts.zne_noise_factors = parseZneFactors(EmZneFactorsField.Value)
opts.zne_extrapolator  = EmExtrapolatorDropdown.Value     % linear|exponential|richardson
opts.dd_sequence       = EmDdSequenceDropdown.Value
opts.twirling_gates / twirling_measure / tem_enable / also_run_raw
```

The client default factor set `[1 3 5]` matches the backend `(1.0, 3.0, 5.0)`.

---

## 10. Heron r2 fractional-gate handling (backend)

IBM Heron r2 (Marrakesh, Fez, Torino) supports continuous-angle 2q rotations, which are mutually exclusive with twirling and ZNE-PEA.

```python
_FRACTIONAL_GATE_NAMES = frozenset({"rzz", "rxx", "ryy", "rzx"})   # :101
```

`_backend_has_fractional_gates` (`:606-628`) intersects this set against `backend.target.operation_names`. When detected, `resolve()` (`:271-286`) forces `twirling_gates = False` and `zne_enable = False`, appending a conflict string to `plan.conflicts` (DD + measurement TREX stay active). The MATLAB UI renders `plan.conflicts` as an amber inline notice. Never fires on the cost preview (backend=None).

---

## 11. Client-side heuristics (MATLAB) — explicitly *not* physics

These live in the front-end and are labelled as heuristics in the source. They drive UI ranking only; they do not affect what runs on hardware.

### 11.1 RunPlanner mitigation-fidelity factor — `RunPlannerService.m`

`PredictionService.predict` takes no mitigation parameter, so the planner multiplies base predicted fidelity by a static factor (`:28-52`):

| level id | label | factor |
|:---:|---|:---:|
| 0 | None | 1.00 |
| 1 | Minimal | 1.05 |
| 2 | Standard | 1.15 |
| 3 | Aggressive | 1.30 |

```matlab
fidOut = min(FIDELITY_CAP, baseFidelity * factor);   % FIDELITY_CAP = 0.99
```

**Pareto frontier** (`:67-92`): sort candidate `(cost, fidelity)` points by cost ascending (fidelity descending as tie-break); keep any point whose fidelity strictly exceeds the best seen so far (`> bestFid + 1e-9`). **pickOptimal** (`:94-138`): cheapest frontier point with `fidelity ≥ target`; if none, fall back to the highest-fidelity finite point overall.

### 11.2 MitigationCompare shot-multiplier color grade — `MitigationCompareViewModel.gradeColor` (`:880-892`)

```matlab
mult ≤ 1.0          → green  [0.30 0.70 0.40]
1.0 < mult ≤ 5.0    → linear green→amber, t = (mult-1)/4
5.0 < mult ≤ 20.0   → linear amber→red,   t = (mult-5)/15
mult > 20.0         → red    [0.85 0.30 0.30]
```

The recommendation strip (`repaintRecommendation`, `:655-699`) picks: **cheapest** = min `shot_multiplier`; **best balance** = min multiplier among levels ≥ 1; **most aggressive** = max multiplier. It reads `cost.shot_multiplier / effective_shots / est_wall_seconds / est_iqp_units` straight from the `CostEstimate` JSON (`:586-589`).

### 11.3 EM dialog bias-reduction ranking — `AnalysisViewModel` (`:2270-2302`)

A separate UI heuristic used to recommend a level in the EM dialog:

```
biasReduction(level):  0→1.0   2→2.8   3→3.5   −1→2.5   (level 1 in between)
score = biasReduction / log(1 + max(shot_multiplier, 1.0))
```
`bestRecommendation` picks the max score. `mapEmTechniqueToBenchmark` (`:2304-2315`) maps level → BenchmarkScreen dropdown value (`0→none, 1→measurement_mitigation, 2/3→zero_noise_extrapolation, 4→readout_calibration`).

---

## 12. Persistence + provenance

The resolved `MitigationPlan.to_snapshot()` is written to three documents (all `dict | None`, default `None` so pre-Phase-2.2 records load without migration):

- `IBMJobDocument` — per-job snapshot; drives the Jobs table "Mitigation" column.
- `CuttingBatchDocument` — batch-level snapshot (per-child snapshots may differ on Heron r2).
- `QaeJobDocument` — QMC/QAE snapshot.

The MATLAB Results screen renders `zne_enable` and friends via `ResultsViewModel.boolBadge(mit, 'zne_enable')` (`:1060`). The Mitigated/Raw toggle appears only when `also_run_raw=true` spawned a level-0 sibling batch (see `doc/Quantum Error Mitigation.md §9` for the sibling machinery).

---

## 13. Formula quick-reference card

| Quantity | Formula | Source |
|---|---|---|
| Technique enable | `flag = effective_level >= threshold` (twirl/dd ≥1, zne ≥2) | `mitigation_service.py:265-269` |
| ZNE noise factors | `(1.0, 3.0, 5.0)` | `:71` |
| ZNE fold count | `k = round((nf − 1)/2)`, `nf = 1 + 2k` | `:634-681` |
| Linear/poly extrapolation | `polyfit(x, y, 1)` intercept | `:733-735` |
| Richardson extrapolation | `Σᵢ yᵢ ∏_{j≠i} (−xⱼ)/(xᵢ−xⱼ)` | `:737-755` |
| Exponential extrapolation | `y = a·e^(−b·t) + c`, return `a + c` | `:757-778` |
| Wall multiplier | `{0:1.0, 1:1.05, 2:3.0, 3:5.0}` | `:81-86` |
| est_wall_seconds | `effective_shots × 1e-4 × wall_mult` | `:489` |
| est_iqp_units | `est_wall_seconds / 60` (ibm_ only) | `:493-497` |
| shot_multiplier | `effective_shots / max(1, ⌊effective_shots/wall_mult⌋)` | `:500-501` |
| Aggressive shot floor | `max(base_shots, 16384)` | `job_service.py:158-163` |
| QPD shot floor | `max(shots, 16384)` iff `n ≥ 50` | `job_service.py:90-100` |
| Planner fidelity factor | `min(0.99, base × {1.00,1.05,1.15,1.30})` | `RunPlannerService.m:28-52` |
| Compare grade color | piecewise green→amber→red on shot_multiplier | `MitigationCompareViewModel.m:880-892` |

---

## 14. Known gaps / discrepancies (verified 2026-05-27)

1. ⚠️ **Server-side ZNE folding is dead code.** `fold_circuit_global` / `extrapolate_zne` / `apply_to_executor` are implemented and tested but **not invoked** by any production submit path. Level 2 today ships twirling + DD + a larger shot floor + the ZNE flags in the snapshot — not actual fold-and-extrapolate un-biasing.
2. ⚠️ **`shot_multiplier` is a wall-clock proxy**, derived from `wall_mult`, not the true shot ratio (which is 4× at base 4096, not 3×).
3. ⚠️ **TEM and Custom get no aggressive shot floor** — both resolve to `effective_for_options = STANDARD`.
4. ⚠️ **`"polynomial"` == `"linear"`** — both degree 1; no genuine higher-order polynomial extrapolator exists.
5. ⚠️ **Cost preview ignores the live backend** — `/estimate` passes `backend=None`, so `seconds_per_shot` is always `1e-4` and Heron r2 downgrade never appears in the preview.

---

## 15. Source map

| Concern | File |
|---|---|
| Level constants, shot floors, sampler options | `sqk-qtau/src/qtau/api/services/job_service.py` |
| resolve / cost / ZNE primitives / Heron r2 | `sqk-qtau/src/qtau/api/services/mitigation_service.py` |
| `/levels` + `/estimate` endpoints | `sqk-qtau/src/qtau/api/routers/mitigation.py` |
| MATLAB HTTP wrapper | `src/domain/services/MitigationService.m` |
| Compare planner (grading, recommendation) | `src/presentation/viewmodels/MitigationCompareViewModel.m` |
| Run planner fidelity heuristic | `src/domain/services/RunPlannerService.m` |
| EM/QMC dialog options + ZNE chart | `src/presentation/viewmodels/AnalysisViewModel.m`, `src/presentation/DialogBuilder.m` |
| Results mitigation badges + Raw toggle | `src/presentation/viewmodels/ResultsViewModel.m` |

**Related docs:** `doc/Quantum Error Mitigation.md` (operator flow + sibling machinery), `doc/Circuit_Cutting_Deep_Dive.md` (cutting math), `doc/superpowers/specs/2026-05-03-mitigation-service.md`.
