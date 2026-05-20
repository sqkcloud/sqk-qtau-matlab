function capture_screenshots()
% capture_screenshots  Guided helper for capturing the screenshots used
%   on the MATLAB File Exchange listing page and embedded into
%   doc/GettingStarted.mlx via Live Editor's Insert -> Image.
%
%   Workflow:
%       >> run('scripts/capture_screenshots.m')
%
%   The script launches QTAUWorkbenchLauncher, then prompts you to
%   navigate to each target screen. Press ENTER at each prompt to capture
%   the currently-visible window. Files land in doc/screenshots/ with
%   numbered, descriptive names so the FEX upload form and Live Editor
%   insertion order are obvious.
%
%   Pre-requisites:
%       * A reachable QTAU FastAPI backend (the captures need real data
%         on screen, not the empty-state placeholders).
%       * Demo data seeded into a project so the Dashboard / Composer /
%         Run Planner have something to render. Use scripts/seed_all.m.
%
%   Output is a set of PNGs in doc/screenshots/. They do NOT ship inside
%   the .mltbx (already excluded by scripts/package_release.m's doc/
%   filter); upload them to the FEX submission form's image gallery, and
%   embed the relevant ones into doc/GettingStarted.mlx in Live Editor.

    scriptDir = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(scriptDir);
    outDir = fullfile(projectRoot, 'doc', 'screenshots');
    if ~isfolder(outDir); mkdir(outDir); end

    fprintf('\n');
    fprintf('  QTAU Connector Workbench - screenshot capture helper\n');
    fprintf('  --------------------------------------------------------\n');
    fprintf('  Output directory: %s\n', outDir);
    fprintf('  Captures: 5 (Login, Dashboard, Composer, Run Planner, QMC).\n');
    fprintf('  At each prompt, navigate to the named screen in the app,\n');
    fprintf('  THEN press ENTER in this Command Window to capture.\n');
    fprintf('  Type "skip" at a prompt to skip that capture.\n\n');

    % Launch the app. The launcher path-adds and opens the main window;
    % the Login dialog appears on top of the Dashboard panel within ~1 s.
    QTAUWorkbenchLauncher;
    drawnow; pause(2);

    % 5 captures, in a fixed order so FEX gallery + Live Editor
    % insertion preserve the same narrative arc.
    captures = { ...
        '01-login.png',       'Login dialog (the Base URL field should be visible at the top)'; ...
        '02-dashboard.png',   'Dashboard screen - KPI strip, workflow stepper, Run Readiness'; ...
        '03-composer.png',    'Composer screen with a non-trivial template loaded (e.g. Phase Estimation)'; ...
        '04-run-planner.png', 'Run Planner screen with the Pareto chart rendered'; ...
        '05-qmc-popup.png',   'Quantum Monte Carlo popup (Analysis -> Run QMC)'};

    nCaptures = size(captures, 1);
    for k = 1:nCaptures
        fname = captures{k, 1};
        descr = captures{k, 2};
        fprintf('\n  [%d/%d] %s\n', k, nCaptures, descr);
        resp = input(sprintf('       Press ENTER to capture (or "skip"): %s -> ', fname), 's');
        if strcmpi(strtrim(resp), 'skip')
            fprintf('       skipped.\n');
            continue;
        end

        target = iPickTopVisibleFigure();
        if isempty(target)
            fprintf('       no visible figure detected - try clicking the app window then re-run.\n');
            continue;
        end

        outPath = fullfile(outDir, fname);
        try
            % exportapp (R2020a+) captures a uifigure (web-based components)
            % including all child uipanels, uibuttons, etc. as drawn on
            % screen. Falls back to exportgraphics for non-uifigure cases
            % (e.g. an axes-only dialog) and for older releases.
            exportapp(target, outPath);
        catch ME1
            try
                exportgraphics(target, outPath, 'Resolution', 144);
            catch ME2
                fprintf('       capture failed: %s / %s\n', ME1.message, ME2.message);
                continue;
            end
        end
        fprintf('       saved -> %s\n', outPath);
    end

    fprintf('\n  Done. Next steps:\n');
    fprintf('    1. Review captures in %s\n', outDir);
    fprintf('    2. Open doc/GettingStarted.mlx in Live Editor. At each section\n');
    fprintf('       break, Insert -> Image -> pick the matching PNG. Save.\n');
    fprintf('    3. On the FEX submission form, upload the same 5 PNGs to\n');
    fprintf('       the image gallery (separate from the toolbox image).\n\n');
end

function fig = iPickTopVisibleFigure()
% iPickTopVisibleFigure  Returns the topmost visible figure (uifigure or
%   classic). Prefers the most recently shown modal (Login dialog, QMC
%   popup), which is what findall returns first.
    figs = findall(0, 'Type', 'figure', 'Visible', 'on');
    if isempty(figs); fig = []; return; end
    fig = figs(1);
end
