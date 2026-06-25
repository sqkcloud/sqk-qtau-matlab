We’ve reviewed the QTau MATLAB Toolbox and I want to share our feedback ahead of our meeting next week.

In summary, you’ve done a lot of good work and it looks very good, but we think there could be some improvements to strengthen its utility within the MATLAB ecosystem.

See the feedback below. I’m looking forward to our conversation next week.

> Status legend: **Done** = shipped on `feature/feedback` (PR open). **Planned** = scheduled in [`feedback_plans.md`](./feedback_plans.md). Effort in **man-days**; "delivered" = already spent.

# Overall Feedback and Direction

- The UI looks polished, and the overall organization of the design, specifications, and architecture appears well thought out.
>>> Answer: Thank you — no change required. We keep the three-layer clean architecture (screens → view-models → services → HTTP gateway) and externalized config (`AppConfig`/`Labels`) as working conventions; all new code follows them.
>>> **Effort: 0 man-days** (no action).

- The toolbox packaging and repository are well done:
    - Integration with the Add-On Explorer works well.
    - Built-in documentation is a positive and important feature.
>>> Answer: Maintained as-is. The only follow-up is additive: we extend the built-in documentation with pages covering the new MATLAB-interop capabilities (import / simulate / export / offline).
>>> **Effort: ~2 man-days** (docs extension — Planned, Phase 4).

- I couldn’t fully explore the app without server authentication.
>>> Answer: **Done.** The Composer is now reachable offline — `NavigationManager.isOfflineCapable('Composer')` + `refreshAuthOverlay(app,key)` show the login overlay only when logged-out *and* the screen needs the backend; an "Explore offline" entry on the Projects screen routes straight in. You can now build / import / simulate / export with no login. Optional follow-up: a sandbox/demo mode so the backend-backed screens (Backends, Jobs, Reports) are browsable without real credentials.
>>> **Effort: ~2 man-days delivered** (Phase 1); **+5 man-days** for sandbox mode (Planned, Phase 4, optional).

- It would be helpful to further clarify the motivation for delivering this functionality within MATLAB:
    - Third-party MATLAB apps are typically most compelling when they integrate into an existing MATLAB-centric workflow (e.g., data processing, analysis, visualization).
    - The connection to the broader MATLAB workflow is not yet clear:
        - There does not appear to be a clear pathway for importing MATLAB data.
        - Export capabilities primarily target external formats (Python, JSON, QASM), rather than enabling continued work within MATLAB.
    - As a result, it is not yet obvious what advantages this approach provides over a web-based or Python-based interface.
>>> Answer: Positioning: *your circuit, your data, and your results never leave MATLAB.* **Done:** a MATLAB (`quantumCircuit`) export target (`CircuitModel.toMatlabScript`) plus a Push-to-workspace action that writes the live circuit back to the base workspace. **Planned:** importing numeric MATLAB data (`.mat`/`table`) as parametric-circuit inputs, and a quant-finance QMC flagship vertical (import a returns `table` → QAE → loss-distribution/VaR pushed back to the workspace) — the concrete, demoable advantage over a web/Python interface.
>>> **Effort: export + push delivered** (Phase 1); **+12 man-days** Planned (Phase 2): results-struct push UI 1 + `.mat`/table import 4 + QMC flagship vertical 7.

- Strengthening integration with existing MATLAB quantum computing functionality would clarify the position of this app within the MATLAB ecosystem:
    - Currently, there is no clear linkage to the MATLAB Quantum Computing Support Package.
    - Inputs appear limited to QASM or circuits constructed directly in the app.
    - Local simulation seems to rely on separate infrastructure rather than MATLAB’s QC capabilities.
    - It would be valuable to support interoperability, for example:
        - Importing circuits created in MATLAB.
        - Using MATLAB’s built in circuit simulation
        - Using MATLAB tooling to generate QASM internally (e.g., via circuit.generateQASM()).
>>> Answer: **Done.** A new `MatlabQuantumBridge` service is the single point of integration with the MATLAB Quantum Computing Support Package: it **imports** a workspace `quantumCircuit` into the Composer (gate-type mapping, 1-based↔0-based index shift) and runs MATLAB's **native `simulate()`** as the authoritative engine, with a per-qubit parity check shown in the Inspect footer. The hand-rolled simulator is retained only for per-step animation and `reset`. **Planned:** the `circuit.generateQASM()` route — note MATLAB emits OpenQASM **3.0** while the app's importer is strict 2.0, so Phase 2 adds a QASM-3 parser + passthrough for circuits using gates outside the Composer palette.
>>> **Effort: ~4 man-days delivered** (Phase 1: import + native simulate + parity); **+4 man-days** for `generateQASM` / QASM-3 (Planned, Phase 2).

# Specific Design Feedback

- The inclusion of pre-built circuit templates would be highly valuable for usability; these were not clearly visible in the current materials.
>>> Answer: The templates already exist — a 12-template gallery in the Composer (`TemplateRegistry`, reached via the **Templates ▾** toolbar button); it was hard to find (partly behind the now-fixed auth wall). We will raise discoverability by surfacing the gallery on the Composer empty-state/landing with one-click insert, and ship the templates as runnable example Live Scripts.
>>> **Effort: ~3 man-days** discoverability (Planned, Phase 3) **+ 3 man-days** Live Scripts (Planned, Phase 4).

- It would be helpful to further clarify the primary target use cases:
    - The app exposes a wide range of features, which creates a powerful but potentially complex user experience.
    - Understanding which workflows are most important for target users could help guide simplification and prioritization.
    - Streamlining the interface around a smaller set of high-value use cases may improve usability.
>>> Answer: We lead with one backbone workflow (build/import → simulate → analyze → run) and the priority audiences (MATLAB quantum researchers, then quant-finance/QMC). To reduce surface area we add **progressive disclosure** — advanced tabs (Mitigation Compare, Resource Estimator, Circuit Cutting, QEC) hidden by default behind a "Show advanced" toggle, implemented by filtering the `NavigationManager` nav arrays per use-case mode. No feature is removed, only de-emphasized.
>>> **Effort: ~4 man-days** (Planned, Phase 3).

- There appears to be some functional overlap between the Prediction and Run Planner tabs:
    - Clarifying their distinct roles—or potentially consolidating them—could reduce confusion.
>>> Answer: Agreed — the overlap is structural (`RunPlannerService` already calls `PredictionService.predict` internally). We consolidate: Prediction becomes Run Planner's first step ("what fidelity will I get?" feeds "cheapest config that hits target F?"), and the standalone Prediction tab is retired from the sidebar while keeping its routing key for back-compat.
>>> **Effort: ~4 man-days** (Planned, Phase 3).

- The circuit export capabilities (Qiskit, Cirq, Braket) are a strong feature for interoperability:
    - It would be helpful to better articulate the primary use cases (e.g., collaboration, downstream execution on specific platforms).
    - If interoperability is not a central use case, maintaining multiple representations may introduce unnecessary complexity.
>>> Answer: We keep the emitters (cheap, already tested) but **demote** them: MATLAB + QASM become the primary export targets, with Qiskit/Cirq/Braket grouped under "Advanced export," and we document the real use cases (collaboration and downstream execution on platform-specific SDKs/hardware) so the rationale is explicit rather than implied by feature breadth.
>>> **Effort: ~2 man-days** (Planned, Phase 3).

---

## Effort roll-up

| Bucket | Man-days |
|--------|:--------:|
| **Delivered (Phase 1)** | ~6 (already spent) |
| Phase 2 — data interop + flagship + generateQASM | 16 |
| Phase 3 — UX simplification (templates surfacing, progressive disclosure, Prediction↔Run Planner, export demotion) | 13 |
| Phase 4 — sandbox mode, Live Scripts, docs | 10 |
| **Remaining total** | **~39 man-days** |

1-engineer finish ≈ **2026-08-28**; 2-engineer ≈ mid-August 2026. Full schedule, calendar, and risks in [`feedback_plans.md`](./feedback_plans.md).
