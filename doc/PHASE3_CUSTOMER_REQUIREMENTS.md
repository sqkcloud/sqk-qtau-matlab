# Phase 3 — Customer Requirement Completion

## Runtime architecture

MATLAB-native path:
`Workspace / quantumCircuit -> MATLAB local simulate -> MATLAB tables and plots`

Remote path:
`MATLAB circuit/data -> QTAU FastAPI orchestration -> prediction / planning / IBM Runtime -> MATLAB analysis`

The Python backend remains the remote orchestration layer. It is not used for the MATLAB local simulator.

## Completed in Phase 3

- Authentication-free startup and offline navigation.
- Runtime capability probing for MATLAB quantum APIs.
- Explicit OpenQASM compatibility reporting.
- MATLAB simulator provider plus QTAU local fallback.
- Workspace/table/MAT export inherited from Phase 1/2.
- Unified Plan & Run entry, with advanced planner as the second stage.
- Three MATLAB-centered domain examples: materials/VQE, financial/QAE, and QMEDIC imaging.
- Unit tests for provider routing and compatibility checks.

## Required release validation

Run `runtests('tests')` and all three sample workflows on each supported MATLAB release. Hardware/IBM Runtime operations still require a connected QTAU server and valid credentials.
