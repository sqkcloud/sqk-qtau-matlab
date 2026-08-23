classdef StatevectorSimulator
    % StatevectorSimulator  Local MATLAB statevector simulator used by
    %                       the Composer Inspect footer.
    %
    %   Caps at 14 qubits (2^14 complex doubles ≈ 256 KB) per the C1
    %   design — anything larger should route to a server-side path.
    %   Single- and two-qubit gates are applied via in-place index
    %   slicing (no Kronecker products) so cost is O(g · 2^n) for g
    %   gates.
    %
    %   Public surface:
    %     StatevectorSimulator.simulate(model)            → struct array of steps
    %     StatevectorSimulator.maxQubits()                → 14
    %     StatevectorSimulator.canSimulate(model)         → tf
    %     StatevectorSimulator.gateLabel(gate)            → char (for caption)
    %
    %   `simulate` returns the initial state plus one entry per recorded
    %   gate. Without opts.maxSteps every gate is recorded; with a budget
    %   the walkthrough keeps evenly-spaced checkpoints and ALWAYS the
    %   final gate, so steps(end) is the circuit's true end state either
    %   way. Each entry carries:
    %       psi             complex column vector of length 2^n —
    %                       populated on the FINAL step only (earlier
    %                       steps are nulled to bound retained memory)
    %       gate            the gate applied THIS step (or [] for step 0)
    %       blochPerQubit   n×3 real matrix [⟨X⟩ ⟨Y⟩ ⟨Z⟩] per qubit
    %       topAmps         struct array {state, prob} length ≤ K
    %       label           short caption ('Initial' / 'h q[0]' / ...)
    %       halted          true once a measurement has stopped
    %                       evolution (remaining gates are counted in
    %                       the final step's label, not simulated)
    %       gateIndex       1-based index of this gate in the circuit
    %                       (0 for the initial state)
    %       totalGates      gate count of the whole circuit, so callers
    %                       report progress in gates rather than steps

    properties (Constant)
        MAX_QUBITS = 14
        TOP_K_DEFAULT = 16
    end

    methods (Static)
        function tf = canSimulate(model)
            tf = ~isempty(model) && isa(model, 'CircuitModel') && ...
                 model.NumQubits > 0 && ...
                 model.NumQubits <= StatevectorSimulator.MAX_QUBITS;
        end

        function n = maxQubits()
            n = StatevectorSimulator.MAX_QUBITS;
        end

        function steps = simulate(model, opts)
            if nargin < 2; opts = struct(); end
            if ~isfield(opts, 'topK') || isempty(opts.topK)
                opts.topK = StatevectorSimulator.TOP_K_DEFAULT;
            end
            % maxSteps bounds how many steps the walkthrough RETAINS —
            % it never bounds how many gates are applied. The Inspect
            % footer passes a finite budget so a huge imported circuit
            % can't build thousands of per-step summaries synchronously
            % on the UI thread; the simulator then records every
            % stride-th gate as a checkpoint. Evolution always runs to
            % the end, so the last step is the circuit's TRUE final
            % state and never a truncated prefix presented as one.
            % Unset ⇒ record every gate.
            if ~isfield(opts, 'maxSteps') || isempty(opts.maxSteps)
                opts.maxSteps = inf;
            end

            n = model.NumQubits;
            if n > StatevectorSimulator.MAX_QUBITS
                error('StatevectorSimulator:TooLarge', ...
                    'Local simulator capped at %d qubits (got %d)', ...
                    StatevectorSimulator.MAX_QUBITS, n);
            end

            % Initial |0...0⟩.
            psi = zeros(2^n, 1);
            psi(1) = 1;

            G = numel(model.Gates);

            % Checkpoint stride. With a budget of B retained steps, one
            % is spent on the initial state, leaving B-1 for gates, so
            % record every ceil(G/(B-1))-th gate. The final gate is
            % ALWAYS recorded regardless of stride.
            stride = 1;
            if isfinite(opts.maxSteps) && G > 0
                budget = max(2, floor(opts.maxSteps));
                if G > budget - 1
                    stride = ceil(G / (budget - 1));
                end
            end

            steps = repmat(StatevectorSimulator.makeStep(), 1, 1);
            steps(1) = StatevectorSimulator.makeStep( ...
                psi, [], 'Initial', n, opts.topK, false, 0, G);

            halted  = false;
            skipped = 0;
            for i = 1:G
                if halted
                    % Evolution already stopped at the first
                    % measurement — count the rest instead of building
                    % an identical summary per remaining gate.
                    skipped = skipped + 1;
                    continue;
                end
                g = model.Gates(i);
                mustRecord = false;
                switch g.kind
                    case 'measure'
                        halted = true;
                        mustRecord = true;
                    case 'barrier'
                        % no state change
                    case 'reset'
                        psi = StatevectorSimulator.applyReset(psi, n, g.qubits(1));
                    otherwise
                        psi = StatevectorSimulator.applyGate(psi, n, g);
                end
                if mustRecord || mod(i, stride) == 0 || i == G
                    steps(end+1) = StatevectorSimulator.makeStep( ...
                        psi, g, StatevectorSimulator.gateLabel(g), ...
                        n, opts.topK, halted, i, G); %#ok<AGROW>
                end
            end

            % Retain the full statevector only on the FINAL step (the
            % one SimulationService and tests consume). Intermediate
            % steps keep just their derived Bloch/topAmps summaries, so
            % total retained memory is O(2^n)+O(g·n) rather than the
            % O(g·2^n) that storing every step's psi would cost.
            for k = 1:numel(steps)-1
                steps(k).psi = [];
            end
            if skipped > 0
                steps(end).label = sprintf('%s  [+%d gate(s) skipped after measurement]', ...
                    steps(end).label, skipped);
            end
        end

        function lbl = gateLabel(g)
            if isempty(g); lbl = 'Initial'; return; end
            switch g.kind
                case {'h','x','y','z','s','t','sdg','tdg','reset'}
                    lbl = sprintf('%s q[%d]', upper(g.kind), g.qubits(1));
                case {'rx','ry','rz'}
                    lbl = sprintf('%s(%s) q[%d]', upper(g.kind), ...
                        CircuitModel.formatTheta(g.params(1)), g.qubits(1));
                case 'cx'
                    lbl = sprintf('CX q[%d]→q[%d]', g.qubits(1), g.qubits(2));
                case 'cz'
                    lbl = sprintf('CZ q[%d]·q[%d]', g.qubits(1), g.qubits(2));
                case 'swap'
                    lbl = sprintf('SWAP q[%d]↔q[%d]', g.qubits(1), g.qubits(2));
                case 'ccx'
                    lbl = sprintf('CCX q[%d],q[%d]→q[%d]', ...
                        g.qubits(1), g.qubits(2), g.qubits(3));
                case 'measure'
                    lbl = sprintf('Measure q[%d]', g.qubits(1));
                case 'barrier'
                    lbl = 'Barrier';
                otherwise
                    lbl = char(g.kind);
            end
        end

        function bloch = blochPerQubit(psi, n)
            bloch = zeros(n, 3);
            for q = 0:n-1
                rho = StatevectorSimulator.reducedDensity1Q(psi, n, q);
                bloch(q+1, 1) = real(rho(1,2) + rho(2,1));         % ⟨X⟩
                bloch(q+1, 2) = real(1i * (rho(1,2) - rho(2,1)));  % ⟨Y⟩
                bloch(q+1, 3) = real(rho(1,1) - rho(2,2));         % ⟨Z⟩
            end
        end

        function top = topAmplitudes(psi, K)
            probs = abs(psi).^2;
            K = min(K, numel(probs));
            % Partial top-K selection (O(2^n)) instead of a full
            % descending sort (O(2^n log 2^n)) — only the K largest
            % probabilities are ever shown in the Inspect footer.
            [sortedP, idx] = maxk(probs, K);
            top = struct('state', {}, 'prob', {});
            for i = 1:K
                if sortedP(i) < 1e-9 && i > 1; break; end
                top(end+1) = struct( ...
                    'state', idx(i) - 1, ...
                    'prob',  sortedP(i)); %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function step = makeStep(psi, gate, label, n, K, halted, gateIndex, totalGates)
            % gateIndex / totalGates let the caller report progress in
            % GATES rather than retained steps — a sampled walkthrough
            % must never present "255 / 255" as a finished circuit.
            % Both branches must declare the same fields in the same
            % order: steps(1) is seeded from the nargin==0 prototype and
            % MATLAB rejects steps(end+1) when the field sets differ.
            if nargin == 0
                step = struct('psi', [], 'gate', [], 'label', '', ...
                    'blochPerQubit', [], ...
                    'topAmps', struct('state', {}, 'prob', {}), ...
                    'halted', false, ...
                    'gateIndex', 0, 'totalGates', 0);
                return;
            end
            step = struct( ...
                'psi',           psi, ...
                'gate',          gate, ...
                'label',         label, ...
                'blochPerQubit', StatevectorSimulator.blochPerQubit(psi, n), ...
                'topAmps',       StatevectorSimulator.topAmplitudes(psi, K), ...
                'halted',        halted, ...
                'gateIndex',     gateIndex, ...
                'totalGates',    totalGates);
        end

        function psi = applyGate(psi, n, g)
            switch g.kind
                case {'h','x','y','z','s','t','sdg','tdg'}
                    U = StatevectorSimulator.matrix1Q(g.kind);
                    psi = StatevectorSimulator.apply1Q(psi, n, g.qubits(1), U);
                case {'rx','ry','rz'}
                    U = StatevectorSimulator.matrixRot(g.kind, g.params(1));
                    psi = StatevectorSimulator.apply1Q(psi, n, g.qubits(1), U);
                case 'cx'
                    psi = StatevectorSimulator.applyCX(psi, n, g.qubits(1), g.qubits(2));
                case 'cz'
                    psi = StatevectorSimulator.applyCZ(psi, n, g.qubits(1), g.qubits(2));
                case 'swap'
                    psi = StatevectorSimulator.applySwap(psi, n, g.qubits(1), g.qubits(2));
                case 'ccx'
                    psi = StatevectorSimulator.applyCCX(psi, n, ...
                        g.qubits(1), g.qubits(2), g.qubits(3));
                otherwise
                    error('StatevectorSimulator:UnknownGate', ...
                        'Cannot apply gate kind: %s', g.kind);
            end
        end

        function U = matrix1Q(kind)
            switch kind
                case 'h';   U = (1/sqrt(2)) * [1 1; 1 -1];
                case 'x';   U = [0 1; 1 0];
                case 'y';   U = [0 -1i; 1i 0];
                case 'z';   U = [1 0; 0 -1];
                case 's';   U = [1 0; 0 1i];
                case 't';   U = [1 0; 0 exp(1i*pi/4)];
                case 'sdg'; U = [1 0; 0 -1i];
                case 'tdg'; U = [1 0; 0 exp(-1i*pi/4)];
                otherwise;  U = eye(2);
            end
        end

        function U = matrixRot(kind, theta)
            c = cos(theta/2); s = sin(theta/2);
            switch kind
                case 'rx'; U = [c, -1i*s; -1i*s, c];
                case 'ry'; U = [c, -s; s, c];
                case 'rz'; U = [exp(-1i*theta/2), 0; 0, exp(1i*theta/2)];
                otherwise; U = eye(2);
            end
        end

        % ── Gate kernels ─────────────────────────────────────────────────
        % All kernels are vectorised over the 2^n amplitudes. A step
        % budget samples which states are RETAINED but every gate is
        % still applied, so a 5000-gate import runs the full evolution —
        % interpreted per-amplitude loops made that the dominant cost.
        % Index arithmetic is unchanged: index = 1 + Σ bₖ·2ᵏ.

        function psi = apply1Q(psi, n, q, U)
            % Bit q varies with stride 2^q, so the sub-vectors for
            % q=0 and q=1 are two slices of a 3-D reshape.
            A  = reshape(psi, 2^q, 2, 2^(n-q-1));
            a0 = A(:, 1, :);
            a1 = A(:, 2, :);
            A(:, 1, :) = U(1,1)*a0 + U(1,2)*a1;
            A(:, 2, :) = U(2,1)*a0 + U(2,2)*a1;
            psi = reshape(A, [], 1);
        end

        function psi = applyCX(psi, n, ctrl, tgt)
            mc = bitshift(1, ctrl);
            mt = bitshift(1, tgt);
            i  = (0:2^n-1).';
            sel = bitand(i, mc) ~= 0 & bitand(i, mt) == 0;
            lo = i(sel) + 1;
            hi = bitor(i(sel), mt) + 1;
            tmp      = psi(lo);
            psi(lo)  = psi(hi);
            psi(hi)  = tmp;
        end

        function psi = applyCZ(psi, n, q1, q2)
            m = bitor(bitshift(1, q1), bitshift(1, q2));
            i = (0:2^n-1).';
            sel = bitand(i, m) == m;
            psi(sel) = -psi(sel);
        end

        function psi = applySwap(psi, n, q1, q2)
            m1 = bitshift(1, q1);
            m2 = bitshift(1, q2);
            i  = (0:2^n-1).';
            % Select the q1=1,q2=0 side of each differing pair so every
            % pair is swapped exactly once (the scalar version used a
            % j > i guard for the same reason).
            sel = bitand(i, m1) ~= 0 & bitand(i, m2) == 0;
            lo = i(sel) + 1;
            hi = bitxor(i(sel), bitor(m1, m2)) + 1;
            tmp     = psi(lo);
            psi(lo) = psi(hi);
            psi(hi) = tmp;
        end

        function psi = applyCCX(psi, n, c1, c2, t)
            mc = bitor(bitshift(1, c1), bitshift(1, c2));
            mt = bitshift(1, t);
            i  = (0:2^n-1).';
            sel = bitand(i, mc) == mc & bitand(i, mt) == 0;
            lo = i(sel) + 1;
            hi = bitor(i(sel), mt) + 1;
            tmp     = psi(lo);
            psi(lo) = psi(hi);
            psi(hi) = tmp;
        end

        function psi = applyReset(psi, n, q)
            % Project onto |0⟩_q, renormalise. If the |0⟩ branch has zero
            % weight, fall back to |0…0⟩ deterministically.
            mask = bitshift(1, q);
            i = (0:2^n-1).';
            psi(bitand(i, mask) ~= 0) = 0;
            nrm = norm(psi);
            if nrm < 1e-12
                psi(:) = 0;
                psi(1) = 1;
            else
                psi = psi / nrm;
            end
        end

        function rho = reducedDensity1Q(psi, n, q)
            % Trace out all qubits except q.
            %
            % Amplitude index is 1 + Σ bₖ·2ᵏ and MATLAB is column-major,
            % so bit q varies with stride 2^q. Reshaping to
            % (2^q × 2 × 2^(n-q-1)) therefore puts the q=0 amplitudes in
            % A(:,1,:) and the q=1 amplitudes in A(:,2,:), and the whole
            % partial trace collapses to four vector reductions.
            %
            % This replaces a scalar loop over all 2^n amplitudes. The
            % Inspect footer calls this n times per step, so at the
            % 14-qubit cap a 256-step walkthrough ran ~59M interpreted
            % loop iterations on the UI thread per refresh.
            A  = reshape(psi, 2^q, 2, 2^(n-q-1));
            a0 = A(:, 1, :);
            a1 = A(:, 2, :);
            rho = zeros(2);
            rho(1,1) = sum(abs(a0(:)).^2);
            rho(2,2) = sum(abs(a1(:)).^2);
            rho(1,2) = sum(a0(:) .* conj(a1(:)));
            rho(2,1) = conj(rho(1,2));
        end
    end
end
