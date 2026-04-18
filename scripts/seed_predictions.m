% seed_predictions.m ───────────────────────────────────────────────────────────
% Runs fidelity predictions for circuits across backends via the REST API.
%
% Usage:
%   >> run('scripts/seed_predictions.m')
%
% Provides data for: Prediction screen (summary table, distribution, budget)
% Prerequisites: seed_projects.m, seed_circuits.m
% ──────────────────────────────────────────────────────────────────────────────

fprintf('\n=== QTAU Seed: Running predictions for circuits ===\n\n');

% ── Configuration ────────────────────────────────────────────────────────────
cfg      = seed_helpers.loadConfig();
BASE_URL = cfg.base_url;

% ── Step 1: Authenticate ────────────────────────────────────────────────────
fprintf('[1/4] Logging in as "%s" ... ', cfg.username);
try
    token = seed_helpers.login(BASE_URL, cfg.login_path, cfg.username, cfg.password);
    fprintf('OK\n');
catch ME
    fprintf('FAILED\n  %s\n', ME.message);
    return;
end

getOpts  = seed_helpers.getOpts(token);
postOpts = seed_helpers.postOpts(token);
postOpts.Timeout = 60;  % Predictions may take longer

% ── Step 2: Fetch circuits ───────────────────────────────────────────────────
fprintf('[2/4] Fetching circuits ... ');
try
    circResp = webread([BASE_URL '/api/circuits'], getOpts);
    if isstruct(circResp) && isfield(circResp, 'circuits')
        circuits = circResp.circuits;
    else
        circuits = circResp;
    end
    nCirc = numel(circuits);
    fprintf('found %d\n', nCirc);
catch ME
    fprintf('FAILED (%s)\n', ME.message); return;
end

if nCirc == 0
    fprintf('  No circuits found. Run seed_circuits.m first.\n');
    return;
end

% ── Step 3: Fetch projects ───────────────────────────────────────────────────
fprintf('[3/4] Fetching projects ... ');
try
    projResp = webread([BASE_URL '/api/projects'], getOpts);
    projects = projResp.projects;
    nProj    = numel(projects);
    fprintf('found %d\n', nProj);
catch ME
    fprintf('FAILED (%s)\n', ME.message); return;
end

% ── Step 4: Run predictions ──────────────────────────────────────────────────
fprintf('[4/4] Running predictions ...\n');

backendSets = { ...
    {{'ibm_boston', 'ibm_fez'}}; ...
    {{'ibm_pittsburgh', 'ibm_kingston'}}; ...
    {{'ibm_miami', 'ibm_marrakesh'}}; ...
    {{'ibm_boston'}}; ...
};

% 4a. Standalone predictions (POST /api/predict)
standaloneCount = 0;
predictUrl = [BASE_URL '/api/predict'];
nPredict = min(nCirc, 6);  % predict first 6 circuits

for i = 1:nPredict
    circ = circuits(i);
    cid  = string(circ.circuit_id);
    cname = string(circ.name);

    bIdx     = mod(i - 1, numel(backendSets)) + 1;
    backends = backendSets{bIdx}{1};

    payload = struct('circuit_id', cid, 'backend_names', {backends});
    try
        resp = webwrite(predictUrl, payload, postOpts);
        standaloneCount = standaloneCount + 1;
        pid = string(resp.prediction_id);
        fprintf('  [%d/%d] Predicted: %-30s  id=%s  backends=%s\n', ...
            i, nPredict, cname, pid, strjoin(backends, ','));
    catch ME
        fprintf('  [%d/%d] FAILED:   %-30s  %s\n', i, nPredict, cname, ME.message);
    end
end

% 4b. Project-scoped predictions (POST /api/projects/{id}/predict)
% Each circuit belongs to a specific project (assigned at upload time), so we
% must fetch circuits scoped to that project via the X-Project-Id header —
% a project-scoped predict rejects circuits from other projects with 404.
projectCount = 0;
nProjPredict = min(nProj, 5);
authHdr = {'Authorization', char("Bearer " + token); 'Accept', 'application/json'};

for i = 1:nProjPredict
    proj = projects(i);
    pid  = string(proj.project_id);
    name = string(proj.name);

    projGetOpts = weboptions('Timeout', 30, 'ContentType', 'json', ...
        'HeaderFields', [authHdr; {'X-Project-Id', char(pid)}]);
    try
        projCircResp = webread([BASE_URL '/api/circuits'], projGetOpts);
        if isstruct(projCircResp) && isfield(projCircResp, 'circuits')
            projCircuits = projCircResp.circuits;
        else
            projCircuits = projCircResp;
        end
    catch
        projCircuits = [];
    end

    if isempty(projCircuits)
        fprintf('  Project SKIPPED (no circuits): %-30s\n', name);
        continue;
    end

    circ     = projCircuits(1);
    cid      = string(circ.circuit_id);
    bIdx     = mod(i - 1, numel(backendSets)) + 1;
    backends = backendSets{bIdx}{1};

    url     = sprintf('%s/api/projects/%s/predict', BASE_URL, pid);
    payload = struct('circuit_id', cid, 'backend_names', {backends});
    try
        webwrite(url, payload, postOpts);
        projectCount = projectCount + 1;
        fprintf('  Project %-35s  circuit=%-25s\n', name, string(circ.name));
    catch ME
        fprintf('  Project FAILED: %-30s  %s\n', name, ME.message);
    end
end

fprintf('\n=== Done: %d standalone + %d project predictions ===\n\n', ...
    standaloneCount, projectCount);
