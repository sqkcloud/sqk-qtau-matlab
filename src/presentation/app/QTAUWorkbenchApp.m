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
        LoginDlgBaseUrlField       % Base URL uihtml input
        LoginDlgBaseUrlValue       % Current base URL string (synced from HTML)
        LoginDlgUsernameField      % Username uihtml input
        LoginDlgUsernameValue      % Current username string (synced from HTML)
        LoginDlgPasswordField      % Password uihtml input (native masking)
        LoginDlgPasswordReal       % Real password string (synced from HTML)
        LoginDlgPasswordVisible    % (unused — managed in HTML)
        LoginDlgEyeButton          % (unused — integrated in password HTML)
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
        DashboardSummaryArea
        DashboardStatusArea
        DashboardRefreshButton
        DashKpiLabels
        DashActivityTable
        DashActivityPrevBtn
        DashActivityPageLabel
        DashActivityNextBtn
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
        CircuitsTable
        CircuitsSearchField
        CircuitsPageLabel
        CircuitsPrevBtn
        CircuitsNextBtn
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
        FeatureTree
        AnalysisFeatureArea
        SimilarityTable
        AnalysisCompareArea
        QVHeatmapAxes
        QVInfoLabel
    end

    % ── Backends tab ──────────────────────────────────────────────────────────
    properties
        BackendTable
        BackendStatusArea
        RefreshBackendsButton
        SelectBackendButton
        BackendKpiLabels
        BackendsSearchField
        BackendsPrevBtn
        BackendsNextBtn
        BackendsPageLabel
        BackendsPopupPanel
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
        CompareAxes
        ErrorHeatmapAxes
        TemporalAxes
        QubitAxes
        RBDecayAxes
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
            app.BenchmarkSvc  = app.Services.BenchmarkSvc;

            Logger.info('QTAUWorkbenchApp', 'Services ready — creating WelcomeVm (lazy init for others)');
            app.WelcomeVm = WelcomeViewModel(app);

            app.buildUI();
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
        function showLoading(app, msg, showTimer)
            if nargin < 2; msg = 'Loading...'; end
            if nargin < 3; showTimer = false; end
            OverlayManager.showLoading(app, msg, showTimer);
        end

        function hideLoading(app)
            OverlayManager.hideLoading(app);
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
            DialogBuilder.buildLoginDialog(app);
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
                    d = app.LoginDlgBaseUrlField.Data;
                    if isempty(d), return; end
                    app.LoginDlgBaseUrlValue = char(string(d.v));
                case 'username'
                    d = app.LoginDlgUsernameField.Data;
                    if isempty(d), return; end
                    app.LoginDlgUsernameValue = char(string(d.v));
            end
            if string(d.a) == "enter"
                app.WelcomeVm.onLogin();
            end
        end

        function onPasswordHtmlData(app, ~)
            d = app.LoginDlgPasswordField.Data;
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

        % -- Column divider registration ---------------------------------------
        function attachColumnDivider(app, divPanel, g)
            comps = {divPanel};
            try
                for ch = divPanel.Children(:)'
                    comps{end+1} = ch; %#ok
                    try
                        for gc = ch.Children(:)'
                            comps{end+1} = gc; %#ok
                        end
                    catch; end
                end
            catch; end
            app.ColumnDividers{end+1} = struct('comps', {comps}, 'grid', g);
            divPanel.Tooltip = 'Drag left/right to resize panels';
            cb = @(~,~)app.onDividerDown(g);
            for j = 1:numel(comps)
                try; comps{j}.ButtonDownFcn = cb; catch; end
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

        % -- Drag / resize callbacks -------------------------------------------
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
                        catch; end
                    end
                end
            catch; end
        end

        function onDividerDown(app, g)
            try
                cw = g.ColumnWidth;
                try; availW = max(300, app.ContentShell.Position(3) - 70); catch; availW = 900; end
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
            catch; app.DragState.active = false; end
        end

        function onFigMouseMove(app)
            if ~app.DragState.active; return; end
            try
                dx = app.UIFigure.CurrentPoint(1) - app.DragState.startX;
                app.DragState.grid.ColumnWidth = {max(120, app.DragState.col1W + dx), 6, ...
                                                   max(120, app.DragState.col3W - dx)};
            catch; app.DragState.active = false; app.UIFigure.Pointer = 'arrow'; end
        end

        function onFigMouseUp(app)
            if app.DragState.active
                app.DragState.active = false;
                app.UIFigure.Pointer = 'arrow';
            end
        end
    end

    % ── Private: UI construction (delegates to LayoutBuilder) ─────────────────
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
            LayoutBuilder.buildAuthOverlay(app);
            drawnow();

            app.onSelectSection('Welcome');
            NavigationManager.fitAllSections(app);
            app.onResizeUI();
            drawnow();
            NavigationManager.forceInitialLayout(app);

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
                    'TimerFcn', @(~,~)NavigationManager.forceInitialLayout(app), ...
                    'StopFcn', @(tObj,~)delete(tObj));
                start(t);
            catch ME; Logger.debug('QTAUWorkbenchApp', 'Layout timer init: %s', ME.message); end

            if ~app.State.isAuthenticated()
                app.showLoginDialog();
            end
        end

    end

end
