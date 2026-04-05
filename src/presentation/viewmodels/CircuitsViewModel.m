classdef CircuitsViewModel < handle
    % CircuitsViewModel  Callbacks for the Circuits screen.
    %
    %   Loads a paginated list of circuits from the API and populates the
    %   CircuitsTable.  Supports Prev / Next page navigation and a quick
    %   jump to the Upload screen.

    properties (Access = private)
        App
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
            if ~app.State.isAuthenticated() || ~app.State.hasProject()
                app.CircuitsTable.Data = {};
                obj.updatePageLabel();
                return;
            end
            app.logEvent('API', sprintf('GET /api/circuits?skip=%d&limit=%d — project: %s', ...
                obj.PageSkip, obj.PageLimit, char(app.State.currentProjectId)));
            try
                data = app.CircuitSvc.listCircuitsPaged(obj.PageSkip, obj.PageLimit, ...
                    app.State.authToken);
                circuits = JsonHelper.extractList(data, 'circuits');
                if isempty(circuits)
                    app.CircuitsTable.Data = {};
                    obj.updatePageLabel();
                    return;
                end
                if isstruct(circuits)
                    circuits = num2cell(circuits);
                end
                n = numel(circuits);
                tableData = cell(n, 8);
                for i = 1:n
                    c = circuits{i};
                    if isstruct(c)
                        tableData{i,1} = char(string(JsonHelper.pick(c, {'circuit_id','id'})));
                        tableData{i,2} = char(string(JsonHelper.pick(c, {'name','circuit_name'})));
                        fmt = JsonHelper.safeField(c, 'format', '');
                        tableData{i,3} = char(string(fmt));
                        % Derive OpenQASM version from format field
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
                app.CircuitsTable.Data = tableData;
                app.logEvent('API', sprintf('listCircuitsPaged → %d circuits loaded', n));
            catch ME
                app.logEvent('ERROR', sprintf('listCircuitsPaged FAILED: %s', ME.message));
            end
            obj.updatePageLabel();
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
    end

    methods (Access = private)
        function updatePageLabel(obj)
            app = obj.App;
            if isempty(app.CircuitsPageLabel) || ~isvalid(app.CircuitsPageLabel)
                return;
            end
            pageNum = floor(obj.PageSkip / obj.PageLimit) + 1;
            app.CircuitsPageLabel.Text = sprintf('Page %d', pageNum);
            % Enable/disable prev button
            if ~isempty(app.CircuitsPrevBtn) && isvalid(app.CircuitsPrevBtn)
                app.CircuitsPrevBtn.Enable = obj.PageSkip > 0;
            end
            % Disable next if fewer rows than limit
            if ~isempty(app.CircuitsNextBtn) && isvalid(app.CircuitsNextBtn)
                tData = app.CircuitsTable.Data;
                if isempty(tData)
                    app.CircuitsNextBtn.Enable = false;
                else
                    app.CircuitsNextBtn.Enable = size(tData, 1) >= obj.PageLimit;
                end
            end
        end
    end
end
