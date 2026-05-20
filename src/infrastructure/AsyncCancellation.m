classdef AsyncCancellation
    % AsyncCancellation  Helpers for cancelling in-flight AsyncRunner futures
    %                     on nav-away.
    %
    %   The four lookup-driven screens (Backends, Mitigation Compare,
    %   Resource Estimator, Run Planner) fire one-to-many parfeval futures
    %   in their onEnter / onEstimate / onPlan handlers. When the user
    %   navigates away mid-fetch, three things should happen:
    %     1. Worker stops (saves backend RTT, IBM rate-limit budget).
    %     2. Polling timer stops (frees the 50 ms tick).
    %     3. Done/error callbacks DO NOT mutate the now-hidden panel.
    %
    %   This class wraps the small idiom every VM needs to honour those
    %   three guarantees:
    %
    %     properties
    %       NavGeneration   double = 0
    %       InFlightFutures cell   = {}
    %     end
    %
    %     function gen = bumpGen(obj)
    %       gen = AsyncCancellation.bump(obj.NavGeneration);
    %       obj.NavGeneration = gen;
    %     end
    %
    %     function dispatch(obj)
    %       gen = obj.bumpGen();
    %       fut = AsyncRunner.run(@work, @(r) obj.onDone(gen, r), ...);
    %       obj.InFlightFutures = AsyncCancellation.appendFutures( ...
    %         obj.InFlightFutures, fut);
    %     end
    %
    %     function onDone(obj, gen, result)
    %       if gen ~= obj.NavGeneration; return; end  % stale, bail
    %       % ... mutate UI ...
    %     end
    %
    %     function cancelInFlight(obj)
    %       obj.NavGeneration = AsyncCancellation.bump(obj.NavGeneration);
    %       obj.InFlightFutures = AsyncCancellation.cancelAll(obj.InFlightFutures);
    %     end
    %
    %   The generation bump in cancelInFlight invalidates any still-queued
    %   callback (cancel() may race with a worker that finished just before
    %   nav-away). The cancel sweep stops still-running workers.

    methods (Static)

        function newGen = bump(currentGen)
            % bump  Return the next generation tag. Pure function so the
            %   VM owns its own NavGeneration property and the helper
            %   stays stateless.
            if isempty(currentGen) || ~isnumeric(currentGen)
                newGen = 1;
            else
                newGen = double(currentGen) + 1;
            end
        end

        function trackList = appendFutures(trackList, newFutures)
            % appendFutures  Push one or many parfeval futures onto an
            %   existing cell-array tracker. Accepts a single future
            %   handle, an empty array (no-op), or a cell of futures
            %   (as returned by AsyncRunner.runMany).
            if isempty(newFutures); return; end
            if iscell(newFutures)
                for i = 1:numel(newFutures)
                    f = newFutures{i};
                    if ~isempty(f); trackList{end+1} = f; end %#ok<AGROW>
                end
            else
                trackList{end+1} = newFutures;
            end
        end

        function trackList = cancelAll(trackList)
            % cancelAll  Best-effort cancel of every tracked future,
            %   then clear the tracker. cancel() on a finished future
            %   is a no-op, so the wrap-in-try is purely defensive
            %   against transient handle invalidity.
            for i = 1:numel(trackList)
                f = trackList{i};
                try
                    if ~isempty(f) && isvalid(f); cancel(f); end
                catch
                end
            end
            trackList = {};
        end

        function tf = isCancellation(ME)
            % isCancellation  True when an MException carries the
            %   identifier shape MATLAB uses for a cancelled parfeval
            %   future. Two spellings exist across MATLAB releases
            %   (Cancelled vs Canceled); match both.
            tf = false;
            try
                id = char(ME.identifier);
                tf = contains(id, 'Cancelled', 'IgnoreCase', true) || ...
                     contains(id, 'Canceled',  'IgnoreCase', true);
            catch
            end
        end

    end
end
