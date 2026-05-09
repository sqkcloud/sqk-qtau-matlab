classdef ResultsViewModel < handle
    % ResultsViewModel  Callback handlers for the Results screen.
    properties
        LastRefresh = []     % tic value — used by autoLoadScreen for freshness caching
        CuttingBatches = {}  % cached list of batch dicts from /api/cutting/batches
        % Phase 4.2 — Mitigated/Raw sibling pair for the currently-
        % displayed cutting batch result. Empty fields when the
        % current result has no sibling. Populated by
        % applySiblingToggle from
        % GET /api/cutting/sibling/{group_id}.
        SiblingPair = struct( ...
            'group_id', '', ...
            'primary_id', '', ...
            'raw_id', '', ...
            'active_role', '')
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = ResultsViewModel(app)
            obj.App = app;
        end

        function onRefreshResults(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), ...
                    'Results', 'Icon', 'warning');
                return;
            end
            app.logEvent('API', 'GET /api/jobs — hunting for a completed job to display');
            app.showLoading(Labels.get('loading_results', 'Loading results...'));
            jobSvc = app.JobSvc;
            token  = app.State.authToken;
            % Ask the jobs list for a completed job first, then fetch its
            % results. Relying on State.selectedJobId (typically the first
            % row in the Jobs table, which is usually queued/running) gave
            % us HTTP 409 every time and left this screen blank.
            AsyncRunner.run( ...
                @() jobSvc.listJobs(token, 0, 100), ...
                @(list) obj.onJobsListedForResults(app, list), ...
                @(ME)   obj.onRefreshResultsError(app, char(app.State.selectedJobId), ME));
            % Kick off the cutting-batches refresh in parallel — the two
            % flows are independent so we don't block jobs on batches.
            obj.loadCuttingBatches();
        end

        function onCuttingBatchSelected(obj, ~, evt)
            % CellSelectionCallback fires with evt.Indices = [row col].
            % Stash the picked batch_id on AppState so the View
            % Reconstruction button (and any future bridges) know which
            % row was last clicked.
            try
                if isempty(evt) || isempty(evt.Indices)
                    return;
                end
                row = evt.Indices(1);
                if row < 1 || row > numel(obj.CuttingBatches); return; end
                batch = obj.CuttingBatches{row};
                bid = char(string(JsonHelper.pick(batch, ...
                    {'batch_id','id'}, '')));
                if ~isempty(bid)
                    obj.App.SelectedBatchId = string(bid);
                    obj.App.logEvent('UI', sprintf( ...
                        'Cutting batch selected: %s', bid));
                end
            catch ME
                Logger.debug('ResultsViewModel', ...
                    'onCuttingBatchSelected: %s', ME.message);
            end
        end

        function onViewReconstruction(obj)
            % Fetch /api/cutting/batches/{id}/result for the selected
            % batch and render the reconstructed expectation values into
            % the ResultJsonArea summary panel above the Cutting Batches
            % table.
            app = obj.App;
            bid = char(app.SelectedBatchId);
            if isempty(strtrim(bid))
                uialert(app.UIFigure, ...
                    'Click a row in the Circuit Cutting Batches table first.', ...
                    'Results', 'Icon', 'info');
                return;
            end
            app.logEvent('API', sprintf( ...
                'GET /api/cutting/batches/%s/result', bid));
            app.showLoading(Labels.get('loading_results', 'Loading results...'));
            svc   = app.CuttingSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getBatchResult(bid, token), ...
                @(data) obj.onReconstructionLoaded(app, bid, data), ...
                @(ME)   obj.onReconstructionError(app, bid, ME));
        end

        function onDownloadJsonResults(obj)
            % Re-fetch /api/jobs/{id}/results and dump the response to a
            % user-chosen .json file. Re-fetching (rather than caching)
            % guarantees the saved JSON matches what the API returns
            % right now and avoids accidentally exporting stale state.
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, ...
                    Labels.get('error_not_authenticated'), ...
                    'Download JSON', 'Icon', 'warning');
                return;
            end
            jid = char(app.State.selectedJobId);
            if isempty(strtrim(jid))
                uialert(app.UIFigure, ...
                    'Wait for a completed job to load first, then try again.', ...
                    'Download JSON', 'Icon', 'info');
                return;
            end
            app.logEvent('API', sprintf('GET /api/jobs/%s/results (export)', jid));
            app.showLoading('Fetching results for export...');
            jobSvc = app.JobSvc;
            token  = app.State.authToken;
            AsyncRunner.run( ...
                @() jobSvc.getJobResults(jid, token), ...
                @(data) obj.onJsonExportReady(app, data, jid), ...
                @(ME)   obj.onJsonExportError(app, ME));
        end

        function onJsonExportReady(~, app, data, jid)
            app.hideLoading();
            cname = char(app.State.selectedCircuitName);
            % Operator filename rule: Results_<circuit>_<jid>_<YYYYMMDD_HHMM>.json
            fname = Exporter.suggestFilename('Results', { ...
                cname, jid, Exporter.minuteStamp()});
            ok = Exporter.toJsonFile(data, fname, app.UIFigure);
            if ok
                app.logEvent('FILE', sprintf('Results JSON saved (job %s)', jid));
                app.State.logActivity( ...
                    sprintf('Download Results JSON — %s', cname), 'Success');
            end
        end

        function onJsonExportError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('JSON export FAILED: %s', ME.message));
            app.showError('Download JSON', ME);
        end

        function onGenerateRunReport(obj)
            % Generate Report button on the Results toolbar — alias for
            % onGenerateReportFromResults (kept for naming consistency
            % with the same button on Analysis / Detailed Analysis,
            % which all bridge to the Reports screen with a pre-filled
            % title via Reports' own loadReportsList → seedReportTitle).
            obj.onGenerateReportFromResults();
        end

        function onGenerateReportFromResults(obj)
            % Bridge from the Results screen to Reports. Confirms a
            % job context exists, then navigates — the Reports screen's
            % own onEnter (loadReportsList) auto-seeds the title from
            % app.State.selectedCircuitName / selectedBackend so the
            % operator only has to confirm format/sections, not retype
            % the title.
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, ...
                    Labels.get('error_not_authenticated'), ...
                    'Generate Report', 'Icon', 'warning');
                return;
            end
            jid = char(app.State.selectedJobId);
            if isempty(strtrim(jid))
                uialert(app.UIFigure, ...
                    'Wait for a completed job to load first, then try again.', ...
                    'Generate Report', 'Icon', 'info');
                return;
            end
            app.logEvent('NAV', sprintf( ...
                'Results → Reports (job %s)', jid));
            app.onSelectSection('Reports');
        end

        function onMitigationToggleClicked(obj, role)
            % Phase 4.2 toggle handler. ``role`` is 'primary' or 'raw'
            % depending on which toggle button the operator clicked.
            % Re-fetches the alternate batch's result and reuses the
            % existing reconstruction-rendering pipeline.
            app = obj.App;
            role = char(role);
            if isempty(obj.SiblingPair.group_id)
                return;
            end
            if strcmp(role, 'primary')
                target = char(obj.SiblingPair.primary_id);
            else
                target = char(obj.SiblingPair.raw_id);
            end
            if isempty(target)
                uialert(app.UIFigure, ...
                    sprintf('No %s sibling exists for this batch.', role), ...
                    'Results', 'Icon', 'info');
                return;
            end
            if strcmp(target, char(app.SelectedBatchId))
                return;  % already showing this batch
            end
            obj.SiblingPair.active_role = role;
            obj.refreshToggleStyle();
            app.SelectedBatchId = string(target);
            app.logEvent('CUT', sprintf( ...
                'Mitigation toggle → %s sibling: %s', role, target));
            app.showLoading(Labels.get('loading_results', 'Loading results...'));
            svc   = app.CuttingSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getBatchResult(target, token), ...
                @(data) obj.onReconstructionLoaded(app, target, data), ...
                @(ME)   obj.onReconstructionError(app, target, ME));
        end
    end

    methods (Access = private)
        function onJobsListedForResults(obj, app, list)
            items = JsonHelper.extractList(list, 'jobs');
            if isempty(items); items = JsonHelper.asList(list); end
            completedId = '';
            for i = 1:numel(items)
                status = lower(char(string(JsonHelper.pick(items(i), {'status'}))));
                if any(strcmp(status, {'completed', 'done', 'success'}))
                    completedId = char(string(JsonHelper.pick(items(i), ...
                        {'job_record_id','job_id','id'})));
                    if ~isempty(completedId); break; end
                end
            end

            % Fall back to whatever is currently selected if no completed
            % job exists — at least the user will still see the "not
            % ready" message explaining why.
            if isempty(completedId)
                if strlength(app.State.selectedJobId) > 0
                    completedId = char(app.State.selectedJobId);
                else
                    app.hideLoading();
                    app.setStatus(app.ResultJsonArea, { ...
                        'No jobs have completed yet.', ...
                        'Results will appear here after at least one job reaches status = completed.', ...
                        'Tip: open the Jobs screen to monitor live progress.'});
                    return;
                end
            else
                % Keep global state in sync so e.g. the Detailed Analysis
                % screen — which also reads app.State.selectedJobId — shows
                % the same job the Results screen is displaying.
                app.State.selectedJobId = string(completedId);
            end

            app.logEvent('API', sprintf('GET /api/jobs/%s/results', completedId));
            svc   = app.JobSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getResults(completedId, token), ...
                @(data) obj.onRefreshResultsComplete(app, completedId, data), ...
                @(ME)   obj.onRefreshResultsError(app, completedId, ME));
        end

        function onRefreshResultsComplete(obj, app, jobId, data)
            % Measured vs Predicted Summary table — `measured_vs_predicted`
            % array on the ResultSummary response.
            rows = JsonHelper.resultsToRows(data);
            if ~isempty(rows)
                app.ResultsTable.Data = rows;
            else
                app.ResultsTable.Data = {};
            end

            % Distribution Review table — `distribution_review` array on
            % the same response. Was previously never populated, leaving
            % the panel permanently empty even on completed jobs.
            distRows = JsonHelper.distributionToRows(data);
            if ~isempty(distRows)
                app.ResultsDistTable.Data = distRows;
            else
                app.ResultsDistTable.Data = {};
            end

            % ResultSummary uses `validation_status` and `estimated_fidelity`;
            % the older `status` / `measured_fidelity` / `fidelity` field
            % names don't exist on this endpoint, which is why this
            % header used to render blank for completed jobs.
            statusStr  = char(JsonHelper.pick(data, {'validation_status','status'}));
            backendStr = char(JsonHelper.pick(data, {'backend_name','backend'}));
            fidVal     = JsonHelper.pick(data, {'estimated_fidelity','measured_fidelity','fidelity'}, NaN);
            if isnumeric(fidVal) && ~isempty(fidVal) && ~all(isnan(fidVal))
                fidelity = sprintf('%.4f', double(fidVal));
            elseif ischar(fidVal) || isstring(fidVal)
                fidelity = char(string(fidVal));
            else
                fidelity = '';
            end
            summary = { ...
                sprintf('Job: %s', jobId), ...
                sprintf('Backend: %s', backendStr), ...
                sprintf('Status: %s',  statusStr), ...
                sprintf('Fidelity: %s', fidelity)};
            app.setStatus(app.ResultJsonArea, summary);
            app.logEvent('API', sprintf('Results loaded — job: %s  status: %s  fidelity: %s  metric rows: %d  dist rows: %d', ...
                jobId, statusStr, fidelity, size(rows,1), size(distRows,1)));
            app.State.logActivity(sprintf('View results — job: %s', char(jobId)), 'Success');
            obj.LastRefresh = tic;
            app.hideLoading();
            % Force the overlay to clear before the Tier B/C paint
            % work runs — applyHeroAndKpis + histogram paint can take
            % 100–300 ms on wide circuits and would otherwise visually
            % "stick" the loader.
            drawnow;
            % Tier B/C visual layer — populate the new identity strip,
            % KPI row, mitigation/timing/context tiles, and histogram
            % chart from the same response. Defensive: each helper
            % silently no-ops on missing widgets / fields so the
            % legacy populate path above stays robust either way.
            try
                ResultsViewModel.applyHeroAndKpis(app, jobId, data, statusStr);
            catch ME
                Logger.warn('ResultsViewModel', ...
                    'applyHeroAndKpis: %s', ME.message);
            end
        end

        function onRefreshResultsError(~, app, jobId, ME)
            app.hideLoading();
            % The backend returns 409 Conflict when the job has not reached
            % the `completed` state yet — that's a normal condition for
            % queued/running jobs, not an error. Show an informative note
            % in the status pane instead of a red alert modal.
            if contains(ME.identifier, 'HTTP409')
                app.logEvent('API', sprintf('Results not ready (job: %s) — job not yet completed', jobId));
                app.setStatus(app.ResultJsonArea, { ...
                    sprintf('Job: %s', jobId), ...
                    'Results are not available yet.', ...
                    'The job is still queued or running — results appear after completion.', ...
                    'Tip: check the Jobs screen for live status and use Refresh once status = completed.'});
                return;
            end
            app.logEvent('ERROR', sprintf('Results FAILED (job: %s): %s', jobId, ME.message));
            app.setStatus(app.ResultJsonArea, {'Results load failed.', ME.message});
            app.showError('Refresh Results', ME);
        end

        % ── Cutting batches ──────────────────────────────────────────────
        function loadCuttingBatches(obj)
            app = obj.App;
            try
                if isempty(app.CuttingSvc); return; end
            catch
                return;
            end
            % Capture LOCAL variables for the parfeval closure. Capturing
            % `app` would drag the entire QTAUWorkbenchApp class graph
            % (including uihtml properties) into the worker process,
            % which can't load matlab.ui.control.WebComponent — the
            % worker errors with "specified superclass ... contains a
            % parse error" and the table stays empty. Local handles to
            % CuttingSvc / CircuitSvc + the auth token sidestep that
            % entirely.
            cutSvc  = app.CuttingSvc;
            circSvc = app.CircuitSvc;
            token   = app.State.authToken;
            AsyncRunner.run( ...
                @() ResultsViewModel.fetchBatchesAndCircuits(cutSvc, circSvc, token), ...
                @(data) obj.onBatchesLoaded(app, data), ...
                @(ME)   obj.onBatchesError(app, ME));
        end

        function onBatchesLoaded(obj, app, data)
            % `data` is the struct produced by fetchBatchesAndCircuits:
            %   data.batches  — /api/cutting/batches response
            %   data.circuits — /api/circuits response (may be empty)
            % Normalise both legs and build a circuit_id → name lookup
            % so the Circuit column can render names instead of UUIDs.
            batchesRaw = [];
            circList   = [];
            try
                if isstruct(data) && isfield(data, 'batches')
                    batchesRaw = data.batches;
                end
                if isstruct(data) && isfield(data, 'circuits')
                    circList = data.circuits;
                end
            catch
            end

            items = {};
            try
                if isstruct(batchesRaw) && isfield(batchesRaw, 'batches')
                    raw = batchesRaw.batches;
                else
                    raw = batchesRaw;
                end
                if isempty(raw)
                    items = {};
                elseif iscell(raw)
                    items = raw(:).';
                elseif isstruct(raw)
                    items = num2cell(raw(:).');
                end
            catch ME
                Logger.warn('ResultsViewModel', ...
                    'onBatchesLoaded: parse failed: %s', ME.message);
                items = {};
            end
            obj.CuttingBatches = items;
            nameMap = ResultsViewModel.buildCircuitNameMap(circList);

            tbl = app.CuttingBatchesTable;
            if isempty(tbl) || ~isvalid(tbl); return; end
            n = numel(items);
            if n == 0
                tbl.Data = {};
                app.logEvent('API', 'Cutting batches loaded: 0 row(s)');
                return;
            end
            rows = cell(n, 8);
            for i = 1:n
                try
                    rows(i, :) = obj.formatBatchRow(items{i}, nameMap);
                catch ME
                    Logger.warn('ResultsViewModel', ...
                        'formatBatchRow row %d failed: %s', i, ME.message);
                    rows(i, :) = {'(parse error)', '', '', '', '', '', '', ''};
                end
            end
            tbl.Data = rows;
            app.logEvent('API', sprintf( ...
                'Cutting batches loaded: %d row(s)', n));
        end

        function onBatchesError(~, app, ME)
            % Cutting batch list is best-effort — failure shouldn't pop a
            % modal (would be noisy if cutting isn't deployed). Surface
            % the failure on the event log AND in the empty-state cell so
            % an empty table never looks like 'success with no data' when
            % it's actually a server failure.
            Logger.warn('ResultsViewModel', ...
                'listBatches FAILED: %s', ME.message);
            try
                app.logEvent('ERROR', sprintf( ...
                    'Cutting batches load failed: %s', ME.message));
            catch
            end
            try
                tbl = app.CuttingBatchesTable;
                if ~isempty(tbl) && isvalid(tbl)
                    tbl.Data = {{'(load failed — see event log)', ...
                        '', '', '', '', '', '', ''}};
                end
            catch
            end
        end

        function row = formatBatchRow(~, batch, nameMap)
            % Build a single 8-cell row matching results_table_cols_cutting_batches:
            %   Batch ID | Circuit | Backend | Mode | k | Status | Observables | Created
            % * Batch ID is shown in full (no truncation) so operators can
            %   correlate with Mongo / API logs without copy-paste guesswork.
            % * Status is uppercased to match the convention on the Jobs
            %   screen (COMPLETED / EXECUTING / FAILED / …).
            % * Circuit resolves circuit_id → name via the supplied
            %   nameMap; falls back to the id when the lookup misses.
            % * Backend is the comma-joined set of distinct backend_name
            %   values from backend_assignments (e.g. "ibm_fez, ibm_boston").
            if nargin < 3; nameMap = containers.Map('KeyType','char','ValueType','char'); end
            bid = char(string(JsonHelper.pick(batch, ...
                {'batch_id','id'}, '')));

            cid = char(string(JsonHelper.pick(batch, {'circuit_id'}, '')));
            circuitName = cid;
            if ~isempty(cid) && isKey(nameMap, cid)
                circuitName = nameMap(cid);
            end

            backendStr = ResultsViewModel.formatBackendList( ...
                JsonHelper.pick(batch, 'backend_assignments', {}));

            mode = upper(char(string(JsonHelper.pick(batch, {'mode'}, ''))));
            cp = JsonHelper.pick(batch, 'cut_plan', struct());
            k = JsonHelper.pick(cp, 'k', 0);
            if ~isnumeric(k); k = str2double(k); end
            kStr = sprintf('%d', int32(k));

            status = upper(char(string(JsonHelper.pick(batch, {'status'}, ''))));

            obs = JsonHelper.pick(batch, 'observables', {});
            if iscell(obs)
                nObs = numel(obs);
            elseif ischar(obs) || isstring(obs)
                nObs = 1;
            elseif isnumeric(obs) && isempty(obs)
                nObs = 0;
            else
                nObs = numel(obs);
            end
            obsStr = sprintf('%d', int32(nObs));

            created = char(string(JsonHelper.pick(batch, ...
                {'created_at','submitted_at'}, '')));
            if numel(created) > 19
                created = created(1:19);
            end

            row = {bid, circuitName, backendStr, mode, kStr, status, obsStr, created};
        end

        function onReconstructionLoaded(obj, app, bid, data)
            % Render the BatchResultResponse in a polished modal popup
            % instead of dumping every observable as raw text into the
            % ResultJsonArea textarea. The dialog handles long Pauli
            % strings, NaN values, and surfaces a diagnostic callout
            % when the reconstruction returned NaN. See
            % DialogBuilder.buildReconstructionDialog for the layout.
            app.hideLoading();
            status = char(string(JsonHelper.pick(data, {'status'}, '')));
            try
                DialogBuilder.buildReconstructionDialog( ...
                    app, char(bid), status, data);
            catch ME
                Logger.warn('ResultsViewModel', ...
                    'buildReconstructionDialog failed: %s', ME.message);
                app.setStatus(app.ResultJsonArea, { ...
                    sprintf('Reconstruction loaded for batch %s.', bid), ...
                    'Could not open the summary popup -- see event log.'});
            end
            app.logEvent('API', sprintf( ...
                'Reconstruction loaded — batch: %s  status: %s', ...
                bid, status));
            app.State.logActivity(sprintf( ...
                'View cutting reconstruction — batch: %s', bid), 'Success');
            obj.LastRefresh = tic;

            % Phase 4.2 — Mitigated/Raw toggle. When the loaded batch
            % carries a non-empty sibling_group_id, resolve the pair
            % via GET /api/cutting/sibling/{group_id} and show the
            % toggle row above the result table. Best-effort: any
            % HTTP failure leaves the toggle hidden rather than
            % surfacing an error modal.
            try
                obj.applySiblingToggle(data);
            catch ME
                Logger.debug('ResultsViewModel', ...
                    'applySiblingToggle: %s', ME.message);
            end
        end

        function onReconstructionError(~, app, bid, ME)
            app.hideLoading();
            if contains(ME.identifier, 'HTTP409')
                app.logEvent('API', sprintf( ...
                    'Reconstruction not ready (batch: %s)', bid));
                app.setStatus(app.ResultJsonArea, { ...
                    sprintf('Batch: %s', bid), ...
                    'Reconstruction is not ready yet.', ...
                    'The batch has not finished — try again once status = completed.'});
                return;
            end
            app.logEvent('ERROR', sprintf( ...
                'Reconstruction FAILED (batch: %s): %s', bid, ME.message));
            app.setStatus(app.ResultJsonArea, { ...
                'Reconstruction load failed.', ME.message});
            app.showError('View Reconstruction', ME);
        end

    end

    methods (Static, Access = private)
        function out = fetchBatchesAndCircuits(cutSvc, circSvc, token)
            % Pull cutting batches (required) and circuits (best-effort)
            % so the row formatter can resolve circuit_id → name. A
            % failure on the circuits leg downgrades the Circuit column
            % to the raw id; the batches still render.
            out = struct('batches', [], 'circuits', []);
            out.batches = cutSvc.listBatches(token);
            try
                out.circuits = circSvc.listCircuits(token);
            catch ME
                Logger.warn('ResultsViewModel', ...
                    'Circuit list fetch failed (batches still shown): %s', ME.message);
            end
        end

        function map = buildCircuitNameMap(circList)
            % circuit_id → display name lookup. Returns an empty map
            % when the circuit list is unavailable or empty.
            map = containers.Map('KeyType', 'char', 'ValueType', 'char');
            if isempty(circList); return; end
            items = JsonHelper.extractList(circList, 'circuits');
            if isempty(items); items = JsonHelper.asList(circList); end
            for i = 1:numel(items)
                cid = char(JsonHelper.pick(items(i), {'circuit_id','id'}));
                nm  = char(JsonHelper.pick(items(i), {'name','circuit_name'}));
                if isempty(nm); nm = cid; end
                if ~isempty(cid); map(cid) = nm; end
            end
        end

        function s = formatBackendList(assignments)
            % Render backend_assignments as a compact, distinct,
            % comma-joined string ("ibm_fez, ibm_boston"). Preserves the
            % first-occurrence order so column reads stay deterministic.
            s = '';
            if isempty(assignments); return; end
            if iscell(assignments)
                items = assignments;
            elseif isstruct(assignments)
                items = num2cell(assignments(:).');
            else
                return;
            end
            seen = {};
            for i = 1:numel(items)
                nm = char(string(JsonHelper.pick(items{i}, ...
                    {'backend_name','backend','name'}, '')));
                if isempty(nm); continue; end
                if any(strcmp(seen, nm)); continue; end
                seen{end+1} = nm; %#ok<AGROW>
            end
            if isempty(seen); return; end
            s = strjoin(seen, ', ');
        end

        function applySiblingToggle(obj, data)
            % Resolve the sibling pair for the freshly-loaded batch
            % result and toggle the Mitigated/Raw row visibility on
            % the Results screen.
            %
            % When ``data.sibling_group_id`` is empty: hide the toggle
            % entirely (single-batch workflows are unaffected).
            %
            % When non-empty: cache the loaded role on
            % obj.SiblingPair.active_role and call
            % GET /api/cutting/sibling/{group_id} to resolve both
            % batch ids. Updates button styles to highlight the
            % currently-displayed role.
            app = obj.App;
            if isempty(app.ResultsMitigationToggleGrid) || ...
                    ~isvalid(app.ResultsMitigationToggleGrid)
                return;
            end

            groupId = char(string(JsonHelper.pick(data, ...
                'sibling_group_id', '')));
            role = char(string(JsonHelper.pick(data, ...
                'mitigation_role', '')));

            if isempty(groupId)
                % No sibling — collapse the toggle row.
                app.ResultsMitigationToggleGrid.Visible = 'off';
                obj.SiblingPair = struct( ...
                    'group_id', '', 'primary_id', '', ...
                    'raw_id', '', 'active_role', '');
                return;
            end

            % Reuse cached pair when we've already resolved this
            % group — saves a redundant HTTP round-trip when the
            % operator toggles back and forth.
            if ~strcmp(obj.SiblingPair.group_id, groupId)
                token = '';
                try
                    token = char(app.State.authToken);
                catch; end
                if isempty(token); return; end
                % Async — was a brief one-time freeze on first toggle.
                % The post-fetch visibility + style logic runs from
                % onSiblingPairLoaded; both cached and just-fetched
                % paths share finalizeMitigationToggle.
                svc = app.CuttingSvc;
                AsyncRunner.run( ...
                    @() svc.getSiblingPair(groupId, token), ...
                    @(pair) obj.onSiblingPairLoaded(app, groupId, role, pair), ...
                    @(ME)   obj.onSiblingPairLoadError(app, ME));
                return;  % continuation lives in the callback
            end
            % Cached case: just update active_role and finalize.
            obj.SiblingPair.active_role = role;
            obj.finalizeMitigationToggle(app);
        end

        function onSiblingPairLoaded(obj, app, groupId, role, pair)
            obj.SiblingPair = struct( ...
                'group_id',    groupId, ...
                'primary_id',  char(string(JsonHelper.pick(pair, ...
                                   'primary_batch_id', ''))), ...
                'raw_id',      char(string(JsonHelper.pick(pair, ...
                                   'raw_batch_id', ''))), ...
                'active_role', role);
            obj.finalizeMitigationToggle(app);
        end

        function onSiblingPairLoadError(~, app, ME)
            Logger.debug('ResultsViewModel', ...
                'getSiblingPair failed: %s', ME.message);
            if ~isempty(app.ResultsMitigationToggleGrid) ...
                    && isvalid(app.ResultsMitigationToggleGrid)
                app.ResultsMitigationToggleGrid.Visible = 'off';
            end
        end

        function finalizeMitigationToggle(obj, app)
            % Shared post-fetch step: hide the toggle when only one
            % sibling exists, otherwise reveal + repaint button styles.
            if isempty(app.ResultsMitigationToggleGrid) ...
                    || ~isvalid(app.ResultsMitigationToggleGrid)
                return;
            end
            if isempty(obj.SiblingPair.primary_id) || ...
                    isempty(obj.SiblingPair.raw_id)
                app.ResultsMitigationToggleGrid.Visible = 'off';
                return;
            end
            app.ResultsMitigationToggleGrid.Visible = 'on';
            obj.refreshToggleStyle();
        end

        function refreshToggleStyle(obj)
            % Highlight whichever role is active by flipping the button
            % styles between 'primary' (active) and 'ghost' (inactive).
            app = obj.App;
            if isempty(app.ResultsMitigatedToggleBtn) || ...
                    ~isvalid(app.ResultsMitigatedToggleBtn)
                return;
            end
            isRawActive = strcmp(char(obj.SiblingPair.active_role), 'raw');
            try
                if isRawActive
                    app.styleBtn(app.ResultsMitigatedToggleBtn, 'ghost');
                    app.styleBtn(app.ResultsRawToggleBtn,       'primary');
                else
                    app.styleBtn(app.ResultsMitigatedToggleBtn, 'primary');
                    app.styleBtn(app.ResultsRawToggleBtn,       'ghost');
                end
            catch ME
                Logger.debug('ResultsViewModel', ...
                    'refreshToggleStyle: %s', ME.message);
            end
        end

        % ── Tier B/C render helpers (M2) ─────────────────────────────────
        function applyHeroAndKpis(app, jobId, data, statusStr)
            % Populate the identity strip, KPI row, mitigation/timing/
            % context tiles, and histogram from a /api/jobs/{id}/results
            % response. Each block is wrapped in its own try/catch so
            % a missing field never blocks the rest.
            cname   = char(app.State.selectedCircuitName);
            backend = char(JsonHelper.pick(data, {'backend_name','backend'}));
            shots   = JsonHelper.pickNumeric(data, 'shots', NaN);
            ibmJob  = char(JsonHelper.pick(data, {'ibm_job_id'}, ''));

            % Identity strip.
            try
                if ~isempty(app.ResultsHeroSubtitle) && isvalid(app.ResultsHeroSubtitle)
                    parts = {};
                    if ~isempty(cname);   parts{end+1} = cname;   end %#ok<AGROW>
                    if ~isempty(backend); parts{end+1} = backend; end %#ok<AGROW>
                    if isfinite(shots) && shots > 0
                        parts{end+1} = sprintf('%d shots', round(shots));
                    end
                    if isempty(parts)
                        sub = 'Run a job to populate this view.';
                    else
                        sub = strjoin(parts, [' ' char(8226) ' ']);
                    end
                    app.ResultsHeroSubtitle.Text = sub;
                end
                if ~isempty(app.ResultsHeroJobLine) && isvalid(app.ResultsHeroJobLine)
                    line = sprintf('Job %s', char(jobId));
                    if ~isempty(ibmJob)
                        line = sprintf('%s   %c   IBM %s', line, char(8226), ibmJob);
                    end
                    line = sprintf('%s   %c   Run %s', line, char(8226), ...
                        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')));
                    app.ResultsHeroJobLine.Text = line;
                end
            catch
            end

            % Status pill.
            try
                ResultsViewModel.setStatusPill(app, statusStr);
            catch
            end

            % KPI row — Fidelity / Success / Dominant / 2Q / Readout.
            fidVal = JsonHelper.pickNumeric(data, ...
                {'estimated_fidelity','measured_fidelity','fidelity'}, NaN);
            succVal = JsonHelper.pickNumeric(data, 'success_rate', NaN);
            domState = char(JsonHelper.pick(data, {'most_frequent_bitstring'}, ''));
            idealOverlap = JsonHelper.pickNumeric(data, 'ideal_overlap', NaN);
            twoQ = JsonHelper.pickNumeric(data, ...
                {'two_qubit_error_impact','features.two_qubit_error_impact'}, NaN);
            readout = JsonHelper.pickNumeric(data, ...
                {'readout_contribution','features.readout_contribution'}, NaN);

            ResultsViewModel.setKpi(app.ResultsKpiFidelityVal, app.ResultsKpiFidelitySub, ...
                ResultsViewModel.fmtRatio(fidVal), ...
                ResultsViewModel.fmtIdealSub(idealOverlap, 'ideal'));
            ResultsViewModel.setKpi(app.ResultsKpiSuccessVal, app.ResultsKpiSuccessSub, ...
                ResultsViewModel.fmtPct(succVal), ...
                ResultsViewModel.fmtIdealSub(1.0, 'ideal'));
            ResultsViewModel.setKpi(app.ResultsKpiDominantVal, app.ResultsKpiDominantSub, ...
                ResultsViewModel.fmtBitstring(domState), '');
            ResultsViewModel.setKpi(app.ResultsKpiTwoQVal, app.ResultsKpiTwoQSub, ...
                ResultsViewModel.fmtRatio(twoQ), 'gate noise');
            ResultsViewModel.setKpi(app.ResultsKpiReadoutVal, app.ResultsKpiReadoutSub, ...
                ResultsViewModel.fmtRatio(readout), 'measurement');

            % Mitigation / Timing / Context tiles. Pull what's
            % available; show "—" for unknown fields.
            mit = JsonHelper.safeField(data, 'mitigation_plan', struct());
            if ~isstruct(mit); mit = struct(); end
            ResultsViewModel.setKvLabels(app.ResultsMitigationLabels, { ...
                ResultsViewModel.mitigationLevelLabel(mit), ...
                ResultsViewModel.boolBadge(mit, 'twirling_gates', 'twirling_measure'), ...
                ResultsViewModel.boolBadge(mit, 'dd_enable'), ...
                ResultsViewModel.boolBadge(mit, 'zne_enable')});
            ResultsViewModel.setKvLabels(app.ResultsTimingLabels, { ...
                ResultsViewModel.timingDelta( ...
                    JsonHelper.pick(data, {'submitted_at'}, ''), ...
                    JsonHelper.pick(data, {'started_at','running_at'}, '')), ...
                ResultsViewModel.timingDelta( ...
                    JsonHelper.pick(data, {'started_at','running_at'}, ''), ...
                    JsonHelper.pick(data, {'completed_at'}, '')), ...
                ResultsViewModel.timingDelta( ...
                    JsonHelper.pick(data, {'submitted_at'}, ''), ...
                    JsonHelper.pick(data, {'completed_at'}, ''))});
            projName = char(app.State.currentProjectName);
            if isempty(projName); projName = char(app.State.currentProjectId); end
            ResultsViewModel.setKvLabels(app.ResultsContextLabels, { ...
                projName, ...
                char(JsonHelper.pick(data, {'submitted_at'}, char(8212))), ...
                char(app.State.currentUser)});

            % Histogram.
            try
                ResultsViewModel.paintResultsHistogram(app, data);
            catch
            end
        end

        function setStatusPill(app, statusStr)
            if isempty(app.ResultsStatusPill) || ~isvalid(app.ResultsStatusPill)
                return;
            end
            s = lower(strtrim(char(statusStr)));
            switch s
                case {'pass','success','completed','done'}
                    bg = Theme.COLOR_SUCCESS;
                    txt = upper(s);
                case {'marginal','warning','warn'}
                    bg = Theme.COLOR_AMBER;
                    txt = upper(s);
                case {'fail','failed','error','cancelled'}
                    bg = Theme.COLOR_DANGER;
                    txt = upper(s);
                case {'queued','pending','running','executing'}
                    bg = Theme.COLOR_PRIMARY;
                    txt = upper(s);
                otherwise
                    bg = Theme.COLOR_DIVIDER;
                    txt = char(8212);
                    if ~isempty(s); txt = upper(s); end
            end
            app.ResultsStatusPill.Text = txt;
            app.ResultsStatusPill.BackgroundColor = bg;
            % White-on-bg always reads against these palette entries.
            app.ResultsStatusPill.FontColor = [1 1 1];
        end

        function setKpi(valLbl, subLbl, valTxt, subTxt)
            try
                if ~isempty(valLbl) && isvalid(valLbl); valLbl.Text = valTxt; end
                if ~isempty(subLbl) && isvalid(subLbl); subLbl.Text = subTxt; end
            catch
            end
        end

        function setKvLabels(handles, values)
            try
                if isempty(handles); return; end
                n = min(numel(handles), numel(values));
                for i = 1:n
                    h = handles{i};
                    if ~isempty(h) && isvalid(h)
                        h.Text = char(string(values{i}));
                    end
                end
            catch
            end
        end

        function s = fmtRatio(v)
            if ~isnumeric(v) || isempty(v) || all(isnan(v))
                s = char(8212); return;
            end
            s = sprintf('%.4f', double(v));
        end

        function s = fmtPct(v)
            if ~isnumeric(v) || isempty(v) || all(isnan(v))
                s = char(8212); return;
            end
            s = sprintf('%.1f%%', 100 * double(v));
        end

        function s = fmtIdealSub(v, prefix)
            if ~isnumeric(v) || isempty(v) || all(isnan(v))
                s = ''; return;
            end
            s = sprintf('(%s %.4f)', prefix, double(v));
        end

        function s = fmtBitstring(b)
            b = char(string(b));
            if isempty(strtrim(b)); s = char(8212); return; end
            if numel(b) > 14
                s = sprintf('%s%s%s', b(1:5), char(8230), b(end-5:end));
            else
                s = b;
            end
        end

        function s = mitigationLevelLabel(mit)
            if ~isstruct(mit); s = char(8212); return; end
            lvl = JsonHelper.pickNumeric(mit, 'level', NaN);
            nm  = char(JsonHelper.pick(mit, {'name'}, ''));
            if isfinite(lvl) && ~isempty(nm)
                s = sprintf('%s (lvl %d)', nm, round(lvl));
            elseif ~isempty(nm)
                s = nm;
            elseif isfinite(lvl)
                s = sprintf('lvl %d', round(lvl));
            else
                s = char(8212);
            end
        end

        function s = boolBadge(mit, varargin)
            if ~isstruct(mit); s = char(8212); return; end
            anyTrue = false;
            for i = 1:numel(varargin)
                v = JsonHelper.pick(mit, varargin{i}, []);
                if islogical(v) && any(v); anyTrue = true; break; end
                if isnumeric(v) && any(v); anyTrue = true; break; end
                if (ischar(v) || isstring(v)) && ~isempty(v) ...
                        && ~strcmpi(strtrim(char(v)), 'off') ...
                        && ~strcmpi(strtrim(char(v)), 'none')
                    anyTrue = true; break;
                end
            end
            if anyTrue; s = 'ON'; else; s = 'off'; end
        end

        function s = timingDelta(startIso, endIso)
            try
                if isempty(startIso) || isempty(endIso); s = char(8212); return; end
                t0 = datetime(string(startIso), 'InputFormat', ...
                    'yyyy-MM-dd''T''HH:mm:ss', 'TimeZone', 'UTC');
                t1 = datetime(string(endIso),   'InputFormat', ...
                    'yyyy-MM-dd''T''HH:mm:ss', 'TimeZone', 'UTC');
                d = seconds(t1 - t0);
                if ~isfinite(d) || d < 0; s = char(8212); return; end
                if d < 60
                    s = sprintf('%.0fs', d);
                elseif d < 3600
                    s = sprintf('%dm %02ds', floor(d/60), mod(round(d), 60));
                else
                    s = sprintf('%dh %02dm', floor(d/3600), floor(mod(d, 3600)/60));
                end
            catch
                s = char(8212);
            end
        end

        function paintResultsHistogram(app, data)
            % Top-N states + "other" bucket. Uses the response's
            % `histogram_data` field (sorted, with bitstring/count/
            % probability) when present; falls back to distribution_review
            % rows otherwise. Ideal overlay is plotted as a dashed line
            % on the same axes when distribution_review carries an
            % `ideal` column.
            if isempty(app.ResultsHistogramAxes) || ~isvalid(app.ResultsHistogramAxes)
                return;
            end
            ax = app.ResultsHistogramAxes;
            cla(ax);
            states = {}; measured = []; ideals = [];
            % Prefer histogram_data (richer, already sorted).
            hd = JsonHelper.pick(data, {'histogram_data'}, []);
            if iscell(hd) && ~isempty(hd)
                topN = min(5, numel(hd));
                for i = 1:topN
                    e = hd{i};
                    states{end+1} = char(string(JsonHelper.pick(e, ...
                        {'bitstring','state'}, ''))); %#ok<AGROW>
                    measured(end+1) = JsonHelper.pickNumeric(e, ...
                        'probability', NaN); %#ok<AGROW>
                    ideals(end+1) = NaN; %#ok<AGROW>
                end
                if numel(hd) > topN
                    % Cap iteration to avoid freezing the UI thread on
                    % wide circuits (22q+ runs can produce 4 k+ distinct
                    % outcomes, each requiring a struct-field lookup).
                    maxRest = min(numel(hd) - topN, 50);
                    rest = 0;
                    for i = (topN + 1):(topN + maxRest)
                        p = JsonHelper.pickNumeric(hd{i}, 'probability', 0);
                        if isfinite(p); rest = rest + p; end
                    end
                    states{end+1} = 'other';
                    measured(end+1) = rest;
                    ideals(end+1) = NaN;
                end
            end
            % Fall back to distribution_review (carries ideal column).
            if isempty(states)
                dr = JsonHelper.pick(data, {'distribution_review'}, []);
                if iscell(dr) && ~isempty(dr)
                    for i = 1:min(6, numel(dr))
                        e = dr{i};
                        states{end+1} = char(string(JsonHelper.pick(e, ...
                            {'state'}, ''))); %#ok<AGROW>
                        measured(end+1) = JsonHelper.pickNumeric(e, ...
                            'measured', NaN); %#ok<AGROW>
                        ideals(end+1) = JsonHelper.pickNumeric(e, ...
                            'ideal', NaN); %#ok<AGROW>
                    end
                end
            end
            if isempty(states); return; end
            x = 1:numel(states);
            % Truncate state labels for x-axis readability.
            shortStates = cellfun(@(s) ResultsViewModel.fmtBitstring(s), ...
                states, 'UniformOutput', false);
            bar(ax, x, measured, ...
                'FaceColor', Theme.COLOR_PRIMARY, 'EdgeColor', 'none', ...
                'FaceAlpha', 0.85);
            hold(ax, 'on');
            % Ideal overlay where available.
            haveIdeal = any(isfinite(ideals));
            if haveIdeal
                plot(ax, x, ideals, ...
                    'LineStyle', '--', 'Marker', 'o', ...
                    'Color', Theme.COLOR_SUCCESS, 'LineWidth', 1.4, ...
                    'MarkerFaceColor', Theme.COLOR_SUCCESS);
                legend(ax, {'Measured','Ideal'}, 'Location', 'best', ...
                    'TextColor', Theme.COLOR_LABEL, 'Box', 'off');
            end
            hold(ax, 'off');
            ax.XTick = x;
            ax.XTickLabel = shortStates;
            ax.YLim = [0 1];
            ax.XGrid = 'off'; ax.YGrid = 'on';
        end
    end
end
