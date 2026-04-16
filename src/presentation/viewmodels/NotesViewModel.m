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
            pid     = app.State.currentProjectId;
            app.logEvent('API', sprintf('PUT /api/projects/%s/notes (%d chars)', pid, numel(content)));
            app.showLoading(Labels.get('loading_saving_notes', 'Saving notes...'));
            svc   = app.ProjectSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.saveNotes(pid, content, token), ...
                @(~) obj.onSaveNotesComplete(app, pid, content), ...
                @(ME) obj.onSaveNotesError(app, pid, ME));
        end

        function onLoadNotes(obj)
            app = obj.App;
            if ~app.State.isAuthenticated() || ~app.State.hasProject()
                app.logEvent('UI', 'Load notes skipped — not authenticated or no project');
                return;
            end
            pid = app.State.currentProjectId;
            app.logEvent('API', sprintf('GET /api/projects/%s/notes', pid));
            app.showLoading(Labels.get('loading_notes', 'Loading notes...'));
            svc   = app.ProjectSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getNotes(pid, token), ...
                @(data) obj.onLoadNotesComplete(app, pid, data), ...
                @(ME)   obj.onLoadNotesError(app, pid, ME));
        end

        function onClearNotes(obj)
            app = obj.App;
            app.NotesArea.Value    = {''};
            app.State.projectNotes = "";
            app.logEvent('UI', 'Notes cleared');
        end
    end

    methods (Access = private)
        function onSaveNotesComplete(~, app, pid, content)
            app.State.projectNotes = content;
            app.logEvent('API', sprintf('Notes saved to server — project: %s', pid));
            app.State.logActivity('Save notes', 'Success');
            app.hideLoading();
        end

        function onSaveNotesError(~, app, pid, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Save notes FAILED (project: %s): %s', pid, ME.message));
            app.showError('Save Notes', ME);
        end

        function onLoadNotesComplete(obj, app, pid, data)
            content = char(JsonHelper.pick(data, {'content','notes','text'}));
            if ~isempty(content)
                app.NotesArea.Value    = strsplit(content, newline);
                app.State.projectNotes = content;
                app.logEvent('API', sprintf('Notes loaded (%d chars) — project: %s', numel(content), pid));
            else
                app.logEvent('API', 'Notes loaded — response empty, no content to display');
            end
            obj.LastRefresh = tic;
            app.hideLoading();
        end

        function onLoadNotesError(~, app, pid, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Load notes FAILED (project: %s): %s', pid, ME.message));
            app.showError('Load Notes', ME);
        end
    end
end
