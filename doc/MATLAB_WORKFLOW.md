# MATLAB-Centered QTAU Workflow

QTAU Workbench is an orchestration and execution-planning layer for MATLAB quantum and scientific workflows.

## Offline workflow

1. Create or select a circuit template.
2. Import a `quantumCircuit` or `CircuitModel` from the MATLAB Workspace.
3. Simulate locally with MATLAB Quantum Computing or QTAU Lightweight Local.
4. Export circuits and results as Workspace variables, `table`, `struct`, or MAT-file.

## Connected workflow

MATLAB preparation → QTAU prediction → backend-aware planning → IBM Runtime execution → MATLAB analysis and reporting.

Run `samples/QTAU_MATLAB_Workflow.m` for an end-to-end local example.
