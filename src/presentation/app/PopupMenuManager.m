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
            app.ProjectsPopupEditBtn.FontColor = Theme.COLOR_HEADING;

            app.ProjectsPopupDeleteBtn = uibutton(pg, 'Text', ...
                [' ' char(10005) '  ' Labels.get('project_ctx_delete', 'Delete')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onDeleteProject());
            app.ProjectsPopupDeleteBtn.Layout.Row = 2;
            app.ProjectsPopupDeleteBtn.BackgroundColor = Theme.COLOR_CARD;
            app.ProjectsPopupDeleteBtn.FontColor = Theme.COLOR_DANGER;
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
            analyzeBtn.FontColor = Theme.COLOR_PRIMARY;

            app.CircuitsPopupEditBtn = uibutton(pg, 'Text', ...
                [' ' char(9999) '  ' Labels.get('circuit_ctx_edit', 'Edit')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupEdit());
            app.CircuitsPopupEditBtn.Layout.Row = 2;
            app.CircuitsPopupEditBtn.BackgroundColor = Theme.COLOR_CARD;
            app.CircuitsPopupEditBtn.FontColor = Theme.COLOR_HEADING;

            app.CircuitsPopupDeleteBtn = uibutton(pg, 'Text', ...
                [' ' char(10005) '  ' Labels.get('circuit_ctx_delete', 'Delete')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupDelete());
            app.CircuitsPopupDeleteBtn.Layout.Row = 3;
            app.CircuitsPopupDeleteBtn.BackgroundColor = Theme.COLOR_CARD;
            app.CircuitsPopupDeleteBtn.FontColor = Theme.COLOR_DANGER;
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
            b1.BackgroundColor = Theme.COLOR_CARD; b1.FontColor = Theme.COLOR_PRIMARY;

            % Set as Backup (char(9744) — empty checkbox)
            b2 = uibutton(pg, 'Text', [' ' char(9744) '  Set as Backup'], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.BackendsVm.onCtxSetBackup());
            b2.Layout.Row = 2;
            b2.BackgroundColor = Theme.COLOR_CARD; b2.FontColor = Theme.COLOR_HEADING;

            % View Details (char(8505) — info)
            b3 = uibutton(pg, 'Text', [' ' char(8505) '  View Details'], ...
                'HorizontalAlignment', 'left', 'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.BackendsVm.onCtxViewDetails());
            b3.Layout.Row = 3;
            b3.BackgroundColor = Theme.COLOR_CARD; b3.FontColor = Theme.COLOR_HEADING;
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
            end
        end

        % ── Global dismiss (called on figure mouse-down) ─────────────────

        function dismissPopups(app)
            PopupMenuManager.dismissOne(app, 'ProjectsPopupPanel', @PopupMenuManager.hideProjectPopup);
            PopupMenuManager.dismissOne(app, 'CircuitsPopupPanel', @PopupMenuManager.hideCircuitsPopup);
            PopupMenuManager.dismissOne(app, 'BackendsPopupPanel', @PopupMenuManager.hideBackendsPopup);
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
    end
end
