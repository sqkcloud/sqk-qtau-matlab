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
            catch
            end
        end

        % ── Nav sidebar ──────────────────────────────────────────────────

        function onToggleNav(app)
            app.NavCollapsed = ~app.NavCollapsed;
            if app.NavCollapsed
                app.BodyGrid.ColumnWidth = {56, '1x'};
                short = NavigationManager.navCollapsedLabels();
                for i = 1:min(numel(app.NavButtons), numel(short))
                    app.NavButtons(i).Text = short{i};
                    app.NavButtons(i).HorizontalAlignment = 'center';
                end
                app.NavToggleButton.Text = char(9776);  % ☰
            else
                app.BodyGrid.ColumnWidth = {230, '1x'};
                full = NavigationManager.navMenuLabels();
                for i = 1:min(numel(app.NavButtons), numel(full))
                    app.NavButtons(i).Text = [' ' full{i}];
                    app.NavButtons(i).HorizontalAlignment = 'left';
                end
                app.NavToggleButton.Text = char(8801);  % ≡
            end
            NavigationManager.updateNavStyles(app, char(app.NavList.Value));
            NavigationManager.onResizeUI(app);
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

        function labels = navMenuLabels()
            labels = { ...
                Labels.get('nav_welcome',           [char(8962) '  Welcome']), ...
                Labels.get('nav_dashboard',         [char(9707) '  Dashboard']), ...
                Labels.get('nav_circuits',          [char(9776) '  Circuits']), ...
                Labels.get('nav_notes',             [char(9998) '  Notes']), ...
                Labels.get('nav_upload',            [char(10548) '  Upload']), ...
                Labels.get('nav_analysis',          [char(8981) '  Analysis']), ...
                Labels.get('nav_backends',          [char(9004) '  Backends']), ...
                Labels.get('nav_benchmark',         [char(9678) '  Benchmark']), ...
                Labels.get('nav_prediction',        [char(9671) '  Prediction']), ...
                Labels.get('nav_jobs',              [char(9635) '  Jobs']), ...
                Labels.get('nav_results',           [char(9633) '  Results']), ...
                Labels.get('nav_detailed_analysis',      [char(9651) '  Detailed Analysis']), ...
                Labels.get('nav_benchmark_dashboard',   [char(9670) '  Benchmark Dashboard']), ...
                Labels.get('nav_qec_simulation',        [char(9673) '  QEC Simulation']), ...
                Labels.get('nav_qec_visualization',     [char(9672) '  QEC Visualization']), ...
                Labels.get('nav_reports',               [char(9636) '  Reports']), ...
                Labels.get('nav_settings',              [char(9881) '  Settings'])};
        end

        function labels = navCollapsedLabels()
            labels = { ...
                Labels.get('nav_short_welcome',           char(8962)), ...
                Labels.get('nav_short_dashboard',         char(9707)), ...
                Labels.get('nav_short_circuits',          char(9776)), ...
                Labels.get('nav_short_notes',             char(9998)), ...
                Labels.get('nav_short_upload',            char(10548)), ...
                Labels.get('nav_short_analysis',          char(8981)), ...
                Labels.get('nav_short_backends',          char(9004)), ...
                Labels.get('nav_short_benchmark',         char(9678)), ...
                Labels.get('nav_short_prediction',        char(9671)), ...
                Labels.get('nav_short_jobs',              char(9635)), ...
                Labels.get('nav_short_results',           char(9633)), ...
                Labels.get('nav_short_detailed_analysis',      char(9651)), ...
                Labels.get('nav_short_benchmark_dashboard',   char(9670)), ...
                Labels.get('nav_short_qec_simulation',        char(9673)), ...
                Labels.get('nav_short_qec_visualization',     char(9672)), ...
                Labels.get('nav_short_reports',               char(9636)), ...
                Labels.get('nav_short_settings',              char(9881))};
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
