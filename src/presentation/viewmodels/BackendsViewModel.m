classdef BackendsViewModel < handle
    % BackendsViewModel  Callback handlers for the Backends screen.

    properties
        LastRefresh = []
    end

    properties (Access = private)
        App
        FullTableData cell = {}   % unfiltered rows for search
        % Pool submission tracking (transient, one round of fan-out at a time)
        PoolResults   cell   = {}
        PoolExpected  double = 0
        PoolDone      double = 0
        PoolSucceeded double = 0
        PoolFailed    double = 0
    end

    properties
        PageSkip  double = 0
        PageLimit double = 15
    end

    methods
        function obj = BackendsViewModel(app)
            obj.App = app;
        end

        % ── Data loading ──────────────────────────────────────────────────

        function onRefreshBackends(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Backends', 'Icon', 'warning'); return;
            end
            % Always try to get enriched backend list with circuit_id.
            % If no circuit selected, fetch one from the project.
            cid = '';
            if app.State.hasCircuit()
                cid = char(app.State.selectedCircuitId);
            end
            app.showLoading(Labels.get('loading_backends', 'Loading backends...'));
            backendSvc  = app.BackendSvc;
            circuitSvc  = app.CircuitSvc;
            token       = app.State.authToken;
            AsyncRunner.run( ...
                @() BackendsViewModel.fetchBackends(backendSvc, circuitSvc, token, cid), ...
                @(data) obj.onRefreshBackendsComplete(app, data), ...
                @(ME)   obj.onRefreshBackendsError(app, ME));
        end

        function onRefreshBackendsComplete(obj, app, data)
            rows = JsonHelper.backendsToRows(data);
            obj.FullTableData = rows;
            obj.PageSkip = 0;  % reset to page 1 on refresh
            obj.applyPage();
            if ~isempty(rows)
                obj.populateKpiCards(app, rows);
            end
            app.setStatus(app.BackendStatusArea, {sprintf('Loaded %d backend(s).', size(rows,1))});
            app.logEvent('API', sprintf('Backends loaded — %d rows', size(rows,1)));
            obj.LastRefresh = tic;
            app.hideLoading();
        end

        function onRefreshBackendsError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Backends FAILED: %s', ME.message));
            app.setStatus(app.BackendStatusArea, {'Backend refresh failed.', ME.message});
            app.showError('Refresh Backends', ME);
        end

        % ── Search ────────────────────────────────────────────────────────

        function onSearch(obj, query)
            app = obj.App;
            if isempty(obj.FullTableData); return; end
            q = lower(strtrim(query));
            if isempty(q)
                % Restore full data with pagination
                obj.PageSkip = 0;
                obj.applyPage();
                return;
            end
            nRows = size(obj.FullTableData, 1);
            keep = false(nRows, 1);
            for i = 1:nRows
                for j = 1:size(obj.FullTableData, 2)
                    v = obj.FullTableData{i, j};
                    if ischar(v) && contains(lower(v), q)
                        keep(i) = true; break;
                    elseif isnumeric(v) && contains(num2str(v), q)
                        keep(i) = true; break;
                    end
                end
            end
            filtered = obj.FullTableData(keep, :);
            app.BackendTable.Data = obj.prependIndex(filtered, 1);
        end

        % ── Pagination ────────────────────────────────────────────────────

        function onNextPage(obj)
            totalItems = size(obj.FullTableData, 1);
            if (obj.PageSkip + obj.PageLimit) < totalItems
                obj.PageSkip = obj.PageSkip + obj.PageLimit;
                obj.applyPage();
            end
        end

        function onPrevPage(obj)
            obj.PageSkip = max(0, obj.PageSkip - obj.PageLimit);
            obj.applyPage();
        end

        % ── Select button ─────────────────────────────────────────────────

        function onSelectBackend(obj)
            app = obj.App;
            row = obj.getSelectedRow();
            if row == 0; return; end
            selName = char(string(app.BackendTable.Data{row, 2}));
            if isempty(selName); return; end

            app.showLoading(Labels.get('loading_saving_selection', 'Saving backend selection...'));
            app.State.selectedBackend = string(selName);
            backupName = obj.findBackup(selName);
            app.State.backupBackend = string(backupName);

            obj.updateKpiForSelection(app, row, backupName);
            obj.updateStatusNotes(app, row, backupName);
            obj.persistSelection(app, selName, backupName);
        end

        % ── Context menu actions ──────────────────────────────────────────

        function onCtxSetPrimary(obj)
            obj.App.hideBackendsPopupMenu();
            drawnow;   % flush the hide before any subsequent work blocks the UI
            app = obj.App;
            row = obj.getSelectedRow();
            if row == 0; return; end
            selName = char(string(app.BackendTable.Data{row, 2}));
            if isempty(selName); return; end
            app.showLoading(Labels.get('loading_saving_primary', 'Setting primary backend...'));
            app.State.selectedBackend = string(selName);
            backupName = obj.findBackup(selName);
            app.State.backupBackend = string(backupName);
            obj.updateKpiForSelection(app, row, backupName);
            obj.updateStatusNotes(app, row, backupName);
            obj.persistSelection(app, selName, backupName);
        end

        function onCtxSetBackup(obj)
            app = obj.App;
            app.hideBackendsPopupMenu();
            drawnow;
            row = obj.getSelectedRow();
            if row == 0; return; end
            backupName = char(string(app.BackendTable.Data{row, 2}));
            app.showLoading(Labels.get('loading_saving_backup', 'Setting backup backend...'));
            app.State.backupBackend = string(backupName);
            if ~isempty(app.BackendKpiLabels) && numel(app.BackendKpiLabels) >= 2
                app.BackendKpiLabels{2}.Text = backupName;
            end
            notes = app.BackendStatusArea.Value;
            notes{end+1} = sprintf('Backup changed to: %s', backupName);
            app.setStatus(app.BackendStatusArea, notes);
            primary = char(app.State.selectedBackend);
            if isempty(primary)
                % No primary selected yet — nothing to persist but we still
                % opened a spinner; close it.
                app.hideLoading();
                return;
            end
            obj.persistSelection(app, primary, backupName);
        end

        % onSubmitToPool  Fan-out: submit the current circuit to each backend
        %   in the server's configured IBM pool (IBM_BACKENDS env). Mirrors
        %   the notebook's 3-QPU concurrent submission pattern — one job per
        %   backend, all fired in parallel via AsyncRunner.
        %
        %   Always fetches fresh /settings/ibm-config first — the cached
        %   ServerIbmConfig from login can become stale between login and
        %   this click (e.g. visiting Backends triggers a server-side
        %   IBM call that may have set the sticky-broken flag). Without
        %   the refetch we'd fire N doomed /jobs/submit calls and the
        %   user would see N × 503 Service Unavailable errors.
        function onSubmitToPool(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Submit Pool', 'Icon', 'warning'); return;
            end
            if ~app.State.hasCircuit()
                uialert(app.UIFigure, Labels.get('error_no_circuit'), 'Submit Pool', 'Icon', 'warning'); return;
            end
            app.showLoading('Checking IBM runtime status...');
            settingsSvc = app.SettingsSvc;
            token       = app.State.authToken;
            AsyncRunner.run( ...
                @() settingsSvc.getIbmConfig(token), ...
                @(cfg) obj.onPoolResolved(app, cfg), ...
                @(ME)  obj.onPoolResolveError(app, ME));
        end

        function onPoolResolved(obj, app, cfg)
            app.hideLoading();
            backends = JsonHelper.safeField(cfg, 'backends', {});
            if ischar(backends); backends = {backends}; end
            if ~iscell(backends); backends = num2cell(string(backends)); end
            hasToken = logical(JsonHelper.safeField(cfg, 'has_token', false));
            broken   = logical(JsonHelper.safeField(cfg, 'runtime_broken', false));
            reason   = char(JsonHelper.safeField(cfg, 'runtime_broken_reason', ''));
            % Update the session cache so other screens don't see stale state.
            app.ServerIbmConfig = struct( ...
                'channel',  string(JsonHelper.safeField(cfg, 'channel', '')), ...
                'instance', string(JsonHelper.safeField(cfg, 'instance', '')), ...
                'backends', {backends}, ...
                'has_token', hasToken, ...
                'runtime_broken', broken, ...
                'runtime_broken_reason', string(reason));

            % Fail with a targeted dialog BEFORE firing N doomed requests.
            if broken
                uialert(app.UIFigure, ...
                    sprintf(['IBM runtime is currently unavailable on the server, ' ...
                            'so all %d submissions would return 503.\n\n%s\n\n' ...
                            'Fix the IBM credentials in the server .env and restart ' ...
                            'the API, then try again.'], numel(backends), reason), ...
                    'Submit to IBM pool', 'Icon', 'error');
                return;
            end
            if ~hasToken
                uialert(app.UIFigure, ...
                    Labels.get('error_no_server_token', ...
                        'Server has no IBM_QUANTUM_TOKEN configured.'), ...
                    'Submit to IBM pool', 'Icon', 'warning');
                return;
            end
            if isempty(backends)
                uialert(app.UIFigure, ...
                    Labels.get('error_no_pool', ...
                        'Server has no IBM backend pool configured.'), ...
                    'Submit to IBM pool', 'Icon', 'warning');
                return;
            end
            % All preconditions met — proceed with fan-out.
            obj.submitPool(app, backends, hasToken);
        end

        function onPoolResolveError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Resolve IBM pool FAILED: %s', ME.message));
            app.showError('Submit to IBM pool', ME);
        end

        function onCtxViewDetails(obj)
            app = obj.App;
            app.hideBackendsPopupMenu();
            drawnow;
            row = obj.getSelectedRow();
            if row == 0; return; end
            bName = char(string(app.BackendTable.Data{row, 2}));
            app.showLoading(sprintf('Loading details for %s...', bName));
            backendSvc = app.BackendSvc;
            token      = app.State.authToken;
            AsyncRunner.run( ...
                @() backendSvc.getBackend(bName, token), ...
                @(detail) obj.onCtxViewDetailsComplete(app, bName, detail), ...
                @(ME)     obj.onCtxViewDetailsError(app, ME));
        end

        function onCtxViewDetailsComplete(~, app, bName, detail)
            notes = {sprintf('=== %s ===', bName), ''};
            notes{end+1} = sprintf('Qubits: %s',      string(JsonHelper.pick(detail, {'num_qubits'})));
            notes{end+1} = sprintf('Operational: %s',  string(JsonHelper.pick(detail, {'operational'})));
            notes{end+1} = sprintf('Simulator: %s',    string(JsonHelper.pick(detail, {'simulator'})));
            notes{end+1} = sprintf('Max shots: %s',    string(JsonHelper.pick(detail, {'max_shots'})));
            notes{end+1} = sprintf('Version: %s',      string(JsonHelper.pick(detail, {'backend_version'})));
            gates = JsonHelper.pick(detail, {'basis_gates'});
            if iscell(gates); notes{end+1} = sprintf('Basis gates: %s', strjoin(string(gates), ', ')); end
            calAge = JsonHelper.pick(detail, {'calibration_age_hours'});
            if isnumeric(calAge) && ~isnan(calAge); notes{end+1} = sprintf('Calibration age: %.1f hours', calAge); end
            app.setStatus(app.BackendStatusArea, notes);
            app.hideLoading();
        end

        function onCtxViewDetailsError(~, app, ME)
            app.hideLoading();
            app.setStatus(app.BackendStatusArea, {sprintf('Failed to load details: %s', ME.message)});
        end
    end

    % ── Private helpers ───────────────────────────────────────────────────
    methods (Access = private)

        function submitPool(obj, app, backends, hasToken)
            if isempty(backends)
                uialert(app.UIFigure, Labels.get('error_no_pool', ...
                    'Server has no IBM backend pool configured.'), ...
                    'Submit to IBM pool', 'Icon', 'warning');
                return;
            end
            if ~hasToken
                uialert(app.UIFigure, Labels.get('error_no_server_token', ...
                    'Server is not configured with an IBM token.'), ...
                    'Submit to IBM pool', 'Icon', 'warning');
                return;
            end
            cid   = char(app.State.selectedCircuitId);
            shots = app.State.benchmarkShots;
            opt   = app.State.benchmarkOptLevel;
            mitig = char(app.State.benchmarkMitigation);
            n     = numel(backends);
            app.logEvent('API', sprintf('Pool submit — circuit: %s  backends: %d', cid, n));
            app.setStatus(app.BackendStatusArea, { ...
                sprintf('Submitting to %d IBM backend(s):', n), ...
                strjoin(cellfun(@(b) ['  • ' char(string(b))], backends, 'UniformOutput', false), newline)});

            % Spawn one AsyncRunner per backend. Each worker fires POST
            % /api/jobs/submit; the record IDs are collected in BackendStatusArea
            % as they come back. AppState.selectedJobId is set to the first
            % successful record so the Jobs screen auto-selects it.
            obj.PoolResults = cell(1, n);
            obj.PoolExpected = n;
            obj.PoolDone = 0;
            obj.PoolSucceeded = 0;
            obj.PoolFailed = 0;
            jobSvc = app.JobSvc;
            token  = app.State.authToken;
            for i = 1:n
                backend = char(string(backends{i}));
                payload = struct( ...
                    'circuit_id',         cid, ...
                    'backend_name',       backend, ...
                    'shots',              shots, ...
                    'optimization_level', opt);
                if ~isempty(mitig) && ~strcmp(mitig, 'none')
                    payload.error_mitigation = mitig;
                end
                idx = i;
                AsyncRunner.run( ...
                    @() jobSvc.submitJob(payload, token), ...
                    @(data) obj.onPoolJobComplete(app, idx, backend, data), ...
                    @(ME)   obj.onPoolJobError(app, idx, backend, ME));
            end
        end

        function onPoolJobComplete(obj, app, idx, backend, data)
            recordId = char(JsonHelper.pick(data, {'job_record_id','id'}));
            ibmJobId = char(JsonHelper.pick(data, {'ibm_job_id'}));
            status   = char(JsonHelper.pick(data, {'status'}));
            obj.PoolResults{idx} = struct('backend', backend, ...
                'record_id', recordId, 'ibm_job_id', ibmJobId, 'status', status, 'ok', true);
            obj.PoolSucceeded = obj.PoolSucceeded + 1;
            if strlength(app.State.selectedJobId) == 0 && ~isempty(recordId)
                app.State.selectedJobId = string(recordId);
            end
            app.logEvent('API', sprintf('Pool[%d] %s — record: %s  ibm_job_id: %s  status: %s', ...
                idx, backend, recordId, ibmJobId, status));
            obj.poolTick(app);
        end

        function onPoolJobError(obj, app, idx, backend, ME)
            obj.PoolResults{idx} = struct('backend', backend, ...
                'record_id', '', 'ibm_job_id', '', 'status', 'failed', ...
                'ok', false, 'error', ME.message);
            obj.PoolFailed = obj.PoolFailed + 1;
            app.logEvent('ERROR', sprintf('Pool[%d] %s FAILED: %s', idx, backend, ME.message));
            obj.poolTick(app);
        end

        function poolTick(obj, app)
            obj.PoolDone = obj.PoolDone + 1;
            if obj.PoolDone < obj.PoolExpected; return; end
            % All workers finished — summarise.
            lines = {sprintf(Labels.get('pool_submit_summary', ...
                'Pool submit complete — %d succeeded, %d failed.'), ...
                obj.PoolSucceeded, obj.PoolFailed)};
            for k = 1:numel(obj.PoolResults)
                r = obj.PoolResults{k};
                if isempty(r); continue; end
                if r.ok
                    lines{end+1} = sprintf('  ✓ %s — %s (IBM %s)', r.backend, r.status, r.ibm_job_id); %#ok<AGROW>
                else
                    lines{end+1} = sprintf('  ✗ %s — %s', r.backend, r.error); %#ok<AGROW>
                end
            end
            app.setStatus(app.BackendStatusArea, lines);
            app.State.logActivity(sprintf('Pool submit — %d/%d ok', ...
                obj.PoolSucceeded, obj.PoolExpected), 'Success');
            if obj.PoolSucceeded > 0
                % Navigate to Jobs so users see the new records.
                app.onSelectSection('Jobs');
            end
        end

        % fetchBackends and hasBackendsData moved to Static methods
        % so they can run on backgroundPool without capturing obj/app.

        function row = getSelectedRow(obj)
            app = obj.App;
            tData = app.BackendTable.Data;
            if isempty(tData); row = 0; return; end
            sel = app.BackendTable.Selection;
            if isempty(sel)
                uialert(app.UIFigure, Labels.get('error_select_backend_row', 'Select a backend row first.'), 'Select Backend', 'Icon', 'warning');
                row = 0; return;
            end
            row = sel(1);
        end

        function backupName = findBackup(obj, primaryName)
            tData = obj.App.BackendTable.Data;
            backupName = '';
            for r = 1:size(tData, 1)
                c = char(string(tData{r, 2}));
                if ~strcmp(c, primaryName) && ~isempty(c); backupName = c; break; end
            end
        end

        function populateKpiCards(~, app, rows)
            if isempty(app.BackendKpiLabels) || numel(app.BackendKpiLabels) < 4; return; end
            n = size(rows, 1); if n == 0; return; end
            primaryName = ''; backupName = ''; bestFid = 0;
            for i = 1:n
                role = lower(char(string(rows{i, 6})));
                fid = rows{i, 4};
                if isnumeric(fid) && ~isnan(fid) && fid > bestFid; bestFid = fid; end
                if strcmp(role, 'primary') && isempty(primaryName); primaryName = char(string(rows{i, 1})); end
                if strcmp(role, 'backup')  && isempty(backupName);  backupName  = char(string(rows{i, 1})); end
            end
            if isempty(primaryName) && n >= 1; primaryName = char(string(rows{1, 1})); end
            if isempty(backupName)  && n >= 2; backupName  = char(string(rows{2, 1})); end
            app.BackendKpiLabels{1}.Text = primaryName;
            app.BackendKpiLabels{2}.Text = backupName;
            if bestFid > 0; app.BackendKpiLabels{3}.Text = sprintf('%.4f', bestFid);
            else; app.BackendKpiLabels{3}.Text = 'N/A'; end
            app.BackendKpiLabels{4}.Text = 'Loading…';
            % Async-fetch calibration age so the KPI strip never blocks
            if ~isempty(primaryName)
                backendSvc = app.BackendSvc;
                token      = app.State.authToken;
                AsyncRunner.run( ...
                    @() backendSvc.getBackend(primaryName, token), ...
                    @(detail) BackendsViewModel.applyCalibrationAge(app, 4, detail), ...
                    @(ME) BackendsViewModel.calibrationAgeError(app, 4, ME));
            else
                app.BackendKpiLabels{4}.Text = 'N/A';
            end
        end

        function updateKpiForSelection(~, app, row, backupName)
            if isempty(app.BackendKpiLabels) || numel(app.BackendKpiLabels) < 4; return; end
            tData = app.BackendTable.Data;
            app.BackendKpiLabels{1}.Text = char(string(tData{row, 2}));
            if ~isempty(backupName); app.BackendKpiLabels{2}.Text = backupName; end
            fid = tData{row, 5};
            if isnumeric(fid) && ~isnan(fid); app.BackendKpiLabels{3}.Text = sprintf('%.4f', fid); end
            app.BackendKpiLabels{4}.Text = 'Loading…';
            primary    = char(string(tData{row,2}));
            backendSvc = app.BackendSvc;
            token      = app.State.authToken;
            AsyncRunner.run( ...
                @() backendSvc.getBackend(primary, token), ...
                @(detail) BackendsViewModel.applyCalibrationAge(app, 4, detail), ...
                @(ME) BackendsViewModel.calibrationAgeError(app, 4, ME));
        end

        function updateStatusNotes(~, app, row, backupName)
            tData = app.BackendTable.Data;
            selName = char(string(tData{row, 2}));
            notes = {sprintf('Primary backend: %s', selName)};
            if ~isempty(backupName); notes{end+1} = sprintf('Backup backend: %s', backupName); end
            notes{end+1} = ''; notes{end+1} = sprintf('Qubits: %s', string(tData{row, 3}));
            notes{end+1} = sprintf('Status: %s', string(tData{row, 4}));
            notes{end+1} = sprintf('Predicted Fidelity: %s', string(tData{row, 5}));
            notes{end+1} = sprintf('Queue: %s', string(tData{row, 6}));
            app.setStatus(app.BackendStatusArea, notes);
        end

        function persistSelection(~, app, primaryName, backupName)
            if ~app.State.isAuthenticated() || ~app.State.hasProject() || isempty(primaryName)
                % No auth / project / primary → nothing to save. The caller
                % may have already opened a loading overlay; close it.
                app.hideLoading();
                return;
            end
            % Run save in the background so the popup close / KPI update
            % aren't blocked by the HTTP round-trip. Callers are expected
            % to have already invoked showLoading; both terminal handlers
            % call hideLoading.
            pid        = app.State.currentProjectId;
            backendSvc = app.BackendSvc;
            token      = app.State.authToken;
            AsyncRunner.run( ...
                @() backendSvc.saveSelection(pid, string(primaryName), string(backupName), token), ...
                @(~) BackendsViewModel.onPersistDone(app, primaryName, backupName), ...
                @(ME) BackendsViewModel.onPersistError(app, ME));
        end

        function applyPage(obj)
            % Show only the current page slice from FullTableData,
            % prepending a 1-based index column.
            app = obj.App;
            n = size(obj.FullTableData, 1);
            startIdx = obj.PageSkip + 1;
            endIdx   = min(obj.PageSkip + obj.PageLimit, n);
            if startIdx <= n
                pageRows = obj.FullTableData(startIdx:endIdx, :);
                app.BackendTable.Data = obj.prependIndex(pageRows, startIdx);
            else
                app.BackendTable.Data = {};
            end
            obj.updatePageLabel();
        end

        function result = prependIndex(~, rows, startNum)
            % Prepend a gray-text index column starting at startNum.
            nRows = size(rows, 1);
            idxCol = cell(nRows, 1);
            for i = 1:nRows
                idxCol{i} = char(string(startNum + i - 1));
            end
            result = [idxCol, rows];
        end

        function updatePageLabel(obj)
            app = obj.App;
            if ~isprop(app, 'BackendsPageLabel') || isempty(app.BackendsPageLabel); return; end
            if ~isvalid(app.BackendsPageLabel); return; end
            totalItems = size(obj.FullTableData, 1);
            page = floor(obj.PageSkip / obj.PageLimit) + 1;
            totalPages = max(1, ceil(totalItems / obj.PageLimit));
            app.BackendsPageLabel.Text = sprintf('Page %d / %d', page, totalPages);
            if isprop(app, 'BackendsPrevBtn') && ~isempty(app.BackendsPrevBtn) && isvalid(app.BackendsPrevBtn)
                app.BackendsPrevBtn.Enable = obj.PageSkip > 0;
            end
            if isprop(app, 'BackendsNextBtn') && ~isempty(app.BackendsNextBtn) && isvalid(app.BackendsNextBtn)
                app.BackendsNextBtn.Enable = (obj.PageSkip + obj.PageLimit) < totalItems;
            end
        end
    end

    methods (Static, Access = private)
        function applyCalibrationAge(app, kpiIdx, detail)
            if isempty(app.BackendKpiLabels) || numel(app.BackendKpiLabels) < kpiIdx; return; end
            if ~isvalid(app.BackendKpiLabels{kpiIdx}); return; end
            ageHrs = JsonHelper.pick(detail, {'calibration_age_hours'});
            if isnumeric(ageHrs) && ~isnan(ageHrs)
                app.BackendKpiLabels{kpiIdx}.Text = sprintf('%.1f hours', ageHrs);
            else
                app.BackendKpiLabels{kpiIdx}.Text = 'N/A';
            end
        end

        function calibrationAgeError(app, kpiIdx, ME)
            Logger.debug('BackendsViewModel', 'calibration age fetch: %s', ME.message);
            if isempty(app.BackendKpiLabels) || numel(app.BackendKpiLabels) < kpiIdx; return; end
            if ~isvalid(app.BackendKpiLabels{kpiIdx}); return; end
            app.BackendKpiLabels{kpiIdx}.Text = 'N/A';
        end

        function onPersistDone(app, primaryName, backupName)
            app.hideLoading();
            app.logEvent('API', sprintf('Backend selection saved — primary: %s  backup: %s', ...
                primaryName, backupName));
        end

        function onPersistError(app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Save selection FAILED: %s', ME.message));
            app.showError('Save Backend Selection', ME);
        end

        function data = fetchBackends(backendSvc, circuitSvc, token, cid)
            % fetchBackends  Fetch backend list with fallback chain.
            %   Static method — runs on backgroundPool.  Must not reference
            %   app or any ViewModel instance.
            data = struct('backends', {{}});
            if ~isempty(cid)
                try
                    data = backendSvc.listBackends(token, cid);
                    if BackendsViewModel.hasBackendsData(data); return; end
                catch
                    Logger.debug('BackendsViewModel', 'Enriched backend list failed for selected circuit');
                end
            end
            try
                circList = circuitSvc.listCircuits(token);
                items = JsonHelper.extractList(circList, 'circuits');
                if ~isempty(items)
                    fallbackCid = char(JsonHelper.pick(items(1), {'circuit_id','id'}));
                    if ~isempty(fallbackCid)
                        data = backendSvc.listBackends(token, fallbackCid);
                        if BackendsViewModel.hasBackendsData(data); return; end
                    end
                end
            catch
                Logger.debug('BackendsViewModel', 'Fallback circuit lookup failed');
            end
            try
                data = backendSvc.listBackends(token, '');
            catch ME; Logger.debug('BackendsViewModel', 'fetchBackends basic list: %s', ME.message); end
        end

        function tf = hasBackendsData(data)
            tf = false;
            if isstruct(data) && isfield(data, 'backends')
                tf = ~isempty(data.backends);
            end
        end
    end
end
