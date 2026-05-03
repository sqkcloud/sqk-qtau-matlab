classdef CircuitsViewModel < handle
    % CircuitsViewModel  Callbacks for the Circuits screen.
    %
    %   Loads a paginated list of circuits from the API and populates the
    %   CircuitsTable.  Supports Prev / Next page navigation, row selection,
    %   right-click context menu (Edit / Delete), and a quick jump to Upload.

    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end

    properties (Access = private)
        App
        RowCircuitIds  cell = {}   % maps table row index → circuit_id
        RowCircuits    cell = {}   % maps table row index → full circuit struct
        FullTableData  cell = {}   % unfiltered table data for search
        FullRowIds     cell = {}   % unfiltered circuit IDs for search
        FullRowData    cell = {}   % unfiltered circuit structs for search
    end

    properties
        PageSkip  double = 0
        PageLimit double = 20
    end

    methods
        function obj = CircuitsViewModel(app)
            obj.App = app;
        end

        function onLoadCircuits(obj)
            app = obj.App;
            % Precondition checks — split so the empty-state banner can
            % explain *why* the table is empty (auth vs no-project).
            if ~app.State.isAuthenticated()
                app.CircuitsTable.Data = {};
                obj.RowCircuitIds = {};
                obj.RowCircuits   = {};
                obj.setEmptyStateMessage('circuits_empty_not_auth');
                obj.updatePageLabel();
                return;
            end
            if ~app.State.hasProject()
                app.CircuitsTable.Data = {};
                obj.RowCircuitIds = {};
                obj.RowCircuits   = {};
                obj.setEmptyStateMessage('circuits_empty_no_project');
                obj.updatePageLabel();
                return;
            end
            % Clear the banner before fetching — a stale message from a
            % previous open shouldn't linger while the new load is in flight.
            obj.setEmptyStateMessage('');
            app.logEvent('API', sprintf('GET /api/circuits?skip=%d&limit=%d — project: %s', ...
                obj.PageSkip, obj.PageLimit, char(app.State.currentProjectId)));
            skip  = obj.PageSkip;
            limit = obj.PageLimit;
            svc   = app.CircuitSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.listCircuitsPaged(skip, limit, token), ...
                @(data) obj.onLoadCircuitsComplete(app, data), ...
                @(ME)   obj.onLoadCircuitsError(app, ME));
        end

        function onNextPage(obj)
            obj.PageSkip = obj.PageSkip + obj.PageLimit;
            obj.onLoadCircuits();
        end

        function onPrevPage(obj)
            obj.PageSkip = max(0, obj.PageSkip - obj.PageLimit);
            obj.onLoadCircuits();
        end

        function onGoToUpload(obj)
            obj.App.onSelectSection('Upload');
        end

        function onSearch(obj, query)
            % Filter the table rows by search query (matches any column)
            app = obj.App;
            if isempty(obj.FullTableData); return; end
            q = lower(strtrim(query));
            if isempty(q)
                % Restore full data
                app.CircuitsTable.Data = obj.FullTableData;
                obj.RowCircuitIds = obj.FullRowIds;
                obj.RowCircuits   = obj.FullRowData;
                return;
            end
            nRows = size(obj.FullTableData, 1);
            keep = false(nRows, 1);
            for i = 1:nRows
                for j = 1:size(obj.FullTableData, 2)
                    val = obj.FullTableData{i, j};
                    if ischar(val) && contains(lower(val), q)
                        keep(i) = true; break;
                    elseif isnumeric(val) && contains(num2str(val), q)
                        keep(i) = true; break;
                    end
                end
            end
            app.CircuitsTable.Data = obj.FullTableData(keep, :);
            idx = find(keep);
            obj.RowCircuitIds = obj.FullRowIds(idx);
            obj.RowCircuits   = obj.FullRowData(idx);
        end

        function onCellSelected(obj, src, evt)
            % Select the entire row when any cell is clicked
            if isempty(evt.Indices); return; end
            row = evt.Indices(1,1);
            src.Selection = row;
        end

        function onContextAnalyze(obj)
            % Triggered from context menu — analyze the selected circuit
            app = obj.App;
            row = obj.getSelectedRow();
            if row < 1 || row > numel(obj.RowCircuitIds); return; end
            cid   = obj.RowCircuitIds{row};
            cname = char(string(JsonHelper.pick(obj.RowCircuits{row}, {'name','circuit_name'})));
            app.State.selectedCircuitId   = string(cid);
            app.State.selectedCircuitName = string(cname);
            app.onSelectSection('Analysis');
            drawnow;
            if ~isempty(app.AnalysisVm)
                items = app.AnalysisCircuitDropdown.ItemsData;
                idx = find(strcmp(items, cid), 1);
                if ~isempty(idx)
                    app.AnalysisCircuitDropdown.Value = cid;
                    app.AnalysisVm.onCircuitSelected(cid);
                end
                app.AnalysisVm.onAnalyzeCircuit();
            end
        end

        function onContextEdit(obj)
            % Triggered from context menu — edit the selected row
            row = obj.getSelectedRow();
            if row > 0; obj.onEditCircuit(row); end
        end

        function onContextDelete(obj)
            % Triggered from context menu — delete the selected row
            row = obj.getSelectedRow();
            if row > 0; obj.onDeleteCircuit(row); end
        end

        function onEditCircuit(obj, row)
            % Show professional edit dialog (matches Edit Project style)
            app = obj.App;
            if row > numel(obj.RowCircuits); return; end
            c   = obj.RowCircuits{row};
            cid = obj.RowCircuitIds{row};

            curName = char(string(JsonHelper.pick(c, {'name','circuit_name'})));
            curCat  = char(string(JsonHelper.safeField(c, 'category', '')));
            curSrc  = char(string(JsonHelper.safeField(c, 'source', '')));
            curFmt  = char(string(JsonHelper.safeField(c, 'format', '')));
            curQb   = JsonHelper.safeField(c, 'num_qubits', '');
            if isnumeric(curQb); curQb = num2str(curQb); else; curQb = char(string(curQb)); end
            curDp   = JsonHelper.safeField(c, 'depth', '');
            if isnumeric(curDp); curDp = num2str(curDp); else; curDp = char(string(curDp)); end

            % Fetch full circuit record (includes raw_content)
            curContent = '';
            try
                full = app.CircuitSvc.getCircuit(cid, app.State.authToken);
                curContent = char(string(JsonHelper.safeField(full, 'raw_content', '')));
            catch
                % raw_content not available — leave empty
            end

            % ── Build modal dialog ───────────────────────────────────
            figPos = app.UIFigure.Position;
            dlgW = 560; dlgH = 680;
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor    = Theme.COLOR_BG;
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;
            titleColor = Theme.COLOR_HEADING;
            subtColor  = Theme.COLOR_MUTED;
            labelColor = Theme.COLOR_LABEL;
            accentBlue = Theme.COLOR_PRIMARY;

            dlg = uifigure( ...
                'Name', 'Edit Circuit', ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'off', ...
                'Color', bgColor);
            Theme.applyFigureMode(dlg, Theme.activeName());

            outerGrid = uigridlayout(dlg, [3 3]);
            outerGrid.RowHeight     = {16, '1x', 16};
            outerGrid.ColumnWidth   = {24, '1x', 24};
            outerGrid.Padding       = [0 0 0 0];
            outerGrid.RowSpacing    = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = bgColor;

            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, ...
                'HighlightColor', cardBorder, ...
                'BorderColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            cg = uigridlayout(card, [14 1]);
            cg.RowHeight = {28, 18, 10, ...
                            16, 34, ...
                            16, 34, ...
                            16, 34, ...
                            28, ...
                            16, '1x', ...
                            42, 18};
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [36 24 36 20];
            cg.RowSpacing  = 2;
            cg.BackgroundColor = cardBg;

            % Title + subtitle
            tmp = uilabel(cg, 'Text', 'Edit Circuit', ...
                'FontSize', 19, 'FontWeight', 'bold', ...
                'FontColor', titleColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
            tmp.Layout.Row = 1;

            tmp = uilabel(cg, 'Text', 'Update circuit metadata and QASM content', ...
                'FontSize', 11, 'FontColor', subtColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            tmp.Layout.Row = 2;

            % Circuit Name
            tmp = uilabel(cg, 'Text', 'Circuit Name', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, 'VerticalAlignment', 'bottom');
            tmp.Layout.Row = 4;
            nameField = uieditfield(cg, 'text', 'Value', curName, 'FontSize', 13);
            nameField.Layout.Row = 5;

            % Category + Format (side by side — labels row)
            cfLblGrid = uigridlayout(cg, [1 2]);
            cfLblGrid.Layout.Row = 6;
            cfLblGrid.ColumnWidth = {'1x', '1x'}; cfLblGrid.Padding = [0 0 0 0];
            cfLblGrid.ColumnSpacing = 12; cfLblGrid.BackgroundColor = cardBg;
            uilabel(cfLblGrid, 'Text', 'Category', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, 'VerticalAlignment', 'bottom');
            uilabel(cfLblGrid, 'Text', 'Format', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, 'VerticalAlignment', 'bottom');

            % Category + Format (side by side — fields row)
            cfGrid = uigridlayout(cg, [1 2]);
            cfGrid.Layout.Row = 7;
            cfGrid.ColumnWidth = {'1x', '1x'}; cfGrid.Padding = [0 0 0 0];
            cfGrid.ColumnSpacing = 12; cfGrid.BackgroundColor = cardBg;

            catItems = {'Oracle', 'Fourier', 'Sampling', 'Optimization', ...
                'Search', 'Simulation', 'Entanglement', 'Arithmetic', ...
                'QEC', 'ML', 'Other'};
            catField = uidropdown(cfGrid, 'Items', catItems, 'Editable', 'on', 'FontSize', 13);
            if ~isempty(curCat); catField.Value = curCat; end

            fmtItems     = {'OpenQASM 2.0', 'OpenQASM 3', 'Qiskit JSON', 'MATLAB struct'};
            fmtItemsData = {'qasm2',        'qasm3',      'json',        'matlab'};
            fmtField = uidropdown(cfGrid, ...
                'Items', fmtItems, 'ItemsData', fmtItemsData, 'FontSize', 13);
            if ismember(curFmt, fmtItemsData)
                fmtField.Value = curFmt;
            else
                fmtField.Value = 'qasm2';
            end

            % Source
            tmp = uilabel(cg, 'Text', 'Source', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, 'VerticalAlignment', 'bottom');
            tmp.Layout.Row = 8;
            srcField = uieditfield(cg, 'text', 'Value', curSrc, 'FontSize', 13);
            srcField.Layout.Row = 9;

            % Read-only info: Qubits / Depth
            infoGrid = uigridlayout(cg, [1 4]);
            infoGrid.Layout.Row = 10;
            infoGrid.ColumnWidth = {'fit', 'fit', 'fit', '1x'};
            infoGrid.Padding = [0 0 0 0]; infoGrid.ColumnSpacing = 6;
            infoGrid.BackgroundColor = cardBg;
            uilabel(infoGrid, 'Text', 'Qubits', 'FontSize', 11, 'FontColor', subtColor);
            uilabel(infoGrid, 'Text', curQb, 'FontSize', 11, 'FontColor', accentBlue, 'FontWeight', 'bold');
            uilabel(infoGrid, 'Text', 'Depth', 'FontSize', 11, 'FontColor', subtColor);
            uilabel(infoGrid, 'Text', curDp, 'FontSize', 11, 'FontColor', accentBlue, 'FontWeight', 'bold');

            % Circuit Content (QASM editor)
            tmp = uilabel(cg, 'Text', 'Circuit Content (OpenQASM)', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, 'VerticalAlignment', 'bottom');
            tmp.Layout.Row = 11;
            contentField = uitextarea(cg, 'Value', curContent, ...
                'FontSize', 12, 'FontName', 'Courier New');
            contentField.Layout.Row = 12;

            % Button bar
            btnBar = uigridlayout(cg, [1 2]);
            btnBar.Layout.Row = 13;
            btnBar.ColumnWidth = {'1x', '1x'};
            btnBar.Padding = [0 0 0 0]; btnBar.ColumnSpacing = 12;
            btnBar.BackgroundColor = cardBg;

            cancelBtn = uibutton(btnBar, 'Text', [char(10006) ' Cancel'], ...
                'ButtonPushedFcn', @(~,~)delete(dlg));
            cancelBtn.Layout.Row = 1; cancelBtn.Layout.Column = 1;
            app.styleBtn(cancelBtn, 'ghost');

            saveBtn = uibutton(btnBar, 'Text', [char(10004) ' Save'], ...
                'ButtonPushedFcn', @(~,~)obj.doSaveCircuit( ...
                    dlg, statusLbl, cid, nameField, catField, srcField, ...
                    fmtField, contentField, row));
            saveBtn.Layout.Row = 1; saveBtn.Layout.Column = 2;
            app.styleBtn(saveBtn, 'primary');

            % Status label
            statusLbl = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', Theme.COLOR_DANGER, ...
                'WordWrap', 'on', 'HorizontalAlignment', 'center');
            statusLbl.Layout.Row = 14;
        end

        function onDeleteCircuit(obj, row)
            % Show delete confirmation dialog
            app = obj.App;
            if row > numel(obj.RowCircuitIds); return; end
            cid  = obj.RowCircuitIds{row};
            cname = '';
            if row <= numel(obj.RowCircuits)
                cname = char(string(JsonHelper.pick(obj.RowCircuits{row}, {'name','circuit_name'})));
            end

            answer = uiconfirm(app.UIFigure, ...
                sprintf('Delete circuit "%s"?\n\nThis action cannot be undone.', cname), ...
                'Delete Circuit', ...
                'Options', {'Cancel', 'Delete'}, ...
                'DefaultOption', 'Cancel', ...
                'CancelOption', 'Cancel', ...
                'Icon', 'warning');
            if strcmp(answer, 'Delete')
                obj.doDeleteCircuit(cid, row);
            end
        end
    end

    methods (Access = private)
        function row = getSelectedRow(obj)
            % Return the currently selected table row, or 0 if none
            app = obj.App;
            sel = app.CircuitsTable.Selection;
            if isempty(sel)
                row = 0;
            else
                row = sel(1);
            end
        end

        function doSaveCircuit(obj, dlg, statusLbl, cid, nameField, catField, srcField, fmtField, contentField, row)
            app = obj.App;
            patch = struct();
            patch.name     = char(strtrim(nameField.Value));
            patch.category = char(strtrim(catField.Value));
            patch.source   = char(strtrim(srcField.Value));
            patch.format   = char(fmtField.Value);
            % Join textarea lines into single string
            cVal = contentField.Value;
            if iscell(cVal)
                patch.raw_content = char(strjoin(string(cVal), newline));
            else
                patch.raw_content = char(cVal);
            end

            if isempty(patch.name)
                statusLbl.Text = Labels.get('circuits_error_name_empty', 'Circuit name cannot be empty.');
                return;
            end

            try
                statusLbl.Text = Labels.get('circuits_status_saving', 'Saving...');
                statusLbl.FontColor = Theme.COLOR_MUTED;
                drawnow;
                app.CircuitSvc.updateCircuit(cid, patch, app.State.authToken);
                app.logEvent('API', sprintf('Circuit updated: %s', cid));
                delete(dlg);
                obj.onLoadCircuits();
            catch ME
                statusLbl.Text = sprintf('%s %s', Labels.get('circuits_error_save_failed', 'Save failed:'), ME.message);
                statusLbl.FontColor = Theme.COLOR_DANGER;
                app.logEvent('ERROR', sprintf('updateCircuit FAILED: %s', ME.message));
            end
        end

        function doDeleteCircuit(obj, cid, ~)
            app = obj.App;
            app.showLoading(Labels.get('loading_circuits_delete', 'Deleting circuit...'));
            svc   = app.CircuitSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.deleteCircuit(cid, token), ...
                @(~) obj.onDeleteComplete(app, cid), ...
                @(ME) obj.onDeleteError(app, ME));
        end

        function onLoadCircuitsComplete(obj, app, data)
            app.hideLoading();
            circuits = JsonHelper.extractList(data, 'circuits');
            if isempty(circuits)
                app.CircuitsTable.Data = {};
                obj.RowCircuitIds = {};
                obj.RowCircuits   = {};
                % Project is active but the API returned no circuits.
                % Distinguish from "no project" by showing the upload-hint
                % message instead of the welcome-screen-hint message.
                obj.setEmptyStateMessage('circuits_empty_no_circuits');
                obj.updatePageLabel();
                return;
            end
            % Data loaded — clear any previous empty-state banner.
            obj.setEmptyStateMessage('');
            if isstruct(circuits)
                circuits = num2cell(circuits);
            end
            n = numel(circuits);
            tableData = cell(n, 8);
            ids   = cell(1, n);
            cdata = cell(1, n);
            for i = 1:n
                c = circuits{i};
                tableData{i,1} = obj.PageSkip + i;
                if isstruct(c)
                    cid = char(string(JsonHelper.pick(c, {'circuit_id','id'})));
                    ids{i}   = cid;
                    cdata{i} = c;
                    tableData{i,2} = char(string(JsonHelper.pick(c, {'name','circuit_name'})));
                    fmt = JsonHelper.safeField(c, 'format', '');
                    tableData{i,3} = char(string(fmt));
                    fmtStr = lower(char(string(fmt)));
                    if contains(fmtStr, '3')
                        tableData{i,4} = '3.0';
                    elseif contains(fmtStr, '2') || contains(fmtStr, 'qasm')
                        tableData{i,4} = '2.0';
                    else
                        tableData{i,4} = char(string(fmt));
                    end
                    cat = JsonHelper.safeField(c, 'category', '');
                    tableData{i,5} = char(string(cat));
                    nq = JsonHelper.safeField(c, 'num_qubits', '');
                    if isnumeric(nq); tableData{i,6} = num2str(nq); else; tableData{i,6} = char(string(nq)); end
                    dp = JsonHelper.safeField(c, 'depth', '');
                    if isnumeric(dp); tableData{i,7} = num2str(dp); else; tableData{i,7} = char(string(dp)); end
                    tableData{i,8} = char(string(JsonHelper.safeField(c, 'created_at', '')));
                end
            end
            obj.RowCircuitIds = ids;
            obj.RowCircuits   = cdata;
            obj.FullTableData = tableData;
            obj.FullRowIds    = ids;
            obj.FullRowData   = cdata;
            app.CircuitsTable.Data = tableData;
            % Re-apply active search filter if any
            if ~isempty(app.CircuitsSearchField) && isvalid(app.CircuitsSearchField)
                q = strtrim(app.CircuitsSearchField.Value);
                if strlength(q) > 0
                    obj.onSearch(char(q));
                end
            end
            app.logEvent('API', sprintf('listCircuitsPaged → %d circuits loaded', n));
            obj.LastRefresh = tic;
            obj.updatePageLabel();
        end

        function onLoadCircuitsError(obj, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('listCircuitsPaged FAILED: %s', ME.message));
            obj.updatePageLabel();
        end

        function onDeleteComplete(obj, app, cid)
            app.logEvent('API', sprintf('Circuit deleted: %s', cid));
            app.State.logActivity(sprintf('Delete circuit — %s', char(cid)), 'Success');
            app.hideLoading();
            obj.onLoadCircuits();
        end

        function onDeleteError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('deleteCircuit FAILED: %s', ME.message));
            app.showError('Delete Circuit', ME);
        end

        function updatePageLabel(obj)
            app = obj.App;
            if isempty(app.CircuitsPageLabel) || ~isvalid(app.CircuitsPageLabel)
                return;
            end
            pageNum = floor(obj.PageSkip / obj.PageLimit) + 1;
            app.CircuitsPageLabel.Text = sprintf('Page %d', pageNum);
            if ~isempty(app.CircuitsPrevBtn) && isvalid(app.CircuitsPrevBtn)
                app.CircuitsPrevBtn.Enable = obj.PageSkip > 0;
            end
            if ~isempty(app.CircuitsNextBtn) && isvalid(app.CircuitsNextBtn)
                tData = app.CircuitsTable.Data;
                if isempty(tData)
                    app.CircuitsNextBtn.Enable = false;
                else
                    app.CircuitsNextBtn.Enable = size(tData, 1) >= obj.PageLimit;
                end
            end
        end

        function setEmptyStateMessage(obj, key)
            % Drive the empty-state banner that sits above the table.
            % `key` is a labels.properties key; pass '' to clear.  The
            % isprop / isvalid guards keep this safe against partially-
            % built screens (lazy nav) and stub apps used by tests.
            app = obj.App;
            if ~isprop(app, 'CircuitsEmptyStateLabel'); return; end
            if isempty(app.CircuitsEmptyStateLabel); return; end
            if ~isvalid(app.CircuitsEmptyStateLabel); return; end
            if isempty(key)
                app.CircuitsEmptyStateLabel.Text = '';
                return;
            end
            switch key
                case 'circuits_empty_not_auth'
                    fallback = 'Sign in to view circuits.';
                case 'circuits_empty_no_project'
                    fallback = 'No project selected — pick one on the Welcome screen first.';
                case 'circuits_empty_no_circuits'
                    fallback = 'No circuits in this project yet — go to Upload to add one.';
                otherwise
                    fallback = '';
            end
            app.CircuitsEmptyStateLabel.Text = Labels.get(key, fallback);
        end
    end
end
