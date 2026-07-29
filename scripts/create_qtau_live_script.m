function outputFile = create_qtau_live_script(outputFile)
%CREATE_QTAU_LIVE_SCRIPT Generate a MATLAB Live Script from the QTAU workflow example.
% Run this function inside MATLAB. It uses matlab.internal.liveeditor.openAndConvert
% when available and falls back to opening the source script for manual Save As.

root = fileparts(fileparts(mfilename('fullpath')));
source = fullfile(root, 'samples', 'QTAU_MATLAB_Workflow.m');
if nargin < 1 || strlength(string(outputFile)) == 0
    outputFile = fullfile(root, 'samples', 'QTAU_MATLAB_Workflow.mlx');
end

if exist('matlab.internal.liveeditor.openAndConvert', 'file') == 2
    matlab.internal.liveeditor.openAndConvert(source, outputFile);
else
    edit(source);
    warning('QTAU:LiveScriptConversion', ...
        ['Automatic conversion is unavailable in this MATLAB release. ' ...
         'The source script was opened; use Save As > MATLAB Live Script (*.mlx).']);
end
end
