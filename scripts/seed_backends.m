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
cfg      = seed_helpers.loadConfig();
BASE_URL = cfg.base_url;

% ── Step 1: Authenticate ────────────────────────────────────────────────────
fprintf('[1/3] Logging in as "%s" ... ', cfg.username);
try
    token = seed_helpers.login(BASE_URL, cfg.login_path, cfg.username, cfg.password);
    fprintf('OK\n');
catch ME
    fprintf('FAILED\n  %s\n', ME.message);
    return;
end

% ── Step 2: Fetch projects ───────────────────────────────────────────────────
fprintf('[2/3] Fetching projects ... ');
getOpts = seed_helpers.getOpts(token);

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

% IBM Quantum backend names — cycle through the current IBM Cloud fleet
backendPairs = { ...
    struct('primary', 'ibm_boston',     'backup', 'ibm_fez'); ...
    struct('primary', 'ibm_fez',        'backup', 'ibm_pittsburgh'); ...
    struct('primary', 'ibm_pittsburgh', 'backup', 'ibm_kingston'); ...
    struct('primary', 'ibm_kingston',   'backup', 'ibm_miami'); ...
    struct('primary', 'ibm_miami',      'backup', 'ibm_marrakesh'); ...
    struct('primary', 'ibm_marrakesh',  'backup', 'ibm_boston'); ...
};

postOpts = seed_helpers.postOpts(token);

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
