# QTAU MATLAB Phase 2: Plan & Run and MATLAB Result Handoff

## User flow

1. Build or import a circuit in MATLAB/Composer.
2. Open **Plan & Run** for a quick backend prediction.
3. Export the prediction payload to `qtauPredictionResult`, or save a MAT-file.
4. Open **Advanced Planner** from the Plan & Run action bar to compare backend × mitigation × shots combinations.
5. Export `qtauRunPlanTable` and `qtauRecommendedRun` to MATLAB Workspace.

## Offline validation

Run `samples/QTAU_Offline_Demo.m` without authentication.

## Live Script

Run `scripts/create_qtau_live_script.m` from MATLAB to generate `samples/QTAU_MATLAB_Workflow.mlx`. The binary `.mlx` is generated inside MATLAB because it is release-specific.
