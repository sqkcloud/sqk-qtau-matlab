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
    %   Requires MATLAB R2021b+ (backgroundPool).
    %   Falls back to synchronous execution on older releases.

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

            try
                pool = backgroundPool();
                future = parfeval(pool, workFcn, 1);
                afterEach(future, @(f) AsyncRunner.handleComplete(f, onDone, onError), 0);

                % Start a watchdog timer that cancels the future on timeout
                if timeoutSec > 0
                    wdog = timer('StartDelay', timeoutSec, ...
                        'TimerFcn', @(~,~) AsyncRunner.onTimeout(future, onError), ...
                        'StopFcn', @(src,~) delete(src));
                    % Store watchdog on future UserData so afterEach can stop it
                    future.UserData = wdog;
                    start(wdog);
                end
            catch
                % backgroundPool unavailable (R2020b or earlier) — run synchronously
                Logger.debug('AsyncRunner', 'backgroundPool unavailable — running synchronously');
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
    end

    methods (Static, Access = private)
        function handleComplete(future, onDone, onError)
            % Stop the watchdog timer if it exists
            try
                if isprop(future, 'UserData') && ~isempty(future.UserData)
                    wdog = future.UserData;
                    if isvalid(wdog); stop(wdog); delete(wdog); end
                    future.UserData = [];
                end
            catch; end

            try
                % Check for error — guard against missing Error property
                hasErr = false;
                try
                    hasErr = ~isempty(future.Error);
                catch; end

                if hasErr
                    err = future.Error;
                    AsyncRunner.runOnMainThread(@() AsyncRunner.invokeError(onError, err));
                else
                    result = fetchOutputs(future);
                    AsyncRunner.runOnMainThread(@() onDone(result));
                end
            catch ME
                Logger.error('AsyncRunner', 'handleComplete error: %s', ME.message);
                if ~isempty(onError)
                    AsyncRunner.runOnMainThread(@() AsyncRunner.invokeError(onError, ME));
                end
            end
        end

        function onTimeout(future, onError)
            % Cancel the future and invoke error callback with a timeout message.
            try
                if ~isempty(future) && isvalid(future) && strcmp(future.State, 'running')
                    cancel(future);
                    Logger.warn('AsyncRunner', 'Task timed out — cancelled');
                    ME = MException('AsyncRunner:Timeout', ...
                        'Operation timed out. The server may be busy — please try again.');
                    AsyncRunner.runOnMainThread(@() AsyncRunner.invokeError(onError, ME));
                end
            catch ex
                Logger.debug('AsyncRunner', 'onTimeout: %s', ex.message);
            end
        end

        function runOnMainThread(fcn)
            t = timer('StartDelay', 0, 'TimerFcn', @(~,~) fcn(), ...
                'StopFcn', @(src,~) delete(src));
            start(t);
        end

        function invokeError(onError, ME)
            if ~isempty(onError)
                onError(ME);
            else
                Logger.error('AsyncRunner', 'Async task failed: %s', ME.message);
            end
        end
    end
end
