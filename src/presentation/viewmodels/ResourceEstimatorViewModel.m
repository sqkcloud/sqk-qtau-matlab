classdef ResourceEstimatorViewModel < handle
    % ResourceEstimatorViewModel  Fault-tolerant resource overhead
    %                              planner. Wraps ResourceEstimatorService
    %                              with a UI surface that lets the user
    %                              point at either an uploaded circuit
    %                              or the live Composer model and tune
    %                              the FT parameters (physical err,
    %                              target logical err, cycle time).

    properties
        LastRefresh = []
    end

    properties
        RootGrid

        CircuitDropdown
        CodeDropdown
        PhysErrField
        LogErrField
        CycleField
        EstimateBtn
        StatusLbl

        % Logical card
        LblLogicalQubits
        LblTGates
        LblToffolis
        LblRotations
        LblClifford

        % Physical card
        LblDistance
        LblPerLogical
        LblTotalPhys
        LblFactories

        % Runtime card
        LblLayers
        LblLatticeCycles
        LblTotalRuntime

        PieGrid          % parent for the lazy uiaxes (built on first repaintPie)
        PiePlaceholder   % uilabel shown until the uiaxes materialises
        PieAxes
        InsightLbl
    end

    properties
        Circuits      = []
        LastResult    = []
        LastModel     = []
    end

    properties (Access = private)
        App
    end

    methods
        function obj = ResourceEstimatorViewModel(app)
            obj.App = app;
        end

        function bindRootGrid(obj, g)
            obj.RootGrid = g;
        end

        function onEnter(obj)
            state = obj.App.State;
            ttl   = AppConfig.getDouble('shared_cache_ttl', 120);
            % Cache hit — paint dropdown synchronously, no HTTP.
            if state.isCircuitsListCacheFresh(ttl)
                obj.onCircuitsLoaded(state.CircuitListCache);
                return;
            end
            obj.flashStatus('Loading circuits…', 'info');
            token = state.authToken;
            circSvc = obj.App.Services.CircuitSvc;
            AsyncRunner.run( ...
                @() circSvc.listCircuits(token), ...
                @(r) obj.onCircuitsLoaded(r), ...
                @(ME) obj.flashStatus(sprintf('Failed to load circuits: %s', ME.message), 'danger'));
        end

        function onCircuitsLoaded(obj, raw)
            % Write-through to the shared cache so Mitigation Compare /
            % Run Planner can render from cache on their next visit.
            try; obj.App.State.setCircuitsListCache(raw); catch; end
            obj.Circuits = ResourceEstimatorViewModel.normalizeList(raw);
            obj.populateCircuitDropdown();
            obj.LastRefresh = tic;
            obj.flashStatus(Labels.get('resource_estimator_status_idle'), 'info');
        end

        function onPickCircuit(~, ~); end
        function onPickCode(~, ~); end

        function onEstimate(obj)
            model = obj.resolveSourceModel();
            if isempty(model)
                obj.flashStatus('Pick a circuit first.', 'danger'); return;
            end
            params = obj.collectParams();
            if strcmp(params.codeType, 'steane')
                obj.flashStatus(Labels.get('resource_estimator_status_steane'), 'danger');
                return;
            end
            try
                obj.LastResult = ResourceEstimatorService.estimate(model, params);
                obj.LastModel  = model;
                obj.repaintCards();
                obj.repaintPie();
                obj.repaintInsights();
                obj.flashStatus(sprintf( ...
                    Labels.get('resource_estimator_status_done_fmt'), ...
                    numel(model.Gates), obj.LastResult.distance, obj.LastResult.totalPhysical), ...
                    'success');
                obj.App.logEvent('FT-EST', sprintf( ...
                    'Estimated %dq → d=%d → %d phys', ...
                    obj.LastResult.logicalQubits, obj.LastResult.distance, ...
                    obj.LastResult.totalPhysical));
            catch ME
                obj.flashStatus(ME.message, 'danger');
            end
        end
    end

    methods (Access = private)
        function model = resolveSourceModel(obj)
            model = [];
            if isempty(obj.CircuitDropdown) || ~isvalid(obj.CircuitDropdown); return; end
            v = obj.CircuitDropdown.Value;
            if isequal(v, '__composer__')
                if ~isempty(obj.App.ComposerVm) && ~isempty(obj.App.ComposerVm.Model)
                    model = obj.App.ComposerVm.Model;
                end
                return;
            end
            for i = 1:numel(obj.Circuits)
                cid = ResourceEstimatorViewModel.safeField(obj.Circuits(i), 'id', '');
                if strcmp(cid, v)
                    qasm = ResourceEstimatorViewModel.safeField(obj.Circuits(i), 'raw_content', '');
                    if isempty(qasm)
                        nq = ResourceEstimatorViewModel.safeField(obj.Circuits(i), 'num_qubits', 1);
                        model = CircuitModel(double(nq));
                        return;
                    end
                    try
                        model = CircuitModel.fromQasm(qasm);
                    catch
                        nq = ResourceEstimatorViewModel.safeField(obj.Circuits(i), 'num_qubits', 1);
                        model = CircuitModel(double(nq));
                    end
                    return;
                end
            end
        end

        function p = collectParams(obj)
            codeId = 'surface';
            if ~isempty(obj.CodeDropdown) && isvalid(obj.CodeDropdown)
                codeId = char(obj.CodeDropdown.Value);
            end
            p = struct( ...
                'codeType',     codeId, ...
                'physErr',      max(1e-7, min(1e-1, obj.PhysErrField.Value)), ...
                'logErr',       max(1e-30, min(0.5, obj.LogErrField.Value)), ...
                'cycleSeconds', max(1e-9, obj.CycleField.Value * 1e-6));   % UI is µs
        end

        function populateCircuitDropdown(obj)
            if isempty(obj.CircuitDropdown) || ~isvalid(obj.CircuitDropdown); return; end
            items = {Labels.get('resource_estimator_circuit_composer')};
            ids   = {'__composer__'};
            for i = 1:numel(obj.Circuits)
                c = obj.Circuits(i);
                name = ResourceEstimatorViewModel.safeField(c, 'name', '?');
                nq   = ResourceEstimatorViewModel.safeField(c, 'num_qubits', 0);
                cid  = ResourceEstimatorViewModel.safeField(c, 'id', '');
                items{end+1} = sprintf('%s (%dq)', char(string(name)), double(nq)); %#ok<AGROW>
                ids{end+1}   = char(string(cid)); %#ok<AGROW>
            end
            obj.CircuitDropdown.Items     = items;
            obj.CircuitDropdown.ItemsData = ids;
            if isempty(obj.CircuitDropdown.Value)
                obj.CircuitDropdown.Value = '__composer__';
            end
        end

        function repaintCards(obj)
            r = obj.LastResult; if isempty(r); return; end
            obj.LblLogicalQubits.Text = sprintf('%d', r.logicalQubits);
            obj.LblTGates.Text        = sprintf('%d', r.tGates);
            obj.LblToffolis.Text      = sprintf('%d', r.toffolis);
            obj.LblRotations.Text     = sprintf('%d (≈ %d T-states)', ...
                r.rotations, r.tGatesFromRotations);
            if r.cliffordOnly
                obj.LblClifford.Text = Labels.get('resource_estimator_lbl_yes');
                obj.LblClifford.FontColor = Theme.COLOR_SUCCESS;
            else
                obj.LblClifford.Text = Labels.get('resource_estimator_lbl_no');
                obj.LblClifford.FontColor = Theme.COLOR_WARNING;
            end

            obj.LblDistance.Text     = sprintf('%d', r.distance);
            obj.LblPerLogical.Text   = sprintf('%d', r.physicalPerLogical);
            obj.LblTotalPhys.Text    = sprintf('%s', ResourceEstimatorViewModel.fmtInt(r.totalPhysical));
            obj.LblFactories.Text    = sprintf('%d', r.tFactories);

            obj.LblLayers.Text         = sprintf('%d', r.depth);
            obj.LblLatticeCycles.Text  = sprintf('%d', r.latticeCycles);
            obj.LblTotalRuntime.Text   = ResourceEstimatorViewModel.fmtSeconds(r.totalSeconds);
        end

        function repaintPie(obj)
            r = obj.LastResult;
            if isempty(r); return; end
            ax = obj.PieAxes;
            if isempty(ax) || ~isvalid(ax)
                % Lazy build — buildPie ships a uilabel placeholder to
                % keep screen-mount fast. Pay the uiaxes construction
                % cost here, inside the Estimate-click flow the user
                % is already watching.
                if isempty(obj.PieGrid) || ~isvalid(obj.PieGrid); return; end
                if ~isempty(obj.PiePlaceholder) && isvalid(obj.PiePlaceholder)
                    delete(obj.PiePlaceholder);
                    obj.PiePlaceholder = [];
                end
                ax = uiaxes(obj.PieGrid);
                ax.Toolbar.Visible = 'off';
                ax.Color  = Theme.COLOR_CARD;
                ax.XColor = Theme.COLOR_MUTED;
                ax.YColor = Theme.COLOR_MUTED;
                ax.Box = 'off'; ax.XTick = []; ax.YTick = [];
                try; disableDefaultInteractivity(ax); catch; end
                obj.PieAxes = ax;
            end
            cla(ax);
            slices = [r.dataQubits, r.ancillaQubits, max(0, r.factoryQubits)];
            labels = { ...
                Labels.get('resource_estimator_pie_data'), ...
                Labels.get('resource_estimator_pie_ancilla'), ...
                Labels.get('resource_estimator_pie_factory')};
            mask = slices > 0;
            slices = slices(mask); labels = labels(mask);
            if isempty(slices); return; end
            colors = [0.30 0.55 0.85; 0.55 0.70 0.90; 0.85 0.55 0.30];
            colors = colors(mask, :);
            try
                p = pie(ax, slices, labels);
                k = 1;
                for i = 1:numel(p)
                    if isa(p(i), 'matlab.graphics.primitive.Patch')
                        p(i).FaceColor = colors(min(k, size(colors, 1)), :);
                        p(i).EdgeColor = 'none';
                        k = k + 1;
                    end
                end
            catch
                % older MATLAB pie path — fallback no-op
            end
            ax.Color = Theme.COLOR_CARD;
        end

        function repaintInsights(obj)
            r = obj.LastResult; if isempty(r); return; end
            lines = {};
            if r.cliffordOnly
                lines{end+1} = Labels.get('resource_estimator_insight_clifford');
            end
            lines{end+1} = sprintf( ...
                Labels.get('resource_estimator_insight_distance_fmt'), ...
                r.distance, r.physicalPerLogical);
            scaleNote = Labels.get('resource_estimator_insight_total_near');
            if r.totalPhysical > 1e4
                scaleNote = Labels.get('resource_estimator_insight_total_mid');
            end
            if r.totalPhysical > 1e6
                scaleNote = Labels.get('resource_estimator_insight_total_far');
            end
            lines{end+1} = sprintf( ...
                Labels.get('resource_estimator_insight_total_fmt'), ...
                r.totalPhysical, scaleNote);
            obj.InsightLbl.Text = strjoin(lines, sprintf('\n'));
        end

        function flashStatus(obj, msg, level)
            if isempty(obj.StatusLbl) || ~isvalid(obj.StatusLbl); return; end
            obj.StatusLbl.Text = char(msg);
            switch char(level)
                case 'danger';  obj.StatusLbl.FontColor = Theme.COLOR_DANGER;
                case 'success'; obj.StatusLbl.FontColor = Theme.COLOR_SUCCESS;
                case 'info';    obj.StatusLbl.FontColor = Theme.COLOR_PRIMARY;
                otherwise;      obj.StatusLbl.FontColor = Theme.COLOR_LABEL;
            end
        end
    end

    methods (Static)
        function arr = normalizeList(raw)
            % Accepts three FastAPI response shapes:
            %   1. envelope struct {circuits|items|data: [...]}
            %   2. bare cell array
            %   3. bare struct (single record) or struct array
            % Without envelope unwrapping the circuits dropdown appeared
            % empty because the wrapper struct counts as 1 element and
            % its fields are not iterated.
            if isempty(raw); arr = []; return; end
            if isstruct(raw) && isscalar(raw)
                envelopeKeys = {'circuits', 'backends', 'levels', 'items', 'data'};
                for k = 1:numel(envelopeKeys)
                    f = envelopeKeys{k};
                    if isfield(raw, f) && ~isempty(raw.(f))
                        raw = raw.(f);
                        break;
                    end
                end
            end
            if iscell(raw)
                try; arr = [raw{:}]; catch; arr = raw; end
            else
                arr = raw;
            end
        end

        function v = safeField(s, field, def)
            v = def;
            try
                if isstruct(s) && isfield(s, field)
                    v = s.(field);
                elseif isobject(s) && isprop(s, field)
                    v = s.(field);
                end
            catch
            end
            if isempty(v); v = def; end
        end

        function txt = fmtInt(n)
            if ~isnumeric(n) || ~isfinite(n); txt = '—'; return; end
            if n >= 1e9
                txt = sprintf('%.2fB', n/1e9);
            elseif n >= 1e6
                txt = sprintf('%.2fM', n/1e6);
            elseif n >= 1e3
                txt = sprintf('%.1fk', n/1e3);
            else
                txt = sprintf('%d', round(n));
            end
        end

        function txt = fmtSeconds(s)
            if ~isnumeric(s) || ~isfinite(s); txt = '—'; return; end
            if s < 1e-6
                txt = sprintf('%.1f ns', s*1e9);
            elseif s < 1e-3
                txt = sprintf('%.1f µs', s*1e6);
            elseif s < 1
                txt = sprintf('%.1f ms', s*1e3);
            elseif s < 60
                txt = sprintf('%.1f s', s);
            elseif s < 3600
                txt = sprintf('%.1f min', s/60);
            elseif s < 86400
                txt = sprintf('%.1f hr', s/3600);
            else
                txt = sprintf('%.1f days', s/86400);
            end
        end
    end
end
