classdef QaeService < handle
    % QaeService  Domain service for Quantum Amplitude Estimation /
    %             Quantum Monte-Carlo analysis.
    %
    %   Wraps the FastAPI endpoints for the "Quantum Monte Carlo
    %   Simulation" section on the Analysis screen:
    %
    %     POST   /api/circuits/{id}/qae/analyze      (queues async job)
    %     GET    /api/qae/jobs/{job_id}              (polls state)
    %     DELETE /api/qae/jobs/{job_id}              (cancels)
    %     GET    /api/circuits/{id}/qae/result       (last cached result)
    %     GET    /api/circuits/{id}/qae/ibm-log      (IBM execution log)
    %
    %   The analyze endpoint is async: submitAnalyze returns immediately
    %   with {job_id, status:"queued"}, then the ViewModel polls
    %   getAnalyzeJob every few seconds until status becomes
    %   completed/failed/cancelled. IBM Runtime QPU queue times (minutes
    %   to hours) would otherwise blow past any HTTP timeout.

    properties (Access = private)
        Client  % FastAPIClient instance (relaxed from typed property so tests can inject a StubFastAPIClient)
    end

    methods
        function obj = QaeService(client)
            obj.Client = client;
            Logger.info('QaeService', 'Initialized');
        end

        % Queue a QAE / QMC analysis as an async job. Returns an envelope
        % {job_id, status:"queued", circuit_id, execution_mode, backend, created_at}
        % that the caller polls via getAnalyzeJob.
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
        function envelope = submitAnalyze(obj, circuitId, mode, shots, epsilon, ...
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
                'submitAnalyze → POST %s (mode=%s shots=%d eps=%.4f mitigation=%s)', ...
                endpoint, char(mode), shots, epsilon, mitLog);
            try
                % The server returns HTTP 202 and only needs to persist
                % the doc + hand off to the worker, so a short timeout is
                % plenty here (long waits live inside the poll loop).
                envelope = obj.Client.postAuthJson(endpoint, payload, token, 30);
                Logger.info('QaeService', 'submitAnalyze → job %s queued', ...
                    char(JsonHelper.pick(envelope, {'job_id'}, '?')));
            catch ME
                Logger.error('QaeService', 'submitAnalyze FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Poll the state of a queued/running/terminal QAE job.
        % Returns the full state envelope; when status='completed' the
        % envelope's .result field contains the full QaeResult payload
        % (same shape as the legacy synchronous response).
        function state = getAnalyzeJob(obj, jobId, token)
            endpoint = sprintf('/api/qae/jobs/%s', char(jobId));
            try
                state = obj.Client.getAuth(endpoint, token);
            catch ME
                Logger.debug('QaeService', 'getAnalyzeJob(%s): %s', char(jobId), ME.message);
                rethrow(ME);
            end
        end

        % Mark a queued/running QAE job as cancelled. Already-completed
        % jobs are returned unchanged.
        function state = cancelAnalyzeJob(obj, jobId, token)
            endpoint = sprintf('/api/qae/jobs/%s', char(jobId));
            Logger.info('QaeService', 'cancelAnalyzeJob → DELETE %s', endpoint);
            try
                state = obj.Client.deleteAuth(endpoint, token);
            catch ME
                Logger.warn('QaeService', 'cancelAnalyzeJob(%s): %s', char(jobId), ME.message);
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

        % Download the IBM Runtime execution log for the circuit's cached
        % QAE result (requires the most recent analyze to have run in
        % 'runtime' mode — the server reads runtime_job_id from the
        % persisted qae document).
        %   fmt       : 'json' | 'jsonl'
        %   localPath : destination file path (caller typically passes a
        %               tempname; caller then uiputfile/copyfile to user)
        function localPath = downloadIbmLog(obj, circuitId, token, fmt, localPath)
            if nargin < 4 || isempty(fmt); fmt = 'json'; end
            endpoint = sprintf('/api/circuits/%s/qae/ibm-log?fmt=%s', ...
                char(circuitId), char(fmt));
            Logger.info('QaeService', 'downloadIbmLog → GET %s', endpoint);
            try
                localPath = obj.Client.downloadFileAuth(endpoint, token, localPath);
            catch ME
                Logger.error('QaeService', 'downloadIbmLog FAILED: %s', ME.message);
                rethrow(ME);
            end
        end
    end
end
