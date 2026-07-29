%% QTAU MATLAB-Centered Workflow
% This example runs without server authentication for local preparation,
% simulation, and Workspace round-trip. Remote prediction and execution are
% enabled after connecting to QTAU.

%% 1. Prepare a circuit in MATLAB
assert(MatlabQuantumService.isAvailable(), ...
    'Install MATLAB Support Package for Quantum Computing to run this section.');
gates = [hGate(1); cxGate(1,2)];
matlabCircuit = quantumCircuit(gates);

%% 2. Convert to the QTAU circuit model
qtauCircuit = MatlabCircuitAdapter.toCircuitModel(matlabCircuit);

%% 3. Simulate using MATLAB Quantum Computing
simulator = SimulationService();
result = simulator.simulate(matlabCircuit, 'matlab', 1024);
probabilityTable = table(result.states, result.probabilities, ...
    'VariableNames', {'State','Probability'});

%% 4. Continue analysis in MATLAB
bar(categorical(probabilityTable.State), probabilityTable.Probability);
ylabel('Probability'); title('QTAU MATLAB Local Simulation');

%% 5. Export the QTAU model back to the Workspace
workspace = MatlabWorkspaceService();
workspace.exportVariable('qtauBellCircuit', qtauCircuit);
workspace.exportVariable('qtauBellResult', probabilityTable);

%% 6. Launch QTAU Workbench for backend-aware planning
% QTAUWorkbenchLauncher
% In the app: Welcome > Plan & Run > Quick Prediction / Compare Options.
