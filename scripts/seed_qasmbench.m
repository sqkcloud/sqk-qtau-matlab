% seed_qasmbench.m ─────────────────────────────────────────────────────────────
% Uploads QTAUBench circuits from samples/qasmbench/ via the QTAU Connector
% REST API.  Files are read from disk (small/, medium/, large/ subdirectories).
%
% Usage:
%   >> run('scripts/seed_qasmbench.m')
%
% Options (set in workspace before running):
%   MAX_FILE_KB   – skip .qasm files larger than this (default 512 KB)
%   INCLUDE_TRANSPILED – upload *_transpiled.qasm too (default false)
%
% Provides data for: Upload screen, Analysis screen
% ──────────────────────────────────────────────────────────────────────────────

fprintf('\n=== QTAU Seed: Uploading QTAUBench circuits ===\n\n');

% ── User-tuneable knobs ─────────────────────────────────────────────────────
if ~exist('MAX_FILE_KB', 'var'),        MAX_FILE_KB = 512;           end
if ~exist('INCLUDE_TRANSPILED', 'var'), INCLUDE_TRANSPILED = false;  end

maxBytes = MAX_FILE_KB * 1024;

% ── Configuration ───────────────────────────────────────────────────────────
cfg      = seed_helpers.loadConfig();
BASE_URL = cfg.base_url;

% ── Resolve samples/qasmbench path ──────────────────────────────────────────
rootDir = fullfile(fileparts(mfilename('fullpath')), '..', 'samples', 'qasmbench');
if ~isfolder(rootDir)
    error('seed_qasmbench:notFound', ...
        'samples/qasmbench/ not found. Clone QTAUBench files first.');
end

% ── Step 1: Authenticate ────────────────────────────────────────────────────
fprintf('[1/4] Logging in as "%s" ... ', cfg.username);
try
    token = seed_helpers.login(BASE_URL, cfg.login_path, cfg.username, cfg.password);
    fprintf('OK\n');
catch ME
    fprintf('FAILED\n  %s\n', ME.message);
    return;
end

% ── Step 2: Discover .qasm files ────────────────────────────────────────────
fprintf('[2/4] Scanning samples/qasmbench/ ...\n');

categories = {'small', 'medium', 'large'};
files      = {};   % each entry: struct(path, name, scale, category, nQubits)

% ── Category mapping based on circuit-name prefix ───────────────────────────
%    Maps the algorithm prefix (e.g. "grover", "qft") to a human-readable
%    category string used in the upload payload.
catMap = struct( ...
    'adder',            'Arithmetic', ...
    'basis_change',     'Basis', ...
    'basis_trotter',    'Simulation', ...
    'basis_test',       'Simulation', ...
    'bb84',             'Cryptography', ...
    'bell',             'Entanglement', ...
    'bigadder',         'Arithmetic', ...
    'bv',               'Oracle', ...
    'bwt',              'Walk', ...
    'cat',              'Entanglement', ...
    'cat_state',        'Entanglement', ...
    'cc',               'Counting', ...
    'deutsch',          'Oracle', ...
    'dnn',              'Machine Learning', ...
    'error_correctiond3', 'Error Correction', ...
    'factor247',        'Factoring', ...
    'fredkin',          'Gate', ...
    'gcm',              'Cryptography', ...
    'ghz',              'Entanglement', ...
    'ghz_state',        'Entanglement', ...
    'grover',           'Search', ...
    'hhl',              'Linear Algebra', ...
    'hs4',              'Hidden Subgroup', ...
    'inverseqft',       'Fourier', ...
    'ipea',             'Phase Estimation', ...
    'ising',            'Simulation', ...
    'iswap',            'Gate', ...
    'knn',              'Machine Learning', ...
    'linearsolver',     'Linear Algebra', ...
    'lpn',              'Cryptography', ...
    'multiplier',       'Arithmetic', ...
    'multiply',         'Arithmetic', ...
    'pea',              'Phase Estimation', ...
    'qaoa',             'Optimization', ...
    'qec_en',           'Error Correction', ...
    'qec_sm',           'Error Correction', ...
    'qec9xz',           'Error Correction', ...
    'qf21',             'Factoring', ...
    'qft',              'Fourier', ...
    'qpe',              'Phase Estimation', ...
    'qram',             'Memory', ...
    'qrng',             'Random', ...
    'quantumwalks',     'Walk', ...
    'qugan',            'Machine Learning', ...
    'random_QAOA',      'Optimization', ...
    'QV',               'Volume', ...
    'sat',              'Satisfiability', ...
    'seca',             'Arithmetic', ...
    'shor',             'Factoring', ...
    'simon',            'Oracle', ...
    'square_root',      'Arithmetic', ...
    'swap_test',        'State Comparison', ...
    'teleportation',    'Entanglement', ...
    'toffoli',          'Gate', ...
    'variational',      'Variational', ...
    'vqe',              'Variational', ...
    'vqe_uccsd',        'Variational', ...
    'wstate',           'Entanglement' ...
);

catFields = fieldnames(catMap);

for s = 1:numel(categories)
    scale  = categories{s};
    subDir = fullfile(rootDir, scale);
    if ~isfolder(subDir), continue; end

    listing = dir(fullfile(subDir, '*.qasm'));
    for f = 1:numel(listing)
        fname = listing(f).name;
        fpath = fullfile(subDir, fname);
        fsize = listing(f).bytes;

        % Skip transpiled if not requested
        if ~INCLUDE_TRANSPILED && contains(fname, '_transpiled')
            continue;
        end

        % Skip files above the size limit
        if fsize > maxBytes
            fprintf('  SKIP (%.0f KB > %d KB limit): %s\n', fsize/1024, MAX_FILE_KB, fname);
            continue;
        end

        % Parse qubit count from filename (e.g. "grover_n2.qasm" → 2)
        nqTok = regexp(fname, '_n(\d+)', 'tokens', 'once');
        if ~isempty(nqTok)
            nQubits = str2double(nqTok{1});
        else
            % Fallback: try bare number like "32.qasm" or "100.qasm"
            nqTok = regexp(fname, '^(\d+)\.qasm$', 'tokens', 'once');
            if ~isempty(nqTok)
                nQubits = str2double(nqTok{1});
            else
                nQubits = 0;
            end
        end

        % Determine algorithm category from prefix
        circCat = 'General';
        for c = 1:numel(catFields)
            prefix = catFields{c};
            if startsWith(fname, prefix)
                circCat = catMap.(prefix);
                break;
            end
        end

        entry = struct( ...
            'path',     fpath, ...
            'name',     fname, ...
            'scale',    scale, ...
            'category', circCat, ...
            'nQubits',  nQubits, ...
            'bytes',    fsize);
        files{end+1} = entry; %#ok<SAGROW>
    end
end

totalFiles = numel(files);
fprintf('  Found %d files to upload (max %d KB, transpiled=%s)\n', ...
    totalFiles, MAX_FILE_KB, string(INCLUDE_TRANSPILED));

if totalFiles == 0
    fprintf('\nNo files to upload. Adjust MAX_FILE_KB or INCLUDE_TRANSPILED.\n');
    return;
end

% ── Step 3: Delete existing QTAUBench circuits ──────────────────────────────
fprintf('[3/4] Deleting existing QTAUBench circuits ... ');
getOpts    = seed_helpers.getOpts(token);
deleteOpts = weboptions('Timeout', 30, 'RequestMethod', 'delete', ...
    'HeaderFields', {'Authorization', char("Bearer " + token)});
deleteCount = 0;
try
    % Phase 1: Collect IDs to delete (paginate without mutating)
    idsToDelete = {};
    pageSkip  = 0;
    pageLimit = 100;
    while true
        listUrl  = sprintf('%s/api/circuits?skip=%d&limit=%d', BASE_URL, pageSkip, pageLimit);
        circResp = webread(listUrl, getOpts);
        if isstruct(circResp) && isfield(circResp, 'circuits')
            items = circResp.circuits;
        else
            items = circResp;
        end
        if isempty(items), break; end

        for k = 1:numel(items)
            src = '';
            if isstruct(items(k)) && isfield(items(k), 'source')
                src = string(items(k).source);
            end
            if src == "QTAUBench"
                idsToDelete{end+1} = char(string(items(k).circuit_id)); %#ok<SAGROW>
            end
        end

        if numel(items) < pageLimit, break; end
        pageSkip = pageSkip + pageLimit;
    end

    % Phase 2: Delete collected IDs
    for d = 1:numel(idsToDelete)
        try
            delUrl = sprintf('%s/api/circuits/%s', BASE_URL, idsToDelete{d});
            webread(delUrl, deleteOpts);
            deleteCount = deleteCount + 1;
        catch
            deleteCount = deleteCount + 1;
        end
    end
    fprintf('deleted %d\n', deleteCount);
catch
    fprintf('(none found or could not check)\n');
end

% ── Step 4: Upload circuits ─────────────────────────────────────────────────
fprintf('[4/4] Uploading %d QTAUBench circuits ...\n', totalFiles);

uploadUrl    = [BASE_URL '/api/circuits/upload'];
opts         = seed_helpers.postOpts(token);
successCount = 0;
circuitIds   = {};

for i = 1:totalFiles
    entry = files{i};

    % Read file content
    fid = fopen(entry.path, 'r');
    if fid < 0
        fprintf('  [%3d/%d] FAILED (cannot read): %s\n', i, totalFiles, entry.name);
        continue;
    end
    content = fread(fid, '*char')';
    fclose(fid);

    payload = struct( ...
        'name',     entry.name, ...
        'format',   'qasm2', ...
        'category', entry.category, ...
        'source',   'QTAUBench', ...
        'content',  content);

    try
        resp = webwrite(uploadUrl, payload, opts);
        cid  = string(resp.circuit_id);
        circuitIds{end+1} = cid; %#ok<SAGROW>
        successCount = successCount + 1;

        valid = 'valid';
        if isfield(resp, 'is_valid') && ~resp.is_valid
            valid = 'INVALID';
        end
        fprintf('  [%3d/%d] Uploaded: %-45s  %5s  %3dq  id=%s  (%s)\n', ...
            i, totalFiles, entry.name, entry.scale, entry.nQubits, cid, valid);
    catch ME
        fprintf('  [%3d/%d] FAILED:  %-45s  %s\n', i, totalFiles, entry.name, ME.message);
    end
end

fprintf('\n=== Done: %d uploaded out of %d ===\n', successCount, totalFiles);
fprintf('  (skipped transpiled=%s, max size=%d KB)\n', ...
    string(~INCLUDE_TRANSPILED), MAX_FILE_KB);
if ~isempty(circuitIds)
    fprintf('Circuit IDs available in workspace variable "circuitIds"\n\n');
end
