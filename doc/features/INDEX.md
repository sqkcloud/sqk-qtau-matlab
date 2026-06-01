# Feature Documentation — QTAU Connector Workbench

> **Looking for everything in one place?** See
> [`../MASTER_REFERENCE.md`](../MASTER_REFERENCE.md) — the consolidated
> compendium of all features, every client-side formula/algorithm (with
> `file:line` citations), and the purpose of each. The per-feature pages
> below go deeper on individual screens.

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

The remaining workspace screens are documented in two places:

- [`analysis.md`](analysis.md) — full per-feature page for the
  Analysis screen (the QMC + QEM popup launchpad).
- [`reports.md`](reports.md) — full per-feature page for the Reports
  screen (Generate / Download / Email / Print, poll-and-stream flow).
- [`screens-overview.md`](screens-overview.md) — consolidated
  per-section pages for the rest, each with the seven-section
  template at compact size.

| # | Screen | Where | Purpose |
|---|--------|-------|---------|
| 9  | Welcome             | [`screens-overview.md` §A](screens-overview.md#a-welcome)             | Login + project picker |
| 10 | Dashboard           | [`screens-overview.md` §B](screens-overview.md#b-dashboard)           | Workflow summary, readiness storyboard |
| 11 | Circuits            | [`screens-overview.md` §C](screens-overview.md#c-circuits)            | Browse/search project circuits |
| 12 | Upload              | [`screens-overview.md` §D](screens-overview.md#d-upload)              | Circuit upload + format detection |
| 13 | Analysis            | [`analysis.md`](analysis.md)                                          | Feature extraction + QMC/QEM popups |
| 14 | Detailed Analysis   | [`screens-overview.md` §E](screens-overview.md#e-detailed-analysis)   | Heatmaps, drift, qubit metrics |
| 15 | Backends            | [`screens-overview.md` §F](screens-overview.md#f-backends)            | Backend explorer with primary/backup |
| 16 | Jobs                | [`screens-overview.md` §G](screens-overview.md#g-jobs)                | Job dashboard, auto-refresh every 5 s |
| 17 | Results             | [`screens-overview.md` §H](screens-overview.md#h-results)             | Measured vs predicted vs ideal |
| 18 | Reports             | [`reports.md`](reports.md)                                            | PDF/HTML/JSON report generation |
| 19 | Settings            | [`screens-overview.md` §J](screens-overview.md#j-settings)            | Account, defaults, storage, notifications |
| 20 | Notes               | [`screens-overview.md` §K](screens-overview.md#k-notes)               | Working notes (hidden in nav) |

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
