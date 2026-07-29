%% QTAU Offline Demo
% This demo runs without QTAU server authentication.
% It creates a Bell circuit, performs local simulation, and exports MATLAB-ready results.

qtauRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(qtauRoot, 'src')));

model = CircuitModel(2);
model.addGate('h', 1);
model.addGate('cx', [1 2]);

simulation = SimulationService();
result = simulation.simulate(model, 'qtau', 1024);
resultTable = MatlabResultAdapter.toTable(result);
assignin('base', 'qtauOfflineCircuit', model);
assignin('base', 'qtauOfflineResult', result);
assignin('base', 'qtauOfflineResultTable', resultTable);

disp('Created Workspace variables:');
disp('  qtauOfflineCircuit');
disp('  qtauOfflineResult');
disp('  qtauOfflineResultTable');

try
    if isfield(result, 'probabilities') && isfield(result, 'states')
        figure('Name', 'QTAU Offline Bell State');
        bar(categorical(string(result.states)), double(result.probabilities));
        xlabel('Basis state'); ylabel('Probability');
        title('QTAU Offline Simulation'); grid on;
    end
catch ME
    warning('QTAU:OfflineDemoPlot', 'Plot skipped: %s', ME.message);
end
