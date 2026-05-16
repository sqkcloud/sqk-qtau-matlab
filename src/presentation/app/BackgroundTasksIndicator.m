classdef BackgroundTasksIndicator < handle
    % BackgroundTasksIndicator  Header badge that surfaces the live count
    %                             of in-flight background tasks. Clicking
    %                             the badge opens a small popover listing
    %                             each active task with progress, View,
    %                             and Cancel actions. Visible only while
    %                             at least one task is queued/running.

    properties (Access = private)
        App
        Button             % uibutton — the badge
        Popover            % uifigure (created lazily)
        PopoverList        % uigridlayout inside the popover
        AccentColor
        TextColor
    end

    methods

        function obj = BackgroundTasksIndicator(app, parent)
            obj.App = app;
            try
                obj.AccentColor = Theme.OVERLAY_ACCENT;
                obj.TextColor   = Theme.NAV_FG;
            catch
                obj.AccentColor = [0.45 0.36 0.62];
                obj.TextColor   = [0.97 0.97 0.95];
            end
            obj.Button = uibutton(parent, ...
                'Text', '', ...
                'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'FontColor', obj.TextColor, ...
                'BackgroundColor', obj.AccentColor, ...
                'Tooltip', 'Background tasks', ...
                'ButtonPushedFcn', @(~,~) obj.togglePopover(), ...
                'Visible', 'off');
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
                if n <= 0
                    obj.Button.Visible = 'off';
                    if ~isempty(obj.Popover) && isvalid(obj.Popover)
                        obj.renderPopoverList();
                    end
                    return;
                end
                obj.Button.Text = sprintf('%s  %d', char(8635), n); % ⟳ N
                obj.Button.Visible = 'on';
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
                obj.Popover = uifigure('Name', 'Background tasks', ...
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
                'Text', 'Clear completed', ...
                'FontSize', 12, ...
                'ButtonPushedFcn', @(~,~) obj.App.BackgroundTasks.clearTerminal());
            clearBtn.Layout.Row = n + 1; clearBtn.Layout.Column = 1;
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
                'FontSize', 11, ...
                'Enable', viewEnable, ...
                'ButtonPushedFcn', @(~,~) BackgroundTasksIndicator.invokeView(obj, viewFn));
            viewBtn.Layout.Row = 1; viewBtn.Layout.Column = 2;

            if isActive; actLabel = 'Cancel'; else; actLabel = 'Clear'; end
            actBtn = uibutton(g, ...
                'Text', actLabel, ...
                'FontSize', 11, ...
                'ButtonPushedFcn', @(~,~) obj.onRowAction(task.id, isActive));
            actBtn.Layout.Row = 1; actBtn.Layout.Column = 3;
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
