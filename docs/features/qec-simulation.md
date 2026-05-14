# QEC Simulation

See also: [`qec-overview.md`](qec-overview.md) for the conceptual primer
on codes and noise models.

## 1. What it is

The QEC Simulation screen lets the operator pick a quantum error
correction code, a noise channel, an error probability `p`, an initial
logical state, and a number of correction rounds, then runs the
client-side `QecEngineService.simulate` and renders logical fidelity,
syndrome histogram, and (when the code is `surface`) a logical-error
rate vs `p` curve.

## 2. Purpose

- Let operators see **logical fidelity** vs **unprotected fidelity**
  side by side, so they understand when QEC pays off (above-threshold)
  vs when it adds overhead without protection (below-threshold).
- Show the **syndrome histogram** so operators can see how often each
  error pattern occurred during the trial — a teaching tool for what
  "the QEC code measures" means in practice.
- Demonstrate the **threshold theorem** for surface codes by sweeping
  `p` and observing the logical-vs-physical error rate crossover.

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Screen | `QecSimulationScreen` | `src/presentation/screens/QecSimulationScreen.m` |
| ViewModel | `QecSimulationViewModel` | `src/presentation/viewmodels/QecSimulationViewModel.m` |
| Service | `QecEngineService` (client-side) | `src/domain/services/QecEngineService.m` |
| Backend | None — fully local | n/a |
| Defaults | `qec_default_trials`, etc. | `resources/app.properties` |

## 4. Algorithm

See [`qec-overview.md`](qec-overview.md) §5. Key UI parameters:

- **Code** — `bitflip3`, `phaseflip3`, `shor9`, `steane7`, `perfect5`,
  `surface`.
- **Noise model** — `bitflip`, `phaseflip`, `depolarizing`, `amplitude_damping`.
- **Error probability `p`** — slider, typically 0.001 – 0.5.
- **Initial logical state** — `|0⟩`, `|1⟩`, `|+⟩`, `|−⟩`, `|i+⟩`, `|i−⟩`.
- **Rounds** — number of (noise → syndrome → correction) iterations
  per trial.
- **Trials** — default from `AppConfig.getDouble('qec_default_trials', 100)`.

## 5. Workflow

1. Open **QEC Simulation**.
2. Pick code + noise + `p` + initial state + rounds.
3. Click **Run** — `QecSimulationViewModel.onRun` calls
   `QecEngineService.simulate` synchronously (fast; ≤ 9 qubits).
4. KPI cards populate: logical fidelity, unprotected fidelity,
   logical-error rate (1 − fidelity at the F > 0.99 threshold).
5. Syndrome histogram bar chart renders the trial counts.
6. (Optional) Run a **`p` sweep** — the screen runs `simulate` for
   `p ∈ {0.001, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2}` and plots the
   logical vs physical error-rate curve.

## 6. Data flow

```
QEC Simulation screen   ──→   QecEngineService.simulate(
                                  codeType, noiseModel, errorProb,
                                  initialState, nRounds)
                              (client-side density-matrix simulation,
                               no HTTP round-trip)
                          ←─  { fidelity, unprotected_fidelity,
                               syndromes, bloch_logical, rho_logical }
```

## 7. Business logic

- **No backend, no auth required** — the screen works fully offline.
- **Trial count** is configurable via `qec_default_trials` in
  `app.properties`; defaults to 100.
- **Surface code** automatically uses the Pauli-frame Monte Carlo path
  (`simulateSurfaceCode`) instead of the density-matrix path.
- **Slider drag** — error-probability slider re-runs simulate on each
  release; the value-changed callback is throttled by the underlying
  uislider behaviour.
- **AppState** is **not** consulted; nothing here depends on auth or
  project context.

## 8. Reference

- Screen: `src/presentation/screens/QecSimulationScreen.m`
- ViewModel: `src/presentation/viewmodels/QecSimulationViewModel.m`
- Service: `src/domain/services/QecEngineService.m`
- Conceptual primer: [`qec-overview.md`](qec-overview.md)
