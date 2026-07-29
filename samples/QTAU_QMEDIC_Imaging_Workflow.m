%% QTAU QMEDIC Imaging Workflow
% Demonstrates MATLAB image preparation/metrics around a locally validated
% quantum circuit. Replace syntheticImage with CT/sinogram data as needed.
[x,y]=meshgrid(linspace(-1,1,128)); reference=exp(-5*(x.^2+y.^2));
lowDose=reference+0.08*randn(size(reference)); restored=imgaussfilt(lowDose,0.8);
rmse=sqrt(mean((restored-reference).^2,'all'));
psnrValue=20*log10(1/rmse);
qc=quantumCircuit([hGate(1); cxGate(1,2)]);
sim=SimulationService().simulate(qc,'auto',1024);
qmedicReport=table(rmse,psnrValue,string(sim.engine), ...
    'VariableNames',{'RMSE','PSNR','SimulationEngine'});
assignin('base','qtauQmedicReport',qmedicReport);
figure; tiledlayout(1,3); nexttile; imagesc(reference); axis image off; title('Reference');
nexttile; imagesc(lowDose); axis image off; title('Low dose');
nexttile; imagesc(restored); axis image off; title('Restored'); colormap gray;
