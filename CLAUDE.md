# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

QDash Workbench is a **MATLAB R2025b** desktop application (App Designer) for managing quantum circuit experiments through a FastAPI backend (QTAU Connector). It provides a 13-tab UI for circuit upload, analysis, backend selection, benchmarking, predictions, job monitoring, and reporting.

## Commands

```matlab
% Launch the app
run('QTAUWorkbenchLauncher.m')
% Or via MATLAB Project Manager:
matlab.project.openProject('sqk-qtau-matlab.prj')

% Run all tests
runtests('tests')

% Run a single test file
runtests('tests/test_AppConfig')

% Reload externalized config without restarting
AppConfig.reload(); Labels.reload();

% Seed demo data into the backend (all screens)
run('scripts/seed_all.m')
% Or seed a single screen's data
run('scripts/seed_projects.m')
```

There is no build step, linter, or CI pipeline. MATLAB interprets `.m` files directly.

## Architecture

Three-layer clean architecture under `src/`:

```
src/
├── presentation/
│   ├── app/QTAUWorkbenchApp.m    ← Main app class (UI chrome, navigation, service wiring)
│   ├── screens/                  ← 13 screen builder functions (pure UI layout)
│   └── viewmodels/               ← 13 ViewModel classes (callbacks, event logic)
├── domain/
│   ├── models/AppState.m         ← Session-scoped mutable state (auth token, project ID, etc.)
│   └── services/                 ← 7 service classes (CircuitService, JobService, etc.)
└── infrastructure/
    ├── http/FastAPIClient.m      ← HTTP gateway (webread/webwrite, Bearer auth, multipart upload)
    └── config/                   ← Static utilities (AppConfig, Labels, Logger, JsonHelper)
```

**Data flow:** Screen → ViewModel → Service → FastAPIClient → HTTP

- **Screens** are functions that build UI into a provided container. They return no object.
- **ViewModels** are classes that own callbacks; they call services and update UI.
- **Services** receive `FastAPIClient` via constructor (dependency injection). They have no UI dependencies.
- **AppState** is instantiated once by `QTAUWorkbenchApp` and shared across ViewModels for the session lifetime.
- **Static utilities** (`AppConfig`, `Labels`, `Logger`, `JsonHelper`) use static methods with cached state; call `.reload()` to refresh.

## Navigation and Screen Switching

`QTAUWorkbenchApp` manages screens via a `SectionPanels` struct (keyed by screen name). Each screen calls `app.createSectionPage('ScreenName')` during `buildUI()` to register a hidden panel, then populates it with UI controls. Navigation is handled by `onSelectSection(key)`, which hides all panels and shows the matching one. The `autoLoadScreen(key)` method triggers ViewModel data-fetching when a screen becomes visible (e.g., Dashboard auto-refreshes on enter).

## Adding a New Screen

Adding a screen requires changes in four places:

1. **Screen function** — Create `src/presentation/screens/FooScreen.m`. Call `app.createSectionPage('Foo')` to get the container, then build UI into it. Wire button callbacks to `app.FooVm.onSomething()`.
2. **ViewModel class** — Create `src/presentation/viewmodels/FooViewModel.m`. Constructor takes `app`. Methods call services and update `app.*` UI properties.
3. **QTAUWorkbenchApp.m** — Add UI property declarations for the screen's controls. Add `FooVm` property. Instantiate `FooVm = FooViewModel(app)` in the constructor. Call `FooScreen(app)` in `buildUI()`. Add a case to `autoLoadScreen()` if the screen should auto-fetch data on navigation.
4. **Nav list** — Add the screen name to `Labels.get('nav_*')` in `resources/labels.properties` and to the nav button/list builder in `buildUI()`.

## Configuration

All runtime config is externalized in `resources/` (key=value `.properties` files):

- `resources/app.properties` — API base URL, login path, timeout, app metadata
- `resources/labels.properties` — 600+ UI text strings (enables text changes without code edits)

Access patterns: `AppConfig.get(key, default)`, `AppConfig.getDouble(key, default)`, `Labels.get(key, default)`.

## Backend API

FastAPIClient talks to a FastAPI server (default `http://34.42.87.190:5715`). Auth is username/password POST → Bearer token. Full endpoint contract is in `docs/fastapi_contract.md` and `docs/openapi.json`.

## Naming Conventions

- **Classes**: PascalCase (`AppState`, `FastAPIClient`)
- **Methods/properties**: camelCase (`onLogin`, `authToken`)
- **Config/label keys**: snake_case (`base_url`, `nav_welcome`)
- **Screen files**: PascalCase matching tab name (`WelcomeScreen.m`)
- **ViewModel files**: PascalCase with `ViewModel` suffix (`WelcomeViewModel.m`)

## Key Patterns

- Errors propagate as `MException` from HTTP → Service → ViewModel, which displays via `uialert()`
- Logger output is structured: `[HH:MM:SS.FFF] LEVEL [Category] Message`
- Button styling uses `app.styleBtn(button, type)` with types `'primary'`, `'secondary'`, `'success'`, `'danger'`, `'ghost'`
- Path resolution uses `fullfile()` throughout (OS-agnostic)
- No hardcoded strings in UI — all text comes from `Labels.get()`
- `JsonHelper.pick(data, {'path1', 'path2'})` walks dotted paths with fallback chains for resilient API field mapping
- File upload in `FastAPIClient` tries `matlab.net.http` multipart first, falls back to system `curl`

## Required MCP Tool Workflow

Every request that involves analyzing, debugging, or modifying code **must** use these MCP tools:

1. **Sequential Thinking** (`mcp__sequential-thinking__sequentialthinking`) — Start here. Break down the problem, plan analysis steps, and reason through the solution before writing code.
2. **Context7** (`mcp__context7__resolve-library-id` → `mcp__context7__query-docs`) — Look up current documentation for any library, framework, or API involved in the task. Always resolve the library ID first, then query docs.
3. **Serena** — Use via SuperClaude skills (`/sc:analyze`, `/sc:reflect`, `/sc:load`) for project-aware deep code analysis, validation, and reflection.

This is not optional. Use all three even for seemingly simple tasks.
