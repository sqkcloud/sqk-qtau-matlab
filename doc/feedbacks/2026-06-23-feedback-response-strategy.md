# QTau MATLAB Toolbox — Response to MathWorks Review

**Date:** 2026-06-23
**Audience:** internal, prep for the MathWorks meeting next week
**Source feedback:** [`feedback.md`](./feedback.md)
**Companion design:** [`../superpowers/specs/2026-06-23-matlab-quantum-bridge-design.md`](../superpowers/specs/2026-06-23-matlab-quantum-bridge-design.md)

---

## 1. The position (headline for the meeting)

> **Your circuit, your data, and your results never leave MATLAB.** The workbench adds
> the production layer the Support Package does not have — backend selection, fidelity
> prediction, mitigation planning, QEC, job monitoring, reporting — sitting **on top of the
> `quantumCircuit` objects you already build in MATLAB.**

That sentence converts the reviewer's sharpest critique ("what advantage over a web/Python
interface?") into the value proposition. Today the app cannot say it, because the MATLAB-native
data path does not exist. Phase 1 builds it.

### One backbone, concentric audiences

The reviewer reads our four target users as four feature-sets — i.e. sprawl. The reframe: **four
audiences, one backbone.** The backbone is the thing every audience shares — *MATLAB-native
objects and data in, results back to MATLAB.* Add it and the breadth becomes layers, not sprawl.

| Layer | Audience | Role in the narrative |
|---|---|---|
| **Backbone** | — | MATLAB QC Support Package bridge: `quantumCircuit` in · native `simulate()` · results → workspace |
| Tier 0 | MATLAB quantum researchers | Credibility + lowest-friction integration. Directly answers "no Support-Package linkage" |
| Flagship | Quant-finance / QMC | The demoable killer vertical — MATLAB data → QAE → results back. Defensible moat |
| Growth | Domain scientists · educators | On-ramp + teaching, same backbone, no new infrastructure |

The answer to "simplify / prioritize" is therefore **not** "cut features" — it is "give the breadth a
center of gravity."

---

## 2. Verified findings (what is actually true in the code)

Checked against the repository before drafting this response:

- **No linkage to the MATLAB Quantum Computing Support Package — confirmed true.** The only
  MATLAB-native simulator is the hand-rolled `src/domain/services/StatevectorSimulator.m`. Zero
  references to `quantumCircuit` / `generateQASM` / Support-Package gate functions. The only
  `QuantumCircuit` references are Python (Qiskit) code generation.
- **Export targets are external-only — confirmed.** QASM 2/3, Qiskit, Cirq, Braket. No MATLAB target.
- **Prediction and Run Planner overlap — confirmed.** Run Planner already calls the prediction
  service internally.
- **Templates exist but are not discoverable.** The Composer ships a 12-template gallery; the
  reviewer never saw it. This is a discoverability/auth-gate problem, not a missing feature.
- **Auth gate blocks exploration — confirmed.** An `AuthOverlay` covers the content area whenever
  no backend token is present, so nothing is explorable offline.

---

## 3. Point-by-point response (what we say to each item)

| Their point | Our response |
|---|---|
| UI polish · packaging · Add-On Explorer · built-in docs | Acknowledge, thank, keep as-is |
| Couldn't explore without auth | **Agree — fixing.** Decouple MATLAB-native paths (build / import / simulate / templates / export) from login → offline mode. Sandbox/demo login for backend-only features |
| Motivation for MATLAB unclear | The position in §1 + a concrete `quantumCircuit` round-trip demo |
| No MATLAB data import path | **Adding.** `quantumCircuit` objects from the workspace (Phase 1); `.mat` / tables (Phase 2) |
| Export targets external-only | **Adding** a MATLAB export target (`quantumCircuit` constructor script) + push-results-to-workspace |
| No Support-Package linkage | **The backbone.** Accept `quantumCircuit`, use native `simulate()`, interoperate with `generateQASM()` |
| Local sim = separate infra | **Adding** native `simulate()` as the authoritative final-state/counts engine; keep the hand-rolled simulator only where it adds value (per-step Inspect animation, reset handling) |
| Templates not visible | Discoverability fix — surface on landing / empty-state, gate-free; also ship as example Live Scripts |
| Clarify use cases / simplify | The layered positioning (§1); progressive disclosure hides advanced tabs by default |
| Prediction ↔ Run Planner overlap | **Consolidate** — fold Prediction in as Run Planner's first step (Prediction = "what fidelity?"; Run Planner = "cheapest config that hits target F") |
| Qiskit/Cirq/Braket export rationale | Articulate: collaboration + downstream execution on platform-specific SDKs/hardware. **Demote** to "Advanced export"; lead with MATLAB + QASM. Keep (cheap), stop foregrounding |

---

## 4. Prioritized roadmap

- **Phase 1 — MATLAB Quantum Bridge (the spine).** Import workspace `quantumCircuit`; native
  `simulate()` engine + parity badge; export `quantumCircuit` script; push results to the
  workspace; auth-decouple the native paths. **This is the spec written alongside this memo.**
- **Phase 2 — Flagship QMC-on-MATLAB-data vertical** + `.mat`/table import + `generateQASM`
  passthrough (richer circuits) and QASM-3 parser support.
- **Phase 3 — UX simplification** (low-effort, high-signal): templates discoverability, progressive
  disclosure, Prediction↔Run Planner merge, export demotion. *Candidates to pull forward as quick
  wins to show momentum at the meeting.*
- **Phase 4 — Polish:** example Live Scripts, sandbox/demo mode for backend features.

---

## 5. One technical trap worth knowing before the meeting

The reviewer suggested importing via `circuit.generateQASM()`. We verified that `generateQASM`
emits **OpenQASM 3.0** (`qubit[2] q;` / `bit[2] c;` / `c = measure q`), while the app's existing
QASM importer is a strict **OpenQASM 2.0** parser — it would reject the 3.0 register and
measurement syntax. So Phase 1 imports `quantumCircuit` objects **directly** (reading
`gate.Type` / `ControlQubits` / `TargetQubits` / `Angles`), which is more robust and gives
gate-level error messages; the `generateQASM` interop path is added in Phase 2 with a QASM-3-aware
parser. We can present this as evidence we engaged with the suggestion at the API level.
