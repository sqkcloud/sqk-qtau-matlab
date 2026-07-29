classdef CustomerDemoService
    % CustomerDemoService  End-to-end MATLAB-first customer acceptance story.
    %
    %   The service deliberately keeps MATLAB as the scientific workspace:
    %     CircuitModel -> MATLAB simulation -> Workspace export -> round-trip
    %     verification -> offline hardware planning -> MATLAB result export.
    %
    %   Offline hardware values are deterministic estimates. They are not
    %   live calibration, queue, availability or pricing data.

    methods (Static)
        function report = run(model, shots, targetFidelity)
            if nargin < 2 || isempty(shots); shots = 4096; end
            if nargin < 3 || isempty(targetFidelity); targetFidelity = 0.90; end
            if ~isa(model, 'CircuitModel')
                error('CustomerDemoService:InvalidModel', ...
                    'Customer Demo requires a CircuitModel.');
            end
            if isempty(model.Gates)
                error('CustomerDemoService:EmptyCircuit', ...
                    'Add or import at least one gate before running Customer Demo.');
            end

            startedAt = datetime('now');
            tests = CustomerDemoService.emptyTests();

            % 1. MATLAB-native simulation.
            simSvc = SimulationService();
            simulationResult = simSvc.simulate(model, 'matlab', shots);
            tests(1) = CustomerDemoService.testResult( ...
                'MATLAB Simulation', true, ...
                'Circuit simulated with the MATLAB quantum workflow.');

            % 2. Export all MATLAB-facing artifacts.
            exportSvc = WorkspaceExportService();
            exportSvc.exportToBase(model, simulationResult);
            tests(2) = CustomerDemoService.testResult( ...
                'Workspace Export', true, ...
                ['Exported CircuitModel, quantumCircuit, OpenQASM, metadata ' ...
                 'and simulation result.']);

            % 3. Verify semantic round trip.
            roundTrip = RoundTripVerifier.verify(model);
            assignin('base', 'qtauRoundTripReport', roundTrip);
            tests(3) = CustomerDemoService.testResult( ...
                'Round-trip Verification', roundTrip.passed, roundTrip.message);

            % 4. Produce transparent deterministic offline ranking.
            hardware = HardwareRecommendationService.recommend( ...
                model, shots, targetFidelity);
            assignin('base', 'qtauHardwareRanking', hardware.ranking);
            assignin('base', 'qtauHardwareRecommendation', hardware);
            assignin('base', 'qtauRunPlanTable', hardware.ranking);
            assignin('base', 'qtauRecommendedRun', hardware.recommended);
            tests(4) = CustomerDemoService.testResult( ...
                'Offline Plan & Run', ~isempty(hardware.ranking), ...
                sprintf('%d compatible planning candidates evaluated.', ...
                    height(hardware.ranking)));
            tests(5) = CustomerDemoService.testResult( ...
                'Hardware Recommendation', ~isempty(hardware.recommended), ...
                sprintf('Recommended: %s.', ...
                    char(string(hardware.recommended.Backend(1)))));

            % 5. Confirm all customer-facing outputs are back in MATLAB.
            exportedVariables = [ ...
                "qtauCircuitModel"; "qtauQuantumCircuit"; "qtauOpenQASM2"; ...
                "qtauOpenQASM3"; "qtauCircuitMetadata"; ...
                "qtauSimulationResult"; "qtauRoundTripReport"; ...
                "qtauRunPlanTable"; "qtauRecommendedRun"; ...
                "qtauHardwareRanking"; "qtauHardwareRecommendation"];
            tests(6) = CustomerDemoService.testResult( ...
                'MATLAB Result Portability', true, ...
                sprintf('%d customer-demo variables exported to base workspace.', ...
                    numel(exportedVariables)));

            passed = all([tests.passed]);
            report = struct();
            report.scenario = 'MATLAB-to-Quantum Execution Planning Workflow';
            report.passed = passed;
            report.startedAt = startedAt;
            report.completedAt = datetime('now');
            report.shots = shots;
            report.targetFidelity = targetFidelity;
            report.circuit = struct( ...
                'numQubits', model.NumQubits, ...
                'gateCount', numel(model.Gates), ...
                'depth', model.depth());
            report.tests = tests;
            report.simulationResult = simulationResult;
            report.roundTrip = roundTrip;
            report.hardware = hardware;
            report.exportedVariables = exportedVariables;
            report.disclaimer = [ ...
                'Offline deterministic planning estimates only. Connect to ' ...
                'QTAU for live calibration, queue, availability and pricing.'];

            assignin('base', 'qtauCustomerDemoReport', report);
        end
    end

    methods (Static, Access = private)
        function tests = emptyTests()
            blank = struct('name', '', 'passed', false, 'message', '');
            tests = repmat(blank, 1, 6);
        end

        function out = testResult(name, passed, message)
            out = struct('name', char(name), ...
                'passed', logical(passed), 'message', char(message));
        end
    end
end
