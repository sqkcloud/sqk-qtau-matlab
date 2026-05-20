classdef NotificationCenter < handle
    % NotificationCenter  Bottom-right toast surface for background-task
    %                       completion (and any other transient notice).
    %
    %   Listens to app.BackgroundTasks.TasksChanged and pops a toast every
    %   time a task transitions to a TERMINAL state ('completed' /
    %   'failed'). The toast lives in a hidden uipanel parented to
    %   app.UIFigure, positioned at the bottom-right, and auto-dismisses
    %   after 6 seconds via a MATLAB timer.
    %
    %   Clicking the "View" link on the toast invokes the task's
    %   userData.onView function handle (provided by the launching VM)
    %   so the user can jump directly to the result — e.g. re-opening
    %   the QMC dialog with the cached payload.
    %
    %   The toast tracks the LAST terminal task id it surfaced so a
    %   redundant TasksChanged broadcast (caused by clear() or unrelated
    %   updates) does not re-pop the same toast.

    properties (Access = private)
        App
        Panel             % uipanel (hidden by default)
        TitleLabel        % uilabel
        BodyLabel         % uilabel
        ViewLink          % uihyperlink
        CloseBtn          % uibutton
        HideTimer         % MATLAB timer
        LastShownId  = '' % most recent task id that we toasted
        CurrentOnView = []
    end

    methods

        function obj = NotificationCenter(app)
            obj.App = app;
            obj.buildPanel();
            try
                addlistener(app.BackgroundTasks, 'TasksChanged', ...
                    @(~,~) obj.onTasksChanged());
            catch ME
                try; Logger.warn('NotificationCenter', ...
                    'addlistener failed: %s', ME.message); catch; end
            end
        end

        function delete(obj)
            try; obj.stopHideTimer(); catch; end
            try
                if ~isempty(obj.Panel) && isvalid(obj.Panel)
                    delete(obj.Panel);
                end
            catch
            end
        end

    end

    methods (Access = private)

        function buildPanel(obj)
            app = obj.App;
            try
                panelBg = Theme.COLOR_CARD;
                fg      = Theme.COLOR_HEADING;
                accent  = Theme.OVERLAY_ACCENT;
                divider = Theme.COLOR_DIVIDER;
            catch
                panelBg = [0.26 0.28 0.35];
                fg      = [0.97 0.97 0.95];
                accent  = [0.45 0.36 0.62];
                divider = [0.20 0.22 0.27];
            end
            obj.Panel = uipanel(app.UIFigure, ...
                'BorderType', 'line', ...
                'BorderColor', divider, ...
                'BackgroundColor', panelBg, ...
                'Visible', 'off', ...
                'AutoResizeChildren', 'off');
            % Position is set on each show() so it tracks figure resizes.
            obj.Panel.Position = [10 10 360 80];

            g = uigridlayout(obj.Panel, [2 3]);
            g.RowHeight   = {18, '1x'};
            g.ColumnWidth = {'1x', 60, 24};
            g.Padding     = [12 8 8 8];
            g.ColumnSpacing = 6;
            g.RowSpacing  = 2;
            g.BackgroundColor = panelBg;

            obj.TitleLabel = uilabel(g, ...
                'Text', '', ...
                'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'FontColor', fg);
            obj.TitleLabel.Layout.Row = 1; obj.TitleLabel.Layout.Column = 1;

            obj.ViewLink = uihyperlink(g, ...
                'Text', 'View', ...
                'URL', '', ...
                'FontSize', 12, ...
                'FontColor', accent, ...
                'VisitedColor', accent, ...
                'HorizontalAlignment', 'right', ...
                'HyperlinkClickedFcn', @(~,~) obj.onView());
            obj.ViewLink.Layout.Row = 1; obj.ViewLink.Layout.Column = 2;

            obj.CloseBtn = uibutton(g, ...
                'Text', char(215), ...   % ×
                'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', panelBg, ...
                'FontColor', fg, ...
                'ButtonPushedFcn', @(~,~) obj.hide());
            obj.CloseBtn.Layout.Row = 1; obj.CloseBtn.Layout.Column = 3;

            obj.BodyLabel = uilabel(g, ...
                'Text', '', ...
                'FontSize', 11, ...
                'FontColor', fg, ...
                'WordWrap', 'on');
            obj.BodyLabel.Layout.Row = 2;
            obj.BodyLabel.Layout.Column = [1 3];
        end

        function onTasksChanged(obj)
            % Find the most recent terminal task that we haven't toasted
            % yet and pop it. We surface at most one toast per TasksChanged
            % broadcast — if multiple tasks went terminal in the same tick
            % (rare), the next broadcast surfaces the next one.
            try
                tasks = obj.App.BackgroundTasks.list();
            catch
                return;
            end
            % Scan newest-first by completedAt.
            best = []; bestTime = NaT;
            for i = 1:numel(tasks)
                t = tasks{i};
                if ~any(strcmp(t.status, {'completed','failed'})); continue; end
                if strcmp(t.id, obj.LastShownId); continue; end
                if isnat(bestTime) || t.completedAt > bestTime
                    best = t; bestTime = t.completedAt;
                end
            end
            if isempty(best); return; end
            obj.LastShownId = best.id;
            obj.show(best);
        end

        function show(obj, task)
            try
                app = obj.App;
                fig = app.UIFigure;

                % Position bottom-right relative to figure size, leaving
                % a 14 px gutter.
                figPos = fig.Position;
                w = 360; h = 84;
                x = max(10, figPos(3) - w - 14);
                y = 14;
                obj.Panel.Position = [x y w h];

                % Style by status.
                switch task.status
                    case 'completed'
                        title = sprintf('%s — completed', task.displayName);
                        body  = obj.formatBody(task, 'Open the result?');
                        canView = ~isempty(obj.viewHandle(task));
                    case 'failed'
                        title = sprintf('%s — failed', task.displayName);
                        body  = obj.formatBody(task, 'See details on the launching screen.');
                        canView = ~isempty(obj.viewHandle(task));
                    otherwise
                        return;
                end
                obj.TitleLabel.Text = title;
                obj.BodyLabel.Text  = body;
                obj.ViewLink.Visible = canView;
                obj.CurrentOnView = obj.viewHandle(task);
                obj.Panel.Visible  = 'on';
                try; uistack(obj.Panel, 'top'); catch; end
                obj.armHideTimer(6);
                drawnow limitrate;
            catch ME
                try; Logger.debug('NotificationCenter', ...
                    'show failed: %s', ME.message); catch; end
            end
        end

        function hide(obj)
            try
                if ~isempty(obj.Panel) && isvalid(obj.Panel)
                    obj.Panel.Visible = 'off';
                end
            catch
            end
            obj.stopHideTimer();
        end

        function onView(obj)
            try
                fn = obj.CurrentOnView;
                obj.hide();
                if ~isempty(fn); fn(); end
            catch ME
                try; Logger.warn('NotificationCenter', ...
                    'onView raised: %s', ME.message); catch; end
            end
        end

        function armHideTimer(obj, sec)
            obj.stopHideTimer();
            t = timer( ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay',    double(sec), ...
                'Name',          'NotificationHide', ...
                'TimerFcn',      @(src,~) obj.onHideTick(src));
            obj.HideTimer = t;
            start(t);
        end

        function onHideTick(obj, src)
            try; stop(src); delete(src); catch; end
            obj.HideTimer = [];
            obj.hide();
        end

        function stopHideTimer(obj)
            try
                if ~isempty(obj.HideTimer) && isvalid(obj.HideTimer)
                    stop(obj.HideTimer); delete(obj.HideTimer);
                end
            catch
            end
            obj.HideTimer = [];
        end

    end

    methods (Static, Access = private)

        function s = formatBody(task, fallback)
            % Compose a one-line body. Prefer error message on failure,
            % else fall back to a generic prompt.
            if strcmp(task.status, 'failed') && ~isempty(task.error)
                try
                    msg = char(task.error.message);
                    if numel(msg) > 200; msg = [msg(1:197) '...']; end
                    s = msg; return;
                catch
                end
            end
            s = char(fallback);
        end

        function fn = viewHandle(task)
            % Pull the optional onView function-handle from userData.
            fn = [];
            try
                if isstruct(task.userData) && isfield(task.userData, 'onView') ...
                        && isa(task.userData.onView, 'function_handle')
                    fn = task.userData.onView;
                end
            catch
            end
        end

    end
end
