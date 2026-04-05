classdef test_AppState < matlab.unittest.TestCase
    % test_AppState  Unit tests for the AppState session model.
    %
    % Run from the project root:
    %   >> runtests('tests/test_AppState')

    properties
        State
    end

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
            AppConfig.reload();
        end
    end

    methods (TestMethodSetup)
        function createFreshState(testCase)
            testCase.State = AppState();
        end
    end

    methods (Test)

        % ── Constructor defaults ─────────────────────────────────────────

        function testBaseUrlLoadedFromConfig(testCase)
            testCase.verifyGreaterThan(strlength(testCase.State.baseUrl), 0, ...
                'baseUrl should be loaded from config');
        end

        function testAuthTokenDefaultEmpty(testCase)
            testCase.verifyEqual(strlength(strtrim(testCase.State.authToken)), 0, ...
                'authToken should default to empty');
        end

        function testTokenTypeDefaultBearer(testCase)
            testCase.verifyEqual(char(testCase.State.tokenType), 'Bearer');
        end

        function testDefaultProjectIdEmpty(testCase)
            testCase.verifyEqual(strlength(strtrim(testCase.State.currentProjectId)), 0);
        end

        function testDefaultCircuitIdEmpty(testCase)
            testCase.verifyEqual(strlength(strtrim(testCase.State.selectedCircuitId)), 0);
        end

        function testDefaultJobIdEmpty(testCase)
            testCase.verifyEqual(strlength(strtrim(testCase.State.selectedJobId)), 0);
        end

        function testDefaultShots(testCase)
            testCase.verifyEqual(testCase.State.defaultShots, 4096);
        end

        function testDefaultOptimization(testCase)
            testCase.verifyEqual(testCase.State.defaultOptimization, 3);
        end

        function testDefaultTimeout(testCase)
            testCase.verifyEqual(testCase.State.defaultTimeout, 120);
        end

        function testBenchmarkShotsDefault(testCase)
            testCase.verifyEqual(testCase.State.benchmarkShots, 4096);
        end

        function testBenchmarkOptLevelDefault(testCase)
            testCase.verifyEqual(testCase.State.benchmarkOptLevel, 3);
        end

        % ── isAuthenticated ──────────────────────────────────────────────

        function testNotAuthenticatedByDefault(testCase)
            testCase.verifyFalse(testCase.State.isAuthenticated(), ...
                'New AppState should not be authenticated');
        end

        function testIsAuthenticatedAfterSettingToken(testCase)
            testCase.State.authToken = "test_token_abc";
            testCase.verifyTrue(testCase.State.isAuthenticated(), ...
                'Should be authenticated after setting a token');
        end

        function testNotAuthenticatedWithWhitespaceToken(testCase)
            testCase.State.authToken = "   ";
            testCase.verifyFalse(testCase.State.isAuthenticated(), ...
                'Whitespace-only token should not count as authenticated');
        end

        % ── hasProject ───────────────────────────────────────────────────

        function testNoProjectByDefault(testCase)
            testCase.verifyFalse(testCase.State.hasProject());
        end

        function testHasProjectAfterSetting(testCase)
            testCase.State.currentProjectId = "proj_123";
            testCase.verifyTrue(testCase.State.hasProject());
        end

        % ── hasCircuit ───────────────────────────────────────────────────

        function testNoCircuitByDefault(testCase)
            testCase.verifyFalse(testCase.State.hasCircuit());
        end

        function testHasCircuitAfterSetting(testCase)
            testCase.State.selectedCircuitId = "circ_456";
            testCase.verifyTrue(testCase.State.hasCircuit());
        end

        % ── hasJob ───────────────────────────────────────────────────────

        function testNoJobByDefault(testCase)
            testCase.verifyFalse(testCase.State.hasJob());
        end

        function testHasJobAfterSetting(testCase)
            testCase.State.selectedJobId = "job_789";
            testCase.verifyTrue(testCase.State.hasJob());
        end

        % ── bearerHeader ─────────────────────────────────────────────────

        function testBearerHeaderFormat(testCase)
            testCase.State.authToken = "my_tok";
            hdr = testCase.State.bearerHeader();
            testCase.verifyEqual(hdr, 'Bearer my_tok');
        end

        function testBearerHeaderEmptyToken(testCase)
            hdr = testCase.State.bearerHeader();
            testCase.verifyEqual(hdr, 'Bearer ');
        end

        % ── resetPipeline ────────────────────────────────────────────────

        function testResetPipelineClearsIdsButKeepsAuth(testCase)
            testCase.State.authToken          = "keep_this";
            testCase.State.currentUser        = "alice";
            testCase.State.selectedFile       = "circuit.qasm";
            testCase.State.selectedCircuitId  = "c1";
            testCase.State.selectedCircuitName = "My Circuit";
            testCase.State.selectedBackend    = "ibm_brisbane";
            testCase.State.backupBackend      = "ibm_osaka";
            testCase.State.selectedJobId      = "j1";
            testCase.State.predictionId       = "pred1";
            testCase.State.reportId           = "rep1";

            testCase.State.resetPipeline();

            % Auth should survive
            testCase.verifyEqual(char(testCase.State.authToken), 'keep_this', ...
                'resetPipeline should not clear authToken');
            testCase.verifyEqual(char(testCase.State.currentUser), 'alice', ...
                'resetPipeline should not clear currentUser');

            % Pipeline IDs should be cleared
            testCase.verifyEqual(strlength(strtrim(testCase.State.selectedFile)), 0);
            testCase.verifyEqual(strlength(strtrim(testCase.State.selectedCircuitId)), 0);
            testCase.verifyEqual(strlength(strtrim(testCase.State.selectedCircuitName)), 0);
            testCase.verifyEqual(strlength(strtrim(testCase.State.selectedBackend)), 0);
            testCase.verifyEqual(strlength(strtrim(testCase.State.backupBackend)), 0);
            testCase.verifyEqual(strlength(strtrim(testCase.State.selectedJobId)), 0);
            testCase.verifyEqual(strlength(strtrim(testCase.State.predictionId)), 0);
            testCase.verifyEqual(strlength(strtrim(testCase.State.reportId)), 0);
        end

        % ── Handle semantics ─────────────────────────────────────────────

        function testAppStateIsHandleClass(testCase)
            testCase.verifyTrue(isa(testCase.State, 'handle'), ...
                'AppState should be a handle class');
        end

        function testSharedReference(testCase)
            ref = testCase.State;
            ref.authToken = "shared_tok";
            testCase.verifyEqual(char(testCase.State.authToken), 'shared_tok', ...
                'Handle semantics: modifying ref should modify original');
        end

    end
end
