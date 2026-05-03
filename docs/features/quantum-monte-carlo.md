# Quantum Monte Carlo (QMC / QAE)

## 1. What it is

Quantum Monte Carlo Simulation is an option-pricing / risk-analytics
workload that uses **Quantum Amplitude Estimation (QAE)** to replace the
classical Monte Carlo expectation-value step. The operator opens a modal
popup from the Analysis screen, picks an execution mode and a risk
metric, runs the analysis (locally on a statevector simulator, or
remotely on IBM Runtime), and gets back a chart-rich report of the loss
distribution, VaR / CVaR, expected payoff, classical-MC equivalent shot
count, the quadratic-speedup factor, and (when run with mitigation) a
Zero-Noise Extrapolation curve.

## 2. Purpose

- Quantitative finance and risk teams need a way to evaluate the
  expected payoff and tail risk (VaR / CVaR) of an option contract under
  a price model. QAE provides a quadratic speedup over classical Monte
  Carlo at a fixed estimation accuracy, so a problem that needed
  10 000 classical samples can land on the same accuracy with ~100
  amplitude-estimation iterations.
- The popup lets a non-quantum operator drive end-to-end: pick a market
  scenario, optionally enable mitigation, optionally pick an IBM
  backend, then export the result as a polished PDF.

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Screen | `AnalysisScreen` (hosts the QMC button) | `src/presentation/screens/AnalysisScreen.m` |
| Dialog builder | `DialogBuilder.buildQmcDialog` | `src/presentation/DialogBuilder.m` |
| ViewModel | `AnalysisViewModel` (the QMC popup is a section of it) | `src/presentation/viewmodels/AnalysisViewModel.m` |
| Service | `QmcService` | `src/domain/services/QmcService.m` |
| Backend router | `qae` router (`/api/circuits/{id}/qae` and `/api/qae/jobs`) | `qdash/api/routers/qae.py` |

Modal flow: `app.AnalysisVm.onOpenQmcDialog()` → `DialogBuilder.buildQmcDialog(app)` instantiates a `uifigure` (`app.QmcDialog`), wires "Run QMC" / "Generate Report" / "Download IBM Log" / "Cancel" buttons to VM callbacks. The dialog stays modal until the operator closes it; the `CloseRequestFcn` routes through `AnalysisVm.onCloseQmcDialog` which stops any in-flight poll timer.

The overlay (`OverlayManager`) re-parents to `app.QmcDialog` automatically when it's open, so loading messages render on top of the modal — see [`architecture.md`](architecture.md) §3.

## 4. Algorithm

### Quantum Amplitude Estimation (QAE)

Given a black-box `A` that prepares `|ψ⟩ = √(1−a)|0⟩|ψ₀⟩ + √a|1⟩|ψ₁⟩`,
QAE estimates the amplitude `a ∈ [0,1]` to additive accuracy `ε` using
`O(1/ε)` queries. Classical Monte Carlo needs `O(1/ε²)` samples for the
same accuracy — **quadratic speedup**.

The backend wraps Qiskit's IterativeAmplitudeEstimation (IAE) for QPU
runs and a textbook QPE-based AE for `statevector` mode.

### Risk metrics derived from `a`

- **expected_payoff** — `a × scale` for the configured option type.
- **var_95 / var_99** — bins of the loss distribution at the
  corresponding quantile.
- **cvar_95** — conditional expectation in the tail of the
  distribution.

The full payoff distribution is reconstructed by post-processing the
amplitude register (`num_eval_qubits` qubits → `2^n` bins).

### Zero-Noise Extrapolation (when `mitigation: "zne"`)

The backend executes the AE circuit at multiple noise scales (1×, 3×, 5×
gate folds), fits a linear or exponential curve to the resulting
amplitudes, and returns the c=0 extrapolant as `mitigated_amplitude`
along with the per-factor sweep in `mitigation_curve`.

## 5. Workflow

1. Operator picks a circuit on the Analysis screen.
2. Clicks the **Quantum Monte Carlo Simulation** button on the Analysis
   toolbar — `AnalysisVm.onOpenQmcDialog` opens the modal.
3. Selects:
   - Execution mode: **Statevector (local)** or **IBM Runtime** (default).
   - Risk metric: option price / VaR-95 / VaR-99 / CVaR-95.
   - Shots, ε, confidence, evaluation-register width.
   - Backend (Runtime mode only).
   - Mitigation: **None** or **Zero-Noise Extrapolation** (default).
   - Optional: market scenario (spot, strike, σ, r, T), correlation
     matrix, compute-Greeks toggle.
4. Clicks **Run QMC** — `AnalysisVm.onRunQmcAnalysis` calls
   `QmcService.submitAnalyze`, which `POST`s to
   `/api/circuits/{id}/qae/analyze` and gets back `{job_id, status:"queued"}`.
5. `AnalysisVm.startQaePoll` arms a 3-second MATLAB `timer` polling
   `GET /api/qae/jobs/{job_id}` until `status ∈ {completed, failed, cancelled}`.
   The loading overlay shows live progress: **Queued (0 %)** →
   **Running (50 %)** → **Completed (100 %)**.
6. On completion, `renderQmcResult` paints the popup: KPIs (amplitude,
   VaR, CVaR, payoff), Greeks table, distribution chart, ZNE curve,
   convergence plot.
7. Operator clicks **Generate Report** — `pollAndDownloadReport` streams
   the PDF built by `ReportService._build_qmc_pdf_bytes` and offers a
   save dialog.
8. Operator clicks **Download IBM Log** (Runtime mode only) —
   `QmcService.downloadIbmLog` streams a JSONL of every IBM Runtime
   submission (`{subcircuit_id, backend, shots, status, job_id, counts, error}`).
9. **Close mid-run** — `CloseRequestFcn` → `AnalysisVm.onCloseQmcDialog`
   stops the poll timer; the server keeps running and the result is still
   cached on the circuit doc for the next visit.

## 6. Data flow

```
QMC popup  --POST /api/circuits/{id}/qae/analyze-->  HTTP 202
   ▲              {execution_mode, shots, epsilon,
   │               confidence_level, num_eval_qubits,
   │               risk_metric, backend?, mitigation?,
   │               market?, correlation?, compute_greeks?}
   │
   │     <--{job_id, status:"queued", circuit_id, ...}--
   │
   │ MATLAB timer (3 s)
   ▼
   GET /api/qae/jobs/{job_id} ──▶ {status:"running", progress, result?}
                              ──▶ {status:"completed", result:{...}}
   │
   │ Optional cancel:
   ▼ DELETE /api/qae/jobs/{job_id}

After completion:
   GET /api/circuits/{id}/qae/result   (cached most-recent result)
   GET /api/circuits/{id}/qae/ibm-log  (Runtime mode JSONL log)
```

### Result payload (key fields)

| Field | Type | Notes |
|-------|------|-------|
| `amplitude_estimate` | float | Raw QAE amplitude `a` |
| `mitigated_amplitude` | float? | ZNE c=0 extrapolant (when mitigation="zne") |
| `mitigation_curve` | `[{noise_factor, amplitude}]` | Per-noise-factor sweep |
| `expected_payoff` | float | Option payoff at `a × scale` |
| `var_95`, `var_99`, `cvar_95` | float | Loss-distribution quantiles |
| `path_distribution` | `[{bin_index, value, probability}]` | 2^N path-amplitude bins |
| `classical_samples_for_same_accuracy` | int | For the speedup ratio |
| `quadratic_speedup` | float | `classical / qae` ratio |
| `runtime_job_id` | str? | IBM Runtime job id (Runtime mode) |
| `greeks` | `{delta, gamma, vega, theta, rho}?` | When compute_greeks=true |
| `market` | `{spot, strike, volatility, ...}?` | Echoed for the report header |

## 7. Business logic

- **Mode default** — IBM Runtime (changes the `backend` requirement and
  enables the IBM Log button).
- **Mitigation default** — Zero-Noise Extrapolation. The popup wires
  the backend to run a 3-point sweep `[1.0, 3.0, 5.0]` with an
  exponential extrapolator unless the operator overrides on the QEM
  popup.
- **Cancellation** — closing the dialog mid-run only stops the matlab
  poll timer; the server keeps running. The result lands on
  `/api/circuits/{id}/qae/result` for the next visit.
- **Async job lifecycle** — `queued → running → completed | failed | cancelled`.
  See [`architecture.md`](architecture.md) §6.
- **Auth + project context** — required. Both `Authorization: Bearer …`
  and `X-Project-Id: …` headers are sent on every call.
- **Cached result** — exactly one persisted QAE result per circuit
  document. Re-running overwrites; the QEM popup reads it back to
  populate its ZNE chart.

## 8. Reference

- Screen: `src/presentation/screens/AnalysisScreen.m`
- Dialog: `src/presentation/DialogBuilder.m` (`buildQmcDialog`)
- ViewModel: `src/presentation/viewmodels/AnalysisViewModel.m` (`onOpenQmcDialog`, `onRunQmcAnalysis`, `startQaePoll`, `renderQmcResult`, `onQmcReportGenerated`, `pollAndDownloadReport`)
- Service: `src/domain/services/QmcService.m`
- Backend router: `qdash/api/routers/qae.py`
- Backend PDF: `qdash/api/services/report_service.py:_build_qmc_pdf_bytes`
- Sample notebook: `samples/aqs-qmc/`
