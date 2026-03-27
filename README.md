# QDash Workbench — QTAU Connector

A professional MATLAB desktop application for managing quantum circuit experiments through a FastAPI backend.
Built with clean architecture, externalized configuration, and structured logging.

---

## Quick Start

### Option 1 — Open via Project Manager (recommended)

1. In MATLAB, go to **Home → Open → Open Project**
2. Select `sqkcloud-qdash-workbench.prj`
3. MATLAB configures the path and launches the app automatically

Or from the Command Window:

```matlab
matlab.project.openProject('sqkcloud-qdash-workbench.prj')
```

### Option 2 — Single command (no project file needed)

```matlab
cd('/path/to/sqkcloud-qdash-workbench')
run('QTAUWorkbenchLauncher.m')
```

That's it. `QTAUWorkbenchLauncher.m` sets up the MATLAB search path and starts the app in one step.

---

## Configuration

All settings live in `resources/` — no source code changes needed.

| File | Purpose |
|---|---|
| `resources/app.properties` | API endpoint, timeout, app metadata |
| `resources/labels.properties` | All UI text strings |

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

## Project Structure

```
sqkcloud-qdash-workbench/
├── QTAUWorkbenchLauncher.m        ← Single-command launcher (path setup + start app)
├── sqkcloud-qdash-workbench.prj ← MATLAB Project Manager file
├── README.md
│
├── src/                         ← All source code
│   ├── QTAUWorkbenchApp.m                ← Application entry point
│   ├── models/
│   │   └── AppState.m           ← Session state container
│   ├── services/                ← API / infrastructure layer
│   │   ├── FastAPIClient.m
│   │   ├── BackendService.m
│   │   ├── CircuitService.m
│   │   ├── JobService.m
│   │   ├── PredictionService.m
│   │   ├── ProjectService.m
│   │   ├── ReportService.m
│   │   └── SettingsService.m
│   ├── tabs/                    ← UI tab builders (presentation layer)
│   │   ├── WelcomeTab.m
│   │   ├── DashboardTab.m
│   │   ├── UploadTab.m
│   │   ├── AnalysisTab.m
│   │   ├── BackendsTab.m
│   │   ├── BenchmarkTab.m
│   │   ├── PredictionTab.m
│   │   ├── JobsTab.m
│   │   ├── ResultsTab.m
│   │   ├── DetailedAnalysisTab.m
│   │   ├── ReportsTab.m
│   │   ├── NotesTab.m
│   │   └── SettingsTab.m
│   └── utils/                   ← Shared utilities
│       ├── AppConfig.m          ← Reads app.properties
│       ├── Labels.m             ← Reads labels.properties
│       ├── Logger.m             ← Structured logger
│       └── JsonHelper.m         ← JSON decode / table mapping
│
├── resources/                   ← Externalized configuration
│   ├── app.properties           ← API URL, timeout, app metadata
│   ├── labels.properties        ← All UI label strings
│   └── sqk-logo-*.svg
│
├── docs/                        ← API documentation
│   ├── fastapi_contract.md
│   └── openapi.json
│
├── scripts/
│   └── launch.m                 ← Launcher if CWD is scripts/
│
├── tests/                       ← Unit tests
│   ├── test_AppConfig.m
│   └── test_Labels.m
│
└── output/                      ← Generated logs, plots, reports (git-ignored)
```

---

## Running Tests

```matlab
runtests('tests')
```

---

## FastAPI Backend Endpoints

The client (`src/services/FastAPIClient.m`) expects these routes on the configured `base_url`:

| Method | Endpoint |
|---|---|
| `GET` | `/health` |
| `POST` | `/api/auth/login` |
| `GET` | `/api/users/me` |
| `GET/POST` | `/api/projects` |
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

## Packaging as a Toolbox

This is source code, not a compiled `.mltbx`. To package:

1. Open the project via the `.prj` file
2. Go to **Home → Add-Ons → Package Toolbox**
3. Set entry point to `src/QTAUWorkbenchApp.m`
