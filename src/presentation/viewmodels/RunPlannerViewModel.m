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

        % Nav-aware cancellation bookkeeping. Every async batch (onEnter
        % runMany, onPlan runMany) captures the current NavGeneration in
        % its callback closure; cancelInFlight bumps the counter so any
        % still-queued callback bails before mutating the panel.
        NavGeneration   double = 0
        InFlightFutures cell   = {}
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

            % Cache hits land synchronously; misses go into a single
            % AsyncRunner.runMany batch (one shared 50ms poller instead
            % of up to three independent timers, as the pre-refactor
            % nested-counter pattern produced).
            cached = struct('circuits', [], 'backends', [], 'levels', []);
            works  = {};
            keys   = {};

            if state.isCircuitsListCacheFresh(ttl)
                cached.circuits = state.CircuitListCache;
            else
                works{end+1} = @() RunPlannerViewModel.safeListFetch( ...
                    @() circSvc.listCircuits(token));
                keys{end+1}  = 'circ';
            end
            if state.isBackendsListCacheFresh(ttl)
                cached.backends = state.BackendListCache;
            else
                works{end+1} = @() RunPlannerViewModel.safeListFetch( ...
                    @() backSvc.listBackends(token, ''));
                keys{end+1}  = 'back';
            end
            if state.isMitigationLevelsCacheFresh(ttl)
                cached.levels = state.MitigationLevelsCache;
            else
                works{end+1} = @() RunPlannerViewModel.safeListFetch( ...
                    @() mitSvc.listLevels(token));
                keys{end+1}  = 'lvl';
            end

            if isempty(works)
                obj.finalizeLoading(cached);
                return;
            end

            gen = AsyncCancellation.bump(obj.NavGeneration);
            obj.NavGeneration = gen;
            fut = AsyncRunner.runMany(works, ...
                @(results) obj.onLoadBatchDone(gen, cached, keys, results), ...
                @(ME)      obj.onLoadBatchError(gen, ME));
            obj.InFlightFutures = AsyncCancellation.appendFutures( ...
                obj.InFlightFutures, fut);
        end

        function onLoadBatchDone(obj, gen, cached, keys, results)
            if gen ~= obj.NavGeneration; return; end
            state = obj.App.State;
            for i = 1:numel(keys)
                r = results{i};
                isErr = RunPlannerViewModel.isFetchError(r);
                if isErr
                    Logger.debug('RunPlannerViewModel', ...
                        'partial fetch failed (%s): %s', keys{i}, r.qtauFetchErr);
                end
                switch keys{i}
                    case 'circ'
                        cached.circuits = r;
                        if ~isErr; state.setCircuitsListCache(r); end
                    case 'back'
                        cached.backends = r;
                        if ~isErr; state.setBackendsListCache(r); end
                    case 'lvl'
                        cached.levels = r;
                        if ~isErr; state.setMitigationLevelsCache(r); end
                end
            end
            obj.finalizeLoading(cached);
        end

        function onLoadBatchError(obj, gen, ME)
            if gen ~= obj.NavGeneration; return; end
            if AsyncCancellation.isCancellation(ME); return; end
            obj.Phase = 'error';
            obj.flashStatus(sprintf( ...
                Labels.get('run_planner_status_err'), ME.message), 'danger');
        end

        function finalizeLoading(obj, cached)
            % Tolerate per-fetch errors: if at least one of the three
            % lists landed, paint what we have so the user can keep
            % moving (e.g. levels missing but circuits + backends OK →
            % planner can still surface base-fidelity predictions on a
            % manual Plan click; the missing levels just means the
            % chip strip is empty).
            circuits = cached.circuits;
            backends = cached.backends;
            levels   = cached.levels;
            if RunPlannerViewModel.isFetchError(circuits); circuits = []; end
            if RunPlannerViewModel.isFetchError(backends); backends = []; end
            if RunPlannerViewModel.isFetchError(levels);   levels   = []; end
            obj.Circuits = RunPlannerViewModel.normalizeList(circuits);
            obj.Backends = RunPlannerViewModel.normalizeList(backends);
            obj.Levels   = RunPlannerViewModel.normalizeList(levels);
            obj.populateCircuitDropdown();
            obj.Phase = 'ready';
            obj.LastRefresh = tic;
            obj.refreshStatus();
        end

        function cancelInFlight(obj)
            % Called by NavigationManager when the user navs away. Bumps
            % generation (in-flight callbacks bail silently), cancels
            % still-running parfeval workers (free worker + timer), and
            % rolls back any transient Phase.
            obj.NavGeneration   = AsyncCancellation.bump(obj.NavGeneration);
            obj.InFlightFutures = AsyncCancellation.cancelAll(obj.InFlightFutures);
            if strcmp(obj.Phase, 'loading') || strcmp(obj.Phase, 'planning')
                obj.Phase = 'ready';
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
            % Validate the chosen circuit source. Two branches:
            %   * Composer mode (dropdown value '__composer__'): require
            %     the live in-app Composer model to have at least one gate.
            %   * Project-circuit mode: require a real circuit id from
            %     the dropdown (rules out the "(loading)" placeholder).
            %     Gate count is intentionally NOT required here — the
            %     /api/circuits list response does not ship raw_content,
            %     so resolveSourceModel falls back to CircuitModel(nq)
            %     with zero gates for every project circuit. Downstream
            %     prediction only needs the circuit id, so the old
            %     "must have gates" check silently bailed every
            %     project-circuit Plan click.
            model      = obj.resolveSourceModel();
            isComposer = ~isempty(obj.CircuitDropdown) ...
                && isvalid(obj.CircuitDropdown) ...
                && isequal(obj.CircuitDropdown.Value, '__composer__');
            if isComposer
                if isempty(model) || numel(model.Gates) == 0
                    obj.flashStatus(Labels.get('run_planner_err_empty_circuit'), 'danger');
                    return;
                end
            else
                cid = RunPlannerViewModel.resolveCircuitId(obj);
                cidTrim = strtrim(char(cid));
                if isempty(cidTrim) || startsWith(cidTrim, '(')
                    obj.flashStatus(Labels.get('run_planner_err_empty_circuit'), 'danger');
                    return;
                end
            end
            shots = max(1, round(obj.ShotsField.Value));
            circuitId  = RunPlannerViewModel.resolveCircuitId(obj);
            % Look up the circuit's actual width (from AppState or the
            % cached circuit list). Filter out backends that physically
            % cannot run a circuit this wide — the server-side predict
            % and mitigation estimators return NaN for those, leaving
            % the Pareto panel showing Cost/Shots/Runtime as NaN with
            % no actionable signal.
            cQubits = RunPlannerViewModel.circuitQubitsFor(obj, circuitId);
            backendPairs = struct('name', {}, 'q', {});
            for bi = 1:numel(obj.Backends)
                nm = char(string(RunPlannerViewModel.safeField( ...
                    obj.Backends(bi), 'name', '')));
                if isempty(nm); continue; end
                bq = double(RunPlannerViewModel.safeField( ...
                    obj.Backends(bi), 'num_qubits', 0));
                if ~isfinite(bq); bq = 0; end
                backendPairs(end+1) = struct('name', nm, 'q', bq); %#ok<AGROW>
            end
            if cQubits > 0
                fit = arrayfun(@(p) p.q == 0 || p.q >= cQubits, backendPairs);
                if ~any(fit)
                    obj.Phase = 'error';
                    widestQ = 0;
                    if ~isempty(backendPairs); widestQ = max([backendPairs.q]); end
                    obj.flashStatus(sprintf( ...
                        ['No backend in your project supports this %d-qubit circuit. ' ...
                         'Widest available is %d qubits — pick a smaller circuit ' ...
                         'or add a wider backend.'], ...
                        round(cQubits), round(widestQ)), 'danger');
                    return;
                end
                backendPairs = backendPairs(fit);
            end
            backendNames = arrayfun(@(p) {p.name}, backendPairs);
            if isempty(backendNames) || isempty(obj.Levels)
                obj.flashStatus(sprintf(Labels.get('run_planner_status_err'), ...
                    'no backends or strategies available'), 'danger');
                return;
            end

            obj.Phase = 'planning';
            obj.flashStatus(sprintf(Labels.get('run_planner_status_planning'), ...
                numel(backendNames) * numel(obj.Levels)), 'info');

            tokenLocal = obj.App.State.authToken;
            mitSvc     = obj.App.Services.MitigationSvc;
            predSvc    = obj.App.Services.PredictionSvc;
            % Use the actual circuit width when known; otherwise fall
            % back to the legacy max-backend proxy so estimators still
            % get a non-zero value.
            if cQubits > 0
                qForEstimate = cQubits;
            else
                qForEstimate = RunPlannerViewModel.maxBackendQubits(obj.Backends);
            end

            % One runMany batch covers (1 predict + N mitigation estimate)
            % fetches. The pre-refactor pattern spawned (N+1) independent
            % AsyncRunner.run dispatches (one polling timer each) and
            % tracked completion via pendingPredict/pendingMitig flags
            % inside nested closures — runMany delivers all results in a
            % single atomic callback. Position 1 is the predict result;
            % positions 2..N+1 are the per-strategy estimates, in the
            % same order as obj.Levels.
            nLevels  = numel(obj.Levels);
            works    = cell(1, 1 + nLevels);
            levelIds = cell(1, nLevels);
            levelObjs = cell(1, nLevels);
            works{1} = @() RunPlannerViewModel.safePredict( ...
                predSvc, circuitId, backendNames, shots, tokenLocal);
            for i = 1:nLevels
                lvl = obj.Levels(i);
                lid = RunPlannerViewModel.safeField(lvl, 'id', '0');
                levelIds{i}  = lid;
                levelObjs{i} = lvl;
                body = struct( ...
                    'mitigation_level',         RunPlannerViewModel.parseLevelId(lid), ...
                    'primitive',                'sampler', ...
                    'backend_name',             char(string(backendNames{1})), ...
                    'base_shots',               int32(shots), ...
                    'circuit_qubits',           int32(qForEstimate), ...
                    'cutting_overhead_qubits',  int32(0));
                works{i+1} = @() RunPlannerViewModel.safeEstimate(mitSvc, body, tokenLocal);
            end

            gen = AsyncCancellation.bump(obj.NavGeneration);
            obj.NavGeneration = gen;
            fut = AsyncRunner.runMany(works, ...
                @(results) obj.onPlanBatchDone(gen, backendNames, levelIds, levelObjs, results), ...
                @(ME)      obj.onPlanBatchError(gen, ME));
            obj.InFlightFutures = AsyncCancellation.appendFutures( ...
                obj.InFlightFutures, fut);
        end

        function onPlanBatchDone(obj, gen, backendNames, levelIds, levelObjs, results)
            if gen ~= obj.NavGeneration; return; end

            % Position 1: predict; positions 2..N+1: mitigation estimates
            % in obj.Levels order.
            predictResult = results{1};
            if RunPlannerViewModel.isFetchError(predictResult)
                Logger.debug('RunPlannerViewModel', ...
                    'predict failed: %s', predictResult.qtauFetchErr);
                baseFidByBackend = RunPlannerViewModel.parsePredictResult([], backendNames);
            else
                baseFidByBackend = RunPlannerViewModel.parsePredictResult( ...
                    predictResult, backendNames);
            end

            costsByStrategy = struct();
            for i = 1:numel(levelIds)
                lid = levelIds{i};
                lvl = levelObjs{i};
                r   = results{i+1};
                safeKey = matlab.lang.makeValidName(['x' lid]);
                if RunPlannerViewModel.isFetchError(r)
                    Logger.debug('RunPlannerViewModel', ...
                        'estimate failed (%s): %s', lid, r.qtauFetchErr);
                    costsByStrategy.(safeKey) = struct('lvl', lvl, 'cost', []);
                else
                    % Unwrap the outer envelope. /api/mitigation/estimate
                    % returns {plan, cost, summary}; the actual CostEstimate
                    % lives inside r.cost. Reading r directly would search
                    % for cost fields at the top level and miss every one,
                    % so the planner used to bake NaN into every config.
                    if isstruct(r) && isfield(r, 'cost') && ~isempty(r.cost)
                        costEst = r.cost;
                    else
                        costEst = r;
                    end
                    costsByStrategy.(safeKey) = struct('lvl', lvl, 'cost', costEst);
                end
            end

            ctx = struct( ...
                'baseFidByBackend', baseFidByBackend, ...
                'costsByStrategy',  costsByStrategy);
            obj.assemblePlan(ctx);
        end

        function onPlanBatchError(obj, gen, ME)
            if gen ~= obj.NavGeneration; return; end
            if AsyncCancellation.isCancellation(ME); return; end
            obj.Phase = 'ready';
            obj.flashStatus(sprintf( ...
                Labels.get('run_planner_status_err'), ME.message), 'danger');
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
                            % pickOptimal returned empty point — every
                            % candidate failed cost estimation. Show an
                            % actionable message instead of formatting
                            % NaNs into the no-target template.
                            msg = Labels.get('run_planner_status_no_viable', ...
                                ['No viable configuration — every candidate backend ' ...
                                 'failed cost estimation. The circuit may be too wide ' ...
                                 'for any backend in your project.']);
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
                cid = RunPlannerViewModel.pickCircuitId(obj.Circuits(i));
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
                cid  = RunPlannerViewModel.pickCircuitId(c);
                items{end+1} = sprintf('%s (%dq)', char(string(name)), double(nq)); %#ok<AGROW>
                ids{end+1}   = cid; %#ok<AGROW>
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
                    % Field names match CostEstimate.to_dict() in
                    % src/qdash/api/services/mitigation_service.py. The
                    % older names (estimated_cost_iqp / estimated_runtime_seconds
                    % / total_shots) never existed on the wire — the same
                    % bug MitigationCompareViewModel fixed earlier (see
                    % its line ~583 comment). Without these correct
                    % names every Plan click silently produced NaN cost
                    % / runtime / shots regardless of circuit width.
                    cost = RunPlannerViewModel.pickCostField(entry.cost, 'est_iqp_units', NaN);
                    rt   = RunPlannerViewModel.pickCostField(entry.cost, 'est_wall_seconds', NaN);
                    tot  = RunPlannerViewModel.pickCostField(entry.cost, 'effective_shots', NaN);
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
            % Sanitize costs/fidelities before computing axis limits.
            % Prediction can return NaN/Inf for backends that fail to
            % transpile a given circuit, and a planner run can produce
            % all-zero costs for very small / cached configurations.
            % Without filtering those out min/max propagate NaN into
            % XLim/YLim and MATLAB throws "Value must be a 1x2 vector
            % … second element greater than the first or Inf".
            finCosts = costs(isfinite(costs));
            finFids  = fids(isfinite(fids));
            if isempty(finCosts)
                xLim = [0, 1];
            else
                xMin = min(finCosts);
                xMax = max(finCosts);
                xLim = [xMin*0.9, xMax*1.1];
                if ~(xLim(1) < xLim(2))
                    pad  = max(1e-6, abs(xMax) * 0.1);
                    xLim = [xMin - pad, xMax + pad];
                    if ~(xLim(1) < xLim(2))
                        xLim = [0, max(1, xMax + 1)];
                    end
                end
            end
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
            if isempty(finFids)
                yLim = [0, 1];
            else
                yLow = max(0, min(finFids) - 0.05);
                yLim = [yLow, 1.0];
                if ~(yLim(1) < yLim(2)); yLim = [0, 1]; end
            end
            ax.XLim = xLim; ax.YLim = yLim;
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
        function out = safeListFetch(workFcn)
            % safeListFetch  Run a list-endpoint fetch in a try/catch so a
            %   single endpoint failure inside a runMany batch yields a
            %   sentinel struct (qtauFetchErr) instead of poisoning the
            %   whole batch via AsyncRunner.pollFutures' first-error-wins
            %   semantics. Callers test via isFetchError before consuming.
            try
                out = workFcn();
            catch ME
                out = struct('qtauFetchErr', ME.message);
            end
        end

        function out = safePredict(predSvc, circuitId, backendNames, shots, token)
            % safePredict  /api/predictions/predict wrapper for runMany.
            try
                out = predSvc.predict(circuitId, backendNames, shots, 1, token);
            catch ME
                out = struct('qtauFetchErr', ME.message);
            end
        end

        function out = safeEstimate(mitSvc, body, token)
            % safeEstimate  Per-strategy /mitigation/estimate wrapper for
            %   runMany. Same partial-failure semantics as safeListFetch.
            try
                out = mitSvc.estimate(body, token);
            catch ME
                out = struct('qtauFetchErr', ME.message);
            end
        end

        function tf = isFetchError(r)
            % isFetchError  Sentinel detector for the qtauFetchErr struct
            %   returned by safeListFetch / safePredict / safeEstimate on
            %   a failed per-element fetch inside a batch.
            tf = isstruct(r) && isscalar(r) && isfield(r, 'qtauFetchErr');
        end

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

        function id = pickCircuitId(c)
            % /api/circuits items expose the identifier under either
            % `circuit_id` (current FastAPI shape, used by every other
            % ViewModel) or the legacy `id` field. Without this fallback
            % chain the planner's dropdown bound every entry's
            % ItemsData to '' and the project-circuit Plan path bailed
            % with "Compose at least one gate before planning." even
            % when the operator picked a real circuit.
            id = char(string(RunPlannerViewModel.safeField(c, 'circuit_id', '')));
            if isempty(id)
                id = char(string(RunPlannerViewModel.safeField(c, 'id', '')));
            end
        end

        function q = circuitQubitsFor(obj, cid)
            % Best-effort circuit width lookup. Tries AppState (set on
            % Analysis nav) first, then the cached circuit list. Returns
            % 0 when unknown so the caller can skip the width filter.
            q = 0;
            try
                v = double(obj.App.State.selectedCircuitQubits);
                if isfinite(v) && v > 0; q = v; return; end
            catch
            end
            for i = 1:numel(obj.Circuits)
                if strcmp(RunPlannerViewModel.pickCircuitId(obj.Circuits(i)), cid)
                    v = double(RunPlannerViewModel.safeField( ...
                        obj.Circuits(i), 'num_qubits', 0));
                    if ~isfinite(v); v = 0; end
                    q = v; return;
                end
            end
        end

        function n = parseLevelId(idChar)
            % Always returns int32 so the result is wire-correct when
            % assigned into the mitigation_level JSON body field (same
            % rationale as MitigationCompareViewModel.parseLevelId).
            v = str2double(idChar);
            if isnan(v); n = int32(-1); else; n = int32(v); end
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
