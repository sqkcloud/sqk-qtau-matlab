% QTAUApp   Main application class for the QTAU Connector Workspace.
%
%   This class builds the entire uifigure-based UI, manages navigation between
%   screens (section panels), handles all user interaction callbacks, maintains
%   shared application state (AppState), communicates with the FastAPI backend
%   (FastAPIClient), and provides developer logging via logEvent.
%
%   Architecture overview:
%     buildUI()           — constructs the top-level chrome (header, nav, content shell)
%     build*Tab functions — called once during startup; each creates a section panel
%     createSectionPage() — factory: creates an invisible scrollable uipanel container
%     onSelectSection()   — shows/hides section panels and updates the nav highlight
%     fitSectionPanel()   — keeps each section panel filling ContentContainer on resize
%     styleBtn/Axes/Table — shared visual helpers for a consistent look and feel
%     attachColumnDivider — registers a divider panel for drag-to-resize behaviour
%     logEvent()          — timestamped developer event log (MATLAB console + live UI)
%
%   Dependencies: AppState.m, FastAPIClient.m, JsonHelper.m, build*Tab.m files
classdef QTAUApp < handle
    properties
        % ── Top-level UI containers ───────────────────────────────────────────
        UIFigure            % Root uifigure window
        RootGrid            % 2-row grid: header (row 1) + body (row 2)
        HeaderGrid          % 3-column grid inside the header bar
        BodyGrid            % 2-column grid: nav sidebar (col 1) + content shell (col 2)

        % ── Navigation sidebar ────────────────────────────────────────────────
        NavPanel            % Dark sidebar panel container
        NavList             % Hidden uilistbox used to track the active section
        NavButtons          % Array of uibutton objects (one per section)
        NavToggleButton     % Hamburger button that collapses/expands the nav
        NavCollapsed = false

        % ── Content area ──────────────────────────────────────────────────────
        ContentShell        % White card that holds the page header + content
        ContentContainer    % Panel whose SizeChangedFcn triggers fitAllSections
        SectionTitleLabel   % Large heading updated when the active section changes
        SectionSubtitleLabel% Smaller description line below the heading
        Tabs                % Alias for ContentContainer (backward compat)

        % ── Resizable column dividers ─────────────────────────────────────────
        % DragState tracks an in-progress drag operation.
        % ColumnDividers is a cell array of structs {comps, grid} where
        %   comps = all handles belonging to a divider (panel + children)
        %   grid  = the uigridlayout whose ColumnWidth is updated on drag.
        DragState = struct('active', false, 'grid', [], 'startX', 0, 'col1W', 0, 'col3W', 0)
        ColumnDividers = {}

        % ── Developer event log ───────────────────────────────────────────────
        EventLog = {}       % Cell array of timestamped log lines (newest first)
        EventLogArea        % uitextarea in the Settings tab that shows the live log

        % ── Section panel registry ────────────────────────────────────────────
        SectionPanels       % Struct mapping safeKey → uipanel for each screen

        % ── Shared services ───────────────────────────────────────────────────
        State               % AppState — shared mutable application state
        Client              % FastAPIClient — HTTP helper targeting the FastAPI backend

        % ── Welcome tab controls ─────────────────────────────────────────────
        BaseUrlField
        ApplyUrlButton
        OpenApiCheckButton
        UsernameField
        PasswordField
        LoginButton
        MeButton
        LogoutButton
        FetchProjectsButton
        LoginStatusArea
        UserInfoArea
        ProjectsTable
        SkipField
        LimitField
        WelcomeNotesArea

        % ── Dashboard tab controls ───────────────────────────────────────────
        DashboardSummaryArea
        DashboardStatusArea
        DashboardRefreshButton

        % ── Notes tab controls ───────────────────────────────────────────────
        NotesArea

        % ── Upload tab controls ──────────────────────────────────────────────
        UploadFileField
        BrowseButton
        UploadButton
        CircuitStatsArea

        % ── Analysis tab controls ────────────────────────────────────────────
        AnalyzeButton
        FeatureTree
        SimilarityTable

        % ── Backend tab controls ─────────────────────────────────────────────
        BackendTable
        BackendStatusArea
        RefreshBackendsButton
        SelectBackendButton

        % ── Benchmark tab controls ───────────────────────────────────────────
        BenchmarkShotsField
        BenchmarkOptField
        BenchmarkRunButton
        BenchmarkStatusArea

        % ── Prediction tab controls ──────────────────────────────────────────
        PredictButton
        PredictionTable
        PredictionTextArea

        % ── Jobs tab controls ────────────────────────────────────────────────
        JobsRefreshButton
        JobsTable
        CancelJobButton
        JobStatusArea

        % ── Results tab controls ─────────────────────────────────────────────
        ResultsRefreshButton
        ResultsTable
        ResultJsonArea

        % ── Detailed Analysis tab controls ───────────────────────────────────
        CompareAxes
        TemporalAxes
        QubitAxes
        PlotComparisonButton
        PlotTemporalButton
        PlotQubitButton

        % ── Reports tab controls ─────────────────────────────────────────────
        ReportTitleField
        ReportFormatDropdown
        GenerateReportButton
        ReportStatusArea
        OpenReportButton
        GeneratedReportList
        AudienceDropdown
        ReportSectionsList
        ReportNotesArea
        ReportPreviewArea

        % ── Settings tab controls ────────────────────────────────────────────
        IbmEmailField
        SettingsBaseUrlField
        DefaultShotsField
        DefaultOptField
        EmailNotifyCheck
        SaveSettingsButton
        SettingsStatusArea

        % ── Loading overlay (shown during startup, deleted when UI is ready) ─
        LoadingOverlay
    end

    methods
        % Constructor — wires up state, HTTP client, and the full UI chrome,
        % then reveals the window after an initial layout pass.
        function app = QTAUApp()
            app.State = AppState();
            app.Client = FastAPIClient(app.State.baseUrl);
            app.buildUI();
            app.logEvent('UI', 'QTAUApp started — storyboard mode active');
            app.forceInitialLayout();
        end

        % Destructor — safely closes the figure if it is still alive.
        function delete(app)
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    delete(app.UIFigure);
                end
            catch
            end
        end
    end

    methods (Access = private)
        % buildUI  Constructs the complete application chrome:
        %   - uifigure with mouse callbacks for drag-to-resize
        %   - 2-row RootGrid: top header bar + body area
        %   - Left sidebar (NavPanel) with collapsible nav buttons
        %   - ContentShell: page heading card + thin separator + ContentContainer
        %   - Calls all build*Tab functions to populate each section panel
        %   - Shows Welcome and triggers initial layout pass
        function buildUI(app)
            app.UIFigure = uifigure('Name', 'Tunning Analysis', 'Position', [80 40 1600 940], ...
                'Color', [0.97 0.98 1.00], 'Visible', 'off');
            app.UIFigure.SizeChangedFcn          = @(~,~)app.onResizeUI();
            app.UIFigure.WindowButtonDownFcn     = @(~,~)app.onFigMouseDown();
            app.UIFigure.WindowButtonMotionFcn   = @(~,~)app.onFigMouseMove();
            app.UIFigure.WindowButtonUpFcn       = @(~,~)app.onFigMouseUp();
            app.RootGrid = uigridlayout(app.UIFigure, [2 1]);
            app.RootGrid.RowHeight = {52, '1x'};
            app.RootGrid.ColumnWidth = {'1x'};
            app.RootGrid.Padding = [0 0 0 0];
            app.RootGrid.RowSpacing = 0;

            app.HeaderGrid = uigridlayout(app.RootGrid, [1 3]);
            app.HeaderGrid.Layout.Row = 1;
            app.HeaderGrid.Layout.Column = 1;
            app.HeaderGrid.ColumnWidth = {250, '1x', 240};
            app.HeaderGrid.RowHeight = {52};
            app.HeaderGrid.Padding = [0 0 12 2];
            app.HeaderGrid.BackgroundColor = [0.10 0.17 0.30];

            logoHost = uigridlayout(app.HeaderGrid, [1 1]);
            logoHost.Layout.Row = 1;
            logoHost.Layout.Column = 1;
            logoHost.RowHeight = {'1x'};
            logoHost.ColumnWidth = {'1x'};
            logoHost.RowSpacing = 0;
            logoHost.ColumnSpacing = 0;
            logoHost.Padding = [0 0 10 0];
            logoHost.BackgroundColor = [0.10 0.17 0.30];

            logoPath = fullfile(fileparts(mfilename('fullpath')), '..', 'resources', 'sqk-logo-kokkos-white1-reordered.svg');
            brandWrap = uigridlayout(logoHost, [1 2]);
            brandWrap.Layout.Row = 1;
            brandWrap.Layout.Column = 1;
            brandWrap.RowHeight = {'1x'};
            brandWrap.ColumnWidth = {108, '1x'};
            brandWrap.Padding = [0 0 10 0];
            brandWrap.RowSpacing = 0;
            brandWrap.ColumnSpacing = 0;
            brandWrap.BackgroundColor = [0.10 0.17 0.30];
            try
                brand = uiimage(brandWrap);
                brand.ImageSource = logoPath;
                brand.ScaleMethod = 'fit';
                brand.Tooltip = 'SQK';
                brand.Layout.Row = 1;
                brand.Layout.Column = 1;
            catch
                brand = uilabel(brandWrap, 'Text', 'SQK');
                brand.FontSize = 14;
                brand.FontWeight = 'bold';
                brand.FontColor = [1 1 1];
                brand.HorizontalAlignment = 'left';
                brand.VerticalAlignment = 'bottom';
                brand.Tooltip = 'SQK';
                brand.Layout.Row = 1;
                brand.Layout.Column = 1;
            end

            subtitle = uilabel(app.HeaderGrid, 'Text', 'Connector Workspace');
            subtitle.FontSize = 14;
            subtitle.HorizontalAlignment = 'center';
            subtitle.FontColor = [0.80 0.87 0.97];
            subtitle.Layout.Row = 1;
            subtitle.Layout.Column = 2;

            userBadge = uilabel(app.HeaderGrid, 'Text', 'SQK Admin Workspace');
            userBadge.FontSize = 13;
            userBadge.FontWeight = 'bold';
            userBadge.HorizontalAlignment = 'right';
            userBadge.FontColor = [1 1 1];
            userBadge.Layout.Row = 1;
            userBadge.Layout.Column = 3;
            userBadge.Tooltip = 'QTAU Connector v2026';

            app.BodyGrid = uigridlayout(app.RootGrid, [1 2]);
            app.BodyGrid.Layout.Row = 2;
            app.BodyGrid.Layout.Column = 1;
            app.BodyGrid.ColumnWidth = {230, '1x'};
            app.BodyGrid.RowHeight = {'1x'};
            app.BodyGrid.Padding = [0 0 0 0];
            app.BodyGrid.ColumnSpacing = 0;
            app.BodyGrid.BackgroundColor = [0.93 0.95 0.98];

            app.NavPanel = uipanel(app.BodyGrid, 'Title', '');
            app.NavPanel.Layout.Row = 1;
            app.NavPanel.Layout.Column = 1;
            app.NavPanel.BackgroundColor = [0.12 0.19 0.31];
            navGrid = uigridlayout(app.NavPanel, [4 1]);
            navGrid.RowHeight = {44, 28, '1x', 28};
            navGrid.Padding = [10 10 10 10];
            navGrid.BackgroundColor = [0.12 0.19 0.31];

            topRow = uigridlayout(navGrid, [1 2]);
            topRow.Layout.Row = 1;
            topRow.Layout.Column = 1;
            topRow.ColumnWidth = {0, '1x'};
            topRow.Padding = [0 0 0 0];
            topRow.BackgroundColor = [0.12 0.19 0.31];

            navBrand = uilabel(topRow, 'Text', '');
            navBrand.Visible = 'off';
            navBrand.Layout.Row = 1;
            navBrand.Layout.Column = 1;

            app.NavToggleButton = uibutton(topRow, 'push', 'Text', '≡', ...
                'ButtonPushedFcn', @(~,~)app.onToggleNav());
            app.NavToggleButton.Layout.Row = 1;
            app.NavToggleButton.Layout.Column = 2;
            app.NavToggleButton.FontSize = 18;
            app.NavToggleButton.FontWeight = 'bold';
            app.NavToggleButton.BackgroundColor = [0.20 0.31 0.49];
            app.NavToggleButton.FontColor = [1 1 1];

            navCaption = uilabel(navGrid, 'Text', 'NAVIGATION');
            navCaption.FontSize = 12;
            navCaption.FontWeight = 'bold';
            navCaption.FontColor = [0.72 0.80 0.92];
            navCaption.Layout.Row = 2;
            navCaption.Layout.Column = 1;

            navButtonsPanel = uipanel(navGrid, 'Title', '');
            navButtonsPanel.Layout.Row = 3;
            navButtonsPanel.Layout.Column = 1;
            navButtonsPanel.BackgroundColor = [0.12 0.19 0.31];
            navButtonsPanel.BorderType = 'none';
            navButtonsGrid = uigridlayout(navButtonsPanel, [13 1]);
            navButtonsGrid.RowHeight = repmat({32}, 1, 13);
            navButtonsGrid.Padding = [0 0 0 0];
            navButtonsGrid.RowSpacing = 6;
            navButtonsGrid.BackgroundColor = [0.12 0.19 0.31];

            names = {'Welcome','Dashboard','Notes','Upload','Analysis','Backends', ...
                'Benchmark','Prediction','Jobs','Results','Detailed Analysis','Reports','Settings'};
            labels = app.navMenuLabels();
            app.NavButtons = gobjects(1, numel(names));
            for i = 1:numel(names)
                app.NavButtons(i) = uibutton(navButtonsGrid, 'push', 'Text', [' ' labels{i}], ...
                    'ButtonPushedFcn', @(~,~)app.onSelectSection(names{i}));
                app.NavButtons(i).Layout.Row = i;
                app.NavButtons(i).Layout.Column = 1;
                app.NavButtons(i).HorizontalAlignment = 'left';
                app.NavButtons(i).FontSize = 14;
                app.NavButtons(i).FontWeight = 'bold';
                app.NavButtons(i).BackgroundColor = [0.16 0.24 0.39];
                app.NavButtons(i).FontColor = [0.92 0.96 1.00];
                app.NavButtons(i).Tooltip = '';  % no tooltip — label is always visible
            end

            app.NavList = uilistbox(navGrid, 'Items', names, 'Visible', 'off');
            app.NavList.Value = 'Welcome';
            app.NavList.Layout.Row = 4;
            app.NavList.Layout.Column = 1;
            app.NavList.ValueChangedFcn = @(src,~)app.onSelectSection(string(src.Value));

            hint = uilabel(navGrid, 'Text', '메뉴 숨기기');
            hint.FontSize = 10;
            hint.FontColor = [0.72 0.80 0.92];
            hint.VerticalAlignment = 'top';
            hint.Layout.Row = 4;
            hint.Layout.Column = 1;
            app.ContentShell = uipanel(app.BodyGrid, 'Title', '');
            app.ContentShell.Layout.Row = 1;
            app.ContentShell.Layout.Column = 2;
            app.ContentShell.BackgroundColor = [0.96 0.97 0.99];
            shellGrid = uigridlayout(app.ContentShell, [3 1]);
            shellGrid.RowHeight = {72, 1, '1x'};
            shellGrid.Padding = [20 16 20 16];
            shellGrid.RowSpacing = 12;
            shellGrid.BackgroundColor = [0.96 0.97 0.99];

            headerPanel = uipanel(shellGrid, 'Title', '');
            headerPanel.Layout.Row = 1;
            headerPanel.Layout.Column = 1;
            headerPanel.BackgroundColor = [1 1 1];
            hg = uigridlayout(headerPanel, [2 1]);
            hg.RowHeight = {28, 20};
            hg.Padding = [16 10 16 10];
            hg.BackgroundColor = [1 1 1];
            app.SectionTitleLabel = uilabel(hg, 'Text', 'Welcome');
            app.SectionTitleLabel.FontSize = 24;
            app.SectionTitleLabel.FontWeight = 'bold';
            app.SectionTitleLabel.Layout.Row = 1;
            app.SectionTitleLabel.Layout.Column = 1;
            app.SectionSubtitleLabel = uilabel(hg, 'Text', 'Server authentication and project access');
            app.SectionSubtitleLabel.FontSize = 12;
            app.SectionSubtitleLabel.FontColor = [0.35 0.40 0.48];
            app.SectionSubtitleLabel.Layout.Row = 2;
            app.SectionSubtitleLabel.Layout.Column = 1;

            sep = uipanel(shellGrid, 'Title', '');
            sep.Layout.Row = 2;
            sep.Layout.Column = 1;
            sep.BackgroundColor = [0.87 0.90 0.95];

            app.ContentContainer = uipanel(shellGrid, 'Title', '');
            app.ContentContainer.Layout.Row = 3;
            app.ContentContainer.Layout.Column = 1;
            app.ContentContainer.BackgroundColor = [0.96 0.97 0.99];
            app.ContentContainer.AutoResizeChildren = 'off';
            app.ContentContainer.SizeChangedFcn = @(~,~)app.onResizeUI();

            app.Tabs = app.ContentContainer;
            app.SectionPanels = struct();

            % ── Loading overlay ───────────────────────────────────────────────
            % Created as a direct child of UIFigure (above all grids) so it
            % covers the whole window while the 13 tab panels are being built.
            % A CSS spin animation is rendered via uihtml; a plain text label
            % is used as a fallback for older MATLAB versions without uihtml.
            figW = app.UIFigure.Position(3);
            figH = app.UIFigure.Position(4);
            app.LoadingOverlay = uipanel(app.UIFigure, 'Title', '');
            app.LoadingOverlay.Units    = 'pixels';
            app.LoadingOverlay.Position = [0 0 figW figH];
            app.LoadingOverlay.BackgroundColor = [0.97 0.98 1.00];
            app.LoadingOverlay.BorderType      = 'none';
            app.LoadingOverlay.AutoResizeChildren = 'off';

            % 3×3 grid centres the spinner cell in the middle of the overlay
            olog = uigridlayout(app.LoadingOverlay, [3 3]);
            olog.RowHeight    = {'1x', 110, '1x'};
            olog.ColumnWidth  = {'1x', 240, '1x'};
            olog.Padding      = [0 0 0 0];
            olog.BackgroundColor = [0.97 0.98 1.00];

            spinHost = uigridlayout(olog, [1 1]);
            spinHost.Layout.Row    = 2;
            spinHost.Layout.Column = 2;
            spinHost.Padding       = [0 0 0 0];
            spinHost.BackgroundColor = [0.97 0.98 1.00];
            try
                % CSS spinning ring + label — works in MATLAB R2021b+
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
                % Fallback: plain animated-text label for older MATLAB
                lbl = uilabel(spinHost, 'Text', 'Loading workspace…');
                lbl.FontSize = 15; lbl.FontWeight = 'bold';
                lbl.FontColor = [0.35 0.42 0.52];
                lbl.HorizontalAlignment = 'center';
                lbl.VerticalAlignment   = 'center';
            end

            % Make figure visible immediately so the user sees the spinner
            app.UIFigure.Visible = 'on';
            drawnow();

            buildWelcomeTab(app);
            buildDashboardTab(app);
            buildNotesTab(app);
            buildUploadTab(app);
            buildAnalysisTab(app);
            buildBackendsTab(app);
            buildBenchmarkTab(app);
            buildPredictionTab(app);
            buildJobsTab(app);
            buildResultsTab(app);
            buildDetailedAnalysisTab(app);
            buildReportsTab(app);
            buildSettingsTab(app);
            drawnow();
            app.onSelectSection("Welcome");
            app.fitAllSections();
            app.onResizeUI();
            drawnow();
            app.forceInitialLayout();
            % Figure is already visible (shown above with the loading overlay).
            drawnow();
            app.forceInitialLayout();

            % ── Remove loading overlay ────────────────────────────────────────
            % All tabs are built and the layout has settled — hide the spinner.
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
            catch
            end
        end

        % sectionSubtitleFor  Returns the descriptive subtitle for each section,
        % displayed in the page header under the section title.
        function subtitle = sectionSubtitleFor(app, key)
            switch char(key)
                case 'Welcome'
                    subtitle = 'Server authentication and project access';
                case 'Dashboard'
                    subtitle = 'Storyboard landing summary and workflow readiness';
                case 'Notes'
                    subtitle = 'Working notes and operator memos';
                case 'Upload'
                    subtitle = 'Circuit upload, format selection, preview, and metadata';
                case 'Analysis'
                    subtitle = 'Circuit feature extraction and QASMBench similarity review';
                case 'Backends'
                    subtitle = 'Backend explorer with primary and backup selection';
                case 'Benchmark'
                    subtitle = 'Execution parameters, mitigation strategy, and cost estimate';
                case 'Prediction'
                    subtitle = 'Predicted fidelity, distribution, and error budget';
                case 'Jobs'
                    subtitle = 'Job monitoring dashboard with partial results and logs';
                case 'Results'
                    subtitle = 'Measured versus predicted versus ideal result analysis';
                case 'Detailed Analysis'
                    subtitle = 'Heatmaps, drift, qubit metrics, and cross-run comparisons';
                case 'Reports'
                    subtitle = 'Report generation and generated report view';
                case 'Settings'
                    subtitle = 'Account settings, defaults, storage, and notifications';
                otherwise
                    subtitle = '';
            end
        end


        function labels = navMenuLabels(app)
            labels = {'⌂  Welcome','◫  Dashboard','✎  Notes','⤴  Upload','⌕  Analysis', ...
                '⌬  Backends','◎  Benchmark','◇  Prediction','▣  Jobs','□  Results', ...
                '△  Detailed Analysis','▤  Reports','⚙  Settings'};
        end

        function labels = navCollapsedLabels(app)
            labels = {'⌂','◫','✎','⤴','⌕','⌬','◎','◇','▣','□','△','▤','⚙'};
        end

        % forceInitialLayout  Runs fitAllSections + onResizeUI twice with short
        % pauses to ensure all uigridlayout measurements are settled after the
        % figure becomes visible.  Also called from a one-shot timer (150 ms)
        % to catch any deferred MATLAB renderer pass.
        function forceInitialLayout(app)
            try
                drawnow();
                pause(0.05);
                app.fitAllSections();
                app.onResizeUI();
                drawnow();
                pause(0.02);
                app.fitAllSections();
            catch
            end
        end

        % updateNavStyles  Highlights the active section button in the sidebar.
        % Active button uses the brand blue accent; inactive buttons use the
        % standard dark sidebar shade.
        function updateNavStyles(app, activeKey)
            names = {'Welcome','Dashboard','Notes','Upload','Analysis','Backends', ...
                'Benchmark','Prediction','Jobs','Results','Detailed Analysis','Reports','Settings'};
            if nargin < 2
                activeKey = 'Welcome';
            end
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


        % fitSectionPanel  Sizes a section panel to exactly fill its parent
        % (ContentContainer).  Called on every resize event so section panels
        % always occupy the full available content area.
        function fitSectionPanel(app, panel)
            if isempty(panel) || ~isvalid(panel); return; end
            try
                parentObj = panel.Parent;
                if ~isempty(parentObj) && isvalid(parentObj)
                    pw = max(1, parentObj.Position(3));
                    ph = max(1, parentObj.Position(4));
                    panel.Position = [0 0 pw ph];
                end
            catch
            end
        end

        % fitAllSections  Iterates over all registered section panels and calls
        % fitSectionPanel on each so they stay in sync after any resize event.
        function fitAllSections(app)
            try
                names = fieldnames(app.SectionPanels);
                for i = 1:numel(names)
                    app.fitSectionPanel(app.SectionPanels.(names{i}));
                end
            catch
            end
        end

        % onResizeUI  Triggered by ContentContainer.SizeChangedFcn whenever the
        % figure or content area changes size.  Delegates to fitAllSections so
        % all section panels fill the new available space.
        function onResizeUI(app)
            app.fitAllSections();
        end

        function syncClient(app)
            app.State.baseUrl = string(app.BaseUrlField.Value);
            app.Client.setBaseUrl(app.State.baseUrl);
            if ~isempty(app.SettingsBaseUrlField) && isvalid(app.SettingsBaseUrlField)
                app.SettingsBaseUrlField.Value = char(app.State.baseUrl);
            end
        end

        function setStatus(app, area, lines)
            if ischar(lines)
                lines = cellstr(string(lines));
            elseif isstring(lines)
                lines = cellstr(string(lines));
            end
            area.Value = lines;
        end

        % ── Developer event log ───────────────────────────────────────────
        % category: 'UI' | 'AUTH' | 'API' | 'CONFIG' | 'DRAG' | 'NAV' | 'ERROR'
        function logEvent(app, category, msg)
            ts   = datestr(now, 'HH:MM:SS.FFF');
            line = sprintf('[%s] %-7s %s', ts, upper(char(category)), char(msg));
            % Prepend (newest first), keep last 1000 entries
            if isempty(app.EventLog)
                app.EventLog = {line};
            else
                app.EventLog = [{line}; app.EventLog(1:min(end,999))];
            end
            % Mirror to MATLAB command window
            fprintf('%s\n', line);
            % Update live console if the Settings panel is visible
            try
                if ~isempty(app.EventLogArea) && isvalid(app.EventLogArea)
                    app.EventLogArea.Value = app.EventLog(1:min(numel(app.EventLog),200));
                end
            catch; end
        end

    end

    methods
        % createSectionPage  Factory that creates a scrollable, invisible uipanel
        % inside ContentContainer for one section, registers it in SectionPanels,
        % and returns it so a build*Tab function can populate it.
        % AutoResizeChildren='on' means the inner uigridlayout auto-fills the panel.
        function panel = createSectionPage(app, key)
            panel = uipanel(app.ContentContainer, 'Title', '', 'Visible', 'off');
            panel.Position = [0 0 max(1, app.ContentContainer.Position(3)) max(1, app.ContentContainer.Position(4))];
            panel.AutoResizeChildren = 'on';   % grid inside fills panel automatically
            panel.Scrollable = 'on';
            panel.BackgroundColor = [0.96 0.97 0.99];
            safeKey = matlab.lang.makeValidName(char(key));
            app.SectionPanels.(safeKey) = panel;
        end

        % ── Visual helpers ────────────────────────────────────────────────────
        % styleBtn  Applies a consistent light-gray palette to a uibutton.
        %   variant: 'primary'   — medium gray, bold  (main actions)
        %            'secondary' — lighter gray, normal (secondary actions)
        %            'success'   — gray with green tint (positive confirm)
        %            'danger'    — gray with red tint   (destructive actions)
        %            'ghost'     — very light gray       (supplemental / cancel)
        function styleBtn(~, btn, variant)
            % All variants use a light-gray palette; weight and shade signal
            % hierarchy while keeping the UI calm and neutral.
            btn.FontSize = 13;
            switch lower(char(variant))
                case 'primary'
                    btn.BackgroundColor = [0.78 0.80 0.83];   % medium-light gray
                    btn.FontColor       = [0.10 0.12 0.16];
                    btn.FontWeight      = 'bold';
                case 'secondary'
                    btn.BackgroundColor = [0.84 0.86 0.88];   % lighter gray
                    btn.FontColor       = [0.18 0.22 0.28];
                    btn.FontWeight      = 'normal';
                case 'success'
                    btn.BackgroundColor = [0.83 0.87 0.84];   % gray with a hint of green
                    btn.FontColor       = [0.12 0.20 0.14];
                    btn.FontWeight      = 'bold';
                case 'danger'
                    btn.BackgroundColor = [0.88 0.84 0.84];   % gray with a hint of red
                    btn.FontColor       = [0.28 0.10 0.10];
                    btn.FontWeight      = 'bold';
                case 'ghost'
                    btn.BackgroundColor = [0.92 0.93 0.94];   % very light gray
                    btn.FontColor       = [0.28 0.32 0.38];
                    btn.FontWeight      = 'normal';
                otherwise
                    btn.BackgroundColor = [0.90 0.91 0.92];
                    btn.FontColor       = [0.22 0.26 0.32];
                    btn.FontWeight      = 'normal';
            end
        end

        % styleAxes  Applies clean, professional styling to a uiaxes object.
        % Turns on grid lines, removes the box, and attaches a zoom/pan toolbar
        % (wrapped in try-catch for version compatibility).
        function styleAxes(~, ax)
            ax.Box       = 'off';
            ax.XGrid     = 'on';
            ax.YGrid     = 'on';
            ax.GridColor = [0.82 0.86 0.92];
            ax.GridAlpha = 0.9;
            ax.FontSize  = 11;
            ax.LineWidth = 1;
            ax.Color     = [1 1 1];
            ax.XColor    = [0.28 0.36 0.48];
            ax.YColor    = [0.28 0.36 0.48];
            try
                axtoolbar(ax, {'zoom','pan','datacursor','restoreview'});
            catch
            end
        end

        % styleTable  Enables row striping and column-sortable on a uitable.
        % Both wrapped in try-catch for backward compatibility with older MATLAB.
        function styleTable(~, tbl)
            try; tbl.RowStriping = 'on'; catch; end
            try
                n = numel(tbl.ColumnName);
                tbl.ColumnSortable = true(1, n);
            catch
            end
        end

        % ── Resizable column divider ──────────────────────────────────────────
        % attachColumnDivider  Registers a narrow uipanel (divPanel) placed in the
        % centre column of grid g as a drag handle.
        %   1. Collects divPanel and all its children (up to 2 levels) into a
        %      component list stored in ColumnDividers.
        %   2. Sets ButtonDownFcn on every component as a belt-and-suspenders
        %      fallback; the primary detection path uses UIFigure.CurrentObject
        %      inside onFigMouseDown, which fires for any figure mouse-down event.
        %
        % Usage (in a build*Tab function):
        %   div = uipanel(g, 'Title', ''); div.Layout.Column = 2; ...
        %   app.attachColumnDivider(div, g);
        function attachColumnDivider(app, divPanel, g)
            % Collect the panel and all descendants (up to 2 levels deep).
            % WindowButtonDownFcn checks UIFigure.CurrentObject against this
            % list so the drag starts regardless of which child is on top.
            comps = {divPanel};
            try
                for ch = divPanel.Children(:)'
                    comps{end+1} = ch;                                   %#ok
                    try
                        for gc = ch.Children(:)'
                            comps{end+1} = gc;                           %#ok
                        end
                    catch; end
                end
            catch; end
            app.ColumnDividers{end+1} = struct('comps', {comps}, 'grid', g);
            divPanel.Tooltip = 'Drag left/right to resize panels';
            % Belt-and-suspenders: also set ButtonDownFcn where supported
            cb = @(~,~)app.onDividerDown(g);
            for j = 1:numel(comps)
                try; comps{j}.ButtonDownFcn = cb; catch; end
            end
        end

        % onFigMouseDown  Figure-level mouse-down handler.
        % Walks the ColumnDividers registry comparing UIFigure.CurrentObject
        % with every registered component; if a match is found, starts a drag.
        function onFigMouseDown(app)
            if app.DragState.active; return; end
            try
                clicked = app.UIFigure.CurrentObject;
                if isempty(clicked); return; end
                for k = 1:numel(app.ColumnDividers)
                    entry = app.ColumnDividers{k};
                    comps = entry.comps;
                    for j = 1:numel(comps)
                        try
                            if isvalid(comps{j}) && isequal(clicked, comps{j})
                                app.onDividerDown(entry.grid);
                                return;
                            end
                        catch; end
                    end
                end
            catch; end
        end

        % onDividerDown  Initiates a drag operation: records the current cursor X
        % and the current pixel widths of columns 1 and 3 so that onFigMouseMove
        % can compute absolute pixel widths from the delta on every motion event.
        function onDividerDown(app, g)
            try
                cw = g.ColumnWidth;
                try; availW = max(300, app.ContentShell.Position(3) - 70); catch; availW = 900; end
                if isnumeric(cw{1})
                    w1 = cw{1};  w3 = cw{3};
                else
                    n1 = str2double(strtrim(strrep(char(cw{1}), 'x', '')));
                    n3 = str2double(strtrim(strrep(char(cw{3}), 'x', '')));
                    if isnan(n1); n1 = 1; end
                    if isnan(n3); n3 = 1; end
                    w1 = availW * n1 / (n1 + n3);
                    w3 = availW * n3 / (n1 + n3);
                end
                app.DragState.active = true;
                app.DragState.grid   = g;
                app.DragState.startX = app.UIFigure.CurrentPoint(1);
                app.DragState.col1W  = w1;
                app.DragState.col3W  = w3;
                app.UIFigure.Pointer = 'lrdrag';
                app.logEvent('DRAG', sprintf('Divider drag started — col1=%.0fpx col3=%.0fpx', w1, w3));
            catch
                app.DragState.active = false;
            end
        end

        % onFigMouseMove  Updates ColumnWidth on every mouse-motion event while
        % a drag is active, enforcing a 120 px minimum on each side panel so
        % content is never completely hidden.
        function onFigMouseMove(app)
            if ~app.DragState.active; return; end
            try
                dx = app.UIFigure.CurrentPoint(1) - app.DragState.startX;
                w1 = max(120, app.DragState.col1W + dx);
                w3 = max(120, app.DragState.col3W - dx);
                app.DragState.grid.ColumnWidth = {w1, 6, w3};
            catch
                app.DragState.active = false;
                app.UIFigure.Pointer = 'arrow';
            end
        end

        % onFigMouseUp  Ends the drag operation and resets the cursor to arrow.
        function onFigMouseUp(app)
            if app.DragState.active
                app.DragState.active = false;
                app.UIFigure.Pointer = 'arrow';
                try
                    cw = app.DragState.grid.ColumnWidth;
                    app.logEvent('DRAG', sprintf('Divider drag ended — col1=%.0fpx col3=%.0fpx', cw{1}, cw{3}));
                catch; end
            end
        end

        % onToggleNav  Collapses or expands the sidebar between 56 px (icon-only)
        % and 230 px (full label) by updating BodyGrid.ColumnWidth and swapping
        % button labels between emoji icons and full navigation text.
        function onToggleNav(app)
            app.NavCollapsed = ~app.NavCollapsed;
            if app.NavCollapsed
                app.BodyGrid.ColumnWidth = {56, '1x'};
                shortLabels = app.navCollapsedLabels();
                if ~isempty(app.NavButtons)
                    for i = 1:min(numel(app.NavButtons), numel(shortLabels))
                        app.NavButtons(i).Text = shortLabels{i};
                        app.NavButtons(i).HorizontalAlignment = 'center';
                    end
                end
                app.NavToggleButton.Text = '☰';
            else
                app.BodyGrid.ColumnWidth = {230, '1x'};
                labels = app.navMenuLabels();
                for i = 1:min(numel(app.NavButtons), numel(labels))
                    app.NavButtons(i).Text = [' ' labels{i}];
                    app.NavButtons(i).HorizontalAlignment = 'left';
                end
                app.NavToggleButton.Text = '≡';
            end
            app.updateNavStyles(char(app.NavList.Value));
            app.onResizeUI();
        end

        % onSelectSection  Shows the requested section panel, hides all others,
        % updates the page heading labels, syncs the nav list selection, and
        % triggers a resize pass to fill any available space.
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
            app.SectionTitleLabel.Text = key;
            app.SectionSubtitleLabel.Text = app.sectionSubtitleFor(key);
            if ~strcmp(app.NavList.Value, key)
                app.NavList.Value = key;
            end
            app.updateNavStyles(key);
            app.onResizeUI();
        end

        function onApplyUrl(app)
            app.syncClient();
            app.logEvent('CONFIG', sprintf('Base URL applied: %s', app.State.baseUrl));
            app.setStatus(app.LoginStatusArea, {sprintf('Base URL set to %s', app.State.baseUrl)});
        end

        function onOpenApiCheck(app)
            app.syncClient();
            app.logEvent('API', sprintf('OpenAPI check → %s', app.State.baseUrl));
            try
                data = app.Client.openApi();
                app.State.lastHealth = "OK";
                app.logEvent('API', 'OpenAPI check OK');
                app.setStatus(app.LoginStatusArea, {'OpenAPI check succeeded.', ...
                    sprintf('Title: %s', JsonHelper.pick(data, {'info.title'})), ...
                    sprintf('Version: %s', JsonHelper.pick(data, {'info.version'}))});
                if ~isempty(app.DashboardStatusArea)
                    if isvalid(app.DashboardStatusArea)
                        app.setStatus(app.DashboardStatusArea, {JsonHelper.pretty(data)});
                    end
                end
            catch ME
                app.State.lastHealth = "FAILED";
                app.logEvent('ERROR', sprintf('OpenAPI check FAILED: %s', ME.message));
                app.setStatus(app.LoginStatusArea, {'OpenAPI check failed.', ME.message});
                uialert(app.UIFigure, ME.message, 'OpenAPI Check Failed', 'Icon', 'error');
            end
        end

        function onLogin(app)
            app.syncClient();
            username = string(app.UsernameField.Value);
            password = string(app.PasswordField.Value);
            app.logEvent('AUTH', sprintf('Login attempt → user: %s', username));
            if strlength(strtrim(username)) == 0
                uialert(app.UIFigure, 'Enter username and password first.', 'Login', 'Icon', 'warning');
                return;
            end
            if strlength(password) == 0
                uialert(app.UIFigure, 'Enter username and password first.', 'Login', 'Icon', 'warning');
                return;
            end
            try
                data = app.Client.login(username, password);
                app.State.authToken = string(JsonHelper.pick(data, {'access_token', 'token', 'data.access_token', 'result.access_token'}));
                app.State.tokenType = string(JsonHelper.pick(data, {'token_type', 'data.token_type', 'result.token_type'}));
                app.State.currentUser = string(JsonHelper.pick(data, {'username', 'user.username', 'data.username', 'result.username'}));
                app.State.defaultProjectId = string(JsonHelper.pick(data, {'default_project_id', 'data.default_project_id', 'result.default_project_id'}));

                if strlength(strtrim(app.State.authToken)) == 0
                    app.setStatus(app.LoginStatusArea, {
                        'Login response received, but no token was found.', ...
                        JsonHelper.pretty(data)
                    });
                    uialert(app.UIFigure, '로그인 응답에서 access_token 값을 찾지 못했습니다.', 'Login Response Mismatch', 'Icon', 'warning');
                    return;
                end

                if strlength(strtrim(app.State.tokenType)) == 0
                    app.State.tokenType = "Bearer";
                end

                app.setStatus(app.LoginStatusArea, {
                    'Login successful.', ...
                    sprintf('Username: %s', app.State.currentUser), ...
                    sprintf('Token type: %s', app.State.tokenType), ...
                    sprintf('Default project: %s', app.State.defaultProjectId)
                    });
                app.logEvent('AUTH', sprintf('Login OK — user: %s, project: %s', app.State.currentUser, app.State.defaultProjectId));
            catch ME
                app.setStatus(app.LoginStatusArea, {'Login failed.', ME.message});
                app.logEvent('ERROR', sprintf('Login FAILED: %s', ME.message));
                uialert(app.UIFigure, ME.message, 'Login Failed', 'Icon', 'error');
            end
        end

        function onGetMe(app)
            if strlength(app.State.authToken) == 0
                uialert(app.UIFigure, 'Login first.', 'User Info', 'Icon', 'warning');
                return;
            end
            try
                data = app.Client.getMe(app.State.authToken);
                app.setStatus(app.UserInfoArea, {JsonHelper.pretty(data)});
            catch ME
                app.setStatus(app.UserInfoArea, {'User info request failed.', ME.message});
                uialert(app.UIFigure, ME.message, 'Get User Info Failed', 'Icon', 'error');
            end
        end

        function onLogout(app)
            app.logEvent('AUTH', 'Logout requested');
            if strlength(app.State.authToken) == 0
                app.setStatus(app.LoginStatusArea, {'Already logged out.'});
                return;
            end
            try
                data = app.Client.logout(app.State.authToken);
                app.State.authToken = "";
                app.setStatus(app.LoginStatusArea, {'Logout successful.', JsonHelper.pretty(data)});
                app.logEvent('AUTH', 'Logout OK');
                app.setStatus(app.UserInfoArea, {'Logged out.'});
            catch ME
                app.setStatus(app.LoginStatusArea, {'Logout failed.', ME.message});
                uialert(app.UIFigure, ME.message, 'Logout Failed', 'Icon', 'error');
            end
        end

        function onFetchProjects(app)
            if strlength(app.State.authToken) == 0
                uialert(app.UIFigure, 'Login first.', 'Projects', 'Icon', 'warning');
                return;
            end
            skip  = max(0, round(app.SkipField.Value));
            limit = max(1, round(app.LimitField.Value));
            app.logEvent('API', sprintf('GET /admin/projects skip=%d limit=%d', skip, limit));
            try
                data = app.Client.listProjects(app.State.authToken, skip, limit);
                rows = JsonHelper.projectsToRows(data);
                app.ProjectsTable.Data = rows;
                app.logEvent('API', sprintf('GET /admin/projects → %d rows returned', size(rows,1)));
                if isstruct(data)
                    if isfield(data, 'total')
                        totalText = sprintf('Total projects reported by server: %s', char(string(data.total)));
                    else
                        totalText = '';
                    end
                else
                    totalText = '';
                end
                statusLines = {sprintf('Fetched %d project rows.', size(rows,1))};
                if ~isempty(totalText)
                    statusLines{end+1} = totalText;
                end
                statusLines{end+1} = JsonHelper.pretty(data);
                app.setStatus(app.UserInfoArea, statusLines);
            catch ME
                details = {'Project fetch failed.', ME.message};
                if ~isempty(ME.identifier)
                    details{end+1} = ['Identifier: ' ME.identifier];
                end
                app.setStatus(app.UserInfoArea, details);
                uialert(app.UIFigure, strjoin(details, newline), 'Fetch Projects Failed', 'Icon', 'error');
            end
        end

        function refreshDashboard(app)
            summary = {
                sprintf('Base URL: %s', app.State.baseUrl)
                sprintf('Current user: %s', app.State.currentUser)
                sprintf('Default project: %s', app.State.defaultProjectId)
                sprintf('Authenticated: %s', string(strlength(app.State.authToken) > 0))
                sprintf('Health: %s', app.State.lastHealth)
                sprintf('Selected backend: %s', app.State.selectedBackend)
                sprintf('Selected file: %s', app.State.selectedFile)
                };
            app.DashboardSummaryArea.Value = summary;
        end

        function onRefreshDashboard(app)
            app.logEvent('UI', 'Dashboard refresh triggered');
            app.refreshDashboard();
            app.DashboardStatusArea.Value = {'Dashboard refreshed.'};
        end

        function onBrowseCircuit(app)
            app.logEvent('UI', 'Browse circuit file dialog opened');
            [file, path] = uigetfile({'*.qasm;*.txt;*.*', 'Circuit Files'});
            if isequal(file, 0)
                app.logEvent('UI', 'Browse cancelled');
                return;
            end
            fullp = fullfile(path, file);
            app.State.selectedFile = string(fullp);
            app.UploadFileField.Value = fullp;
            info = dir(fullp);
            app.logEvent('UI', sprintf('Circuit selected: %s (%d bytes)', file, info.bytes));
            app.CircuitStatsArea.Value = {sprintf('Selected file: %s', fullp), sprintf('Size: %d bytes', info.bytes)};
        end

        function onUploadCircuit(app)
            app.logEvent('API', sprintf('POST /api/circuits — file: %s', app.State.selectedFile));
            app.CircuitStatsArea.Value = {'Upload placeholder only.', sprintf('Target base URL: %s', app.State.baseUrl)};
        end

        function onAnalyzeCircuit(app)
            app.logEvent('API', 'POST /api/analyze — circuit feature extraction started');
            delete(app.FeatureTree.Children);
            root = uitreenode(app.FeatureTree, 'Text', 'Circuit');
            uitreenode(root, 'Text', 'Depth: 128');
            uitreenode(root, 'Text', 'Qubits: 27');
            uitreenode(root, 'Text', 'Two-qubit gates: 54');
            expand(root);
            app.SimilarityTable.Data = {'QFT-27', 0.91, 'Fourier'; 'BV-27', 0.66, 'Oracle'; 'Grover-20', 0.52, 'Search'};
            app.logEvent('API', 'Analysis complete — similarity table populated');
        end

        function onRefreshBackends(app)
            app.logEvent('API', 'GET /api/backends — refreshing backend list');
            app.BackendStatusArea.Value = {'Backend refresh placeholder.'};
            app.BackendTable.Data = { ...
                'ibm_brisbane', 127, 'online', 0.963, 'short', 'primary candidate'; ...
                'ibm_kyiv',     127, 'online', 0.954, 'medium','backup candidate'};
        end

        function onSelectBackend(app)
            data = app.BackendTable.Data;
            if isempty(data), return; end
            app.State.selectedBackend = string(data{1,1});
            app.logEvent('CONFIG', sprintf('Backend selected: %s', app.State.selectedBackend));
            app.BackendStatusArea.Value = {sprintf('Selected backend: %s', app.State.selectedBackend)};
        end

        function onRunBenchmark(app)
            shots = app.BenchmarkShotsField.Value;
            opt   = app.BenchmarkOptField.Value;
            app.logEvent('API', sprintf('POST /api/benchmark — shots=%g opt=%g', shots, opt));
            app.BenchmarkStatusArea.Value = {sprintf('Benchmark started with shots=%g and optimization=%g', shots, opt)};
        end

        function onRunPrediction(app)
            app.logEvent('API', 'POST /api/predictions — running fidelity prediction');
            app.PredictionTable.Data = {'Estimated runtime', '12.4 s'; 'Estimated fidelity', '0.981'; 'Expected queue', 'medium'};
            app.PredictionTextArea.Value = {'Prediction completed.'};
            app.logEvent('API', 'Prediction complete — fidelity: 0.981');
        end

        function onRefreshJobs(app)
            app.logEvent('API', 'GET /api/jobs — refreshing job list');
            app.JobsTable.Data = { ...
                'job-001','ibm_brisbane','running','67%', datestr(now,'yyyy-mm-dd HH:MM'); ...
                'job-002','ibm_kyiv',   'queued',  '12%', datestr(now,'yyyy-mm-dd HH:MM')};
            app.JobStatusArea.Value = {'Jobs refreshed.'};
            app.logEvent('API', 'Job list refreshed — 2 jobs');
        end

        function onCancelJob(app)
            app.logEvent('API', 'DELETE /api/jobs/:id — cancel job request sent');
            app.JobStatusArea.Value = {'Cancel request placeholder sent.'};
        end

        function onRefreshResults(app)
            app.logEvent('API', 'GET /api/results — loading result data');
            app.ResultsTable.Data = { ...
                'Success probability',  0.941, 0.952, 1.000, 'Close to model'; ...
                'Dominant state mass',  0.760, 0.774, 0.801, 'Minor readout loss'; ...
                'Two-qubit error',      0.041, 0.038, 0.000, 'Slightly above expectation'; ...
                'Readout contribution', 0.034, 0.032, 0.000, 'Stable'};
            app.ResultJsonArea.Value = {'Results refreshed.', sprintf('Timestamp: %s', datestr(now))};
            app.logEvent('API', 'Results loaded — 4 metrics');
        end

        function onPlotComparison(app)
            cla(app.CompareAxes);
            x = 1:5; y = [0.75 0.82 0.88 0.91 0.94];
            plot(app.CompareAxes, x, y, '-o');
            xlabel(app.CompareAxes, 'Candidate'); ylabel(app.CompareAxes, 'Similarity'); title(app.CompareAxes, 'Comparison');
        end

        function onPlotTemporal(app)
            cla(app.TemporalAxes);
            x = 1:10; y = cumsum(rand(1,10));
            plot(app.TemporalAxes, x, y, '-o');
            xlabel(app.TemporalAxes, 'Time'); ylabel(app.TemporalAxes, 'Metric'); title(app.TemporalAxes, 'Temporal');
        end

        function onPlotQubit(app)
            cla(app.QubitAxes);
            x = 1:12; y = rand(1,12);
            bar(app.QubitAxes, x, y);
            xlabel(app.QubitAxes, 'Qubit'); ylabel(app.QubitAxes, 'Error'); title(app.QubitAxes, 'Qubit');
        end

        function onGenerateReport(app)
            try; title = app.ReportTitleField.Value; catch; title = 'Report'; end
            try; fmt   = app.ReportFormatDropdown.Value; catch; fmt = 'PDF'; end
            app.logEvent('API', sprintf('POST /api/reports — format: %s, title: "%s"', fmt, title));
            app.ReportStatusArea.Value = { ...
                sprintf('Generating %s report: "%s"', fmt, title), ...
                'All pipeline sections included.', ...
                sprintf('Timestamp: %s', datestr(now)), ...
                'Status: template assembled — save to disk to export.'};
            app.logEvent('API', 'Report generation complete');
        end

        function onOpenReport(app)
            try
                sel = app.GeneratedReportList.Value;
                app.logEvent('UI', sprintf('Opening report: %s', sel));
                if isempty(sel)
                    app.ReportStatusArea.Value = {'No report selected in list.'};
                else
                    app.ReportStatusArea.Value = {sprintf('Opening: %s', sel), ...
                        '(Preview only in storyboard mode)'};
                end
            catch
                app.logEvent('ERROR', 'onOpenReport: no selection');
                app.ReportStatusArea.Value = {'Open report: not available in demo mode.'};
            end
        end

        function onClearLog(app)
            app.EventLog = {};
            try
                if ~isempty(app.EventLogArea) && isvalid(app.EventLogArea)
                    app.EventLogArea.Value = {'Log cleared.'};
                end
            catch; end
            fprintf('[%s] UI      Event log cleared\n', datestr(now,'HH:MM:SS.FFF'));
        end

        function onSaveSettings(app)
            app.logEvent('CONFIG', 'Settings save requested');
            try; app.State.baseUrl = string(app.BaseUrlField.Value); catch; end
            try; app.Client.setBaseUrl(app.State.baseUrl); catch; end
            app.logEvent('CONFIG', sprintf('Settings saved — base URL: %s', app.State.baseUrl));
            try
                % Confirm to user via the banner area if it still exists
                if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                    app.SettingsStatusArea.Value = {'Settings saved.'};
                end
            catch; end
            uialert(app.UIFigure, 'Settings saved for this session.', 'Settings', 'Icon', 'success');
        end
    end
end