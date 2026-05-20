%% Example 2 - Visualize a quantum circuit from OpenQASM (no backend needed)
% Use *CircuitDiagram* - the toolbox's QASM-to-rendering helper - to
% produce three representations of a circuit:
%
%   1. Plain-text ASCII (great for fixed-width logs)
%   2. Colored HTML (rendered in a uihtml inside the workbench)
%   3. SVG vector graphics (best for reports and the Composer canvas)
%
% No QTAU backend connection is required - the parser and renderer run
% entirely in MATLAB.

projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));

%% Section 1 - Load a sample QASM circuit
qasmPath = fullfile(projectRoot, 'samples', 'bell_state.qasm');
qasmText = fileread(qasmPath);
fprintf('Loaded %d bytes of QASM from %s\n\n', numel(qasmText), qasmPath);
disp(qasmText);

%% Section 2 - ASCII rendering
% The text renderer is useful for terminal logs and quick inspection.
lines = CircuitDiagram.render(qasmText);
fprintf('\n--- ASCII diagram ---\n');
for k = 1:numel(lines)
    fprintf('%s\n', lines{k});
end

%% Section 3 - SVG rendering for inline display
% renderSvg returns a complete <svg>...</svg> string suitable for
% drop-in inside any uihtml widget. Here we save it to a file so you
% can open it in a browser.
svg = CircuitDiagram.renderSvg(qasmText);
svgPath = fullfile(tempdir, 'bell_state.svg');
fid = fopen(svgPath, 'w');
fwrite(fid, svg);
fclose(fid);
fprintf('\nSVG saved to %s (open in a browser to view)\n', svgPath);

%% Section 4 - Render any of the bundled QTAUBench circuits
% The toolbox ships a curated 10-circuit subset of PNNL QASMBench under
% samples/qasmbench/small/. Cycle through them to see how the renderer
% handles different gate sets and qubit counts.
benchDir = fullfile(projectRoot, 'samples', 'qasmbench', 'small');
if isfolder(benchDir)
    files = dir(fullfile(benchDir, '*.qasm'));
    if ~isempty(files)
        % Pick the first one as a demonstration. Switch to any other
        % file in the list to render a different circuit.
        pick = files(1);
        bench = fileread(fullfile(pick.folder, pick.name));
        fprintf('\n--- ASCII diagram of %s ---\n', pick.name);
        for L = CircuitDiagram.render(bench)
            fprintf('%s\n', L{1});
        end
    end
end

%% Where to go next
% * Open the *Composer* screen in the workbench. The SVG renderer
%   above is the same code path that draws the canvas.
% * The *Reproducibility Bundle* feature (Composer toolbar -> Bundle)
%   exports a ZIP with the QASM, Python equivalents (Qiskit/Cirq/
%   Braket), calibration snapshot, and a manifest with SHA-256
%   checksums. Open one of those bundles to see how CircuitDiagram is
%   referenced from the README inside the ZIP.
