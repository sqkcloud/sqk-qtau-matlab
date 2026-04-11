classdef BackendsViewModel < handle
    % BackendsViewModel  Callback handlers for the Backends screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = BackendsViewModel(app)
            obj.App = app;
        end

        function onRefreshBackends(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Backends', 'Icon', 'warning'); return;
            end
            % Pass circuit_id to get enriched backend list with fidelity
            cid = '';
            if app.State.hasCircuit()
                cid = char(app.State.selectedCircuitId);
            end
            app.showLoading(Labels.get('loading_backends', 'Loading backends...'));
            try
                data = [];
                if ~isempty(cid)
                    try
                        data = app.BackendSvc.listBackends(app.State.authToken, cid);
                    catch
                        app.logEvent('WARN', 'Enriched backend list failed; retrying without circuit_id');
                        data = app.BackendSvc.listBackends(app.State.authToken, '');
                    end
                else
                    data = app.BackendSvc.listBackends(app.State.authToken, '');
                end
                rows = JsonHelper.backendsToRows(data);
                if ~isempty(rows)
                    app.BackendTable.Data = rows;
                    obj.populateKpiCards(app, rows);
                end
                app.setStatus(app.BackendStatusArea, {sprintf('Loaded %d backend(s).', size(rows,1))});
                app.logEvent('API', sprintf('Backends loaded — %d rows returned', size(rows,1)));
                app.State.logActivity(sprintf('Refresh backends — %d loaded', size(rows,1)), 'Success');
                obj.LastRefresh = tic;
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Backends FAILED: %s', ME.message));
                app.setStatus(app.BackendStatusArea, {'Backend refresh failed.', ME.message});
                app.showError('Refresh Backends', ME);
            end
        end

        function onSelectBackend(obj)
            app = obj.App;
            tData = app.BackendTable.Data;
            if isempty(tData)
                app.logEvent('UI', 'Backend select triggered but table is empty');
                return;
            end
            % Read the user's actual row selection
            sel = app.BackendTable.Selection;
            if isempty(sel)
                % Fall back to first row if no selection
                sel = 1;
            end
            row = sel(1);
            selName = char(string(tData{row, 1}));
            if isempty(selName)
                return;
            end
            app.State.selectedBackend = string(selName);
            app.logEvent('CONFIG', sprintf('Backend selected: %s (row %d)', selName, row));

            % Auto-set backup to next best
            backupName = '';
            for r = 1:size(tData, 1)
                candidate = char(string(tData{r, 1}));
                if ~strcmp(candidate, selName) && ~isempty(candidate)
                    backupName = candidate;
                    break;
                end
            end
            app.State.backupBackend = string(backupName);

            % Update KPI cards
            obj.populateKpiCards(app, tData);
            if ~isempty(app.BackendKpiLabels) && numel(app.BackendKpiLabels) >= 2
                app.BackendKpiLabels{1}.Text = selName;
                if ~isempty(backupName)
                    app.BackendKpiLabels{2}.Text = backupName;
                end
            end

            % Update status notes
            notes = {sprintf('Primary backend: %s', selName)};
            if ~isempty(backupName); notes{end+1} = sprintf('Backup backend: %s', backupName); end
            notes{end+1} = sprintf('Qubits: %s', string(tData{row, 2}));
            notes{end+1} = sprintf('Status: %s', string(tData{row, 3}));
            notes{end+1} = sprintf('Predicted Fidelity: %s', string(tData{row, 4}));
            app.setStatus(app.BackendStatusArea, notes);

            % Persist to server
            if app.State.isAuthenticated() && app.State.hasProject() && ~isempty(selName)
                app.showLoading(Labels.get('loading_saving', 'Saving selection...'));
                try
                    app.BackendSvc.saveSelection(app.State.currentProjectId, ...
                        app.State.selectedBackend, app.State.backupBackend, app.State.authToken);
                    app.logEvent('API', sprintf('Backend selection saved — primary: %s  backup: %s', selName, backupName));
                    app.State.logActivity(sprintf('Select backend — %s', selName), 'Success');
                    app.hideLoading();
                catch ME
                    app.hideLoading();
                    app.logEvent('ERROR', sprintf('Save backend selection FAILED: %s', ME.message));
                    app.showError('Save Backend Selection', ME);
                end
            end
        end
    end

    methods (Access = private)
        function populateKpiCards(~, app, rows)
            if isempty(app.BackendKpiLabels) || numel(app.BackendKpiLabels) < 4; return; end
            n = size(rows, 1);
            if n == 0; return; end

            primaryName = ''; backupName = ''; bestFidelity = 0;
            for i = 1:n
                role = lower(char(string(rows{i, 6})));
                fid  = rows{i, 4};
                if isnumeric(fid) && ~isnan(fid) && fid > bestFidelity
                    bestFidelity = fid;
                end
                if strcmp(role, 'primary') && isempty(primaryName)
                    primaryName = char(string(rows{i, 1}));
                elseif strcmp(role, 'backup') && isempty(backupName)
                    backupName = char(string(rows{i, 1}));
                end
            end
            if isempty(primaryName) && n >= 1; primaryName = char(string(rows{1, 1})); end
            if isempty(backupName)  && n >= 2; backupName  = char(string(rows{2, 1})); end

            calAge = 'N/A';
            try
                if ~isempty(primaryName) && ~isempty(app.State.authToken)
                    detail = app.BackendSvc.getBackend(primaryName, app.State.authToken);
                    ageHrs = JsonHelper.pick(detail, {'calibration_age_hours'});
                    if isnumeric(ageHrs) && ~isnan(ageHrs)
                        calAge = sprintf('%.1f hours', ageHrs);
                    end
                end
            catch; end

            app.BackendKpiLabels{1}.Text = primaryName;
            app.BackendKpiLabels{2}.Text = backupName;
            if bestFidelity > 0
                app.BackendKpiLabels{3}.Text = sprintf('%.4f', bestFidelity);
            else
                app.BackendKpiLabels{3}.Text = 'N/A';
            end
            app.BackendKpiLabels{4}.Text = calAge;
        end
    end
end
