# QTAU Connector Workbench — Key Features Explained

**A plain-language guide to what the app does, why each feature exists, and the math behind it.**

This document is written for **users** — operators, researchers, and reviewers — not just developers. Each feature below answers three questions:

- **What it does** — the capability in one or two sentences.
- **Why it matters** — the real problem it solves for you.
- **The math inside** — the key formula(s), with every symbol explained in plain words so you can read the numbers the app shows you and know exactly what they mean.

> **Where the math runs.** QTAU Workbench is a MATLAB desktop app talking to a FastAPI backend. Some features compute their numbers **locally in MATLAB** (instant, offline) — these are marked **⚙ Local**. Others send your request to the **backend** and render the answer — marked **🌐 Server**. This matters because the local ones work without a live server and you can audit the exact formula in the MATLAB source.
>
> For terse engineering detail with `file:line` citations, see [`MASTER_REFERENCE.md`](MASTER_REFERENCE.md). For the deepest dives, see [`Error_Mitigation_Deep_Dive.md`](Error_Mitigation_Deep_Dive.md) and [`Circuit_Cutting_Deep_Dive.md`](Circuit_Cutting_Deep_Dive.md).

---

## Table of contents

1. [Circuit Composer & Local Simulation](#1-circuit-composer--local-simulation-)
2. [Circuit Analysis & QTAUBench Similarity](#2-circuit-analysis--qtaubench-similarity-)
3. [Quantum Monte Carlo (QAE risk analytics)](#3-quantum-monte-carlo-qae-risk-analytics--)
4. [Quantum Error Mitigation](#4-quantum-error-mitigation--heuristics--engine)
5. [Circuit Cutting](#5-circuit-cutting-)
6. [Fidelity Prediction](#6-fidelity-prediction-)
7. [Benchmarking](#7-benchmarking-)
8. [Mitigation Compare](#8-mitigation-compare-)
9. [Fault-Tolerant Resource Estimator](#9-fault-tolerant-resource-estimator-)
10. [Run Planner](#10-run-planner-)
11. [QEC Simulation & Visualization](#11-qec-simulation--visualization-)
12. [Backends Explorer](#12-backends-explorer-)
13. [Jobs & Results](#13-jobs--results-)
14. [Reports & Reproducibility Bundle](#14-reports--reproducibility-bundle--)

---

## 1. Circuit Composer & Local Simulation ⚙

**What it does.** Lets you build a quantum circuit inside the app — click-to-place gates on a wire canvas, or type OpenQASM 2.0 and watch the canvas redraw. A built-in "Inspect" panel simulates the circuit on your own machine (up to 14 qubits) and shows you, qubit by qubit, where the quantum state actually is.

**Why it matters.** You can design, sanity-check, and understand a circuit *before* spending real quantum hardware time or backend credits. The local simulator is exact (no noise), so it's your ground truth for "what should this circuit do."

### The math inside

A quantum state of *n* qubits is a list of 2ⁿ complex numbers (the **statevector** `ψ`). The app starts every circuit in the all-zeros state and then applies each gate as a matrix multiplication.

**Starting state:** `ψ = [1, 0, 0, …, 0]` — 100 % probability of measuring `|00…0⟩`.

**Single-qubit gates** are 2×2 matrices. The ones you place on the canvas are exactly these:

| Gate | Matrix | What it does physically |
|------|--------|--------------------------|
| H (Hadamard) | `(1/√2)·[1 1; 1 −1]` | Creates an equal superposition — the basis of most quantum advantage |
| X | `[0 1; 1 0]` | Bit-flip (quantum NOT) |
| Y | `[0 −i; i 0]` | Bit-flip + phase-flip |
| Z | `[1 0; 0 −1]` | Phase-flip |
| S | `[1 0; 0 i]` | Quarter-turn phase |
| T | `[1 0; 0 e^(iπ/4)]` | Eighth-turn phase (the expensive "non-Clifford" gate — see §9) |
| Rx(θ) | `[cos(θ/2) −i·sin(θ/2); −i·sin(θ/2) cos(θ/2)]` | Rotation by angle θ about the X axis |
| Ry(θ) | `[cos(θ/2) −sin(θ/2); sin(θ/2) cos(θ/2)]` | Rotation about the Y axis |
| Rz(θ) | `[e^(−iθ/2) 0; 0 e^(iθ/2)]` | Rotation about the Z axis |

**Two-qubit gates** (CX, CZ, SWAP) and the three-qubit Toffoli (CCX) act by conditionally swapping or phasing pairs of entries in `ψ`. The simulator does this efficiently by flipping bits in the state's index rather than building a giant matrix.

**Reading the state — the Bloch vector.** For each qubit the app shows three numbers ⟨X⟩, ⟨Y⟩, ⟨Z⟩ between −1 and +1. They are the average outcomes you'd get measuring that qubit along each axis:

```
⟨X⟩ = real( ρ₁₂ + ρ₂₁ )
⟨Y⟩ = real( i·(ρ₁₂ − ρ₂₁) )
⟨Z⟩ = real( ρ₁₁ − ρ₂₂ )
```

Here `ρ` is the qubit's **reduced density matrix** (the 2×2 description of one qubit after ignoring the others). Intuition: **⟨Z⟩ = +1** means "definitely 0", **⟨Z⟩ = −1** means "definitely 1", **⟨Z⟩ = 0** with non-zero ⟨X⟩ or ⟨Y⟩ means "in superposition." If all three are near zero, the qubit is **entangled** with the rest — its information lives in the correlations, not in the qubit alone.

**Top-K amplitudes.** The probability of measuring outcome `i` is the Born rule `Pᵢ = |ψᵢ|²`. The app sorts these and shows the most likely bitstrings as bars.

**The 14-qubit cap** exists because 2ⁿ grows explosively — 14 qubits already means 16,384 complex numbers; 30 qubits would need a billion. This is *why* real quantum hardware (and the cutting/prediction features below) exist.

---

## 2. Circuit Analysis & QTAUBench Similarity 🌐

**What it does.** Extracts the structural fingerprint of a circuit — qubit count, depth, gate counts by type, the ratio of two-qubit gates, the T-gate count — and matches it against **QTAUBench**, a library of 250+ reference circuits, to tell you "your circuit looks most like *this* known algorithm."

**Why it matters.** Two numbers predict almost everything about how a circuit will run on noisy hardware: **depth** (how many gate layers — more layers, more time for errors to accumulate) and **two-qubit-gate count** (two-qubit gates are ~10× noisier than single-qubit gates). The similarity match lets you reuse known benchmark results instead of starting from scratch.

### The math inside

The heavy lifting (feature vector + similarity scoring) runs on the backend. The fingerprint fields it returns:

- **depth** — the number of sequential gate layers (the circuit's "critical path").
- **two_qubit_gate_ratio** = (two-qubit gates) / (total gates). A blunt but powerful noise proxy.
- **t_count** — number of T / T† gates, which drive fault-tolerant cost (§9).
- **similarity** — a score (typically 0–1) per benchmark match. Higher = structurally closer. The backend computes it from the feature vectors; treat it like a "nearest-neighbour" distance turned into a closeness score.

---

## 3. Quantum Monte Carlo (QAE risk analytics) 🌐 + ⚙

**What it does.** A popup (launched from the Analysis screen) that runs **Quantum Amplitude Estimation (QAE)** — the quantum version of Monte Carlo simulation used for financial risk (Value-at-Risk, option Greeks, loss distributions). It can run on a local simulator or on real IBM Runtime hardware, and produces a one-click PDF report.

**Why it matters.** Classical Monte Carlo is the workhorse of risk pricing, but it converges slowly. QAE promises a **quadratic speedup** — the headline reason a bank would care about quantum computing. This feature demonstrates and measures that speedup on your circuit.

### The math inside

**The convergence advantage (the whole point).** To estimate a quantity to error ε:

```
Classical Monte Carlo:   error  ∝  1/√N      (need N samples)
Quantum Amplitude Est.:   error  ∝  1/N       (need only √N as many)
```

where **N** = number of samples / oracle calls. Read it this way: to get one more decimal digit of accuracy, classical MC needs **100×** more samples; QAE needs only **10×**. The app draws both curves on a log-log plot so you can see the gap widen. *(These reference curves are drawn locally in MATLAB; the actual estimate comes from the backend QAE engine.)*

**What QAE estimates.** A single amplitude `a` = the probability that a designated "objective qubit" is measured as 1. Your risk question (e.g. "what fraction of outcomes lose more than $X") is encoded so its answer *is* that probability. The app shows `P(objective = 1) = a` as a two-bar chart.

**Value-at-Risk (VaR).** The report marks `var_95` and `var_99` as vertical lines on the loss distribution. **VaR at 95 %** means: "95 % of the time, losses are no worse than this line." It's read off the **cumulative distribution** `P(loss ≤ x)`, which the app also plots.

**Greeks** `[delta, gamma, vega, theta, rho]` are the sensitivities of an option's price to the underlying price, its curvature, volatility, time, and interest rate — the standard risk dashboard, here computed from the quantum result.

**Zero-Noise Extrapolation curve.** On hardware runs the popup shows amplitude vs. *noise factor*, with the native hardware at noise factor 1.0 and an extrapolated "what it would be at zero noise" point. (How that extrapolation is computed is §4.)

---

## 4. Quantum Error Mitigation ⚙ heuristics + 🌐 engine

**What it does.** Reduces the impact of hardware noise on your results **without** full error correction, by trading extra shots/runtime for accuracy. You pick a level — None / Minimal / Standard / Aggressive — and the app applies a matching recipe of techniques.

**Why it matters.** Today's quantum computers are noisy. Error *correction* (§9, §11) needs thousands of physical qubits per logical qubit and isn't available yet. Error *mitigation* is what makes near-term hardware usable: it cleans up the answer statistically at the cost of running more.

### The math inside

**The levels and their cost** (the cost model runs on the backend):

| Level | Techniques applied | Wall-clock multiplier |
|:-----:|--------------------|:---------------------:|
| 0 None | raw run | 1.0× |
| 1 Minimal | larger shot floor | 1.05× |
| 2 Standard | + twirling + dynamical decoupling | (level-2 recipe) |
| 2 Aggressive | + Zero-Noise Extrapolation (3 noise factors, exponential fit) | 3.0× |

**Cost preview formula** (what the cost card shows you):

```
est_wall_seconds = effective_shots × seconds_per_shot × wall_mult
est_iqp_units    = est_wall_seconds / 60          (IBM backends only)
shot_multiplier  = effective_shots / max(1, ⌊effective_shots / wall_mult⌋)
```

- **effective_shots** — how many measurement repetitions actually run (mitigation raises this; Aggressive floors it at 16,384).
- **seconds_per_shot** — time per repetition (default 1×10⁻⁴ s in the preview).
- **wall_mult** — the multiplier from the table above. ⚠️ The displayed `shot_multiplier` is a *wall-clock proxy*, not the literal shot ratio — see the deep dive.

**Zero-Noise Extrapolation (ZNE) — the core mitigation idea.** You can't turn hardware noise *down*, but you can turn it *up* on purpose, measure the answer at several noise levels, and extrapolate back to "zero noise."

*Step 1 — amplify noise by circuit folding.* Replace the circuit `U` with `U(U†U)ᵏ`. Mathematically `U†U` is the identity, so the *ideal* answer is unchanged — but each extra gate gets exposed to more noise:

```
noise_factor = 1 + 2k        →   k = 0 gives 1×,  k = 1 gives 3×,  k = 2 gives 5×
```

The default noise factors are **(1.0, 3.0, 5.0)**.

*Step 2 — extrapolate to zero.* Given the measured value `yᵢ` at each noise factor `xᵢ`, estimate the value at `x = 0`. The app supports four methods:

- **linear / polynomial** — straight-line least-squares fit; return the intercept (the y-value where the line hits x = 0).
- **richardson** — exact polynomial interpolation through all points, evaluated at zero:
  ```
  ŷ₀ = Σᵢ yᵢ · ∏(j≠i) (−xⱼ)/(xᵢ − xⱼ)
  ```
- **exponential** *(the default)* — fit `y = a·e^(−b·x) + c`, then the zero-noise value is `a + c`. This is the default because hardware noise tends to decay roughly exponentially with circuit depth.

> ⚠️ **Honest caveat** (verified in the deep dive): in the current production submit path, the folding/extrapolation code is *recorded for provenance* but the un-biasing is **not yet executed server-side** at level 2 — what actually ships is twirling + dynamical decoupling + the larger shot floor. The QMC popup's ZNE curve is a separate visualization. See [`Error_Mitigation_Deep_Dive.md`](Error_Mitigation_Deep_Dive.md) §5.

**The Run-Planner fidelity heuristic** ⚙ (used by §10). Because the prediction service has no mitigation parameter, the app multiplies base fidelity by a static factor, capped at 0.99:

```
None ×1.00   Minimal ×1.05   Standard ×1.15   Aggressive ×1.30
fidelity = min(0.99, base_fidelity × factor)
```

This is explicitly a UI heuristic, surfaced to you as such.

---

## 5. Circuit Cutting 🌐

**What it does.** Splits a circuit that's too big for any single quantum computer into smaller sub-circuits that fit, runs them (possibly on different machines in parallel), and mathematically reconstructs the answer the full circuit would have given.

**Why it matters.** Your circuit might need 250 qubits but the biggest available chip has 156. Cutting lets you run it anyway. The trade-off is cost: cutting is **never free** — each cut multiplies the number of shots you need.

### The math inside

**The sampling overhead γ — the key formula.** Every cut you make multiplies the measurement budget by a factor γ (gamma). The app reports it directly:

```
sampling_overhead        = γ        (from the cutting addon's exact calculation)
sampling_overhead_log10  = log₁₀(γ)
```

Intuition: for the standard cutting basis, γ grows roughly as **4^(number of cuts)** — so 1 cut ≈ 4× more shots, 2 cuts ≈ 16×, 3 cuts ≈ 64×. The app reads the *exact* value from the addon rather than the `4ᵏ` rule of thumb, but `4ᵏ` is the right mental model. **This is why you cut as few times as possible.**

**Feasibility gate.** If γ exceeds **10⁶**, reconstruction noise drowns the signal no matter how many shots you buy, so the app flags the plan infeasible (you can override).

**How many cuts (target_k).** When auto-cutting a wide circuit across a fleet, the app picks:

```
target_k = max(2, ⌈ n / widest ⌉)
```

- **n** — your circuit's qubit count.
- **widest** — the largest chip in your backend pool.

Example: a 250-qubit circuit on a fleet whose widest chip is 156 qubits → `⌈250/156⌉ = 2` → split into two ~125-qubit halves, both of which fit. This smart default is what prevents a catastrophic over-cut.

**Reconstruction.** After the sub-circuits run, the full expectation value is rebuilt as a **weighted sum** of the sub-results using QPD (quasi-probability decomposition) coefficients. ⚠️ Note: the reported `std_err` is currently hardcoded to 0.0 on success — don't read it as a real uncertainty (see [`Circuit_Cutting_Deep_Dive.md`](Circuit_Cutting_Deep_Dive.md) §5.4).

---

## 6. Fidelity Prediction 🌐

**What it does.** Before you spend hardware time, predicts how faithfully a given circuit will run on a given backend — a single **fidelity** number (0 to 1), plus a probability distribution and a breakdown of where the errors come from (the "error budget").

**Why it matters.** It answers "is this circuit even worth running on this machine?" A predicted fidelity of 0.05 tells you the result will be mostly noise — don't waste the credits. The error budget tells you *what* to fix (e.g. "80 % of your error is from two-qubit gates → reduce circuit depth").

### The math inside

The fidelity model runs on the backend (`POST /api/predict`). Conceptually, circuit fidelity is the product of surviving each operation:

```
F ≈ ∏(gates) (1 − error_rate_of_that_gate)
```

so fidelity falls off roughly exponentially with depth and two-qubit-gate count. The backend uses the live calibration data (per-gate and readout error rates) of the chosen backend to compute the real number; the app renders it with its distribution and per-source error budget.

---

## 7. Benchmarking 🌐

**What it does.** Measures and scores how a backend performs, across a grid of circuit sizes (the **volumetric benchmark**), and reports industry-standard metrics: Quantum Volume, CLOPS, Layer Fidelity, EPLG. Also detects performance **regression** over time.

**Why it matters.** Backends drift — a chip that ran well last week may have degraded. Benchmarking gives you an objective, comparable scorecard so you pick the right machine today and catch silent degradation.

### The math inside (metrics defined; computed on the backend)

- **Quantum Volume (QV)** — the largest *square* circuit (equal width and depth) the device can run with >⅔ success. Reported as `2^(largest passing size)`. A single number capturing "how big a useful circuit fits."
- **CLOPS** — Circuit Layer Operations Per Second; raw speed.
- **Layer Fidelity / EPLG** — Error Per Layered Gate; how much fidelity is lost per gate layer. Lower is better.
- **Volumetric grid** — a heatmap over (width × depth) showing fidelity in each cell; the boundary of the "green" region is the device's practical capability.
- **Scorecard** combines capacity, scalability, accuracy, and runtime sub-scores into one overall rating.

---

## 8. Mitigation Compare 🌐

**What it does.** Puts mitigation strategies side by side — for one circuit across several backends — showing cost, shot multiplier, runtime, and IQP-cost for each, with a recommendation strip (cheapest / best balance / most aggressive).

**Why it matters.** Mitigation is a cost/accuracy dial. This screen turns an abstract choice into a concrete comparison so you can answer "is Aggressive on chip A cheaper than Standard on chip B?" at a glance. It's a differentiator — no major cloud platform ships a side-by-side mitigation cost comparator.

### The math inside

Each card uses the same cost-preview formula from §4 (`est_wall_seconds`, `shot_multiplier`, `est_iqp_units`), computed by parallel backend calls — one per chip — then ranked locally by the shot multiplier.

---

## 9. Fault-Tolerant Resource Estimator ⚙

**What it does.** Answers the big-picture question: "to run this circuit *with full error correction*, how many physical qubits and how much time would I need?" Given your circuit and three parameters (physical error rate, target logical error rate, cycle time), it computes the surface-code distance, total physical qubits, T-factory count, and runtime — entirely locally.

**Why it matters.** It bridges today (noisy, ~100s of qubits) and the fault-tolerant future (millions of qubits). It tells you, concretely, *how far away* a useful fault-tolerant run is for your specific algorithm — and the app narrates the answer ("near-term" / "exceeds today's largest devices" / "fault-tolerant scale").

### The math inside (all local, auditable in `ResourceEstimatorService.m`)

**Code distance d** — how big each logical qubit's protective tile must be. Derived by inverting the Fowler surface-code error formula `logical_error ≈ 0.03·(p/p_th)^((d+1)/2)`:

```
d = 2 · [ ln(ε / 0.03) / ln(p / p_th) ] − 1        (then rounded up to the next odd number)
```

- **p** — physical error rate (how often one physical operation fails, e.g. 10⁻³).
- **p_th = 0.01** — the surface-code *threshold*. Below it, adding more qubits reduces error; above it, error correction fails (the app caps d at 51 to flag this).
- **ε** — the logical error rate you want (e.g. 10⁻¹⁵, i.e. essentially never fails).

Bigger gap between p and p_th, or a more demanding ε, → larger d.

**Physical qubits per logical qubit:**

```
physical_per_logical = 2·d² + 1
```

A distance-15 code, for example, needs 2·225+1 = 451 physical qubits for *one* logical qubit. This is the overhead that makes fault tolerance so expensive.

**T-state budget.** The cheap "Clifford" gates (H, S, CNOT) are nearly free to error-correct; the expensive ones are T-gates and anything built from them. The estimator counts them:

```
total_T = (T and T† gates) + 7 × (Toffoli gates) + (T-gates from arbitrary rotations)
```

- A **Toffoli** costs **7** T-gates.
- An arbitrary rotation (a non-Clifford Rx/Ry/Rz) is approximated by the **Solovay-Kitaev** bound `≈ 3·log₂(1/ε)` T-gates each — because arbitrary angles must be built from a discrete gate set, and finer accuracy needs more gates.
- A rotation is "free" (Clifford) only if its angle is a multiple of π/2.

**T-factories** (the assembly lines that produce the special states T-gates consume):

```
factory_qubits = 16 × physical_per_logical      (when any T-gates are needed)
```

**Total qubits and runtime:**

```
data_qubits    = logical_qubits × physical_per_logical
ancilla_qubits = 10 % of data qubits             (routing space)
total_physical = data + ancilla + factory_qubits

runtime_seconds = depth × d × overhead × cycle_time
```

where **cycle_time** is the duration of one error-correction round (default 1 µs), **depth** is your circuit's depth, and **overhead** is ×10 when T-factories are active. The app shows these as a pie chart (data / ancilla / factory) plus result cards.

---

## 10. Run Planner ⚙

**What it does.** Answers "give me fidelity F at the **minimum cost**." You set a target fidelity and shot count; the planner crosses every backend with every mitigation strategy, finds the cost-vs-fidelity trade-off curve, and recommends the cheapest configuration that hits your target.

**Why it matters.** This is the question every operator actually has, and no competing platform answers it in one click. Instead of manually comparing dozens of (backend, mitigation) combinations, you get one recommendation plus a visual of all your options.

### The math inside (local, in `RunPlannerService.m`)

**Step 1 — build candidates.** For each backend (base fidelity from §6) × each mitigation level (cost from §4, fidelity via the §4 heuristic factor), make one `(cost, fidelity)` point.

**Step 2 — the Pareto frontier.** A configuration is "Pareto-optimal" if nothing else is both cheaper *and* more accurate. The planner finds these by sorting points by cost (cheapest first) and keeping any point that beats the best fidelity seen so far:

```
sort points by cost ascending (fidelity descending as tie-break)
best = −∞
for each point in order:
    if point.fidelity > best:   keep it on the frontier;  best = point.fidelity
```

The kept points form the trade-off curve — every point on it is a "smart" choice; everything below it is strictly worse.

**Step 3 — pick the optimal.** Walk the frontier from cheapest up and take the first point that meets your target:

```
recommendation = cheapest frontier point with fidelity ≥ target
if none reaches the target → fall back to the highest-fidelity point available
```

The app plots all candidates, overlays the frontier and your target line, and stars the recommendation — with hand-off buttons to submit that run or bundle that config.

---

## 11. QEC Simulation & Visualization ⚙

**What it does.** Simulates quantum **error-correcting codes** (3-qubit bit/phase-flip, Steane [[7,1,3]], Shor [[9,1,3]], the [[5,1,3]] perfect code, and surface codes) under realistic noise, and visualizes the result as a 3D Bloch sphere, a surface-code lattice, and an error-propagation view — all locally.

**Why it matters.** Error correction is *the* path to useful quantum computing, and it's deeply unintuitive. This feature lets you see, hands-on, how a code detects and fixes errors and how its protection improves with code distance — the conceptual bridge to the Resource Estimator (§9).

### The math inside (local, in `QecEngineService.m`)

**Noise as Kraus channels.** Noise is applied to the density matrix `ρ` as `ρ → Σₖ Eₖ ρ Eₖ†`, where the `Eₖ` depend on the channel:

| Channel | Operators |
|---------|-----------|
| Bit-flip | `E₀ = √(1−p)·I`, `E₁ = √p·X` |
| Phase-flip | `E₀ = √(1−p)·I`, `E₁ = √p·Z` |
| Depolarizing | `E₀ = √(1−3p/4)·I`, `E₁ = √(p/4)·X`, `E₂ = √(p/4)·Y`, `E₃ = √(p/4)·Z` |
| Amplitude damping | `E₀ = [1 0; 0 √(1−γ)]`, `E₁ = [0 √γ; 0 0]` (energy loss) |

Here **p** is the error probability and **γ** the damping (relaxation) strength.

**The payoff — logical fidelity.** A distance-3 code corrects any *single* error. Its surviving fidelity is the chance of zero errors plus the chance of exactly one (which gets corrected):

```
F = (1−p)ⁿ + n·p·(1−p)^(n−1)
```

- **n** — number of physical qubits in the code (3, 5, 7, or 9).
- First term `(1−p)ⁿ` — probability *nothing* went wrong.
- Second term `n·p·(1−p)^(n−1)` — probability exactly one of the n qubits erred (any single one), which the decoder repairs.

The lesson you can see in the numbers: a single physical qubit has fidelity `1−p`; the encoded logical qubit has fidelity `≈ 1 − O(p²)`. For small p that's a huge improvement — **that's what error correction buys you**, and bigger codes (larger n / distance) push the protection further.

**Error-weight distribution.** The chance of exactly `w` errors among n qubits is the binomial:

```
P(w errors) = C(n, w) · pʷ · (1−p)^(n−w)
```

**Syndrome decoding.** The simulator measures *parity checks* (stabilizers) that reveal *where* an error is without disturbing the stored data, then looks up the correction. For the 3-qubit code two parity bits `s₁, s₂` pinpoint which qubit flipped; the [[5,1,3]] code uses four stabilizers (`XZZXI`, `IXZZX`, `XIXZZ`, `ZXIXZ`) giving a 16-entry lookup. The Bloch sphere and lattice views animate exactly this detect-and-correct cycle.

---

## 12. Backends Explorer 🌐

**What it does.** Browse available quantum backends, pick a primary and a backup, and drill into live telemetry: an overview, a per-qubit health heat-grid (T1, T2, gate error, readout error), 7-day history sparklines, and a force-directed graph of the chip's qubit connectivity colored by health.

**Why it matters.** Not all qubits are equal — and they change daily. Seeing the calibration map lets you avoid bad qubits and pick the chip whose *good* region matches your circuit's shape. The topology graph shows which qubits can directly talk (two-qubit gates only run between connected qubits).

### The numbers shown

- **T1** — energy-relaxation time (how long a qubit stays in `|1⟩` before decaying). Longer = better.
- **T2** — dephasing time (how long a superposition's phase survives). Longer = better.
- **gate_err / readout_err / 2Q_err** — per-operation and per-measurement error rates. Lower = better.
- **Node color** — a composite health score (green/amber/red) blending T1, T2, and gate error, so you can spot the strong and weak regions of the chip at a glance.

---

## 13. Jobs & Results 🌐

**What it does.** **Jobs** is a live monitoring dashboard — every submitted run with its status and progress, auto-refreshing every 5 seconds. **Results** compares, for a completed job, the **measured** outcomes against the **predicted** and the **ideal** (noiseless) distributions.

**Why it matters.** Jobs tells you what's happening *now* without manual refreshing. Results closes the loop: it shows you how close reality came to theory, and (with mitigation) how much the mitigation actually helped — the evidence you need to trust or distrust a result.

### The math inside

The key comparison is between three probability distributions over measurement outcomes: **ideal** (from noiseless simulation), **predicted** (the fidelity model's expectation, §6), and **measured** (the real counts, normalized to probabilities). The visual gap between *measured* and *ideal* is your effective error; the gap between *measured* and *predicted* tells you whether the prediction model was trustworthy.

---

## 14. Reports & Reproducibility Bundle 🌐 + ⚙

**What it does.** **Reports** generates shareable PDF / HTML / JSON documents (the QMC report has dedicated vector charts: loss distribution with VaR, CDF, QAE-vs-classical convergence, ZNE curve, Greeks table). The **Reproducibility Bundle** is a one-click ZIP containing your circuit (as OpenQASM plus Qiskit / Cirq / Braket Python), its metadata, the backend calibration snapshot, mitigation estimates, the fault-tolerant estimate, an auto-generated README, and a manifest with SHA-256 checksums.

**Why it matters.** Science requires reproducibility, and quantum results depend on the *exact* circuit, backend calibration, and settings at run time — details that are normally lost. The bundle packages all of it so anyone can rerun and verify your experiment. No competing platform packages reproducibility metadata as a single downloadable artifact.

### The math inside

**SHA-256 checksums** in the manifest are cryptographic fingerprints of each file — a 256-bit number where changing a single byte produces a completely different hash. They let a reviewer confirm the files they received are byte-for-byte what you packaged, with no tampering or corruption.

---

## Quick reference — where each feature's math lives

| Feature | Local ⚙ | Server 🌐 | Key formula |
|---------|:------:|:--------:|-------------|
| Composer / Inspect | ✓ | | Gate matrices, Born rule `\|ψᵢ\|²`, Bloch ⟨X⟩⟨Y⟩⟨Z⟩ |
| Analysis / similarity | | ✓ | feature vector, similarity score |
| Quantum Monte Carlo | partial | ✓ | QAE `1/N` vs classical `1/√N`; VaR, Greeks |
| Error Mitigation | heuristic | ✓ | ZNE fold `nf = 1+2k`; extrapolate to x=0; cost model |
| Circuit Cutting | | ✓ | overhead `γ ≈ 4^cuts`; `target_k = ⌈n/widest⌉` |
| Fidelity Prediction | | ✓ | `F ≈ ∏(1 − gate_error)` |
| Benchmarking | | ✓ | Quantum Volume, EPLG, volumetric grid |
| Mitigation Compare | | ✓ | cost-preview formula (§4) |
| Resource Estimator | ✓ | | `d = 2·ratio−1`; `2d²+1`; T-budget; runtime |
| Run Planner | ✓ | (inputs) | Pareto frontier; cheapest-meets-target |
| QEC Simulation | ✓ | | Kraus channels; `F = (1−p)ⁿ + n·p(1−p)ⁿ⁻¹` |
| Backends | | ✓ | T1/T2, composite health score |
| Jobs / Results | | ✓ | measured vs predicted vs ideal distributions |
| Reports / Bundle | ✓ | ✓ | SHA-256 checksums |

---

*Every local formula in this document was verified against the MATLAB source; every server formula against the backend deep dives, on review. Symbols: `p` = physical error rate, `ε` = target logical error / accuracy, `d` = code distance, `n` = qubit/sample count, `N` = Monte-Carlo samples, `γ` = sampling overhead, `θ` = rotation angle, `ρ` = density matrix, `ψ` = statevector.*
