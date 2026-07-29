classdef AcceptanceTestService
    % AcceptanceTestService  Customer acceptance tests 3-6.
    methods (Static)
        function report = run(model, simulationResult, shots, targetFidelity)
            if nargin<2; simulationResult=[]; end
            if nargin<3; shots=4096; end
            if nargin<4; targetFidelity=.90; end
            exporter=WorkspaceExportService();
            test3=struct('name','Workspace Export','passed',false,'details','');
            try
                exporter.exportToBase(model,simulationResult);
                test3.passed=evalin('base',"exist('qtauQuantumCircuit','var')==1 && exist('qtauWorkspacePackage','var')==1");
                test3.details='Exported CircuitModel, quantumCircuit, QASM2/3, metadata and simulation result.';
            catch ME; test3.details=ME.message; end
            rt=RoundTripVerifier.verify(model);
            test4=struct('name','Round Trip','passed',rt.passed,'details',rt.message);
            hw=HardwareRecommendationService.recommend(model,shots,targetFidelity);
            test5=struct('name','Offline Planner','passed',height(hw.ranking)>=3,'details',sprintf('%d candidates generated.',height(hw.ranking)));
            test6=struct('name','Hardware Recommendation','passed',~isempty(hw.recommended),'details',char(hw.recommended.Backend(1)));
            tests=[test3,test4,test5,test6];
            report=struct('generatedAt',datetime('now'),'tests',tests,'roundTrip',rt,'hardware',hw,'passed',all([tests.passed]));
            assignin('base','qtauAcceptanceReport',report);
            assignin('base','qtauHardwareRanking',hw.ranking);
        end
    end
end
