classdef RunPlannerService
    % RunPlannerService  Pure-math orchestrator for cost-aware run planning.
    %
    %   Cross-multiplies backends × mitigation strategies into candidate
    %   (cost, fidelity) points, applies a heuristic mitigation-fidelity
    %   factor, computes the Pareto frontier, and picks the optimal
    %   recommendation under a user-specified target fidelity.
    %
    %   Public API:
    %     RunPlannerService.mitigationFactorTable()                → struct
    %     RunPlannerService.applyMitigationFactor(base, level)     → double
    %     RunPlannerService.computeParetoFrontier(points)          → struct array
    %     RunPlannerService.pickOptimal(points, frontier, target)  → struct
    %     RunPlannerService.makePoint(...)                         → struct
    %
    %   Heuristic disclaimer: PredictionService.predict does not
    %   currently accept a mitigation-level parameter. We therefore
    %   apply a static multiplicative factor (table below) to convert
    %   base predicted fidelity into a per-strategy approximation. The
    %   caller MUST surface this disclaimer to the user. Phase 2 will
    %   replace the heuristic with a real backend endpoint.

    properties (Constant)
        FIDELITY_CAP = 0.99
    end

    methods (Static)
        function tbl = mitigationFactorTable()
            % Returns level_id (char) → struct('factor', double, 'label', char).
            % Keys match MitigationService level ids ('0' / '1' / '2' / '3').
            tbl = struct();
            tbl.x0 = struct('id', '0', 'label', 'None',       'factor', 1.00);
            tbl.x1 = struct('id', '1', 'label', 'Minimal',    'factor', 1.05);
            tbl.x2 = struct('id', '2', 'label', 'Standard',   'factor', 1.15);
            tbl.x3 = struct('id', '3', 'label', 'Aggressive', 'factor', 1.30);
        end

        function fidOut = applyMitigationFactor(baseFidelity, levelId)
            % Multiply base fidelity by the heuristic factor for `levelId`,
            % cap at FIDELITY_CAP. Unknown levels → factor = 1.0.
            if ~isfinite(baseFidelity); fidOut = NaN; return; end
            factor = 1.0;
            tbl = RunPlannerService.mitigationFactorTable();
            fns = fieldnames(tbl);
            for i = 1:numel(fns)
                row = tbl.(fns{i});
                if strcmp(row.id, char(string(levelId)))
                    factor = row.factor; break;
                end
            end
            fidOut = min(RunPlannerService.FIDELITY_CAP, baseFidelity * factor);
        end

        function p = makePoint(backend, levelId, levelLabel, baseFid, fid, cost, runtime, totalShots, shotMult)
            p = struct( ...
                'backend',       char(string(backend)), ...
                'level',         char(string(levelId)), ...
                'levelLabel',    char(string(levelLabel)), ...
                'baseFidelity',  double(baseFid), ...
                'fidelity',      double(fid), ...
                'cost',          double(cost), ...
                'runtime',       double(runtime), ...
                'totalShots',    double(totalShots), ...
                'shotMult',      double(shotMult));
        end

        function frontier = computeParetoFrontier(points)
            % Walks points sorted by cost ascending, keeping any point that
            % strictly improves on the best fidelity seen so far. Result
            % is the lower-cost-better-fidelity Pareto-optimal subset.
            frontier = struct( ...
                'backend', {}, 'level', {}, 'levelLabel', {}, ...
                'baseFidelity', {}, 'fidelity', {}, ...
                'cost', {}, 'runtime', {}, 'totalShots', {}, 'shotMult', {});
            if isempty(points); return; end
            % Drop points with non-finite cost or fidelity.
            keep = arrayfun(@(p) isfinite(p.cost) && isfinite(p.fidelity), points);
            points = points(keep);
            if isempty(points); return; end
            % Sort by cost ascending, then fidelity descending as tie-break.
            costs = [points.cost];
            fids  = [points.fidelity];
            [~, ord] = sortrows([costs(:), -fids(:)], [1 2]);
            sorted = points(ord);
            bestFid = -inf;
            for i = 1:numel(sorted)
                if sorted(i).fidelity > bestFid + 1e-9
                    frontier(end+1) = sorted(i); %#ok<AGROW>
                    bestFid = sorted(i).fidelity;
                end
            end
        end

        function r = pickOptimal(points, frontier, targetFidelity)
            % Among the frontier, the cheapest point with fidelity ≥ target
            % is the optimal recommendation. If none meets target, fall
            % back to the highest-fidelity point overall (NOT necessarily
            % on the frontier — the user wants the best they CAN get).
            r = struct( ...
                'point',     [], ...
                'metTarget', false, ...
                'reason',    '');
            if isempty(frontier) && isempty(points); return; end
            if ~isempty(frontier)
                fids = [frontier.fidelity];
                hit = find(fids >= targetFidelity, 1, 'first');  % cheapest first
                if ~isempty(hit)
                    r.point     = frontier(hit);
                    r.metTarget = true;
                    r.reason    = 'optimal frontier point hitting target';
                    return;
                end
            end
            % Target not met — fall back to highest-fidelity overall.
            allFids = [points.fidelity];
            [~, idx] = max(allFids);
            r.point     = points(idx);
            r.metTarget = false;
            r.reason    = 'target not reachable; highest-fidelity option';
        end
    end
end
