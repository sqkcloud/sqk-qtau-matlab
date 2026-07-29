classdef HardwareRecommendationService
    % HardwareRecommendationService  Transparent offline hardware ranking.
    methods (Static)
        function result = recommend(model, shots, targetFidelity)
            if nargin<2; shots=4096; end
            if nargin<3; targetFidelity=0.90; end
            nq=double(model.NumQubits); ng=numel(model.Gates); depth=double(model.depth());
            kinds=string({model.Gates.kind}); cxCount=sum(ismember(lower(kinds),["cx","cz","swap","ccx"]));
            name=["MATLAB Local Simulator";"Heron-class Hardware Estimate";"Eagle-class Hardware Estimate"];
            qubits=[32;133;127];
            fidelity=[0.999; max(.50,.975-.0020*ng-.0040*cxCount-.0010*nq); max(.45,.952-.0030*ng-.0055*cxCount-.0015*nq)];
            runtime=[max(.01,.002*ng); 7+.0018*shots+.10*depth; 10+.0025*shots+.14*depth];
            cost=[0; .0011*shots*(1+nq/100); .00085*shots*(1+nq/90)];
            compatible=qubits>=nq;
            score=100*fidelity-0.12*runtime-0.03*cost;
            score(~compatible)=-Inf;
            meets=fidelity>=targetFidelity & compatible;
            ranking=table(name,qubits,compatible,fidelity,runtime,cost,score,meets, ...
                'VariableNames',{'Backend','CapacityQubits','Compatible','PredictedFidelity','EstimatedRuntimeSec','EstimatedCost','Score','MeetsTarget'});
            ranking=sortrows(ranking,{'MeetsTarget','Score'},{'descend','descend'});
            result=struct('summary',struct('NumQubits',nq,'GateCount',ng,'Depth',depth,'EntanglingGateCount',cxCount,'Shots',shots,'TargetFidelity',targetFidelity), ...
                'ranking',ranking,'recommended',ranking(1,:), ...
                'disclaimer','Offline deterministic estimate; connect to QTAU for live calibration, queue and pricing.');
        end
    end
end
