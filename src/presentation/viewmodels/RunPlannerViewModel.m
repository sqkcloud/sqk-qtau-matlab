classdef RunPlannerViewModel < handle
    % RunPlannerViewModel  Cost-aware run planner. Synthesises Prediction
    %                       fidelity-per-backend with Mitigation cost-per-
    %                       strategy estimates into a Pareto frontier,
    %                       and recommends the cheapest configuration
    %                       that hits a user-specified target fidelity.
    %
    %   State machine:
    %     IDLE → LOADING (circuits + backends + levels)
    %          → READY  (dropdowns populated; target slider live)
    %          → PLANNING (predict + N×estimate calls in flight)
    %          → DONE     (scatter + recommendation rendered)
    %          → ERROR    (catastrophic — surface message)

    properties
        LastRefresh = []
    end

    properties
        RootGrid

        CircuitDropdown
        TargetSlider
        TargetValueLbl
        ShotsField
        PlanBtn
        SubmitBtn
        BundleBtn
        StatusLbl

        ScatterGrid        % parent for the lazy uiaxes (built on first repaintScatter)
        ScatterPlaceholder % uilabel shown until the uiaxes materialises
        ScatterAxes

        % Recommendation card
        LblBackend
        LblMitigation
        LblShots
        LblFidelity
        LblCost
        LblRuntime
        LblFactorNote
    end

    properties
        Circuits      = []
        Backends      = []
        Levels        = []
        Points        = []
        Frontier      = []
        Optimal       = []
        Phase         = 'idle'
    end

    properties (Access = private)
        App
    end

    methods
        function obj = RunPlannerViewModel(app)
            obj.App = app;
        end

        function bindRootGrid(obj, g)
            obj.RootGrid = g;
        end

        function onEnter(obj)
            obj.Phase = 'loading';
            obj.refreshStatus();

            state   = obj.App.State;
            token   = state.authToken;
            circSvc = obj.App.Services.CircuitSvc;
            backSvc = obj.App.Services.BackendSvc;
            mitSvc  = obj.App.Services.MitigationSvc;
            ttl     = AppConfig.getDouble('shared_cache_ttl', 120);

            results = struct('circuits', [], 'backends', [], 'levels', [], ...
                'circDone', false, 'backDone', false, 'levelDone', false);
            done = @() finalize();

            % Each of the 3 lookups uses the shared session cache when
            % fresh — saves a cross-continent round-trip per nav across
            % Mitigation Compare / Run Planner / Resource Estimator.
            if state.isCircuitsListCacheFresh(ttl)
                results.circuits = state.CircuitListCache;
                results.circDone = true;
            else
                AsyncRunner.run(@() circSvc.listCircuits(token), ...
                    @(r) onPart('circ', r), @(ME) onPart('circ', ME));
            end
            if state.isBackendsListCacheFresh(ttl)
                results.backends = state.BackendListCache;
                results.backDone = true;
            else
                AsyncRunner.run(@() backSvc.listBackends(token, ''), ...
                    @(r) onPart('back', r), @(ME) onPart('back', ME));
            end
            if state.isMitigationLevelsCacheFresh(ttl)
                results.levels = state.MitigationLevelsCache;
                results.levelDone = true;
            else
                AsyncRunner.run(@() mitSvc.listLevels(token), ...
                    @(r) onPart('lvl', r), @(ME) onPart('lvl', ME));
            end

            % All three hit the cache — finalize synchronously.
            if results.circDone && results.backDone && results.levelDone
                done();
                return;
            end

            function onPart(which, r)
                if ~isa(r, 'MException')
                    switch which
                        case 'circ'
                            results.circuits = r;
                            state.setCircuitsListCache(r);
                        case 'back'
                            results.backends = r;
                            state.setBackendsListCache(r);
                        case 'lvl'
                            results.levels = r;
                            state.setMitigationLevelsCache(r);
                    end
                end
                switch which
                    case 'circ'; results.circDone  = true;
                    case 'back'; results.backDone  = true;
                    case 'lvl';  results.levelDone = true;
                end
                if results.circDone && results.backDone && results.levelDone
                    done();
                end
            end

            function finalize()
                obj.Circuits = RunPlannerViewModel.normalizeList(results.circuits);
                obj.Backends = RunPlannerViewModel.normalizeList(results.backends);
                obj.Levels   = RunPlannerViewModel.normalizeList(results.levels);
                obj.populateCircuitDropdown();
                obj.Phase = 'ready';
                obj.LastRefresh = tic;
                obj.refreshStatus();
            end
        end

        function onPickCircuit(~, ~); end

        function onTargetChanged(obj, evt)
            try
                v = evt.Value;
            catch
                v = obj.TargetSlider.Value;
            end
            obj.TargetValueLbl.Text = sprintf('%.2f', v);
        end

        function onPlan(obj)
            model = obj.resolveSourceModel();
            if isempty(model) || numel(model.Gates) == 0
                obj.flashStatus(Labels.get('run_planner_err_empty_circuit'), 'danger');
                return;
            end
            shots = max(1, round(obj.ShotsField.Value));
            backendNames = arrayfun(@(b) RunPlannerViewModel.safeField(b, 'name', ''), ...
                obj.Backends, 'UniformOutput', false);
            backendNames = backendNames(~cellfun(@isempty, backendNames));
            if isempty(backendNames) || isempty(obj.Levels)
                obj.flashStatus(sprintf(Labels.get('run_planner_status_err'), ...
                    'no backends or strategies available'), 'danger');
                return;
            end

            obj.Phase = 'planning';
            obj.flashStatus(sprintf(Labels.get('run_planner_status_planning'), ...
                numel(backendNames) * numel(obj.Levels)), 'info');

            ctx = struct( ...
                'circuitId',    RunPlannerViewModel.resolveCircuitId(obj), ...
                'backendNames', {backendNames}, ...
                'shots',        shots, ...
                'baseFidByBackend', struct(), ...
                'costsByStrategy', struct(), ...
                'pendingPredict',  true, ...
                'pendingMitig',    numel(obj.Levels), ...
                'failures',        {{}});

            tokenLocal = obj.App.State.authToken;
            mitSvc = obj.App.Services.MitigationSvc;
            predSvc = obj.App.Services.PredictionSvc;

            AsyncRunner.run( ...
                @() predSvc.predict(ctx.circuitId, backendNames, shots, 1, tokenLocal), ...
                @(r) onPredictDone(r), @(ME) onPredictErr(ME));

            qProxy = RunPlannerViewModel.maxBackendQubits(obj.Backends);
            for i = 1:numel(obj.Levels)
                lvl = obj.Levels(i);
                lid = RunPlannerViewModel.safeField(lvl, 'id', '0');
                body = struct( ...
                    'mitigation_level', RunPlannerViewModel.parseLevelId(lid), ...
                    'primitive',                'sampler', ...
                    'backend_name',             char(string(backendNames{1})), ...
                    'base_shots',               int32(shots), ...
                    'circuit_qubits',           int32(qProxy), ...
                    'cutting_overhead_qubits',  int32(0));
                AsyncRunner.run( ...
                    @() mitSvc.estimate(body, tokenLocal), ...
                    @(r) onMitigDone(lid, lvl, r), ...
                    @(ME) onMitigErr(lid, lvl, ME));
            end

            function onPredictDone(r)
                ctx.pendingPredict = false;
                ctx.baseFidByBackend = RunPlannerViewModel.parsePredictResult(r, backendNames);
                tryFinalize();
            end
            function onPredictErr(ME)
                ctx.pendingPredict = false;
                ctx.failures{end+1} = sprintf('predict: %s', ME.message);
                ctx.baseFidByBackend = RunPlannerViewModel.parsePredictResult([], backendNames);
                tryFinalize();
            end
            function onMitigDone(lid, lvl, r)
                ctx.costsByStrategy.(matlab.lang.makeValidName(['x' lid])) = struct( ...
                    'lvl', lvl, 'cost', r);
                ctx.pendingMitig = ctx.pendingMitig - 1;
                tryFinalize();
            end
            function onMitigErr(lid, lvl, ME)
                ctx.failures{end+1} = sprintf('mitig %s: %s', lid, ME.message);
                ctx.costsByStrategy.(matlab.lang.makeValidName(['x' lid])) = struct( ...
                    'lvl', lvl, 'cost', []);
                ctx.pendingMitig = ctx.pendingMitig - 1;
                tryFinalize();
            end
            function tryFinalize()
                if ~ctx.pendingPredict && ctx.pendingMitig <= 0
                    obj.assemblePlan(ctx);
                end
            end
        end

        function onSubmit(obj)
            obj.flashStatus('Submit-this-run hands off to Benchmark in Phase 2.', 'info');
            try
                obj.App.onSelectSection('Benchmark');
            catch
            end
        end

        function onBundle(obj)
            try
                obj.App.onSelectSection('Composer');
                cvm = obj.App.ComposerVm;
                if ~isempty(cvm) && ismethod(cvm, 'onOpenBundle')
                    cvm.onOpenBundle();
                end
            catch ME
                obj.flashStatus(sprintf('Bundle hand-off failed: %s', ME.message), 'danger');
            end
        end

        function refreshStatus(obj)
            if isempty(obj.StatusLbl) || ~isvalid(obj.StatusLbl); return; end
            switch obj.Phase
                case 'idle';     msg = Labels.get('run_planner_status_idle'); col = Theme.COLOR_LABEL;
                case 'loading';  msg = Labels.get('run_planner_status_loading'); col = Theme.COLOR_LABEL;
                case 'ready';    msg = Labels.get('run_planner_status_idle'); col = Theme.COLOR_LABEL;
                case 'planning'; msg = obj.StatusLbl.Text; col = Theme.COLOR_PRIMARY;
                case 'done'
                    if ~isempty(obj.Optimal) && obj.Optimal.metTarget
                        msg = sprintf(Labels.get('run_planner_status_done_fmt'), ...
                            numel(obj.Points), numel(obj.Frontier), obj.Optimal.point.fidelity);
                        col = Theme.COLOR_SUCCESS;
                    else
                        target = obj.TargetSlider.Value;
                        if ~isempty(obj.Optimal) && ~isempty(obj.Optimal.point)
                            msg = sprintf(Labels.get('run_planner_status_no_target'), ...
                                target, obj.Optimal.point.fidelity, obj.Optimal.point.cost);
                        else
                            msg = sprintf(Labels.get('run_planner_status_no_target'), target, NaN, NaN);
                        end
                        col = Theme.COLOR_WARNING;
                    end
                otherwise; msg = obj.StatusLbl.Text; col = Theme.COLOR_LABEL;
            end
            obj.StatusLbl.Text = msg;
            obj.StatusLbl.FontColor = col;
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
                cid = RunPlannerViewModel.safeField(obj.Circuits(i), 'id', '');
                if strcmp(cid, v)
                    qasm = RunPlannerViewModel.safeField(obj.Circuits(i), 'raw_content', '');
                    if ~isempty(qasm)
                        try; model = CircuitModel.fromQasm(qasm); catch; end
                    end
                    if isempty(model)
                        nq = RunPlannerViewModel.safeField(obj.Circuits(i), 'num_qubits', 1);
                        model = CircuitModel(double(nq));
                    end
                    return;
                end
            end
        end

        function populateCircuitDropdown(obj)
            if isempty(obj.CircuitDropdown) || ~isvalid(obj.CircuitDropdown); return; end
            items = {Labels.get('run_planner_circuit_composer')};
            ids   = {'__composer__'};
            for i = 1:numel(obj.Circuits)
                c = obj.Circuits(i);
                name = RunPlannerViewModel.safeField(c, 'name', '?');
                nq   = RunPlannerViewModel.safeField(c, 'num_qubits', 0);
                cid  = RunPlannerViewModel.safeField(c, 'id', '');
                items{end+1} = sprintf('%s (%dq)', char(string(name)), double(nq)); %#ok<AGROW>
                ids{end+1}   = char(string(cid)); %#ok<AGROW>
            end
            obj.CircuitDropdown.Items     = items;
            obj.CircuitDropdown.ItemsData = ids;
            if isempty(obj.CircuitDropdown.Value)
                obj.CircuitDropdown.Value = '__composer__';
            end
        end

        function assemblePlan(obj, ctx)
            points = struct( ...
                'backend', {}, 'level', {}, 'levelLabel', {}, ...
                'baseFidelity', {}, 'fidelity', {}, ...
                'cost', {}, 'runtime', {}, 'totalShots', {}, 'shotMult', {});
            stratFns = fieldnames(ctx.costsByStrategy);
            backendKeys = fieldnames(ctx.baseFidByBackend);
            for bi = 1:numel(backendKeys)
                bk = backendKeys{bi};
                bname = ctx.baseFidByBackend.(bk).name;
                baseFid = ctx.baseFidByBackend.(bk).fidelity;
                for si = 1:numel(stratFns)
                    sk = stratFns{si};
                    entry = ctx.costsByStrategy.(sk);
                    lvl = entry.lvl;
                    lid = RunPlannerViewModel.safeField(lvl, 'id', '0');
                    lbl = RunPlannerViewModel.safeField(lvl, 'label', ...
                          RunPlannerViewModel.safeField(lvl, 'name', lid));
                    if isempty(entry.cost); continue; end
                    cost = RunPlannerViewModel.pickCostField(entry.cost, 'estimated_cost_iqp', NaN);
                    rt   = RunPlannerViewModel.pickCostField(entry.cost, 'estimated_runtime_seconds', NaN);
                    tot  = RunPlannerViewModel.pickCostField(entry.cost, 'total_shots', NaN);
                    mult = RunPlannerViewModel.pickCostField(entry.cost, 'shot_multiplier', 1.0);
                    fidM = RunPlannerService.applyMitigationFactor(baseFid, lid);
                    points(end+1) = RunPlannerService.makePoint( ...
                        bname, lid, lbl, baseFid, fidM, cost, rt, tot, mult); %#ok<AGROW>
                end
            end
            obj.Points = points;
            obj.Frontier = RunPlannerService.computeParetoFrontier(points);
            target = obj.TargetSlider.Value;
            obj.Optimal = RunPlannerService.pickOptimal(points, obj.Frontier, target);
            obj.Phase = 'done';
            obj.repaintScatter();
            obj.repaintCard();
            obj.refreshStatus();
            obj.App.logEvent('PLANNER', sprintf( ...
                'Planned %d configs · %d frontier · target %.2f → %s', ...
                numel(points), numel(obj.Frontier), target, ...
                ternaryRP(obj.Optimal.metTarget, 'hit', 'miss')));
        end

        function repaintScatter(obj)
            ax = obj.ScatterAxes;
            if isempty(ax) || ~isvalid(ax)
                % Lazy build — buildScatter deliberately ships a uilabel
                % placeholder to keep screen-mount fast. Pay the uiaxes
                % construction cost here, inside the Plan-spinner window
                % the user is already watching.
                if isempty(obj.ScatterGrid) || ~isvalid(obj.ScatterGrid); return; end
                if ~isempty(obj.ScatterPlaceholder) && isvalid(obj.ScatterPlaceholder)
                    delete(obj.ScatterPlaceholder);
                    obj.ScatterPlaceholder = [];
                end
                ax = uiaxes(obj.ScatterGrid);
                ax.Toolbar.Visible = 'off';
                ax.Color  = Theme.COLOR_CARD;
                ax.XColor = Theme.COLOR_MUTED;
                ax.YColor = Theme.COLOR_MUTED;
                ax.FontSize = 10;
                ax.Box = 'off';
                try; disableDefaultInteractivity(ax); catch; end
                obj.ScatterAxes = ax;
            end
            cla(ax);
            if isempty(obj.Points); return; end
            costs = [obj.Points.cost];
            fids  = [obj.Points.fidelity];
            hold(ax, 'on');
            scatter(ax, costs, fids, 36, [0.55 0.60 0.70], 'filled', ...
                'MarkerEdgeColor', 'none');
            if ~isempty(obj.Frontier)
                fc = [obj.Frontier.cost];
                ff = [obj.Frontier.fidelity];
                plot(ax, fc, ff, '-o', 'Color', Theme.COLOR_PRIMARY, ...
                    'MarkerFaceColor', Theme.COLOR_PRIMARY, ...
                    'MarkerSize', 6, 'LineWidth', 1.4);
            end
            target = obj.TargetSlider.Value;
            xLim = [min(costs)*0.9, max(costs)*1.1];
            if xLim(1) >= xLim(2); xLim = [0, max(1, max(costs))]; end
            line(ax, xLim, [target target], 'Color', Theme.COLOR_WARNING, ...
                'LineStyle', '--', 'LineWidth', 1.0);
            text(ax, xLim(2), target, sprintf(' target %.2f', target), ...
                'Color', Theme.COLOR_WARNING, 'FontSize', 9, ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
            if ~isempty(obj.Optimal) && ~isempty(obj.Optimal.point)
                p = obj.Optimal.point;
                col = ternaryRP(obj.Optimal.metTarget, Theme.COLOR_SUCCESS, Theme.COLOR_WARNING);
                scatter(ax, p.cost, p.fidelity, 110, col, 'p', 'filled', ...
                    'MarkerEdgeColor', Theme.COLOR_HEADING);
            end
            hold(ax, 'off');
            ax.XLabel.String = Labels.get('run_planner_chart_xlabel');
            ax.YLabel.String = Labels.get('run_planner_chart_ylabel');
            ax.Title.String  = Labels.get('run_planner_chart_title');
            ax.XLim = xLim; ax.YLim = [max(0, min(fids)-0.05), 1.0];
        end

        function repaintCard(obj)
            if isempty(obj.LblBackend) || ~isvalid(obj.LblBackend); return; end
            if isempty(obj.Optimal) || isempty(obj.Optimal.point)
                obj.LblBackend.Text    = '—';
                obj.LblMitigation.Text = '—';
                obj.LblShots.Text      = '—';
                obj.LblFidelity.Text   = '—';
                obj.LblCost.Text       = '—';
                obj.LblRuntime.Text    = '—';
                return;
            end
            p = obj.Optimal.point;
            obj.LblBackend.Text    = char(string(p.backend));
            obj.LblMitigation.Text = sprintf('%s (level %s)', p.levelLabel, p.level);
            obj.LblShots.Text      = sprintf('%d (×%.2f)', round(p.totalShots), p.shotMult);
            obj.LblFidelity.Text   = sprintf('%.3f (base %.3f)', p.fidelity, p.baseFidelity);
            obj.LblCost.Text       = sprintf('~%.3f IQP', p.cost);
            obj.LblRuntime.Text    = sprintf('~%.2fs', p.runtime);
            obj.LblFactorNote.Text = Labels.get('run_planner_card_factor_note');
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
            %   1. envelope struct {circuits|backends|levels|items|data: [...]}
            %   2. bare cell array
            %   3. bare struct (single record) or struct array
            % Without envelope unwrapping the dropdowns appeared empty
            % because the wrapper struct counts as 1 element and its
            % fields are not iterated.
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
            if iscell(raw); try; arr = [raw{:}]; catch; arr = raw; end
            else; arr = raw; end
        end

        function v = safeField(s, field, def)
            v = def;
            try
                if isstruct(s) && isfield(s, field); v = s.(field);
                elseif isobject(s) && isprop(s, field); v = s.(field);
                end
            catch
            end
            if isempty(v); v = def; end
        end

        function n = parseLevelId(idChar)
            v = str2double(idChar);
            if isnan(v); n = -1; else; n = int32(v); end
        end

        function q = maxBackendQubits(backends)
            q = 1;
            for i = 1:numel(backends)
                nq = RunPlannerViewModel.safeField(backends(i), 'num_qubits', 1);
                if ~isnumeric(nq); nq = 1; end
                q = max(q, double(nq));
            end
        end

        function id = resolveCircuitId(obj)
            id = '';
            if ~isempty(obj.CircuitDropdown) && isvalid(obj.CircuitDropdown)
                v = obj.CircuitDropdown.Value;
                if ~isequal(v, '__composer__'); id = char(string(v)); end
            end
        end

        function map = parsePredictResult(r, backendNames)
            % Best-effort: predict response shapes vary. Accept either a
            % struct array with .name/.fidelity, or a struct with .results
            % / .predictions array. Anything we can't parse → default
            % fidelity 0.80 per backend so the planner still produces
            % output rather than failing silently.
            map = struct();
            try
                if isstruct(r) && isfield(r, 'results')
                    list = r.results;
                elseif isstruct(r) && isfield(r, 'predictions')
                    list = r.predictions;
                elseif iscell(r)
                    list = [r{:}];
                else
                    list = r;
                end
                for i = 1:numel(list)
                    if iscell(list); item = list{i}; else; item = list(i); end
                    name = RunPlannerViewModel.safeField(item, 'backend_name', ...
                           RunPlannerViewModel.safeField(item, 'name', ''));
                    fid  = RunPlannerViewModel.safeField(item, 'predicted_fidelity', ...
                           RunPlannerViewModel.safeField(item, 'fidelity', NaN));
                    if isempty(name) || ~isfinite(fid); continue; end
                    safe = matlab.lang.makeValidName(['b_' char(string(name))]);
                    map.(safe) = struct('name', char(string(name)), 'fidelity', double(fid));
                end
            catch
            end
            for i = 1:numel(backendNames)
                bn = char(string(backendNames{i}));
                safe = matlab.lang.makeValidName(['b_' bn]);
                if ~isfield(map, safe)
                    map.(safe) = struct('name', bn, 'fidelity', 0.80);
                end
            end
        end

        function v = pickCostField(costStruct, field, def)
            v = def;
            try
                if isstruct(costStruct) && isfield(costStruct, field)
                    v = double(costStruct.(field));
                end
            catch
            end
            if isempty(v) || ~isnumeric(v); v = def; end
        end
    end
end

function v = ternaryRP(cond, a, b)
    if cond; v = a; else; v = b; end
end
