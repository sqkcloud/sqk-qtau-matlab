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
- 20 unit-test files covering services, infrastructure, and configuration utilities.
- Apache 2.0 license, with PNNL QASMBench attribution in `NOTICE`.

### Requirements

- MATLAB **R2025b** or later.
- A reachable QTAU FastAPI backend (the toolbox is the client only).

## [Unreleased] — roadmap

### Planned for 1.1.0

- Full MATLAB Help browser integration (`info.xml` + `helptoc.xml` + `demos.xml`) alongside a `.mlx` Getting Started guide exported to HTML.
- Re-enable the **Notes** screen in the sidebar (currently hidden behind a feature flag).
- Pre-rendered `.mlx` live examples under `doc/examples/` surfaced in **Help → Examples**.

[1.0.0]: https://github.com/sqkcloud/sqk-qtau-matlab/releases/tag/v1.0.0
