% QTAUWorkbenchLauncher.m ──────────────────────────────────────────────────────
% Single-command launcher for QDash Workbench.
%
%   This script is used in two ways:
%
%   1. Automatically — the Project Manager runs it when you open the .prj file.
%   2. Manually     — run it directly from the MATLAB Command Window:
%
%         >> run('QTAUWorkbenchLauncher.m')IMP
%
% It adds all source folders to the MATLAB search path and then starts the app.
% ──────────────────────────────────────────────────────────────────────────────

% Close any existing app window so live objects are destroyed before
% clearing class definitions.  Without this, MATLAB warns that it cannot
% clear classes that still have live instances.
figures = findall(0, 'Type', 'figure');
for k = 1:numel(figures)
    try; delete(figures(k)); catch; end
end
% Suppress warnings that fire when handle objects still have live references.
% NOTE: clear classes also clears all workspace variables, so warning state
% cannot be saved/restored across this call — suppress before, re-enable after.
warning('off', 'all');
clear classes %#ok<CLSCR>
warning('on', 'all');

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

for k = 1:numel(foldersToAdd)
    p = fullfile(projectRoot, foldersToAdd{k});
    if isfolder(p)
        addpath(p);
    end
end

% Flush MATLAB's internal function/class location cache so it does not
% serve stale file-path mappings left over from previous path layouts.
rehash;

fprintf('\n');
fprintf('  ╔══════════════════════════════════════════════════╗\n');
fprintf('  ║   QDash Workbench — QTAU Connector Workspace     ║\n');
fprintf('  ╚══════════════════════════════════════════════════╝\n');
fprintf('  Starting application...\n\n');

QTAUWorkbenchApp;
