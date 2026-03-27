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
            filePath = char(app.State.selectedFile);
            if isempty(filePath) || ~isfile(filePath)
                uialert(app.UIFigure, Labels.get('error_no_file'), 'Upload', 'Icon', 'warning');
                return;
            end
            name     = char(app.CircuitNameField.Value);
            format   = char(app.UploadFormatDropdown.Value);
            category = char(app.CircuitCategoryDropdown.Value);
            app.logEvent('API', sprintf('POST /api/circuits/upload — file: %s  name: %s  format: %s  category: %s', ...
                filePath, name, format, category));
            try
                data = app.CircuitSvc.uploadCircuit(filePath, name, format, category, ...
                    app.State.authToken);
                app.State.selectedCircuitId   = string(JsonHelper.pick(data, {'circuit_id','id'}));
                app.State.selectedCircuitName = string(name);
                app.logEvent('API', sprintf('Circuit uploaded successfully — id: %s  name: %s  format: %s', ...
                    app.State.selectedCircuitId, name, format));
                app.setStatus(app.CircuitStatsArea, { ...
                    sprintf('Circuit ID: %s', app.State.selectedCircuitId), ...
                    sprintf('Name: %s', name), ...
                    sprintf('Format: %s', format), ...
                    sprintf('Category: %s', category), ...
                    'Status: Uploaded successfully'});
            catch ME
                app.logEvent('ERROR', sprintf('Upload FAILED (file: %s): %s', filePath, ME.message));
                app.setStatus(app.CircuitStatsArea, {'Upload failed.', ME.message});
                app.showError('Upload Circuit', ME);
            end
        end
    end
end
