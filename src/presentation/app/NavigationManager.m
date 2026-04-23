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
                panel = app.SectionPanels.(names{i});
                if isempty(panel) || ~isvalid(panel)
                    Logger.debug('NavigationManager', ...
                        'skipping invalid panel: %s', names{i});
                    continue;
                end
                panel.Visible = 'off';
            end
            safeKey = matlab.lang.makeValidName(char(key));
            if isfield(app.SectionPanels, safeKey)
                panel = app.SectionPanels.(safeKey);
                if ~isempty(panel) && isvalid(panel)
                    panel.Visible = 'on';
                end
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

            % Centralised "Loading {screen}..." overlay. We flip it on
            % right before firing any VM auto-loader that is actually
            % going to do async work (stale cache), and off again via
            % the VM's own hideLoading in its done/error callback. A
            % safety timer auto-dismisses after 20s so a forgetful VM
            % cannot leave a stuck overlay.  Fresh-cache hits skip the
            % overlay entirely so nav stays snappy when there's nothing
            % to fetch.
            switch key
                case 'Welcome'
                    if app.State.isAuthenticated() && ~NavigationManager.isScreenFresh(app.WelcomeVm, ttl)
                        NavigationManager.showNavLoading(app, 'Welcome');
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
                            NavigationManager.showNavLoading(app, 'Upload');
                            app.UploadVm.onRefreshCircuits();
                        end
                    end
                case 'Circuits'
                    if ~isempty(app.CircuitsVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.CircuitsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Circuits');
                        app.CircuitsVm.onLoadCircuits();
                    end
                case 'Dashboard'
                    if ~isempty(app.DashboardVm) && ~NavigationManager.isScreenFresh(app.DashboardVm, ttl)
                        NavigationManager.showNavLoading(app, 'Dashboard');
                        app.DashboardVm.onRefreshDashboard();
                    elseif ~isempty(app.DashboardVm)
                        % Screen is fresh but activities may have changed from other screens
                        app.DashboardVm.refreshActivityTable();
                    end
                case 'Notes'
                    if ~isempty(app.NotesVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.NotesVm, ttl)
                        NavigationManager.showNavLoading(app, 'Notes');
                        app.NotesVm.onLoadNotes();
                    end
                case 'Analysis'
                    if ~isempty(app.AnalysisVm) && ~NavigationManager.isScreenFresh(app.AnalysisVm, ttl)
                        NavigationManager.showNavLoading(app, 'Analysis');
                        app.AnalysisVm.onEnter();
                    end
                case 'Backends'
                    if ~isempty(app.BackendsVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.BackendsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Backends');
                        app.BackendsVm.onRefreshBackends();
                    end
                case 'Prediction'
                    if ~isempty(app.PredictionVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.PredictionVm, ttl)
                        NavigationManager.showNavLoading(app, 'Prediction');
                        app.PredictionVm.onEnter();
                    end
                case 'Jobs'
                    if ~isempty(app.JobsVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.JobsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Jobs');
                        app.JobsVm.onRefreshJobs();
                    end
                    % Keep the Job Monitoring Dashboard live: auto-poll
                    % GET /api/jobs every 5s while the Jobs screen is
                    % visible. Status/Progress columns update without
                    % the user having to hit Refresh. The timer self-
                    % terminates on the next tick after the user
                    % navigates away.
                    if ~isempty(app.JobsVm) && app.State.hasProject()
                        app.JobsVm.startAutoRefresh(5);
                    end
                case 'Results'
                    if ~isempty(app.ResultsVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.ResultsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Results');
                        app.ResultsVm.onRefreshResults();
                    end
                case 'Benchmark'
                    if ~isempty(app.BenchmarkVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.BenchmarkVm, ttl)
                        NavigationManager.showNavLoading(app, 'Benchmark');
                        app.BenchmarkVm.onLoadBenchmark();
                    end
                case 'Detailed Analysis'
                    % On first entry, paint seeded demo charts so the layout
                    % isn't empty. Skipped on subsequent entries so any live
                    % data from Refresh buttons is preserved.
                    if ~isempty(app.DetailedAnalysisVm) ...
                            && ~isempty(app.CompareAxes) && isvalid(app.CompareAxes) ...
                            && isempty(app.CompareAxes.Children)
                        app.DetailedAnalysisVm.plotAllDemos();
                    end
                    % Populate the Circuit dropdown whenever we enter the
                    % screen — the user may have uploaded new circuits
                    % elsewhere in the session.
                    if ~isempty(app.DetailedAnalysisVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.DetailedAnalysisVm, ttl)
                        NavigationManager.showNavLoading(app, 'Detailed Analysis');
                        app.DetailedAnalysisVm.onEnter();
                    end
                case 'Benchmark Dashboard'
                    if ~isempty(app.BenchmarkDashboardVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.BenchmarkDashboardVm, ttl)
                        NavigationManager.showNavLoading(app, 'Benchmark Dashboard');
                        app.BenchmarkDashboardVm.onEnter();
                    end
                case 'Settings'
                    if ~isempty(app.SettingsVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.SettingsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Settings');
                        app.SettingsVm.onEnter();
                    end
            end
        end

        % ── Nav-triggered loading overlay ───────────────────────────────
        %   A VM's own showLoading() call (if any) will overwrite the
        %   message with something more specific. A VM's hideLoading()
        %   in its done/error callback dismisses it; the safety timer
        %   auto-dismisses after 20s for VMs that forget.

        function showNavLoading(app, key)
            try
                label = sprintf('Loading %s...', char(key));
                app.showLoading(label);
            catch ME
                Logger.debug('NavigationManager', 'showNavLoading: %s', ME.message);
                return;
            end
            NavigationManager.armNavOverlayTimer(app, 20);
        end

        function armNavOverlayTimer(app, seconds)
            % Start (or restart) the safety timer that dismisses the
            % loading overlay if nothing else does. Always disarms any
            % prior timer first so rapid nav doesn't stack timers.
            NavigationManager.disarmNavOverlayTimer(app);
            try
                t = timer( ...
                    'StartDelay', seconds, ...
                    'BusyMode',   'drop', ...
                    'Name',       'NavOverlayAutoDismiss', ...
                    'TimerFcn',   @(src,~) NavigationManager.onNavOverlayTimeout(app, src));
                app.NavOverlayTimer = t;
                start(t);
            catch ME
                Logger.debug('NavigationManager', 'armNavOverlayTimer: %s', ME.message);
            end
        end

        function disarmNavOverlayTimer(app)
            try
                if isprop(app, 'NavOverlayTimer') && ~isempty(app.NavOverlayTimer) ...
                        && isvalid(app.NavOverlayTimer)
                    stop(app.NavOverlayTimer);
                    delete(app.NavOverlayTimer);
                end
            catch
            end
            try; app.NavOverlayTimer = []; catch; end
        end

        function onNavOverlayTimeout(app, src)
            try; stop(src); delete(src); catch; end
            try; app.NavOverlayTimer = []; catch; end
            try
                app.hideLoading();
                Logger.debug('NavigationManager', ...
                    'Nav loading overlay auto-dismissed by safety timer');
            catch
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
                case 'Detailed Analysis'
                    if isempty(app.DetailedAnalysisVm); app.DetailedAnalysisVm = DetailedAnalysisViewModel(app); end
                case 'Benchmark Dashboard'
                    if isempty(app.BenchmarkDashboardVm); app.BenchmarkDashboardVm = BenchmarkDashboardViewModel(app); end
                case 'Reports'
                    if isempty(app.ReportsVm); app.ReportsVm = ReportsViewModel(app); end
                case 'Settings'
                    if isempty(app.SettingsVm); app.SettingsVm = SettingsViewModel(app); end
                case 'QEC Simulation'
                    if isempty(app.QecSimulationVm); app.QecSimulationVm = QecSimulationViewModel(app); end
                case 'QEC Visualization'
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
                app.BodyGrid.ColumnWidth = {260, '1x'};
                app.NavToggleButton.Text = char(8801);  % ≡
            end
            NavigationManager.renderNavHtml(app, char(app.NavList.Value), app.NavCollapsed);
            NavigationManager.onResizeUI(app);
        end

        function updateNavStyles(app, activeKey)
            % Push active-item change via Data instead of rebuilding
            % HTMLSource. Rebuilding on every nav click tears down the
            % browser DOM mid-event-dispatch, which races with MATLAB's
            % internal controller lookup and surfaces as
            %   "Invalid or deleted object" / "Value must be a handle"
            % inside HTML/getComponentToApplyButtonEvent or
            % HTML/sendFlushEventToClient. The JS listener installed by
            % renderNavHtml reads {a:'setActive', name:...} and toggles
            % the .active class in place, keeping the DOM intact.
            if isempty(app.NavHtml) || ~isvalid(app.NavHtml); return; end
            app.NavHtml.Data = struct('a', 'setActive', 'name', activeKey);
        end

        function onNavHtmlClick(app, src)
            % Handles click events from the uihtml nav menu. DataChanged
            % fires for both directions (client-set and MATLAB-set), so
            % filter: clicks from the browser arrive as plain strings,
            % while our own pushes from updateNavStyles are structs.
            try
                d = src.Data;
                if isstruct(d); return; end
                clickedName = char(string(d));
                if ~isempty(clickedName)
                    app.onSelectSection(clickedName);
                end
            catch ME
                Logger.debug('NavigationManager', 'onNavHtmlClick: %s', ME.message);
            end
        end

        function renderNavHtml(app, activeKey, collapsed)
            % Generates HTML for the nav menu with consistent icon sizing.
            % Called on initial build, collapse toggle, and theme change —
            % NOT on every nav click (see updateNavStyles).
            names = NavigationManager.navNames();
            icons = NavigationManager.navIcons();
            labels = NavigationManager.navLabels();

            activeBg   = Theme.toHex(Theme.NAV_ACTIVE_BG);
            activeFg   = Theme.toHex(Theme.NAV_ACTIVE_FG);
            normalBg   = Theme.toHex(Theme.NAV_BG);
            normalFg   = Theme.toHex(Theme.NAV_FG);
            hoverBg    = Theme.toHex(Theme.NAV_HOVER_BG);
            bodyBg     = Theme.toHex(Theme.NAV_BG);

            css = [ ...
                'html,body{margin:0;padding:0;height:100%;overflow-y:auto;overflow-x:hidden;' ...
                'background:' bodyBg ';font-family:-apple-system,"Segoe UI",Roboto,sans-serif;}' ...
                '.nav{display:flex;flex-direction:column;gap:6px;padding:0;}' ...
                '.btn{display:flex;align-items:center;border:none;border-radius:6px;' ...
                'cursor:pointer;font-weight:700;font-size:14px;color:' normalFg ';' ...
                'background:' normalBg ';transition:background 0.15s;}' ...
                '.btn:hover{background:' hoverBg ';}' ...
                '.btn.active{background:' activeBg ';color:' activeFg ';}' ...
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
                btn = ['<button class="' cls '" data-name="' names{i} '" onclick="sendClick(' q names{i} q ')">' ...
                       '<span class="icon">' icons{i} '</span>' ...
                       '<span class="label">' labels{i} '</span></button>'];
                items = [items btn]; %#ok<AGROW>
            end

            js = ['var _comp;' ...
                  'function applyActive(n){var bs=document.querySelectorAll(".btn");' ...
                  'for(var i=0;i<bs.length;i++){' ...
                  'if(bs[i].getAttribute("data-name")===n){bs[i].classList.add("active");}' ...
                  'else{bs[i].classList.remove("active");}}}' ...
                  'function setup(htmlComponent){' ...
                  '_comp=htmlComponent;' ...
                  'htmlComponent.addEventListener("DataChanged",function(){' ...
                  'var d=_comp.Data;' ...
                  'if(d&&typeof d==="object"&&d.a==="setActive"){applyActive(d.name);}' ...
                  '});' ...
                  'var d0=_comp.Data;' ...
                  'if(d0&&typeof d0==="object"&&d0.a==="setActive"){applyActive(d0.name);}' ...
                  '}' ...
                  'function sendClick(name){if(_comp){_comp.Data=name;}}'];

            app.NavHtml.HTMLSource = ['<html><head><style>' css '</style></head><body>' ...
                '<div class="nav">' items '</div>' ...
                '<script>' js '</script></body></html>'];
        end

        function n = navNames()
            % Notes intentionally omitted — hidden from the sidebar for
            % now. The NotesScreen / NotesViewModel are still wired up
            % in QTAUWorkbenchApp so the tab can be re-enabled later by
            % adding 'Notes' back to navNames / navIcons / navLabels.
            n = {'Welcome','Dashboard','Circuits','Upload','Analysis','Backends', ...
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
            lb = {'Welcome','Dashboard','Circuits','Upload','Analysis','Backends', ...
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
            panel.BackgroundColor    = Theme.COLOR_BG;
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
