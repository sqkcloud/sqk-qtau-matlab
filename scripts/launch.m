% launch.m ─────────────────────────────────────────────────────────────────────
% Launcher shortcut — delegates to QTAUWorkbench.m at the project root.
%
% Use this if your MATLAB working directory is inside scripts/ rather than
% the project root.
% ──────────────────────────────────────────────────────────────────────────────

scriptDir   = fileparts(mfilename('fullpath'));
projectRoot = fullfile(scriptDir, '..');
run(fullfile(projectRoot, 'QTAUWorkbench.m'));
