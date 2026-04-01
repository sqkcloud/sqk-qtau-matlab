# QDash Workbench — QTAU Connector

A professional MATLAB R2025b desktop application for managing quantum circuit experiments through a FastAPI backend.
Built with clean three-layer architecture (presentation / domain / infrastructure), externalized configuration, and structured logging.

---

## Quick Start

### Option 1 — Open via Project Manager (recommended)

1. In MATLAB, go to **Home → Open → Open Project**
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

That's it. `QTAUWorkbenchLauncher.m` sets up the MATLAB search path and starts the app in one step.

---

## Configuration

All settings live in `resources/` — no source code changes needed.

| File | Purpose |
|---|---|
| `resources/app.properties` | API endpoint, timeout, app metadata |
| `resources/labels.properties` | All UI text strings (600+) |

To change the backend URL, edit `resources/app.properties`:

```properties
base_url=http://34.42.87.190:5715
login_path=/api/auth/login
http_timeout=30
```

`login_path` is the POST path for username/password login (no host). If your API serves login at `/auth/login` instead of `/api/auth/login`, set `login_path=/auth/login`.

### Login returns HTTP 401

A **401 Unauthorized** response means the server rejected the request: wrong username/password, account missing, or account disabled. It is not a MATLAB bug. Confirm credentials with whoever administers the QTAU API, or check the server logs. After pulling the latest code, login uses `webwrite` with form fields `username` and `application/x-www-form-urlencoded` as required by the OpenAPI contract.

---

## Architecture

Three-layer clean architecture under `src/`:

```
src/
├── presentation/          ← UI layer
│   ├── app/               ← Main application class
│   ├── screens/           ← Screen builder functions (pure UI layout)
│   └── viewmodels/        ← ViewModel classes (callbacks, event logic)
├── domain/                ← Business logic layer
│   ├── models/            ← Session-scoped state
│   └── services/          ← API service classes
└── infrastructure/        ← Technical foundation
    ├── http/              ← HTTP gateway
    └── config/            ← Static utilities
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
│   │   │   └── QTAUWorkbenchApp.m    ← Main app class (UI chrome, navigation, service wiring)
│   │   ├── screens/                  ← 13 screen builder functions
│   │   │   ├── WelcomeScreen.m
│   │   │   ├── DashboardScreen.m
│   │   │   ├── UploadScreen.m
│   │   │   ├── AnalysisScreen.m
│   │   │   ├── DetailedAnalysisScreen.m
│   │   │   ├── BackendsScreen.m
│   │   │   ├── BenchmarkScreen.m
│   │   │   ├── PredictionScreen.m
│   │   │   ├── JobsScreen.m
│   │   │   ├── ResultsScreen.m
│   │   │   ├── ReportsScreen.m
│   │   │   ├── NotesScreen.m
│   │   │   └── SettingsScreen.m
│   │   └── viewmodels/               ← 13 ViewModel classes
│   │       ├── WelcomeViewModel.m
│   │       ├── DashboardViewModel.m
│   │       ├── UploadViewModel.m
│   │       ├── AnalysisViewModel.m
│   │       ├── DetailedAnalysisViewModel.m
│   │       ├── BackendsViewModel.m
│   │       ├── BenchmarkViewModel.m
│   │       ├── PredictionViewModel.m
│   │       ├── JobsViewModel.m
│   │       ├── ResultsViewModel.m
│   │       ├── ReportsViewModel.m
│   │       ├── NotesViewModel.m
│   │       └── SettingsViewModel.m
│   ├── domain/
│   │   ├── models/
│   │   │   └── AppState.m            ← Session-scoped mutable state
│   │   └── services/                 ← 7 service classes
│   │       ├── BackendService.m
│   │       ├── CircuitService.m
│   │       ├── JobService.m
│   │       ├── PredictionService.m
│   │       ├── ProjectService.m
│   │       ├── ReportService.m
│   │       └── SettingsService.m
│   └── infrastructure/
│       ├── http/
│       │   └── FastAPIClient.m       ← HTTP gateway (webread/webwrite, Bearer auth)
│       └── config/
│           ├── AppConfig.m           ← Reads app.properties
│           ├── Labels.m              ← Reads labels.properties
│           ├── Logger.m              ← Structured logger
│           └── JsonHelper.m          ← JSON decode / table mapping
│
├── resources/                        ← Externalized configuration
│   ├── app.properties
│   ├── labels.properties
│   └── sqk-logo-*.svg
│
├── docs/                             ← API documentation
│   ├── fastapi_contract.md
│   └── openapi.json
│
├── scripts/
│   ├── launch.m                      ← Launcher if CWD is scripts/
│   └── seed_projects.m               ← Seed demo projects via API
│
├── tests/                            ← Unit tests
│   ├── test_AppConfig.m
│   └── test_Labels.m
│
└── output/                           ← Generated logs, plots, reports (git-ignored)
```

---

## Key Features

- **13-tab workflow UI** — Welcome, Dashboard, Upload, Analysis, Detailed Analysis, Backends, Benchmark, Prediction, Jobs, Results, Reports, Notes, Settings
- **Google-inspired login dialog** — Clean, professional sign-in card with externalized labels
- **Auto-loading Dashboard** — Navigating to Dashboard automatically fetches live data from the API
- **Project context tracking** — Selected project name and ID persist across all screens via AppState
- **Externalized text** — 600+ UI strings in `labels.properties` (change text without editing code)
- **Structured logging** — `[HH:MM:SS.FFF] LEVEL [Category] Message` format via `Logger`

---

## Running Tests

```matlab
runtests('tests')

% Run a single test file
runtests('tests/test_AppConfig')
```

---

## FastAPI Backend Endpoints

The client (`src/infrastructure/http/FastAPIClient.m`) expects these routes on the configured `base_url`:

| Method | Endpoint |
|---|---|
| `GET` | `/health` |
| `POST` | `/api/auth/login` |
| `GET` | `/api/users/me` |
| `GET/POST` | `/api/projects` |
| `GET` | `/api/projects/{id}/dashboard` |
| `POST` | `/api/circuits/upload` |
| `POST` | `/api/circuits/{id}/analyze` |
| `GET` | `/api/backends` |
| `POST` | `/api/projects/{id}/benchmark-config` |
| `POST` | `/api/predict` |
| `GET` | `/api/jobs` |
| `GET` | `/api/jobs/{id}/results` |
| `POST` | `/api/reports/generate` |
| `GET/PUT` | `/api/settings` |

Full contract: [`docs/fastapi_contract.md`](docs/fastapi_contract.md)

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Classes | PascalCase | `AppState`, `FastAPIClient` |
| Methods / properties | camelCase | `onLogin`, `authToken` |
| Config / label keys | snake_case | `base_url`, `nav_welcome` |
| Screen files | PascalCase + `Screen` | `WelcomeScreen.m` |
| ViewModel files | PascalCase + `ViewModel` | `WelcomeViewModel.m` |

---

## Packaging as a Toolbox

This is source code, not a compiled `.mltbx`. To package:

1. Open the project via the `.prj` file
2. Go to **Home → Add-Ons → Package Toolbox**
3. Set entry point to `src/presentation/app/QTAUWorkbenchApp.m`
