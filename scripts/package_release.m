function outFile = package_release()
% package_release  Build the QTAU Connector Workbench .mltbx programmatically.
%
%   Replaces the manual GUI flow described in PUBLISHING.md Section 4
%   ("Configure the toolbox task") and Section 5 ("Reanalyze + package")
%   with a single repeatable command. Uses MATLAB R2023a+'s
%   matlab.addons.toolbox.ToolboxOptions API, which maps 1:1 to the
%   four GUI panels (Toolbox Info / Requirements / Install Actions /
%   Portability).
%
%   Pre-requisites (PUBLISHING.md Steps 0-3 must be done first):
%       * MATLAB R2025b or later.
%       * resources/toolbox-icon.png exists (Step 2).
%       * doc/GettingStarted.mlx exists (Step 3 — convert from .m).
%       * resources/app.properties has base_url= empty (Option C).
%
%   Usage:
%       >> run('scripts/package_release.m')
%       % or, if scripts/ is on the path:
%       >> package_release
%
%   Output: release/QTAUConnectorWorkbench.mltbx
%
%   The TOOLBOX_IDENTIFIER constant below must NEVER change across
%   releases. MATLAB uses it to recognize an installed toolbox as the
%   same product across version upgrades. Changing it would force every
%   user to uninstall the old version manually before installing the
%   new one, and File Exchange would treat it as a brand-new submission.

    % ── Stable toolbox identifier ─────────────────────────────────────
    % Generated v4 UUID, frozen for the lifetime of the product. Do
    % NOT regenerate.
    TOOLBOX_IDENTIFIER = 'd4f2a8e9-3c1b-4e5d-9a6c-7b3d2f8e1a4c';

    % ── Locate project root ───────────────────────────────────────────
    scriptDir   = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(scriptDir);
    fprintf('Project root: %s\n', projectRoot);

    % ── Pre-flight checks ─────────────────────────────────────────────
    iconPath = fullfile(projectRoot, 'resources', 'toolbox-icon.png');
    if ~isfile(iconPath)
        error('package_release:NoIcon', ...
            'Missing toolbox icon at %s.\nRender resources/sqk-logo-*.svg to PNG first — see PUBLISHING.md Step 2.', iconPath);
    end

    % Prefer the .mlx Live Editor version (richer rendering with output
    % panels), fall back to the .m script if the .mlx hasn't been
    % generated yet. MATLAB's ToolboxOptions accepts either.
    gettingStartedPath = fullfile(projectRoot, 'doc', 'GettingStarted.mlx');
    if ~isfile(gettingStartedPath)
        gettingStartedPath = fullfile(projectRoot, 'doc', 'GettingStarted.m');
        if ~isfile(gettingStartedPath)
            error('package_release:NoGettingStarted', ...
                ['Missing doc/GettingStarted.mlx AND doc/GettingStarted.m.\n' ...
                 'Open doc/GettingStarted.m in MATLAB Live Editor and Save As .mlx,\n' ...
                 'or restore the .m script — see PUBLISHING.md Step 3.']);
        end
        fprintf('Note: using doc/GettingStarted.m (no .mlx present).\n');
        fprintf('      Convert to .mlx for richer rendering — see 1.1.0 roadmap.\n');
    end

    appProps = fullfile(projectRoot, 'resources', 'app.properties');
    if ~isfile(appProps)
        error('package_release:NoAppProps', 'Missing %s.', appProps);
    end
    propsText = fileread(appProps);
    % \h (horizontal whitespace: space + tab) instead of \s so the
    % match can't span across newlines onto the next key's line. The
    % old \s-based regex falsely fired on `base_url=\nlogin_path=...`
    % because \s* swallowed the newline and \S landed on the `l`.
    if ~isempty(regexp(propsText, '^\h*base_url\h*=\h*\S', 'lineanchors', 'once'))
        warning('package_release:BaseUrlNotEmpty', ...
            ['resources/app.properties has a non-empty base_url=. ' ...
             'The shipped toolbox would hard-code that URL for every install. ' ...
             'For File Exchange, base_url should be blank (Option C).']);
    end

    licensePath = fullfile(projectRoot, 'LICENSE');
    noticePath  = fullfile(projectRoot, 'NOTICE');
    if ~isfile(licensePath) || ~isfile(noticePath)
        error('package_release:NoLicense', ...
            'LICENSE and NOTICE files must exist at the project root.');
    end

    % ── Build the ToolboxOptions ──────────────────────────────────────
    opts = matlab.addons.toolbox.ToolboxOptions(projectRoot, TOOLBOX_IDENTIFIER);

    % Toolbox Information
    opts.ToolboxName      = 'QTAU Connector Workbench';
    opts.ToolboxVersion   = '1.0.0';
    opts.AuthorName       = 'Mason';
    opts.AuthorEmail      = 'contact@sqkcloud.com';
    opts.AuthorCompany    = 'SQK Cloud Inc';
    opts.Summary          = 'MATLAB desktop client for managing IBM Quantum experiments through the QTAU FastAPI backend.';
    opts.Description      = sprintf([ ...
        'A professional MATLAB R2025b+ desktop client for managing quantum-circuit experiments ' ...
        'through the QTAU FastAPI backend. The toolbox is the client only — your data lives on ' ...
        'whichever QTAU server you connect to.\n\n' ...
        'Features:\n' ...
        '  * 20+ workflow screens covering circuit upload, in-app composer, analysis, backend ' ...
        'exploration, benchmark planning, prediction, mitigation cost compare, run planner, ' ...
        'job monitoring, results, reports, QEC simulation and visualization.\n' ...
        '  * Quantum Monte Carlo simulation popup with async IBM Runtime job execution, ' ...
        'zero-noise extrapolation, vector-chart PDF reports, and IBM execution-log download.\n' ...
        '  * Right-click context menus on Jobs and Cutting Batches tables for quick navigation.\n' ...
        '  * Cost-aware run planner that surfaces the cheapest backend x mitigation x shots ' ...
        'configuration that hits your target fidelity, via a Pareto frontier.\n\n' ...
        'Prerequisites:\n' ...
        '  * MATLAB R2025b or later.\n' ...
        '  * A running QTAU FastAPI server you can reach (the toolbox does not include the backend). ' ...
        'On first launch the Base URL field is blank — set it via the Login dialog or Settings -> Connection.\n\n' ...
        'Getting started: after install, type QTAUWorkbenchLauncher at the MATLAB prompt. ' ...
        'See the bundled Getting Started guide via Add-Ons -> Manage Add-Ons -> Options.']);
    opts.ToolboxImageFile = iconPath;

    % File inclusion — start from the auto-discovered file list, drop
    % everything matching the exclusion rules in PUBLISHING.md.
    fprintf('Filtering files (start: %d)... ', numel(opts.ToolboxFiles));
    keep = true(size(opts.ToolboxFiles));
    for i = 1:numel(opts.ToolboxFiles)
        if iShouldExclude(char(opts.ToolboxFiles(i)), projectRoot)
            keep(i) = false;
        end
    end
    opts.ToolboxFiles = opts.ToolboxFiles(keep);
    fprintf('end: %d (%d excluded)\n', numel(opts.ToolboxFiles), sum(~keep));

    % Install Actions — MATLAB Path. Matches QTAUWorkbenchLauncher.m
    % lines 48-59 so the install-time and runtime addpath sets are
    % identical (idempotent).
    opts.ToolboxMatlabPath = string({ ...
        projectRoot, ...
        fullfile(projectRoot, 'src', 'presentation'), ...
        fullfile(projectRoot, 'src', 'presentation', 'app'), ...
        fullfile(projectRoot, 'src', 'presentation', 'screens'), ...
        fullfile(projectRoot, 'src', 'presentation', 'viewmodels'), ...
        fullfile(projectRoot, 'src', 'domain'), ...
        fullfile(projectRoot, 'src', 'domain', 'models'), ...
        fullfile(projectRoot, 'src', 'domain', 'services'), ...
        fullfile(projectRoot, 'src', 'infrastructure'), ...
        fullfile(projectRoot, 'src', 'infrastructure', 'http'), ...
        fullfile(projectRoot, 'src', 'infrastructure', 'config')});

    % Install Actions — Java Classpath, Apps
    opts.ToolboxJavaPath  = string.empty;
    opts.AppGalleryFiles  = string.empty;

    % Install Actions — Getting Started Guide
    opts.ToolboxGettingStartedGuide = gettingStartedPath;

    % Requirements — none beyond base MATLAB
    opts.RequiredAddons             = struct.empty;
    opts.RequiredAdditionalSoftware = struct.empty;

    % Toolbox Portability
    opts.MinimumMatlabRelease       = 'R2025b';
    opts.MaximumMatlabRelease       = '';
    opts.SupportedPlatforms.Win64        = true;
    opts.SupportedPlatforms.Maci64       = true;
    opts.SupportedPlatforms.Glnxa64      = true;
    opts.SupportedPlatforms.MatlabOnline = true;

    % Output Settings
    releaseDir = fullfile(projectRoot, 'release');
    if ~isfolder(releaseDir); mkdir(releaseDir); end
    opts.OutputFile = fullfile(releaseDir, 'QTAUConnectorWorkbench.mltbx');

    % ── Package ───────────────────────────────────────────────────────
    fprintf('\nPackaging %s v%s\n', opts.ToolboxName, opts.ToolboxVersion);
    fprintf('  Identifier:   %s\n', TOOLBOX_IDENTIFIER);
    fprintf('  Files:        %d\n', numel(opts.ToolboxFiles));
    fprintf('  Path entries: %d\n', numel(opts.ToolboxMatlabPath));
    fprintf('  Min release:  %s\n', opts.MinimumMatlabRelease);
    fprintf('  Output:       %s\n', opts.OutputFile);
    fprintf('  Running matlab.addons.toolbox.packageToolbox...\n');

    matlab.addons.toolbox.packageToolbox(opts);

    if ~isfile(opts.OutputFile)
        error('package_release:NoOutput', ...
            'packageToolbox returned without writing %s.', opts.OutputFile);
    end

    info = dir(opts.OutputFile);
    fprintf('\nDone — %.2f MB at %s\n', info.bytes / 1024 / 1024, opts.OutputFile);
    fprintf('Next: smoke-test on a clean MATLAB (PUBLISHING.md Section 6).\n');

    if nargout > 0
        outFile = opts.OutputFile;
    end
end


function tf = iShouldExclude(absPath, projectRoot)
% iShouldExclude  True when a project-relative path matches one of the
%   PUBLISHING.md exclusion rules. Forward-slash-normalized so the same
%   patterns work on Windows + macOS + Linux.
    rel = strrep(absPath, [projectRoot filesep], '');
    rel = strrep(rel, '\', '/');

    % Whole-directory excludes (anywhere)
    dirPrefixes = { ...
        '.git/', '.github/', '.claude/', '.serena/', ...
        'tests/', 'scripts/', 'output/', 'release/'};
    for i = 1:numel(dirPrefixes)
        if startsWith(rel, dirPrefixes{i}); tf = true; return; end
    end

    % Exact path matches
    exactExcludes = { ...
        '.gitignore', '.gitattributes', '.DS_Store', ...
        'CLAUDE.md', 'PUBLISHING.md', ...
        'resources/seed.properties', ...
        'doc/keys.txt'};
    for i = 1:numel(exactExcludes)
        if strcmp(rel, exactExcludes{i}); tf = true; return; end
    end

    % Root-level session artifact prefixes
    rootArtifactPrefixes = { ...
        'EmAnalysis_', 'Report_', 'ExecLog_', ...
        'Results_', 'Reconstruction_'};
    for i = 1:numel(rootArtifactPrefixes)
        if startsWith(rel, rootArtifactPrefixes{i}) && ~contains(rel, '/')
            tf = true; return;
        end
    end

    % File-extension excludes
    suffixExcludes = {'.mex', '.token', '.env', '.mltbx'};
    for i = 1:numel(suffixExcludes)
        if endsWith(rel, suffixExcludes{i}); tf = true; return; end
    end

    % doc/ — ship ONLY the Getting Started guide (.mlx preferred, .m
    % fallback); everything else under doc/ is internal dev material
    % (architecture notes, OpenAPI dump, dev guide, notebooks,
    % superpowers/, features/, etc.).
    if startsWith(rel, 'doc/') ...
            && ~strcmp(rel, 'doc/GettingStarted.m') ...
            && ~strcmp(rel, 'doc/GettingStarted.mlx')
        tf = true; return;
    end

    % samples/qasmbench/ — the full PNNL bench (480 MB, 252 circuits) is
    % too large for the File Exchange 100 MB ceiling. Keep a curated
    % 10-circuit subset representing the main algorithm families; the
    % full catalog stays on the QASMBench GitHub for power users (see
    % README "QASMBench" section for the clone command).
    qasmbenchKeep = { ...
        'samples/qasmbench/small/bell_n4.qasm', ...
        'samples/qasmbench/small/grover_n2.qasm', ...
        'samples/qasmbench/small/deutsch_n2.qasm', ...
        'samples/qasmbench/small/dnn_n2.qasm', ...
        'samples/qasmbench/small/qaoa_n3.qasm', ...
        'samples/qasmbench/small/vqe_uccsd_n4.qasm', ...
        'samples/qasmbench/small/qft_n4.qasm', ...
        'samples/qasmbench/small/teleportation_n3.qasm', ...
        'samples/qasmbench/small/simon_n6.qasm', ...
        'samples/qasmbench/small/cat_state_n4.qasm'};
    if startsWith(rel, 'samples/qasmbench/')
        if ~any(strcmp(rel, qasmbenchKeep))
            tf = true; return;
        end
    end

    tf = false;
end
