classdef QaeService < handle
    % QaeService  Domain service for Quantum Amplitude Estimation /
    %             Quantum Monte-Carlo analysis.
    %
    %   Wraps the FastAPI endpoints added for the "Quantum Monte Carlo
    %   Simulation (Quantum Amplitude Estimation)" section on the
    %   Analysis screen:
    %
    %     POST /api/circuits/{id}/qae/analyze
    %     GET  /api/circuits/{id}/qae/result
    %
    %   Supports both 'statevector' (local Qiskit Aer simulation, no IBM
    %   credentials) and 'runtime' (IBM Qiskit Runtime via QiskitRuntimeService
    %   on the server). If 'runtime' returns HTTP 503 because credentials
    %   are not configured, the caller may retry in 'statevector' mode.

    properties (Access = private)
        Client FastAPIClient
    end

    methods
        function obj = QaeService(client)
            obj.Client = client;
            Logger.info('QaeService', 'Initialized');
        end

        % Run a QAE / QMC analysis on a stored circuit.
        %   mode          : 'statevector' | 'runtime'
        %   shots         : Monte-Carlo-equivalent shot count
        %   epsilon       : target estimation error (0.001 – 0.5)
        %   confidence    : confidence level (0.80 – 0.999)
        %   numEvalQubits : path-register width (informational / plot axis)
        %   riskMetric    : 'option_price' | 'var_95' | 'var_99' | 'cvar_95'
        %   backend       : IBM backend name (runtime mode only; [] otherwise)
        %   opts (struct, optional) may carry advanced knobs:
        %       mitigation  — 'none' | 'zne' | 'pec'
        %       market      — struct(spot,strike,volatility,risk_free_rate,
        %                          time_to_maturity,option_type,notional)
        %       correlation — cell-of-row-vectors forming an NxN matrix
        %       compute_greeks — logical
        %   token         : bearer token
        function data = analyze(obj, circuitId, mode, shots, epsilon, ...
                                confidence, numEvalQubits, riskMetric, ...
                                backend, opts, token)
            if nargin < 11
                % Backward-compat 10-arg form (no opts): shift args.
                token = opts;
                opts = struct();
            end
            endpoint = sprintf('/api/circuits/%s/qae/analyze', char(circuitId));
            payload = struct( ...
                'execution_mode',   char(mode), ...
                'shots',            shots, ...
                'epsilon',          epsilon, ...
                'confidence_level', confidence, ...
                'num_eval_qubits',  numEvalQubits, ...
                'risk_metric',      char(riskMetric));
            if ~isempty(backend) && strlength(string(backend)) > 0
                payload.backend = char(backend);
            end
            if isstruct(opts)
                if isfield(opts, 'mitigation');      payload.mitigation     = char(opts.mitigation); end
                if isfield(opts, 'market')   && ~isempty(opts.market);   payload.market   = opts.market;   end
                if isfield(opts, 'correlation') && ~isempty(opts.correlation)
                    payload.correlation = opts.correlation;
                end
                if isfield(opts, 'compute_greeks'); payload.compute_greeks = logical(opts.compute_greeks); end
            end
            if isfield(payload, 'mitigation'); mitLog = payload.mitigation; else; mitLog = 'none'; end
            Logger.info('QaeService', ...
                'analyze → POST %s (mode=%s shots=%d eps=%.4f mitigation=%s)', ...
                endpoint, char(mode), shots, epsilon, mitLog);
            try
                data = obj.Client.postAuthJson(endpoint, payload, token);
                Logger.info('QaeService', 'analyze → response received');
            catch ME
                Logger.error('QaeService', 'analyze FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Fetch the most recent cached QAE result for a circuit.
        function data = getLast(obj, circuitId, token)
            endpoint = sprintf('/api/circuits/%s/qae/result', char(circuitId));
            Logger.info('QaeService', 'getLast → GET %s', endpoint);
            try
                data = obj.Client.getAuth(endpoint, token);
            catch ME
                Logger.debug('QaeService', 'getLast: %s', ME.message);
                rethrow(ME);
            end
        end
    end
end
