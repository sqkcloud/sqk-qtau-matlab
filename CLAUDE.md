# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

QDash Workbench is a **MATLAB R2025b** desktop application for managing quantum circuit experiments through a FastAPI backend (QTAU Connector). It provides a 17-screen UI spanning circuit upload, analysis, backend selection, benchmarking, predictions, job monitoring, QEC simulation, and reporting.

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
% Seed QASMBench circuits
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
│   └── services/                 ← 10 service classes
│       ├── AuthService.m         ← Authentication (login/logout/me)
│       ├── BackendService.m      ← Quantum backend management and calibration
│       ├── BenchmarkService.m    ← Volumetric benchmarks, scorecards, regression
│       ├── CircuitService.m      ← Circuit upload, analysis, preview, benchmark matching
│       ├── JobService.m          ← Job submission, polling, results, error trends
│       ├── PredictionService.m   ← Fidelity prediction and optimization
│       ├── ProjectService.m      ← Project CRUD, dashboard, notes, activities
│       ├── QecEngineService.m    ← QEC simulation engine (surface codes, noise models)
│       ├── ReportService.m       ← Report generation, download, sharing
│       └── SettingsService.m     ← User settings and IBM token verification
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

## Screens (17)

| Screen | ViewModel | Purpose |
|--------|-----------|---------|
| WelcomeScreen | WelcomeViewModel | Login, project selection, recent projects |
| DashboardScreen | DashboardViewModel | Workflow summary and readiness storyboard |
| CircuitsScreen | CircuitsViewModel | Browse, search, manage project circuits |
| NotesScreen | NotesViewModel | Working notes and operator memos |
| UploadScreen | UploadViewModel | Circuit upload with format selection and preview |
| AnalysisScreen | AnalysisViewModel | Circuit feature extraction and QASMBench similarity |
| DetailedAnalysisScreen | DetailedAnalysisViewModel | Heatmaps, drift, qubit metrics, cross-run comparisons |
| BackendsScreen | BackendsViewModel | Backend explorer with primary/backup selection |
| BenchmarkScreen | BenchmarkViewModel | Execution parameters, mitigation strategy, cost |
| BenchmarkDashboardScreen | BenchmarkDashboardViewModel | Benchmark configuration summary and recommendations |
| PredictionScreen | PredictionViewModel | Predicted fidelity, distribution, error budget |
| JobsScreen | JobsViewModel | Job monitoring dashboard with logs |
| ResultsScreen | ResultsViewModel | Measured vs predicted vs ideal result analysis |
| ReportsScreen | ReportsViewModel | Report generation and viewing |
| SettingsScreen | SettingsViewModel | Account settings, defaults, storage, notifications |
| QecSimulationScreen | QecSimulationViewModel | QEC simulation under configurable noise models |
| QecVisualizationScreen | QecVisualizationViewModel | 3D Bloch sphere, surface code lattice, error propagation |

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

FastAPIClient talks to a FastAPI server (default `http://localhost:5715`). Auth is username/password POST → Bearer token. The MATLAB client uses **75 endpoints** across 9 categories (auth, projects, circuits, backends, benchmarks, predictions, jobs, reports, settings). Full endpoint contract is in `docs/fastapi_contract.md` and `docs/openapi.json`.

## Seed Scripts (14)

All seed scripts are in `scripts/` and use `seed_helpers.m` for authentication and HTTP setup:

| Script | Data |
|--------|------|
| `seed_all.m` | Master orchestrator — runs all seed scripts in order |
| `seed_projects.m` | 20 demo projects |
| `seed_circuits.m` | 10 sample OpenQASM circuits (inline content) |
| `seed_qasmbench.m` | 113+ QASMBench circuits from `samples/qasmbench/` |
| `seed_qasmbench_invalid.m` | Re-upload 25 previously invalid QASMBench circuits |
| `seed_backends.m` | Backend selections per project |
| `seed_benchmarks.m` | Benchmark configs and strategy comparisons |
| `seed_predictions.m` | Fidelity predictions |
| `seed_jobs.m` | Quantum job submissions |
| `seed_reports.m` | Generated reports |
| `seed_notes.m` | Markdown notes and checklists |
| `seed_settings.m` | User preferences |

## Sample Circuits

- `samples/*.qasm` — 12 hand-crafted OpenQASM 2.0 circuits (Bell state, GHZ, Grover, etc.)
- `samples/qasmbench/` — 252 circuits from [PNNL QASMBench](https://github.com/pnnl/QASMBench)
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
