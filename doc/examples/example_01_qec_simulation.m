%% Example 1 - Local QEC simulation (no backend needed)
% This example exercises *QecEngineService* - the pure-MATLAB density-matrix
% simulator that ships inside QTAU Connector Workbench. No connection to
% the QTAU FastAPI server is needed: every line below runs offline.
%
% Convert this file to a Live Script ( File -> Save As -> .mlx ) to embed
% sweep-curve plots inline.

%% Prerequisites
% * MATLAB R2025b or later.
% * QTAU Connector Workbench installed (via the .mltbx). After install:
%
%     >> matlab.addons.installedAddons
%
%   should list "QTAU Connector Workbench" as an entry.
%
% The launcher does the path-add for you, but for a standalone example
% we add the service folder directly so you can run this without
% launching the full UI.

projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));

%% Build the simulation engine
engine = QecEngineService();

%% Section 1 - A perfect (noiseless) bit-flip code
% Encode |+> through the 3-qubit bit-flip code, apply zero noise, and
% verify the recovered fidelity is 1.0. Pre-1.1.0 this returned 0.5 due
% to a literal-partial-trace decoder; 1.1.0 ships the inverse-encoding
% decoder that handles superposition logical inputs correctly.
result = engine.simulate('bitflip3', 'depolarizing', 0, '+', 1);
fprintf('Recovered fidelity (no noise, |+> input): %.4f\n', result.fidelity);

%% Section 2 - Fidelity vs. noise sweep
% Sweep the depolarizing error probability from 0 to 0.5 and plot the
% recovered logical fidelity at each point. The characteristic
% threshold behaviour of the 3-qubit code (a code distance of 1 for
% phase errors) means the curve dips fast once depolarizing noise
% mixes in Z-type errors the bit-flip code cannot correct.
pRange = linspace(0, 0.5, 21);
sweep = engine.sweepErrorRate('bitflip3', 'depolarizing', pRange, '+', 1);

figure;
plot(sweep.errorRates, sweep.fidelities, '-o', 'LineWidth', 1.5);
xlabel('Depolarizing error probability p');
ylabel('Recovered logical fidelity');
title('3-qubit bit-flip code under depolarizing noise');
grid on; ylim([0 1]);

%% Section 3 - Compare codes side-by-side
% sweepErrorRate for each of the three small codes the engine ships,
% overlay the fidelity curves, and look for the regime where each code
% wins.
codes  = {'bitflip3', 'phaseflip3', 'shor9'};
colors = {[0.20 0.45 0.85], [0.85 0.40 0.20], [0.30 0.65 0.35]};
pRange = linspace(0, 0.3, 16);

figure; hold on;
for k = 1:numel(codes)
    s = engine.sweepErrorRate(codes{k}, 'depolarizing', pRange, '0', 1);
    plot(s.errorRates, s.fidelities, '-o', ...
         'Color', colors{k}, 'LineWidth', 1.5, 'DisplayName', codes{k});
end
xlabel('Depolarizing error probability p');
ylabel('Recovered logical fidelity');
title('Code comparison under depolarizing noise (|0> input)');
legend('Location', 'southwest');
grid on; ylim([0 1]);

%% Section 4 - Bloch vector of the recovered state
% Whatever code you decode into a 2x2 density matrix, you can read off
% the Bloch coordinates. Below: |+> encoded through bitflip3 at p=0.05,
% decoded, and projected onto the Bloch sphere.
r = engine.simulate('bitflip3', 'depolarizing', 0.05, '+', 1);
[rx, ry, rz] = engine.blochVector(r.rhoLogical);
fprintf('Bloch vector at p=0.05: (X=%+0.3f, Y=%+0.3f, Z=%+0.3f)\n', rx, ry, rz);
fprintf('|r| = %.4f (1.0 = pure, 0.0 = maximally mixed)\n', sqrt(rx^2+ry^2+rz^2));

%% Where to go next
% * Open the *QEC Simulation* screen in the workbench for an interactive
%   version of these sweeps with parameter sliders.
% * Open the *QEC Visualization* screen to see the surface-code lattice
%   and error-propagation animation rendered in 3D.
% * Read |samples/aqs-qmc/| for a reference Quantum Monte Carlo
%   notebook the workbench's QMC popup can run against.
