classdef test_ReportService < matlab.unittest.TestCase
    % test_ReportService  Unit tests for the ReportService domain service.
    %
    % Run from the project root:
    %   >> runtests('tests/test_ReportService')

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
            testCase.Service = ReportService(testCase.Stub);
        end
    end

    methods (Test)

        % ── Constructor ──────────────────────────────────────────────────

        function testConstructorAcceptsClient(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'ReportService'));
        end

        function testServiceIsHandle(testCase)
            testCase.verifyTrue(isa(testCase.Service, 'handle'));
        end

        % ── generateReport ───────────────────────────────────────────────

        function testGenerateReportPosts(testCase)
            testCase.Service.generateReport('My Report', 'pdf', 'all', 'job1', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/reports/generate'));
        end

        function testGenerateReportPayload(testCase)
            testCase.Service.generateReport('Title', 'html', 'summary', 'j2', 'tok');
            p = testCase.Stub.LastPayload;
            testCase.verifyEqual(p.title, 'Title');
            testCase.verifyEqual(p.format, 'html');
            % ReportService.generateReport wraps `sections` in a cell so
            % the JSON payload is an array (the FastAPI side iterates
            % section names). A flat char assertion would lock the API
            % shape back to a string.
            testCase.verifyEqual(p.sections, {'summary'});
            % Job identifier is sent on the wire as `job_record_id`
            % (matches the FastAPI ReportRequest model), not `job_id`.
            testCase.verifyEqual(p.job_record_id, 'j2');
        end

        % ── listReports ──────────────────────────────────────────────────

        function testListReportsUsesGetAuth(testCase)
            testCase.Service.listReports('tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/reports'));
        end

        % ── getReport ────────────────────────────────────────────────────

        function testGetReportUsesReportId(testCase)
            testCase.Service.getReport('rep_abc', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'getAuth');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), '/api/reports/rep_abc'));
        end

        % ── downloadReport ───────────────────────────────────────────────

        function testDownloadReportUsesCorrectEndpoint(testCase)
            testCase.Service.downloadReport('rep_xyz', 'tok');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'rep_xyz/download'));
        end

        % ── shareReport ──────────────────────────────────────────────────

        function testShareReportPosts(testCase)
            testCase.Service.shareReport('rep_1', 'user@example.com', 'tok');
            testCase.verifyEqual(char(testCase.Stub.LastMethod), 'postAuthJson');
            testCase.verifyTrue(contains(char(testCase.Stub.LastEndpoint), 'rep_1/share'));
        end

        function testShareReportPayloadContainsEmail(testCase)
            testCase.Service.shareReport('rep_2', 'alice@test.com', 'tok');
            testCase.verifyEqual(testCase.Stub.LastPayload.email, 'alice@test.com');
        end

        % ── Return value comes from stub ─────────────────────────────────

        function testReturnValueFromStub(testCase)
            testCase.Stub.Response = struct('report_id', 'r1', 'status', 'generated');
            data = testCase.Service.generateReport('T', 'pdf', 'all', 'j', 'tok');
            testCase.verifyEqual(data.report_id, 'r1');
            testCase.verifyEqual(data.status, 'generated');
        end

        % ── Token forwarding ─────────────────────────────────────────────

        function testTokenIsForwarded(testCase)
            testCase.Service.listReports('my_secret_token');
            testCase.verifyEqual(char(testCase.Stub.LastToken), 'my_secret_token');
        end

    end
end
