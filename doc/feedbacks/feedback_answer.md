We’ve reviewed the QTau MATLAB Toolbox and I want to share our feedback ahead of our meeting next week.

In summary, you’ve done a lot of good work and it looks very good, but we think there could be some improvements to strengthen its utility within the MATLAB ecosystem.

See the feedback below. I’m looking forward to our conversation next week.

> Each item is answered with the solution we will implement and an effort estimate in **man-days**.

# Overall Feedback and Direction

- The UI looks polished, and the overall organization of the design, specifications, and architecture appears well thought out.
>>> Answer: Maintain the current direction — keep the three-layer clean architecture (screens → view-models → services → HTTP gateway) and the externalized configuration (`AppConfig`/`Labels`) as the working conventions, and hold all new work to the same standard.
>>> **Effort: 0 man-days** (no development).

- The toolbox packaging and repository are well done:
    - Integration with the Add-On Explorer works well.
    - Built-in documentation is a positive and important feature.
>>> Answer: Keep the packaging and Add-On Explorer integration as-is, and extend the built-in documentation with pages for the new MATLAB-interop capabilities (import, native simulation, MATLAB export, offline use).
>>> **Effort: ~2 man-days.**

- I couldn’t fully explore the app without server authentication.
>>> Answer: Decouple the MATLAB-native paths from the backend login. Classify the Composer as offline-capable (`NavigationManager.isOfflineCapable`) and gate the login overlay per screen (`refreshAuthOverlay`), so building, importing, simulating, and exporting work with no login; add an "Explore offline" entry on the Projects screen that routes straight into the Composer. Backend-backed screens still require auth.
>>> **Effort: ~2 man-days.**

- It would be helpful to further clarify the motivation for delivering this functionality within MATLAB:
    - Third-party MATLAB apps are typically most compelling when they integrate into an existing MATLAB-centric workflow (e.g., data processing, analysis, visualization).
    - The connection to the broader MATLAB workflow is not yet clear:
        - There does not appear to be a clear pathway for importing MATLAB data.
        - Export capabilities primarily target external formats (Python, JSON, QASM), rather than enabling continued work within MATLAB.
    - As a result, it is not yet obvious what advantages this approach provides over a web-based or Python-based interface.
>>> Answer: Make MATLAB the round-trip anchor — *circuit, data, and results never leave MATLAB.* Concretely:
>>> - **Export back to MATLAB:** a MATLAB (`quantumCircuit`) export target that emits a runnable script (`CircuitModel.toMatlabScript`), plus a Push-to-workspace action that writes the live `quantumCircuit` to the base workspace. *(~2 man-days)*
>>> - **Import MATLAB data:** load workspace data (`quantumCircuit` objects now; numeric `.mat`/`table` values as parametric-circuit inputs) directly into the app. *(~2 man-days)*
>>> - **Demonstrate the advantage:** a quant-finance Quantum Monte Carlo path that takes a MATLAB returns vector/table, runs QAE, and pushes the loss distribution back to the workspace — a workflow that is only natural inside MATLAB. *(~2 man-days)*
>>> **Effort: ~6 man-days.**

- Strengthening integration with existing MATLAB quantum computing functionality would clarify the position of this app within the MATLAB ecosystem:
    - Currently, there is no clear linkage to the MATLAB Quantum Computing Support Package.
    - Inputs appear limited to QASM or circuits constructed directly in the app.
    - Local simulation seems to rely on separate infrastructure rather than MATLAB’s QC capabilities.
    - It would be valuable to support interoperability, for example:
        - Importing circuits created in MATLAB.
        - Using MATLAB’s built in circuit simulation
        - Using MATLAB tooling to generate QASM internally (e.g., via circuit.generateQASM()).
>>> Answer: Add a single `MatlabQuantumBridge` service as the one place that talks to the MATLAB Quantum Computing Support Package, and route every interop path through it:
>>> - **Import circuits created in MATLAB:** convert a workspace `quantumCircuit` into the app's circuit model — map each gate's `Type`/`ControlQubits`/`TargetQubits`/`Angles` and shift MATLAB's 1-based qubit indices to the app's 0-based convention. *(~2 man-days)*
>>> - **Use MATLAB's built-in simulation:** run MATLAB's native `simulate()` as the authoritative engine and surface a per-qubit parity check against the in-app step simulator. *(~2 man-days)*
>>> - **Use MATLAB's QASM tooling:** accept `circuit.generateQASM()` output as an import path (MATLAB emits OpenQASM 3.0, so we recognize its register/measure syntax and reuse the existing gate mapping). *(~1.5 man-days)*
>>> Everything degrades gracefully when the Support Package add-on is absent.
>>> **Effort: ~5.5 man-days.**

# Specific Design Feedback

- The inclusion of pre-built circuit templates would be highly valuable for usability; these were not clearly visible in the current materials.
>>> Answer: Surface the Composer's pre-built circuit-template gallery prominently — present it on the Composer empty-state/landing with one-click insert so it is the obvious starting point — and ship a set of example circuits as runnable Live Scripts.
>>> **Effort: ~2 man-days** (surfacing) **+ ~3 man-days** (example Live Scripts).

- It would be helpful to further clarify the primary target use cases:
    - The app exposes a wide range of features, which creates a powerful but potentially complex user experience.
    - Understanding which workflows are most important for target users could help guide simplification and prioritization.
    - Streamlining the interface around a smaller set of high-value use cases may improve usability.
>>> Answer: Define the primary workflow (build/import → simulate → analyze → run) and target audience (MATLAB quantum researchers, then quant-finance), and add **progressive disclosure** — the interface defaults to that core workflow, with advanced surfaces (Mitigation Compare, Resource Estimator, Circuit Cutting, QEC) hidden behind a "Show advanced" toggle (driven by filtering the navigation entries per use-case mode). No feature is removed, only de-emphasized.
>>> **Effort: ~4 man-days.**

- There appears to be some functional overlap between the Prediction and Run Planner tabs:
    - Clarifying their distinct roles—or potentially consolidating them—could reduce confusion.
>>> Answer: Consolidate the two. Prediction answers *"what fidelity will I get?"* and Run Planner answers *"cheapest configuration that hits target fidelity F?"* — Run Planner already calls the prediction service internally, so fold Prediction in as Run Planner's first step and retire the standalone Prediction tab (keeping its routing key for back-compatibility).
>>> **Effort: ~3 man-days.**

- The circuit export capabilities (Qiskit, Cirq, Braket) are a strong feature for interoperability:
    - It would be helpful to better articulate the primary use cases (e.g., collaboration, downstream execution on specific platforms).
    - If interoperability is not a central use case, maintaining multiple representations may introduce unnecessary complexity.
>>> Answer: Keep the Qiskit/Cirq/Braket emitters but reposition them — make MATLAB and QASM the primary export targets and group the Python ecosystems under an "Advanced export" section, with a short note documenting their use case (collaboration and downstream execution on platform-specific SDKs/hardware).
>>> **Effort: ~2 man-days.**

---

## Effort summary

| Requirement | Man-days |
|-------------|:--------:|
| Maintain architecture/conventions | 0 |
| Extend built-in documentation | 2 |
| Offline app exploration | 2 |
| MATLAB round-trip — export back, data import, QMC showcase | 6 |
| MATLAB Quantum Computing Support Package interop | 5.5 |
| Surface circuit templates | 2 (+3 example Live Scripts) |
| Clarify use cases / progressive disclosure | 4 |
| Consolidate Prediction & Run Planner | 3 |
| Reposition Qiskit/Cirq/Braket export | 2 |
| **Total** | **~26.5 man-days** (+3 optional Live Scripts) |
