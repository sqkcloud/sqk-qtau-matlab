%% QTAU VQE / Materials MATLAB Workflow
% MATLAB-native preparation and simulation, followed by optional remote planning.
assert(MatlabQuantumService.isAvailable(), ...
    'Install MATLAB Support Package for Quantum Computing.');
theta = linspace(0,2*pi,25)';
energy = zeros(size(theta));
for k=1:numel(theta)
    % Minimal parameter sweep demonstrating the MATLAB-centered loop.
    gates = [ryGate(1,theta(k)); cxGate(1,2)];
    qc = quantumCircuit(gates);
    result = SimulationService().simulate(qc,'matlab',0);
    p = result.probabilities;
    if isempty(p); energy(k)=NaN; else; energy(k)=1-2*sum(p(2:2:end)); end
end
vqeTable=table(theta,energy,'VariableNames',{'Theta','EstimatedEnergy'});
assignin('base','qtauVqeSweep',vqeTable);
plot(theta,energy,'o-'); xlabel('Theta'); ylabel('Estimated energy'); grid on;
