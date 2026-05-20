# QEC Visualization

See also: [`qec-overview.md`](qec-overview.md) for the conceptual primer
on codes and noise models.

## 1. What it is

The QEC Visualization screen renders three interactive 3D / 2D pedagogy
views of an error-correction simulation: a Bloch-sphere trajectory
showing the logical qubit drifting under noise, a surface-code lattice
showing data qubits + ancilla measurements, and an error-propagation
animation that highlights how a single physical error spreads through
the code.

## 2. Purpose

- **Build intuition** for what error correction *does*: errors take
  the logical state away from the Bloch sphere's surface; correction
  pulls it back. The 3D animation makes this concrete in a way a
  fidelity number can't.
- **Show stabiliser geometry** for the surface code: where the X- and
  Z-stabiliser ancilla qubits sit, which data qubits each one measures.
- **Demonstrate error propagation** through entangling gates, which is
  the core reason a code's distance limits its correctable error
  weight.

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Screen | `QecVisualizationScreen` | `src/presentation/screens/QecVisualizationScreen.m` |
| ViewModel | `QecVisualizationViewModel` | `src/presentation/viewmodels/QecVisualizationViewModel.m` |
| Service | `QecEngineService` (reused for the simulation backbone) | `src/domain/services/QecEngineService.m` |
| Backend | None — fully local | n/a |

## 4. Algorithm / rendering

### Bloch-sphere trajectory

Each round of (noise → syndrome → correction) appends a point to a
trajectory list of `[rx, ry, rz]` Bloch vectors derived from
`QecEngineService.blochVector(rho_logical)`. The screen plots:

- A unit sphere wireframe (axes + meridians).
- The trajectory as a poly-line from the initial state to the final
  state.
- Markers at each round so the operator can step through.

### Surface-code lattice

For a `d × d` surface code (default d=3), the screen draws a 2D grid:

- Data qubits at every site.
- X-stabiliser ancilla on alternating plaquettes (red).
- Z-stabiliser ancilla on the complementary plaquettes (blue).
- Edges connect each ancilla to the four data qubits it measures.

Active syndromes from the most recent simulation are highlighted
(filled markers vs hollow).

### Error-propagation animation

For a chosen single-qubit Pauli error (`X` or `Z` on a configurable
data qubit), the screen animates how the error spreads through the
encoded state under the code's stabilisers:

- t=0 — error injected.
- t=1..n — error commutes / anticommutes with each stabiliser; the
  animation marks every stabiliser whose syndrome flips.

## 5. Workflow

1. Open **QEC Visualization**.
2. Pick a code (Bloch-sphere mode supports any small code; lattice
   mode requires `surface`).
3. Pick a noise model + error rate (or use defaults from a recent
   Simulation run if `app.State.lastQecResult` is set).
4. Click **Animate** — VM runs simulate, accumulates trajectory points,
   then steps through the animation at a configurable speed.
5. **Stabiliser inspector** — click any ancilla to see which data
   qubits it measures and its current syndrome bit.

## 6. Data flow

```
QEC Visualization screen  ──→  QecEngineService.simulate(...)
                              (client-side, same engine as Simulation)
                          ←─  { rho_logical, bloch_logical, syndromes, ... }

For multi-round trajectories:
  loop nRounds × {
      QecEngineService.applyNoiseChannel + extractAndCorrect
      → append blochVector(rho_logical) to trajectory
  }
```

## 7. Business logic

- **No backend, no auth required** — fully local.
- **Lattice mode is surface-only** — other codes don't have a 2D
  geometric realisation; the lattice view greys out / hides for them.
- **Animation speed** — adjustable via a slider; the underlying
  trajectory is precomputed so the slider just throttles the playhead.
- **Reset** — restores the trajectory to t=0 without recomputing.

## 8. Reference

- Screen: `src/presentation/screens/QecVisualizationScreen.m`
- ViewModel: `src/presentation/viewmodels/QecVisualizationViewModel.m`
- Service: `src/domain/services/QecEngineService.m`
- Conceptual primer: [`qec-overview.md`](qec-overview.md)
