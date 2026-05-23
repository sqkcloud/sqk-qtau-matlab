# QTAU Connector Workbench — Technical Specification

**Version:** 1.2.4 (matches `resources/app.properties:app_version`)
**Platform:** MATLAB R2025b (App Designer / uifigure runtime)
**Backend:** FastAPI (default base URL `http://34.42.87.190:5715`)
**Repository:** `sqk-qtau-matlab` (branch `feature/refactor`)
**Status:** Production toolbox + FEX listing

---

## 1. Purpose & Scope

QTAU Connector Workbench is a MATLAB desktop application that drives end-to-end quantum-circuit experiments against a remote FastAPI control plane (QTAU Connector). It is a thick client: UI chrome, navigation, in-app circuit composing, statevector simulation, and fault-tolerant resource estimation run locally in MATLAB; all persistence, job scheduling, IBM Runtime execution, and report rendering live on the FastAPI server.

The product surfaces **22 screens** (20 visible, 2 hidden — Notes + Upload), wired to **18 domain services**, against approximately **80 REST endpoints**. It is delivered as a MATLAB Project (`sqk-qtau-matlab.prj`) and a File Exchange listing.

This document specifies the runtime architecture, data flow, REST contract surface, and component hierarchy. It does **not** specify business policy (mitigation strategies, surface-code parameters, QMC analytics formulas) — those live alongside the relevant service classes and in `doc/Quantum Error Mitigation.md`, `doc/circuit_cutting_algorithm.md`, and `samples/aqs-qmc/`.

---

## 2. Technology Stack

| Concern | Choice |
|---|---|
| Language | MATLAB R2025b (`classdef` OOP, `uifigure` UI, `matlab.net.http` HTTP) |
| UI framework | App Designer / uifigure (uigridlayout, uipanel, uiaxes, uihtml, uitable) |
| HTTP transport | `matlab.net.http.*` (primary), `webread` / `webwrite` (GET/PUT/PATCH/DELETE), `curl` (file-upload fallback) |
| Encoding | UTF-8 (explicit `unicode2native` on POST bodies) |
| Auth | OAuth2-Password (`application/x-www-form-urlencoded` → Bearer JWT) |
| Project headers | `X-Project-Id` injected by `FastAPIClient.ProjectId` |
| Async primitives | `parfeval` (`AsyncRunner`), MATLAB `timer` (polling, auto-refresh), `onCleanup` (resource scope) |
| Local sim | Statevector engine, ≤ 14 qubits (`StatevectorSimulator`) |
| Local QEC | Closed-form analytical engine + Monte-Carlo path (`QecEngineService`) |
| Local FT estimator | Surface-code distance + 15-to-1 distillation (`ResourceEstimatorService`) |
| Config | `.properties` files in `resources/`, cached statically with `.reload()` |
| Tests | MATLAB `runtests`, 31 files using `StubFastAPIClient` |
| Build | None — interpreted; `scripts/package_release.m` produces the toolbox bundle |

---

## 3. High-Level Architecture

Three-layer **Clean Architecture** with one-way dependencies pointing inward:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PRESENTATION                                                        │
│   QTAUWorkbenchApp  (UI chrome, owns AppState + ServiceContainer)   │
│   ├── LayoutBuilder · NavigationManager · OverlayManager            │
│   ├── PopupMenuManager · StyleHelper · DialogBuilder                │
│   ├── BackgroundTasksIndicator · NotificationCenter · HelpContent   │
│   ├── 22 *Screen.m   (pure UI layout functions)                     │
│   └── 22 *ViewModel.m (callbacks, state binding, service calls)     │
├─────────────────────────────────────────────────────────────────────┤
│ DOMAIN                                                              │
│   ServiceContainer  (DI root)                                       │
│   ├── 14 HTTP-backed services (Auth, Project, Circuit, Backend, …)  │
│   ├── 4  local-only services (QecEngine, ResourceEstimator,         │
│   │      RunPlanner, StatevectorSimulator)                          │
│   └── Models: AppState · CircuitModel · TemplateRegistry            │
├─────────────────────────────────────────────────────────────────────┤
│ INFRASTRUCTURE                                                      │
│   http/FastAPIClient        (HTTP gateway, multipart upload)        │
│   AsyncRunner · PollingRunner · AsyncCancellation · Exporter        │
│   config/AppConfig · Labels · Logger · Theme · JsonHelper           │
│       CircuitDiagram · OversizeDetector                             │
└─────────────────────────────────────────────────────────────────────┘
                              ▼ HTTPS
                         FastAPI backend
```

**Invariants**

- **Infrastructure** has no upward references; `FastAPIClient` knows only `AppConfig` + `Logger`.
- **Services** receive `FastAPIClient` via constructor (DI). They expose typed methods, propagate `MException` upward, never touch UI handles.
- **ViewModels** own all callbacks and UI mutations; they call services with `app.State.authToken` as an argument.
- **Screens** are pure builder *functions* (not classes). They call `app.createSectionPage(key)` to register a hidden panel, populate it, and wire button callbacks to `app.{Name}Vm.onSomething()`.
- **AppState** is a single mutable handle shared across all ViewModels for the session lifetime.
- **ServiceContainer** is instantiated once by `QTAUWorkbenchApp` with the configured base URL.

---

## 4. Component Hierarchy

### 4.1 Bootstrap

```
QTAUWorkbenchLauncher.m
  ├─ kill leftover figures + timers (drainable strong references)
  ├─ if dev (.git present OR QTAU_DEV=1):  clear classes + targeted reload
  ├─ rmpath any stale src/ entries
  ├─ addpath(src/presentation/{app,screens,viewmodels},
  │          src/domain/{models,services},
  │          src/infrastructure/{http,config})
  └─ QTAUWorkbenchApp()           ← entry point
```

### 4.2 `QTAUWorkbenchApp` (1568 LOC)

Owns the figure, the grid, the section panels, the activity log, the overlay stack, and every ViewModel. Delegates non-trivial logic:

| Helper | Responsibility |
|---|---|
| `LayoutBuilder` | One-time uigridlayout / header / nav / overlay construction |
| `NavigationManager` | `onSelectSection`, lazy screen build, prefetch, nav styling, resize, cache TTL |
| `OverlayManager` | `showLoading` / `hideLoading`, auth overlay, error dialogs, safety timer |
| `PopupMenuManager` | Right-click menus for Projects & Circuits tables |
| `StyleHelper` | Buttons (`primary` / `secondary` / `success` / `danger` / `ghost`), axes styling, table styling |
| `DialogBuilder` | Login dialog, NewProject, EditProject, **Quantum Monte Carlo modal** |
| `BackgroundTasksIndicator` | Tray icon for `BackgroundTaskManager` |
| `NotificationCenter` | Toast / inline notifications |
| `HelpContent` | Per-screen `?` help body |
| `ChartHelper` | Chart axes config shared across screens |

### 4.3 Screen ↔ ViewModel pairs (22 each)

`{Name}Screen.m` is a function `Screen(app)`; `{Name}ViewModel.m` is a `classdef ViewModel < handle` constructed with `app`. See `CLAUDE.md` § Screens for the per-screen feature contract. Hidden in sidebar: `Notes`, `Upload` (Composer and Circuits toolbars are the canonical authoring / import entry points).

### 4.4 Service catalog

| Service | HTTP | Purpose |
|---|:--:|---|
| `AuthService` | ✓ | login / logout / me / list projects |
| `ProjectService` | ✓ | project CRUD, dashboard, activities, notes, benchmark config, latest prediction, reports |
| `CircuitService` | ✓ | upload (multipart or text), list (paged), get, analyze, preview, match-benchmarks, update, delete |
| `BackendService` | ✓ | list / get / calibration / calibration history / topology / compare / save+get selection |
| `BenchmarkService` | ✓ | volumetric, system metrics, scorecard, regression, classify, prediction calibration |
| `PredictionService` | ✓ | predict (multi-backend), getPrediction, optimize |
| `JobService` | ✓ | submit (project-scoped), list, get, status, cancel, pause, results, detailed results, error trends, RB decay |
| `ReportService` | ✓ | generate, list, get, download (PDF binary), share |
| `SettingsService` | ✓ | get / save preferences, IBM credentials verify, clear cache |
| `QmcService` | ✓ | submit async QAE, poll job, cancel job, get cached result, download IBM exec log |
| `CuttingService` | ✓ | analyze cuts, list presets, create batch (202), poll, get result, sibling pair, cancel, list batches |
| `MitigationService` | ✓ | list levels, estimate cost per chip × strategy |
| `QecEngineService` | – | local closed-form + Monte-Carlo QEC simulation, code comparison, surface-code sweep |
| `ResourceEstimatorService` | – | surface-code distance, physical/logical qubits, T-state budget, runtime |
| `RunPlannerService` | – | Pareto frontier over (cost, fidelity) candidates, pick-optimal under target |
| `StatevectorSimulator` | – | ≤ 14 qubits, gate-by-gate, Bloch + top-K amplitudes |
| `BundleService` | – | reproducibility ZIP — QASM + 3 Python ecosystems + manifest.json + README + SHA-256 |
| `BackgroundTaskManager` | – | in-process task registry for the tray indicator |

### 4.5 Infrastructure

```
infrastructure/
├── http/FastAPIClient.m  (613 LOC — HTTP gateway, multipart, error normalization)
├── AsyncRunner.m         (parfeval wrapper, future result handling)
├── PollingRunner.m       (timer-driven polling primitive used by QAE + cutting)
├── AsyncCancellation.m   (cancellation token plumbed through PollingRunner)
├── Exporter.m            (QASM/Qiskit/Cirq/Braket code export from CircuitModel)
└── config/
    ├── AppConfig.m       (static cached read of resources/app.properties)
    ├── Labels.m          (static cached read of resources/labels.properties — 600+ strings)
    ├── Logger.m          (DEBUG/HTTP/INFO/WARN/ERROR; level read from log_level)
    ├── JsonHelper.m      (dotted-path pick, table mapping, list-envelope extraction)
    ├── Theme.m           (color + font constants)
    ├── CircuitDiagram.m  (SVG rendering used by Circuits preview + Composer canvas)
    └── OversizeDetector.m (defends Composer simulator against impossible problem sizes)
```

---

## 5. Data Flow

### 5.1 Synchronous request (canonical path)

```
User click in Screen
   └─ callback → ViewModel.onAction()
       ├─ app.Overlay.showLoading('Action …')
       ├─ try
       │   result = app.Services.{X}Svc.method(args, app.State.authToken)
       │            └─ FastAPIClient.{verb}AuthJson(endpoint, payload, token)
       │                ├─ matlab.net.http.RequestMessage  (POST/PATCH-raw)
       │                ├─ webwrite                          (PUT/PATCH-json)
       │                ├─ webread                           (GET/DELETE)
       │                └─ websave                           (binary downloads)
       │   <- JSON normalised via normalizeJsonResponse
       ├─ JsonHelper.pick / extractListSafe → row shape
       ├─ update app.* UI handles (uitable, uiaxes, uilabel, …)
       ├─ app.State.logActivity('Action', 'Success')   (capped at 500 rows)
       └─ finally: app.Overlay.hideLoading()
```

**Error path.** Non-2xx responses become `MException` with identifier `MATLAB:webservices:HTTPNNNStatusCodeError` whose message embeds the FastAPI `detail` JSON field. `OverlayManager.showError` renders a `uialert`. HTTP 404 on GET is demoted to `Logger.debug` (used as a "does it exist?" probe by QAE-cache and similar idempotent lookups).

### 5.2 Async job polling (QAE / Quantum Monte Carlo)

```
AnalysisViewModel.onRunQae
  ├─ envelope = QmcSvc.submitAnalyze(...)   → HTTP 202 {job_id, status:'queued'}
  ├─ start MATLAB timer (period = 3 s)
  └─ on tick:
        state = QmcSvc.getAnalyzeJob(jobId)
        switch state.status
          'queued'    → overlay 'Queued (0 %)'
          'running'   → overlay 'Running (50 %)'  (server emits progress)
          'completed' → stop timer, render result, enable 'Download IBM Log'
          'failed' / 'cancelled' → stop timer, surface detail
        if user closes dialog mid-run:
          DialogBuilder CloseRequestFcn → AnalysisViewModel.onCloseQaeDialog
          → stop poll timer (server keeps running; result remains cached)
```

The same shape (HTTP 202 + poll + cancel) governs **Circuit Cutting batches** via `CuttingService.{createBatch, pollBatch, getBatchResult, cancelBatch}`.

### 5.3 Background auto-refresh

| Screen | Period | Source | Behaviour |
|---|---|---|---|
| Dashboard | 30 s | `ProjectService.getDashboard` | Silent — no overlay flicker |
| Jobs | 5 s | `JobService.listJobs` | Self-terminates next tick after nav-away |

### 5.4 Session caching

`AppState` holds four lookup caches with `datetime`-stamped freshness predicates:

| Cache | Source endpoint | Consumers |
|---|---|---|
| `CircuitListCache` | `/api/circuits` | Mitigation Compare, Run Planner, Resource Estimator |
| `BackendListCache` | `/api/backends` | All planning screens |
| `BackendPoolCache` | `/api/backends` (normalised) | Circuit Cutting per-row pickers |
| `MitigationLevelsCache` | `/api/mitigation/levels` | Mitigation Compare, Run Planner |

TTL is governed by `resources/app.properties:shared_cache_ttl` (default 120 s) and per-screen `screen_cache_ttl_*` (lookup-driven planning screens hold 5 minutes).

### 5.5 Static-class caching

`AppConfig`, `Labels`, `Logger`, `Theme` keep `persistent` state inside static methods. Call `AppConfig.reload()` / `Labels.reload()` to drop the cache without restarting MATLAB. Dev launches additionally `clear classes` so live `.m` edits take effect.

---

## 6. REST API Surface

The MATLAB client consumes ~80 endpoints across 10 categories. The full request/response contract is in `doc/fastapi_contract.md` and the OpenAPI dump is in `doc/openapi.json`. The condensed inventory:

### 6.1 Authentication
- `POST /api/auth/login` — form-encoded → `{access_token, token_type, username, default_project_id}`
- `GET  /api/auth/me`
- `POST /api/auth/logout`

### 6.2 Projects
- `GET /api/projects`, `POST /api/projects`
- `GET|PATCH|DELETE /api/projects/{project_id}`
- `GET /api/projects/{project_id}/dashboard`
- `GET|POST /api/projects/{project_id}/activities`
- `GET|PUT /api/projects/{project_id}/notes`

### 6.3 Circuits
- `GET /api/circuits`
- `POST /api/circuits/upload` (text), `POST /api/circuits/upload/file` (multipart)
- `GET|PATCH|DELETE /api/circuits/{circuit_id}`
- `POST /api/circuits/{circuit_id}/analyze`
- `GET /api/circuits/{circuit_id}/{analysis,preview}`
- `POST /api/circuits/{circuit_id}/match-benchmarks`

### 6.4 Backends
- `GET /api/backends`, `GET /api/backends/{name}`
- `GET /api/backends/{name}/calibration`
- `GET /api/backends/{name}/calibration_history?days=N&qubit_index=K`
- `GET /api/backends/{name}/topology`
- `POST /api/backends/compare`
- `GET|POST /api/projects/{project_id}/backend-selection`

### 6.5 Benchmark
- `POST|GET /api/projects/{project_id}/benchmark-config`
- `POST /api/projects/{project_id}/benchmark-config/compare-strategies`
- `GET /api/benchmark/volumetric`
- `GET /api/benchmark/system-metrics/{backend_name}`
- `GET /api/benchmark/{scorecard,regression,prediction-calibration}`
- `GET /api/benchmark/classify/{circuit_id}`

### 6.6 Predictions
- `POST /api/predict`, `GET /api/predict/{prediction_id}`
- `POST /api/projects/{project_id}/predict`, `GET /api/projects/{project_id}/predict/latest`
- `POST /api/optimize`

### 6.7 Jobs
- `POST|GET /api/projects/{project_id}/jobs`
- `GET /api/jobs` (sorted DESC by `submitted_at`, self-healing lazy refresh of in-flight IBM jobs)
- `GET /api/jobs/{job_record_id}` and `/status`, `/results`, `/results/detailed`, `/error-trends`, `/rb-decay`
- `POST /api/jobs/{job_record_id}/{cancel,pause}`

### 6.8 QAE / Quantum Monte Carlo
- `POST /api/circuits/{circuit_id}/qae/analyze` → **HTTP 202** `{job_id}`
- `GET  /api/qae/jobs/{job_id}`
- `DELETE /api/qae/jobs/{job_id}`
- `GET /api/circuits/{circuit_id}/qae/result`
- `GET /api/circuits/{circuit_id}/qae/ibm-log?fmt=json|jsonl`

### 6.9 Circuit Cutting
- `POST /api/cutting/analyze`
- `GET /api/cutting/presets`
- `POST /api/circuits/{circuit_id}/cutting/batches` → **HTTP 202**
- `GET /api/cutting/batches/{batch_id}` (+ `/result`, sibling pair)
- `DELETE /api/cutting/batches/{batch_id}`
- `GET /api/cutting/batches?project_id=…`

### 6.10 Mitigation
- `GET /api/mitigation/levels`
- `POST /api/mitigation/estimate`

### 6.11 Reports
- `POST /api/reports/generate`, `GET /api/reports`
- `GET|POST /api/projects/{project_id}/reports`
- `GET /api/reports/{report_id}` and `/download` (binary), `/share`

### 6.12 Settings
- `GET|POST /api/settings`
- `GET /api/settings/preferences`
- `POST /api/settings/verify-ibm`
- `DELETE /api/settings/cache`

### 6.13 Headers and conventions

| Header | When | Source |
|---|---|---|
| `Authorization: Bearer <jwt>` | every authenticated call | `AppState.authToken` |
| `X-Project-Id` | every authenticated call when a project is selected | `FastAPIClient.ProjectId` |
| `Accept: application/json` | all JSON calls | `FastAPIClient.authHeaders` |
| `Content-Type: application/json` | POST/PATCH/PUT | `matlab.net.http.field.ContentTypeField` |
| `Content-Type: application/x-www-form-urlencoded` | login only | `FormProvider` |
| `Content-Type: multipart/form-data; boundary=…` | file upload | hand-built body in `uploadViaHttpNet` |

Paginated list endpoints take `skip` + `limit` query params (max `limit=100`).

---

## 7. Navigation & Screen Lifecycle

**Routing keys** (`NavigationManager.navNames`) are decoupled from **display labels** (`navLabels`). Example: routing key `'Welcome'` displays as `'Projects'`.

```
onSelectSection(key)
  ├─ cancelInFlightFor(prevKey)
  ├─ ensureScreenBuilt(key)              ← lazy build on first visit
  │     └─ screenBuilderFor(key)(app)     ← runs the *Screen(app) function once
  ├─ hide previous panel, show app.SectionPanels(key)
  ├─ if !isScreenFresh(vm, ttlForScreen(key)):
  │     showNavLoading(key) + armNavOverlayTimer(20 s)
  ├─ autoLoadScreen(key)                 ← VM-specific data fetch
  └─ kickPrefetch(key)                   ← warm caches for likely-next screens
```

The safety timer `armNavOverlayTimer` auto-dismisses the loading overlay after 20 s in case a ViewModel forgets `hideLoading()`. `OverlayManager.showLoading` / `hideLoading` both disarm it on entry so rapid navigation cannot cross-fire.

Default landing screen at boot and after login: `'Dashboard'`. Re-enabling `'Notes'` requires three array edits in `NavigationManager` (the `NotesViewModel` is always instantiated, so the tab lights up immediately).

---

## 8. Authentication & Security

- **Transport.** `FastAPIClient.assertSafeBaseUrl` rejects non-HTTPS base URLs unless (a) the host is loopback, or (b) `allow_insecure_base_url=true` is set in `app.properties` (currently `true` to support the demo cluster at `34.42.87.190`). Credentials traverse unencrypted in that mode — production deployments must flip this to `false`.
- **Token storage.** `AppState.authToken` is held only in memory for the session lifetime; no disk persistence.
- **Username masking.** `Logger.maskUsername` redacts username in info-level login logs.
- **Path-segment encoding.** `FastAPIClient.encodePathSegment` percent-encodes user-supplied IDs that interpolate into URL paths (RFC 3986 unreserved set).
- **UTF-8 enforcement.** POST bodies go through `unicode2native(jsonencode(payload), 'UTF-8')` to avoid `uint8()` truncation of multibyte characters.
- **HTTP 204 normalization.** `webread` raises on 204; `FastAPIClient.isNoContent` distinguishes "successful delete with no body" from a real error.

---

## 9. Configuration

All runtime tunables in `resources/`:

- `app.properties` — `base_url`, `login_path`, `http_timeout`, `app_name`, `app_version`, `docs_url`, log level, cache TTLs (default 30 s, per-screen overrides for the four lookup-driven planning screens at 300 s, `shared_cache_ttl=120`), QEC defaults, confidence threshold.
- `labels.properties` — 600+ UI strings, accessed via `Labels.get(key, default)`. Enables non-code text changes.
- `seed.properties` — credentials for seed scripts (copied from `seed.properties.example`).

Static-class reload semantics: `AppConfig.reload()` + `Labels.reload()` drop cached parses.

---

## 10. In-App Compute Modules

Four services run **fully locally** — no HTTP, no token, no project context. They are CPU-bound and can be exercised in `runtests` without a backend.

| Service | Algorithm | Constraint |
|---|---|---|
| `StatevectorSimulator` | dense `2^n × 1` ket, gate-by-gate | ≤ 14 qubits (`maxQubits`), enforced by `canSimulate` |
| `QecEngineService` | closed-form analytical fidelity for bitflip3 / phaseflip3 / Shor(9) / Steane(7) / Perfect(5); MC path retained for parity checks | analytical: < 1 ms; MC: limited by `qec_compare_trials` |
| `ResourceEstimatorService` | surface-code distance from Fowler inverse-threshold; physical qubits `2d²+1`; T-state budget = T/T† direct + Toffoli×7 + SK rough bound | physical err must be below threshold; assumptions warned in insight strip |
| `RunPlannerService` | Pareto frontier over (cost ↗, fidelity ↗) candidates; `pickOptimal(target)` returns cheapest at-target config; falls back to highest-fidelity if no candidate meets target | heuristic mitigation factor table; capped at 0.99 |
| `BundleService` | hashes files (SHA-256), assembles ZIP with `manifest.json`, README, multi-target code, optional calibration + mitigation + FT snapshots | none |

---

## 11. Adding a New Screen — Required Edits

1. `src/presentation/screens/FooScreen.m` — function that calls `app.createSectionPage('Foo')`, builds UI into the returned container, wires callbacks to `app.FooVm.onSomething()`.
2. `src/presentation/viewmodels/FooViewModel.m` — `classdef FooViewModel < handle`, constructor takes `app`, methods call services and update `app.*` UI handles.
3. `src/presentation/app/QTAUWorkbenchApp.m` — declare UI properties, declare `FooVm`, instantiate in the constructor, call `FooScreen(app)` in `buildUI()`, add an `autoLoadScreen` case if it should auto-fetch.
4. `NavigationManager.navNames / navIcons / navLabels` — add routing key, glyph, label.
5. `resources/labels.properties` — add any `nav_foo`, `foo_title`, `foo_subtitle` keys.
6. (optional) `src/domain/ServiceContainer.m` — wire any new service required by the screen.

---

## 12. Testing

31 test files in `tests/` exercise services, infrastructure, viewmodels, and config utilities. Tests use `StubFastAPIClient.m` (a drop-in mock matching the `FastAPIClient` surface) so the service layer runs in isolation. Run:

```matlab
runtests('tests')                          % all
runtests('tests/test_CircuitService')      % one
```

No CI pipeline; tests are run locally before release.

---

## 13. Build & Distribution

- No build step. MATLAB interprets `.m` files directly.
- `scripts/package_release.m` produces the toolbox bundle for File Exchange.
- Seed scripts in `scripts/seed_*.m` populate a fresh backend (orchestrator: `seed_all.m`); `seed_qasmbench.m` ingests 252 QTAUBench circuits.
- Sample circuits live under `samples/` (12 hand-crafted + 252 QASMBench rebranded to QTAUBench + the AQS-QMC reference notebook).

---

## 14. Key External References

| Doc | Purpose |
|---|---|
| `CLAUDE.md` | Agent / contributor guide; ground-truth for screen contracts and workflow |
| `doc/architecture.md` | Earlier architecture narrative (overlaps with §3 here; this spec supersedes for component lists) |
| `doc/fastapi_contract.md` | Full request/response shape per endpoint |
| `doc/openapi.json` | Machine-readable OpenAPI dump |
| `doc/workflow.md` | End-to-end operator workflow narrative |
| `doc/development_guide.md` | Contributor onboarding |
| `doc/Quantum Error Mitigation.md` | QEM ladder and policy |
| `doc/circuit_cutting_algorithm.md` | Cut analysis + reconstruction math |
| `samples/aqs-qmc/` | Canonical IBM-exec-log JSONL schema reference |
