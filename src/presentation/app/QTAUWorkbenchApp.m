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
    end

    % ── Shared services ───────────────────────────────────────────────────────
    properties
        State           % AppState
        Client          % FastAPIClient
        CircuitSvc      % CircuitService
        BackendSvc      % BackendService
        JobSvc          % JobService
        ProjectSvc      % ProjectService
        PredictionSvc   % PredictionService
        ReportSvc       % ReportService
        SettingsSvc     % SettingsService
    end

    % ── Screen callback services ──────────────────────────────────────────────
    properties
        WelcomeVm           % WelcomeViewModel
        DashboardVm         % DashboardViewModel
        NotesVm             % NotesViewModel
        UploadVm            % UploadViewModel
        AnalysisVm          % AnalysisViewModel
        BackendsVm          % BackendsViewModel
        BenchmarkVm         % BenchmarkViewModel
        PredictionVm        % PredictionViewModel
        JobsVm              % JobsViewModel
        ResultsVm           % ResultsViewModel
        DetailedAnalysisVm  % DetailedAnalysisViewModel
        ReportsVm           % ReportsViewModel
        SettingsVm          % SettingsViewModel
    end

    % ── Login dialog ──────────────────────────────────────────────────────────
    properties
        LoginDialog                % modal uifigure
        LoginDlgBaseUrlField       % Base URL edit field in dialog
        LoginDlgUsernameField      % Username edit field in dialog
        LoginDlgPasswordField      % Password edit field (displays masked dots)
        LoginDlgPasswordReal       % Real password string (stored separately)
        LoginDlgStatusLabel        % Status label in dialog
    end

    % ── Welcome tab ───────────────────────────────────────────────────────────
    properties
        UserInfoArea
        ProjectsTable
        ProjectsPageLabel          % "Page X of Y"
        ProjectsPrevButton
        ProjectsNextButton
        WelcomeLogoutButton        % Logout button on Welcome screen
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
    end

    % ── Analysis tab ──────────────────────────────────────────────────────────
    properties
        AnalyzeButton
        FeatureTree
        AnalysisFeatureArea     % annotation text beside the tree
        SimilarityTable
        AnalysisCompareArea     % detailed comparison notes
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
        CompareAxes
        TemporalAxes
        QubitAxes
        DetailedInsightArea
        RefreshCompareButton
        RefreshTemporalButton
        RefreshQubitButton
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
            app.Client        = FastAPIClient(app.State.baseUrl);
            app.CircuitSvc    = CircuitService(app.Client);
            app.BackendSvc    = BackendService(app.Client);
            app.JobSvc        = JobService(app.Client);
            app.ProjectSvc    = ProjectService(app.Client);
            app.PredictionSvc = PredictionService(app.Client);
            app.ReportSvc     = ReportService(app.Client);
            app.SettingsSvc   = SettingsService(app.Client);
            Logger.info('QTAUWorkbenchApp', 'All services initialized — creating screen callback objects');
            app.WelcomeVm          = WelcomeViewModel(app);
            app.DashboardVm        = DashboardViewModel(app);
            app.NotesVm            = NotesViewModel(app);
            app.UploadVm           = UploadViewModel(app);
            app.AnalysisVm         = AnalysisViewModel(app);
            app.BackendsVm         = BackendsViewModel(app);
            app.BenchmarkVm        = BenchmarkViewModel(app);
            app.PredictionVm       = PredictionViewModel(app);
            app.JobsVm             = JobsViewModel(app);
            app.ResultsVm          = ResultsViewModel(app);
            app.DetailedAnalysisVm = DetailedAnalysisViewModel(app);
            app.ReportsVm          = ReportsViewModel(app);
            app.SettingsVm         = SettingsViewModel(app);
            Logger.info('QTAUWorkbenchApp', 'Screen callback objects ready — building UI');
            app.buildUI();
            app.logEvent('UI', 'QTAUWorkbenchApp started');
            app.forceInitialLayout();
            Logger.info('QTAUWorkbenchApp', '=== QTAUWorkbenchApp ready ===');
        end

        function delete(app)
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch
            end
        end
    end

    % Callable from src/presentation/screens/*.m (package-less functions cannot use private methods).
    methods
        function updateWelcomeAuthButtons(app)
            if isempty(app.WelcomeLogoutButton) || ~isvalid(app.WelcomeLogoutButton)
                return;
            end
            if app.State.isAuthenticated()
                app.WelcomeLogoutButton.Visible = 'on';
            else
                app.WelcomeLogoutButton.Visible = 'off';
            end
        end

        function showLoginDialog(app)
            % Create modal login dialog — modern card layout centred over main figure
            figPos = app.UIFigure.Position;
            dlgW = 440; dlgH = 480;
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            app.LoginDialog = uifigure('Name', Labels.get('login_dlg_title', 'Login'), ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'off', ...
                'Color', [0.95 0.96 0.98]);

            % ── Outer grid: centres the card vertically & horizontally ───────
            outerGrid = uigridlayout(app.LoginDialog, [3 3]);
            outerGrid.RowHeight   = {16, '1x', 28};
            outerGrid.ColumnWidth = {24, '1x', 24};
            outerGrid.Padding     = [0 0 0 0];
            outerGrid.RowSpacing  = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = [0.95 0.96 0.98];

            % ── Card panel ───────────────────────────────────────────────────
            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', [1 1 1], ...
                'HighlightColor', [0.88 0.89 0.92], ...
                'ShadowColor', [0.88 0.89 0.92]);
            card.Layout.Row = 2; card.Layout.Column = 2;

            % 11 rows: brand icon | brand text | subtitle | spacer |
            %          baseurl label | baseurl field | user label | user field |
            %          pass label | pass field | spacer | login btn |
            %          status | help link
            cg = uigridlayout(card, [14 1]);
            cg.RowHeight   = {40, 28, 20, 12, ...   % brand icon, title, subtitle, spacer
                              16, 34, 16, 34, ...    % url label, url field, user label, user field
                              16, 34, 14, ...         % pass label, pass field, spacer
                              42, 22, 18};            % login btn, status, help
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [36 28 36 20];
            cg.RowSpacing  = 2;
            cg.BackgroundColor = [1 1 1];

            % Row 1 — Brand icon (quantum atom symbol)
            brandIcon = uilabel(cg, 'Text', char(9883), ...
                'FontSize', 30, 'FontColor', [0.26 0.52 0.96], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            brandIcon.Layout.Row = 1; brandIcon.Layout.Column = 1;

            % Row 2 — Brand title
            brandTitle = uilabel(cg, 'Text', Labels.get('login_dlg_brand', 'QTAU Connector'), ...
                'FontSize', 20, 'FontWeight', 'bold', ...
                'FontColor', [0.15 0.18 0.24], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
            brandTitle.Layout.Row = 2; brandTitle.Layout.Column = 1;

            % Row 3 — Subtitle
            subtitleLbl = uilabel(cg, 'Text', Labels.get('login_dlg_subtitle', 'Sign in to your workspace'), ...
                'FontSize', 12, 'FontColor', [0.45 0.50 0.58], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            subtitleLbl.Layout.Row = 3; subtitleLbl.Layout.Column = 1;

            % Row 4 — spacer (empty)

            % Row 5 — Base URL label
            urlLbl = uilabel(cg, 'Text', Labels.get('welcome_label_base_url', 'Base URL'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', [0.30 0.34 0.42], ...
                'VerticalAlignment', 'bottom');
            urlLbl.Layout.Row = 5; urlLbl.Layout.Column = 1;

            % Row 6 — Base URL field
            app.LoginDlgBaseUrlField = uieditfield(cg, 'text', ...
                'Value', AppConfig.get('base_url', 'http://34.42.87.190:5715'), ...
                'Placeholder', Labels.get('login_dlg_placeholder_url', 'https://your-server:port'), ...
                'FontSize', 13);
            app.LoginDlgBaseUrlField.Layout.Row = 6; app.LoginDlgBaseUrlField.Layout.Column = 1;

            % Row 7 — Username label
            userLbl = uilabel(cg, 'Text', Labels.get('welcome_label_username', 'Username'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', [0.30 0.34 0.42], ...
                'VerticalAlignment', 'bottom');
            userLbl.Layout.Row = 7; userLbl.Layout.Column = 1;

            % Row 8 — Username field
            app.LoginDlgUsernameField = uieditfield(cg, 'text', 'Value', '', ...
                'Placeholder', Labels.get('login_dlg_placeholder_user', 'Enter your username'), ...
                'FontSize', 13);
            app.LoginDlgUsernameField.Layout.Row = 8; app.LoginDlgUsernameField.Layout.Column = 1;

            % Row 9 — Password label
            passLbl = uilabel(cg, 'Text', Labels.get('welcome_label_password', 'Password'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', [0.30 0.34 0.42], ...
                'VerticalAlignment', 'bottom');
            passLbl.Layout.Row = 9; passLbl.Layout.Column = 1;

            % Row 10 — Password field (dot-masked)
            app.LoginDlgPasswordReal = '';
            app.LoginDlgPasswordField = uieditfield(cg, 'text', 'Value', '', ...
                'Placeholder', Labels.get('login_dlg_placeholder_pass', 'Enter your password'), ...
                'FontSize', 13);
            app.LoginDlgPasswordField.Layout.Row = 10; app.LoginDlgPasswordField.Layout.Column = 1;
            app.LoginDlgPasswordField.ValueChangingFcn = @(~, evt) app.onPasswordChanging(evt);

            % Row 11 — spacer (empty)

            % Row 12 — Login button (Google Blue accent)
            loginBtn = uibutton(cg, 'Text', Labels.get('welcome_btn_login', 'Sign in'), ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onLogin(), ...
                'FontSize', 14, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], ...
                'BackgroundColor', [0.26 0.52 0.96]);
            loginBtn.Layout.Row = 12; loginBtn.Layout.Column = 1;

            % Row 13 — Status label (error messages)
            app.LoginDlgStatusLabel = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', [0.84 0.18 0.18], ...
                'WordWrap', 'on', 'HorizontalAlignment', 'center');
            app.LoginDlgStatusLabel.Layout.Row = 13; app.LoginDlgStatusLabel.Layout.Column = 1;

            % Row 14 — Help / forgot link
            helpLbl = uilabel(cg, 'Text', Labels.get('login_dlg_forgot', 'Forgot credentials? Contact your admin.'), ...
                'FontSize', 10, 'FontColor', [0.55 0.58 0.64], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            helpLbl.Layout.Row = 14; helpLbl.Layout.Column = 1;

            % ── Version footer outside the card ──────────────────────────────
            verLbl = uilabel(outerGrid, 'Text', Labels.get('login_dlg_version', 'QTAU Connector Workspace v2026'), ...
                'FontSize', 9, 'FontColor', [0.60 0.63 0.68], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
            verLbl.Layout.Row = 3; verLbl.Layout.Column = 2;

            Logger.info('QTAUWorkbenchApp', 'Login dialog shown');
        end

        function onPasswordChanging(app, evt)
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
    end

    % ── UI construction (private) ─────────────────────────────────────────────
    methods (Access = private)

        function buildUI(app)
            app.UIFigure = uifigure('Name', 'Tunning Analysis', ...
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
            NotesScreen(app);
            UploadScreen(app);
            AnalysisScreen(app);
            BackendsScreen(app);
            BenchmarkScreen(app);
            PredictionScreen(app);
            JobsScreen(app);
            ResultsScreen(app);
            DetailedAnalysisScreen(app);
            ReportsScreen(app);
            SettingsScreen(app);
            drawnow();

            app.onSelectSection('Welcome');
            app.fitAllSections();
            app.onResizeUI();
            drawnow();
            app.forceInitialLayout();

            try
                if ~isempty(app.LoadingOverlay) && isvalid(app.LoadingOverlay)
                    delete(app.LoadingOverlay);
                    app.LoadingOverlay = [];
                end
            catch; end
            drawnow();

            try
                t = timer('ExecutionMode','singleShot','StartDelay',0.15, ...
                    'TimerFcn', @(~,~)app.forceInitialLayout());
                start(t);
            catch; end

            % Auto-show login dialog if not yet authenticated
            if ~app.State.isAuthenticated()
                app.showLoginDialog();
            end
        end

        function buildHeader(app)
            app.HeaderGrid = uigridlayout(app.RootGrid, [1 3]);
            app.HeaderGrid.Layout.Row    = 1;
            app.HeaderGrid.Layout.Column = 1;
            app.HeaderGrid.ColumnWidth   = {250, '1x', 240};
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
            subtitle.FontSize = 14;
            subtitle.HorizontalAlignment = 'center';
            subtitle.FontColor = [0.80 0.87 0.97];
            subtitle.Layout.Row = 1; subtitle.Layout.Column = 2;

            userBadge = uilabel(app.HeaderGrid, 'Text', 'SQK Admin Workspace');
            userBadge.FontSize = 13; userBadge.FontWeight = 'bold';
            userBadge.HorizontalAlignment = 'right';
            userBadge.FontColor = [1 1 1];
            userBadge.Layout.Row = 1; userBadge.Layout.Column = 3;
            userBadge.Tooltip = 'QTAU Connector v2026';
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

            navBtnsGrid = uigridlayout(navBtnsPanel, [13 1]);
            navBtnsGrid.RowHeight = repmat({32}, 1, 13);
            navBtnsGrid.Padding = [0 0 0 0]; navBtnsGrid.RowSpacing = 6;
            navBtnsGrid.BackgroundColor = [0.12 0.19 0.31];

            names  = {'Welcome','Dashboard','Notes','Upload','Analysis','Backends', ...
                      'Benchmark','Prediction','Jobs','Results','Detailed Analysis','Reports','Settings'};
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
            shellGrid.RowHeight  = {72, 1, '1x'};
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
            app.SectionTitleLabel.FontSize = 24; app.SectionTitleLabel.FontWeight = 'bold';
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

        % ── Section metadata — loaded from labels.properties ─────────────────
        function subtitle = sectionSubtitleFor(~, key)
            keyMap = struct( ...
                'Welcome',         'subtitle_welcome', ...
                'Dashboard',       'subtitle_dashboard', ...
                'Notes',           'subtitle_notes', ...
                'Upload',          'subtitle_upload', ...
                'Analysis',        'subtitle_analysis', ...
                'Backends',        'subtitle_backends', ...
                'Benchmark',       'subtitle_benchmark', ...
                'Prediction',      'subtitle_prediction', ...
                'Jobs',            'subtitle_jobs', ...
                'Results',         'subtitle_results', ...
                'DetailedAnalysis','subtitle_detailed_analysis', ...
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
                Labels.get('nav_notes',             '✎  Notes'), ...
                Labels.get('nav_upload',            '⤴  Upload'), ...
                Labels.get('nav_analysis',          '⌕  Analysis'), ...
                Labels.get('nav_backends',          '⌬  Backends'), ...
                Labels.get('nav_benchmark',         '◎  Benchmark'), ...
                Labels.get('nav_prediction',        '◇  Prediction'), ...
                Labels.get('nav_jobs',              '▣  Jobs'), ...
                Labels.get('nav_results',           '□  Results'), ...
                Labels.get('nav_detailed_analysis', '△  Detailed Analysis'), ...
                Labels.get('nav_reports',           '▤  Reports'), ...
                Labels.get('nav_settings',          '⚙  Settings')};
        end

        function labels = navCollapsedLabels(~)
            labels = { ...
                Labels.get('nav_short_welcome',           '⌂'), ...
                Labels.get('nav_short_dashboard',         '◫'), ...
                Labels.get('nav_short_notes',             '✎'), ...
                Labels.get('nav_short_upload',            '⤴'), ...
                Labels.get('nav_short_analysis',          '⌕'), ...
                Labels.get('nav_short_backends',          '⌬'), ...
                Labels.get('nav_short_benchmark',         '◎'), ...
                Labels.get('nav_short_prediction',        '◇'), ...
                Labels.get('nav_short_jobs',              '▣'), ...
                Labels.get('nav_short_results',           '□'), ...
                Labels.get('nav_short_detailed_analysis', '△'), ...
                Labels.get('nav_short_reports',           '▤'), ...
                Labels.get('nav_short_settings',          '⚙')};
        end

        function forceInitialLayout(app)
            try
                drawnow(); pause(0.05);
                app.fitAllSections(); app.onResizeUI();
                drawnow(); pause(0.02);
                app.fitAllSections();
            catch; end
        end

        function updateNavStyles(app, activeKey)
            names = {'Welcome','Dashboard','Notes','Upload','Analysis','Backends', ...
                'Benchmark','Prediction','Jobs','Results','Detailed Analysis','Reports','Settings'};
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
            catch; end
        end

        function fitAllSections(app)
            try
                names = fieldnames(app.SectionPanels);
                for i = 1:numel(names)
                    app.fitSectionPanel(app.SectionPanels.(names{i}));
                end
            catch; end
        end

        function onResizeUI(app)
            app.fitAllSections();
        end

    end % private methods

    % ── Public helpers (called by ViewModels) ─────────────────────────────────
    methods

        % Synchronise HTTP client base URL from AppState.
        function syncClient(app)
            app.Client.setBaseUrl(app.State.baseUrl);
            if ~isempty(app.SettingsBaseUrlField) && isvalid(app.SettingsBaseUrlField)
                app.SettingsBaseUrlField.Value = char(app.State.baseUrl);
            end
        end

        function setStatus(~, area, lines)
            if ischar(lines) || isstring(lines)
                lines = cellstr(string(lines));
            end
            area.Value = lines;
        end

        function logEvent(app, category, msg)
            ts   = datestr(now, 'HH:MM:SS.FFF'); %#ok<TNOW1,DATST>
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
            catch; end
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
            btn.FontSize = 13;
            switch lower(char(variant))
                case 'primary'
                    btn.BackgroundColor = [0.78 0.80 0.83];
                    btn.FontColor       = [0.10 0.12 0.16];
                    btn.FontWeight      = 'bold';
                case 'secondary'
                    btn.BackgroundColor = [0.84 0.86 0.88];
                    btn.FontColor       = [0.18 0.22 0.28];
                    btn.FontWeight      = 'normal';
                case 'success'
                    btn.BackgroundColor = [0.83 0.87 0.84];
                    btn.FontColor       = [0.12 0.20 0.14];
                    btn.FontWeight      = 'bold';
                case 'danger'
                    btn.BackgroundColor = [0.88 0.84 0.84];
                    btn.FontColor       = [0.28 0.10 0.10];
                    btn.FontWeight      = 'bold';
                case 'ghost'
                    btn.BackgroundColor = [0.92 0.93 0.94];
                    btn.FontColor       = [0.28 0.32 0.38];
                    btn.FontWeight      = 'normal';
                otherwise
                    btn.BackgroundColor = [0.90 0.91 0.92];
                    btn.FontColor       = [0.22 0.26 0.32];
                    btn.FontWeight      = 'normal';
            end
        end

        function styleAxes(~, ax)
            ax.Box = 'off'; ax.XGrid = 'on'; ax.YGrid = 'on';
            ax.GridColor = [0.82 0.86 0.92]; ax.GridAlpha = 0.9;
            ax.FontSize  = 11; ax.LineWidth = 1;
            ax.Color = [1 1 1];
            ax.XColor = [0.28 0.36 0.48]; ax.YColor = [0.28 0.36 0.48];
            try; axtoolbar(ax, {'zoom','pan','datacursor','restoreview'}); catch; end
        end

        function styleTable(~, tbl)
            try; tbl.RowStriping = 'on'; catch; end
            try; tbl.ColumnSortable = true(1, numel(tbl.ColumnName)); catch; end
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

end
