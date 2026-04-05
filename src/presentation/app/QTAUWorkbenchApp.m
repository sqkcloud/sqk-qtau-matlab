% QTAUWorkbenchApp   Main application class for the QTAU Connector Workspace.
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
%   Each on*() callback: validates preconditions → calls a service method →
%   maps the response with JsonHelper → updates the relevant UI control(s).
%   All errors are caught locally and surfaced as uialert + logEvent entries.
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
        NavToggleButton
        NavCollapsed = false

        ContentShell
        ContentContainer
        SectionTitleLabel
        SectionSubtitleLabel
        Tabs                        % alias for ContentContainer (backward compat)

        DragState = struct('active', false, 'grid', [], 'startX', 0, 'col1W', 0, 'col3W', 0)
        ColumnDividers = {}

        EventLog  = {}
        EventLogArea
        SectionPanels

        LoadingOverlay
        ActivityOverlay            % Reusable loading overlay for API calls
        AuthOverlay                % Login-required overlay covering content area
        HeaderUserLabel            % Logged-in username button in header
        HeaderUserMenu             % Dropdown panel for user menu
        HeaderUserMenuPanel        % The popup panel container
        HeaderLoginButton          % Login button in header (shown when logged out)
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
    end

    % ── Screen callback services ──────────────────────────────────────────────
    properties
        WelcomeVm           % WelcomeViewModel
        DashboardVm         % DashboardViewModel
        CircuitsVm          % CircuitsViewModel
        NotesVm             % NotesViewModel
        UploadVm            % UploadViewModel
        AnalysisVm          % AnalysisViewModel
        BackendsVm          % BackendsViewModel
        BenchmarkVm         % BenchmarkViewModel
        PredictionVm        % PredictionViewModel
        JobsVm              % JobsViewModel
        ResultsVm           % ResultsViewModel
        DetailedAnalysisVm       % DetailedAnalysisViewModel
        BenchmarkDashboardVm     % BenchmarkDashboardViewModel
        ReportsVm                % ReportsViewModel
        SettingsVm          % SettingsViewModel
        QecSimulationVm     % QecSimulationViewModel
        QecVisualizationVm  % QecVisualizationViewModel
    end

    % ── Login dialog ──────────────────────────────────────────────────────────
    properties
        LoginDialog                % modal uifigure
        LoginDlgBaseUrlField       % Base URL edit field in dialog
        LoginDlgUsernameField      % Username edit field in dialog
        LoginDlgPasswordField      % Password edit field (displays masked dots)
        LoginDlgPasswordReal       % Real password string (stored separately)
        LoginDlgPasswordVisible    % logical — true = show plain text
        LoginDlgEyeButton          % Eye toggle button
        LoginDlgStatusLabel        % Status label in dialog
    end

    % ── New Project dialog ────────────────────────────────────────────────────
    properties
        NewProjectDialog            % modal uifigure
        NewProjNameField            % Project name edit field
        NewProjDescField            % Description text area
        NewProjTagsField            % Tags edit field (comma-separated)
        NewProjStatusLabel          % Status / error label
    end

    % ── Edit Project dialog ──────────────────────────────────────────────────
    properties
        EditProjectDialog           % modal uifigure
        EditProjNameField           % Project name edit field
        EditProjDescField           % Description text area
        EditProjTagsField           % Tags edit field (comma-separated)
        EditProjStatusLabel         % Status / error label
        EditProjId                  % Project ID being edited
    end

    % ── Welcome tab ───────────────────────────────────────────────────────────
    properties
        UserInfoArea
        ActiveProjectLabel         % Active Project name display in box
        ProjectsSearchField        % Search input for projects
        ProjectsTable
        ProjectsPopupPanel         % Custom right-click popup (uipanel overlay)
        ProjectsPopupEditBtn       % Edit button inside popup
        ProjectsPopupDeleteBtn     % Delete button inside popup
        ProjectsPageLabel          % "Page X of Y"
        ProjectsPrevButton
        ProjectsNextButton
    end

    % ── Dashboard tab ─────────────────────────────────────────────────────────
    properties
        DashboardSummaryArea
        DashboardStatusArea
        DashboardRefreshButton
        DashKpiLabels           % 1×4 cell of uilabel handles (Active Project…Pipeline Stage)
        DashActivityTable
        DashReadinessArea
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
        CircuitsTable               % Table showing paginated circuits
        CircuitsSearchField         % Search input field
        CircuitsPageLabel           % "Page N" label
        CircuitsPrevBtn             % Prev page button
        CircuitsNextBtn             % Next page button
        CircuitsUploadBtn           % Upload button (navigates to Upload)
        CircuitsPopupPanel          % Custom right-click popup panel
        CircuitsPopupEditBtn        % Edit button inside popup
        CircuitsPopupDeleteBtn      % Delete button inside popup
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
        UploadActiveProjectLabel    % Active project name on Upload screen
        UploadCircuitsTable         % Table showing circuits in current project
        UploadRefreshCircuitsBtn    % Refresh button for circuits table
        UploadDeleteCircuitBtn      % Delete selected circuit button
    end

    % ── Analysis tab ──────────────────────────────────────────────────────────
    properties
        AnalysisCircuitDropdown     % Circuit selector dropdown
        AnalyzeButton
        FeatureTree
        AnalysisFeatureArea     % annotation text beside the tree
        SimilarityTable
        AnalysisCompareArea     % detailed comparison notes
        QVHeatmapAxes              % Quantum Volume heatmap axes (Depth x Width)
        QVInfoLabel                % QV summary annotation label
    end

    % ── Backends tab ──────────────────────────────────────────────────────────
    properties
        BackendTable
        BackendStatusArea
        RefreshBackendsButton
        SelectBackendButton
        BackendKpiLabels        % 1×4 cell: Recommended Primary, Backup, Fidelity, Cal Age
    end

    % ── Benchmark tab ─────────────────────────────────────────────────────────
    properties
        BenchmarkShotsField
        BenchmarkOptField
        BenchmarkMitigationDropdown
        BenchmarkStrategyDropdown
        BenchmarkRunButton
        BenchmarkStatusArea
        BenchmarkStrategyTable
    end

    % ── Prediction tab ────────────────────────────────────────────────────────
    properties
        PredictButton
        PredictionTable
        PredictionTextArea
    end

    % ── Jobs tab ──────────────────────────────────────────────────────────────
    properties
        JobsRefreshButton
        JobsTable
        CancelJobButton
        PauseJobButton
        JobStatusArea
        JobLogsArea
    end

    % ── Results tab ───────────────────────────────────────────────────────────
    properties
        ResultsTable
        ResultJsonArea
        ResultsDistTable
    end

    % ── Detailed Analysis tab ─────────────────────────────────────────────────
    properties
        CompareAxes           % Row 2-Col 1: Measured vs Ideal distribution bar
        ErrorHeatmapAxes      % Row 2-Col 2: Cross-qubit error rate heatmap
        TemporalAxes          % Row 2-Col 3: Temporal stability with confidence band
        QubitAxes             % Row 3-Col 1: Per-qubit T1/T2 coherence scatter
        RBDecayAxes           % Row 3-Col 2: Randomized benchmarking decay curve
        DetailedInsightArea
        RefreshCompareButton
        RefreshHeatmapButton
        RefreshTemporalButton
        RefreshQubitButton
        RefreshRBButton
    end

    % ── Benchmark Dashboard tab ──────────────────────────────────────────────
    properties
        BenchmarkBackendDropdown
        BenchmarkRefreshButton
        BenchmarkKpiLabels
        VolumetricAxes
        ScorecardAxes
        CalibrationAxes
        RegressionAxes
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
        QecSyndromeAxes
        QecSuccessAxes
        QecResultsTable
        QecRunButton
        QecSweepButton
        QecCompareButton
        QecClearButton
    end

    % ── QEC Visualization tab ─────────────────────────────────────────────────
    properties
        QecBlochAxes
        QecLatticeAxes
        QecDecayAxes
        QecErrorWeightAxes
        QecRefreshBlochButton
        QecRefreshLatticeButton
        QecAnimateButton
    end

    % ── Reports tab ───────────────────────────────────────────────────────────
    properties
        ReportTitleField
        ReportFormatDropdown
        ReportSectionsField
        GenerateReportButton
        ReportStatusArea
        OpenReportButton
        GeneratedReportList
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
        EmailNotifyCheck
        NotifyEmailField
        AlertThresholdDropdown
        SaveSettingsButton
        VerifyIbmButton
        SettingsStatusArea
    end

    % ── Constructor / destructor ──────────────────────────────────────────────
    methods
        function app = QTAUWorkbenchApp()
            Logger.info('QTAUWorkbenchApp', '=== QTAUWorkbenchApp initializing ===');
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
            app.BenchmarkSvc  = BenchmarkService(app.Client);

            % Only WelcomeVm is created eagerly (handles login dialog).
            % All other ViewModels are created lazily via ensureVm().
            Logger.info('QTAUWorkbenchApp', 'Services ready — creating WelcomeVm (lazy init for others)');
            app.WelcomeVm = WelcomeViewModel(app);

            app.buildUI();
            app.logEvent('UI', 'QTAUWorkbenchApp started');
            app.forceInitialLayout();
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
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch ME
                Logger.debug('QTAUWorkbenchApp', 'Cleanup: %s', ME.message);
            end
        end
    end

    % Callable from src/presentation/screens/*.m (package-less functions cannot use private methods).
    methods
        function updateWelcomeAuthButtons(app)
            if app.State.isAuthenticated()
                % Header: show username, hide Login button
                if ~isempty(app.HeaderUserLabel) && isvalid(app.HeaderUserLabel)
                    app.HeaderUserLabel.Text = ['  ' char(app.State.currentUser) '  ' char(9662)];
                    app.HeaderUserLabel.Visible = 'on';
                end
                if ~isempty(app.HeaderLoginButton) && isvalid(app.HeaderLoginButton)
                    app.HeaderLoginButton.Visible = 'off';
                end
            else
                % Header: hide username, show Login button, hide menu
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

        function showLoginDialog(app)
            DialogBuilder.buildLoginDialog(app);
        end

        function showNewProjectDialog(app)
            DialogBuilder.buildNewProjectDialog(app);
        end

        function buildProjectPopupMenu(app)
            % Create a custom popup panel (context-menu replacement) for the
            % projects table.  Positioned absolutely inside the UIFigure so
            % we have full control over text alignment and styling.
            popW = 160; popH = 72;
            app.ProjectsPopupPanel = uipanel(app.UIFigure, ...
                'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', [1 1 1], ...
                'BorderColor', [0.78 0.80 0.84], ...
                'Position', [0 0 popW popH], ...
                'Visible', 'off');

            pg = uigridlayout(app.ProjectsPopupPanel, [2 1]);
            pg.RowHeight   = {'1x', '1x'};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [4 4 4 4];
            pg.RowSpacing  = 2;
            pg.BackgroundColor = [1 1 1];

            app.ProjectsPopupEditBtn = uibutton(pg, 'Text', ...
                [' ' char(9999) '  ' Labels.get('project_ctx_edit', 'Edit')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onEditProject());
            app.ProjectsPopupEditBtn.Layout.Row = 1;
            app.ProjectsPopupEditBtn.BackgroundColor = [1 1 1];
            app.ProjectsPopupEditBtn.FontColor = [0.15 0.18 0.24];

            app.ProjectsPopupDeleteBtn = uibutton(pg, 'Text', ...
                [' ' char(10005) '  ' Labels.get('project_ctx_delete', 'Delete')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onDeleteProject());
            app.ProjectsPopupDeleteBtn.Layout.Row = 2;
            app.ProjectsPopupDeleteBtn.BackgroundColor = [1 1 1];
            app.ProjectsPopupDeleteBtn.FontColor = [0.70 0.15 0.15];
        end

        function showProjectPopupMenu(app, x, y)
            % Show the custom popup at the given figure-relative position.
            if isempty(app.ProjectsPopupPanel) || ~isvalid(app.ProjectsPopupPanel)
                app.buildProjectPopupMenu();
            end
            popW = 160; popH = 72;
            % Clamp to figure bounds
            figPos = app.UIFigure.Position;
            px = min(x, figPos(3) - popW - 4);
            py = max(y - popH, 4);
            app.ProjectsPopupPanel.Position = [px py popW popH];
            app.ProjectsPopupPanel.Visible = 'on';
        end

        function hideProjectPopupMenu(app)
            if ~isempty(app.ProjectsPopupPanel) && isvalid(app.ProjectsPopupPanel)
                app.ProjectsPopupPanel.Visible = 'off';
            end
        end

        function onFigureMouseDown(app)
            % Hide popup menus on any left-click outside them.
            if ~isempty(app.ProjectsPopupPanel) && isvalid(app.ProjectsPopupPanel) ...
                    && strcmp(app.ProjectsPopupPanel.Visible, 'on')
                cp = app.UIFigure.CurrentPoint;
                pp = app.ProjectsPopupPanel.Position;
                if cp(1) < pp(1) || cp(1) > pp(1)+pp(3) || ...
                   cp(2) < pp(2) || cp(2) > pp(2)+pp(4)
                    app.hideProjectPopupMenu();
                end
            end
            if ~isempty(app.CircuitsPopupPanel) && isvalid(app.CircuitsPopupPanel) ...
                    && strcmp(app.CircuitsPopupPanel.Visible, 'on')
                cp = app.UIFigure.CurrentPoint;
                pp = app.CircuitsPopupPanel.Position;
                if cp(1) < pp(1) || cp(1) > pp(1)+pp(3) || ...
                   cp(2) < pp(2) || cp(2) > pp(2)+pp(4)
                    app.hideCircuitsPopupMenu();
                end
            end
        end

        % ── Circuits popup (same pattern as Projects popup) ─────────────
        function buildCircuitsPopupMenu(app)
            popW = 160; popH = 108;
            app.CircuitsPopupPanel = uipanel(app.UIFigure, ...
                'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', [1 1 1], ...
                'BorderColor', [0.78 0.80 0.84], ...
                'Position', [0 0 popW popH], ...
                'Visible', 'off');

            pg = uigridlayout(app.CircuitsPopupPanel, [3 1]);
            pg.RowHeight   = {'1x', '1x', '1x'};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [4 4 4 4];
            pg.RowSpacing  = 2;
            pg.BackgroundColor = [1 1 1];

            analyzeBtn = uibutton(pg, 'Text', ...
                [' ' char(8981) '  ' Labels.get('circuit_ctx_analyze', 'Analyze')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupAnalyze());
            analyzeBtn.Layout.Row = 1;
            analyzeBtn.BackgroundColor = [1 1 1];
            analyzeBtn.FontColor = [0.13 0.33 0.73];

            app.CircuitsPopupEditBtn = uibutton(pg, 'Text', ...
                [' ' char(9999) '  ' Labels.get('circuit_ctx_edit', 'Edit')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupEdit());
            app.CircuitsPopupEditBtn.Layout.Row = 2;
            app.CircuitsPopupEditBtn.BackgroundColor = [1 1 1];
            app.CircuitsPopupEditBtn.FontColor = [0.15 0.18 0.24];

            app.CircuitsPopupDeleteBtn = uibutton(pg, 'Text', ...
                [' ' char(10005) '  ' Labels.get('circuit_ctx_delete', 'Delete')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupDelete());
            app.CircuitsPopupDeleteBtn.Layout.Row = 3;
            app.CircuitsPopupDeleteBtn.BackgroundColor = [1 1 1];
            app.CircuitsPopupDeleteBtn.FontColor = [0.70 0.15 0.15];
        end

        function showCircuitsPopupMenu(app, x, y)
            if isempty(app.CircuitsPopupPanel) || ~isvalid(app.CircuitsPopupPanel)
                app.buildCircuitsPopupMenu();
            end
            popW = 160; popH = 108;
            figPos = app.UIFigure.Position;
            px = min(x, figPos(3) - popW - 4);
            py = max(y - popH, 4);
            app.CircuitsPopupPanel.Position = [px py popW popH];
            app.CircuitsPopupPanel.Visible = 'on';
        end

        function hideCircuitsPopupMenu(app)
            if ~isempty(app.CircuitsPopupPanel) && isvalid(app.CircuitsPopupPanel)
                app.CircuitsPopupPanel.Visible = 'off';
            end
        end

        function onCircuitsPopupAnalyze(app)
            app.hideCircuitsPopupMenu();
            app.CircuitsVm.onContextAnalyze();
        end

        function onCircuitsPopupEdit(app)
            app.hideCircuitsPopupMenu();
            app.CircuitsVm.onContextEdit();
        end

        function onCircuitsPopupDelete(app)
            app.hideCircuitsPopupMenu();
            app.CircuitsVm.onContextDelete();
        end

        function showEditProjectDialog(app, projectId, projName, projDesc, projTags)
            DialogBuilder.buildEditProjectDialog(app, projectId, projName, projDesc, projTags);
        end

        function onPasswordChanging(app, evt)
            if app.LoginDlgPasswordVisible
                % Plain-text mode — store the value directly
                app.LoginDlgPasswordReal = char(evt.Value);
                return;
            end
            newVal  = char(evt.Value);
            oldReal = char(app.LoginDlgPasswordReal);
            oldLen  = strlength(string(oldReal));
            newLen  = strlength(string(newVal));

            if newLen > oldLen
                % Characters added at the end
                typed = newVal(oldLen+1:end);
                app.LoginDlgPasswordReal = [oldReal, typed];
            elseif newLen < oldLen
                % Characters deleted from end
                app.LoginDlgPasswordReal = oldReal(1:newLen);
            end
            % Replace displayed text with dots
            app.LoginDlgPasswordField.Value = repmat(char(8226), 1, strlength(string(app.LoginDlgPasswordReal)));
        end

        function onLoginKeyPress(app, evt)
            % Triggered on any key press in the login dialog
            if strcmp(evt.Key, 'return')
                if isempty(app.LoginDialog) || ~isvalid(app.LoginDialog)
                    return;
                end
                app.WelcomeVm.onLogin();
            end
        end

        function onTogglePasswordVisibility(app)
            app.LoginDlgPasswordVisible = ~app.LoginDlgPasswordVisible;
            ud = app.LoginDlgEyeButton.UserData;
            if app.LoginDlgPasswordVisible
                app.LoginDlgPasswordField.Value = char(app.LoginDlgPasswordReal);
                app.LoginDlgEyeButton.HTMLSource = ud.visibleHtml;
            else
                app.LoginDlgPasswordField.Value = repmat(char(8226), 1, strlength(string(app.LoginDlgPasswordReal)));
                app.LoginDlgEyeButton.HTMLSource = ud.hiddenHtml;
            end
        end
    end

    % ── UI construction (private) ─────────────────────────────────────────────
    methods (Access = private)

        function buildUI(app)
            app.UIFigure = uifigure('Name', 'QTAU Connector Workspace', ...
                'Position', [80 40 1600 940], ...
                'Color', [0.97 0.98 1.00], 'Visible', 'off');
            app.UIFigure.AutoResizeChildren    = 'off';
            app.UIFigure.SizeChangedFcn        = @(~,~)app.onResizeUI();
            app.UIFigure.WindowButtonDownFcn   = @(~,~)app.onFigMouseDown();
            app.UIFigure.WindowButtonMotionFcn = @(~,~)app.onFigMouseMove();
            app.UIFigure.WindowButtonUpFcn     = @(~,~)app.onFigMouseUp();

            % Root 2-row grid: header | body
            app.RootGrid = uigridlayout(app.UIFigure, [2 1]);
            app.RootGrid.RowHeight   = {52, '1x'};
            app.RootGrid.ColumnWidth = {'1x'};
            app.RootGrid.Padding     = [0 0 0 0];
            app.RootGrid.RowSpacing  = 0;

            app.buildHeader();
            app.buildBody();
            app.buildLoadingOverlay();

            % Reveal the figure with just the spinner visible while tabs build
            app.UIFigure.Visible = 'on';
            drawnow();

            WelcomeScreen(app);
            app.updateWelcomeAuthButtons();
            DashboardScreen(app);
            CircuitsScreen(app);
            NotesScreen(app);
            UploadScreen(app);
            AnalysisScreen(app);
            BackendsScreen(app);
            BenchmarkScreen(app);
            PredictionScreen(app);
            JobsScreen(app);
            ResultsScreen(app);
            DetailedAnalysisScreen(app);
            BenchmarkDashboardScreen(app);
            QecSimulationScreen(app);
            QecVisualizationScreen(app);
            ReportsScreen(app);
            SettingsScreen(app);
            app.buildAuthOverlay();
            drawnow();

            app.onSelectSection('Welcome');
            app.fitAllSections();
            app.onResizeUI();
            drawnow();
            app.forceInitialLayout();

            % Show auth overlay if not authenticated
            if ~app.State.isAuthenticated()
                app.showAuthOverlay();
            else
                app.hideAuthOverlay();
            end

            try
                if ~isempty(app.LoadingOverlay) && isvalid(app.LoadingOverlay)
                    delete(app.LoadingOverlay);
                    app.LoadingOverlay = [];
                end
            catch ME; Logger.debug('QTAUWorkbenchApp', 'Overlay cleanup: %s', ME.message); end
            drawnow();

            try
                t = timer('ExecutionMode','singleShot','StartDelay',0.15, ...
                    'TimerFcn', @(~,~)app.forceInitialLayout(), ...
                    'StopFcn', @(tObj,~)delete(tObj));
                start(t);
            catch ME; Logger.debug('QTAUWorkbenchApp', 'Layout timer init: %s', ME.message); end

            % Auto-show login dialog if not yet authenticated
            if ~app.State.isAuthenticated()
                app.showLoginDialog();
            end
        end

        function buildHeader(app)
            app.HeaderGrid = uigridlayout(app.RootGrid, [1 3]);
            app.HeaderGrid.Layout.Row    = 1;
            app.HeaderGrid.Layout.Column = 1;
            app.HeaderGrid.ColumnWidth   = {250, '1x', 'fit'};
            app.HeaderGrid.RowHeight     = {52};
            app.HeaderGrid.Padding       = [0 0 12 2];
            app.HeaderGrid.BackgroundColor = [0.10 0.17 0.30];

            logoHost = uigridlayout(app.HeaderGrid, [1 1]);
            logoHost.Layout.Row = 1; logoHost.Layout.Column = 1;
            logoHost.RowHeight = {'1x'}; logoHost.ColumnWidth = {'1x'};
            logoHost.Padding = [0 0 10 0];
            logoHost.RowSpacing = 0; logoHost.ColumnSpacing = 0;
            logoHost.BackgroundColor = [0.10 0.17 0.30];

            logoPath = fullfile(fileparts(mfilename('fullpath')), '..', '..', '..', ...
                'resources', 'sqk-logo-kokkos-white1-reordered.svg');
            brandWrap = uigridlayout(logoHost, [1 2]);
            brandWrap.Layout.Row = 1; brandWrap.Layout.Column = 1;
            brandWrap.RowHeight = {'1x'}; brandWrap.ColumnWidth = {108, '1x'};
            brandWrap.Padding = [0 0 10 0];
            brandWrap.RowSpacing = 0; brandWrap.ColumnSpacing = 0;
            brandWrap.BackgroundColor = [0.10 0.17 0.30];
            try
                brand = uiimage(brandWrap);
                brand.ImageSource = logoPath;
                brand.ScaleMethod = 'fit';
                brand.Tooltip = 'SQK';
                brand.Layout.Row = 1; brand.Layout.Column = 1;
            catch
                brand = uilabel(brandWrap, 'Text', 'SQK');
                brand.FontSize = 14; brand.FontWeight = 'bold';
                brand.FontColor = [1 1 1];
                brand.HorizontalAlignment = 'left';
                brand.VerticalAlignment   = 'bottom';
                brand.Layout.Row = 1; brand.Layout.Column = 1;
            end

            subtitle = uilabel(app.HeaderGrid, 'Text', 'Connector Workspace');
            subtitle.FontSize = 14; subtitle.FontWeight = 'bold';
            subtitle.HorizontalAlignment = 'center';
            subtitle.FontColor = [0.80 0.87 0.97];
            subtitle.Layout.Row = 1; subtitle.Layout.Column = 2;

            headerRight = uigridlayout(app.HeaderGrid, [1 3]);
            headerRight.Layout.Row = 1; headerRight.Layout.Column = 3;
            headerRight.ColumnWidth = {'fit', 'fit', 'fit'};
            headerRight.Padding = [0 0 4 0]; headerRight.ColumnSpacing = 10;
            headerRight.BackgroundColor = [0.10 0.17 0.30];

            userBadge = uilabel(headerRight, 'Text', 'SQK Admin Workspace');
            userBadge.FontSize = 13; userBadge.FontWeight = 'bold';
            userBadge.HorizontalAlignment = 'right';
            userBadge.FontColor = [1 1 1];
            userBadge.Layout.Row = 1; userBadge.Layout.Column = 1;
            userBadge.Tooltip = 'QTAU Connector v2026';

            % Login link (shown when logged out) — no border
            app.HeaderLoginButton = uihyperlink(headerRight, ...
                'Text', Labels.get('header_btn_login', 'Login'), ...
                'URL', '', ...
                'HyperlinkClickedFcn', @(~,~)app.showLoginDialog(), ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0.85 0.92 1.00], ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
            app.HeaderLoginButton.Layout.Row = 1; app.HeaderLoginButton.Layout.Column = 2;
            app.HeaderLoginButton.VisitedColor = [0.85 0.92 1.00];

            % Username link (shown when logged in) — left-click opens dropdown menu
            app.HeaderUserLabel = uihyperlink(headerRight, ...
                'Text', '', ...
                'URL', '', ...
                'HyperlinkClickedFcn', @(~,~)app.toggleHeaderUserMenu(), ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0.85 0.92 1.00], ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
            app.HeaderUserLabel.Layout.Row = 1; app.HeaderUserLabel.Layout.Column = 3;
            app.HeaderUserLabel.Visible = 'off';
            app.HeaderUserLabel.VisitedColor = [0.85 0.92 1.00];

            % Dropdown menu panel (hidden by default, positioned over the figure)
            app.HeaderUserMenuPanel = uipanel(app.UIFigure, 'Title', '', ...
                'Position', [0 0 180 76], 'Visible', 'off', ...
                'BackgroundColor', [1 1 1], 'BorderType', 'line');
            mg = uigridlayout(app.HeaderUserMenuPanel, [2 1]);
            mg.RowHeight = {32, 32}; mg.ColumnWidth = {'1x'};
            mg.Padding = [4 4 4 4]; mg.RowSpacing = 2;
            mg.BackgroundColor = [1 1 1];

            accountBtn = uibutton(mg, 'Text', [char(9881) '  ' Labels.get('header_menu_my_account', 'My Account')], ...
                'HorizontalAlignment', 'left', 'FontSize', 15, ...
                'FontColor', [0.20 0.20 0.25], 'BackgroundColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~)app.onHeaderMenuAction('account'));
            accountBtn.Layout.Row = 1; accountBtn.Layout.Column = 1;

            logoutBtn = uibutton(mg, 'Text', [char(9211) '  ' Labels.get('header_menu_logout', 'Logout')], ...
                'HorizontalAlignment', 'left', 'FontSize', 15, ...
                'FontColor', [0.70 0.15 0.15], 'BackgroundColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~)app.onHeaderMenuAction('logout'));
            logoutBtn.Layout.Row = 2; logoutBtn.Layout.Column = 1;
        end

        function toggleHeaderUserMenu(app)
            if app.HeaderUserMenuPanel.Visible == "on"
                app.HeaderUserMenuPanel.Visible = 'off';
                return;
            end
            % Position the menu below the username button at top-right
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

        function buildBody(app)
            app.BodyGrid = uigridlayout(app.RootGrid, [1 2]);
            app.BodyGrid.Layout.Row    = 2;
            app.BodyGrid.Layout.Column = 1;
            app.BodyGrid.ColumnWidth   = {230, '1x'};
            app.BodyGrid.RowHeight     = {'1x'};
            app.BodyGrid.Padding       = [0 0 0 0];
            app.BodyGrid.ColumnSpacing = 0;
            app.BodyGrid.BackgroundColor = [0.93 0.95 0.98];

            % Sidebar
            app.NavPanel = uipanel(app.BodyGrid, 'Title', '');
            app.NavPanel.Layout.Row = 1; app.NavPanel.Layout.Column = 1;
            app.NavPanel.BackgroundColor = [0.12 0.19 0.31];

            navGrid = uigridlayout(app.NavPanel, [4 1]);
            navGrid.RowHeight = {44, 1, '1x', 28};
            navGrid.Padding = [10 10 10 10];
            navGrid.BackgroundColor = [0.12 0.19 0.31];

            topRow = uigridlayout(navGrid, [1 2]);
            topRow.Layout.Row = 1; topRow.Layout.Column = 1;
            topRow.ColumnWidth = {0, '1x'};
            topRow.Padding = [0 0 0 0];
            topRow.BackgroundColor = [0.12 0.19 0.31];

            navBrand = uilabel(topRow, 'Text', '');
            navBrand.Visible = 'off';
            navBrand.Layout.Row = 1; navBrand.Layout.Column = 1;

            app.NavToggleButton = uibutton(topRow, 'push', 'Text', '≡', ...
                'ButtonPushedFcn', @(~,~)app.onToggleNav());
            app.NavToggleButton.Layout.Row = 1; app.NavToggleButton.Layout.Column = 2;
            app.NavToggleButton.FontSize = 18; app.NavToggleButton.FontWeight = 'bold';
            app.NavToggleButton.BackgroundColor = [0.20 0.31 0.49];
            app.NavToggleButton.FontColor = [1 1 1];

            navSep = uipanel(navGrid, 'Title', '');
            navSep.Layout.Row = 2; navSep.Layout.Column = 1;
            navSep.BackgroundColor = [0.30 0.40 0.55];
            navSep.BorderType = 'none';

            navBtnsPanel = uipanel(navGrid, 'Title', '');
            navBtnsPanel.Layout.Row = 3; navBtnsPanel.Layout.Column = 1;
            navBtnsPanel.BackgroundColor = [0.12 0.19 0.31];
            navBtnsPanel.BorderType = 'none';

            navBtnsGrid = uigridlayout(navBtnsPanel, [17 1]);
            navBtnsGrid.RowHeight = repmat({32}, 1, 17);
            navBtnsGrid.Padding = [0 0 0 0]; navBtnsGrid.RowSpacing = 6;
            navBtnsGrid.BackgroundColor = [0.12 0.19 0.31];

            names  = {'Welcome','Dashboard','Circuits','Notes','Upload','Analysis','Backends', ...
                      'Benchmark','Prediction','Jobs','Results','Detailed Analysis', ...
                      'Benchmark Dashboard', ...
                      'QEC Simulation','QEC Visualization','Reports','Settings'};
            labels = app.navMenuLabels();
            app.NavButtons = gobjects(1, numel(names));
            for i = 1:numel(names)
                app.NavButtons(i) = uibutton(navBtnsGrid, 'push', ...
                    'Text', [' ' labels{i}], ...
                    'ButtonPushedFcn', @(~,~)app.onSelectSection(names{i}));
                app.NavButtons(i).Layout.Row = i; app.NavButtons(i).Layout.Column = 1;
                app.NavButtons(i).HorizontalAlignment = 'left';
                app.NavButtons(i).FontSize = 14; app.NavButtons(i).FontWeight = 'bold';
                app.NavButtons(i).BackgroundColor = [0.16 0.24 0.39];
                app.NavButtons(i).FontColor = [0.92 0.96 1.00];
            end

            app.NavList = uilistbox(navGrid, 'Items', names, 'Visible', 'off');
            app.NavList.Value = 'Welcome';
            app.NavList.Layout.Row = 4; app.NavList.Layout.Column = 1;
            app.NavList.ValueChangedFcn = @(src,~)app.onSelectSection(string(src.Value));

            hint = uilabel(navGrid, 'Text', '메뉴 숨기기');
            hint.FontSize = 10; hint.FontColor = [0.72 0.80 0.92];
            hint.VerticalAlignment = 'top';
            hint.Layout.Row = 4; hint.Layout.Column = 1;

            % Content shell
            app.ContentShell = uipanel(app.BodyGrid, 'Title', '');
            app.ContentShell.Layout.Row = 1; app.ContentShell.Layout.Column = 2;
            app.ContentShell.BackgroundColor = [0.96 0.97 0.99];

            shellGrid = uigridlayout(app.ContentShell, [3 1]);
            shellGrid.RowHeight  = {82, 1, '1x'};
            shellGrid.Padding    = [20 16 20 16];
            shellGrid.RowSpacing = 12;
            shellGrid.BackgroundColor = [0.96 0.97 0.99];

            headerPanel = uipanel(shellGrid, 'Title', '');
            headerPanel.Layout.Row = 1; headerPanel.Layout.Column = 1;
            headerPanel.BackgroundColor = [1 1 1];
            hg = uigridlayout(headerPanel, [2 1]);
            hg.RowHeight = {28, 20}; hg.Padding = [16 10 16 10];
            hg.BackgroundColor = [1 1 1];
            app.SectionTitleLabel = uilabel(hg, 'Text', 'Welcome');
            app.SectionTitleLabel.FontSize = 18; app.SectionTitleLabel.FontWeight = 'bold';
            app.SectionTitleLabel.Layout.Row = 1; app.SectionTitleLabel.Layout.Column = 1;
            app.SectionSubtitleLabel = uilabel(hg, 'Text', 'Server authentication and project access');
            app.SectionSubtitleLabel.FontSize = 12;
            app.SectionSubtitleLabel.FontColor = [0.35 0.40 0.48];
            app.SectionSubtitleLabel.Layout.Row = 2; app.SectionSubtitleLabel.Layout.Column = 1;

            sep = uipanel(shellGrid, 'Title', '');
            sep.Layout.Row = 2; sep.Layout.Column = 1;
            sep.BackgroundColor = [0.87 0.90 0.95];

            app.ContentContainer = uipanel(shellGrid, 'Title', '');
            app.ContentContainer.Layout.Row = 3; app.ContentContainer.Layout.Column = 1;
            app.ContentContainer.BackgroundColor = [0.96 0.97 0.99];
            app.ContentContainer.AutoResizeChildren = 'off';
            app.ContentContainer.SizeChangedFcn = @(~,~)app.onResizeUI();

            app.Tabs          = app.ContentContainer;
            app.SectionPanels = struct();
        end

        function buildLoadingOverlay(app)
            figW = app.UIFigure.Position(3);
            figH = app.UIFigure.Position(4);
            app.LoadingOverlay = uipanel(app.UIFigure, 'Title', '');
            app.LoadingOverlay.Units    = 'pixels';
            app.LoadingOverlay.Position = [0 0 figW figH];
            app.LoadingOverlay.BackgroundColor = [0.97 0.98 1.00];
            app.LoadingOverlay.BorderType      = 'none';
            app.LoadingOverlay.AutoResizeChildren = 'off';

            olog = uigridlayout(app.LoadingOverlay, [3 3]);
            olog.RowHeight   = {'1x', 110, '1x'};
            olog.ColumnWidth = {'1x', 240, '1x'};
            olog.Padding     = [0 0 0 0];
            olog.BackgroundColor = [0.97 0.98 1.00];

            spinHost = uigridlayout(olog, [1 1]);
            spinHost.Layout.Row = 2; spinHost.Layout.Column = 2;
            spinHost.Padding = [0 0 0 0];
            spinHost.BackgroundColor = [0.97 0.98 1.00];
            try
                sp = uihtml(spinHost);
                sp.HTMLSource = [ ...
                    '<div style="display:flex;flex-direction:column;align-items:center;', ...
                    'justify-content:center;height:100%;font-family:-apple-system,', ...
                    '''Segoe UI'',Arial,sans-serif;">', ...
                    '<div style="width:46px;height:46px;border:5px solid #dde3ee;', ...
                    'border-top-color:#2952a3;border-radius:50%;', ...
                    'animation:spin 0.85s linear infinite;"></div>', ...
                    '<style>@keyframes spin{to{transform:rotate(360deg)}}</style>', ...
                    '<p style="margin-top:18px;font-size:13px;color:#5a6478;', ...
                    'letter-spacing:0.03em;font-weight:500;">Loading workspace…</p>', ...
                    '</div>'];
            catch
                lbl = uilabel(spinHost, 'Text', 'Loading workspace…');
                lbl.FontSize = 15; lbl.FontWeight = 'bold';
                lbl.FontColor = [0.35 0.42 0.52];
                lbl.HorizontalAlignment = 'center';
                lbl.VerticalAlignment   = 'center';
            end
        end

        function buildAuthOverlay(app)
            % Overlay that covers content area when user is not authenticated.
            pos = app.ContentContainer.Position;
            app.AuthOverlay = uipanel(app.ContentContainer, 'Title', '', ...
                'BorderType', 'none', 'BackgroundColor', [0.96 0.97 0.99]);
            app.AuthOverlay.AutoResizeChildren = 'on';
            app.AuthOverlay.Position = [0 0 max(1, pos(3)) max(1, pos(4))];

            og = uigridlayout(app.AuthOverlay, [3 3]);
            og.RowHeight   = {'1x', 180, '1x'};
            og.ColumnWidth = {'1x', 320, '1x'};
            og.Padding     = [0 0 0 0];
            og.BackgroundColor = [0.96 0.97 0.99];

            card = uipanel(og, 'Title', '');
            card.Layout.Row = 2; card.Layout.Column = 2;
            card.BackgroundColor = [1 1 1];

            cg = uigridlayout(card, [4 1]);
            cg.RowHeight  = {40, 24, 20, 34};
            cg.Padding    = [24 20 24 20];
            cg.RowSpacing = 10;
            cg.BackgroundColor = [1 1 1];

            icon = uilabel(cg, 'Text', char(9888));
            icon.FontSize = 28; icon.HorizontalAlignment = 'center';
            icon.Layout.Row = 1; icon.Layout.Column = 1;

            ttl = uilabel(cg, 'Text', Labels.get('auth_overlay_title', 'Authentication Required'));
            ttl.FontSize = 16; ttl.FontWeight = 'bold';
            ttl.HorizontalAlignment = 'center';
            ttl.Layout.Row = 2; ttl.Layout.Column = 1;

            sub = uilabel(cg, 'Text', Labels.get('auth_overlay_subtitle', 'Please sign in to access the workspace'));
            sub.FontSize = 12; sub.FontColor = [0.35 0.40 0.48];
            sub.HorizontalAlignment = 'center';
            sub.Layout.Row = 3; sub.Layout.Column = 1;

            btn = uibutton(cg, 'Text', Labels.get('auth_overlay_btn', 'Sign In'));
            btn.Layout.Row = 4; btn.Layout.Column = 1;
            app.styleBtn(btn, 'primary');
            btn.ButtonPushedFcn = @(~,~)app.showLoginDialog();
        end

        % ── Section metadata — loaded from labels.properties ─────────────────
        function subtitle = sectionSubtitleFor(~, key)
            keyMap = struct( ...
                'Welcome',         'subtitle_welcome', ...
                'Dashboard',       'subtitle_dashboard', ...
                'Circuits',        'subtitle_circuits', ...
                'Notes',           'subtitle_notes', ...
                'Upload',          'subtitle_upload', ...
                'Analysis',        'subtitle_analysis', ...
                'Backends',        'subtitle_backends', ...
                'Benchmark',       'subtitle_benchmark', ...
                'Prediction',      'subtitle_prediction', ...
                'Jobs',            'subtitle_jobs', ...
                'Results',         'subtitle_results', ...
                'DetailedAnalysis',  'subtitle_detailed_analysis', ...
                'QECSimulation',    'subtitle_qec_simulation', ...
                'QECVisualization', 'subtitle_qec_visualization', ...
                'Reports',         'subtitle_reports', ...
                'Settings',        'subtitle_settings');
            safeKey = matlab.lang.makeValidName(char(key));
            if isfield(keyMap, safeKey)
                subtitle = Labels.get(keyMap.(safeKey), char(key));
            else
                subtitle = '';
            end
        end

        function labels = navMenuLabels(~)
            labels = { ...
                Labels.get('nav_welcome',           '⌂  Welcome'), ...
                Labels.get('nav_dashboard',         '◫  Dashboard'), ...
                Labels.get('nav_circuits',          '☰  Circuits'), ...
                Labels.get('nav_notes',             '✎  Notes'), ...
                Labels.get('nav_upload',            '⤴  Upload'), ...
                Labels.get('nav_analysis',          '⌕  Analysis'), ...
                Labels.get('nav_backends',          '⌬  Backends'), ...
                Labels.get('nav_benchmark',         '◎  Benchmark'), ...
                Labels.get('nav_prediction',        '◇  Prediction'), ...
                Labels.get('nav_jobs',              '▣  Jobs'), ...
                Labels.get('nav_results',           '□  Results'), ...
                Labels.get('nav_detailed_analysis',      '△  Detailed Analysis'), ...
                Labels.get('nav_benchmark_dashboard',   '◆  Benchmark Dashboard'), ...
                Labels.get('nav_qec_simulation',        '◉  QEC Simulation'), ...
                Labels.get('nav_qec_visualization',     '◈  QEC Visualization'), ...
                Labels.get('nav_reports',               '▤  Reports'), ...
                Labels.get('nav_settings',              '⚙  Settings')};
        end

        function labels = navCollapsedLabels(~)
            labels = { ...
                Labels.get('nav_short_welcome',           '⌂'), ...
                Labels.get('nav_short_dashboard',         '◫'), ...
                Labels.get('nav_short_circuits',          '☰'), ...
                Labels.get('nav_short_notes',             '✎'), ...
                Labels.get('nav_short_upload',            '⤴'), ...
                Labels.get('nav_short_analysis',          '⌕'), ...
                Labels.get('nav_short_backends',          '⌬'), ...
                Labels.get('nav_short_benchmark',         '◎'), ...
                Labels.get('nav_short_prediction',        '◇'), ...
                Labels.get('nav_short_jobs',              '▣'), ...
                Labels.get('nav_short_results',           '□'), ...
                Labels.get('nav_short_detailed_analysis',      '△'), ...
                Labels.get('nav_short_benchmark_dashboard',   '◆'), ...
                Labels.get('nav_short_qec_simulation',        '◉'), ...
                Labels.get('nav_short_qec_visualization',     '◈'), ...
                Labels.get('nav_short_reports',               '▤'), ...
                Labels.get('nav_short_settings',              '⚙')};
        end

        function forceInitialLayout(app)
            try
                drawnow(); pause(0.05);
                app.fitAllSections(); app.onResizeUI();
                drawnow(); pause(0.02);
                app.fitAllSections();
            catch ME; Logger.debug('QTAUWorkbenchApp', 'forceInitialLayout: %s', ME.message); end
        end

        function updateNavStyles(app, activeKey)
            names = {'Welcome','Dashboard','Circuits','Notes','Upload','Analysis','Backends', ...
                'Benchmark','Prediction','Jobs','Results','Detailed Analysis', ...
                'Benchmark Dashboard', ...
                'QEC Simulation','QEC Visualization','Reports','Settings'};
            for i = 1:min(numel(app.NavButtons), numel(names))
                if strcmp(names{i}, activeKey)
                    app.NavButtons(i).BackgroundColor = [0.29 0.49 0.82];
                    app.NavButtons(i).FontColor = [1 1 1];
                else
                    app.NavButtons(i).BackgroundColor = [0.16 0.24 0.39];
                    app.NavButtons(i).FontColor = [0.92 0.96 1.00];
                end
            end
        end

        function fitSectionPanel(~, panel)
            if isempty(panel) || ~isvalid(panel); return; end
            try
                p = panel.Parent;
                if ~isempty(p) && isvalid(p)
                    panel.Position = [0 0 max(1, p.Position(3)) max(1, p.Position(4))];
                end
            catch ME; Logger.debug('QTAUWorkbenchApp', 'fitSectionPanel: %s', ME.message); end
        end

        function fitAllSections(app)
            try
                names = fieldnames(app.SectionPanels);
                for i = 1:numel(names)
                    app.fitSectionPanel(app.SectionPanels.(names{i}));
                end
            catch ME; Logger.debug('QTAUWorkbenchApp', 'fitAllSections: %s', ME.message); end
        end

        function onResizeUI(app)
            app.fitAllSections();
            app.fitAuthOverlay();
        end

        function fitAuthOverlay(app)
            if ~isempty(app.AuthOverlay) && isvalid(app.AuthOverlay)
                pos = app.ContentContainer.Position;
                app.AuthOverlay.Position = [0 0 max(1, pos(3)) max(1, pos(4))];
            end
        end

    end % private methods

    % ── Public helpers (called by ViewModels) ─────────────────────────────────
    methods

        function showAuthOverlay(app)
            if ~isempty(app.AuthOverlay) && isvalid(app.AuthOverlay)
                app.fitAuthOverlay();
                app.AuthOverlay.Visible = 'on';
                uistack(app.AuthOverlay, 'top');
            end
        end

        function hideAuthOverlay(app)
            if ~isempty(app.AuthOverlay) && isvalid(app.AuthOverlay)
                app.AuthOverlay.Visible = 'off';
            end
        end

        % Synchronise HTTP client base URL from AppState.
        function syncClient(app)
            app.Client.setBaseUrl(app.State.baseUrl);
            app.Client.ProjectId = app.State.currentProjectId;
            if ~isempty(app.SettingsBaseUrlField) && isvalid(app.SettingsBaseUrlField)
                app.SettingsBaseUrlField.Value = char(app.State.baseUrl);
            end
        end

        function showLoading(app, msg)
            if nargin < 2; msg = 'Loading...'; end
            try
                % Remove previous overlay if any
                if ~isempty(app.ActivityOverlay) && isvalid(app.ActivityOverlay)
                    delete(app.ActivityOverlay);
                end
                figW = app.UIFigure.Position(3);
                figH = app.UIFigure.Position(4);
                app.ActivityOverlay = uipanel(app.UIFigure, 'Title', '', ...
                    'Units', 'pixels', 'Position', [0 0 figW figH], ...
                    'BackgroundColor', [1 1 1], 'BorderType', 'none');
                og = uigridlayout(app.ActivityOverlay, [3 3]);
                og.RowHeight   = {'1x', 90, '1x'};
                og.ColumnWidth = {'1x', 260, '1x'};
                og.Padding     = [0 0 0 0];
                og.BackgroundColor = [1 1 1];
                host = uigridlayout(og, [1 1]);
                host.Layout.Row = 2; host.Layout.Column = 2;
                host.Padding = [0 0 0 0]; host.BackgroundColor = [1 1 1];
                try
                    sp = uihtml(host);
                    sp.HTMLSource = [ ...
                        '<div style="display:flex;flex-direction:column;align-items:center;' ...
                        'justify-content:center;height:100%;font-family:-apple-system,' ...
                        '''Segoe UI'',Arial,sans-serif;">' ...
                        '<div style="width:36px;height:36px;border:4px solid #dde3ee;' ...
                        'border-top-color:#2952a3;border-radius:50%;' ...
                        'animation:spin 0.85s linear infinite;"></div>' ...
                        '<style>@keyframes spin{to{transform:rotate(360deg)}}</style>' ...
                        '<p style="margin-top:14px;font-size:13px;color:#5a6478;' ...
                        'letter-spacing:0.03em;font-weight:500;">' char(msg) '</p></div>'];
                catch
                    lbl = uilabel(host, 'Text', char(msg), 'FontSize', 14, ...
                        'FontWeight', 'bold', 'FontColor', [0.35 0.42 0.52], ...
                        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
                end
                drawnow();
            catch ME
                Logger.debug('QTAUWorkbenchApp', 'showLoading: %s', ME.message);
            end
        end

        function hideLoading(app)
            try
                if ~isempty(app.ActivityOverlay) && isvalid(app.ActivityOverlay)
                    delete(app.ActivityOverlay);
                    app.ActivityOverlay = [];
                end
                drawnow();
            catch ME
                Logger.debug('QTAUWorkbenchApp', 'hideLoading: %s', ME.message);
            end
        end

        function setStatus(~, area, lines)
            if ischar(lines) || isstring(lines)
                lines = cellstr(string(lines));
            end
            area.Value = lines;
        end

        function logEvent(app, category, msg)
            ts   = char(datetime('now', 'Format', 'HH:mm:ss.SSS'));
            line = sprintf('[%s] %-8s [QTAUWorkbenchApp] %s', ts, upper(char(category)), char(msg));
            if isempty(app.EventLog)
                app.EventLog = {line};
            else
                app.EventLog = [{line}; app.EventLog(1:min(end, 999))];
            end
            fprintf('%s\n', line);
            try
                if ~isempty(app.EventLogArea) && isvalid(app.EventLogArea)
                    app.EventLogArea.Value = app.EventLog(1:min(numel(app.EventLog), 200));
                end
            catch ME; fprintf('[QTAUWorkbenchApp] EventLogArea update: %s\n', ME.message); end
        end

        % showError  Display a standardised error popup with title "Error".
        %   Logs the error and shows a uialert with full context details.
        function showError(app, context, ME)
            msg = sprintf('%s\n\nDetails:\n%s\n\nIdentifier: %s', ...
                char(context), ME.message, ME.identifier);
            app.logEvent('ERROR', sprintf('[%s] %s', char(context), ME.message));
            uialert(app.UIFigure, msg, Labels.get('error_title', 'Error'), 'Icon', 'error');
        end

        function panel = createSectionPage(app, key)
            panel = uipanel(app.ContentContainer, 'Title', '', 'Visible', 'off');
            panel.Position = [0 0 max(1, app.ContentContainer.Position(3)) ...
                                    max(1, app.ContentContainer.Position(4))];
            panel.AutoResizeChildren = 'on';
            panel.Scrollable         = 'on';
            panel.BackgroundColor    = [0.96 0.97 0.99];
            safeKey = matlab.lang.makeValidName(char(key));
            app.SectionPanels.(safeKey) = panel;
        end

        % styleBtn  Apply a consistent palette to any uibutton.
        %   variant: 'primary' | 'secondary' | 'success' | 'danger' | 'ghost'
        function styleBtn(~, btn, variant)
            % Clean macOS-native button style: white bg, dark text, subtle fill variants
            btn.FontSize = 14;
            btn.FontWeight = 'normal';
            btn.BackgroundColor = [1 1 1];
            btn.FontColor       = [0.15 0.15 0.15];
            switch lower(char(variant))
                case 'primary'
                    btn.BackgroundColor = [0.93 0.95 1.00];
                    btn.FontColor       = [0.13 0.33 0.73];
                    btn.FontWeight      = 'bold';
                case 'secondary'
                    btn.BackgroundColor = [0.96 0.96 0.97];
                    btn.FontColor       = [0.15 0.15 0.15];
                case 'success'
                    btn.BackgroundColor = [0.93 0.98 0.94];
                    btn.FontColor       = [0.13 0.40 0.18];
                    btn.FontWeight      = 'bold';
                case 'danger'
                    btn.BackgroundColor = [0.99 0.93 0.93];
                    btn.FontColor       = [0.70 0.15 0.15];
                    btn.FontWeight      = 'bold';
                case 'ghost'
                    btn.BackgroundColor = [0.96 0.96 0.97];
                    btn.FontColor       = [0.25 0.25 0.28];
            end
        end

        function styleAxes(~, ax)
            ax.Box = 'off'; ax.XGrid = 'on'; ax.YGrid = 'on';
            ax.GridColor = [0.82 0.86 0.92]; ax.GridAlpha = 0.9;
            ax.FontSize  = 11; ax.LineWidth = 1;
            ax.Color = [1 1 1];
            ax.XColor = [0.28 0.36 0.48]; ax.YColor = [0.28 0.36 0.48];
            try; axtoolbar(ax, {'zoom','pan','datacursor','restoreview'}); catch ME; Logger.debug('QTAUWorkbenchApp', 'axtoolbar: %s', ME.message); end
        end

        function styleTable(~, tbl)
            try; tbl.RowStriping = 'on'; catch ME; Logger.debug('QTAUWorkbenchApp', 'RowStriping: %s', ME.message); end
            try; tbl.ColumnSortable = true(1, numel(tbl.ColumnName)); catch ME; Logger.debug('QTAUWorkbenchApp', 'ColumnSortable: %s', ME.message); end
        end

        % attachColumnDivider  Registers a panel as a resizable column handle.
        function attachColumnDivider(app, divPanel, g)
            comps = {divPanel};
            try
                for ch = divPanel.Children(:)'
                    comps{end+1} = ch; %#ok
                    try
                        for gc = ch.Children(:)'
                            comps{end+1} = gc; %#ok
                        end
                    catch ME; Logger.debug('QTAUWorkbenchApp', 'Divider grandchildren: %s', ME.message); end
                end
            catch ME; Logger.debug('QTAUWorkbenchApp', 'Divider children: %s', ME.message); end
            app.ColumnDividers{end+1} = struct('comps', {comps}, 'grid', g);
            divPanel.Tooltip = 'Drag left/right to resize panels';
            cb = @(~,~)app.onDividerDown(g);
            for j = 1:numel(comps)
                try; comps{j}.ButtonDownFcn = cb; catch ME; Logger.debug('QTAUWorkbenchApp', 'ButtonDownFcn: %s', ME.message); end
            end
        end
    end

    % ── Lazy ViewModel initialization ────────────────────────────────────────
    methods
        function ensureVm(app, key)
            % Create the ViewModel for the given screen key if it doesn't
            % exist yet.  Called by autoLoadScreen before data-fetching.
            switch key
                case 'Dashboard'
                    if isempty(app.DashboardVm); app.DashboardVm = DashboardViewModel(app); end
                case 'Circuits'
                    if isempty(app.CircuitsVm); app.CircuitsVm = CircuitsViewModel(app); end
                case 'Notes'
                    if isempty(app.NotesVm); app.NotesVm = NotesViewModel(app); end
                case 'Upload'
                    if isempty(app.UploadVm); app.UploadVm = UploadViewModel(app); end
                case 'Analysis'
                    if isempty(app.AnalysisVm); app.AnalysisVm = AnalysisViewModel(app); end
                case 'Backends'
                    if isempty(app.BackendsVm); app.BackendsVm = BackendsViewModel(app); end
                case 'Benchmark'
                    if isempty(app.BenchmarkVm); app.BenchmarkVm = BenchmarkViewModel(app); end
                case 'Prediction'
                    if isempty(app.PredictionVm); app.PredictionVm = PredictionViewModel(app); end
                case 'Jobs'
                    if isempty(app.JobsVm); app.JobsVm = JobsViewModel(app); end
                case 'Results'
                    if isempty(app.ResultsVm); app.ResultsVm = ResultsViewModel(app); end
                case 'DetailedAnalysis'
                    if isempty(app.DetailedAnalysisVm); app.DetailedAnalysisVm = DetailedAnalysisViewModel(app); end
                case 'BenchmarkDashboard'
                    if isempty(app.BenchmarkDashboardVm); app.BenchmarkDashboardVm = BenchmarkDashboardViewModel(app); end
                case 'Reports'
                    if isempty(app.ReportsVm); app.ReportsVm = ReportsViewModel(app); end
                case 'Settings'
                    if isempty(app.SettingsVm); app.SettingsVm = SettingsViewModel(app); end
                case 'QECSimulation'
                    if isempty(app.QecSimulationVm); app.QecSimulationVm = QecSimulationViewModel(app); end
                case 'QECVisualization'
                    if isempty(app.QecVisualizationVm); app.QecVisualizationVm = QecVisualizationViewModel(app); end
            end
        end

        function fresh = isScreenFresh(~, vm, ttlSeconds)
            % Return true if the ViewModel was refreshed within ttlSeconds.
            % VMs that support caching have a LastRefresh property (tic value).
            fresh = false;
            if isempty(vm); return; end
            try
                lr = vm.LastRefresh;
                if ~isempty(lr) && lr > 0
                    fresh = toc(lr) < ttlSeconds;
                end
            catch
                % VM doesn't have LastRefresh — always stale
            end
        end
    end

    % ── Navigation + resize callbacks ─────────────────────────────────────────
    methods
        function onSelectSection(app, key)
            if isstring(key); key = char(key); end
            app.logEvent('NAV', sprintf('Navigating to: %s', key));
            names = fieldnames(app.SectionPanels);
            for i = 1:numel(names)
                app.SectionPanels.(names{i}).Visible = 'off';
            end
            safeKey = matlab.lang.makeValidName(key);
            if isfield(app.SectionPanels, safeKey)
                app.SectionPanels.(safeKey).Visible = 'on';
            end
            app.SectionTitleLabel.Text    = key;
            app.SectionSubtitleLabel.Text = app.sectionSubtitleFor(key);
            if ~strcmp(app.NavList.Value, key)
                app.NavList.Value = key;
            end
            app.updateNavStyles(key);
            app.onResizeUI();
            % Auto-load data when entering a screen
            app.autoLoadScreen(key);
        end

        function autoLoadScreen(app, key)
            % Ensure the ViewModel exists (lazy init), then trigger
            % data-load only if the screen data is stale (> 30 s).
            app.ensureVm(key);
            ttl = AppConfig.getDouble('screen_cache_ttl', 30);

            switch key
                case 'Welcome'
                    if app.State.isAuthenticated() && ~app.isScreenFresh(app.WelcomeVm, ttl)
                        app.WelcomeVm.onFetchProjects();
                    end
                case 'Upload'
                    if ~isempty(app.UploadVm)
                        if ~isempty(app.UploadActiveProjectLabel) && isvalid(app.UploadActiveProjectLabel)
                            projName = app.State.currentProjectName;
                            if strlength(projName) == 0
                                projName = Labels.get('upload_label_no_project');
                            end
                            app.UploadActiveProjectLabel.Text = char(projName);
                        end
                        if ~app.isScreenFresh(app.UploadVm, ttl)
                            app.UploadVm.onRefreshCircuits();
                        end
                    end
                case 'Circuits'
                    if ~isempty(app.CircuitsVm) && app.State.hasProject() ...
                            && ~app.isScreenFresh(app.CircuitsVm, ttl)
                        app.CircuitsVm.onLoadCircuits();
                    end
                case 'Dashboard'
                    if ~isempty(app.DashboardVm) && ~app.isScreenFresh(app.DashboardVm, ttl)
                        app.DashboardVm.onRefreshDashboard();
                    end
                case 'Notes'
                    if ~isempty(app.NotesVm) && app.State.hasProject() ...
                            && ~app.isScreenFresh(app.NotesVm, ttl)
                        app.NotesVm.onLoadNotes();
                    end
                case 'Analysis'
                    if ~isempty(app.AnalysisVm) && ~app.isScreenFresh(app.AnalysisVm, ttl)
                        app.AnalysisVm.onEnter();
                    end
                case 'Backends'
                    if ~isempty(app.BackendsVm) && app.State.isAuthenticated() ...
                            && ~app.isScreenFresh(app.BackendsVm, ttl)
                        app.BackendsVm.onRefreshBackends();
                    end
                case 'Jobs'
                    if ~isempty(app.JobsVm) && app.State.hasProject() ...
                            && ~app.isScreenFresh(app.JobsVm, ttl)
                        app.JobsVm.onRefreshJobs();
                    end
                case 'Results'
                    if ~isempty(app.ResultsVm) && app.State.hasProject() ...
                            && ~app.isScreenFresh(app.ResultsVm, ttl)
                        app.ResultsVm.onRefreshResults();
                    end
            end
        end

        function onToggleNav(app)
            app.NavCollapsed = ~app.NavCollapsed;
            if app.NavCollapsed
                app.BodyGrid.ColumnWidth = {56, '1x'};
                short = app.navCollapsedLabels();
                for i = 1:min(numel(app.NavButtons), numel(short))
                    app.NavButtons(i).Text = short{i};
                    app.NavButtons(i).HorizontalAlignment = 'center';
                end
                app.NavToggleButton.Text = '☰';
            else
                app.BodyGrid.ColumnWidth = {230, '1x'};
                full = app.navMenuLabels();
                for i = 1:min(numel(app.NavButtons), numel(full))
                    app.NavButtons(i).Text = [' ' full{i}];
                    app.NavButtons(i).HorizontalAlignment = 'left';
                end
                app.NavToggleButton.Text = '≡';
            end
            app.updateNavStyles(char(app.NavList.Value));
            app.onResizeUI();
        end

        function onFigMouseDown(app)
            if app.DragState.active; return; end
            try
                clicked = app.UIFigure.CurrentObject;
                if isempty(clicked); return; end
                for k = 1:numel(app.ColumnDividers)
                    entry = app.ColumnDividers{k};
                    for j = 1:numel(entry.comps)
                        try
                            if isvalid(entry.comps{j}) && isequal(clicked, entry.comps{j})
                                app.onDividerDown(entry.grid); return;
                            end
                        catch ME; Logger.debug('QTAUWorkbenchApp', 'Divider comp check: %s', ME.message); end
                    end
                end
            catch ME; Logger.debug('QTAUWorkbenchApp', 'onFigMouseDown: %s', ME.message); end
        end

        function onDividerDown(app, g)
            try
                cw = g.ColumnWidth;
                try; availW = max(300, app.ContentShell.Position(3) - 70); catch ME; Logger.debug('QTAUWorkbenchApp', 'availW fallback: %s', ME.message); availW = 900; end
                if isnumeric(cw{1})
                    w1 = cw{1}; w3 = cw{3};
                else
                    n1 = str2double(strtrim(strrep(char(cw{1}), 'x', '')));
                    n3 = str2double(strtrim(strrep(char(cw{3}), 'x', '')));
                    if isnan(n1); n1 = 1; end; if isnan(n3); n3 = 1; end
                    w1 = availW * n1 / (n1 + n3);
                    w3 = availW * n3 / (n1 + n3);
                end
                app.DragState.active = true; app.DragState.grid = g;
                app.DragState.startX = app.UIFigure.CurrentPoint(1);
                app.DragState.col1W  = w1; app.DragState.col3W = w3;
                app.UIFigure.Pointer = 'lrdrag';
            catch ME; Logger.debug('QTAUWorkbenchApp', 'onDividerDown: %s', ME.message); app.DragState.active = false; end
        end

        function onFigMouseMove(app)
            if ~app.DragState.active; return; end
            try
                dx = app.UIFigure.CurrentPoint(1) - app.DragState.startX;
                app.DragState.grid.ColumnWidth = {max(120, app.DragState.col1W + dx), 6, ...
                                                   max(120, app.DragState.col3W - dx)};
            catch ME; Logger.debug('QTAUWorkbenchApp', 'onFigMouseMove: %s', ME.message); app.DragState.active = false; app.UIFigure.Pointer = 'arrow'; end
        end

        function onFigMouseUp(app)
            if app.DragState.active
                app.DragState.active = false;
                app.UIFigure.Pointer = 'arrow';
            end
        end
    end

end
