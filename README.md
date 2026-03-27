# QTAU MATLAB 2025b Add-on Source (FastAPI-connected)

This package provides a MATLAB 2025b-compatible source scaffold for the QTAU add-on described in the storyboard PDF.
It includes:

- multi-screen desktop UI implemented in MATLAB using `uifigure`, `uitabgroup`, grids, tables, trees, gauges, and charts
- 12 storyboard screens/tabs
- FastAPI backend client service with JSON request/response handling
- app state model and DTO mapping
- placeholders for upload, analysis, backend discovery, benchmark configuration, prediction, job monitoring, results, reports, and settings

## Important

This is **source code**, not a compiled `.mltbx` binary package. Packaging a true MATLAB Toolbox file requires MATLAB tooling at build time. You can open this project in MATLAB 2025b and package it as a toolbox from:

`HOME > Add-Ons > Package Toolbox`

Suggested toolbox entry point:

- `src/QTAUApp.m`

## Expected FastAPI endpoints

The included client expects these routes:

- `GET    /health`
- `POST   /api/projects`
- `POST   /api/circuits/upload`
- `POST   /api/circuits/analyze`
- `GET    /api/backends`
- `POST   /api/benchmark/configure`
- `POST   /api/predictions`
- `POST   /api/jobs`
- `GET    /api/jobs/{job_id}`
- `GET    /api/jobs/{job_id}/partial-results`
- `GET    /api/results/{job_id}`
- `POST   /api/reports/generate`
- `GET    /api/reports/{report_id}`
- `GET    /api/settings`
- `PUT    /api/settings`

You can change these in `src/services/FastAPIClient.m`.

## Quick start

1. Add the `src` folder to MATLAB path.
2. Run:

```matlab
app = QTAUApp;
```

3. Set FastAPI base URL in Settings tab.
4. Click **Refresh Backends** / **Analyze Circuit** / **Run Benchmark** / **Submit Job**.

## Structure

- `src/QTAUApp.m` - main app UI and orchestration
- `src/services/FastAPIClient.m` - backend REST client
- `src/models/AppState.m` - application state container
- `src/utils/JsonHelper.m` - JSON helpers
- `src/utils/TableDataFactory.m` - demo tables and chart data
- `docs/fastapi_contract.md` - recommended backend request/response contract

