% QTAUWorkbenchLauncher  Single-command launcher for QTAU: Hardware-Agnostic Execution.
%
%   Adds every src/ folder to the MATLAB search path and starts the
%   QTAUWorkbenchApp main window.
%
%   This script runs in two ways:
%     1. Automatically — the MATLAB Project Manager runs it when you open
%        the sqk-qtau-matlab.prj file.
%     2. Manually — invoke it from the MATLAB command line:
%           >> run('QTAUWorkbenchLauncher.m')
%
%   Environment variables:
%     QTAU_DEV=1   Force `clear classes` on launch (slower cold start;
%                  useful when iterating on classdef property changes).
%
%   See also: QTAUWorkbenchApp, AppConfig, Labels.

% Close any existing app window so live objects are destroyed before
% clearing class definitions.  Without this, MATLAB warns that it cannot
% clear classes that still have live instances.
figures = findall(0, 'Type', 'figure');
for k = 1:numel(figures)
    try; delete(figures(k)); catch; end
end

% `clear classes` wipes the JIT cache, m-file location cache, AND the
% `persistent cachedProps` in Labels.m / AppConfig.m — forcing a full
% 600-line labels.properties re-parse on every launch and dropping all
% in-memory class metadata. On a 200+ .m file project that costs 1-3 s
% on every cold start. Production / deployed builds skip it for the
% faster warm-cache path. Dev launches (any tree with a `.git` folder
% next to this launcher, OR explicit QTAU_DEV=1) always clear so .m
% edits the operator just made on disk take effect on next launch
% without them having to remember the env var. Without this auto-clear,
% MATLAB's cached classdef vtable executes whatever method bodies were
% loaded on FIRST launch and ignores every subsequent .m edit until
% `clear classes` is run — causing confusing "my fix did not apply"
% loops where the source has the change but the running session does
% not.
launcherDir = fileparts(mfilename('fullpath'));
isDevLaunch = strcmp(getenv('QTAU_DEV'), '1') ...
    || isfolder(fullfile(launcherDir, '.git'));
if isDevLaunch
    % Drain everything that can hold a strong reference to a classdef
    % instance before `clear classes`. MATLAB silently REFUSES to clear
    % a class definition if any live instance, timer with that class
    % in its UserData, or figure still references it. The old launcher
    % suppressed warnings so the refusal was invisible — operator
    % thought clear succeeded, MATLAB executed cached bytecode forever,
    % .m edits never took effect. New launcher: kill timers + figures
    % first, keep warnings audible so a failed clear is loud.
    try; delete(timerfindall); catch; end
    try; close all force; catch; end
    % Cancel any in-flight parfeval futures on the background pool —
    % their captured closures hold strong refs to VM / app handles, so
    % a live future will pin every classdef in the dispatch chain and
    % make `clear classes` warn for each one. Cancel is best-effort:
    % some MATLAB releases reject cancel on already-finished futures.
    try
        pool = backgroundPool();
        if ~isempty(pool)
            futs = pool.FevalQueue.QueuedFutures;
            for kk = 1:numel(futs); try; cancel(futs(kk)); catch; end; end
            futs = pool.FevalQueue.RunningFutures;
            for kk = 1:numel(futs); try; cancel(futs(kk)); catch; end; end
        end
    catch
    end
    % Drop the prior app instance still pinned by base-workspace `ans`
    % (assignment-less invocation of `QTAUWorkbenchApp;` leaves the
    % returned handle in ans, which alone is enough to block class
    % clearing). Delete it explicitly so its delete() chain releases
    % every VM / service / timer reference before `clear classes`.
    try
        evalin('base', ...
            ['try; if exist(''ans'',''var'') && isa(ans, ''handle'')' ...
             ' && isvalid(ans); delete(ans); end; catch; end; ' ...
             'clear ans;']);
    catch
    end
    drawnow;
    % Reset lastwarn so a stale prior warning can't impersonate a
    % blocked-clear failure below.
    lastwarn('');
    clear classes %#ok<CLSCR>
    % Detect a blocked `clear classes` and SURGICALLY reload the
    % user-defined classes that the close-button + dialog teardown
    % path actually depends on. The MATLAB-wide warning fires for
    % onCleanup whenever any cleanup obj is alive (very common from
    % MATLAB / Project startup itself), so a hard-fail on the
    % warning produces false-positives that block every launch. The
    % real concern is only the handful of user classes whose .m
    % edits the operator is iterating on — clear those by NAME.
    % `clear ClassName` is more granular than `clear classes` and
    % usually succeeds when the broad clear is blocked.
    [warnMsg, ~] = lastwarn();
    if ~isempty(warnMsg) && (contains(warnMsg, 'Cannot clear') || ...
            contains(warnMsg, 'cannot be cleared'))
        fprintf(2, ...
            '\n  ⚠  clear classes warned; force-reloading hot-path user classes:\n');
        hotClasses = { ...
            'AnalysisViewModel', ...
            'DialogBuilder', ...
            'QTAUWorkbenchApp', ...
            'OverlayManager', ...
            'NavigationManager'};
        for k = 1:numel(hotClasses)
            try
                evalin('base', sprintf('clear %s', hotClasses{k}));
                fprintf(2, '       cleared %s\n', hotClasses{k});
            catch ME
                fprintf(2, '       FAILED %s — %s\n', hotClasses{k}, ME.message);
            end
        end
        fprintf(2, ...
            '     If your .m edits still do not take effect, fully quit\n');
        fprintf(2, ...
            '     MATLAB (Cmd-Q on macOS, exit otherwise) and relaunch.\n\n');
    end
    % `clear classes` wipes ALL workspace variables in addition to class
    % definitions, so isDevLaunch + launcherDir are gone here. Restore
    % them so the rest of the script (path setup, the later
    % `if isDevLaunch` for rehash) still sees the intended values.
    launcherDir = fileparts(mfilename('fullpath'));
    isDevLaunch = strcmp(getenv('QTAU_DEV'), '1') ...
        || isfolder(fullfile(launcherDir, '.git'));
end

projectRoot = fileparts(mfilename('fullpath'));

% Remove any stale paths from this project that may survive across sessions.
% This handles directory renames/reorganizations without requiring a full
% restoredefaultpath (which would also remove user toolboxes).
srcRoot = fullfile(projectRoot, 'src');
pathParts = strsplit(path, pathsep);
for k = 1:numel(pathParts)
    if strncmp(pathParts{k}, srcRoot, numel(srcRoot))
        rmpath(pathParts{k});
    end
end

foldersToAdd = { ...
    fullfile('src', 'presentation', 'app'), ...
    fullfile('src', 'presentation', 'screens'), ...
    fullfile('src', 'presentation', 'viewmodels'), ...
    fullfile('src', 'presentation'), ...
    fullfile('src', 'domain', 'models'), ...
    fullfile('src', 'domain', 'services'), ...
    fullfile('src', 'domain'), ...
    fullfile('src', 'infrastructure', 'http'), ...
    fullfile('src', 'infrastructure', 'config'), ...
    fullfile('src', 'infrastructure') ...
};

% Batch-add all valid folders in ONE addpath call instead of N sequential
% ones. addpath accepts varargs and runs path-normalization + duplicate
% detection + cache update once instead of per-folder.
existingFolders = cell(1, numel(foldersToAdd));
keepIdx = false(1, numel(foldersToAdd));
for k = 1:numel(foldersToAdd)
    p = fullfile(projectRoot, foldersToAdd{k});
    if isfolder(p)
        existingFolders{k} = p;
        keepIdx(k) = true;
    end
end
existingFolders = existingFolders(keepIdx);
if ~isempty(existingFolders)
    addpath(existingFolders{:});
end

% rehash flushes MATLAB's function/class location cache. Only needed
% when `clear classes` ran above (dev path); a normal launch hits the
% already-warm cache and rehash is 50-200 ms of pure waste.
if isDevLaunch
    rehash;
end

fprintf('\n');clear
appName    = AppConfig.get('app_name', 'QTAU: Hardware-Agnostic Execution');
bannerText = sprintf('QDash Workbench — %s', appName);
innerWidth = max(50, strlength(bannerText) + 6);
bar        = repmat('═', 1, innerWidth);
padded     = sprintf(' %s ', bannerText);
pad        = innerWidth - strlength(padded);
leftPad    = floor(pad / 2);
rightPad   = pad - leftPad;
fprintf('  ╔%s╗\n', bar);
fprintf('  ║%s%s%s║\n', repmat(' ', 1, leftPad), padded, repmat(' ', 1, rightPad));
fprintf('  ╚%s╝\n', bar);
fprintf('  Starting application...\n\n');

QTAUWorkbenchApp;
