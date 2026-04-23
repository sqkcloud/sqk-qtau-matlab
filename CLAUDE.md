# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

QTAU Connector Workbench is a **MATLAB R2025b** desktop application for managing quantum circuit experiments through a FastAPI backend (QTAU Connector). It provides a 17-screen UI (16 visible in the sidebar, Notes is temporarily hidden) spanning circuit upload, analysis, backend selection, benchmarking, fidelity prediction, job monitoring, QEC simulation, and reporting. The Analysis screen hosts a Quantum Monte Carlo simulation popup with async job execution, IBM Runtime integration, zero-noise extrapolation, and one-click PDF report generation.

## Commands

```matlab
% Launch the app
run('QTAUWorkbenchLauncher.m')
% Or via MATLAB Project Manager:
matlab.project.openProject('sqk-qtau-matlab.prj')

% Run all tests (20 test files)
runtests('tests')

% Run a single test file
runtests('tests/test_AppConfig')

% Reload externalized config without restarting
AppConfig.reload(); Labels.reload();

% Seed demo data into the backend (all screens)
run('scripts/seed_all.m')
% Or seed a single screen's data
run('scripts/seed_projects.m')
% Seed QTAUBench circuits
run('scripts/seed_qasmbench.m')
```

There is no build step, linter, or CI pipeline. MATLAB interprets `.m` files directly.

## Architecture

Three-layer clean architecture under `src/`:

```
src/
├── presentation/
│   ├── app/
│   │   ├── QTAUWorkbenchApp.m    ← Main app class (UI chrome, navigation, service wiring)
│   │   ├── LayoutBuilder.m       ← UI layout utilities
│   │   ├── NavigationManager.m   ← Screen switching logic
│   │   ├── OverlayManager.m      ← Overlay/modal management
│   │   ├── PopupMenuManager.m    ← Context menu management
│   │   └── StyleHelper.m         ← UI styling utilities
│   ├── screens/                  ← 17 screen builder functions (pure UI layout)
│   ├── viewmodels/               ← 17 ViewModel classes (callbacks, event logic)
│   └── DialogBuilder.m           ← Dialog creation utilities
├── domain/
│   ├── ServiceContainer.m        ← Dependency injection container
│   ├── models/AppState.m         ← Session-scoped mutable state (auth token, project ID, etc.)
│   └── services/                 ← 11 service classes
│       ├── AuthService.m         ← Authentication (login/logout/me)
│       ├── BackendService.m      ← Quantum backend management and calibration
│       ├── BenchmarkService.m    ← Volumetric benchmarks, scorecards, regression
│       ├── CircuitService.m      ← Circuit upload, analysis, preview, benchmark matching
│       ├── JobService.m          ← Job submission, polling, results, error trends
│       ├── PredictionService.m   ← Fidelity prediction and optimization
│       ├── ProjectService.m      ← Project CRUD, dashboard, notes, activities
│       ├── QaeService.m          ← Async QAE / Quantum Monte Carlo (submit / poll / cancel / IBM log)
│       ├── QecEngineService.m    ← QEC simulation engine (surface codes, noise models)
│       ├── ReportService.m       ← Report generation, download, sharing
│       └── SettingsService.m     ← User settings and IBM token verification
├── presentation/DialogBuilder.m  ← Modal dialog factory (hosts the Quantum Monte Carlo popup)
└── infrastructure/
    ├── AsyncRunner.m             ← Async execution wrapper
    ├── http/FastAPIClient.m      ← HTTP gateway (webread/webwrite, Bearer auth, multipart upload)
    └── config/
        ├── AppConfig.m           ← Reads app.properties
        ├── Labels.m              ← Reads labels.properties (600+ UI strings)
        ├── Logger.m              ← Structured logger
        ├── JsonHelper.m          ← JSON decode / table mapping / dotted-path traversal
        ├── CircuitDiagram.m      ← Circuit visualization and SVG rendering
        └── Theme.m               ← UI color and styling constants
```

**Data flow:** Screen → ViewModel → Service → FastAPIClient → HTTP

- **Screens** are functions that build UI into a provided container. They return no object.
- **ViewModels** are classes that own callbacks; they call services and update UI.
- **Services** receive `FastAPIClient` via constructor (dependency injection). They have no UI dependencies.
- **AppState** is instantiated once by `QTAUWorkbenchApp` and shared across ViewModels for the session lifetime.
- **ServiceContainer** wires all services with `FastAPIClient` via dependency injection.
- **Static utilities** (`AppConfig`, `Labels`, `Logger`, `JsonHelper`) use static methods with cached state; call `.reload()` to refresh.

## Screens (17 total — 16 visible, 1 hidden)

| Screen | ViewModel | Purpose | Sidebar |
|--------|-----------|---------|:-------:|
| WelcomeScreen | WelcomeViewModel | Login, project selection, recent projects | ✓ |
| DashboardScreen | DashboardViewModel | Workflow summary and readiness storyboard | ✓ |
| CircuitsScreen | CircuitsViewModel | Browse, search, manage project circuits | ✓ |
| NotesScreen | NotesViewModel | Working notes and operator memos | — (hidden) |
| UploadScreen | UploadViewModel | Circuit upload with format selection and preview | ✓ |
| AnalysisScreen | AnalysisViewModel | Circuit feature extraction, QTAUBench similarity, **Quantum Monte Carlo popup** | ✓ |
| DetailedAnalysisScreen | DetailedAnalysisViewModel | Heatmaps, drift, qubit metrics, cross-run comparisons — toolbar has Circuit selector + **Analyze bridge** to the Analysis screen | ✓ |
| BackendsScreen | BackendsViewModel | Backend explorer with primary/backup selection | ✓ |
| BenchmarkScreen | BenchmarkViewModel | Execution parameters, mitigation strategy, cost | ✓ |
| BenchmarkDashboardScreen | BenchmarkDashboardViewModel | Benchmark configuration summary and recommendations | ✓ |
| PredictionScreen | PredictionViewModel | Predicted fidelity, distribution, error budget — Circuit + Backend dropdowns on toolbar | ✓ |
| JobsScreen | JobsViewModel | Job Monitoring Dashboard with 6-col table (Job ID / Circuit / Backend / Status / Progress / Created), **auto-refresh every 5 s** while visible, detailed job logs | ✓ |
| ResultsScreen | ResultsViewModel | Measured vs predicted vs ideal result analysis (auto-picks the first completed job) | ✓ |
| ReportsScreen | ReportsViewModel | Report generation and viewing | ✓ |
| SettingsScreen | SettingsViewModel | Account settings, defaults, storage, notifications | ✓ |
| QecSimulationScreen | QecSimulationViewModel | QEC simulation under configurable noise models | ✓ |
| QecVisualizationScreen | QecVisualizationViewModel | 3D Bloch sphere, surface code lattice, error propagation | ✓ |

**Re-enable Notes:** add `'Notes'` back to `navNames` / `navLabels` and `char(9998)` to `navIcons` at position 4 in `NavigationManager.m`. The `NotesScreen` / `NotesViewModel` are still instantiated so the tab lights up immediately.

## Quantum Monte Carlo (QMC) popup

A modal `uifigure` (built by `DialogBuilder.buildQmcDialog`) launched from the Analysis toolbar. Runs QAE-based Monte Carlo risk analytics against either local statevector or IBM Runtime. Key integration points:

- **Async job pattern:** `POST /api/circuits/{id}/qae/analyze` returns `HTTP 202 {job_id}` immediately. `AnalysisViewModel.startQaePoll` drives a 3-second MATLAB `timer` polling `GET /api/qae/jobs/{job_id}` until `status` is `completed / failed / cancelled`. The loading overlay shows live `Queued (0 %)` → `Running (50 %)` → `Completed (100 %)` as the server advances.
- **Close mid-run:** `CloseRequestFcn` routes through `AnalysisViewModel.onCloseQaeDialog` which stops the poll timer; the server keeps running and the result is still cached on the circuit doc for the next visit.
- **Execution mode:** defaults to **IBM Runtime**; mitigation defaults to **Zero-Noise Extrapolation**.
- **Generate Report:** PDFs go through `ReportService._build_qmc_pdf_bytes` (dedicated vector-chart QMC builder — loss distribution with VaR, CDF, QAE vs classical MC convergence, amplitude bar, ZNE curve, Greeks table, market scenario, benchmark matches).
- **Download IBM Log:** button next to Run QMC streams `GET /api/circuits/{id}/qae/ibm-log?fmt=jsonl` — one record per IBM submission matching the schema in `samples/aqs-qmc/outputs_hybrid_mc_qdist_stable/quantum_exec_log.jsonl` (`{subcircuit_id, backend, shots, status, job_id, counts, error}`). Default save name: `ExecLog_{backend}_{circuit}_{YYYYMMDD}.jsonl`. Button is disabled unless the cached QAE result has a `runtime_job_id`.

## Navigation and Screen Switching

`QTAUWorkbenchApp` manages screens via `NavigationManager`. Each screen calls `app.createSectionPage('ScreenName')` during `buildUI()` to register a hidden panel, then populates it with UI controls. Navigation is handled by `onSelectSection(key)`, which hides all panels and shows the matching one. The `autoLoadScreen(key)` method triggers ViewModel data-fetching when a screen becomes visible (e.g., Dashboard auto-refreshes on enter).

## Adding a New Screen

Adding a screen requires changes in four places:

1. **Screen function** — Create `src/presentation/screens/FooScreen.m`. Call `app.createSectionPage('Foo')` to get the container, then build UI into it. Wire button callbacks to `app.FooVm.onSomething()`.
2. **ViewModel class** — Create `src/presentation/viewmodels/FooViewModel.m`. Constructor takes `app`. Methods call services and update `app.*` UI properties.
3. **QTAUWorkbenchApp.m** — Add UI property declarations for the screen's controls. Add `FooVm` property. Instantiate `FooVm = FooViewModel(app)` in the constructor. Call `FooScreen(app)` in `buildUI()`. Add a case to `autoLoadScreen()` if the screen should auto-fetch data on navigation.
4. **Nav list** — Add the screen name to `Labels.get('nav_*')` in `resources/labels.properties` and to the nav button/list builder in `buildUI()`.

## Configuration

All runtime config is externalized in `resources/` (key=value `.properties` files):

- `resources/app.properties` — API base URL, login path, timeout, app metadata, QEC simulation defaults
- `resources/labels.properties` — 600+ UI text strings (enables text changes without code edits)
- `resources/seed.properties` — Seed script credentials (copy from `seed.properties.example`)

Access patterns: `AppConfig.get(key, default)`, `AppConfig.getDouble(key, default)`, `Labels.get(key, default)`.

## Backend API

FastAPIClient talks to a FastAPI server (default `http://34.42.87.190:5715`). Auth is username/password POST → Bearer token. The MATLAB client uses **~80 endpoints** across 10 categories (auth, projects, circuits, backends, benchmarks, predictions, jobs, qae, reports, settings). Full endpoint contract is in `docs/fastapi_contract.md` and `docs/openapi.json`.

Notable flows:

- **QAE async jobs** — `POST /api/circuits/{id}/qae/analyze` → `202 {job_id}`, then poll `GET /api/qae/jobs/{job_id}`; `DELETE` cancels. The legacy synchronous call is gone — every caller must poll.
- **IBM execution log** — `GET /api/circuits/{id}/qae/ibm-log?fmt=json|jsonl` pulls counts + metadata from `QiskitRuntimeService.job(runtime_job_id)` for the cached QAE result; schema matches the hybrid-QMC notebook's `JSONLLogger`.
- **Sort-by-submitted_at** — `GET /api/jobs` now returns newest first (backend `.sort("-submitted_at")` using the existing compound index); MATLAB re-sorts defensively in `JsonHelper.jobsToRows` as a second layer.
- **Self-healing job list** — `list_jobs` lazy-refreshes up to 10 in-flight jobs per call from IBM Quantum so progress advances even when the Celery beat sweeper isn't deployed.
- **Report PDF** — `POST /api/reports/generate` returns a `report_id`; `GET /api/reports/{id}/download` streams the PDF. QMC reports go through a dedicated builder with native ReportLab vector charts.

## Nav-click loading overlay + auto-refresh

`NavigationManager.autoLoadScreen` shows a `Loading {Screen}…` overlay for every screen whose cache is stale, and arms a 20-second safety timer (`armNavOverlayTimer`) that auto-dismisses the overlay if a VM forgets its own `hideLoading`. `OverlayManager.showLoading` / `hideLoading` both disarm the safety timer on entry so rapid navigation can't cross-fire. VMs that previously had the overlay gap (Circuits, Upload, Prediction, Settings) now call `hideLoading()` in their completion callbacks.

The Jobs screen additionally runs a **5-second auto-refresh timer** (`JobsViewModel.startAutoRefresh`) while visible, polling `GET /api/jobs` silently (no overlay flash) so Status / Progress columns stay live. The timer self-terminates on the next tick after the user navigates away.

## Seed Scripts (14)

All seed scripts are in `scripts/` and use `seed_helpers.m` for authentication and HTTP setup:

| Script | Data |
|--------|------|
| `seed_all.m` | Master orchestrator — runs all seed scripts in order |
| `seed_projects.m` | 20 demo projects |
| `seed_circuits.m` | 10 sample OpenQASM circuits (inline content) |
| `seed_qasmbench.m` | 113+ QTAUBench circuits from `samples/qasmbench/` |
| `seed_qasmbench_invalid.m` | Re-upload 25 previously invalid QTAUBench circuits |
| `seed_backends.m` | Backend selections per project |
| `seed_benchmarks.m` | Benchmark configs and strategy comparisons |
| `seed_predictions.m` | Fidelity predictions |
| `seed_jobs.m` | Quantum job submissions |
| `seed_reports.m` | Generated reports |
| `seed_notes.m` | Markdown notes and checklists |
| `seed_settings.m` | User preferences |

## Sample Circuits

- `samples/*.qasm` — 12 hand-crafted OpenQASM 2.0 circuits (Bell state, GHZ, Grover, etc.)
- `samples/qasmbench/` — 252 circuits ingested from [PNNL QASMBench](https://github.com/pnnl/QASMBench) but rebranded as **QTAUBench** in all UI labels and DB records (filesystem directory kept as `qasmbench/` for loader-stability). Running `scripts/migrate_rename_bench_sources.py` on the backend rewrites any legacy `QASMBench` / `MQTBench` source fields in Mongo to `QTAUBench`.
- `samples/aqs-qmc/` — reference Quantum Monte Carlo notebook + `outputs_hybrid_mc_qdist_stable/` which pins the canonical IBM-exec-log JSONL schema that `GET /qae/ibm-log` matches.
  - `small/` — 85 files (2-10 qubits)
  - `medium/` — 47 files (11-27 qubits)
  - `large/` — 120 files (28+ qubits)

## Naming Conventions

- **Classes**: PascalCase (`AppState`, `FastAPIClient`)
- **Methods/properties**: camelCase (`onLogin`, `authToken`)
- **Config/label keys**: snake_case (`base_url`, `nav_welcome`)
- **Screen files**: PascalCase matching tab name (`WelcomeScreen.m`)
- **ViewModel files**: PascalCase with `ViewModel` suffix (`WelcomeViewModel.m`)
- **Service files**: PascalCase with `Service` suffix (`CircuitService.m`)

## Key Patterns

- Errors propagate as `MException` from HTTP → Service → ViewModel, which displays via `uialert()`
- Logger output is structured: `[HH:MM:SS.FFF] LEVEL [Category] Message`
- Button styling uses `StyleHelper` with types `'primary'`, `'secondary'`, `'success'`, `'danger'`, `'ghost'`
- Path resolution uses `fullfile()` throughout (OS-agnostic)
- No hardcoded strings in UI — all text comes from `Labels.get()`
- `JsonHelper.pick(data, {'path1', 'path2'})` walks dotted paths with fallback chains for resilient API field mapping
- File upload in `FastAPIClient` tries `matlab.net.http` multipart first, falls back to system `curl`
- Paginated API list endpoints use `skip` and `limit` query params (max `limit=100`)

## Testing

20 unit test files in `tests/` covering all services, infrastructure, and config utilities. Tests use `StubFastAPIClient.m` as a mock HTTP client for isolated testing without a live backend.

```matlab
runtests('tests')                    % Run all
runtests('tests/test_CircuitService') % Run one
```

## Required MCP Tool Workflow

Every request that involves analyzing, debugging, or modifying code **must** use these MCP tools:

1. **Sequential Thinking** (`mcp__sequential-thinking__sequentialthinking`) — Start here. Break down the problem, plan analysis steps, and reason through the solution before writing code.
2. **Context7** (`mcp__context7__resolve-library-id` → `mcp__context7__query-docs`) — Look up current documentation for any library, framework, or API involved in the task. Always resolve the library ID first, then query docs.
3. **Serena** — Use via SuperClaude skills (`/sc:analyze`, `/sc:reflect`, `/sc:load`) for project-aware deep code analysis, validation, and reflection.

This is not optional. Use all three even for seemingly simple tasks.
