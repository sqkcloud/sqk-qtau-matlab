% run_tests.m  Headless test runner for the QTAU MATLAB suite.
%
% Adds all src/ subfolders + tests/ to the path, runs every test file in
% tests/, prints a one-line summary, and writes a Markdown report to
% doc/TEST_REPORT.md so the result is reviewable outside MATLAB.
%
% Usage:
%   /Applications/MATLAB_R2025b.app/bin/matlab -batch \
%     "run('scripts/run_tests.m')"

function run_tests
    projectRoot = fileparts(fileparts(mfilename('fullpath')));
    cd(projectRoot);

    foldersToAdd = { ...
        fullfile('src', 'presentation', 'app'), ...
        fullfile('src', 'presentation', 'screens'), ...
        fullfile('src', 'presentation', 'viewmodels'), ...
        fullfile('src', 'presentation'), ...
        fullfile('src', 'domain', 'models'), ...
        fullfile('src', 'domain', 'services'), ...
        fullfile('src', 'domain'), ...
        fullfile('src', 'infrastructure', 'http'), ...
        fullfile('src', 'infrastructure', 'config'), ...
        fullfile('src', 'infrastructure'), ...
        'tests'};
    for k = 1:numel(foldersToAdd)
        p = fullfile(projectRoot, foldersToAdd{k});
        if isfolder(p); addpath(p); end
    end

    import matlab.unittest.TestSuite
    import matlab.unittest.TestRunner

    suite = TestSuite.fromFolder('tests');
    fprintf('[run_tests] Discovered %d test methods.\n', numel(suite));

    runner = TestRunner.withTextOutput('Verbosity', 1);
    tic;
    results = runner.run(suite);
    elapsed = toc;

    nPass  = sum([results.Passed]);
    nFail  = sum([results.Failed]);
    nIncomp = sum([results.Incomplete]);

    fprintf('\n[run_tests] PASSED=%d  FAILED=%d  INCOMPLETE=%d  TIME=%.1fs\n', ...
        nPass, nFail, nIncomp, elapsed);

    writeMarkdownReport(results, elapsed, fullfile(projectRoot, 'doc', 'TEST_REPORT.md'));

    if nFail > 0 || nIncomp > 0
        exit(1);
    end
end

function writeMarkdownReport(results, elapsed, outPath)
    fid = fopen(outPath, 'w');
    if fid < 0
        warning('run_tests:writeFailed', 'Cannot write %s', outPath);
        return;
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>

    nPass   = sum([results.Passed]);
    nFail   = sum([results.Failed]);
    nIncomp = sum([results.Incomplete]);
    total   = numel(results);
    when    = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');

    fprintf(fid, '# QTAU Connector Workbench — Test Report\n\n');
    fprintf(fid, '**Generated:** %s\n', char(when));
    fprintf(fid, '**Runner:** `scripts/run_tests.m` (MATLAB Unit Test Framework)\n');
    fprintf(fid, '**MATLAB:** %s\n', version);
    fprintf(fid, '**Elapsed:** %.1f s\n\n', elapsed);

    fprintf(fid, '## Summary\n\n');
    fprintf(fid, '| Metric | Value |\n|---|---:|\n');
    fprintf(fid, '| Total tests | %d |\n', total);
    fprintf(fid, '| Passed | %d |\n', nPass);
    fprintf(fid, '| Failed | %d |\n', nFail);
    fprintf(fid, '| Incomplete | %d |\n', nIncomp);
    if total > 0
        fprintf(fid, '| Pass rate | %.1f%% |\n', 100 * nPass / total);
    end
    fprintf(fid, '\n');

    if nFail == 0 && nIncomp == 0
        fprintf(fid, '## Result\n\n**ALL TESTS PASSED.**\n\n');
    else
        fprintf(fid, '## Result\n\n**FAILURES PRESENT — see Failed Tests below.**\n\n');
    end

    files = unique(extractFileFromName({results.Name}));
    fprintf(fid, '## Per-File Breakdown\n\n');
    fprintf(fid, '| File | Tests | Passed | Failed | Total Time (s) |\n|---|---:|---:|---:|---:|\n');
    for i = 1:numel(files)
        f = files{i};
        idx = startsWith({results.Name}, [f '/']);
        nf = sum(idx);
        np = sum([results(idx).Passed]);
        nfail = sum([results(idx).Failed]);
        durTotal = sum([results(idx).Duration]);
        fprintf(fid, '| `%s` | %d | %d | %d | %.3f |\n', f, nf, np, nfail, durTotal);
    end
    fprintf(fid, '\n');

    % Full per-test detail: status, duration, scenario hint (derived from name).
    fprintf(fid, '## Per-Test Detail\n\n');
    fprintf(fid, '| # | Test | Status | Duration (s) | Notes |\n|---:|---|:---:|---:|---|\n');
    for i = 1:numel(results)
        r = results(i);
        if r.Passed
            statusCell = 'PASS';
            note = scenarioHint(r.Name);
        elseif r.Failed
            statusCell = 'FAIL';
            note = oneLineFailure(r);
        elseif r.Incomplete
            statusCell = 'INCOMPLETE';
            note = oneLineFailure(r);
        else
            statusCell = '?';
            note = '';
        end
        note = strrep(note, '|', '\|');
        fprintf(fid, '| %d | `%s` | %s | %.3f | %s |\n', ...
            i, r.Name, statusCell, r.Duration, note);
    end
    fprintf(fid, '\n');

    failed = results([results.Failed] | [results.Incomplete]);
    if ~isempty(failed)
        fprintf(fid, '## Failure Diagnostics\n\n');
        for i = 1:numel(failed)
            r = failed(i);
            fprintf(fid, '### `%s`\n\n', r.Name);
            fprintf(fid, '- **Duration:** %.3f s\n', r.Duration);
            try
                diag = char(r.Details.DiagnosticRecord(1).Report);
                diag = strrep(diag, '`', '\`');
                fprintf(fid, '- **Diagnostic:**\n\n```\n%s\n```\n\n', diag);
            catch
                fprintf(fid, '- **Diagnostic:** (none captured)\n\n');
            end
            try
                stack = r.Details.DiagnosticRecord(1).Stack;
                if ~isempty(stack)
                    fprintf(fid, '- **Stack:**\n\n```\n');
                    for s = 1:numel(stack)
                        fprintf(fid, '  %s (line %d)\n', stack(s).name, stack(s).line);
                    end
                    fprintf(fid, '```\n\n');
                end
            catch
            end
        end
    end

    fprintf(fid, '## Environment\n\n');
    fprintf(fid, '- Platform: %s\n', computer);
    fprintf(fid, '- Working directory: `%s`\n', pwd);
end

function note = scenarioHint(testName)
    [~, leaf] = strtok(testName, '/');
    leaf = regexprep(leaf, '^/', '');
    leaf = regexprep(leaf, '^test_?', '');
    leaf = regexprep(leaf, '_', ' ');
    leaf = regexprep(leaf, '([a-z])([A-Z])', '$1 $2');
    if isempty(leaf)
        note = '';
    else
        note = ['verifies ', lower(leaf)];
    end
end

function s = oneLineFailure(r)
    s = '';
    try
        diag = char(r.Details.DiagnosticRecord(1).Report);
        lines = strsplit(diag, newline);
        for k = 1:numel(lines)
            ln = strtrim(lines{k});
            if isempty(ln); continue; end
            if startsWith(ln, '---'); continue; end
            s = ln;
            break;
        end
        if isempty(s) && ~isempty(lines)
            s = strtrim(lines{1});
        end
    catch
        s = '(no diagnostic)';
    end
    if numel(s) > 180
        s = [s(1:177) '...'];
    end
end

function out = extractFileFromName(names)
    out = cell(1, numel(names));
    for i = 1:numel(names)
        n = char(names{i});
        slash = strfind(n, '/');
        if isempty(slash); slash = strfind(n, '\'); end
        if isempty(slash)
            dot = strfind(n, '.');
            if ~isempty(dot); out{i} = n(1:dot(1)-1); else; out{i} = n; end
        else
            out{i} = n(1:slash(1)-1);
        end
    end
end
