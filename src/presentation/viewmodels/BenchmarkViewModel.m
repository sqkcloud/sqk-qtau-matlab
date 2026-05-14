classdef BenchmarkViewModel < handle
    % BenchmarkViewModel  Callback handlers for the Benchmark screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = BenchmarkViewModel(app)
            obj.App = app;
        end

        % ── Circuit / Backend dropdown callbacks ─────────────────────────

        function onCircuitSelected(obj, circuitId)
            app = obj.App;
            circuitId = char(circuitId);
            if isempty(circuitId) || strlength(circuitId) == 0; return; end
            app.State.selectedCircuitId = string(circuitId);
            % Resolve display name from dropdown
            dd = app.BenchmarkCircuitDropdown;
            idx = find(strcmp(dd.ItemsData, circuitId), 1);
            if ~isempty(idx)
                app.State.selectedCircuitName = string(dd.Items{idx});
            end
            app.logEvent('UI', sprintf('Benchmark circuit selected: %s', circuitId));
            % Reload backends with circuit context for enriched fidelity data
            obj.loadBackends();
        end

        function onBackendSelected(obj, backendName)
            app = obj.App;
            backendName = char(backendName);
            if isempty(backendName) || strlength(backendName) == 0; return; end
            app.State.selectedBackend = string(backendName);
            app.logEvent('UI', sprintf('Benchmark backend selected: %s', backendName));
        end

        % ── Run benchmark ────────────────────────────────────────────────

        function onRunBenchmark(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Benchmark', 'Icon', 'warning'); return;
            end

            % Read form values
            shots    = round(app.BenchmarkShotsField.Value);
            opt      = round(app.BenchmarkOptField.Value);
            mitig    = char(app.BenchmarkMitigationDropdown.Value);
            strategy = char(app.BenchmarkStrategyDropdown.Value);

            % Read circuit and backend from dropdowns
            circuitId   = char(app.BenchmarkCircuitDropdown.Value);
            backendName = char(app.BenchmarkBackendSelect.Value);

            % Sync to AppState
            app.State.benchmarkShots      = shots;
            app.State.benchmarkOptLevel   = opt;
            app.State.benchmarkMitigation = string(mitig);
            app.State.benchmarkStrategy   = string(strategy);
            if strlength(circuitId) > 0
                app.State.selectedCircuitId = string(circuitId);
            end
            if strlength(backendName) > 0
                app.State.selectedBackend = string(backendName);
            end

            app.logEvent('CONFIG', sprintf('Benchmark config — shots: %d  opt: %d  mitigation: %s  strategy: %s', ...
                shots, opt, mitig, strategy));

            % Check prerequisites from dropdowns
            hasCircuit = strlength(circuitId) > 0;
            hasBackend = strlength(backendName) > 0;
            if ~app.State.hasProject() || ~hasCircuit || ~hasBackend
                missing = {};
                if ~app.State.hasProject(); missing{end+1} = 'project'; end
                if ~hasCircuit;             missing{end+1} = 'circuit'; end
                if ~hasBackend;             missing{end+1} = 'backend'; end
                app.logEvent('CONFIG', sprintf('Benchmark config saved to session only — missing: %s', strjoin(missing, ', ')));
                app.setStatus(app.BenchmarkStatusArea, { ...
                    sprintf('Shots: %d  Opt level: %d', shots, opt), ...
                    sprintf('Mitigation: %s', mitig), ...
                    sprintf('Strategy: %s', strategy), ...
                    sprintf('Config saved to session (select %s first).', strjoin(missing, ', '))});
                return;
            end

            pid   = app.State.currentProjectId;
            token = app.State.authToken;

            app.showLoading(Labels.get('loading_benchmark', 'Running benchmark...'));
            app.logEvent('API', sprintf('POST /api/projects/%s/benchmark-config', pid));
            ctx = struct('pid', pid, 'cid', circuitId, 'backend', backendName, ...
                'shots', shots, 'opt', opt, 'mitig', mitig, 'strategy', strategy);
            projSvc = app.ProjectSvc;
            AsyncRunner.run( ...
                @() projSvc.saveBenchmarkConfig(pid, circuitId, backendName, shots, opt, mitig, strategy, token), ...
                @(configResp) obj.onSaveBenchmarkConfigComplete(app, ctx, configResp), ...
                @(ME)         obj.onBenchmarkError(app, ME));
        end

        function onSaveBenchmarkConfigComplete(obj, app, ctx, configResp)
            obj.displayExecutionPlan(configResp, ctx.shots, ctx.opt, ctx.mitig, ctx.strategy);
            app.logEvent('API', 'Benchmark config saved — execution plan displayed');
            % Step 2 — chained async: compare transpilation strategies
            strategies = obj.buildStrategiesList(ctx.strategy);
            app.logEvent('API', sprintf('POST /api/projects/%s/benchmark-config/compare-strategies', ctx.pid));
            projSvc = app.ProjectSvc;
            token   = app.State.authToken;
            AsyncRunner.run( ...
                @() projSvc.compareStrategies(ctx.pid, ctx.cid, ctx.backend, strategies, token), ...
                @(compData) obj.onCompareStrategiesComplete(app, ctx, compData), ...
                @(ME)       obj.onCompareStrategiesFallback(app, ctx, ME));
        end

        function onCompareStrategiesComplete(obj, app, ctx, compData)
            rows = JsonHelper.benchmarkStrategyToRows(compData);
            if ~isempty(rows)
                app.BenchmarkStrategyTable.Data = rows;
                app.logEvent('API', sprintf('Strategy comparison complete — %d rows', size(rows, 1)));
            else
                % API returned 200 but `strategies: []` — typically the
                % backend's Qiskit transpilation failed for every level/
                % routing pair. Render local estimates instead.
                app.BenchmarkStrategyTable.Data = obj.estimateStrategies(ctx.strategy, ctx.opt, ctx.shots);
                app.logEvent('WARN', ...
                    'API returned strategies=[] — using local estimates. Check backend logs for "Transpilation failed" warnings.');
            end
            obj.finishBenchmarkRun(app);
        end

        function onCompareStrategiesFallback(obj, app, ctx, ME)
            app.logEvent('WARN', sprintf( ...
                'Strategy comparison API failed: %s — using local estimates', ME.message));
            app.BenchmarkStrategyTable.Data = obj.estimateStrategies(ctx.strategy, ctx.opt, ctx.shots);
            obj.finishBenchmarkRun(app);
        end

        function onBenchmarkError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Benchmark API FAILED: %s', ME.message));
            app.setStatus(app.BenchmarkStatusArea, {'Benchmark failed (API error).', ME.message});
            app.showError('Run Benchmark', ME);
        end

        function finishBenchmarkRun(obj, app)
            app.State.logActivity('Run benchmark', 'Success');
            obj.LastRefresh = tic;
            app.hideLoading();
        end

        % ── Submit benchmark to IBM Quantum ──────────────────────────────
        %   onRunBenchmark above only persists the config and runs a LOCAL
        %   transpilation-strategy comparison. onSubmitBenchmarkToIbm
        %   actually dispatches the circuit to IBM hardware via
        %   POST /api/jobs/submit — the same endpoint the Prediction
        %   screen's "Submit to IBM" button uses, parametrised from the
        %   Benchmark form's shots / opt / mitigation values.

        function onSubmitBenchmarkToIbm(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Submit', 'Icon', 'warning'); return;
            end
            circuitId   = char(app.BenchmarkCircuitDropdown.Value);
            backendName = char(app.BenchmarkBackendSelect.Value);
            if strlength(circuitId) == 0
                uialert(app.UIFigure, Labels.get('error_no_circuit'), 'Submit', 'Icon', 'warning');
                return;
            end
            if strlength(backendName) == 0
                uialert(app.UIFigure, ...
                    Labels.get('error_no_backend', 'Select a backend first.'), ...
                    'Submit', 'Icon', 'warning');
                return;
            end
            % Surface known-bad server state early (prefetched at login).
            cfg = app.ServerIbmConfig;
            if isstruct(cfg) && isfield(cfg, 'channel') && strlength(string(cfg.channel)) > 0
                if isfield(cfg, 'runtime_broken') && logical(cfg.runtime_broken)
                    reason = '';
                    if isfield(cfg, 'runtime_broken_reason')
                        reason = char(string(cfg.runtime_broken_reason));
                    end
                    uialert(app.UIFigure, ...
                        sprintf('IBM runtime unavailable on server:\n%s', reason), ...
                        'Submit', 'Icon', 'warning');
                    return;
                end
                if isfield(cfg, 'has_token') && ~logical(cfg.has_token)
                    uialert(app.UIFigure, ...
                        Labels.get('error_no_server_token', ...
                            'Server is not configured with an IBM token.'), ...
                        'Submit', 'Icon', 'warning');
                    return;
                end
            end
            shots = round(app.BenchmarkShotsField.Value);
            opt   = round(app.BenchmarkOptField.Value);
            mitig = char(app.BenchmarkMitigationDropdown.Value);

            % Mirror AppState so downstream screens (Jobs, Results) see
            % the same context if the user navigates.
            app.State.selectedCircuitId   = string(circuitId);
            app.State.selectedBackend     = string(backendName);
            app.State.benchmarkShots      = shots;
            app.State.benchmarkOptLevel   = opt;
            app.State.benchmarkMitigation = string(mitig);

            payload = struct( ...
                'circuit_id',         circuitId, ...
                'backend_name',       backendName, ...
                'shots',              shots, ...
                'optimization_level', opt);
            if ~isempty(mitig) && ~strcmp(mitig, 'none')
                payload.error_mitigation = mitig;
            end
            % Phase 2.4: forward the operator's chosen QEM ladder level
            % so the server's MitigationService.resolve() honors it
            % through the SamplerV2 stack instead of silently applying
            % the Standard default. Without this, Settings → "Default
            % mitigation level" had no effect on standard job submits
            % even though the field exists on SubmitJobRequest.
            try
                lvl = double(app.State.preferredMitigationLevel);
                if isfinite(lvl)
                    payload.mitigation_level = int32(lvl);
                end
            catch
            end

            mitLogStr = mitig;
            if isfield(payload, 'mitigation_level')
                mitLogStr = sprintf('%s (level=%d)', mitig, payload.mitigation_level);
            end
            app.logEvent('API', sprintf('POST /api/jobs/submit — circuit: %s  backend: %s  shots: %d  opt: %d  mitig: %s', ...
                circuitId, backendName, shots, opt, mitLogStr));
            app.showLoading(Labels.get('loading_submitting_bench', ...
                'Submitting benchmark to IBM Quantum...'));
            jobSvc = app.JobSvc;
            token  = app.State.authToken;
            AsyncRunner.run( ...
                @() jobSvc.submitJob(payload, token), ...
                @(data) obj.onSubmitBenchmarkComplete(app, circuitId, backendName, data), ...
                @(ME)   obj.onSubmitBenchmarkError(app, circuitId, backendName, ME));
        end

        function onSubmitBenchmarkComplete(~, app, cid, backendName, data)
            app.hideLoading();
            recordId = char(JsonHelper.pick(data, {'job_record_id','id'}));
            ibmJobId = char(JsonHelper.pick(data, {'ibm_job_id'}));
            status   = char(JsonHelper.pick(data, {'status'}));
            if ~isempty(recordId)
                app.State.selectedJobId = string(recordId);
            end
            app.logEvent('API', sprintf('Benchmark submitted — record: %s  ibm_job_id: %s  status: %s', ...
                recordId, ibmJobId, status));
            app.State.logActivity(sprintf('Benchmark submit — %s → %s', cid, backendName), 'Success');
            app.onSelectSection('Jobs');
            uialert(app.UIFigure, ...
                sprintf(Labels.get('benchmark_submit_success', ...
                    'Benchmark submitted to %s — IBM job id: %s'), backendName, ibmJobId), ...
                'Benchmark Submitted', 'Icon', 'success');
        end

        function onSubmitBenchmarkError(~, app, cid, backendName, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Benchmark submit FAILED (circuit: %s  backend: %s): %s', ...
                cid, backendName, ME.message));
            % On 503, the real reason is almost always "server marked its
            % IBM runtime broken after login". Refetch /settings/ibm-config
            % and surface the actual cause instead of a generic error.
            if contains(ME.message, '503') || contains(ME.message, 'Service Unavailable')
                settSvc = app.SettingsSvc;
                tok     = app.State.authToken;
                AsyncRunner.run( ...
                    @() settSvc.getIbmConfig(tok), ...
                    @(cfg) BenchmarkViewModel.explain503(app, cfg, cid, backendName), ...
                    @(~)   app.showError('Submit Benchmark to IBM', ME));
                return;
            end
            app.showError('Submit Benchmark to IBM', ME);
        end

        % ── Auto-load on screen entry ────────────────────────────────────

        function onLoadBenchmark(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            app.showLoading(Labels.get('loading_benchmark_entry', 'Loading benchmark data...'));

            % Capture parameters on UI thread
            token  = app.State.authToken;
            pid    = '';
            if app.State.hasProject(); pid = char(app.State.currentProjectId); end
            selCid = char(app.State.selectedCircuitId);
            circSvc   = app.CircuitSvc;
            projSvc   = app.ProjectSvc;
            backSvc   = app.BackendSvc;

            % Two-stage parallel fetch (was 3 serial calls inside one
            % worker — ~3-5 s on initial Benchmark nav).
            %
            % Stage 1 (runMany, runs in parallel on backgroundPool):
            %   - listCircuits(token)
            %   - getBenchmarkConfig(pid, token)  (skipped if no project)
            % Stage 2 (AsyncRunner.run, after stage 1):
            %   - listBackends with resolved circuit id + fallback chain
            %     (needs circuits list to resolve the fallback cid AND
            %     needs benchConfig to detect a configured-circuit
            %     override — so cannot start until stage 1 is complete).
            %
            % Saves one HTTP round-trip (stage 1 is max(circuits, config)
            % instead of sum). Full 3-way parallelism would require
            % optimistic backends-with-selCid dispatch + re-fetch on
            % override — deferred to a follow-up.
            if isempty(pid)
                AsyncRunner.runMany( ...
                    { @() BenchmarkViewModel.safeFetch( ...
                          @() circSvc.listCircuits(token)) }, ...
                    @(s1) obj.onCircuitsAndConfigReady(app, backSvc, ...
                          token, selCid, s1{1}, [], ''), ...
                    @(ME) obj.onLoadBenchmarkError(app, ME));
            else
                AsyncRunner.runMany( ...
                    { @() BenchmarkViewModel.safeFetch( ...
                          @() circSvc.listCircuits(token)), ...
                      @() BenchmarkViewModel.safeFetch( ...
                          @() projSvc.getBenchmarkConfig(pid, token)) }, ...
                    @(s1) obj.onCircuitsAndConfigReady(app, backSvc, ...
                          token, selCid, s1{1}, s1{2}, ...
                          char(JsonHelper.pick(s1{2}, {'status'}))), ...
                    @(ME) obj.onLoadBenchmarkError(app, ME));
            end
        end

        function onCircuitsAndConfigReady(obj, app, backSvc, token, ...
                selCid, circuits, benchConfig, benchStatus)
            % Stage-1 completion: a saved 'configured' benchConfig may
            % override the UI-tracked selCid. Resolve the effective
            % circuit id, then kick the stage-2 backends fetch.
            if strcmp(benchStatus, 'configured') && ~isempty(benchConfig)
                cfgCid = char(JsonHelper.pick(benchConfig, {'circuit_id'}));
                if ~isempty(cfgCid) && strlength(cfgCid) > 0
                    selCid = cfgCid;
                end
            end
            AsyncRunner.run( ...
                @() BenchmarkViewModel.fetchBackendsWithFallback( ...
                    backSvc, token, selCid, circuits), ...
                @(backends) obj.applyEntryData(app, struct( ...
                    'circuits',    circuits, ...
                    'benchConfig', benchConfig, ...
                    'benchStatus', benchStatus, ...
                    'backends',    backends)), ...
                @(ME) obj.onLoadBenchmarkError(app, ME));
        end
    end

    methods (Access = private)

        % ── Entry data callback (runs on main thread) ───────────────────

        function applyEntryData(obj, app, R)
            % Apply circuits to dropdown
            try
                obj.applyCircuitDropdown(R.circuits);
            catch ME
                app.logEvent('DEBUG', sprintf('applyCircuitDropdown: %s', ME.message));
            end

            % Restore benchmark config & circuit selection
            data   = R.benchConfig;
            status = R.benchStatus;
            if ~isempty(data) && strcmp(status, 'configured')
                cid = char(JsonHelper.pick(data, {'circuit_id'}));
                if ~isempty(cid) && strlength(cid) > 0
                    app.State.selectedCircuitId = string(cid);
                    obj.selectDropdownValue(app.BenchmarkCircuitDropdown, cid);
                end
            end

            % Apply backends to dropdown
            try
                obj.populateBackendDropdown(R.backends);
            catch ME
                app.logEvent('DEBUG', sprintf('populateBackendDropdown: %s', ME.message));
                app.BenchmarkBackendSelect.Items     = {'(no backends)'};
                app.BenchmarkBackendSelect.ItemsData = {''};
                app.BenchmarkBackendSelect.Value     = '';
            end

            % Restore remaining config fields
            if ~isempty(data) && strcmp(status, 'configured')
                bn = char(JsonHelper.pick(data, {'backend_name'}));
                if ~isempty(bn) && strlength(bn) > 0
                    app.State.selectedBackend = string(bn);
                    obj.selectDropdownValue(app.BenchmarkBackendSelect, bn);
                end
                s = JsonHelper.toDouble(JsonHelper.pick(data, {'shots'}));
                o = JsonHelper.toDouble(JsonHelper.pick(data, {'optimization_level'}));
                if s > 0; app.BenchmarkShotsField.Value = s; end
                if o >= 0; app.BenchmarkOptField.Value = o; end
                em = char(JsonHelper.pick(data, {'error_mitigation'}));
                ts = char(JsonHelper.pick(data, {'transpilation_strategy'}));
                if ~isempty(em)
                    try app.BenchmarkMitigationDropdown.Value = em; catch ME; Logger.debug('BenchmarkViewModel', 'restoreMitigationDropdown: %s', ME.message); end
                end
                if ~isempty(ts)
                    try app.BenchmarkStrategyDropdown.Value = ts; catch ME; Logger.debug('BenchmarkViewModel', 'restoreStrategyDropdown: %s', ME.message); end
                end
                obj.displayExecutionPlan(data, s, o, em, ts);
                app.logEvent('LOAD', 'Loaded existing benchmark config from server');
            end

            % Oversize-circuit detection — once both circuits and backends
            % are loaded, warn the user if the selected circuit is too wide
            % for any single backend (pointing them at Circuit Cutting).
            try
                selCid = char(app.State.selectedCircuitId);
                if ~isempty(selCid)
                    circuits = JsonHelper.extractList(R.circuits, 'circuits');
                    for i = 1:numel(circuits)
                        c = circuits(i);
                        if iscell(circuits); c = circuits{i}; end
                        if strcmp(char(JsonHelper.pick(c, {'circuit_id','id'})), selCid)
                            OversizeDetector.check(app, c, R.backends);
                            break;
                        end
                    end
                end
            catch ME
                Logger.debug('BenchmarkViewModel', ...
                    'OversizeDetector: %s', ME.message);
            end

            obj.LastRefresh = tic;
            app.hideLoading();
        end

        function onLoadBenchmarkError(~, app, ME)
            app.hideLoading();
            app.logEvent('WARN', sprintf('Benchmark entry load failed: %s', ME.message));
        end

        function applyCircuitDropdown(obj, data)
            app = obj.App;
            items = JsonHelper.extractList(data, 'circuits');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0
                app.BenchmarkCircuitDropdown.Items     = {'(no circuits)'};
                app.BenchmarkCircuitDropdown.ItemsData = {''};
                app.BenchmarkCircuitDropdown.Value     = '';
                return;
            end
            names = cell(1, n);
            ids   = cell(1, n);
            for i = 1:n
                ids{i}   = char(JsonHelper.pick(items(i), {'circuit_id','id'}));
                names{i} = char(JsonHelper.pick(items(i), {'name','circuit_name','filename'}));
                if isempty(names{i}) || strlength(names{i}) == 0
                    names{i} = ids{i};
                end
            end
            app.BenchmarkCircuitDropdown.Items     = names;
            app.BenchmarkCircuitDropdown.ItemsData = ids;
            if app.State.hasCircuit()
                obj.selectDropdownValue(app.BenchmarkCircuitDropdown, char(app.State.selectedCircuitId));
            end
            app.logEvent('LOAD', sprintf('Loaded %d circuits into benchmark dropdown', n));
        end

        % ── Populate circuit dropdown (legacy, kept for onCircuitSelected) ─

        function loadCircuits(obj)
            app = obj.App;
            % Async — listing the project's circuits hits the API and
            % was previously freezing the Benchmark tab on entry. The
            % populate-dropdown work runs on the main thread inside the
            % onLoadCircuitsComplete callback.
            circuitSvc = app.CircuitSvc;
            token      = app.State.authToken;
            AsyncRunner.run( ...
                @() circuitSvc.listCircuits(token), ...
                @(data) obj.onLoadCircuitsComplete(app, data), ...
                @(ME)   app.logEvent('DEBUG', sprintf('Failed to load circuits for benchmark: %s', ME.message)));
        end

        function onLoadCircuitsComplete(obj, app, data)
            items = JsonHelper.extractList(data, 'circuits');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0
                app.BenchmarkCircuitDropdown.Items     = {'(no circuits)'};
                app.BenchmarkCircuitDropdown.ItemsData = {''};
                app.BenchmarkCircuitDropdown.Value     = '';
                return;
            end
            names = cell(1, n);
            ids   = cell(1, n);
            for i = 1:n
                ids{i}   = char(JsonHelper.pick(items(i), {'circuit_id','id'}));
                names{i} = char(JsonHelper.pick(items(i), {'name','circuit_name','filename'}));
                if isempty(names{i}) || strlength(names{i}) == 0
                    names{i} = ids{i};
                end
            end
            app.BenchmarkCircuitDropdown.Items     = names;
            app.BenchmarkCircuitDropdown.ItemsData = ids;
            % Pre-select if AppState already has a circuit
            if app.State.hasCircuit()
                obj.selectDropdownValue(app.BenchmarkCircuitDropdown, char(app.State.selectedCircuitId));
            end
            app.logEvent('LOAD', sprintf('Loaded %d circuits into benchmark dropdown', n));
        end

        % ── Populate backend dropdown ────────────────────────────────────

        function loadBackends(obj)
            % loadBackends  Populate the backend dropdown.
            %   The 3-tier resolution (enriched-with-cid → fallback-cid →
            %   bare list) lives in BackendsViewModel.fetchBackends and
            %   is shared with DashboardViewModel.paintBackendHealth.
            %   Async dispatch — the entire chain runs on backgroundPool
            %   so the Benchmark tab stays responsive on entry.
            app = obj.App;
            cid = '';
            if app.State.hasCircuit()
                cid = char(app.State.selectedCircuitId);
            end
            backendSvc = app.BackendSvc;
            circuitSvc = app.CircuitSvc;
            token      = app.State.authToken;
            AsyncRunner.run( ...
                @() BackendsViewModel.fetchBackends(backendSvc, circuitSvc, token, cid), ...
                @(data) obj.onLoadBackendsComplete(app, data), ...
                @(ME)   obj.onLoadBackendsError(app, ME));
        end

        function onLoadBackendsComplete(obj, app, data)
            if obj.hasBackendData(data)
                obj.populateBackendDropdown(data);
                return;
            end
            % All resolution tiers came back empty.
            app.BenchmarkBackendSelect.Items     = {'(no backends)'};
            app.BenchmarkBackendSelect.ItemsData = {''};
            app.BenchmarkBackendSelect.Value     = '';
            app.logEvent('WARN', 'No backends found for benchmark dropdown');
        end

        function onLoadBackendsError(~, app, ME)
            Logger.debug('BenchmarkViewModel', 'loadBackends async chain failed: %s', ME.message);
            app.BenchmarkBackendSelect.Items     = {'(no backends)'};
            app.BenchmarkBackendSelect.ItemsData = {''};
            app.BenchmarkBackendSelect.Value     = '';
        end

        function tf = hasBackendData(~, data)
            tf = false;
            if isstruct(data) && isfield(data, 'backends')
                tf = ~isempty(data.backends);
            end
        end

        function populateBackendDropdown(obj, data)
            app = obj.App;
            items = JsonHelper.extractList(data, 'backends');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            names = cell(1, n);
            for i = 1:n
                names{i} = char(JsonHelper.pick(items(i), {'name','backend_name'}));
            end
            app.BenchmarkBackendSelect.Items     = names;
            app.BenchmarkBackendSelect.ItemsData = names;

            if strlength(app.State.selectedBackend) > 0
                obj.selectDropdownValue(app.BenchmarkBackendSelect, char(app.State.selectedBackend));
            end
            app.logEvent('LOAD', sprintf('Loaded %d backends into benchmark dropdown', n));
        end

        % ── Execution plan display ───────────────────────────────────────

        function displayExecutionPlan(obj, resp, shots, opt, mitig, strategy)
            app = obj.App;
            lines = {};

            lines{end+1} = sprintf('Shots: %d   Opt level: %d', shots, opt);
            lines{end+1} = sprintf('Mitigation: %s', mitig);
            lines{end+1} = sprintf('Strategy: %s', strategy);
            lines{end+1} = '';

            cost    = JsonHelper.pick(resp, {'cost_estimate_credits'});
            queue   = JsonHelper.pick(resp, {'estimated_queue_minutes'});
            runtime = JsonHelper.pick(resp, {'estimated_runtime_seconds'});

            costVal = JsonHelper.toDouble(cost);
            if costVal > 0
                lines{end+1} = sprintf('Est. cost: %.4f credits', costVal);
            end
            queueVal = JsonHelper.toDouble(queue);
            if queueVal > 0
                lines{end+1} = sprintf('Est. queue: %.1f min', queueVal);
            end
            rtVal = JsonHelper.toDouble(runtime);
            if rtVal > 0
                lines{end+1} = sprintf('Est. runtime: %.2f sec', rtVal);
            end

            recStrat = char(JsonHelper.pick(resp, {'recommended_strategy'}));
            layout   = char(JsonHelper.pick(resp, {'suggested_qubit_layout'}));
            if strlength(recStrat) > 0
                lines{end+1} = sprintf('Recommended: %s', recStrat);
            end
            if strlength(layout) > 0
                lines{end+1} = sprintf('Qubit layout: %s', layout);
            end

            statusStr = char(JsonHelper.pick(resp, {'status'}));
            if strcmp(statusStr, 'configured')
                lines{end+1} = '';
                lines{end+1} = 'Configuration saved.';
            end

            app.setStatus(app.BenchmarkStatusArea, lines);
        end

        % ── Local strategy estimation (fallback) ─────────────────────────

        function rows = estimateStrategies(~, routing, opt, shots)
            % estimateStrategies  Generate estimated strategy comparison data
            %   when the backend API is unavailable (e.g. Qiskit not installed).
            routing = char(routing);
            rows = cell(3, 5);

            % Base estimates: depth and 2Q gates decrease with higher opt level
            baseFidelity = max(0.3, 1.0 - (shots / 100000));
            for lev = 1:3
                name = sprintf('level%d_%s', lev, routing);
                % Higher opt level → lower depth and 2Q gates → better fidelity
                depthFactor = 1.0 - (lev - 1) * 0.15;
                depth  = round(100 * depthFactor);
                gates  = round(40 * depthFactor);
                fid    = min(0.99, baseFidelity + (lev - 1) * 0.08);
                comment = sprintf('opt_level=%d (estimated)', lev);

                rows{lev, 1} = name;
                % int32 so uitable renders '100' not '100.0000' — same
                % convention as the API path in
                % JsonHelper.benchmarkStrategyToRows.
                rows{lev, 2} = int32(depth);
                rows{lev, 3} = int32(gates);
                rows{lev, 4} = round(fid, 4);
                rows{lev, 5} = comment;
            end
        end

        % ── Strategy list builder ────────────────────────────────────────

        function strategies = buildStrategiesList(~, routing)
            routing = char(routing);
            if ismember(routing, {'sabre', 'stochastic', 'basic'})
                strategies = { ...
                    sprintf('level1_%s', routing), ...
                    sprintf('level2_%s', routing), ...
                    sprintf('level3_%s', routing)};
            else
                strategies = {'level1_sabre', 'level2_sabre', 'level3_sabre'};
            end
        end

        % ── Dropdown helper ──────────────────────────────────────────────

        function selectDropdownValue(~, dd, value)
            try
                if any(strcmp(dd.ItemsData, value))
                    dd.Value = value;
                end
            catch ME
                Logger.debug('BenchmarkViewModel', 'selectDropdownValue: %s', ME.message);
            end
        end
    end

    methods (Static, Access = private)

        function out = safeFetch(fn)
            % safeFetch  Run a 0-arg work function and silence any error
            %   so a single failing call cannot poison a parallel batch.
            %   Used for the circuits + benchConfig stage-1 fetches:
            %   either one failing should still let the other deliver
            %   its result and the screen render with whatever it has.
            try
                out = fn();
            catch ME
                Logger.debug('BenchmarkViewModel', 'safeFetch: %s', ME.message);
                out = [];
            end
        end

        function backends = fetchBackendsWithFallback(backSvc, token, selCid, circuits)
            % fetchBackendsWithFallback  Stage-2 backends fetch with the
            %   same 3-level fallback as the previous in-worker logic:
            %     1. Use selCid if it produces items.
            %     2. Else use the first circuit from the project list.
            %     3. Else basic list (selCid='').
            backends = struct('backends', {{}});
            if ~isempty(selCid) && strlength(selCid) > 0
                try
                    backends = backSvc.listBackends(token, selCid);
                    if BenchmarkViewModel.hasBackendItems(backends); return; end
                catch; end
            end
            try
                items = JsonHelper.extractList(circuits, 'circuits');
                if ~isempty(items)
                    fallCid = char(JsonHelper.pick(items(1), {'circuit_id','id'}));
                    if ~isempty(fallCid) && strlength(fallCid) > 0
                        backends = backSvc.listBackends(token, fallCid);
                        if BenchmarkViewModel.hasBackendItems(backends); return; end
                    end
                end
            catch; end
            try
                backends = backSvc.listBackends(token, '');
            catch; end
        end

        function tf = hasBackendItems(data)
            tf = false;
            if isstruct(data) && isfield(data, 'backends')
                tf = ~isempty(data.backends);
            end
        end

        function explain503(app, cfg, cid, backendName)
            % Post-failure diagnostic — called after a 503 from /jobs/submit
            % to surface the real server-side runtime state.
            broken   = logical(JsonHelper.safeField(cfg, 'runtime_broken', false));
            reason   = char(JsonHelper.safeField(cfg, 'runtime_broken_reason', ''));
            hasToken = logical(JsonHelper.safeField(cfg, 'has_token', false));
            backends = JsonHelper.safeField(cfg, 'backends', {});
            if ischar(backends); backends = {backends}; end
            if ~iscell(backends); backends = num2cell(string(backends)); end
            % Refresh session cache.
            app.ServerIbmConfig = struct( ...
                'channel',  string(JsonHelper.safeField(cfg, 'channel', '')), ...
                'instance', string(JsonHelper.safeField(cfg, 'instance', '')), ...
                'backends', {backends}, ...
                'has_token', hasToken, ...
                'runtime_broken', broken, ...
                'runtime_broken_reason', string(reason));
            if broken
                uialert(app.UIFigure, ...
                    sprintf(['IBM runtime is currently unavailable on the server.\n\n' ...
                            'Backend: %s\nReason: %s\n\nFix the IBM credentials in the ' ...
                            'server .env and restart the API, then try again.'], ...
                            backendName, reason), ...
                    'Submit Benchmark to IBM', 'Icon', 'error');
            elseif ~hasToken
                uialert(app.UIFigure, ...
                    'The server has no IBM_QUANTUM_TOKEN configured. Ask the operator to set it in .env and restart.', ...
                    'Submit Benchmark to IBM', 'Icon', 'error');
            else
                uialert(app.UIFigure, ...
                    sprintf('Server returned 503 for circuit %s / backend %s but reports IBM runtime as healthy. Try again in a moment.', cid, backendName), ...
                    'Submit Benchmark to IBM', 'Icon', 'warning');
            end
        end
    end
end
