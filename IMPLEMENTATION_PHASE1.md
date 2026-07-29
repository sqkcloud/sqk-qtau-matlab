# QTAU MATLAB Integration — Phase 1 Implementation

## Implemented

1. Offline entry points on Welcome screen
   - Open Templates
   - Import Workspace
   - Open MATLAB workflow example
   - Connect to QTAU only when remote features are needed
2. MATLAB Workspace import/export service
3. Optional MATLAB `quantumCircuit` adapter
4. MATLAB built-in simulation provider with QTAU local fallback
5. Template discovery from Welcome screen
6. Navigation labels reorganized as `Plan & Run` and `Planner Advanced`
7. MATLAB-centered executable example and workflow documentation

## New classes

- `MatlabWorkspaceService`
- `MatlabQuantumService`
- `SimulationService`
- `MatlabCircuitAdapter`
- `MatlabResultAdapter`

## Composer additions

- Import Workspace
- Export Workspace as `CircuitModel` or `quantumCircuit`
- MATLAB Simulate and export result as `qtauSimulationResult`

## Compatibility behavior

The MATLAB Quantum Computing Support Package is optional. The toolbox detects
`quantumCircuit`, `generateQASM`, and `simulate` at runtime. Existing QTAU local
features continue to work without the support package.

## Remaining Phase 2 work

- Full single-screen consolidation of Prediction and Run Planner content
- Results toolbar buttons for table/struct/MAT export of live server results
- Dedicated offline demo project and sample result datasets
- Broader OpenQASM 3 gate mapping and adapter compatibility diagnostics
- Automated validation in MATLAB R2024b/R2025a with the support package installed
