% test_MatlabQuantumBridge.m ──────────────────────────────────────────────────
% Unit tests for the MATLAB Support Package interop bridge.
% Support-Package-dependent cases assumeTrue(isAvailable) so CI without the
% add-on reports them Incomplete (skipped), not failed.
%
% Run from the project root:
%   >> runtests('tests/test_MatlabQuantumBridge')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_MatlabQuantumBridge
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
end

function test_isAvailable_returns_scalar_logical(testCase)
    tf = MatlabQuantumBridge.isAvailable();
    testCase.assertTrue(islogical(tf) && isscalar(tf));
end
