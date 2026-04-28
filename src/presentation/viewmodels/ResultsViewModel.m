classdef ResultsViewModel < handle
    % ResultsViewModel  Callback handlers for the Results screen.
    properties
        LastRefresh = []     % tic value — used by autoLoadScreen for freshness caching
        CuttingBatches = {}  % cached list of batch dicts from /api/cutting/batches
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
            rows = JsonHelper.resultsToRows(data);
            if ~isempty(rows)
                app.ResultsTable.Data = rows;
            end
            statusStr  = char(JsonHelper.pick(data, {'status'}));
            backendStr = char(JsonHelper.pick(data, {'backend_name','backend'}));
            fidelity   = char(JsonHelper.pick(data, {'measured_fidelity','fidelity'}));
            summary = { ...
                sprintf('Job: %s', jobId), ...
                sprintf('Backend: %s', backendStr), ...
                sprintf('Status: %s',  statusStr), ...
                sprintf('Fidelity: %s', fidelity)};
            app.setStatus(app.ResultJsonArea, summary);
            app.logEvent('API', sprintf('Results loaded — job: %s  status: %s  fidelity: %s  rows: %d', ...
                jobId, statusStr, fidelity, size(rows,1)));
            app.State.logActivity(sprintf('View results — job: %s', char(jobId)), 'Success');
            obj.LastRefresh = tic;
            app.hideLoading();
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
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() app.CuttingSvc.listBatches(token), ...
                @(data) obj.onBatchesLoaded(app, data), ...
                @(ME)   obj.onBatchesError(app, ME));
        end

        function onBatchesLoaded(obj, app, data)
            % Normalise the /api/cutting/batches response into a cell
            % array of batch dicts. The response shape is {batches: [...]}.
            % MATLAB jsondecode quirks force three branches:
            %   * batches absent / data not a struct → empty
            %   * batches is a JSON array of N>=1 → struct array of size N
            %   * batches is a 1-element JSON array → single struct (NOT
            %     a 1-element struct array) — MATLAB collapses singletons
            %   * batches is an empty JSON array → empty double []
            items = {};
            try
                if isstruct(data) && isfield(data, 'batches')
                    raw = data.batches;
                    if isempty(raw)
                        items = {};
                    elseif iscell(raw)
                        items = raw(:).';
                    elseif isstruct(raw)
                        items = num2cell(raw(:).');
                    end
                end
            catch ME
                Logger.warn('ResultsViewModel', ...
                    'onBatchesLoaded: parse failed: %s', ME.message);
                items = {};
            end
            obj.CuttingBatches = items;

            tbl = app.CuttingBatchesTable;
            if isempty(tbl) || ~isvalid(tbl); return; end
            n = numel(items);
            if n == 0
                tbl.Data = {};
                app.logEvent('API', 'Cutting batches loaded: 0 row(s)');
                return;
            end
            rows = cell(n, 6);
            for i = 1:n
                try
                    rows(i, :) = obj.formatBatchRow(items{i});
                catch ME
                    Logger.warn('ResultsViewModel', ...
                        'formatBatchRow row %d failed: %s', i, ME.message);
                    rows(i, :) = {'(parse error)', '', '', '', '', ''};
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
                        '', '', '', '', ''}};
                end
            catch
            end
        end

        function row = formatBatchRow(~, batch)
            % Build a single 6-cell row matching results_table_cols_cutting_batches:
            %   Batch ID | Mode | k | Status | Observables | Created
            bid = char(string(JsonHelper.pick(batch, ...
                {'batch_id','id'}, '')));
            short = bid;
            if numel(short) > 8; short = [short(1:8) '…']; end
            mode = char(string(JsonHelper.pick(batch, {'mode'}, '')));
            cp = JsonHelper.pick(batch, 'cut_plan', struct());
            k = JsonHelper.pick(cp, 'k', 0);
            if ~isnumeric(k); k = str2double(k); end
            kStr = sprintf('%d', int32(k));
            status = char(string(JsonHelper.pick(batch, {'status'}, '')));
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
            % Trim ISO-8601 microseconds + timezone for compact display.
            if numel(created) > 19
                created = created(1:19);
            end
            row = {short, mode, kStr, status, obsStr, created};
        end

        function onReconstructionLoaded(obj, app, bid, data)
            app.hideLoading();
            status = char(string(JsonHelper.pick(data, {'status'}, '')));
            lines = obj.summariseReconstruction(bid, status, data);
            app.setStatus(app.ResultJsonArea, lines);
            app.logEvent('API', sprintf( ...
                'Reconstruction loaded — batch: %s  status: %s', ...
                bid, status));
            app.State.logActivity(sprintf( ...
                'View cutting reconstruction — batch: %s', bid), 'Success');
            obj.LastRefresh = tic;
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

        function lines = summariseReconstruction(~, bid, status, data)
            % Render the BatchResultResponse into 4-12 readable lines for
            % the ResultJsonArea textarea: header + each expectation row.
            lines = {};
            lines{end+1} = sprintf('Batch: %s', bid); %#ok<*AGROW>
            lines{end+1} = sprintf('Status: %s', status);
            exps = JsonHelper.pick(data, 'expectations', {});
            if iscell(exps); arr = exps; ...
            elseif isstruct(exps); arr = num2cell(exps); ...
            else; arr = {}; end
            if isempty(arr)
                lines{end+1} = '(no expectation values yet)';
                return;
            end
            lines{end+1} = '';
            lines{end+1} = 'Reconstructed expectation values:';
            for i = 1:numel(arr)
                e = arr{i};
                obsv = char(string(JsonHelper.pick(e, 'observable', '')));
                val  = JsonHelper.pick(e, 'value', NaN);
                err  = JsonHelper.pick(e, 'std_err', 0);
                st   = char(string(JsonHelper.pick(e, 'status', 'ok')));
                if ~isnumeric(val); val = str2double(val); end
                if ~isnumeric(err); err = str2double(err); end
                lines{end+1} = sprintf('  %s = %.6f ± %.6f  (%s)', ...
                    obsv, double(val), double(err), st);
            end
        end
    end
end
