# Phase 3.2 — MATLAB Adapter Search Path Fix

Fixed `QTAUWorkbenchLauncher.m` so that `src/domain/adapters` is added to the MATLAB search path.

This resolves:

```text
Unable to resolve the name 'MatlabCircuitAdapter.compatibility'.
```

Validation commands:

```matlab
which MatlabCircuitAdapter -all
methods MatlabCircuitAdapter
report = MatlabCircuitAdapter.compatibility("OPENQASM 3; qubit[2] q;")
```
