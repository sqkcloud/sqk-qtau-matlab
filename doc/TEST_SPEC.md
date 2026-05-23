# QTAU Connector Workbench — Test Specification

**Companion to:** `doc/TECHNICAL_SPEC.md`
**Test framework:** MATLAB Unit Test Framework (`runtests`, `matlab.unittest.TestCase`)
**Test root:** `tests/`
**Mocks:** `tests/StubFastAPIClient.m` (records last call + canned response)
**Helpers:** `tests/StubAnalysisApp.m`, `tests/TestBenchmarkDashboardVmProbe.m`, `tests/TestCircuitCuttingVmProbe.m`

---

## 1. Goals

The test suite verifies that the **MATLAB-side contract** in `TECHNICAL_SPEC.md` holds without requiring a running FastAPI backend:

1. **HTTP boundary** (`FastAPIClient`) refuses unsafe URLs, percent-encodes path segments, and routes verbs to the correct transport.
2. **Domain services** delegate to the documented endpoints with the right HTTP verb, path, and payload shape.
3. **ViewModels** wire screen callbacks to the right service calls and propagate state mutations onto `AppState`.
4. **Local compute** (`StatevectorSimulator`, `QecEngineService`, `ResourceEstimatorService`, `RunPlannerService`, `BundleService`) produces deterministic outputs for known inputs.
5. **Configuration utilities** (`AppConfig`, `Labels`) load, cache, and reload `.properties` keys without crashing.

The suite is fast (no I/O, no HTTP, no UI) so it can run on every commit.

---

## 2. Test Inventory

| File | Surface | Style |
|---|---|---|
| `test_AppConfig.m` | `AppConfig.get` / `getDouble` / `reload` | functiontests |
| `test_AppState.m` | `AppState` predicates + activity log + reset | functiontests |
| `test_AsyncRunner.m` | `parfeval` wrapper, future result handling | classdef |
| `test_AuthService.m` | login / logout / me / list projects delegation | classdef |
| `test_BackendService.m` | list / get / calibration / topology / compare / save+get selection | classdef |
| `test_BackgroundTaskManager.m` *(new)* | register / update / complete / fail / cancel / clear / countActive / events | functiontests |
| `test_BenchmarkDashboardViewModel.m` | dashboard VM load, state mutation | classdef |
| `test_BenchmarkService.m` | volumetric / system-metrics / scorecard / regression / classify / prediction-calibration | classdef |
| `test_BundleService.m` | reproducibility ZIP assembly, manifest, SHA-256 | functiontests |
| `test_CircuitCuttingViewModel.m` | cutting VM submit / poll / cancel | classdef |
| `test_CircuitModel.m` + `_export.m` | circuit model + QASM/Qiskit/Cirq/Braket export | mix |
| `test_CircuitService.m` | upload / list / get / analyze / preview / match-benchmarks / update / delete | classdef |
| `test_CuttingService.m` | analyze cuts / presets / batches / poll / cancel | classdef |
| `test_FastAPIClient.m` | construction, URL safety, project-id, timeout | classdef |
| `test_JobService.m` | submit / list / get / status / cancel / pause / results / detailed / error-trends / rb-decay | classdef |
| `test_JsonHelper.m` | dotted-path pick, list-envelope extraction, table mapping | functiontests |
| `test_Labels.m` | label lookup + reload | functiontests |
| `test_Logger.m` | level threshold, structured format, masking | functiontests |
| `test_MitigationCompareViewModel.m` | mitigation compare VM parallel-fan-out | classdef |
| `test_MitigationService.m` *(new)* | list-levels / estimate delegation | functiontests |
| `test_PredictionService.m` | predict (multi-backend) / getPrediction / optimize | classdef |
| `test_ProjectService.m` | CRUD / dashboard / activities / notes / benchmark-config / latest-prediction / reports | classdef |
| `test_QecEngineService.m` | analytical fidelity, code comparison, surface-code sweep | functiontests |
| `test_QmcService.m` *(new)* | submitAnalyze / getAnalyzeJob / cancel / getLast / downloadIbmLog | functiontests |
| `test_ReportService.m` | generate / list / get / download / share | classdef |
| `test_ResourceEstimatorService.m` | distance from physical err, T-state budget, runtime | functiontests |
| `test_RunPlannerService.m` | Pareto frontier, mitigation factor table, pickOptimal | functiontests |
| `test_ServiceContainer.m` | DI wiring of all 14 HTTP services | classdef |
| `test_SettingsService.m` | get / save preferences, verify-IBM, clear cache | classdef |
| `test_StatevectorSimulator.m` | gate-by-gate, Bloch, top-K amplitudes, ≤ 14 qubits | functiontests |
| `test_TemplateRegistry.m` | composer-template gallery integrity | functiontests |
| `test_Theme.m` | color/font constants reachable | functiontests |

*Total: 34 test files (31 pre-existing + 3 new in this pass).*

---

## 3. Test Cases — New Files

Each case below states **scenario** (what is being exercised), **inputs**, **system under test invocation**, **expected output** (the assertion's predicate), and the **type of assertion**. The **actual output** and **status** for each case are filled in at run time and dumped into `doc/TEST_REPORT.md` by `scripts/run_tests.m`.

### 3.1 `test_MitigationService.m`

| ID | Scenario | Inputs | SUT call | Expected Output | Assertion |
|---|---|---|---|---|---|
| MIT-01 | `listLevels` reaches the levels endpoint via the auth-`GET` verb | `token='tok-123'` | `svc.listLevels(token)` | Stub `LastMethod == 'getAuth'`; `LastEndpoint == '/api/mitigation/levels'` | `assertEqual` |
| MIT-02 | `estimate` reaches the estimate endpoint via the auth-`POST` verb | `body=struct(mitigation_level=1, backend_name='ibm_marrakesh', base_shots=4096, circuit_qubits=5)`; `token='tok-1'` | `svc.estimate(body, token)` | Stub `LastMethod == 'postAuthJson'`; `LastEndpoint == '/api/mitigation/estimate'` | `assertEqual` |
| MIT-03 | `estimate` payload round-trips intact | `body=struct(mitigation_level=2, backend_name='ibm_torino', base_shots=8192, circuit_qubits=12)`; `token='tok'` | `svc.estimate(body, token)` | `LastPayload.mitigation_level == 2`; `backend_name == 'ibm_torino'`; `base_shots == 8192`; `circuit_qubits == 12` | `assertEqual` per field |
| MIT-04 | `listLevels` forwards the bearer token to the client | `token='tok-abc'` | `svc.listLevels(token)` | `LastToken == 'tok-abc'` | `assertEqual` |
| MIT-05 | `estimate` returns the client response unchanged | Stub `Response = struct(plan=struct(id='plan-1'), cost=struct(shot_multiplier=1.7), summary='Mitigation: Standard')` | `out = svc.estimate(struct(), 'tok')` | `out.plan.id == 'plan-1'`; `out.cost.shot_multiplier == 1.7`; `out.summary == 'Mitigation: Standard'` | `assertEqual` per field |
| MIT-06 | Constructor stores the injected `FastAPIClient` | `stub = StubFastAPIClient()` | `svc = MitigationService(stub)` | `isa(svc, 'MitigationService') == true` | `assertTrue` |

### 3.2 `test_QmcService.m`

| ID | Scenario | Inputs | SUT call | Expected Output | Assertion |
|---|---|---|---|---|---|
| QMC-01 | `submitAnalyze` posts to the per-circuit QAE-analyze endpoint | `circuitId='cir-42'`, mode `'statevector'`, shots=4096, eps=0.01, conf=0.95, eval_qubits=6, metric `'option_price'`, backend=`[]`, opts=`struct()`, `token='tok'` | `svc.submitAnalyze(...)` | `LastMethod == 'postAuthJson'`; `LastEndpoint` contains `'/api/circuits/cir-42/qae/analyze'` | `assertEqual` + `contains` |
| QMC-02 | `submitAnalyze` payload includes the six required fields and omits `backend` when caller passes `[]` | mode `'statevector'`, shots=2048, eps=0.005, conf=0.99, eval_qubits=8, metric `'var_95'`, backend=`[]` | as above | `p.execution_mode=='statevector'`; `p.shots==2048`; `p.epsilon==0.005`; `p.confidence_level==0.99`; `p.num_eval_qubits==8`; `p.risk_metric=='var_95'`; `isfield(p,'backend')==false` | `assertEqual` + `assertFalse` |
| QMC-03 | `submitAnalyze` adds `backend` when runtime mode supplies a backend name | mode `'runtime'`, backend `'ibm_marrakesh'` | as above | `isfield(p,'backend')==true`; `p.backend=='ibm_marrakesh'` | `assertTrue` + `assertEqual` |
| QMC-04 | `submitAnalyze` propagates `opts.mitigation` and `opts.compute_greeks` into the payload | `opts=struct(mitigation='zne', compute_greeks=true)`, mode `'runtime'`, backend `'ibm_torino'` | as above | `p.mitigation=='zne'`; `logical(p.compute_greeks)==true` | `assertEqual` |
| QMC-05 | `getAnalyzeJob` polls the per-job endpoint via `GET` | `jobId='job-xyz'`, `token='tok'` | `svc.getAnalyzeJob(jobId, token)` | `LastMethod == 'getAuth'`; `LastEndpoint == '/api/qae/jobs/job-xyz'` | `assertEqual` |
| QMC-06 | `cancelAnalyzeJob` cancels via `DELETE` | same | `svc.cancelAnalyzeJob(jobId, token)` | `LastMethod == 'deleteAuth'`; `LastEndpoint == '/api/qae/jobs/job-xyz'` | `assertEqual` |
| QMC-07 | `getLast` fetches the cached result for a circuit | `circuitId='cir-7'`, `token='tok'` | `svc.getLast(circuitId, token)` | `LastMethod == 'getAuth'`; `LastEndpoint == '/api/circuits/cir-7/qae/result'` | `assertEqual` |
| QMC-08 | `downloadIbmLog` streams the JSONL export and writes the destination file | `circuitId='cir-9'`, `fmt='jsonl'`, `destPath=tempname()+'.jsonl'`, `token='tok'` | `saved = svc.downloadIbmLog(...)` | `LastMethod == 'downloadFileAuth'`; `LastEndpoint` contains `'/qae/ibm-log'` and `'fmt=jsonl'`; `saved==destPath`; `exist(destPath,'file')==2` | `assertEqual` + `contains` + `exist` |

### 3.3 `test_BackgroundTaskManager.m`

| ID | Scenario | Inputs | SUT call | Expected Output | Assertion |
|---|---|---|---|---|---|
| BGT-01 | Sequential id allocation `bgt_1`, `bgt_2`, … | two `register` calls with distinct `displayName` | `id1=mgr.register(...)`; `id2=mgr.register(...)` | `id1=='bgt_1'`; `id2=='bgt_2'` | `assertEqual` |
| BGT-02 | Default status on new task is `'queued'` | one `register` call without status | `t=mgr.findById(id)` | `t.status=='queued'` | `assertEqual` |
| BGT-03 | `update(id, fields)` patches progress + statusText | `update(id, struct(progressPct=42, statusText='Running shots'))` | `t=mgr.findById(id)` | `t.progressPct==42`; `t.statusText=='Running shots'` | `assertEqual` |
| BGT-04 | `complete` marks terminal-success and fires `onComplete(payload)` | task registered with `onComplete=cb`; `complete(id, struct(value=99))` | `t=mgr.findById(id)` + captured callback record | `t.status=='completed'`; `t.progressPct==100`; callback ran once with `payload.value==99` | `assertEqual` |
| BGT-05 | `fail(id, ME)` stores the MException | `ME=MException('Test:Boom','kaboom')`; `mgr.fail(id, ME)` | `t=mgr.findById(id)` | `t.status=='failed'`; `t.error.identifier=='Test:Boom'` | `assertEqual` |
| BGT-06 | `cancel` calls `onCancel` and flips status | task registered with `onCancel=fn`; `mgr.cancel(id)` | `t=mgr.findById(id)` + cancel-hit counter | `t.status=='cancelled'`; `hits==1` | `assertEqual` |
| BGT-07 | `cancel` is a no-op on terminal tasks | `complete(id, struct(done=true))`; `mgr.cancel(id)` | `t=mgr.findById(id)` | `t.status=='completed'` (not flipped) | `assertEqual` |
| BGT-08 | `clearTerminal` evicts only completed/failed/cancelled | 3 tasks A,B,C; B→complete; C→cancel; A stays queued | `list=mgr.list()` | `numel(list)==1`; `list{1}.displayName=='A'` | `assertEqual` |
| BGT-09 | `countActive` counts only queued + running | 3 tasks; B→`running` via `update`; C→complete | `n=mgr.countActive()` | `n==2` | `assertEqual` |

### 3.4 `test_FastAPIClient.m` — flag-aware security cases (updated)

| ID | Scenario | Inputs | SUT call | Expected Output | Assertion |
|---|---|---|---|---|---|
| FAC-RemoteHttp | Remote plain-HTTP URL is allowed iff `allow_insecure_base_url=true` | URL `'http://api.example.com'`; live flag value | `FastAPIClient.assertSafeBaseUrl(url)` | flag=true ⇒ no error; flag=false ⇒ `MException(FastAPIClient:insecureBaseUrl)` | `verifyWarningFree` / `verifyError` |
| FAC-SetBaseUrl | `setBaseUrl` enforces the same policy | URL `'http://attacker.example.com'`; live flag value | `client.setBaseUrl(url)` | as above | as above |

These two cases previously asserted unconditional rejection. They now branch on `AppConfig.get('allow_insecure_base_url', 'false')` so the test reflects the operator-configurable policy (the demo cluster at `http://34.42.87.190:5715` runs with the flag set to `true`).

---

## 3.5 Reporting Schema

`scripts/run_tests.m` emits a Markdown report at `doc/TEST_REPORT.md` with one row per test method:

| Column | Source | Example |
|---|---|---|
| `#` | iteration index | `42` |
| `Test` | `result.Name` (full `<file>/<method>`) | `test_QmcService/test_submitAnalyze_payload_shape` |
| `Status` | derived: `Passed→PASS`, `Failed→FAIL`, `Incomplete→INCOMPLETE` | `PASS` |
| `Duration (s)` | `result.Duration` | `0.012` |
| `Notes` | scenario hint for PASS (derived from method name) / one-line failure summary for FAIL | `verifies submit analyze payload shape` |

For failing tests, an extra **Failure Diagnostics** section dumps:
- the full diagnostic text from `result.Details.DiagnosticRecord(1).Report`
- the call stack from `result.Details.DiagnosticRecord(1).Stack` (one line per frame: function name + line number)

That stack frame is the **reason of failure** — usually a `verifyEqual` / `verifyError` line that points back to the assertion that failed and the actual-vs-expected pair captured by the MATLAB Unit Test Framework.

---

## 4. Running the Suite

```matlab
% All tests
runtests('tests')

% One file
runtests('tests/test_QmcService')

% From the shell (CI / scripted)
matlab -batch "addpath(genpath('src')); addpath('tests'); results = runtests('tests'); disp(results); assertSuccess(results)"
```

This pass executes the suite via `/Applications/MATLAB_R2025b.app/bin/matlab -batch` with `scripts/run_tests.m` — emits a console summary and writes a Markdown report to `doc/TEST_REPORT.md`.

---

## 5. Stub Surface

`StubFastAPIClient` records the most recent call and returns a canned `Response`. Per-method coverage:

| Stub method | Records | Notes |
|---|---|---|
| `login`, `logout`, `getMe`, `listProjects` | endpoint + token | `login` masks the password |
| `get`, `getAuth`, `deleteAuth` | endpoint + token | no payload |
| `postAuthJson(..., varargin)` | endpoint + payload + token | `varargin` swallows optional `timeoutSec` (QmcService passes 30) |
| `putAuthJson`, `patchAuthJson`, `patchAuthRaw` | endpoint + payload + token | |
| `uploadFileAuth` | endpoint + file + fields + token | |
| `downloadFileAuth` | endpoint + localPath + token | writes a 2-byte `{}` placeholder so callers that `stat` the destination see a real file |

Dependency-injected via the service constructor, so production `FastAPIClient` never runs in unit tests.

---

## 6. Acceptance Criteria

The suite **passes** when:

- Every `Test` method reports `Passed = true`.
- Total execution time stays under 30 seconds on a dev workstation.
- No test prints to stderr (errors / unexpected warnings).

The suite **fails the build** when any of:

- A service-layer test reports a different endpoint, verb, or payload field than the corresponding row in `doc/fastapi_contract.md`.
- A safety-helper test allows a URL the `FastAPIClient.assertSafeBaseUrl` policy must reject.
- A local-compute test produces a non-deterministic result on identical inputs.

---

## 7. Out of Scope

- Integration / end-to-end tests against the live FastAPI server. Those live under `scripts/seed_*.m` and a manual smoke run.
- UI tests against the rendered `uifigure`. MATLAB lacks a headless rendering harness in the project's tool inventory.
- Performance benchmarks. Cache-hit timing is observed at runtime via `Logger.http`.
