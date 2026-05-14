% seed_qae.m ──────────────────────────────────────────────────────────────────
% Seeds the AQS-QMC Quantum Amplitude Estimation VaR reference circuit for the
% Quantum Monte Carlo Simulation (Quantum Amplitude Estimation) feature.
%
% Uploads samples/aqs-qmc/AQS OpenQASM VaR 7q ibm_marrakesh.20260406111331.qasm
% into every project via POST /api/circuits/upload, then immediately runs a
% statevector-mode QAE analysis (POST /api/circuits/{id}/qae/analyze) so the
% Analysis screen's Quantum Amplitude Estimation popup opens with data already
% populated (amplitude, VaR, path PDF, convergence curve, Greeks, ZNE curve).
%
% Usage:
%   >> run('scripts/seed_qae.m')
%
% Provides data for : Analysis screen (Quantum Amplitude Estimation popup),
%                     Reports screen (Quantum Monte Carlo report section).
% Prerequisite      : seed_projects.m (projects must exist).
% Downstream        : none — this is a leaf seed.
% ──────────────────────────────────────────────────────────────────────────────

fprintf('\n=== QTAU Seed: AQS-QMC VaR reference circuit (Quantum Amplitude Estimation) ===\n\n');

% ── Configuration ───────────────────────────────────────────────────────────
cfg      = seed_helpers.loadConfig();
BASE_URL = cfg.base_url;

thisDir      = fileparts(mfilename('fullpath'));
projectRoot  = fullfile(thisDir, '..');
qasmFileName = 'AQS OpenQASM VaR 7q ibm_marrakesh.20260406111331.qasm';
qasmPath     = fullfile(projectRoot, 'samples', 'aqs-qmc', qasmFileName);

if exist(qasmPath, 'file') ~= 2
    fprintf('FAILED: sample file not found at\n  %s\n', qasmPath);
    return;
end

% ── Step 1: Authenticate ────────────────────────────────────────────────────
fprintf('[1/5] Logging in as "%s" ... ', cfg.username);
try
    token = seed_helpers.login(BASE_URL, cfg.login_path, cfg.username, cfg.password);
    fprintf('OK\n');
catch ME
    fprintf('FAILED\n  %s\n', ME.message);
    return;
end

% ── Step 2: Fetch projects ──────────────────────────────────────────────────
fprintf('[2/5] Fetching projects ... ');
getOpts = seed_helpers.getOpts(token);
try
    projResp = webread([BASE_URL '/api/projects'], getOpts);
    if isstruct(projResp) && isfield(projResp, 'projects')
        projects = projResp.projects;
    else
        projects = projResp;
    end
    nProj = numel(projects);
    fprintf('found %d projects\n', nProj);
catch ME
    fprintf('FAILED (%s)\n', ME.message);
    return;
end
if nProj == 0
    fprintf('  No projects found. Run seed_projects.m first.\n');
    return;
end

% ── Step 3: Load the QASM file from disk ────────────────────────────────────
fprintf('[3/5] Reading %s ... ', qasmFileName);
try
    fid = fopen(qasmPath, 'r');
    if fid < 0
        error('Could not open %s', qasmPath);
    end
    cleanup  = onCleanup(@() fclose(fid));
    qasmText = fread(fid, '*char')';
    fprintf('OK (%d bytes)\n', numel(qasmText));
catch ME
    fprintf('FAILED\n  %s\n', ME.message);
    return;
end
circuit = struct( ...
    'name',     'aqs_qmc_var_7q_ibm_marrakesh', ...
    'format',   'qasm2', ...
    'category', 'Risk analysis', ...
    'source',   'AQS-QMC reference', ...
    'content',  qasmText);

% ── Step 4: Upload (or reuse existing) per project ──────────────────────────
% Idempotent: if a circuit with the same name already exists in the
% project (re-run of the seed, or shared via seed_qasmbench), skip the
% upload and reuse that circuit_id. The server enforces a unique
% (project_id, name) index and would otherwise reply HTTP 409 Conflict.
fprintf('[4/5] Upload-or-reuse QAE reference circuit in every project ...\n');

uploadUrl = [BASE_URL '/api/circuits/upload'];
authHdr   = {'Authorization', char("Bearer " + token); ...
             'Accept',        'application/json'};

uploadedIds = cell(nProj, 1);
uploadedCount = 0;
reusedCount   = 0;
failedCount   = 0;
for p = 1:nProj
    pid  = char(string(projects(p).project_id));
    name = char(string(projects(p).name));
    projHdr = [authHdr; {'X-Project-Id', pid}];
    postOpts = weboptions('Timeout', 60, ...
        'MediaType', 'application/json', 'ContentType', 'json', ...
        'HeaderFields', projHdr);
    listOpts = weboptions('Timeout', 30, 'ContentType', 'json', ...
        'HeaderFields', projHdr);

    % --- Look for an existing circuit with the target name --------------
    cid = '';
    try
        listResp = webread([BASE_URL '/api/circuits'], listOpts);
        if isstruct(listResp) && isfield(listResp, 'circuits')
            items = listResp.circuits;
        else
            items = listResp;
        end
        for k = 1:numel(items)
            if isfield(items(k), 'name') && strcmp(char(string(items(k).name)), circuit.name)
                cid = char(string(items(k).circuit_id));
                break;
            end
        end
    catch
        % Project may be empty or the list call failed — fall through to
        % the upload path below and let that surface the real error.
    end

    if ~isempty(cid)
        uploadedIds{p} = cid;
        reusedCount = reusedCount + 1;
        fprintf('  [%2d/%d] %-40s  reused     → %s\n', p, nProj, name, cid);
        continue;
    end

    % --- Otherwise upload a fresh copy ---------------------------------
    try
        resp = webwrite(uploadUrl, circuit, postOpts);
        cid  = char(string(resp.circuit_id));
        uploadedIds{p} = cid;
        uploadedCount = uploadedCount + 1;
        fprintf('  [%2d/%d] %-40s  uploaded   → %s\n', p, nProj, name, cid);
    catch ME
        uploadedIds{p} = '';
        failedCount = failedCount + 1;
        fprintf('  [%2d/%d] %-40s  FAILED (%s)\n', p, nProj, name, ME.message);
    end
end

fprintf('  → %d uploaded, %d reused, %d failed (out of %d projects)\n', ...
    uploadedCount, reusedCount, failedCount, nProj);

% ── Step 5: Run QAE analysis on every uploaded circuit ──────────────────────
% Statevector mode is used so the seed does not require IBM Runtime
% credentials. Results are cached on the circuit document, so the
% Analysis screen popup opens with full data populated.
fprintf('[5/5] Running statevector QAE analysis on each uploaded circuit ...\n');

analyzed = 0;
for p = 1:nProj
    cid = uploadedIds{p};
    if isempty(cid); continue; end
    pid  = char(string(projects(p).project_id));
    name = char(string(projects(p).name));

    analyzeUrl = sprintf('%s/api/circuits/%s/qae/analyze', BASE_URL, cid);
    opts = weboptions('Timeout', 180, ...
        'MediaType', 'application/json', 'ContentType', 'json', ...
        'HeaderFields', [authHdr; {'X-Project-Id', pid}]);
    payload = struct( ...
        'execution_mode',   'statevector', ...
        'shots',            4096, ...
        'epsilon',          0.01, ...
        'confidence_level', 0.95, ...
        'num_eval_qubits',  7, ...
        'risk_metric',      'var_95', ...
        'mitigation',       'zne', ...
        'compute_greeks',   true, ...
        'market', struct( ...
            'spot',             100.0, ...
            'strike',           100.0, ...
            'volatility',       0.20, ...
            'risk_free_rate',   0.05, ...
            'time_to_maturity', 0.0833, ...
            'option_type',      'call', ...
            'notional',         100.0));
    try
        resp = webwrite(analyzeUrl, payload, opts);
        amp    = resp.amplitude_estimate;
        var95  = resp.var_95;
        speed  = resp.quadratic_speedup;
        fprintf('  [%2d/%d] %-40s  amp=%.4f  VaR95=%6.2f  speedup=%5.1fx\n', ...
            p, nProj, name, amp, var95, speed);
        analyzed = analyzed + 1;
    catch ME
        fprintf('  [%2d/%d] %-40s  QAE FAILED (%s)\n', p, nProj, name, ME.message);
    end
end

fprintf('\n=== Done: %d uploaded, %d reused, %d QAE analyses across %d projects ===\n', ...
    uploadedCount, reusedCount, analyzed, nProj);
fprintf('Open the Analysis screen → "Quantum Amplitude Estimation" popup to\n');
fprintf('see path PDF, VaR thresholds, CDF, convergence, amplitude bar,\n');
fprintf('Greeks (Δ, Γ, Vega, Θ, ρ), and Zero-Noise Extrapolation curve.\n\n');

if (uploadedCount + reusedCount) > 0
    uploadedIds = uploadedIds(~cellfun(@isempty, uploadedIds));
    fprintf('Circuit IDs available in workspace variable "uploadedIds"\n\n');
end
