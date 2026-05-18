# Analysis

## 1. What it is

The Analysis screen runs **circuit feature extraction** (qubits, depth,
2Q-gate count, gate composition, T-count, fidelity estimate) against a
selected circuit, computes **structural similarity** to QTAUBench
reference circuits, and renders a complexity landscape. It is also the
launchpad for the **Quantum Monte Carlo** popup
([`quantum-monte-carlo.md`](quantum-monte-carlo.md)) and the
**Quantum Error Mitigation** popup
([`quantum-error-mitigation.md`](quantum-error-mitigation.md)).

## 2. Purpose

- Give operators a one-click way to characterize an arbitrary uploaded
  circuit (qubits, depth, what gates dominate).
- Find the closest QTAUBench peers so an unknown circuit gets framed
  against well-characterised benchmark structures (Bell, GHZ, QFT,
  VQE, QAOA, etc.).
- Provide entry points to the two heaviest-weight workloads in the
  app — QMC and QEM — without making them top-level screens.

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Screen | `AnalysisScreen` | `src/presentation/screens/AnalysisScreen.m` |
| ViewModel | `AnalysisViewModel` | `src/presentation/viewmodels/AnalysisViewModel.m` |
| Service | `CircuitService` (analyze + getCircuit), `BenchmarkService` (classification + matches) | `src/domain/services/` |
| Backend router | `circuits` (`/api/circuits/{id}/analyze`), `benchmark/classify` | `qdash/api/routers/` |

## 4. Algorithm

### Circuit feature extraction

`POST /api/circuits/{id}/analyze` parses the circuit's gate-graph and
returns:

- Qubit count, depth, total gate count.
- Per-gate-type counts: `{ h, x, y, z, s, t, cx, ccx, ... }`.
- 2Q ratio = (2-qubit gates) / (total gates).
- T-count.
- Estimated fidelity from a NISQ noise model (1Q: 0.1 %, 2Q: 1 %,
  meas: 2 %).
- Structural fingerprint used by similarity matching.

### Similarity matching

`AnalysisViewModel.applyBenchmarkMatches` ranks the QTAUBench library
by structural similarity to the active circuit; top matches populate
the Match Profile sidebar.

### Complexity landscape

`buildQVHeatmap` plots width × depth vs fidelity, with the active
circuit highlighted. Annotates the regime (small / mid / utility-scale).

## 5. Workflow

1. Open **Analysis**.
2. Pick a circuit from the toolbar dropdown — auto-fetches via
   `CircuitService.getCircuit`.
3. `onEnter` triggers `POST /api/circuits/{id}/analyze` async.
4. Feature panel populates: qubits / depth / 2Q ratio / T-count.
5. Match Profile sidebar lists top-N QTAUBench peers with similarity
   scores.
6. Complexity landscape highlights the circuit's `(width, depth)`.
7. **Run Analyze** button re-runs feature extraction.
8. **Quantum Monte Carlo Simulation** opens the QMC popup.
9. **Quantum Error Mitigation Analysis** opens the QEM popup.
10. **Open in Detailed Analysis** bridges to the Detailed Analysis
    screen with the same circuit pre-selected.

## 6. Data flow

```
GET  /api/circuits                                    (dropdown)
GET  /api/circuits/{id}                               (selected circuit)
POST /api/circuits/{id}/analyze                       (feature extraction)
GET  /api/benchmark/classify/{id}?project_id=…        (QV depth class)

QMC popup → /api/circuits/{id}/qae/* (see quantum-monte-carlo.md)
QEM popup → /api/mitigation/*       (see quantum-error-mitigation.md)
```

## 7. Business logic

- **Circuit selection** is sticky across navigation via
  `app.State.selectedCircuitId` / `selectedCircuitName`.
- **Auto-fetch** — `onEnter` runs on tab open via NavigationManager
  `autoLoadScreen`.
- **Async + loading overlay** — every fetch goes through
  `runAsyncWithLoading` (see [`architecture.md`](architecture.md) §2).
- **Modal popups** — both QMC and QEM are separate `uifigure`s; the
  ActivityOverlay re-parents to whichever modal is open.

## 8. Reference

- Screen: `src/presentation/screens/AnalysisScreen.m`
- ViewModel: `src/presentation/viewmodels/AnalysisViewModel.m`
- QMC: [`quantum-monte-carlo.md`](quantum-monte-carlo.md)
- QEM: [`quantum-error-mitigation.md`](quantum-error-mitigation.md)
