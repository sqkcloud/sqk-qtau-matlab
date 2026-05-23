% test_MitigationService.m ────────────────────────────────────────────────────
% Unit tests for MitigationService — verifies that the two endpoints (
% /api/mitigation/levels and /api/mitigation/estimate ) are reached with the
% correct HTTP verbs and that the supplied payload + token round-trip
% verbatim through the StubFastAPIClient.
%
% Run:
%   >> runtests('tests/test_MitigationService')

function tests = test_MitigationService
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

% MIT-06
function test_constructor_creates_service(testCase)
    stub = StubFastAPIClient();
    svc  = MitigationService(stub);
    testCase.assertTrue(isa(svc, 'MitigationService'));
end

% MIT-01
function test_listLevels_uses_getAuth(testCase)
    stub = StubFastAPIClient();
    svc  = MitigationService(stub);
    svc.listLevels('tok-123');
    testCase.assertEqual(char(stub.LastMethod), 'getAuth');
    testCase.assertEqual(char(stub.LastEndpoint), '/api/mitigation/levels');
end

% MIT-04
function test_listLevels_forwards_token(testCase)
    stub = StubFastAPIClient();
    svc  = MitigationService(stub);
    svc.listLevels('tok-abc');
    testCase.assertEqual(char(stub.LastToken), 'tok-abc');
end

% MIT-02
function test_estimate_uses_postAuthJson(testCase)
    stub = StubFastAPIClient();
    svc  = MitigationService(stub);
    body = struct('mitigation_level', 1, 'backend_name', 'ibm_marrakesh', ...
                  'base_shots', 4096, 'circuit_qubits', 5);
    svc.estimate(body, 'tok-1');
    testCase.assertEqual(char(stub.LastMethod), 'postAuthJson');
    testCase.assertEqual(char(stub.LastEndpoint), '/api/mitigation/estimate');
end

% MIT-03
function test_estimate_preserves_payload(testCase)
    stub = StubFastAPIClient();
    svc  = MitigationService(stub);
    body = struct('mitigation_level', 2, 'backend_name', 'ibm_torino', ...
                  'base_shots', 8192, 'circuit_qubits', 12);
    svc.estimate(body, 'tok');
    captured = stub.LastPayload;
    testCase.assertEqual(captured.mitigation_level, 2);
    testCase.assertEqual(char(captured.backend_name), 'ibm_torino');
    testCase.assertEqual(captured.base_shots, 8192);
    testCase.assertEqual(captured.circuit_qubits, 12);
end

% MIT-05
function test_estimate_returns_stub_response(testCase)
    stub = StubFastAPIClient();
    stub.Response = struct('plan', struct('id', 'plan-1'), ...
                            'cost', struct('shot_multiplier', 1.7), ...
                            'summary', 'Mitigation: Standard');
    svc  = MitigationService(stub);
    out  = svc.estimate(struct(), 'tok');
    testCase.assertEqual(char(out.plan.id), 'plan-1');
    testCase.assertEqual(out.cost.shot_multiplier, 1.7);
    testCase.assertEqual(char(out.summary), 'Mitigation: Standard');
end
