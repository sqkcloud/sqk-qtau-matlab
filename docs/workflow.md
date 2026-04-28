# QTAU Connector Workbench — End-to-End Workflows

This doc walks through how the application actually works, end-to-end. Where `architecture.md` describes **what** the layers are, this one describes **how data moves** through them, **which components talk to which**, and **what the data models look like**.

Read this when you need to:
- Understand how a click on the Welcome screen ends up as a Mongo write.
- Trace where a value on the Results screen came from.
- Know which `*Service` method to call from a new ViewModel.
- Audit the request/response shape of any endpoint.

---

## 1. Component relationship overview

```
┌──────────────────────────────────────────────────────────────────────┐
│ MATLAB R2025b — QTAU Connector Workbench                             │
│                                                                      │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐           │
│   │   Screen     │───▶│  ViewModel   │───▶│   Service    │           │
│   │  (UI build)  │    │ (callbacks)  │    │ (HTTP wrap)  │           │
│   └──────────────┘    └──────────────┘    └──────┬───────┘           │
│                              │                   │                   │
│                              ▼                   ▼                   │
│                       ┌──────────────┐    ┌──────────────┐           │
│                       │  AppState    │    │ FastAPIClient│           │
│                       │ (session)    │    │ (HTTP gw)    │           │
│                       └──────────────┘    └──────┬───────┘           │
└─────────────────────────────────────────────────┼────────────────────┘
                                                   │  HTTPS + Bearer
                                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ FastAPI server (qdash) — http://34.42.87.190:5715                   │
│                                                                     │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│   │   Router     │───▶│   Service    │───▶│  Repository  │          │
│   │ (routes +    │    │  (business   │    │   (Mongo I/O)│          │
│   │  validation) │    │   logic)     │    │              │          │
│   └──────────────┘    └──────┬───────┘    └──────┬───────┘          │
│                              │                    │                 │
│                              ▼                    ▼                 │
│                       ┌──────────────┐    ┌──────────────┐          │
│                       │ ibm_runtime  │    │   MongoDB    │          │
│                       │ (Qiskit IBM) │    │ (Bunnet ODM) │          │
│                       └──────┬───────┘    └──────────────┘          │
└─────────────────────────────┼────────────────────────────────────── │
                              │  Qiskit Runtime
                              ▼
                       ┌──────────────┐
                       │ IBM Quantum  │
                       │   (remote)   │
                       └──────────────┘
```

**Key invariants:**
- The MATLAB app is **presentation-only**. No persistent state lives client-side.
- The MATLAB app **never** talks to IBM Quantum directly — only through our FastAPI server.
- All long-running operations (cutting batches, QMC analyses, IBM Runtime jobs) are **async**: a POST returns `202` with an id, the client polls.
- Every HTTP request carries `Authorization: Bearer <token>` and (when set) `X-Project-Id: <uuid>`.

---

## 2. Layer responsibilities — the contract

### 2.1 MATLAB layers

| Layer | Lives in | Owns | Never does |
|---|---|---|---|
| **Screen** | `src/presentation/screens/*.m` (functions) | Building UI components into a section panel; binding button callbacks to `app.<Vm>.method()` | HTTP calls, business logic, AppState mutation |
| **ViewModel** | `src/presentation/viewmodels/*ViewModel.m` (classes) | Reading user inputs, validating, calling services, updating UI handles, managing async lifecycle (timers, AsyncRunner closures) | Direct HTTP, building UI components, parsing JSON byte strings |
| **Service** | `src/domain/services/*Service.m` (classes) | One per backend domain. Wraps `FastAPIClient` calls, returns decoded structs. Stateless. | UI access (no `app.UIFigure`), schema parsing of nested fields (callers use `JsonHelper.pick`) |
| **AppState** | `src/domain/models/AppState.m` (one instance) | Session-scoped mutable state — auth token, current user, current project, selected circuit/job/backend | Persistence, IO |
| **Infrastructure** | `src/infrastructure/**` | HTTP gateway (`FastAPIClient`), async dispatch (`AsyncRunner`), config loaders (`AppConfig`, `Labels`, `Theme`, `Logger`, `JsonHelper`) | Domain knowledge |

### 2.2 Server layers

| Layer | Lives in | Owns | Never does |
|---|---|---|---|
| **Router** | `src/qdash/api/routers/*.py` | URL routing, HTTP-status mapping, request body validation via Pydantic schemas, project context resolution | Business logic, Mongo I/O |
| **Service** | `src/qdash/api/services/*.py` | Domain logic (cutting pipeline, job submission, analysis), Mongo + IBM Runtime I/O, transaction boundaries | Direct HTTP request access |
| **Repository** | `src/qdash/repository/*.py` | Mongo CRUD via Bunnet (`Document.find`, `.save`, etc.) | Business logic, IBM calls |
| **Schemas** | `src/qdash/api/schemas/*.py` | Pydantic DTOs that define the request/response shape | Logic |
| **Document Models** | `src/qdash/dbmodel/*.py` | Bunnet `Document` subclasses — Mongo schema + indexes | Business logic |

---

## 3. Application boot — what happens when the app launches

```
QTAUWorkbenchLauncher.m
  │
  ▼
QTAUWorkbenchApp() constructor
  │
  ├─→ AppConfig.reload()      ← reads resources/app.properties
  ├─→ Labels.reload()         ← reads resources/labels.properties (566+ keys)
  ├─→ Theme.setActive(loadPersisted())  ← getpref('QTAUWorkbench','theme') ?? 'dracula'
  │
  ├─→ AppState                ← single long-lived instance
  │
  ├─→ FastAPIClient(base_url) ← reads base_url from app.properties
  │
  ├─→ ServiceContainer.buildServices(client)
  │     ├── AuthSvc, ProjectSvc, CircuitSvc, BackendSvc, BenchmarkSvc,
  │     ├── PredictionSvc, JobSvc, QmcSvc, CuttingSvc, QecEngineSvc,
  │     └── ReportSvc, SettingsSvc
  │
  ├─→ buildUI()
  │     ├── header (logo, project picker, user menu)
  │     ├── nav sidebar (uihtml — NavigationManager.renderNavHtml)
  │     ├── 17 section panels (one per screen, all hidden initially)
  │     └── auth overlay (covers everything until login)
  │
  ├─→ ViewModels
  │     ├── WelcomeVm (eager — shows projects)
  │     └── 16 others (lazy — instantiated on first nav to that screen)
  │
  ├─→ DialogBuilder.buildLoginDialog(app)
  │     ↓ user submits → POST /api/auth/login
  │     ↓ token + token_type + default_project on response
  │     ↓ stored on AppState
  │
  └─→ NavigationManager.onSelectSection('Welcome')
```

After this, the app is idle until the user navigates somewhere.

---

## 4. The standard flow — Screen ↔ ViewModel ↔ Service

Every feature follows this pattern. Example: **user clicks Refresh on the Backends screen**.

```
1. BackendsScreen built the button:
       refreshBtn.ButtonPushedFcn = @(~,~) app.BackendsVm.onRefresh();

2. User clicks → MATLAB invokes the callback (main thread).

3. BackendsViewModel.onRefresh:
       app.showLoading('Loading backends...')
       svc   = app.BackendSvc      ← LOCAL var (avoids parfeval app-capture)
       token = app.State.authToken
       AsyncRunner.run( ...
           @() svc.listBackends(token, ''), ...     ← runs in worker
           @(data) obj.onRefreshComplete(app, data),  ← runs on main thread
           @(ME)   obj.onRefreshError(app, ME))

4. Worker thread calls BackendService.listBackends:
       result = client.getAuth('/api/backends', token)
       returns the decoded struct

5. FastAPIClient.getAuth (worker thread):
       webread + auth headers + UTF-8 decode → struct.

6. AsyncRunner success callback fires on main thread:
       BackendsViewModel.onRefreshComplete(app, data):
           items = JsonHelper.extractList(data, 'backends')
           app.BackendsTable.Data = …
           app.hideLoading()

7. (Or error path:)
       BackendsViewModel.onRefreshError(app, ME):
           app.hideLoading()
           app.showError('Backends', ME)   ← strips internal URLs via OverlayManager.sanitizeErrorMessage
```

### 4.1 Why `svc` is a LOCAL variable

`AsyncRunner.run` uses `parfeval(backgroundPool(), …)`. When the closure captures `app`, the worker process tries to deserialize the entire `QTAUWorkbenchApp` class — including its `uihtml` properties whose superclass `matlab.ui.control.WebComponent` isn't on the worker's classpath. Result: `'matlab.ui.control.WebComponent' contains a parse error` and the worker silently fails.

Capturing `svc = app.BackendSvc` to a local variable means the closure captures only the service handle (which has `FastAPIClient` + nothing else) — the worker classpath has those.

**Rule:** any AsyncRunner closure must capture local variables, never `app`. Success/error callbacks DO run on the main thread, so they can capture `app` freely.

---

## 5. Data lifecycle — where each kind of value comes from

### 5.1 Authentication

```
Login dialog (uihtml fields)
  │ POST /api/auth/login
  │   form-urlencoded: username, password
  ▼
auth_router.login → Mongo `user` lookup → bcrypt verify → JWT mint
  │
  ▼ {access_token, token_type, default_project_id}
  │
AppState.authToken = access_token
AppState.tokenType = "Bearer"
AppState.currentProjectId = default_project_id
FastAPIClient.ProjectId  = default_project_id
```

After this, every subsequent request automatically attaches `Authorization: Bearer <token>` and `X-Project-Id: <uuid>`.

### 5.2 Project list

```
GET /api/projects
  │
  ▼
project_router.list → ProjectService.list_projects(user)
  │   reads MongoDB `project` collection
  │   filters by membership (project_membership) + ownership
  ▼
[{project_id, name, owner_username, created_at, …}]
  │
WelcomeVm.Projects ← cached for 30s (isScreenFresh)
```

### 5.3 Circuit upload

```
POST /api/circuits
  │  multipart/form-data:
  │    file (QASM/QIR), name, format, description
  │
  ▼
circuit_router.upload → CircuitService.upload_circuit
  │   • Parse via Qiskit (QuantumCircuit.from_qasm_str)
  │   • Extract features: num_qubits, depth, gate_counts, …
  │   • Match against QTAUBench (cosine similarity)
  │   • Save to MongoDB `circuit` { raw_content, features, similarity }
  ▼
{circuit_id, name, num_qubits, …}
```

### 5.4 IBM Quantum job — the round-trip

This is the most complex one. Trace counts from IBM to the Results screen:

```
PredictionViewModel.onSubmitToIbm()
  │ POST /api/jobs/submit
  │   { circuit_id, backend_name, shots, optimization_level }
  ▼
job_router.submit → JobService.submit_job
  │   • Mongo `circuit` → load QASM → Qiskit transpile
  │   • IBM Runtime: SamplerV2(mode=backend).run([transpiled])
  │   • ibm_job_id returned
  │   • Mongo `ibm_job` { status: "queued", ibm_job_id, … }
  ▼
{job_record_id, ibm_job_id, status: "queued"}

═══ time passes ═══

JobsViewModel auto-refresh (every 5s):
  GET /api/jobs?skip=0&limit=50
   ▼
  job_router.list → JobService.list_jobs
    • Mongo find sorted by submitted_at desc
    • For up to 10 in-flight jobs: lazy-refresh from IBM
        _refresh_ibm_status(record_id, ibm_job_id):
          ibm_job = service.job(ibm_job_id)
          ibm_status = ibm_job.status()           ← "DONE" / "QUEUED" / etc.
          if DONE:
              counts = _extract_counts_from_result(ibm_job.result())
              Mongo update: status="completed", raw_counts={…}
   ▼
  [{job_record_id, status, raw_counts?, …}]

═══ user navigates to Results ═══

ResultsViewModel.onRefreshResults:
  1. GET /api/jobs?skip=0&limit=100
     → pick first job with status="completed"
  2. GET /api/jobs/{record_id}/results
     → ResultsService.get_result_summary
         counts = doc.raw_counts                  ← from Mongo, not IBM
         compute fidelity vs ideal distribution
         return { rows, summary, distribution }
  3. Populate ResultsTable + ResultJsonArea + ResultsDistTable
```

**Key:** the MATLAB app **only ever reads `raw_counts` from Mongo**. If counts aren't there, the Results screen is blank. The fix is always upstream — get counts into Mongo — never retry the MATLAB call.

When all jobs reach a terminal state, `JobsViewModel.onRefreshJobsComplete` auto-stops the 5-second auto-refresh timer to avoid hammering the server with pointless polls.

### 5.5 Cutting batch — split + parallel + reconstruct

See `circuit_cutting_algorithm.md` for the full algorithm. Workflow summary:

```
Analysis → Circuit Cutting bridge button (or direct nav)
  ▼
CircuitCuttingViewModel.onAnalyzeCuts:
  POST /api/cutting/analyze
    body = { circuit_id, target_k }
  ▼
  CuttingService.analyze_cuts:
    • Smart target_k default if needed (⌈n / widest_backend⌉)
    • Run pipeline.analyze_cuts → cut_plan
    • Skip-cutting recommendation if n ≤ widest backend
  ▼
{ candidates: [cut_plan], cutting_recommended, direct_run_backend, … }

If cutting_recommended=False:
  → Modal: "Submit Directly" / "Proceed with Cutting" / "Cancel"
  → Submit Directly → bridge to Backends screen with backend pre-selected

Else: user clicks Run →
  POST /api/circuits/{cid}/cutting/batches
    body = { mode, preset, cut_plan, backend_assignments, observables }
  ▼
  CuttingBatchService.create_batch + dispatch:
    • plan_execution → expand to hardware-ready sub-experiments per label
    • If backend_assignments=[]: select_backends (size-aware, distinct-first)
    • k × JobService.submit_cutting_subcircuit
        → k IBM jobs in parallel, one per partition label
  ▼
HTTP 202 { batch_id, status: "executing", … }

═══ client polls every 3s ═══

GET /api/cutting/batches/{batch_id}
  ▼
  CuttingBatchService.poll_batch:
    • For each child: JobService.get_job_status(project_id, record_id)
    • progress = mean(child.progress_pct)
    • all terminal → _reconstruct_and_complete
        • For each child: extract counts → SamplerResult
        • pipeline.reconstruct_expectations(results, observables, cut_plan)
        • status = "completed", reconstruction = { expectations, … }

═══ on Results screen ═══

ResultsViewModel.loadCuttingBatches:
  GET /api/cutting/batches  (sorted by created_at desc, project-scoped)
  → populate Cutting Batches table

User clicks row → app.SelectedBatchId = …
User clicks "View Reconstruction":
  GET /api/cutting/batches/{id}/result
  → render expectations into ResultJsonArea
```

### 5.6 QMC (Quantum Monte Carlo) analysis

```
Analysis screen → "Quantum Monte Carlo" button → DialogBuilder.buildQmcDialog
  ▼
operator picks: execution_mode (statevector / IBM Runtime), mitigation,
              market scenario (spot, vol, r, T), confidence, epsilon
  ▼
AnalysisViewModel.onRunQmc:
  POST /api/circuits/{cid}/qae/analyze
    body = { execution_mode, mitigation, ... }
  ▼
QmcService.submit (server side) → 202 { job_id }
  ▼
3s poll timer:
  GET /api/qae/jobs/{job_id} → { status, progress, partial_results }
  ▼
status = "completed" → fetch full result, render charts (loss CDF,
amplitude estimate, ZNE curve, Greeks).

User clicks Generate Report:
  POST /api/reports/generate
    body = { title, report_type: "technical", format: "pdf",
             sections: [executive_summary, …, quantum_monte_carlo, …],
             circuit_id }
  ▼
ReportService._build_qmc_pdf_bytes (vector charts via ReportLab)
  ▼
{ report_id }

User clicks Download:
  GET /api/reports/{report_id}/download → PDF stream
```

(Note: MATLAB-side classes are named `QmcService`/`QmcSvc`. The legacy `/api/qae/*` URL paths remain on the server — coordinated rename pending.)

---

## 6. Request workflow — what's in every HTTP call

### 6.1 Headers (added by FastAPIClient automatically)

```
Authorization: Bearer <token>
Accept:        application/json
Content-Type:  application/json    ← POST/PUT/PATCH only
X-Project-Id:  <uuid>              ← when AppState.currentProjectId is set
```

### 6.2 Body encoding

POST bodies go through `FastAPIClient.postAuthJson`:

```matlab
msgBody.Payload = unicode2native(jsonencode(payload), 'UTF-8');
```

The `unicode2native(..., 'UTF-8')` (NOT `uint8(...)`) is critical — it correctly emits multi-byte UTF-8 sequences for non-ASCII characters (em-dashes, smart quotes, non-Latin scripts). The earlier `uint8(...)` cast each char to `char & 0xFF`, truncating multi-byte chars to a single garbage byte and triggering HTTP 400 from FastAPI's body parser.

### 6.3 Error mapping

| HTTP status | Meaning | MATLAB handling |
|---|---|---|
| 200 / 201 / 202 | Success | Service returns decoded struct |
| 400 | Bad request | `MException` with `MATLAB:webservices:HTTP400StatusCodeError` — popup with `OverlayManager.sanitizeErrorMessage` (strips `https?://host:port`) |
| 401 | Unauthorized | Redirect to login (token expired) |
| 404 | Not found | Inline message (e.g. "Job not found") |
| 409 | Conflict / not ready | Inline status, NOT modal — "Results not ready" |
| 422 | Validation | Surface FastAPI's `detail` text; usually a programmer error |
| 500/502/503 | Server error | Modal popup; user retries |

### 6.4 Project-scoped resolution

Every endpoint that returns project-scoped data uses `Depends(get_project_context)` server-side. Resolution priority:
1. Path parameter (e.g. `/api/projects/{id}/...`)
2. `X-Project-Id` header (sent by `FastAPIClient` when set)
3. `user.default_project_id` (from JWT claims)
4. Owned-project fallback
5. → 400 if all unset

---

## 7. Async work — the parfeval pool + timers

```
AsyncRunner.run(workFcn, onDone, onError, timeoutSec?)
  │
  ▼
parfeval(backgroundPool(), workFcn, 1)   ← R2025b thread-based pool
  │
  ▼
worker thread runs workFcn
  │
  ├─ success → onDone(result)  ← main thread
  └─ failure → onError(ME)     ← main thread
```

Two screens run their own timers in addition:
- **Jobs**: 5-second `MATLAB:timer` polling `/api/jobs` while the screen is visible. Self-stops when all jobs are terminal OR when the user navigates away.
- **Circuit Cutting**: 3-second poll timer against `/api/cutting/batches/{id}` while a batch is executing. Self-stops when status is terminal.

Both timers use `BusyMode='drop'` so a slow tick can't cause overlap.

---

## 8. UI lifecycle — where the surprises live

### 8.1 Navigation

`NavigationManager.autoLoadScreen(key)`:

```
isScreenFresh(Vm, ttl=30s) ?
  yes → snap instantly (no fetch, no overlay)
  no  → showNavLoading(key) + Vm.onFetch…()
        + 20s safety timer (auto-dismiss overlay)
```

### 8.2 uihtml event-queue race

`uihtml` components communicate with their JavaScript counterpart via `peerEvent` messages. After detaching `DataChangedFcn = ''`, MATLAB needs time to drain queued events before `delete()` — otherwise the dispatcher hits a deleted model and prints `'Invalid or deleted object'`.

Pattern:
```matlab
component.DataChangedFcn = '';
drawnow;
pause(0.05);
drawnow;
delete(component);
```

Used in `WelcomeViewModel.onLoginOk` and `DialogBuilder.closeLoginDialog`.

### 8.3 Loading overlay

`app.showLoading(msg)` and `app.hideLoading()` are mandatory bookends. A 20-second safety timer auto-dismisses the overlay so a forgetful VM can't leave it stuck. Both methods cross-cancel the timer.

---

## 9. Data models — Mongo & MATLAB structs

### 9.1 Mongo collections (Bunnet `Document` classes)

| Collection | Document model | Key fields |
|---|---|---|
| `user` | `UserDocument` | username, hashed_password, default_project_id |
| `project` | `ProjectDocument` | project_id, name, owner_username, created_at |
| `project_membership` | `ProjectMembershipDocument` | project_id, username, role |
| `circuit` | `CircuitDocument` | circuit_id, project_id, name, format, raw_content, features, similarity, qae |
| `ibm_job` | `IBMJobDocument` | job_record_id, ibm_job_id, project_id, circuit_id, backend_name, shots, status, raw_counts, batch_id, cut_role |
| `cutting_batch` | `CuttingBatchDocument` | batch_id, project_id, circuit_id, mode, preset, status, cut_plan, backend_assignments, child_job_ids, reconstruction |
| `qae_job` | `QaeJobDocument` | job_id, circuit_id, status, partial_results, runtime_job_id |
| `prediction` | `PredictionDocument` | prediction_id, circuit_id, backend_name, predicted_fidelity |
| `benchmark_*` | various | volumetric, scorecard, regression results |
| `report` | `ReportDocument` | report_id, project_id, format, generated_at, file_path |
| `settings` | `SettingsDocument` | username, ibm_token, defaults, notifications |

### 9.2 MATLAB session state — `AppState`

```matlab
AppState properties:
  baseUrl                  string    % API base (e.g. "http://34.42.87.190:5715")
  authToken                string    % JWT
  tokenType                string    % "Bearer"
  currentUser              string
  currentProjectId         string
  currentProjectName       string
  selectedCircuitId        string
  selectedCircuitName      string
  selectedJobId            string
  selectedBackend          string    % suggested backend (from cutting bridge)
  IBMConfig                struct    % cached server IBM config
```

Every ViewModel reads/writes via `app.State.*`. State is **session-scoped** — survives navigation, reset on logout.

### 9.3 The cut_plan struct (round-trip)

After analyze:
```json
{
  "cuts": [],
  "k": 3,
  "target_k": 3,
  "sampling_overhead": 81.0,
  "sampling_overhead_log10": 1.908,
  "per_subcircuit_qubits": [63, 63, 1],
  "qubits_per_qpu": 63,
  "feasible": true,
  "feasibility_reason": "",
  "_partition_labels": ["s0","s0","...","s1","s1","...","s2"],
  "_addon_overflowed": false
}
```

After dispatch (server-side enrichment, persisted on the batch doc):
```json
{
  "...": "all of the above, plus",
  "coefficients": [[1.0, "EXACT"], "..."],
  "subobservables_by_label": { "s0": ["ZZZ..."], "s1": ["..."], "s2": ["..."] },
  "observables": ["Z...Z"],
  "label_order": ["s0","s1","s2"],
  "subexperiments_count_by_label": { "s0": 243, "s1": 243, "s2": 1 }
}
```

The MATLAB client strips `feasibility_reason` and `feasible` before round-trip POST (defensive — the UTF-8 fix in `FastAPIClient.postAuthJson` is the actual root-cause fix, but the strip stays as belt-and-braces).

---

## 10. Algorithms — high-level catalog

| Domain | Algorithm | File |
|---|---|---|
| Circuit width estimation | Qiskit's transpiler depth/width counts | `circuit_service.py` (`upload_circuit`) |
| Benchmark similarity matching | Cosine similarity on feature vector | `circuit_service.py` (`match_benchmarks`) |
| Cut detection | `qiskit-addon-cutting.find_cuts` (CKT method) | `cutting/base.py` (analyze_cuts) |
| Partition labelling | NetworkX connected components on cut circuit | `cutting/base.py` (`_labels_from_cut_circuit`) |
| Singleton packing | Greedy fit-to-largest-under-budget | `cutting/base.py` (`_pack_singletons`) |
| Backend selection | Fit-decreasing greedy with distinct-first | `cutting/base.py` (`select_backends`) |
| QPD reconstruction | `qiskit-addon-cutting.reconstruct_expectation_values` | `cutting/base.py` (reconstruct_expectations) |
| Status status→progress mapping | Lookup table | `job_service.py` (`_PROGRESS_MAP`) |
| Counts extraction (IBM result → dict) | Probe `data.meas`, `data.c`, walk `DataBin` | `job_service.py` (`_extract_counts_from_result`) |
| QMC Quantum Amplitude Estimation | IBM IterativeAmplitudeEstimation + ZNE mitigation | `qae_service.py` |
| Fidelity comparison (measured vs ideal) | TVD + Hellinger + classical fidelity | `results_service.py` |
| Theme palette interpolation | Static palette tables | `Theme.m` |

---

## 11. Where things live — quick map

| Question | File |
|---|---|
| Which endpoint does Screen X hit? | `src/presentation/viewmodels/XViewModel.m` → `app.*Svc.*()` calls |
| What does response field Y map to? | `src/domain/services/*.m` + `JsonHelper.pick(data, {'a','b','c'})` |
| Why is the nav sidebar showing the wrong active item? | `NavigationManager.renderNavHtml` / `updateNavStyles` |
| Why is the overlay stuck? | VM didn't call `hideLoading()`; safety timer fires at 20s |
| Why is a field blank on Results? | Mongo `ibm_job.raw_counts` is missing |
| How do I change a UI string? | `resources/labels.properties`, then `Labels.reload()` |
| How do I add a new screen? | See `architecture.md` § "Adding a New Screen" |
| How do I trace cutting flow? | `circuit_cutting_algorithm.md` |
| What's cached and for how long? | `AppConfig screen_cache_ttl` + `isScreenFresh` in `NavigationManager.m` |
| How do I add a new endpoint? | New router method in `qdash/api/routers/*.py`, add Pydantic schema, plumb via DI in `dependencies.py`, add MATLAB service method in `src/domain/services/*Service.m` |
| Why does parfeval throw `WebComponent` errors? | Closure captured `app` — see § 4.1 |
| Why is the Results table empty? | Either `listBatches` failed (server log), or batch docs failed validation, or no batches exist for the project |

---

## 12. Related docs

- `architecture.md` — layer structure, DI, code organization.
- `circuit_cutting_algorithm.md` — the cutting feature in depth.
- `fastapi_contract.md` — endpoint reference (request/response shapes).
- `openapi.json` — machine-readable contract.
- `development_guide.md` — local setup, build, test commands.
