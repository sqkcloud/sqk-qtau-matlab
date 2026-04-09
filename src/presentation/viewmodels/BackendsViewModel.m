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
            app.logEvent('API', 'GET /api/backends');
            app.showLoading(Labels.get('loading_backends', 'Loading backends...'));
            try
                data = app.BackendSvc.listBackends(app.State.authToken);
                rows = JsonHelper.backendsToRows(data);
                if ~isempty(rows)
                    app.BackendTable.Data = rows;
                    if ~isempty(app.BackendKpiLabels) && numel(app.BackendKpiLabels) >= 4
                        app.BackendKpiLabels{1}.Text = char(rows{1,1});
                        if size(rows,1) >= 2; app.BackendKpiLabels{2}.Text = char(rows{2,1}); end
                        app.BackendKpiLabels{3}.Text = sprintf('%.3f', rows{1,4});
                    end
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
            data = app.BackendTable.Data;
            if isempty(data)
                app.logEvent('UI', 'Backend select triggered but table is empty');
                return;
            end
            sel = data{1, 1};
            app.State.selectedBackend = string(sel);
            app.logEvent('CONFIG', sprintf('Backend selected: %s', sel));
            app.setStatus(app.BackendStatusArea, { ...
                sprintf('Primary backend: %s', sel), ...
                'Selection saved to session.'});
            if app.State.isAuthenticated() && app.State.hasProject()
                app.logEvent('API', sprintf('POST /api/projects/%s/backend-selection — backend: %s', ...
                    app.State.currentProjectId, sel));
                app.showLoading(Labels.get('loading_saving', 'Saving selection...'));
                try
                    app.BackendSvc.saveSelection(app.State.currentProjectId, ...
                        app.State.selectedBackend, app.State.backupBackend, app.State.authToken);
                    app.logEvent('API', sprintf('Backend selection saved to server — project: %s  backend: %s', ...
                        app.State.currentProjectId, sel));
                    app.State.logActivity(sprintf('Select backend — %s', sel), 'Success');
                    app.hideLoading();
                catch ME
                    app.hideLoading();
                    app.logEvent('ERROR', sprintf('Save backend selection FAILED (project: %s): %s', ...
                        app.State.currentProjectId, ME.message));
                    app.showError('Save Backend Selection', ME);
                end
            else
                app.logEvent('CONFIG', 'Backend selection stored in session only (not authenticated or no project)');
            end
        end
    end
end
