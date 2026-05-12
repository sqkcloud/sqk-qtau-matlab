% test_MitigationCompareViewModel.m ──────────────────────────────────────────
% Focused unit tests for the static helpers on MitigationCompareViewModel.
% The full lifecycle (onEnter / onEstimate) requires a stub QTAUWorkbenchApp,
% which is out of scope here — tests target the pure formatting + parsing
% utilities the view layer relies on.
%
% Run from the project root:
%   >> runtests('tests/test_MitigationCompareViewModel')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_MitigationCompareViewModel
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'presentation', 'viewmodels'));
end

% ── parseLevelId ────────────────────────────────────────────────────────────
function test_parseLevelId_numeric(testCase)
    testCase.assertEqual(MitigationCompareViewModel.parseLevelId('0'), int32(0));
    testCase.assertEqual(MitigationCompareViewModel.parseLevelId('2'), int32(2));
    testCase.assertEqual(MitigationCompareViewModel.parseLevelId('3'), int32(3));
end

function test_parseLevelId_invalid_returns_minus_one(testCase)
    testCase.assertEqual(MitigationCompareViewModel.parseLevelId('custom'), int32(-1));
    testCase.assertEqual(MitigationCompareViewModel.parseLevelId(''),       int32(-1));
end

% ── gradeColor (color grading by shot multiplier) ───────────────────────────
function test_gradeColor_unity_is_green(testCase)
    rgb = MitigationCompareViewModel.gradeColor(1.0);
    testCase.assertEqual(rgb, [0.30 0.70 0.40], 'AbsTol', 1e-9);
end

function test_gradeColor_mid_is_amber_band(testCase)
    rgb = MitigationCompareViewModel.gradeColor(5.0);
    testCase.assertEqual(rgb, [0.95 0.70 0.30], 'AbsTol', 1e-9);
end

function test_gradeColor_high_is_red(testCase)
    rgb = MitigationCompareViewModel.gradeColor(50.0);
    testCase.assertEqual(rgb, [0.85 0.30 0.30], 'AbsTol', 1e-9);
end

function test_gradeColor_nonfinite_is_neutral(testCase)
    rgb = MitigationCompareViewModel.gradeColor(NaN);
    testCase.assertEqual(rgb, [0.5 0.5 0.5]);
end

% ── fmtInt ──────────────────────────────────────────────────────────────────
function test_fmtInt_under_1k_renders_plain(testCase)
    testCase.assertEqual(MitigationCompareViewModel.fmtInt(512), '512');
end

function test_fmtInt_thousand_uses_k_suffix(testCase)
    testCase.assertEqual(MitigationCompareViewModel.fmtInt(8192), '8.2k');
end

function test_fmtInt_million_uses_M_suffix(testCase)
    testCase.assertEqual(MitigationCompareViewModel.fmtInt(2.5e6), '2.50M');
end

% ── fmtSeconds ──────────────────────────────────────────────────────────────
function test_fmtSeconds_subminute(testCase)
    testCase.assertEqual(MitigationCompareViewModel.fmtSeconds(2.5), '2.5s');
end

function test_fmtSeconds_subhour(testCase)
    testCase.assertEqual(MitigationCompareViewModel.fmtSeconds(125), '2m 5s');
end

% ── safeField defensive accessor ────────────────────────────────────────────
function test_safeField_existing(testCase)
    s = struct('shot_multiplier', 2.5);
    testCase.assertEqual(MitigationCompareViewModel.safeField(s, 'shot_multiplier', 1.0), 2.5);
end

function test_safeField_missing_falls_back(testCase)
    s = struct('foo', 1);
    testCase.assertEqual(MitigationCompareViewModel.safeField(s, 'bar', 99), 99);
end

% ── level label / id resolvers ──────────────────────────────────────────────
function test_levelLabel_prefers_label(testCase)
    lvl = struct('id', 2, 'name', 'standard', 'label', 'Standard');
    testCase.assertEqual(MitigationCompareViewModel.levelLabel(lvl), 'Standard');
end

function test_levelLabel_falls_through_to_name_when_no_label(testCase)
    lvl = struct('id', 0, 'name', 'raw', 'label', '');
    testCase.assertEqual(MitigationCompareViewModel.levelLabel(lvl), 'raw');
end

function test_levelId_uses_id_field(testCase)
    lvl = struct('id', 3, 'name', 'aggressive');
    testCase.assertEqual(MitigationCompareViewModel.levelId(lvl), '3');
end
