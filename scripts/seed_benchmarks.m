% seed_benchmarks.m ────────────────────────────────────────────────────────────
% Saves benchmark configurations and runs strategy comparisons for projects.
%
% Usage:
%   >> run('scripts/seed_benchmarks.m')
%
% Provides data for: Benchmark screen (config panel + strategy table)
% Prerequisites: seed_projects.m, seed_circuits.m, seed_backends.m
% ──────────────────────────────────────────────────────────────────────────────

fprintf('\n=== QTAU Seed: Configuring benchmarks for projects ===\n\n');

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
getOpts = weboptions('Timeout', 30, 'ContentType', 'json', 'HeaderFields', authHeader);
postOpts = weboptions('Timeout', 30, 'MediaType', 'application/json', ...
    'ContentType', 'json', 'HeaderFields', authHeader);

% ── Step 2: Fetch projects ───────────────────────────────────────────────────
fprintf('[2/4] Fetching projects ... ');
try
    projResp = webread([BASE_URL '/api/projects'], getOpts);
    projects = projResp.projects;
    nProj = numel(projects);
    fprintf('found %d\n', nProj);
catch ME
    fprintf('FAILED (%s)\n', ME.message); return;
end

% ── Step 3: Fetch circuits ───────────────────────────────────────────────────
fprintf('[3/4] Fetching circuits ... ');
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

% ── Step 4: Save benchmark configs ───────────────────────────────────────────
fprintf('[4/4] Saving benchmark configurations ...\n');

% Configuration presets to cycle through
configs = { ...
    struct('shots', 1024, 'optimization_level', 1, ...
           'error_mitigation', 'none', ...
           'transpilation_strategy', 'sabre'); ...
    struct('shots', 4096, 'optimization_level', 2, ...
           'error_mitigation', 'measurement_mitigation', ...
           'transpilation_strategy', 'sabre'); ...
    struct('shots', 8192, 'optimization_level', 3, ...
           'error_mitigation', 'dynamical_decoupling', ...
           'transpilation_strategy', 'stochastic'); ...
    struct('shots', 4096, 'optimization_level', 2, ...
           'error_mitigation', 'readout_calibration', ...
           'transpilation_strategy', 'basic'); ...
    struct('shots', 2048, 'optimization_level', 1, ...
           'error_mitigation', 'zero_noise_extrapolation', ...
           'transpilation_strategy', 'sabre'); ...
};

% Backend names to pair with circuits
backendNames = {'ibm_brisbane', 'ibm_sherbrooke', 'ibm_kyoto', 'ibm_osaka'};

configCount  = 0;
compareCount = 0;

for i = 1:nProj
    proj = projects(i);
    pid  = string(proj.project_id);
    name = string(proj.name);

    % Pick a circuit and config for this project
    circIdx = mod(i - 1, nCirc) + 1;
    circ    = circuits(circIdx);
    cid     = string(circ.circuit_id);

    cfgIdx  = mod(i - 1, numel(configs)) + 1;
    cfg     = configs{cfgIdx};

    bkIdx   = mod(i - 1, numel(backendNames)) + 1;
    backend = backendNames{bkIdx};

    % 4a. Save benchmark config
    payload = struct( ...
        'circuit_id',             cid, ...
        'backend_name',           backend, ...
        'shots',                  cfg.shots, ...
        'optimization_level',     cfg.optimization_level, ...
        'error_mitigation',       cfg.error_mitigation, ...
        'transpilation_strategy', cfg.transpilation_strategy);

    url = sprintf('%s/api/projects/%s/benchmark-config', BASE_URL, pid);
    try
        webwrite(url, payload, postOpts);
        configCount = configCount + 1;
        fprintf('  [%2d/%d] Config  %-35s  shots=%d opt=%d\n', ...
            i, nProj, name, cfg.shots, cfg.optimization_level);
    catch ME
        fprintf('  [%2d/%d] Config  FAILED: %-30s  %s\n', i, nProj, name, ME.message);
    end

    % 4b. Compare strategies (for first 5 projects)
    if i <= 5
        compareUrl = sprintf('%s/api/projects/%s/benchmark-config/compare-strategies', BASE_URL, pid);
        comparePayload = struct('circuit_id', cid, 'backend_name', backend);
        try
            webwrite(compareUrl, comparePayload, postOpts);
            compareCount = compareCount + 1;
            fprintf('          -> Strategy comparison done\n');
        catch ME
            fprintf('          -> Strategy comparison FAILED: %s\n', ME.message);
        end
    end
end

fprintf('\n=== Done: %d configs saved, %d strategy comparisons ===\n\n', ...
    configCount, compareCount);
