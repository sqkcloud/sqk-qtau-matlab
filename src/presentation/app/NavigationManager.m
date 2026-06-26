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
            % Lazy screen build: builds the panel + widgets the first
            % time the user nav-clicks here. Subsequent visits are a
            % no-op and snap instantly. See QTAUWorkbenchApp.buildUI for
            % the rationale (eager build cost ~32s of startup).
            NavigationManager.ensureScreenBuilt(app, key);

            % Hide the previously-visible panel only. The pre-perf-pass
            % loop iterated every entry in app.SectionPanels and set
            % Visible='off' on each — but uipanel.Visible writes
            % trigger a layout pass even when the value is already
            % 'off', so the loop paid ~10 ms × 22 panels (≈200 ms)
            % per nav for no benefit.
            prevKey = '';
            try
                if isprop(app, 'LastSectionKey'); prevKey = char(app.LastSectionKey); end
            catch; end
            if ~isempty(prevKey) && ~strcmp(prevKey, char(key))
                prevSafe = matlab.lang.makeValidName(prevKey);
                if isfield(app.SectionPanels, prevSafe)
                    prevPanel = app.SectionPanels.(prevSafe);
                    if ~isempty(prevPanel) && isvalid(prevPanel)
                        prevPanel.Visible = 'off';
                    end
                end
                % B7 — cancel any in-flight AsyncRunner futures owned by
                % the outgoing VM so a 30-second fetch the user left
                % behind doesn't keep burning the worker + 50ms polling
                % timer. cancelInFlightFor maps the routing key to the
                % VM and is a no-op for screens that haven't implemented
                % cancelInFlight yet.
                NavigationManager.cancelInFlightFor(app, prevKey);
            end

            safeKey = matlab.lang.makeValidName(char(key));
            if isfield(app.SectionPanels, safeKey)
                panel = app.SectionPanels.(safeKey);
                if ~isempty(panel) && isvalid(panel)
                    % Fit BEFORE Visible='on' so the first paint uses
                    % the correct size — prevents the resize-flash
                    % that happened when the window had been resized
                    % while this panel was hidden. Other panels are
                    % re-fitted on demand the next time they become
                    % visible (instead of every nav, as the old
                    % fitAllSections loop did).
                    NavigationManager.fitSectionPanel(panel);
                    panel.Visible = 'on';
                end
            end
            try; app.LastSectionKey = string(key); catch; end

            % Phase 8: resolve the displayed title via navLabels so
            % the screen header shows "Projects" when the user picks
            % the Welcome routing key (the routing key 'Welcome' is
            % preserved for back-compat; only the displayed label
            % changed).
            app.SectionTitleLabel.Text    = NavigationManager.displayLabelFor(key);
            app.SectionSubtitleLabel.Text = NavigationManager.sectionSubtitleFor(key);
            % NavList.Items mirrors navNames (visible sidebar entries
             % only). When a cross-screen bridge routes to a hidden key
             % (Composer / Detailed Analysis / Benchmark Dashboard /
             % Upload / Notes) the listbox would reject the value and
             % throw validateValuePresentInItems. Skip the assignment in
             % that case — the hidden listbox is invisible UI plumbing
             % from a pre-uihtml era and not user-facing.
            if any(strcmp(app.NavList.Items, key)) && ~strcmp(app.NavList.Value, key)
                app.NavList.Value = key;
            end
            NavigationManager.updateNavStyles(app, key);
            % Auth overlay sits on top of every section and must follow
            % the new visible panel's size. The pre-perf-pass
            % onResizeUI() call also looped every panel via
            % fitAllSections — we've already resized the active panel
            % above, so call only the auth-overlay helper directly.
            NavigationManager.refreshAuthOverlay(app, key);
            NavigationManager.autoLoadScreen(app, key);
        end

        % ── Lazy screen building ─────────────────────────────────────────
        function ensureScreenBuilt(app, key)
            % Build a screen's UI on first visit, no-op after that.
            % Welcome is built eagerly during boot; everything else is
            % deferred so startup is ~2 s instead of ~32 s.
            try
                if isempty(app.BuiltScreens) || ~isa(app.BuiltScreens, 'containers.Map')
                    app.BuiltScreens = containers.Map('KeyType','char','ValueType','logical');
                end
                if isKey(app.BuiltScreens, key) && app.BuiltScreens(key)
                    return;
                end
            catch
                % If BuiltScreens is somehow unusable, fall through and
                % attempt the build — the screen builder will overwrite
                % any half-built panel via createSectionPage.
            end
            builder = NavigationManager.screenBuilderFor(key);
            if isempty(builder); return; end
            try
                % Use the same message format as showNavLoading so the
                % idempotent fast-path in OverlayManager.showLoading
                % matches and the second showLoading call (from
                % autoLoadScreen) is a no-op instead of an HTMLSource
                % rebuild that flickers.
                app.showLoading(sprintf('Loading %s...', key));
                % drawnow + pause + drawnow forces the loading overlay
                % uihtml to actually PAINT before the synchronous builder
                % hogs the main thread. Without the pause, the JS render
                % is queued but not flushed: the user sees the panel
                % render naked first (1-2 s for slow screens) and then
                % the overlay only appears AFTER the builder returns,
                % which is the inverse of what makes sense to a user.
                %
                % 30 ms covers one CEF vsync frame (~16 ms); the prior
                % 100 ms was conservative and added a flat tax to every
                % first-visit of every screen (~70 ms × 22 screens =
                % ~1.5 s wasted across the session).
                drawnow;
                pause(0.03);
                drawnow;
                % Fire the data fetch IN PARALLEL with the screen build.
                % Builder + first-paint of widget-heavy screens (uitable,
                % uihtml) blocks the main thread ~1-1.5 s; the AsyncRunner
                % polling timer cannot fire its callback while the main
                % thread is busy, so the fetch and the build now overlap
                % instead of serializing. autoLoadScreen reads each VM's
                % PrefetchInFlight flag to avoid a redundant second fetch.
                NavigationManager.kickPrefetch(app, key);
                builder(app);
                app.BuiltScreens(key) = true;
                Logger.info('NavigationManager', ...
                    'Screen built on first nav: %s', key);
                % NOTE: previously this hid the overlay here ("drop the
                % build-time overlay so autoLoadScreen can re-show its
                % own").  That caused a visible double-flicker because
                % hideLoading -> showLoading triggered two CEF render
                % frames.  Instead we leave the overlay UP and let
                % autoLoadScreen either (a) keep it up via the
                % idempotent showNavLoading call (when async work is
                % about to fire) or (b) hide it at end-of-autoLoadScreen
                % when no async work was kicked.  Single continuous
                % overlay, no flicker.
            catch ME
                Logger.error('NavigationManager', ...
                    'Screen build failed for %s: %s', key, ME.message);
                % Make sure a build failure also drops the overlay -
                % otherwise a single bad screen builder leaves the
                % entire UI stuck behind the spinner.
                try; app.hideLoading(); catch; end
            end
        end

        function kickPrefetch(app, key)
            % Pre-fire the data fetch for screens whose initial widget
            % paint blocks the main thread for ~500 ms+. Called from
            % ensureScreenBuilt BEFORE the builder runs, so the HTTP
            % request flies to the backgroundPool worker in parallel
            % with widget construction + first paint. Each VM sets a
            % PrefetchInFlight flag that autoLoadScreen reads to skip
            % the otherwise-redundant second fetch.
            %
            % Add new cases here when profiling shows another screen
            % paying a noticeable build/paint gap before its first
            % onLoad* call. Keep this list narrow — every entry costs
            % one HTTP call on every first nav.
            try
                switch char(key)
                    case 'Circuits'
                        if ~isempty(app.CircuitsVm)
                            app.CircuitsVm.prefetchCircuits();
                        end
                end
            catch ME
                Logger.debug('NavigationManager', 'kickPrefetch(%s): %s', char(key), ME.message);
            end
        end

        function fcn = screenBuilderFor(key)
            % Map sidebar key → screen-builder function handle.
            switch key
                case 'Welcome';              fcn = @WelcomeScreen;
                case 'Dashboard';            fcn = @DashboardScreen;
                case 'Circuits';             fcn = @CircuitsScreen;
                case 'Composer';             fcn = @ComposerScreen;
                case 'Notes';                fcn = @NotesScreen;
                case 'Upload';               fcn = @UploadScreen;
                case 'Analysis';             fcn = @AnalysisScreen;
                case 'Backends';             fcn = @BackendsScreen;
                case 'Benchmark';            fcn = @BenchmarkScreen;
                case 'Prediction';           fcn = @PredictionScreen;
                case 'Mitigation Compare';   fcn = @MitigationCompareScreen;
                case 'Resource Estimator';   fcn = @ResourceEstimatorScreen;
                case 'Run Planner';          fcn = @RunPlannerScreen;
                case 'Jobs';                 fcn = @JobsScreen;
                case 'Results';              fcn = @ResultsScreen;
                case 'Detailed Analysis';    fcn = @DetailedAnalysisScreen;
                case 'Benchmark Dashboard';  fcn = @BenchmarkDashboardScreen;
                case 'Circuit Cutting';      fcn = @CircuitCuttingScreen;
                case 'QEC Simulation';       fcn = @QecSimulationScreen;
                case 'QEC Visualization';    fcn = @QecVisualizationScreen;
                case 'Reports';              fcn = @ReportsScreen;
                case 'Settings';             fcn = @SettingsScreen;
                otherwise;                   fcn = [];
            end
        end

        function autoLoadScreen(app, key)
            NavigationManager.ensureVm(app, key);
            % B10 — per-screen TTL with fallback to the global default
            % (30 s). The config-style screens (Backends / Mitigation
            % Compare / Resource Estimator / Run Planner) override to
            % 300 s in app.properties so a quick nav-away-and-back
            % doesn't re-fire ~750 ms worth of round-trips for data
            % that hasn't changed in a session.
            ttl = NavigationManager.ttlForScreen(key);

            % Centralised "Loading {screen}..." overlay. We flip it on
            % right before firing any VM auto-loader that is actually
            % going to do async work (stale cache), and off again via
            % the VM's own hideLoading in its done/error callback. A
            % safety timer auto-dismisses after 20s so a forgetful VM
            % cannot leave a stuck overlay.  Fresh-cache hits skip the
            % overlay entirely so nav stays snappy when there's nothing
            % to fetch.
            %
            % asyncStarted tracks whether any case in the switch below
            % actually kicked async work (which will hide the overlay
            % from its own callback).  When false, we hide the
            % build-time overlay (left up by ensureScreenBuilt) at the
            % end of this function so the user sees a single continuous
            % overlay, never the previous double-flicker.
            asyncStarted = false;

            switch key
                case 'Welcome'
                    if app.State.isAuthenticated() && ~NavigationManager.isScreenFresh(app.WelcomeVm, ttl)
                        NavigationManager.showNavLoading(app, 'Welcome');
                        app.WelcomeVm.onFetchProjects();
                        asyncStarted = true;
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
                            asyncStarted = true;
                        end
                    end
                case 'Circuits'
                    if ~isempty(app.CircuitsVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.CircuitsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Circuits');
                        % If kickPrefetch already dispatched the call,
                        % the overlay is already up and the worker is
                        % busy — no need to fire a second listCircuits.
                        if ~app.CircuitsVm.PrefetchInFlight
                            app.CircuitsVm.onLoadCircuits();
                        end
                        asyncStarted = true;
                    end
                case 'Dashboard'
                    if ~isempty(app.DashboardVm) && ~NavigationManager.isScreenFresh(app.DashboardVm, ttl)
                        NavigationManager.showNavLoading(app, 'Dashboard');
                        app.DashboardVm.onRefreshDashboard();
                        asyncStarted = true;
                    elseif ~isempty(app.DashboardVm)
                        % Screen is fresh but activities may have changed from other screens
                        app.DashboardVm.refreshActivityTable();
                    end
                case 'Notes'
                    if ~isempty(app.NotesVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.NotesVm, ttl)
                        NavigationManager.showNavLoading(app, 'Notes');
                        app.NotesVm.onLoadNotes();
                        asyncStarted = true;
                    end
                case 'Analysis'
                    if ~isempty(app.AnalysisVm) && ~NavigationManager.isScreenFresh(app.AnalysisVm, ttl)
                        NavigationManager.showNavLoading(app, 'Analysis');
                        app.AnalysisVm.onEnter();
                        asyncStarted = true;
                    end
                case 'Backends'
                    % B2 skin-first: VM.onRefreshBackends drops a
                    % "Loading backends..." line into the in-panel
                    % BackendStatusArea while the async fetch runs.
                    % The full-screen nav overlay is gone — the user
                    % sees the toolbar, the empty backends table, and
                    % the status line immediately, and the table
                    % populates inline as soon as /api/backends lands.
                    if ~isempty(app.BackendsVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.BackendsVm, ttl)
                        app.BackendsVm.onRefreshBackends();
                    end
                case 'Prediction'
                    if ~isempty(app.PredictionVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.PredictionVm, ttl)
                        NavigationManager.showNavLoading(app, 'Prediction');
                        app.PredictionVm.onEnter();
                        asyncStarted = true;
                    end
                case 'Mitigation Compare'
                    % B2 skin-first: VM.onEnter signals progress via its
                    % inline StatusLbl ("Loading circuits / backends /
                    % strategies…"), the dropdowns already show
                    % " (loading)" placeholders, and the card grid
                    % shows its empty-state prompt. The full-screen
                    % overlay is dropped — the tail-end of
                    % autoLoadScreen lets the build-time overlay (if
                    % any) hide via `~asyncStarted` so the panel
                    % becomes interactive immediately.
                    if ~isempty(app.MitigationCompareVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.MitigationCompareVm, ttl)
                        app.MitigationCompareVm.onEnter();
                    end
                case 'Resource Estimator'
                    % B2 skin-first: VM.onEnter writes 'Loading
                    % circuits…' to its StatusLbl and the result cards
                    % display em-dash placeholders until Estimate is
                    % clicked. No full-screen overlay needed on auto-
                    % load.
                    if ~isempty(app.ResourceEstimatorVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.ResourceEstimatorVm, ttl)
                        app.ResourceEstimatorVm.onEnter();
                    end
                case 'Run Planner'
                    % B2 skin-first: VM.onEnter sets Phase='loading'
                    % which refreshStatus writes to StatusLbl. The
                    % scatter axes ship a uilabel placeholder and the
                    % recommendation card shows em-dash defaults.
                    if ~isempty(app.RunPlannerVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.RunPlannerVm, ttl)
                        app.RunPlannerVm.onEnter();
                    end
                case 'Jobs'
                    if ~isempty(app.JobsVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.JobsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Jobs');
                        app.JobsVm.onRefreshJobs();
                        asyncStarted = true;
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
                        asyncStarted = true;
                    end
                case 'Benchmark'
                    if ~isempty(app.BenchmarkVm) && app.State.hasProject() ...
                            && ~NavigationManager.isScreenFresh(app.BenchmarkVm, ttl)
                        NavigationManager.showNavLoading(app, 'Benchmark');
                        app.BenchmarkVm.onLoadBenchmark();
                        asyncStarted = true;
                    end
                case 'Detailed Analysis'
                    % First-entry demo paint REMOVED on purpose: the
                    % hardcoded demos were identical for every circuit
                    % and gave the operator the impression Detailed
                    % Analysis didn't actually depend on the selected
                    % circuit. The new flow paints either real per-
                    % circuit data (resolved via the latest completed
                    % job) or an explicit "no completed jobs yet"
                    % empty-state — both wired through onEnter →
                    % loadCircuits → onDetailedCircuitsLoaded →
                    % refreshAllForCircuit on the VM. plotAllDemos
                    % stays defined as a per-axis fallback inside
                    % individual onPlotXxxComplete handlers when the
                    % backend returns an empty list for that specific
                    % metric — narrow safety net, not the screen-wide
                    % misleader.
                    if ~isempty(app.DetailedAnalysisVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.DetailedAnalysisVm, ttl)
                        NavigationManager.showNavLoading(app, 'Detailed Analysis');
                        app.DetailedAnalysisVm.onEnter();
                        asyncStarted = true;
                    end
                case 'Benchmark Dashboard'
                    if ~isempty(app.BenchmarkDashboardVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.BenchmarkDashboardVm, ttl)
                        NavigationManager.showNavLoading(app, 'Benchmark Dashboard');
                        app.BenchmarkDashboardVm.onEnter();
                        asyncStarted = true;
                    end
                case 'Circuit Cutting'
                    % B2 skin-first: VM.onEnter fires loadCircuits /
                    % loadPresets / loadBackendPool as parallel async
                    % parfeval futures and writes operational hints
                    % to the inline CuttingStatusLabel via
                    % refreshStatus. The full-screen nav overlay is
                    % gone — the user sees the mode tabs, the toolbar,
                    % and the empty Cut Plan / Backend Assignments
                    % cards immediately, and each card populates as
                    % its respective fetch lands.
                    if ~isempty(app.CircuitCuttingVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.CircuitCuttingVm, ttl)
                        app.CircuitCuttingVm.onEnter();
                    end
                case 'Settings'
                    if ~isempty(app.SettingsVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.SettingsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Settings');
                        app.SettingsVm.onEnter();
                        asyncStarted = true;
                    end
                case 'Reports'
                    %  Populate the GeneratedReportList with the user's
                    %  existing reports (newest first) so Open / PDF /
                    %  Email work even on a fresh tab visit. The VM's
                    %  loadReportsList runs async via AsyncRunner; if
                    %  it fails it logs a warn and leaves the list
                    %  empty (Generate still works either way).
                    %
                    %  The isScreenFresh gate matches every other case
                    %  in this switch — without it, Reports re-issued
                    %  GET /api/reports on every tab visit (200–800 ms
                    %  cross-continent RTT each time, even after the
                    %  user just navigated away and back). The VM now
                    %  declares LastRefresh; onPageLoaded stamps it on
                    %  success.
                    if ~isempty(app.ReportsVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.ReportsVm, ttl)
                        NavigationManager.showNavLoading(app, 'Reports');
                        app.ReportsVm.loadReportsList();
                        asyncStarted = true;
                    end
                case 'QEC Simulation'
                    %  Phase 1+2: populate Circuit + Backend dropdowns
                    %  on first nav so the operator can pick a target
                    %  hardware/circuit pair and see calibration-driven
                    %  results instead of generic parametric output.
                    if ~isempty(app.QecSimulationVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.QecSimulationVm, ttl)
                        NavigationManager.showNavLoading(app, 'QEC Simulation');
                        app.QecSimulationVm.onEnter();
                        asyncStarted = true;
                    end
                case 'QEC Visualization'
                    if ~isempty(app.QecVisualizationVm) && app.State.isAuthenticated() ...
                            && ~NavigationManager.isScreenFresh(app.QecVisualizationVm, ttl)
                        NavigationManager.showNavLoading(app, 'QEC Visualization');
                        app.QecVisualizationVm.onEnter();
                        asyncStarted = true;
                    end
            end

            % No async work fired -> drop any leftover build-time overlay
            % that ensureScreenBuilt left up.  Covers (a) screens with no
            % autoLoad case (QEC Simulation / QEC Visualization) and
            % (b) fresh-cache subsequent visits.  When asyncStarted is
            % true the VM's own done/error callback will hide.
            if ~asyncStarted
                try; app.hideLoading(); catch; end
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
                case 'Composer'
                    if isempty(app.ComposerVm); app.ComposerVm = ComposerViewModel(app); end
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
                case 'Mitigation Compare'
                    if isempty(app.MitigationCompareVm); app.MitigationCompareVm = MitigationCompareViewModel(app); end
                case 'Resource Estimator'
                    if isempty(app.ResourceEstimatorVm); app.ResourceEstimatorVm = ResourceEstimatorViewModel(app); end
                case 'Run Planner'
                    if isempty(app.RunPlannerVm); app.RunPlannerVm = RunPlannerViewModel(app); end
                case 'Jobs'
                    if isempty(app.JobsVm); app.JobsVm = JobsViewModel(app); end
                case 'Results'
                    if isempty(app.ResultsVm); app.ResultsVm = ResultsViewModel(app); end
                case 'Detailed Analysis'
                    if isempty(app.DetailedAnalysisVm); app.DetailedAnalysisVm = DetailedAnalysisViewModel(app); end
                case 'Benchmark Dashboard'
                    if isempty(app.BenchmarkDashboardVm); app.BenchmarkDashboardVm = BenchmarkDashboardViewModel(app); end
                case 'Circuit Cutting'
                    if isempty(app.CircuitCuttingVm); app.CircuitCuttingVm = CircuitCuttingViewModel(app); end
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

        function ttl = ttlForScreen(key)
            % ttlForScreen  Per-screen cache TTL override with fallback
            %   to the global screen_cache_ttl. Lets config-style screens
            %   (Backends, Mitigation Compare, Resource Estimator, Run
            %   Planner — data that changes rarely inside a session) be
            %   marked long-cache while keeping the Dashboard's
            %   auto-refresh-friendly default of 30 seconds.
            %
            %   Property key shape: screen_cache_ttl_<lowercased_key>
            %   with spaces → underscores. Example: 'Mitigation Compare'
            %   → screen_cache_ttl_mitigation_compare. Missing entry
            %   falls through to the global default.
            defaultTtl = AppConfig.getDouble('screen_cache_ttl', 30);
            safeKey    = lower(strrep(char(key), ' ', '_'));
            perKey     = ['screen_cache_ttl_' safeKey];
            ttl        = AppConfig.getDouble(perKey, defaultTtl);
        end

        function cancelInFlightFor(app, key)
            % cancelInFlightFor  Map a routing key to the corresponding
            %   VM and ask it to cancel any in-flight AsyncRunner
            %   future. Called from onSelectSection right after the
            %   outgoing panel is hidden so a mid-fetch nav-away frees
            %   the worker + polling timer instead of letting the ghost
            %   fetch run to completion (and possibly land on a stale
            %   generation that a defensive isvalid() check has to
            %   discard).
            %
            %   Only the four lookup-driven screens that have
            %   implemented cancelInFlight (Backends, Mitigation
            %   Compare, Resource Estimator, Run Planner) are covered.
            %   Other screens' AsyncRunner calls stay un-cancellable
            %   for now — Phase A targeted scope.
            if isempty(key); return; end
            try
                switch char(key)
                    case 'Backends'
                        if ~isempty(app.BackendsVm)
                            app.BackendsVm.cancelInFlight();
                        end
                    case 'Mitigation Compare'
                        if ~isempty(app.MitigationCompareVm)
                            app.MitigationCompareVm.cancelInFlight();
                        end
                    case 'Resource Estimator'
                        if ~isempty(app.ResourceEstimatorVm)
                            app.ResourceEstimatorVm.cancelInFlight();
                        end
                    case 'Run Planner'
                        if ~isempty(app.RunPlannerVm)
                            app.RunPlannerVm.cancelInFlight();
                        end
                end
            catch ME
                Logger.debug('NavigationManager', ...
                    'cancelInFlightFor(%s): %s', char(key), ME.message);
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
            %
            % Hidden routing keys (Detailed Analysis / Benchmark
            % Dashboard / Upload / Composer) don't appear in the
            % sidebar HTML, so passing them straight through would
            % leave nothing highlighted — disorienting for the user.
            % parentNavKey maps each hidden key to the visible parent
            % section it logically belongs to so the sidebar shows
            % which workflow the user is in.
            if isempty(app.NavHtml) || ~isvalid(app.NavHtml); return; end
            highlightKey = NavigationManager.parentNavKey(activeKey);
            app.NavHtml.Data = struct('a', 'setActive', 'name', highlightKey);
        end

        function key = parentNavKey(key)
            % Map a routing key to the sidebar item that should be
            % highlighted while it's the active screen. Visible
            % sidebar keys pass through unchanged; hidden child
            % screens resolve to their parent workflow:
            %   Detailed Analysis    -> Analysis
            %   Benchmark Dashboard  -> Benchmark
            %   Upload / Composer    -> Circuits   (both extend the
            %                                       Circuits workflow:
            %                                       Composer authors a
            %                                       circuit, Upload
            %                                       imports one)
            switch char(key)
                case 'Detailed Analysis'
                    key = 'Analysis';
                case 'Benchmark Dashboard'
                    key = 'Benchmark';
                case {'Upload', 'Composer'}
                    key = 'Circuits';
            end
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
                if strcmp(clickedName, '__toggleAdvanced__')
                    % Progressive-disclosure toggle — flip state and re-render
                    % the sidebar in place; never routed to a screen.
                    app.ShowAdvanced = ~app.ShowAdvanced;
                    activeKey = 'Dashboard';
                    if ~isempty(app.NavList) && isvalid(app.NavList)
                        activeKey = char(app.NavList.Value);
                    end
                    NavigationManager.renderNavHtml(app, activeKey, app.NavCollapsed);
                    return;
                end
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
                '.label{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}' ...
                '.btn.toggle{opacity:0.8;font-weight:600;font-size:13px;margin-top:6px;}'];

            if collapsed
                css = [css '.btn{justify-content:center;padding:6px 0;height:32px;}' ...
                           '.label{display:none;}'];
            else
                css = [css '.btn{padding:6px 12px;height:32px;gap:10px;}'];
            end

            q = char(39);  % single-quote for JS strings
            items = '';
            for i = 1:numel(names)
                % Progressive disclosure: skip advanced screens unless the
                % user enabled "Show advanced". The active screen is always
                % kept visible so its highlight never disappears.
                if NavigationManager.isAdvancedScreen(names{i}) ...
                        && ~app.ShowAdvanced && ~strcmp(names{i}, activeKey)
                    continue;
                end
                cls = 'btn';
                if strcmp(names{i}, activeKey); cls = 'btn active'; end
                btn = ['<button class="' cls '" data-name="' names{i} '" onclick="sendClick(' q names{i} q ')">' ...
                       '<span class="icon">' icons{i} '</span>' ...
                       '<span class="label">' labels{i} '</span></button>'];
                items = [items btn]; %#ok<AGROW>
            end
            % Show/Hide advanced toggle — a distinct nav row that flips
            % app.ShowAdvanced (handled by onNavHtmlClick, not routed).
            if app.ShowAdvanced
                togLabel = Labels.get('nav_hide_advanced');
                togIcon  = char(9652);   % ▴
            else
                togLabel = Labels.get('nav_show_advanced');
                togIcon  = char(9662);   % ▾
            end
            togName = '__toggleAdvanced__';
            items = [items '<button class="btn toggle" data-name="' togName ...
                     '" onclick="sendClick(' q togName q ')">' ...
                     '<span class="icon">' togIcon '</span>' ...
                     '<span class="label">' togLabel '</span></button>'];

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
            % Routing keys — these MUST match the case labels in
            % screenBuilderFor / ensureVm / autoLoadScreen / etc. The
            % displayed labels (navLabels) are decoupled, so we can
            % display "Projects" while keeping the routing key 'Welcome'
            % (Phase 8 rename: cosmetic only — file/class names stay as
            % WelcomeScreen / WelcomeViewModel for back-compat with any
            % out-of-tree caller).
            %
            % Phase 8 reorder: Dashboard moved to position 1 (first
            % sidebar entry) — operators land on it after login by
            % default; Projects (formerly Welcome) sits at position 2.
            % Upload is hidden from the sidebar — the Composer + Circuits
            % toolbars host the upload entry-points instead. UploadScreen /
            % UploadViewModel / app.UploadVm stay so any cross-screen call
            % (`app.onSelectSection('Upload')`) still routes correctly.
            %
            % Prediction is hidden too — it has been consolidated into Run
            % Planner (which already computes per-backend fidelity as its
            % first step). PredictionScreen / PredictionViewModel / the
            % 'Prediction' routing key stay wired so any cross-screen call
            % (`app.onSelectSection('Prediction')`) still routes correctly.
            n = {'Dashboard','Welcome','Circuits','Analysis', ...
                 'Circuit Cutting','Backends', ...
                 'Benchmark','Mitigation Compare','Resource Estimator','Run Planner', ...
                 'Jobs','Results', ...
                 'QEC Simulation','QEC Visualization','Reports','Settings'};
        end

        function ic = navIcons()
            % Icon characters — kept semantic (house, grid, pencil, etc.).
            % Sizing is handled by the CSS .icon container, not the glyph.
            % Phase 8 reorder mirrors navNames (Dashboard before Welcome).
            ic = { ...
                char(9707),  ... ◫ Dashboard
                char(8962),  ... ⌂ Projects (was Welcome)
                char(9776),  ... ☰ Circuits
                char(8981),  ... ⌕ Analysis
                char(9986),  ... ✂ Circuit Cutting
                char(9004),  ... ⌬ Backends
                char(9678),  ... ◎ Benchmark
                char(9878),  ... ⚖ Mitigation Compare
                char(9580),  ... ╌ Resource Estimator
                char(9881),  ... ⚙ Run Planner
                char(9635),  ... ▣ Jobs
                char(9633),  ... □ Results
                char(9673),  ... ◉ QEC Simulation
                char(9672),  ... ◈ QEC Visualization
                char(9636),  ... ▤ Reports
                char(9881)}; % ⚙ Settings
        end

        function lb = navLabels()
            % Text labels (no icon prefix — icon is rendered separately).
            % Phase 8 changes:
            %   1. Dashboard is now position 1 (was position 2).
            %   2. Position 2 displays "Projects" — the screen formerly
            %      named "Welcome". Routing keys (navNames) stay 'Welcome'
            %      so the underlying WelcomeScreen.m / WelcomeViewModel.m
            %      classes don't need to be renamed.
            lb = {'Dashboard','Projects','Circuits','Analysis', ...
                  'Circuit Cutting','Backends', ...
                  'Benchmark','Mitigation Compare','Resource Estimator','Run Planner', ...
                  'Jobs','Results', ...
                  'QEC Simulation','QEC Visualization','Reports','Settings'};
        end

        function lbl = displayLabelFor(key)
            % Phase 8 helper: resolve a routing-key (from navNames) to
            % its display label (navLabels). Used by onSelectSection
            % so the screen-header title reflects the user-facing name
            % (e.g. "Projects") instead of the underlying routing key
            % (e.g. "Welcome"). Falls back to the key itself when no
            % match is found — preserves behaviour for any out-of-list
            % routing keys.
            names  = NavigationManager.navNames();
            labels = NavigationManager.navLabels();
            idx = find(strcmp(names, char(key)), 1);
            if ~isempty(idx) && idx <= numel(labels)
                lbl = char(labels{idx});
            else
                lbl = char(key);
            end
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
                'Welcome',          'subtitle_welcome', ...
                'Dashboard',        'subtitle_dashboard', ...
                'Circuits',         'subtitle_circuits', ...
                'Composer',         'subtitle_composer', ...
                'Notes',            'subtitle_notes', ...
                'Upload',           'subtitle_upload', ...
                'Analysis',         'subtitle_analysis', ...
                'Backends',         'subtitle_backends', ...
                'Benchmark',        'subtitle_benchmark', ...
                'Prediction',       'subtitle_prediction', ...
                'MitigationCompare','subtitle_mitigation_compare', ...
                'ResourceEstimator','subtitle_resource_estimator', ...
                'RunPlanner',       'subtitle_run_planner', ...
                'Jobs',             'subtitle_jobs', ...
                'Results',          'subtitle_results', ...
                'DetailedAnalysis', 'subtitle_detailed_analysis', ...
                'QECSimulation',    'subtitle_qec_simulation', ...
                'QECVisualization', 'subtitle_qec_visualization', ...
                'Reports',          'subtitle_reports', ...
                'Settings',         'subtitle_settings', ...
                'CircuitCutting',   'subtitle_circuit_cutting');
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
            % Kept for back-compat — now resizes only the currently-
            % active panel via onResizeUI. The pre-perf-pass loop
            % iterated every entry in app.SectionPanels, paying a
            % uipanel.Position-triggered layout recompute per panel
            % on every nav and every window resize. Inactive panels
            % are re-fitted on demand the next time onSelectSection
            % flips their Visible='on'.
            NavigationManager.onResizeUI(app);
        end

        function onResizeUI(app)
            % Resize only the currently-visible section panel + the
            % auth overlay. Replaces the pre-perf-pass behavior that
            % looped every panel via fitAllSections (~22 layout passes
            % per resize / per nav).
            try
                if isprop(app, 'LastSectionKey')
                    key = char(app.LastSectionKey);
                    if ~isempty(key)
                        safeKey = matlab.lang.makeValidName(key);
                        if isfield(app.SectionPanels, safeKey)
                            NavigationManager.fitSectionPanel(app.SectionPanels.(safeKey));
                        end
                    end
                end
            catch ME; Logger.debug('NavigationManager', 'onResizeUI: %s', ME.message); end
            OverlayManager.fitAuthOverlay(app);
        end

        function forceInitialLayout(app)
            % Dropped the pre-perf-pass pause(0.05) / pause(0.02)
            % taxes — they were anti-flicker measures from an earlier
            % MATLAB release. On R2025b a single drawnow() flush is
            % sufficient, and the prior double-fitAllSections call
            % is redundant now that onResizeUI fits the active panel.
            try
                drawnow();
                NavigationManager.onResizeUI(app);
                drawnow();
            catch ME; Logger.debug('NavigationManager', 'forceInitialLayout: %s', ME.message); end
        end

        % ── Offline-capability classification ───────────────────────────

        function tf = isOfflineCapable(key)
            % Screens whose core surface is fully local (no FastAPIClient)
            % and therefore usable without a backend login.
            tf = any(strcmp(char(key), {'Composer'}));
        end

        function tf = isAdvancedScreen(key)
            % Progressive disclosure: specialist surfaces that are hidden
            % from the sidebar until the user opts into "Show advanced".
            % They are NOT removed — routing keys stay live, so cross-screen
            % links and the toggle still reach them. Keeps the default
            % sidebar focused on the core build -> simulate -> analyse -> run
            % workflow (client feedback: streamline the wide feature set).
            tf = any(strcmp(char(key), { ...
                'Circuit Cutting', 'Mitigation Compare', 'Resource Estimator', ...
                'QEC Simulation', 'QEC Visualization'}));
        end

        function refreshAuthOverlay(app, key)
            % Show the auth overlay only when logged out AND the active
            % screen needs the backend. Offline-capable screens render
            % with no overlay.
            if app.State.isAuthenticated() || NavigationManager.isOfflineCapable(key)
                OverlayManager.hideAuthOverlay(app);
            else
                OverlayManager.showAuthOverlay(app);
            end
            OverlayManager.fitAuthOverlay(app);
        end

    end
end
