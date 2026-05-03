# Workspace Screens — Overview

This file documents the remaining workspace screens (those not already
covered by their own per-feature page). Each section follows the
standard seven-section template at a compact size: what / purpose /
architecture / algorithm-or-data / workflow / data flow / business
logic.

Cross-cutting patterns referenced throughout: see
[`architecture.md`](architecture.md).

---

## A. Welcome

**1. What it is** — login + project picker landing screen. First view
after launching the app.

**2. Purpose** — collect username / password, fetch the user's
projects, let the operator pick (or create) a project, and persist
the choice in `AppState.currentProjectId`.

**3. Architecture** — `WelcomeScreen.m` + `WelcomeViewModel.m` →
`AuthService.login` (POST `/api/auth/login`) and
`ProjectService.listProjects` (GET `/api/projects`).

**4. Data** — login response `{access_token, token_type, default_project}`;
project list response `{projects:[…], skip, limit, total}`.

**5. Workflow** — Enter username / password → click **Sign in** →
project list populates → pick a project → screen auto-navigates to
Dashboard.

**6. Data flow**
```
POST /api/auth/login   form: username=&password=          → token
GET  /api/projects                                        → project list
```

**7. Business logic** — Token + project id are stored in `AppState`
and reused as `Authorization: Bearer <token>` and `X-Project-Id`
headers by every subsequent request. Login is the **only** screen that
runs without an existing token.

**Reference** — `src/presentation/screens/WelcomeScreen.m`,
`src/presentation/viewmodels/WelcomeViewModel.m`,
`src/domain/services/AuthService.m`.

---

## B. Dashboard

**1. What it is** — workflow summary + readiness storyboard for the
active project.

**2. Purpose** — give the operator a quick "where am I" view: which
circuits are uploaded, which jobs are running / completed, what
predictions exist, what reports are pending.

**3. Architecture** — `DashboardScreen.m` + `DashboardViewModel.m` →
`ProjectService.getDashboard` (GET `/api/projects/{id}/dashboard`).

**4. Data** — Dashboard response is a denormalised aggregation:
`{circuit_count, job_count_running, job_count_completed,
prediction_count, report_count, recent_activity:[…]}`.

**5. Workflow** — Auto-refreshes on tab open
(`autoLoadScreen` → `app.DashboardVm.onEnter`).

**6. Data flow**
```
GET /api/projects/{project_id}/dashboard   → KPIs + recent activity
GET /api/projects/{project_id}/activities  → activity timeline
```

**7. Business logic** — Read-only. Auto-refresh respects the freshness
TTL — no polling beyond the freshness window.

**Reference** — `src/presentation/screens/DashboardScreen.m`,
`src/presentation/viewmodels/DashboardViewModel.m`,
`src/domain/services/ProjectService.m`.

---

## C. Circuits

**1. What it is** — paginated, searchable list of the active project's
circuits.

**2. Purpose** — browse / search / pick a circuit to drive Analysis,
Cutting, Benchmark, Prediction, Jobs.

**3. Architecture** — `CircuitsScreen.m` + `CircuitsViewModel.m` →
`CircuitService.listCircuitsPaged` (GET `/api/circuits?skip=&limit=`).

**4. Data** — Circuit list envelope:
`{circuits:[{id, name, format, num_qubits, depth, category,
created_at}], skip, limit, total}`.

**5. Workflow** — Tab open auto-loads the first 20 circuits; search
box filters client-side; pagination via skip / limit; clicking a row
sets `app.State.selectedCircuitId`.

**6. Data flow**
```
GET /api/circuits?skip=&limit=          (paginated)
GET /api/circuits/{id}                  (per-circuit detail on click)
```

**7. Business logic** — Empty-state banner above the table when the
project has zero circuits (Phase 6.2). Selection is sticky across
navigation.

**Reference** — `src/presentation/screens/CircuitsScreen.m`,
`src/presentation/viewmodels/CircuitsViewModel.m`,
`src/domain/services/CircuitService.m`.

---

## D. Upload

**1. What it is** — circuit file upload with format detection and
preview.

**2. Purpose** — bring an external `.qasm` / `.qpy` / `.json` file
into the project's circuit collection.

**3. Architecture** — `UploadScreen.m` + `UploadViewModel.m` →
`CircuitService.uploadCircuit` (POST `/api/circuits/upload/file`,
multipart form-data via `FastAPIClient.uploadFileAuth`).

**4. Data** — multipart fields: `circuit_name`, `format`, `category`,
`num_qubits`, `depth`. Server returns the persisted circuit record.

**5. Workflow** — File picker → format auto-detected from extension →
metadata fields prefilled from a quick parse → preview pane renders
the circuit diagram → click **Upload** → toast on success.

**6. Data flow**
```
POST /api/circuits/upload/file
     multipart: file=… + circuit_name=… + format=… + category=… +
                num_qubits=… + depth=…
     → { id, name, format, ... }
```

**7. Business logic** — File-upload uses `matlab.net.http` multipart
first, falls back to the system `curl` binary
(`FastAPIClient.uploadFileAuth`). Auth + project context required.

**Reference** — `src/presentation/screens/UploadScreen.m`,
`src/presentation/viewmodels/UploadViewModel.m`,
`src/domain/services/CircuitService.m` (`uploadCircuit`).

---

## E. Detailed Analysis

**1. What it is** — heatmaps, drift, qubit metrics, and cross-run
comparison view for a selected circuit.

**2. Purpose** — let operators investigate a single circuit's
behaviour in detail (per-qubit T1/T2/readout-error, fidelity drift
between runs, side-by-side comparison vs another job).

**3. Architecture** — `DetailedAnalysisScreen.m` +
`DetailedAnalysisViewModel.m`. Aggregates data from `JobService`,
`BackendService`, `CircuitService`. Bridges to Analysis screen via
the **Analyze** toolbar button.

**4. Data** — composite of job result counts, calibration per-qubit
arrays, and similarity-matched reference circuits.

**5. Workflow** — Auto-loads on tab open; toolbar Circuit dropdown
switches subject; Analyze button bridges to Analysis screen.

**6. Data flow**
```
GET /api/jobs/{id}                       (job-result data)
GET /api/backends/{name}/calibration     (per-qubit metrics)
GET /api/circuits                        (Circuit dropdown)
```

**7. Business logic** — Read-only, project-scoped, auth required.
Demo charts paint on first entry if axes are empty (preserves live
data on subsequent visits).

**Reference** — `src/presentation/screens/DetailedAnalysisScreen.m`,
`src/presentation/viewmodels/DetailedAnalysisViewModel.m`.

---

## F. Backends

**1. What it is** — backend explorer with primary / backup selection.

**2. Purpose** — let the operator browse available IBM (and future
non-IBM) backends, see their calibration / queue depth / status, and
pin a primary + backup pair for the project.

**3. Architecture** — `BackendsScreen.m` + `BackendsViewModel.m` →
`BackendService.listBackends` + `getCalibration`.

**4. Data** — Backend list `{backends:[{name, status, num_qubits,
basis_gates, queue_length, last_calibration}]}`; calibration response
shape documented in `quantum-error-mitigation.md` §4.

**5. Workflow** — Auto-refresh on tab open; click row → calibration
detail panel; **Set as primary** / **Set as backup** buttons persist
the choice in `AppState` + via Settings.

**6. Data flow**
```
GET /api/backends                        (list)
GET /api/backends/{name}/calibration     (per-backend detail)
```

**7. Business logic** — Auth required. Loading overlay is
nav-triggered. Primary backend feeds the Benchmark / Prediction /
Cutting screens by default.

**Reference** — `src/presentation/screens/BackendsScreen.m`,
`src/presentation/viewmodels/BackendsViewModel.m`,
`src/domain/services/BackendService.m`.

---

## G. Jobs

**1. What it is** — Job Monitoring Dashboard with a 6-column table
(Job ID / Circuit / Backend / Status / Progress / Created).

**2. Purpose** — track all submitted jobs, watch progress in real
time, drill into a job's details, and cancel queued jobs.

**3. Architecture** — `JobsScreen.m` + `JobsViewModel.m` →
`JobService.listJobs` / `getJob` / `getStatus` / `cancelJob`.

**4. Data** — list envelope `{jobs:[{job_record_id, circuit_id,
backend_name, status, progress, submitted_at, mitigation_plan?}]}`.

**5. Workflow** — Tab open seeds the table + arms a **5-second auto-
refresh timer** (`startAutoRefresh(5)`). The timer self-terminates on
the next tick after the user navigates away. Click row → details panel.

**6. Data flow**
```
GET /api/jobs?skip=&limit=               (sorted newest first)
GET /api/jobs/{id}/status                (lightweight poll)
GET /api/jobs/{id}                       (full record)
DELETE /api/jobs/{id}                    (cancel queued)
```

**7. Business logic** — Auto-refresh runs silently (no overlay flash).
Self-healing list: backend lazy-refreshes up to 10 in-flight jobs per
call from IBM Quantum so progress advances without a Celery sweeper.
Mitigation plan column shows the snapshot persisted at submit time.

**Reference** — `src/presentation/screens/JobsScreen.m`,
`src/presentation/viewmodels/JobsViewModel.m`,
`src/domain/services/JobService.m`.

---

## H. Results

**1. What it is** — measured vs predicted vs ideal result analysis for
the most recent completed job.

**2. Purpose** — compare what the QPU actually returned to the
predicted distribution and the noiseless ideal, with optional toggle
between the mitigated and raw sibling batches.

**3. Architecture** — `ResultsScreen.m` + `ResultsViewModel.m` →
`JobService.getJobResult`, `CuttingService.getSiblingPair` (when the
result has a `sibling_group_id`), `PredictionService.getPrediction`.

**4. Data** — job result `{counts, expectation_values, fidelity?,
sibling_group_id?, mitigation_plan?}`.

**5. Workflow** — Tab open auto-picks the first completed job and
populates the panels. Mitigated / Raw toggle resolves the partner via
`/api/cutting/sibling/{group_id}`.

**6. Data flow**
```
GET /api/jobs?status=completed&limit=1   (latest completed)
GET /api/jobs/{id}                       (full result)
GET /api/cutting/sibling/{group_id}      (when sibling exists)
GET /api/predict/{prediction_id}         (predicted distribution)
```

**7. Business logic** — Read-only. The Mitigated / Raw toggle is only
visible when the loaded job has `sibling_group_id` set (i.e. the
batch was submitted with `also_run_raw: true`).

**Reference** — `src/presentation/screens/ResultsScreen.m`,
`src/presentation/viewmodels/ResultsViewModel.m`.

---

## I. Reports

**See** [`reports.md`](reports.md) for the full per-feature page —
Reports gets its own document because the operator surface (Generate
→ poll → save → open, plus Email / Print distribution) is non-trivial
and was the subject of a recent fix-end-to-end pass.

---

## J. Settings

**1. What it is** — per-user account / defaults / storage / notifications.

**2. Purpose** — centralised place for the operator's preferences
(default mitigation level, IBM Runtime token, preferred backend, theme,
auto-refresh cadence).

**3. Architecture** — `SettingsScreen.m` + `SettingsViewModel.m` →
`SettingsService.getSettings` / `updateSettings`,
`SettingsService.verifyIbmToken`.

**4. Data** — `{default_mitigation_level, default_backend,
ibm_runtime_token, theme, auto_refresh_seconds, ...}`.

**5. Workflow** — Tab open loads current settings; **Save** persists.
**Verify IBM token** does a round-trip to IBM Runtime via the backend.

**6. Data flow**
```
GET    /api/settings                      → current settings
PATCH  /api/settings                      → updated settings
POST   /api/settings/ibm/verify           → {ok, channels, instances}
```

**7. Business logic** — Auth required. Mitigation level dropdown
mirrors the QEM ladder (Raw / Standard / Aggressive / TEM / Custom).
Persisted preferences flow into Cutting screen's mitigation default.

**Reference** — `src/presentation/screens/SettingsScreen.m`,
`src/presentation/viewmodels/SettingsViewModel.m`,
`src/domain/services/SettingsService.m`.

---

## K. Notes

**1. What it is** — working notes / operator memos for the active
project. Currently **hidden** from the sidebar (the screen + VM still
build, just not navigable).

**2. Purpose** — markdown-style notes for run-day operator context
(what was tried, what worked, why a backend was switched).

**3. Architecture** — `NotesScreen.m` + `NotesViewModel.m` →
`ProjectService.listNotes` / `createNote` / `updateNote` / `deleteNote`.

**4. Data** — `{notes:[{id, title, body, created_at, updated_at}]}`.

**5. Workflow** — When re-enabled (per CLAUDE.md instructions:
add `'Notes'` back to `navNames` / `navLabels` and `char(9998)` to
`navIcons` at position 4 in `NavigationManager.m`), the operator gets
a list-of-notes pane on the left and an editor pane on the right.

**6. Data flow**
```
GET    /api/projects/{id}/notes
POST   /api/projects/{id}/notes
PATCH  /api/projects/{id}/notes/{noteId}
DELETE /api/projects/{id}/notes/{noteId}
```

**7. Business logic** — Project-scoped. Auto-save on idle (Phase 2
when re-enabled).

**Reference** — `src/presentation/screens/NotesScreen.m`,
`src/presentation/viewmodels/NotesViewModel.m`.
