# Predictions

## 1. What it is

The Predictions screen forecasts a circuit's runtime characteristics —
fidelity, queue time, output distribution — on one or many backends
*before* the operator submits the job. It also exposes
`/api/optimize` which runs Qiskit's transpiler with a configurable
`optimization_level` and `transpilation_strategy`, so the operator can
preview how a given backend will rewrite their circuit.

## 2. Purpose

- Avoid wasting expensive QPU shots on a circuit / backend pair that
  will deliver poor fidelity.
- Compare across multiple backends in one call to pick the best
  primary / backup pair.
- Surface predicted fidelity, expected output distribution, and an
  error budget breakdown so the operator can reason about which error
  source (1Q gate / 2Q gate / readout / decoherence) dominates.

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Screen | `PredictionScreen` | `src/presentation/screens/PredictionScreen.m` |
| ViewModel | `PredictionViewModel` | `src/presentation/viewmodels/PredictionViewModel.m` |
| Service | `PredictionService` | `src/domain/services/PredictionService.m` |
| Backend router | `predict` + `optimize` (`/api/predict`, `/api/optimize`) | `qdash/api/routers/prediction.py` |

## 4. Algorithm

### `/api/predict`

The backend wraps a noise-aware fidelity model. Input shape:

```
{ "circuit_id":         "<uuid>",
  "backend_names":      ["ibm_pittsburgh", "ibm_marrakesh"],
  "shots":              4096,
  "optimization_level": 1 }
```

For each requested backend it returns:

- `predicted_fidelity` — derived from the device's calibration:
  per-1Q-gate / per-2Q-gate / per-readout error compounded across the
  transpiled circuit's gate counts.
- `confidence_interval: [lo, hi]` — 95 % CI around the prediction.
- `error_budget` — per-source breakdown.
- `expected_distribution` — top-k bitstring probabilities under the
  fidelity model.
- `queue_time_estimate` — IBM Runtime queue estimator.

### `/api/optimize`

Runs Qiskit's transpiler with the requested `optimization_level`
(0 / 1 / 2 / 3) and `transpilation_strategy` (`'default'`, `'sabre'`,
`'noise_aware'`). Returns the transpiled circuit + cost reduction
metrics (depth before / after, 2Q-gate count before / after).

## 5. Workflow

1. Operator opens **Prediction**.
2. Toolbar **Circuit** + **Backend** dropdowns auto-populate from the
   project's circuits + the backend pool.
3. Picks shots and optimization level.
4. Clicks **Predict** — single-backend or cross-backend (multi-select)
   depending on dropdown mode. Returns one card per backend with
   predicted fidelity, CI, expected distribution histogram, and error
   budget pie-chart.
5. Clicks **Optimize** to view the transpiled circuit and the
   depth / 2Q-gate reductions.
6. Optionally **Save Prediction** — server persists the prediction
   record so Reports can reference it via `prediction_id`.

## 6. Data flow

```
POST /api/predict
     body = { circuit_id, backend_names: [...], shots, optimization_level }
     → { predictions: [
          { backend_name, predicted_fidelity, confidence_interval,
            error_budget, expected_distribution, queue_time_estimate, ... },
          ...
       ], prediction_id?, created_at }

GET /api/predict/{prediction_id}
     → previously persisted prediction record

POST /api/optimize
     body = { circuit_id, backend_name, optimization_level,
              transpilation_strategy }
     → { transpiled_circuit, depth_before, depth_after,
         twoq_before, twoq_after, ... }
```

## 7. Business logic

- **Multi-backend** — `backend_names` is always sent as an array; a
  single-backend predict just sends `[backend_name]`.
  `PredictionService.normalizeBackends` accepts char / string / cell /
  string-array inputs and normalises to `cellstr`.
- **Project context** — required; predictions are scoped to a project.
- **Read-only operation** — `/api/predict` does not submit any
  hardware work. Only `/api/jobs/submit` does that, on a separate
  Benchmark / Jobs flow.
- **Save = persist** — calling `getPrediction(id)` later requires the
  predict POST to have returned a `prediction_id`. Auto-saved when the
  caller passes a project context.

## 8. Reference

- Screen: `src/presentation/screens/PredictionScreen.m`
- ViewModel: `src/presentation/viewmodels/PredictionViewModel.m`
- Service: `src/domain/services/PredictionService.m`
- Backend router: `qdash/api/routers/prediction.py`
