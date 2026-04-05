classdef UploadViewModel < handle
    % UploadViewModel  Callback handlers for the Upload screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = UploadViewModel(app)
            obj.App = app;
        end

        function onBrowseCircuit(obj)
            app = obj.App;
            app.logEvent('UI', 'Browse circuit file dialog opened');
            [file, path] = uigetfile({'*.qasm;*.txt;*.*', 'Circuit Files'});
            if isequal(file, 0)
                app.logEvent('UI', 'Browse file dialog cancelled by user');
                return;
            end
            fullp = fullfile(path, file);
            app.State.selectedFile = string(fullp);
            app.UploadFileField.Value = fullp;
            [~, fname, ~] = fileparts(file);
            app.CircuitNameField.Value = fname;
            info = dir(fullp);
            app.logEvent('UI', sprintf('Circuit file selected: %s  path: %s  size: %d bytes', ...
                file, path, info.bytes));
            try
                content = fileread(fullp);
                app.CircuitPreviewArea.Value = strsplit(content, newline);
                app.logEvent('UI', sprintf('Circuit file preview loaded (%d lines)', numel(strsplit(content, newline))));
            catch ME
                app.logEvent('WARN', sprintf('Could not read file for preview: %s', ME.message));
            end
            app.setStatus(app.CircuitStatsArea, { ...
                sprintf('File: %s', file), ...
                sprintf('Path: %s', path), ...
                sprintf('Size: %d bytes', info.bytes), ...
                'Status: ready for upload'});
        end

        function onUploadCircuit(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Upload', 'Icon', 'warning'); return;
            end
            if ~app.State.hasProject()
                uialert(app.UIFigure, Labels.get('upload_error_no_project'), 'Upload', 'Icon', 'warning'); return;
            end
            filePath = char(app.State.selectedFile);
            if isempty(filePath) || ~isfile(filePath)
                uialert(app.UIFigure, Labels.get('error_no_file'), 'Upload', 'Icon', 'warning');
                return;
            end
            name     = char(app.CircuitNameField.Value);
            format   = char(app.UploadFormatDropdown.Value);
            category = char(app.CircuitCategoryDropdown.Value);
            app.logEvent('API', sprintf('POST /api/circuits/upload — file: %s  name: %s  format: %s  category: %s  project: %s', ...
                filePath, name, format, category, char(app.State.currentProjectId)));
            app.showLoading(Labels.get('loading_uploading', 'Uploading circuit...'));
            try
                data = app.CircuitSvc.uploadCircuit(filePath, name, format, category, ...
                    app.State.authToken);
                app.State.selectedCircuitId   = string(JsonHelper.pick(data, {'circuit_id','id'}));
                app.State.selectedCircuitName = string(name);
                app.logEvent('API', sprintf('Circuit uploaded successfully — id: %s  name: %s  format: %s  project: %s', ...
                    app.State.selectedCircuitId, name, format, char(app.State.currentProjectId)));
                app.setStatus(app.CircuitStatsArea, { ...
                    sprintf('Circuit ID: %s', app.State.selectedCircuitId), ...
                    sprintf('Name: %s', name), ...
                    sprintf('Format: %s', format), ...
                    sprintf('Category: %s', category), ...
                    sprintf('Project: %s', char(app.State.currentProjectName)), ...
                    'Status: Uploaded successfully'});
                uialert(app.UIFigure, ...
                    sprintf('Circuit "%s" uploaded successfully.\n\nCircuit ID: %s\nFormat: %s\nCategory: %s\nProject: %s', ...
                        name, char(app.State.selectedCircuitId), format, category, char(app.State.currentProjectName)), ...
                    Labels.get('upload_success_title', 'Upload Successful'), 'Icon', 'success');
                app.hideLoading();
                % Refresh circuits table after successful upload
                obj.onRefreshCircuits();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Upload FAILED (file: %s): %s', filePath, ME.message));
                app.setStatus(app.CircuitStatsArea, {'Upload failed.', ME.message});
                app.showError('Upload Circuit', ME);
            end
        end

        function onRefreshCircuits(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                return;
            end
            if ~app.State.hasProject()
                app.UploadCircuitsTable.Data = {};
                return;
            end
            app.logEvent('API', sprintf('GET /api/circuits — project: %s', char(app.State.currentProjectId)));
            try
                data = app.CircuitSvc.listCircuits(app.State.authToken);
                circuits = JsonHelper.extractList(data, 'circuits');
                if isempty(circuits)
                    app.UploadCircuitsTable.Data = {};
                    app.logEvent('API', 'listCircuits → 0 circuits in project');
                    return;
                end
                if isstruct(circuits)
                    circuits = num2cell(circuits);
                end
                n = numel(circuits);
                tableData = cell(n, 7);
                for i = 1:n
                    c = circuits{i};
                    if isstruct(c)
                        tableData{i,1} = char(string(JsonHelper.pick(c, {'circuit_id','id'})));
                        tableData{i,2} = char(string(JsonHelper.pick(c, {'name','circuit_name'})));
                        tableData{i,3} = char(string(JsonHelper.safeField(c, 'format', '')));
                        nq = JsonHelper.safeField(c, 'num_qubits', '');
                        if isnumeric(nq); tableData{i,4} = num2str(nq); else; tableData{i,4} = char(string(nq)); end
                        dp = JsonHelper.safeField(c, 'depth', '');
                        if isnumeric(dp); tableData{i,5} = num2str(dp); else; tableData{i,5} = char(string(dp)); end
                        iv = JsonHelper.safeField(c, 'is_valid', '');
                        if islogical(iv)
                            if iv; tableData{i,6} = 'Yes'; else; tableData{i,6} = 'No'; end
                        else
                            tableData{i,6} = char(string(iv));
                        end
                        tableData{i,7} = char(string(JsonHelper.safeField(c, 'created_at', '')));
                    end
                end
                app.UploadCircuitsTable.Data = tableData;
                app.logEvent('API', sprintf('listCircuits → %d circuits loaded for project %s', n, char(app.State.currentProjectId)));
            catch ME
                app.logEvent('ERROR', sprintf('listCircuits FAILED: %s', ME.message));
            end
        end

        function onDeleteCircuit(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Delete Circuit', 'Icon', 'warning'); return;
            end
            sel = app.UploadCircuitsTable.Selection;
            if isempty(sel)
                uialert(app.UIFigure, 'Select a circuit row first.', 'Delete Circuit', 'Icon', 'warning'); return;
            end
            row = sel(1);
            tData = app.UploadCircuitsTable.Data;
            circuitId = tData{row, 1};
            circuitName = tData{row, 2};
            answer = uiconfirm(app.UIFigure, ...
                sprintf('Delete circuit "%s" (%s)?', circuitName, circuitId), ...
                'Confirm Delete', 'Options', {'Delete','Cancel'}, 'DefaultOption', 'Cancel');
            if ~strcmp(answer, 'Delete')
                return;
            end
            app.logEvent('API', sprintf('DELETE /api/circuits/%s', circuitId));
            try
                app.CircuitSvc.deleteCircuit(circuitId, app.State.authToken);
                app.logEvent('API', sprintf('Circuit deleted: %s', circuitId));
                obj.onRefreshCircuits();
            catch ME
                app.logEvent('ERROR', sprintf('deleteCircuit FAILED: %s', ME.message));
                app.showError('Delete Circuit', ME);
            end
        end
    end
end
