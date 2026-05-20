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

        % ── pickNumeric tests ────────────────────────────────────────────
        function testPickNumericSinglePath(testCase)
            data = struct('shots', 4096);
            val = JsonHelper.pickNumeric(data, 'shots', NaN);
            testCase.verifyEqual(val, 4096, ...
                'pickNumeric should resolve a simple numeric field');
        end

        function testPickNumericFallbackChain(testCase)
            data = struct('measured_fidelity', 0.97);
            val = JsonHelper.pickNumeric(data, ...
                {'estimated_fidelity','measured_fidelity','fidelity'}, NaN);
            testCase.verifyEqual(val, 0.97, ...
                'pickNumeric should fall through to the first matching path');
        end

        function testPickNumericMixedDotFallbackDoesNotError(testCase)
            % Regression: previously split(["a","features.b"], '.') threw
            % "Element 2 of the text contains 1 matches while the previous
            % elements have 0", aborting ResultsViewModel.applyHeroAndKpis.
            data = struct('features', struct('two_qubit_error_impact', 0.123));
            val = JsonHelper.pickNumeric(data, ...
                {'two_qubit_error_impact','features.two_qubit_error_impact'}, NaN);
            testCase.verifyEqual(val, 0.123, ...
                'pickNumeric must walk a dotted fallback path without crashing on mixed-dot chains');
        end

        function testPickNumericMissingReturnsDefault(testCase)
            data = struct('foo', 'bar');
            val = JsonHelper.pickNumeric(data, ...
                {'nonexistent','also_missing'}, -1);
            testCase.verifyEqual(val, -1, ...
                'pickNumeric should return the supplied default when no path matches');
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

        function testBackendsToRowsEmptyArrayInEnvelope(testCase)
            % Regression: envelope with empty `backends` must NOT produce a
            % garbage row from the response wrapped as a single item.
            data = struct('backends', [], 'project_id', 'p1');
            rows = JsonHelper.backendsToRows(data);
            testCase.verifyEqual(size(rows, 1), 0);
        end

        function testJobsToRowsEmpty(testCase)
            rows = JsonHelper.jobsToRows(struct());
            testCase.verifyTrue(isempty(rows) || size(rows, 1) == 0);
        end

        function testJobsToRowsEmptyArrayInEnvelope(testCase)
            data = struct('jobs', [], 'project_id', 'p1');
            rows = JsonHelper.jobsToRows(data);
            testCase.verifyEqual(size(rows, 1), 0);
        end

        function testActivityToRowsEmptyArrayInEnvelope(testCase)
            data = struct('recent_activity', [], 'project_id', 'p1');
            rows = JsonHelper.activityToRows(data);
            testCase.verifyEqual(size(rows, 1), 0);
        end

        function testExtractListSafeReturnsListWhenPresent(testCase)
            s1 = struct('name', 'a'); s2 = struct('name', 'b');
            data = struct('items', [s1 s2], 'envelope_field', 'x');
            items = JsonHelper.extractListSafe(data, 'items');
            testCase.verifyEqual(numel(items), 2);
        end

        function testExtractListSafeReturnsEmptyForEmptyArray(testCase)
            % This is the bug guard: must return [] not the envelope.
            data = struct('items', [], 'envelope_field', 'x');
            items = JsonHelper.extractListSafe(data, 'items');
            testCase.verifyTrue(isempty(items));
        end

        function testExtractListSafeReturnsEmptyForMissingField(testCase)
            data = struct('other_field', 'x');
            items = JsonHelper.extractListSafe(data, 'items');
            testCase.verifyTrue(isempty(items));
        end

        function testResultsToRowsEmpty(testCase)
            rows = JsonHelper.resultsToRows(struct());
            testCase.verifyTrue(isempty(rows) || size(rows, 1) == 0);
        end

        function testBenchmarkStrategyToRowsEmpty(testCase)
            rows = JsonHelper.benchmarkStrategyToRows(struct());
            testCase.verifyTrue(isempty(rows) || size(rows, 1) == 0);
        end

        function testBenchmarkStrategyToRowsEmptyStrategiesArray(testCase)
            % Regression: previously returned 1 garbage row of zeros when
            % the API responded with `{strategies: [], circuit_id: ..., backend_name: ...}`
            % because the asList fallback wrapped the envelope as one item.
            data = struct( ...
                'strategies',   [], ...
                'circuit_id',   'c1', ...
                'backend_name', 'ibm_boston');
            rows = JsonHelper.benchmarkStrategyToRows(data);
            testCase.verifyEqual(size(rows, 1), 0, ...
                'Empty strategies array must yield zero rows, not a garbage row');
        end

        function testBenchmarkStrategyToRowsHappyPath(testCase)
            % Backend response shape from sqk-qtau storyboard router.
            s1 = struct('name', 'level1_sabre', 'depth', 100, ...
                'two_qubit_gates', 40, 'predicted_fidelity', 0.92, ...
                'comment', 'opt_level=1');
            s2 = struct('name', 'level3_sabre', 'depth', 70, ...
                'two_qubit_gates', 28, 'predicted_fidelity', 0.96, ...
                'comment', 'opt_level=3');
            data = struct('strategies', [s1 s2], ...
                'circuit_id', 'c1', 'backend_name', 'ibm_boston');
            rows = JsonHelper.benchmarkStrategyToRows(data);
            testCase.verifyEqual(size(rows, 1), 2);
            testCase.verifyEqual(rows{1, 1}, 'level1_sabre');
            % Depth + 2Q-gate counts are int32 by design (see
            % JsonHelper.benchmarkStrategyToRows comments: uitable
            % otherwise renders '100' as '100.0000'). Match the class.
            testCase.verifyEqual(rows{1, 2}, int32(100));
            testCase.verifyEqual(rows{1, 3}, int32(40));
            testCase.verifyEqual(rows{2, 1}, 'level3_sabre');
            testCase.verifyEqual(rows{2, 4}, 0.96);
        end

        function testBenchmarkStrategyToRowsAcceptsBackendAfterFields(testCase)
            % The Python backend's PredictionService.optimize() actually
            % stores the post-transpile metrics under `*_after` keys.
            % StoryboardService maps them to the public names but tolerate
            % both forms here in case a direct caller passes the raw dict.
            s = struct('strategy_name', 'level2_sabre', ...
                'depth_after', 85, 'two_qubit_gates_after', 34, ...
                'predicted_fidelity', 0.94);
            data = struct('strategies', s, ...
                'circuit_id', 'c1', 'backend_name', 'b1');
            rows = JsonHelper.benchmarkStrategyToRows(data);
            testCase.verifyEqual(rows{1, 1}, 'level2_sabre');
            testCase.verifyEqual(rows{1, 2}, int32(85));
            testCase.verifyEqual(rows{1, 3}, int32(34));
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
