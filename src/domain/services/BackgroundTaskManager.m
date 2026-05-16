classdef BackgroundTaskManager < handle
    % BackgroundTaskManager  Central registry of long-running async tasks
    %                          (Run QMC, Circuit Cutting, IBM job submit /
    %                          poll). Lets the user dismiss the loading
    %                          overlay and keep navigating while a task
    %                          continues on the server; surfaces progress
    %                          + completion via the header indicator and
    %                          a toast notification.
    %
    %   A task is a struct with:
    %     .id            char  — auto-assigned (e.g. 'bgt_7')
    %     .kind          char  — 'qmc' | 'cutting' | 'ibm_job' | ...
    %     .displayName   char  — human label ('QMC — circuit X')
    %     .status        char  — 'queued' | 'running' | 'completed' |
    %                            'failed' | 'cancelled'
    %     .progressPct   double — 0..100
    %     .statusText    char   — current step message
    %     .startedAt     datetime
    %     .updatedAt     datetime
    %     .completedAt   datetime | NaT
    %     .result        struct | []   — terminal payload on success
    %     .error         MException | [] — terminal error on failure
    %     .onComplete    function_handle | []  — fired on success
    %     .onCancel      function_handle | []  — fired by cancel()
    %     .pollCtx       struct | []   — PollingRunner.start ctx; used
    %                                    for timer cleanup on cancel
    %     .userData      struct  — caller-defined extras (job_id, ...)
    %
    %   Lifecycle:
    %     id = mgr.register(task);
    %     mgr.update(id, struct('progressPct',50,'statusText','Running'));
    %     mgr.complete(id, resultStruct);    %  -> fires onComplete + toast
    %     mgr.fail(id, ME);                  %  -> fires toast
    %     mgr.cancel(id);                    %  -> calls onCancel, stops
    %                                           poll, marks 'cancelled'
    %
    %   Events:
    %     TasksChanged — fires after any mutation. Indicator + notifier
    %                    subscribe to this; payload is empty (subscribers
    %                    re-read .list()). Subscribers must be cheap.
    %
    %   Threading:
    %     All methods run on the main thread; updates from
    %     PollingRunner.tick are already main-thread (MATLAB timer).
    %     No locking needed.

    events
        TasksChanged
    end

    properties (Access = private)
        Tasks      = {}   % cell array of task structs
        IdCounter  = 0
    end

    methods

        function id = register(obj, task)
            % register  Add a new task and return its assigned id.
            obj.IdCounter = obj.IdCounter + 1;
            id = sprintf('bgt_%d', obj.IdCounter);
            t = BackgroundTaskManager.normalize(task);
            t.id = id;
            if isempty(t.status);    t.status    = 'queued';        end
            if isnat(t.startedAt);   t.startedAt = datetime('now'); end
            t.updatedAt = t.startedAt;
            obj.Tasks{end+1} = t;
            notify(obj, 'TasksChanged');
        end

        function update(obj, id, fields)
            % update  Patch fields onto an existing task. Silently ignores
            %   an unknown id (e.g. fired by a stale timer after cancel).
            idx = obj.findIndex(id);
            if idx == 0; return; end
            t = obj.Tasks{idx};
            f = fieldnames(fields);
            for i = 1:numel(f)
                t.(f{i}) = fields.(f{i});
            end
            t.updatedAt = datetime('now');
            obj.Tasks{idx} = t;
            notify(obj, 'TasksChanged');
        end

        function complete(obj, id, result)
            % complete  Mark terminal-success. Fires task.onComplete and
            %   broadcasts TasksChanged. The task remains in the list
            %   (status='completed') so the indicator can show it as a
            %   "recently finished" entry — call clear(id) to evict.
            idx = obj.findIndex(id);
            if idx == 0; return; end
            t = obj.Tasks{idx};
            t.status      = 'completed';
            t.progressPct = 100;
            t.result      = result;
            t.completedAt = datetime('now');
            t.updatedAt   = t.completedAt;
            obj.Tasks{idx} = t;
            notify(obj, 'TasksChanged');
            % Fire the VM callback AFTER the listener pass so the indicator
            % renders the terminal state before any nested UI work runs.
            if ~isempty(t.onComplete)
                try
                    t.onComplete(result);
                catch ME
                    try; Logger.warn('BackgroundTaskManager', ...
                        'onComplete(%s) raised: %s', id, ME.message); catch; end
                end
            end
        end

        function fail(obj, id, ME)
            % fail  Mark terminal-failure with the captured MException.
            idx = obj.findIndex(id);
            if idx == 0; return; end
            t = obj.Tasks{idx};
            t.status      = 'failed';
            t.error       = ME;
            t.completedAt = datetime('now');
            t.updatedAt   = t.completedAt;
            obj.Tasks{idx} = t;
            notify(obj, 'TasksChanged');
        end

        function cancel(obj, id)
            % cancel  Best-effort server-side cancel + poll teardown.
            %   Idempotent on already-terminal tasks (no-op).
            idx = obj.findIndex(id);
            if idx == 0; return; end
            t = obj.Tasks{idx};
            if any(strcmp(t.status, {'completed','failed','cancelled'}))
                return;
            end
            if ~isempty(t.onCancel)
                try; t.onCancel(); catch ME
                    try; Logger.debug('BackgroundTaskManager', ...
                        'onCancel(%s) raised: %s', id, ME.message); catch; end
                end
            end
            if ~isempty(t.pollCtx)
                try; PollingRunner.cancel(t.pollCtx); catch; end
            end
            t.status      = 'cancelled';
            t.completedAt = datetime('now');
            t.updatedAt   = t.completedAt;
            obj.Tasks{idx} = t;
            notify(obj, 'TasksChanged');
        end

        function clear(obj, id)
            % clear  Evict a terminal task from the list. No-op if absent.
            idx = obj.findIndex(id);
            if idx == 0; return; end
            obj.Tasks(idx) = [];
            notify(obj, 'TasksChanged');
        end

        function clearTerminal(obj)
            % clearTerminal  Evict every completed/failed/cancelled task.
            keep = true(1, numel(obj.Tasks));
            for i = 1:numel(obj.Tasks)
                if any(strcmp(obj.Tasks{i}.status, ...
                        {'completed','failed','cancelled'}))
                    keep(i) = false;
                end
            end
            if all(keep); return; end
            obj.Tasks = obj.Tasks(keep);
            notify(obj, 'TasksChanged');
        end

        function out = list(obj)
            % list  Snapshot of every tracked task (active + terminal).
            out = obj.Tasks;
        end

        function t = findById(obj, id)
            % findById  Return the task struct for id, or [] if unknown.
            idx = obj.findIndex(id);
            if idx == 0; t = []; else; t = obj.Tasks{idx}; end
        end

        function n = countActive(obj)
            % countActive  Number of tasks in queued/running.
            n = 0;
            for i = 1:numel(obj.Tasks)
                if any(strcmp(obj.Tasks{i}.status, {'queued','running'}))
                    n = n + 1;
                end
            end
        end

    end

    methods (Access = private)

        function idx = findIndex(obj, id)
            idx = 0;
            for i = 1:numel(obj.Tasks)
                if strcmp(obj.Tasks{i}.id, id)
                    idx = i; return;
                end
            end
        end

    end

    methods (Static, Access = private)

        function t = normalize(task)
            % normalize  Fill in defaults for any unset task fields so
            %   downstream code can assume the struct shape.
            defaults = struct( ...
                'id',          '', ...
                'kind',        'task', ...
                'displayName', 'Background task', ...
                'status',      '', ...
                'progressPct', 0, ...
                'statusText',  '', ...
                'startedAt',   NaT, ...
                'updatedAt',   NaT, ...
                'completedAt', NaT, ...
                'result',      [], ...
                'error',       [], ...
                'onComplete',  [], ...
                'onCancel',    [], ...
                'pollCtx',     [], ...
                'userData',    struct());
            t = defaults;
            if ~isstruct(task); return; end
            f = fieldnames(defaults);
            inFields = fieldnames(task);
            for i = 1:numel(inFields)
                if any(strcmp(inFields{i}, f))
                    t.(inFields{i}) = task.(inFields{i});
                end
            end
        end

    end
end
