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
            try
                % ── Step 1: Save benchmark config ────────────────────────
                app.logEvent('API', sprintf('POST /api/projects/%s/benchmark-config', pid));
                configResp = app.ProjectSvc.saveBenchmarkConfig( ...
                    pid, circuitId, backendName, shots, opt, mitig, strategy, token);

                % ── Display execution plan from config response ──────────
                obj.displayExecutionPlan(configResp, shots, opt, mitig, strategy);
                app.logEvent('API', 'Benchmark config saved — execution plan displayed');

                % ── Step 2: Compare transpilation strategies ─────────────
                strategies = obj.buildStrategiesList(strategy);
                app.logEvent('API', sprintf('POST /api/projects/%s/benchmark-config/compare-strategies', pid));
                try
                    compData = app.ProjectSvc.compareStrategies( ...
                        pid, circuitId, backendName, strategies, token);
                    rows = JsonHelper.benchmarkStrategyToRows(compData);
                    if ~isempty(rows)
                        app.BenchmarkStrategyTable.Data = rows;
                        app.logEvent('API', sprintf('Strategy comparison complete — %d rows', size(rows, 1)));
                    else
                        % API returned but with empty strategies — use estimates
                        app.BenchmarkStrategyTable.Data = obj.estimateStrategies(strategy, opt, shots);
                        app.logEvent('WARN', 'API returned empty strategies — using local estimates');
                    end
                catch ME2
                    % compare-strategies failed (e.g. Qiskit not installed — 503)
                    app.logEvent('WARN', sprintf('Strategy comparison API failed: %s — using local estimates', ME2.message));
                    app.BenchmarkStrategyTable.Data = obj.estimateStrategies(strategy, opt, shots);
                end

                app.State.logActivity('Run benchmark', 'Success');
                obj.LastRefresh = tic;
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Benchmark API FAILED: %s', ME.message));
                app.setStatus(app.BenchmarkStatusArea, { ...
                    'Benchmark failed (API error).', ME.message});
                app.showError('Run Benchmark', ME);
            end
        end

        % ── Auto-load on screen entry ────────────────────────────────────

        function onLoadBenchmark(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end

            % Step 1: Populate circuit dropdown
            obj.loadCircuits();

            % Step 2: Load saved benchmark config to get circuit_id BEFORE loading backends.
            %   GET /api/backends requires circuit_id to return the full backend list;
            %   without it the endpoint only returns project-registered backends (often empty).
            if app.State.hasProject()
                try
                    data = app.ProjectSvc.getBenchmarkConfig( ...
                        app.State.currentProjectId, app.State.authToken);
                    status = char(JsonHelper.pick(data, {'status'}));
                    if strcmp(status, 'configured')
                        % Restore circuit_id into AppState so loadBackends can use it
                        cid = char(JsonHelper.pick(data, {'circuit_id'}));
                        if ~isempty(cid) && strlength(cid) > 0
                            app.State.selectedCircuitId = string(cid);
                            obj.selectDropdownValue(app.BenchmarkCircuitDropdown, cid);
                        end
                    end
                catch ME
                    app.logEvent('DEBUG', sprintf('No existing benchmark config: %s', ME.message));
                    data = [];
                    status = '';
                end
            else
                data = [];
                status = '';
            end

            % Step 3: Load backends WITH circuit_id now available in AppState
            obj.loadBackends();

            % Step 4: Restore remaining config fields if a saved config was loaded
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
                    try app.BenchmarkMitigationDropdown.Value = em; catch; end
                end
                if ~isempty(ts)
                    try app.BenchmarkStrategyDropdown.Value = ts; catch; end
                end

                obj.displayExecutionPlan(data, s, o, em, ts);
                obj.LastRefresh = tic;
                app.logEvent('LOAD', 'Loaded existing benchmark config from server');
            end
        end
    end

    methods (Access = private)

        % ── Populate circuit dropdown ────────────────────────────────────

        function loadCircuits(obj)
            app = obj.App;
            try
                data = app.CircuitSvc.listCircuits(app.State.authToken);
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
            catch ME
                app.logEvent('DEBUG', sprintf('Failed to load circuits for benchmark: %s', ME.message));
            end
        end

        % ── Populate backend dropdown ────────────────────────────────────

        function loadBackends(obj)
            % loadBackends  Populate the backend dropdown.
            %   GET /api/backends?circuit_id=X returns the full enriched list.
            %   Without circuit_id it returns only project-registered backends (often empty).
            %   Mirrors the fallback logic from BackendsViewModel.fetchBackends().
            app = obj.App;
            data = struct('backends', {{}});

            % Attempt 1: enriched list with selected circuit
            cid = '';
            if app.State.hasCircuit()
                cid = char(app.State.selectedCircuitId);
            end
            if ~isempty(cid) && strlength(cid) > 0
                try
                    data = app.BackendSvc.listBackends(app.State.authToken, cid);
                    if obj.hasBackendData(data)
                        obj.populateBackendDropdown(data);
                        return;
                    end
                catch; end
            end

            % Attempt 2: use any circuit from the project as fallback
            try
                circList = app.CircuitSvc.listCircuits(app.State.authToken);
                items = JsonHelper.extractList(circList, 'circuits');
                if ~isempty(items)
                    fallbackCid = char(JsonHelper.pick(items(1), {'circuit_id','id'}));
                    if ~isempty(fallbackCid) && strlength(fallbackCid) > 0
                        data = app.BackendSvc.listBackends(app.State.authToken, fallbackCid);
                        if obj.hasBackendData(data)
                            obj.populateBackendDropdown(data);
                            return;
                        end
                    end
                end
            catch; end

            % Attempt 3: basic list without circuit_id (last resort)
            try
                data = app.BackendSvc.listBackends(app.State.authToken, '');
                if obj.hasBackendData(data)
                    obj.populateBackendDropdown(data);
                    return;
                end
            catch; end

            % All attempts failed
            app.BenchmarkBackendSelect.Items     = {'(no backends)'};
            app.BenchmarkBackendSelect.ItemsData = {''};
            app.BenchmarkBackendSelect.Value     = '';
            app.logEvent('WARN', 'No backends found for benchmark dropdown');
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
                rows{lev, 2} = depth;
                rows{lev, 3} = gates;
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
            catch
            end
        end
    end
end
