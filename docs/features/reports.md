# Reports

## 1. What it is

The Reports screen generates, downloads, distributes, and re-opens
analysis reports as PDF / HTML / JSON. It is the **distribution
surface** for everything the rest of the app produces — Quantum Monte
Carlo results, Quantum Error Mitigation analyses, generic project
summaries — and the only screen with a dedicated email-share path.

## 2. Purpose

- Turn a project's analysis state into a portable artifact (PDF for
  share-with-stakeholders, HTML for embed-in-wiki, JSON for
  programmatic consumption).
- Re-download / re-open any prior report from the project (the list is
  populated on tab open).
- Distribute via three channels: **PDF download** (open in OS default
  viewer), **Email** (server-side share via SMTP), **Print** (open in
  default viewer; operator hits Cmd-P from there).

## 3. Architecture

| Layer | Component | Path |
|-------|-----------|------|
| Screen | `ReportsScreen` | `src/presentation/screens/ReportsScreen.m` |
| ViewModel | `ReportsViewModel` | `src/presentation/viewmodels/ReportsViewModel.m` |
| Service | `ReportService` | `src/domain/services/ReportService.m` |
| Backend router | `reports` (`/api/reports/*` and `/api/projects/{id}/reports`) | `qdash/api/routers/reports.py` |
| Backend builders | `_build_qmc_pdf_bytes`, `_build_em_pdf_bytes`, HTML→PDF fallback | `qdash/api/services/report_service.py` |

## 4. Algorithm / flow

### Generate flow (mirrors the QMC popup pattern)

1. `POST /api/reports/generate` (or `/api/projects/{id}/reports`) with
   `{title, report_type:"technical", format, sections, circuit_id?,
   prediction_id?, job_record_id?, metadata?}` → returns
   `{report_id, status, message}` (synchronous in the current backend).
2. Poll `GET /api/reports/{id}` until `status ∈ {ready, completed,
   success, done}` (defensive — built-in for future async builders).
3. Stream `GET /api/reports/{id}/download` to a temp file via
   `ReportService.downloadReportFile` (binary stream — *not* the
   `downloadReport` JSON path).
4. `uiputfile` for the user's destination → `copyfile` → `web()` to
   open in the OS default viewer.

### Builder dispatch (server-side)

`ReportService._render_and_save` picks one of three PDF builders:

- `_build_em_pdf_bytes` — when `metadata.report_kind == "error_mitigation"`
  or sections has `error_mitigation` without `quantum_monte_carlo`.
- `_build_qmc_pdf_bytes` — when the circuit has cached QAE data and
  the QEM path wasn't requested.
- HTML→PDF fallback — generic reports.

## 5. Workflow

1. Open **Reports**. List of existing reports loads automatically
   (`autoLoadScreen` → `ReportsVm.loadReportsList`).
2. **Generate**: type a title, pick format (PDF / HTML / JSON), edit
   sections (default `'all'`), click **Generate**. Spinner shows
   *"Generating report..."* then *"Downloading PDF report..."*.
   Save dialog appears; the file is saved + opened.
3. **Open**: pick a row in the list → click **▶ Open** →
   poll-and-download → save dialog → open.
4. **Distribution Actions**:
   - **↓ PDF** — alias for Open on the current selection.
   - **✉ Email** — `inputdlg` for recipient → POST
     `/api/reports/{id}/share` → "Report shared with X" status.
   - **⎙ Print** — alias for Open; user prints from the OS viewer.
5. **Workflow Complete**:
   - **Detailed Analysis** — bridges to that screen.
   - **Restart Pipeline** — calls Settings VM's `onRestartPipeline`.

## 6. Data flow

```
Tab open:
   GET /api/reports                                 (list, newest first)

Generate:
   POST /api/reports/generate (or /api/projects/{id}/reports)
        body = { title, report_type, format,
                 sections: [...], circuit_id?, prediction_id?,
                 job_record_id?, metadata? }
        → { report_id, status:"ready", message }

   poll GET /api/reports/{id}
        → { report_id, title, format, status, sections,
            created_at, ... }

   stream GET /api/reports/{id}/download
        → binary FileResponse (PDF / HTML / JSON)

Distribute:
   POST /api/reports/{id}/share
        body = { email }
        → { ok: true, message? }
```

## 7. Business logic

- **List ItemsData = report_id** — the GeneratedReportList stores
  report ids in `ItemsData` so selection drives Open / Email / Print
  directly. Filenames in `Items` are display-only.
- **Format dropdown** is restricted to backend-supported `pdf` /
  `html` / `json` — picking unsupported formats silently fell back to
  PDF in the legacy code, which was misleading.
- **Streaming** uses `downloadReportFile` (websave-based) not
  `downloadReport` (webread-based). The latter was the original bug:
  webread parses bytes as JSON, then `JsonHelper.pick` fails silently.
- **Auto-list-load** on tab open via NavigationManager's `Reports`
  case in `autoLoadScreen`.
- **Polling** is defensive — the backend currently returns
  `status: "ready"` synchronously on POST, but the polling loop
  handles future async builders.
- **Auth + project context** — required.

## 8. Reference

- Screen: `src/presentation/screens/ReportsScreen.m`
- ViewModel: `src/presentation/viewmodels/ReportsViewModel.m`
  (`loadReportsList`, `onGenerateReport`, `onOpenReport`,
   `onDownloadPdf`, `onShareEmail`, `onPrintReport`,
   `dispatchDownload`, `pollAndDownload`)
- Service: `src/domain/services/ReportService.m`
- Backend router: `qdash/api/routers/reports.py`
- Backend PDF builders: `qdash/api/services/report_service.py`
