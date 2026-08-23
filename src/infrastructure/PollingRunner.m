classdef PollingRunner
    % PollingRunner  Wraps the "submit returns job_id, then poll
    %                 GET /api/.../{id} every N seconds until a terminal
    %                 state is reached" pattern used by the Quantum
    %                 Monte Carlo flow and reserved for future long-
    %                 running async endpoints (e.g. server-side resource
    %                 estimation, live mitigation A/B, multi-strategy
    %                 benchmark sweeps).
    %
    %   The existing inline implementation lives inside
    %   AnalysisViewModel.startQmcPoll / onQmcPollTick / stopQmcPoll
    %   (~80 lines, three nested methods). PollingRunner.start(opts)
    %   collapses that contract down to one call.
    %
    %   Relationship to AsyncRunner: a MATLAB timer schedules the poll
    %   cadence, but each individual poll GET is dispatched THROUGH
    %   AsyncRunner (parfeval worker) so a slow or hung backend can never
    %   block the UI thread. At most one poll is in flight at a time; a
    %   tick that fires while the previous GET is still running is
    %   skipped. Results are delivered back on the main thread, where the
    %   user-supplied isTerminal / onProgress / onDone callbacks run.
    %   (Earlier revisions ran the GET inline on the main thread on the
    %   assumption every poll is a fast ~200 ms round-trip; a degraded
    %   backend broke that assumption and froze the app for up to the
    %   request timeout on every tick, hence the async dispatch.)
    %
    %   Usage:
    %       ctx = PollingRunner.start(struct( ...
    %           'pollFcn',     @() qmcSvc.getAnalyzeJob(jobId, token), ...
    %           'isTerminal',  @(s) any(strcmp(char(s.status), ...
    %                                {'completed','failed','cancelled'})), ...
    %           'onProgress',  @(s) app.showLoading(formatProgress(s)), ...
    %           'onDone',      @(s) obj.routeTerminalState(s), ...
    %           'onError',     @(ME) obj.showError('QMC', ME), ...
    %           'intervalSec', 3, ...
    %           'timeoutSec',  3600, ...
    %           'name',        ['QmcPoll-' jobId]));
    %       % ... later, on cancel:
    %       PollingRunner.cancel(ctx);
    %
    %   Contract:
    %     - pollFcn is dispatched OFF the UI thread via AsyncRunner. Keep
    %       it a single HTTP GET that RETURNS the state struct — do NOT
    %       touch UI inside pollFcn (UI work belongs in onProgress /
    %       onDone, which run on the main thread).
    %     - isTerminal is called with the result of each successful poll.
    %       When it returns true, the timer is stopped, deleted, and
    %       onDone is fired with the same state object.
    %     - onProgress is fired on each successful NON-terminal poll.
    %       Use it to update a progress overlay or log line.
    %     - onError fires on:
    %         (a) timeout (timeoutSec exceeded with no terminal state),
    %             with a PollingRunner:Timeout MException.
    %         (b) stall (stallTimeoutSec elapsed with no SUCCESSFUL
    %             poll), with a PollingRunner:Stalled MException. This
    %             is what bounds a caller that disables the overall
    %             timeout (timeoutSec = 0) — without it an unreachable
    %             backend keeps the loop, its timer and its captured VM
    %             closures alive forever, and the owning
    %             BackgroundTaskManager entry never reaches a terminal
    %             state so it can never be evicted.
    %         (c) any unexpected error inside the tick itself (NOT
    %             pollFcn HTTP errors — those are treated as transient
    %             and logged at debug, so a single network blip doesn't
    %             abort the whole poll).
    %     - PollingRunner.cancel stops the cadence timer AND cancels the
    %       in-flight worker request, so a cancelled poll releases its
    %       pool slot immediately instead of squatting on it until the
    %       per-request timeout. Idempotent and safe to call on a ctx
    %       whose timer has already terminated (no-op).

    methods (Static)

        function ctx = start(opts)
            % start  Begin polling. Returns a ctx struct with the
            %   underlying MATLAB timer handle in .Timer so callers can
            %   cancel via PollingRunner.cancel(ctx).
            %
            %   Required opts fields:
            %     .pollFcn     — @() returning the state struct
            %     .isTerminal  — @(state) -> logical
            %     .onDone      — @(state) called once at terminal state
            %
            %   Optional opts fields (defaults in parens):
            %     .onError         — @(ME)         (silent if omitted)
            %     .onProgress      — @(state)      (noop if omitted)
            %     .intervalSec     — seconds       (3.0)
            %     .timeoutSec      — seconds total (3600; <=0 disables)
            %     .stallTimeoutSec — seconds since the last SUCCESSFUL
            %                        poll before giving up (600; <=0
            %                        disables)
            %     .pollTimeoutSec  — per-request cap (30)
            %     .name            — timer Name    ('PollingRunner')
            if ~isstruct(opts)
                error('PollingRunner:BadOpts', 'start expects an options struct');
            end
            mustHave = {'pollFcn','isTerminal','onDone'};
            for i = 1:numel(mustHave)
                if ~isfield(opts, mustHave{i}) || isempty(opts.(mustHave{i}))
                    error('PollingRunner:BadOpts', ...
                        'opts.%s is required', mustHave{i});
                end
            end
            if ~isfield(opts, 'onError')    || isempty(opts.onError);    opts.onError    = @(~) []; end
            if ~isfield(opts, 'onProgress') || isempty(opts.onProgress); opts.onProgress = @(~) []; end
            if ~isfield(opts, 'intervalSec')|| isempty(opts.intervalSec);opts.intervalSec= 3.0;     end
            if ~isfield(opts, 'timeoutSec') || isempty(opts.timeoutSec); opts.timeoutSec = 3600;    end
            if ~isfield(opts, 'stallTimeoutSec') || isempty(opts.stallTimeoutSec)
                opts.stallTimeoutSec = 600;
            end
            if ~isfield(opts, 'name')       || isempty(opts.name);       opts.name       = 'PollingRunner'; end

            t = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period',        double(opts.intervalSec), ...
                'StartDelay',    0, ...
                'BusyMode',      'drop', ...
                'Name',          char(opts.name), ...
                'UserData',      struct( ...
                    'startTic',  tic, ...
                    'lastOkTic', tic, ...
                    'inflight',  false, ...
                    'future',    []));
            t.TimerFcn = @(src,~) PollingRunner.tick(src, opts);
            start(t);
            ctx = struct('Timer', t);
        end

        function cancel(ctx)
            % cancel  Stop + delete the polling timer in ctx AND abort
            %   any in-flight poll request. Idempotent.
            try
                if isstruct(ctx) && isfield(ctx, 'Timer') ...
                        && ~isempty(ctx.Timer) && isvalid(ctx.Timer)
                    % Read UserData BEFORE deleting the timer — that's
                    % where the in-flight future handle lives.
                    ud = ctx.Timer.UserData;
                    stop(ctx.Timer);
                    delete(ctx.Timer);
                    PollingRunner.cancelInflight(ud);
                end
            catch
            end
        end

    end

    methods (Static, Access = private)

        function tick(timerObj, opts)
            % tick  One poll cadence. Enforces the overall timeout, then
            %   dispatches pollFcn OFF the UI thread via AsyncRunner so a
            %   slow/hung GET can't freeze the app. At most one poll is
            %   in flight; a tick arriving while the previous GET is
            %   still running is skipped. The success/error handlers run
            %   back on the main thread (AsyncRunner completion timer).
            nm = '';
            try
                nm = char(timerObj.Name);
                ud = timerObj.UserData;
                if opts.timeoutSec > 0 && toc(ud.startTic) > opts.timeoutSec
                    PollingRunner.stopTimer(timerObj);
                    PollingRunner.cancelInflight(ud);
                    opts.onError(MException('PollingRunner:Timeout', ...
                        'Polling exceeded %g seconds without reaching a terminal state.', ...
                        double(opts.timeoutSec)));
                    return;
                end

                % Stall guard. Transient GET failures never abort the
                % loop by design, so without this a permanently
                % unreachable backend polls forever — and a caller that
                % disabled timeoutSec would never reach a terminal
                % state at all. Measured from the last SUCCESSFUL poll,
                % so a long-but-healthy job is unaffected.
                if opts.stallTimeoutSec > 0 && toc(ud.lastOkTic) > opts.stallTimeoutSec
                    PollingRunner.stopTimer(timerObj);
                    PollingRunner.cancelInflight(ud);
                    opts.onError(MException('PollingRunner:Stalled', ...
                        ['No successful poll for %g seconds — giving up. ' ...
                         'The backend may be unreachable.'], ...
                        double(opts.stallTimeoutSec)));
                    return;
                end

                if ud.inflight
                    return;   % previous poll still running — skip this tick
                end
                ud.inflight = true;
                timerObj.UserData = ud;

                fut = AsyncRunner.run(opts.pollFcn, ...
                    @(state) PollingRunner.onPoll(timerObj, opts, state), ...
                    @(ME)    PollingRunner.onPollError(timerObj, ME), ...
                    PollingRunner.pollTimeout(opts));

                % Retain the future so cancel() can abort an in-flight
                % GET instead of leaving it to squat on a worker slot.
                % Re-check validity first: AsyncRunner falls back to a
                % synchronous call when no pool is available, in which
                % case onPoll already ran and may have deleted the timer.
                if isvalid(timerObj)
                    ud = timerObj.UserData;
                    ud.future = fut;
                    timerObj.UserData = ud;
                end
            catch ME
                PollingRunner.stopTimer(timerObj);
                Logger.error('PollingRunner', ...
                    'fatal tick error (%s): %s', nm, ME.message);
                opts.onError(ME);
            end
        end

        function onPoll(timerObj, opts, state)
            % onPoll  Main-thread success handler for one poll. Ignores
            %   the result if the timer was cancelled while the GET was
            %   in flight (a stale result after PollingRunner.cancel).
            if isempty(timerObj) || ~isvalid(timerObj); return; end
            nm = char(timerObj.Name);
            ud = timerObj.UserData;
            ud.inflight  = false;
            ud.future    = [];
            ud.lastOkTic = tic;     % resets the stall guard
            timerObj.UserData = ud;
            try
                if opts.isTerminal(state)
                    PollingRunner.stopTimer(timerObj);
                    opts.onDone(state);
                else
                    opts.onProgress(state);
                end
            catch ME
                PollingRunner.stopTimer(timerObj);
                Logger.error('PollingRunner', ...
                    'fatal onPoll error (%s): %s', nm, ME.message);
                opts.onError(ME);
            end
        end

        function onPollError(timerObj, ME)
            % onPollError  Transient GET failure (or per-poll timeout):
            %   free the in-flight slot and keep polling, matching the
            %   original "a single network blip doesn't abort" contract.
            if isempty(timerObj) || ~isvalid(timerObj); return; end
            ud = timerObj.UserData;
            ud.inflight = false;
            ud.future   = [];
            timerObj.UserData = ud;
            % lastOkTic is deliberately NOT reset here — consecutive
            % failures must accumulate toward the stall guard.
            Logger.debug('PollingRunner', ...
                'transient poll error (%s): %s', char(timerObj.Name), ME.message);
        end

        function cancelInflight(ud)
            % cancelInflight  Abort the parfeval future recorded in a
            %   timer's UserData, if one is still queued/running. Frees
            %   the worker slot immediately; AsyncRunner's own 50 ms
            %   completion poller then observes the cancelled state on
            %   its next tick and tears itself down. Tolerant of the
            %   synchronous-fallback case, where future is [].
            try
                if ~isstruct(ud) || ~isfield(ud, 'future') || isempty(ud.future)
                    return;
                end
                fut = ud.future;
                if ~isvalid(fut); return; end
                if any(strcmp(fut.State, {'queued', 'running'}))
                    cancel(fut);
                end
            catch
            end
        end

        function s = pollTimeout(opts)
            % pollTimeout  Per-request cap so a hung GET releases the
            %   in-flight slot (via onPollError) and the loop retries on
            %   the next tick instead of stalling forever. Defaults to
            %   30 s; override with opts.pollTimeoutSec.
            s = 30;
            if isfield(opts, 'pollTimeoutSec') && ~isempty(opts.pollTimeoutSec) ...
                    && opts.pollTimeoutSec > 0
                s = double(opts.pollTimeoutSec);
            end
        end

        function stopTimer(timerObj)
            % stopTimer  Stop + delete a timer, tolerant of an already
            %   invalid/deleted handle.
            try
                if ~isempty(timerObj) && isvalid(timerObj)
                    stop(timerObj); delete(timerObj);
                end
            catch
            end
        end

    end
end
