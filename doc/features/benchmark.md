# Benchmark

## 1. What it is

Benchmark is the operator surface for running standard quantum
benchmarks (Quantum Volume, CLOPS, Layer Fidelity, EPLG), comparing
backends, tracking calibration drift, classifying circuits into QV
depth classes, and reviewing prediction-vs-actual fidelity calibration.
The product splits the surface across two screens:

- **Benchmark** — submit a benchmark configuration (execution params,
  mitigation strategy, cost preview).
- **Benchmark Dashboard** — read-only summary of past configurations
  + recommendations.

## 2. Purpose

- Quantitatively compare hardware: which backend has higher Quantum
  Volume? Which has lower EPLG? Which has more stable layer fidelity
  over the past week?
- Track **calibration drift** — when did the backend's fidelity start
  to slip? `getBenchmarkRegression` returns time-series fidelity for
  standard benchmark circuits.
- **Classify** a circuit into a QV depth class so the operator can
  reason about whether it's a "QV-3" (small algorithm) or "QV-5+"
  (utility-scale) workload.
- **Calibrate predictions** — compare predicted vs actual fidelity
  for completed jobs; surface MAE / Pearson correlation.

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Screen | `BenchmarkScreen`, `BenchmarkDashboardScreen` | `src/presentation/screens/` |
| ViewModel | `BenchmarkViewModel`, `BenchmarkDashboardViewModel` | `src/presentation/viewmodels/` |
| Service | `BenchmarkService` | `src/domain/services/BenchmarkService.m` |
| Backend router | `benchmark` router (`/api/benchmark/*`) | `qdash/api/routers/benchmark.py` |

## 4. Algorithm / data sources

### Volumetric Fidelity Map

`GET /api/benchmark/volumetric?project_id=…` returns a grid of
(width, depth) → fidelity values for the QED-C-style volumetric
heatmap. Empty cells correspond to circuits the backend can't run
(width > device qubits or depth > coherence budget).

### System Benchmark Metrics

`GET /api/benchmark/system-metrics/{backend}` returns the standard
suite:

- **Quantum Volume** — IBM's headline metric `2^n` where `n` is the
  largest square circuit the device can run with > 2/3 success.
- **CLOPS** — Circuit Layer Operations Per Second; throughput.
- **Layer Fidelity** — average per-layer 2Q-gate fidelity across the
  device.
- **EPLG** — Effective Per-Layer Error rate.

### Backend Scorecard (QPack-inspired)

`GET /api/benchmark/scorecard?project_id=…&backend_name=…` returns
multi-dimensional scoring: capacity / scalability / accuracy / runtime
sub-scores plus a weighted overall score.

### Benchmark Regression

`GET /api/benchmark/regression?project_id=…&backend_name=…` returns
time-series fidelity for a few canonical benchmark circuits,
enabling drift detection.

### Circuit Classification

`GET /api/benchmark/classify/{circuit_id}?project_id=…` returns
`{qv_depth_class, algorithm_domain, complexity_tier}`.

### Prediction Calibration

`GET /api/benchmark/prediction-calibration?project_id=…` returns
scatter data plus accuracy metrics (MAE, Pearson) for predicted-vs-
actual fidelity over the project's completed jobs.

## 5. Workflow

### Benchmark screen

1. Operator opens **Benchmark**.
2. Picks circuit, backend, shot count, optimization level.
3. Picks **Mitigation strategy** (dropdown pre-fillable from QEM
   popup's Apply to Benchmark).
4. Reviews **Cost preview** (effective shots, est. wall, IQP units)
   pulled from `/api/mitigation/estimate`.
5. Clicks **Run Benchmark** — submits a job via the standard job
   pipeline (`POST /api/jobs/submit`).

### Benchmark Dashboard

1. Operator opens **Benchmark Dashboard**.
2. KPI cards summarise the latest scorecard for the active backend.
3. Recommendations card surfaces "Try Aggressive on this circuit;
   bias-reduction estimated 2.8× at 3× shot overhead" style hints.
4. Drift table lists recent regression-fidelity trends per benchmark
   circuit.

## 6. Data flow

```
Open Benchmark Dashboard:
   GET /api/benchmark/volumetric?project_id=…              (heatmap)
   GET /api/benchmark/scorecard?project_id=…&backend_name=…
   GET /api/benchmark/regression?project_id=…&backend_name=…
   GET /api/benchmark/system-metrics/{backend}              (QV, CLOPS, …)

Classify currently-selected circuit:
   GET /api/benchmark/classify/{circuit_id}?project_id=…

Calibrate predictions:
   GET /api/benchmark/prediction-calibration?project_id=…
```

## 7. Business logic

- **Project-scoped** — all benchmark queries take `project_id` so
  results are namespaced per project.
- **Backend-pinned** — most dashboards default to `app.State.selectedBackend`
  (set on the Backends screen).
- **Read-only screen** — `getVolumetric`, `getSystemMetrics`,
  `getBackendScorecard`, `getBenchmarkRegression`,
  `getCircuitClassification`, `getPredictionCalibration` are all
  GETs; the screen never mutates server state.
- **Auth + project context** — required.
- **No async-job pattern** — these endpoints are fast (calibration
  data is already aggregated server-side).

## 8. Reference

- Screens: `src/presentation/screens/BenchmarkScreen.m`, `BenchmarkDashboardScreen.m`
- ViewModels: `src/presentation/viewmodels/BenchmarkViewModel.m`, `BenchmarkDashboardViewModel.m`
- Service: `src/domain/services/BenchmarkService.m`
- Backend router: `qdash/api/routers/benchmark.py`
