# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

QDash Workbench is a **MATLAB R2025b** desktop application (App Designer) for managing quantum circuit experiments through a FastAPI backend (QTAU Connector). It provides a 13-tab UI for circuit upload, analysis, backend selection, benchmarking, predictions, job monitoring, and reporting.

## Commands

```matlab
% Launch the app
run('QTAUWorkbenchLauncher.m')
% Or via MATLAB Project Manager:
matlab.project.openProject('sqkcloud-qdash-workbench.prj')

% Run all tests
runtests('tests')

% Run a single test file
runtests('tests/test_AppConfig')

% Reload externalized config without restarting
AppConfig.reload(); Labels.reload();
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
- Button styling uses `styleBtn(button, type)` with types `'primary'`, `'secondary'`, `'ghost'`, `'danger'`
- Path resolution uses `fullfile()` throughout (OS-agnostic)
- No hardcoded strings in UI — all text comes from `Labels.get()`

## Required MCP Tool Workflow

Every request that involves analyzing, debugging, or modifying code **must** use these MCP tools:

1. **Sequential Thinking** (`mcp__sequential-thinking__sequentialthinking`) — Start here. Break down the problem, plan analysis steps, and reason through the solution before writing code.
2. **Context7** (`mcp__context7__resolve-library-id` → `mcp__context7__query-docs`) — Look up current documentation for any library, framework, or API involved in the task. Always resolve the library ID first, then query docs.
3. **Serena** — Use via SuperClaude skills (`/sc:analyze`, `/sc:reflect`, `/sc:load`) for project-aware deep code analysis, validation, and reflection.

This is not optional. Use all three even for seemingly simple tasks.

## Note on README

The `README.md` project structure section reflects the pre-refactor layout (flat `src/` with `tabs/`, `utils/`). The actual current structure uses `presentation/`, `domain/`, `infrastructure/` layers as described above.
