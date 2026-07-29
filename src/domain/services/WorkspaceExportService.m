classdef WorkspaceExportService < handle
    % WorkspaceExportService  MATLAB-centered export package for Composer.
    methods
        function payload = buildPackage(~, model, simulationResult)
            if nargin < 3; simulationResult = []; end
            if ~isa(model,'CircuitModel')
                error('WorkspaceExportService:InvalidModel','Expected CircuitModel.');
            end
            payload = struct();
            payload.circuitModel = model.copy();
            payload.quantumCircuit = WorkspaceExportService.toQuantumCircuit(model);
            payload.openQASM2 = string(model.toQasm());
            payload.openQASM3 = string(model.toQasm3());
            payload.simulationResult = simulationResult;
            payload.metadata = struct( ...
                'exportedAt', datetime('now'), ...
                'numQubits', model.NumQubits, ...
                'numGates', numel(model.Gates), ...
                'depth', model.depth(), ...
                'source', 'QTAU Composer', ...
                'client', 'MATLAB');
        end

        function exportToBase(obj, model, simulationResult)
            payload = obj.buildPackage(model, simulationResult);
            assignin('base','qtauCircuitModel',payload.circuitModel);
            assignin('base','qtauQuantumCircuit',payload.quantumCircuit);
            assignin('base','qtauOpenQASM2',payload.openQASM2);
            assignin('base','qtauOpenQASM3',payload.openQASM3);
            assignin('base','qtauCircuitMetadata',payload.metadata);
            assignin('base','qtauWorkspacePackage',payload);
            if ~isempty(simulationResult)
                assignin('base','qtauSimulationResult',simulationResult);
            end
        end

        function savePackage(obj, path, model, simulationResult)
            qtauWorkspacePackage = obj.buildPackage(model, simulationResult); %#ok<NASGU>
            save(path,'qtauWorkspacePackage');
        end
    end

    methods (Static)
        function qc = toQuantumCircuit(model)
            % Avoid referring to the abstract class directly on releases
            % where the package layout differs: accumulate in a cell first.
            gateCells = {};
            for i = 1:numel(model.Gates)
                g = model.Gates(i); q = double(g.qubits) + 1;
                switch lower(g.kind)
                    case 'h'; gateCells{end+1}=hGate(q(1));
                    case 'x'; gateCells{end+1}=xGate(q(1));
                    case 'y'; gateCells{end+1}=yGate(q(1));
                    case 'z'; gateCells{end+1}=zGate(q(1));
                    case 's'; gateCells{end+1}=sGate(q(1));
                    case 't'; gateCells{end+1}=tGate(q(1));
                    case 'sdg'; gateCells{end+1}=siGate(q(1));
                    case 'tdg'; gateCells{end+1}=tiGate(q(1));
                    case 'rx'; gateCells{end+1}=rxGate(q(1),double(g.params(1)));
                    case 'ry'; gateCells{end+1}=ryGate(q(1),double(g.params(1)));
                    case 'rz'; gateCells{end+1}=rzGate(q(1),double(g.params(1)));
                    case 'cx'; gateCells{end+1}=cxGate(q(1),q(2));
                    case 'cz'; gateCells{end+1}=czGate(q(1),q(2));
                    case 'swap'; gateCells{end+1}=swapGate(q(1),q(2));
                    case 'ccx'; gateCells{end+1}=ccxGate(q(1),q(2),q(3));
                    case {'measure','barrier'}
                        % Measurement is represented by sampling the state.
                    otherwise
                        error('WorkspaceExportService:UnsupportedGate', ...
                            'Cannot export gate "%s" to quantumCircuit.',g.kind);
                end
            end
            if isempty(gateCells)
                qc = quantumCircuit(model.NumQubits);
            else
                gateArray = gateCells{1};
                for i=2:numel(gateCells); gateArray(end+1)=gateCells{i}; end %#ok<AGROW>
                qc = quantumCircuit(gateArray, model.NumQubits);
            end
        end
    end
end
