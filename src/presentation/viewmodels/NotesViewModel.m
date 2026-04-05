classdef NotesViewModel < handle
    % NotesViewModel  Callback handlers for the Notes screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = NotesViewModel(app)
            obj.App = app;
        end

        function onSaveNotes(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasProject()
                app.State.projectNotes = strjoin(app.NotesArea.Value, newline);
                app.logEvent('UI', 'Notes saved to session only (not authenticated or no project selected)');
                return;
            end
            content = strjoin(app.NotesArea.Value, newline);
            app.logEvent('API', sprintf('PUT /api/projects/%s/notes (%d chars)', ...
                app.State.currentProjectId, numel(content)));
            app.showLoading(Labels.get('loading_saving_notes', 'Saving notes...'));
            try
                app.ProjectSvc.saveNotes(app.State.currentProjectId, content, app.State.authToken);
                app.State.projectNotes = content;
                app.logEvent('API', sprintf('Notes saved to server — project: %s', app.State.currentProjectId));
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Save notes FAILED (project: %s): %s', ...
                    app.State.currentProjectId, ME.message));
                app.showError('Save Notes', ME);
            end
        end

        function onLoadNotes(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasProject()
                app.logEvent('UI', 'Load notes skipped — not authenticated or no project');
                return;
            end
            app.logEvent('API', sprintf('GET /api/projects/%s/notes', app.State.currentProjectId));
            app.showLoading(Labels.get('loading_notes', 'Loading notes...'));
            try
                data    = app.ProjectSvc.getNotes(app.State.currentProjectId, app.State.authToken);
                content = char(JsonHelper.pick(data, {'content','notes','text'}));
                if ~isempty(content)
                    app.NotesArea.Value    = strsplit(content, newline);
                    app.State.projectNotes = content;
                    app.logEvent('API', sprintf('Notes loaded (%d chars) — project: %s', ...
                        numel(content), app.State.currentProjectId));
                else
                    app.logEvent('API', 'Notes loaded — response empty, no content to display');
                end
                obj.LastRefresh = tic;
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Load notes FAILED (project: %s): %s', ...
                    app.State.currentProjectId, ME.message));
                app.showError('Load Notes', ME);
            end
        end

        function onClearNotes(obj)
            app = obj.App;
            app.NotesArea.Value    = {''};
            app.State.projectNotes = "";
            app.logEvent('UI', 'Notes cleared');
        end
    end
end
