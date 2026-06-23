We’ve reviewed the QTau MATLAB Toolbox and I want to share our feedback ahead of our meeting next week.
 
In summary, you’ve done a lot of good work and it looks very good, but we think there could be some improvements to strengthen its utility within the MATLAB ecosystem.
 
See the feedback below. I’m looking forward to our conversation next week.

# Overall Feedback and Direction

- The UI looks polished, and the overall organization of the design, specifications, and architecture appears well thought out.
- The toolbox packaging and repository are well done:
    - Integration with the Add-On Explorer works well.
    - Built-in documentation is a positive and important feature.
- I couldn’t fully explore the app without server authentication.
- It would be helpful to further clarify the motivation for delivering this functionality within MATLAB:
    - Third-party MATLAB apps are typically most compelling when they integrate into an existing MATLAB-centric workflow (e.g., data processing, analysis, visualization).
    - The connection to the broader MATLAB workflow is not yet clear:
        - There does not appear to be a clear pathway for importing MATLAB data.
        - Export capabilities primarily target external formats (Python, JSON, QASM), rather than enabling continued work within MATLAB.
    - As a result, it is not yet obvious what advantages this approach provides over a web-based or Python-based interface.
- Strengthening integration with existing MATLAB quantum computing functionality would clarify the position of this app within the MATLAB ecosystem:
    - Currently, there is no clear linkage to the MATLAB Quantum Computing Support Package.
    - Inputs appear limited to QASM or circuits constructed directly in the app.
    - Local simulation seems to rely on separate infrastructure rather than MATLAB’s QC capabilities.
    - It would be valuable to support interoperability, for example:
        - Importing circuits created in MATLAB.
        - Using MATLAB’s built in circuit simulation
        - Using MATLAB tooling to generate QASM internally (e.g., via circuit.generateQASM()).
 

# Specific Design Feedback

- The inclusion of pre-built circuit templates would be highly valuable for usability; these were not clearly visible in the current materials.
- It would be helpful to further clarify the primary target use cases:
    - The app exposes a wide range of features, which creates a powerful but potentially complex user experience.
    - Understanding which workflows are most important for target users could help guide simplification and prioritization.
    - Streamlining the interface around a smaller set of high-value use cases may improve usability.
- There appears to be some functional overlap between the Prediction and Run Planner tabs:
    - Clarifying their distinct roles—or potentially consolidating them—could reduce confusion.
- The circuit export capabilities (Qiskit, Cirq, Braket) are a strong feature for interoperability:
    - It would be helpful to better articulate the primary use cases (e.g., collaboration, downstream execution on specific platforms).
    - If interoperability is not a central use case, maintaining multiple representations may introduce unnecessary complexity.