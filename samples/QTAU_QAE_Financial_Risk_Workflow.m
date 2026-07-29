%% QTAU QAE Financial Risk Workflow
% Classical portfolio scenarios remain in MATLAB; a representative amplitude
% circuit is locally validated before optional QTAU remote execution planning.
rng(7); returns=0.01+0.04*randn(10000,1); loss=max(-returns,0);
classicalMeanLoss=mean(loss); classicalVaR=quantile(loss,0.95);
qc=quantumCircuit([hGate(1); ryGate(2,2*asin(sqrt(min(1,classicalMeanLoss/0.1)))); cxGate(1,2)]);
sim=SimulationService().simulate(qc,'auto',2048);
riskSummary=table(classicalMeanLoss,classicalVaR,string(sim.engine), ...
    'VariableNames',{'MeanLoss','VaR95','SimulationEngine'});
assignin('base','qtauRiskSummary',riskSummary); disp(riskSummary);
