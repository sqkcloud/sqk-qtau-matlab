# QTAU Connector Workbench — Master Reference

**Features · Formulas · Algorithms · Purpose**

**Version:** matches `resources/app.properties:app_version` (1.2.4)
**Platform:** MATLAB R2025b (App Designer / `uifigure`)
**Backend:** FastAPI "QTAU Connector" (default `http://localhost:5715`, fallback in `AppConfig`)
**Status:** consolidated reference — single source for *what every feature does, why it exists, and the exact math behind it*.

---

## How to read this document

This is the **one place** that answers three questions for every part of the app:

1. **What is it / what is it for?** — Part I (screens) and Part II (services).
2. **What is the formula or algorithm?** — Part III, every equation quoted verbatim from source with a `file:line` citation.
3. **Where do I go deeper?** — Part IV links the existing deep-dive docs.

**Conventions**

- Every formula is cited as `File.m:line` so it can be diffed against the implementation.
- A critical architectural fact: **most analytics math runs on the FastAPI backend, not in MATLAB.** MATLAB owns the math for the *client-side / offline* features only:
  - Fault-tolerant resource estimation (`ResourceEstimatorService`)
  - Cost-aware run planning / Pareto frontier (`RunPlannerService`)
  - QEC simulation engine (`QecEngineService`)
  - Local statevector simulation (`StatevectorSimulator`, `CircuitDiagram`)
  - QMC / ZNE / PEC chart rendering + the PEC γ̄ overhead (`AnalysisViewModel`)
- Everything else (fidelity prediction, benchmark scoring, mitigation cost, QAE engine, circuit feature extraction) is **backend-resident**; MATLAB marshals the request and renders the response. Those are flagged 🌐 and the backend field contract is in `doc/fastapi_contract.md` / `doc/openapi.json`.

---

# Part I — Feature & Screen Catalog

22 screens total: **17 visible in the sidebar**, **5 hidden** (reachable via in-app navigation). Routing keys, display labels, and icons are decoupled (see `NavigationManager.m`).

## Visible screens (sidebar)

| # | Routing key | Sidebar label | ViewModel | Purpose | Primary services |
|---|---|---|---|---|---|
| 1 | `Dashboard` | Dashboard | `DashboardViewModel` | Default landing. Workflow stepper, KPI strip, Run-Readiness, backend health, job-submission trend, merged activity feed. 30 s silent auto-refresh. | `ProjectService` |
| 2 | `Welcome` | **Projects** | `WelcomeViewModel` | Login, project selection, recent projects. Auto-navigates to Dashboard on login. | `AuthService`, `ProjectService` |
| 3 | `Circuits` | Circuits | `CircuitsViewModel` | Browse / search / paginate project circuits. Toolbar exposes Composer (✎) + Upload (↑). | `CircuitService` |
| 4 | `Analysis` | Analysis | `AnalysisViewModel` | Circuit feature extraction, QTAUBench similarity, **QMC popup** + **QEM popup**. | `CircuitService`, `QmcService`, `MitigationService`, `ReportService` |
| 5 | `Circuit Cutting` | Circuit Cutting | `CircuitCuttingViewModel` | Cut detection + distributed reconstruction (Automatic / Assisted / Manual). | `CuttingService`, `CircuitService`, `BackendService` |
| 6 | `Backends` | Backends | `BackendsViewModel` | Backend explorer + primary/backup selection. Telemetry tabs (Overview / Per-Qubit / History / Topology force-directed graph). | `BackendService` |
| 7 | `Benchmark` | Benchmark | `BenchmarkViewModel` | Execution params, mitigation strategy, cost preview. | `BenchmarkService`, `PredictionService`, `MitigationService` |
| 8 | `Prediction` | Prediction | `PredictionViewModel` | Predicted fidelity, distribution, error budget per backend. | `PredictionService` |
| 9 | `Mitigation Compare` | Mitigation Compare | `MitigationCompareViewModel` | Side-by-side mitigation cost / shot-multiplier / runtime / IQP-cost across chips. | `MitigationService` |
| 10 | `Resource Estimator` | Resource Estimator | `ResourceEstimatorViewModel` | **Fault-tolerant overhead planner** — surface-code distance, physical-per-logical, T-factory count, runtime. | `ResourceEstimatorService` ⚙ |
| 11 | `Run Planner` | Run Planner | `RunPlannerViewModel` | **Cost-aware run optimisation** — Pareto frontier over backend × mitigation, cheapest config hitting target fidelity. | `PredictionService`, `MitigationService`, `RunPlannerService` ⚙ |
| 12 | `Jobs` | Jobs | `JobsViewModel` | Job monitoring dashboard. 5 s auto-refresh while visible. | `JobService` |
| 13 | `Results` | Results | `ResultsViewModel` | Measured vs predicted vs ideal. Auto-picks first completed job. | `JobService`, `PredictionService` |
| 14 | `QEC Simulation` | QEC Simulation | `QecSimulationViewModel` | **Client-side QEC simulation** — 6 codes × 4 noise channels, logical fidelity. | `QecEngineService` ⚙ |
| 15 | `QEC Visualization` | QEC Visualization | `QecVisualizationViewModel` | 3D Bloch sphere, surface-code lattice, error propagation. | `QecEngineService` ⚙ |
| 16 | `Reports` | Reports | `ReportsViewModel` | Report generation / download / email / print (PDF / HTML / JSON). | `ReportService` |
| 17 | `Settings` | Settings | `SettingsViewModel` | Account, defaults, storage, notifications, IBM token verify. | `SettingsService`, `AuthService` |

⚙ = contains real client-side math (see Part III).

## Hidden screens (in app, not in sidebar)

| Routing key | ViewModel | Purpose | Entry point |
|---|---|---|---|
| `Composer` | `ComposerViewModel` | In-app circuit authoring: gate palette, wire canvas, bidirectional OpenQASM 2.0 mirror, 12-template gallery, Inspect footer (local statevector sim), multi-target code export, reproducibility bundle. | Circuits toolbar (✎) |
| `Upload` | `UploadViewModel` | Circuit upload, format detection, preview. | Circuits toolbar (↑) |
| `Detailed Analysis` | `DetailedAnalysisViewModel` | Heatmaps, drift, per-qubit metrics, cross-run comparison. | Analysis bridge / Detailed Analysis nav |
| `Benchmark Dashboard` | `BenchmarkDashboardViewModel` | Benchmark config summary + recommendations + regression. | Benchmark screen |
| `Notes` | `NotesViewModel` | Working notes / operator memos. Hidden; re-enable per CLAUDE.md. | (disabled in nav) |

---

# Part II — Service Catalog (18 services)

Three-layer clean architecture: **Screen → ViewModel → Service → FastAPIClient → HTTP**. Services have no UI. 🌐 = HTTP proxy (math is backend-side); ⚙ = local math (formulas in Part III).

| Service | Type | Purpose |
|---|:--:|---|
| `AuthService` | 🌐 | Login / logout / `me`. OAuth2-password → Bearer JWT. |
| `BackendService` | 🌐 | Backend listing, calibration, calibration history, topology. |
| `BackgroundTaskManager` | local | Registry for long-running async tasks (QMC, cutting, IBM jobs); progress + completion toasts. No analytics math. |
| `BenchmarkService` | 🌐 | Volumetric heatmap, system metrics (QV/CLOPS/Layer Fidelity/EPLG), scorecard, regression, classification, prediction calibration. |
| `BundleService` | local | Reproducibility-bundle assembler: circuit (QASM + Python ecosystems) + metadata + calibration + mitigation + FT estimate → ZIP with SHA-256 manifest. Packaging, not numerics. |
| `CircuitService` | 🌐 | Circuit upload (multipart), list, analyze, preview, QTAUBench match. |
| `CuttingService` | 🌐 | Cut analysis, presets, backend assignment, execution, reconstruction. |
| `JobService` | 🌐 | Job submission, polling, cancel, results, error trends. |
| `MitigationService` | 🌐 | Mitigation levels + cost estimate (shot-multiplier, IQP cost, runtime — backend-computed). |
| `PredictionService` | 🌐 | Fidelity prediction + transpilation optimization. |
| `ProjectService` | 🌐 | Project CRUD, dashboard, notes, activities. |
| `QecEngineService` | ⚙ | Client-side QEC simulation (density-matrix + Monte-Carlo). **All math local.** |
| `QmcService` | 🌐 | QMC/QAE async job submit / poll / cancel / IBM exec-log. |
| `ReportService` | 🌐 | Report generate / download / stream / email / print. |
| `ResourceEstimatorService` | ⚙ | FT resource estimation (surface-code). **All math local.** |
| `RunPlannerService` | ⚙ | Pareto frontier + optimal-run selection. **All math local.** |
| `SettingsService` | 🌐 | User preferences, IBM token verification. |
| `StatevectorSimulator` | ⚙ | Local statevector simulator (≤14 qubits) for Composer Inspect. **All math local.** |

---

# Part III — Formulas & Algorithms Compendium

Each subsection: **purpose → formula(s) verbatim → citation → notes.** Everything here is verified against current source.

## 3.1 Fault-Tolerant Resource Estimation — `ResourceEstimatorService` ⚙

**Purpose:** given a circuit + FT parameters (physical error rate `p`, target logical error rate `ε`, surface-code cycle time), compute surface-code distance, physical-qubit footprint, T-state budget, T-factory count, and wall-clock runtime. Powers the **Resource Estimator** screen and the FT section of the reproducibility bundle.

**Math sources** (cited in the file header `ResourceEstimatorService.m:9-17`): Fowler et al. PRA 2012 (surface codes); Bravyi & Kitaev (15-to-1 distillation); Selinger/Ross (Solovay-Kitaev).

### Constants — `ResourceEstimatorService.m:26-33`
```
SURFACE_THRESHOLD (p_th)      = 0.01
PREFACTOR                     = 0.03
T_GATES_PER_TOFFOLI           = 7
T_FACTORY_FOOTPRINT_FACTOR    = 16
D_MIN = 3,  D_MAX = 51
```
Default params — `:36-42`: `physErr = 1e-3`, `logErr = 1e-15`, `cycleSeconds = 1e-6`.

### Code distance (Fowler inverse) — `:122-126`
Logical error per cycle ≈ `0.03 · (p / p_th)^((d+1)/2)`. Inverting for `d`:
```matlab
ratio = log(logErr / PREFACTOR) / log(physErr / pTh);   % :122
dRaw  = 2 * ratio - 1;                                   % :123
d     = max(D_MIN, ceil(dRaw));                          % :124
if mod(d,2)==0; d = d+1; end                             % :125  enforce odd
d     = min(d, D_MAX);                                   % :126
```
Guard: if `p ≥ p_th` the code can't reduce error → `d = D_MAX` (`:116-121`).

### Physical qubits per logical (rotated planar code) — `:56`
```matlab
phl = 2 * d^2 + 1;
```

### T-state budget — `tStateBudget`, `:129-155`
Solovay-Kitaev per-rotation cost — `:140`:
```matlab
sk = max(1, ceil(3 * log2(1 / max(targetEps, 1e-30))));
```
Per-gate accumulation — `:141-153`: `t`/`tdg` → `tGates += 1`; `ccx` → `toffolis += 1`; non-Clifford `rx/ry/rz` → `nonCliffordRotations += 1`, `tGatesFromRotations += sk`.

Total T — `:58-60`:
```matlab
totalT = tGates + 7*toffolis + tGatesFromRotations;
```
Clifford-rotation test — `isCliffordRotation`, `:157-164` (θ is Clifford iff θ/(π/2) is integer within 1e-9):
```matlab
r  = theta / (pi/2);
tf = abs(r - round(r)) < 1e-9;
```

### T-factory footprint — `:61-69`
```matlab
if totalT > 0
    tFactories       = 1;
    factoryQubits    = 16 * phl;   % 16d² per active factory
    tFactoryOverhead = 10;
else
    tFactories = 0; factoryQubits = 0; tFactoryOverhead = 1;
end
```

### Qubit allocation — `:71-74`
```matlab
logicalQubits = max(1, model.NumQubits);
dataQubits    = logicalQubits * phl;
ancillaQubits = ceil(0.10 * dataQubits);            % 10% routing ancilla
totalPhysical = dataQubits + ancillaQubits + factoryQubits;
```

### Runtime — `:76-78`
```matlab
depth         = max(1, model.depth());
latticeCycles = depth * d * tFactoryOverhead;
totalSeconds  = latticeCycles * cycleSeconds;
```

## 3.2 Cost-Aware Run Planning — `RunPlannerService` ⚙

**Purpose:** answer *"give me fidelity F at minimum cost."* Cross-multiplies backends × mitigation strategies into (cost, fidelity) candidates, computes the Pareto frontier, recommends the cheapest config meeting the target. Powers the **Run Planner** screen. Base fidelity comes from `PredictionService` (🌐), per-strategy cost from `MitigationService` (🌐); the planner combines them locally.

**Heuristic disclaimer** (file header `:16-21`): `PredictionService.predict` has no mitigation-level parameter, so a *static multiplicative factor* approximates per-strategy fidelity. UI must surface this. Phase 2 replaces it with a real endpoint.

### Mitigation-fidelity factor table — `:28-36`
| Level id | Label | Factor |
|:--:|---|:--:|
| 0 | None | 1.00 |
| 1 | Minimal | 1.05 |
| 2 | Standard | 1.15 |
| 3 | Aggressive | 1.30 |

```matlab
FIDELITY_CAP = 0.99;                                  % :24
fidOut = min(FIDELITY_CAP, baseFidelity * factor);    % :51
```

### Pareto frontier — `computeParetoFrontier`, `:67-92`
```matlab
keep   = arrayfun(@(p) isfinite(p.cost) && isfinite(p.fidelity), points);  % :77 drop non-finite
[~, ord] = sortrows([costs(:), -fids(:)], [1 2]);   % :83 cost ↑, fidelity ↓ tie-break
sorted = points(ord);
bestFid = -inf;
for i = 1:numel(sorted)
    if sorted(i).fidelity > bestFid + 1e-9          % :87 keep strict improvements only
        frontier(end+1) = sorted(i);
        bestFid = sorted(i).fidelity;
    end
end
```

### Optimal pick — `pickOptimal`, `:94-115+`
```matlab
hit = find(fids >= targetFidelity, 1, 'first');     % :106 cheapest frontier point meeting target
% if none meets target → fall back to highest-fidelity point overall (:114+)
```

## 3.3 QEC Simulation Engine — `QecEngineService` ⚙

**Purpose:** density-matrix + Monte-Carlo simulation of quantum error-correcting codes under configurable noise. Powers **QEC Simulation** + **QEC Visualization**. No HTTP. Codes: `bitflip3`, `phaseflip3`, `shor9`, `steane7`, `perfect5`, `surface`, `repetition`. Noise channels: bit-flip, phase-flip, depolarizing, amplitude-damping.

### Pauli constants — `:12-19` · I2, X, Y, Z, H

### Fidelity between states — `:230-231`
```matlab
F = real(trace(rhoIdeal * rhoActual));
F = max(0, min(1, F));
```

### Bloch vector from 2×2 ρ — `:236-238`
```matlab
rx = real(trace(rho * X));  ry = real(trace(rho * Y));  rz = real(trace(rho * Z));
```

### Kraus noise channels — `:487-505`
```matlab
% bit-flip   :487   E0 = sqrt(1-p)·I2,  E1 = sqrt(p)·X
% phase-flip :490   E0 = sqrt(1-p)·I2,  E1 = sqrt(p)·Z
% depolarize :493   E0=sqrt(1-3p/4)·I2, E1=sqrt(p/4)·X, E2=sqrt(p/4)·Y, E3=sqrt(p/4)·Z
% amp-damp   :504   E0=[1 0;0 sqrt(1-γ)], E1=[0 sqrt(γ);0 0]
```
Channel application (Kraus sum) — `:476-480`: `rhoNew = Σ_k Eₖ · ρ · Eₖ'`.

### Error-weight distribution (binomial) — `:258`
```matlab
probs(w+1) = nchoosek(nQubits, w) * errorProb^w * (1-errorProb)^(nQubits-w);
```

### Surface-code logical error (Monte-Carlo) — `:205-209`
```matlab
logicalErrorRate = nLogicalErr / nTrials;
fid = 1 - logicalErrorRate;
rz  = 2*fid - 1;
```

### Analytical logical fidelity (closed-form, decoder-success binomial) — `:1003-1016`
For a distance-3 family code correcting `t = 1` error:
```matlab
F = (1-p)^3 + 3*p*(1-p)^2;   % :1003  bit/phase-flip 3-qubit
F = (1-p)^5 + 5*p*(1-p)^4;   % :1006  [[5,1,3]] perfect
F = (1-p)^7 + 7*p*(1-p)^6;   % :1009  Steane [[7,1,3]]
F = (1-p)^9 + 9*p*(1-p)^8;   % :1012  Shor [[9,1,3]]
F = (1-p)^9 + 9*p*(1-p)^8;   % :1016  surface d=3 (9 data qubits)
```
General form: `F = (1-p)^n + n·p·(1-p)^(n-1)` (zero-error + single-error-corrected terms).

### Syndrome decoding
- Bit-flip parity syndrome — `:554-556`: `s = real(trace(ZZ·ρ))`, `synBit = s < 0`.
- Bit-flip syndrome→qubit lookup — `:559-566`: `synVal = s1·2 + s2`.
- Perfect-5 stabilizers `XZZXI / IXZZX / XIXZZ / ZXIXZ` — `:678`; 16-value syndrome lookup — `:688`.
- Surface-code lattice: `nData = distance^2` (`:180`); X/Z stabilizers at half-integer coords by parity (`:285,:296`); logical error iff any row has odd residual parity (`:972-979`).

### CNOT matrix (MSB convention) — `:796-804` · bit-shift masks + row swap when control=1.
### Logical-state projection — `:820-830` · largest eigenstate of encoded |0⟩/|1⟩, projected to a 2×2 logical ρ.
### Arbitrary single-qubit state — `:331`: `psi = [cos(θ/2); e^{iφ}·sin(θ/2)]`.

## 3.4 Local Statevector Simulator — `StatevectorSimulator` ⚙

**Purpose:** offline statevector evolution for the Composer **Inspect** footer (Bloch tiles, top-K amplitudes, auto-step). Cap **`MAX_QUBITS = 14`** (`:28`), `TOP_K_DEFAULT = 16` (`:29`).

### Init — `:55-56`: `psi = zeros(2^n,1); psi(1) = 1` (|0…0⟩).

### Gate matrices — `:189-206`
```matlab
H   = (1/sqrt(2))*[1 1; 1 -1];          X = [0 1; 1 0];     Y = [0 -1i; 1i 0];
Z   = [1 0; 0 -1];   S = [1 0; 0 1i];   T = [1 0; 0 exp(1i*pi/4)];
Sdg = [1 0; 0 -1i];  Tdg = [1 0; 0 exp(-1i*pi/4)];
Rx(θ) = [cos(θ/2) -1i*sin(θ/2); -1i*sin(θ/2) cos(θ/2)];   % :204
Ry(θ) = [cos(θ/2) -sin(θ/2);    sin(θ/2)     cos(θ/2)];   % :205
Rz(θ) = [exp(-1i*θ/2) 0; 0 exp(1i*θ/2)];                  % :206
```

### Single-qubit application (in-place bit-slicing, O(2ⁿ)) — `:212-221`
```matlab
mask = bitshift(1, q);
% for each base with (base & mask)==0, on pair (lo, hi):
psi(lo) = U(1,1)*a + U(1,2)*b;
psi(hi) = U(2,1)*a + U(2,2)*b;
```

### Multi-qubit gates (bit-mask, MSB convention)
- **CX** — `:225-234`: if `i & mc != 0` and `i & mt == 0`, swap `psi(i) ↔ psi(i|mt)`.
- **CZ** — `:239-244`: if `(i & m) == m`, phase `psi(i+1) = -psi(i+1)`.
- **SWAP** — `:249-262`: when bits differ, swap `psi(i) ↔ psi(i XOR (m1|m2))`.
- **CCX** — `:267-276`: if `(i & mc)==mc` and `i & mt == 0`, swap `psi(i) ↔ psi(i|mt)`.
- **reset** — `:283-296`: zero amplitudes where bit set, renormalize (fallback |0…0⟩ if norm < 1e-12).

### Reduced 1-qubit density matrix — `:302-320`
```matlab
rho(b,b)   += |psi(i)|^2;                 % diagonal probabilities
rho(bi,bj) += psi(i)*conj(psi(j));        % coherences, j = i XOR mask, j>i
```

### Bloch vector per qubit — `:124-129`
```matlab
⟨X⟩ = real(rho(1,2)+rho(2,1));
⟨Y⟩ = real(1i*(rho(1,2)-rho(2,1)));
⟨Z⟩ = real(rho(1,1)-rho(2,2));
```

### Top-K amplitudes — `:133-142`: `probs = abs(psi).^2`, sort descending, keep first K with `prob ≥ 1e-9`.

## 3.5 Circuit Preview & Diagram Math — `CircuitDiagram` ⚙

**Purpose:** render SVG circuit diagrams + measurement-probability bars for previews. Has its own lightweight statevector path (same gate matrices as 3.4: `:893-921`).

### Per-qubit P(|1⟩) from statevector — `:585-595`
```matlab
probs = abs(stateVec).^2;
mask1 = bitand(allIdx, 2^qi) > 0;
qubitProbs(qi+1) = sum(probs(mask1));
```

### SVG layout constants — `:541-550`
```
gateW=24  gateH=20  colW=32  rowH=32  labelW=80  padT=12 padB=12 padR=18
```
Canvas — `:597-601`: `svgW = labelW + cols·colW + padR (+ probW)`; `svgH = padT + nQubits·rowH + padB`.
Wire/gate placement — `:620,:654,:658`: `wy = padT + (qi-0.5)·rowH`; `cx = labelW + (ci-0.5)·colW`; `cy = padT + (qi-0.5)·rowH`.
Probability bar — `:633-641`: `barX = circuitEndX + 20`, `barW = 52`, `fillW = max(round(barW·prob), 0)`.

### Distribution chart — `:951-1095`: top `maxBars = 32` outcomes, y-axis auto-scaled to nice values (5/10/25/50/100 %), `bh = max(round(chartH·pct/yMax), 0)`. Ket labels — `:1099-1100`: `dec2bin(idx, nQubits)` → `|bits⟩`.

## 3.6 QMC / QAE / ZNE / PEC — `AnalysisViewModel` (rendering) + 🌐 backend (engine)

**Purpose:** the Quantum Monte Carlo popup renders QAE risk analytics. The QAE *engine* (amplitude estimation, ZNE fit, VaR/Greeks) runs on the backend via `QmcService` (🌐, async `POST .../qae/analyze` → `202 {job_id}` → poll); MATLAB extracts result fields and draws charts. Two formulas are computed *locally*: the convergence reference curves and the PEC overhead γ̄.

### QAE vs classical MC convergence (reference curves) — `:2940-2948`
```
QAE / QMC      error ~ 1/N         % quadratic speedup
Classical MC   error ~ 1/sqrt(N)
```
Rendered as legends `'QMC ~ 1/N'` / `'Classical MC ~ 1/√{N}'` on log-log axes.

### Zero-Noise Extrapolation — `:2980-3025`
Plots amplitude vs noise factor; native point at `nf = 1.0`, extrapolated zero-noise point marked at `nf == 0`. **Fit itself is backend-owned**; MATLAB renders the scatter + extrapolated marker.

### PEC overhead γ̄ (computed locally) — `computeGammaBar`, `:2231-2244`
```matlab
gammabar = (1 - eplg)^(-2);     % inverse transform from error-per-logical-gate
% PEC sampling overhead grows as:
overhead = gammaBar ^ depth;    % :2244
```

### Risk fields extracted (backend-computed) — `:2857-2978`
`var_95`, `var_99` (VaR threshold lines), CDF `P(loss ≤ x)`, Greeks `[delta, gamma, vega, theta, rho]` (`:2963-2967`), objective-qubit amplitude `P(objective=1) = a` (`:3030-3046`).

## 3.7 Backend-Resident Math (🌐 — not in MATLAB)

These features' numerics live on the FastAPI server; MATLAB only marshals requests / renders responses. Contract: `doc/fastapi_contract.md`, `doc/openapi.json`. Listed here so the compendium is complete.

| Feature | Service / endpoint | Backend computes |
|---|---|---|
| Fidelity prediction | `PredictionService` → `POST /api/predict` | Per-backend fidelity, distribution, error budget |
| Transpilation optimize | `PredictionService` → `POST /api/optimize` | Optimized depth / gate-count |
| Volumetric benchmark | `BenchmarkService` → `GET /api/benchmark/volumetric` | (width × depth) → fidelity heatmap |
| System metrics | `…/system-metrics/{backend}` | Quantum Volume, CLOPS, Layer Fidelity, EPLG |
| Scorecard | `…/scorecard` | Capacity / scalability / accuracy / runtime sub-scores + overall |
| Regression | `…/regression` | Time-series fidelity drift detection |
| Mitigation cost | `MitigationService` → `POST /api/mitigation/estimate` | Shot multiplier, IQP cost, runtime estimate |
| Circuit features | `CircuitService` → `POST /api/circuits/{id}/analyze` | depth, gate counts, two-qubit ratio, T-count, feature vector |
| QTAUBench similarity | `…/match-benchmarks` | Similarity score per benchmark circuit |
| QAE engine | `QmcService` → `…/qae/analyze` | Amplitude estimation, ZNE fit, VaR, Greeks |
| Circuit cutting | `CuttingService` → `/api/cutting/*` | Cut finding, subcircuit generation, reconstruction |

---

# Part IV — Deeper References

| Topic | Document |
|---|---|
| Error Mitigation internals + formulas | [`Error_Mitigation_Deep_Dive.md`](Error_Mitigation_Deep_Dive.md), [`Quantum Error Mitigation.md`](Quantum%20Error%20Mitigation.md) |
| Circuit cutting algorithm + formulas | [`Circuit_Cutting_Deep_Dive.md`](Circuit_Cutting_Deep_Dive.md), [`circuit_cutting_algorithm.md`](circuit_cutting_algorithm.md) |
| Per-feature pages (7-section template) | [`features/INDEX.md`](features/INDEX.md) + `features/*.md` |
| Runtime architecture, data flow, REST surface | [`TECHNICAL_SPEC.md`](TECHNICAL_SPEC.md), [`architecture.md`](architecture.md) |
| Operator workflow | [`workflow.md`](workflow.md) |
| Full REST contract | [`fastapi_contract.md`](fastapi_contract.md), [`openapi.json`](openapi.json) |
| Test coverage | [`TEST_SPEC.md`](TEST_SPEC.md), [`TEST_REPORT.md`](TEST_REPORT.md) |

---

# Appendix — Constants Quick Table

| Constant | Value | Source |
|---|---|---|
| Surface-code threshold p_th | 0.01 | `ResourceEstimatorService.m:27` |
| FT prefactor | 0.03 | `:28` |
| T-gates per Toffoli | 7 | `:29` |
| T-factory footprint factor | 16 (×phl) | `:30` |
| Code distance range | [3, 51] | `:31-32` |
| Default phys err / log err / cycle | 1e-3 / 1e-15 / 1e-6 s | `:39-41` |
| Routing-ancilla fraction | 10 % of data qubits | `:73` |
| T-factory time overhead | ×10 | `:64` |
| Run-planner fidelity cap | 0.99 | `RunPlannerService.m:24` |
| Mitigation factors (None→Aggressive) | 1.00 / 1.05 / 1.15 / 1.30 | `:32-35` |
| Statevector qubit cap | 14 | `StatevectorSimulator.m:28` |
| Top-K amplitudes | 16 | `:29` |
| Diagram grid (gateW/gateH/colW/rowH) | 24/20/32/32 px | `CircuitDiagram.m:541-550` |
| Distribution chart max bars | 32 | `CircuitDiagram.m` |

*All `file:line` citations verified against source at time of writing. Re-verify after refactors — line numbers drift.*
