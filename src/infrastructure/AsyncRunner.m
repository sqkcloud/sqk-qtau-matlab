classdef AsyncRunner
    % AsyncRunner  Execute functions asynchronously using parfeval.
    %
    %   Wraps parfeval(backgroundPool(), ...) so that long-running API calls
    %   don't block the MATLAB UI thread.  Results are delivered via a
    %   user-supplied callback (onDone) that runs on the main thread.
    %
    %   Usage:
    %       AsyncRunner.run(@()svc.analyzeCircuit(cid, token), ...
    %           @(result) applyResult(result), ...
    %           @(ME) app.showError('Analyze', ME));
    %
    %   With timeout (seconds):
    %       AsyncRunner.run(workFcn, onDone, onError, 120);
    %
    %   Pool acquisition order:
    %     1. backgroundPool()         (lightweight, R2021b+)
    %     2. Existing parallel pool   (gcp 'nocreate')
    %     3. parpool('Threads')       (shared-memory, R2020b+)
    %     4. Synchronous fallback     (last resort, blocks UI)

    methods (Static)

        function future = run(workFcn, onDone, onError, timeoutSec)
            % RUN  Execute workFcn asynchronously; call onDone(result) or
            %      onError(MException) on completion.
            %
            %   workFcn    — @() expression returning one output
            %   onDone     — @(result) callback on success
            %   onError    — @(ME) callback on failure  (optional)
            %   timeoutSec — seconds before auto-cancel (optional, default 120)
            if nargin < 3; onError = []; end
            if nargin < 4; timeoutSec = 120; end

            pool = AsyncRunner.acquirePool();

            if ~isempty(pool)
                try
                    % Wrap the work function so it always returns 1 output,
                    % even on error.  This avoids MATLAB:maxlhs when
                    % parfeval expects 1 output but the function throws.
                    future = parfeval(pool, @() AsyncRunner.safeCall(workFcn), 1);

                    % Poll the future via a fast timer.  afterEach does NOT
                    % fire for errored futures, so we use a 50ms polling
                    % timer that checks future.State and delivers the
                    % result (or error) to the main thread.
                    poller = timer('Period', 0.05, 'ExecutionMode', 'fixedRate', ...
                        'TimerFcn', @(src,~) AsyncRunner.pollFuture(src, future, onDone, onError, timeoutSec), ...
                        'UserData', tic);
                    start(poller);
                    return;
                catch ME
                    Logger.warn('AsyncRunner', 'parfeval dispatch failed: %s', ME.message);
                    % Fall through to synchronous
                end
            end

            % Synchronous fallback — runs on the UI thread
            try
                result = workFcn();
                onDone(result);
                future = [];
            catch ME
                if ~isempty(onError)
                    onError(ME);
                else
                    rethrow(ME);
                end
                future = [];
            end
        end
    end

    methods (Static, Hidden)
        function out = safeCall(workFcn)
            % safeCall  Execute workFcn, returning a struct that always
            %   has exactly 1 output.  If workFcn throws, the error is
            %   stored in the struct instead of propagating to parfeval.
            %   Must be non-private so parfeval workers can call it.
            %
            %   Handles MATLAB:maxlhs (anonymous functions whose body
            %   never returns a value, e.g. @() error(...)) by retrying
            %   with zero output arguments.
            try
                val = workFcn();
                out = struct('ok', true, 'value', {val}, 'error', []);
            catch ME
                if strcmp(ME.identifier, 'MATLAB:maxlhs')
                    try
                        workFcn();
                        out = struct('ok', true, 'value', {[]}, 'error', []);
                    catch ME2
                        out = struct('ok', false, 'value', {[]}, 'error', ME2);
                    end
                else
                    out = struct('ok', false, 'value', {[]}, 'error', ME);
                end
            end
        end
    end

    methods (Static, Access = private)

        % ── Pool acquisition with caching ────────────────────────────────

        function pool = acquirePool()
            % acquirePool  Return a reusable parallel pool, or [] if none
            %   available.  Caches the pool in a persistent variable so
            %   backgroundPool() / parpool() is called at most once per
            %   session.  Logs the actual error on first failure.
            persistent cachedPool poolFailed

            % Fast path: already have a working pool
            if ~isempty(cachedPool)
                try
                    if isa(cachedPool, 'parallel.Pool') || isa(cachedPool, 'parallel.BackgroundPool')
                        pool = cachedPool;
                        return;
                    end
                catch
                    cachedPool = [];
                end
            end

            % If we already tried and failed, don't retry every call
            if ~isempty(poolFailed) && poolFailed
                pool = [];
                return;
            end

            % Strategy 1: backgroundPool (lightweight, shared-memory)
            try
                cachedPool = backgroundPool();
                pool = cachedPool;
                Logger.info('AsyncRunner', 'Using backgroundPool for async dispatch');
                return;
            catch ME
                Logger.warn('AsyncRunner', 'backgroundPool() failed: %s', ME.message);
            end

            % Strategy 2: reuse an existing parallel pool
            try
                existing = gcp('nocreate');
                if ~isempty(existing)
                    cachedPool = existing;
                    pool = cachedPool;
                    Logger.info('AsyncRunner', 'Reusing existing parallel pool (%s, %d workers)', ...
                        existing.Cluster.Profile, existing.NumWorkers);
                    return;
                end
            catch ME
                Logger.debug('AsyncRunner', 'gcp(''nocreate'') failed: %s', ME.message);
            end

            % Strategy 3: create a thread-based pool (shared-memory, no serialization)
            try
                cachedPool = parpool('Threads');
                pool = cachedPool;
                Logger.info('AsyncRunner', 'Created Threads pool (%d workers)', cachedPool.NumWorkers);
                return;
            catch ME
                Logger.warn('AsyncRunner', 'parpool(''Threads'') failed: %s', ME.message);
            end

            % All strategies failed — fall back to synchronous
            poolFailed = true;
            pool = [];
            Logger.warn('AsyncRunner', ...
                'No parallel pool available — all async work will run synchronously on the UI thread');
        end

        % ── Future polling (runs on main thread via timer) ────────────────

        function pollFuture(timerObj, future, onDone, onError, timeoutSec)
            % pollFuture  Called every 50ms to check if the parfeval future
            %   has finished.  Delivers the result (or error) on the main
            %   thread, then stops and deletes the polling timer.
            try
                state = future.State;
                if strcmp(state, 'running') || strcmp(state, 'queued')
                    % Check timeout
                    if timeoutSec > 0
                        elapsed = toc(timerObj.UserData);
                        if elapsed > timeoutSec
                            cancel(future);
                            stop(timerObj); delete(timerObj);
                            Logger.warn('AsyncRunner', 'Task timed out — cancelled');
                            ME = MException('AsyncRunner:Timeout', ...
                                'Operation timed out. The server may be busy — please try again.');
                            if ~isempty(onError); onError(ME); end
                            return;
                        end
                    end
                    return; % still running — check again on next tick
                end

                % Future finished — stop polling
                stop(timerObj); delete(timerObj);

                % Check if the future itself errored (safeCall failed to
                % execute, e.g. closure serialization or path issue).
                if ~isempty(future.Error)
                    err = future.Error;
                    % Unwrap ParallelException → remotecause → cause
                    try; if ~isempty(err.remotecause); err = err.remotecause{1}; end; catch; end
                    try; if ~isempty(err.cause); err = err.cause{1}; end; catch; end
                    Logger.error('AsyncRunner', 'Background task error: %s', err.message);
                    if ~isempty(onError); onError(err); else
                        Logger.error('AsyncRunner', 'Async task failed (no handler): %s', err.message);
                    end
                    return;
                end

                % safeCall wraps errors in a struct.  Unwrap it.
                out = fetchOutputs(future);
                if isstruct(out) && isfield(out, 'ok')
                    if out.ok
                        onDone(out.value);
                    else
                        if ~isempty(onError)
                            onError(out.error);
                        else
                            Logger.error('AsyncRunner', 'Async task failed: %s', out.error.message);
                        end
                    end
                else
                    % Unexpected result shape — treat as success
                    onDone(out);
                end
            catch ME
                try stop(timerObj); delete(timerObj); catch; end
                Logger.error('AsyncRunner', 'pollFuture error: %s', ME.message);
                if ~isempty(onError)
                    onError(ME);
                end
            end
        end
    end
end
