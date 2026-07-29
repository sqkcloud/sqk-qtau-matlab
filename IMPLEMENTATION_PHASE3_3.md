# Phase 3.3 — Offline MATLAB Simulation Resolution Fix

- Removed the runtime dependency on `MatlabCircuitAdapter.compatibility` from the Composer MATLAB simulation path.
- `SimulationService` now converts `CircuitModel` directly to MATLAB `quantumCircuit` using OpenQASM string/file fallbacks.
- Launcher now adds the complete `src` tree with `genpath`, always refreshes MATLAB path/toolbox caches, and verifies required classes before opening the UI.
