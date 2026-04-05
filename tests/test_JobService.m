classdef test_JobService < matlab.unittest.TestCase
    % test_JobService  Unit tests for the JobService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_JobService')

    properties
        Stub
        Service
    end

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'http'));
            addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
            addpath(fullfile(projectRoot, 'tests'));
        end
    end

    methods (TestMethodSetup)
        function createService(testCase)
            testCase.Stub = StubFastAPIClient();
            testCase.Service = JobService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorAcceptsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'JobService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'));
        end

        % ── submitJob ────────────────────────────────────────────────────

        function testSubmitJobPosts(testCase)
            payload = struct('circuit_id', 'c1', 'backend_name', 'ibm_brisbane', ...
                'shots', 4096, 'optimization_level', 3);
            testCase.Service.submitJob(payload, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/jobs/submit'));
        end

        function testSubmitJobForwardsPayload(testCase)
            payload = struct('circuit_id', 'c2', 'backend_name', 'be');
            testCase.Service.submitJob(payload, 'tok');
            testCase.verifyEqual(testCase.Stub.LastPayload.circuit_id, 'c2');
        end

        % ── listJobs ─────────────────────────────────────────────────────

        function testListJobsUsesGetAuth(testCase)
            testCase.Service.listJobs('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/jobs'));
        end

        function testListJobsDefaultPagination(testCase)
            testCase.Service.listJobs('tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'skip=0'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'limit=50'));
        end

        function testListJobsCustomPagination(testCase)
            testCase.Service.listJobs('tok', 20, 10);
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'skip=20'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'limit=10'));
        end

        % ── getJob ───────────────────────────────────────────────────────

        function testGetJobUsesJobId(testCase)
            testCase.Service.getJob('job_abc', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'job_abc'));
        end

        % ── getStatus ────────────────────────────────────────────────────

        function testGetStatusUsesCorrectEndpoint(testCase)
            testCase.Service.getStatus('job_xyz', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'job_xyz/status'));
        end

        % ── cancelJob ────────────────────────────────────────────────────

        function testCancelJobPosts(testCase)
            testCase.Service.cancelJob('job_1', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'job_1/cancel'));
        end

        % ── pauseJob ─────────────────────────────────────────────────────

        function testPauseJobPosts(testCase)
            testCase.Service.pauseJob('job_2', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'job_2/pause'));
        end

        % ── getResults ───────────────────────────────────────────────────

        function testGetResultsGets(testCase)
            testCase.Service.getResults('job_3', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'job_3/results'));
        end

        % ── getDetailedResults ───────────────────────────────────────────

        function testGetDetailedResultsGets(testCase)
            testCase.Service.getDetailedResults('job_4', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'job_4/results/detailed'));
        end

        % ── getErrorTrends ───────────────────────────────────────────────

        function testGetErrorTrendsGets(testCase)
            testCase.Service.getErrorTrends('job_5', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'job_5/error-trends'));
        end

        % ── getRBDecay ───────────────────────────────────────────────────

        function testGetRBDecayGets(testCase)
            testCase.Service.getRBDecay('job_6', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'job_6/rb-decay'));
        end

        % ── listProjectJobs ──────────────────────────────────────────────

        function testListProjectJobsUsesProjectId(testCase)
            testCase.Service.listProjectJobs('proj_1', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj_1/jobs'));
        end

        function testListProjectJobsDefaultPagination(testCase)
            testCase.Service.listProjectJobs('proj_2', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'skip=0'));
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'limit=50'));
        end

        % ── submitProjectJob ─────────────────────────────────────────────

        function testSubmitProjectJobPosts(testCase)
            payload = struct('circuit_id', 'c1');
            testCase.Service.submitProjectJob('proj_3', payload, 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'proj_3/jobs'));
        end

        % ── Token forwarding ─────────────────────────────────────────────

        function testTokenIsForwarded(testCase)
            testCase.Service.listJobs('secret');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'secret');
        end

    end
end
