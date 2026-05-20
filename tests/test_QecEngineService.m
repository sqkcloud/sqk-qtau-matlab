classdef test_QecEngineService < matlab.unittest.TestCase
    % test_QecEngineService  Unit tests for the QEC simulation engine.

    properties
        Engine
    end

    methods (TestMethodSetup)
        function createEngine(testCase)
            testCase.Engine = QecEngineService();
        end
    end

    methods (Test)

        % ── Fidelity tests ────────────────────────────────────────────────
        function testBitFlipNoNoisePerfectFidelity(testCase)
            % With zero noise, fidelity should be 1.0
            r = testCase.Engine.simulate('bitflip3', 'bitflip', 0, '0', 1);
            testCase.verifyGreaterThanOrEqual(r.fidelity, 0.99, ...
                'Bit-flip code with p=0 should have near-perfect fidelity');
        end

        function testPhaseFlipNoNoisePerfectFidelity(testCase)
            r = testCase.Engine.simulate('phaseflip3', 'phaseflip', 0, '0', 1);
            testCase.verifyGreaterThanOrEqual(r.fidelity, 0.99, ...
                'Phase-flip code with p=0 should have near-perfect fidelity');
        end

        function testDepolarizingNoNoisePerfectFidelity(testCase)
            % Uses |+⟩ — the encoded state is GHZ-3, the worst-case
            % input for any naive partial-trace decoder. 1.1.0 ships
            % QecEngineService.decodeBitFlip3 which applies the inverse
            % encoding circuit (CNOT_1->3 · CNOT_1->2) before tracing,
            % so the recovered fidelity is 1.0 even under the
            % depolarizing channel at p=0. 1.0.0 capped at 0.5 here.
            r = testCase.Engine.simulate('bitflip3', 'depolarizing', 0, '+', 1);
            testCase.verifyGreaterThanOrEqual(r.fidelity, 0.99, ...
                'Depolarizing noise with p=0 should give perfect fidelity');
        end

        % ── Bloch vector tests ────────────────────────────────────────────
        function testBlochVectorZeroState(testCase)
            rho = [1 0; 0 0];  % |0⟩
            [rx, ry, rz] = testCase.Engine.blochVector(rho);
            testCase.verifyEqual(rz, 1, 'AbsTol', 1e-10, '|0⟩ Bloch Z should be 1');
            testCase.verifyEqual(rx, 0, 'AbsTol', 1e-10, '|0⟩ Bloch X should be 0');
            testCase.verifyEqual(ry, 0, 'AbsTol', 1e-10, '|0⟩ Bloch Y should be 0');
        end

        function testBlochVectorPlusState(testCase)
            psi = [1;1]/sqrt(2);
            rho = psi * psi';
            [rx, ry, rz] = testCase.Engine.blochVector(rho);
            testCase.verifyEqual(rx, 1, 'AbsTol', 1e-10, '|+⟩ Bloch X should be 1');
            testCase.verifyEqual(rz, 0, 'AbsTol', 1e-10, '|+⟩ Bloch Z should be 0');
        end

        function testBlochVectorMixedState(testCase)
            rho = eye(2) / 2;  % maximally mixed
            [rx, ry, rz] = testCase.Engine.blochVector(rho);
            testCase.verifyEqual(rx, 0, 'AbsTol', 1e-10, 'Mixed state Bloch X should be 0');
            testCase.verifyEqual(ry, 0, 'AbsTol', 1e-10, 'Mixed state Bloch Y should be 0');
            testCase.verifyEqual(rz, 0, 'AbsTol', 1e-10, 'Mixed state Bloch Z should be 0');
        end

        % ── Fidelity monotonicity ────────────────────────────────────────
        function testFidelityDecreasesWithNoise(testCase)
            r1 = testCase.Engine.simulate('bitflip3', 'bitflip', 0.01, '0', 1);
            r2 = testCase.Engine.simulate('bitflip3', 'bitflip', 0.20, '0', 1);
            testCase.verifyGreaterThan(r1.fidelity, r2.fidelity, ...
                'Fidelity should decrease with higher error probability');
        end

        % ── Sweep tests ──────────────────────────────────────────────────
        function testSweepReturnsCorrectPoints(testCase)
            pRange = linspace(0, 0.3, 10);
            sweep = testCase.Engine.sweepErrorRate('bitflip3', 'bitflip', pRange, '0', 1);
            testCase.verifyEqual(numel(sweep.fidelities), 10, ...
                'Sweep should return one fidelity per error rate point');
            testCase.verifyEqual(numel(sweep.errorRates), 10);
            testCase.verifySize(sweep.blochVectors, [10 3]);
        end

        % ── Result structure completeness ─────────────────────────────────
        function testResultStructureFields(testCase)
            r = testCase.Engine.simulate('bitflip3', 'bitflip', 0.05, '0', 1);
            testCase.verifyTrue(isfield(r, 'fidelity'));
            testCase.verifyTrue(isfield(r, 'blochVector'));
            testCase.verifyTrue(isfield(r, 'syndromeHistogram'));
            testCase.verifyTrue(isfield(r, 'correctionSuccess'));
            testCase.verifyTrue(isfield(r, 'rhoLogical'));
            testCase.verifyTrue(isfield(r, 'codeType'));
            testCase.verifyTrue(isfield(r, 'noiseModel'));
            testCase.verifyTrue(isfield(r, 'errorProb'));
        end

        % ── Surface code Monte Carlo ──────────────────────────────────────
        function testSurfaceCodeReturnsResult(testCase)
            r = testCase.Engine.simulateSurfaceCode(3, 0.01, 100);
            testCase.verifyTrue(isfield(r, 'fidelity'));
            testCase.verifyTrue(isfield(r, 'logicalErrorRate'));
            testCase.verifyTrue(isfield(r, 'distance'));
            testCase.verifyGreaterThanOrEqual(r.fidelity, 0, 'Fidelity must be >= 0');
            testCase.verifyLessThanOrEqual(r.fidelity, 1, 'Fidelity must be <= 1');
        end

        % ── Compare codes ─────────────────────────────────────────────────
        function testCompareCodesReturnsCellArray(testCase)
            codes = {'bitflip3', 'phaseflip3'};
            pRange = linspace(0, 0.2, 5);
            results = testCase.Engine.compareCodes(codes, 'depolarizing', pRange, '0', 1);
            testCase.verifyEqual(numel(results), 2, ...
                'compareCodes should return one sweep per code');
        end

        % ── Error weight distribution ─────────────────────────────────────
        function testErrorWeightDistribution(testCase)
            dist = testCase.Engine.errorWeightDistribution(3, 0.1);
            testCase.verifyEqual(numel(dist.weights), 4);  % 0,1,2,3
            testCase.verifyEqual(sum(dist.probs), 1, 'AbsTol', 1e-10, ...
                'Error weight probabilities should sum to 1');
        end

        % ── Fidelity decay over rounds ────────────────────────────────────
        function testDecayOverRounds(testCase)
            decay = testCase.Engine.simulateDecay('bitflip3', 'bitflip', 0.05, '0', 5);
            testCase.verifyEqual(numel(decay.fidelities), 5);
            testCase.verifyEqual(numel(decay.rounds), 5);
        end

        % ── Surface lattice coordinates ───────────────────────────────────
        function testSurfaceLatticeCoords(testCase)
            lattice = testCase.Engine.surfaceLatticeCoords(3);
            testCase.verifyEqual(lattice.nData, 9, 'Distance-3 surface code has 9 data qubits');
            testCase.verifyEqual(lattice.distance, 3);
        end

        % ── Shor code basic test ──────────────────────────────────────────
        function testShor9NoNoise(testCase)
            r = testCase.Engine.simulate('shor9', 'depolarizing', 0, '0', 1);
            testCase.verifyGreaterThanOrEqual(r.fidelity, 0.95, ...
                'Shor code with no noise should have high fidelity');
        end

        % ── Steane code basic test ────────────────────────────────────────
        function testSteane7NoNoise(testCase)
            r = testCase.Engine.simulate('steane7', 'depolarizing', 0, '0', 1);
            testCase.verifyGreaterThanOrEqual(r.fidelity, 0.95, ...
                'Steane code with no noise should have high fidelity');
        end

        % ── Custom initial state ──────────────────────────────────────────
        function testCustomInitialState(testCase)
            r = testCase.Engine.simulate('bitflip3', 'bitflip', 0, '1', 1);
            testCase.verifyGreaterThanOrEqual(r.fidelity, 0.99, ...
                'Bit-flip code encoding |1⟩ with no noise should preserve fidelity');
        end
    end
end
