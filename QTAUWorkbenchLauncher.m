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
% on every cold start. The default (production) path skips it. Devs
% iterating on classdef changes (added/removed properties) set
% QTAU_DEV=1 in their env to force the clear.
isDevLaunch = strcmp(getenv('QTAU_DEV'), '1');
if isDevLaunch
    warning('off', 'all');
    clear classes %#ok<CLSCR>
    warning('on', 'all');
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
