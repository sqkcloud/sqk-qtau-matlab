classdef TemplateRegistry
    % TemplateRegistry  Catalogue of 18 curated quantum-circuit templates
    %                   used by the Composer screen's gallery.
    %
    %   Each template is generated programmatically into a CircuitModel —
    %   parameterized templates (GHZ_n, QFT_n, Grover_k, Bernstein-Vazirani_n,
    %   Deutsch-Jozsa_n, W_n, IQFT_n, HEA) build their gate list at
    %   instantiate-time from the user-supplied parameters. Static templates
    %   (Bell, Phase Estimation toy, VQE H2, QAOA Max-Cut, Trotter,
    %   Teleportation, Superdense, Bit-Flip Code, Phase-Flip Code, CHSH)
    %   accept the same `params` struct shape but ignore unused fields.
    %
    %   Public surface:
    %     TemplateRegistry.list()                   → struct array of metadata
    %     TemplateRegistry.find(id)                 → metadata for one template
    %     TemplateRegistry.defaultParams(id)        → struct with default params
    %     TemplateRegistry.instantiate(id, params)  → CircuitModel ready to render
    %
    %   Instantiation is pure — no I/O, no AppState reads — so it can be
    %   called from tests as well as the live UI. Bad params throw an
    %   MException with a clear message that the ViewModel surfaces in
    %   the parameter dialog.

    methods (Static)
        function items = list()
            items = [
                tpl('bell',       Labels.get('composer_template_bell'),       Labels.get('composer_template_bell_desc'),       2,  false)
                tpl('ghz',        Labels.get('composer_template_ghz'),        Labels.get('composer_template_ghz_desc'),        4,  true)
                tpl('wstate',     Labels.get('composer_template_wstate'),     Labels.get('composer_template_wstate_desc'),     4,  true)
                tpl('qft',        Labels.get('composer_template_qft'),        Labels.get('composer_template_qft_desc'),        4,  true)
                tpl('iqft',       Labels.get('composer_template_iqft'),       Labels.get('composer_template_iqft_desc'),       4,  true)
                tpl('grover',     Labels.get('composer_template_grover'),     Labels.get('composer_template_grover_desc'),     4,  true)
                tpl('bv',         Labels.get('composer_template_bv'),         Labels.get('composer_template_bv_desc'),         5,  true)
                tpl('dj',         Labels.get('composer_template_dj'),         Labels.get('composer_template_dj_desc'),         4,  true)
                tpl('pe',         Labels.get('composer_template_pe'),         Labels.get('composer_template_pe_desc'),         4,  false)
                tpl('vqe',        Labels.get('composer_template_vqe'),        Labels.get('composer_template_vqe_desc'),        2,  true)
                tpl('hea',        Labels.get('composer_template_hea'),        Labels.get('composer_template_hea_desc'),        4,  true)
                tpl('qaoa',       Labels.get('composer_template_qaoa'),       Labels.get('composer_template_qaoa_desc'),       3,  true)
                tpl('trotter',    Labels.get('composer_template_trotter'),    Labels.get('composer_template_trotter_desc'),    4,  true)
                tpl('teleport',   Labels.get('composer_template_teleport'),   Labels.get('composer_template_teleport_desc'),   3,  false)
                tpl('superdense', Labels.get('composer_template_superdense'), Labels.get('composer_template_superdense_desc'), 2,  true)
                tpl('bitflip',    Labels.get('composer_template_bitflip'),    Labels.get('composer_template_bitflip_desc'),    3,  false)
                tpl('phaseflip',  Labels.get('composer_template_phaseflip'),  Labels.get('composer_template_phaseflip_desc'),  3,  false)
                tpl('chsh',       Labels.get('composer_template_chsh'),       Labels.get('composer_template_chsh_desc'),       2,  false)
            ];
        end

        function meta = find(id)
            items = TemplateRegistry.list();
            ids   = {items.id};
            idx   = find(strcmp(ids, char(id)), 1);
            if isempty(idx)
                error('TemplateRegistry:UnknownId', ...
                    'No template with id "%s"', id);
            end
            meta = items(idx);
        end

        function p = defaultParams(id)
            switch char(id)
                case 'bell';       p = struct();
                case 'ghz';        p = struct('n', 4);
                case 'wstate';     p = struct('n', 4);
                case 'qft';        p = struct('n', 4);
                case 'iqft';       p = struct('n', 4);
                case 'grover';     p = struct('k', 3, 'marked', '101');
                case 'bv';         p = struct('n', 4, 'hidden', '1011');
                case 'dj';         p = struct('n', 3, 'balanced', 1);
                case 'pe';         p = struct();
                case 'vqe';        p = struct('theta', pi/4);
                case 'hea';        p = struct('n', 4, 'layers', 2);
                case 'qaoa';       p = struct('gamma', pi/3, 'beta', pi/4);
                case 'trotter';    p = struct('dt', 0.4, 'steps', 2);
                case 'teleport';   p = struct();
                case 'superdense'; p = struct('message', '11');
                case 'bitflip';    p = struct();
                case 'phaseflip';  p = struct();
                case 'chsh';       p = struct();
                otherwise
                    error('TemplateRegistry:UnknownId', ...
                        'No defaultParams for "%s"', id);
            end
        end

        function model = instantiate(id, params)
            if nargin < 2; params = TemplateRegistry.defaultParams(id); end
            switch char(id)
                case 'bell';       model = TemplateRegistry.buildBell();
                case 'ghz';        model = TemplateRegistry.buildGhz(params.n);
                case 'wstate';     model = TemplateRegistry.buildWState(params.n);
                case 'qft';        model = TemplateRegistry.buildQft(params.n);
                case 'iqft';       model = TemplateRegistry.buildIqft(params.n);
                case 'grover';     model = TemplateRegistry.buildGrover(params.k, params.marked);
                case 'bv';         model = TemplateRegistry.buildBv(params.n, params.hidden);
                case 'dj';         model = TemplateRegistry.buildDj(params.n, params.balanced);
                case 'pe';         model = TemplateRegistry.buildPe();
                case 'vqe';        model = TemplateRegistry.buildVqe(params.theta);
                case 'hea';        model = TemplateRegistry.buildHea(params.n, params.layers);
                case 'qaoa';       model = TemplateRegistry.buildQaoa(params.gamma, params.beta);
                case 'trotter';    model = TemplateRegistry.buildTrotter(params.dt, params.steps);
                case 'teleport';   model = TemplateRegistry.buildTeleport();
                case 'superdense'; model = TemplateRegistry.buildSuperdense(params.message);
                case 'bitflip';    model = TemplateRegistry.buildBitFlipCode();
                case 'phaseflip';  model = TemplateRegistry.buildPhaseFlipCode();
                case 'chsh';       model = TemplateRegistry.buildChsh();
                otherwise
                    error('TemplateRegistry:UnknownId', ...
                        'No instantiator for "%s"', id);
            end
        end
    end

    methods (Static, Access = private)
        % ── Builders ──────────────────────────────────────────────────────
        function m = buildBell()
            m = CircuitModel(2);
            m.addGate('h',  0);
            m.addGate('cx', [0 1]);
            m.addGate('measure', 0);
            m.addGate('measure', 1);
        end

        function m = buildGhz(n)
            n = TemplateRegistry.clampN(n, 2, 16);
            m = CircuitModel(n);
            m.addGate('h', 0);
            for q = 1:n-1
                m.addGate('cx', [0 q]);
            end
        end

        function m = buildQft(n)
            n = TemplateRegistry.clampN(n, 2, 8);
            m = CircuitModel(n);
            % Standard QFT on n qubits. Substitute controlled-phase via
            % Rz/CX decomposition so we stay inside palette gates.
            for j = 0:n-1
                m.addGate('h', j);
                for k = j+1:n-1
                    angle = pi / 2^(k - j);
                    m.addGate('rz', k,  angle/2);
                    m.addGate('cx', [j k]);
                    m.addGate('rz', k, -angle/2);
                    m.addGate('cx', [j k]);
                end
            end
            % Bit-reversal swaps.
            for j = 0:floor(n/2)-1
                m.addGate('swap', [j, n-1-j]);
            end
        end

        function m = buildGrover(k, markedStr)
            k = TemplateRegistry.clampN(k, 2, 6);
            n = k + 1;
            m = CircuitModel(n);
            marked = TemplateRegistry.padBits(markedStr, k);
            anc = k;

            for q = 0:k-1; m.addGate('h', q); end
            m.addGate('x', anc);
            m.addGate('h', anc);

            % Oracle: flip ancilla iff data qubits == marked.
            for q = 0:k-1
                if marked(q+1) == '0'; m.addGate('x', q); end
            end
            if k == 2
                m.addGate('ccx', [0 1 anc]);
            else
                % k>=3: chained CCX onto a borrowed register; users
                % see the chain explicitly so the multi-control structure
                % is visible in the canvas.
                m.addGate('ccx', [0 1 anc]);
                for q = 2:k-1
                    m.addGate('ccx', [q anc 0]);
                end
            end
            for q = 0:k-1
                if marked(q+1) == '0'; m.addGate('x', q); end
            end

            % Diffuser.
            for q = 0:k-1; m.addGate('h', q); end
            for q = 0:k-1; m.addGate('x', q); end
            if k >= 2; m.addGate('h', k-1); end
            if k == 2
                m.addGate('cx', [0 1]);
            else
                m.addGate('ccx', [0 1 k-1]);
            end
            if k >= 2; m.addGate('h', k-1); end
            for q = 0:k-1; m.addGate('x', q); end
            for q = 0:k-1; m.addGate('h', q); end

            for q = 0:k-1; m.addGate('measure', q); end
        end

        function m = buildBv(n, hiddenStr)
            n = TemplateRegistry.clampN(n, 1, 12);
            m = CircuitModel(n + 1);
            hidden = TemplateRegistry.padBits(hiddenStr, n);
            anc = n;
            for q = 0:n-1; m.addGate('h', q); end
            m.addGate('x', anc); m.addGate('h', anc);
            for q = 0:n-1
                if hidden(q+1) == '1'
                    m.addGate('cx', [q anc]);
                end
            end
            for q = 0:n-1; m.addGate('h', q); end
            for q = 0:n-1; m.addGate('measure', q); end
        end

        function m = buildDj(n, balanced)
            n = TemplateRegistry.clampN(n, 1, 12);
            m = CircuitModel(n + 1);
            anc = n;
            for q = 0:n-1; m.addGate('h', q); end
            m.addGate('x', anc); m.addGate('h', anc);
            if balanced
                m.addGate('cx', [0 anc]);
            end
            for q = 0:n-1; m.addGate('h', q); end
            for q = 0:n-1; m.addGate('measure', q); end
        end

        function m = buildPe()
            % Toy 4-qubit phase estimation: 3 counting qubits + 1 eigenstate.
            m = CircuitModel(4);
            ev = 3;
            m.addGate('x', ev);
            for q = 0:2; m.addGate('h', q); end
            for j = 0:2
                angle = (pi/4) * 2^j;
                m.addGate('rz', ev,  angle/2);
                m.addGate('cx', [j ev]);
                m.addGate('rz', ev, -angle/2);
                m.addGate('cx', [j ev]);
            end
            % Inverse QFT on counting register (3 qubits).
            iqft = TemplateRegistry.buildQft(3);
            for i = numel(iqft.Gates):-1:1
                g = iqft.Gates(i);
                if any(strcmp({'rz'}, g.kind))
                    m.addGate(g.kind, g.qubits, -g.params);
                else
                    m.addGate(g.kind, g.qubits, g.params);
                end
            end
            for q = 0:2; m.addGate('measure', q); end
        end

        function m = buildVqe(theta)
            m = CircuitModel(2);
            m.addGate('ry', 0, theta);
            m.addGate('ry', 1, theta);
            m.addGate('cx', [0 1]);
            m.addGate('ry', 0, theta/2);
            m.addGate('ry', 1, theta/2);
        end

        function m = buildQaoa(gamma, beta)
            m = CircuitModel(3);
            for q = 0:2; m.addGate('h', q); end
            edges = {[0 1], [1 2], [0 2]};
            for i = 1:numel(edges)
                e = edges{i};
                m.addGate('cx', e);
                m.addGate('rz', e(2), 2*gamma);
                m.addGate('cx', e);
            end
            for q = 0:2; m.addGate('rx', q, 2*beta); end
            for q = 0:2; m.addGate('measure', q); end
        end

        function m = buildTrotter(dt, steps)
            steps = max(1, round(steps));
            m = CircuitModel(4);
            for s = 1:steps
                for j = 0:2
                    % XX(dt)
                    m.addGate('h', j);
                    m.addGate('h', j+1);
                    m.addGate('cx', [j j+1]);
                    m.addGate('rz', j+1, dt);
                    m.addGate('cx', [j j+1]);
                    m.addGate('h', j);
                    m.addGate('h', j+1);
                    % YY(dt)
                    m.addGate('s',  j);
                    m.addGate('s',  j+1);
                    m.addGate('h',  j);
                    m.addGate('h',  j+1);
                    m.addGate('cx', [j j+1]);
                    m.addGate('rz', j+1, dt);
                    m.addGate('cx', [j j+1]);
                    m.addGate('h',  j);
                    m.addGate('h',  j+1);
                    m.addGate('sdg', j);
                    m.addGate('sdg', j+1);
                end
            end
        end

        function m = buildTeleport()
            m = CircuitModel(3);
            m.addGate('h', 0);             % state to teleport: |+⟩ on q[0]
            m.addGate('h', 1);             % EPR pair (q[1], q[2])
            m.addGate('cx', [1 2]);
            m.addGate('cx', [0 1]);        % Bell measurement basis
            m.addGate('h', 0);
            m.addGate('measure', 0);
            m.addGate('measure', 1);
            % Conditional corrections (palette has no classical-control;
            % the circuit shows the correction structure unconditionally).
            m.addGate('x', 2);
            m.addGate('z', 2);
            m.addGate('measure', 2);
        end

        function m = buildSuperdense(messageStr)
            msg = TemplateRegistry.padBits(messageStr, 2);
            m = CircuitModel(2);
            m.addGate('h', 0);
            m.addGate('cx', [0 1]);
            if msg(2) == '1'; m.addGate('x', 0); end
            if msg(1) == '1'; m.addGate('z', 0); end
            m.addGate('cx', [0 1]);
            m.addGate('h', 0);
            m.addGate('measure', 0);
            m.addGate('measure', 1);
        end

        function m = buildWState(n)
            % W state |W_n⟩ = (|10..0⟩ + |010..0⟩ + … + |0..01⟩)/√n.
            % Iterative construction (Cruz et al. 2018, simplified): seed
            % |10..0⟩, then for each i, controlled-Ry rotates the next
            % qubit and a CX hands off the |1⟩.  Controlled-Ry(θ) is
            % decomposed into Ry(θ/2)·CX·Ry(-θ/2)·CX since the palette
            % has no native CRy.
            n = TemplateRegistry.clampN(n, 2, 8);
            m = CircuitModel(n);
            m.addGate('x', 0);
            for i = 0:n-2
                theta = 2 * acos(sqrt(1.0 / (n - i)));
                m.addGate('ry', i+1,  theta/2);
                m.addGate('cx', [i i+1]);
                m.addGate('ry', i+1, -theta/2);
                m.addGate('cx', [i i+1]);
                m.addGate('cx', [i+1 i]);
            end
        end

        function m = buildIqft(n)
            % Inverse QFT — reverse the QFT gate list and negate rotations.
            n = TemplateRegistry.clampN(n, 2, 8);
            qft = TemplateRegistry.buildQft(n);
            m = CircuitModel(n);
            for i = numel(qft.Gates):-1:1
                g = qft.Gates(i);
                if any(strcmp({'rx','ry','rz'}, g.kind))
                    m.addGate(g.kind, g.qubits, -g.params);
                elseif strcmp(g.kind, 's');   m.addGate('sdg', g.qubits);
                elseif strcmp(g.kind, 'sdg'); m.addGate('s',   g.qubits);
                elseif strcmp(g.kind, 't');   m.addGate('tdg', g.qubits);
                elseif strcmp(g.kind, 'tdg'); m.addGate('t',   g.qubits);
                else
                    % Self-inverse: H, X, Y, Z, CX, CZ, SWAP, CCX.
                    m.addGate(g.kind, g.qubits, g.params);
                end
            end
        end

        function m = buildHea(n, layers)
            % Hardware-Efficient Ansatz (RealAmplitudes-style):
            % alternating Ry rotation layers + linear CX entanglement.
            % Rotation angle is parameterized as θ = π/4 by default —
            % real variational use replaces these with trainable angles.
            n = TemplateRegistry.clampN(n, 2, 6);
            if isempty(layers) || ~isnumeric(layers) || ~isfinite(layers)
                layers = 2;
            end
            layers = max(1, min(6, round(layers)));
            theta = pi/4;
            m = CircuitModel(n);
            for L = 1:layers
                for q = 0:n-1
                    m.addGate('ry', q, theta);
                end
                for q = 0:n-2
                    m.addGate('cx', [q q+1]);
                end
                m.addGate('barrier', 0:n-1);
            end
            % Final rotation layer (RealAmplitudes convention).
            for q = 0:n-1
                m.addGate('ry', q, theta);
            end
        end

        function m = buildBitFlipCode()
            % 3-qubit repetition (bit-flip) code.  Encodes α|0⟩+β|1⟩ on
            % q[0] into α|000⟩+β|111⟩, then majority-vote decodes after
            % an (unmodeled) error channel.  Barriers mark the encode /
            % error / decode boundaries so the structure stays readable.
            m = CircuitModel(3);
            m.addGate('cx', [0 1]);
            m.addGate('cx', [0 2]);
            m.addGate('barrier', [0 1 2]);   % ── error channel here ──
            m.addGate('barrier', [0 1 2]);
            m.addGate('cx', [0 1]);
            m.addGate('cx', [0 2]);
            m.addGate('ccx', [1 2 0]);
            m.addGate('measure', 0);
        end

        function m = buildPhaseFlipCode()
            % 3-qubit phase-flip code — bit-flip code conjugated by H so
            % the protected error is Z rather than X.
            m = CircuitModel(3);
            m.addGate('cx', [0 1]);
            m.addGate('cx', [0 2]);
            m.addGate('h', 0); m.addGate('h', 1); m.addGate('h', 2);
            m.addGate('barrier', [0 1 2]);   % ── phase error channel here ──
            m.addGate('barrier', [0 1 2]);
            m.addGate('h', 0); m.addGate('h', 1); m.addGate('h', 2);
            m.addGate('cx', [0 1]);
            m.addGate('cx', [0 2]);
            m.addGate('ccx', [1 2 0]);
            m.addGate('measure', 0);
        end

        function m = buildChsh()
            % CHSH Bell-inequality test on the Bell pair |Φ+⟩.
            % Alice measures q[0] in the Z basis; Bob rotates q[1] by
            % -π/4 then measures, giving one of the four CHSH terms.
            % Cycling Alice/Bob's rotations across four runs yields the
            % full ⟨S⟩ ≈ 2√2 violation.
            m = CircuitModel(2);
            m.addGate('h', 0);
            m.addGate('cx', [0 1]);
            m.addGate('barrier', [0 1]);
            m.addGate('ry', 1, -pi/4);
            m.addGate('measure', 0);
            m.addGate('measure', 1);
        end

        % ── Helpers ──────────────────────────────────────────────────────
        function v = clampN(n, lo, hi)
            if isempty(n) || ~isnumeric(n) || ~isfinite(n)
                error('TemplateRegistry:BadParam', 'n must be a finite integer');
            end
            v = max(lo, min(hi, round(n)));
        end

        function s = padBits(str, len)
            s = char(string(str));
            s = regexprep(s, '[^01]', '');
            if isempty(s); s = repmat('0', 1, len); end
            if numel(s) < len
                s = [repmat('0', 1, len - numel(s)), s];
            elseif numel(s) > len
                s = s(end-len+1:end);
            end
        end
    end
end

function s = tpl(id, name, desc, qubits, parameterized)
    s = struct( ...
        'id',           id, ...
        'name',         name, ...
        'description',  desc, ...
        'qubits',       qubits, ...
        'parameterized', parameterized);
end
