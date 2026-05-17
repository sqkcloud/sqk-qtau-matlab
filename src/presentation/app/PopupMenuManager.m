classdef PopupMenuManager
    % PopupMenuManager  Builds and manages context-menu popup panels for
    %                    the Projects and Circuits tables.
    %
    %   Extracted from QTAUWorkbenchApp to reduce class size.
    %   All methods are static — call as PopupMenuManager.showProjectPopup(app, x, y).

    methods (Static)

        % ── Projects popup ───────────────────────────────────────────────

        function buildProjectPopup(app)
            popW = 160; popH = 72;
            app.ProjectsPopupPanel = uipanel(app.UIFigure, ...
                'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', Theme.COLOR_CARD, ...
                'BorderColor', Theme.COLOR_DIVIDER, ...
                'Position', [0 0 popW popH], ...
                'Visible', 'off');

            pg = uigridlayout(app.ProjectsPopupPanel, [2 1]);
            pg.RowHeight   = {'1x', '1x'};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [4 4 4 4];
            pg.RowSpacing  = 2;
            pg.BackgroundColor = Theme.COLOR_CARD;

            app.ProjectsPopupEditBtn = uibutton(pg, 'Text', ...
                [' ' char(9999) '  ' Labels.get('project_ctx_edit', 'Edit')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onEditProject());
            app.ProjectsPopupEditBtn.Layout.Row = 1;
            app.ProjectsPopupEditBtn.BackgroundColor = Theme.COLOR_CARD;
            app.ProjectsPopupEditBtn.FontColor = Theme.BTN_FG_DEFAULT;

            app.ProjectsPopupDeleteBtn = uibutton(pg, 'Text', ...
                [' ' char(10005) '  ' Labels.get('project_ctx_delete', 'Delete')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onDeleteProject());
            app.ProjectsPopupDeleteBtn.Layout.Row = 2;
            app.ProjectsPopupDeleteBtn.BackgroundColor = Theme.COLOR_CARD;
            app.ProjectsPopupDeleteBtn.FontColor = Theme.BTN_FG_DEFAULT;
        end

        function showProjectPopup(app, x, y)
            if isempty(app.ProjectsPopupPanel) || ~isvalid(app.ProjectsPopupPanel)
                PopupMenuManager.buildProjectPopup(app);
            end
            popW = 160; popH = 72;
            figPos = app.UIFigure.Position;
            px = min(x, figPos(3) - popW - 4);
            py = max(y - popH, 4);
            app.ProjectsPopupPanel.Position = [px py popW popH];
            app.ProjectsPopupPanel.Visible = 'on';
        end

        function hideProjectPopup(app)
            if ~isempty(app.ProjectsPopupPanel) && isvalid(app.ProjectsPopupPanel)
                app.ProjectsPopupPanel.Visible = 'off';
            end
        end

        % ── Circuits popup ───────────────────────────────────────────────

        function buildCircuitsPopup(app)
            popW = 160; popH = 108;
            app.CircuitsPopupPanel = uipanel(app.UIFigure, ...
                'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', Theme.COLOR_CARD, ...
                'BorderColor', Theme.COLOR_DIVIDER, ...
                'Position', [0 0 popW popH], ...
                'Visible', 'off');

            pg = uigridlayout(app.CircuitsPopupPanel, [3 1]);
            pg.RowHeight   = {'1x', '1x', '1x'};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [4 4 4 4];
            pg.RowSpacing  = 2;
            pg.BackgroundColor = Theme.COLOR_CARD;

            analyzeBtn = uibutton(pg, 'Text', ...
                [' ' char(8981) '  ' Labels.get('circuit_ctx_analyze', 'Analyze')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupAnalyze());
            analyzeBtn.Layout.Row = 1;
            analyzeBtn.BackgroundColor = Theme.COLOR_CARD;
            analyzeBtn.FontColor = Theme.BTN_FG_DEFAULT;

            app.CircuitsPopupEditBtn = uibutton(pg, 'Text', ...
                [' ' char(9999) '  ' Labels.get('circuit_ctx_edit', 'Edit')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupEdit());
            app.CircuitsPopupEditBtn.Layout.Row = 2;
            app.CircuitsPopupEditBtn.BackgroundColor = Theme.COLOR_CARD;
            app.CircuitsPopupEditBtn.FontColor = Theme.BTN_FG_DEFAULT;

            app.CircuitsPopupDeleteBtn = uibutton(pg, 'Text', ...
                [' ' char(10005) '  ' Labels.get('circuit_ctx_delete', 'Delete')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupDelete());
            app.CircuitsPopupDeleteBtn.Layout.Row = 3;
            app.CircuitsPopupDeleteBtn.BackgroundColor = Theme.COLOR_CARD;
            app.CircuitsPopupDeleteBtn.FontColor = Theme.BTN_FG_DEFAULT;
        end

        function showCircuitsPopup(app, x, y)
            if isempty(app.CircuitsPopupPanel) || ~isvalid(app.CircuitsPopupPanel)
                PopupMenuManager.buildCircuitsPopup(app);
            end
            popW = 160; popH = 108;
            figPos = app.UIFigure.Position;
            px = min(x, figPos(3) - popW - 4);
            py = max(y - popH, 4);
            app.CircuitsPopupPanel.Position = [px py popW popH];
            app.CircuitsPopupPanel.Visible = 'on';
        end

        function hideCircuitsPopup(app)
            if ~isempty(app.CircuitsPopupPanel) && isvalid(app.CircuitsPopupPanel)
                app.CircuitsPopupPanel.Visible = 'off';
            end
        end

        % ── Backends popup ────────────────────────────────────────────────

        function buildBackendsPopup(app)
            popW = 180; popH = 108;
            app.BackendsPopupPanel = uipanel(app.UIFigure, ...
                'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', Theme.COLOR_CARD, ...
                'BorderColor', Theme.COLOR_DIVIDER, ...
                'Position', [0 0 popW popH], ...
                'Visible', 'off');

            pg = uigridlayout(app.BackendsPopupPanel, [3 1]);
            pg.RowHeight   = {'1x', '1x', '1x'};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [4 4 4 4];
            pg.RowSpacing  = 2;
            pg.BackgroundColor = Theme.COLOR_CARD;

            % Set as Primary (char(9745) — same as Select button)
            b1 = uibutton(pg, 'Text', [' ' char(9745) '  Set as Primary'], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.BackendsVm.onCtxSetPrimary());
            b1.Layout.Row = 1;
            b1.BackgroundColor = Theme.COLOR_CARD; b1.FontColor = Theme.BTN_FG_DEFAULT;

            % Set as Backup (char(9744) — empty checkbox)
            b2 = uibutton(pg, 'Text', [' ' char(9744) '  Set as Backup'], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.BackendsVm.onCtxSetBackup());
            b2.Layout.Row = 2;
            b2.BackgroundColor = Theme.COLOR_CARD; b2.FontColor = Theme.BTN_FG_DEFAULT;

            % View Details (char(8505) — info)
            b3 = uibutton(pg, 'Text', [' ' char(8505) '  View Details'], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.BackendsVm.onCtxViewDetails());
            b3.Layout.Row = 3;
            b3.BackgroundColor = Theme.COLOR_CARD; b3.FontColor = Theme.BTN_FG_DEFAULT;
        end

        function showBackendsPopup(app, x, y)
            if isempty(app.BackendsPopupPanel) || ~isvalid(app.BackendsPopupPanel)
                PopupMenuManager.buildBackendsPopup(app);
            end
            popW = 180; popH = 108;
            figPos = app.UIFigure.Position;
            px = min(x, figPos(3) - popW - 4);
            py = max(y - popH, 4);
            app.BackendsPopupPanel.Position = [px py popW popH];
            app.BackendsPopupPanel.Visible = 'on';
        end

        function hideBackendsPopup(app)
            if ~isempty(app.BackendsPopupPanel) && isvalid(app.BackendsPopupPanel)
                app.BackendsPopupPanel.Visible = 'off';
                % Move the hidden panel off-screen — same R2025b
                % uifigure workaround we already use for the
                % ActivityOverlay. Visible='off' alone is NOT
                % sufficient on some R2025b builds: the still-alive
                % uipanel can keep capturing pointer hit-tests over
                % its last Position rectangle, swallowing the next
                % right-click before it reaches WindowButtonDownFcn
                % — that's the "first right-click works, second one
                % doesn't" symptom. showBackendsPopup re-assigns
                % Position = [px py popW popH] on the next open, so
                % this is self-restoring.
                try
                    app.BackendsPopupPanel.Position = [-99999 -99999 1 1];
                catch
                end
            end
        end

        % ── Reports popup ────────────────────────────────────────────────
        %   Mirrors the Backends/Circuits convention: a uipanel of left-
        %   aligned uibutton rows shown on right-click of a row in the
        %   Reports library uitable. Rows replace the dedicated
        %   Distribution row that used to live below the table.

        function buildReportsPopup(app)
            popW = 180; popH = 144;
            app.ReportsPopupPanel = uipanel(app.UIFigure, ...
                'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', Theme.COLOR_CARD, ...
                'BorderColor', Theme.COLOR_DIVIDER, ...
                'Position', [0 0 popW popH], ...
                'Visible', 'off');

            pg = uigridlayout(app.ReportsPopupPanel, [4 1]);
            pg.RowHeight   = {'1x', '1x', '1x', '1x'};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [4 4 4 4];
            pg.RowSpacing  = 2;
            pg.BackgroundColor = Theme.COLOR_CARD;

            % Open (char(9654) — ▶)
            b1 = uibutton(pg, 'Text', ...
                [' ' char(9654) '  ' Labels.get('reports_ctx_open', 'Open')], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~) PopupMenuManager.runAndHide(app, ...
                    @() app.ReportsVm.onOpenReport()));
            b1.Layout.Row = 1;
            b1.BackgroundColor = Theme.COLOR_CARD; b1.FontColor = Theme.BTN_FG_DEFAULT;

            % Download (char(8595) — ↓)
            b2 = uibutton(pg, 'Text', ...
                [' ' char(8595) '  ' Labels.get('reports_ctx_download', 'Download')], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~) PopupMenuManager.runAndHide(app, ...
                    @() app.ReportsVm.onDownloadPdf()));
            b2.Layout.Row = 2;
            b2.BackgroundColor = Theme.COLOR_CARD; b2.FontColor = Theme.BTN_FG_DEFAULT;

            % Email (char(9993) — ✉)
            b3 = uibutton(pg, 'Text', ...
                [' ' char(9993) '  ' Labels.get('reports_ctx_email', 'Email')], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~) PopupMenuManager.runAndHide(app, ...
                    @() app.ReportsVm.onShareEmail()));
            b3.Layout.Row = 3;
            b3.BackgroundColor = Theme.COLOR_CARD; b3.FontColor = Theme.BTN_FG_DEFAULT;

            % Print (char(9113) — ⎙)
            b4 = uibutton(pg, 'Text', ...
                [' ' char(9113) '  ' Labels.get('reports_ctx_print', 'Print')], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~) PopupMenuManager.runAndHide(app, ...
                    @() app.ReportsVm.onPrintReport()));
            b4.Layout.Row = 4;
            b4.BackgroundColor = Theme.COLOR_CARD; b4.FontColor = Theme.BTN_FG_DEFAULT;
        end

        function showReportsPopup(app, x, y)
            if isempty(app.ReportsPopupPanel) || ~isvalid(app.ReportsPopupPanel)
                PopupMenuManager.buildReportsPopup(app);
            end
            popW = 180; popH = 144;
            figPos = app.UIFigure.Position;
            px = min(x, figPos(3) - popW - 4);
            py = max(y - popH, 4);
            app.ReportsPopupPanel.Position = [px py popW popH];
            app.ReportsPopupPanel.Visible = 'on';
        end

        function hideReportsPopup(app)
            if ~isempty(app.ReportsPopupPanel) && isvalid(app.ReportsPopupPanel)
                app.ReportsPopupPanel.Visible = 'off';
            end
        end

        % ── Global dismiss (called on figure mouse-down) ─────────────────

        function dismissPopups(app)
            PopupMenuManager.dismissOne(app, 'ProjectsPopupPanel', @PopupMenuManager.hideProjectPopup);
            PopupMenuManager.dismissOne(app, 'CircuitsPopupPanel', @PopupMenuManager.hideCircuitsPopup);
            PopupMenuManager.dismissOne(app, 'BackendsPopupPanel', @PopupMenuManager.hideBackendsPopup);
            PopupMenuManager.dismissOne(app, 'ReportsPopupPanel',  @PopupMenuManager.hideReportsPopup);
        end

    end

    methods (Static, Access = private)
        function dismissOne(app, propName, hideFcn)
            if isprop(app, propName) && ~isempty(app.(propName)) && isvalid(app.(propName)) ...
                    && strcmp(app.(propName).Visible, 'on')
                cp = app.UIFigure.CurrentPoint;
                pp = app.(propName).Position;
                if cp(1) < pp(1) || cp(1) > pp(1)+pp(3) || ...
                   cp(2) < pp(2) || cp(2) > pp(2)+pp(4)
                    hideFcn(app);
                end
            end
        end

        function runAndHide(app, fn)
            % Used by Reports context-menu rows: invoke the action, then
            % close the popup so it doesn't linger after the user clicks.
            % The fn callback handles its own errors via uialert; here we
            % just guarantee the popup hides on every code path.
            try; fn(); catch ME
                Logger.warn('PopupMenuManager', ...
                    'context-menu action failed: %s', ME.message);
            end
            try; PopupMenuManager.hideReportsPopup(app); catch; end
        end
    end
end
