classdef UploadViewModel < handle
    % UploadViewModel  Callback handlers for the Upload screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
        ParsedQubits double = 0
        ParsedDepth  double = 0
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
            app.State.selectedCircuitId   = "";  % clear — new file not yet uploaded
            app.State.selectedCircuitName = "";
            app.UploadFileField.Value = fullp;
            app.CircuitNameField.Value = file;  % include extension
            info = dir(fullp);
            app.logEvent('UI', sprintf('Circuit file selected: %s  path: %s  size: %d bytes', ...
                file, path, info.bytes));
            content = '';
            maxPreviewBytes = 100000;  % 100 KB limit for TextArea preview
            try
                content = fileread(fullp);
                if numel(content) > maxPreviewBytes
                    previewText = content(1:maxPreviewBytes);
                    % Trim to last complete line
                    lastNL = find(previewText == newline, 1, 'last');
                    if ~isempty(lastNL); previewText = previewText(1:lastNL); end
                    totalLines = numel(strfind(content, newline)) + 1;
                    previewLines = strsplit(previewText, newline);
                    previewLines{end+1} = sprintf('... [truncated — showing %d of %d lines (%.1f MB file)]', ...
                        numel(previewLines), totalLines, numel(content)/1e6);
                    app.CircuitPreviewArea.Value = previewLines;
                    app.logEvent('UI', sprintf('Circuit file preview truncated (%d/%d lines, %.1f MB)', ...
                        numel(previewLines)-1, totalLines, numel(content)/1e6));
                else
                    app.CircuitPreviewArea.Value = strsplit(content, newline);
                    app.logEvent('UI', sprintf('Circuit file preview loaded (%d lines)', numel(strsplit(content, newline))));
                end
                % Auto-detect format from OPENQASM header
                if contains(content, 'OPENQASM 3')
                    app.UploadFormatDropdown.Value = 'qasm3';
                elseif contains(content, 'OPENQASM 2') || contains(content, 'OPENQASM')
                    app.UploadFormatDropdown.Value = 'qasm2';
                end
                % Extract qubits and depth from content for upload metadata
                obj.extractCircuitStats(content);
            catch ME
                app.logEvent('WARN', sprintf('Could not read file for preview: %s', ME.message));
            end
            % Build colored HTML circuit diagram (renderSvg auto-truncates large circuits)
            diagramHtml = '';
            try
                diagramHtml = CircuitDiagram.renderSvg(content);
            catch ME; Logger.debug('UploadViewModel', 'onBrowseCircuit renderSvg: %s', ME.message); end
            app.CircuitStatsArea.HTMLSource = CircuitDiagram.buildStatsHtml({}, diagramHtml);
        end

        function onUploadCircuit(obj, silent)
            if nargin < 2; silent = false; end
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
            format   = 'auto';  % let backend auto-detect from OPENQASM header
            category = char(app.CircuitCategoryDropdown.Value);
            nQubits  = obj.ParsedQubits;
            depth    = obj.ParsedDepth;
            app.logEvent('API', sprintf('Upload circuit — file: %s  name: %s  format: %s  category: %s  qubits: %d  depth: %d  project: %s', ...
                filePath, name, format, category, nQubits, depth, char(app.State.currentProjectId)));
            % Show file size in loading overlay; enable elapsed timer for large files
            fInfo = dir(filePath);
            if fInfo.bytes >= 1048576
                sizeStr = sprintf('%.1f MB', fInfo.bytes / 1048576);
            elseif fInfo.bytes >= 1024
                sizeStr = sprintf('%.0f KB', fInfo.bytes / 1024);
            else
                sizeStr = sprintf('%d B', fInfo.bytes);
            end
            loadMsg = sprintf('Uploading %s (%s) ...', name, sizeStr);
            app.showLoading(loadMsg, fInfo.bytes > 102400);
            svc   = app.CircuitSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.uploadCircuit(filePath, name, format, category, ...
                    nQubits, depth, token), ...
                @(data) obj.onUploadComplete(app, data, name, format, category, silent), ...
                @(ME) obj.onUploadError(app, filePath, ME));
        end

        function onGoToAnalyze(obj)
            % Upload the circuit asynchronously if not yet saved, then
            % navigate to Analysis and auto-analyze. The upload runs on
            % backgroundPool so a large QASM file doesn't freeze the
            % whole UI; the navigate-and-trigger chain is invoked from
            % the success callback OR directly when no upload is needed.
            app = obj.App;

            % Path A: upload required (file selected but no circuit ID yet).
            if strlength(app.State.selectedCircuitId) == 0
                filePath = char(app.State.selectedFile);
                if ~isempty(filePath) && isfile(filePath)
                    if ~app.State.isAuthenticated()
                        uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Upload', 'Icon', 'warning'); return;
                    end
                    if ~app.State.hasProject()
                        uialert(app.UIFigure, Labels.get('upload_error_no_project'), 'Upload', 'Icon', 'warning'); return;
                    end
                    name     = char(app.CircuitNameField.Value);
                    format   = 'auto';
                    category = char(app.CircuitCategoryDropdown.Value);
                    fInfo = dir(filePath);
                    if fInfo.bytes >= 1048576
                        sizeStr = sprintf('%.1f MB', fInfo.bytes / 1048576);
                    elseif fInfo.bytes >= 1024
                        sizeStr = sprintf('%.0f KB', fInfo.bytes / 1024);
                    else
                        sizeStr = sprintf('%d B', fInfo.bytes);
                    end
                    app.showLoading(sprintf('Uploading %s (%s) ...', name, sizeStr), fInfo.bytes > 102400);

                    svc     = app.CircuitSvc;
                    token   = app.State.authToken;
                    parsedQ = obj.ParsedQubits;
                    parsedD = obj.ParsedDepth;
                    AsyncRunner.run( ...
                        @() svc.uploadCircuit(filePath, name, format, category, parsedQ, parsedD, token), ...
                        @(data) obj.onGoToAnalyzeUploadComplete(app, data, name), ...
                        @(ME)   obj.onGoToAnalyzeUploadError(app, filePath, ME));
                    return;  % continuation lives in the success callback
                end
            end

            % Path B: no upload needed — navigate + trigger immediately.
            obj.gotoAnalyzeAndTrigger(app);
        end

        function onGoToAnalyzeUploadComplete(obj, app, data, name)
            app.State.selectedCircuitId   = string(JsonHelper.pick(data, {'circuit_id','id'}));
            app.State.selectedCircuitName = string(name);
            app.logEvent('API', sprintf('Circuit uploaded (for analyze) — id: %s', app.State.selectedCircuitId));
            app.hideLoading();
            obj.gotoAnalyzeAndTrigger(app);
        end

        function onGoToAnalyzeUploadError(~, app, filePath, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Upload for analyze FAILED (%s): %s', filePath, ME.message));
            app.showError('Upload Circuit', ME);
        end

        function gotoAnalyzeAndTrigger(~, app)
            % Shared navigation + auto-analyze step. Used by both the
            % no-upload path and the post-upload success callback.
            if ~app.State.hasCircuit()
                uialert(app.UIFigure, ...
                    Labels.get('error_save_circuit_first', 'Please save the circuit first before analyzing.'), ...
                    'No Circuit', 'Icon', 'warning');
                return;
            end
            targetCid = char(app.State.selectedCircuitId);
            % Navigate to Analysis — onEnter reloads dropdown and selects
            % the circuit matching app.State.selectedCircuitId.
            app.onSelectSection('Analysis');
            drawnow;  % ensure UI updates and onEnter completes
            % Force-select the target circuit and trigger analysis.
            if ~isempty(app.AnalysisVm)
                items = app.AnalysisCircuitDropdown.ItemsData;
                idx = find(strcmp(items, targetCid), 1);
                if ~isempty(idx)
                    app.AnalysisCircuitDropdown.Value = targetCid;
                    app.AnalysisVm.onCircuitSelected(targetCid);
                end
                app.AnalysisVm.onAnalyzeCircuit();
            end
        end

        function onRefreshCircuits(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                try; app.hideLoading(); catch; end
                return;
            end
            if ~app.State.hasProject()
                app.UploadCircuitsTable.Data = {};
                try; app.hideLoading(); catch; end
                return;
            end
            app.logEvent('API', sprintf('Loading circuits — project: %s', char(app.State.currentProjectId)));
            % Async — populating the Circuits table is a tab-enter
            % path (and the post-delete refresh target). Sync was
            % freezing the Upload tab on each refresh.
            svc   = app.CircuitSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.listCircuits(token), ...
                @(data) obj.onCircuitsLoaded(app, data), ...
                @(ME)   obj.onCircuitsLoadError(app, ME));
        end

        function onCircuitsLoaded(obj, app, data)
            try
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
                obj.LastRefresh = tic;
            catch ME
                app.logEvent('ERROR', sprintf('onCircuitsLoaded render: %s', ME.message));
            end
            try; app.hideLoading(); catch; end
        end

        function onCircuitsLoadError(~, app, ME)
            app.logEvent('ERROR', sprintf('listCircuits FAILED: %s', ME.message));
            try; app.hideLoading(); catch; end
        end

        function onDeleteCircuit(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Delete Circuit', 'Icon', 'warning'); return;
            end
            sel = app.UploadCircuitsTable.Selection;
            if isempty(sel)
                uialert(app.UIFigure, Labels.get('error_select_circuit_row', 'Select a circuit row first.'), 'Delete Circuit', 'Icon', 'warning'); return;
            end
            row = sel(1);
            tData = app.UploadCircuitsTable.Data;
            circuitId   = tData{row, 1};
            circuitName = tData{row, 2};
            answer = uiconfirm(app.UIFigure, ...
                sprintf('Delete circuit "%s" (%s)?', circuitName, circuitId), ...
                'Confirm Delete', 'Options', {'Delete','Cancel'}, 'DefaultOption', 'Cancel');
            if ~strcmp(answer, 'Delete')
                return;
            end
            app.logEvent('API', sprintf('Delete circuit — id %s', circuitId));
            % Async — delete on backgroundPool, refresh the table from
            % the success callback so the user sees an instant UI
            % response instead of a frozen window.
            svc   = app.CircuitSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.deleteCircuit(circuitId, token), ...
                @(~)  obj.onDeleteCircuitComplete(app, circuitId, circuitName), ...
                @(ME) obj.onDeleteCircuitError(app, ME));
        end

        function onDeleteCircuitComplete(obj, app, circuitId, circuitName)
            app.logEvent('API', sprintf('Circuit deleted: %s', circuitId));
            app.State.logActivity(sprintf('Delete circuit — %s', circuitName), 'Success');
            % Circuit list shrank — invalidate shared cache so the
            % deletion propagates to Mitigation/RunPlanner/ResourceEst.
            try; app.State.invalidateCircuitsListCache(); catch; end
            obj.onRefreshCircuits();  % itself dispatches async listCircuits
        end

        function onDeleteCircuitError(~, app, ME)
            app.logEvent('ERROR', sprintf('deleteCircuit FAILED: %s', ME.message));
            app.showError('Delete Circuit', ME);
        end
    end

    methods (Access = private)
        function onUploadComplete(obj, app, data, name, format, category, silent)
            app.State.selectedCircuitId   = string(JsonHelper.pick(data, {'circuit_id','id'}));
            app.State.selectedCircuitName = string(name);
            app.logEvent('API', sprintf('Circuit uploaded successfully — id: %s  name: %s  format: %s  project: %s', ...
                app.State.selectedCircuitId, name, format, char(app.State.currentProjectId)));
            app.State.logActivity(sprintf('Upload circuit — %s', name), 'Success');
            % Circuit list just grew — invalidate shared cache so the
            % new circuit appears on Mitigation/RunPlanner/ResourceEst.
            try; app.State.invalidateCircuitsListCache(); catch; end

            % Async preview fetch — the server-rendered SVG GET was a
            % 200-1000 ms freeze on top of the already-async upload.
            % The diagram-render + success-alert continuation runs from
            % onUploadCompleteAfterPreview on the main thread once the
            % preview round-trip lands.
            svc   = app.CircuitSvc;
            cid   = char(app.State.selectedCircuitId);
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.previewCircuit(cid, token), ...
                @(prevData) obj.onUploadCompleteAfterPreview(app, prevData, name, format, category, silent), ...
                @(ME) obj.onUploadCompletePreviewFailed(app, name, format, category, silent, ME));
        end

        function onUploadCompleteAfterPreview(obj, app, prevData, name, format, category, silent)
            diagramHtml = '';
            try
                if ~isempty(prevData)
                    serverSvg = char(JsonHelper.pick(prevData, {'svg'}));
                    if ~isempty(serverSvg) && startsWith(strtrim(serverSvg), '<svg')
                        diagramHtml = serverSvg;
                    end
                end
            catch ME
                Logger.debug('UploadViewModel', ...
                    'onUploadComplete previewCircuit parse: %s', ME.message);
            end
            % Fallback: client-side rendering of the local QASM.
            if isempty(diagramHtml)
                filePath2 = char(app.State.selectedFile);
                if ~isempty(filePath2) && isfile(filePath2)
                    try
                        diagramHtml = CircuitDiagram.renderSvg(fileread(filePath2));
                    catch ME
                        Logger.debug('UploadViewModel', ...
                            'onUploadComplete fallback renderSvg: %s', ME.message);
                    end
                end
            end
            app.CircuitStatsArea.HTMLSource = CircuitDiagram.buildStatsHtml({}, diagramHtml);
            if ~silent
                uialert(app.UIFigure, ...
                    sprintf('Circuit "%s" uploaded successfully.\n\nCircuit ID: %s\nFormat: %s\nCategory: %s\nProject: %s', ...
                        name, char(app.State.selectedCircuitId), format, category, char(app.State.currentProjectName)), ...
                    Labels.get('upload_success_title', 'Upload Successful'), 'Icon', 'success');
            end
            app.hideLoading();
            obj.onRefreshCircuits();
        end

        function onUploadCompletePreviewFailed(obj, app, name, format, category, silent, ME)
            % Preview GET failed — proceed with empty server SVG so the
            % continuation falls back to client-side renderSvg.
            Logger.debug('UploadViewModel', ...
                'onUploadComplete previewCircuit: %s', ME.message);
            obj.onUploadCompleteAfterPreview(app, [], name, format, category, silent);
        end

        function onUploadError(~, app, filePath, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Upload FAILED (file: %s): %s', filePath, ME.message));
            app.CircuitStatsArea.HTMLSource = CircuitDiagram.buildStatsHtml({}, ...
                sprintf('<p style="color:#DC2626;font-family:sans-serif">Upload failed: %s</p>', ME.message));
            app.showError('Upload Circuit', ME);
        end

        function extractCircuitStats(obj, content)
            % Extract qubit count and estimated depth from raw QASM text.
            nq = 0; gates = 0;
            lines = strsplit(content, newline);
            for k = 1:numel(lines)
                ln = strtrim(lines{k});
                % qreg q[N]; or qubit[N] name;
                tok = regexp(ln, '(?:qreg\s+\w+\[(\d+)\]|qubit\[(\d+)\])', 'tokens');
                for j = 1:numel(tok)
                    vals = tok{j};
                    for m = 1:numel(vals)
                        if ~isempty(vals{m}); nq = nq + str2double(vals{m}); end
                    end
                end
                % Count gate lines (h, x, cx, etc.)
                if ~isempty(regexp(ln, '^\s*(?:\w+\s*=\s*)?(?:h|x|y|z|s|t|rx|ry|rz|cx|cz|ccx|swap|u[123]?|cu[123]?|measure)\b', 'once'))
                    gates = gates + 1;
                end
            end
            obj.ParsedQubits = max(nq, 1);
            obj.ParsedDepth  = max(ceil(gates / max(nq, 1)), 1);
        end
    end
end
