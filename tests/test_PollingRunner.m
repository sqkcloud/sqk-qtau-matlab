classdef test_PollingRunner < matlab.unittest.TestCase
    % test_PollingRunner  Unit tests for the async poll-loop wrapper.
    %
    % Covers terminal delivery, the stall guard that bounds a
    % permanently-failing poll, cancellation teardown, and the
    % "pollFcn must not capture the app" closure contract from
    % doc/workflow.md.
    %
    % Callbacks record into a containers.Map (a HANDLE) that is passed
    % into the wait helper by argument. Do not switch these to plain
    % locals + an anonymous predicate: an anonymous function snapshots
    % the variables it closes over, so the predicate would never observe
    % a callback that fires after it was created.
    %
    % Each poll GET is dispatched through AsyncRunner, so these tests
    % spin the event loop (pause + drawnow service timer callbacks)
    % rather than asserting immediately after start().
    %
    % Run from the project root:
    %   >> runtests('tests/test_PollingRunner')

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure'));
        end
    end

    methods (Test)

        % -- Terminal delivery --------------------------------------------------

        function testTerminalStateFiresOnDone(testCase)
            box = containers.Map();
            ctx = PollingRunner.start(struct( ...
                'pollFcn',     @() struct('status', 'completed'), ...
                'isTerminal',  @(s) strcmp(s.status, 'completed'), ...
                'onDone',      @(s)  test_PollingRunner.record(box, 'done', s), ...
                'onError',     @(ME) test_PollingRunner.record(box, 'error', ME), ...
                'intervalSec', 0.2, ...
                'timeoutSec',  0, ...
                'name',        'PollTest-done'));
            ok = test_PollingRunner.waitForKey(box, 'done', 30);
            PollingRunner.cancel(ctx);
            testCase.verifyTrue(ok, 'onDone never fired');
            testCase.verifyFalse(isKey(box, 'error'));
            testCase.verifyEqual(box('done').status, 'completed');
        end

        % -- Stall guard --------------------------------------------------------

        function testStallGuardBoundsAPermanentlyFailingPoll(testCase)
            % A poll whose GET always fails must not retry forever.
            % With no overall timeout (timeoutSec = 0, as the
            % circuit-cutting caller uses) the stall guard is the only
            % thing that turns an unreachable backend into a terminal
            % onError instead of an immortal 'running' task.
            box = containers.Map();
            ctx = PollingRunner.start(struct( ...
                'pollFcn',         @() error('PollTest:Down', 'backend unreachable'), ...
                'isTerminal',      @(~) false, ...
                'onDone',          @(s)  test_PollingRunner.record(box, 'done', s), ...
                'onError',         @(ME) test_PollingRunner.record(box, 'error', ME), ...
                'intervalSec',     0.2, ...
                'timeoutSec',      0, ...
                'stallTimeoutSec', 1, ...
                'name',            'PollTest-stall'));
            ok = test_PollingRunner.waitForKey(box, 'error', 30);
            PollingRunner.cancel(ctx);
            testCase.verifyTrue(ok, 'stall guard never fired onError');
            testCase.verifyEqual(box('error').identifier, 'PollingRunner:Stalled');
            testCase.verifyFalse(isKey(box, 'done'));
        end

        function testHealthyPollIsNotKilledByTheStallGuard(testCase)
            % The guard measures from the last SUCCESSFUL poll, so a
            % long-running-but-responsive job must survive well past
            % stallTimeoutSec without being aborted.
            box = containers.Map();
            ctx = PollingRunner.start(struct( ...
                'pollFcn',         @() struct('status', 'running'), ...
                'isTerminal',      @(~) false, ...
                'onDone',          @(s)  test_PollingRunner.record(box, 'done', s), ...
                'onProgress',      @(s)  test_PollingRunner.bump(box, 'polls'), ...
                'onError',         @(ME) test_PollingRunner.record(box, 'error', ME), ...
                'intervalSec',     0.2, ...
                'timeoutSec',      0, ...
                'stallTimeoutSec', 1, ...
                'name',            'PollTest-healthy'));
            % Run for ~3x the stall budget while every poll succeeds.
            t0 = tic;
            while toc(t0) < 3; pause(0.05); drawnow; end
            PollingRunner.cancel(ctx);
            testCase.verifyFalse(isKey(box, 'error'), ...
                'stall guard aborted a healthy poll');
            testCase.verifyTrue(isKey(box, 'polls') && box('polls') > 1, ...
                'expected repeated successful polls');
        end

        % -- Cancellation -------------------------------------------------------

        function testCancelStopsPollingAndIsIdempotent(testCase)
            box = containers.Map();
            ctx = PollingRunner.start(struct( ...
                'pollFcn',     @() struct('status', 'running'), ...
                'isTerminal',  @(~) false, ...
                'onDone',      @(~) [], ...
                'onProgress',  @(s) test_PollingRunner.bump(box, 'polls'), ...
                'intervalSec', 0.2, ...
                'timeoutSec',  0, ...
                'name',        'PollTest-cancel'));
            polled = test_PollingRunner.waitForKey(box, 'polls', 30);
            testCase.assertTrue(polled, 'poll loop never ran — test is vacuous');
            PollingRunner.cancel(ctx);
            PollingRunner.cancel(ctx);          % idempotent — must not throw
            testCase.verifyFalse(isvalid(ctx.Timer));
            settled = box('polls');
            for k = 1:10; pause(0.1); drawnow; end
            testCase.verifyEqual(box('polls'), settled, ...
                'polling continued after cancel');
        end

        % -- Closure contract ---------------------------------------------------

        function testPollFcnClosuresNeverCaptureTheApp(testCase)
            % doc/workflow.md:170 — AsyncRunner dispatches pollFcn onto a
            % parfeval worker, and a closure capturing QTAUWorkbenchApp
            % fails to deserialize there (uihtml / WebComponent is not on
            % the worker classpath). PollingRunner classifies that failure
            % as transient, so the loop would retry forever without ever
            % surfacing the error. Callers must hoist the token/service
            % into locals before building pollFcn.
            thisDir = fileparts(mfilename('fullpath'));
            vmDir   = fullfile(thisDir, '..', 'src', 'presentation', 'viewmodels');
            files   = dir(fullfile(vmDir, '*.m'));
            offenders = {};
            for i = 1:numel(files)
                lines = readlines(fullfile(files(i).folder, files(i).name));
                for k = 1:numel(lines)
                    ln = char(lines(k));
                    if ~contains(ln, '''pollFcn'''); continue; end
                    if contains(ln, 'app.') || contains(ln, 'App.')
                        offenders{end+1} = sprintf('%s:%d: %s', ...
                            files(i).name, k, strtrim(ln)); %#ok<AGROW>
                    end
                end
            end
            testCase.verifyEmpty(offenders, sprintf( ...
                'pollFcn closure captures the app (hoist to a local first):\n%s', ...
                strjoin(offenders, newline)));
        end

    end

    methods (Static, Access = private)
        function record(box, key, payload)
            box(key) = payload;
        end

        function bump(box, key)
            if isKey(box, key); box(key) = box(key) + 1; else; box(key) = 1; end
        end

        function ok = waitForKey(box, key, timeoutSec)
            % Spin the event loop until the callback records `key`, or
            % the budget runs out. pause + drawnow service the timer
            % callbacks that drive both the PollingRunner cadence and
            % AsyncRunner's completion poller.
            t0 = tic;
            ok = false;
            while toc(t0) < timeoutSec
                if isKey(box, key); ok = true; return; end
                pause(0.05);
                drawnow;
            end
        end
    end
end
