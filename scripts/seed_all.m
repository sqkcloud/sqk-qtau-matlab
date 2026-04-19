% seed_all.m ───────────────────────────────────────────────────────────────────
% Master orchestrator — runs all seed scripts in the correct order.
%
% Usage:
%   >> run('scripts/seed_all.m')
%
% Execution order (each script handles its own authentication):
%   1. seed_projects    — Welcome screen: 20 projects
%   2. seed_circuits    — Upload screen: 10 OpenQASM circuits
%   3. seed_backends    — Backends screen: backend selections per project
%   4. seed_benchmarks  — Benchmark screen: configs + strategy comparisons
%   5. seed_predictions — Prediction screen: fidelity predictions
%   6. seed_jobs        — Jobs screen: quantum job submissions
%   7. seed_reports     — Reports screen: generated reports
%   8. seed_notes       — Notes screen: markdown notes + checklists
%   9. seed_settings    — Settings screen: user preferences
%  10. seed_qae         — Analysis screen: Quantum Amplitude Estimation
%                         (uploads AQS-QMC VaR reference circuit and caches
%                         a statevector-mode QAE analysis on each)
%
% Each script is self-contained and can also be run independently.
% If a script fails, the orchestrator continues with the next one.
% ──────────────────────────────────────────────────────────────────────────────

% Resolve the scripts directory
thisFile   = mfilename('fullpath');
scriptsDir = fileparts(thisFile);

% Load config to display target URL
cfg = seed_helpers.loadConfig();

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║         QTAU Seed — Full Data Population                    ║\n');
fprintf('║         Target: %-43s║\n', cfg.base_url);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

seedScripts = { ...
    'seed_projects',    'Welcome screen (projects)'; ...
    'seed_circuits',    'Upload screen (circuits)'; ...
    'seed_backends',    'Backends screen (selections)'; ...
    'seed_benchmarks',  'Benchmark screen (configs)'; ...
    'seed_predictions', 'Prediction screen (predictions)'; ...
    'seed_jobs',        'Jobs screen (job submissions)'; ...
    'seed_reports',     'Reports screen (reports)'; ...
    'seed_notes',       'Notes screen (notes + checklists)'; ...
    'seed_settings',    'Settings screen (preferences)'; ...
    'seed_qae',         'Analysis screen (Quantum Amplitude Estimation)'; ...
};

nScripts = size(seedScripts, 1);
results  = cell(nScripts, 1);

totalStart = tic;

for i = 1:nScripts
    scriptName = seedScripts{i, 1};
    screenDesc = seedScripts{i, 2};
    scriptPath = fullfile(scriptsDir, [scriptName '.m']);

    fprintf('\n────────────────────────────────────────────────────────────\n');
    fprintf('  [%d/%d] Running %s  (%s)\n', i, nScripts, scriptName, screenDesc);
    fprintf('────────────────────────────────────────────────────────────\n');

    if ~isfile(scriptPath)
        fprintf('  SKIPPED: %s not found\n', scriptPath);
        results{i} = 'SKIPPED';
        continue;
    end

    try
        run(scriptPath);
        results{i} = 'OK';
    catch ME
        fprintf('\n  ERROR in %s: %s\n', scriptName, ME.message);
        results{i} = 'FAILED';
    end
end

elapsed = toc(totalStart);

% ── Summary ──────────────────────────────────────────────────────────────────
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║                    Seed Summary                             ║\n');
fprintf('╠══════════════════════════════════════════════════════════════╣\n');
for i = 1:nScripts
    status = results{i};
    if strcmp(status, 'OK')
        tag = ' OK ';
    elseif strcmp(status, 'SKIPPED')
        tag = 'SKIP';
    else
        tag = 'FAIL';
    end
    fprintf('║  [%s] %-20s  %s\n', tag, seedScripts{i,1}, seedScripts{i,2});
end
fprintf('╠══════════════════════════════════════════════════════════════╣\n');
fprintf('║  Total time: %.1f seconds                                   ║\n', elapsed);
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');
