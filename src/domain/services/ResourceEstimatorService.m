classdef ResourceEstimatorService
    % ResourceEstimatorService  Fault-tolerant resource overhead
    %                            calculator. Pure math, no HTTP.
    %
    %   Given a CircuitModel and a parameter struct, returns the
    %   physical-qubit / code-distance / T-factory / runtime estimate
    %   under a surface-code error-correction model.
    %
    %   Math sources:
    %     - Code distance: Fowler et al., "Surface codes: Towards
    %       practical large-scale quantum computation" (PRA 2012).
    %       Logical error per cycle ≈ 0.03 × (p_phys / p_th)^((d+1)/2).
    %     - Physical-per-logical (rotated planar surface code): 2d² + 1.
    %     - T-state synthesis: Selinger / Ross, Solovay-Kitaev rough
    %       bound 3·log2(1/ε) per arbitrary rotation.
    %     - 15-to-1 distillation factory: Bravyi & Kitaev, ~16d²
    %       physical qubits per active factory.
    %
    %   Public API:
    %     ResourceEstimatorService.estimate(model, params) → struct
    %     ResourceEstimatorService.defaultParams()         → struct
    %     ResourceEstimatorService.codeDistance(p, eps)    → int
    %     ResourceEstimatorService.tStateBudget(model, eps) → struct
    %     ResourceEstimatorService.isCliffordRotation(theta) → tf

    properties (Constant)
        SURFACE_THRESHOLD = 0.01
        PREFACTOR         = 0.03
        T_GATES_PER_TOFFOLI = 7
        T_FACTORY_FOOTPRINT_FACTOR = 16
        D_MIN = 3
        D_MAX = 51
    end

    methods (Static)
        function p = defaultParams()
            p = struct( ...
                'codeType',     'surface', ...
                'physErr',      1e-3, ...
                'logErr',       1e-15, ...
                'cycleSeconds', 1e-6);
        end

        function out = estimate(model, params)
            if nargin < 2; params = ResourceEstimatorService.defaultParams(); end
            if isempty(model) || ~isa(model, 'CircuitModel')
                error('ResourceEstimatorService:BadInput', ...
                    'estimate requires a CircuitModel instance');
            end

            tBudget = ResourceEstimatorService.tStateBudget(model, params.logErr);
            cliffordOnly = (tBudget.tGates == 0 && tBudget.toffolis == 0 && ...
                            tBudget.nonCliffordRotations == 0);

            d   = ResourceEstimatorService.codeDistance(params.physErr, params.logErr);
            phl = 2 * d^2 + 1;

            totalT = tBudget.tGates + ...
                     ResourceEstimatorService.T_GATES_PER_TOFFOLI * tBudget.toffolis + ...
                     tBudget.tGatesFromRotations;
            if totalT > 0
                tFactories = 1;
                factoryQubits = ResourceEstimatorService.T_FACTORY_FOOTPRINT_FACTOR * phl;
                tFactoryOverhead = 10;
            else
                tFactories = 0;
                factoryQubits = 0;
                tFactoryOverhead = 1;
            end

            logicalQubits = max(1, model.NumQubits);
            dataQubits    = logicalQubits * phl;
            ancillaQubits = ceil(0.10 * dataQubits);
            totalPhysical = dataQubits + ancillaQubits + factoryQubits;

            depth = max(1, model.depth());
            latticeCycles = depth * d * tFactoryOverhead;
            totalSeconds = latticeCycles * params.cycleSeconds;

            out = struct( ...
                'logicalQubits',         logicalQubits, ...
                'tGates',                tBudget.tGates, ...
                'toffolis',              tBudget.toffolis, ...
                'rotations',             tBudget.nonCliffordRotations, ...
                'tGatesFromRotations',   tBudget.tGatesFromRotations, ...
                'cliffordOnly',          cliffordOnly, ...
                'distance',              d, ...
                'physicalPerLogical',    phl, ...
                'dataQubits',            dataQubits, ...
                'ancillaQubits',         ancillaQubits, ...
                'factoryQubits',         factoryQubits, ...
                'totalPhysical',         totalPhysical, ...
                'tFactories',            tFactories, ...
                'tFactoryOverhead',      tFactoryOverhead, ...
                'totalT',                totalT, ...
                'depth',                 depth, ...
                'latticeCycles',         latticeCycles, ...
                'totalSeconds',          totalSeconds);
        end

        function d = codeDistance(physErr, logErr)
            % Fowler et al. inverse: solve 0.03 × (p / p_th)^((d+1)/2) = eps
            %   → (d+1)/2 = log(eps / 0.03) / log(p / p_th)
            %   → d = 2·ratio - 1
            % Both numerator and denominator are negative when p < p_th
            % AND eps < 0.03, so the ratio is positive and d > 0.
            pTh = ResourceEstimatorService.SURFACE_THRESHOLD;
            if physErr <= 0 || physErr >= 1
                error('ResourceEstimatorService:BadParam', ...
                    'physical error rate must be in (0, 1)');
            end
            if logErr <= 0 || logErr >= 1
                error('ResourceEstimatorService:BadParam', ...
                    'logical error rate must be in (0, 1)');
            end
            if physErr >= pTh
                % Above threshold → surface code does not reduce error;
                % cap at d_max to surface this clearly.
                d = ResourceEstimatorService.D_MAX;
                return;
            end
            ratio = log(logErr / ResourceEstimatorService.PREFACTOR) / log(physErr / pTh);
            dRaw = 2 * ratio - 1;
            d = max(ResourceEstimatorService.D_MIN, ceil(dRaw));
            if mod(d, 2) == 0; d = d + 1; end
            d = min(d, ResourceEstimatorService.D_MAX);
        end

        function b = tStateBudget(model, targetEps)
            % Count T-states needed for an arbitrary circuit. Splits
            % the count by source so the UI can show the breakdown.
            b = struct( ...
                'tGates',               0, ...
                'toffolis',             0, ...
                'nonCliffordRotations', 0, ...
                'tGatesFromRotations',  0);
            if nargin < 2 || isempty(targetEps); targetEps = 1e-15; end
            % Solovay-Kitaev rough cost per arbitrary rotation:
            %   ~3 · log2(1/ε)  T-gates
            sk = max(1, ceil(3 * log2(1 / max(targetEps, 1e-30))));
            for i = 1:numel(model.Gates)
                g = model.Gates(i);
                switch lower(g.kind)
                    case {'t', 'tdg'}
                        b.tGates = b.tGates + 1;
                    case 'ccx'
                        b.toffolis = b.toffolis + 1;
                    case {'rx', 'ry', 'rz'}
                        if ~isempty(g.params) && ~ResourceEstimatorService.isCliffordRotation(g.params(1))
                            b.nonCliffordRotations = b.nonCliffordRotations + 1;
                            b.tGatesFromRotations  = b.tGatesFromRotations + sk;
                        end
                end
            end
        end

        function tf = isCliffordRotation(theta)
            % Rotations by integer multiples of pi/2 along their axis are
            % Clifford (S, S†, X, Y, Z up to phase). Anything else is
            % non-Clifford and incurs T-state synthesis cost.
            if ~isfinite(theta); tf = false; return; end
            r = theta / (pi/2);
            tf = abs(r - round(r)) < 1e-9;
        end
    end
end
