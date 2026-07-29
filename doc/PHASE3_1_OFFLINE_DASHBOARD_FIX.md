# Phase 3.1 — Offline Dashboard Navigation Fix

## Symptom

After opening a template, selecting **Dashboard** displayed a loading overlay that did not close. Because the overlay covered the application, the user could not return to **Projects** and select **Run Offline Demo**.

## Root cause

`NavigationManager.autoLoadScreen` always treated the Dashboard refresh as asynchronous. In offline or no-project state, however, `DashboardViewModel.onRefreshDashboard` completed synchronously from local session state. The navigation layer therefore waited for an asynchronous callback that would never run and leave the overlay visible.

## Fix

- Show the Dashboard loading overlay only when authenticated and an active project exists.
- Run the offline Dashboard refresh synchronously without setting `asyncStarted`.
- Explicitly hide any residual overlay after local fallback rendering.
- Do not start the 30-second backend refresh timer in offline mode.
- Replace the project dropdown's `loading projects` placeholder with `Offline MATLAB Workspace`.
- Mark Dashboard as an offline-capable screen so the authentication overlay does not cover it.

## Acceptance test

1. Start QTAU without the Python/FastAPI backend.
2. Open a Bell or GHZ template.
3. Select Dashboard.
4. Confirm the Dashboard appears immediately with `Offline MATLAB Workspace`.
5. Select Projects.
6. Select Run Offline Demo.
7. Confirm `qtauOfflineCircuit`, `qtauOfflineResult`, and `qtauOfflineResultTable` appear in the MATLAB Workspace.
