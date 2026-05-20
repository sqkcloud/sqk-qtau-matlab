classdef BackgroundTasksIndicator < handle
    % BackgroundTasksIndicator  Header badge that surfaces the live count
    %                             of in-flight background tasks. Clicking
    %                             the badge opens a small popover listing
    %                             each active task with progress, View,
    %                             and Cancel actions. Visible only while
    %                             at least one task is queued/running.

    properties (Access = private)
        App
        Button             % uihtml — the badge (circular outline, ghost style)
        Popover            % uifigure (created lazily)
        PopoverList        % uigridlayout inside the popover
    end

    methods

        function obj = BackgroundTasksIndicator(app, parent)
            obj.App = app;
            % Styled as a uihtml ghost badge to mirror LayoutBuilder's
            % buildHelpIconHtml — circular outline, transparent fill,
            % white border, subtle hover. Pill-shaped when a count is
            % visible, perfect circle when empty.
            obj.Button = uihtml(parent);
            obj.Button.Layout.Column = 1;
            obj.Button.HTMLSource = BackgroundTasksIndicator.buildBadgeHtml(0);
            obj.Button.DataChangedFcn = @(~,~) obj.togglePopover();
            try
                addlistener(app.BackgroundTasks, 'TasksChanged', ...
                    @(~,~) obj.refresh());
            catch
            end
            obj.refresh();
        end

        function refresh(obj)
            try
                n = obj.App.BackgroundTasks.countActive();
                % Keep the badge visible at all times — operators
                % rely on its constant placement in the top toolbar
                % as a tray entry-point. Empty state shows just the
                % refresh glyph (no count); active state shows the
                % glyph + integer count in a pill.
                if ~isempty(obj.Button) && isvalid(obj.Button)
                    obj.Button.HTMLSource = BackgroundTasksIndicator.buildBadgeHtml(n);
                end
                if ~isempty(obj.Popover) && isvalid(obj.Popover)
                    obj.renderPopoverList();
                end
            catch ME
                try; Logger.debug('BackgroundTasksIndicator', ...
                    'refresh failed: %s', ME.message); catch; end
            end
        end

        function delete(obj)
            try
                if ~isempty(obj.Popover) && isvalid(obj.Popover)
                    delete(obj.Popover);
                end
            catch
            end
            try
                if ~isempty(obj.Button) && isvalid(obj.Button)
                    delete(obj.Button);
                end
            catch
            end
        end

    end

    methods (Access = private)

        function togglePopover(obj)
            if ~isempty(obj.Popover) && isvalid(obj.Popover) ...
                    && strcmp(obj.Popover.Visible, 'on')
                obj.Popover.Visible = 'off';
                return;
            end
            obj.openPopover();
        end

        function openPopover(obj)
            try
                figW = 420; figH = 320;
                try
                    mainPos = obj.App.UIFigure.Position;
                    x = max(0, mainPos(1) + mainPos(3) - figW - 16);
                    y = max(0, mainPos(2) + mainPos(4) - figH - 56);
                catch
                    x = 100; y = 100;
                end
                obj.Popover = uifigure('Name', 'Background Tasks', ...
                    'Position', [x y figW figH], ...
                    'Resize', 'off');
                try
                    obj.Popover.Color = Theme.COLOR_CARD;
                catch
                end
                obj.PopoverList = uigridlayout(obj.Popover, [1 1]);
                obj.PopoverList.Padding = [12 12 12 12];
                obj.PopoverList.RowHeight = {'1x'};
                try
                    obj.PopoverList.BackgroundColor = Theme.COLOR_CARD;
                catch
                end
                obj.renderPopoverList();
            catch ME
                try; Logger.debug('BackgroundTasksIndicator', ...
                    'openPopover failed: %s', ME.message); catch; end
            end
        end

        function renderPopoverList(obj)
            if isempty(obj.PopoverList) || ~isvalid(obj.PopoverList); return; end
            for c = obj.PopoverList.Children'
                try; delete(c); catch; end
            end

            tasks = obj.App.BackgroundTasks.list();
            if isempty(tasks)
                lbl = uilabel(obj.PopoverList, ...
                    'Text', 'No background tasks.', ...
                    'HorizontalAlignment', 'center', ...
                    'FontSize', 12);
                try; lbl.FontColor = Theme.COLOR_MUTED; catch; end
                return;
            end

            n = numel(tasks);
            inner = uigridlayout(obj.PopoverList, [n + 1, 1]);
            inner.Padding = [0 0 0 0];
            inner.RowSpacing = 6;
            rowH = cell(1, n + 1);
            for i = 1:n; rowH{i} = 'fit'; end
            rowH{end} = 32;
            inner.RowHeight = rowH;
            try; inner.BackgroundColor = Theme.COLOR_CARD; catch; end

            for i = 1:n
                obj.renderTaskRow(inner, i, tasks{i});
            end

            clearBtn = uibutton(inner, ...
                'Text', 'Clear Completed', ...
                'FontSize', 13, ...
                'ButtonPushedFcn', @(~,~) obj.App.BackgroundTasks.clearTerminal());
            clearBtn.Layout.Row = n + 1; clearBtn.Layout.Column = 1;
            try; obj.App.styleBtn(clearBtn, 'ghost'); catch; end
        end

        function renderTaskRow(obj, parent, rowIdx, task)
            cell = uipanel(parent, 'BorderType', 'line');
            cell.Layout.Row = rowIdx; cell.Layout.Column = 1;
            try
                cell.BorderColor = Theme.COLOR_DIVIDER;
                cell.BackgroundColor = Theme.COLOR_CARD;
            catch
            end

            g = uigridlayout(cell, [2 3]);
            g.RowHeight   = {'fit', 'fit'};
            g.ColumnWidth = {'1x', 70, 70};
            g.Padding     = [10 8 10 8];
            g.ColumnSpacing = 6; g.RowSpacing = 2;
            try; g.BackgroundColor = Theme.COLOR_CARD; catch; end

            title = uilabel(g, ...
                'Text', task.displayName, ...
                'FontSize', 12, 'FontWeight', 'bold');
            title.Layout.Row = 1; title.Layout.Column = 1;
            try; title.FontColor = Theme.COLOR_HEADING; catch; end

            statusBits = {upper(task.status)};
            if ~isempty(task.progressPct) && task.progressPct > 0 ...
                    && ~strcmp(task.status, 'completed')
                statusBits{end+1} = sprintf('%d%%', round(task.progressPct));
            end
            if ~isempty(task.statusText)
                txt = char(task.statusText);
                if numel(txt) > 80; txt = [txt(1:77) '...']; end
                statusBits{end+1} = txt;
            end
            sublbl = uilabel(g, ...
                'Text', strjoin(statusBits, ' · '), ...
                'FontSize', 11);
            sublbl.Layout.Row = 2; sublbl.Layout.Column = [1 3];
            try; sublbl.FontColor = Theme.COLOR_MUTED; catch; end

            isActive = any(strcmp(task.status, {'queued','running'}));

            viewFn = [];
            try
                if isstruct(task.userData) && isfield(task.userData,'onView') ...
                        && isa(task.userData.onView, 'function_handle')
                    viewFn = task.userData.onView;
                end
            catch
            end
            if ~isempty(viewFn); viewEnable = 'on'; else; viewEnable = 'off'; end
            viewBtn = uibutton(g, ...
                'Text', 'View', ...
                'FontSize', 12, ...
                'Enable', viewEnable, ...
                'ButtonPushedFcn', @(~,~) BackgroundTasksIndicator.invokeView(obj, viewFn));
            viewBtn.Layout.Row = 1; viewBtn.Layout.Column = 2;
            try; obj.App.styleBtn(viewBtn, 'secondary'); catch; end

            if isActive
                actLabel = 'Cancel';
                actStyle = 'danger';
            else
                actLabel = 'Clear';
                actStyle = 'ghost';
            end
            actBtn = uibutton(g, ...
                'Text', actLabel, ...
                'FontSize', 12, ...
                'ButtonPushedFcn', @(~,~) obj.onRowAction(task.id, isActive));
            actBtn.Layout.Row = 1; actBtn.Layout.Column = 3;
            try; obj.App.styleBtn(actBtn, actStyle); catch; end
        end

        function onRowAction(obj, taskId, isActive)
            try
                if isActive
                    obj.App.BackgroundTasks.cancel(taskId);
                else
                    obj.App.BackgroundTasks.clear(taskId);
                end
            catch ME
                try; Logger.debug('BackgroundTasksIndicator', ...
                    'row action (%s) failed: %s', taskId, ME.message); catch; end
            end
        end

    end

    methods (Static, Access = private)

        function html = buildBadgeHtml(count)
            % buildBadgeHtml  Themed circular/pill badge for the
            %   background-tasks indicator. Mirrors the visual style of
            %   LayoutBuilder.buildHelpIconHtml (the (?) help icon) —
            %   transparent fill, 1.5 px white outline, subtle hover bg.
            %   Renders a perfect circle when count == 0 (just the
            %   refresh glyph), expanding to a pill when a count is
            %   visible.
            try
                bg = Theme.toHex(Theme.NAV_BG);
                fg = Theme.toHex(Theme.NAV_FG);
            catch
                bg = '#1A1F26'; fg = '#F2F4F7';
            end
            if count <= 0
                label = char(8635);              % ⟳ glyph alone
            else
                label = sprintf('%s %d', char(8635), count);
            end
            html = [ ...
                '<!DOCTYPE html><html><head><meta charset="utf-8"><style>' ...
                'html,body{margin:0;padding:0;width:100%;height:100%;' ...
                'background:' bg ';display:flex;align-items:center;' ...
                'justify-content:center;font-family:-apple-system,' ...
                '"Segoe UI",Helvetica,Arial,sans-serif;}' ...
                '.tasks{height:22px;min-width:22px;width:auto;padding:0 8px;' ...
                'box-sizing:border-box;border-radius:11px;' ...
                'border:1.5px solid ' fg '99;color:' fg ';' ...
                'display:flex;align-items:center;justify-content:center;' ...
                'font-size:12px;font-weight:700;line-height:1;cursor:pointer;' ...
                'background:transparent;user-select:none;white-space:nowrap;' ...
                'transition:background 120ms ease, border-color 120ms ease;}' ...
                '.tasks:hover{background:' fg '22;border-color:' fg ';}' ...
                '.tasks:active{background:' fg '33;}' ...
                '</style></head><body>' ...
                '<div class="tasks" id="b" title="Background Tasks">' label '</div>' ...
                '<script>' ...
                'function setup(htmlComponent){' ...
                ' var b=document.getElementById("b");' ...
                ' if(!b)return;' ...
                ' b.addEventListener("click",function(){' ...
                '  htmlComponent.Data=Date.now();' ...
                ' });' ...
                '}' ...
                '</script>' ...
                '</body></html>'];
        end

        function invokeView(obj, viewFn)
            try
                if ~isempty(obj.Popover) && isvalid(obj.Popover)
                    obj.Popover.Visible = 'off';
                end
                if ~isempty(viewFn); viewFn(); end
            catch ME
                try; Logger.warn('BackgroundTasksIndicator', ...
                    'invokeView raised: %s', ME.message); catch; end
            end
        end

    end
end
