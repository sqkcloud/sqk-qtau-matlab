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
                'BackgroundColor', [1 1 1], ...
                'BorderColor', [0.78 0.80 0.84], ...
                'Position', [0 0 popW popH], ...
                'Visible', 'off');

            pg = uigridlayout(app.ProjectsPopupPanel, [2 1]);
            pg.RowHeight   = {'1x', '1x'};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [4 4 4 4];
            pg.RowSpacing  = 2;
            pg.BackgroundColor = [1 1 1];

            app.ProjectsPopupEditBtn = uibutton(pg, 'Text', ...
                [' ' char(9999) '  ' Labels.get('project_ctx_edit', 'Edit')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onEditProject());
            app.ProjectsPopupEditBtn.Layout.Row = 1;
            app.ProjectsPopupEditBtn.BackgroundColor = [1 1 1];
            app.ProjectsPopupEditBtn.FontColor = [0.15 0.18 0.24];

            app.ProjectsPopupDeleteBtn = uibutton(pg, 'Text', ...
                [' ' char(10005) '  ' Labels.get('project_ctx_delete', 'Delete')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onDeleteProject());
            app.ProjectsPopupDeleteBtn.Layout.Row = 2;
            app.ProjectsPopupDeleteBtn.BackgroundColor = [1 1 1];
            app.ProjectsPopupDeleteBtn.FontColor = [0.70 0.15 0.15];
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
                'BackgroundColor', [1 1 1], ...
                'BorderColor', [0.78 0.80 0.84], ...
                'Position', [0 0 popW popH], ...
                'Visible', 'off');

            pg = uigridlayout(app.CircuitsPopupPanel, [3 1]);
            pg.RowHeight   = {'1x', '1x', '1x'};
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [4 4 4 4];
            pg.RowSpacing  = 2;
            pg.BackgroundColor = [1 1 1];

            analyzeBtn = uibutton(pg, 'Text', ...
                [' ' char(8981) '  ' Labels.get('circuit_ctx_analyze', 'Analyze')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupAnalyze());
            analyzeBtn.Layout.Row = 1;
            analyzeBtn.BackgroundColor = [1 1 1];
            analyzeBtn.FontColor = [0.13 0.33 0.73];

            app.CircuitsPopupEditBtn = uibutton(pg, 'Text', ...
                [' ' char(9999) '  ' Labels.get('circuit_ctx_edit', 'Edit')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupEdit());
            app.CircuitsPopupEditBtn.Layout.Row = 2;
            app.CircuitsPopupEditBtn.BackgroundColor = [1 1 1];
            app.CircuitsPopupEditBtn.FontColor = [0.15 0.18 0.24];

            app.CircuitsPopupDeleteBtn = uibutton(pg, 'Text', ...
                [' ' char(10005) '  ' Labels.get('circuit_ctx_delete', 'Delete')], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~)app.onCircuitsPopupDelete());
            app.CircuitsPopupDeleteBtn.Layout.Row = 3;
            app.CircuitsPopupDeleteBtn.BackgroundColor = [1 1 1];
            app.CircuitsPopupDeleteBtn.FontColor = [0.70 0.15 0.15];
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

        % ── Global dismiss (called on figure mouse-down) ─────────────────

        function dismissPopups(app)
            if ~isempty(app.ProjectsPopupPanel) && isvalid(app.ProjectsPopupPanel) ...
                    && strcmp(app.ProjectsPopupPanel.Visible, 'on')
                cp = app.UIFigure.CurrentPoint;
                pp = app.ProjectsPopupPanel.Position;
                if cp(1) < pp(1) || cp(1) > pp(1)+pp(3) || ...
                   cp(2) < pp(2) || cp(2) > pp(2)+pp(4)
                    PopupMenuManager.hideProjectPopup(app);
                end
            end
            if ~isempty(app.CircuitsPopupPanel) && isvalid(app.CircuitsPopupPanel) ...
                    && strcmp(app.CircuitsPopupPanel.Visible, 'on')
                cp = app.UIFigure.CurrentPoint;
                pp = app.CircuitsPopupPanel.Position;
                if cp(1) < pp(1) || cp(1) > pp(1)+pp(3) || ...
                   cp(2) < pp(2) || cp(2) > pp(2)+pp(4)
                    PopupMenuManager.hideCircuitsPopup(app);
                end
            end
        end

    end
end
