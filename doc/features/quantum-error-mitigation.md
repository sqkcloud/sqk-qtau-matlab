# Quantum Error Mitigation (QEM)

Cross-link: a deeper phase-history of the QEM system as a whole is in
[`../Quantum Error Mitigation.md`](../Quantum%20Error%20Mitigation.md).
This document covers the **operator surface** — the QEM popup launched
from the Analysis screen — using the standard seven-section template.

## 1. What it is

A modal popup that consolidates everything the operator needs to reason
about error mitigation for a specific circuit / backend pair: the
mitigation-level ladder (Raw / Standard / Aggressive / TEM / Custom),
ZNE noise-factor sweep, dynamical-decoupling sequence, twirling toggles,
TEM toggle, sibling-raw toggle, an Estimated Cost preview, a
per-technique comparison table, ZNE evidence (when QAE is cached),
the PEC γ̄^depth feasibility curve, the cutting overhead curve, the
γ̄ KPI strip, and a Recommendation card.

## 2. Purpose

- Help an operator **pick** a mitigation level that's an honest
  trade-off between bias reduction, shot overhead, and wall-clock —
  rather than blindly defaulting to Standard.
- Provide a **what-if surface** that doesn't actually submit work: every
  number on this popup comes from `/api/mitigation/estimate` (cost
  preview) plus cached results, so operators can iterate cheaply before
  hitting Run on the Benchmark or Cutting screen.
- Apply the selected stack to the Benchmark screen via
  **Apply to Benchmark**, or generate a QEM-specific PDF via
  **Generate Report**.

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Trigger | Analysis screen toolbar button | `src/presentation/screens/AnalysisScreen.m` |
| Dialog builder | `DialogBuilder.buildErrorMitigationDialog` | `src/presentation/DialogBuilder.m:776–1148` |
| ViewModel | `AnalysisViewModel.onOpenEmDialog` and friends | `src/presentation/viewmodels/AnalysisViewModel.m` |
| Service | `MitigationService` | `src/domain/services/MitigationService.m` |
| Backend router | `mitigation` router (`/api/mitigation/{levels, estimate}`) | `qdash/api/routers/mitigation.py` |
| Backend PDF | `ReportService._build_em_pdf_bytes` | `qdash/api/services/report_service.py` |

The popup is a separate `uifigure` (`app.EmDialog`). The
`OverlayManager.showLoading` host-detection block re-parents loading
overlays to it when open (`OverlayManager.m:75–90`).

## 4. Algorithm

### Mitigation-level ladder

The five levels are server-defined enum values (also mirrored as a
static fallback in `AnalysisViewModel.staticEmLevelLadder`):

| id | name | label | overhead hint |
|---:|------|-------|---------------|
| 0  | raw       | Raw                    | 1× shots, 1× wall-clock |
| 1  | standard  | Standard (default)     | ~1× shots, ~1× wall-clock |
| 2  | aggressive| Aggressive             | ~3× shots, ~3× wall-clock |
| 3  | tem       | TEM (utility-scale)    | ~5–15× wall-clock (Phase 4) |
| -1 | custom    | Custom (advanced)      | varies |

### γ̄ (gamma-bar) KPI

`γ̄ = (1 − EPLG)^(−2)`. EPLG (Effective Per-Layer error rate) comes
from the backend calibration, with this fallback chain
(`AnalysisViewModel.extractEplg`):

1. Top-level `eplg` / `epc` / `avg_2q_gate_error` / `two_q_error_avg`.
2. `mean(couplings[].gate_error_2q)` if `couplings[]` is populated.
3. Heuristic `10·avg(qubits[].gate_error_1q) + 0.1·avg(qubits[].readout_error)`
   when only per-qubit data is available (typical IBM calibration
   shape today).

The PEC γ̄^depth feasibility curve plots `γ̄^d` for `d ∈ logspace(0,4)`
and crosses the 1e4 classical-sim threshold at the depth at which PEC
becomes infeasible.

### Recommendation ranker

`bestRecommendation` picks the level that maximises
`bias_reduction / log(1 + shot_multiplier)`. Bias-reduction values are
heuristics in `AnalysisViewModel.estimateBiasReduction` aligned with
the server level IDs (3 = TEM, −1 = Custom).

### Static fallback for `/api/mitigation/levels`

When the deployed backend doesn't yet have the `mitigation` router (or
the route returns 4xx), the popup paints a static ladder synchronously
at dialog open so the dropdown is never stuck on "(loading…)" —
`AnalysisViewModel.applyEmLocalLevelFallback`.

## 5. Workflow

1. Open Analysis → pick a circuit → click **Quantum Error Mitigation Analysis**.
2. The popup opens. Static ladder paints immediately. Async refresh
   shows a spinner labelled *"Refreshing mitigation analysis..."*
   (`Labels.get('loading_em_refresh')`) while five
   `/api/mitigation/estimate` POSTs run plus one calibration GET.
3. The Technique table populates with per-level Bias / Overhead × /
   Wall (s) / Pick. The Recommendation card lists the auto-pick.
4. The KPI strip fills (Qubits / Depth / 2Q / γ̄ / Advantage).
5. The PEC γ̄^depth chart draws the feasibility curve with the
   classical-sim threshold and a dotted line at the current circuit's
   depth.
6. The Raw vs Mitigated histogram renders bitstring counts (sampler
   mode) or the QAE path-distribution top bins (when only QAE data is
   cached) — `renderEmRawMitigatedHistogram` falls back gracefully.
7. Operator can change Backend / Mitigation level / form fields. Each
   change re-runs the async refresh with the spinner.
8. **Apply to Benchmark** — pre-fills the Benchmark screen's Mitigation
   dropdown with the recommended level.
9. **Export JSON** — saves the in-memory bundle to a local `.json`.
10. **Generate Report** — POSTs to `/api/reports/generate` with
    `metadata.report_kind = "error_mitigation"` so the backend routes
    to its dedicated `_build_em_pdf_bytes` builder (teal/orange
    palette, technique comparison, ZNE evidence).

## 6. Data flow

```
Open dialog →  GET  /api/mitigation/levels                 (envelope)
            │  fallback: static ladder if 4xx
            │
            │  for each level in ladder:
            │    POST /api/mitigation/estimate             (cost preview)
            │    body = {mitigation_level, primitive,
            │            backend_name, base_shots,
            │            circuit_qubits, cutting_overhead_qubits,
            │            mitigation_options? (Custom only)}
            │
            │  GET  /api/backends/{name}/calibration       (γ̄ + PEC chart)
            │  GET  /api/circuits/{id}/qae/result          (ZNE curve)
            │  GET  /api/circuits/{id}                     (KPIs)
            │  POST /api/cutting/analyze                   (cuts curve)
            │
Generate Report:
            POST /api/reports/generate  (metadata.report_kind=
                                         "error_mitigation",
                                         metadata.em_bundle=[...],
                                         metadata.em_form={...})
            poll GET /api/reports/{id}  → status="ready"
            stream GET /api/reports/{id}/download → local PDF
```

## 7. Business logic

- **Form-change refresh** is async and paired with the standard
  loading overlay (`AnalysisViewModel.refreshEmEstimateBundle`).
- **Calibration cache** — `app.EmCachedCalibration = {backend, data}`
  is keyed by backend name. The KPI / γ̄^depth renderers prefer the
  cache and only fall back to a sync `getCalibration` when empty
  (defense-in-depth for legacy entry paths).
- **Custom-level options** — only forwarded to `/api/mitigation/estimate`
  for the **currently-selected** level (matches legacy behaviour).
- **Snapshot pattern** — every async work captures form state into a
  plain struct on the main thread (`snapshotEmFormState`) so the worker
  can't deref a torn-down dropdown if the dialog closes mid-flight.
- **TEM is Phase 4** — falls back to Standard with a note today.
- **Heron-r2 fractional gates** — when the backend uses continuous-angle
  2q rotations, twirling and ZNE-PEA are auto-disabled with an inline
  conflict notice on the popup (mutually exclusive per IBM Runtime
  docs).

## 8. Reference

- Trigger button: `src/presentation/screens/AnalysisScreen.m`
- Dialog: `src/presentation/DialogBuilder.m:776–1148` (`buildErrorMitigationDialog`)
- ViewModel: `src/presentation/viewmodels/AnalysisViewModel.m` (`onOpenEmDialog`, `loadEmInitialData`, `loadEmBackendsForDialog`, `refreshEmEstimateBundle`, `applyEmRefreshResults`, `renderEmKpis`, `renderEmGammaDepthCurve`, `renderEmZneCurve`, `renderEmRawMitigatedHistogram`, `renderEmTechniqueTable`, `renderEmRecommendation`, `onEmGenerateReport`, `applyEmLocalLevelFallback`)
- Service: `src/domain/services/MitigationService.m`
- Backend router: `qdash/api/routers/mitigation.py`
- Backend PDF: `qdash/api/services/report_service.py:_build_em_pdf_bytes`
- Phase-history doc: [`../Quantum Error Mitigation.md`](../Quantum%20Error%20Mitigation.md)
