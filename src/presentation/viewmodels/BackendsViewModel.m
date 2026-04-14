classdef BackendsViewModel < handle
    % BackendsViewModel  Callback handlers for the Backends screen.

    properties
        LastRefresh = []
    end

    properties (Access = private)
        App
        FullTableData cell = {}   % unfiltered rows for search
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
            AsyncRunner.run( ...
                @() obj.fetchBackends(app, cid), ...
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
            obj.onSelectBackend();
        end

        function onCtxSetBackup(obj)
            app = obj.App;
            app.hideBackendsPopupMenu();
            row = obj.getSelectedRow();
            if row == 0; return; end
            backupName = char(string(app.BackendTable.Data{row, 2}));
            app.State.backupBackend = string(backupName);
            if ~isempty(app.BackendKpiLabels) && numel(app.BackendKpiLabels) >= 2
                app.BackendKpiLabels{2}.Text = backupName;
            end
            notes = app.BackendStatusArea.Value;
            notes{end+1} = sprintf('Backup changed to: %s', backupName);
            app.setStatus(app.BackendStatusArea, notes);
            primary = char(app.State.selectedBackend);
            if ~isempty(primary); obj.persistSelection(app, primary, backupName); end
        end

        function onCtxViewDetails(obj)
            app = obj.App;
            app.hideBackendsPopupMenu();
            row = obj.getSelectedRow();
            if row == 0; return; end
            bName = char(string(app.BackendTable.Data{row, 2}));
            app.showLoading(sprintf('Loading details for %s...', bName));
            AsyncRunner.run( ...
                @() app.BackendSvc.getBackend(bName, app.State.authToken), ...
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

        function data = fetchBackends(obj, app, cid)
            % Try enriched list with circuit_id. If that fails (404),
            % try fetching a circuit_id from the project, then fall back to basic.
            data = struct('backends', {{}});
            if ~isempty(cid)
                try
                    data = app.BackendSvc.listBackends(app.State.authToken, cid);
                    if obj.hasBackends(data); return; end
                catch
                    app.logEvent('WARN', 'Enriched backend list failed for selected circuit');
                end
            end
            % Try with any circuit from the project
            try
                circList = app.CircuitSvc.listCircuits(app.State.authToken);
                items = JsonHelper.extractList(circList, 'circuits');
                if ~isempty(items)
                    fallbackCid = char(JsonHelper.pick(items(1), {'circuit_id','id'}));
                    if ~isempty(fallbackCid)
                        data = app.BackendSvc.listBackends(app.State.authToken, fallbackCid);
                        if obj.hasBackends(data); return; end
                    end
                end
            catch
                app.logEvent('WARN', 'Fallback circuit lookup failed');
            end
            % Last resort: basic list (may be empty)
            try
                data = app.BackendSvc.listBackends(app.State.authToken, '');
            catch ME; Logger.debug('BackendsViewModel', 'fetchBackends basic list: %s', ME.message); end
        end

        function tf = hasBackends(~, data)
            tf = false;
            if isstruct(data) && isfield(data, 'backends')
                tf = ~isempty(data.backends);
            end
        end

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
                AsyncRunner.run( ...
                    @() app.BackendSvc.getBackend(primaryName, app.State.authToken), ...
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
            primary = char(string(tData{row,2}));
            AsyncRunner.run( ...
                @() app.BackendSvc.getBackend(primary, app.State.authToken), ...
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
            if app.State.isAuthenticated() && app.State.hasProject() && ~isempty(primaryName)
                try
                    app.BackendSvc.saveSelection(app.State.currentProjectId, ...
                        string(primaryName), string(backupName), app.State.authToken);
                    app.logEvent('API', sprintf('Backend selection saved — primary: %s  backup: %s', primaryName, backupName));
                catch ME
                    app.logEvent('ERROR', sprintf('Save selection FAILED: %s', ME.message));
                    app.showError('Save Backend Selection', ME);
                end
            end
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
    end
end
