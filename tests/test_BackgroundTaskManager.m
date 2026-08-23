% test_BackgroundTaskManager.m ────────────────────────────────────────────────
% Unit tests for BackgroundTaskManager — the in-process registry that tracks
% long-running QMC / Cutting / IBM-job tasks so the user can navigate away
% from the loading overlay without abandoning the work.
%
% Run:
%   >> runtests('tests/test_BackgroundTaskManager')

function tests = test_BackgroundTaskManager
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'infrastructure'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
end

% BGT-01
function test_register_assigns_sequential_ids(testCase)
    mgr = BackgroundTaskManager();
    id1 = mgr.register(struct('kind','qmc','displayName','run-A'));
    id2 = mgr.register(struct('kind','qmc','displayName','run-B'));
    testCase.assertEqual(id1, 'bgt_1');
    testCase.assertEqual(id2, 'bgt_2');
end

% BGT-02
function test_register_defaults_status_to_queued(testCase)
    mgr = BackgroundTaskManager();
    id = mgr.register(struct('kind','qmc','displayName','run-A'));
    t = mgr.findById(id);
    testCase.assertEqual(t.status, 'queued');
end

% BGT-03
function test_update_patches_fields(testCase)
    mgr = BackgroundTaskManager();
    id = mgr.register(struct('kind','qmc','displayName','run-A'));
    mgr.update(id, struct('progressPct', 42, 'statusText', 'Running shots'));
    t = mgr.findById(id);
    testCase.assertEqual(t.progressPct, 42);
    testCase.assertEqual(t.statusText, 'Running shots');
end

% BGT-04
function test_complete_marks_completed_and_fires_callback(testCase)
    mgr = BackgroundTaskManager();
    evalin('base', 'clear bgt_test_capture');
    cb = @(payload) recordComplete(payload);
    id = mgr.register(struct('kind','qmc','displayName','run-A', ...
                              'onComplete', cb));
    mgr.complete(id, struct('value', 99));
    t = mgr.findById(id);
    testCase.assertEqual(t.status, 'completed');
    testCase.assertEqual(t.progressPct, 100);
    captured = evalin('base', 'bgt_test_capture');
    testCase.assertEqual(captured.hits, 1);
    testCase.assertEqual(captured.payload.value, 99);
    evalin('base', 'clear bgt_test_capture');
end

% BGT-05
function test_fail_stores_exception(testCase)
    mgr = BackgroundTaskManager();
    id = mgr.register(struct('kind','qmc','displayName','run-A'));
    ME = MException('Test:Boom', 'kaboom');
    mgr.fail(id, ME);
    t = mgr.findById(id);
    testCase.assertEqual(t.status, 'failed');
    testCase.assertEqual(t.error.identifier, 'Test:Boom');
end

% BGT-06
function test_cancel_invokes_onCancel_and_marks_cancelled(testCase)
    mgr = BackgroundTaskManager();
    evalin('base', 'bgt_cancel_hits = 0;');
    cancelCb = @() evalin('base', 'bgt_cancel_hits = bgt_cancel_hits + 1;');
    id = mgr.register(struct('kind','qmc','displayName','run-A', ...
                              'onCancel', cancelCb));
    mgr.cancel(id);
    t = mgr.findById(id);
    testCase.assertEqual(t.status, 'cancelled');
    hits = evalin('base', 'bgt_cancel_hits');
    testCase.assertEqual(hits, 1);
    evalin('base', 'clear bgt_cancel_hits');
end

% BGT-07
function test_cancel_is_idempotent_on_terminal_tasks(testCase)
    mgr = BackgroundTaskManager();
    id = mgr.register(struct('kind','qmc','displayName','run-A'));
    mgr.complete(id, struct('done', true));
    mgr.cancel(id);   % must be a no-op
    t = mgr.findById(id);
    testCase.assertEqual(t.status, 'completed');
end

% BGT-08
function test_clearTerminal_evicts_only_terminal_tasks(testCase)
    mgr = BackgroundTaskManager();
    idA = mgr.register(struct('kind','qmc','displayName','A')); %#ok<NASGU>
    idB = mgr.register(struct('kind','qmc','displayName','B'));
    idC = mgr.register(struct('kind','qmc','displayName','C'));
    mgr.complete(idB, struct());
    mgr.cancel(idC);
    mgr.clearTerminal();
    list = mgr.list();
    testCase.assertEqual(numel(list), 1);
    testCase.assertEqual(char(list{1}.displayName), 'A');
end

% BGT-09
function test_countActive_counts_only_queued_and_running(testCase)
    mgr = BackgroundTaskManager();
    idA = mgr.register(struct('kind','qmc','displayName','A')); %#ok<NASGU>
    idB = mgr.register(struct('kind','qmc','displayName','B'));
    idC = mgr.register(struct('kind','qmc','displayName','C'));
    mgr.update(idB, struct('status', 'running'));
    mgr.complete(idC, struct());
    testCase.assertEqual(mgr.countActive(), 2);
end

% BGT-10
function test_complete_releases_callback_handles(testCase)
    % Terminal transition nulls the callback/poll-ctx closures so a
    % finished task stops pinning VM/app object graphs; result is kept.
    mgr = BackgroundTaskManager();
    id = mgr.register(struct('kind','qmc','displayName','A', ...
        'onComplete', @(r) r, 'onCancel', @() 1));
    mgr.complete(id, struct('value', 7));
    t = mgr.findById(id);
    testCase.assertEmpty(t.onComplete);
    testCase.assertEmpty(t.onCancel);
    testCase.assertEqual(t.result.value, 7);
end

% BGT-11
function test_terminal_retention_is_bounded(testCase)
    % Retained terminal tasks are capped (oldest evicted) so a long
    % session can't grow the registry unbounded.
    mgr = BackgroundTaskManager();
    ids = cell(1, 30);
    for k = 1:30
        ids{k} = mgr.register(struct('kind','qmc','displayName',sprintf('run-%d',k)));
        mgr.complete(ids{k}, struct());
    end
    testCase.assertLessThanOrEqual(numel(mgr.list()), 25);
    testCase.assertNotEmpty(mgr.findById(ids{30}));   % newest kept
    testCase.assertEmpty(mgr.findById(ids{1}));       % oldest evicted
end

% ── helpers ─────────────────────────────────────────────────────────────────
function recordComplete(payload)
    % Bridge the callback's local scope to the test by stashing the payload
    % in the base workspace. Cleared by the test on the way out.
    cur = struct('hits', 0, 'payload', []);
    try
        if evalin('base', 'exist(''bgt_test_capture'',''var'')') == 1
            cur = evalin('base', 'bgt_test_capture');
        end
    catch
    end
    cur.hits = cur.hits + 1;
    cur.payload = payload;
    assignin('base', 'bgt_test_capture', cur);
end
