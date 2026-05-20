classdef test_Logger < matlab.unittest.TestCase
    % test_Logger  Unit tests for the Logger static utility class.
    %
    % Run from the project root:
    %   >> runtests('tests/test_Logger')

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
        end
    end

    methods (TestMethodSetup)
        function resetLogLevel(~)
            % Logger.currentLevel is a persistent — state leaks between
            % tests. Without this reset, alphabetically-earlier tests
            % that raise the level (e.g. testDebugSuppressedAtInfoLevel
            % → INFO) silently suppress later tests that exercise
            % Logger.debug output (e.g. testLogOutputUppercasesLevel).
            Logger.setLevel('DEBUG');
        end
    end

    methods (Test)

        % ── Core log method ──────────────────────────────────────────────

        function testLogDoesNotThrow(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.log('INFO', 'TestCat', 'hello %s', 'world'));
        end

        function testLogWithoutVarargs(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.log('INFO', 'TestCat', 'simple message'));
        end

        % ── Level convenience methods ────────────────────────────────────

        function testInfoDoesNotThrow(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.info('TestCat', 'info message'));
        end

        function testInfoWithFormat(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.info('TestCat', 'count: %d', 42));
        end

        function testWarnDoesNotThrow(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.warn('TestCat', 'warn message'));
        end

        function testWarnWithFormat(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.warn('TestCat', 'warning: %s at line %d', 'oops', 10));
        end

        function testErrorDoesNotThrow(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.error('TestCat', 'error message'));
        end

        function testErrorWithFormat(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.error('TestCat', 'failed: %s', 'reason'));
        end

        function testDebugDoesNotThrow(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.debug('TestCat', 'debug message'));
        end

        function testDebugWithFormat(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.debug('TestCat', 'value=%d', 99));
        end

        % ── HTTP convenience methods ─────────────────────────────────────

        function testHttpDoesNotThrow(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.http('GET', 'http://example.com/api'));
        end

        function testHttpResponseDoesNotThrow(testCase)
            testCase.verifyWarningFree( ...
                @() Logger.httpResponse('POST', 'http://example.com/api', '200 OK'));
        end

        % ── Output format validation ─────────────────────────────────────

        function testLogOutputContainsTimestamp(testCase)
            % Capture stdout and verify the log line format
            output = evalc("Logger.info('FmtTest', 'hello')");
            testCase.verifyTrue(contains(output, '['), ...
                'Log output should contain bracket-delimited timestamp');
            testCase.verifyTrue(contains(output, 'INFO'), ...
                'Log output should contain the level string');
            testCase.verifyTrue(contains(output, 'FmtTest'), ...
                'Log output should contain the category');
            testCase.verifyTrue(contains(output, 'hello'), ...
                'Log output should contain the message');
        end

        function testLogOutputUppercasesLevel(testCase)
            output = evalc("Logger.debug('Cat', 'msg')");
            testCase.verifyTrue(contains(output, 'DEBUG'), ...
                'Level should be uppercased in output');
        end

        function testLogWithMultipleVarargs(testCase)
            output = evalc("Logger.info('Test', 'a=%d b=%s', 1, 'two')");
            testCase.verifyTrue(contains(output, 'a=1'), ...
                'First vararg should be formatted');
            testCase.verifyTrue(contains(output, 'b=two'), ...
                'Second vararg should be formatted');
        end

        % ── Log-level filtering ──────────────────────────────────────────

        function testSetAndGetLevel(testCase)
            Logger.setLevel('WARN');
            testCase.verifyEqual(Logger.getLevel(), 'WARN');
            Logger.setLevel('DEBUG');  % reset
        end

        function testDebugSuppressedAtInfoLevel(testCase)
            Logger.setLevel('INFO');
            output = evalc("Logger.debug('Test', 'should be hidden')");
            testCase.verifyTrue(isempty(strtrim(output)), ...
                'DEBUG messages should be suppressed when level is INFO');
            Logger.setLevel('DEBUG');
        end

        function testInfoShownAtInfoLevel(testCase)
            Logger.setLevel('INFO');
            output = evalc("Logger.info('Test', 'visible')");
            testCase.verifyTrue(contains(output, 'visible'), ...
                'INFO messages should show when level is INFO');
            Logger.setLevel('DEBUG');
        end

        function testErrorAlwaysShown(testCase)
            Logger.setLevel('ERROR');
            output = evalc("Logger.error('Test', 'critical')");
            testCase.verifyTrue(contains(output, 'critical'), ...
                'ERROR messages should always show');
            Logger.setLevel('DEBUG');
        end

        function testWarnSuppressedAtErrorLevel(testCase)
            Logger.setLevel('ERROR');
            output = evalc("Logger.warn('Test', 'should hide')");
            testCase.verifyTrue(isempty(strtrim(output)), ...
                'WARN messages should be suppressed when level is ERROR');
            Logger.setLevel('DEBUG');
        end

        % ── Token redaction ──────────────────────────────────────────────

        function testRedactBearerToken(testCase)
            out = Logger.redact('Bearer abc123xyz');
            testCase.verifyEqual(out, 'Bearer ***');
        end

        function testRedactAuthorizationHeader(testCase)
            out = Logger.redact('Authorization: Bearer secrettoken');
            testCase.verifyEqual(out, 'Authorization: Bearer ***');
        end

        function testRedactQueryParamToken(testCase)
            out = Logger.redact('GET /api/x?access_token=zzz&foo=1');
            testCase.verifyTrue(contains(out, 'access_token=***'), ...
                'access_token query param value should be masked');
            testCase.verifyTrue(contains(out, 'foo=1'), ...
                'non-credential params must be preserved');
        end

        function testRedactPreservesSafeText(testCase)
            in  = 'GET /api/circuits — 12 rows';
            out = Logger.redact(in);
            testCase.verifyEqual(out, in);
        end

        function testLogOutputRedactsBearerToken(testCase)
            output = evalc("Logger.info('Test', 'Authorization: Bearer leakme')");
            testCase.verifyFalse(contains(output, 'leakme'), ...
                'Bearer token must not appear in log output');
            testCase.verifyTrue(contains(output, 'Bearer ***'), ...
                'Bearer should be replaced with ***');
        end

    end
end
