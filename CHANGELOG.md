# Changelog

All notable changes to **QTAU Connector Workbench** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-05-19

### Added

- Initial public release on MATLAB Central File Exchange.
- Three-layer clean architecture (presentation / domain / infrastructure) under `src/`.
- 20 workflow screens spanning circuit upload, in-app composer, analysis, backend exploration, benchmark planning, fidelity prediction, mitigation cost comparison, run planner, job monitoring, results, reports, QEC simulation, and 3D visualization.
- Quantum Monte Carlo simulation popup with async IBM Runtime job execution, zero-noise extrapolation, vector-chart PDF reports, and IBM execution-log download.
- Cost-aware Run Planner that surfaces the cheapest *backend × mitigation × shots* configuration meeting a target fidelity, via a Pareto frontier.
- Reproducibility Bundle export (QASM + Qiskit / Cirq / Braket Python + manifest with SHA-256 checksums).
- Externalised configuration through `resources/app.properties` and `resources/labels.properties` (600+ UI strings, runtime-reloadable).
- 31 unit-test files covering services, infrastructure, viewmodels, and configuration utilities.
- Apache 2.0 license, with PNNL QASMBench attribution in `NOTICE`.

### Requirements

- MATLAB **R2025b** or later.
- A reachable QTAU FastAPI backend (the toolbox is the client only).

## [1.1.0] — 2026-05-20

### Added

- **MATLAB Help browser integration.** `info.xml` at the toolbox root + `doc/help/{helptoc.xml,demos.xml,overview.html,getting-started.html,screens.html,troubleshooting.html}`. The toolbox now appears as a first-class entry in F1 search and the Add-On Explorer's Examples tab.
- **Notes screen** restored to the sidebar at position 4 between Circuits and Analysis. The `NotesScreen` / `NotesViewModel` were already wired in `NavigationManager`'s routing; only the `navNames` / `navIcons` / `navLabels` arrays needed the entry back.
- **Pre-rendered example scripts** under `doc/examples/`:
  - `example_01_qec_simulation.m` — sweep fidelity vs. depolarizing-noise probability, compare codes side-by-side, inspect Bloch vectors. Runs offline.
  - `example_02_visualize_circuit.m` — render OpenQASM via `CircuitDiagram` as ASCII / HTML / SVG. Runs offline.
  - `example_03_connect_and_browse.m` — drive the FastAPI backend programmatically (login, list projects, browse circuits).
  Each `.m` is also registered in `doc/help/demos.xml` so MATLAB's `demo` command surfaces them.

### Fixed

- **QEC 3-qubit bit-flip decoder.** `QecEngineService.decodeLogical` now applies the inverse encoding circuit (`CNOT_{1→3}` then `CNOT_{1→2}`) before partial-tracing the ancilla qubits, fixing a 0.5-fidelity ceiling on superposition logical inputs for the `bitflip3`, `repetition`, and `phaseflip3` codes. New helper `QecEngineService.cnotMatrix(control, target, nQubits)` and `decodeBitFlip3` encapsulate the fix. Product-state inputs (`|0⟩`, `|1⟩`) produce bit-identical results to 1.0.0 because CNOT with control bit zero is the identity.
- **`test_QecEngineService.testDepolarizingNoNoisePerfectFidelity`** restored to its original `|+⟩` input now that the decoder handles superpositions correctly.

## [1.0.0] — 2026-05-19

### Added

- Initial public release on MATLAB Central File Exchange.
- Three-layer clean architecture (presentation / domain / infrastructure) under `src/`.
- 20 workflow screens spanning circuit upload, in-app composer, analysis, backend exploration, benchmark planning, fidelity prediction, mitigation cost comparison, run planner, job monitoring, results, reports, QEC simulation, and 3D visualization.
- Quantum Monte Carlo simulation popup with async IBM Runtime job execution, zero-noise extrapolation, vector-chart PDF reports, and IBM execution-log download.
- Cost-aware Run Planner that surfaces the cheapest *backend × mitigation × shots* configuration meeting a target fidelity, via a Pareto frontier.
- Reproducibility Bundle export (QASM + Qiskit / Cirq / Braket Python + manifest with SHA-256 checksums).
- Externalised configuration through `resources/app.properties` and `resources/labels.properties` (600+ UI strings, runtime-reloadable).
- 31 unit-test files covering services, infrastructure, viewmodels, and configuration utilities.
- Apache 2.0 license, with PNNL QASMBench attribution in `NOTICE`.

### Requirements

- MATLAB **R2025b** or later.
- A reachable QTAU FastAPI backend (the toolbox is the client only).

[1.1.0]: https://github.com/sqkcloud/sqk-qtau-matlab/releases/tag/v1.1.0
[1.0.0]: https://github.com/sqkcloud/sqk-qtau-matlab/releases/tag/v1.0.0
