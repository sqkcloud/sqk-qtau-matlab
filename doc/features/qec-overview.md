# Quantum Error Correction (QEC) — Overview

This is the conceptual overview shared by the two QEC operator surfaces:
[`qec-simulation.md`](qec-simulation.md) and
[`qec-visualization.md`](qec-visualization.md).

## 1. What it is

Quantum Error Correction encodes a single **logical qubit** into many
**physical qubits** so that local errors can be detected via syndrome
measurements and corrected before they accumulate into a logical
error. QDash ships a **client-side** density-matrix QEC simulation
engine (no backend HTTP) covering the canonical small codes plus a
Monte-Carlo Pauli-frame surface code simulator for d=3 surface codes.

## 2. Purpose

- **Pedagogy** — walk operators / students through how a QEC code
  catches errors. The Visualization screen renders 3D Bloch-sphere
  trajectories, surface-code lattices, and error propagation animations.
- **Cost intuition** — a logical qubit at today's hardware costs
  ~1 000 physical qubits. The Simulation screen lets the operator pick
  a code (3-qubit bit-flip up to d=3 surface), pick a noise model and
  error rate, and see the logical fidelity vs the unprotected baseline.
- **Sanity-check** future hardware planning — when does it pay to use a
  9-qubit Shor code over a 3-qubit repetition code? When does the
  surface code's threshold theorem kick in?

## 3. Codes implemented (`QecEngineService.simulate`)

| Code | Physical qubits | Protects against | Notes |
|------|-----------------|------------------|-------|
| `bitflip3`   | 3 | X errors | Repetition code, single-error correcting |
| `phaseflip3` | 3 | Z errors | H-conjugated repetition code |
| `shor9`      | 9 | Arbitrary single-qubit error | Concatenated bit + phase flip |
| `steane7`    | 7 | Arbitrary single-qubit error | CSS code, transversal Cliffords |
| `perfect5`   | 5 | Arbitrary single-qubit error | Perfect (smallest distance-3) code |
| `surface`    | 9 (d=3) | Arbitrary local errors | Topological code; Monte Carlo simulator |

## 4. Noise channels

| Model | Kraus operators |
|-------|-----------------|
| `bitflip` | `√(1−p)·I, √p·X` |
| `phaseflip` | `√(1−p)·I, √p·Z` |
| `depolarizing` | `√(1−p)·I, √(p/3)·X, √(p/3)·Y, √(p/3)·Z` |
| `amplitude_damping` | Standard T₁ relaxation channel |

## 5. Algorithm

For non-surface codes (`bitflip3` / `phaseflip3` / `shor9` / `steane7` /
`perfect5`), the simulation is **density-matrix** based:

```
ψ₀  → encode → ρ_encoded
                │
                │ for round = 1..nRounds:
                │   apply noise channel  (ρ → Σ K_i ρ K_i†)
                │   extract syndrome     (project onto stabiliser ±1 eigenspaces)
                │   apply correction     (Pauli flip indicated by syndrome)
                │
                ▼
   decode logical → ρ_logical
   F = Tr( |ψ₀⟩⟨ψ₀| · ρ_logical )    # logical fidelity
```

The simulator runs `nTrials` (default 100) per call to estimate the
**logical-error rate** as `1 − P(F > 0.99)`.

For the surface code the engine switches to **stochastic Pauli-frame**
simulation (`simulateSurfaceCode(d=3, p, 500)`) which is the textbook
Monte Carlo approach used to compute the threshold.

## 6. Outputs

`QecEngineService.simulate` returns a struct:

```
{
  fidelity:             float,   # logical fidelity after correction
  unprotected_fidelity: float,   # baseline (1 physical qubit, same noise)
  syndromes:            map<bitstring → count>,  # syndrome histogram
  bloch_logical:        [rx, ry, rz],            # final Bloch vector
  rho_logical:          2x2 complex,             # final density matrix
  n_trials, n_rounds, code, noise, p             # echoed input
}
```

## 7. Why client-side

QEC simulation is small (≤ 9 qubits → 2⁹ = 512-dim Hilbert space; for
d=3 surface code the active stabiliser group is ~2⁸) so MATLAB can run
it on the laptop without an HTTP round-trip. This avoids saturating the
backend with pedagogy traffic and keeps the simulation interactive
(slider drag → instant re-render).

## 8. Reference

- Service: `src/domain/services/QecEngineService.m` (constants, `simulate`,
  `simulateSurfaceCode`, `encode`, `extractAndCorrect`, `decodeLogical`,
  `fidelity`, `blochVector`, `applyNoiseChannel`)
- Operator surfaces:
  [`qec-simulation.md`](qec-simulation.md),
  [`qec-visualization.md`](qec-visualization.md)
