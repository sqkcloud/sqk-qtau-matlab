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
    %   Why not AsyncRunner? AsyncRunner dispatches a SINGLE workFcn on
    %   a parfeval worker and delivers ONE result. PollingRunner runs N
    %   identical GETs on the MAIN thread via a MATLAB timer, calling a
    %   user-supplied isTerminal predicate after each response to decide
    %   whether to stop. Each poll is a fast HTTP GET (~200 ms RTT), so
    %   firing it on the main thread is cheap; a parfeval worker would
    %   add serialization overhead with no benefit.
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
    %     - pollFcn runs synchronously on the main thread inside the
    %       timer's TimerFcn. Keep it FAST — a single HTTP GET.
    %     - isTerminal is called with the result of each successful poll.
    %       When it returns true, the timer is stopped, deleted, and
    %       onDone is fired with the same state object.
    %     - onProgress is fired on each successful NON-terminal poll.
    %       Use it to update a progress overlay or log line.
    %     - onError fires on:
    %         (a) timeout (timeoutSec exceeded with no terminal state),
    %             with a PollingRunner:Timeout MException.
    %         (b) any unexpected error inside the tick itself (NOT
    %             pollFcn HTTP errors — those are treated as transient
    %             and logged at debug, so a single network blip doesn't
    %             abort the whole poll).
    %     - PollingRunner.cancel is idempotent and safe to call on a
    %       ctx whose timer has already terminated (no-op).

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
            %     .onError     — @(ME)         (silent if omitted)
            %     .onProgress  — @(state)      (noop if omitted)
            %     .intervalSec — seconds       (3.0)
            %     .timeoutSec  — seconds total (3600; <=0 disables)
            %     .name        — timer Name    ('PollingRunner')
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
            if ~isfield(opts, 'name')       || isempty(opts.name);       opts.name       = 'PollingRunner'; end

            t = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period',        double(opts.intervalSec), ...
                'StartDelay',    0, ...
                'BusyMode',      'drop', ...
                'Name',          char(opts.name), ...
                'UserData',      tic);
            t.TimerFcn = @(src,~) PollingRunner.tick(src, opts);
            start(t);
            ctx = struct('Timer', t);
        end

        function cancel(ctx)
            % cancel  Stop + delete the polling timer in ctx. Idempotent.
            try
                if isstruct(ctx) && isfield(ctx, 'Timer') ...
                        && ~isempty(ctx.Timer) && isvalid(ctx.Timer)
                    stop(ctx.Timer);
                    delete(ctx.Timer);
                end
            catch
            end
        end

    end

    methods (Static, Access = private)

        function tick(timerObj, opts)
            % tick  One poll iteration. Bails on transient HTTP errors
            %   (logged at debug) so a single network blip doesn't abort
            %   the loop; stops on timeout (onError) or terminal state
            %   (onDone). Any fatal error inside the tick path itself
            %   (not from pollFcn) stops the timer and surfaces via
            %   onError so a misconfigured opts.isTerminal predicate
            %   doesn't spin forever.
            try
                if opts.timeoutSec > 0 && toc(timerObj.UserData) > opts.timeoutSec
                    try; stop(timerObj); delete(timerObj); catch; end
                    opts.onError(MException('PollingRunner:Timeout', ...
                        'Polling exceeded %g seconds without reaching a terminal state.', ...
                        double(opts.timeoutSec)));
                    return;
                end

                try
                    state = opts.pollFcn();
                catch ME
                    % Transient HTTP error — log + keep polling
                    Logger.debug('PollingRunner', ...
                        'transient poll error (%s): %s', char(timerObj.Name), ME.message);
                    return;
                end

                if opts.isTerminal(state)
                    try; stop(timerObj); delete(timerObj); catch; end
                    opts.onDone(state);
                    return;
                end

                opts.onProgress(state);
            catch ME
                try; stop(timerObj); delete(timerObj); catch; end
                Logger.error('PollingRunner', ...
                    'fatal tick error (%s): %s', char(timerObj.Name), ME.message);
                opts.onError(ME);
            end
        end

    end
end
