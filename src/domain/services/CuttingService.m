classdef CuttingService < handle
    % CuttingService  HTTP client for /api/cutting/* endpoints.
    %
    %   Thin wrapper over FastAPIClient — every method returns the decoded
    %   JSON struct so the ViewModel layer can pick the fields it needs.
    %
    %   Endpoints mirror the design in
    %   docs/superpowers/specs/2026-04-24-circuit-cutting-design.md.

    properties (Access = private)
        Client  % FastAPIClient instance
    end

    methods
        function obj = CuttingService(client)
            obj.Client = client;
            Logger.info('CuttingService', 'Initialized');
        end

        % ── Analyze (preflight cut detection) ────────────────────────────
        function result = analyzeCuts(obj, circuitId, targetK, token)
            % POST /api/cutting/analyze
            body = struct('circuit_id', char(circuitId));
            if ~isempty(targetK) && isnumeric(targetK)
                body.target_k = int32(targetK);
            end
            result = obj.Client.postAuthJson('/api/cutting/analyze', body, token);
        end

        % ── Presets ──────────────────────────────────────────────────────
        function result = listPresets(obj, token)
            % GET /api/cutting/presets
            result = obj.Client.getAuth('/api/cutting/presets', token);
        end

        % ── Batch create ─────────────────────────────────────────────────
        function result = createBatch(obj, circuitId, body, token)
            % POST /api/circuits/{circuit_id}/cutting/batches → 202 {batch_id}
            endpoint = sprintf('/api/circuits/%s/cutting/batches', ...
                FastAPIClient.encodePathSegment(char(circuitId)));
            result = obj.Client.postAuthJson(endpoint, body, token);
        end

        % ── Poll ─────────────────────────────────────────────────────────
        function result = pollBatch(obj, batchId, token)
            % GET /api/cutting/batches/{batch_id}
            endpoint = sprintf('/api/cutting/batches/%s', ...
                FastAPIClient.encodePathSegment(char(batchId)));
            result = obj.Client.getAuth(endpoint, token);
        end

        % ── Result ───────────────────────────────────────────────────────
        function result = getBatchResult(obj, batchId, token)
            % GET /api/cutting/batches/{batch_id}/result
            endpoint = sprintf('/api/cutting/batches/%s/result', ...
                FastAPIClient.encodePathSegment(char(batchId)));
            result = obj.Client.getAuth(endpoint, token);
        end

        % ── Sibling pair lookup (Phase 4) ────────────────────────────────
        function result = getSiblingPair(obj, groupId, token)
            % GET /api/cutting/sibling/{sibling_group_id}
            %
            % Returns {sibling_group_id, primary_batch_id, raw_batch_id,
            % primary_status, raw_status}. Either batch field may be
            % empty string when only one sibling exists in the group
            % (e.g. raw sibling persistence failed). Used by the
            % Results screen Mitigated/Raw toggle to resolve the
            % partner batch when the loaded result carries a non-empty
            % sibling_group_id.
            endpoint = sprintf('/api/cutting/sibling/%s', ...
                FastAPIClient.encodePathSegment(char(groupId)));
            result = obj.Client.getAuth(endpoint, token);
        end

        % ── Cancel ───────────────────────────────────────────────────────
        function result = cancelBatch(obj, batchId, token)
            % DELETE /api/cutting/batches/{batch_id}
            endpoint = sprintf('/api/cutting/batches/%s', ...
                FastAPIClient.encodePathSegment(char(batchId)));
            result = obj.Client.deleteAuth(endpoint, token);
        end

        % ── List (History) ───────────────────────────────────────────────
        function result = listBatches(obj, token)
            % GET /api/cutting/batches
            result = obj.Client.getAuth('/api/cutting/batches', token);
        end
    end
end
