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
            % User explicitly asked for fresh backend data — drop the
            % shared caches so Mitigation/RunPlanner and the legacy
            % CircuitCutting pool cache also pick up the refresh.
            try
                app.State.invalidateBackendsListCache();
                app.State.BackendPoolCache   = [];
                app.State.BackendPoolCacheAt = [];
            catch; end
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
                obj.populateOverviewKpis(app, rows);
            end
            app.setStatus(app.BackendStatusArea, {sprintf('Loaded %d backend(s).', size(rows,1))});
            app.logEvent('API', sprintf('Backends loaded — %d rows', size(rows,1)));
            obj.LastRefresh = tic;
            app.hideLoading();

            % Auto-select the first backend row so the Telemetry sub-tabs
            % (Per-Qubit / History / Topology) paint with data immediately
            % on screen entry. Before this, the three tabs sat empty until
            % the user clicked a table row — which made the whole panel
            % look broken on first nav. SelectionChangedFcn may not fire
            % on a programmatic Selection write across MATLAB releases,
            % so we invoke onTableRowSelected explicitly.
            try
                if size(rows, 1) > 0 && ~isempty(app.BackendTable) ...
                        && isvalid(app.BackendTable)
                    app.BackendTable.Selection = 1;
                    obj.onTableRowSelected();
                end
            catch ME
                Logger.debug('BackendsViewModel', ...
                    'auto-select row 1: %s', ME.message);
            end

            % C2.B1 — Pre-fetch calibration history for every backend so
            % the Telemetry tab strip lights up instantly on row select.
            % Batched via AsyncRunner.runMany: a single shared poller
            % covers all N fetches instead of one 50 ms timer per
            % backend. The pre-batch path looped AsyncRunner.run per
            % row, which spawned N concurrent futures + N independent
            % polling timers — for ~20 IBM backends that flooded the
            % background pool and kept the UI thread ticking at
            % 400 Hz of timer overhead for ~30 s after every visit,
            % which the user perceived as app-wide sluggishness.
            obj.kickCalibrationHistoryBatch(app, rows);
        end

        function kickCalibrationHistoryBatch(obj, app, rows)
            % Fire all per-backend /calibration_history fetches as ONE
            % AsyncRunner.runMany batch. Per-row failures are swallowed
            % via safeCalibrationFetch so one backend returning 4xx
            % cannot poison the entire batch (runMany surfaces only
            % the first error to onError and discards every other
            % result, so we wrap each work fn defensively).
            if ~app.State.isAuthenticated(); return; end
            n = size(rows, 1);
            if n == 0; return; end
            names = cell(1, n);
            works = cell(1, n);
            k = 0;
            svc   = app.BackendSvc;
            token = app.State.authToken;
            for r = 1:n
                bn = char(string(rows{r, 2}));
                if isempty(bn); continue; end
                k = k + 1;
                names{k} = bn;
                works{k} = @() BackendsViewModel.safeCalibrationFetch(svc, bn, 7, token);
            end
            if k == 0; return; end
            names = names(1:k); works = works(1:k);
            AsyncRunner.runMany(works, ...
                @(results) obj.onCalibrationHistoryBatchLoaded(app, names, results), ...
                @(ME) Logger.debug('BackendsViewModel', ...
                    'calibration-history batch: %s', ME.message));
        end

        function onCalibrationHistoryBatchLoaded(obj, app, names, results)
            % Land every per-backend response into the cache in a
            % single pass, then repaint the active row (if any). One
            % paint at the end of the batch instead of N incremental
            % paints — same data, no flicker.
            if isempty(app.CalibrationHistoryCache)
                app.CalibrationHistoryCache = struct();
            end
            for i = 1:numel(names)
                if isempty(results{i}); continue; end
                safeKey = matlab.lang.makeValidName(char(names{i}));
                app.CalibrationHistoryCache.(safeKey) = results{i};
            end
            try
                row = obj.getSelectedRow();
                if row > 0
                    selName = char(string(app.BackendTable.Data{row, 2}));
                    safeKey = matlab.lang.makeValidName(selName);
                    if isfield(app.CalibrationHistoryCache, safeKey)
                        obj.populateTelemetryPanel(app, selName);
                    end
                end
            catch ME
                Logger.debug('BackendsViewModel', ...
                    'batch-arrival paint skipped: %s', ME.message);
            end
        end

        % ── C2.B1 — Calibration history + Telemetry panel ─────────────────

        function fetchCalibrationHistory(obj, backendName, days)
            % Async dispatch of GET /api/backends/{name}/calibration_history.
            % Result lands in onCalibrationHistoryLoaded which caches
            % the response on app.CalibrationHistoryCache for fast
            % paints when the Telemetry tab strip needs to render.
            app   = obj.App;
            if ~app.State.isAuthenticated(); return; end
            if isempty(backendName); return; end
            if nargin < 3 || isempty(days); days = 7; end
            svc   = app.BackendSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getCalibrationHistory(backendName, days, token), ...
                @(data) obj.onCalibrationHistoryLoaded(app, backendName, data), ...
                @(ME)   Logger.debug('BackendsViewModel', ...
                            'getCalibrationHistory(%s): %s', char(backendName), ME.message));
        end

        function onCalibrationHistoryLoaded(obj, app, backendName, data)
            % Cache the response keyed by backend name. If the user
            % already has this backend selected when the response
            % lands, paint the Telemetry panel immediately.
            if isempty(app.CalibrationHistoryCache)
                app.CalibrationHistoryCache = struct();
            end
            safeKey = matlab.lang.makeValidName(char(backendName));
            app.CalibrationHistoryCache.(safeKey) = data;
            % If this is the currently-selected backend, repaint now.
            try
                row = obj.getSelectedRow();
                if row > 0
                    selName = char(string(app.BackendTable.Data{row, 2}));
                    if strcmp(selName, char(backendName))
                        obj.populateTelemetryPanel(app, backendName);
                    end
                end
            catch ME
                Logger.debug('BackendsViewModel', ...
                    'history-arrival paint skipped: %s', ME.message);
            end
        end

        function onTableRowSelected(obj)
            % Wired to BackendTable.CellSelectionChangedFcn so the
            % Telemetry tab strip drills into the clicked row.
            app = obj.App;
            row = obj.getSelectedRow();
            if row == 0; return; end
            selName = char(string(app.BackendTable.Data{row, 2}));
            if isempty(selName); return; end
            % Reflect the selected backend in the Overview KPI strip's
            % 4th card so the user can always see which one is being
            % drilled into across all four tabs.
            try
                if isprop(app, 'OverviewKpiLabels') && ...
                        ~isempty(app.OverviewKpiLabels) && ...
                        numel(app.OverviewKpiLabels) >= 4 && ...
                        ~isempty(app.OverviewKpiLabels{4}) && ...
                        isvalid(app.OverviewKpiLabels{4})
                    app.OverviewKpiLabels{4}.Text = selName;
                    app.OverviewKpiLabels{4}.FontSize = 12;  % name strings are longer than numbers
                end
            catch ME
                Logger.debug('BackendsViewModel', ...
                    'overview KPI selected-name update: %s', ME.message);
            end
            safeKey = matlab.lang.makeValidName(selName);
            if isstruct(app.CalibrationHistoryCache) && ...
                    isfield(app.CalibrationHistoryCache, safeKey)
                obj.populateTelemetryPanel(app, selName);
            else
                % Cache miss — dispatch; onCalibrationHistoryLoaded
                % will paint once the response lands.
                obj.fetchCalibrationHistory(selName, 7);
            end
        end

        function populateOverviewKpis(~, app, rows)
            % Fill the Telemetry > Overview KPI strip cards: total
            % backends, operational count, max qubit width, and the
            % currently-selected backend (last card is repopulated by
            % onTableRowSelected when the user picks a row). Defensive
            % against missing handles and unparseable cell contents so a
            % single bad row never blanks the whole strip.
            if ~isprop(app, 'OverviewKpiLabels'); return; end
            if isempty(app.OverviewKpiLabels) || numel(app.OverviewKpiLabels) < 4
                return;
            end
            n = size(rows, 1);
            operational = 0;
            maxQubits = 0;
            for r = 1:n
                try
                    qb = rows{r, 3};   % col 3 = num_qubits per JsonHelper.backendsToRows
                    if isnumeric(qb) && isfinite(qb) && qb > maxQubits
                        maxQubits = qb;
                    elseif ischar(qb) || isstring(qb)
                        qbn = str2double(char(string(qb)));
                        if ~isnan(qbn) && qbn > maxQubits; maxQubits = qbn; end
                    end
                    st = lower(char(string(rows{r, 4})));
                    if contains(st, 'operat') || contains(st, 'online') || ...
                            contains(st, 'active') || contains(st, 'available') || ...
                            contains(st, char(9989)) || strcmp(st, 'ok')
                        operational = operational + 1;
                    end
                catch
                end
            end
            try; app.OverviewKpiLabels{1}.Text = sprintf('%d', n); catch; end
            try; app.OverviewKpiLabels{2}.Text = sprintf('%d / %d', operational, n); catch; end
            try; app.OverviewKpiLabels{3}.Text = sprintf('%d', round(maxQubits)); catch; end
            % Card 4 is repopulated by onTableRowSelected with the
            % currently-selected backend name. Reset to em-dash here so
            % a refresh-without-selection shows a clean placeholder.
            try
                app.OverviewKpiLabels{4}.Text = char(8212);
                app.OverviewKpiLabels{4}.FontSize = 16;
            catch
            end
        end

        function updateLatestCalibrationKpi(~, app)
            % Optional helper to surface "most recent calibration" if a
            % future revision wants to expose it in the Overview strip.
            % Currently unused because KPI 4 holds the selected backend
            % name (more interactive). Kept as a single-source helper
            % so toggling the KPI's role is a one-line wire change.
            if ~isprop(app, 'OverviewKpiLabels'); return; end
            if isempty(app.OverviewKpiLabels) || numel(app.OverviewKpiLabels) < 4
                return;
            end
            cache = app.CalibrationHistoryCache;
            if ~isstruct(cache); return; end
            names = fieldnames(cache);
            latest = NaT('TimeZone', 'UTC');
            for i = 1:numel(names)
                try
                    recs = JsonHelper.pick(cache.(names{i}), {'records'}, []);
                    for j = 1:numel(recs)
                        if iscell(recs); r = recs{j}; else; r = recs(j); end
                        t = datetime( ...
                            strrep(char(r.sampled_at), 'Z', '+00:00'), ...
                            'InputFormat', 'yyyy-MM-dd''T''HH:mm:ssXXX', ...
                            'TimeZone', 'UTC');
                        if isnat(latest) || t > latest; latest = t; end
                    end
                catch
                end
            end
            if isnat(latest); return; end
            try
                ageHours = hours(datetime('now', 'TimeZone', 'UTC') - latest);
                if ageHours < 1
                    txt = '< 1 hr ago';
                elseif ageHours < 24
                    txt = sprintf('%.0f hr ago', ageHours);
                else
                    txt = sprintf('%.1f day ago', ageHours / 24);
                end
                app.OverviewKpiLabels{4}.Text = txt;
            catch
            end
        end

        function populateTelemetryPanel(obj, app, backendName)
            safeKey = matlab.lang.makeValidName(char(backendName));
            if isempty(app.CalibrationHistoryCache); return; end
            if ~isfield(app.CalibrationHistoryCache, safeKey); return; end
            data = app.CalibrationHistoryCache.(safeKey);
            obj.paintTelemetryPerQubitHeatGrid(app, data);
            obj.paintTelemetryHistoryCharts(app, data);
        end

        function paintTelemetryPerQubitHeatGrid(~, app, data)
            if isempty(app.TelemetryPerQubitGrid) || ...
                    ~isvalid(app.TelemetryPerQubitGrid)
                return;
            end
            parent = app.TelemetryPerQubitGrid;
            delete(parent.Children);

            % Empty-state: no data yet → centered messaging across the
            % whole grid instead of a wall of blank cells. Distinguishes
            % "still loading" from "no row selected" via the message.
            recs = [];
            try; recs = data.records; catch; end
            if isempty(recs)
                parent.RowHeight   = {'1x'};
                parent.ColumnWidth = {'1x'};
                empty = uilabel(parent, ...
                    'Text', Labels.get('backends_perqubit_empty', ...
                        'No per-qubit calibration data available for this backend.'), ...
                    'FontSize', 11, ...
                    'FontColor', Theme.COLOR_MUTED, ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'center', ...
                    'WordWrap', 'on');
                empty.Layout.Row = 1; empty.Layout.Column = 1;
                return;
            end

            % Data-layout: 6 rows × 17 cols (col 1 = metric row labels,
            % cols 2-17 = up to 16 qubits). Wider col 1 so labels like
            % "Readout err" / "Gate err" fit without truncation.
            parent.RowHeight   = repmat({22}, 1, 6);
            parent.ColumnWidth = [{90}, repmat({60}, 1, 16)];

            metrics      = {'qubit', 'T1', 'T2', 'gate_err', 'rd_err', '2Q_err'};
            rowLabels    = {'',      'T1', 'T2', 'Gate err', 'Readout err', '2Q err'};

            if iscell(recs); n = numel(recs); else; n = numel(recs); end
            per_qubit = containers.Map('KeyType', 'int32', 'ValueType', 'any');
            for i = 1:n
                if iscell(recs); r = recs{i}; else; r = recs(i); end
                qi = int32(JsonHelper.pickNumeric(r, 'qubit_index', -1));
                if qi < 0; continue; end
                if ~isKey(per_qubit, qi)
                    per_qubit(qi) = r;  % first wins (DESC sorted = newest)
                end
            end
            qubits = sort(cell2mat(keys(per_qubit)));

            % Column 1 — metric row labels. Right-aligned so the value
            % cells immediately to the right read as the "value of this
            % metric" without ambiguity.
            for m = 2:numel(metrics)
                rl = uilabel(parent, 'Text', rowLabels{m}, ...
                    'FontSize', 10, 'FontWeight', 'bold', ...
                    'FontColor', Theme.COLOR_MUTED, ...
                    'HorizontalAlignment', 'right', ...
                    'VerticalAlignment', 'center');
                rl.Layout.Row = m; rl.Layout.Column = 1;
            end

            % Columns 2-17 — per-qubit data. Row 1 is the qubit header.
            for c = 1:min(numel(qubits), 16)
                hdr = uilabel(parent, 'Text', sprintf('q[%d]', qubits(c)), ...
                              'FontSize', 10, 'FontWeight', 'bold', ...
                              'FontColor', Theme.COLOR_LABEL, ...
                              'HorizontalAlignment', 'center');
                hdr.Layout.Row = 1; hdr.Layout.Column = c + 1;
                for m = 2:numel(metrics)
                    r = per_qubit(qubits(c));
                    switch metrics{m}
                        case 'T1';        v = JsonHelper.pickNumeric(r, 'T1', NaN);
                        case 'T2';        v = JsonHelper.pickNumeric(r, 'T2', NaN);
                        case 'gate_err';  v = JsonHelper.pickNumeric(r, 'gate_error', NaN);
                        case 'rd_err';    v = JsonHelper.pickNumeric(r, 'readout_error', NaN);
                        case '2Q_err';    v = JsonHelper.pickNumeric(r, 'two_q_error', NaN);
                    end
                    color = BackendsViewModel.healthColor(metrics{m}, v);
                    lbl = uilabel(parent, ...
                        'Text', BackendsViewModel.fmtMetric(metrics{m}, v), ...
                        'FontSize', 10, 'BackgroundColor', color, ...
                        'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'center');
                    lbl.Layout.Row = m; lbl.Layout.Column = c + 1;
                end
            end
        end

        function paintTelemetryHistoryCharts(~, app, data)
            if isempty(app.TelemetryHistoryAxes) || ...
                    numel(app.TelemetryHistoryAxes) < 3
                return;
            end
            fields   = {'T1', 'T2', 'two_q_error'};
            titles   = {'T1 coherence (µs)', 'T2 coherence (µs)', '2Q gate error'};
            % Scale factor per field — T1/T2 are in seconds in the
            % backend payload but the chart title advertises microseconds,
            % so multiply for display.
            scales   = [1e6, 1e6, 1.0];

            recs = [];
            try; recs = data.records; catch; end

            % Empty-state: paint a centered "no data" annotation in
            % each of the 3 axes instead of leaving them showing the
            % pre-styled grid with no curve. Keeps the panel from
            % looking broken on a backend that has no recorded history.
            if isempty(recs)
                for k = 1:3
                    ax = app.TelemetryHistoryAxes{k};
                    if isempty(ax) || ~isvalid(ax); continue; end
                    cla(ax);
                    ax.Title.String = titles{k};
                    ax.XLim = [0 1]; ax.YLim = [0 1];
                    text(ax, 0.5, 0.5, Labels.get('backends_history_empty', ...
                        'No calibration history available for this backend.'), ...
                        'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'middle', ...
                        'FontSize', 10, ...
                        'Color', Theme.COLOR_MUTED, ...
                        'HitTest', 'off', 'PickableParts', 'none');
                end
                return;
            end

            if iscell(recs); n = numel(recs); else; n = numel(recs); end
            for k = 1:3
                ax = app.TelemetryHistoryAxes{k};
                if isempty(ax) || ~isvalid(ax); continue; end
                cla(ax);
                ax.Title.String = titles{k};
                ts = NaT(1, n); vals = nan(1, n);
                for i = 1:n
                    if iscell(recs); r = recs{i}; else; r = recs(i); end
                    try
                        ts(i) = datetime(strrep(char(r.sampled_at), 'Z', '+00:00'), ...
                                         'InputFormat', 'yyyy-MM-dd''T''HH:mm:ssXXX', ...
                                         'TimeZone', 'UTC');
                    catch; continue; end
                    vals(i) = JsonHelper.pickNumeric(r, fields{k}, NaN) * scales(k);
                end
                valid = ~isnat(ts) & ~isnan(vals);
                if any(valid)
                    [tsS, idx] = sort(ts(valid));
                    vS = vals(valid); vS = vS(idx);
                    plot(ax, tsS, vS, '-o', ...
                        'Color', Theme.COLOR_PRIMARY, ...
                        'MarkerFaceColor', Theme.COLOR_PRIMARY, ...
                        'MarkerEdgeColor', Theme.COLOR_PRIMARY, ...
                        'MarkerSize', 3.5, ...
                        'LineWidth', 1.4);
                    ax.XGrid = 'on'; ax.YGrid = 'on';
                    try
                        ax.XAxis.TickLabelFormat = 'MMM d';
                    catch
                    end
                else
                    % Records exist but none parsed cleanly for this
                    % field — annotate so the panel doesn't look broken.
                    ax.XLim = [0 1]; ax.YLim = [0 1];
                    text(ax, 0.5, 0.5, Labels.get('backends_history_empty', ...
                        'No calibration history available for this backend.'), ...
                        'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'middle', ...
                        'FontSize', 10, 'Color', Theme.COLOR_MUTED, ...
                        'HitTest', 'off', 'PickableParts', 'none');
                end
            end
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
            app.showLoading(Labels.get('loading_backends_check_runtime', 'Checking IBM runtime status...'));
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

        % ── Topology tab — coupling-map graph ────────────────────────────
        function onTelemetryTabChanged(obj, evt)
            % Dispatched by the telemetry uitabgroup's SelectionChangedFcn.
            % Only the Topology tab needs eager paint — the other three
            % are populated by populateTelemetryPanel on row select.
            try
                titleStr = char(string(evt.NewValue.Title));
            catch
                return;
            end
            if ~strcmp(titleStr, Labels.get('backends_topology_tab_title'))
                return;
            end
            app = obj.App;
            row = obj.getSelectedRow();
            if row == 0
                obj.paintTopologyPlaceholder(Labels.get('backends_topology_no_selection'));
                return;
            end
            backendName = char(string(app.BackendTable.Data{row, 2}));
            if isempty(backendName); return; end
            safeKey = matlab.lang.makeValidName(backendName);
            if isstruct(app.TopologyCache) && isfield(app.TopologyCache, safeKey)
                obj.paintTopology(backendName);
            else
                obj.fetchTopology(backendName);
            end
        end

        function fetchTopology(obj, backendName)
            % Dispatch GET /api/backends/{name}/topology asynchronously.
            obj.paintTopologyPlaceholder(Labels.get('backends_topology_loading'));
            app = obj.App;
            svc = app.Services.backendService;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getTopology(backendName, token), ...
                @(data) obj.onTopologyLoaded(backendName, data), ...
                @(ME)   obj.onTopologyError(backendName, ME));
        end

        function onTopologyLoaded(obj, backendName, data)
            app = obj.App;
            if isempty(app.TopologyCache); app.TopologyCache = struct(); end
            safeKey = matlab.lang.makeValidName(char(backendName));
            app.TopologyCache.(safeKey) = data;
            % Repaint only if user is still on the Topology tab AND on
            % this backend (don't fight a stale fetch).
            try
                row = obj.getSelectedRow();
                if row == 0; return; end
                selName = char(string(app.BackendTable.Data{row, 2}));
                if strcmp(selName, char(backendName))
                    obj.paintTopology(backendName);
                end
            catch ME
                Logger.debug('BackendsViewModel', ...
                    'topology arrival paint skipped: %s', ME.message);
            end
        end

        function onTopologyError(obj, backendName, ME)
            obj.paintTopologyPlaceholder(sprintf( ...
                Labels.get('backends_topology_fetch_err'), ME.message));
            Logger.warn('BackendsViewModel', ...
                'getTopology failed for %s: %s', char(backendName), ME.message);
        end

        function paintTopology(obj, backendName)
            app = obj.App;
            if isempty(app.TopologyAxes) || ~isvalid(app.TopologyAxes); return; end
            ax = app.TopologyAxes;
            cla(ax);
            ax.XLim = [-1.1 1.1]; ax.YLim = [-1.1 1.1];

            safeKey = matlab.lang.makeValidName(char(backendName));
            data = app.TopologyCache.(safeKey);
            cm = JsonHelper.pick(data, {'coupling_map', 'couplingMap'}, []);
            n  = JsonHelper.pickNumeric(data, 'num_qubits', NaN);
            if ~isfinite(n)
                n = JsonHelper.pickNumeric(data, 'n_qubits', NaN);
            end

            if isempty(cm)
                obj.paintTopologyPlaceholder(Labels.get('backends_topology_unavailable'));
                return;
            end

            edges = BackendsViewModel.normalizeCouplingMap(cm);
            if isempty(edges)
                obj.paintTopologyPlaceholder(Labels.get('backends_topology_unavailable'));
                return;
            end

            % Cap node count: include any qubit referenced in coupling_map
            % even if num_qubits is missing.
            maxIdx = max(edges(:));
            if ~isfinite(n); n = maxIdx; end
            n = max(double(n), maxIdx);

            s = edges(:, 1); t = edges(:, 2);
            G = graph(s, t, [], double(n));

            try
                gp = plot(ax, G, 'Layout', 'force', ...
                    'NodeFontSize', 7, ...
                    'NodeFontColor', Theme.COLOR_HEADING, ...
                    'EdgeColor', Theme.COLOR_DIVIDER, ...
                    'EdgeAlpha', 0.6, ...
                    'LineWidth', 0.8, ...
                    'MarkerSize', 6);
            catch ME
                obj.paintTopologyPlaceholder(sprintf( ...
                    'Graph render failed: %s', ME.message));
                return;
            end

            healthRgb = obj.computeQubitColors(backendName, double(n));
            gp.NodeColor = healthRgb;

            if n <= 64
                gp.NodeLabel = arrayfun(@(q) sprintf('%d', q-1), ...
                    1:double(n), 'UniformOutput', false);
            else
                gp.NodeLabel = repmat({''}, 1, double(n));
            end

            gp.ButtonDownFcn = @(src,evt) obj.onTopologyNodeClicked(src, evt, backendName);

            metaLbl = app.TopologyInfoLbl.UserData;
            if ~isempty(metaLbl) && isvalid(metaLbl)
                metaLbl.Text = sprintf( ...
                    Labels.get('backends_topology_meta_fmt'), ...
                    char(backendName), double(n), size(edges, 1));
            end
            app.TopologyInfoLbl.Text = Labels.get('backends_topology_no_selection');
        end

        function onTopologyNodeClicked(obj, gp, evt, backendName)
            try
                ip = evt.IntersectionPoint;
                xs = gp.XData; ys = gp.YData;
            catch
                return;
            end
            d = (xs - ip(1)).^2 + (ys - ip(2)).^2;
            [~, idx] = min(d);
            if isempty(idx); return; end
            qubit = idx - 1;
            app = obj.App;
            safeKey = matlab.lang.makeValidName(char(backendName));
            calRecord = [];
            if isstruct(app.CalibrationHistoryCache) && ...
                    isfield(app.CalibrationHistoryCache, safeKey)
                calData = app.CalibrationHistoryCache.(safeKey);
                calRecord = BackendsViewModel.findLatestCalForQubit(calData, qubit);
            end
            topoData = app.TopologyCache.(safeKey);
            cm = JsonHelper.pick(topoData, {'coupling_map', 'couplingMap'}, []);
            edges = BackendsViewModel.normalizeCouplingMap(cm);
            if isempty(edges)
                neighbours = [];
            else
                lhs = edges(edges(:,1) == qubit+1, 2) - 1;
                rhs = edges(edges(:,2) == qubit+1, 1) - 1;
                neighbours = unique([lhs; rhs]);
            end
            basisGates = JsonHelper.pick(topoData, {'basis_gates', 'basisGates'}, {});
            txt = BackendsViewModel.formatTopologyDetail(qubit, calRecord, neighbours, basisGates);
            app.TopologyInfoLbl.Text = txt;
        end

        function paintTopologyPlaceholder(obj, msg)
            app = obj.App;
            if isempty(app.TopologyAxes) || ~isvalid(app.TopologyAxes); return; end
            ax = app.TopologyAxes;
            cla(ax);
            ax.XLim = [-1 1]; ax.YLim = [-1 1];
            text(ax, 0, 0, char(msg), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontSize', 12, 'Color', Theme.COLOR_MUTED);
            metaLbl = app.TopologyInfoLbl.UserData;
            if ~isempty(metaLbl) && isvalid(metaLbl)
                metaLbl.Text = '';
            end
            app.TopologyInfoLbl.Text = '';
        end

        function rgb = computeQubitColors(obj, backendName, n)
            % Returns n×3 RGB matrix. If calibration data is missing, use
            % a neutral grey so the graph still renders.
            rgb = repmat([0.55 0.58 0.62], n, 1);
            app = obj.App;
            safeKey = matlab.lang.makeValidName(char(backendName));
            if ~isstruct(app.CalibrationHistoryCache) || ...
                    ~isfield(app.CalibrationHistoryCache, safeKey)
                return;
            end
            calData = app.CalibrationHistoryCache.(safeKey);
            for q = 0:n-1
                rec = BackendsViewModel.findLatestCalForQubit(calData, q);
                if ~isempty(rec)
                    rgb(q+1, :) = BackendsViewModel.qubitHealthScore(rec);
                end
            end
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
            % Phase 2.4: capture the operator's chosen QEM ladder level
            % once per pool so every per-backend payload below carries
            % it. Without this, a multi-backend pool submit silently
            % defaulted to Standard server-side regardless of what the
            % operator picked in Settings → "Default mitigation level".
            mitigLvl = [];
            try
                lvl = double(app.State.preferredMitigationLevel);
                if isfinite(lvl); mitigLvl = int32(lvl); end
            catch
            end
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
                if ~isempty(mitigLvl)
                    payload.mitigation_level = mitigLvl;
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
                % Silent return — every caller already checks `row == 0`.
                % A modal uialert here was firing spuriously on every
                % SelectionChangedFcn callback (the modern uitable
                % triggers SelectionChangedFcn on deselect too) and was
                % awkward to dismiss. Action buttons that genuinely need
                % to warn the user about an empty selection can call
                % app.setStatus(app.BackendStatusArea, ...) directly.
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

    methods (Static)
        % Static helpers — access widened from `private` to default
        % (public) so QecSimulationViewModel and
        % QecVisualizationViewModel can reuse `fetchBackends` to get
        % the same circuit-enriched backend list (with qubit counts)
        % that the Backends screen itself uses. The other helpers in
        % this block become public too; they're still effectively
        % internal to the Backends flow, but widening their
        % visibility avoids a second copy of the fetch fallback
        % logic in each consumer VM.
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

        % C2.B1 — health-graded background color for the Per-Qubit
        % heat-grid cells. Thresholds match the Quantum-Insider 2026
        % dashboard study (>95% Optimal/green, 70-95% Watch/amber,
        % <70% Critical/red), with metric-appropriate cutoffs.
        function c = healthColor(metric, v)
            c = Theme.COLOR_CARD;
            if isnan(v); return; end
            switch metric
                case {'gate_err','rd_err','2Q_err'}
                    if v < 5e-3;       c = [0.85 0.95 0.85];
                    elseif v < 2e-2;   c = [1.00 0.95 0.80];
                    else;              c = [0.99 0.83 0.83];
                    end
                case 'T1'
                    if v > 1e-4;       c = [0.85 0.95 0.85];
                    elseif v > 5e-5;   c = [1.00 0.95 0.80];
                    else;              c = [0.99 0.83 0.83];
                    end
                case 'T2'
                    if v > 7e-5;       c = [0.85 0.95 0.85];
                    elseif v > 3e-5;   c = [1.00 0.95 0.80];
                    else;              c = [0.99 0.83 0.83];
                    end
            end
        end

        function out = safeCalibrationFetch(svc, backendName, days, token)
            % Try/catch wrapper for AsyncRunner.runMany batch members
            % — one backend's HTTP failure (404 / 5xx / network blip)
            % must NOT discard every other result via runMany's
            % first-error-wins semantics. Empty out signals "skip" to
            % onCalibrationHistoryBatchLoaded.
            try
                out = svc.getCalibrationHistory(backendName, days, token);
            catch ME
                Logger.debug('BackendsViewModel', ...
                    'calibration-history skip (%s): %s', char(backendName), ME.message);
                out = [];
            end
        end

        % C2.B1 — metric-aware cell text formatting for the heat-grid.
        function s = fmtMetric(metric, v)
            if isnan(v); s = char(8212); return; end
            switch metric
                case 'T1';        s = sprintf('%.0f us', v * 1e6);
                case 'T2';        s = sprintf('%.0f us', v * 1e6);
                case 'gate_err';  s = sprintf('%.1e', v);
                case 'rd_err';    s = sprintf('%.1e', v);
                case '2Q_err';    s = sprintf('%.1e', v);
                otherwise;        s = sprintf('%g', v);
            end
        end

        % ── Topology helpers ─────────────────────────────────────────────
        function edges = normalizeCouplingMap(cm)
            % Accepts cell-of-pairs ({{0,1},{1,2},...}), N×2 numeric, or
            % cell-of-2-element-arrays. Returns a deduplicated 1-based
            % undirected edge list (M×2 numeric, src < dst per row).
            edges = [];
            if isempty(cm); return; end
            if isnumeric(cm) && size(cm, 2) == 2
                pairs = double(cm);
            elseif iscell(cm)
                pairs = zeros(numel(cm), 2);
                for i = 1:numel(cm)
                    p = cm{i};
                    if iscell(p) && numel(p) == 2
                        pairs(i, :) = [double(p{1}), double(p{2})];
                    elseif isnumeric(p) && numel(p) == 2
                        pairs(i, :) = double(p(:))';
                    else
                        return;  % unparseable shape
                    end
                end
            else
                return;
            end
            % Convert to 1-based, undirected (sort each row), dedupe.
            pairs = pairs + 1;
            pairs = unique(sort(pairs, 2), 'rows');
            % Drop self-loops just in case.
            pairs(pairs(:,1) == pairs(:,2), :) = [];
            edges = pairs;
        end

        function rec = findLatestCalForQubit(calData, qubit)
            rec = [];
            if isempty(calData); return; end
            recs = JsonHelper.pick(calData, {'records'}, []);
            if isempty(recs); return; end
            n = numel(recs);
            for i = 1:n
                if iscell(recs); r = recs{i}; else; r = recs(i); end
                qi = JsonHelper.pickNumeric(r, 'qubit_index', NaN);
                if isfinite(qi) && qi == qubit
                    rec = r;  % first wins (DESC sorted = newest)
                    return;
                end
            end
        end

        function rgb = qubitHealthScore(rec)
            % Composite green→amber→red based on T1, T2, and gate error.
            % Worst metric drives the colour so a single bad axis pulls
            % the qubit toward the red end.
            rgb = [0.85 0.95 0.85];
            t1 = JsonHelper.pickNumeric(rec, 'T1', NaN);
            t2 = JsonHelper.pickNumeric(rec, 'T2', NaN);
            ge = JsonHelper.pickNumeric(rec, 'gate_error', NaN);
            grades = zeros(1, 3);  % 0 = good, 1 = watch, 2 = critical
            if isfinite(t1)
                if t1 > 1e-4;     grades(1) = 0;
                elseif t1 > 5e-5; grades(1) = 1;
                else;             grades(1) = 2; end
            end
            if isfinite(t2)
                if t2 > 7e-5;     grades(2) = 0;
                elseif t2 > 3e-5; grades(2) = 1;
                else;             grades(2) = 2; end
            end
            if isfinite(ge)
                if ge < 5e-3;     grades(3) = 0;
                elseif ge < 2e-2; grades(3) = 1;
                else;             grades(3) = 2; end
            end
            worst = max(grades);
            switch worst
                case 0; rgb = [0.30 0.70 0.40];   % healthy green
                case 1; rgb = [0.95 0.70 0.30];   % watch amber
                case 2; rgb = [0.85 0.30 0.30];   % critical red
            end
        end

        function txt = formatTopologyDetail(qubit, rec, neighbours, basisGates)
            lines = {sprintf(Labels.get('backends_topology_qubit_fmt'), qubit)};
            if ~isempty(rec)
                t1 = JsonHelper.pickNumeric(rec, 'T1', NaN);
                t2 = JsonHelper.pickNumeric(rec, 'T2', NaN);
                ge = JsonHelper.pickNumeric(rec, 'gate_error', NaN);
                re = JsonHelper.pickNumeric(rec, 'readout_error', NaN);
                lines{end+1} = sprintf('T1: %s', BackendsViewModel.fmtMetric('T1', t1));
                lines{end+1} = sprintf('T2: %s', BackendsViewModel.fmtMetric('T2', t2));
                lines{end+1} = sprintf('Gate err: %s', BackendsViewModel.fmtMetric('gate_err', ge));
                lines{end+1} = sprintf('Readout err: %s', BackendsViewModel.fmtMetric('rd_err', re));
            else
                lines{end+1} = '(no calibration data)';
            end
            if ~isempty(neighbours)
                lines{end+1} = sprintf('%s: %s', ...
                    Labels.get('backends_topology_neighbors'), ...
                    strjoin(arrayfun(@(q) sprintf('q[%d]', q), neighbours, ...
                        'UniformOutput', false), ', '));
            end
            if ~isempty(basisGates)
                if iscell(basisGates)
                    bg = strjoin(cellfun(@char, basisGates, 'UniformOutput', false), ', ');
                else
                    bg = char(string(basisGates));
                end
                lines{end+1} = sprintf('%s: %s', ...
                    Labels.get('backends_topology_basis_gates'), bg);
            end
            txt = strjoin(lines, sprintf('\n'));
        end
    end
end
