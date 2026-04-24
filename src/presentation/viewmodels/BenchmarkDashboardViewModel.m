classdef BenchmarkDashboardViewModel < handle
    % BenchmarkDashboardViewModel  Callbacks for the Benchmark Dashboard tab.
    %
    %   Fetches volumetric data, system metrics, scorecard, prediction
    %   calibration, and benchmark regression from the API and renders
    %   the corresponding charts on the dashboard.
    %
    %   Each refresh clears every panel first, then applies whatever the
    %   server returned — so a backend change always either shows the new
    %   data or an explicit empty-state with a reason, never the previous
    %   backend's content. The response `source` / `*_considered` counts are
    %   surfaced in the toolbar and status line so the operator can tell
    %   whether "--" means "no data on the backend" vs. "IBM Runtime not
    %   configured" vs. "no jobs on this project yet".

    properties
        App  % Reference to QTAUWorkbenchApp
        LastRefresh = []
        LastResults = struct()  % last fetched results (for Export Data)
    end

    methods
        function obj = BenchmarkDashboardViewModel(app)
            obj.App = app;
        end

        % ── Entry hook (called on screen activation) ─────────────────────
        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            obj.loadBackends();
            obj.onRefreshAll();
        end

        % ── Refresh All ──────────────────────────────────────────────────
        function onRefreshAll(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_login_required', 'Please login first.'), 'Auth Required');
                return;
            end

            % Ensure the backend dropdown is populated before a refresh —
            % protects the Refresh All button when the user skips onEnter.
            try
                items = app.BenchmarkBackendDropdown.Items;
                if isempty(items) || (numel(items) == 1 && strcmp(items{1}, '(none)'))
                    obj.loadBackends();
                end
            catch ME
                Logger.debug('BenchmarkDashboardViewModel', 'dropdown guard: %s', ME.message);
            end

            app.showLoading();

            % Clear every panel immediately so a slow backend can never leave
            % stale content from the previously-selected backend on screen.
            obj.resetAllPanels();
            obj.setStatusLine('Loading…');
            obj.setSourceBadge('', Theme.COLOR_MUTED);

            % Capture parameters on UI thread before dispatching
            backendName = '';
            try backendName = char(app.BenchmarkBackendDropdown.Value); catch; end
            if isempty(backendName); backendName = char(app.State.selectedBackend); end
            pid    = '';
            if app.State.hasProject(); pid = char(app.State.currentProjectId); end
            % Services expect the raw bearer token — FastAPIClient.authHeaders
            % prepends the "Bearer " prefix itself. Passing bearerHeader()
            % here produced "Bearer Bearer <token>" and every call 401ed.
            token = app.State.authToken;
            svc   = app.BenchmarkSvc;

            % Run all 5 API fetches off the UI thread in one async task
            AsyncRunner.run( ...
                @() BenchmarkDashboardViewModel.fetchAllData(svc, backendName, pid, token), ...
                @(results) obj.applyAllData(app, backendName, results), ...
                @(ME)      obj.onRefreshError(app, ME));
        end

        % ── Backend dropdown population ──────────────────────────────────
        function loadBackends(obj)
            % Populate BenchmarkBackendDropdown via BackendService with a
            % 3-tier fallback, mirroring BenchmarkViewModel.loadBackends:
            %   1. list scoped to the currently-selected circuit
            %   2. list for the first circuit in the project
            %   3. basic list without circuit filter
            app = obj.App;
            token = app.State.authToken;

            cid = '';
            if app.State.hasCircuit(); cid = char(app.State.selectedCircuitId); end
            if ~isempty(cid) && strlength(cid) > 0
                try
                    data = app.BackendSvc.listBackends(token, cid);
                    if obj.hasBackendData(data)
                        obj.populateBackendDropdown(data);
                        return;
                    end
                catch ME
                    Logger.debug('BenchmarkDashboardViewModel', 'loadBackends circuit: %s', ME.message);
                end
            end

            try
                circList = app.CircuitSvc.listCircuits(token);
                items = JsonHelper.extractList(circList, 'circuits');
                if ~isempty(items)
                    fallbackCid = char(JsonHelper.pick(items(1), {'circuit_id','id'}));
                    if ~isempty(fallbackCid) && strlength(fallbackCid) > 0
                        data = app.BackendSvc.listBackends(token, fallbackCid);
                        if obj.hasBackendData(data)
                            obj.populateBackendDropdown(data);
                            return;
                        end
                    end
                end
            catch ME
                Logger.debug('BenchmarkDashboardViewModel', 'loadBackends fallback circuit: %s', ME.message);
            end

            try
                data = app.BackendSvc.listBackends(token, '');
                if obj.hasBackendData(data)
                    obj.populateBackendDropdown(data);
                    return;
                end
            catch ME
                Logger.debug('BenchmarkDashboardViewModel', 'loadBackends basic list: %s', ME.message);
            end

            app.BenchmarkBackendDropdown.Items     = {'(no backends)'};
            app.BenchmarkBackendDropdown.ItemsData = {''};
            app.BenchmarkBackendDropdown.Value     = '';
            app.logEvent('WARN', 'No backends found for benchmark dashboard dropdown');
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
            app.BenchmarkBackendDropdown.Items     = names;
            app.BenchmarkBackendDropdown.ItemsData = names;

            if strlength(app.State.selectedBackend) > 0
                match = find(strcmp(names, char(app.State.selectedBackend)), 1);
                if ~isempty(match)
                    app.BenchmarkBackendDropdown.Value = names{match};
                end
            end
            app.logEvent('LOAD', sprintf('Loaded %d backends into benchmark dashboard dropdown', n));
        end

        % ── Backend dropdown change ──────────────────────────────────────
        function onBackendChanged(obj, backendName)
            app = obj.App;
            bn = char(backendName);
            if isempty(bn); return; end
            % Persist selection so other screens (Benchmark, Backends) pick
            % up the same choice via AppState.selectedBackend.
            app.State.selectedBackend = string(bn);
            app.logEvent('BENCH', sprintf('Backend changed → %s', bn));
            obj.onRefreshAll();
        end

        % ── Export Data ──────────────────────────────────────────────────
        function onExportData(obj)
            % Write the last-fetched volumetric / regression / calibration
            % points and system metrics to CSV files the user picks. Uses
            % uiputfile so the operator can choose location and filename.
            app = obj.App;
            if isempty(fieldnames(obj.LastResults))
                uialert(app.UIFigure, ...
                    'Press Refresh All first — no data has been fetched yet.', ...
                    'Nothing to Export');
                return;
            end
            ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
            backend = '';
            try backend = char(app.BenchmarkBackendDropdown.Value); catch; end
            defaultName = sprintf('benchmark_%s_%s.csv', ...
                matlab.lang.makeValidName(backend), ts);
            [file, path] = uiputfile({'*.csv', 'CSV (comma-separated)'}, ...
                'Export benchmark data', defaultName);
            if isequal(file, 0); return; end
            out = fullfile(path, file);
            try
                obj.writeExportCsv(out, backend);
                uialert(app.UIFigure, ...
                    sprintf('Exported to %s', out), 'Export', 'Icon', 'success');
                app.logEvent('BENCH', sprintf('Exported benchmark data → %s', out));
            catch ex
                app.showError('Export Data', ex);
            end
        end
    end

    methods (Access = private)

        % ── Apply fetched data to UI (runs on main thread) ──────────────

        function applyAllData(obj, app, backendName, R)
            try
                obj.LastResults = R;
                obj.applySystemMetrics(app, backendName, R.metrics);
                obj.applyVolumetric(app, R.volumetric);
                obj.applyScorecard(app, backendName, R.scorecard);
                obj.applyCalibration(app, R.calibration);
                obj.applyRegression(app, backendName, R.regression);
                obj.applyStatusLine(app, backendName, R);
                app.logEvent('BENCH', 'All benchmark data refreshed');
                app.State.logActivity('Refresh benchmark dashboard', 'Success');
                obj.LastRefresh = tic;
            catch ex
                app.logEvent('ERROR', ['Benchmark apply failed: ' ex.message]);
            end
            app.hideLoading();
        end

        function onRefreshError(obj, app, ME)
            app.logEvent('ERROR', ['Benchmark refresh failed: ' ME.message]);
            app.showError('Benchmark Refresh', ME);
            obj.setStatusLine(sprintf('Refresh failed: %s', ME.message));
            obj.setSourceBadge('error', [0.80 0.30 0.30]);
            app.hideLoading();
        end

        % ── Reset every panel so stale content never leaks across refreshes
        function resetAllPanels(obj)
            app = obj.App;
            if ~isempty(app.BenchmarkKpiLabels)
                for k = 1:numel(app.BenchmarkKpiLabels)
                    app.BenchmarkKpiLabels{k}.Text = '--';
                end
            end
            try cla(app.VolumetricAxes);   catch; end
            try cla(app.ScorecardAxes);    catch; end
            try cla(app.CalibrationAxes);  catch; end
            try cla(app.RegressionAxes);   catch; end
        end

        % ── System Metrics ───────────────────────────────────────────────
        function applySystemMetrics(obj, app, backendName, data)
            if isempty(app.BenchmarkKpiLabels); return; end
            if isempty(data) || ~isstruct(data)
                for k = 1:numel(app.BenchmarkKpiLabels)
                    app.BenchmarkKpiLabels{k}.Text = '--';
                end
                return;
            end

            qv    = JsonHelper.pick(data, 'quantum_volume', []);
            clops = JsonHelper.pick(data, 'clops', []);
            lf    = JsonHelper.pick(data, 'layer_fidelity', []);
            eplg  = JsonHelper.pick(data, 'eplg', []);
            nq    = JsonHelper.pick(data, 'num_qubits', []);
            calH  = JsonHelper.pick(data, 'calibration_age_hours', []);
            src   = char(JsonHelper.pick(data, 'source', 'unavailable'));

            app.BenchmarkKpiLabels{1}.Text = obj.formatKpi(qv, '%d');
            app.BenchmarkKpiLabels{2}.Text = obj.formatKpi(clops, '%.0f');
            app.BenchmarkKpiLabels{3}.Text = obj.formatKpi(lf, '%.4f');
            app.BenchmarkKpiLabels{4}.Text = obj.formatKpi(eplg, '%.6f');

            % Overall Score = LF × 10 (puts 0–1 fidelity onto the same
            % 0–10 axis as the scorecard radar for at-a-glance comparison).
            if isnumeric(lf) && ~isempty(lf) && ~isnan(lf)
                app.BenchmarkKpiLabels{5}.Text = sprintf('%.2f', lf * 10);
            else
                app.BenchmarkKpiLabels{5}.Text = '--';
            end

            % Enrich the unit sub-labels with real context so the KPI cards
            % explain themselves — calibration age, qubit count, source hint.
            if ~isempty(app.BenchmarkKpiUnits)
                app.BenchmarkKpiUnits{1}.Text = 'quantum volume';
                if isnumeric(clops) && ~isempty(clops) && clops > 0
                    app.BenchmarkKpiUnits{2}.Text = sprintf('%.1f k ops/s', clops / 1000);
                else
                    app.BenchmarkKpiUnits{2}.Text = 'kilo ops/s';
                end
                if isnumeric(nq) && ~isempty(nq) && nq > 0
                    app.BenchmarkKpiUnits{3}.Text = sprintf('N = %d qubits', int32(nq));
                else
                    app.BenchmarkKpiUnits{3}.Text = '0 – 1';
                end
                if isnumeric(calH) && ~isempty(calH) && calH >= 0
                    app.BenchmarkKpiUnits{4}.Text = sprintf('cal %.1f h old', calH);
                else
                    app.BenchmarkKpiUnits{4}.Text = '0 – 1';
                end
                app.BenchmarkKpiUnits{5}.Text = '0 – 10 (= LF × 10)';
            end

            % Tint the source badge so the user can tell at a glance whether
            % metrics are live IBM Runtime data or fallback stub values.
            switch src
                case 'ibm_runtime'
                    obj.setSourceBadge('live', Theme.COLOR_SUCCESS);
                case 'stub'
                    obj.setSourceBadge('stub', [0.80 0.55 0.15]);
                case 'unavailable'
                    obj.setSourceBadge('n/a', [0.55 0.55 0.60]);
                otherwise
                    obj.setSourceBadge(src, [0.55 0.55 0.60]);
            end

            app.logEvent('BENCH', sprintf('System metrics loaded for %s (source=%s)', ...
                backendName, src));
        end

        % ── Volumetric Heatmap ───────────────────────────────────────────
        function applyVolumetric(obj, app, data)
            ax = app.VolumetricAxes;
            cla(ax);
            if isempty(data) || ~isstruct(data)
                obj.showEmptyAxesMessage(ax, ...
                    'No volumetric data available.', ...
                    'Refresh after jobs complete on this project.');
                title(ax, 'Volumetric Fidelity Map', 'Interpreter', 'none');
                return;
            end
            points = JsonHelper.pick(data, 'data_points', {});
            if obj.isEmptyList(points)
                preds = JsonHelper.pick(data, 'predictions_count', 0);
                execs = JsonHelper.pick(data, 'executions_count', 0);
                hint = 'Submit and complete benchmark jobs to populate this map.';
                if preds > 0 || execs > 0
                    hint = sprintf('Server returned %d predictions and %d executions but none had usable width/depth fields.', ...
                        preds, execs);
                end
                obj.showEmptyAxesMessage(ax, ...
                    'No volumetric data for this project yet.', hint);
                title(ax, 'Volumetric Fidelity Map', 'Interpreter', 'none');
                return;
            end
            try
                [widths, depths, fids] = obj.extractFields(points, ...
                    {'width','depth','fidelity'}, [1 1 0]);
                scatter(ax, depths, widths, 50, fids, 'filled');
                colormap(ax, parula);
                colorbar(ax);
                clim(ax, [0 1]);
                title(ax, 'Volumetric Fidelity Map', 'Interpreter', 'none');
                xlabel(ax, 'Circuit Depth', 'Interpreter', 'none');
                ylabel(ax, 'Circuit Width', 'Interpreter', 'none');
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Volumetric apply failed: ' ex.message]);
            end
        end

        % ── Backend Scorecard (Radar Chart) ──────────────────────────────
        function applyScorecard(obj, app, backendName, data)
            ax = app.ScorecardAxes;
            cla(ax);
            ax.ThetaTick = [0 90 180 270];
            ax.ThetaTickLabel = {'Capacity','Scalability','Accuracy','Runtime'};
            ax.RLim = [0 10];
            if isempty(backendName) || isempty(data) || ~isstruct(data)
                title(ax, 'Backend Scorecard', 'Interpreter', 'none');
                return;
            end
            try
                jobs   = JsonHelper.pick(data, 'jobs_considered', 0);
                avail  = JsonHelper.pick(data, 'data_available', false);
                if ~avail || jobs == 0
                    title(ax, sprintf('Scorecard: %s (no jobs yet)', backendName), ...
                        'Interpreter', 'none');
                    return;
                end
                cap = JsonHelper.pick(JsonHelper.pick(data, 'capacity', struct()), 'score', 0);
                scl = JsonHelper.pick(JsonHelper.pick(data, 'scalability', struct()), 'score', 0);
                acc = JsonHelper.pick(JsonHelper.pick(data, 'accuracy', struct()), 'score', 0);
                rtm = JsonHelper.pick(JsonHelper.pick(data, 'runtime', struct()), 'score', 0);
                angles = linspace(0, 2*pi, 5);
                values = [cap scl acc rtm cap];
                polarplot(ax, angles, values, '-o', 'LineWidth', 2, ...
                    'Color', Theme.COLOR_PRIMARY, 'MarkerFaceColor', Theme.COLOR_PRIMARY);
                title(ax, sprintf('Scorecard: %s  (N=%d jobs)', backendName, jobs), ...
                    'Interpreter', 'none');
            catch ex
                app.logEvent('WARN', ['Scorecard apply failed: ' ex.message]);
            end
        end

        % ── Prediction Calibration (Scatter) ─────────────────────────────
        function applyCalibration(obj, app, data)
            ax = app.CalibrationAxes;
            cla(ax);
            if isempty(data) || ~isstruct(data)
                obj.showEmptyAxesMessage(ax, ...
                    'No prediction calibration data yet.', ...
                    'Run predictions and complete the corresponding jobs to populate this chart.');
                title(ax, 'Predicted vs Actual Fidelity', 'Interpreter', 'none');
                return;
            end
            try
                points = JsonHelper.pick(data, 'data_points', {});
                mae  = JsonHelper.pick(data, 'mean_absolute_error', 0);
                corr = JsonHelper.pick(data, 'correlation', 0);
                if obj.isEmptyList(points)
                    preds = JsonHelper.pick(data, 'predictions_considered', 0);
                    jobs  = JsonHelper.pick(data, 'jobs_considered', 0);
                    hint = 'Run predictions and complete the corresponding jobs.';
                    if preds > 0 && jobs > 0
                        hint = sprintf('Found %d predictions and %d completed jobs but none matched on circuit+backend.', ...
                            preds, jobs);
                    elseif preds == 0 && jobs > 0
                        hint = sprintf('Have %d completed jobs but no predictions for this project.', jobs);
                    elseif preds > 0 && jobs == 0
                        hint = sprintf('Have %d predictions but no completed jobs yet.', preds);
                    end
                    obj.showEmptyAxesMessage(ax, 'No prediction calibration data yet.', hint);
                    title(ax, 'Predicted vs Actual Fidelity', 'Interpreter', 'none');
                    return;
                end
                [preds, actuals] = obj.extractFields(points, ...
                    {'predicted_fidelity','actual_fidelity'}, [0 0]);
                scatter(ax, preds, actuals, 36, Theme.COLOR_PRIMARY, 'filled');
                hold(ax, 'on');
                plot(ax, [0 1], [0 1], '--', 'Color', Theme.COLOR_PURPLE, 'LineWidth', 1.2);
                hold(ax, 'off');
                title(ax, sprintf('Pred vs Actual (MAE=%.3f, r=%.2f)', mae, corr), ...
                    'Interpreter', 'none');
                xlabel(ax, 'Predicted Fidelity', 'Interpreter', 'none');
                ylabel(ax, 'Actual Fidelity', 'Interpreter', 'none');
                xlim(ax, [0 1]); ylim(ax, [0 1]);
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Calibration apply failed: ' ex.message]);
            end
        end

        % ── Benchmark Regression (Time Series) ──────────────────────────
        function applyRegression(obj, app, backendName, data)
            ax = app.RegressionAxes;
            cla(ax);
            if isempty(backendName)
                obj.showEmptyAxesMessage(ax, ...
                    'Select a backend to see fidelity regression.', '');
                title(ax, 'Fidelity over Time', 'Interpreter', 'none');
                return;
            end
            if isempty(data) || ~isstruct(data)
                obj.showEmptyAxesMessage(ax, ...
                    sprintf('No regression data for %s.', backendName), ...
                    'Press Refresh All after jobs complete.');
                title(ax, ['Fidelity Trend: ' backendName], 'Interpreter', 'none');
                return;
            end
            try
                points = JsonHelper.pick(data, 'data_points', {});
                if obj.isEmptyList(points)
                    obj.showEmptyAxesMessage(ax, ...
                        sprintf('No completed jobs yet on %s.', backendName), ...
                        'Submit and complete benchmark circuits on this backend.');
                    title(ax, ['Fidelity Trend: ' backendName], 'Interpreter', 'none');
                    return;
                end
                fids = obj.extractFields(points, {'fidelity'}, 0);
                plot(ax, 1:numel(fids), fids, '-o', ...
                    'Color', Theme.COLOR_PRIMARY, 'LineWidth', 1.4, 'MarkerSize', 4);
                title(ax, sprintf('Fidelity Trend: %s  (N=%d jobs)', ...
                    backendName, numel(fids)), 'Interpreter', 'none');
                xlabel(ax, 'Job Index', 'Interpreter', 'none');
                ylabel(ax, 'Fidelity', 'Interpreter', 'none');
                ylim(ax, [0 1]);
                app.styleAxes(ax);
            catch ex
                app.logEvent('WARN', ['Regression apply failed: ' ex.message]);
            end
        end

        % ── Status line (below toolbar) ──────────────────────────────────
        function applyStatusLine(obj, app, backendName, R)
            parts = {};
            if ~isempty(backendName)
                parts{end+1} = sprintf('backend: %s', backendName);
            end
            if ~isempty(R.volumetric)
                preds = JsonHelper.pick(R.volumetric, 'predictions_count', 0);
                execs = JsonHelper.pick(R.volumetric, 'executions_count', 0);
                parts{end+1} = sprintf('%d predictions · %d executions', preds, execs);
            end
            if ~isempty(R.regression)
                rjobs = JsonHelper.pick(R.regression, 'jobs_considered', 0);
                parts{end+1} = sprintf('%d backend jobs', rjobs);
            end
            if ~isempty(R.metrics)
                calH = JsonHelper.pick(R.metrics, 'calibration_age_hours', []);
                if isnumeric(calH) && ~isempty(calH) && calH >= 0
                    parts{end+1} = sprintf('cal %.1f h old', calH);
                end
                src = char(JsonHelper.pick(R.metrics, 'source', ''));
                detail = char(JsonHelper.pick(R.metrics, 'source_detail', ''));
                if ~isempty(src)
                    if ~isempty(detail)
                        parts{end+1} = sprintf('source: %s — %s', src, detail);
                    else
                        parts{end+1} = sprintf('source: %s', src);
                    end
                end
            end
            if isempty(parts)
                msg = 'Refreshed. No data returned for the current selection.';
            else
                msg = strjoin(parts, '  ·  ');
            end
            obj.setStatusLine(msg);
        end

        function setStatusLine(obj, msg)
            try
                obj.App.BenchmarkStatusLabel.Text = msg;
            catch
                % Status label not yet built (first refresh during construction)
            end
        end

        function setSourceBadge(obj, label, color)
            try
                b = obj.App.BenchmarkSourceBadge;
                if isempty(label)
                    b.Text = '';
                    b.BackgroundColor = Theme.COLOR_CARD;
                    return;
                end
                b.Text = upper(label);
                b.BackgroundColor = color;
                if mean(color) > 0.6
                    b.FontColor = [0.10 0.10 0.10];
                else
                    b.FontColor = [1 1 1];
                end
            catch
                % Badge not yet built
            end
        end

        function txt = formatKpi(~, val, fmt)
            if isempty(val) || ~isnumeric(val) || any(isnan(val))
                txt = '--'; return;
            end
            % `%d` needs an integer; coerce to be safe.
            if contains(fmt, '%d')
                txt = sprintf(fmt, int64(round(double(val))));
            else
                txt = sprintf(fmt, double(val));
            end
        end

        % ── Export helper ────────────────────────────────────────────────
        function writeExportCsv(obj, outPath, backendName)
            R = obj.LastResults;
            fid = fopen(outPath, 'w');
            if fid < 0
                error('Benchmark:Export', 'Cannot open %s for writing', outPath);
            end
            cleanup = onCleanup(@() fclose(fid));
            fprintf(fid, '# QTAU Benchmark Dashboard export\n');
            fprintf(fid, '# generated,%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
            fprintf(fid, '# backend,%s\n\n', backendName);

            if isfield(R, 'metrics') && ~isempty(R.metrics)
                fprintf(fid, 'section,system_metrics\n');
                fprintf(fid, 'key,value\n');
                m = R.metrics;
                keys = {'backend_name','source','source_detail','num_qubits', ...
                    'calibration_age_hours','quantum_volume','clops','clops_h', ...
                    'layer_fidelity','eplg','median_gate_error_1q', ...
                    'median_ecr_error','median_readout_error','median_t1_us', ...
                    'median_t2_us'};
                for i = 1:numel(keys)
                    v = JsonHelper.pick(m, keys{i}, '');
                    fprintf(fid, '%s,%s\n', keys{i}, obj.csvCell(v));
                end
                fprintf(fid, '\n');
            end

            if isfield(R, 'volumetric') && ~isempty(R.volumetric)
                fprintf(fid, 'section,volumetric\n');
                fprintf(fid, 'width,depth,fidelity,circuit_name,source\n');
                pts = JsonHelper.pick(R.volumetric, 'data_points', {});
                obj.writeCsvRows(fid, pts, {'width','depth','fidelity','circuit_name','source'});
                fprintf(fid, '\n');
            end

            if isfield(R, 'calibration') && ~isempty(R.calibration)
                fprintf(fid, 'section,prediction_calibration\n');
                fprintf(fid, 'circuit_id,backend_name,predicted_fidelity,actual_fidelity,timestamp\n');
                pts = JsonHelper.pick(R.calibration, 'data_points', {});
                obj.writeCsvRows(fid, pts, {'circuit_id','backend_name','predicted_fidelity','actual_fidelity','timestamp'});
                fprintf(fid, '\n');
            end

            if isfield(R, 'regression') && ~isempty(R.regression)
                fprintf(fid, 'section,regression\n');
                fprintf(fid, 'timestamp,circuit_name,fidelity,backend_name\n');
                pts = JsonHelper.pick(R.regression, 'data_points', {});
                obj.writeCsvRows(fid, pts, {'timestamp','circuit_name','fidelity','backend_name'});
                fprintf(fid, '\n');
            end
        end

        function writeCsvRows(obj, fid, points, fields)
            if obj.isEmptyList(points); return; end
            for i = 1:numel(points)
                if iscell(points); p = points{i}; else; p = points(i); end
                parts = cell(1, numel(fields));
                for k = 1:numel(fields)
                    v = JsonHelper.pick(p, fields{k}, '');
                    parts{k} = obj.csvCell(v);
                end
                fprintf(fid, '%s\n', strjoin(parts, ','));
            end
        end

        function s = csvCell(~, v)
            if isempty(v)
                s = '';
            elseif isnumeric(v) || islogical(v)
                s = num2str(double(v));
            else
                s = char(string(v));
                s = strrep(s, '"', '""');
                if any(s == ',') || any(s == '"') || any(s == newline)
                    s = sprintf('"%s"', s);
                end
            end
        end

        % ── Shared helpers ───────────────────────────────────────────────
        function tf = isEmptyList(~, points)
            tf = isempty(points) || (iscell(points) && isempty(points)) ...
                || (isstruct(points) && numel(points) == 0);
        end

        function showEmptyAxesMessage(~, ax, msg, hint)
            cla(ax);
            if strlength(string(hint)) > 0
                text(ax, 0.5, 0.55, msg, ...
                    'HorizontalAlignment', 'center', 'FontSize', 13, ...
                    'FontWeight', 'bold', 'Color', Theme.COLOR_MUTED, ...
                    'Units', 'normalized', 'Interpreter', 'none');
                text(ax, 0.5, 0.42, hint, ...
                    'HorizontalAlignment', 'center', 'FontSize', 11, ...
                    'Color', Theme.COLOR_MUTED, 'Units', 'normalized', ...
                    'Interpreter', 'none');
            else
                text(ax, 0.5, 0.5, msg, ...
                    'HorizontalAlignment', 'center', 'FontSize', 13, ...
                    'FontWeight', 'bold', 'Color', Theme.COLOR_MUTED, ...
                    'Units', 'normalized', 'Interpreter', 'none');
            end
        end

        function varargout = extractFields(~, points, fields, defaults)
            % Pull a parallel numeric vector per requested field from either
            % a struct array or cell array of structs.
            n = numel(points);
            varargout = cell(1, numel(fields));
            for k = 1:numel(fields)
                out = zeros(1, n);
                for i = 1:n
                    if iscell(points); p = points{i}; else; p = points(i); end
                    v = JsonHelper.pick(p, fields{k}, defaults(k));
                    if isnumeric(v) && isscalar(v); out(i) = v;
                    else; out(i) = defaults(k); end
                end
                varargout{k} = out;
            end
        end
    end

    methods (Static, Access = private)

        % ── Data fetching (runs off UI thread) ───────────────────────────

        function results = fetchAllData(svc, backendName, pid, token)
            % fetchAllData  Run all 5 API calls and return a struct of
            %   results.  Each call is wrapped in try-catch so a single
            %   failure doesn't abort the others. The failures are logged
            %   at WARN level so the user can see why panels are empty.
            results = struct('metrics', [], 'volumetric', [], ...
                'scorecard', [], 'calibration', [], 'regression', []);

            if ~isempty(backendName)
                try results.metrics = svc.getSystemMetrics(backendName, token);
                catch ME; Logger.warn('BenchmarkDashboardViewModel', 'fetchMetrics (%s): %s', backendName, ME.message); end
            end
            if ~isempty(pid)
                try results.volumetric = svc.getVolumetricData(pid, token);
                catch ME; Logger.warn('BenchmarkDashboardViewModel', 'fetchVolumetric: %s', ME.message); end
            end
            if ~isempty(backendName) && ~isempty(pid)
                try results.scorecard = svc.getBackendScorecard(pid, backendName, token);
                catch ME; Logger.warn('BenchmarkDashboardViewModel', 'fetchScorecard (%s): %s', backendName, ME.message); end
            end
            if ~isempty(pid)
                try results.calibration = svc.getPredictionCalibration(pid, token);
                catch ME; Logger.warn('BenchmarkDashboardViewModel', 'fetchCalibration: %s', ME.message); end
            end
            if ~isempty(backendName) && ~isempty(pid)
                try results.regression = svc.getBenchmarkRegression(pid, backendName, token);
                catch ME; Logger.warn('BenchmarkDashboardViewModel', 'fetchRegression (%s): %s', backendName, ME.message); end
            end
        end
    end
end
