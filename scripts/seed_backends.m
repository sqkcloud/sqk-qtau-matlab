% seed_backends.m ──────────────────────────────────────────────────────────────
% Saves backend selections for every project via the QTAU Connector REST API.
%
% Usage:
%   >> run('scripts/seed_backends.m')
%
% Provides data for: Backends screen (backend-selection panel)
% Prerequisite : seed_projects.m (projects must exist)
% ──────────────────────────────────────────────────────────────────────────────

fprintf('\n=== QTAU Seed: Saving backend selections for projects ===\n\n');

% ── Configuration ────────────────────────────────────────────────────────────
BASE_URL   = 'http://34.42.87.190:5715';
LOGIN_PATH = '/api/auth/login';
USERNAME   = 'admin';
PASSWORD   = 'passw0rd';

% ── Step 1: Authenticate ────────────────────────────────────────────────────
fprintf('[1/3] Logging in as "%s" ... ', USERNAME);
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

% ── Step 2: Fetch projects ───────────────────────────────────────────────────
fprintf('[2/3] Fetching projects ... ');
getOpts = weboptions( ...
    'Timeout',      30, ...
    'ContentType',  'json', ...
    'HeaderFields', {'Authorization', char("Bearer " + token)});

try
    projResp = webread([BASE_URL '/api/projects'], getOpts);
    if isstruct(projResp) && isfield(projResp, 'projects')
        projects = projResp.projects;
    else
        projects = projResp;
    end
    if isstruct(projects)
        nProj = numel(projects);
    else
        nProj = numel(projects);
    end
    fprintf('found %d projects\n', nProj);
catch ME
    fprintf('FAILED (%s)\n', ME.message);
    return;
end

if nProj == 0
    fprintf('  No projects found. Run seed_projects.m first.\n');
    return;
end

% ── Step 3: Assign backend selections ────────────────────────────────────────
fprintf('[3/3] Saving backend selections ...\n');

% IBM Quantum backend names — cycle through these
backendPairs = { ...
    struct('primary', 'ibm_brisbane',   'backup', 'ibm_sherbrooke'); ...
    struct('primary', 'ibm_sherbrooke', 'backup', 'ibm_kyoto'); ...
    struct('primary', 'ibm_kyoto',      'backup', 'ibm_brisbane'); ...
    struct('primary', 'ibm_osaka',      'backup', 'ibm_brisbane'); ...
    struct('primary', 'ibm_brisbane',   'backup', 'ibm_osaka'); ...
    struct('primary', 'ibm_sherbrooke', 'backup', 'ibm_brisbane'); ...
};

postOpts = weboptions( ...
    'Timeout',      30, ...
    'MediaType',    'application/json', ...
    'ContentType',  'json', ...
    'HeaderFields', {'Authorization', char("Bearer " + token)});

successCount = 0;
for i = 1:nProj
    proj = projects(i);
    pid  = string(proj.project_id);
    name = string(proj.name);

    pairIdx = mod(i - 1, numel(backendPairs)) + 1;
    pair    = backendPairs{pairIdx};

    payload = struct( ...
        'primary_backend_id', pair.primary, ...
        'backup_backend_id',  pair.backup);

    url = sprintf('%s/api/projects/%s/backend-selection', BASE_URL, pid);
    try
        webwrite(url, payload, postOpts);
        successCount = successCount + 1;
        fprintf('  [%2d/%d] %-40s  primary=%-15s backup=%s\n', ...
            i, nProj, name, pair.primary, pair.backup);
    catch ME
        % Show HTTP status if available for easier debugging
        msg = ME.message;
        if contains(msg, '404')
            msg = [msg ' (endpoint may not exist — check API version)'];
        elseif contains(msg, '422')
            msg = [msg ' (payload validation failed — check field names)'];
        end
        fprintf('  [%2d/%d] FAILED: %-40s  %s\n', i, nProj, name, msg);
    end
end

fprintf('\n=== Done: %d / %d backend selections saved ===\n\n', successCount, nProj);
