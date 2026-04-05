classdef test_JsonHelper < matlab.unittest.TestCase
    % test_JsonHelper  Unit tests for the JsonHelper static utility class.
    %
    % Run from the project root:
    %   >> runtests('tests/test_JsonHelper')

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
        end
    end

    methods (Test)

        % ── pick tests ───────────────────────────────────────────────────

        function testPickSimpleField(testCase)
            data = struct('name', 'Alice');
            val  = JsonHelper.pick(data, {'name'});
            testCase.verifyEqual(char(val), 'Alice', ...
                'pick should return value for a simple field');
        end

        function testPickDottedPath(testCase)
            inner = struct('access_token', 'tok123');
            data  = struct('data', inner);
            val   = JsonHelper.pick(data, {'data.access_token'});
            testCase.verifyEqual(char(val), 'tok123', ...
                'pick should walk a dotted path');
        end

        function testPickFallbackChain(testCase)
            data = struct('alt_id', 'xyz');
            val  = JsonHelper.pick(data, {'id', 'alt_id'});
            testCase.verifyEqual(char(val), 'xyz', ...
                'pick should fall through to the second path when the first is missing');
        end

        function testPickReturnsEmptyForMissing(testCase)
            data = struct('foo', 'bar');
            val  = JsonHelper.pick(data, {'nonexistent', 'also_missing'});
            testCase.verifyEqual(strlength(strtrim(string(val))), 0, ...
                'pick should return empty string when no paths match');
        end

        function testPickNumericValue(testCase)
            data = struct('count', 42);
            val  = JsonHelper.pick(data, {'count'});
            testCase.verifyEqual(char(val), '42', ...
                'pick should convert numeric values to string');
        end

        function testPickOnJsonString(testCase)
            jsonStr = '{"token": "abc"}';
            val = JsonHelper.pick(jsonStr, {'token'});
            testCase.verifyEqual(char(val), 'abc', ...
                'pick should decode a JSON string input');
        end

        % ── pickOne tests ────────────────────────────────────────────────

        function testPickOneSimple(testCase)
            data = struct('status', 'ok');
            val  = JsonHelper.pickOne(data, "status");
            testCase.verifyEqual(char(val), 'ok');
        end

        function testPickOneMissingField(testCase)
            data = struct('a', 1);
            val  = JsonHelper.pickOne(data, "b");
            testCase.verifyEqual(char(val), '', ...
                'pickOne should return empty string for missing field');
        end

        % ── toDouble tests ───────────────────────────────────────────────

        function testToDoubleFromNumber(testCase)
            d = JsonHelper.toDouble(3.14);
            testCase.verifyEqual(d, 3.14, 'AbsTol', 1e-10);
        end

        function testToDoubleFromString(testCase)
            d = JsonHelper.toDouble("42");
            testCase.verifyEqual(d, 42);
        end

        function testToDoubleFromChar(testCase)
            d = JsonHelper.toDouble('7.5');
            testCase.verifyEqual(d, 7.5, 'AbsTol', 1e-10);
        end

        function testToDoubleFromNonNumericReturnsZero(testCase)
            d = JsonHelper.toDouble("not a number");
            testCase.verifyEqual(d, 0, ...
                'toDouble should return 0 for non-numeric strings');
        end

        function testToDoubleFromEmptyStringReturnsZero(testCase)
            d = JsonHelper.toDouble("");
            testCase.verifyEqual(d, 0);
        end

        % ── extractList tests ────────────────────────────────────────────

        function testExtractListReturnsArray(testCase)
            items = [struct('id', 1), struct('id', 2)];
            data  = struct('projects', items);
            result = JsonHelper.extractList(data, 'projects');
            testCase.verifyEqual(numel(result), 2);
        end

        function testExtractListMissingFieldReturnsEmpty(testCase)
            data   = struct('other', 'value');
            result = JsonHelper.extractList(data, 'nonexistent');
            testCase.verifyTrue(isempty(result));
        end

        function testExtractListFromJsonString(testCase)
            jsonStr = '{"items": [{"x": 1}, {"x": 2}]}';
            result  = JsonHelper.extractList(jsonStr, 'items');
            testCase.verifyEqual(numel(result), 2);
        end

        % ── pretty tests ─────────────────────────────────────────────────

        function testPrettyStruct(testCase)
            data = struct('key', 'value');
            out  = JsonHelper.pretty(data);
            testCase.verifyClass(out, 'char');
            testCase.verifyTrue(contains(out, 'key'), ...
                'pretty of struct should contain field name');
        end

        function testPrettyString(testCase)
            out = JsonHelper.pretty("hello world");
            testCase.verifyEqual(out, 'hello world');
        end

        function testPrettyChar(testCase)
            out = JsonHelper.pretty('simple text');
            testCase.verifyEqual(out, 'simple text');
        end

        function testPrettyJsonString(testCase)
            out = JsonHelper.pretty('{"a": 1}');
            testCase.verifyClass(out, 'char');
            testCase.verifyTrue(contains(out, 'a'), ...
                'pretty should decode JSON string input');
        end

        % ── decodeIfJson tests ───────────────────────────────────────────

        function testDecodeIfJsonObject(testCase)
            result = JsonHelper.decodeIfJson('{"x": 10}');
            testCase.verifyTrue(isstruct(result));
            testCase.verifyEqual(result.x, 10);
        end

        function testDecodeIfJsonArray(testCase)
            result = JsonHelper.decodeIfJson('[1, 2, 3]');
            testCase.verifyEqual(numel(result), 3);
        end

        function testDecodeIfJsonPlainText(testCase)
            result = JsonHelper.decodeIfJson('not json');
            testCase.verifyEqual(result, 'not json', ...
                'Plain text should pass through unchanged');
        end

        function testDecodeIfJsonAlreadyStruct(testCase)
            s = struct('a', 1);
            result = JsonHelper.decodeIfJson(s);
            testCase.verifyTrue(isstruct(result));
            testCase.verifyEqual(result.a, 1);
        end

        % ── safeField tests ──────────────────────────────────────────────

        function testSafeFieldPresent(testCase)
            s = struct('name', 'test');
            val = JsonHelper.safeField(s, 'name', 'default');
            testCase.verifyEqual(val, 'test');
        end

        function testSafeFieldMissing(testCase)
            s = struct('name', 'test');
            val = JsonHelper.safeField(s, 'missing', 'default');
            testCase.verifyEqual(val, 'default');
        end

        function testSafeFieldNotStruct(testCase)
            val = JsonHelper.safeField(42, 'field', 'fallback');
            testCase.verifyEqual(val, 'fallback');
        end

        % ── asList tests ─────────────────────────────────────────────────

        function testAsListWithStruct(testCase)
            s = struct('a', 1);
            items = JsonHelper.asList(s);
            testCase.verifyTrue(isstruct(items));
        end

        function testAsListWithEmptyReturnsEmpty(testCase)
            items = JsonHelper.asList(42);
            testCase.verifyTrue(isempty(items));
        end

        % ── DTO row mapper smoke tests ───────────────────────────────────

        function testProjectsToRowsEmpty(testCase)
            [rows, ids] = JsonHelper.projectsToRows(struct());
            testCase.verifyTrue(isempty(rows) || size(rows, 1) == 0);
            testCase.verifyTrue(isempty(ids));
        end

        function testProjectsToRowsWithData(testCase)
            p1 = struct('project_id', 'p1', 'name', 'Proj1', ...
                'tags', {{'a','b'}}, 'member_count', '3', ...
                'created_at', '2025-01-01', 'description', 'desc');
            data = struct('projects', p1);
            [rows, ids] = JsonHelper.projectsToRows(data);
            testCase.verifyEqual(size(rows, 1), 1, 'Should have 1 row');
            testCase.verifyEqual(size(rows, 2), 5, 'Should have 5 columns');
            testCase.verifyEqual(ids{1}, 'p1');
            testCase.verifyEqual(rows{1,1}, 'Proj1');
        end

        function testBackendsToRowsEmpty(testCase)
            rows = JsonHelper.backendsToRows(struct());
            testCase.verifyTrue(isempty(rows) || size(rows, 1) == 0);
        end

        function testJobsToRowsEmpty(testCase)
            rows = JsonHelper.jobsToRows(struct());
            testCase.verifyTrue(isempty(rows) || size(rows, 1) == 0);
        end

        function testResultsToRowsEmpty(testCase)
            rows = JsonHelper.resultsToRows(struct());
            testCase.verifyTrue(isempty(rows) || size(rows, 1) == 0);
        end

        function testBenchmarkStrategyToRowsEmpty(testCase)
            rows = JsonHelper.benchmarkStrategyToRows(struct());
            testCase.verifyTrue(isempty(rows) || size(rows, 1) == 0);
        end

        function testPredictionToLinesEmpty(testCase)
            lines = JsonHelper.predictionToLines(struct());
            testCase.verifyClass(lines, 'cell');
        end

        function testPredictionToLinesWithData(testCase)
            data = struct('predicted_fidelity', '0.95', ...
                'success_probability', '0.90', ...
                'queue_time', '5m', ...
                'runtime', '10s');
            lines = JsonHelper.predictionToLines(data);
            testCase.verifyGreaterThanOrEqual(numel(lines), 4);
            testCase.verifyTrue(contains(lines{1}, '0.95'));
        end

    end
end
