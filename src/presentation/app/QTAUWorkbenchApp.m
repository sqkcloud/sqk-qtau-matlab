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
        Client          % FastAPIClient
        AuthSvc         % AuthService
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

    % ── Welcome tab ───────────────────────────────────────────────────────────
    properties
        UserInfoArea
        ActiveProjectLabel         % Active Project name display in box
        ProjectsTable
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
        AnalysisCircuitDropdown     % Circuit selector dropdown
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
            app.AuthSvc       = AuthService(app.Client);
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
            % Create modal login dialog — Google-inspired professional layout
            figPos = app.UIFigure.Position;
            dlgW = 480; dlgH = 520;
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            % Google-inspired color palette
            bgColor     = [0.965 0.969 0.976];   % #f7f8f9 — page background
            cardBg      = [1 1 1];                % white card
            cardBorder  = [0.855 0.863 0.878];    % #dadce0
            titleColor  = [0.125 0.129 0.141];    % #202124
            subtColor   = [0.373 0.392 0.424];    % #5f6368
            labelColor  = [0.373 0.392 0.424];    % #5f6368
            fieldColor  = [0.125 0.129 0.141];    % #202124
            accentBlue  = [0.102 0.451 0.910];    % #1a73e8
            errorRed    = [0.851 0.188 0.145];    % #d93025
            footerColor = [0.584 0.604 0.643];    % #959aa4

            app.LoginDialog = uifigure( ...
                'Name', Labels.get('login_dlg_title', 'Sign In'), ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'off', ...
                'Color', bgColor);

            % ── Outer grid: top spacer + card + footer ───────────────────────
            outerGrid = uigridlayout(app.LoginDialog, [3 3]);
            outerGrid.RowHeight   = {16, '1x', 28};
            outerGrid.ColumnWidth = {36, '1x', 36};
            outerGrid.Padding     = [0 0 0 0];
            outerGrid.RowSpacing  = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = bgColor;

            % ── Card panel ───────────────────────────────────────────────────
            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, ...
                'HighlightColor', cardBorder, ...
                'BorderColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            % Card inner grid — generous spacing for Google-like airiness
            % logo | title | subtitle | gap1 |
            % url-lbl | url-field | gap2 | user-lbl | user-field |
            % gap3 | pass-lbl | pass-row | forgot | gap4 |
            % sign-in | status
            cg = uigridlayout(card, [15 1]);
            cg.RowHeight = {32, ...     %  1: "Sign in" title
                            20, ...     %  2: subtitle
                            12, ...     %  3: gap
                            16, ...     %  4: Server URL label
                            36, ...     %  5: Server URL field
                            8, ...      %  6: gap
                            16, ...     %  7: Username label
                            36, ...     %  8: Username field
                            8, ...      %  9: gap
                            16, ...     % 10: Password label
                            36, ...     % 11: Password row
                            20, ...     % 12: Forgot link
                            12, ...     % 13: gap
                            40, ...     % 14: Sign In button
                            20};        % 15: Status / error
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [32 24 32 18];
            cg.RowSpacing  = 2;
            cg.BackgroundColor = cardBg;

            % Row 1 — "Sign in" title
            titleLbl = uilabel(cg, 'Text', Labels.get('login_dlg_sign_in', 'Sign in'), ...
                'FontSize', 24, 'FontWeight', 'bold', ...
                'FontColor', titleColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            % Row 2 — Subtitle
            subLbl = uilabel(cg, ...
                'Text', Labels.get('login_dlg_subtitle', 'to continue to QTAU Connector'), ...
                'FontSize', 13, 'FontColor', subtColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            % Row 3 — gap

            % Row 4 — Server URL label
            urlLbl = uilabel(cg, ...
                'Text', Labels.get('welcome_label_base_url', 'Server URL'), ...
                'FontSize', 12, 'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            urlLbl.Layout.Row = 4; urlLbl.Layout.Column = 1;

            % Row 5 — Server URL field
            app.LoginDlgBaseUrlField = uieditfield(cg, 'text', ...
                'Value', char(app.State.baseUrl), ...
                'Placeholder', Labels.get('login_dlg_placeholder_url', 'https://your-server:port'), ...
                'FontSize', 14, 'FontColor', fieldColor);
            app.LoginDlgBaseUrlField.Layout.Row = 5;
            app.LoginDlgBaseUrlField.Layout.Column = 1;

            % Row 6 — gap

            % Row 7 — Username label
            userLbl = uilabel(cg, ...
                'Text', Labels.get('welcome_label_username', 'Username'), ...
                'FontSize', 12, 'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            userLbl.Layout.Row = 7; userLbl.Layout.Column = 1;

            % Row 8 — Username field
            app.LoginDlgUsernameField = uieditfield(cg, 'text', 'Value', '', ...
                'Placeholder', Labels.get('login_dlg_placeholder_user', 'Enter your username'), ...
                'FontSize', 14, 'FontColor', fieldColor);
            app.LoginDlgUsernameField.Layout.Row = 8;
            app.LoginDlgUsernameField.Layout.Column = 1;

            % Row 9 — gap

            % Row 10 — Password label
            passLbl = uilabel(cg, ...
                'Text', Labels.get('welcome_label_password', 'Password'), ...
                'FontSize', 12, 'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            passLbl.Layout.Row = 10; passLbl.Layout.Column = 1;

            % Row 11 — Password field + Show/Hide toggle
            app.LoginDlgPasswordReal    = '';
            app.LoginDlgPasswordVisible = false;
            passRow = uigridlayout(cg, [1 2]);
            passRow.Layout.Row = 11; passRow.Layout.Column = 1;
            passRow.ColumnWidth = {'1x', 34};
            passRow.Padding = [0 0 0 0]; passRow.ColumnSpacing = 8;
            passRow.BackgroundColor = cardBg;

            app.LoginDlgPasswordField = uieditfield(passRow, 'text', 'Value', '', ...
                'Placeholder', Labels.get('login_dlg_placeholder_pass', 'Enter your password'), ...
                'FontSize', 14, 'FontColor', fieldColor);
            app.LoginDlgPasswordField.Layout.Row = 1;
            app.LoginDlgPasswordField.Layout.Column = 1;
            app.LoginDlgPasswordField.ValueChangingFcn = ...
                @(~, evt) app.onPasswordChanging(evt);

            eyeSvgOpen  = '<svg viewBox="0 0 24 24" width="20" height="20"><path fill="#FIL" d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zm0 12.5c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z"/></svg>';
            eyeSvgSlash = '<svg viewBox="0 0 24 24" width="20" height="20"><path fill="#FIL" d="M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C11.74 7.13 12.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z"/></svg>';
            eyeColor = '6B7280';
            htmlTpl = [ ...
                '<html><head><style>' ...
                'body{margin:0;display:flex;align-items:center;justify-content:center;height:100%%;' ...
                'cursor:pointer;background:BGC;user-select:none;box-sizing:border-box;' ...
                'border:1px solid #dadce0;border-radius:6px;}' ...
                'div:hover{opacity:0.7;}' ...
                '</style></head><body>' ...
                '<div id="eyeBtn" title="Show or hide password">SVG</div>' ...
                '<script>' ...
                'function setup(comp){document.getElementById("eyeBtn").addEventListener("click",function(){comp.Data=Date.now();});}' ...
                '</script></body></html>'];
            openSvg  = strrep(eyeSvgOpen,  '#FIL', ['#' eyeColor]);
            slashSvg = strrep(eyeSvgSlash, '#FIL', ['#' eyeColor]);
            app.LoginDlgEyeButton = uihtml(passRow);
            app.LoginDlgEyeButton.Layout.Row = 1;
            app.LoginDlgEyeButton.Layout.Column = 2;
            app.LoginDlgEyeButton.HTMLSource = strrep(strrep(htmlTpl, 'SVG', slashSvg), 'BGC', '#f8f9fc');
            app.LoginDlgEyeButton.DataChangedFcn = @(~,~)app.onTogglePasswordVisibility();
            app.LoginDlgEyeButton.UserData = struct( ...
                'hiddenHtml', strrep(strrep(htmlTpl, 'SVG', slashSvg), 'BGC', '#f8f9fc'), ...
                'visibleHtml', strrep(strrep(htmlTpl, 'SVG', openSvg), 'BGC', '#f8f9fc'));

            % Row 12 — Forgot credentials link (blue, left-aligned)
            helpLbl = uilabel(cg, ...
                'Text', Labels.get('login_dlg_forgot', 'Forgot credentials? Contact your admin.'), ...
                'FontSize', 11, 'FontColor', accentBlue, ...
                'HorizontalAlignment', 'left', 'VerticalAlignment', 'center');
            helpLbl.Layout.Row = 12; helpLbl.Layout.Column = 1;

            % Row 13 — gap

            % Row 14 — Sign In button (Google blue, bold)
            loginBtn = uibutton(cg, ...
                'Text', Labels.get('welcome_btn_login', 'Sign In'), ...
                'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], ...
                'BackgroundColor', accentBlue, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onLogin());
            loginBtn.Layout.Row = 14; loginBtn.Layout.Column = 1;

            % Row 15 — Status / error label
            app.LoginDlgStatusLabel = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', errorRed, ...
                'WordWrap', 'on', 'HorizontalAlignment', 'center');
            app.LoginDlgStatusLabel.Layout.Row = 15;
            app.LoginDlgStatusLabel.Layout.Column = 1;

            % ── Version footer below card ────────────────────────────────────
            verLbl = uilabel(outerGrid, ...
                'Text', Labels.get('login_dlg_version', 'QTAU Connector Workspace v2026'), ...
                'FontSize', 9, 'FontColor', footerColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
            verLbl.Layout.Row = 3; verLbl.Layout.Column = 2;

            % Enter key triggers login from anywhere in the dialog
            app.LoginDialog.KeyPressFcn = @(~, evt) app.onLoginKeyPress(evt);

            Logger.info('QTAUWorkbenchApp', 'Login dialog shown');
        end

        function showNewProjectDialog(app)
            % Create modal New Project dialog — modern card layout matching login style
            figPos = app.UIFigure.Position;
            dlgW = 480; dlgH = 520;
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            app.NewProjectDialog = uifigure( ...
                'Name', Labels.get('new_proj_dlg_title', 'New Project'), ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'off', ...
                'Color', [0.95 0.96 0.98]);

            % ── Outer grid: centres the card ────────────────────────────────
            outerGrid = uigridlayout(app.NewProjectDialog, [3 3]);
            outerGrid.RowHeight     = {16, '1x', 16};
            outerGrid.ColumnWidth   = {24, '1x', 24};
            outerGrid.Padding       = [0 0 0 0];
            outerGrid.RowSpacing    = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = [0.95 0.96 0.98];

            % ── Card panel ──────────────────────────────────────────────────
            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', [1 1 1], ...
                'HighlightColor', [0.88 0.89 0.92], ...
                'BorderColor', [0.88 0.89 0.92]);
            card.Layout.Row = 2; card.Layout.Column = 2;

            % 11 rows: title | subtitle | spacer |
            %          name label | name field | desc label | desc area |
            %          tags label | tags field | spacer |
            %          button bar | status
            cg = uigridlayout(card, [12 1]);
            cg.RowHeight = {28, 18, 10, ...          % title, subtitle, spacer
                            16, 34, 16, 90, ...      % name lbl, name field, desc lbl, desc area
                            16, 34, 14, ...           % tags lbl, tags field, spacer
                            42, 20};                  % button bar, status
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [36 24 36 20];
            cg.RowSpacing  = 2;
            cg.BackgroundColor = [1 1 1];

            % Row 1 — Title
            titleLbl = uilabel(cg, 'Text', Labels.get('new_proj_dlg_heading', 'Create New Project'), ...
                'FontSize', 19, 'FontWeight', 'bold', ...
                'FontColor', [0.15 0.18 0.24], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            % Row 2 — Subtitle
            subLbl = uilabel(cg, 'Text', Labels.get('new_proj_dlg_subtitle', 'Set up a new quantum experiment workspace'), ...
                'FontSize', 11, 'FontColor', [0.45 0.50 0.58], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            % Row 3 — spacer

            % Row 4 — Project Name label
            nameLbl = uilabel(cg, 'Text', Labels.get('new_proj_label_name', 'Project Name'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', [0.30 0.34 0.42], ...
                'VerticalAlignment', 'bottom');
            nameLbl.Layout.Row = 4; nameLbl.Layout.Column = 1;

            % Row 5 — Project Name field
            app.NewProjNameField = uieditfield(cg, 'text', 'Value', '', ...
                'Placeholder', Labels.get('new_proj_placeholder_name', 'e.g. BV-27 Fidelity Study'), ...
                'FontSize', 13);
            app.NewProjNameField.Layout.Row = 5; app.NewProjNameField.Layout.Column = 1;

            % Row 6 — Description label
            descLbl = uilabel(cg, 'Text', Labels.get('new_proj_label_desc', 'Description'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', [0.30 0.34 0.42], ...
                'VerticalAlignment', 'bottom');
            descLbl.Layout.Row = 6; descLbl.Layout.Column = 1;

            % Row 7 — Description text area
            app.NewProjDescField = uitextarea(cg, 'Value', '', ...
                'Placeholder', Labels.get('new_proj_placeholder_desc', 'Describe the purpose and scope of this project...'), ...
                'FontSize', 13);
            app.NewProjDescField.Layout.Row = 7; app.NewProjDescField.Layout.Column = 1;

            % Row 8 — Tags label
            tagsLbl = uilabel(cg, 'Text', Labels.get('new_proj_label_tags', 'Tags (comma-separated)'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', [0.30 0.34 0.42], ...
                'VerticalAlignment', 'bottom');
            tagsLbl.Layout.Row = 8; tagsLbl.Layout.Column = 1;

            % Row 9 — Tags field
            app.NewProjTagsField = uieditfield(cg, 'text', 'Value', '', ...
                'Placeholder', Labels.get('new_proj_placeholder_tags', 'e.g. calibration, 27-qubit, fidelity'), ...
                'FontSize', 13);
            app.NewProjTagsField.Layout.Row = 9; app.NewProjTagsField.Layout.Column = 1;

            % Row 10 — spacer

            % Row 11 — Button bar (Create + Cancel)
            btnBar = uigridlayout(cg, [1 2]);
            btnBar.Layout.Row = 11; btnBar.Layout.Column = 1;
            btnBar.ColumnWidth = {'1x', '1x'};
            btnBar.Padding = [0 0 0 0]; btnBar.ColumnSpacing = 12;
            btnBar.BackgroundColor = [1 1 1];

            cancelBtn = uibutton(btnBar, 'Text', Labels.get('new_proj_btn_cancel', 'Cancel'), ...
                'ButtonPushedFcn', @(~,~)delete(app.NewProjectDialog));
            cancelBtn.Layout.Row = 1; cancelBtn.Layout.Column = 1;
            app.styleBtn(cancelBtn, 'ghost');

            createBtn = uibutton(btnBar, 'Text', Labels.get('new_proj_btn_create', 'Create'), ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onCreateProject());
            createBtn.Layout.Row = 1; createBtn.Layout.Column = 2;
            app.styleBtn(createBtn, 'primary');

            % Row 12 — Status label
            app.NewProjStatusLabel = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', [0.84 0.18 0.18], ...
                'WordWrap', 'on', 'HorizontalAlignment', 'center');
            app.NewProjStatusLabel.Layout.Row = 12; app.NewProjStatusLabel.Layout.Column = 1;

            Logger.info('QTAUWorkbenchApp', 'New Project dialog shown');
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
                    'TimerFcn', @(~,~)app.forceInitialLayout());
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
            subtitle.FontSize = 14;
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
                'FontSize', 12, 'FontWeight', 'bold', 'FontColor', [0.85 0.92 1.00], ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
            app.HeaderLoginButton.Layout.Row = 1; app.HeaderLoginButton.Layout.Column = 2;
            app.HeaderLoginButton.VisitedColor = [0.85 0.92 1.00];

            % Username link (shown when logged in) — left-click opens dropdown menu
            app.HeaderUserLabel = uihyperlink(headerRight, ...
                'Text', '', ...
                'URL', '', ...
                'HyperlinkClickedFcn', @(~,~)app.toggleHeaderUserMenu(), ...
                'FontSize', 12, 'FontWeight', 'bold', 'FontColor', [0.85 0.92 1.00], ...
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
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'FontColor', [0.20 0.20 0.25], 'BackgroundColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~)app.onHeaderMenuAction('account'));
            accountBtn.Layout.Row = 1; accountBtn.Layout.Column = 1;

            logoutBtn = uibutton(mg, 'Text', [char(9211) '  ' Labels.get('header_menu_logout', 'Logout')], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
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
            catch ME; Logger.debug('QTAUWorkbenchApp', 'forceInitialLayout: %s', ME.message); end
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
            btn.FontSize = 12;
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
            % Trigger the appropriate ViewModel data-load for each screen.
            switch key
                case 'Welcome'
                    if ~isempty(app.WelcomeVm) && app.State.isAuthenticated()
                        app.WelcomeVm.onFetchProjects();
                    end
                case 'Dashboard'
                    if ~isempty(app.DashboardVm)
                        app.DashboardVm.onRefreshDashboard();
                    end
                case 'Notes'
                    if ~isempty(app.NotesVm) && app.State.hasProject()
                        app.NotesVm.onLoadNotes();
                    end
                case 'Analysis'
                    if ~isempty(app.AnalysisVm)
                        app.AnalysisVm.onEnter();
                    end
                case 'Backends'
                    if ~isempty(app.BackendsVm) && app.State.isAuthenticated()
                        app.BackendsVm.onRefreshBackends();
                    end
                case 'Jobs'
                    if ~isempty(app.JobsVm) && app.State.hasProject()
                        app.JobsVm.onRefreshJobs();
                    end
                case 'Results'
                    if ~isempty(app.ResultsVm) && app.State.hasProject()
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
