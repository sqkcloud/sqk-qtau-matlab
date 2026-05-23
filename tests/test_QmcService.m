% test_QmcService.m ───────────────────────────────────────────────────────────
% Unit tests for QmcService — verifies the QAE / Quantum Monte Carlo flow:
% submit (async 202) / poll / cancel / fetch-cached / download-IBM-log.
% All HTTP work is recorded by StubFastAPIClient; no real network.
%
% Run:
%   >> runtests('tests/test_QmcService')

function tests = test_QmcService
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'http'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
    addpath(fullfile(projectRoot, 'tests'));
end

% QMC-01
function test_submitAnalyze_uses_postAuthJson_with_circuit_id(testCase)
    stub = StubFastAPIClient();
    svc  = QmcService(stub);
    svc.submitAnalyze('cir-42', 'statevector', 4096, 0.01, 0.95, 6, ...
                       'option_price', [], struct(), 'tok');
    testCase.assertEqual(char(stub.LastMethod), 'postAuthJson');
    testCase.assertTrue(contains(char(stub.LastEndpoint), '/api/circuits/cir-42/qae/analyze'));
end

% QMC-02
function test_submitAnalyze_payload_shape(testCase)
    stub = StubFastAPIClient();
    svc  = QmcService(stub);
    svc.submitAnalyze('c1', 'statevector', 2048, 0.005, 0.99, 8, ...
                       'var_95', [], struct(), 'tok');
    p = stub.LastPayload;
    testCase.assertEqual(char(p.execution_mode),  'statevector');
    testCase.assertEqual(p.shots,                 2048);
    testCase.assertEqual(p.epsilon,               0.005);
    testCase.assertEqual(p.confidence_level,      0.99);
    testCase.assertEqual(p.num_eval_qubits,       8);
    testCase.assertEqual(char(p.risk_metric),     'var_95');
    testCase.assertFalse(isfield(p, 'backend'), ...
        'backend must be omitted when caller passes []');
end

% QMC-03
function test_submitAnalyze_adds_backend_when_runtime(testCase)
    stub = StubFastAPIClient();
    svc  = QmcService(stub);
    svc.submitAnalyze('c1', 'runtime', 4096, 0.01, 0.95, 6, ...
                       'option_price', 'ibm_marrakesh', struct(), 'tok');
    p = stub.LastPayload;
    testCase.assertTrue(isfield(p, 'backend'));
    testCase.assertEqual(char(p.backend), 'ibm_marrakesh');
end

% QMC-04
function test_submitAnalyze_forwards_mitigation_option(testCase)
    stub = StubFastAPIClient();
    svc  = QmcService(stub);
    opts = struct('mitigation', 'zne', 'compute_greeks', true);
    svc.submitAnalyze('c1', 'runtime', 4096, 0.01, 0.95, 6, ...
                       'option_price', 'ibm_torino', opts, 'tok');
    p = stub.LastPayload;
    testCase.assertEqual(char(p.mitigation), 'zne');
    testCase.assertEqual(logical(p.compute_greeks), true);
end

% QMC-05
function test_getAnalyzeJob_uses_getAuth_with_job_id(testCase)
    stub = StubFastAPIClient();
    svc  = QmcService(stub);
    svc.getAnalyzeJob('job-xyz', 'tok');
    testCase.assertEqual(char(stub.LastMethod), 'getAuth');
    testCase.assertEqual(char(stub.LastEndpoint), '/api/qae/jobs/job-xyz');
end

% QMC-06
function test_cancelAnalyzeJob_uses_deleteAuth(testCase)
    stub = StubFastAPIClient();
    svc  = QmcService(stub);
    svc.cancelAnalyzeJob('job-xyz', 'tok');
    testCase.assertEqual(char(stub.LastMethod), 'deleteAuth');
    testCase.assertEqual(char(stub.LastEndpoint), '/api/qae/jobs/job-xyz');
end

% QMC-07
function test_getLast_hits_qae_result_endpoint(testCase)
    stub = StubFastAPIClient();
    svc  = QmcService(stub);
    svc.getLast('cir-7', 'tok');
    testCase.assertEqual(char(stub.LastMethod), 'getAuth');
    testCase.assertEqual(char(stub.LastEndpoint), '/api/circuits/cir-7/qae/result');
end

% QMC-08
function test_downloadIbmLog_passes_fmt_query_param(testCase)
    stub = StubFastAPIClient();
    svc  = QmcService(stub);
    destPath = [tempname() '.jsonl'];
    cleanup = onCleanup(@() safeDelete(destPath)); %#ok<NASGU>
    saved = svc.downloadIbmLog('cir-9', 'tok', 'jsonl', destPath);
    testCase.assertEqual(char(stub.LastMethod), 'downloadFileAuth');
    testCase.assertTrue(contains(char(stub.LastEndpoint), '/api/circuits/cir-9/qae/ibm-log'));
    testCase.assertTrue(contains(char(stub.LastEndpoint), 'fmt=jsonl'));
    testCase.assertEqual(saved, destPath);
    testCase.assertEqual(exist(destPath, 'file'), 2, ...
        'Stub downloadFileAuth must touch the destination file');
end

function safeDelete(p)
    if exist(p, 'file') == 2
        try; delete(p); catch; end
    end
end
