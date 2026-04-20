# QDash Workbench — QTAU Connector

A professional **MATLAB R2025b** desktop application for managing quantum circuit experiments through a FastAPI backend.
Built with clean three-layer architecture (presentation / domain / infrastructure), externalized configuration, and structured logging.

---

## Quick Start

### Option 1 — Open via Project Manager (recommended)

1. In MATLAB, go to **Home > Open > Open Project**
2. Select `sqk-qtau-matlab.prj`
3. MATLAB configures the path and launches the app automatically

Or from the Command Window:

```matlab
matlab.project.openProject('sqk-qtau-matlab.prj')
```

### Option 2 — Single command (no project file needed)

```matlab
cd('/path/to/sqk-qtau-matlab')
run('QTAUWorkbenchLauncher.m')
```

`QTAUWorkbenchLauncher.m` sets up the MATLAB search path and starts the app in one step.

---

## Configuration

All settings live in `resources/` — no source code changes needed.

| File | Purpose |
|---|---|
| `resources/app.properties` | API endpoint, timeout, app metadata, QEC defaults |
| `resources/labels.properties` | All UI text strings (600+) |
| `resources/seed.properties` | Seed script credentials (copy from `.example`) |

To change the backend URL, edit `resources/app.properties`:

```properties
base_url=http://34.42.87.190:5715
login_path=/api/auth/login
http_timeout=30
```

### Login returns HTTP 401

A **401 Unauthorized** response means the server rejected the request: wrong username/password, account missing, or account disabled. Confirm credentials with whoever administers the QTAU API, or check the server logs.

---

## Architecture

Three-layer clean architecture under `src/`:

```
src/
├── presentation/          ← UI layer
│   ├── app/               ← Main app class, layout, navigation, styling, overlays
│   ├── screens/           ← 17 screen builder functions (pure UI layout)
│   └── viewmodels/        ← 17 ViewModel classes (callbacks, event logic)
├── domain/                ← Business logic layer
│   ├── models/            ← Session-scoped state (AppState)
│   ├── services/          ← 10 service classes
│   └── ServiceContainer.m ← Dependency injection container
└── infrastructure/        ← Technical foundation
    ├── http/              ← HTTP gateway (FastAPIClient)
    ├── config/            ← Static utilities (AppConfig, Labels, Logger, JsonHelper, Theme, CircuitDiagram)
    └── AsyncRunner.m      ← Async execution wrapper
```

**Data flow:** Screen → ViewModel → Service → FastAPIClient → HTTP

- **Screens** are functions that build UI into a provided container. They return no object.
- **ViewModels** are classes that own callbacks; they call services and update UI.
- **Services** receive `FastAPIClient` via constructor (dependency injection). They have no UI dependencies.
- **AppState** is instantiated once by `QTAUWorkbenchApp` and shared across ViewModels for the session lifetime.
- **Static utilities** (`AppConfig`, `Labels`, `Logger`, `JsonHelper`) use static methods with cached state; call `.reload()` to refresh.

---

## Project Structure

```
sqk-qtau-matlab/
├── QTAUWorkbenchLauncher.m           ← Single-command launcher (path setup + start app)
├── sqk-qtau-matlab.prj               ← MATLAB Project Manager file
├── README.md
├── CLAUDE.md
│
├── src/
│   ├── presentation/
│   │   ├── app/
│   │   │   ├── QTAUWorkbenchApp.m    ← Main app class (UI chrome, navigation, service wiring)
│   │   │   ├── LayoutBuilder.m       ← UI layout utilities
│   │   │   ├── NavigationManager.m   ← Screen switching logic
│   │   │   ├── OverlayManager.m      ← Overlay/modal management
│   │   │   ├── PopupMenuManager.m    ← Context menu management
│   │   │   └── StyleHelper.m         ← UI styling utilities
│   │   ├── screens/                  ← 17 screen builder functions
│   │   │   ├── WelcomeScreen.m
│   │   │   ├── DashboardScreen.m
│   │   │   ├── CircuitsScreen.m
│   │   │   ├── NotesScreen.m
│   │   │   ├── UploadScreen.m
│   │   │   ├── AnalysisScreen.m
│   │   │   ├── DetailedAnalysisScreen.m
│   │   │   ├── BackendsScreen.m
│   │   │   ├── BenchmarkScreen.m
│   │   │   ├── BenchmarkDashboardScreen.m
│   │   │   ├── PredictionScreen.m
│   │   │   ├── JobsScreen.m
│   │   │   ├── ResultsScreen.m
│   │   │   ├── ReportsScreen.m
│   │   │   ├── SettingsScreen.m
│   │   │   ├── QecSimulationScreen.m
│   │   │   └── QecVisualizationScreen.m
│   │   ├── viewmodels/               ← 17 ViewModel classes
│   │   │   ├── WelcomeViewModel.m
│   │   │   ├── DashboardViewModel.m
│   │   │   ├── CircuitsViewModel.m
│   │   │   ├── NotesViewModel.m
│   │   │   ├── UploadViewModel.m
│   │   │   ├── AnalysisViewModel.m
│   │   │   ├── DetailedAnalysisViewModel.m
│   │   │   ├── BackendsViewModel.m
│   │   │   ├── BenchmarkViewModel.m
│   │   │   ├── BenchmarkDashboardViewModel.m
│   │   │   ├── PredictionViewModel.m
│   │   │   ├── JobsViewModel.m
│   │   │   ├── ResultsViewModel.m
│   │   │   ├── ReportsViewModel.m
│   │   │   ├── SettingsViewModel.m
│   │   │   ├── QecSimulationViewModel.m
│   │   │   └── QecVisualizationViewModel.m
│   │   └── DialogBuilder.m           ← Dialog creation utilities
│   │
│   ├── domain/
│   │   ├── ServiceContainer.m        ← Dependency injection container
│   │   ├── models/
│   │   │   └── AppState.m            ← Session-scoped mutable state
│   │   └── services/                 ← 10 service classes
│   │       ├── AuthService.m
│   │       ├── BackendService.m
│   │       ├── BenchmarkService.m
│   │       ├── CircuitService.m
│   │       ├── JobService.m
│   │       ├── PredictionService.m
│   │       ├── ProjectService.m
│   │       ├── QecEngineService.m
│   │       ├── ReportService.m
│   │       └── SettingsService.m
│   │
│   └── infrastructure/
│       ├── AsyncRunner.m             ← Async execution wrapper
│       ├── http/
│       │   └── FastAPIClient.m       ← HTTP gateway (webread/webwrite, Bearer auth, multipart)
│       └── config/
│           ├── AppConfig.m           ← Reads app.properties
│           ├── Labels.m              ← Reads labels.properties (600+ UI strings)
│           ├── Logger.m              ← Structured logger
│           ├── JsonHelper.m          ← JSON decode / table mapping
│           ├── CircuitDiagram.m      ← Circuit visualization and rendering
│           └── Theme.m               ← UI color and styling constants
│
├── resources/                        ← Externalized configuration
│   ├── app.properties                ← API endpoint, timeout, QEC defaults
│   ├── labels.properties             ← 600+ UI text strings
│   ├── seed.properties               ← Seed credentials (git-ignored)
│   ├── seed.properties.example       ← Seed credentials template
│   └── sqk-logo-*.svg               ← Application logo
│
├── docs/                             ← API documentation
│   ├── fastapi_contract.md           ← Endpoint contract with request/response examples
│   └── openapi.json                  ← OpenAPI 3.0 specification
│
├── scripts/                          ← Seed and utility scripts
│   ├── launch.m                      ← Launcher if CWD is scripts/
│   ├── seed_all.m                    ← Master orchestrator (runs all seed scripts)
│   ├── seed_helpers.m                ← Shared auth and HTTP utilities
│   ├── seed_projects.m              ← Seed 20 demo projects
│   ├── seed_circuits.m              ← Seed 10 sample OpenQASM circuits
│   ├── seed_qasmbench.m             ← Seed 113+ QTAUBench benchmark circuits
│   ├── seed_qasmbench_invalid.m     ← Re-upload previously invalid QTAUBench circuits
│   ├── seed_backends.m              ← Seed backend selections
│   ├── seed_benchmarks.m            ← Seed benchmark configurations
│   ├── seed_predictions.m           ← Seed fidelity predictions
│   ├── seed_jobs.m                  ← Seed job submissions
│   ├── seed_reports.m               ← Seed generated reports
│   ├── seed_notes.m                 ← Seed markdown notes
│   └── seed_settings.m             ← Seed user preferences
│
├── samples/                          ← OpenQASM circuit files
│   ├── *.qasm                        ← 12 hand-crafted sample circuits
│   └── qasmbench/                    ← QTAUBench benchmark suite (252 circuits)
│       ├── small/                    ← 2-10 qubits (85 files)
│       ├── medium/                   ← 11-27 qubits (47 files)
│       └── large/                    ← 28+ qubits (120 files)
│
├── tests/                            ← 20 unit test files
│   ├── StubFastAPIClient.m          ← Mock HTTP client for testing
│   ├── test_AppConfig.m
│   ├── test_AppState.m
│   ├── test_AsyncRunner.m
│   ├── test_AuthService.m
│   ├── test_BackendService.m
│   ├── test_BenchmarkService.m
│   ├── test_CircuitService.m
│   ├── test_FastAPIClient.m
│   ├── test_JobService.m
│   ├── test_JsonHelper.m
│   ├── test_Labels.m
│   ├── test_Logger.m
│   ├── test_PredictionService.m
│   ├── test_ProjectService.m
│   ├── test_QecEngineService.m
│   ├── test_ReportService.m
│   ├── test_ServiceContainer.m
│   ├── test_SettingsService.m
│   └── test_Theme.m
│
└── output/                           ← Generated logs, plots, reports (git-ignored)
```

---

## Key Features

- **17-screen workflow UI** — Welcome, Dashboard, Circuits, Notes, Upload, Analysis, Detailed Analysis, Backends, Benchmark, Benchmark Dashboard, Prediction, Jobs, Results, Reports, Settings, QEC Simulation, QEC Visualization
- **Google-inspired login dialog** — Professional sign-in card with externalized labels
- **Auto-loading screens** — Dashboard and other screens auto-fetch data when navigated to
- **Project context tracking** — Selected project persists across all screens via AppState
- **Circuit management** — Browse, upload, analyze, preview SVG diagrams, match against benchmarks
- **QEC simulation engine** — Surface code simulation with configurable noise models and 3D visualization
- **QTAUBench integration** — 252 benchmark circuits from PNNL QTAUBench (small/medium/large)
- **Externalized text** — 600+ UI strings in `labels.properties` (change text without editing code)
- **Structured logging** — `[HH:MM:SS.FFF] LEVEL [Category] Message` format via `Logger`
- **Dependency injection** — Services wired via `ServiceContainer` with `FastAPIClient` injection
- **Comprehensive seed scripts** — 14 scripts to populate the backend with demo data

---

## Running Tests

```matlab
% Run all 20 tests
runtests('tests')

% Run a single test file
runtests('tests/test_AppConfig')
```

Tests use `StubFastAPIClient.m` as a mock HTTP client for isolated unit testing.

---

## Seeding Demo Data

```matlab
% Seed all screens at once
run('scripts/seed_all.m')

% Or seed individual screens
run('scripts/seed_projects.m')
run('scripts/seed_circuits.m')
run('scripts/seed_qasmbench.m')
```

Requires `resources/seed.properties` with `seed_username` and `seed_password`. Copy from `seed.properties.example`.

---

## FastAPI Backend Endpoints

The client communicates with the FastAPI backend across **75 endpoints** organized into 9 categories:

| Category | Key Endpoints | Methods |
|---|---|---|
| **Auth** | `/api/auth/login`, `/api/auth/me`, `/api/auth/logout` | POST, GET |
| **Projects** | `/api/projects`, `/api/projects/{id}/dashboard`, `.../notes`, `.../benchmark-config` | GET, POST, PATCH, DELETE |
| **Circuits** | `/api/circuits`, `/api/circuits/upload/file`, `.../{id}/analyze`, `.../{id}/preview` | GET, POST, PATCH, DELETE |
| **Backends** | `/api/backends`, `.../{name}/calibration`, `.../{name}/topology`, `.../compare` | GET, POST |
| **Benchmarks** | `/api/benchmark/volumetric`, `.../scorecard`, `.../regression`, `.../classify/{id}` | GET |
| **Predictions** | `/api/predict`, `/api/optimize` | POST, GET |
| **Jobs** | `/api/projects/{id}/jobs`, `/api/jobs/{id}/status`, `.../results`, `.../cancel` | GET, POST |
| **Reports** | `/api/reports/generate`, `.../{id}/download`, `.../{id}/share` | GET, POST |
| **Settings** | `/api/settings`, `/api/settings/preferences`, `/api/settings/verify-ibm` | GET, POST, DELETE |

Full contract with request/response examples: [`docs/fastapi_contract.md`](docs/fastapi_contract.md)

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Classes | PascalCase | `AppState`, `FastAPIClient` |
| Methods / properties | camelCase | `onLogin`, `authToken` |
| Config / label keys | snake_case | `base_url`, `nav_welcome` |
| Screen files | PascalCase + `Screen` | `WelcomeScreen.m` |
| ViewModel files | PascalCase + `ViewModel` | `WelcomeViewModel.m` |
| Service files | PascalCase + `Service` | `CircuitService.m` |

---

## Packaging as a Toolbox

This is source code, not a compiled `.mltbx`. To package:

1. Open the project via the `.prj` file
2. Go to **Home > Add-Ons > Package Toolbox**
3. Set entry point to `src/presentation/app/QTAUWorkbenchApp.m`
