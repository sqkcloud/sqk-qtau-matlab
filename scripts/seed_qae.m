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

% ── Step 4: Upload into every project ───────────────────────────────────────
fprintf('[4/5] Uploading QAE reference circuit into every project ...\n');

uploadUrl = [BASE_URL '/api/circuits/upload'];
authHdr   = {'Authorization', char("Bearer " + token); ...
             'Accept',        'application/json'};

uploadedIds = cell(nProj, 1);
successCount = 0;
for p = 1:nProj
    pid  = char(string(projects(p).project_id));
    name = char(string(projects(p).name));
    opts = weboptions('Timeout', 60, ...
        'MediaType', 'application/json', 'ContentType', 'json', ...
        'HeaderFields', [authHdr; {'X-Project-Id', pid}]);
    try
        resp = webwrite(uploadUrl, circuit, opts);
        cid  = char(string(resp.circuit_id));
        uploadedIds{p} = cid;
        successCount = successCount + 1;
        fprintf('  [%2d/%d] %-40s  uploaded → %s\n', p, nProj, name, cid);
    catch ME
        uploadedIds{p} = '';
        fprintf('  [%2d/%d] %-40s  FAILED (%s)\n', p, nProj, name, ME.message);
    end
end

fprintf('  → %d/%d uploads succeeded\n', successCount, nProj);

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

fprintf('\n=== Done: %d uploads, %d QAE analyses across %d projects ===\n', ...
    successCount, analyzed, nProj);
fprintf('Open the Analysis screen → "Quantum Amplitude Estimation" popup to\n');
fprintf('see path PDF, VaR thresholds, CDF, convergence, amplitude bar,\n');
fprintf('Greeks (Δ, Γ, Vega, Θ, ρ), and Zero-Noise Extrapolation curve.\n\n');

if successCount > 0
    uploadedIds = uploadedIds(~cellfun(@isempty, uploadedIds));
    fprintf('Uploaded circuit IDs available in workspace variable "uploadedIds"\n\n');
end
