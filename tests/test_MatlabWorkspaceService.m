function tests = test_MatlabWorkspaceService
tests = functiontests(localfunctions);
end
function testExportImport(testCase)
svc = MatlabWorkspaceService();
cleanup = onCleanup(@() evalin('base','clear qtauTestValue'));
svc.exportVariable('qtauTestValue', struct('x',42));
v = svc.importVariable('qtauTestValue');
verifyEqual(testCase, v.x, 42);
end
function testInvalidName(testCase)
verifyError(testCase, @() MatlabWorkspaceService.validateName('bad name'), ...
    'MatlabWorkspaceService:InvalidVariableName');
end
