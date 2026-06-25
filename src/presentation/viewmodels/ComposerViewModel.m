classdef ComposerViewModel < handle
    % ComposerViewModel  State + callbacks for the Composer screen.
    %
    %   Owns the live CircuitModel under edit, the armed-gate state
    %   machine (1Q / 2Q / 3Q click sequences), the OpenQASM mirror
    %   sync direction guard, the Inspect-mode cache + auto-step timer,
    %   and all uifigure-modal dialogs (Templates gallery, parameter
    %   prompts, Save name dialog, gate-theta prompt).
    %
    %   The Screen builder writes UI handles into the public properties
    %   below so callbacks can read them without indirection. Every
    %   callback logs to `app.logEvent` under either the 'COMPOSE' or
    %   'INSPECT' category for the Dashboard activity feed.

    properties
        LastRefresh = []
    end

    % UI handles (populated by ComposerScreen).
    properties
        RootGrid

        StatusLbl
        BtnInspect
        BtnOpenAnalysis
        BtnExport
        BtnBundle

        HeroPanel

        PaletteButtons

        CanvasAxes
        CanvasInnerGrid       % uigridlayout that hosts the axes; row 1 resized per-qubit (25 px each)
        CanvasEmpty
        SelectionTitle
        SelectionDetail

        MirrorPanel
        MirrorTextarea
        MirrorErrorLbl
        MirrorToggleBtn

        InspectPanel
        InspectToggleBtn
        InspectSlider
        InspectStepLbl
        InspectPlayBtn
        InspectCaptionLbl
        InspectContent
        InspectTabBlochBtn
        InspectTabAmpsBtn
    end

    properties
        Model

        ArmedKind     = ''
        PendingClicks = []

        MirrorSyncSuspended = false
        LastValidQasm = ''

        InspectExpanded = true   % Inspect footer is pinned open
        InspectSteps    = []
        InspectStepIdx  = 1
        InspectTab      = 'bloch'
        PlayTimer       = []

        MirrorCollapsed = false
    end

    properties (Access = private)
        App
    end

    methods
        function obj = ComposerViewModel(app)
            obj.App = app;
            obj.Model = CircuitModel(2);
        end

        % ── Wiring helpers ───────────────────────────────────────────────
        function bindRootGrid(obj, g)
            obj.RootGrid = g;
            obj.applyMirrorCollapse();
            obj.applyInspectCollapse();
            % Inspect is pinned open, so trigger an initial simulator run
            % (or the empty-state hint when there are no gates yet).
            if obj.InspectExpanded
                obj.refreshInspect();
            end
        end

        % ── Toolbar callbacks ────────────────────────────────────────────
        function onAddQubit(obj)
            if obj.Model.NumQubits >= CircuitModel.MAX_QUBITS
                obj.flashStatus(Labels.get('composer_err_max_qubits'), 'danger'); return;
            end
            obj.Model.setNumQubits(obj.Model.NumQubits + 1);
            obj.afterModelEdit(sprintf(Labels.get('composer_toast_qubit_added'), obj.Model.NumQubits-1));
        end

        function onRemoveQubit(obj)
            if obj.Model.NumQubits <= 1
                obj.flashStatus(Labels.get('composer_err_min_qubits'), 'danger'); return;
            end
            obj.Model.setNumQubits(obj.Model.NumQubits - 1);
            obj.afterModelEdit(sprintf(Labels.get('composer_toast_qubit_removed'), obj.Model.NumQubits));
        end

        function onClear(obj)
            obj.Model.clear();
            obj.PendingClicks = [];
            obj.afterModelEdit(Labels.get('composer_toast_circuit_cleared'));
        end

        function onValidate(obj)
            try
                CircuitModel.fromQasm(obj.Model.toQasm());
                obj.flashStatus(sprintf(Labels.get('composer_status_valid_fmt'), ...
                    obj.Model.NumQubits, obj.Model.depth(), numel(obj.Model.Gates)), 'success');
            catch ME
                obj.flashStatus(sprintf(Labels.get('composer_status_invalid_fmt'), ME.message), 'danger');
            end
        end

        function onSave(obj)
            if obj.Model.isEmpty()
                obj.flashStatus(Labels.get('composer_err_no_gates'), 'danger'); return;
            end
            if ~obj.App.State.hasProject()
                obj.flashStatus(Labels.get('composer_save_no_project'), 'danger'); return;
            end
            obj.openSaveDialog();
        end

        function onOpenTemplatesDialog(obj)
            obj.openTemplatesDialog();
        end

        function onOpenAnalysis(obj)
            obj.App.onSelectSection('Analysis');
        end

        function onOpenExport(obj)
            % Multi-target code export: OpenQASM 2/3, Qiskit, Cirq, Braket.
            obj.openExportDialog();
        end

        function onOpenBundle(obj)
            % Reproducibility-bundle export — packages the current circuit
            % plus opt-in metadata (backend calibration, mitigation
            % estimates, FT estimate) into a single ZIP with manifest.
            obj.openBundleDialog();
        end

        function onToggleMirror(obj)
            obj.MirrorCollapsed = ~obj.MirrorCollapsed;
            obj.applyMirrorCollapse();
        end

        function onToggleInspect(obj)
            % Inspect is pinned expanded — the button just re-runs the
            % simulator on the current circuit so the user can refresh
            % the slider/Bloch/amps after edits.
            obj.InspectExpanded = true;
            obj.applyInspectCollapse();
            obj.refreshInspect();
        end

        % ── Palette: arm a gate ──────────────────────────────────────────
        function onArmGate(obj, kind)
            obj.ArmedKind = char(kind);
            obj.PendingClicks = [];
            obj.highlightPalette();
            obj.refreshStatus();
            obj.App.logEvent('COMPOSE', sprintf('Armed %s', obj.ArmedKind));
        end

        % ── Canvas click ────────────────────────────────────────────────
        function onCanvasClick(obj, evt)
            if isempty(obj.ArmedKind); return; end
            try
                cp = obj.CanvasAxes.CurrentPoint;
                yClick = cp(1, 2);
            catch
                if nargin > 1 && isfield(evt, 'IntersectionPoint')
                    yClick = evt.IntersectionPoint(2);
                else
                    return;
                end
            end
            n = obj.Model.NumQubits;
            qubit = round(yClick);
            if qubit < 0 || qubit >= n; return; end

            obj.PendingClicks(end+1) = qubit; %#ok<AGROW>
            need = obj.expectedClicks(obj.ArmedKind);

            if numel(obj.PendingClicks) < need
                obj.refreshStatus();
                return;
            end

            if numel(unique(obj.PendingClicks)) ~= numel(obj.PendingClicks)
                obj.flashStatus('Pick distinct qubits — same wire selected twice.', 'danger');
                obj.PendingClicks = [];
                return;
            end

            obj.placeGate(obj.ArmedKind, obj.PendingClicks);
            obj.PendingClicks = [];
            obj.refreshStatus();
        end

        function onDeleteLast(obj)
            if obj.Model.isEmpty(); return; end
            obj.Model.removeGate(numel(obj.Model.Gates));
            obj.afterModelEdit('Removed last gate.');
        end

        % ── Mirror sync ──────────────────────────────────────────────────
        function onMirrorEdited(obj)
            if obj.MirrorSyncSuspended; return; end
            text = strjoin(obj.MirrorTextarea.Value, sprintf('\n'));
            try
                m = CircuitModel.fromQasm(text);
                obj.Model = m;
                obj.LastValidQasm = text;
                obj.MirrorErrorLbl.Text = '';
                obj.invalidateInspect();
                obj.repaintCanvas();
                obj.refreshStatus();
                obj.App.logEvent('COMPOSE', 'Mirror commit: canvas re-rendered');
            catch ME
                obj.MirrorErrorLbl.Text = sprintf('%s: %s', ...
                    Labels.get('composer_mirror_invalid'), ME.message);
                obj.flashStatus(sprintf(Labels.get('composer_status_invalid_fmt'), ME.message), 'danger');
            end
        end

        % Legacy v0.1 entry-point kept for any out-of-tree callers; the
        % live UI no longer wires it (Templates dialog dispatches
        % directly to onTemplatePicked).
        function onTemplateClicked(obj, templateId)
            try
                meta = TemplateRegistry.find(templateId);
                obj.onTemplatePicked(meta, []);
            catch ME
                obj.flashStatus(ME.message, 'danger');
            end
        end

        % ── Inspect callbacks ────────────────────────────────────────────
        function onInspectSliderChanging(obj, evt)
            if isempty(obj.InspectSteps); return; end
            idx = max(1, min(numel(obj.InspectSteps), round(evt.Value) + 1));
            if idx ~= obj.InspectStepIdx
                obj.InspectStepIdx = idx;
                obj.paintInspectStep();
            end
        end

        function onInspectSliderChanged(obj, evt)
            obj.onInspectSliderChanging(evt);
        end

        function onInspectStepDelta(obj, delta)
            if isempty(obj.InspectSteps); return; end
            obj.InspectStepIdx = max(1, min(numel(obj.InspectSteps), obj.InspectStepIdx + delta));
            obj.InspectSlider.Value = obj.InspectStepIdx - 1;
            obj.paintInspectStep();
        end

        function onInspectPlayToggle(obj)
            if isempty(obj.PlayTimer) || ~isvalid(obj.PlayTimer)
                obj.startPlayTimer();
                obj.InspectPlayBtn.Text = Labels.get('composer_inspect_pause');
            else
                obj.stopPlayTimer();
                obj.InspectPlayBtn.Text = Labels.get('composer_inspect_play');
            end
        end

        function onInspectTab(obj, tab)
            obj.InspectTab = char(tab);
            if strcmp(obj.InspectTab, 'bloch')
                StyleHelper.styleBtn(obj.InspectTabBlochBtn, 'primary');
                StyleHelper.styleBtn(obj.InspectTabAmpsBtn,  'ghost');
            else
                StyleHelper.styleBtn(obj.InspectTabBlochBtn, 'ghost');
                StyleHelper.styleBtn(obj.InspectTabAmpsBtn,  'primary');
            end
            obj.paintInspectStep();
        end

        % ── Public painters ──────────────────────────────────────────────
        function repaintCanvas(obj)
            if isempty(obj.CanvasAxes) || ~isvalid(obj.CanvasAxes); return; end
            ax = obj.CanvasAxes;
            cla(ax);
            n = max(1, obj.Model.NumQubits);
            depth = max(1, obj.Model.depth());
            xMax = depth + 1;

            % Pixel-fixed wire spacing: 25 px per qubit unit (matches the
            % rest of the app's circuit-diagram surfaces). Resize the
            % inner grid's axes row so consecutive wires render exactly
            % 25 px apart regardless of container height.
            if ~isempty(obj.CanvasInnerGrid) && isvalid(obj.CanvasInnerGrid)
                obj.CanvasInnerGrid.RowHeight{1} = max(50, 25 * n);
            end

            % Grid backdrop: keep at least 8 visible time-step columns
            % even when the circuit is empty, plus 3 columns of headroom
            % past the last gate so the user always sees where the next
            % gate would land. Vertical dotted lines at each integer x
            % column produce the IBM/Cirq-style grid aesthetic.
            gridCols = max(8, depth + 3);
            xMax = max(xMax, gridCols + 0.5);

            ax.XLim = [-0.5, xMax + 0.5];
            ax.YLim = [-0.5, n - 0.5];
            ax.YDir = 'reverse';
            hold(ax, 'on');

            % Grid columns first → bottom layer (wires + gates draw above).
            gridColor = 0.5 * Theme.COLOR_DIVIDER + 0.5 * Theme.COLOR_CARD;
            for col = 1:gridCols
                line(ax, [col col], [-0.5, n - 0.5], ...
                    'Color', gridColor, 'LineStyle', ':', 'LineWidth', 0.5, ...
                    'HitTest', 'off', 'PickableParts', 'none');
            end

            wireC = Theme.COLOR_DIVIDER;
            for q = 0:n-1
                line(ax, [-0.5 xMax+0.5], [q q], 'Color', wireC, 'LineWidth', 1.2, ...
                    'HitTest', 'off', 'PickableParts', 'none');
                text(ax, -0.4, q, sprintf(Labels.get('composer_canvas_qubit_fmt'), q), ...
                    'FontSize', 11, 'Color', Theme.COLOR_LABEL, 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
                    'HitTest', 'off', 'PickableParts', 'none');
            end

            for i = 1:numel(obj.Model.Gates)
                obj.drawGate(ax, i, obj.Model.Gates(i));
            end

            obj.CanvasEmpty.Visible = matlab.lang.OnOffSwitchState(obj.Model.isEmpty());

            hold(ax, 'off');
            obj.LastRefresh = tic;
        end

        function repaintMirror(obj)
            if isempty(obj.MirrorTextarea) || ~isvalid(obj.MirrorTextarea); return; end
            obj.MirrorSyncSuspended = true;
            obj.MirrorTextarea.Value = obj.Model.toQasm();
            obj.MirrorSyncSuspended = false;
            obj.MirrorErrorLbl.Text = '';
        end

        function refreshStatus(obj)
            if isempty(obj.StatusLbl) || ~isvalid(obj.StatusLbl); return; end
            obj.refreshSelection();

            if isempty(obj.ArmedKind)
                obj.StatusLbl.Text = Labels.get('composer_status_idle');
                obj.StatusLbl.FontColor = Theme.COLOR_LABEL;
                return;
            end
            need = obj.expectedClicks(obj.ArmedKind);
            placed = numel(obj.PendingClicks);
            if need > 1
                if placed == 0
                    obj.StatusLbl.Text = sprintf(Labels.get('composer_status_armed_2q_fmt'), upper(obj.ArmedKind));
                else
                    obj.StatusLbl.Text = Labels.get('composer_status_pending_2q');
                end
            else
                obj.StatusLbl.Text = sprintf(Labels.get('composer_status_armed_fmt'), upper(obj.ArmedKind));
            end
            obj.StatusLbl.FontColor = Theme.COLOR_PRIMARY;
        end

        function refreshSelection(obj)
            if isempty(obj.SelectionTitle) || ~isvalid(obj.SelectionTitle); return; end
            n = numel(obj.Model.Gates);
            if n == 0
                obj.SelectionTitle.Text = 'Selected: (none)';
                obj.SelectionDetail.Text = sprintf( ...
                    'Qubits: %d · Gates: 0 · Depth: 0', obj.Model.NumQubits);
                return;
            end
            g = obj.Model.Gates(end);
            obj.SelectionTitle.Text = sprintf('Last: %s', StatevectorSimulator.gateLabel(g));
            obj.SelectionDetail.Text = sprintf( ...
                'Qubits: %d · Gates: %d · Depth: %d\nLast added: %s', ...
                obj.Model.NumQubits, n, obj.Model.depth(), ...
                StatevectorSimulator.gateLabel(g));
        end

        function applyHeroVisibility(obj)
            % Hero strip stays always visible — small enough that hiding
            % it adds noise rather than reclaiming useful canvas space.
            if isempty(obj.HeroPanel) || ~isvalid(obj.HeroPanel); return; end
            obj.HeroPanel.Visible = matlab.lang.OnOffSwitchState(true);
        end
    end

    methods (Access = private)
        function n = expectedClicks(~, kind)
            switch kind
                case {'cx','cz','swap'}; n = 2;
                case 'ccx';              n = 3;
                otherwise;               n = 1;
            end
        end

        function placeGate(obj, kind, qubits)
            try
                params = [];
                if any(strcmp({'rx','ry','rz'}, kind))
                    theta = obj.promptTheta(kind, qubits(1));
                    if isempty(theta); return; end
                    params = theta;
                end
                obj.Model.addGate(kind, qubits, params);
                obj.afterModelEdit(sprintf('Placed %s on q[%s]', upper(kind), ...
                    strjoin(arrayfun(@(q) sprintf('%d', q), qubits, 'UniformOutput', false), ',')));
                obj.App.logEvent('COMPOSE', sprintf('Add %s on %s', kind, mat2str(qubits)));
            catch ME
                obj.flashStatus(ME.message, 'danger');
            end
        end

        function afterModelEdit(obj, statusMsg)
            obj.invalidateInspect();
            obj.repaintCanvas();
            obj.repaintMirror();
            obj.applyHeroVisibility();
            obj.refreshStatus();
            obj.LastValidQasm = obj.Model.toQasm();
            if nargin >= 2 && ~isempty(statusMsg)
                obj.flashStatus(statusMsg, 'info');
            end
            if ~isempty(obj.BtnOpenAnalysis) && isvalid(obj.BtnOpenAnalysis)
                obj.BtnOpenAnalysis.Enable = matlab.lang.OnOffSwitchState(false);
            end
        end

        function highlightPalette(obj)
            if isempty(obj.PaletteButtons); return; end
            kinds = obj.PaletteButtons.keys;
            for i = 1:numel(kinds)
                btn = obj.PaletteButtons(kinds{i});
                if strcmp(kinds{i}, obj.ArmedKind)
                    StyleHelper.styleBtn(btn, 'primary');
                else
                    StyleHelper.styleBtn(btn, 'ghost');
                end
                btn.FontWeight = 'bold';
            end
        end

        function flashStatus(obj, msg, level)
            if isempty(obj.StatusLbl) || ~isvalid(obj.StatusLbl); return; end
            obj.StatusLbl.Text = char(msg);
            switch char(level)
                case 'danger';  obj.StatusLbl.FontColor = Theme.COLOR_DANGER;
                case 'success'; obj.StatusLbl.FontColor = Theme.COLOR_SUCCESS;
                otherwise;      obj.StatusLbl.FontColor = Theme.COLOR_LABEL;
            end
        end

        % ── Drawing one gate on the canvas ───────────────────────────────
        function drawGate(obj, ax, idx, g)
            x = idx;
            switch g.kind
                case {'h','x','y','z','s','t','sdg','tdg'}
                    obj.drawBox(ax, x, g.qubits(1), upper(g.kind));
                case 'reset'
                    obj.drawBox(ax, x, g.qubits(1), '|0⟩');
                case {'rx','ry','rz'}
                    txt = sprintf('%s(%s)', upper(g.kind), CircuitModel.formatTheta(g.params(1)));
                    obj.drawBox(ax, x, g.qubits(1), txt);
                case 'cx'
                    obj.drawCtrl(ax, x, g.qubits(1));
                    obj.drawTargetCircle(ax, x, g.qubits(2));
                    obj.drawConnector(ax, x, g.qubits(1), g.qubits(2));
                case 'cz'
                    obj.drawCtrl(ax, x, g.qubits(1));
                    obj.drawCtrl(ax, x, g.qubits(2));
                    obj.drawConnector(ax, x, g.qubits(1), g.qubits(2));
                case 'swap'
                    obj.drawSwapMark(ax, x, g.qubits(1));
                    obj.drawSwapMark(ax, x, g.qubits(2));
                    obj.drawConnector(ax, x, g.qubits(1), g.qubits(2));
                case 'ccx'
                    obj.drawCtrl(ax, x, g.qubits(1));
                    obj.drawCtrl(ax, x, g.qubits(2));
                    obj.drawTargetCircle(ax, x, g.qubits(3));
                    qs = sort(g.qubits);
                    s = ComposerViewModel.gateStyle();
                    line(ax, [x x], [qs(1) qs(end)], ...
                        'Color', s.Border, 'LineWidth', 1.2, ...
                        'HitTest', 'off', 'PickableParts', 'none');
                case 'measure'
                    obj.drawBox(ax, x, g.qubits(1), 'M');
                case 'barrier'
                    n = obj.Model.NumQubits;
                    line(ax, [x x], [-0.4 n-0.6], ...
                        'Color', Theme.COLOR_MUTED, 'LineStyle', ':', 'LineWidth', 1.2, ...
                        'HitTest', 'off', 'PickableParts', 'none');
            end
        end

        function drawBox(~, ax, x, q, label)
            % Blue gate palette matches the SVG circuit renderer
            % (CircuitDiagram.drawSvgDiagram) used by Circuit Preview
            % and the QTAUBench Similarity Circuit Diagram tab, so the
            % Composer canvas reads as the same visual language as the
            % other circuit-render surfaces instead of the previous
            % theme-driven purple variant.
            s = ComposerViewModel.gateStyle();
            w = 0.7; h = 0.55;
            rectangle(ax, 'Position', [x - w/2, q - h/2, w, h], ...
                'FaceColor', s.Fill, ...
                'EdgeColor', s.Border, 'LineWidth', 1.2, ...
                'Curvature', 0.3);
            text(ax, x, q, char(label), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontWeight', 'bold', 'FontSize', 11, ...
                'Color', s.Text, ...
                'HitTest', 'off', 'PickableParts', 'none');
        end

        function drawCtrl(~, ax, x, q)
            s = ComposerViewModel.gateStyle();
            r = 0.13;
            rectangle(ax, 'Position', [x-r, q-r, 2*r, 2*r], ...
                'FaceColor', s.Border, ...
                'EdgeColor', s.Border, 'Curvature', 1.0);
        end

        function drawTargetCircle(~, ax, x, q)
            s = ComposerViewModel.gateStyle();
            r = 0.22;
            rectangle(ax, 'Position', [x-r, q-r, 2*r, 2*r], ...
                'FaceColor', s.TargetFill, 'EdgeColor', s.Border, ...
                'LineWidth', 1.4, 'Curvature', 1.0);
            line(ax, [x-r, x+r], [q q], 'Color', s.Text, 'LineWidth', 1.4, ...
                'HitTest', 'off', 'PickableParts', 'none');
            line(ax, [x x], [q-r, q+r], 'Color', s.Text, 'LineWidth', 1.4, ...
                'HitTest', 'off', 'PickableParts', 'none');
        end

        function drawSwapMark(~, ax, x, q)
            s = ComposerViewModel.gateStyle();
            r = 0.16;
            line(ax, [x-r, x+r], [q-r, q+r], 'Color', s.Border, 'LineWidth', 1.6);
            line(ax, [x-r, x+r], [q+r, q-r], 'Color', s.Border, 'LineWidth', 1.6);
        end

        function drawConnector(~, ax, x, q1, q2)
            s = ComposerViewModel.gateStyle();
            line(ax, [x x], [min(q1,q2), max(q1,q2)], ...
                'Color', s.Border, 'LineWidth', 1.2, ...
                'HitTest', 'off', 'PickableParts', 'none');
        end

        % ── Templates dialog ─────────────────────────────────────────────
        function openTemplatesDialog(obj)
            items = TemplateRegistry.list();
            nTotal = numel(items);

            fig = uifigure('Name', Labels.get('composer_btn_templates'), ...
                'Position', [200 100 960 720], 'WindowStyle', 'modal', ...
                'Color', Theme.COLOR_BG);
            try; Theme.applyFigureMode(fig, Theme.activeName()); catch; end

            outer = uigridlayout(fig, [4 1]);
            outer.RowHeight = {40, '1x', 1, 'fit'};
            outer.Padding = [16 16 16 16];
            outer.RowSpacing = 10;
            outer.BackgroundColor = Theme.COLOR_BG;

            % ── Row 1: Search bar (field + button + match-count label) ───
            top = uigridlayout(outer, [1 3]);
            top.Layout.Row = 1; top.Layout.Column = 1;
            top.ColumnWidth = {'1x', 110, 200};
            top.Padding = [0 0 0 0]; top.ColumnSpacing = 8;
            top.BackgroundColor = Theme.COLOR_BG;

            searchField = uieditfield(top, 'text', ...
                'Placeholder', Labels.get('composer_template_search_placeholder', ...
                    'Search templates by name or description…'));
            searchField.Layout.Row = 1; searchField.Layout.Column = 1;
            searchField.FontSize = 12;
            searchField.ValueChangedFcn = @(src,~) rebuildCards(src.Value);

            searchBtn = uibutton(top, 'Text', [char(8981) ' Search'], ...
                'ButtonPushedFcn', @(~,~) rebuildCards(searchField.Value));
            searchBtn.Layout.Row = 1; searchBtn.Layout.Column = 2;
            StyleHelper.styleBtn(searchBtn, 'ghost');
            searchBtn.FontSize = 12;

            countLbl = uilabel(top, 'Text', ...
                sprintf(Labels.get('composer_template_count_fmt', '%d of %d templates'), ...
                    nTotal, nTotal));
            countLbl.Layout.Row = 1; countLbl.Layout.Column = 3;
            countLbl.HorizontalAlignment = 'right';
            countLbl.FontSize = 11;
            countLbl.FontColor = Theme.COLOR_MUTED;

            % ── Row 2: Card grid hosted in a scrollable panel so we can
            % grow past the visible viewport once filters narrow / widen
            % the set.
            gridHost = uipanel(outer, 'BorderType', 'none', ...
                'BackgroundColor', Theme.COLOR_BG, 'Scrollable', 'on');
            gridHost.Layout.Row = 2; gridHost.Layout.Column = 1;

            grid = uigridlayout(gridHost, [1 4]);
            grid.RowSpacing    = 12;
            grid.ColumnSpacing = 12;
            grid.ColumnWidth   = {'1x','1x','1x','1x'};
            grid.Padding       = [4 4 4 4];
            grid.BackgroundColor = Theme.COLOR_BG;
            % uipanel.Scrollable on its own does not engage when the
            % child is a uigridlayout — the grid auto-fills the panel
            % instead of producing the fixed-pixel overflow uipanel
            % needs to grow a scrollbar, so all 18 templates packed
            % into 5 rows (180 px each) silently clipped the bottom
            % two rows below the dialog footer. Setting Scrollable='on'
            % on the grid itself activates vertical scrolling because
            % rebuildCards writes fixed-pixel RowHeight per card row.
            grid.Scrollable = 'on';

            % Seed with all templates.
            rebuildCards('');

            % ── Row 3: hairline divider ──────────────────────────────────
            divider = uipanel(outer, 'BorderType', 'none', ...
                'BackgroundColor', Theme.COLOR_DIVIDER);
            divider.Layout.Row = 3; divider.Layout.Column = 1;

            % ── Row 4: footer (Cancel) ───────────────────────────────────
            barRow = uigridlayout(outer, [1 2]);
            barRow.Layout.Row = 4; barRow.Layout.Column = 1;
            barRow.ColumnWidth = {'1x', 100};
            barRow.RowHeight = {36};
            barRow.Padding = [0 0 0 0];
            barRow.BackgroundColor = Theme.COLOR_BG;
            spacer = uilabel(barRow, 'Text', ''); spacer.Layout.Column = 1; %#ok<NASGU>
            cancelBtn = uibutton(barRow, 'Text', Labels.get('composer_param_cancel'), ...
                'ButtonPushedFcn', @(~,~) close(fig));
            cancelBtn.Layout.Column = 2;
            StyleHelper.styleBtn(cancelBtn, 'ghost');

            % ── Closures ─────────────────────────────────────────────────
            function rebuildCards(query)
                if ~isvalid(grid); return; end
                delete(grid.Children);
                filtered = filterItems(items, query);
                nMatch = numel(filtered);
                countLbl.Text = sprintf( ...
                    Labels.get('composer_template_count_fmt', '%d of %d templates'), ...
                    nMatch, nTotal);
                nCols = 4;

                if nMatch == 0
                    grid.RowHeight   = {'fit'};
                    grid.ColumnWidth = {'1x'};
                    qstr = strtrim(char(query));
                    emptyMsg = uilabel(grid, ...
                        'Text', sprintf( ...
                            Labels.get('composer_template_no_match_fmt', ...
                                'No templates match "%s".'), qstr), ...
                        'HorizontalAlignment', 'center', ...
                        'FontSize', 13, 'FontColor', Theme.COLOR_MUTED);
                    emptyMsg.Layout.Row = 1; emptyMsg.Layout.Column = 1;
                    return;
                end

                nRows = ceil(nMatch / nCols);
                grid.RowHeight   = repmat({180}, 1, nRows);
                grid.ColumnWidth = repmat({'1x'}, 1, nCols);
                for k = 1:nMatch
                    m = filtered(k);
                    r = floor((k-1)/nCols) + 1;
                    c = mod(k-1, nCols) + 1;
                    obj.buildTemplateCard(grid, m, fig, r, c);
                end
            end

            function out = filterItems(allItems, q)
                qs = lower(strtrim(char(q)));
                if isempty(qs)
                    out = allItems;
                    return;
                end
                keep = false(1, numel(allItems));
                for i = 1:numel(allItems)
                    hay = lower([char(allItems(i).name)        ' ' ...
                                 char(allItems(i).description) ' ' ...
                                 char(allItems(i).id)]);
                    if contains(hay, qs)
                        keep(i) = true;
                    end
                end
                out = allItems(keep);
            end
        end

        function buildTemplateCard(obj, parent, meta, parentFig, row, col)
            card = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
                'BorderColor', Theme.COLOR_DIVIDER, 'BackgroundColor', Theme.COLOR_CARD);
            card.Layout.Row = row; card.Layout.Column = col;
            cg = uigridlayout(card, [4 1]);
            cg.Padding = [12 10 12 10];
            cg.RowSpacing = 4;
            cg.RowHeight = {22, 'fit', 18, 32};
            cg.BackgroundColor = Theme.COLOR_CARD;

            uilabel(cg, 'Text', meta.name, ...
                'FontSize', 13, 'FontWeight', 'bold', 'FontColor', Theme.COLOR_HEADING);
            uilabel(cg, 'Text', meta.description, ...
                'FontSize', 11, 'FontColor', Theme.COLOR_LABEL, 'WordWrap', 'on');
            uilabel(cg, 'Text', sprintf('%d qubit(s) · %s', meta.qubits, ...
                ternary(meta.parameterized, 'parameterized', 'fixed')), ...
                'FontSize', 10, 'FontColor', Theme.COLOR_MUTED);

            useBtn = uibutton(cg, 'Text', Labels.get('composer_template_use_btn'), ...
                'ButtonPushedFcn', @(~,~) obj.onTemplatePicked(meta, parentFig));
            StyleHelper.styleBtn(useBtn, 'primary');
        end

        function onTemplatePicked(obj, meta, parentFig)
            params = TemplateRegistry.defaultParams(meta.id);
            if meta.parameterized
                params = obj.openParamDialog(meta, params);
                if isempty(params)
                    if ~isempty(parentFig) && isvalid(parentFig); close(parentFig); end
                    return;
                end
            end
            try
                obj.Model = TemplateRegistry.instantiate(meta.id, params);
                obj.afterModelEdit(sprintf(Labels.get('composer_toast_template_loaded'), meta.name));
                obj.App.logEvent('COMPOSE', sprintf('Load template: %s', meta.id));
            catch ME
                obj.flashStatus(ME.message, 'danger');
            end
            if ~isempty(parentFig) && isvalid(parentFig); close(parentFig); end
        end

        function params = openParamDialog(~, meta, defaults)
            ret = struct('done', false, 'params', defaults);

            % Pre-compute the number of input fields so the dialog can be
            % sized tightly (avoids the empty-whitespace look the original
            % had — fixed 10 rows × 30 px regardless of template).
            switch meta.id
                case {'ghz','qft','iqft','wstate','vqe','superdense'}; nFields = 1;
                case {'grover','bv','dj','qaoa','trotter','hea'};      nFields = 2;
                otherwise; nFields = 2;
            end

            % Geometry — keep tight so the dialog hugs its content.
            headerH = 56;   rowH = 34;   rowGap = 8;
            panelPadV = 14;
            panelH = panelPadV*2 + nFields*rowH + (nFields-1)*rowGap;
            footerH = 36;
            outerPadV = 18;  outerGap = 14;
            dialogW = 520;
            dialogH = outerPadV*2 + headerH + outerGap + panelH + ...
                      outerGap + 1 + outerGap + footerH;
            % Centre on the primary screen.
            try
                screen = get(0, 'ScreenSize');
                xPos = max(80, round((screen(3) - dialogW) / 2));
                yPos = max(80, round((screen(4) - dialogH) / 2));
            catch
                xPos = 320; yPos = 240;
            end

            fig = uifigure('Name', Labels.get('composer_param_title'), ...
                'Position', [xPos yPos dialogW dialogH], ...
                'WindowStyle', 'modal', 'Color', Theme.COLOR_BG, ...
                'Resize', 'off');
            try; Theme.applyFigureMode(fig, Theme.activeName()); catch; end

            outer = uigridlayout(fig, [4 1]);
            outer.RowHeight = {headerH, panelH, 1, footerH};
            outer.Padding = [20 outerPadV 20 outerPadV];
            outer.RowSpacing = outerGap;
            outer.BackgroundColor = Theme.COLOR_BG;

            % ── Header: template name + subtitle ─────────────────────────
            header = uigridlayout(outer, [2 1]);
            header.Layout.Row = 1; header.Layout.Column = 1;
            header.RowHeight = {24, 28};
            header.RowSpacing = 2; header.Padding = [0 0 0 0];
            header.BackgroundColor = Theme.COLOR_BG;
            titleLbl = uilabel(header, 'Text', char(meta.name), ...
                'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', Theme.COLOR_HEADING);
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;
            subLbl = uilabel(header, 'Text', Labels.get('composer_param_subtitle', ...
                'Configure values before inserting this template into the circuit.'), ...
                'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            % ── Field panel (card) ───────────────────────────────────────
            fieldPanel = uipanel(outer, 'BorderType', 'line', ...
                'BorderColor', Theme.COLOR_DIVIDER, ...
                'BackgroundColor', Theme.COLOR_CARD);
            fieldPanel.Layout.Row = 2; fieldPanel.Layout.Column = 1;

            g = uigridlayout(fieldPanel, [nFields 2]);
            g.RowHeight = repmat({rowH}, 1, nFields);
            g.ColumnWidth = {220, '1x'};
            g.Padding = [18 panelPadV 18 panelPadV];
            g.RowSpacing = rowGap;
            g.ColumnSpacing = 12;
            g.BackgroundColor = Theme.COLOR_CARD;

            row = 0;
            handles = struct();
            switch meta.id
                case 'ghz'
                    [row, handles.n] = numField(g, row, Labels.get('composer_param_n_qubits'), defaults.n);
                case 'wstate'
                    [row, handles.n] = numField(g, row, Labels.get('composer_param_n_qubits'), defaults.n);
                case 'qft'
                    [row, handles.n] = numField(g, row, Labels.get('composer_param_n_qubits'), defaults.n);
                case 'iqft'
                    [row, handles.n] = numField(g, row, Labels.get('composer_param_n_qubits'), defaults.n);
                case 'hea'
                    [row, handles.n]      = numField(g, row, Labels.get('composer_param_n_qubits'), defaults.n);
                    [row, handles.layers] = numField(g, row, Labels.get('composer_param_layers'), defaults.layers);
                case 'grover'
                    [row, handles.k]      = numField(g, row, Labels.get('composer_param_k'), defaults.k);
                    [row, handles.marked] = strField(g, row, Labels.get('composer_param_marked'), defaults.marked);
                case 'bv'
                    [row, handles.n]      = numField(g, row, Labels.get('composer_param_n_qubits'), defaults.n);
                    [row, handles.hidden] = strField(g, row, Labels.get('composer_param_hidden'), defaults.hidden);
                case 'dj'
                    [row, handles.n]        = numField(g, row, Labels.get('composer_param_n_qubits'), defaults.n);
                    [row, handles.balanced] = numField(g, row, Labels.get('composer_param_balanced'), defaults.balanced);
                case 'vqe'
                    [row, handles.theta] = numField(g, row, Labels.get('composer_param_theta'), defaults.theta);
                case 'qaoa'
                    [row, handles.gamma] = numField(g, row, Labels.get('composer_param_gamma'), defaults.gamma);
                    [row, handles.beta]  = numField(g, row, Labels.get('composer_param_beta'),  defaults.beta);
                case 'trotter'
                    [row, handles.dt]    = numField(g, row, Labels.get('composer_param_dt'), defaults.dt);
                    [row, handles.steps] = numField(g, row, Labels.get('composer_param_steps'), defaults.steps);
                case 'superdense'
                    [row, handles.message] = strField(g, row, Labels.get('composer_param_message'), defaults.message);
            end

            % ── Hairline divider above the footer ────────────────────────
            divider = uipanel(outer, 'BorderType', 'none', ...
                'BackgroundColor', Theme.COLOR_DIVIDER);
            divider.Layout.Row = 3; divider.Layout.Column = 1;

            % ── Footer: spacer · Cancel · Apply Template ─────────────────
            footer = uigridlayout(outer, [1 3]);
            footer.Layout.Row = 4; footer.Layout.Column = 1;
            footer.ColumnWidth = {'1x', 100, 150};
            footer.RowHeight = {footerH};
            footer.Padding = [0 0 0 0]; footer.ColumnSpacing = 8;
            footer.BackgroundColor = Theme.COLOR_BG;
            spacer = uilabel(footer, 'Text', ''); spacer.Layout.Column = 1; %#ok<NASGU>
            cancelBtn = uibutton(footer, 'Text', Labels.get('composer_param_cancel'), ...
                'ButtonPushedFcn', @(~,~) cancelAndClose());
            cancelBtn.Layout.Column = 2;
            StyleHelper.styleBtn(cancelBtn, 'ghost');
            applyBtn = uibutton(footer, 'Text', Labels.get('composer_param_apply'), ...
                'ButtonPushedFcn', @(~,~) accept());
            applyBtn.Layout.Column = 3;
            StyleHelper.styleBtn(applyBtn, 'primary');

            % Treat window-close as Cancel so callers still get [] back.
            fig.CloseRequestFcn = @(~,~) cancel();

            uiwait(fig);
            if ret.done
                params = ret.params;
            else
                params = [];
            end

            function accept()
                p = struct();
                fns = fieldnames(handles);
                for i = 1:numel(fns)
                    h = handles.(fns{i});
                    if isa(h, 'matlab.ui.control.NumericEditField')
                        p.(fns{i}) = h.Value;
                    elseif isa(h, 'matlab.ui.control.EditField')
                        p.(fns{i}) = char(h.Value);
                    end
                end
                ret.params = mergeStructs(defaults, p);
                ret.done = true;
                if isvalid(fig); delete(fig); end
            end

            function cancel()
                ret.done = false;
                if isvalid(fig); delete(fig); end
            end
        end

        % ── Reproducibility Bundle dialog ────────────────────────────────
        function openBundleDialog(obj)
            ctx = obj.collectBundleContext();
            haveBackend = ~isempty(ctx.backend);
            haveMitig   = ~isempty(ctx.mitigationEstimates);
            haveFt      = ~isempty(ctx.ftResult);

            fig = uifigure('Name', Labels.get('bundle_dlg_title'), ...
                'Position', [240 220 560 460], 'Color', Theme.COLOR_BG);
            try; Theme.applyFigureMode(fig, Theme.activeName()); catch; end

            outer = uigridlayout(fig, [4 1]);
            outer.RowHeight = {44, '1x', 1, 'fit'};
            outer.Padding = [16 16 16 16]; outer.RowSpacing = 12;
            outer.BackgroundColor = Theme.COLOR_BG;

            % Name row.
            nameRow = uigridlayout(outer, [1 2]);
            nameRow.Layout.Row = 1; nameRow.Layout.Column = 1;
            nameRow.ColumnWidth = {120, '1x'};
            nameRow.Padding = [0 0 0 0]; nameRow.ColumnSpacing = 8;
            nameRow.BackgroundColor = Theme.COLOR_BG;
            uilabel(nameRow, 'Text', Labels.get('bundle_dlg_name_lbl'), ...
                'FontSize', 12, 'FontColor', Theme.COLOR_LABEL);
            nameField = uieditfield(nameRow, 'text', ...
                'Value', BundleService.defaultName(ctx));

            % Checkbox stack.
            chkPanel = uipanel(outer, 'Title', Labels.get('bundle_dlg_include_lbl'), ...
                'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
                'BackgroundColor', Theme.COLOR_CARD, ...
                'ForegroundColor', Theme.COLOR_HEADING, 'FontWeight', 'bold');
            chkPanel.Layout.Row = 2; chkPanel.Layout.Column = 1;
            cg = uigridlayout(chkPanel, [5 1]);
            cg.RowHeight = repmat({'fit'}, 1, 5);
            cg.Padding = [16 12 16 12]; cg.RowSpacing = 6;
            cg.BackgroundColor = Theme.COLOR_CARD;

            chkCircuit = uicheckbox(cg, 'Text', Labels.get('bundle_dlg_chk_circuit'), 'Value', true);
            chkMeta    = uicheckbox(cg, 'Text', Labels.get('bundle_dlg_chk_meta'),    'Value', true);
            chkBackend = uicheckbox(cg, 'Text', addUnavailHint(Labels.get('bundle_dlg_chk_backend'), haveBackend, Labels.get('bundle_dlg_unavail_backend')), 'Value', haveBackend, 'Enable', haveBackend);
            chkMitig   = uicheckbox(cg, 'Text', addUnavailHint(Labels.get('bundle_dlg_chk_mitig'),   haveMitig,   Labels.get('bundle_dlg_unavail_mitig')),   'Value', haveMitig,   'Enable', haveMitig);
            chkFt      = uicheckbox(cg, 'Text', addUnavailHint(Labels.get('bundle_dlg_chk_ft'),      haveFt,      Labels.get('bundle_dlg_unavail_ft')),      'Value', haveFt,      'Enable', haveFt);
            chkMeta.Tooltip = 'README + manifest.json with SHA-256 checksums always included.';

            % Hairline divider — matches Templates / Export footers.
            divider = uipanel(outer, 'BorderType', 'none', ...
                'BackgroundColor', Theme.COLOR_DIVIDER);
            divider.Layout.Row = 3; divider.Layout.Column = 1;

            % Footer.
            footer = uigridlayout(outer, [1 3]);
            footer.Layout.Row = 4; footer.Layout.Column = 1;
            footer.ColumnWidth = {'1x', 100, 140};
            footer.RowHeight = {36};
            footer.Padding = [0 0 0 0]; footer.ColumnSpacing = 8;
            footer.BackgroundColor = Theme.COLOR_BG;
            spacer = uilabel(footer, 'Text', ''); spacer.Layout.Column = 1; %#ok<NASGU>
            cancelBtn = uibutton(footer, 'Text', Labels.get('bundle_dlg_btn_cancel'), ...
                'ButtonPushedFcn', @(~,~) close(fig));
            cancelBtn.Layout.Column = 2;
            StyleHelper.styleBtn(cancelBtn, 'ghost');
            saveBtn = uibutton(footer, 'Text', Labels.get('bundle_dlg_btn_save'), ...
                'ButtonPushedFcn', @(~,~) doSave());
            saveBtn.Layout.Column = 3;
            StyleHelper.styleBtn(saveBtn, 'primary');

            function doSave()
                opts = struct( ...
                    'includeCircuit',    logical(chkCircuit.Value), ...
                    'includeBackend',    logical(chkBackend.Value), ...
                    'includeMitigation', logical(chkMitig.Value), ...
                    'includeFt',         logical(chkFt.Value)); %#ok<STRNU>
                proposed = strtrim(nameField.Value);
                if isempty(proposed); proposed = BundleService.defaultName(ctx); end
                [file, path] = uiputfile('*.zip', Labels.get('bundle_dlg_title'), proposed);
                if isequal(file, 0); return; end
                opts.savePath = fullfile(path, file);
                close(fig);
                try
                    saved = BundleService.assemble(ctx, opts);
                    obj.flashStatus(sprintf(Labels.get('bundle_status_saved_fmt'), saved), 'success');
                    obj.App.logEvent('COMPOSE', sprintf('Bundle exported → %s', file));
                catch ME
                    obj.flashStatus(sprintf(Labels.get('bundle_status_err_fmt'), ME.message), 'danger');
                end
            end

            function s = addUnavailHint(base, available, hint)
                if available
                    s = base;
                else
                    s = sprintf('%s   [%s]', base, hint);
                end
            end
        end

        function ctx = collectBundleContext(obj)
            % Aggregate cross-screen state into a single ctx struct.
            ctx = struct( ...
                'circuit',             obj.Model, ...
                'circuitName',         'untitled', ...
                'backend',             [], ...
                'mitigationEstimates', [], ...
                'ftResult',            [], ...
                'ftParams',            []);
            try
                ctx.circuitName = char(string(obj.App.State.currentProjectName));
            catch
            end
            % Pull cached backend telemetry if a row is selected on Backends.
            try
                bvm = obj.App.BackendsVm;
                if ~isempty(bvm) && ~isempty(obj.App.BackendTable) && isvalid(obj.App.BackendTable)
                    sel = obj.App.BackendTable.Selection;
                    if ~isempty(sel)
                        row = sel(1);
                        bname = char(string(obj.App.BackendTable.Data{row, 2}));
                        safeKey = matlab.lang.makeValidName(bname);
                        cal = struct();
                        if isstruct(obj.App.CalibrationHistoryCache) && ...
                                isfield(obj.App.CalibrationHistoryCache, safeKey)
                            cal = obj.App.CalibrationHistoryCache.(safeKey);
                        end
                        ctx.backend = struct('name', bname, 'calibration', cal);
                    end
                end
            catch
            end
            % Pull mitigation estimates if the user ran a compare recently.
            try
                mvm = obj.App.MitigationCompareVm;
                if ~isempty(mvm) && ~isempty(mvm.Estimates) && mvm.Estimates.Count > 0
                    ctx.mitigationEstimates = mvm.Estimates;
                end
            catch
            end
            % Pull FT estimate if the user ran the Resource Estimator recently.
            try
                rvm = obj.App.ResourceEstimatorVm;
                if ~isempty(rvm) && ~isempty(rvm.LastResult)
                    ctx.ftResult = rvm.LastResult;
                end
            catch
            end
        end

        % ── Export dialog (multi-target code emission) ───────────────────
        function openExportDialog(obj)
            formats = {
                'qasm2',  Labels.get('composer_export_fmt_qasm2'),  'qasm';
                'qasm3',  Labels.get('composer_export_fmt_qasm3'),  'qasm';
                'qiskit', Labels.get('composer_export_fmt_qiskit'), 'py';
                'cirq',   Labels.get('composer_export_fmt_cirq'),   'py';
                'braket', Labels.get('composer_export_fmt_braket'), 'py';
                'matlab', Labels.get('composer_export_fmt_matlab'), 'm';
            };
            % WindowStyle='normal' so uiputfile inside Save doesn't deadlock.
            fig = uifigure('Name', Labels.get('composer_export_title'), ...
                'Position', [240 200 760 540], 'Color', Theme.COLOR_BG);
            try; Theme.applyFigureMode(fig, Theme.activeName()); catch; end

            outer = uigridlayout(fig, [4 1]);
            outer.RowHeight = {32, '1x', 1, 'fit'};
            outer.Padding = [16 16 16 16]; outer.RowSpacing = 10;
            outer.BackgroundColor = Theme.COLOR_BG;

            top = uigridlayout(outer, [1 4]);
            top.Layout.Row = 1; top.Layout.Column = 1;
            top.ColumnWidth = {'fit', 200, '1x', 'fit'};
            top.Padding = [0 0 0 0]; top.ColumnSpacing = 8;
            top.BackgroundColor = Theme.COLOR_BG;

            uilabel(top, 'Text', Labels.get('composer_export_format_lbl'), ...
                'FontSize', 12, 'FontColor', Theme.COLOR_LABEL);
            fmtDD = uidropdown(top, ...
                'Items', formats(:, 2)', 'ItemsData', formats(:, 1)', ...
                'Value', 'qiskit');
            uilabel(top, 'Text', '');  % spacer
            statusLbl = uilabel(top, 'Text', Labels.get('composer_export_status_idle'), ...
                'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
                'HorizontalAlignment', 'right', 'WordWrap', 'on');

            previewTa = uitextarea(outer, 'Editable', 'on', 'WordWrap', 'off');
            previewTa.Layout.Row = 2;
            previewTa.FontName = 'Menlo'; previewTa.FontSize = 11;
            previewTa.BackgroundColor = Theme.COLOR_ACCENT_BG;
            previewTa.FontColor       = Theme.COLOR_LABEL;

            % Hairline divider — matches the Templates dialog footer.
            divider = uipanel(outer, 'BorderType', 'none', ...
                'BackgroundColor', Theme.COLOR_DIVIDER);
            divider.Layout.Row = 3; divider.Layout.Column = 1;

            footer = uigridlayout(outer, [1 4]);
            footer.Layout.Row = 4; footer.Layout.Column = 1;
            footer.ColumnWidth = {120, 120, '1x', 100};
            footer.RowHeight = {36};
            footer.Padding = [0 0 0 0]; footer.ColumnSpacing = 8;
            footer.BackgroundColor = Theme.COLOR_BG;

            btnCopy = uibutton(footer, 'Text', Labels.get('composer_export_btn_copy'), ...
                'ButtonPushedFcn', @(~,~) doCopy());
            StyleHelper.styleBtn(btnCopy, 'primary');

            btnSave = uibutton(footer, 'Text', Labels.get('composer_export_btn_save'), ...
                'ButtonPushedFcn', @(~,~) doSave());
            StyleHelper.styleBtn(btnSave, 'secondary');

            spacer = uilabel(footer, 'Text', ''); spacer.Layout.Column = 3; %#ok<NASGU>

            btnClose = uibutton(footer, 'Text', Labels.get('composer_export_btn_close'), ...
                'ButtonPushedFcn', @(~,~) close(fig));
            btnClose.Layout.Column = 4;
            StyleHelper.styleBtn(btnClose, 'ghost');

            % Initial render + format-change wiring.
            fmtDD.ValueChangedFcn = @(~,~) refreshPreview();
            refreshPreview();

            function refreshPreview()
                fmtId = fmtDD.Value;
                txt = obj.emitForFormat(fmtId);
                previewTa.Value = strsplit(txt, sprintf('\n'));
            end

            function doCopy()
                txt = strjoin(previewTa.Value, sprintf('\n'));
                try
                    clipboard('copy', txt);
                    statusLbl.Text = sprintf( ...
                        Labels.get('composer_export_status_copied'), strlength(txt));
                    statusLbl.FontColor = Theme.COLOR_SUCCESS;
                catch
                    statusLbl.Text = Labels.get('composer_export_status_copy_err');
                    statusLbl.FontColor = Theme.COLOR_DANGER;
                end
            end

            function doSave()
                fmtId = fmtDD.Value;
                idx = find(strcmp(formats(:, 1), fmtId), 1);
                ext = '*.txt';
                if ~isempty(idx); ext = ['*.' formats{idx, 3}]; end
                stamp = datestr(now, 'yyyymmdd-HHMMSS'); %#ok<DATST,TNOW1>
                defaultName = sprintf('composer_export_%s.%s', stamp, formats{idx, 3});
                [file, path] = uiputfile(ext, 'Save export', defaultName);
                if isequal(file, 0)
                    statusLbl.Text = sprintf( ...
                        Labels.get('composer_export_status_save_err'), 'cancelled');
                    statusLbl.FontColor = Theme.COLOR_MUTED;
                    return;
                end
                full = fullfile(path, file);
                txt = strjoin(previewTa.Value, sprintf('\n'));
                try
                    fid = fopen(full, 'w', 'n', 'UTF-8');
                    if fid < 0; error('cannot open file for writing'); end
                    fwrite(fid, txt); fclose(fid);
                    statusLbl.Text = sprintf( ...
                        Labels.get('composer_export_status_saved_fmt'), strlength(txt), full);
                    statusLbl.FontColor = Theme.COLOR_SUCCESS;
                    obj.App.logEvent('COMPOSE', sprintf('Exported %s → %s', fmtId, file));
                catch ME
                    statusLbl.Text = sprintf( ...
                        Labels.get('composer_export_status_save_err'), ME.message);
                    statusLbl.FontColor = Theme.COLOR_DANGER;
                end
            end
        end

        function txt = emitForFormat(obj, fmtId)
            switch char(fmtId)
                case 'qasm2';  txt = obj.Model.toQasm();
                case 'qasm3';  txt = obj.Model.toQasm3();
                case 'qiskit'; txt = obj.Model.toQiskitPython();
                case 'cirq';   txt = obj.Model.toCirqPython();
                case 'braket'; txt = obj.Model.toBraketPython();
                case 'matlab'; txt = obj.Model.toMatlabScript();
                otherwise;     txt = obj.Model.toQasm();
            end
        end

        % ── Save dialog ──────────────────────────────────────────────────
        function openSaveDialog(obj)
            stamp = datestr(now, 'yyyymmdd-HHMMSS'); %#ok<DATST,TNOW1>
            defaultName = sprintf(Labels.get('composer_save_default_fmt'), stamp);

            fig = uifigure('Name', Labels.get('composer_save_title'), ...
                'Position', [300 250 420 200], 'WindowStyle', 'modal', ...
                'Color', Theme.COLOR_BG);
            try; Theme.applyFigureMode(fig, Theme.activeName()); catch; end

            g = uigridlayout(fig, [3 2]);
            g.RowHeight = {30, 30, 50};
            g.ColumnWidth = {120, '1x'};
            g.Padding = [16 16 16 16];
            g.RowSpacing = 10;

            uilabel(g, 'Text', Labels.get('composer_save_name'));
            ed = uieditfield(g, 'text', 'Value', defaultName);

            qLabel = uilabel(g, 'Text', sprintf('Qubits: %d · Gates: %d · Depth: %d', ...
                obj.Model.NumQubits, numel(obj.Model.Gates), obj.Model.depth())); %#ok<NASGU>
            blank = uilabel(g, 'Text', ''); %#ok<NASGU>

            barCol = uigridlayout(g, [1 3]);
            barCol.Layout.Row = 3; barCol.Layout.Column = [1 2];
            barCol.ColumnWidth = {'1x', 130, 130};
            barCol.Padding = [0 6 0 0];
            spacer = uilabel(barCol, 'Text', ''); spacer.Layout.Column = 1; %#ok<NASGU>
            cancelBtn = uibutton(barCol, 'Text', Labels.get('composer_save_btn_cancel'), ...
                'ButtonPushedFcn', @(~,~) close(fig));
            cancelBtn.Layout.Column = 2;
            StyleHelper.styleBtn(cancelBtn, 'ghost');
            saveBtn = uibutton(barCol, 'Text', Labels.get('composer_save_btn_save'), ...
                'ButtonPushedFcn', @(~,~) accept());
            saveBtn.Layout.Column = 3;
            StyleHelper.styleBtn(saveBtn, 'primary');

            function accept()
                name = strtrim(ed.Value);
                if isempty(name); name = defaultName; end
                close(fig);
                obj.doSave(name);
            end
        end

        function doSave(obj, name)
            qasm = obj.Model.toQasm();
            tmpFile = [tempname() '.qasm'];
            fid = fopen(tmpFile, 'w');
            if fid < 0
                obj.flashStatus(sprintf(Labels.get('composer_status_save_err_fmt'), ...
                    'cannot create temp file'), 'danger');
                return;
            end
            fwrite(fid, qasm); fclose(fid);

            obj.flashStatus(sprintf('Saving %s…', name), 'info');
            svc   = obj.App.Services.CircuitSvc;
            token = obj.App.State.authToken;
            n     = obj.Model.NumQubits;
            depth = obj.Model.depth();

            AsyncRunner.run( ...
                @() svc.uploadCircuit(tmpFile, name, 'openqasm2', 'Composer', n, depth, token), ...
                @(result) obj.onSaveDone(name, result, tmpFile), ...
                @(ME)     obj.onSaveError(ME, tmpFile));
        end

        function onSaveDone(obj, name, ~, tmpFile)
            try; if exist(tmpFile, 'file'); delete(tmpFile); end; catch; end
            % Circuit list just grew — invalidate shared cache so the
            % new circuit appears on Mitigation/RunPlanner/ResourceEst.
            try; obj.App.State.invalidateCircuitsListCache(); catch; end
            obj.flashStatus(sprintf(Labels.get('composer_status_save_ok_fmt'), name), 'success');
            obj.App.logEvent('COMPOSE', sprintf('Saved circuit "%s"', name));
            if ~isempty(obj.BtnOpenAnalysis) && isvalid(obj.BtnOpenAnalysis)
                obj.BtnOpenAnalysis.Enable = matlab.lang.OnOffSwitchState(true);
            end
        end

        function onSaveError(obj, ME, tmpFile)
            try; if exist(tmpFile, 'file'); delete(tmpFile); end; catch; end
            obj.flashStatus(sprintf(Labels.get('composer_status_save_err_fmt'), ME.message), 'danger');
            obj.App.logEvent('COMPOSE', sprintf('Save failed: %s', ME.message));
        end

        % ── Theta prompt for rotation gates ──────────────────────────────
        function theta = promptTheta(~, kind, q)
            res = struct('val', pi/4, 'done', false);
            fig = uifigure('Name', sprintf(Labels.get('composer_param_gate_theta'), upper(kind), q), ...
                'Position', [300 250 360 160], 'WindowStyle', 'modal', ...
                'Color', Theme.COLOR_BG);
            try; Theme.applyFigureMode(fig, Theme.activeName()); catch; end
            g = uigridlayout(fig, [2 2]);
            g.RowHeight = {30, 50};
            g.ColumnWidth = {120, '1x'};
            g.Padding = [16 16 16 16];
            g.RowSpacing = 10;

            uilabel(g, 'Text', Labels.get('composer_param_theta'));
            ed = uieditfield(g, 'numeric', 'Value', pi/4);

            barCol = uigridlayout(g, [1 2]);
            barCol.Layout.Row = 2; barCol.Layout.Column = [1 2];
            barCol.ColumnWidth = {'1x', 120};
            barCol.Padding = [0 6 0 0];
            spacer = uilabel(barCol, 'Text', ''); %#ok<NASGU>
            applyBtn = uibutton(barCol, 'Text', Labels.get('composer_param_apply'), ...
                'ButtonPushedFcn', @(~,~) finalize());
            StyleHelper.styleBtn(applyBtn, 'primary');
            uiwait(fig);
            if res.done; theta = res.val; else; theta = []; end

            function finalize()
                res.val = ed.Value;
                res.done = true;
                if isvalid(fig); close(fig); end
            end
        end

        % ── Mirror / Inspect collapse ────────────────────────────────────
        function applyMirrorCollapse(obj)
            if isempty(obj.RootGrid) || ~isvalid(obj.RootGrid); return; end
            if obj.MirrorCollapsed
                obj.RootGrid.RowHeight{4} = 32;
                if ~isempty(obj.MirrorTextarea); obj.MirrorTextarea.Visible = 'off'; end
                if ~isempty(obj.MirrorToggleBtn); obj.MirrorToggleBtn.Text = char(8963); end
            else
                obj.RootGrid.RowHeight{4} = 160;
                if ~isempty(obj.MirrorTextarea); obj.MirrorTextarea.Visible = 'on'; end
                if ~isempty(obj.MirrorToggleBtn); obj.MirrorToggleBtn.Text = char(8964); end
            end
        end

        function applyInspectCollapse(obj)
            if isempty(obj.RootGrid) || ~isvalid(obj.RootGrid); return; end
            if obj.InspectExpanded
                obj.RootGrid.RowHeight{5} = 360;
                if ~isempty(obj.InspectToggleBtn); obj.InspectToggleBtn.Text = char(8963); end
            else
                obj.RootGrid.RowHeight{5} = 36;
                if ~isempty(obj.InspectToggleBtn); obj.InspectToggleBtn.Text = char(8964); end
            end
            content = obj.InspectContent;
            if ~isempty(content) && isvalid(content)
                content.Visible = matlab.lang.OnOffSwitchState(obj.InspectExpanded);
            end
        end

        % ── Inspect engine ───────────────────────────────────────────────
        function invalidateInspect(obj)
            obj.InspectSteps = [];
            obj.InspectStepIdx = 1;
            obj.stopPlayTimer();
            if obj.InspectExpanded
                obj.refreshInspect();
            end
        end

        function refreshInspect(obj)
            if isempty(obj.InspectContent) || ~isvalid(obj.InspectContent); return; end
            n = obj.Model.NumQubits;
            if obj.Model.isEmpty()
                obj.showInspectMessage(Labels.get('composer_inspect_no_circuit'));
                return;
            end
            if ~StatevectorSimulator.canSimulate(obj.Model)
                obj.showInspectMessage(sprintf(Labels.get('composer_status_inspect_off'), n));
                return;
            end
            try
                obj.InspectSteps = StatevectorSimulator.simulate(obj.Model);
            catch ME
                obj.showInspectMessage(sprintf('Simulator error: %s', ME.message));
                return;
            end
            stepCount = numel(obj.InspectSteps);
            obj.InspectStepIdx = stepCount;
            obj.InspectSlider.Limits = [0, max(1, stepCount-1)];
            obj.InspectSlider.Value = stepCount - 1;
            obj.InspectSlider.Enable = matlab.lang.OnOffSwitchState(stepCount > 1);
            obj.paintInspectStep();
        end

        function showInspectMessage(obj, msg)
            content = obj.InspectContent;
            delete(content.Children);
            g = uigridlayout(content, [1 1]);
            g.Padding = [16 16 16 16];
            g.BackgroundColor = Theme.COLOR_CARD;
            uilabel(g, 'Text', msg, ...
                'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
                'HorizontalAlignment', 'center', 'WordWrap', 'on');
            obj.InspectStepLbl.Text = '';
            obj.InspectCaptionLbl.Text = '';
        end

        function paintInspectStep(obj)
            if isempty(obj.InspectSteps) || isempty(obj.InspectContent) || ...
               ~isvalid(obj.InspectContent)
                return;
            end
            stepCount = numel(obj.InspectSteps);
            idx = max(1, min(stepCount, obj.InspectStepIdx));
            step = obj.InspectSteps(idx);

            obj.InspectStepLbl.Text = sprintf('%d / %d', idx-1, stepCount-1);
            if idx == 1
                obj.InspectCaptionLbl.Text = Labels.get('composer_inspect_at_init');
            else
                obj.InspectCaptionLbl.Text = sprintf( ...
                    Labels.get('composer_inspect_after_fmt'), idx-1, stepCount-1, step.label);
            end

            content = obj.InspectContent;
            delete(content.Children);
            switch obj.InspectTab
                case 'amps'
                    obj.paintAmps(content, step);
                otherwise
                    obj.paintBloch(content, step, obj.Model.NumQubits);
            end
        end

        function paintBloch(~, content, step, n)
            cols = min(n, 8);
            rows = ceil(n / cols);
            g = uigridlayout(content, [rows cols]);
            g.RowSpacing = 8; g.ColumnSpacing = 8;
            g.Padding = [10 10 10 10];
            g.BackgroundColor = Theme.COLOR_CARD;
            for q = 0:n-1
                r = floor(q / cols) + 1;
                c = mod(q, cols) + 1;
                tile = uipanel(g, 'Title', sprintf(Labels.get('composer_inspect_bloch_lbl'), q), ...
                    'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER, ...
                    'BackgroundColor', Theme.COLOR_CARD, ...
                    'ForegroundColor', Theme.COLOR_LABEL, 'FontWeight', 'bold');
                tile.Layout.Row = r; tile.Layout.Column = c;
                tg = uigridlayout(tile, [1 1]);
                tg.Padding = [4 4 4 4];
                tg.BackgroundColor = Theme.COLOR_CARD;
                ax = uiaxes(tg);
                ax.Toolbar.Visible = 'off';
                ax.Color = Theme.COLOR_CARD;
                ax.XColor = Theme.COLOR_MUTED; ax.YColor = Theme.COLOR_MUTED;
                ax.XLim = [-1.1 1.1]; ax.YLim = [0.5 3.5];
                ax.YTick = 1:3; ax.YTickLabel = {'Z','Y','X'};
                ax.XTick = [-1 0 1];
                ax.FontSize = 9;
                hold(ax, 'on');
                v = step.blochPerQubit(q+1, :);
                colors = {Theme.COLOR_DANGER, Theme.COLOR_WARNING, Theme.COLOR_PRIMARY};
                for k = 1:3
                    yPos = 4 - k;
                    barh(ax, yPos, v(k), 'BarWidth', 0.6, 'FaceColor', colors{k}, ...
                        'EdgeColor', 'none');
                end
                line(ax, [0 0], [0.5 3.5], 'Color', Theme.COLOR_DIVIDER, 'LineWidth', 0.8);
                hold(ax, 'off');
            end
        end

        function paintAmps(~, content, step)
            g = uigridlayout(content, [1 1]);
            g.Padding = [10 10 10 10];
            g.BackgroundColor = Theme.COLOR_CARD;
            ax = uiaxes(g);
            ax.Toolbar.Visible = 'off';
            ax.Color = Theme.COLOR_CARD;
            ax.XColor = Theme.COLOR_MUTED; ax.YColor = Theme.COLOR_MUTED;
            ax.FontSize = 10;
            top = step.topAmps;
            if isempty(top); return; end
            n = ceil(log2(numel(step.psi)));
            probs = arrayfun(@(s) s.prob, top);
            labels = arrayfun(@(s) sprintf('|%s⟩', dec2bin(s.state, n)), ...
                top, 'UniformOutput', false);
            barh(ax, probs, 'FaceColor', Theme.COLOR_PRIMARY, 'EdgeColor', 'none');
            ax.YTick = 1:numel(probs);
            ax.YTickLabel = labels;
            ax.YDir = 'reverse';
            ax.XLim = [0, max(1.0, max(probs)*1.1)];
            xlabel(ax, '|amplitude|^2');
        end

        function startPlayTimer(obj)
            obj.stopPlayTimer();
            obj.PlayTimer = timer( ...
                'ExecutionMode', 'fixedRate', 'Period', 0.6, 'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) obj.onPlayTick());
            start(obj.PlayTimer);
        end

        function stopPlayTimer(obj)
            try
                if ~isempty(obj.PlayTimer) && isvalid(obj.PlayTimer)
                    stop(obj.PlayTimer); delete(obj.PlayTimer);
                end
            catch
            end
            obj.PlayTimer = [];
            if ~isempty(obj.InspectPlayBtn) && isvalid(obj.InspectPlayBtn)
                obj.InspectPlayBtn.Text = Labels.get('composer_inspect_play');
            end
        end

        function onPlayTick(obj)
            if isempty(obj.InspectSteps) || ~obj.InspectExpanded
                obj.stopPlayTimer(); return;
            end
            if obj.InspectStepIdx >= numel(obj.InspectSteps)
                obj.stopPlayTimer(); return;
            end
            obj.InspectStepIdx = obj.InspectStepIdx + 1;
            obj.InspectSlider.Value = obj.InspectStepIdx - 1;
            obj.paintInspectStep();
        end
    end

    methods (Static, Access = private)
        function s = gateStyle()
            % gateStyle  Single source of truth for the Composer's gate
            %   colour palette. Matches the SVG circuit renderer
            %   (CircuitDiagram.drawSvgDiagram + Circuit Preview) so
            %   the Composer canvas, the QTAUBench Similarity Circuit
            %   Diagram, and the Circuit Preview all read as the same
            %   visual language — a unified blue treatment rather than
            %   the previous theme-driven purple on the Composer side.
            %
            %   Hex values mirror the Tailwind blue ramp used by the
            %   SVG renderer:
            %     Fill        = #1D4ED8  (blue-700, single-qubit + measure box)
            %     TargetFill  = #2563EB  (blue-600, CNOT / CCX target circle)
            %     Border      = #3B82F6  (blue-500, gate border + connector + control dot)
            %     Text        = #FFFFFF  (white, gate label + target cross)
            s = struct( ...
                'Fill',       [29/255 78/255 216/255],   ... % #1D4ED8
                'TargetFill', [37/255 99/255 235/255],   ... % #2563EB
                'Border',     [59/255 130/255 246/255],  ... % #3B82F6
                'Text',       [1 1 1]);                       % #FFFFFF
        end
    end
end

% ── File-private helpers ─────────────────────────────────────────────────
function [row, h] = numField(g, row, label, defaultVal)
    row = row + 1;
    lbl = uilabel(g, 'Text', char(label)); lbl.Layout.Row = row; lbl.Layout.Column = 1;
    h = uieditfield(g, 'numeric', 'Value', double(defaultVal));
    h.Layout.Row = row; h.Layout.Column = 2;
end

function [row, h] = strField(g, row, label, defaultVal)
    row = row + 1;
    lbl = uilabel(g, 'Text', char(label)); lbl.Layout.Row = row; lbl.Layout.Column = 1;
    h = uieditfield(g, 'text', 'Value', char(defaultVal));
    h.Layout.Row = row; h.Layout.Column = 2;
end

function out = mergeStructs(a, b)
    out = a;
    fns = fieldnames(b);
    for i = 1:numel(fns); out.(fns{i}) = b.(fns{i}); end
end

function v = ternary(cond, a, b)
    if cond; v = a; else; v = b; end
end
