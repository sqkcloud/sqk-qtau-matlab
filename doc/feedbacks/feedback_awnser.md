We’ve reviewed the QTau MATLAB Toolbox and I want to share our feedback ahead of our meeting next week.

In summary, you’ve done a lot of good work and it looks very good, but we think there could be some improvements to strengthen its utility within the MATLAB ecosystem.

See the feedback below. I’m looking forward to our conversation next week.

> **Status legend:** **Done** = shipped on `feature/feedback` (PR open). **2-week sprint** = in the 1-engineer / 2-week plan below. **Deferred** = fast-follow backlog (larger or softer items, parked to hit the 2-week target). Effort in **man-days**.
>
> **2-week sprint = ~7.5 build-days + buffer ≈ 10 working days.** It ships the cheap, high-signal items (S1, S3, S4, the `generateQASM` interop the reviewer asked for, and the results-push gap-closer). The two large pieces — the **QMC flagship vertical (7d)** and the **`.mat`/table data-import layer (4d)** — plus soft UX (progressive disclosure, Live Scripts, sandbox) are **deferred** to fit the window. Trade-off: the *demoable* finance advantage (O4d) leans on the QMC flagship, so it slips; the round-trip + generateQASM still answer O4d. A *thin* QMC demo (~2–3d) can be swapped in for one sprint item if the flagship matters more.

# Overall Feedback and Direction

- The UI looks polished, and the overall organization of the design, specifications, and architecture appears well thought out.
>>> Answer: Thank you — no change required. We keep the three-layer clean architecture (screens → view-models → services → HTTP gateway) and externalized config (`AppConfig`/`Labels`) as working conventions; all new code follows them.
>>> **Effort: 0 man-days** (no action).

- The toolbox packaging and repository are well done:
    - Integration with the Add-On Explorer works well.
    - Built-in documentation is a positive and important feature.
>>> Answer: Maintained as-is. Additive follow-up: extend the built-in documentation with pages covering the new MATLAB-interop capabilities (import / simulate / export / offline).
>>> **Effort: ~2 man-days — Deferred** (docs extension; the new features are already documented in these feedback docs).

- I couldn’t fully explore the app without server authentication.
>>> Answer: **Done.** The Composer is now reachable offline — `NavigationManager.isOfflineCapable('Composer')` + `refreshAuthOverlay(app,key)` show the login overlay only when logged-out *and* the screen needs the backend; an "Explore offline" entry on the Projects screen routes straight in. You can now build / import / simulate / export with no login. Optional follow-up: a sandbox/demo mode so the backend-backed screens (Backends, Jobs, Reports) are browsable without real credentials.
>>> **Effort: ~2 man-days delivered** (Phase 1); sandbox mode **~5 man-days — Deferred** (optional).

- It would be helpful to further clarify the motivation for delivering this functionality within MATLAB:
    - Third-party MATLAB apps are typically most compelling when they integrate into an existing MATLAB-centric workflow (e.g., data processing, analysis, visualization).
    - The connection to the broader MATLAB workflow is not yet clear:
        - There does not appear to be a clear pathway for importing MATLAB data.
        - Export capabilities primarily target external formats (Python, JSON, QASM), rather than enabling continued work within MATLAB.
    - As a result, it is not yet obvious what advantages this approach provides over a web-based or Python-based interface.
>>> Answer: Positioning: *your circuit, your data, and your results never leave MATLAB.* **Done:** a MATLAB (`quantumCircuit`) export target (`CircuitModel.toMatlabScript`) plus a Push-to-workspace action. **Sprint:** a results-push UI so simulation/analysis outputs (counts, statevector) also flow back to the workspace — closes the one open acceptance gap. **Deferred:** numeric `.mat`/`table` data import and the quant-finance QMC flagship vertical (the strongest demoable advantage over web/Python).
>>> **Effort: export+push delivered** (Phase 1); results-push UI **~1 man-day — 2-week sprint**; data import **~4** + QMC flagship **~7 man-days — Deferred**.

- Strengthening integration with existing MATLAB quantum computing functionality would clarify the position of this app within the MATLAB ecosystem:
    - Currently, there is no clear linkage to the MATLAB Quantum Computing Support Package.
    - Inputs appear limited to QASM or circuits constructed directly in the app.
    - Local simulation seems to rely on separate infrastructure rather than MATLAB’s QC capabilities.
    - It would be valuable to support interoperability, for example:
        - Importing circuits created in MATLAB.
        - Using MATLAB’s built in circuit simulation
        - Using MATLAB tooling to generate QASM internally (e.g., via circuit.generateQASM()).
>>> Answer: **Done.** A new `MatlabQuantumBridge` service is the single point of integration with the MATLAB Quantum Computing Support Package: it **imports** a workspace `quantumCircuit` into the Composer (gate-type mapping, 1-based↔0-based index shift) and runs MATLAB's **native `simulate()`** as the authoritative engine, with a per-qubit parity check in the Inspect footer. The hand-rolled simulator is retained only for per-step animation and `reset`. **Sprint:** add the `circuit.generateQASM()` import path — handling the exact OpenQASM-3 header/measure subset MATLAB emits (a full general QASM-3 parser is deferred).
>>> **Effort: ~4 man-days delivered** (Phase 1); generateQASM import (MATLAB subset) **~2 man-days — 2-week sprint** (full QASM-3 parser — Deferred).

# Specific Design Feedback

- The inclusion of pre-built circuit templates would be highly valuable for usability; these were not clearly visible in the current materials.
>>> Answer: The templates already exist — a 12-template gallery in the Composer (`TemplateRegistry`, via the **Templates ▾** toolbar button); it was hard to find (partly behind the now-fixed auth wall). **Sprint:** surface the existing gallery on the Composer empty-state/landing with one-click insert. Live Scripts deferred.
>>> **Effort: ~1.5 man-days — 2-week sprint** (surface existing gallery); example Live Scripts **~3 man-days — Deferred**.

- It would be helpful to further clarify the primary target use cases:
    - The app exposes a wide range of features, which creates a powerful but potentially complex user experience.
    - Understanding which workflows are most important for target users could help guide simplification and prioritization.
    - Streamlining the interface around a smaller set of high-value use cases may improve usability.
>>> Answer: Direction set by the positioning (one backbone workflow; researchers → quant-finance lead). The structural fix — **progressive disclosure** (advanced tabs hidden by default behind a "Show advanced" toggle, via `NavigationManager` nav-array filtering) — is deferred so the sprint stays inside 2 weeks.
>>> **Effort: ~4 man-days — Deferred.**

- There appears to be some functional overlap between the Prediction and Run Planner tabs:
    - Clarifying their distinct roles—or potentially consolidating them—could reduce confusion.
>>> Answer: Agreed — the overlap is structural (`RunPlannerService` already calls `PredictionService.predict` internally). **Sprint (minimal):** retire the standalone Prediction tab from the sidebar (keep its routing key for back-compat) and expose prediction as Run Planner's first step by reusing the existing predict call — no full UI redesign.
>>> **Effort: ~2 man-days — 2-week sprint.**

- The circuit export capabilities (Qiskit, Cirq, Braket) are a strong feature for interoperability:
    - It would be helpful to better articulate the primary use cases (e.g., collaboration, downstream execution on specific platforms).
    - If interoperability is not a central use case, maintaining multiple representations may introduce unnecessary complexity.
>>> Answer: Keep the emitters (cheap, already tested) but **demote** them: regroup the export dialog so MATLAB + QASM are primary and Qiskit/Cirq/Braket sit under "Advanced export," with a one-paragraph doc note on the real use cases (collaboration, downstream SDK/hardware execution).
>>> **Effort: ~1 man-day — 2-week sprint.**

---

## Effort roll-up

### 2-week sprint (1 engineer)

| # | Sprint item | Feedback | Man-days |
|---|-------------|:--------:|:--------:|
| 1 | Results push UI | O4 | 1 |
| 2 | Export demotion | S4 | 1 |
| 3 | Templates on empty-state | S1 | 1.5 |
| 4 | Prediction → Run Planner (minimal) | S3 | 2 |
| 5 | generateQASM import (MATLAB subset) | O5d-iii | 2 |
| | **Build subtotal** | | **7.5** |
| | + test/review buffer | | ~2.5 |
| | **Sprint total** | | **~10 (≈ 2 weeks)** |

### Deferred backlog (fast-follow, ~25 man-days)

| Item | Feedback | Man-days |
|------|:--------:|:--------:|
| QMC flagship vertical | O4d | 7 |
| `.mat` / table data import | O4b | 4 |
| Progressive disclosure | S2 | 4 |
| Sandbox / demo mode | O3b | 5 |
| Example Live Scripts | S1 | 3 |
| Built-in docs extension | O2 | 2 |

**Delivered already (Phase 1): ~6 man-days.** Full schedule + day-by-day calendar in [`feedback_plans.md`](./feedback_plans.md).
