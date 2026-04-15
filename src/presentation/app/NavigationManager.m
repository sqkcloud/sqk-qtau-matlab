classdef NavigationManager
    % NavigationManager  Screen switching, lazy ViewModel initialization,
    %                     nav styling, layout, and resize handling.
    %
    %   Extracted from QTAUWorkbenchApp to reduce class size.
    %   All methods are static — call as NavigationManager.onSelectSection(app, key).

    methods (Static)

        % ── Section switching ────────────────────────────────────────────

        function onSelectSection(app, key)
            if isstring(key); key = char(key); end
            app.logEvent('NAV', sprintf('Navigating to: %s', key));
            % Dismiss any popup that might still be visible from the
            % outgoing screen before we show the new one.
            try PopupMenuManager.dismissPopups(app); catch; end
            names = fieldnames(app.SectionPanels);
            for i = 1:numel(names)
                app.SectionPanels.(names{i}).Visible = 'off';
            end
            safeKey = matlab.lang.makeValidName(char(key));
            if isfield(app.SectionPanels, safeKey)
                app.SectionPanels.(safeKey).Visible = 'on';
            end
            app.SectionTitleLabel.Text    = key;
            app.SectionSubtitleLabel.Text = NavigationManager.sectionSubtitleFor(key);
            if ~strcmp(app.NavList.Value, key)
                app.NavList.Value = key;
            end
            NavigationManager.updateNavStyles(app, key);
            NavigationManager.onResizeUI(app);
            NavigationManager.autoLoadScreen(app, key);
        end

        function autoLoadScreen(app, key)
            NavigationManager.ensureVm(app, key);
            ttl = AppConfig.getDouble('screen_cache_ttl', 30);

            switch key
                case 'Welcome'
                    if app.State.isAuthenticated() && ~NavigationManager.isScreenFresh(app.WelcomeVm, ttl)
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
                        if ~NavigationManager.isScreenFresh(app.UploadVm, ttl)
                            app.UploadVm.onRefreshCircuits();
                        end
                    end
                case 'Circuits'
                    if ~isempty(app.CircuitsVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.CircuitsVm, ttl)
                        app.CircuitsVm.onLoadCircuits();
                    end
                case 'Dashboard'
                    if ~isempty(app.DashboardVm) && ~NavigationManager.isScreenFresh(app.DashboardVm, ttl)
                        app.DashboardVm.onRefreshDashboard();
                    elseif ~isempty(app.DashboardVm)
                        % Screen is fresh but activities may have changed from other screens
                        app.DashboardVm.refreshActivityTable();
                    end
                case 'Notes'
                    if ~isempty(app.NotesVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.NotesVm, ttl)
                        app.NotesVm.onLoadNotes();
                    end
                case 'Analysis'
                    if ~isempty(app.AnalysisVm) && ~NavigationManager.isScreenFresh(app.AnalysisVm, ttl)
                        app.AnalysisVm.onEnter();
                    end
                case 'Backends'
                    if ~isempty(app.BackendsVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.BackendsVm, ttl)
                        app.BackendsVm.onRefreshBackends();
                    end
                case 'Jobs'
                    if ~isempty(app.JobsVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.JobsVm, ttl)
                        app.JobsVm.onRefreshJobs();
                    end
                case 'Results'
                    if ~isempty(app.ResultsVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.ResultsVm, ttl)
                        app.ResultsVm.onRefreshResults();
                    end
                case 'Benchmark'
                    if ~isempty(app.BenchmarkVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.BenchmarkVm, ttl)
                        app.BenchmarkVm.onLoadBenchmark();
                    end
                case 'DetailedAnalysis'
                    % On first entry, paint seeded demo charts so the layout
                    % isn't empty. Skipped on subsequent entries so any live
                    % data from Refresh buttons is preserved.
                    if ~isempty(app.DetailedAnalysisVm) ...
                            && ~isempty(app.CompareAxes) && isvalid(app.CompareAxes) ...
                            && isempty(app.CompareAxes.Children)
                        app.DetailedAnalysisVm.plotAllDemos();
                    end
                case 'Settings'
                    if ~isempty(app.SettingsVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.SettingsVm, ttl)
                        app.SettingsVm.onEnter();
                    end
            end
        end

        % ── Lazy ViewModel initialization ────────────────────────────────

        function ensureVm(app, key)
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

        function fresh = isScreenFresh(vm, ttlSeconds)
            fresh = false;
            if isempty(vm); return; end
            try
                lr = vm.LastRefresh;
                if ~isempty(lr) && lr > 0
                    fresh = toc(lr) < ttlSeconds;
                end
            catch ME
                Logger.debug('NavigationManager', 'freshness check: %s', ME.message);
            end
        end

        % ── Nav sidebar ──────────────────────────────────────────────────

        function onToggleNav(app)
            app.NavCollapsed = ~app.NavCollapsed;
            if app.NavCollapsed
                app.BodyGrid.ColumnWidth = {56, '1x'};
                app.NavToggleButton.Text = char(9776);  % ☰
            else
                app.BodyGrid.ColumnWidth = {230, '1x'};
                app.NavToggleButton.Text = char(8801);  % ≡
            end
            NavigationManager.renderNavHtml(app, char(app.NavList.Value), app.NavCollapsed);
            NavigationManager.onResizeUI(app);
        end

        function updateNavStyles(app, activeKey)
            NavigationManager.renderNavHtml(app, activeKey, app.NavCollapsed);
        end

        function onNavHtmlClick(app, src)
            % Handles click events from the uihtml nav menu.
            try
                clickedName = char(string(src.Data));
                if ~isempty(clickedName)
                    app.onSelectSection(clickedName);
                end
            catch ME
                Logger.debug('NavigationManager', 'onNavHtmlClick: %s', ME.message);
            end
        end

        function renderNavHtml(app, activeKey, collapsed)
            % Generates HTML for the nav menu with consistent icon sizing.
            names = NavigationManager.navNames();
            icons = NavigationManager.navIcons();
            labels = NavigationManager.navLabels();

            activeBg  = '#4a7dd2';  % [0.29 0.49 0.82]
            normalBg  = '#293d63';  % [0.16 0.24 0.39]
            normalFg  = '#ebf5ff';  % [0.92 0.96 1.00]
            hoverBg   = '#34507a';

            css = [ ...
                'html,body{margin:0;padding:0;height:100%;overflow-y:auto;overflow-x:hidden;' ...
                'background:#1e304f;font-family:-apple-system,"Segoe UI",Roboto,sans-serif;}' ...
                '.nav{display:flex;flex-direction:column;gap:6px;padding:0;}' ...
                '.btn{display:flex;align-items:center;border:none;border-radius:6px;' ...
                'cursor:pointer;font-weight:700;font-size:14px;color:' normalFg ';' ...
                'background:' normalBg ';transition:background 0.15s;}' ...
                '.btn:hover{background:' hoverBg ';}' ...
                '.btn.active{background:' activeBg ';color:#fff;}' ...
                '.icon{display:inline-flex;align-items:center;justify-content:center;' ...
                'width:22px;height:22px;font-size:16px;flex-shrink:0;text-align:center;}' ...
                '.label{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}'];

            if collapsed
                css = [css '.btn{justify-content:center;padding:6px 0;height:32px;}' ...
                           '.label{display:none;}'];
            else
                css = [css '.btn{padding:6px 12px;height:32px;gap:10px;}'];
            end

            q = char(39);  % single-quote for JS strings
            items = '';
            for i = 1:numel(names)
                cls = 'btn';
                if strcmp(names{i}, activeKey); cls = 'btn active'; end
                btn = ['<button class="' cls '" onclick="sendClick(' q names{i} q ')">' ...
                       '<span class="icon">' icons{i} '</span>' ...
                       '<span class="label">' labels{i} '</span></button>'];
                items = [items btn]; %#ok<AGROW>
            end

            js = ['var _comp;' ...
                  'function setup(htmlComponent){_comp=htmlComponent;}' ...
                  'function sendClick(name){if(_comp){_comp.Data=name;}}'];

            app.NavHtml.HTMLSource = ['<html><head><style>' css '</style></head><body>' ...
                '<div class="nav">' items '</div>' ...
                '<script>' js '</script></body></html>'];
        end

        function n = navNames()
            n = {'Welcome','Dashboard','Circuits','Notes','Upload','Analysis','Backends', ...
                 'Benchmark','Prediction','Jobs','Results','Detailed Analysis', ...
                 'Benchmark Dashboard', ...
                 'QEC Simulation','QEC Visualization','Reports','Settings'};
        end

        function ic = navIcons()
            % Icon characters — kept semantic (house, grid, pencil, etc.).
            % Sizing is handled by the CSS .icon container, not the glyph.
            ic = { ...
                char(8962),  ... ⌂ Welcome
                char(9707),  ... ◫ Dashboard
                char(9776),  ... ☰ Circuits
                char(9998),  ... ✎ Notes
                char(8593),  ... ↑ Upload
                char(8981),  ... ⌕ Analysis
                char(9004),  ... ⌬ Backends
                char(9678),  ... ◎ Benchmark
                char(9671),  ... ◇ Prediction
                char(9635),  ... ▣ Jobs
                char(9633),  ... □ Results
                char(9651),  ... △ Detailed Analysis
                char(9670),  ... ◆ Benchmark Dashboard
                char(9673),  ... ◉ QEC Simulation
                char(9672),  ... ◈ QEC Visualization
                char(9636),  ... ▤ Reports
                char(9881)}; % ⚙ Settings
        end

        function lb = navLabels()
            % Text labels (no icon prefix — icon is rendered separately).
            lb = {'Welcome','Dashboard','Circuits','Notes','Upload','Analysis','Backends', ...
                  'Benchmark','Prediction','Jobs','Results','Detailed Analysis', ...
                  'Benchmark Dashboard', ...
                  'QEC Simulation','QEC Visualization','Reports','Settings'};
        end

        function labels = navMenuLabels()
            % Legacy: full "icon  Label" strings for any remaining callers.
            ic = NavigationManager.navIcons();
            lb = NavigationManager.navLabels();
            labels = cell(1, numel(lb));
            for i = 1:numel(lb)
                labels{i} = [ic{i} '  ' lb{i}];
            end
        end

        function labels = navCollapsedLabels()
            labels = NavigationManager.navIcons();
        end

        function subtitle = sectionSubtitleFor(key)
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

        % ── Section page creation ────────────────────────────────────────

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

        % ── Layout / resize ──────────────────────────────────────────────

        function fitSectionPanel(panel)
            if isempty(panel) || ~isvalid(panel); return; end
            try
                p = panel.Parent;
                if ~isempty(p) && isvalid(p)
                    panel.Position = [0 0 max(1, p.Position(3)) max(1, p.Position(4))];
                end
            catch ME; Logger.debug('NavigationManager', 'fitSectionPanel: %s', ME.message); end
        end

        function fitAllSections(app)
            try
                names = fieldnames(app.SectionPanels);
                for i = 1:numel(names)
                    NavigationManager.fitSectionPanel(app.SectionPanels.(names{i}));
                end
            catch ME; Logger.debug('NavigationManager', 'fitAllSections: %s', ME.message); end
        end

        function onResizeUI(app)
            NavigationManager.fitAllSections(app);
            OverlayManager.fitAuthOverlay(app);
        end

        function forceInitialLayout(app)
            try
                drawnow(); pause(0.05);
                NavigationManager.fitAllSections(app); NavigationManager.onResizeUI(app);
                drawnow(); pause(0.02);
                NavigationManager.fitAllSections(app);
            catch ME; Logger.debug('NavigationManager', 'forceInitialLayout: %s', ME.message); end
        end

    end
end
