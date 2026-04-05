classdef test_AsyncRunner < matlab.unittest.TestCase
    % test_AsyncRunner  Unit tests for the AsyncRunner utility class.
    %
    % These tests exercise the synchronous fallback path so they work in
    % any MATLAB environment (with or without backgroundPool).
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
            result = [];
            AsyncRunner.run(@() 42, @(r) assignin('caller', 'result', r), @(ME) []);
            % The synchronous fallback calls onDone directly, so we use a
            % capture variable instead.
            captured = [];
            AsyncRunner.run(@() 42, @(r) captureResult(r), @(ME) []);
            testCase.verifyEqual(captured, 42);

            function captureResult(r)
                captured = r;
            end
        end

        function testRunReturnsStringResult(testCase)
            captured = '';
            AsyncRunner.run(@() 'hello', @(r) captureResult(r), @(ME) []);
            testCase.verifyEqual(captured, 'hello');

            function captureResult(r)
                captured = r;
            end
        end

        function testRunReturnsStructResult(testCase)
            captured = [];
            expected = struct('a', 1, 'b', 'two');
            AsyncRunner.run(@() expected, @(r) captureResult(r), @(ME) []);
            testCase.verifyEqual(captured.a, 1);
            testCase.verifyEqual(captured.b, 'two');

            function captureResult(r)
                captured = r;
            end
        end

        function testWorkFcnResultPassedToOnDone(testCase)
            captured = [];
            AsyncRunner.run(@() 7 * 6, @(r) captureResult(r), @(ME) []);
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
                @(r) testCase.verifyFail('onDone should not be called on error'), ...
                @(ME) captureError(ME));
            testCase.verifyNotEmpty(capturedME, ...
                'onError should be called when workFcn throws');
            testCase.verifyEqual(capturedME.identifier, 'TEST:fail');
            testCase.verifyTrue(contains(capturedME.message, 'deliberate error'));

            function captureError(ME)
                capturedME = ME;
            end
        end

        function testErrorWithoutOnErrorRethrows(testCase)
            testCase.verifyError( ...
                @() AsyncRunner.run( ...
                    @() error('TEST:noHandler', 'no handler'), ...
                    @(r) [], []), ...
                'TEST:noHandler');
        end

        % -- onDone is not called on failure -----------------------------------

        function testOnDoneNotCalledOnError(testCase)
            doneCalled = false;
            AsyncRunner.run( ...
                @() error('TEST:skip', 'skip'), ...
                @(r) setDone(), ...
                @(ME) []);
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
            testCase.verifyEqual(captured, 99);

            function captureResult(r)
                captured = r;
            end
        end

    end
end
