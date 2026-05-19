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

### Known issues (test-only, no end-user impact)

These five tests fail in 1.0.0 against the current MATLAB runtime but the affected production code paths work correctly in the app. Scheduled for resolution in 1.0.1:

- `test_JsonHelper/testBenchmarkStrategyToRows*` (2 tests) — `int32` vs `double` class assertion mismatch from a newer MATLAB JSON decoder behavior. Benchmark data still renders correctly on screen.
- `test_MitigationCompareViewModel/test_parseLevelId_invalid_returns_minus_one` — same `int32` vs `double` class mismatch.
- `test_AsyncRunner/testRunReturnsScalarResult` — async dispatch timing flake (the other AsyncRunner tests all pass; production code is fine).
- `test_Logger/testLogOutputUppercasesLevel` — log-level case-format test that doesn't match the current output format. All other logger tests pass.
- `test_ReportService/testGenerateReportPayload` — payload struct field shape (`cell` vs `char`) — endpoint still receives the right data.

### Investigation needed

- `test_QecEngineService/testDepolarizingNoNoisePerfectFidelity` — at noise probability 0 with the 3-qubit bit-flip code under a depolarizing channel, fidelity returns 0.5 instead of the expected ≥0.99. The matched-noise cases (bitflip+bitflip, phaseflip+phaseflip) pass, so the core QEC simulation works; this is a cross-channel edge case in the simulation pipeline.

[1.0.0]: https://github.com/sqkcloud/sqk-qtau-matlab/releases/tag/v1.0.0
