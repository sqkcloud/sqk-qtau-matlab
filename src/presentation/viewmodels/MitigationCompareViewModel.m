classdef MitigationCompareViewModel < handle
    % MitigationCompareViewModel  Side-by-side error-mitigation strategy
    %                              planner. Pre-submit cost / shot-multiplier
    %                              / runtime / IQP-cost comparison driven
    %                              by parallel `/api/mitigation/estimate`
    %                              calls (one per chip).
    %
    %   State machine:
    %     IDLE → LOADING (fetching circuits + backends + levels)
    %          → READY  (dropdowns + chip strip populated)
    %          → ESTIMATING (N parallel estimate dispatches in flight)
    %          → DONE       (cards + ranking + recommendation rendered)
    %          → ERROR      (catastrophic — surface the message)

    properties
        LastRefresh = []
    end

    properties
        RootGrid

        CircuitDropdown
        BackendDropdown
        ShotsField
        EstimateBtn
        RefreshBtn
        ExportBtn
        StatusLbl

        ChipPanel
        ChipBtns

        CardPanel
        CardGrid
        CardHandles

        RankGrid          % parent for the lazy uiaxes (built on first repaintRanking)
        RankPlaceholder   % uilabel shown until the uiaxes materialises
        RankAxes
        ReccoLbl
    end

    properties
        Circuits      = []
        Backends      = []
        Levels        = []
        SelectedChips = {}
        Estimates
        Phase         = 'idle'
        Pending       = 0
        StartTic      = []
        Failures      = 0
    end

    properties (Access = private)
        App
    end

    methods
        function obj = MitigationCompareViewModel(app)
            obj.App = app;
            obj.Estimates = containers.Map('KeyType','char','ValueType','any');
        end

        function bindRootGrid(obj, g)
            obj.RootGrid = g;
        end

        % ── Lifecycle ────────────────────────────────────────────────────
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
                'circDone', false, 'backDone', false, 'levelDone', false, ...
                'errors', {{}});
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
                    @(r) onPart('lvl',  r), @(ME) onPart('lvl',  ME));
            end

            % All three hit the cache — finalize synchronously.
            if results.circDone && results.backDone && results.levelDone
                done();
                return;
            end

            function onPart(which, r)
                if isa(r, 'MException')
                    results.errors{end+1} = sprintf('%s: %s', which, r.message);
                else
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
                if ~isempty(results.errors) && ...
                        (isempty(results.circuits) || isempty(results.backends) || isempty(results.levels))
                    obj.Phase = 'error';
                    obj.flashStatus(sprintf( ...
                        Labels.get('mitigation_compare_status_failed'), ...
                        strjoin(results.errors, '; ')), 'danger');
                    return;
                end
                obj.Circuits = MitigationCompareViewModel.normalizeList(results.circuits);
                obj.Backends = MitigationCompareViewModel.normalizeList(results.backends);
                obj.Levels   = MitigationCompareViewModel.normalizeLevels(results.levels);
                obj.populateDropdowns();
                obj.populateChips();
                obj.SelectedChips = obj.intersectChips({'0','1','2','3'});
                obj.repaintChips();
                obj.Phase = 'ready';
                obj.LastRefresh = tic;
                obj.refreshStatus();
            end
        end

        % ── Toolbar callbacks ────────────────────────────────────────────
        function onPickCircuit(~, ~); end
        function onPickBackend(~, ~); end

        function onChipToggle(obj, levelId)
            levelId = char(string(levelId));
            idx = find(strcmp(obj.SelectedChips, levelId), 1);
            if isempty(idx)
                obj.SelectedChips{end+1} = levelId;
            else
                obj.SelectedChips(idx) = [];
            end
            obj.repaintChips();
            obj.refreshStatus();
        end

        function onEstimate(obj)
            if ~obj.canEstimate(); return; end
            obj.Phase = 'estimating';
            obj.Pending = numel(obj.SelectedChips);
            obj.Failures = 0;
            obj.StartTic = tic;
            obj.Estimates = containers.Map('KeyType','char','ValueType','any');
            obj.refreshStatus();
            obj.paintCardsLoading();

            body = obj.buildBaseBody();
            mitSvc = obj.App.Services.MitigationSvc;
            token = obj.App.State.authToken;

            for i = 1:numel(obj.SelectedChips)
                levelId = obj.SelectedChips{i};
                bodyI = body;
                bodyI.mitigation_level = MitigationCompareViewModel.parseLevelId(levelId);
                AsyncRunner.run( ...
                    @() mitSvc.estimate(bodyI, token), ...
                    @(r)  obj.onEstimateDone(levelId, r), ...
                    @(ME) obj.onEstimateError(levelId, ME));
            end
        end

        function onRefresh(obj)
            obj.LastRefresh = [];
            obj.onEnter();
        end

        function onExport(obj)
            obj.flashStatus('Export queued for Phase B (Reports integration).', 'info');
        end

        % ── Estimate callbacks ───────────────────────────────────────────
        function onEstimateDone(obj, levelId, r)
            obj.Estimates(levelId) = struct( ...
                'levelId',    levelId, ...
                'summary',    MitigationCompareViewModel.safeField(r, 'summary', ''), ...
                'cost',       MitigationCompareViewModel.safeField(r, 'cost', struct()), ...
                'plan',       MitigationCompareViewModel.safeField(r, 'plan', struct()), ...
                'errored',    false, ...
                'err',        '');
            obj.Pending = obj.Pending - 1;
            if obj.Pending <= 0; obj.finalizeRun(); end
        end

        function onEstimateError(obj, levelId, ME)
            obj.Estimates(levelId) = struct( ...
                'levelId', levelId, 'summary', '', 'cost', struct(), ...
                'plan', struct(), 'errored', true, 'err', ME.message);
            obj.Pending = obj.Pending - 1;
            obj.Failures = obj.Failures + 1;
            if obj.Pending <= 0; obj.finalizeRun(); end
        end

        function refreshStatus(obj)
            if isempty(obj.StatusLbl) || ~isvalid(obj.StatusLbl); return; end
            switch obj.Phase
                case 'idle'
                    obj.StatusLbl.Text = Labels.get('mitigation_compare_status_idle');
                    obj.StatusLbl.FontColor = Theme.COLOR_LABEL;
                case 'loading'
                    obj.StatusLbl.Text = 'Loading circuits / backends / strategies…';
                    obj.StatusLbl.FontColor = Theme.COLOR_LABEL;
                case 'ready'
                    nSel = numel(obj.SelectedChips);
                    if nSel == 1
                        obj.StatusLbl.Text = Labels.get('mitigation_compare_status_ready_picked_one');
                    elseif nSel > 1
                        obj.StatusLbl.Text = sprintf( ...
                            Labels.get('mitigation_compare_status_ready_picked'), nSel);
                    else
                        obj.StatusLbl.Text = Labels.get('mitigation_compare_status_idle');
                    end
                    obj.StatusLbl.FontColor = Theme.COLOR_LABEL;
                case 'estimating'
                    obj.StatusLbl.Text = sprintf( ...
                        Labels.get('mitigation_compare_status_running'), obj.Pending);
                    obj.StatusLbl.FontColor = Theme.COLOR_PRIMARY;
                case 'done'
                    elapsed = toc(obj.StartTic);
                    n = numel(obj.SelectedChips);
                    if obj.Failures == 0
                        obj.StatusLbl.Text = sprintf( ...
                            Labels.get('mitigation_compare_status_done'), n, elapsed);
                        obj.StatusLbl.FontColor = Theme.COLOR_SUCCESS;
                    else
                        obj.StatusLbl.Text = sprintf( ...
                            Labels.get('mitigation_compare_status_partial'), ...
                            n - obj.Failures, n, obj.Failures);
                        obj.StatusLbl.FontColor = Theme.COLOR_WARNING;
                    end
            end
            obj.refreshButtonEnabled();
        end

        function refreshButtonEnabled(obj)
            if isempty(obj.EstimateBtn) || ~isvalid(obj.EstimateBtn); return; end
            obj.EstimateBtn.Enable = matlab.lang.OnOffSwitchState(obj.canEstimate());
        end

        function tf = canEstimate(obj)
            tf = ~isempty(obj.CircuitDropdown) && isvalid(obj.CircuitDropdown) && ...
                 ~isempty(obj.CircuitDropdown.Value) && ...
                 ~isempty(obj.BackendDropdown) && isvalid(obj.BackendDropdown) && ...
                 ~isempty(obj.BackendDropdown.Value) && ...
                 ~isempty(obj.SelectedChips);
        end
    end

    methods (Access = private)
        function populateDropdowns(obj)
            if isempty(obj.CircuitDropdown) || ~isvalid(obj.CircuitDropdown); return; end
            cItems = arrayfun(@(c) MitigationCompareViewModel.circLabel(c), ...
                obj.Circuits, 'UniformOutput', false);
            % The server's CircuitDocument primary key is `circuit_id`, not
            % `id`. Reading the wrong field left every ItemsData entry as ''
            % which broke canEstimate (Value-emptiness check) and also made
            % find(strcmp(ItemsData,Value)) collapse to row 1 regardless of
            % the user's actual pick. `id` stays as a fallback so stub
            % tests / future schema variants still resolve.
            cIds   = arrayfun(@(c) MitigationCompareViewModel.pickCircuitId(c), ...
                obj.Circuits, 'UniformOutput', false);
            obj.CircuitDropdown.Items     = cItems;
            obj.CircuitDropdown.ItemsData = cIds;

            bItems = arrayfun(@(b) MitigationCompareViewModel.safeField(b, 'name', '?'), ...
                obj.Backends, 'UniformOutput', false);
            obj.BackendDropdown.Items     = bItems;
            obj.BackendDropdown.ItemsData = bItems;
        end

        function populateChips(obj)
            if isempty(obj.ChipPanel) || ~isvalid(obj.ChipPanel); return; end
            delete(obj.ChipPanel.Children);
            n = numel(obj.Levels);
            if n == 0
                g = uigridlayout(obj.ChipPanel, [1 1]); g.Padding = [0 0 0 0];
                uilabel(g, 'Text', Labels.get('mitigation_compare_err_no_levels'), ...
                    'FontColor', Theme.COLOR_DANGER);
                return;
            end
            cols = max(2, n);
            g = uigridlayout(obj.ChipPanel, [1 cols]);
            g.RowHeight = {30}; g.Padding = [0 0 0 0];
            g.ColumnWidth = repmat({'1x'}, 1, cols);
            g.BackgroundColor = Theme.COLOR_CARD;
            obj.ChipBtns = containers.Map('KeyType','char','ValueType','any');
            for i = 1:n
                lvl = obj.Levels(i);
                lid = MitigationCompareViewModel.levelId(lvl);
                btn = uibutton(g, 'Text', MitigationCompareViewModel.levelLabel(lvl), ...
                    'ButtonPushedFcn', @(~,~) obj.onChipToggle(lid));
                btn.Layout.Row = 1; btn.Layout.Column = i;
                StyleHelper.styleBtn(btn, 'ghost');
                obj.ChipBtns(lid) = btn;
            end
        end

        function repaintChips(obj)
            if isempty(obj.ChipBtns); return; end
            keys = obj.ChipBtns.keys;
            for i = 1:numel(keys)
                btn = obj.ChipBtns(keys{i});
                if any(strcmp(obj.SelectedChips, keys{i}))
                    StyleHelper.styleBtn(btn, 'primary');
                else
                    StyleHelper.styleBtn(btn, 'ghost');
                end
                btn.FontWeight = 'bold';
            end
        end

        function picks = intersectChips(obj, candidateIds)
            picks = {};
            if isempty(obj.Levels); return; end
            available = arrayfun(@(L) MitigationCompareViewModel.levelId(L), ...
                obj.Levels, 'UniformOutput', false);
            for i = 1:numel(candidateIds)
                if any(strcmp(available, candidateIds{i}))
                    picks{end+1} = candidateIds{i}; %#ok<AGROW>
                end
            end
            if isempty(picks) && ~isempty(available)
                picks = available(1:min(2, numel(available)));
            end
        end

        function body = buildBaseBody(obj)
            cIdx = find(strcmp(obj.CircuitDropdown.ItemsData, obj.CircuitDropdown.Value), 1);
            qubits = 2;
            if ~isempty(cIdx) && cIdx <= numel(obj.Circuits)
                qubits = MitigationCompareViewModel.safeField(obj.Circuits(cIdx), ...
                    'num_qubits', 2);
                if isempty(qubits) || ~isnumeric(qubits) || qubits < 1; qubits = 2; end
            end
            shots = obj.ShotsField.Value;
            if isempty(shots) || ~isnumeric(shots) || shots < 1; shots = 4096; end
            body = struct( ...
                'primitive',                'sampler', ...
                'backend_name',             char(obj.BackendDropdown.Value), ...
                'base_shots',               int32(shots), ...
                'circuit_qubits',           int32(qubits), ...
                'cutting_overhead_qubits',  int32(0));
        end

        function paintCardsLoading(obj)
            if isempty(obj.CardPanel) || ~isvalid(obj.CardPanel); return; end
            delete(obj.CardPanel.Children);
            n = numel(obj.SelectedChips);
            if n == 0; return; end
            cols = min(n, 4);
            rows = ceil(n / cols);
            obj.CardGrid = uigridlayout(obj.CardPanel, [rows cols]);
            obj.CardGrid.RowSpacing = 12; obj.CardGrid.ColumnSpacing = 12;
            obj.CardGrid.Padding = [0 0 0 0];
            obj.CardGrid.RowHeight   = repmat({'1x'}, 1, rows);
            obj.CardGrid.ColumnWidth = repmat({'1x'}, 1, cols);
            obj.CardGrid.BackgroundColor = Theme.COLOR_BG;
            obj.CardHandles = containers.Map('KeyType','char','ValueType','any');
            for i = 1:n
                lid = obj.SelectedChips{i};
                row = floor((i-1)/cols) + 1;
                col = mod(i-1, cols) + 1;
                obj.buildCard(obj.CardGrid, lid, row, col, true);
            end
        end

        function buildCard(obj, parent, levelId, row, col, isLoading)
            card = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
                'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
            card.Layout.Row = row; card.Layout.Column = col;
            cg = uigridlayout(card, [7 2]);
            cg.RowHeight   = {28, 24, 24, 24, 24, 'fit', 'fit'};
            cg.ColumnWidth = {130, '1x'};
            cg.Padding     = [12 10 12 10]; cg.RowSpacing = 4;
            cg.BackgroundColor = Theme.COLOR_CARD;
            % Per-card vertical scroll: the body's natural height (~210 px —
            % 5 metric rows × ~24 px + summary + status + padding) exceeds
            % the row height allotted by the parent CardGrid. Scrollable on
            % the *uigridlayout* is the documented way to scroll a grid in
            % R2025b — Scrollable on the wrapping uipanel does nothing for
            % a uigridlayout child (the grid resizes to fit instead of
            % overflowing). At least one fixed-pixel row is required to
            % unlock scrolling; the five 24-28 px metric rows satisfy that.
            cg.Scrollable = 'on';

            lvl = obj.findLevel(levelId);
            titleLbl = uilabel(cg, 'Text', MitigationCompareViewModel.levelLabel(lvl), ...
                'FontSize', 13, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = [1 2];

            keyL = @(lblKey) uilabel(cg, 'Text', Labels.get(lblKey), ...
                'FontColor', Theme.COLOR_MUTED, 'FontSize', 11, ...
                'HorizontalAlignment', 'left');
            valL = @() uilabel(cg, 'Text', '', ...
                'FontSize', 12, 'FontColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');

            k1 = keyL('mitigation_compare_card_shot_mult');  k1.Layout.Row = 2; k1.Layout.Column = 1;
            v1 = valL();                                       v1.Layout.Row = 2; v1.Layout.Column = 2;
            k2 = keyL('mitigation_compare_card_total_shot'); k2.Layout.Row = 3; k2.Layout.Column = 1;
            v2 = valL();                                       v2.Layout.Row = 3; v2.Layout.Column = 2;
            k3 = keyL('mitigation_compare_card_runtime');    k3.Layout.Row = 4; k3.Layout.Column = 1;
            v3 = valL();                                       v3.Layout.Row = 4; v3.Layout.Column = 2;
            k4 = keyL('mitigation_compare_card_cost');       k4.Layout.Row = 5; k4.Layout.Column = 1;
            v4 = valL();                                       v4.Layout.Row = 5; v4.Layout.Column = 2;

            sumLbl = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
            sumLbl.Layout.Row = 6; sumLbl.Layout.Column = [1 2];

            statusLbl = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
            statusLbl.Layout.Row = 7; statusLbl.Layout.Column = [1 2];

            obj.CardHandles(levelId) = struct( ...
                'shotMult', v1, 'totalShots', v2, 'runtime', v3, ...
                'cost', v4, 'summary', sumLbl, 'status', statusLbl);

            if isLoading
                statusLbl.Text = Labels.get('mitigation_compare_card_loading');
                statusLbl.FontColor = Theme.COLOR_MUTED;
            end
        end

        function finalizeRun(obj)
            obj.Phase = 'done';
            obj.repaintCards();
            obj.repaintRanking();
            obj.repaintRecommendation();
            obj.refreshStatus();
            obj.App.logEvent('MITIG-CMP', sprintf( ...
                'Compared %d strategies (%d failed)', ...
                numel(obj.SelectedChips), obj.Failures));
        end

        function repaintCards(obj)
            keys = obj.Estimates.keys;
            for i = 1:numel(keys)
                lid = keys{i};
                if ~obj.CardHandles.isKey(lid); continue; end
                h = obj.CardHandles(lid);
                e = obj.Estimates(lid);
                if e.errored
                    h.status.Text = sprintf('%s: %s', ...
                        Labels.get('mitigation_compare_card_error'), e.err);
                    h.status.FontColor = Theme.COLOR_DANGER;
                    continue;
                end
                cost = e.cost;
                % Field names mirror CostEstimate.to_dict() in
                % qdash/api/services/mitigation_service.py — earlier names
                % (total_shots / estimated_runtime_seconds / estimated_cost_iqp)
                % never existed on the wire and rendered every card cell as the
                % unavail glyph.
                shotMult = MitigationCompareViewModel.safeField(cost, 'shot_multiplier', 1.0);
                total    = MitigationCompareViewModel.safeField(cost, 'effective_shots', NaN);
                runtime  = MitigationCompareViewModel.safeField(cost, 'est_wall_seconds', NaN);
                iqp      = MitigationCompareViewModel.safeField(cost, 'est_iqp_units', NaN);
                h.shotMult.Text   = sprintf('%.2f×', shotMult);
                h.totalShots.Text = MitigationCompareViewModel.fmtInt(total);
                h.runtime.Text    = MitigationCompareViewModel.fmtSeconds(runtime);
                h.cost.Text       = MitigationCompareViewModel.fmtCost(iqp);
                h.summary.Text    = char(string(e.summary));
                h.status.Text     = '';
            end
        end

        function repaintRanking(obj)
            ax = obj.RankAxes;
            if isempty(ax) || ~isvalid(ax)
                % Lazy build — buildRanking deliberately ships a uilabel
                % placeholder to keep screen-mount under ~1 s. We pay the
                % uiaxes construction cost here, inside the spinner that
                % the user is already watching while the parallel estimate
                % requests complete.
                if isempty(obj.RankGrid) || ~isvalid(obj.RankGrid); return; end
                if ~isempty(obj.RankPlaceholder) && isvalid(obj.RankPlaceholder)
                    delete(obj.RankPlaceholder);
                    obj.RankPlaceholder = [];
                end
                ax = uiaxes(obj.RankGrid);
                ax.Toolbar.Visible = 'off';
                ax.Color  = Theme.COLOR_CARD;
                ax.XColor = Theme.COLOR_MUTED;
                ax.YColor = Theme.COLOR_MUTED;
                ax.FontSize = 10;
                ax.Box   = 'off';
                ax.XTick = []; ax.YTick = [];
                try; disableDefaultInteractivity(ax); catch; end
                obj.RankAxes = ax;
            end
            cla(ax);
            keys = obj.Estimates.keys;
            mults = []; labels = {};
            for i = 1:numel(keys)
                e = obj.Estimates(keys{i});
                if e.errored; continue; end
                mults(end+1) = MitigationCompareViewModel.safeField( ...
                    e.cost, 'shot_multiplier', 1.0); %#ok<AGROW>
                labels{end+1} = MitigationCompareViewModel.levelLabel( ...
                    obj.findLevel(keys{i})); %#ok<AGROW>
            end
            if isempty(mults); return; end
            [mults, ord] = sort(mults);
            labels = labels(ord);

            colors = zeros(numel(mults), 3);
            for i = 1:numel(mults)
                colors(i, :) = MitigationCompareViewModel.gradeColor(mults(i));
            end
            hold(ax, 'on');
            for i = 1:numel(mults)
                barh(ax, i, mults(i), 'FaceColor', colors(i, :), ...
                    'EdgeColor', 'none', 'BarWidth', 0.6);
            end
            hold(ax, 'off');
            ax.YTick = 1:numel(labels);
            ax.YTickLabel = labels;
            ax.YDir = 'reverse';
            ax.XLabel.String = Labels.get('mitigation_compare_chart_xlabel');
            ax.XLim = [0, max(1.05, max(mults) * 1.1)];
        end

        function repaintRecommendation(obj)
            if isempty(obj.ReccoLbl) || ~isvalid(obj.ReccoLbl); return; end
            keys = obj.Estimates.keys;
            best = struct('cheapest', [], 'balance', [], 'aggro', []);
            cheapMult = inf; balanceMult = inf; aggroMult = -inf;
            for i = 1:numel(keys)
                e = obj.Estimates(keys{i});
                if e.errored; continue; end
                m = MitigationCompareViewModel.safeField( ...
                    e.cost, 'shot_multiplier', NaN);
                if ~isfinite(m); continue; end
                lid = keys{i};
                lbl = MitigationCompareViewModel.levelLabel(obj.findLevel(lid));
                if m < cheapMult
                    cheapMult = m; best.cheapest = struct('lbl', lbl, 'm', m);
                end
                lvlNum = MitigationCompareViewModel.parseLevelId(lid);
                if lvlNum >= 1 && m < balanceMult
                    balanceMult = m; best.balance = struct('lbl', lbl, 'm', m);
                end
                if m > aggroMult
                    aggroMult = m; best.aggro = struct('lbl', lbl, 'm', m);
                end
            end
            lines = {};
            if ~isempty(best.cheapest)
                lines{end+1} = sprintf( ...
                    Labels.get('mitigation_compare_recco_cheapest'), ...
                    best.cheapest.lbl, sprintf('%.2f×', best.cheapest.m));
            end
            if ~isempty(best.balance) && ~strcmp(best.balance.lbl, ...
                    MitigationCompareViewModel.tryGetLbl(best.cheapest))
                lines{end+1} = sprintf( ...
                    Labels.get('mitigation_compare_recco_balance'), ...
                    best.balance.lbl, sprintf('%.2f×', best.balance.m));
            end
            if ~isempty(best.aggro) && ~strcmp(best.aggro.lbl, ...
                    MitigationCompareViewModel.tryGetLbl(best.cheapest))
                lines{end+1} = sprintf( ...
                    Labels.get('mitigation_compare_recco_aggro'), ...
                    best.aggro.lbl, sprintf('%.2f×', best.aggro.m));
            end
            lines{end+1} = Labels.get('mitigation_compare_recco_explain');
            obj.ReccoLbl.Text = strjoin(lines, sprintf('\n'));
        end

        function lvl = findLevel(obj, levelId)
            lvl = struct('id', levelId, 'name', levelId, 'label', levelId);
            for i = 1:numel(obj.Levels)
                lid = MitigationCompareViewModel.levelId(obj.Levels(i));
                if strcmp(lid, levelId); lvl = obj.Levels(i); return; end
            end
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
            if iscell(raw)
                try; arr = [raw{:}]; catch; arr = raw; end
            else
                arr = raw;
            end
        end

        function arr = normalizeLevels(raw)
            arr = MitigationCompareViewModel.normalizeList(raw);
        end

        function lbl = levelLabel(lvl)
            if isempty(lvl); lbl = ''; return; end
            if isfield(lvl, 'label') && ~isempty(lvl.label)
                lbl = char(string(lvl.label)); return;
            end
            if isfield(lvl, 'name')  && ~isempty(lvl.name)
                lbl = char(string(lvl.name));  return;
            end
            if isfield(lvl, 'id')
                lbl = char(string(lvl.id));   return;
            end
            lbl = '?';
        end

        function id = levelId(lvl)
            if isfield(lvl, 'id')
                id = char(string(lvl.id));
            elseif isfield(lvl, 'name')
                id = char(string(lvl.name));
            else
                id = '?';
            end
        end

        function n = parseLevelId(idChar)
            v = str2double(idChar);
            if isnan(v); n = -1; else; n = int32(v); end
        end

        function lbl = circLabel(c)
            n  = MitigationCompareViewModel.safeField(c, 'name', '');
            q  = MitigationCompareViewModel.safeField(c, 'num_qubits', 0);
            if isempty(n)
                n = MitigationCompareViewModel.safeField(c, 'circuit_id', ...
                    MitigationCompareViewModel.safeField(c, 'id', '?'));
            end
            lbl = sprintf('%s (%dq)', char(string(n)), double(q));
        end

        function id = pickCircuitId(c)
            id = MitigationCompareViewModel.safeField(c, 'circuit_id', '');
            if isempty(id)
                id = MitigationCompareViewModel.safeField(c, 'id', '');
            end
            id = char(string(id));
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
            if ~isnumeric(n) || ~isfinite(n)
                txt = Labels.get('mitigation_compare_card_unavail'); return;
            end
            if n >= 1e6
                txt = sprintf('%.2fM', n/1e6);
            elseif n >= 1e3
                txt = sprintf('%.1fk', n/1e3);
            else
                txt = sprintf('%d', round(n));
            end
        end

        function txt = fmtSeconds(s)
            if ~isnumeric(s) || ~isfinite(s)
                txt = Labels.get('mitigation_compare_card_unavail'); return;
            end
            if s < 60
                txt = sprintf('%.1fs', s);
            elseif s < 3600
                txt = sprintf('%dm %ds', floor(s/60), round(mod(s,60)));
            else
                txt = sprintf('%.1fh', s/3600);
            end
        end

        function txt = fmtCost(c)
            if ~isnumeric(c) || ~isfinite(c)
                txt = Labels.get('mitigation_compare_card_unavail'); return;
            end
            txt = sprintf('~%.3f IQP', c);
        end

        function rgb = gradeColor(mult)
            if ~isfinite(mult); rgb = [0.5 0.5 0.5]; return; end
            if mult <= 1.0; rgb = [0.30 0.70 0.40]; return; end
            if mult <= 5.0
                t = (mult - 1.0) / 4.0;
                rgb = (1-t) * [0.30 0.70 0.40] + t * [0.95 0.70 0.30];
            elseif mult <= 20.0
                t = (mult - 5.0) / 15.0;
                rgb = (1-t) * [0.95 0.70 0.30] + t * [0.85 0.30 0.30];
            else
                rgb = [0.85 0.30 0.30];
            end
        end

        function s = tryGetLbl(rec)
            if isempty(rec); s = ''; else; s = rec.lbl; end
        end
    end
end
