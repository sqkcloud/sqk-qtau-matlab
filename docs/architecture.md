# QTAU Connector Workbench — Architecture Guide

MATLAB R2025b desktop client. Talks to a FastAPI server (`http://34.42.87.190:5715` by default). All persistent state lives server-side; the MATLAB app is **presentation-only** and caches data in-memory per session.

This doc explains how the pieces fit together so a new contributor can figure out where to look for any given feature.

---

## 1. Three-layer clean architecture

```
src/
├── presentation/          ← UI chrome + screens + viewmodels (all MATLAB UI APIs)
│   ├── app/               ← QTAUWorkbenchApp, LayoutBuilder, NavigationManager,
│   │                        OverlayManager, PopupMenuManager, StyleHelper
│   ├── screens/           ← 17 PascalCase screen-builder functions
│   ├── viewmodels/        ← 17 PascalCase *ViewModel classes
│   └── DialogBuilder.m    ← Modal-dialog factory (Login, NewProject, QMC)
│
├── domain/                ← Services + session state + DI
│   ├── ServiceContainer.m
│   ├── models/AppState.m  ← session-scoped mutable state (auth token, project id…)
│   └── services/          ← 11 *Service classes (no UI calls)
│
└── infrastructure/        ← Everything stateless + IO
    ├── AsyncRunner.m      ← async dispatch (backgroundPool / timer)
    ├── http/FastAPIClient ← HTTP gateway (Bearer auth, multipart upload)
    └── config/            ← AppConfig, Labels, Logger, Theme, JsonHelper, CircuitDiagram
```

**Data flows one way**: `Screen → ViewModel → Service → FastAPIClient → HTTP`.
Screens never build services; services never touch UI. The bridge is always a ViewModel.

---

## 2. The dependency-injection wiring

All services are constructed once in `ServiceContainer.buildServices(client)` and attached to the main app via `QTAUWorkbenchApp` constructor. ViewModels receive the `app` reference and read `app.<XxxSvc>` / `app.State` / `app.UIFigure`.

```
FastAPIClient (1)
   └── ServiceContainer.buildServices()
          ├── AuthSvc        → /api/auth/*
          ├── ProjectSvc     → /api/projects/*
          ├── CircuitSvc     → /api/circuits/*
          ├── BackendSvc     → /api/backends/*
          ├── BenchmarkSvc   → /api/benchmark/*
          ├── PredictionSvc  → /api/predictions/*
          ├── JobSvc         → /api/jobs/*
          ├── QmcSvc         → /api/circuits/*/qae/*  +  /api/qae/jobs/*
          │                    (formerly QaeSvc — class & property renamed
          │                     to QMC; HTTP routes still use the legacy
          │                     /qae/ path on the server)
          ├── CuttingSvc     → /api/cutting/*  +  /api/circuits/*/cutting/batches
          ├── QecEngineSvc   → local-only (no backend)
          ├── ReportSvc      → /api/reports/*
          └── SettingsSvc    → /api/settings/*
```

`AppState` (one instance, long-lived) holds the session: `authToken`, `tokenType`, `currentUser`, `currentProjectId`, `currentProjectName`, `selectedCircuitId`, etc. Every ViewModel reads/writes via `app.State.*`.

---

## 3. Screen ↔ ViewModel ↔ Service matrix

| Screen (sidebar label) | ViewModel | Service(s) used |
|---|---|---|
| Welcome | WelcomeViewModel | Auth, Project, Settings |
| Dashboard | DashboardViewModel | Project |
| Circuits | CircuitsViewModel | Circuit |
| Notes *(hidden)* | NotesViewModel | Project |
| Upload | UploadViewModel | Circuit |
| Analysis | AnalysisViewModel | Circuit, Backend, **Qmc**, Report |
| Detailed Analysis | DetailedAnalysisViewModel | Circuit, Job |
| Backends | BackendsViewModel | Backend, Circuit, Job, Settings |
| Benchmark | BenchmarkViewModel | Backend, Circuit, Job, Project, Settings |
| Benchmark Dashboard | BenchmarkDashboardViewModel | Backend, Benchmark, Circuit |
| **Circuit Cutting** | **CircuitCuttingViewModel** | **Cutting, Backend, Circuit** |
| Prediction | PredictionViewModel | Backend, Circuit, Job, Prediction, Settings |
| Jobs | JobsViewModel | Job, Circuit |
| Results | ResultsViewModel | Job, **Cutting** |
| Reports | ReportsViewModel | Project, Report |
| Settings | SettingsViewModel | Settings |
| QEC Simulation | QecSimulationViewModel | *(local simulator only)* |
| QEC Visualization | QecVisualizationViewModel | *(local rendering only)* |

`QTAUWorkbenchApp.autoLoadScreen(key)` decides whether the screen needs to (re)fetch on every navigation — see § 6.

---

## 4. Data lifecycle — where results come from

All persistent state lives on the server. The MATLAB client **never** talks to IBM Quantum directly. Counts, calibration, predictions, and report artifacts all flow through our FastAPI + MongoDB.

### IBM Quantum job results — the full round-trip

This is the one with the most moving parts. Trace a job's counts from IBM to the Results screen:

```
IBM Quantum (remote)
        │  ibm_job.result()
        ▼
_refresh_ibm_status()                        (API:  qdash/api/services/job_service.py)
        │  • Status: "DONE" / "JobStatus.DONE" → normalized to "completed"
        │  • counts = _extract_counts_from_result(result)
        │    probes data.meas → data.c → walks DataBin fields
        ▼
MongoDB `ibm_job` doc                         (persistent cache)
        │  { status: "completed",
        │    raw_counts: { "01011010…": 512, … },
        │    result_metadata: { shots: 4096 },
        │    completed_at: "2026-…" }
        ▼
GET /api/jobs/{job_record_id}/results         (FastAPI router)
        │  ResultsService.get_result_summary():
        │  counts = doc.get("raw_counts")   ← READS FROM MONGO, NOT IBM
        ▼
JobService.getJobResults() / ResultsService   (MATLAB:  src/domain/services/JobService.m)
        │
        ▼
ResultsViewModel.onRefresh()                  (MATLAB:  src/presentation/viewmodels/)
        │  Populates app.ResultsFidelityLabel / tables / distribution
        ▼
Results screen
```

Two implications:

1. **MATLAB only ever reads `raw_counts` from Mongo.** If counts aren't there, the Results screen is blank.
2. **Only the API service bridges to IBM.** It does this lazily on two triggers:
   - Status poll (`_refresh_ibm_status`) when viewing a job whose status is `queued` / `running`.
   - Back-fill when a `completed` / `done` / `success` job has no `raw_counts` yet (e.g. migrated from an older status-mapping bug). Handled by `_needs_ibm_refresh(doc)`.

When the Results screen is empty, the fix is always upstream — get counts into Mongo — never retry the MATLAB call.

### Other data shapes (summary)

| Data | Authoritative source | Cache in MATLAB? |
|---|---|---|
| Auth token | FastAPI `/api/auth/login` | `AppState.authToken` (session only) |
| Project list | MongoDB `project` | `WelcomeVm.Projects` until next `isScreenFresh` miss |
| Circuit list | MongoDB `circuit` | `CircuitsVm.Circuits`, shared by Analysis & Upload |
| Backend list / calibration | Mongo cache + IBM Runtime passthrough | `BackendsVm.Backends` |
| Benchmark / volumetric / scorecard | MongoDB `benchmark_*` collections | `BenchmarkVm.*` |
| Predictions | MongoDB `prediction` | `PredictionVm.Predictions` |
| Jobs | MongoDB `ibm_job`, lazy-refreshed from IBM | `JobsVm.Rows` |
| QAE result | MongoDB `circuit.qae` field | `AnalysisVm.QmcLastResult` |
| Reports | MongoDB `report` + file bytes | not cached — streamed per click |
| Settings / IBM config | MongoDB `settings` | `SettingsVm.Cfg` |

---

## 5. HTTP — FastAPIClient

One gateway for every request. Three things to know:

1. **Bearer auth** — `X-Project-Id` and `Authorization: Bearer …` are added automatically from `AppState` when `Client.ProjectId` and `Client.AuthToken` are set.
2. **File upload** — `uploadViaHttpNet` (R2025b multipart via `matlab.net.http.MessageBody`) with a `curl` fallback for environments where httpnet chokes.
3. **Error handling** — non-2xx throws `MException`. Services propagate; ViewModels catch and render via `uialert(app.UIFigure, …)`.

All endpoint names, shapes, and response codes are in [`fastapi_contract.md`](./fastapi_contract.md) and the generated [`openapi.json`](./openapi.json).

---

## 6. Navigation & caching (the one place most features hook in)

`NavigationManager.onSelectSection(key)` is the centre of screen-switching.

```
user clicks nav button
   │
   ▼
NavigationManager.onNavHtmlClick
   │  (onNavHtmlClick filters struct vs string Data; structs are our own
   │   setActive pushes from updateNavStyles, ignored)
   ▼
QTAUWorkbenchApp.onSelectSection(key)
   │
   ├─→ hide all SectionPanels, show the matching one
   ├─→ NavigationManager.updateNavStyles(app, key)        ← pushes Data,
   │                                                        JS toggles class
   └─→ NavigationManager.autoLoadScreen(app, key)
            │
            ├─→ isScreenFresh(Vm, ttl) ?  ← screen_cache_ttl (default 30 s)
            │        yes → no-op, snap instantly
            │        no  → showNavLoading(key) + Vm.onFetch…()
            │              (VM's done/error callback calls hideLoading)
            │
            └─→ 20 s safety timer auto-dismisses the overlay so a
                forgetful VM can't leave it stuck (armNavOverlayTimer)
```

Every VM that owns async work tracks its own `Vm.LastLoaded = datetime('now')`. `isScreenFresh` returns true while `now - LastLoaded < ttl`.

### Two screens are special

- **Jobs** runs a 5-second auto-refresh timer (`JobsViewModel.startAutoRefresh`) while visible, polling `/api/jobs` silently (no overlay). Timer self-terminates when the user leaves.
- **Analysis → QMC dialog** runs a 3-second poll timer against `/api/qae/jobs/{id}` while the popup is open. Closing the popup stops the timer; the server keeps running — re-opening the dialog re-hydrates from `circuit.qae`.

---

## 7. Async work — `AsyncRunner`

Long calls (circuit upload, QAE analyze, backend list with IBM round-trip) go through `AsyncRunner.run(fn, onDone, onError)`.

- Under MATLAB R2025b the default pool is `backgroundPool` (thread-based, shares heap).
- Fallback is a `timer` with `TimerFcn` on the UI thread — slower but always available.

VMs feed the loading overlay into the completion callbacks:

```matlab
app.showLoading('Running QMC…');
AsyncRunner.run(...
    @() app.QaeSvc.analyze(cid, payload, app.State.authToken), ...
    @(res) obj.onQaeAnalysisDone(res), ...
    @(err) obj.onQaeAnalysisError(err));
```

Error handlers always call `app.hideLoading()` so the overlay never gets stuck.

---

## 8. Externalized configuration

| File | Key format | Read via |
|---|---|---|
| `resources/app.properties` | `base_url`, `login_path`, `screen_cache_ttl`, … | `AppConfig.get(key)`, `AppConfig.getDouble(key, default)` |
| `resources/labels.properties` | 600+ keys, `nav_welcome`, `error_login_unauthorized`, … | `Labels.get(key, fallback)` |
| `resources/seed.properties` | `admin_username`, `admin_password` | `scripts/seed_helpers.m` |

Hot-reload both at runtime: `AppConfig.reload(); Labels.reload();`. No restart needed.

---

## 9. UI primitives worth knowing

### `uihtml` components with callbacks

Only four exist in the whole app — they're the ones that can race with their own events:

- `LoginDlgBaseUrlField`, `LoginDlgUsernameField`, `LoginDlgPasswordField` (in `DialogBuilder.buildLoginDialog`)
- `NavHtml` (in `LayoutBuilder`, managed by `NavigationManager`)

Rules when deleting or replacing one of these:

1. Detach `DataChangedFcn = ''` first.
2. `drawnow` to flush queued events.
3. Then `delete(component)` or reassign `HTMLSource`.

See `WelcomeViewModel.onLogin` and `DialogBuilder.closeLoginDialog` for the canonical pattern.

For NavHtml specifically, `updateNavStyles` pushes `Data = struct('a','setActive','name',key)` instead of rebuilding `HTMLSource` on every nav click — the JS handler toggles the `.active` class in place. `renderNavHtml` only re-renders on initial build, collapse toggle, and theme change.

### Loading overlay

- `app.showLoading('message…')` — fades in the `LoadingOverlay` uihtml and arms the 20 s safety timer.
- `app.hideLoading()` — fades out and disarms the safety timer.
- Rapid navigation is safe: both methods cross-cancel.

### Theme

- `Theme.applyFigureMode(fig, name)` on any uifigure keeps it in sync with the active palette.
- `Theme.COLOR_*` constants are the palette; all screens and dialogs should use these, never hard-code colours.

---

## 10. Logs & telemetry

`Logger.info|warn|error|debug|auth|nav|api|http|ui(category, fmt, args…)` produces:

```
[HH:MM:SS.FFF] LEVEL    [Category         ] Message
```

Categories in use: `QTAUWorkbenchApp`, `AnalysisViewModel`, `FastAPIClient`, `CircuitService`, `NavigationManager`, `DialogBuilder`, `AsyncRunner`, plus each screen's builder function.

---

## 11. Where things live — quick reference

| Question | Look here |
|---|---|
| Which endpoint does Screen X hit? | `src/presentation/viewmodels/XViewModel.m` → the `app.*Svc.*()` calls |
| What does response field Y map to? | `src/domain/services/*.m` + `JsonHelper.pick(data, {'a','b','c'})` in ViewModels |
| Why is the nav sidebar showing the wrong active item? | `NavigationManager.renderNavHtml` / `updateNavStyles` |
| Why is the overlay stuck? | VM didn't call `hideLoading()`; safety timer fires at 20 s |
| Why is a field blank on Results? | Mongo `ibm_job.raw_counts` is missing — see § 4 |
| How do I change a UI string? | `resources/labels.properties`, then `Labels.reload()` |
| How do I enable Notes? | Re-add `'Notes'` to `navNames`/`navLabels`/`navIcons` in `NavigationManager.m` |
| What's cached and for how long? | `AppConfig screen_cache_ttl` + `isScreenFresh` in `NavigationManager.m` |
