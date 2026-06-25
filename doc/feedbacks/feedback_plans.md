# QTau MATLAB Toolbox — Feedback Resolution Plan & Schedule

**Date:** 2026-06-25
**Source feedback:** [`feedback.md`](./feedback.md)
**Strategy memo:** [`2026-06-23-feedback-response-strategy.md`](./2026-06-23-feedback-response-strategy.md)
**Phase-1 design:** [`../superpowers/specs/2026-06-23-matlab-quantum-bridge-design.md`](../superpowers/specs/2026-06-23-matlab-quantum-bridge-design.md)
**Phase-1 plan:** [`../superpowers/plans/2026-06-23-matlab-quantum-bridge.md`](../superpowers/plans/2026-06-23-matlab-quantum-bridge.md)

This document maps **every** MathWorks feedback item to a concrete solution, records what is already shipped, and gives a detailed effort + calendar schedule for the remainder.

---

## 1. Status legend & assumptions

| Mark | Meaning |
|------|---------|
| ✅ Done | Implemented on `feature/feedback` (PR open against `main`) |
| 🟡 Partial | Capability shipped; a follow-up surface/polish remains |
| ⏳ Planned | Designed, scheduled below, not yet built |
| 💬 Narrative | Addressed by positioning/communication (no code) |

**Scheduling assumptions** (calendar shifts if these change):
- **1 primary engineer**, 5-day weeks. Effort is also given in **dev-days** (resourcing-independent) so a second engineer can parallelize independent tasks.
- Implementation resumes **Mon 2026-06-30** (after the review meeting).
- Each phase carries a **~20% buffer** for test/review/doc/integration (the subagent-driven review gates used in Phase 1).
- "Done" items were built this session; their effort is shown for reference only.

---

## 2. The unifying solution (why these fixes hang together)

The feedback reduces to one root cause: **the toolbox had no MATLAB-native center of gravity** — circuits and results never touched the MATLAB workspace, so it read as a web/Python client wearing a MATLAB skin. The fix is one backbone — *MATLAB-native objects/data in, results back to MATLAB* — with the rest of the feedback (templates, simplification, tab overlap, export rationale) layered on top. Phase 1 built the backbone; Phases 2–4 complete the data story and the UX.

---

## 3. Feedback → Solution matrix (every item)

### 3.1 Overall Feedback and Direction

| # | Feedback item | Solution | Status | Phase |
|---|---------------|----------|:------:|:-----:|
| O1 | UI polished; design/spec/architecture well thought out | Maintain; keep the clean-architecture conventions | ✅ (no action) | — |
| O2 | Packaging, Add-On Explorer integration, built-in docs are good | Maintain; extend docs with new MATLAB-interop pages | 🟡 | 4 |
| O3 | Couldn't explore the app without server authentication | Decouple MATLAB-native paths from login: **Composer reachable offline**, "Explore offline" entry on Projects screen, auth overlay gated per screen | ✅ | 1 |
| O3b | …extend offline exploration to backend-backed screens | **Sandbox/demo mode** so reviewers can browse Backends/Jobs/etc. without real credentials | ⏳ | 4 |
| O4a | Motivation for MATLAB unclear; should fit a MATLAB-centric workflow | Positioning: *"your circuit, data, and results never leave MATLAB"*; one backbone, concentric audiences (researchers → quant-finance → domain/education) | 💬 + ✅ | 1 |
| O4b | No clear pathway for importing MATLAB **data** | (i) Import workspace `quantumCircuit` objects — done. (ii) Import `.mat`/`table`/numeric data into parametric circuits — planned | 🟡 | 1 / 2 |
| O4c | Export targets are external (Python/JSON/QASM), not "continue in MATLAB" | **MATLAB (`quantumCircuit`) export target** + **Push-to-workspace** action | ✅ | 1 |
| O4d | Not obvious what advantage over web/Python | The `quantumCircuit` round-trip demo + positioning narrative; reinforced by the QMC-on-MATLAB-data flagship vertical | 🟡 (narrative ✅; flagship ⏳) | 1 / 2 |
| O5a | No clear linkage to the MATLAB Quantum Computing Support Package | **`MatlabQuantumBridge`** service — the only module touching Support Package API | ✅ | 1 |
| O5b | Inputs limited to QASM or in-app circuits | Import any base-workspace `quantumCircuit` into the Composer (gate-type mapping, 0↔1 index shift) | ✅ | 1 |
| O5c | Local simulation relies on separate infrastructure, not MATLAB QC | Native `simulate()` as authoritative engine + per-qubit parity flash; hand-rolled simulator retained only for per-step Inspect animation & `reset` | ✅ | 1 |
| O5d-i | Interop: import circuits created in MATLAB | Same as O5b | ✅ | 1 |
| O5d-ii | Interop: use MATLAB's built-in circuit simulation | Same as O5c | ✅ | 1 |
| O5d-iii | Interop: use MATLAB tooling to generate QASM (`circuit.generateQASM()`) | **`generateQASM` passthrough** + OpenQASM-3 parser (lets richer MATLAB circuits — gates outside the Composer palette — flow in via MATLAB's own QASM 3.0 output) | ⏳ | 2 |

> **Why O5d-iii is Phase 2, not 1:** verified that `generateQASM` emits **OpenQASM 3.0** (`qubit[N] q;` / `c = measure q`), which the app's strict **2.0** parser rejects. Phase 1 imports `quantumCircuit` objects **directly** (more robust, gate-level errors); the `generateQASM` route is the additive path for gates the Composer palette doesn't model.

### 3.2 Specific Design Feedback

| # | Feedback item | Solution | Status | Phase |
|---|---------------|----------|:------:|:-----:|
| S1 | Pre-built circuit templates not clearly visible | Templates already exist (12-template gallery in Composer). Fix **discoverability**: surface on landing/empty-state, gate-free; ship example **Live Scripts** | 🟡 (exist; surfacing ⏳) | 3 / 4 |
| S2a | Wide feature range → complex UX | **Progressive disclosure** — advanced tabs hidden by default behind a use-case/role mode selector | ⏳ | 3 |
| S2b | Clarify which workflows matter most | Positioning (§2): lead with researcher round-trip + quant-finance QMC; document target use cases | 💬 | 1 (memo) |
| S2c | Streamline around high-value use cases | Default the UI to the backbone workflow; demote niche surfaces | ⏳ | 3 |
| S3 | Prediction ↔ Run Planner overlap | **Consolidate** — fold Prediction in as Run Planner's first step (Prediction = "what fidelity?"; Run Planner = "cheapest config that hits target F"). Run Planner already calls the prediction service internally | ⏳ | 3 |
| S4 | Articulate Qiskit/Cirq/Braket export use cases; trim if not central | **Demote** to "Advanced export"; lead with MATLAB + QASM; document the use case (collaboration + downstream execution on platform SDKs). Keep (cheap) but stop foregrounding | ⏳ | 3 |

---

## 3.3 Per-item solution detail (expanded)

Each item below states the **problem**, the **solution mechanism** (concrete code/approach), and **where** it lives. ✅ items reference shipped code on `feature/feedback`; ⏳ items describe the planned approach.

### Overall Feedback and Direction

**O1 — UI / design / architecture are good ✅ (no action).**
No change required. The three-layer clean architecture (screens → view-models → services → `FastAPIClient`) and the externalized config (`AppConfig`/`Labels`) are kept as the working conventions; all new Phase-1 code follows them (e.g., `MatlabQuantumBridge` is a static domain service mirroring `StatevectorSimulator`, and every new string goes through `Labels.get`).

**O2 — Packaging / Add-On Explorer / built-in docs are good 🟡 (extend in Phase 4).**
Maintain the toolbox packaging as-is. The only follow-up is additive: Phase 4 adds MATLAB-interop pages to the built-in documentation (P4.3) so the new import/simulate/export/offline capabilities are discoverable from the Add-On help, and example Live Scripts (P4.1) ship as runnable docs.

**O3 — Couldn't explore without server authentication ✅.**
*Problem:* a global `AuthOverlay` covered the content area whenever no backend token was present, so nothing was usable offline. *Solution:* classification + per-screen gating. `NavigationManager.isOfflineCapable(key)` returns true only for `'Composer'`; `NavigationManager.refreshAuthOverlay(app, key)` hides the overlay when `app.State.isAuthenticated() || isOfflineCapable(key)` and shows it otherwise. The single `OverlayManager.fitAuthOverlay(app)` call inside `onSelectSection` was replaced by `refreshAuthOverlay(app, key)` (the resize-only call in `onResizeUI` was left intact). Net effect: a logged-out user can open the Composer and build/import/simulate/export with no login wall, while backend-backed screens still gate correctly.

**O3b — Extend offline exploration to backend screens ⏳ (Phase 4).**
*Solution:* a **sandbox/demo mode** (P4.2) that serves canned data to Backends/Jobs/Reports so a reviewer can browse those screens without real credentials. Lower priority and independent — it does not block anything.

**O4a — Motivation for delivering in MATLAB unclear 💬 + ✅.**
*Solution (communication):* the positioning headline — *"your circuit, your data, and your results never leave MATLAB"* — with one backbone and concentric audiences (researchers → quant-finance → domain/education). *Solution (code that makes the claim true):* the Phase-1 `quantumCircuit` round-trip (import → edit → simulate → export/push) is the concrete demonstration. Full narrative is in the strategy memo §1.

**O4b — No clear pathway for importing MATLAB data 🟡 (1 / 2).**
*Problem:* two distinct senses of "data" — (i) circuits and (ii) numeric workspace data. *Solution (i), shipped:* `MatlabQuantumBridge.importByName(name)` pulls a base-workspace `quantumCircuit` (via `evalin`) and converts it to the internal `CircuitModel`; the Composer's **Import MATLAB** toolbar button (`onImportFromMatlab` → `openImportDialog`) lists candidates from `listWorkspaceCircuits()` and loads the chosen one with `obj.Model = …; afterModelEdit(...)`. *Solution (ii), Phase 2 (P2.3):* a data-binding layer to import `.mat`/`table`/numeric workspace values as parametric-circuit inputs (e.g., rotation angles, initial states).

**O4c — Export targets are external-only, not "continue in MATLAB" ✅.**
*Problem:* export emitted QASM/Qiskit/Cirq/Braket only — nothing that returns to MATLAB. *Solution:* two new return paths. (1) **MATLAB export target** — `CircuitModel.toMatlabScript` emits a runnable script (`gates = [hGate(1); cxGate(1,2); …]; qc = quantumCircuit(gates, n);`), wired into the export dialog via a `'matlab'` row in `formats` and a `case 'matlab'` in `emitForFormat`. (2) **Push-to-workspace** — the export dialog's `doPushWorkspace` builds the live object with `MatlabQuantumBridge.toQuantumCircuit(model)` and writes it to the base workspace via `pushToWorkspace('qtau_circuit', qc)` (`assignin('base', …)`).

**O4d — Not obvious what advantage over web/Python 🟡 (narrative ✅; flagship ⏳).**
*Solution:* the answer is the round-trip itself (O4b/O4c/O5*) plus the Phase-2 **quant-finance QMC vertical** (P2.4) — import a MATLAB returns `table`, run QAE, push loss-distribution/VaR back to the workspace — which is the demoable, defensible "only-in-MATLAB" story.

**O5a — No linkage to the MATLAB Quantum Computing Support Package ✅.**
*Solution:* a single new service, `src/domain/services/MatlabQuantumBridge.m`, is the **only** module that references Support-Package API (`quantumCircuit`, `simulate`, gate constructors). Everything else reaches the Support Package through it, and degrades cleanly via `MatlabQuantumBridge.isAvailable()` (`exist('quantumCircuit','class')==8`) when the add-on is absent.

**O5b — Inputs limited to QASM or in-app circuits ✅.**
*Solution:* `fromQuantumCircuit(qc)` iterates `qc.Gates`, maps each `gate.Type` to an internal kind via `typeToKind` (e.g. `"si"`→`sdg`, `"ti"`→`tdg`), reads `[ControlQubits TargetQubits]` and shifts MATLAB's 1-based indices to the internal 0-based convention (`−1`), and rebuilds the `CircuitModel` with `addGate`. A workspace `quantumCircuit` is now a first-class input alongside QASM and the in-app palette.

**O5c — Local simulation relies on separate infrastructure ✅.**
*Problem:* local simulation used a hand-rolled `StatevectorSimulator`, not MATLAB's engine. *Solution:* `simulateNative(model)` converts to a `quantumCircuit` and calls MATLAB's native `simulate()`, returning `.Amplitudes` plus per-qubit P(\|0⟩) marginals (`probability(s, q, "0")`). The Composer's Inspect footer runs `flashNativeParity`, which cross-checks those native marginals against the hand-rolled simulator's `(1 + ⟨Z⟩)/2` (from `blochPerQubit`) within `1e-6` and flashes a match/mismatch badge. The hand-rolled simulator is deliberately retained for two things MATLAB's terminal-measurement `simulate` cannot do cheaply: per-step Inspect animation, and circuits containing `reset`. This makes MATLAB's engine the authoritative simulator while keeping the step-through UX.

**O5d-i / O5d-ii — Import MATLAB circuits / use MATLAB's built-in simulation ✅.**
Same mechanisms as O5b (`fromQuantumCircuit`/import dialog) and O5c (`simulateNative`/parity).

**O5d-iii — Use MATLAB tooling to generate QASM (`circuit.generateQASM()`) ⏳ (Phase 2, P2.1).**
*Problem & finding:* the reviewer's literal suggestion is to import via `generateQASM`. Verified on R2025b that `generateQASM` emits **OpenQASM 3.0** (`qubit[N] q;` / `bit[N] c;` / `c = measure q`), which the app's strict **OpenQASM 2.0** parser (`CircuitModel.fromQasm`) rejects at the header and measurement lines. *Solution:* Phase 1 deliberately imports `quantumCircuit` objects **directly** (more robust, gate-level error messages). Phase 2 adds the `generateQASM` route as the *additive* path for circuits whose gates fall outside the 18-gate Composer palette (`u`, `cp`, `rzz`, composite, …): extend `fromQasm` to accept QASM-3 register/measure syntax, and add a bridge fallback that stores MATLAB's `generateQASM` output as the canonical circuit text for such richer circuits.

### Specific Design Feedback

**S1 — Pre-built templates not clearly visible 🟡 (exist; surfacing in Phase 3, Live Scripts in Phase 4).**
*Finding:* the templates are not missing — the Composer already ships a 12-template gallery (`TemplateRegistry` + `openTemplatesDialog`, reachable via the **Templates ▾** toolbar button). The reviewer simply never reached it (blocked partly by the auth wall, now fixed in O3). *Solution:* Phase 3 (P3.1) raises discoverability — surface the gallery on the Composer empty-state/landing with one-click insert, gate-free; Phase 4 (P4.1) additionally ships templates as runnable example Live Scripts.

**S2a — Wide feature range → complex UX ⏳ (Phase 3, P3.2).**
*Solution:* **progressive disclosure.** Introduce a use-case/role mode that, by default, shows only the backbone workflow screens and hides the advanced surfaces (Mitigation Compare, Resource Estimator, Circuit Cutting, QEC) behind a "Show advanced" toggle. Implemented by filtering the `navNames`/`navLabels`/`navIcons` arrays in `NavigationManager` according to the active mode — no screen is removed, only de-emphasized.

**S2b — Clarify which workflows matter most 💬 (strategy memo).**
*Solution (communication):* documented target use cases and the lead workflows (researcher round-trip + quant-finance QMC) in the strategy memo §1; this also drives the P3.2 default-mode choice.

**S2c — Streamline around high-value use cases ⏳ (Phase 3).**
*Solution:* the UI defaults to the backbone workflow (build/import → simulate → analyze → run), with niche surfaces demoted via the same progressive-disclosure mechanism (P3.2) and the export demotion (P3.4).

**S3 — Prediction ↔ Run Planner overlap ⏳ (Phase 3, P3.3).**
*Finding:* the overlap is real and structural — `RunPlannerService` already calls `PredictionService.predict` internally (Run Planner cross-multiplies per-backend base fidelity by per-strategy mitigation cost). *Solution:* **consolidate** — fold Prediction in as Run Planner's first step. Prediction answers *"what fidelity will I get?"*; Run Planner answers *"cheapest config that hits target fidelity F?"* — i.e. Prediction is the input to Run Planner, not a peer. Retire the standalone Prediction tab from the sidebar while keeping its routing key alive for back-compat (same pattern already used for hidden screens like Upload/Notes), so cross-screen calls to `onSelectSection('Prediction')` still resolve.

**S4 — Articulate / trim Qiskit-Cirq-Braket export ⏳ (Phase 3, P3.4).**
*Solution:* keep the emitters (they are cheap and already tested) but **demote** them. Group **MATLAB + QASM** as the primary export targets and collapse Qiskit/Cirq/Braket under an "Advanced export" subgroup in the export dialog's `formats` list; document the genuine use cases (collaboration and downstream execution on platform-specific SDKs/hardware) in the help so the rationale is explicit rather than implied by feature sprawl.

---

## 4. Solution detail by phase

### Phase 1 — MATLAB Quantum Bridge ✅ (shipped this cycle)

Resolves **O3, O4c, O5a, O5b, O5c, O5d-i, O5d-ii** and the narrative half of **O4a/O4d/S2b**.

Delivered (on `feature/feedback`, PR open):
- `MatlabQuantumBridge` static service — `isAvailable`, `to/fromQuantumCircuit`, `simulateNative` (per-qubit parity), `listWorkspaceCircuits`/`importByName`/`pushToWorkspace`.
- `CircuitModel.toMatlabScript` emitter + "MATLAB (quantumCircuit)" export target.
- Composer UI: Import-from-MATLAB picker, Push-to-workspace, native-`simulate` parity flash.
- `NavigationManager`: Composer offline-capable; auth overlay gated per screen; "Explore offline" Welcome entry.
- Tests: `MatlabQuantumBridge` 15, `CircuitModel_export` +5, `NavigationManager` 2 — all green on the live R2025b + Support Package install.

**Reference effort (already spent):** ~6 dev-days equivalent (spec + plan + 6 implementation units + review gates).

### Phase 2 — MATLAB data interop + flagship vertical ⏳

Resolves **O4b (data import), O4d (flagship), O5d-iii, and the deferred results-struct push.**

| Task | Solution | Effort (dev-days) |
|------|----------|:-----------------:|
| P2.1 `generateQASM` passthrough + OpenQASM-3 parser | Extend `CircuitModel.fromQasm` to accept QASM-3 register/measure syntax; add a bridge fallback that stores MATLAB's `generateQASM` output for circuits using gates outside the palette | 4 |
| P2.2 Results-struct push UI | Surface `pushToWorkspace` for simulation/analysis results (counts, statevector, predictions) — the helper exists & is tested; this wires a UI affordance (likely on Results/Inspect) | 1 |
| P2.3 MATLAB data import (`.mat` / `table` / numeric) | Import workspace data as inputs to parametric circuits (angles, initial states); a small data-binding layer + picker | 4 |
| P2.4 Quant-finance QMC flagship vertical | End-to-end demo: import a MATLAB price/returns `table` → parametric QMC circuit → QAE run → loss-distribution/VaR results pushed back to the workspace; the defensible "why MATLAB" showcase | 7 |
| | **Subtotal** | **16** |

### Phase 3 — UX simplification & consolidation ⏳

Resolves **S1 (surfacing), S2a, S2c, S3, S4.**

| Task | Solution | Effort (dev-days) |
|------|----------|:-----------------:|
| P3.1 Templates discoverability | Surface the 12-template gallery on the Composer empty-state/landing; one-click insert; gate-free | 3 |
| P3.2 Progressive disclosure | Use-case/role mode that hides advanced tabs by default; "Show advanced" toggle | 4 |
| P3.3 Prediction ↔ Run Planner consolidation | Merge Prediction into Run Planner as step 1; retire the standalone Prediction tab (keep routing key for back-compat) | 4 |
| P3.4 Export rationalization | Group MATLAB + QASM as primary; collapse Qiskit/Cirq/Braket under "Advanced export"; document use cases | 2 |
| | **Subtotal** | **13** |

### Phase 4 — Polish, docs & access ⏳

Resolves **O2 (docs extension), O3b (sandbox), S1 (Live Scripts).**

| Task | Solution | Effort (dev-days) |
|------|----------|:-----------------:|
| P4.1 Example Live Scripts | Teaching/onboarding `.mlx` walkthroughs (build → simulate → analyze → report) shipped with the toolbox | 3 |
| P4.2 Sandbox/demo mode | Let reviewers browse backend-backed screens (Backends/Jobs/Reports) against canned data without real credentials | 5 |
| P4.3 Docs extension | Add MATLAB-interop pages to the built-in documentation | 2 |
| | **Subtotal** | **10** |

---

## 5. Schedule — 2-week target

The full phased plan above totals **~39 dev-days (~9 weeks, 1 engineer)**. To meet a **1-engineer / 2-week** target, the work is split into a **2-week sprint** (the cheap, high-signal items in *minimal* form) and a **deferred backlog** (the two large pieces + soft UX/polish). The compression is **scope reduction, not faster estimates** — see the trade-offs in §5.3.

### 5.1 Two-week sprint (1 engineer, start Mon 2026-06-30)

| # | Sprint item | Feedback | Minimal scope | Days |
|---|-------------|:--------:|---------------|:----:|
| 1 | Results push UI | O4 (AC gap) | wire the existing `pushToWorkspace` helper to a Results/Inspect button | 1 |
| 2 | Export demotion | S4 | regroup the export `formats` list (MATLAB+QASM primary, rest "Advanced") + 1 doc paragraph | 1 |
| 3 | Templates on empty-state | S1 | surface the existing 12-template gallery on the Composer empty-state; no new authoring | 1.5 |
| 4 | Prediction → Run Planner (minimal) | S3 | retire the Prediction tab (keep routing key); reuse the existing predict call as Run Planner step 1 | 2 |
| 5 | generateQASM import (MATLAB subset) | O5d-iii | accept *only* the OpenQASM-3 header/measure subset MATLAB emits → existing gate-map; not a general QASM-3 parser | 2 |
| | **Build subtotal** | | | **7.5** |
| | + test / review / integration buffer | | | ~2.5 |
| | **Sprint total** | | | **~10 (≈ 2 weeks)** |

### 5.2 Day-by-day calendar

```
Day  Date          Task
───  ────────────  ──────────────────────────────────────────────
 1   Mon Jun 30    #1 results push UI  +  #2 export demotion (start)
 2   Tue Jul 01    #2 export demotion (finish)  +  #3 templates (start)
 3   Wed Jul 02    #3 templates empty-state (finish)
 4   Thu Jul 03    #4 Prediction -> Run Planner (start)
 5   Fri Jul 04    #4 Prediction -> Run Planner (finish + test)
 6   Mon Jul 07    #5 generateQASM import (build)
 7   Tue Jul 08    #5 generateQASM import (finish + test)
 8   Wed Jul 09    integration + full test pass
 9   Thu Jul 10    review fixes + inline doc notes
10   Fri Jul 11    buffer / demo prep
```

**1-engineer sprint finish: ~Fri 2026-07-11.**

### 5.3 What the sprint defers (trade-offs)

| Deferred item | Feedback | Days | Why it's safe to defer |
|---------------|:--------:|:----:|------------------------|
| QMC flagship vertical | O4d | 7 | O4d still answered by the shipped round-trip + generateQASM interop. **Swap-in:** a *thin* QMC demo (workspace vector → existing QMC popup → push results) ≈ 2–3d can replace one sprint item if the finance showcase is a priority. |
| `.mat` / table data import | O4b | 4 | O4b's circuit-import half is already shipped; numeric data-binding is additive |
| Progressive disclosure | S2 | 4 | S2 direction is set by the positioning memo; the UI toggle is polish |
| Sandbox / demo mode | O3b | 5 | Independent, no dependents; offline Composer already unblocks exploration |
| Example Live Scripts | S1 | 3 | Gallery surfacing (sprint #3) covers the core S1 ask |
| Built-in docs extension | O2 | 2 | These feedback docs + inline notes cover it interim |
| Full general QASM-3 parser | O5d-iii | ~2 | Sprint #5 handles MATLAB's emitted subset; arbitrary QASM-3 is rarely needed |

**Deferred backlog total ≈ 25–27 dev-days.**

### 5.4 Sequencing notes

- **Front-load #1 + #2** (1-day wins) for immediate momentum and a quick demoable diff.
- **#4 (Prediction↔Run Planner)** edits shared view-model/lookup code — keep it isolated from #3 to avoid merge churn.
- **#5 (generateQASM)** reuses the existing direct gate-map; only QASM-3 header/measure recognition is new, which bounds the risk.

---

## 6. Risks & dependencies

| Risk | Mitigation |
|------|-----------|
| `generateQASM` emits gates outside the Composer palette → import fails | P2.1 stores the raw QASM-3 as canonical text for such circuits (read-only beyond the palette) rather than forcing a full canvas render |
| QMC vertical scope creep (P2.4) | Time-box to one end-to-end happy path (table → QAE → workspace); defer extra instruments to a later cycle |
| Prediction↔Run Planner merge breaks existing flows (P3.3) | Keep the `Prediction` routing key alive for back-compat; migrate behind the merged view; full test pass before retiring the tab |
| Support Package not installed on a user's machine | Already handled — every native path guards on `MatlabQuantumBridge.isAvailable()` and degrades with a hint |
| MATLAB headless test flakiness (parallel pool) | Known: `test_AsyncRunner` flakes under full-suite batch but passes isolated; run affected suites by name in CI |

---

## 7. Summary

- **Backbone shipped (Phase 1, ~6 dev-days):** the highest-leverage feedback — no Support-Package linkage, no MATLAB data path, external-only export, auth wall — is **resolved**.
- **2-week sprint (~10 dev-days, 1 engineer, finish ≈ 2026-07-11):** ships the cheap high-signal items in *minimal* form — results push (O4), export demotion (S4), templates surfacing (S1), Prediction↔Run Planner merge (S3), generateQASM import (O5d-iii). See §5.1.
- **Deferred backlog (~25 dev-days):** QMC flagship (O4d), `.mat`/table import (O4b), progressive disclosure (S2), sandbox (O3b), Live Scripts (S1), docs (O2). The QMC flagship is the main trade-off — a thin 2–3d demo can swap into the sprint if the finance showcase is a priority.
- Every feedback bullet is still tracked in §3; nothing is dropped — the large items are **parked, not abandoned**.
