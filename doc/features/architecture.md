# Cross-cutting Concerns

This document describes patterns and infrastructure shared by every feature.
Per-feature documents reference back here rather than re-describing these
patterns.

## 1. Three-layer clean architecture

```
Presentation                    Domain                     Infrastructure
──────────────                  ──────                     ──────────────
Screen function   →  app.*Vm  →  Service  →  FastAPIClient → HTTP (FastAPI)
(builds UI)         (callbacks  (HTTP-only,  (webread /
                     and event   no UI deps) webwrite +
                     logic)                  matlab.net.http
                                             multipart)
```

- **Screen** functions live in `src/presentation/screens/` and only build
  UI into a container provided by `app.createSectionPage(name)`.
- **ViewModel** classes live in `src/presentation/viewmodels/` and own
  every callback wired by the Screen. Each VM holds a reference to the
  app and reads/writes UI properties directly.
- **Service** classes live in `src/domain/services/` and wrap HTTP
  endpoints. Each takes a `FastAPIClient` instance via DI
  (`ServiceContainer.m`).
- **AppState** (`src/domain/models/AppState.m`) holds session-scoped
  mutable state — auth token, project id, selections — shared across VMs.
- **Static utilities** (`AppConfig`, `Labels`, `Logger`, `JsonHelper`)
  use static methods with cached state. Call `.reload()` to refresh.

## 2. Async dispatch (`AsyncRunner` + `runAsyncWithLoading`)

Every long-running HTTP call goes through `AsyncRunner.run(work, onOk, onErr)`
which dispatches `work` to MATLAB's `backgroundPool` via `parfeval`, and
runs `onOk(data)` or `onErr(ME)` back on the main UI thread.

The Phase 6.4 standard pattern is `app.runAsyncWithLoading(msg, work, onOk, onErr)`
(`QTAUWorkbenchApp.m:646`) which wraps an `AsyncRunner.run` call with
`app.showLoading` + auto-hide on both ok and err paths. Use this for
any operation that should block the UI with a spinner.

## 3. Loading overlay (`OverlayManager`)

`OverlayManager.showLoading(app, msg, showTimer)` and `hideLoading(app)`
manage a single `uihtml` ActivityOverlay component per host figure.
Conventions (`OverlayManager.m:9–51`):

- **Message text** — `Labels.get('loading_<scope>_<action>', '<English ...>')`
  with **3 ASCII dots** (Unicode ellipsis defeats idempotency dedup).
- **Idempotency** — re-showing with the same message is a no-op (no
  CEF flicker).
- **Modal-aware parenting** — auto-detects `app.QmcDialog` and
  `app.EmDialog` and re-parents the overlay onto whichever modal is
  open (`OverlayManager.m:67–90`).
- **Safety timer** — `NavigationManager.armNavOverlayTimer` auto-dismisses
  the overlay after 20 s if a VM forgets to hide it.

## 4. Authentication and project context

- **Login** — `WelcomeScreen` collects username/password, hands to
  `AuthService.login` which posts to `/api/auth/login` and returns
  `{access_token, token_type:"bearer", default_project}`.
- **Token storage** — `app.State.authToken`. Every Service method
  takes the token as its last argument and `FastAPIClient` adds the
  `Authorization: Bearer <token>` header.
- **Project context** — `app.State.currentProjectId`. The
  `FastAPIClient.authHeaders` helper additionally sets `X-Project-Id`
  so project-scoped endpoints know which project context to apply.
- **`hasProject` / `hasCircuit` / `isAuthenticated`** — guards used by
  every VM before posting to the API. UI buttons short-circuit with
  a `uialert` when the precondition fails.

## 5. Error propagation

```
HTTP error  →  FastAPIClient throws MException
            →  Service rethrows
            →  AsyncRunner forwards to onErr(ME)
            →  ViewModel hides loading + uialert(parent, ME.message)
```

`OverlayManager.showError(app, context, ME)` is the canonical wrapper
that:

- Strips `http://host:port` from `webservices` errors so the deployed
  server's IP doesn't leak to the popup
  (`OverlayManager.sanitizeErrorMessage`).
- Logs the full URL into `app.EventLog` for triage.
- Pops a `uialert` with title "Error".

## 6. Async-job pattern (poll until terminal)

For backend operations that take longer than a single HTTP request can
hold open (IBM Runtime QPU queues, Quantum Monte Carlo, Circuit Cutting
batches), the contract is:

1. **Submit** — `POST /api/<...>` returns `HTTP 202 {job_id, status: "queued"}`.
2. **Poll** — `GET /api/<...>/{job_id}` every N seconds until
   `status ∈ {ready, completed, success, done}`.
3. **Cancel** — `DELETE /api/<...>/{job_id}` flips state to `cancelled`.
4. **Result** — when terminal, the poll envelope embeds the full
   result (QMC), or there's a separate `/result` endpoint (Cutting).

The MATLAB-side polling is implemented with a MATLAB `timer` (e.g.
`AnalysisViewModel.startQaePoll` for QMC) or with an inline loop inside
the background-thread work function (e.g. `pollAndDownload` in
`ReportsViewModel`).

## 7. List endpoints + pagination

Pagination uses `skip` and `limit` query params with `limit ≤ 100`.
Responses are envelopes with the items under a named key:

```json
{ "circuits": [...], "skip": 0, "limit": 20, "total": 113 }
{ "jobs":     [...], "skip": 0, "limit": 50 }
{ "reports":  [...], "skip": 0, "limit": 20 }
```

`JsonHelper.extractList(data, '<key>')` is the canonical accessor.
`JsonHelper.asList(data)` falls back when the response is a bare array.

## 8. Logging convention

`Logger.<level>('<Category>', '<message>', args...)` produces
`[HH:MM:SS.fff] LEVEL    [Category] Message`. The four levels are
`debug`, `info`, `warn`, `error`. `Logger.http` is a category-of-its-own
emitted by `FastAPIClient` for every request and response status.

## 9. Theming

`Theme.setActive(name)` swaps the active theme; `Theme.applyFigureMode`
cascades the base color scheme. Every renderer reads `Theme.COLOR_*`
constants and `styleBtn(b, type)` for primary / secondary / danger /
ghost buttons.

## 10. Naming conventions

- **Classes**: `PascalCase` (`AppState`, `FastAPIClient`).
- **Methods/properties**: `camelCase` (`onLogin`, `authToken`).
- **Config / label keys**: `snake_case` (`base_url`, `nav_welcome`).
- **Screen files**: `PascalCase` matching tab name (`WelcomeScreen.m`).
- **ViewModel files**: `PascalCase` + `ViewModel` suffix.
- **Service files**: `PascalCase` + `Service` suffix.
