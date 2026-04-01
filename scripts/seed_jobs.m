% seed_jobs.m ──────────────────────────────────────────────────────────────────
% Submits quantum jobs for circuits across backends via the REST API.
%
% Usage:
%   >> run('scripts/seed_jobs.m')
%
% Provides data for: Jobs screen, Results screen, Detailed Analysis screen
% Prerequisites: seed_projects.m, seed_circuits.m
% ──────────────────────────────────────────────────────────────────────────────

fprintf('\n=== QTAU Seed: Submitting quantum jobs ===\n\n');

% ── Configuration ────────────────────────────────────────────────────────────
BASE_URL   = 'http://34.42.87.190:5715';
LOGIN_PATH = '/api/auth/login';
USERNAME   = 'admin';
PASSWORD   = 'passw0rd';

% ── Step 1: Authenticate ────────────────────────────────────────────────────
fprintf('[1/4] Logging in as "%s" ... ', USERNAME);
try
    import matlab.net.http.*
    import matlab.net.http.field.*
    import matlab.net.http.io.*
    body = FormProvider('username', USERNAME, 'password', PASSWORD);
    req  = RequestMessage('POST', ...
        [ContentTypeField(MediaType('application/x-www-form-urlencoded'))], body);
    resp = req.send(matlab.net.URI([BASE_URL LOGIN_PATH]));
    if resp.StatusCode ~= 200
        error('Login failed with status %d', int32(resp.StatusCode));
    end
    token = string(resp.Body.Data.access_token);
    fprintf('OK\n');
catch ME
    fprintf('FAILED\n  %s\n', ME.message);
    return;
end

authHeader = {'Authorization', char("Bearer " + token)};
getOpts  = weboptions('Timeout', 30, 'ContentType', 'json', 'HeaderFields', authHeader);
postOpts = weboptions('Timeout', 60, 'MediaType', 'application/json', ...
    'ContentType', 'json', 'HeaderFields', authHeader);

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

% ── Step 4: Submit jobs ──────────────────────────────────────────────────────
fprintf('[4/4] Submitting jobs ...\n');

% Job configuration presets
jobConfigs = { ...
    struct('backend', 'ibm_brisbane',   'shots', 1024, 'opt', 1); ...
    struct('backend', 'ibm_sherbrooke', 'shots', 4096, 'opt', 2); ...
    struct('backend', 'ibm_kyoto',      'shots', 8192, 'opt', 3); ...
    struct('backend', 'ibm_osaka',      'shots', 2048, 'opt', 1); ...
    struct('backend', 'ibm_brisbane',   'shots', 4096, 'opt', 2); ...
};

jobIds = {};

% 4a. Standalone jobs (POST /api/jobs/submit)
submitUrl     = [BASE_URL '/api/jobs/submit'];
standaloneCount = 0;
nSubmit = min(nCirc, 8);  % submit first 8 circuits

for i = 1:nSubmit
    circ = circuits(i);
    cid  = string(circ.circuit_id);
    cname = string(circ.name);

    cfgIdx = mod(i - 1, numel(jobConfigs)) + 1;
    cfg    = jobConfigs{cfgIdx};

    payload = struct( ...
        'circuit_id',         cid, ...
        'backend_name',       cfg.backend, ...
        'shots',              cfg.shots, ...
        'optimization_level', cfg.opt);

    try
        resp = webwrite(submitUrl, payload, postOpts);
        jid  = string(resp.job_record_id);
        jobIds{end+1} = jid; %#ok<SAGROW>
        standaloneCount = standaloneCount + 1;
        fprintf('  [%d/%d] Submitted: %-25s  job=%s  backend=%s  shots=%d\n', ...
            i, nSubmit, cname, jid, cfg.backend, cfg.shots);
    catch ME
        fprintf('  [%d/%d] FAILED:   %-25s  %s\n', i, nSubmit, cname, ME.message);
    end
end

% 4b. Project-scoped jobs (POST /api/projects/{id}/jobs)
projectCount = 0;
nProjJobs = min(nProj, 5);

for i = 1:nProjJobs
    proj = projects(i);
    pid  = string(proj.project_id);
    name = string(proj.name);

    circIdx = mod(i - 1, nCirc) + 1;
    circ    = circuits(circIdx);
    cid     = string(circ.circuit_id);

    cfgIdx = mod(i - 1, numel(jobConfigs)) + 1;
    cfg    = jobConfigs{cfgIdx};

    url     = sprintf('%s/api/projects/%s/jobs', BASE_URL, pid);
    payload = struct( ...
        'circuit_id',         cid, ...
        'backend_name',       cfg.backend, ...
        'shots',              cfg.shots, ...
        'optimization_level', cfg.opt);

    try
        resp = webwrite(url, payload, postOpts);
        jid  = string(resp.job_record_id);
        jobIds{end+1} = jid; %#ok<SAGROW>
        projectCount = projectCount + 1;
        fprintf('  Project: %-35s  job=%s\n', name, jid);
    catch ME
        fprintf('  Project FAILED: %-30s  %s\n', name, ME.message);
    end
end

fprintf('\n=== Done: %d standalone + %d project jobs submitted ===\n', ...
    standaloneCount, projectCount);
if ~isempty(jobIds)
    fprintf('Job IDs available in workspace variable "jobIds"\n\n');
end
