classdef MitigationService < handle
    % MitigationService  HTTP client for /api/mitigation/* endpoints.
    %
    %   Thin wrapper over FastAPIClient. Surfaces the cost-preview
    %   endpoint so the UI can render "Mitigation: <Level> · ~Nx shots
    %   · est. Hms" below every submit dialog before the operator hits
    %   Run.
    %
    %   Endpoints mirror the design in
    %   docs/superpowers/specs/2026-05-03-mitigation-service.md.

    properties (Access = private)
        Client  % FastAPIClient instance
    end

    methods
        function obj = MitigationService(client)
            obj.Client = client;
            Logger.info('MitigationService', 'Initialized');
        end

        function result = listLevels(obj, token)
            % GET /api/mitigation/levels
            %
            % Returns the cell array of level descriptors the UI
            % uses to populate its mitigation-level dropdown:
            %   {struct('id',0,'name','raw','label','Raw',...), ...}
            result = obj.Client.getAuth('/api/mitigation/levels', token);
        end

        function result = estimate(obj, body, token)
            % POST /api/mitigation/estimate
            %
            % body fields (see EstimateRequest in
            % src/qdash/api/routers/mitigation.py):
            %   .mitigation_level         : int (-1..3, optional)
            %   .mitigation_options       : struct (Custom override)
            %   .primitive                : 'sampler' | 'estimator'
            %   .backend_name             : char (e.g. 'ibm_marrakesh')
            %   .base_shots               : int
            %   .circuit_qubits           : int
            %   .cutting_overhead_qubits  : int (subcircuit width when
            %                                    this is a cutting submit)
            %
            % Returns:
            %   struct with .plan (snapshot), .cost (CostEstimate),
            %   .summary (one-line UI string).
            %
            %   The summary string is what the UI renders directly —
            %   format: "Mitigation: Standard · ~1.05× shots · est. 2s
            %   · ~0.03 IQP units".
            result = obj.Client.postAuthJson( ...
                '/api/mitigation/estimate', body, token);
        end
    end
end
