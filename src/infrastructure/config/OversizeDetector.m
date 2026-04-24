classdef OversizeDetector
    % OversizeDetector  Detect circuits too wide for any single backend in
    %                   the current pool, and nudge the user toward the
    %                   Circuit Cutting screen.
    %
    %   The detector is idempotent per session: it tracks which
    %   circuit/backend combinations have already been warned about in a
    %   persistent (in-process) set so the same oversize circuit doesn't
    %   pop a dialog on every data reload.
    %
    %   Usage (from a ViewModel after circuit + backends have both been
    %   fetched):
    %       OversizeDetector.check(app, circuit, backendPool);

    methods (Static)

        function check(app, circuit, backendPool)
            % Check if `circuit` exceeds the widest backend in `backendPool`
            % and, if so, show a one-time uialert pointing at the Circuit
            % Cutting screen. Silent when it fits.
            try
                nq = OversizeDetector.circuitQubits(circuit);
                maxQ = OversizeDetector.poolMaxQubits(backendPool);
                if nq <= 0 || maxQ <= 0 || nq <= maxQ
                    return;
                end
                cid = OversizeDetector.circuitKey(circuit);
                key = sprintf('%s:%d:%d', cid, nq, maxQ);
                if OversizeDetector.alreadyWarned(key); return; end
                OversizeDetector.markWarned(key);
                msg = sprintf([ ...
                    'This circuit has %d qubits, but the widest backend in the ' ...
                    'current pool only has %d. Open Circuit Cutting from the ' ...
                    'sidebar to split + distribute across multiple QPUs.'], ...
                    nq, maxQ);
                try
                    uialert(app.UIFigure, msg, 'Circuit Too Large', ...
                        'Icon', 'warning');
                catch
                    Logger.warn('OversizeDetector', ...
                        'uialert unavailable: %s', msg);
                end
            catch ME
                Logger.debug('OversizeDetector', 'check failed: %s', ME.message);
            end
        end

        function resetSession()
            % Forget all warnings for a new session (used on logout).
            OversizeDetector.warnedSet('clear');
        end
    end

    methods (Static, Access = private)

        function n = circuitQubits(circuit)
            n = 0;
            if isempty(circuit); return; end
            try
                n = double(JsonHelper.pick(circuit, ...
                    {'num_qubits','features.num_qubits'}, 0));
            catch; end
        end

        function m = poolMaxQubits(pool)
            m = 0;
            if isempty(pool); return; end
            if isstruct(pool) && isfield(pool, 'backends')
                items = JsonHelper.extractList(pool, 'backends');
            elseif iscell(pool)
                items = pool;
            else
                items = pool;
            end
            for i = 1:numel(items)
                b = items(i);
                if iscell(items); b = items{i}; end
                try
                    q = double(JsonHelper.pick(b, 'num_qubits', 0));
                    if ~isnumeric(q); q = 0; end
                    if q > m; m = q; end
                catch; end
            end
        end

        function s = circuitKey(circuit)
            try
                s = char(JsonHelper.pick(circuit, {'circuit_id','id'}, ''));
            catch
                s = '';
            end
            if isempty(s); s = '<unknown>'; end
        end

        function tf = alreadyWarned(key)
            tf = ismember(string(key), OversizeDetector.warnedSet());
        end

        function markWarned(key)
            OversizeDetector.warnedSet('add', string(key));
        end

        function s = warnedSet(op, value)
            % In-process persistent set. `op` is one of '', 'add', 'clear'.
            persistent warned
            if isempty(warned); warned = string.empty(1, 0); end
            if nargin >= 1 && strcmp(op, 'clear')
                warned = string.empty(1, 0);
                s = warned; return;
            end
            if nargin >= 2 && strcmp(op, 'add')
                warned = unique([warned, value]);
            end
            s = warned;
        end
    end
end
