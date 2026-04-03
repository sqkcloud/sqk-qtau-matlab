classdef AnalysisViewModel < handle
    % AnalysisViewModel  Callback handlers for the Analysis screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = AnalysisViewModel(app)
            obj.App = app;
        end

        function onEnter(obj)
            % Called when navigating to the Analysis screen — load circuits
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            app.logEvent('API', 'GET /api/circuits — loading circuit list for Analysis');
            app.showLoading(Labels.get('loading_circuits', 'Loading circuits...'));
            try
                data = app.CircuitSvc.listCircuits(app.State.authToken);
                items = JsonHelper.extractList(data, 'circuits');
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n == 0
                    app.AnalysisCircuitDropdown.Items     = {'(no circuits)'};
                    app.AnalysisCircuitDropdown.ItemsData = {''};
                    return;
                end
                names = cell(1, n);
                ids   = cell(1, n);
                for i = 1:n
                    cid  = char(JsonHelper.pick(items(i), {'circuit_id','id'}));
                    cname = char(JsonHelper.pick(items(i), {'name','circuit_name'}));
                    if isempty(cname); cname = cid; end
                    names{i} = cname;
                    ids{i}   = cid;
                end
                app.AnalysisCircuitDropdown.Items     = names;
                app.AnalysisCircuitDropdown.ItemsData = ids;
                % Auto-select the first circuit
                app.AnalysisCircuitDropdown.Value = ids{1};
                obj.onCircuitSelected(ids{1});
                app.logEvent('API', sprintf('Circuit list loaded — %d circuit(s), auto-selected: %s', n, names{1}));
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('WARN', sprintf('Failed to load circuits: %s', ME.message));
            end
        end

        function onCircuitSelected(obj, circuitId)
            app = obj.App;
            if isempty(circuitId); return; end
            app.State.selectedCircuitId   = string(circuitId);
            app.State.selectedCircuitName = string(app.AnalysisCircuitDropdown.Value);
            % Find display name from Items
            idx = find(strcmp(app.AnalysisCircuitDropdown.ItemsData, circuitId), 1);
            if ~isempty(idx)
                app.State.selectedCircuitName = string(app.AnalysisCircuitDropdown.Items{idx});
            end
            app.logEvent('UI', sprintf('Circuit selected: %s (%s)', ...
                char(app.State.selectedCircuitName), circuitId));
        end

        function onAnalyzeCircuit(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Analyze', 'Icon', 'warning'); return;
            end
            if ~app.State.hasCircuit()
                uialert(app.UIFigure, Labels.get('error_no_circuit'), 'Analyze', 'Icon', 'warning'); return;
            end
            cid = app.State.selectedCircuitId;
            app.logEvent('API', sprintf('POST /api/circuits/%s/analyze — circuit: %s  name: %s', ...
                cid, cid, app.State.selectedCircuitName));
            app.showLoading(Labels.get('loading_analyzing', 'Analyzing circuit...'));
            try
                data = app.CircuitSvc.analyzeCircuit(cid, app.State.authToken);
                obj.applyAnalysisData(data);
                obj.applyBenchmarkMatches(data);
                app.logEvent('API', sprintf('Circuit analysis complete — circuit: %s', cid));
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Analysis FAILED (circuit: %s): %s', cid, ME.message));
                app.showError('Analyze Circuit', ME);
            end
        end
    end

    methods (Access = private)
        function applyAnalysisData(obj, data)
            app = obj.App;
            delete(app.FeatureTree.Children);
            try
                name  = char(JsonHelper.pick(data, {'circuit_name','name'}));
                depth = char(JsonHelper.pick(data, {'depth'}));
                width = char(JsonHelper.pick(data, {'num_qubits','width'}));
                sq    = char(JsonHelper.pick(data, {'single_qubit_gates','num_1q'}));
                tq    = char(JsonHelper.pick(data, {'two_qubit_gates','num_2q','cx_count'}));
                meas  = char(JsonHelper.pick(data, {'measurements','num_measurements'}));
                par   = char(JsonHelper.pick(data, {'parallelism_score','parallelism'}));
                coup  = char(JsonHelper.pick(data, {'coupling_pressure'}));

                root = uitreenode(app.FeatureTree, 'Text', name);
                arch = uitreenode(root, 'Text', 'Structure');
                    uitreenode(arch, 'Text', sprintf('Depth: %s', depth));
                    uitreenode(arch, 'Text', sprintf('Width: %s qubits', width));
                gc = uitreenode(root, 'Text', 'Gate counts');
                    uitreenode(gc, 'Text', sprintf('Single-qubit: %s', sq));
                    uitreenode(gc, 'Text', sprintf('Two-qubit: %s', tq));
                    uitreenode(gc, 'Text', sprintf('Measurement: %s', meas));
                qf = uitreenode(root, 'Text', 'Quantum features');
                    uitreenode(qf, 'Text', sprintf('Parallelism score: %s', par));
                    uitreenode(qf, 'Text', sprintf('Coupling pressure: %s', coup));
                expand(root); expand(arch); expand(gc); expand(qf);
            catch ME
                Logger.warn('AnalysisViewModel', 'applyAnalysisData tree build failed: %s', ME.message);
                uitreenode(app.FeatureTree, 'Text', JsonHelper.pretty(data));
            end
        end

        function applyBenchmarkMatches(obj, data)
            app = obj.App;
            try
                items = JsonHelper.extractList(data, 'benchmark_matches');
                if isempty(items); items = JsonHelper.extractList(data, 'matches'); end
                if isempty(items); items = JsonHelper.asList(data); end
                n = numel(items);
                if n == 0; return; end
                rows = cell(n, 4);
                for i = 1:n
                    rows{i,1} = char(JsonHelper.pick(items(i), {'benchmark_name','name'}));
                    rows{i,2} = JsonHelper.toDouble(JsonHelper.pick(items(i), {'similarity','score'}));
                    rows{i,3} = char(JsonHelper.pick(items(i), {'category'}));
                    rows{i,4} = char(JsonHelper.pick(items(i), {'notes','comment'}));
                end
                app.SimilarityTable.Data = rows;
            catch ME
                Logger.warn('AnalysisViewModel', 'applyBenchmarkMatches failed: %s', ME.message);
            end
        end
    end
end
