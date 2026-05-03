# Feature Documentation — QTAU Connector Workbench

This directory holds per-feature reference documents. Each one follows the
same seven-section template:

1. **What it is** — one-paragraph definition.
2. **Purpose** — who it's for, what problem it solves.
3. **Architecture** — clean-architecture mapping (Screen → ViewModel → Service → HTTP).
4. **Algorithm** — the actual computation, when applicable.
5. **Workflow** — operator click-by-click flow.
6. **Data flow** — endpoints, payloads, response shapes.
7. **Business logic** — domain rules, validation, error paths.

Every document cites code by `path:line` so the description can be
verified against the implementation. The reference at the end of each
document lists the screen, ViewModel, service, and backend router.

## Headline features (named in the product brief)

| # | Feature | Document | Surface |
|---|---------|----------|---------|
| 1 | Quantum Monte Carlo (QMC / QAE) | [`quantum-monte-carlo.md`](quantum-monte-carlo.md) | Analysis screen popup |
| 2 | Quantum Error Mitigation (QEM)  | [`quantum-error-mitigation.md`](quantum-error-mitigation.md) | Analysis screen popup |
| 3 | Circuit Cutting                  | [`circuit-cutting.md`](circuit-cutting.md) | Circuit Cutting screen |
| 4 | Benchmark                        | [`benchmark.md`](benchmark.md) | Benchmark + Benchmark Dashboard |
| 5 | Predictions                      | [`predictions.md`](predictions.md) | Prediction screen |
| 6 | QEC overview                     | [`qec-overview.md`](qec-overview.md) | shared concepts |
| 7 | QEC Simulation                   | [`qec-simulation.md`](qec-simulation.md) | QEC Simulation screen |
| 8 | QEC Visualization                | [`qec-visualization.md`](qec-visualization.md) | QEC Visualization screen |

## Workspace screens

| # | Screen | Document | Purpose |
|---|--------|----------|---------|
| 9  | Welcome             | [`welcome.md`](welcome.md)              | Login + project picker |
| 10 | Dashboard           | [`dashboard.md`](dashboard.md)          | Workflow summary, readiness storyboard |
| 11 | Circuits            | [`circuits.md`](circuits.md)            | Browse/search project circuits |
| 12 | Upload              | [`upload.md`](upload.md)                | Circuit upload + format detection |
| 13 | Analysis            | [`analysis.md`](analysis.md)            | Feature extraction + QMC/QEM popups |
| 14 | Detailed Analysis   | [`detailed-analysis.md`](detailed-analysis.md) | Heatmaps, drift, qubit metrics |
| 15 | Backends            | [`backends.md`](backends.md)            | Backend explorer with primary/backup |
| 16 | Jobs                | [`jobs.md`](jobs.md)                    | Job dashboard, auto-refresh every 5 s |
| 17 | Results             | [`results.md`](results.md)              | Measured vs predicted vs ideal |
| 18 | Reports             | [`reports.md`](reports.md)              | PDF/HTML/JSON report generation |
| 19 | Settings            | [`settings.md`](settings.md)            | Account, defaults, storage, notifications |
| 20 | Notes               | [`notes.md`](notes.md)                  | Working notes (hidden in nav) |

## Cross-cutting concerns

| Topic | Document |
|-------|----------|
| Architecture, async, loading overlay, auth, project context, error handling | [`architecture.md`](architecture.md) |

## Conventions used by all documents

- Source citations are `path:line` (e.g. `AnalysisViewModel.m:712`).
- HTTP shapes are quoted from live server probes against
  `http://34.42.87.190:5715` and from the source under
  `/Users/mason/Workspace/Projects/QDash/sqk-qtau/src/qdash/api/routers/`.
- Loading-overlay messages are sourced through
  `Labels.get('loading_<scope>_<action>', '<English fallback...>')` per
  `OverlayManager.m:9–51` (Phase 6.4 standard).
- Error propagation: `MException` from HTTP → Service → ViewModel →
  `uialert(parent, ...)`.
