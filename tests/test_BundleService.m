% test_BundleService.m ───────────────────────────────────────────────────────
% Tests for the reproducibility-bundle assembler.
%
% Run from the project root:
%   >> runtests('tests/test_BundleService')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_BundleService
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
end

% ── defaultName ─────────────────────────────────────────────────────────────
function test_default_name_starts_with_qtau_bundle(testCase)
    ctx = makeBellCtx();
    name = BundleService.defaultName(ctx);
    testCase.assertSubstring(name, 'qtau-bundle');
    testCase.assertSubstring(name, '.zip');
end

function test_default_name_sanitizes_circuit_name(testCase)
    ctx = makeBellCtx();
    ctx.circuitName = 'Hello World!! @#$';
    name = BundleService.defaultName(ctx);
    % All illegal chars collapse to single hyphens
    testCase.assertSubstring(name, 'Hello-World');
    testCase.assertEqual(any(name == ' '), false);
end

% ── assemble — basic ZIP output ─────────────────────────────────────────────
function test_assemble_writes_zip(testCase)
    ctx = makeBellCtx();
    savePath = [tempname() '.zip'];
    cleanup = onCleanup(@() safeDelete(savePath));
    opts = struct('savePath', savePath);

    saved = BundleService.assemble(ctx, opts);
    testCase.assertEqual(saved, savePath);
    testCase.assertEqual(exist(savePath, 'file'), 2, ...
        'Bundle ZIP should exist on disk');
    info = dir(savePath);
    testCase.assertGreaterThan(info.bytes, 100, ...
        'Bundle ZIP should be non-trivial size');
    delete(cleanup);
end

% ── assemble — manifest + README always present ─────────────────────────────
function test_assemble_contents_include_manifest_and_readme(testCase)
    ctx = makeBellCtx();
    savePath = [tempname() '.zip'];
    cleanup = onCleanup(@() safeDelete(savePath));
    BundleService.assemble(ctx, struct('savePath', savePath));

    extractDir = [tempname() '-extract'];
    mkdir(extractDir);
    cleanup2 = onCleanup(@() safeRmdir(extractDir));
    unzip(savePath, extractDir);

    testCase.assertEqual(exist(fullfile(extractDir, 'README.md'), 'file'), 2);
    testCase.assertEqual(exist(fullfile(extractDir, 'manifest.json'), 'file'), 2);
    testCase.assertEqual(exist(fullfile(extractDir, 'circuit', 'original.qasm'), 'file'), 2);

    raw = fileread(fullfile(extractDir, 'manifest.json'));
    m = jsondecode(raw);
    testCase.assertEqual(char(string(m.bundle_version)), '1.0');
    testCase.assertSubstring(char(string(m.generator)), 'QTAU');
    testCase.assertGreaterThan(numel(m.files), 0);
    delete(cleanup); delete(cleanup2);
end

% ── assemble — backend / mitigation / ft are conditional ────────────────────
function test_assemble_omits_optional_sections_when_absent(testCase)
    ctx = makeBellCtx();
    savePath = [tempname() '.zip'];
    cleanup = onCleanup(@() safeDelete(savePath));
    BundleService.assemble(ctx, struct('savePath', savePath));

    extractDir = [tempname() '-extract'];
    mkdir(extractDir);
    cleanup2 = onCleanup(@() safeRmdir(extractDir));
    unzip(savePath, extractDir);

    testCase.assertEqual(exist(fullfile(extractDir, 'backend'),     'dir'), 0, ...
        'Backend dir should be absent when ctx.backend is empty');
    testCase.assertEqual(exist(fullfile(extractDir, 'mitigation'),  'dir'), 0);
    testCase.assertEqual(exist(fullfile(extractDir, 'ft_estimate'), 'dir'), 0);
    delete(cleanup); delete(cleanup2);
end

function test_assemble_includes_optional_sections_when_present(testCase)
    ctx = makeBellCtx();
    ctx.backend = struct('name', 'demo_qpu', ...
        'calibration', struct('records', {{}}));
    ctx.mitigationEstimates = containers.Map( ...
        {'0','1'}, ...
        {struct('summary','None'), struct('summary','TREX')});
    ctx.ftResult = struct( ...
        'logicalQubits', 2, 'distance', 15, 'totalPhysical', 993);
    ctx.ftParams = struct('codeType','surface','physErr',1e-3);

    savePath = [tempname() '.zip'];
    cleanup = onCleanup(@() safeDelete(savePath));
    BundleService.assemble(ctx, struct('savePath', savePath));

    extractDir = [tempname() '-extract'];
    mkdir(extractDir);
    cleanup2 = onCleanup(@() safeRmdir(extractDir));
    unzip(savePath, extractDir);

    testCase.assertEqual(exist(fullfile(extractDir, 'backend', 'name.txt'), 'file'), 2);
    testCase.assertEqual(exist(fullfile(extractDir, 'mitigation', 'estimates.json'), 'file'), 2);
    testCase.assertEqual(exist(fullfile(extractDir, 'ft_estimate', 'result.json'), 'file'), 2);
    delete(cleanup); delete(cleanup2);
end

% ── validation ──────────────────────────────────────────────────────────────
function test_assemble_rejects_missing_circuit(testCase)
    ctx = struct('circuit', []);
    testCase.verifyError( ...
        @() BundleService.assemble(ctx, struct('savePath', tempname())), ...
        'BundleService:BadCtx');
end

function test_assemble_rejects_missing_save_path(testCase)
    ctx = makeBellCtx();
    testCase.verifyError( ...
        @() BundleService.assemble(ctx, struct()), ...
        'BundleService:BadOpts');
end

% ── helpers ─────────────────────────────────────────────────────────────────
function ctx = makeBellCtx()
    m = CircuitModel(2);
    m.addGate('h', 0); m.addGate('cx', [0 1]);
    ctx = struct( ...
        'circuit',             m, ...
        'circuitName',         'bell-state', ...
        'backend',             [], ...
        'mitigationEstimates', [], ...
        'ftResult',            [], ...
        'ftParams',            []);
end

function safeDelete(p)
    try; if exist(p, 'file') == 2; delete(p); end; catch; end
end

function safeRmdir(p)
    try; if exist(p, 'dir') == 7; rmdir(p, 's'); end; catch; end
end
