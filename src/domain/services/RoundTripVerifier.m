classdef RoundTripVerifier
    % RoundTripVerifier  Verifies Composer -> quantumCircuit -> Composer.
    methods (Static)
        function report = verify(model)
            report = struct('passed',false,'qubitsMatch',false,'gatesMatch',false, ...
                'probabilitiesMatch',false,'maxProbabilityError',NaN, ...
                'originalGateCount',numel(model.Gates),'roundTripGateCount',0, ...
                'message','');
            try
                qc = WorkspaceExportService.toQuantumCircuit(model);
                imported = MatlabCircuitAdapter.toCircuitModel(qc);
                report.qubitsMatch = model.NumQubits == imported.NumQubits;
                report.roundTripGateCount = numel(imported.Gates);
                report.gatesMatch = RoundTripVerifier.gatesEquivalent(model,imported);
                sim = SimulationService();
                a = sim.simulate(model,'matlab',0);
                b = sim.simulate(imported,'matlab',0);
                [sa,pa] = RoundTripVerifier.sortedProbabilities(a);
                [sb,pb] = RoundTripVerifier.sortedProbabilities(b);
                if isequal(sa,sb)
                    report.maxProbabilityError = max(abs(pa-pb),[],'omitnan');
                    if isempty(report.maxProbabilityError); report.maxProbabilityError=0; end
                    report.probabilitiesMatch = report.maxProbabilityError < 1e-10;
                end
                report.passed = report.qubitsMatch && report.gatesMatch && report.probabilitiesMatch;
                if report.passed
                    report.message='Round-trip PASS: qubits, gates and state probabilities match.';
                else
                    report.message='Round-trip FAIL: inspect qubit, gate or probability comparison fields.';
                end
            catch ME
                report.message=ME.message;
            end
        end
    end
    methods (Static, Access=private)
        function tf = gatesEquivalent(a,b)
            ga=a.Gates; gb=b.Gates;
            % MATLAB quantumCircuit does not preserve explicit measurement
            % nodes because sampling is separate. Compare unitary gates only.
            ga=ga(~ismember({ga.kind},{'measure','barrier'}));
            gb=gb(~ismember({gb.kind},{'measure','barrier'}));
            if numel(ga)~=numel(gb); tf=false; return; end
            tf=true;
            for i=1:numel(ga)
                tf=tf && strcmpi(ga(i).kind,gb(i).kind) && ...
                    isequal(double(ga(i).qubits),double(gb(i).qubits));
                if ~tf; return; end
                if numel(ga(i).params)~=numel(gb(i).params); tf=false; return; end
                if ~isempty(ga(i).params) && any(abs(double(ga(i).params)-double(gb(i).params))>1e-10)
                    tf=false; return;
                end
            end
        end
        function [s,p]=sortedProbabilities(r)
            s=string(r.states(:)); p=double(r.probabilities(:));
            [s,ix]=sort(s); p=p(ix);
        end
    end
end
