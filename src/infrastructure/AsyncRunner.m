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

        function warmUp()
            % WARMUP  Pre-spawn the parallel-pool worker so the first
            %         user-visible API call doesn't pay the worker
            %         startup cost (~3–5 s on macOS).
            %
            %         Call once at app boot, after the UIFigure is
            %         visible — the warm-up runs in the background
            %         while the user reads the login screen, and the
            %         next real run() lands on a hot worker.
            %
            %         Idempotent: subsequent calls just kick another
            %         no-op into an already-warm pool. Failure is
            %         silent (logged at debug) so a missing PCT
            %         license never breaks boot.
            try
                pool = AsyncRunner.acquirePool();
                if isempty(pool); return; end
                % @() true is the smallest possible payload — its
                % only purpose is to force the pool to materialise
                % a worker process before the first real request.
                parfeval(pool, @() true, 1);
                Logger.info('AsyncRunner', 'Pool warm-up dispatched');
            catch ME
                Logger.debug('AsyncRunner', 'warmUp failed: %s', ME.message);
            end
        end

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

                    % Poll the future via a fast timer. afterEach does NOT
                    % fire for errored futures, so we use a 50ms polling
                    % timer that checks future.State and delivers the
                    % result (or error) to the main thread.
                    %
                    % (Briefly bumped to 100ms in an earlier perf round
                    % under the theory it would "halve timer overhead" —
                    % the CPU savings turned out to be in the
                    % microseconds per tick, while the added 25ms
                    % average latency per request was a measurable
                    % user-perceptible regression. 50ms is the right
                    % balance: tick cost is still negligible and
                    % completed futures land within ~25ms on average.)
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

        function futures = runMany(workFcns, onAllDone, onError, timeoutSec)
            % RUNMANY  Execute N workFcns concurrently; deliver all results
            %          to onAllDone in input order via a SINGLE polling
            %          timer (vs. N independent timers when callers spam
            %          AsyncRunner.run).
            %
            %   workFcns   — cell array of @() expressions, each returning 1 output
            %   onAllDone  — @(results) callback with a 1×N cell array of
            %                results in the same order as workFcns
            %   onError    — @(ME) called once if ANY future errors (other
            %                futures finish but their results are discarded).
            %                Optional.
            %   timeoutSec — total wall-clock timeout for the whole batch
            %                (default 120 s). On timeout all in-flight
            %                futures are cancelled.
            %
            % Use this when 2+ independent HTTP/disk calls would otherwise
            % serialize on the worker (e.g. listJobs + listCircuits,
            % listCircuits + getBenchmarkConfig). backgroundPool() has
            % NumWorkers = maxNumCompThreads, so multiple parfeval
            % dispatches actually run concurrently.
            if nargin < 3; onError = []; end
            if nargin < 4; timeoutSec = 120; end

            n = numel(workFcns);
            if n == 0
                if ~isempty(onAllDone); onAllDone({}); end
                futures = {};
                return;
            end

            pool = AsyncRunner.acquirePool();

            if ~isempty(pool)
                try
                    futures = cell(1, n);
                    for i = 1:n
                        wf = workFcns{i};
                        futures{i} = parfeval(pool, ...
                            @() AsyncRunner.safeCall(wf), 1);
                    end

                    poller = timer('Period', 0.05, 'ExecutionMode', 'fixedRate', ...
                        'TimerFcn', @(src,~) AsyncRunner.pollFutures( ...
                            src, futures, onAllDone, onError, timeoutSec), ...
                        'UserData', tic);
                    start(poller);
                    return;
                catch ME
                    Logger.warn('AsyncRunner', 'runMany dispatch failed: %s', ME.message);
                end
            end

            % Synchronous fallback — runs sequentially on the UI thread.
            results = cell(1, n);
            try
                for i = 1:n
                    results{i} = workFcns{i}();
                end
                if ~isempty(onAllDone); onAllDone(results); end
                futures = {};
            catch ME
                if ~isempty(onError)
                    onError(ME);
                else
                    rethrow(ME);
                end
                futures = {};
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

        function pollFutures(timerObj, futures, onAllDone, onError, timeoutSec)
            % pollFutures  Called every 50 ms to check if ALL parfeval
            %   futures in the batch have finished.  Delivers results
            %   (or first error) on the main thread, then stops and
            %   deletes the polling timer.
            try
                n = numel(futures);
                allDone = true;
                firstError = [];
                for i = 1:n
                    f = futures{i};
                    s = f.State;
                    if strcmp(s, 'running') || strcmp(s, 'queued')
                        allDone = false;
                        break;
                    elseif ~isempty(f.Error) && isempty(firstError)
                        firstError = f.Error;
                    end
                end

                if ~allDone
                    % Check batch timeout
                    if timeoutSec > 0
                        elapsed = toc(timerObj.UserData);
                        if elapsed > timeoutSec
                            for j = 1:n
                                try; cancel(futures{j}); catch; end
                            end
                            stop(timerObj); delete(timerObj);
                            Logger.warn('AsyncRunner', 'runMany batch timed out');
                            ME = MException('AsyncRunner:Timeout', ...
                                'Operation timed out. The server may be busy — please try again.');
                            if ~isempty(onError); onError(ME); end
                            return;
                        end
                    end
                    return; % still pending — re-check on next tick
                end

                % All futures finished — stop polling
                stop(timerObj); delete(timerObj);

                % Surface the first error if any future errored before
                % its safeCall wrapper could run (closure serialization,
                % path issue, etc.).
                if ~isempty(firstError)
                    err = firstError;
                    try; if ~isempty(err.remotecause); err = err.remotecause{1}; end; catch; end
                    try; if ~isempty(err.cause); err = err.cause{1}; end; catch; end
                    Logger.error('AsyncRunner', 'runMany task error: %s', err.message);
                    if ~isempty(onError); onError(err); else
                        Logger.error('AsyncRunner', 'runMany failed (no handler): %s', err.message);
                    end
                    return;
                end

                % Collect results from safeCall wrappers.  If any
                % individual workFcn errored inside its safeCall, surface
                % that error via onError and abort delivery.
                results = cell(1, n);
                for i = 1:n
                    out = fetchOutputs(futures{i});
                    if isstruct(out) && isfield(out, 'ok')
                        if out.ok
                            results{i} = out.value;
                        else
                            Logger.error('AsyncRunner', ...
                                'runMany task #%d failed: %s', i, out.error.message);
                            if ~isempty(onError); onError(out.error); return; end
                            results{i} = [];
                        end
                    else
                        results{i} = out;
                    end
                end

                if ~isempty(onAllDone); onAllDone(results); end
            catch ME
                try stop(timerObj); delete(timerObj); catch; end
                Logger.error('AsyncRunner', 'pollFutures error: %s', ME.message);
                if ~isempty(onError); onError(ME); end
            end
        end

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
