% seed_qasmbench_invalid.m ─────────────────────────────────────────────────────
% Re-uploads the 25 QASMBench circuits that were previously marked INVALID
% by the backend (before the qiskit LEGACY gate-set fix).
%
% After the backend fix (qasm2.loads with LEGACY_CUSTOM_INSTRUCTIONS),
% 22 of these now parse correctly.  Only 3 remain truly invalid due to
% upstream QASMBench bugs (vqe_uccsd_n4/n6/n8 reference undefined `q[]`).
%
% This script deletes the old INVALID copies first, then re-uploads so
% the backend can re-validate with the corrected parser.
%
% Usage:
%   >> run('scripts/seed_qasmbench_invalid.m')
%
% Provides data for: Upload screen, Analysis screen
% ──────────────────────────────────────────────────────────────────────────────

fprintf('\n=== QTAU Seed: Re-uploading 25 previously-INVALID QASMBench circuits ===\n\n');

% ── Configuration ───────────────────────────────────────────────────────────
cfg      = seed_helpers.loadConfig();
BASE_URL = cfg.base_url;

% ── Resolve samples/qasmbench path ──────────────────────────────────────────
rootDir = fullfile(fileparts(mfilename('fullpath')), '..', 'samples', 'qasmbench');
if ~isfolder(rootDir)
    error('seed_qasmbench_invalid:notFound', ...
        'samples/qasmbench/ not found. Clone QASMBench files first.');
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

% ── Step 2: Define the 25 previously-INVALID circuits ───────────────────────
fprintf('[2/4] Preparing circuit list ...\n');

% Category mapping (same as seed_qasmbench.m)
catMap = struct( ...
    'basis_test',       'Simulation', ...
    'basis_trotter',    'Simulation', ...
    'dnn',              'Machine Learning', ...
    'gcm',              'Cryptography', ...
    'knn',              'Machine Learning', ...
    'qugan',            'Machine Learning', ...
    'shor',             'Factoring', ...
    'swap_test',        'State Comparison', ...
    'vqe',              'Variational', ...
    'vqe_uccsd',        'Variational' ...
);
catFields = fieldnames(catMap);

invalidList = { ...
%   scale     filename
    'small',  'basis_test_n4.qasm'; ...
    'small',  'basis_trotter_n4.qasm'; ...
    'small',  'shor_n5.qasm'; ...
    'small',  'vqe_n4.qasm'; ...
    'small',  'vqe_uccsd_n4.qasm'; ...
    'small',  'vqe_uccsd_n6.qasm'; ...
    'small',  'vqe_uccsd_n8.qasm'; ...
    'medium', 'gcm_h6.qasm'; ...
    'medium', 'knn_n25.qasm'; ...
    'medium', 'swap_test_n25.qasm'; ...
    'large',  'dnn_n33.qasm'; ...
    'large',  'dnn_n51.qasm'; ...
    'large',  'knn_129.qasm'; ...
    'large',  'knn_341.qasm'; ...
    'large',  'knn_n31.qasm'; ...
    'large',  'knn_n41.qasm'; ...
    'large',  'knn_n67.qasm'; ...
    'large',  'qugan_n111.qasm'; ...
    'large',  'qugan_n39.qasm'; ...
    'large',  'qugan_n395.qasm'; ...
    'large',  'qugan_n71.qasm'; ...
    'large',  'swap_test_n115.qasm'; ...
    'large',  'swap_test_n361.qasm'; ...
    'large',  'swap_test_n41.qasm'; ...
    'large',  'swap_test_n83.qasm'; ...
};

totalFiles = size(invalidList, 1);

% Build file entries
files = {};
for i = 1:totalFiles
    scale = invalidList{i, 1};
    fname = invalidList{i, 2};
    fpath = fullfile(rootDir, scale, fname);

    if ~isfile(fpath)
        fprintf('  MISSING: %s/%s\n', scale, fname);
        continue;
    end

    % Parse qubit count from filename
    nqTok = regexp(fname, '_n(\d+)', 'tokens', 'once');
    if ~isempty(nqTok)
        nQubits = str2double(nqTok{1});
    else
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
        'nQubits',  nQubits);
    files{end+1} = entry; %#ok<SAGROW>
end

totalFiles = numel(files);
fprintf('  Found %d files to re-upload\n', totalFiles);

% ── Step 3: Delete old INVALID copies by name ──────────────────────────────
fprintf('[3/4] Deleting old copies of these circuits ... ');
getOpts    = seed_helpers.getOpts(token);
deleteOpts = weboptions('Timeout', 30, 'RequestMethod', 'delete', ...
    'HeaderFields', {'Authorization', char("Bearer " + token)});
deleteCount = 0;

% Build lookup set of filenames to delete
deleteNames = {};
for i = 1:totalFiles
    deleteNames{end+1} = files{i}.name; %#ok<SAGROW>
end

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
            cname = '';
            if isstruct(items(k)) && isfield(items(k), 'name')
                cname = char(string(items(k).name));
            end
            if ismember(cname, deleteNames)
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
fprintf('[4/4] Uploading %d circuits ...\n', totalFiles);

uploadUrl    = [BASE_URL '/api/circuits/upload'];
opts         = seed_helpers.postOpts(token);
successCount = 0;
validCount   = 0;
invalidCount = 0;
circuitIds   = {};

for i = 1:totalFiles
    entry = files{i};

    % Read file content
    fid = fopen(entry.path, 'r');
    if fid < 0
        fprintf('  [%2d/%d] FAILED (cannot read): %s\n', i, totalFiles, entry.name);
        continue;
    end
    content = fread(fid, '*char')';
    fclose(fid);

    payload = struct( ...
        'name',     entry.name, ...
        'format',   'qasm2', ...
        'category', entry.category, ...
        'source',   'QASMBench', ...
        'content',  content);

    try
        resp = webwrite(uploadUrl, payload, opts);
        cid  = string(resp.circuit_id);
        circuitIds{end+1} = cid; %#ok<SAGROW>
        successCount = successCount + 1;

        if isfield(resp, 'is_valid') && resp.is_valid
            valid = 'valid';
            validCount = validCount + 1;
        else
            valid = 'INVALID';
            invalidCount = invalidCount + 1;
        end
        fprintf('  [%2d/%d] Uploaded: %-45s  %5s  %3dq  id=%s  (%s)\n', ...
            i, totalFiles, entry.name, entry.scale, entry.nQubits, cid, valid);
    catch ME
        fprintf('  [%2d/%d] FAILED:  %-45s  %s\n', i, totalFiles, entry.name, ME.message);
    end
end

fprintf('\n=== Done: %d uploaded (%d valid, %d still invalid) out of %d ===\n', ...
    successCount, validCount, invalidCount, totalFiles);
if ~isempty(circuitIds)
    fprintf('Circuit IDs available in workspace variable "circuitIds"\n\n');
end
