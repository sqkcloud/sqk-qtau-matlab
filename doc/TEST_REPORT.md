# QTAU Connector Workbench — Test Report

**Generated:** 2026-05-23 18:21:27
**Runner:** `scripts/run_tests.m` (MATLAB Unit Test Framework)
**MATLAB:** 25.2.0.3177638 (R2025b) Update 5
**Elapsed:** 247.8 s

## Summary

| Metric | Value |
|---|---:|
| Total tests | 456 |
| Passed | 456 |
| Failed | 0 |
| Incomplete | 0 |
| Pass rate | 100.0% |

## Result

**ALL TESTS PASSED.**

## Per-File Breakdown

| File | Tests | Passed | Failed | Total Time (s) |
|---|---:|---:|---:|---:|
| `test_AnalysisViewModel` | 5 | 5 | 0 | 3.954 |
| `test_AppConfig` | 8 | 8 | 0 | 0.145 |
| `test_AppState` | 26 | 26 | 0 | 0.146 |
| `test_AsyncRunner` | 8 | 8 | 0 | 8.383 |
| `test_AuthService` | 7 | 7 | 0 | 0.112 |
| `test_BackendService` | 12 | 12 | 0 | 0.220 |
| `test_BackgroundTaskManager` | 9 | 9 | 0 | 0.121 |
| `test_BenchmarkDashboardViewModel` | 3 | 3 | 0 | 0.070 |
| `test_BenchmarkService` | 10 | 10 | 0 | 0.166 |
| `test_BundleService` | 8 | 8 | 0 | 6.320 |
| `test_CircuitCuttingViewModel` | 12 | 12 | 0 | 0.121 |
| `test_CircuitModel` | 13 | 13 | 0 | 0.147 |
| `test_CircuitModel_export` | 13 | 13 | 0 | 0.074 |
| `test_CircuitService` | 13 | 13 | 0 | 0.124 |
| `test_CuttingService` | 10 | 10 | 0 | 0.080 |
| `test_FastAPIClient` | 15 | 15 | 0 | 0.124 |
| `test_JobService` | 19 | 19 | 0 | 0.111 |
| `test_JsonHelper` | 50 | 50 | 0 | 0.154 |
| `test_Labels` | 7 | 7 | 0 | 0.079 |
| `test_Logger` | 25 | 25 | 0 | 0.087 |
| `test_MitigationCompareViewModel` | 16 | 16 | 0 | 0.075 |
| `test_MitigationService` | 6 | 6 | 0 | 0.065 |
| `test_PredictionService` | 12 | 12 | 0 | 0.111 |
| `test_ProjectService` | 19 | 19 | 0 | 0.125 |
| `test_QecEngineService` | 17 | 17 | 0 | 221.105 |
| `test_QmcService` | 8 | 8 | 0 | 0.129 |
| `test_ReportService` | 11 | 11 | 0 | 0.123 |
| `test_ResourceEstimatorService` | 15 | 15 | 0 | 0.115 |
| `test_RunPlannerService` | 13 | 13 | 0 | 0.134 |
| `test_ServiceContainer` | 18 | 18 | 0 | 0.295 |
| `test_SettingsService` | 10 | 10 | 0 | 0.115 |
| `test_StatevectorSimulator` | 7 | 7 | 0 | 0.158 |
| `test_TemplateRegistry` | 8 | 8 | 0 | 0.379 |
| `test_Theme` | 23 | 23 | 0 | 0.065 |

## Per-Test Detail

| # | Test | Status | Duration (s) | Notes |
|---:|---|:---:|---:|---|
| 1 | `test_AnalysisViewModel/testRenderComplexityLandscapePopulatesInfoLabel` | PASS | 2.419 | verifies render complexity landscape populates info label |
| 2 | `test_AnalysisViewModel/testRenderPaintsAxesChildren` | PASS | 0.325 | verifies render paints axes children |
| 3 | `test_AnalysisViewModel/testRegimeClassification` | PASS | 0.599 | verifies regime classification |
| 4 | `test_AnalysisViewModel/testFidelityEstimateReactsToTwoQubitGates` | PASS | 0.379 | verifies fidelity estimate reacts to two qubit gates |
| 5 | `test_AnalysisViewModel/testRenderFallsBackWhenDataIsEmpty` | PASS | 0.233 | verifies render falls back when data is empty |
| 6 | `test_AppConfig/test_base_url_key_is_known` | PASS | 0.089 | verifies base url key is known |
| 7 | `test_AppConfig/test_base_url_when_set_starts_with_http` | PASS | 0.001 | verifies base url when set starts with http |
| 8 | `test_AppConfig/test_http_timeout_is_positive` | PASS | 0.002 | verifies http timeout is positive |
| 9 | `test_AppConfig/test_app_name_is_present` | PASS | 0.006 | verifies app name is present |
| 10 | `test_AppConfig/test_login_path_is_present` | PASS | 0.006 | verifies login path is present |
| 11 | `test_AppConfig/test_missing_key_returns_default` | PASS | 0.003 | verifies missing key returns default |
| 12 | `test_AppConfig/test_missing_key_getDouble_returns_default` | PASS | 0.007 | verifies missing key get double returns default |
| 13 | `test_AppConfig/test_reload_does_not_crash` | PASS | 0.031 | verifies reload does not crash |
| 14 | `test_AppState/testBaseUrlLoadedFromConfig` | PASS | 0.058 | verifies base url loaded from config |
| 15 | `test_AppState/testAuthTokenDefaultEmpty` | PASS | 0.004 | verifies auth token default empty |
| 16 | `test_AppState/testTokenTypeDefaultBearer` | PASS | 0.004 | verifies token type default bearer |
| 17 | `test_AppState/testDefaultProjectIdEmpty` | PASS | 0.004 | verifies default project id empty |
| 18 | `test_AppState/testDefaultCircuitIdEmpty` | PASS | 0.004 | verifies default circuit id empty |
| 19 | `test_AppState/testDefaultJobIdEmpty` | PASS | 0.004 | verifies default job id empty |
| 20 | `test_AppState/testDefaultPinnedJobIdEmpty` | PASS | 0.004 | verifies default pinned job id empty |
| 21 | `test_AppState/testDefaultShots` | PASS | 0.003 | verifies default shots |
| 22 | `test_AppState/testDefaultOptimization` | PASS | 0.003 | verifies default optimization |
| 23 | `test_AppState/testDefaultTimeout` | PASS | 0.004 | verifies default timeout |
| 24 | `test_AppState/testBenchmarkShotsDefault` | PASS | 0.003 | verifies benchmark shots default |
| 25 | `test_AppState/testBenchmarkOptLevelDefault` | PASS | 0.003 | verifies benchmark opt level default |
| 26 | `test_AppState/testNotAuthenticatedByDefault` | PASS | 0.005 | verifies not authenticated by default |
| 27 | `test_AppState/testIsAuthenticatedAfterSettingToken` | PASS | 0.001 | verifies is authenticated after setting token |
| 28 | `test_AppState/testNotAuthenticatedWithWhitespaceToken` | PASS | 0.001 | verifies not authenticated with whitespace token |
| 29 | `test_AppState/testNoProjectByDefault` | PASS | 0.001 | verifies no project by default |
| 30 | `test_AppState/testHasProjectAfterSetting` | PASS | 0.001 | verifies has project after setting |
| 31 | `test_AppState/testNoCircuitByDefault` | PASS | 0.001 | verifies no circuit by default |
| 32 | `test_AppState/testHasCircuitAfterSetting` | PASS | 0.001 | verifies has circuit after setting |
| 33 | `test_AppState/testNoJobByDefault` | PASS | 0.001 | verifies no job by default |
| 34 | `test_AppState/testHasJobAfterSetting` | PASS | 0.001 | verifies has job after setting |
| 35 | `test_AppState/testBearerHeaderFormat` | PASS | 0.003 | verifies bearer header format |
| 36 | `test_AppState/testBearerHeaderEmptyToken` | PASS | 0.002 | verifies bearer header empty token |
| 37 | `test_AppState/testResetPipelineClearsIdsButKeepsAuth` | PASS | 0.026 | verifies reset pipeline clears ids but keeps auth |
| 38 | `test_AppState/testAppStateIsHandleClass` | PASS | 0.001 | verifies app state is handle class |
| 39 | `test_AppState/testSharedReference` | PASS | 0.003 | verifies shared reference |
| 40 | `test_AsyncRunner/testRunReturnsScalarResult` | PASS | 1.213 | verifies run returns scalar result |
| 41 | `test_AsyncRunner/testRunReturnsStringResult` | PASS | 1.019 | verifies run returns string result |
| 42 | `test_AsyncRunner/testRunReturnsStructResult` | PASS | 1.021 | verifies run returns struct result |
| 43 | `test_AsyncRunner/testWorkFcnResultPassedToOnDone` | PASS | 1.028 | verifies work fcn result passed to on done |
| 44 | `test_AsyncRunner/testErrorCallsOnError` | PASS | 1.039 | verifies error calls on error |
| 45 | `test_AsyncRunner/testErrorWithoutOnErrorRethrows` | PASS | 1.012 | verifies error without on error rethrows |
| 46 | `test_AsyncRunner/testOnDoneNotCalledOnError` | PASS | 1.027 | verifies on done not called on error |
| 47 | `test_AsyncRunner/testOnErrorIsOptional` | PASS | 1.025 | verifies on error is optional |
| 48 | `test_AuthService/testConstructorAcceptsClient` | PASS | 0.070 | verifies constructor accepts client |
| 49 | `test_AuthService/testServiceIsHandle` | PASS | 0.003 | verifies service is handle |
| 50 | `test_AuthService/testLoginDelegatesToClient` | PASS | 0.012 | verifies login delegates to client |
| 51 | `test_AuthService/testLoginIncrementsCallCount` | PASS | 0.007 | verifies login increments call count |
| 52 | `test_AuthService/testLogoutDelegatesToClient` | PASS | 0.009 | verifies logout delegates to client |
| 53 | `test_AuthService/testGetMeDelegatesToClient` | PASS | 0.006 | verifies get me delegates to client |
| 54 | `test_AuthService/testListProjectsDelegatesToClient` | PASS | 0.004 | verifies list projects delegates to client |
| 55 | `test_BackendService/testConstructorAcceptsClient` | PASS | 0.086 | verifies constructor accepts client |
| 56 | `test_BackendService/testServiceIsHandle` | PASS | 0.002 | verifies service is handle |
| 57 | `test_BackendService/testListBackendsUsesGetAuth` | PASS | 0.008 | verifies list backends uses get auth |
| 58 | `test_BackendService/testGetBackendIncludesName` | PASS | 0.017 | verifies get backend includes name |
| 59 | `test_BackendService/testGetCalibrationUsesCorrectEndpoint` | PASS | 0.004 | verifies get calibration uses correct endpoint |
| 60 | `test_BackendService/testGetTopologyUsesCorrectEndpoint` | PASS | 0.005 | verifies get topology uses correct endpoint |
| 61 | `test_BackendService/testCompareBackendsPosts` | PASS | 0.007 | verifies compare backends posts |
| 62 | `test_BackendService/testCompareBackendsPayloadContainsCircuitId` | PASS | 0.006 | verifies compare backends payload contains circuit id |
| 63 | `test_BackendService/testSaveSelectionPosts` | PASS | 0.010 | verifies save selection posts |
| 64 | `test_BackendService/testSaveSelectionPayload` | PASS | 0.008 | verifies save selection payload |
| 65 | `test_BackendService/testGetSelectionGets` | PASS | 0.007 | verifies get selection gets |
| 66 | `test_BackendService/testTokenIsForwarded` | PASS | 0.059 | verifies token is forwarded |
| 67 | `test_BackgroundTaskManager/test_register_assigns_sequential_ids` | PASS | 0.059 | verifies register assigns sequential ids |
| 68 | `test_BackgroundTaskManager/test_register_defaults_status_to_queued` | PASS | 0.004 | verifies register defaults status to queued |
| 69 | `test_BackgroundTaskManager/test_update_patches_fields` | PASS | 0.011 | verifies update patches fields |
| 70 | `test_BackgroundTaskManager/test_complete_marks_completed_and_fires_callback` | PASS | 0.015 | verifies complete marks completed and fires callback |
| 71 | `test_BackgroundTaskManager/test_fail_stores_exception` | PASS | 0.007 | verifies fail stores exception |
| 72 | `test_BackgroundTaskManager/test_cancel_invokes_onCancel_and_marks_cancelled` | PASS | 0.007 | verifies cancel invokes on cancel and marks cancelled |
| 73 | `test_BackgroundTaskManager/test_cancel_is_idempotent_on_terminal_tasks` | PASS | 0.004 | verifies cancel is idempotent on terminal tasks |
| 74 | `test_BackgroundTaskManager/test_clearTerminal_evicts_only_terminal_tasks` | PASS | 0.010 | verifies clear terminal evicts only terminal tasks |
| 75 | `test_BackgroundTaskManager/test_countActive_counts_only_queued_and_running` | PASS | 0.005 | verifies count active counts only queued and running |
| 76 | `test_BenchmarkDashboardViewModel/testPickHandlesMissingAndPresentNumerics` | PASS | 0.060 | verifies pick handles missing and present numerics |
| 77 | `test_BenchmarkDashboardViewModel/testPickSourceStringFallback` | PASS | 0.005 | verifies pick source string fallback |
| 78 | `test_BenchmarkDashboardViewModel/testFormatKpiReturnsDashForEmpty` | PASS | 0.005 | verifies format kpi returns dash for empty |
| 79 | `test_BenchmarkService/testConstructorSetsClient` | PASS | 0.083 | verifies constructor sets client |
| 80 | `test_BenchmarkService/testServiceIsHandle` | PASS | 0.003 | verifies service is handle |
| 81 | `test_BenchmarkService/testGetVolumetricDataUsesGetAuth` | PASS | 0.008 | verifies get volumetric data uses get auth |
| 82 | `test_BenchmarkService/testGetSystemMetricsUsesBackendName` | PASS | 0.011 | verifies get system metrics uses backend name |
| 83 | `test_BenchmarkService/testGetBackendScorecardUsesProjectAndBackend` | PASS | 0.016 | verifies get backend scorecard uses project and backend |
| 84 | `test_BenchmarkService/testGetBenchmarkRegressionUsesCorrectEndpoint` | PASS | 0.006 | verifies get benchmark regression uses correct endpoint |
| 85 | `test_BenchmarkService/testGetCircuitClassificationUsesCircuitId` | PASS | 0.006 | verifies get circuit classification uses circuit id |
| 86 | `test_BenchmarkService/testGetPredictionCalibrationUsesProjectId` | PASS | 0.006 | verifies get prediction calibration uses project id |
| 87 | `test_BenchmarkService/testTokenIsForwarded` | PASS | 0.006 | verifies token is forwarded |
| 88 | `test_BenchmarkService/testReturnValueComesFromStub` | PASS | 0.021 | verifies return value comes from stub |
| 89 | `test_BundleService/test_default_name_starts_with_qtau_bundle` | PASS | 0.073 | verifies default name starts with qtau bundle |
| 90 | `test_BundleService/test_default_name_sanitizes_circuit_name` | PASS | 0.020 | verifies default name sanitizes circuit name |
| 91 | `test_BundleService/test_assemble_writes_zip` | PASS | 6.046 | verifies assemble writes zip |
| 92 | `test_BundleService/test_assemble_contents_include_manifest_and_readme` | PASS | 0.048 | verifies assemble contents include manifest and readme |
| 93 | `test_BundleService/test_assemble_omits_optional_sections_when_absent` | PASS | 0.030 | verifies assemble omits optional sections when absent |
| 94 | `test_BundleService/test_assemble_includes_optional_sections_when_present` | PASS | 0.048 | verifies assemble includes optional sections when present |
| 95 | `test_BundleService/test_assemble_rejects_missing_circuit` | PASS | 0.042 | verifies assemble rejects missing circuit |
| 96 | `test_BundleService/test_assemble_rejects_missing_save_path` | PASS | 0.013 | verifies assemble rejects missing save path |
| 97 | `test_CircuitCuttingViewModel/testFormatOverheadHandlesEmpty` | PASS | 0.052 | verifies format overhead handles empty |
| 98 | `test_CircuitCuttingViewModel/testFormatPerSubHandlesCellAndArray` | PASS | 0.004 | verifies format per sub handles cell and array |
| 99 | `test_CircuitCuttingViewModel/testDefaultModeIsAssisted` | PASS | 0.001 | verifies default mode is assisted |
| 100 | `test_CircuitCuttingViewModel/testParseObservableLinesReturnsEmptyForPlaceholderOnly` | PASS | 0.032 | verifies parse observable lines returns empty for placeholder only |
| 101 | `test_CircuitCuttingViewModel/testParseObservableLinesDropsBlanksAndPlaceholder` | PASS | 0.004 | verifies parse observable lines drops blanks and placeholder |
| 102 | `test_CircuitCuttingViewModel/testParseObservableLinesHandlesStringAndChar` | PASS | 0.006 | verifies parse observable lines handles string and char |
| 103 | `test_CircuitCuttingViewModel/testParseObservableLinesHandlesEmptyInput` | PASS | 0.005 | verifies parse observable lines handles empty input |
| 104 | `test_CircuitCuttingViewModel/testCheckQasmCuttableAllowsTerminalMeasure` | PASS | 0.011 | verifies check qasm cuttable allows terminal measure |
| 105 | `test_CircuitCuttingViewModel/testCheckQasmCuttableFlagsClassicalControl` | PASS | 0.002 | verifies check qasm cuttable flags classical control |
| 106 | `test_CircuitCuttingViewModel/testCheckQasmCuttableFlagsBB84Pattern` | PASS | 0.003 | verifies check qasm cuttable flags bb84pattern |
| 107 | `test_CircuitCuttingViewModel/testCheckQasmCuttableFlagsReset` | PASS | 0.001 | verifies check qasm cuttable flags reset |
| 108 | `test_CircuitCuttingViewModel/testCheckQasmCuttableHandlesEmpty` | PASS | 0.000 | verifies check qasm cuttable handles empty |
| 109 | `test_CircuitModel/test_default_qubit_count` | PASS | 0.042 | verifies default qubit count |
| 110 | `test_CircuitModel/test_clamps_to_max_qubits` | PASS | 0.001 | verifies clamps to max qubits |
| 111 | `test_CircuitModel/test_addGate_h_appends` | PASS | 0.007 | verifies add gate h appends |
| 112 | `test_CircuitModel/test_addGate_rejects_unsupported_kind` | PASS | 0.012 | verifies add gate rejects unsupported kind |
| 113 | `test_CircuitModel/test_addGate_rejects_qubit_out_of_range` | PASS | 0.007 | verifies add gate rejects qubit out of range |
| 114 | `test_CircuitModel/test_setNumQubits_drops_out_of_range` | PASS | 0.006 | verifies set num qubits drops out of range |
| 115 | `test_CircuitModel/test_toQasm_emits_header_and_gates` | PASS | 0.006 | verifies to qasm emits header and gates |
| 116 | `test_CircuitModel/test_toQasm_renders_pi_rotations_symbolically` | PASS | 0.003 | verifies to qasm renders pi rotations symbolically |
| 117 | `test_CircuitModel/test_round_trip_bell` | PASS | 0.018 | verifies round trip bell |
| 118 | `test_CircuitModel/test_round_trip_with_rotation` | PASS | 0.021 | verifies round trip with rotation |
| 119 | `test_CircuitModel/test_fromQasm_rejects_unsupported_statement` | PASS | 0.009 | verifies from qasm rejects unsupported statement |
| 120 | `test_CircuitModel/test_fromQasm_handles_measurements` | PASS | 0.004 | verifies from qasm handles measurements |
| 121 | `test_CircuitModel/test_fromQasm_evals_pi_expressions` | PASS | 0.008 | verifies from qasm evals pi expressions |
| 122 | `test_CircuitModel_export/test_qasm3_uses_qubit_array_decl` | PASS | 0.034 | verifies qasm3 uses qubit array decl |
| 123 | `test_CircuitModel_export/test_qasm3_measure_uses_assignment_form` | PASS | 0.002 | verifies qasm3 measure uses assignment form |
| 124 | `test_CircuitModel_export/test_qiskit_emits_imports_and_constructor` | PASS | 0.004 | verifies qiskit emits imports and constructor |
| 125 | `test_CircuitModel_export/test_qiskit_emits_np_pi_for_rotations` | PASS | 0.002 | verifies qiskit emits np pi for rotations |
| 126 | `test_CircuitModel_export/test_qiskit_emits_measure_and_barrier` | PASS | 0.002 | verifies qiskit emits measure and barrier |
| 127 | `test_CircuitModel_export/test_cirq_emits_line_qubits_and_circuit` | PASS | 0.003 | verifies cirq emits line qubits and circuit |
| 128 | `test_CircuitModel_export/test_cirq_renames_ccx_to_toffoli` | PASS | 0.002 | verifies cirq renames ccx to toffoli |
| 129 | `test_CircuitModel_export/test_cirq_uses_measurement_keys` | PASS | 0.006 | verifies cirq uses measurement keys |
| 130 | `test_CircuitModel_export/test_braket_emits_circuit_constructor` | PASS | 0.004 | verifies braket emits circuit constructor |
| 131 | `test_CircuitModel_export/test_braket_renames_ccx_to_ccnot` | PASS | 0.002 | verifies braket renames ccx to ccnot |
| 132 | `test_CircuitModel_export/test_braket_renames_sdg_tdg` | PASS | 0.002 | verifies braket renames sdg tdg |
| 133 | `test_CircuitModel_export/test_all_emitters_carry_header_comment` | PASS | 0.006 | verifies all emitters carry header comment |
| 134 | `test_CircuitModel_export/test_empty_circuit_still_emits_scaffold` | PASS | 0.005 | verifies empty circuit still emits scaffold |
| 135 | `test_CircuitService/testConstructorAcceptsClient` | PASS | 0.072 | verifies constructor accepts client |
| 136 | `test_CircuitService/testServiceIsHandle` | PASS | 0.003 | verifies service is handle |
| 137 | `test_CircuitService/testListCircuitsDelegatesToGetAuth` | PASS | 0.006 | verifies list circuits delegates to get auth |
| 138 | `test_CircuitService/testListCircuitsPagedBuildsQueryParams` | PASS | 0.006 | verifies list circuits paged builds query params |
| 139 | `test_CircuitService/testGetCircuitUsesCircuitId` | PASS | 0.004 | verifies get circuit uses circuit id |
| 140 | `test_CircuitService/testAnalyzeCircuitPostsToCorrectEndpoint` | PASS | 0.005 | verifies analyze circuit posts to correct endpoint |
| 141 | `test_CircuitService/testGetAnalysisUsesCorrectEndpoint` | PASS | 0.004 | verifies get analysis uses correct endpoint |
| 142 | `test_CircuitService/testMatchBenchmarksPostsCorrectly` | PASS | 0.004 | verifies match benchmarks posts correctly |
| 143 | `test_CircuitService/testPreviewCircuitGetsCorrectEndpoint` | PASS | 0.004 | verifies preview circuit gets correct endpoint |
| 144 | `test_CircuitService/testUpdateCircuitPatchesCorrectly` | PASS | 0.006 | verifies update circuit patches correctly |
| 145 | `test_CircuitService/testDeleteCircuitDeletesCorrectly` | PASS | 0.003 | verifies delete circuit deletes correctly |
| 146 | `test_CircuitService/testUploadCircuitDelegatesToUploadFileAuth` | PASS | 0.005 | verifies upload circuit delegates to upload file auth |
| 147 | `test_CircuitService/testTokenIsForwarded` | PASS | 0.003 | verifies token is forwarded |
| 148 | `test_CuttingService/testConstructorSetsClient` | PASS | 0.055 | verifies constructor sets client |
| 149 | `test_CuttingService/testAnalyzeCutsPostsToAnalyzeEndpoint` | PASS | 0.005 | verifies analyze cuts posts to analyze endpoint |
| 150 | `test_CuttingService/testAnalyzeCutsOmitsTargetKWhenEmpty` | PASS | 0.002 | verifies analyze cuts omits target kwhen empty |
| 151 | `test_CuttingService/testListPresetsUsesGetAuth` | PASS | 0.003 | verifies list presets uses get auth |
| 152 | `test_CuttingService/testCreateBatchHitsCircuitEndpoint` | PASS | 0.003 | verifies create batch hits circuit endpoint |
| 153 | `test_CuttingService/testPollBatchIncludesBatchIdInPath` | PASS | 0.002 | verifies poll batch includes batch id in path |
| 154 | `test_CuttingService/testGetBatchResultSuffixesResult` | PASS | 0.002 | verifies get batch result suffixes result |
| 155 | `test_CuttingService/testCancelUsesDeleteAuth` | PASS | 0.003 | verifies cancel uses delete auth |
| 156 | `test_CuttingService/testListBatchesUsesGetAuth` | PASS | 0.003 | verifies list batches uses get auth |
| 157 | `test_CuttingService/testTokenIsForwarded` | PASS | 0.003 | verifies token is forwarded |
| 158 | `test_FastAPIClient/testConstructorSetsBaseUrl` | PASS | 0.039 | verifies constructor sets base url |
| 159 | `test_FastAPIClient/testConstructorDefaultTimeout` | PASS | 0.004 | verifies constructor default timeout |
| 160 | `test_FastAPIClient/testConstructorDefaultProjectIdEmpty` | PASS | 0.003 | verifies constructor default project id empty |
| 161 | `test_FastAPIClient/testConstructorAcceptsStringUrl` | PASS | 0.008 | verifies constructor accepts string url |
| 162 | `test_FastAPIClient/testFastAPIClientIsHandle` | PASS | 0.003 | verifies fast apiclient is handle |
| 163 | `test_FastAPIClient/testSetBaseUrlChangesUrl` | PASS | 0.003 | verifies set base url changes url |
| 164 | `test_FastAPIClient/testSetBaseUrlAcceptsString` | PASS | 0.005 | verifies set base url accepts string |
| 165 | `test_FastAPIClient/testHttpsBaseUrlAccepted` | PASS | 0.008 | verifies https base url accepted |
| 166 | `test_FastAPIClient/testHttpLoopbackAccepted` | PASS | 0.015 | verifies http loopback accepted |
| 167 | `test_FastAPIClient/testHttpRemoteRejected` | PASS | 0.005 | verifies http remote rejected |
| 168 | `test_FastAPIClient/testEmptyBaseUrlRejected` | PASS | 0.009 | verifies empty base url rejected |
| 169 | `test_FastAPIClient/testSetBaseUrlRejectsInsecureRemote` | PASS | 0.007 | verifies set base url rejects insecure remote |
| 170 | `test_FastAPIClient/testProjectIdCanBeSet` | PASS | 0.002 | verifies project id can be set |
| 171 | `test_FastAPIClient/testTimeoutCanBeChanged` | PASS | 0.005 | verifies timeout can be changed |
| 172 | `test_FastAPIClient/testMultipleInstancesAreIndependent` | PASS | 0.007 | verifies multiple instances are independent |
| 173 | `test_JobService/testConstructorAcceptsClient` | PASS | 0.055 | verifies constructor accepts client |
| 174 | `test_JobService/testServiceIsHandle` | PASS | 0.002 | verifies service is handle |
| 175 | `test_JobService/testSubmitJobPosts` | PASS | 0.004 | verifies submit job posts |
| 176 | `test_JobService/testSubmitJobForwardsPayload` | PASS | 0.003 | verifies submit job forwards payload |
| 177 | `test_JobService/testListJobsUsesGetAuth` | PASS | 0.003 | verifies list jobs uses get auth |
| 178 | `test_JobService/testListJobsDefaultPagination` | PASS | 0.002 | verifies list jobs default pagination |
| 179 | `test_JobService/testListJobsCustomPagination` | PASS | 0.005 | verifies list jobs custom pagination |
| 180 | `test_JobService/testGetJobUsesJobId` | PASS | 0.005 | verifies get job uses job id |
| 181 | `test_JobService/testGetStatusUsesCorrectEndpoint` | PASS | 0.003 | verifies get status uses correct endpoint |
| 182 | `test_JobService/testCancelJobPosts` | PASS | 0.003 | verifies cancel job posts |
| 183 | `test_JobService/testPauseJobPosts` | PASS | 0.003 | verifies pause job posts |
| 184 | `test_JobService/testGetResultsGets` | PASS | 0.003 | verifies get results gets |
| 185 | `test_JobService/testGetDetailedResultsGets` | PASS | 0.002 | verifies get detailed results gets |
| 186 | `test_JobService/testGetErrorTrendsGets` | PASS | 0.005 | verifies get error trends gets |
| 187 | `test_JobService/testGetRBDecayGets` | PASS | 0.003 | verifies get rbdecay gets |
| 188 | `test_JobService/testListProjectJobsUsesProjectId` | PASS | 0.002 | verifies list project jobs uses project id |
| 189 | `test_JobService/testListProjectJobsDefaultPagination` | PASS | 0.002 | verifies list project jobs default pagination |
| 190 | `test_JobService/testSubmitProjectJobPosts` | PASS | 0.003 | verifies submit project job posts |
| 191 | `test_JobService/testTokenIsForwarded` | PASS | 0.002 | verifies token is forwarded |
| 192 | `test_JsonHelper/testPickSimpleField` | PASS | 0.016 | verifies pick simple field |
| 193 | `test_JsonHelper/testPickDottedPath` | PASS | 0.006 | verifies pick dotted path |
| 194 | `test_JsonHelper/testPickFallbackChain` | PASS | 0.002 | verifies pick fallback chain |
| 195 | `test_JsonHelper/testPickReturnsEmptyForMissing` | PASS | 0.002 | verifies pick returns empty for missing |
| 196 | `test_JsonHelper/testPickNumericValue` | PASS | 0.001 | verifies pick numeric value |
| 197 | `test_JsonHelper/testPickOnJsonString` | PASS | 0.001 | verifies pick on json string |
| 198 | `test_JsonHelper/testPickNumericSinglePath` | PASS | 0.002 | verifies pick numeric single path |
| 199 | `test_JsonHelper/testPickNumericFallbackChain` | PASS | 0.001 | verifies pick numeric fallback chain |
| 200 | `test_JsonHelper/testPickNumericMixedDotFallbackDoesNotError` | PASS | 0.003 | verifies pick numeric mixed dot fallback does not error |
| 201 | `test_JsonHelper/testPickNumericMissingReturnsDefault` | PASS | 0.001 | verifies pick numeric missing returns default |
| 202 | `test_JsonHelper/testPickOneSimple` | PASS | 0.002 | verifies pick one simple |
| 203 | `test_JsonHelper/testPickOneMissingField` | PASS | 0.006 | verifies pick one missing field |
| 204 | `test_JsonHelper/testToDoubleFromNumber` | PASS | 0.013 | verifies to double from number |
| 205 | `test_JsonHelper/testToDoubleFromString` | PASS | 0.002 | verifies to double from string |
| 206 | `test_JsonHelper/testToDoubleFromChar` | PASS | 0.004 | verifies to double from char |
| 207 | `test_JsonHelper/testToDoubleFromNonNumericReturnsZero` | PASS | 0.005 | verifies to double from non numeric returns zero |
| 208 | `test_JsonHelper/testToDoubleFromEmptyStringReturnsZero` | PASS | 0.001 | verifies to double from empty string returns zero |
| 209 | `test_JsonHelper/testExtractListReturnsArray` | PASS | 0.001 | verifies extract list returns array |
| 210 | `test_JsonHelper/testExtractListMissingFieldReturnsEmpty` | PASS | 0.003 | verifies extract list missing field returns empty |
| 211 | `test_JsonHelper/testExtractListFromJsonString` | PASS | 0.001 | verifies extract list from json string |
| 212 | `test_JsonHelper/testPrettyStruct` | PASS | 0.010 | verifies pretty struct |
| 213 | `test_JsonHelper/testPrettyString` | PASS | 0.005 | verifies pretty string |
| 214 | `test_JsonHelper/testPrettyChar` | PASS | 0.001 | verifies pretty char |
| 215 | `test_JsonHelper/testPrettyJsonString` | PASS | 0.002 | verifies pretty json string |
| 216 | `test_JsonHelper/testDecodeIfJsonObject` | PASS | 0.001 | verifies decode if json object |
| 217 | `test_JsonHelper/testDecodeIfJsonArray` | PASS | 0.001 | verifies decode if json array |
| 218 | `test_JsonHelper/testDecodeIfJsonPlainText` | PASS | 0.001 | verifies decode if json plain text |
| 219 | `test_JsonHelper/testDecodeIfJsonAlreadyStruct` | PASS | 0.002 | verifies decode if json already struct |
| 220 | `test_JsonHelper/testSafeFieldPresent` | PASS | 0.001 | verifies safe field present |
| 221 | `test_JsonHelper/testSafeFieldMissing` | PASS | 0.001 | verifies safe field missing |
| 222 | `test_JsonHelper/testSafeFieldNotStruct` | PASS | 0.001 | verifies safe field not struct |
| 223 | `test_JsonHelper/testAsListWithStruct` | PASS | 0.002 | verifies as list with struct |
| 224 | `test_JsonHelper/testAsListWithEmptyReturnsEmpty` | PASS | 0.001 | verifies as list with empty returns empty |
| 225 | `test_JsonHelper/testProjectsToRowsEmpty` | PASS | 0.001 | verifies projects to rows empty |
| 226 | `test_JsonHelper/testProjectsToRowsWithData` | PASS | 0.007 | verifies projects to rows with data |
| 227 | `test_JsonHelper/testBackendsToRowsEmpty` | PASS | 0.001 | verifies backends to rows empty |
| 228 | `test_JsonHelper/testBackendsToRowsEmptyArrayInEnvelope` | PASS | 0.001 | verifies backends to rows empty array in envelope |
| 229 | `test_JsonHelper/testJobsToRowsEmpty` | PASS | 0.002 | verifies jobs to rows empty |
| 230 | `test_JsonHelper/testJobsToRowsEmptyArrayInEnvelope` | PASS | 0.001 | verifies jobs to rows empty array in envelope |
| 231 | `test_JsonHelper/testActivityToRowsEmptyArrayInEnvelope` | PASS | 0.001 | verifies activity to rows empty array in envelope |
| 232 | `test_JsonHelper/testExtractListSafeReturnsListWhenPresent` | PASS | 0.001 | verifies extract list safe returns list when present |
| 233 | `test_JsonHelper/testExtractListSafeReturnsEmptyForEmptyArray` | PASS | 0.000 | verifies extract list safe returns empty for empty array |
| 234 | `test_JsonHelper/testExtractListSafeReturnsEmptyForMissingField` | PASS | 0.000 | verifies extract list safe returns empty for missing field |
| 235 | `test_JsonHelper/testResultsToRowsEmpty` | PASS | 0.001 | verifies results to rows empty |
| 236 | `test_JsonHelper/testBenchmarkStrategyToRowsEmpty` | PASS | 0.001 | verifies benchmark strategy to rows empty |
| 237 | `test_JsonHelper/testBenchmarkStrategyToRowsEmptyStrategiesArray` | PASS | 0.001 | verifies benchmark strategy to rows empty strategies array |
| 238 | `test_JsonHelper/testBenchmarkStrategyToRowsHappyPath` | PASS | 0.020 | verifies benchmark strategy to rows happy path |
| 239 | `test_JsonHelper/testBenchmarkStrategyToRowsAcceptsBackendAfterFields` | PASS | 0.005 | verifies benchmark strategy to rows accepts backend after fields |
| 240 | `test_JsonHelper/testPredictionToLinesEmpty` | PASS | 0.002 | verifies prediction to lines empty |
| 241 | `test_JsonHelper/testPredictionToLinesWithData` | PASS | 0.005 | verifies prediction to lines with data |
| 242 | `test_Labels/test_error_title_is_error` | PASS | 0.050 | verifies error title is error |
| 243 | `test_Labels/test_nav_welcome_is_present` | PASS | 0.001 | verifies nav welcome is present |
| 244 | `test_Labels/test_missing_key_returns_default` | PASS | 0.002 | verifies missing key returns default |
| 245 | `test_Labels/test_cols_returns_cell_array` | PASS | 0.004 | verifies cols returns cell array |
| 246 | `test_Labels/test_cols_falls_back_gracefully` | PASS | 0.004 | verifies cols falls back gracefully |
| 247 | `test_Labels/test_items_returns_cell_array` | PASS | 0.002 | verifies items returns cell array |
| 248 | `test_Labels/test_reload_does_not_crash` | PASS | 0.016 | verifies reload does not crash |
| 249 | `test_Logger/testLogDoesNotThrow` | PASS | 0.022 | verifies log does not throw |
| 250 | `test_Logger/testLogWithoutVarargs` | PASS | 0.006 | verifies log without varargs |
| 251 | `test_Logger/testInfoDoesNotThrow` | PASS | 0.004 | verifies info does not throw |
| 252 | `test_Logger/testInfoWithFormat` | PASS | 0.005 | verifies info with format |
| 253 | `test_Logger/testWarnDoesNotThrow` | PASS | 0.004 | verifies warn does not throw |
| 254 | `test_Logger/testWarnWithFormat` | PASS | 0.006 | verifies warn with format |
| 255 | `test_Logger/testErrorDoesNotThrow` | PASS | 0.004 | verifies error does not throw |
| 256 | `test_Logger/testErrorWithFormat` | PASS | 0.003 | verifies error with format |
| 257 | `test_Logger/testDebugDoesNotThrow` | PASS | 0.003 | verifies debug does not throw |
| 258 | `test_Logger/testDebugWithFormat` | PASS | 0.003 | verifies debug with format |
| 259 | `test_Logger/testHttpDoesNotThrow` | PASS | 0.004 | verifies http does not throw |
| 260 | `test_Logger/testHttpResponseDoesNotThrow` | PASS | 0.004 | verifies http response does not throw |
| 261 | `test_Logger/testLogOutputContainsTimestamp` | PASS | 0.004 | verifies log output contains timestamp |
| 262 | `test_Logger/testLogOutputUppercasesLevel` | PASS | 0.001 | verifies log output uppercases level |
| 263 | `test_Logger/testLogWithMultipleVarargs` | PASS | 0.002 | verifies log with multiple varargs |
| 264 | `test_Logger/testSetAndGetLevel` | PASS | 0.004 | verifies set and get level |
| 265 | `test_Logger/testDebugSuppressedAtInfoLevel` | PASS | 0.001 | verifies debug suppressed at info level |
| 266 | `test_Logger/testInfoShownAtInfoLevel` | PASS | 0.001 | verifies info shown at info level |
| 267 | `test_Logger/testErrorAlwaysShown` | PASS | 0.001 | verifies error always shown |
| 268 | `test_Logger/testWarnSuppressedAtErrorLevel` | PASS | 0.001 | verifies warn suppressed at error level |
| 269 | `test_Logger/testRedactBearerToken` | PASS | 0.001 | verifies redact bearer token |
| 270 | `test_Logger/testRedactAuthorizationHeader` | PASS | 0.001 | verifies redact authorization header |
| 271 | `test_Logger/testRedactQueryParamToken` | PASS | 0.000 | verifies redact query param token |
| 272 | `test_Logger/testRedactPreservesSafeText` | PASS | 0.001 | verifies redact preserves safe text |
| 273 | `test_Logger/testLogOutputRedactsBearerToken` | PASS | 0.001 | verifies log output redacts bearer token |
| 274 | `test_MitigationCompareViewModel/test_parseLevelId_numeric` | PASS | 0.044 | verifies parse level id numeric |
| 275 | `test_MitigationCompareViewModel/test_parseLevelId_invalid_returns_minus_one` | PASS | 0.003 | verifies parse level id invalid returns minus one |
| 276 | `test_MitigationCompareViewModel/test_gradeColor_unity_is_green` | PASS | 0.009 | verifies grade color unity is green |
| 277 | `test_MitigationCompareViewModel/test_gradeColor_mid_is_amber_band` | PASS | 0.004 | verifies grade color mid is amber band |
| 278 | `test_MitigationCompareViewModel/test_gradeColor_high_is_red` | PASS | 0.003 | verifies grade color high is red |
| 279 | `test_MitigationCompareViewModel/test_gradeColor_nonfinite_is_neutral` | PASS | 0.001 | verifies grade color nonfinite is neutral |
| 280 | `test_MitigationCompareViewModel/test_fmtInt_under_1k_renders_plain` | PASS | 0.001 | verifies fmt int under 1k renders plain |
| 281 | `test_MitigationCompareViewModel/test_fmtInt_thousand_uses_k_suffix` | PASS | 0.001 | verifies fmt int thousand uses k suffix |
| 282 | `test_MitigationCompareViewModel/test_fmtInt_million_uses_M_suffix` | PASS | 0.001 | verifies fmt int million uses m suffix |
| 283 | `test_MitigationCompareViewModel/test_fmtSeconds_subminute` | PASS | 0.001 | verifies fmt seconds subminute |
| 284 | `test_MitigationCompareViewModel/test_fmtSeconds_subhour` | PASS | 0.001 | verifies fmt seconds subhour |
| 285 | `test_MitigationCompareViewModel/test_safeField_existing` | PASS | 0.001 | verifies safe field existing |
| 286 | `test_MitigationCompareViewModel/test_safeField_missing_falls_back` | PASS | 0.001 | verifies safe field missing falls back |
| 287 | `test_MitigationCompareViewModel/test_levelLabel_prefers_label` | PASS | 0.001 | verifies level label prefers label |
| 288 | `test_MitigationCompareViewModel/test_levelLabel_falls_through_to_name_when_no_label` | PASS | 0.001 | verifies level label falls through to name when no label |
| 289 | `test_MitigationCompareViewModel/test_levelId_uses_id_field` | PASS | 0.002 | verifies level id uses id field |
| 290 | `test_MitigationService/test_constructor_creates_service` | PASS | 0.050 | verifies constructor creates service |
| 291 | `test_MitigationService/test_listLevels_uses_getAuth` | PASS | 0.003 | verifies list levels uses get auth |
| 292 | `test_MitigationService/test_listLevels_forwards_token` | PASS | 0.003 | verifies list levels forwards token |
| 293 | `test_MitigationService/test_estimate_uses_postAuthJson` | PASS | 0.003 | verifies estimate uses post auth json |
| 294 | `test_MitigationService/test_estimate_preserves_payload` | PASS | 0.004 | verifies estimate preserves payload |
| 295 | `test_MitigationService/test_estimate_returns_stub_response` | PASS | 0.003 | verifies estimate returns stub response |
| 296 | `test_PredictionService/testConstructorAcceptsClient` | PASS | 0.055 | verifies constructor accepts client |
| 297 | `test_PredictionService/testServiceIsHandle` | PASS | 0.001 | verifies service is handle |
| 298 | `test_PredictionService/testPredictPostsToCorrectEndpoint` | PASS | 0.008 | verifies predict posts to correct endpoint |
| 299 | `test_PredictionService/testPredictPayloadContainsAllFields` | PASS | 0.010 | verifies predict payload contains all fields |
| 300 | `test_PredictionService/testPredictAcceptsCellArrayOfBackends` | PASS | 0.007 | verifies predict accepts cell array of backends |
| 301 | `test_PredictionService/testPredictAcceptsStringBackend` | PASS | 0.005 | verifies predict accepts string backend |
| 302 | `test_PredictionService/testPredictRoundsShots` | PASS | 0.004 | verifies predict rounds shots |
| 303 | `test_PredictionService/testGetPredictionUsesGetAuth` | PASS | 0.003 | verifies get prediction uses get auth |
| 304 | `test_PredictionService/testOptimizeCircuitPosts` | PASS | 0.004 | verifies optimize circuit posts |
| 305 | `test_PredictionService/testOptimizeCircuitPayloadContainsStrategy` | PASS | 0.007 | verifies optimize circuit payload contains strategy |
| 306 | `test_PredictionService/testReturnValueFromStub` | PASS | 0.004 | verifies return value from stub |
| 307 | `test_PredictionService/testTokenIsForwarded` | PASS | 0.003 | verifies token is forwarded |
| 308 | `test_ProjectService/testConstructorAcceptsClient` | PASS | 0.065 | verifies constructor accepts client |
| 309 | `test_ProjectService/testServiceIsHandle` | PASS | 0.001 | verifies service is handle |
| 310 | `test_ProjectService/testListProjectsUsesGetAuth` | PASS | 0.005 | verifies list projects uses get auth |
| 311 | `test_ProjectService/testCreateProjectPostsCorrectly` | PASS | 0.004 | verifies create project posts correctly |
| 312 | `test_ProjectService/testCreateProjectPayloadContainsName` | PASS | 0.003 | verifies create project payload contains name |
| 313 | `test_ProjectService/testUpdateProjectUsesPatchAuthRaw` | PASS | 0.004 | verifies update project uses patch auth raw |
| 314 | `test_ProjectService/testDeleteProjectUsesDeleteAuth` | PASS | 0.003 | verifies delete project uses delete auth |
| 315 | `test_ProjectService/testGetProjectUsesGetAuth` | PASS | 0.002 | verifies get project uses get auth |
| 316 | `test_ProjectService/testGetDashboardUsesCorrectEndpoint` | PASS | 0.003 | verifies get dashboard uses correct endpoint |
| 317 | `test_ProjectService/testGetNotesUsesGetAuth` | PASS | 0.003 | verifies get notes uses get auth |
| 318 | `test_ProjectService/testSaveNotesUsesPutAuthJson` | PASS | 0.004 | verifies save notes uses put auth json |
| 319 | `test_ProjectService/testSaveBenchmarkConfigPosts` | PASS | 0.005 | verifies save benchmark config posts |
| 320 | `test_ProjectService/testGetBenchmarkConfigGets` | PASS | 0.003 | verifies get benchmark config gets |
| 321 | `test_ProjectService/testCompareStrategiesPosts` | PASS | 0.004 | verifies compare strategies posts |
| 322 | `test_ProjectService/testPredictPosts` | PASS | 0.004 | verifies predict posts |
| 323 | `test_ProjectService/testGetLatestPredictionGets` | PASS | 0.003 | verifies get latest prediction gets |
| 324 | `test_ProjectService/testListReportsGets` | PASS | 0.003 | verifies list reports gets |
| 325 | `test_ProjectService/testGenerateReportPosts` | PASS | 0.004 | verifies generate report posts |
| 326 | `test_ProjectService/testTokenIsForwarded` | PASS | 0.002 | verifies token is forwarded |
| 327 | `test_QecEngineService/testBitFlipNoNoisePerfectFidelity` | PASS | 0.286 | verifies bit flip no noise perfect fidelity |
| 328 | `test_QecEngineService/testPhaseFlipNoNoisePerfectFidelity` | PASS | 0.163 | verifies phase flip no noise perfect fidelity |
| 329 | `test_QecEngineService/testDepolarizingNoNoisePerfectFidelity` | PASS | 0.164 | verifies depolarizing no noise perfect fidelity |
| 330 | `test_QecEngineService/testBlochVectorZeroState` | PASS | 0.022 | verifies bloch vector zero state |
| 331 | `test_QecEngineService/testBlochVectorPlusState` | PASS | 0.012 | verifies bloch vector plus state |
| 332 | `test_QecEngineService/testBlochVectorMixedState` | PASS | 0.011 | verifies bloch vector mixed state |
| 333 | `test_QecEngineService/testFidelityDecreasesWithNoise` | PASS | 0.176 | verifies fidelity decreases with noise |
| 334 | `test_QecEngineService/testSweepReturnsCorrectPoints` | PASS | 0.836 | verifies sweep returns correct points |
| 335 | `test_QecEngineService/testResultStructureFields` | PASS | 0.090 | verifies result structure fields |
| 336 | `test_QecEngineService/testSurfaceCodeReturnsResult` | PASS | 0.051 | verifies surface code returns result |
| 337 | `test_QecEngineService/testCompareCodesReturnsCellArray` | PASS | 1.247 | verifies compare codes returns cell array |
| 338 | `test_QecEngineService/testErrorWeightDistribution` | PASS | 0.012 | verifies error weight distribution |
| 339 | `test_QecEngineService/testDecayOverRounds` | PASS | 1.243 | verifies decay over rounds |
| 340 | `test_QecEngineService/testSurfaceLatticeCoords` | PASS | 0.003 | verifies surface lattice coords |
| 341 | `test_QecEngineService/testShor9NoNoise` | PASS | 209.959 | verifies shor9no noise |
| 342 | `test_QecEngineService/testSteane7NoNoise` | PASS | 6.723 | verifies steane7no noise |
| 343 | `test_QecEngineService/testCustomInitialState` | PASS | 0.106 | verifies custom initial state |
| 344 | `test_QmcService/test_submitAnalyze_uses_postAuthJson_with_circuit_id` | PASS | 0.088 | verifies submit analyze uses post auth json with circuit id |
| 345 | `test_QmcService/test_submitAnalyze_payload_shape` | PASS | 0.012 | verifies submit analyze payload shape |
| 346 | `test_QmcService/test_submitAnalyze_adds_backend_when_runtime` | PASS | 0.004 | verifies submit analyze adds backend when runtime |
| 347 | `test_QmcService/test_submitAnalyze_forwards_mitigation_option` | PASS | 0.008 | verifies submit analyze forwards mitigation option |
| 348 | `test_QmcService/test_getAnalyzeJob_uses_getAuth_with_job_id` | PASS | 0.003 | verifies get analyze job uses get auth with job id |
| 349 | `test_QmcService/test_cancelAnalyzeJob_uses_deleteAuth` | PASS | 0.003 | verifies cancel analyze job uses delete auth |
| 350 | `test_QmcService/test_getLast_hits_qae_result_endpoint` | PASS | 0.003 | verifies get last hits qae result endpoint |
| 351 | `test_QmcService/test_downloadIbmLog_passes_fmt_query_param` | PASS | 0.008 | verifies download ibm log passes fmt query param |
| 352 | `test_ReportService/testConstructorAcceptsClient` | PASS | 0.070 | verifies constructor accepts client |
| 353 | `test_ReportService/testServiceIsHandle` | PASS | 0.002 | verifies service is handle |
| 354 | `test_ReportService/testGenerateReportPosts` | PASS | 0.011 | verifies generate report posts |
| 355 | `test_ReportService/testGenerateReportPayload` | PASS | 0.013 | verifies generate report payload |
| 356 | `test_ReportService/testListReportsUsesGetAuth` | PASS | 0.004 | verifies list reports uses get auth |
| 357 | `test_ReportService/testGetReportUsesReportId` | PASS | 0.004 | verifies get report uses report id |
| 358 | `test_ReportService/testDownloadReportUsesCorrectEndpoint` | PASS | 0.003 | verifies download report uses correct endpoint |
| 359 | `test_ReportService/testShareReportPosts` | PASS | 0.004 | verifies share report posts |
| 360 | `test_ReportService/testShareReportPayloadContainsEmail` | PASS | 0.005 | verifies share report payload contains email |
| 361 | `test_ReportService/testReturnValueFromStub` | PASS | 0.005 | verifies return value from stub |
| 362 | `test_ReportService/testTokenIsForwarded` | PASS | 0.003 | verifies token is forwarded |
| 363 | `test_ResourceEstimatorService/test_distance_default_thresholds` | PASS | 0.055 | verifies distance default thresholds |
| 364 | `test_ResourceEstimatorService/test_distance_lower_target_grows` | PASS | 0.002 | verifies distance lower target grows |
| 365 | `test_ResourceEstimatorService/test_distance_above_threshold_caps` | PASS | 0.001 | verifies distance above threshold caps |
| 366 | `test_ResourceEstimatorService/test_distance_always_odd` | PASS | 0.005 | verifies distance always odd |
| 367 | `test_ResourceEstimatorService/test_pi_over_2_is_clifford` | PASS | 0.002 | verifies pi over 2 is clifford |
| 368 | `test_ResourceEstimatorService/test_pi_over_4_is_not_clifford` | PASS | 0.001 | verifies pi over 4 is not clifford |
| 369 | `test_ResourceEstimatorService/test_clifford_only_circuit_zero_t_states` | PASS | 0.004 | verifies clifford only circuit zero t states |
| 370 | `test_ResourceEstimatorService/test_t_gate_counted` | PASS | 0.003 | verifies t gate counted |
| 371 | `test_ResourceEstimatorService/test_toffoli_counted_separately` | PASS | 0.003 | verifies toffoli counted separately |
| 372 | `test_ResourceEstimatorService/test_clifford_rotations_excluded` | PASS | 0.002 | verifies clifford rotations excluded |
| 373 | `test_ResourceEstimatorService/test_arbitrary_rotation_costs_t_states` | PASS | 0.003 | verifies arbitrary rotation costs t states |
| 374 | `test_ResourceEstimatorService/test_bell_state_estimate` | PASS | 0.006 | verifies bell state estimate |
| 375 | `test_ResourceEstimatorService/test_toffoli_circuit_needs_factory` | PASS | 0.005 | verifies toffoli circuit needs factory |
| 376 | `test_ResourceEstimatorService/test_runtime_scales_with_depth` | PASS | 0.005 | verifies runtime scales with depth |
| 377 | `test_ResourceEstimatorService/test_estimate_rejects_bad_params` | PASS | 0.019 | verifies estimate rejects bad params |
| 378 | `test_RunPlannerService/test_factor_table_levels` | PASS | 0.065 | verifies factor table levels |
| 379 | `test_RunPlannerService/test_factor_caps_at_99` | PASS | 0.004 | verifies factor caps at 99 |
| 380 | `test_RunPlannerService/test_unknown_level_factor_one` | PASS | 0.004 | verifies unknown level factor one |
| 381 | `test_RunPlannerService/test_factor_handles_nan` | PASS | 0.001 | verifies factor handles nan |
| 382 | `test_RunPlannerService/test_frontier_empty_input` | PASS | 0.004 | verifies frontier empty input |
| 383 | `test_RunPlannerService/test_frontier_single_point` | PASS | 0.011 | verifies frontier single point |
| 384 | `test_RunPlannerService/test_frontier_drops_dominated_points` | PASS | 0.013 | verifies frontier drops dominated points |
| 385 | `test_RunPlannerService/test_frontier_drops_nonfinite_points` | PASS | 0.004 | verifies frontier drops nonfinite points |
| 386 | `test_RunPlannerService/test_optimal_returns_cheapest_hitting_target` | PASS | 0.003 | verifies optimal returns cheapest hitting target |
| 387 | `test_RunPlannerService/test_optimal_falls_back_when_no_target_hit` | PASS | 0.004 | verifies optimal falls back when no target hit |
| 388 | `test_RunPlannerService/test_optimal_returns_empty_when_all_costs_nan` | PASS | 0.002 | verifies optimal returns empty when all costs nan |
| 389 | `test_RunPlannerService/test_optimal_skips_nan_cost_when_others_are_finite` | PASS | 0.005 | verifies optimal skips nan cost when others are finite |
| 390 | `test_RunPlannerService/test_makePoint_round_trip` | PASS | 0.014 | verifies make point round trip |
| 391 | `test_ServiceContainer/testConstructorReturnsServiceContainer` | PASS | 0.123 | verifies constructor returns service container |
| 392 | `test_ServiceContainer/testContainerIsHandle` | PASS | 0.008 | verifies container is handle |
| 393 | `test_ServiceContainer/testClientNotEmpty` | PASS | 0.011 | verifies client not empty |
| 394 | `test_ServiceContainer/testAuthSvcNotEmpty` | PASS | 0.010 | verifies auth svc not empty |
| 395 | `test_ServiceContainer/testCircuitSvcNotEmpty` | PASS | 0.010 | verifies circuit svc not empty |
| 396 | `test_ServiceContainer/testBackendSvcNotEmpty` | PASS | 0.014 | verifies backend svc not empty |
| 397 | `test_ServiceContainer/testJobSvcNotEmpty` | PASS | 0.011 | verifies job svc not empty |
| 398 | `test_ServiceContainer/testProjectSvcNotEmpty` | PASS | 0.011 | verifies project svc not empty |
| 399 | `test_ServiceContainer/testPredictionSvcNotEmpty` | PASS | 0.011 | verifies prediction svc not empty |
| 400 | `test_ServiceContainer/testReportSvcNotEmpty` | PASS | 0.009 | verifies report svc not empty |
| 401 | `test_ServiceContainer/testSettingsSvcNotEmpty` | PASS | 0.011 | verifies settings svc not empty |
| 402 | `test_ServiceContainer/testQecEngineNotEmpty` | PASS | 0.011 | verifies qec engine not empty |
| 403 | `test_ServiceContainer/testBenchmarkSvcNotEmpty` | PASS | 0.015 | verifies benchmark svc not empty |
| 404 | `test_ServiceContainer/testClientIsFastAPIClient` | PASS | 0.010 | verifies client is fast apiclient |
| 405 | `test_ServiceContainer/testAuthSvcIsAuthService` | PASS | 0.009 | verifies auth svc is auth service |
| 406 | `test_ServiceContainer/testCircuitSvcIsCircuitService` | PASS | 0.007 | verifies circuit svc is circuit service |
| 407 | `test_ServiceContainer/testQecEngineIsQecEngineService` | PASS | 0.007 | verifies qec engine is qec engine service |
| 408 | `test_ServiceContainer/testBenchmarkSvcIsBenchmarkService` | PASS | 0.007 | verifies benchmark svc is benchmark service |
| 409 | `test_SettingsService/testConstructorAcceptsClient` | PASS | 0.067 | verifies constructor accepts client |
| 410 | `test_SettingsService/testServiceIsHandle` | PASS | 0.002 | verifies service is handle |
| 411 | `test_SettingsService/testGetPreferencesUsesGetAuth` | PASS | 0.008 | verifies get preferences uses get auth |
| 412 | `test_SettingsService/testGetServerConfigUsesGetAuth` | PASS | 0.006 | verifies get server config uses get auth |
| 413 | `test_SettingsService/testSavePreferencesPosts` | PASS | 0.006 | verifies save preferences posts |
| 414 | `test_SettingsService/testSavePreferencesForwardsPayload` | PASS | 0.004 | verifies save preferences forwards payload |
| 415 | `test_SettingsService/testVerifyIbmCredentialsPosts` | PASS | 0.005 | verifies verify ibm credentials posts |
| 416 | `test_SettingsService/testVerifyIbmCredentialsPayload` | PASS | 0.007 | verifies verify ibm credentials payload |
| 417 | `test_SettingsService/testClearCacheUsesDeleteAuth` | PASS | 0.004 | verifies clear cache uses delete auth |
| 418 | `test_SettingsService/testTokenIsForwarded` | PASS | 0.004 | verifies token is forwarded |
| 419 | `test_StatevectorSimulator/test_canSimulate_caps_at_14` | PASS | 0.061 | verifies can simulate caps at 14 |
| 420 | `test_StatevectorSimulator/test_bell_state_matches_reference` | PASS | 0.028 | verifies bell state matches reference |
| 421 | `test_StatevectorSimulator/test_ghz3_matches_reference` | PASS | 0.016 | verifies ghz3 matches reference |
| 422 | `test_StatevectorSimulator/test_plus_state_bloch` | PASS | 0.011 | verifies plus state bloch |
| 423 | `test_StatevectorSimulator/test_measure_halts_subsequent_gates` | PASS | 0.015 | verifies measure halts subsequent gates |
| 424 | `test_StatevectorSimulator/test_top_amplitudes_sorted` | PASS | 0.004 | verifies top amplitudes sorted |
| 425 | `test_StatevectorSimulator/test_rx_pi_rotates_to_minus_i` | PASS | 0.025 | verifies rx pi rotates to minus i |
| 426 | `test_TemplateRegistry/test_list_returns_eighteen` | PASS | 0.059 | verifies list returns eighteen |
| 427 | `test_TemplateRegistry/test_find_returns_matching_metadata` | PASS | 0.006 | verifies find returns matching metadata |
| 428 | `test_TemplateRegistry/test_find_throws_on_unknown` | PASS | 0.013 | verifies find throws on unknown |
| 429 | `test_TemplateRegistry/test_every_template_instantiates` | PASS | 0.289 | verifies every template instantiates |
| 430 | `test_TemplateRegistry/test_bell_has_h_then_cx` | PASS | 0.003 | verifies bell has h then cx |
| 431 | `test_TemplateRegistry/test_ghz_n_widens_with_n` | PASS | 0.003 | verifies ghz n widens with n |
| 432 | `test_TemplateRegistry/test_dj_constant_has_no_oracle` | PASS | 0.003 | verifies dj constant has no oracle |
| 433 | `test_TemplateRegistry/test_superdense_pads_message` | PASS | 0.002 | verifies superdense pads message |
| 434 | `test_Theme/testColorBgIsRgbTriple` | PASS | 0.027 | verifies color bg is rgb triple |
| 435 | `test_Theme/testColorCardIsRgbTriple` | PASS | 0.003 | verifies color card is rgb triple |
| 436 | `test_Theme/testColorDividerIsRgbTriple` | PASS | 0.002 | verifies color divider is rgb triple |
| 437 | `test_Theme/testColorHeadingIsRgbTriple` | PASS | 0.002 | verifies color heading is rgb triple |
| 438 | `test_Theme/testColorLabelIsRgbTriple` | PASS | 0.004 | verifies color label is rgb triple |
| 439 | `test_Theme/testColorMutedIsRgbTriple` | PASS | 0.002 | verifies color muted is rgb triple |
| 440 | `test_Theme/testColorPrimaryIsRgbTriple` | PASS | 0.004 | verifies color primary is rgb triple |
| 441 | `test_Theme/testColorSuccessIsRgbTriple` | PASS | 0.002 | verifies color success is rgb triple |
| 442 | `test_Theme/testColorPurpleIsRgbTriple` | PASS | 0.002 | verifies color purple is rgb triple |
| 443 | `test_Theme/testColorAmberIsRgbTriple` | PASS | 0.001 | verifies color amber is rgb triple |
| 444 | `test_Theme/testFontSizeSmIsPositive` | PASS | 0.003 | verifies font size sm is positive |
| 445 | `test_Theme/testFontSizeIsPositive` | PASS | 0.001 | verifies font size is positive |
| 446 | `test_Theme/testFontSizeMdIsPositive` | PASS | 0.001 | verifies font size md is positive |
| 447 | `test_Theme/testFontSizeLgIsPositive` | PASS | 0.001 | verifies font size lg is positive |
| 448 | `test_Theme/testFontSizeTitleIsPositive` | PASS | 0.001 | verifies font size title is positive |
| 449 | `test_Theme/testFontSizeOrdering` | PASS | 0.003 | verifies font size ordering |
| 450 | `test_Theme/testBtnRowHeightIsPositive` | PASS | 0.002 | verifies btn row height is positive |
| 451 | `test_Theme/testActionBarHeightIsPositive` | PASS | 0.001 | verifies action bar height is positive |
| 452 | `test_Theme/testBtnWidthIsPositive` | PASS | 0.001 | verifies btn width is positive |
| 453 | `test_Theme/testDividerWidthIsPositive` | PASS | 0.001 | verifies divider width is positive |
| 454 | `test_Theme/testGridPaddingIsFourElement` | PASS | 0.002 | verifies grid padding is four element |
| 455 | `test_Theme/testGridRowSpacingIsPositive` | PASS | 0.001 | verifies grid row spacing is positive |
| 456 | `test_Theme/testKpiInnerPadIsFourElement` | PASS | 0.001 | verifies kpi inner pad is four element |

## Environment

- Platform: MACA64
- Working directory: `/Users/mason/Workspace/Projects/QDash/sqk-qtau-matlab`
