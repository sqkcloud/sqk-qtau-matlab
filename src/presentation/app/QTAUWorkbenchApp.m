% QTAUWorkbenchApp   Main application class for QTAU: Hardware-Agnostic Execution.
%
%   Architecture (Clean Architecture for MATLAB):
%
%     Presentation layer  — QTAUWorkbenchApp (UI chrome) + *Screen functions
%     Service layer       — CircuitService, BackendService, JobService,
%                           ProjectService, PredictionService, ReportService,
%                           SettingsService  (business logic, no UI)
%     Infrastructure      — FastAPIClient (HTTP, no business logic)
%     Domain / Models     — AppState (mutable session context), JsonHelper (DTOs)
%
%   This class owns all UI properties and services.  Heavy logic is
%   delegated to focused helper classes:
%     LayoutBuilder      — one-time UI construction (header, body, overlays)
%     NavigationManager  — section switching, lazy VM init, nav styling, resize
%     OverlayManager     — loading spinners, auth overlay, logging, errors
%     PopupMenuManager   — context-menu popups for Projects & Circuits tables
%     StyleHelper        — button / axes / table styling
%     DialogBuilder      — modal dialogs (Login, NewProject, EditProject)
%
%   Dependencies: AppState.m, FastAPIClient.m, *Service.m, JsonHelper.m,
%                 *Screen.m files (one per screen).
classdef QTAUWorkbenchApp < handle

    % ── UI containers ─────────────────────────────────────────────────────────
    properties
        UIFigure
        RootGrid
        HeaderGrid
        BodyGrid

        NavPanel
        NavList
        NavButtons
        NavHtml                     % uihtml nav menu with consistent icon sizing
        NavToggleButton
        NavCollapsed = false
        % Routing key of the currently-visible section panel. Read by
        % NavigationManager.onSelectSection / onResizeUI to hide and
        % resize only the active panel instead of looping all 22
        % entries in SectionPanels on every nav (≈200 ms saved/nav).
        LastSectionKey = ""

        ContentShell
        ShellGrid                    % uigridlayout inside ContentShell
        HeaderSectionPanel           % card holding section title + subtitle
        HeaderSectionGrid            % uigridlayout inside HeaderSectionPanel
        HeaderSectionSep             % thin divider below HeaderSectionPanel
        ContentContainer
        SectionTitleLabel
        SectionSubtitleLabel
        SectionHelpButton              % "?" help icon next to SectionTitleLabel

        EventLog  = {}
        EventLogArea
        SectionPanels
        BuiltScreens               % containers.Map<char,logical> — which lazy screens have been built

        LoadingOverlay
        ActivityOverlay            % Reusable loading overlay for API calls
        OverlayBgButton            % "Run in background" uibutton overlaid on ActivityOverlay
        NavOverlayTimer            % Safety-timer that auto-dismisses the nav loading overlay
        AuthOverlay                % Login-required overlay covering content area
        HeaderUserLabel            % Logged-in username button in header
        HeaderUserMenuPanel        % The popup panel container
        HeaderLoginButton          % Login button in header (shown when logged out)
        AppHelpButton              % "?" app-level help icon next to userBadge in the header
        BackgroundTasks            % BackgroundTaskManager — registry of long-running async tasks
        Notifications              % NotificationCenter — toast surface for terminal tasks
        TasksIndicator             % BackgroundTasksIndicator — header badge
    end

    % ── Shared services ───────────────────────────────────────────────────────
    properties
        State           % AppState
        Services        % ServiceContainer (owns Client + all domain services)
        Client          % FastAPIClient  (shortcut → Services.Client)
        AuthSvc         % AuthService
        CircuitSvc      % CircuitService
        BackendSvc      % BackendService
        JobSvc          % JobService
        ProjectSvc      % ProjectService
        PredictionSvc   % PredictionService
        ReportSvc       % ReportService
        SettingsSvc     % SettingsService
        QecEngine       % QecEngineService (local computation, no HTTP)
        BenchmarkSvc    % BenchmarkService
        QmcSvc          % QmcService (Quantum Amplitude Estimation / QMC)
        CuttingSvc      % CuttingService (circuit cutting + reconstruction)
        MitigationSvc   % MitigationService (QEM ladder + cost preview)
    end

    % ── Screen callback services ──────────────────────────────────────────────
    properties
        WelcomeVm           % WelcomeViewModel
        DashboardVm         % DashboardViewModel
        ComposerVm          % ComposerViewModel — lazy-initialized via NavigationManager.ensureVm
        CircuitsVm          % CircuitsViewModel
        NotesVm             % NotesViewModel
        UploadVm            % UploadViewModel
        AnalysisVm          % AnalysisViewModel
        BackendsVm          % BackendsViewModel
        BenchmarkVm         % BenchmarkViewModel
        PredictionVm        % PredictionViewModel
        MitigationCompareVm % MitigationCompareViewModel — pre-submit strategy planner
        ResourceEstimatorVm % ResourceEstimatorViewModel — fault-tolerant overhead planner
        RunPlannerVm        % RunPlannerViewModel — cost-aware run optimisation
        JobsVm              % JobsViewModel
        ResultsVm           % ResultsViewModel
        DetailedAnalysisVm       % DetailedAnalysisViewModel
        BenchmarkDashboardVm     % BenchmarkDashboardViewModel
        CircuitCuttingVm         % CircuitCuttingViewModel
        ReportsVm                % ReportsViewModel
        SettingsVm          % SettingsViewModel
        QecSimulationVm     % QecSimulationViewModel
        QecVisualizationVm  % QecVisualizationViewModel
    end

    % ── Login dialog ──────────────────────────────────────────────────────────
    properties
        LoginDialog                % modal uifigure
        LoginDlgBaseUrlField       % Base URL uihtml input
        LoginDlgBaseUrlValue       % Current base URL string (synced from HTML)
        LoginDlgUsernameField      % Username uihtml input
        LoginDlgUsernameValue      % Current username string (synced from HTML)
        LoginDlgPasswordField      % Password uihtml input (native masking)
        LoginDlgPasswordReal       % Real password string (synced from HTML)
        LoginDlgStatusLabel        % Status label in dialog
    end

    % ── New Project dialog ────────────────────────────────────────────────────
    properties
        NewProjectDialog
        NewProjNameField
        NewProjDescField
        NewProjTagsField
        NewProjStatusLabel
    end

    % ── Edit Project dialog ──────────────────────────────────────────────────
    properties
        EditProjectDialog
        EditProjNameField
        EditProjDescField
        EditProjTagsField
        EditProjStatusLabel
        EditProjId
    end

    % ── Welcome tab ───────────────────────────────────────────────────────────
    properties
        UserInfoArea
        ActiveProjectLabel
        ProjectsSearchField
        ProjectsTable
        ProjectsPopupPanel
        ProjectsPopupEditBtn
        ProjectsPopupDeleteBtn
        ProjectsPageLabel
        ProjectsPrevButton
        ProjectsNextButton
    end

    % ── Dashboard tab ─────────────────────────────────────────────────────────
    properties
        DashboardSummaryArea         % legacy text area (kept for fallback path)
        DashboardStatusArea          % legacy JSON tree (no longer painted; held for back-compat)
        DashboardRefreshButton
        DashKpiLabels                % {1×4} cell of uilabel handles for KPI hero strip
        DashActivityTable
        DashActivityPrevBtn
        DashActivityPageLabel
        DashActivityNextBtn
        DashReadinessArea            % legacy text area (kept for fallback path)
        % ── Phase 1 dashboard refactor (Google/IBM-style) ────────────────
        DashStepperDots              % {1×8} cell of uilabel handles for stage dots
        DashStepperNames             % {1×8} cell of uibutton handles for stage names (Phase 2: clickable)
        DashReadinessLabels          % {1×4} cell of uilabel handles for run-readiness KPIs
        DashActivityAxes             % uiaxes for the 7-day jobs-per-day bar chart
        DashActivityGrid             % parent grid for the lazy uiaxes (built on first paint)
        DashActivityPlaceholder      % uilabel placeholder until the uiaxes materialises
        % ── Phase 2 dashboard refactor (live system status) ──────────────
        DashBackendHealthCards       % {1×N} cell of structs {nameLbl, dotLbl, qubitsLbl}
                                     %   for the Backend Health panel; rendered from the
                                     %   enriched listBackends response.
        % ── Phase 3 dashboard refactor (project switcher + smart CTA) ────
        DashProjectDropdown          % uidropdown in toolbar — switch active project
        DashNextStepButton           % uibutton in KPI strip slot 4 — context-aware CTA
                                     %   that adapts text + target per pipeline_stage
        % ── Phase 4 dashboard refactor (live auto-refresh + stats today) ─
        DashAutoRefreshTimer         % MATLAB timer — refreshes the dashboard every
                                     %   30 s while visible; self-terminates on nav-away
        DashStatsSubline             % uilabel inside Activity Trend panel showing
                                     %   "Today: N jobs · M.M h compute · K failed"
        % ── Phase 7 dashboard refactor (empty state + delta indicator) ───
        DashOuterGrid                % handle to the dashboard's outer uigridlayout so
                                     %   the VM can toggle RowHeight on the empty-state
                                     %   row at runtime (show/hide cleanly)
        DashEmptyStatePanel          % the welcome hero card shown for fresh projects
                                     %   (zero circuits, zero recent jobs); hidden when
                                     %   any meaningful data exists
        % ── Phase 9 dashboard polish (greeting + readiness hints) ────────
        DashGreetingLabel            % uilabel in toolbar — dynamic "Welcome back, X ·
                                     %   Last refreshed HH:MM · N projects · M circuits"
                                     %   replaces the meta-jargon "Storyboard landing
                                     %   summary" subtitle
        DashReadinessHints           % {1×4} cell of uilabel handles for empty-state
                                     %   hints under each Run Readiness KPI value
                                     %   ("Upload a circuit" / "Run prediction" / …)
        DashActivityBars             % bar() handle for the Job Submissions chart so
                                     %   per-bar CData (today accent vs muted others)
                                     %   can be set from onJobsForTrend
    end

    % ── Notes tab ─────────────────────────────────────────────────────────────
    properties
        NotesArea
        NotesRunbookTable
        SaveNotesButton
        ClearNotesButton
    end

    % ── Circuits tab ─────────────────────────────────────────────────────────
    properties
        CircuitsTable
        CircuitsSearchField
        CircuitsEmptyStateLabel    % banner above the table that explains why no rows are visible
        CircuitsPageLabel
        CircuitsPrevBtn
        CircuitsNextBtn
        CircuitsComposerBtn
        CircuitsUploadBtn
        CircuitsPopupPanel
        CircuitsPopupEditBtn
        CircuitsPopupDeleteBtn
    end

    % ── Upload tab ────────────────────────────────────────────────────────────
    properties
        UploadFileField
        BrowseButton
        UploadButton
        UploadFormatDropdown
        CircuitNameField
        CircuitCategoryDropdown
        CircuitMetadataArea
        CircuitPreviewArea
        CircuitStatsArea
        UploadActiveProjectLabel
        UploadCircuitsTable
        UploadRefreshCircuitsBtn
        UploadDeleteCircuitBtn
    end

    % ── Analysis tab ──────────────────────────────────────────────────────────
    properties
        AnalysisCircuitDropdown
        AnalyzeButton
        AnalysisUploadBtn       % Upload bridge button moved into the toolbar (M7)
        % Tier B exports — Download JSON dumps the analyze response
        % via Exporter.toJsonFile; Generate Report bridges to the
        % Reports screen whose loadReportsList → seedReportTitle
        % pre-fills the title for the active circuit. M7: both
        % buttons start disabled and only enable after a successful
        % AnalysisVm.applyAnalysisData; disabled again on circuit
        % change so they never export stale data.
        AnalysisDownloadJsonBtn
        AnalysisGeneratePdfBtn
        % ── Tier C KPI row (M3) ─────────────────────────────────────
        % 5 cards across the top of the Analysis screen showing key
        % characterisation numbers from the analyze response.
        AnalysisKpiQubitsVal
        AnalysisKpiQubitsSub
        AnalysisKpiDepthVal
        AnalysisKpiDepthSub
        AnalysisKpiGatesVal
        AnalysisKpiGatesSub
        AnalysisKpiTwoQVal
        AnalysisKpiTwoQSub
        AnalysisKpiParaVal
        AnalysisKpiParaSub
        FeatureTree
        AnalysisFeatureArea
        SimilarityTable
        AnalysisCompareArea
        QVHeatmapAxes
        QVHeatmapGrid             % parent grid for the lazy uiaxes (built on first paint)
        QVHeatmapPlaceholder      % uilabel placeholder until the uiaxes materialises
        QVInfoLabel
        % Quantum Monte Carlo Simulation (Quantum Amplitude Estimation)
        %   Hosted inside the modal popup built by DialogBuilder.buildQmcDialog;
        %   the launcher button lives on the Analysis toolbar.
        QmcOpenButton
        QmcDialog                  % uifigure handle while the popup is open
        QmcModeDropdown
        QmcBackendField
        QmcShotsField
        QmcEpsilonField
        QmcConfidenceField
        QmcRiskDropdown
        QmcFooterGrid           % M9 — uigridlayout handle of the dialog footer; the VM resizes its columns to reveal/hide export buttons
        QmcRunButton
        QmcDownloadResultsBtn   % M9 — exports app.QmcLastResult to .json; hidden until Run QMC succeeds
        QmcReportButton
        QmcDownloadLogButton    % Download IBM Runtime execution log (runtime mode only)
        QmcKpiLabels
        QmcGreeksLabels      % Delta / Gamma / Vega / Theta / Rho labels
        QmcPathAxes          % Loss / path distribution with VaR threshold
        QmcConvergenceAxes   % QMC 1/N vs classical MC 1/√N
        QmcCdfAxes           % Cumulative loss distribution
        QmcAmpAxes           % Amplitude-estimation bar chart
        QmcZneAxes           % Zero-noise extrapolation curve
        % Advanced controls
        QmcMitigationDropdown
        QmcSpotField
        QmcStrikeField
        QmcVolField
        QmcRateField
        QmcTenorField
        QmcOptionTypeDropdown
        QmcNotionalField
        QmcLastResult = []   % struct cache of most recent QMC response
        QmcActiveJobId = ''  % job_id of the currently-polling async QMC job ('' when idle)
        QmcActiveTaskId = '' % BackgroundTaskManager id for the in-flight QMC task ('' when idle)
        QmcPollTimer = []    % MATLAB timer driving QMC job polling (empty when idle)
        QmcBackendMeta = []  % struct array {name, num_qubits} for the loaded QMC backend dropdown — used by the runtime-mode pre-flight width check
        QmcBanner = []       % uigridlayout banner shown above the QMC body when the active circuit cannot run in any mode
        QmcBannerLabel = []  % uilabel inside the banner — text refreshed by AnalysisViewModel.applyQmcViability
    end

    % ── Quantum Error Mitigation Analysis popup (Phase 6.x) ───────────────────
    %   Hosted inside the modal popup built by
    %   DialogBuilder.buildErrorMitigationDialog; the launcher button sits
    %   next to QmcOpenButton on the Analysis screen toolbar.  No backend
    %   changes — every panel reads cached QAE / cutting / mitigation data
    %   that is already exposed by the FastAPI services.
    properties
        EmOpenButton
        EmDialog                    % uifigure handle while popup is open
        EmCircuitInfoLabel          % "qubits / depth / 2Q" header line on form
        EmBackendDropdown
        EmPrimitiveDropdown         % sampler / estimator
        EmBaseShotsField
        EmLevelDropdown             % populated from /api/mitigation/levels
        EmZneFactorsField           % editfield, comma-separated noise factors
        EmExtrapolatorDropdown      % linear / polynomial / exponential / richardson
        EmDdSequenceDropdown        % XpXm / XY4 / XY8
        EmTwirlGatesCheckbox
        EmTwirlMeasureCheckbox
        EmTemCheckbox
        EmAlsoRunRawCheckbox
        EmCostSummaryLabel          % live one-line summary from /api/mitigation/estimate
        EmConflictLabel             % notes / conflicts banner (non-empty -> red)
        EmKpiLabels                 % cell{1,5}: qubits, depth, 2Q, gammabar, advantage
        EmZneAxes                   % measured ZNE curve (cached qae.mitigation_curve)
        EmGammaDepthAxes            % gammabar^depth feasibility curve
        EmOverheadCutsAxes          % cutting overhead vs target k sweep
        EmTechniqueTable            % per-technique comparison table
        EmHistogramAxes             % raw vs mitigated bitstring distribution
        EmRecommendationLabel       % auto-picked stack, parented to a card panel
        EmStatusBanner              % "predicted only" / "no result" microcopy
        EmRunButton                 % refresh estimate + render
        EmApplyButton               % navigate to Benchmark with prefill
        EmExportButton              % export bundle JSON
        EmReportButton              % generate report (reuses ReportSvc)
        EmLevels = []               % cached /api/mitigation/levels response
        EmEstimateBundle = []       % cell of {techniqueId, label, plan, cost} per row
        EmQaeCached = []            % cached QAE result struct (or [] if none)
        EmCuttingCached = []        % cached /cutting/analyze sweep
        EmCircuitMeta = []          % qubits / depth / 2Q / etc. from CircuitSvc.getCircuit
        EmCachedCalibration = []    % {backend, data} cache fetched alongside the
                                    %   estimate sweep so renderEmKpis +
                                    %   renderEmGammaDepthCurve don't issue their
                                    %   own sync calibration GETs.
        EmCalInFlightBackend = ''   % name of the backend whose calibration is
                                    %   currently being fetched on a background
                                    %   pool (set by AnalysisViewModel
                                    %   .dispatchEmCalibrationFetch). Used as a
                                    %   per-backend dedup so concurrent renders
                                    %   don't fan out duplicate IBM round-trips.
    end

    % ── Backends tab ──────────────────────────────────────────────────────────
    properties
        BackendTable
        BackendStatusArea
        RefreshBackendsButton
        SelectBackendButton
        SubmitPoolButton        % Fan-out submit to every backend in IBM_BACKENDS
        BackendKpiLabels
        OverviewKpiLabels = {}        % {1×4} cell of uilabel value handles
                                      % for the Telemetry > Overview tab's
                                      % KPI strip: Total backends, Operational,
                                      % Top width (qubits), Latest calibration.
        BackendsSearchField
        BackendsPrevBtn
        BackendsNextBtn
        BackendsPageLabel
        BackendsPopupPanel
        % C2.B1 — calibration sparkline column + Telemetry tab strip.
        CalibrationHistoryCache = []  % struct keyed by makeValidName(backend) → response
        BackendSparklineGrid          % overlay uigridlayout that mirrors the BackendTable rows
        BackendSparklineAxes          % struct keyed by makeValidName(backend) → uiaxes per row
        % Per-Qubit / History / Topology tabs were removed — they
        % reproducibly broke R2025b uifigure CEF click dispatch.
        % Only the Overview content remains in the right-side panel.
    end

    % ── Benchmark tab ─────────────────────────────────────────────────────────
    properties
        BenchmarkCircuitDropdown
        BenchmarkBackendSelect
        BenchmarkShotsField
        BenchmarkOptField
        BenchmarkMitigationDropdown
        BenchmarkStrategyDropdown
        BenchmarkRunButton
        BenchmarkSubmitButton   % Submit benchmark to IBM (POST /api/jobs/submit)
        BenchmarkStatusArea
        BenchmarkStrategyTable
    end

    % ── Prediction tab ────────────────────────────────────────────────────────
    properties
        PredictButton
        PredictionCircuitDropdown   % Circuit selector on the Prediction toolbar
        PredictionBackendDropdown   % Backend selector on the Prediction toolbar
        PredictionTable
        PredictionDistAxes      % Probability distribution bar chart
        PredictionDistGrid              % parent grid for the lazy uiaxes
        PredictionDistPlaceholder       % uilabel placeholder until the uiaxes materialises
        PredictionBudgetAxes    % Error budget breakdown bar chart
        PredictionBudgetGrid            % parent grid for the lazy uiaxes
        PredictionBudgetPlaceholder     % uilabel placeholder until the uiaxes materialises
        PredictionHeadlineLabel % Top-backend recommendation callout
        SubmitJobButton         % Submit to IBM Quantum (POST /api/jobs/submit)
    end

    % ── Jobs tab ──────────────────────────────────────────────────────────────
    properties
        JobsSearchField              % uieditfield — Job ID / Circuit substring filter
        JobsRefreshButton
        JobsTable
        CancelJobButton
        PauseJobButton
        JobStatusArea
        JobLogsArea
        JobsPrevButton          % Pagination: previous page
        JobsNextButton          % Pagination: next page
        JobsPageLabel           % Pagination footer text
        % Right-click context menu on JobsTable. Built in JobsScreen,
        % enable/disable driven by JobsViewModel.onContextMenuOpening
        % from the right-clicked row's Status column.
        JobsContextMenu
        JobsCtx_ViewResults
        JobsCtx_DetailedAnalysis
        JobsCtx_Cancel
        JobsCtx_CopyJobId
        JobsCtx_CopyIbmJobId
        JobsCtx_OpenIbm
    end

    % ── Results tab ───────────────────────────────────────────────────────────
    properties
        ResultsTable
        ResultJsonArea
        ResultsDistTable
        % Phase 4.2: Mitigated/Raw toggle row (hidden by default,
        % populated by ResultsViewModel.applySiblingToggle when the
        % loaded batch carries a non-empty sibling_group_id).
        ResultsMitigationToggleGrid  % parent uipanel — Visible toggled
        ResultsMitigatedToggleBtn    % left half of the segmented control
        ResultsRawToggleBtn          % right half
        CuttingBatchesTable    % Cutting Batches list on the Results screen
        SelectedBatchId = ""   % Most recently picked cutting batch row
        % Right-click context menu on CuttingBatchesTable. Built in
        % ResultsScreen, enable/disable driven by
        % ResultsViewModel.onBatchContextMenuOpening from the row's
        % Status column.
        BatchesContextMenu
        BatchesCtx_ViewReconstruction
        BatchesCtx_DetailedAnalysis
        BatchesCtx_DownloadJson
        BatchesCtx_GenerateReport
        % Tier B exports — Download JSON dumps /api/jobs/{id}/results
        % via Exporter.toJsonFile; Generate Report bridges to the
        % Reports screen whose loadReportsList → seedReportTitle
        % pre-fills the title for the active job.
        ResultsDownloadJsonBtn
        ResultsGeneratePdfBtn
        % ── Tier B/C visual redesign widgets (M2) ───────────────────
        % Identity strip across the top of the Results screen.
        ResultsHeroTitle              % "Quantum Run Report"
        ResultsHeroSubtitle           % "<circuit> · <backend> · <shots>"
        ResultsHeroJobLine            % "Job <id> · Run <timestamp>"
        ResultsStatusPill             % colour-coded uilabel pill
        % 5 KPI cards (value + ideal sub-label).
        ResultsKpiFidelityVal
        ResultsKpiFidelitySub
        ResultsKpiSuccessVal
        ResultsKpiSuccessSub
        ResultsKpiDominantVal
        ResultsKpiDominantSub
        ResultsKpiTwoQVal
        ResultsKpiTwoQSub
        ResultsKpiReadoutVal
        ResultsKpiReadoutSub
        % Distribution + histogram row.
        ResultsHistogramAxes          % uiaxes — bars + ideal overlay
        ResultsHistogramGrid          % parent grid for the lazy uiaxes
        ResultsHistogramPlaceholder   % uilabel placeholder until the uiaxes materialises
        % Mitigation / Timing / Context tiles (cell arrays of uilabels).
        ResultsMitigationLabels = {}  % {LevelVal, TwirlingVal, DDVal, ZNEVal}
        ResultsTimingLabels    = {}   % {QueuedVal, RunVal, TotalVal}
        ResultsContextLabels   = {}   % {ProjectVal, SubmittedVal, UserVal}
    end

    % ── Detailed Analysis tab ─────────────────────────────────────────────────
    properties
        CompareAxes
        CompareGrid                   % parent grid for the lazy uiaxes
        ComparePlaceholder            % uilabel placeholder until the uiaxes materialises
        ErrorHeatmapAxes
        ErrorHeatmapGrid              % parent grid for the lazy uiaxes
        ErrorHeatmapPlaceholder       % uilabel placeholder until the uiaxes materialises
        TemporalAxes
        TemporalGrid                  % parent grid for the lazy uiaxes
        TemporalPlaceholder           % uilabel placeholder until the uiaxes materialises
        QubitAxes
        QubitGrid                     % parent grid for the lazy uiaxes
        QubitPlaceholder              % uilabel placeholder until the uiaxes materialises
        RBDecayAxes
        RBDecayGrid                   % parent grid for the lazy uiaxes
        RBDecayPlaceholder            % uilabel placeholder until the uiaxes materialises
        DetailedInsightArea
        RefreshCompareButton
        RefreshHeatmapButton
        RefreshTemporalButton
        RefreshQubitButton
        RefreshRBButton
        DetailedAnalysisCircuitDropdown   % Circuit selector on the Detailed Analysis toolbar
        DetailedAnalysisAnalyzeButton     % Analyze button: re-runs all 5 detailed charts for the selected circuit
        % Tier B exports — Download JSON dumps the detailed-results
        % response via Exporter.toJsonFile; Generate Report bridges
        % to Reports.
        DetailedDownloadJsonBtn
        DetailedGeneratePdfBtn
        % ── Tier C KPI row (M3) ─────────────────────────────────────
        % 5 cards across the top of the Detailed Analysis screen
        % showing per-job characterisation numbers (fidelity / drift
        % / qubit count / RB decay / outlier count) populated from
        % whichever detail-fetch endpoint runs on screen entry.
        DetailedKpiFidelityVal
        DetailedKpiFidelitySub
        DetailedKpiDriftVal
        DetailedKpiDriftSub
        DetailedKpiQubitsVal
        DetailedKpiQubitsSub
        DetailedKpiRBVal
        DetailedKpiRBSub
        DetailedKpiOutliersVal
        DetailedKpiOutliersSub
    end

    % ── Benchmark Dashboard tab ──────────────────────────────────────────────
    properties
        BenchmarkBackendDropdown
        BenchmarkRefreshButton
        BenchmarkKpiLabels
        BenchmarkKpiUnits           % cell{5} — secondary small text under each KPI value
        BenchmarkStatusLabel        % "N jobs · M preds · cal 18 h old · source: ibm_runtime"
        BenchmarkSourceBadge        % small tinted badge in the toolbar showing metrics source
        VolumetricAxes
        VolumetricGrid                 % parent grid for the lazy uiaxes
        VolumetricPlaceholder          % uilabel placeholder until the uiaxes materialises
        ScorecardAxes
        ScorecardGrid                  % parent grid for the lazy polaraxes
        ScorecardPlaceholder           % uilabel placeholder until the polaraxes materialises
        CalibrationAxes
        CalibrationGrid                % parent grid for the lazy uiaxes
        CalibrationPlaceholder         % uilabel placeholder until the uiaxes materialises
        RegressionAxes
        RegressionGrid                 % parent grid for the lazy uiaxes
        RegressionPlaceholder          % uilabel placeholder until the uiaxes materialises
    end

    % ── Circuit Cutting tab ──────────────────────────────────────────────────
    properties
        CuttingCircuitDropdown      % Circuit picker (avoids having to set it elsewhere)
        CuttingModeDropdown         % Automatic / Assisted / Manual
        CuttingPresetDropdown       % Preset registry (Option C slot)
        CuttingTargetKSpin          % Spinner: force target_k (0 = auto)
        CuttingCompatBanner         % Red/amber banner shown for un-cuttable circuits
        CuttingMainGrid             % Outer grid handle so VM can collapse the banner row
        CuttingAnalyzeBtn           % Analyze Cuts button (toggled enable on incompat)
        CuttingRunBtn               % Run Cutting button (toggled enable on incompat)
        CuttingStatusLabel          % Status banner (kept for back-compat / VM hooks)
        CuttingMitigationLabel      % One-line "Mitigation: <Level> · ~Nx
                                    % shots · est. Hms" populated by
                                    % CircuitCuttingViewModel.applyAnalyze
                                    % from POST /api/mitigation/estimate.
                                    % Right-aligned on the toolbar's
                                    % status row.
        CuttingMitigationDropdown   % Phase 3.1: ladder-level selector
                                    % (Raw / Standard / Aggressive / TEM
                                    % / Custom). Populated from
                                    % GET /api/mitigation/levels with a
                                    % hardcoded fallback. Drives the
                                    % create-batch body's
                                    % mitigation_level field at Run
                                    % time and re-triggers the cost-
                                    % preview line on every change.
        % KPI strip — one big number per metric, IBM-Quantum-style at-a-glance
        CuttingKpiKValue            % Subcircuits count
        CuttingKpiOverheadValue     % Sampling overhead (formatted scientific)
        CuttingKpiQubitsValue       % Per-subcircuit qubit split, e.g. "19+19+1"
        CuttingKpiFeasibilityChip   % Pill label "● OK" / "● Refused"
        CuttingKpiFeasibilityPanel  % Backing panel (so we can recolor the pill bg)
        % Cut Plan card — structured metric rows, replaces the old text dump
        CuttingPlanKValue           % "k = N" detail row
        CuttingPlanCutsValue        % "Cuts detected"
        CuttingPlanOverheadValue    % "Sampling overhead" (scientific)
        CuttingPlanLog10Value       % "log10 overhead"
        CuttingPlanPerSubValue      % "Per-subcircuit qubits"
        CuttingPlanReasonLabel      % Wrapped feasibility reason text (only when infeasible)
        CuttingPlanText             % Hidden legacy textarea — kept so VM back-compat path works
        % Backend Assignments card — rebuilt per render with one row per subcircuit
        CuttingBackendGrid          % Parent uigridlayout we repopulate
        CuttingBackendEmptyLabel    % Shown until Analyze Cuts produces a plan
        CuttingBackendText          % Hidden legacy textarea — kept for back-compat
        CuttingObservablesText      % Pauli-string editor
        CuttingObservablesWarning   % Hardware-aware coherence warning shown
                                    % above the textarea when the analyze
                                    % response carries a non-empty
                                    % coherence_warning field (n>50 cat /
                                    % GHZ on real hardware — weight-N
                                    % witnesses sit at noise floor; only
                                    % weight-2 ZZ correlators are meaningful).
        CuttingDistCheckbox         % opt-in: also reconstruct bitstring distribution
        CuttingAlsoRunRawCheckbox   % Phase 3.3: when checked, the cutting
                                    % batch service spawns a sibling Raw
                                    % batch (mitigation_level=0)
                                    % alongside the primary so the
                                    % Results screen can render
                                    % mitigated-vs-raw side-by-side.
                                    % Routed via the also_run_raw field
                                    % on CreateBatchRequest.
        CuttingResultsLabel         % Reconstructed expectations display
        CuttingResultsEmptyLabel    % Pretty empty-state when no batch has run yet
        % Post-run action bar — quick jumps from a finished cutting batch
        % to the four downstream artifacts (job list, results screen,
        % reconstruction popup, detailed analysis). Each button is
        % gated by CircuitCuttingViewModel.refreshActionButtons based
        % on batch state (none / dispatched / partly-complete / done).
        CuttingActionsHeader              % "Batch <id> · Status: <status>" line
        CuttingJobsBtn                    % Jump to Jobs screen
        CuttingResultsBtn                 % Jump to Results screen
        CuttingViewReconBtn               % Open reconstruction popup
        CuttingDetailedAnalysisBtn        % Jump to Detailed Analysis screen
    end

    % ── QEC Simulation tab ────────────────────────────────────────────────────
    properties
        QecCodeDropdown
        QecInitialStateDropdown
        QecThetaSpinner
        QecThetaLabel
        QecPhiSpinner
        QecPhiLabel
        QecDistanceSpinner
        QecDistanceLabel
        QecNoiseDropdown
        QecErrorProbSlider
        QecErrorProbLabel
        QecRoundsSpinner
        QecTrialsSpinner
        QecFidelityAxes
        QecFidelityGrid                % parent grid for the lazy uiaxes
        QecFidelityPlaceholder         % uilabel placeholder until the uiaxes materialises
        QecSyndromeAxes
        QecSyndromeGrid                % parent grid for the lazy uiaxes
        QecSyndromePlaceholder         % uilabel placeholder until the uiaxes materialises
        QecSuccessAxes
        QecSuccessGrid                 % parent grid for the lazy uiaxes
        QecSuccessPlaceholder          % uilabel placeholder until the uiaxes materialises
        QecResultsTable
        QecRunButton
        QecSweepButton
        QecCompareButton
        QecClearButton
        % ── Phase 1+2: backend/circuit selectors so QEC simulation
        %    differs per hardware target and per circuit instead of
        %    showing the same parametric output regardless of
        %    selection. Calibration drives auto-seed of the Error
        %    Probability slider AND a per-qubit error vector for
        %    the Monte Carlo path.
        QecCircuitDropdown
        QecBackendDropdown
        QecContextLabel              % single condensed line summarising
                                     % selected backend cal + circuit profile
    end

    % ── QEC Visualization tab ─────────────────────────────────────────────────
    properties
        QecBlochAxes
        QecBlochGrid                   % parent grid for the lazy uiaxes
        QecBlochPlaceholder            % uilabel placeholder until the uiaxes materialises
        QecLatticeAxes
        QecLatticeGrid                 % parent grid for the lazy uiaxes
        QecLatticePlaceholder          % uilabel placeholder until the uiaxes materialises
        QecDecayAxes
        QecDecayGrid                   % parent grid for the lazy uiaxes
        QecDecayPlaceholder            % uilabel placeholder until the uiaxes materialises
        QecErrorWeightAxes
        QecErrorWeightGrid             % parent grid for the lazy uiaxes
        QecErrorWeightPlaceholder      % uilabel placeholder until the uiaxes materialises
        QecRefreshBlochButton
        QecRefreshLatticeButton
        QecAnimateButton
        % ── Phase 1+2: same selector pattern; lattice distance
        %    auto-scales with backend qubit count (16→3, 27→5,
        %    65→7, 156→11) so a 156-qubit backend draws a
        %    representative d=11 lattice instead of the demo d=3.
        QecVizCircuitDropdown
        QecVizBackendDropdown
        QecVizContextLabel
    end

    % ── Reports tab ───────────────────────────────────────────────────────────
    properties
        ReportTitleField
        ReportFormatDropdown
        ReportSectionsField
        GenerateReportButton
        ReportStatusArea
        OpenReportButton
        GeneratedReportList          % legacy uilistbox handle (kept = [] now)
        % ── Phase 6.5 redesign — KPI strip + table-based library ──────
        ReportsKpiTotal              % uilabel: total report count
        ReportsKpiPdf                % uilabel: PDF count
        ReportsKpiHtml               % uilabel: HTML count
        ReportsKpiLatest             % uilabel: human-readable "N min ago"
        ReportsTable                 % uitable: Format / Title / Created / Status
        ReportsSearchField           % uieditfield: client-side filter
        ReportsRefreshBtn            % uibutton: manual reload
        ReportsDetailLabel           % legacy uilabel handle (now [] — Selected line removed)
        ReportsCachedItems = {}      % cell of report metadata structs (cache
                                     % for search filter without HTTP round-trip)
        % ── Phase 6.6 — pagination + right-click popup ────────────────
        ReportsCurrentPage = 1       % 1-indexed current page
        ReportsPageSize    = 20      % items per page (server skip/limit)
        ReportsPrevBtn               % uibutton: prev page
        ReportsNextBtn               % uibutton: next page
        ReportsPageIndicator         % uilabel: "Page N · Y items"
        ReportsPopupPanel            % uipanel: right-click context menu
                                     % (built lazily by PopupMenuManager.buildReportsPopup)
    end

    % ── Settings tab ──────────────────────────────────────────────────────────
    properties
        IbmEmailField
        IbmApiTokenField
        IbmChannelDropdown
        IbmInstanceField
        SettingsBaseUrlField
        DefaultShotsField
        DefaultOptField
        SettingsTimeoutField
        SettingsLogLevelDropdown
        SettingsMitigationLevelDropdown   % Phase 3.6: default-level picker
                                          % on Settings → Defaults dialog.
                                          % Persists to user_preferences as
                                          % default_mitigation_level and
                                          % seeds app.State.preferred-
                                          % MitigationLevel.
        EmailNotifyCheck
        NotifyEmailField
        AlertThresholdDropdown
        SaveSettingsButton
        VerifyIbmButton
        SettingsStatusArea
        ServerIbmStatusArea   % Read-only text area — shows server IBM runtime config
        ServerIbmConfig = struct('channel','','instance','','backends',{{}},'has_token',false)
    end

    % ── Constructor / destructor ──────────────────────────────────────────────
    methods
        function app = QTAUWorkbenchApp()
            Logger.info('QTAUWorkbenchApp', '=== QTAUWorkbenchApp initializing ===');

            % Load the persisted theme BEFORE any UI is built so every
            % panel, label, and overlay picks up the correct palette on
            % first render (no initial flash-of-light-theme for Dark users).
            Theme.setActive(Theme.loadPersisted());

            % Apply log_level from app.properties (INFO by default in
            % the shipped config). Done before AppState/Services come
            % up so the boot-time and steady-state HTTP request
            % logging respects the configured threshold — the prior
            % DEBUG default fprintf'd a line per HTTP request, which
            % on data-heavy screens (Backends fan-out) flooded the
            % console with ~80 lines per visit and contributed to
            % the perceived sluggishness.
            try; Logger.reload(); catch; end

            app.State         = AppState();
            Logger.info('QTAUWorkbenchApp', 'AppState created — baseUrl: %s', char(app.State.baseUrl));

            % Service initialization (delegated to ServiceContainer)
            app.Services      = ServiceContainer(app.State.baseUrl);
            app.Client        = app.Services.Client;
            app.AuthSvc       = app.Services.AuthSvc;
            app.CircuitSvc    = app.Services.CircuitSvc;
            app.BackendSvc    = app.Services.BackendSvc;
            app.JobSvc        = app.Services.JobSvc;
            app.ProjectSvc    = app.Services.ProjectSvc;
            app.PredictionSvc = app.Services.PredictionSvc;
            app.ReportSvc     = app.Services.ReportSvc;
            app.SettingsSvc   = app.Services.SettingsSvc;
            app.QecEngine     = app.Services.QecEngine;
            app.BenchmarkSvc  = app.Services.BenchmarkSvc;
            app.QmcSvc        = app.Services.QmcSvc;
            app.CuttingSvc    = app.Services.CuttingSvc;
            app.MitigationSvc = app.Services.MitigationSvc;

            % Kick the parallel-pool warm-up as soon as services are
            % wired — the pool acquisition is the slow part (1.3–3.9 s
            % cold on macOS) and parfeval(@()true) runs in the
            % background. By the time the user reads the login dialog
            % and submits credentials, the pool is already warm and the
            % first real AsyncRunner.run() lands on a hot worker.
            % Idempotent; the original (now redundant) call at the end
            % of buildUI is left in place as a no-op safety net.
            AsyncRunner.warmUp();

            % BackgroundTaskManager has to exist BEFORE buildUI because
            % LayoutBuilder.buildHeader mounts the TasksIndicator which
            % addlisten's to its TasksChanged event.
            app.BackgroundTasks = BackgroundTaskManager();

            Logger.info('QTAUWorkbenchApp', 'Services ready — creating WelcomeVm (lazy init for others)');
            app.WelcomeVm = WelcomeViewModel(app);

            app.buildUI();

            % NotificationCenter parents its toast panel to app.UIFigure
            % so it has to come up after buildUI created the figure.
            try
                app.Notifications = NotificationCenter(app);
            catch ME
                Logger.warn('QTAUWorkbenchApp', ...
                    'NotificationCenter init failed: %s', ME.message);
            end

            app.logEvent('UI', 'QTAUWorkbenchApp started');
            NavigationManager.forceInitialLayout(app);
            Logger.info('QTAUWorkbenchApp', '=== QTAUWorkbenchApp ready ===');
        end

        function delete(app)
            try
                if app.State.isAuthenticated() && ~isempty(app.AuthSvc)
                    app.AuthSvc.logout(app.State.authToken);
                    app.State.authToken = "";
                end
            catch ME
                Logger.debug('QTAUWorkbenchApp', 'Logout on close: %s', ME.message);
            end
            % LoginDialog is kept alive across the session for reuse;
            % tear it down now since the app is exiting.
            try
                if ~isempty(app.LoginDialog) && isvalid(app.LoginDialog)
                    delete(app.LoginDialog);
                end
            catch
            end
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch ME
                Logger.debug('QTAUWorkbenchApp', 'Cleanup: %s', ME.message);
            end
        end
    end

    % ── Thin delegation methods (preserve existing caller contracts) ──────────
    %   Screens, ViewModels, and DialogBuilder call these on app.* — each
    %   forwards to the appropriate helper class.
    methods

        % -- Navigation (→ NavigationManager) ----------------------------------
        function onSelectSection(app, key)
            NavigationManager.onSelectSection(app, key);
        end

        function panel = createSectionPage(app, key)
            panel = NavigationManager.createSectionPage(app, key);
        end

        function ensureVm(app, key)
            NavigationManager.ensureVm(app, key);
        end

        function fresh = isScreenFresh(app, vm, ttl)
            fresh = NavigationManager.isScreenFresh(vm, ttl);
        end

        function onToggleNav(app)
            NavigationManager.onToggleNav(app);
        end

        function onResizeUI(app)
            NavigationManager.onResizeUI(app);
        end

        % -- Overlays / logging (→ OverlayManager) ----------------------------
        function showLoading(app, msg, showTimer, bgTaskId)
            if nargin < 2; msg = 'Loading...'; end
            if nargin < 3; showTimer = false; end
            if nargin < 4; bgTaskId = ''; end
            OverlayManager.showLoading(app, msg, showTimer, bgTaskId);
        end

        function hideLoading(app)
            OverlayManager.hideLoading(app);
        end

        % runInBackground  Dismiss the loading overlay while leaving the
        %   underlying poll alive in app.BackgroundTasks. Wired as the
        %   ButtonPushedFcn of the "Run in background" button rendered
        %   over the overlay when a registered task is in flight. taskId
        %   is informational — the polling timer is owned by
        %   BackgroundTaskManager, so simply hiding the overlay does not
        %   stop the underlying server-side job from progressing.
        function runInBackground(app, taskId)
            try; app.hideLoading(); catch; end
            % Release the QMC overlay binding when the backgrounded task
            % matches the active QMC binding. Without this, the QMC
            % PollingRunner's onQmcProgress tick (every 3 s) sees
            % QmcActiveTaskId == taskId, passes its strcmp gate, and
            % re-calls app.showLoading(...) — which re-pops the modal
            % overlay seconds after the operator clicked "Run in
            % background". The poll itself stays alive (managed by
            % BackgroundTasks); only the overlay binding is dropped,
            % fulfilling the run-in-background promise.
            try
                if ~isempty(taskId) && ~isempty(app.QmcActiveTaskId) ...
                        && strcmp(char(app.QmcActiveTaskId), char(taskId))
                    app.QmcActiveJobId  = '';
                    app.QmcActiveTaskId = '';
                end
            catch
            end
            try
                if ~isempty(taskId) && ~isempty(app.BackgroundTasks)
                    t = app.BackgroundTasks.findById(taskId);
                    if ~isempty(t)
                        app.logEvent('TASK', sprintf( ...
                            'Task %s (%s) moved to background', ...
                            char(taskId), char(t.displayName)));
                    end
                end
            catch
            end
        end

        % runAsyncWithLoading  Standardized show + AsyncRunner + auto-hide.
        %
        %   The recommended idiom for any VM action that does asynchronous
        %   work behind a loading overlay.  Replaces the four-line
        %   show / AsyncRunner.run(work, onOk, onErr) / hide-in-onOk /
        %   hide-in-onErr boilerplate that was duplicated across ~150
        %   sites and was the source of "forgot to hide on the error
        %   path" bugs that left a stuck overlay.
        %
        %   Pattern:
        %     app.runAsyncWithLoading( ...
        %         Labels.get('loading_circuits_list', 'Loading circuits...'), ...
        %         @() svc.listCircuits(token), ...
        %         @(data) obj.onLoaded(data), ...
        %         @(ME)   obj.onError(ME));
        %
        %   onOk and onErr may be empty ([]) for fire-and-forget work.
        %   The overlay is hidden BEFORE either user callback runs, so
        %   the callback can safely call showLoading again with a
        %   different message (chained operations).
        function runAsyncWithLoading(app, msg, work, onOk, onErr)
            if nargin < 4; onOk  = []; end
            if nargin < 5; onErr = []; end
            app.showLoading(msg);
            wrappedOk  = @(data) QTAUWorkbenchApp.dispatchAfterHide(app, onOk,  data);
            wrappedErr = @(ME)   QTAUWorkbenchApp.dispatchAfterHide(app, onErr, ME);
            AsyncRunner.run(work, wrappedOk, wrappedErr);
        end

        % runSyncWithLoading  Standardized show + sync work + auto-hide.
        %
        %   For synchronous work that needs an overlay (rare, but used by
        %   some seed/import paths). hideLoading is wired through
        %   onCleanup so it fires even if `fn` errors or is interrupted
        %   by Ctrl-C.
        %
        %   Pattern:
        %     app.runSyncWithLoading( ...
        %         Labels.get('loading_clearing_cache', 'Clearing cache...'), ...
        %         @() obj.purgeLocalCache());
        function runSyncWithLoading(app, msg, fn)
            app.showLoading(msg);
            cleanup = onCleanup(@() app.hideLoading()); %#ok<NASGU>
            fn();
        end

        function showAuthOverlay(app)
            OverlayManager.showAuthOverlay(app);
        end

        function hideAuthOverlay(app)
            OverlayManager.hideAuthOverlay(app);
        end

        function showError(app, context, ME)
            OverlayManager.showError(app, context, ME);
        end

        % -- Theming ----------------------------------------------------------
        function applyTheme(app, themeName)
            % Hot-swap the active theme and rebuild every themed surface.
            % AppState (auth token, project id, etc.) is preserved because
            % it lives off the UI tree. Screens rebuild through their
            % existing Screen*(app) functions, which read Theme.* to pick
            % up the new palette.
            app.logEvent('CONFIG', sprintf('Theme change → %s', char(themeName)));
            Theme.setActive(themeName);

            % 0. Flip MATLAB's built-in figure Theme first — this cascades
            %    the base styling (scrollbars, focus rings, default
            %    uitable/dropdown/editfield/axes colors) across all
            %    existing components BEFORE we start our manual repaint.
            %    Anything we miss in the rebuild still comes out correct.
            Theme.applyFigureMode(app.UIFigure, themeName);

            currentKey = 'Welcome';
            try
                if ~isempty(app.NavList) && isvalid(app.NavList)
                    currentKey = char(app.NavList.Value);
                end
            catch; end

            % 1. Close any modal dialogs (the Display settings dialog is
            %    itself usually the trigger — re-opening in the new theme
            %    is a cleaner UX than trying to live-repaint it).
            try
                modals = findall(groot, 'Type', 'figure', 'WindowStyle', 'modal');
                for i = 1:numel(modals)
                    if isvalid(modals(i)) && modals(i) ~= app.UIFigure
                        delete(modals(i));
                    end
                end
            catch ME; Logger.debug('QTAUWorkbenchApp', 'close modals: %s', ME.message); end

            % 2. Main figure + root chrome (header bar, nav rail, section
            %    title card, divider, toggle button, header user menu).
            try
                LayoutBuilder.repaintChrome(app);
            catch ME; Logger.debug('QTAUWorkbenchApp', 'chrome repaint: %s', ME.message); end

            % 3. Nav HTML re-rendered from the palette.
            try
                NavigationManager.renderNavHtml(app, currentKey, app.NavCollapsed);
            catch ME; Logger.debug('QTAUWorkbenchApp', 'nav repaint: %s', ME.message); end

            % 4. Destroy and rebuild all section panels so each screen's
            %    color literals are re-read from the active Theme.
            try
                names = fieldnames(app.SectionPanels);
                for i = 1:numel(names)
                    p = app.SectionPanels.(names{i});
                    if ~isempty(p) && isvalid(p); delete(p); end
                end
                app.SectionPanels = struct();
            catch ME; Logger.debug('QTAUWorkbenchApp', 'panel teardown: %s', ME.message); end

            % Reset per-VM freshness caches so data refetches on re-entry.
            vms = {'WelcomeVm','DashboardVm','CircuitsVm','NotesVm','UploadVm', ...
                   'AnalysisVm','BackendsVm','BenchmarkVm','PredictionVm','JobsVm', ...
                   'ResultsVm','DetailedAnalysisVm','BenchmarkDashboardVm', ...
                   'CircuitCuttingVm', ...
                   'QecSimulationVm','QecVisualizationVm','ReportsVm','SettingsVm'};
            for i = 1:numel(vms)
                try
                    vm = app.(vms{i});
                    if ~isempty(vm) && isprop(vm, 'LastRefresh')
                        vm.LastRefresh = [];
                    end
                catch; end
            end

            % 5. Rebuild Welcome eagerly (it's the user's anchor screen
            %    and must exist for onSelectSection / auth-overlay to
            %    have something to sit on top of). Reset BuiltScreens
            %    so every OTHER screen rebuilds lazily the next time
            %    the user nav-clicks it — same pattern as initial boot.
            %    Avoids the ~32s eager-rebuild cost on every theme
            %    change for screens the user may never re-visit in
            %    the new theme.
            try
                WelcomeScreen(app);
            catch ME
                Logger.warn('QTAUWorkbenchApp', ...
                    'Rebuild of Welcome failed: %s', ME.message);
            end
            app.BuiltScreens = containers.Map('KeyType','char','ValueType','logical');
            app.BuiltScreens('Welcome') = true;

            % 6. Restore the previously-active screen.
            try
                app.onSelectSection(currentKey);
            catch ME; Logger.debug('QTAUWorkbenchApp', 'restore section: %s', ME.message); end

            % 7. Auth overlay regenerate if currently visible.
            try
                if ~isempty(app.AuthOverlay) && isvalid(app.AuthOverlay) ...
                        && strcmp(app.AuthOverlay.Visible, 'on')
                    delete(app.AuthOverlay);
                    app.AuthOverlay = [];
                    LayoutBuilder.buildAuthOverlay(app);
                    OverlayManager.showAuthOverlay(app);
                end
            catch ME; Logger.debug('QTAUWorkbenchApp', 'auth overlay: %s', ME.message); end

            NavigationManager.forceInitialLayout(app);
            app.logEvent('CONFIG', sprintf('Theme applied: %s', char(themeName)));
        end

        function logEvent(app, category, msg)
            OverlayManager.logEvent(app, category, msg);
        end

        function setStatus(app, area, lines) %#ok<INUSL>
            OverlayManager.setStatus(area, lines);
        end

        % -- Styling (→ StyleHelper) -------------------------------------------
        function styleBtn(app, btn, variant) %#ok<INUSL>
            StyleHelper.styleBtn(btn, variant);
        end

        function styleAxes(app, ax) %#ok<INUSL>
            StyleHelper.styleAxes(ax);
        end

        function styleTable(app, tbl) %#ok<INUSL>
            StyleHelper.styleTable(tbl);
        end

        function ax = ensureLazyAxes(app, axesField, gridField, placeholderField)
            % Materialise a lazy uiaxes on first access — see Phase 3
            % perf notes. Screens build a uilabel placeholder + store
            % the parent grid + placeholder on app at construction
            % time (cheap). The first repaint call into a screen calls
            % ensureLazyAxes(...) to swap the placeholder for a real
            % uiaxes, paying the ~0.5–1.5 s cold-paint cost inside the
            % spinner window the user is already watching instead of
            % at screen-mount time. Returns [] when the parent grid is
            % missing — caller should bail out. Idempotent: subsequent
            % calls return the cached axes unchanged.
            ax = app.(axesField);
            if ~isempty(ax) && isvalid(ax); return; end
            g = app.(gridField);
            if isempty(g) || ~isvalid(g); ax = []; return; end
            if ~isempty(app.(placeholderField)) && isvalid(app.(placeholderField))
                delete(app.(placeholderField));
                app.(placeholderField) = [];
            end
            ax = uiaxes(g);
            app.(axesField) = ax;
        end

        % -- Popups (→ PopupMenuManager) ---------------------------------------
        function buildProjectPopupMenu(app)
            PopupMenuManager.buildProjectPopup(app);
        end

        function showProjectPopupMenu(app, x, y)
            PopupMenuManager.showProjectPopup(app, x, y);
        end

        function hideProjectPopupMenu(app)
            PopupMenuManager.hideProjectPopup(app);
        end

        function buildCircuitsPopupMenu(app)
            PopupMenuManager.buildCircuitsPopup(app);
        end

        function showCircuitsPopupMenu(app, x, y)
            PopupMenuManager.showCircuitsPopup(app, x, y);
        end

        function hideCircuitsPopupMenu(app)
            PopupMenuManager.hideCircuitsPopup(app);
        end

        function buildBackendsPopupMenu(app)
            PopupMenuManager.buildBackendsPopup(app);
        end
        function showBackendsPopupMenu(app, x, y)
            PopupMenuManager.showBackendsPopup(app, x, y);
        end
        function hideBackendsPopupMenu(app)
            PopupMenuManager.hideBackendsPopup(app);
        end

        function buildReportsPopupMenu(app)
            PopupMenuManager.buildReportsPopup(app);
        end
        function showReportsPopupMenu(app, x, y)
            PopupMenuManager.showReportsPopup(app, x, y);
        end
        function hideReportsPopupMenu(app)
            PopupMenuManager.hideReportsPopup(app);
        end

        function onFigureMouseDown(app)
            PopupMenuManager.dismissPopups(app);
        end

        function onCircuitsPopupAnalyze(app)
            PopupMenuManager.hideCircuitsPopup(app);
            app.CircuitsVm.onContextAnalyze();
        end

        function onCircuitsPopupEdit(app)
            PopupMenuManager.hideCircuitsPopup(app);
            app.CircuitsVm.onContextEdit();
        end

        function onCircuitsPopupDelete(app)
            PopupMenuManager.hideCircuitsPopup(app);
            app.CircuitsVm.onContextDelete();
        end

        % -- Dialogs (→ DialogBuilder) -----------------------------------------
        function showLoginDialog(app)
            % Reuse-not-rebuild: the LoginDialog stays alive across
            % the session (3 uihtml fields cost 4–18 s cold to build).
            % First call → buildLoginDialog. Subsequent calls (after
            % logout, X-close, or login-success) → resetLoginDialog +
            % Visible='on'. Sub-second on every show after the first.
            if ~isempty(app.LoginDialog) && isvalid(app.LoginDialog)
                DialogBuilder.resetLoginDialog(app);
                try app.LoginDialog.Visible = 'on'; catch; end
                try figure(app.LoginDialog); catch; end
            else
                DialogBuilder.buildLoginDialog(app);
            end
        end

        function showNewProjectDialog(app)
            DialogBuilder.buildNewProjectDialog(app);
        end

        function showEditProjectDialog(app, projectId, projName, projDesc, projTags)
            DialogBuilder.buildEditProjectDialog(app, projectId, projName, projDesc, projTags);
        end

        % -- Auth header buttons -----------------------------------------------
        function updateWelcomeAuthButtons(app)
            if app.State.isAuthenticated()
                if ~isempty(app.HeaderUserLabel) && isvalid(app.HeaderUserLabel)
                    app.HeaderUserLabel.Text = ['  ' char(app.State.currentUser) '  ' char(9662)];
                    app.HeaderUserLabel.Visible = 'on';
                end
                if ~isempty(app.HeaderLoginButton) && isvalid(app.HeaderLoginButton)
                    app.HeaderLoginButton.Visible = 'off';
                end
            else
                if ~isempty(app.HeaderUserLabel) && isvalid(app.HeaderUserLabel)
                    app.HeaderUserLabel.Text = '';
                    app.HeaderUserLabel.Visible = 'off';
                end
                if ~isempty(app.HeaderLoginButton) && isvalid(app.HeaderLoginButton)
                    app.HeaderLoginButton.Visible = 'on';
                end
                if ~isempty(app.HeaderUserMenuPanel) && isvalid(app.HeaderUserMenuPanel)
                    app.HeaderUserMenuPanel.Visible = 'off';
                end
            end
        end

        % -- Client sync -------------------------------------------------------
        function syncClient(app)
            app.Client.setBaseUrl(app.State.baseUrl);
            app.Client.ProjectId = app.State.currentProjectId;
            if ~isempty(app.SettingsBaseUrlField) && isvalid(app.SettingsBaseUrlField)
                app.SettingsBaseUrlField.Value = char(app.State.baseUrl);
            end
        end

        % -- Login dialog HTML input callbacks ---------------------------------
        function onTextFieldHtmlData(app, fieldName)
            switch fieldName
                case 'baseUrl'
                    f = app.LoginDlgBaseUrlField;
                    if isempty(f) || ~isvalid(f), return; end
                    d = f.Data;
                    if isempty(d), return; end
                    app.LoginDlgBaseUrlValue = char(string(d.v));
                case 'username'
                    f = app.LoginDlgUsernameField;
                    if isempty(f) || ~isvalid(f), return; end
                    d = f.Data;
                    if isempty(d), return; end
                    app.LoginDlgUsernameValue = char(string(d.v));
            end
            if string(d.a) == "enter"
                app.WelcomeVm.onLogin();
            end
        end

        function onPasswordHtmlData(app, ~)
            f = app.LoginDlgPasswordField;
            if isempty(f) || ~isvalid(f), return; end
            d = f.Data;
            if isempty(d), return; end
            action = string(d.a);
            if action == "i"
                app.LoginDlgPasswordReal = char(string(d.v));
            elseif action == "enter"
                app.LoginDlgPasswordReal = char(string(d.v));
                app.WelcomeVm.onLogin();
            end
        end

        function onLoginKeyPress(app, evt)
            if strcmp(evt.Key, 'return')
                if isempty(app.LoginDialog) || ~isvalid(app.LoginDialog)
                    return;
                end
                app.WelcomeVm.onLogin();
            end
        end

        % -- Header user menu --------------------------------------------------
        function toggleHeaderUserMenu(app)
            if app.HeaderUserMenuPanel.Visible == "on"
                app.HeaderUserMenuPanel.Visible = 'off';
                return;
            end
            figPos = app.UIFigure.Position;
            menuW = 180; menuH = 76;
            app.HeaderUserMenuPanel.Position = [figPos(3) - menuW - 16, figPos(4) - 52 - menuH - 4, menuW, menuH];
            app.HeaderUserMenuPanel.Visible = 'on';
        end

        function onHeaderMenuAction(app, action)
            app.HeaderUserMenuPanel.Visible = 'off';
            switch action
                case 'account'
                    app.onSelectSection('Settings');
                case 'logout'
                    app.WelcomeVm.onLogout();
            end
        end

        % -- Shared-lookup eager prefetch -----------------------------------
        %   Warms the AppState session caches for /api/circuits,
        %   /api/backends, and /api/mitigation/levels in the background so
        %   Mitigation Compare / Run Planner / Resource Estimator can
        %   render their dropdowns from cache on first visit. Idempotent:
        %   skips any cache that is already fresh per shared_cache_ttl.
        %   Fire-and-forget — failures log at debug and never surface to UI.
        function eagerPrefetchSharedLookups(app)
            try
                if isempty(app.State) || ~app.State.isAuthenticated(); return; end
                ttl   = AppConfig.getDouble('shared_cache_ttl', 120);
                state = app.State;
                token = state.authToken;
                svcs  = app.Services;

                if ~state.isCircuitsListCacheFresh(ttl)
                    AsyncRunner.run( ...
                        @() svcs.CircuitSvc.listCircuits(token), ...
                        @(r) state.setCircuitsListCache(r), ...
                        @(ME) Logger.debug('QTAUWorkbenchApp', 'eagerPrefetch circuits: %s', ME.message));
                end
                if ~state.isBackendsListCacheFresh(ttl)
                    AsyncRunner.run( ...
                        @() svcs.BackendSvc.listBackends(token, ''), ...
                        @(r) state.setBackendsListCache(r), ...
                        @(ME) Logger.debug('QTAUWorkbenchApp', 'eagerPrefetch backends: %s', ME.message));
                end
                if ~state.isMitigationLevelsCacheFresh(ttl)
                    AsyncRunner.run( ...
                        @() svcs.MitigationSvc.listLevels(token), ...
                        @(r) state.setMitigationLevelsCache(r), ...
                        @(ME) Logger.debug('QTAUWorkbenchApp', 'eagerPrefetch levels: %s', ME.message));
                end
            catch ME
                Logger.debug('QTAUWorkbenchApp', 'eagerPrefetchSharedLookups: %s', ME.message);
            end
        end

    end

    % ── Private: UI construction (delegates to LayoutBuilder) ─────────────────
    methods (Access = private)

        function buildUI(app)
            app.UIFigure = uifigure('Name', AppConfig.get('app_name', 'QTAU: Hardware-Agnostic Execution'), ...
                'Position', [80 40 1600 940], ...
                'Color', Theme.COLOR_BG, 'Visible', 'off');
            % R2025a+ built-in theme cascade — handles uitable/uidropdown/
            % uieditfield/uiaxes defaults so our custom palette only has to
            % paint bespoke surfaces (panels, uihtml, nav, overlays).
            Theme.applyFigureMode(app.UIFigure, Theme.activeName());
            app.UIFigure.AutoResizeChildren    = 'off';
            app.UIFigure.SizeChangedFcn        = @(~,~)app.onResizeUI();

            app.RootGrid = uigridlayout(app.UIFigure, [2 1]);
            app.RootGrid.RowHeight   = {52, '1x'};
            app.RootGrid.ColumnWidth = {'1x'};
            app.RootGrid.Padding     = [0 0 0 0];
            app.RootGrid.RowSpacing  = 0;

            LayoutBuilder.buildHeader(app);
            LayoutBuilder.buildBody(app);
            LayoutBuilder.buildLoadingOverlay(app);

            app.UIFigure.Visible = 'on';
            drawnow();

            % Lazy screen-building. The legacy code built all 17 screens
            % eagerly here, costing ~32 s of startup time before the
            % user even saw the Welcome screen (Analysis alone took 7 s,
            % QEC Visualization 4 s, etc.). Now each non-Welcome screen
            % builds on first nav via NavigationManager.ensureScreenBuilt.
            % Steady-state nav is just as fast (already-built screens
            % skip the build); first-nav-per-screen pays a one-time
            % 0.2–7 s cost while showing a loading overlay.
            %
            % BuiltScreens tracks which screens have been built so the
            % nav manager doesn't rebuild on every visit. Welcome is
            % still built eagerly because it's the first screen the
            % user lands on and the auth overlay sits on top of it.
            app.BuiltScreens = containers.Map('KeyType','char','ValueType','logical');
            WelcomeScreen(app);
            app.BuiltScreens('Welcome') = true;
            app.updateWelcomeAuthButtons();
            LayoutBuilder.buildAuthOverlay(app);
            drawnow();

            % Phase 8: default landing screen is now Dashboard. The
            % Projects (formerly Welcome) screen still hosts login +
            % the project-picker; an unauthenticated boot will see the
            % auth overlay regardless of which screen is selected, and
            % onLogin auto-navigates back to Dashboard once login
            % completes — so landing on Dashboard from boot is
            % consistent with the post-login behavior.
            app.onSelectSection('Dashboard');
            % onSelectSection already fits the active panel and calls
            % fitAuthOverlay, so the pre-perf-pass fitAllSections +
            % onResizeUI calls here were redundant — they fanned out
            % to every panel needlessly. forceInitialLayout below
            % gives a final flush for the figure as a whole.
            drawnow();
            NavigationManager.forceInitialLayout(app);

            % Pre-warm the parallel-pool worker so the user's first
            % async action (login → fetch projects, or first nav with
            % stale cache) doesn't pay the ~3–5 s worker spawn cost.
            % Runs in the background; fire-and-forget. Idempotent so
            % calling at boot is safe even if the pool is already up.
            AsyncRunner.warmUp();

            if ~app.State.isAuthenticated()
                app.showAuthOverlay();
            else
                app.hideAuthOverlay();
                % Warm shared lookup caches so Mitigation Compare /
                % Run Planner / Resource Estimator can render dropdowns
                % from cache on their first visit this session.
                app.eagerPrefetchSharedLookups();
            end

            try
                if ~isempty(app.LoadingOverlay) && isvalid(app.LoadingOverlay)
                    delete(app.LoadingOverlay);
                    app.LoadingOverlay = [];
                end
            catch ME; Logger.debug('QTAUWorkbenchApp', 'Overlay cleanup: %s', ME.message); end
            drawnow();

            % Pre-perf-pass this fired a singleShot 150 ms timer to
            % run forceInitialLayout once more — belt-and-suspenders
            % against the old eager all-panel resize that sometimes
            % didn't settle in time. With NavigationManager now
            % resizing only the active panel and forceInitialLayout
            % running synchronously above (pause()-free), the deferred
            % re-layout is redundant and produces a visible flash
            % after the user already sees the UI.

            if ~app.State.isAuthenticated()
                app.showLoginDialog();
            end
        end

    end

    % ── Private static helpers ─────────────────────────────────────────────
    methods (Static, Access = private)
        function dispatchAfterHide(app, callback, arg)
            % Used by runAsyncWithLoading: drop the overlay first so any
            % nested showLoading inside the user callback is observed,
            % then invoke the callback (if non-empty) with its argument.
            % Errors raised by the callback are logged but not rethrown
            % — AsyncRunner already isolates the worker thread, and
            % crashing the dispatcher would leave the overlay in an
            % indeterminate state.
            try; app.hideLoading(); catch; end
            if isempty(callback); return; end
            try
                callback(arg);
            catch ME
                Logger.warn('runAsyncWithLoading', '%s', ME.message);
            end
        end
    end

end
