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
    %   `simulate` returns one entry per gate plus the initial state,
    %   each carrying:
    %       psi             complex column vector of length 2^n
    %       gate            the gate applied THIS step (or [] for step 0)
    %       blochPerQubit   n×3 real matrix [⟨X⟩ ⟨Y⟩ ⟨Z⟩] per qubit
    %       topAmps         struct array {state, prob} length ≤ K
    %       label           short caption ('Initial' / 'h q[0]' / ...)
    %       halted          true if subsequent gates were skipped
    %                       (first measurement halts the simulator)

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
            if ~isfield(opts, 'topK'); opts.topK = StatevectorSimulator.TOP_K_DEFAULT; end

            n = model.NumQubits;
            if n > StatevectorSimulator.MAX_QUBITS
                error('StatevectorSimulator:TooLarge', ...
                    'Local simulator capped at %d qubits (got %d)', ...
                    StatevectorSimulator.MAX_QUBITS, n);
            end

            % Initial |0...0⟩.
            psi = zeros(2^n, 1);
            psi(1) = 1;

            steps = repmat(StatevectorSimulator.makeStep(), 1, 1);
            steps(1) = StatevectorSimulator.makeStep( ...
                psi, [], 'Initial', n, opts.topK, false);

            halted = false;
            for i = 1:numel(model.Gates)
                g = model.Gates(i);
                if halted
                    steps(end+1) = StatevectorSimulator.makeStep( ...
                        psi, g, ...
                        sprintf('(skipped) %s', StatevectorSimulator.gateLabel(g)), ...
                        n, opts.topK, true); %#ok<AGROW>
                    continue;
                end
                switch g.kind
                    case 'measure'
                        halted = true;
                        steps(end+1) = StatevectorSimulator.makeStep( ...
                            psi, g, StatevectorSimulator.gateLabel(g), ...
                            n, opts.topK, true); %#ok<AGROW>
                    case 'barrier'
                        steps(end+1) = StatevectorSimulator.makeStep( ...
                            psi, g, StatevectorSimulator.gateLabel(g), ...
                            n, opts.topK, false); %#ok<AGROW>
                    case 'reset'
                        psi = StatevectorSimulator.applyReset(psi, n, g.qubits(1));
                        steps(end+1) = StatevectorSimulator.makeStep( ...
                            psi, g, StatevectorSimulator.gateLabel(g), ...
                            n, opts.topK, false); %#ok<AGROW>
                    otherwise
                        psi = StatevectorSimulator.applyGate(psi, n, g);
                        steps(end+1) = StatevectorSimulator.makeStep( ...
                            psi, g, StatevectorSimulator.gateLabel(g), ...
                            n, opts.topK, false); %#ok<AGROW>
                end
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
            [sortedP, idx] = sort(probs, 'descend');
            K = min(K, numel(probs));
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
        function step = makeStep(psi, gate, label, n, K, halted)
            if nargin == 0
                step = struct('psi', [], 'gate', [], 'label', '', ...
                    'blochPerQubit', [], ...
                    'topAmps', struct('state', {}, 'prob', {}), ...
                    'halted', false);
                return;
            end
            step = struct( ...
                'psi',           psi, ...
                'gate',          gate, ...
                'label',         label, ...
                'blochPerQubit', StatevectorSimulator.blochPerQubit(psi, n), ...
                'topAmps',       StatevectorSimulator.topAmplitudes(psi, K), ...
                'halted',        halted);
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

        function psi = apply1Q(psi, n, q, U)
            mask = bitshift(1, q);
            N = 2^n;
            for base = 0:N-1
                if bitand(base, mask) ~= 0; continue; end
                lo = base + 1;
                hi = bitor(base, mask) + 1;
                a = psi(lo); b = psi(hi);
                psi(lo) = U(1,1)*a + U(1,2)*b;
                psi(hi) = U(2,1)*a + U(2,2)*b;
            end
        end

        function psi = applyCX(psi, n, ctrl, tgt)
            mc = bitshift(1, ctrl);
            mt = bitshift(1, tgt);
            N = 2^n;
            for i = 0:N-1
                if bitand(i, mc) ~= 0 && bitand(i, mt) == 0
                    j = bitor(i, mt);
                    tmp = psi(i+1);
                    psi(i+1) = psi(j+1);
                    psi(j+1) = tmp;
                end
            end
        end

        function psi = applyCZ(psi, n, q1, q2)
            m = bitor(bitshift(1, q1), bitshift(1, q2));
            N = 2^n;
            for i = 0:N-1
                if bitand(i, m) == m
                    psi(i+1) = -psi(i+1);
                end
            end
        end

        function psi = applySwap(psi, n, q1, q2)
            m1 = bitshift(1, q1);
            m2 = bitshift(1, q2);
            N = 2^n;
            for i = 0:N-1
                b1 = bitand(i, m1) ~= 0;
                b2 = bitand(i, m2) ~= 0;
                if b1 ~= b2
                    j = bitxor(i, bitor(m1, m2));
                    if j > i
                        tmp = psi(i+1);
                        psi(i+1) = psi(j+1);
                        psi(j+1) = tmp;
                    end
                end
            end
        end

        function psi = applyCCX(psi, n, c1, c2, t)
            mc = bitor(bitshift(1, c1), bitshift(1, c2));
            mt = bitshift(1, t);
            N = 2^n;
            for i = 0:N-1
                if bitand(i, mc) == mc && bitand(i, mt) == 0
                    j = bitor(i, mt);
                    tmp = psi(i+1);
                    psi(i+1) = psi(j+1);
                    psi(j+1) = tmp;
                end
            end
        end

        function psi = applyReset(psi, n, q)
            % Project onto |0⟩_q, renormalise. If the |0⟩ branch has zero
            % weight, fall back to |0…0⟩ deterministically.
            mask = bitshift(1, q);
            N = 2^n;
            for i = 0:N-1
                if bitand(i, mask) ~= 0
                    psi(i+1) = 0;
                end
            end
            nrm = norm(psi);
            if nrm < 1e-12
                psi(:) = 0;
                psi(1) = 1;
            else
                psi = psi / nrm;
            end
        end

        function rho = reducedDensity1Q(psi, n, q)
            % Trace out all qubits except q. Sum |amp|² and cross terms
            % over the env basis (states that match on every non-q bit).
            mask = bitshift(1, q);
            N = 2^n;
            rho = zeros(2);
            for i = 0:N-1
                bit_i = (bitand(i, mask) ~= 0) + 1;
                a = psi(i+1);
                if a == 0; continue; end
                rho(bit_i, bit_i) = rho(bit_i, bit_i) + a * conj(a);
                % Cross term: pair (i, j) where j differs only at bit q.
                j = bitxor(i, mask);
                if j > i
                    b = psi(j+1);
                    if b ~= 0
                        bit_j = (bitand(j, mask) ~= 0) + 1;
                        rho(bit_i, bit_j) = rho(bit_i, bit_j) + a * conj(b);
                        rho(bit_j, bit_i) = rho(bit_j, bit_i) + b * conj(a);
                    end
                end
            end
        end
    end
end
