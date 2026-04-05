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
    %   Requires MATLAB R2021b+ (backgroundPool).
    %   Falls back to synchronous execution on older releases.

    methods (Static)

        function future = run(workFcn, onDone, onError)
            % RUN  Execute workFcn asynchronously; call onDone(result) or
            %      onError(MException) on completion.
            %
            %   workFcn  — @() expression returning one output
            %   onDone   — @(result) callback on success
            %   onError  — @(ME) callback on failure  (optional)
            if nargin < 3; onError = []; end

            try
                pool = backgroundPool();
                future = parfeval(pool, workFcn, 1);
                afterEach(future, @(f) AsyncRunner.handleComplete(f, onDone, onError), 0);
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
            try
                if ~isempty(future.Error)
                    if ~isempty(onError)
                        onError(future.Error);
                    else
                        Logger.error('AsyncRunner', 'Async task failed: %s', future.Error.message);
                    end
                else
                    result = fetchOutputs(future);
                    onDone(result);
                end
            catch ME
                Logger.error('AsyncRunner', 'handleComplete error: %s', ME.message);
                if ~isempty(onError)
                    onError(ME);
                end
            end
        end
    end
end
