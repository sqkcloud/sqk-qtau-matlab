% QTAUWorkbench.m ──────────────────────────────────────────────────────────────
% Single-command launcher for QDash Workbench.
%
% This script is used in two ways:
%
%   1. Automatically — the Project Manager runs it when you open the .prj file.
%   2. Manually     — run it directly from the MATLAB Command Window:
%
%         >> run('QTAUWorkbench.m')
%
% It adds all source folders to the MATLAB search path and then starts the app.
% ──────────────────────────────────────────────────────────────────────────────

projectRoot = fileparts(mfilename('fullpath'));

foldersToAdd = { ...
    'src', ...
    fullfile('src', 'models'), ...
    fullfile('src', 'services'), ...
    fullfile('src', 'tabs'), ...
    fullfile('src', 'utils') ...
};

for k = 1:numel(foldersToAdd)
    p = fullfile(projectRoot, foldersToAdd{k});
    if isfolder(p)
        pathParts = strsplit(path, pathsep);
        if ~any(strcmp(pathParts, p))
            addpath(p);
        end
    end
end

fprintf('\n');
fprintf('  ╔══════════════════════════════════════════════════╗\n');
fprintf('  ║   QDash Workbench — QTAU Connector Workspace     ║\n');
fprintf('  ╚══════════════════════════════════════════════════╝\n');
fprintf('  Starting application...\n\n');

QTAUWorkbenchApp;
