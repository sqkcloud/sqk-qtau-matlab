classdef BundleService
    % BundleService  Reproducibility-bundle assembler.
    %
    %   Packages a circuit and its surrounding metadata (backend
    %   calibration snapshot, mitigation estimates, FT resource
    %   estimate, RNG seeds) into a single ZIP that a colleague or
    %   future-you can use to reproduce an experiment cleanly.
    %
    %   Public API:
    %     BundleService.assemble(ctx, opts)   → savedPath
    %     BundleService.defaultName(ctx)      → char
    %
    %   Context shape (`ctx`):
    %     .circuit              CircuitModel handle (required)
    %     .circuitName          char (display name; 'untitled' if empty)
    %     .backend              struct('name', 'calibration') | []
    %     .mitigationEstimates  containers.Map | struct | []
    %     .ftResult             struct (ResourceEstimatorService output) | []
    %     .ftParams             struct (FT input params)              | []
    %
    %   Options shape (`opts`):
    %     .savePath          char (absolute path to target .zip)
    %     .includeCircuit    logical (default true)
    %     .includeBackend    logical (default true if backend present)
    %     .includeMitigation logical (default true if estimates present)
    %     .includeFt         logical (default true if ftResult present)

    properties (Constant)
        BUNDLE_VERSION = '1.0'
    end

    methods (Static)
        function name = defaultName(ctx)
            base = 'qtau-bundle';
            if isstruct(ctx) && isfield(ctx, 'circuitName') && ~isempty(ctx.circuitName)
                base = [base '-' BundleService.sanitizeName(ctx.circuitName)];
            end
            stamp = datestr(now, 'yyyymmdd-HHMMSS'); %#ok<DATST,TNOW1>
            name = sprintf('%s-%s.zip', base, stamp);
        end

        function savedPath = assemble(ctx, opts)
            BundleService.validateCtx(ctx);
            opts = BundleService.normalizeOpts(opts, ctx);

            tmpDir = [tempname() '-bundle'];
            mkdir(tmpDir);
            cleanupObj = onCleanup(@() BundleService.rmTree(tmpDir));

            files = {};

            % ── Circuit artefacts ────
            if opts.includeCircuit
                circDir = fullfile(tmpDir, 'circuit');
                mkdir(circDir);
                BundleService.writeText(fullfile(circDir, 'original.qasm'),       ctx.circuit.toQasm());
                BundleService.writeText(fullfile(circDir, 'original.qiskit.py'),  ctx.circuit.toQiskitPython());
                BundleService.writeText(fullfile(circDir, 'original.cirq.py'),    ctx.circuit.toCirqPython());
                BundleService.writeText(fullfile(circDir, 'original.braket.py'),  ctx.circuit.toBraketPython());
                BundleService.writeText(fullfile(circDir, 'meta.json'),           ...
                    BundleService.encodeJson(BundleService.buildMeta(ctx)));
                files = [files, {
                    'circuit/original.qasm', 'circuit/original.qiskit.py', ...
                    'circuit/original.cirq.py', 'circuit/original.braket.py', ...
                    'circuit/meta.json'}];
            end

            % ── Backend snapshot ────
            backend = BundleService.safeField(ctx, 'backend', []);
            if opts.includeBackend && ~isempty(backend)
                bDir = fullfile(tmpDir, 'backend');
                mkdir(bDir);
                bname = BundleService.safeField(backend, 'name', 'unknown');
                BundleService.writeText(fullfile(bDir, 'name.txt'), char(string(bname)));
                cal = BundleService.safeField(backend, 'calibration', struct());
                BundleService.writeText(fullfile(bDir, 'calibration_snapshot.json'), ...
                    BundleService.encodeJson(cal));
                files = [files, {'backend/name.txt', 'backend/calibration_snapshot.json'}];
            end

            % ── Mitigation estimates ────
            mit = BundleService.safeField(ctx, 'mitigationEstimates', []);
            if opts.includeMitigation && ~isempty(mit)
                mDir = fullfile(tmpDir, 'mitigation');
                mkdir(mDir);
                BundleService.writeText(fullfile(mDir, 'estimates.json'), ...
                    BundleService.encodeJson(BundleService.mapToStruct(mit)));
                files{end+1} = 'mitigation/estimates.json';
            end

            % ── FT resource estimate ────
            ftRes = BundleService.safeField(ctx, 'ftResult', []);
            if opts.includeFt && ~isempty(ftRes)
                fDir = fullfile(tmpDir, 'ft_estimate');
                mkdir(fDir);
                BundleService.writeText(fullfile(fDir, 'parameters.json'), ...
                    BundleService.encodeJson(BundleService.safeField(ctx, 'ftParams', struct())));
                BundleService.writeText(fullfile(fDir, 'result.json'), ...
                    BundleService.encodeJson(ftRes));
                files = [files, {'ft_estimate/parameters.json', 'ft_estimate/result.json'}];
            end

            % ── Seeds placeholder ────
            sDir = fullfile(tmpDir, 'seeds');
            mkdir(sDir);
            seedNote = struct( ...
                'note', 'v1 of the reproducibility bundle does not auto-track classical RNG seeds.', ...
                'next', 'Set seeds explicitly in your reproduction script before re-running.');
            BundleService.writeText(fullfile(sDir, 'rng_seeds.json'), ...
                BundleService.encodeJson(seedNote));
            files{end+1} = 'seeds/rng_seeds.json';

            % ── README + manifest ────
            BundleService.writeText(fullfile(tmpDir, 'README.md'), ...
                BundleService.buildReadme(ctx, opts, files));
            files = [{'README.md'}, files];

            manifest = BundleService.buildManifest(tmpDir, files);
            BundleService.writeText(fullfile(tmpDir, 'manifest.json'), ...
                BundleService.encodeJson(manifest));
            files{end+1} = 'manifest.json';

            % ── ZIP ────
            % MATLAB's zip(zipfile, files, rootfolder) expects `files`
            % to be RELATIVE paths. The `files` cell already holds
            % project-relative names like 'circuit/original.qasm' —
            % pass them as-is so the zip preserves the directory
            % structure. Passing absolute paths here would silently
            % flatten subdirectories.
            zip(opts.savePath, files, tmpDir);
            savedPath = opts.savePath;

            delete(cleanupObj);
            BundleService.rmTree(tmpDir);
        end
    end

    methods (Static, Access = private)
        function validateCtx(ctx)
            if ~isstruct(ctx)
                error('BundleService:BadCtx', 'ctx must be a struct');
            end
            if ~isfield(ctx, 'circuit') || isempty(ctx.circuit) || ~isa(ctx.circuit, 'CircuitModel')
                error('BundleService:BadCtx', 'ctx.circuit must be a CircuitModel');
            end
        end

        function opts = normalizeOpts(opts, ctx)
            if ~isstruct(opts)
                error('BundleService:BadOpts', 'opts must be a struct');
            end
            if ~isfield(opts, 'savePath') || isempty(opts.savePath)
                error('BundleService:BadOpts', 'opts.savePath is required');
            end
            opts = BundleService.fillDefault(opts, 'includeCircuit',    true);
            opts = BundleService.fillDefault(opts, 'includeBackend',    ~isempty(BundleService.safeField(ctx, 'backend', [])));
            opts = BundleService.fillDefault(opts, 'includeMitigation', ~isempty(BundleService.safeField(ctx, 'mitigationEstimates', [])));
            opts = BundleService.fillDefault(opts, 'includeFt',         ~isempty(BundleService.safeField(ctx, 'ftResult', [])));
        end

        function s = fillDefault(s, field, def)
            if ~isfield(s, field) || isempty(s.(field)); s.(field) = def; end
        end

        function meta = buildMeta(ctx)
            m = ctx.circuit;
            kindHist = containers.Map('KeyType','char','ValueType','int32');
            for i = 1:numel(m.Gates)
                k = char(m.Gates(i).kind);
                if isKey(kindHist, k); kindHist(k) = kindHist(k) + 1;
                else;                  kindHist(k) = int32(1); end
            end
            kindNames = kindHist.keys;
            kindCounts = cell(1, numel(kindNames));
            for i = 1:numel(kindNames); kindCounts{i} = kindHist(kindNames{i}); end
            meta = struct( ...
                'name',        BundleService.safeField(ctx, 'circuitName', 'untitled'), ...
                'num_qubits',  m.NumQubits, ...
                'depth',       m.depth(), ...
                'gate_count',  numel(m.Gates), ...
                'gate_kinds',  {kindNames}, ...
                'gate_counts', {kindCounts});
        end

        function manifest = buildManifest(tmpDir, files)
            entries = struct('path', {}, 'sha256', {}, 'size', {});
            for i = 1:numel(files)
                p = fullfile(tmpDir, files{i});
                info = dir(p);
                if isempty(info); continue; end
                entries(end+1) = struct( ...
                    'path',   files{i}, ...
                    'sha256', BundleService.sha256(p), ...
                    'size',   info.bytes); %#ok<AGROW>
            end
            manifest = struct( ...
                'bundle_version', BundleService.BUNDLE_VERSION, ...
                'generated_at',   datestr(now, 'yyyy-mm-ddTHH:MM:SSZ'), ... %#ok<DATST,TNOW1>
                'generator',      'QTAU Connector Workspace', ...
                'files',          entries);
        end

        function txt = buildReadme(ctx, opts, files)
            stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<DATST,TNOW1>
            name = BundleService.safeField(ctx, 'circuitName', 'untitled');
            lines = {
                sprintf('# Reproducibility bundle — %s', char(string(name)))
                ''
                sprintf('Generated by QTAU Connector Workspace on %s.', stamp)
                ''
                '## Contents'
                ''};
            for i = 1:numel(files)
                lines{end+1} = sprintf('- `%s`', files{i}); %#ok<AGROW>
            end
            lines{end+1} = '';
            lines{end+1} = '## How to reproduce';
            lines{end+1} = '';
            lines{end+1} = '1. Unzip this archive into a working directory.';
            lines{end+1} = '2. Inspect `circuit/original.qasm` for the canonical circuit.';
            lines{end+1} = '3. Use any of the `circuit/original.<ecosystem>.py` files as runnable starters.';
            step = 4;
            if opts.includeBackend
                lines{end+1} = sprintf('%d. The backend identity and calibration snapshot live under `backend/`.', step);
                step = step + 1;
            end
            if opts.includeMitigation
                lines{end+1} = sprintf('%d. Mitigation strategy estimates were captured under `mitigation/estimates.json`.', step);
                step = step + 1;
            end
            if opts.includeFt
                lines{end+1} = sprintf('%d. The fault-tolerant resource estimate captured at bundle time is under `ft_estimate/`.', step);
                step = step + 1;
            end
            lines{end+1} = '';
            lines{end+1} = sprintf('Bundle version: %s.', BundleService.BUNDLE_VERSION);
            txt = strjoin(lines, sprintf('\n'));
        end

        function writeText(path, txt)
            fid = fopen(path, 'w', 'n', 'UTF-8');
            if fid < 0
                error('BundleService:WriteFail', 'cannot open %s for writing', path);
            end
            fwrite(fid, char(txt));
            fclose(fid);
        end

        function txt = encodeJson(value)
            try
                txt = jsonencode(value, 'PrettyPrint', true);
            catch
                txt = jsonencode(value);
            end
        end

        function s = mapToStruct(m)
            if isstruct(m); s = m; return; end
            if ~isa(m, 'containers.Map'); s = struct(); return; end
            s = struct();
            keys = m.keys;
            for i = 1:numel(keys)
                safe = matlab.lang.makeValidName(keys{i});
                s.(safe) = m(keys{i});
            end
        end

        function v = safeField(s, field, def)
            v = def;
            try
                if isstruct(s) && isfield(s, field); v = s.(field);
                elseif isobject(s) && isprop(s, field); v = s.(field);
                end
            catch
            end
            if isempty(v); v = def; end
        end

        function hex = sha256(filePath)
            try
                md = java.security.MessageDigest.getInstance('SHA-256');
                fid = fopen(filePath, 'r');
                if fid < 0; error('BundleService:Hash', 'cannot open for hashing'); end
                while true
                    buf = fread(fid, 65536, 'uint8=>uint8');
                    if isempty(buf); break; end
                    md.update(buf);
                end
                fclose(fid);
                bytes = typecast(md.digest(), 'uint8');
                hex = sprintf('%02x', bytes);
            catch
                info = dir(filePath);
                if isempty(info); hex = 'unavailable'; return; end
                hex = sprintf('len=%d', info.bytes);
            end
        end

        function s = sanitizeName(s)
            s = char(string(s));
            s = regexprep(s, '[^a-zA-Z0-9._-]+', '-');
            s = regexprep(s, '-+', '-');
            s = regexprep(s, '^-|-$', '');
            if isempty(s); s = 'untitled'; end
        end

        function rmTree(p)
            try
                if exist(p, 'dir'); rmdir(p, 's'); end
            catch
            end
        end
    end
end
