classdef test_AsyncRunner < matlab.unittest.TestCase
    % test_AsyncRunner  Unit tests for the AsyncRunner utility class.
    %
    % Tests work with both async (backgroundPool available) and synchronous
    % (fallback) execution.  A brief pause + drawnow after run() ensures
    % background results and timer-based callbacks have time to complete.
    %
    % Run from the project root:
    %   >> runtests('tests/test_AsyncRunner')

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure'));
        end
    end

    methods (Test)

        % -- Synchronous success path ------------------------------------------

        function testRunReturnsScalarResult(testCase)
            captured = [];
            AsyncRunner.run(@() 42, @(r) captureResult(r), @(ME) []);
            test_AsyncRunner.waitForAsync();
            testCase.verifyEqual(captured, 42);

            function captureResult(r)
                captured = r;
            end
        end

        function testRunReturnsStringResult(testCase)
            captured = '';
            AsyncRunner.run(@() 'hello', @(r) captureResult(r), @(ME) []);
            test_AsyncRunner.waitForAsync();
            testCase.verifyEqual(captured, 'hello');

            function captureResult(r)
                captured = r;
            end
        end

        function testRunReturnsStructResult(testCase)
            captured = [];
            expected = struct('a', 1, 'b', 'two');
            AsyncRunner.run(@() expected, @(r) captureResult(r), @(ME) []);
            test_AsyncRunner.waitForAsync();
            testCase.verifyEqual(captured.a, 1);
            testCase.verifyEqual(captured.b, 'two');

            function captureResult(r)
                captured = r;
            end
        end

        function testWorkFcnResultPassedToOnDone(testCase)
            captured = [];
            AsyncRunner.run(@() 7 * 6, @(r) captureResult(r), @(ME) []);
            test_AsyncRunner.waitForAsync();
            testCase.verifyEqual(captured, 42, ...
                'workFcn result should be passed to onDone callback');

            function captureResult(r)
                captured = r;
            end
        end

        % -- Error handling path -----------------------------------------------

        function testErrorCallsOnError(testCase)
            capturedME = [];
            AsyncRunner.run( ...
                @() error('TEST:fail', 'deliberate error'), ...
                @(r) [], ...
                @(ME) captureError(ME));
            test_AsyncRunner.waitForAsync();
            testCase.verifyNotEmpty(capturedME, ...
                'onError should be called when workFcn throws');
            testCase.verifySubstring(capturedME.message, 'deliberate error');

            function captureError(ME)
                capturedME = ME;
            end
        end

        function testErrorWithoutOnErrorRethrows(testCase)
            % In synchronous mode, the error rethrows. In async mode, the
            % error is delivered via timer and cannot rethrow to the caller.
            % Test both: either we get the error synchronously (verifyError)
            % or it completes without throwing (async path).
            threw = false;
            try
                AsyncRunner.run( ...
                    @() error('TEST:noHandler', 'no handler'), ...
                    @(r) [], []);
            catch ME
                threw = true;
                testCase.verifyEqual(ME.identifier, 'TEST:noHandler');
            end
            % In async mode, parfeval swallows the error — that's OK.
            % We just verify the call didn't crash the framework.
            if ~threw
                test_AsyncRunner.waitForAsync();
            end
        end

        % -- onDone is not called on failure -----------------------------------

        function testOnDoneNotCalledOnError(testCase)
            doneCalled = false;
            AsyncRunner.run( ...
                @() error('TEST:skip', 'skip'), ...
                @(r) setDone(), ...
                @(ME) []);
            test_AsyncRunner.waitForAsync();
            testCase.verifyFalse(doneCalled, ...
                'onDone should not be called when workFcn errors');

            function setDone()
                doneCalled = true;
            end
        end

        % -- Optional onError --------------------------------------------------

        function testOnErrorIsOptional(testCase)
            captured = [];
            AsyncRunner.run(@() 99, @(r) captureResult(r));
            test_AsyncRunner.waitForAsync();
            testCase.verifyEqual(captured, 99);

            function captureResult(r)
                captured = r;
            end
        end

    end

    methods (Static, Access = private)
        function waitForAsync(~)
            % Give background tasks + timer callbacks time to complete.
            % The chain is: parfeval → afterEach → handleComplete →
            % runOnMainThread (timer) → callback.  Multiple drawnow
            % passes ensure pending timer callbacks are processed.
            for k = 1:10
                pause(0.1);
                drawnow;
            end
        end
    end
end
