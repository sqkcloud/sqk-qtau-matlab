classdef StubFastAPIClient < handle
    % StubFastAPIClient  Minimal test double for FastAPIClient.
    %
    %   Records which methods were called and returns configurable canned
    %   responses.  Used by service-layer unit tests to verify that services
    %   delegate to the expected FastAPIClient methods without making real
    %   HTTP calls.

    properties
        BaseUrl   string = "http://stub:0000"
        Timeout   double = 5
        ProjectId string = ""

        % ── Call recording ───────────────────────────────────────────────
        LastMethod    string = ""
        LastEndpoint  string = ""
        LastPayload          = []
        LastToken     string = ""
        CallCount     double = 0

        % ── Configurable response ────────────────────────────────────────
        Response = struct('status', 'ok')
    end

    methods
        function obj = StubFastAPIClient()
            % No-arg constructor for easy instantiation in tests.
        end

        % ── Named convenience methods (matching FastAPIClient API) ───────

        function data = login(obj, username, ~)
            obj.record('login', '/api/auth/login', struct('username', char(username)), '');
            data = obj.Response;
        end

        function data = logout(obj, token)
            obj.record('logout', '/api/auth/logout', struct(), token);
            data = obj.Response;
        end

        function data = getMe(obj, token)
            obj.record('getMe', '/api/auth/me', [], token);
            data = obj.Response;
        end

        function data = listProjects(obj, token, ~, ~)
            obj.record('listProjects', '/api/projects', [], token);
            data = obj.Response;
        end

        % ── Generic HTTP primitives ──────────────────────────────────────

        function data = get(obj, endpoint)
            obj.record('get', endpoint, [], '');
            data = obj.Response;
        end

        function data = getAuth(obj, endpoint, token)
            obj.record('getAuth', endpoint, [], token);
            data = obj.Response;
        end

        function data = postAuthJson(obj, endpoint, payload, token, varargin)
            % varargin absorbs optional timeoutSec (QmcService passes it).
            obj.record('postAuthJson', endpoint, payload, token);
            data = obj.Response;
        end

        function localPath = downloadFileAuth(obj, endpoint, token, localPath)
            obj.record('downloadFileAuth', endpoint, struct('localPath', char(localPath)), token);
            fid = fopen(localPath, 'w');
            if fid >= 0
                fwrite(fid, uint8('{}'));
                fclose(fid);
            end
        end

        function data = putAuthJson(obj, endpoint, payload, token)
            obj.record('putAuthJson', endpoint, payload, token);
            data = obj.Response;
        end

        function data = patchAuthJson(obj, endpoint, payload, token)
            obj.record('patchAuthJson', endpoint, payload, token);
            data = obj.Response;
        end

        function data = patchAuthRaw(obj, endpoint, jsonBody, token)
            obj.record('patchAuthRaw', endpoint, jsonBody, token);
            data = obj.Response;
        end

        function data = deleteAuth(obj, endpoint, token)
            obj.record('deleteAuth', endpoint, [], token);
            data = obj.Response;
        end

        function data = uploadFileAuth(obj, endpoint, filePath, extraFields, token)
            obj.record('uploadFileAuth', endpoint, struct('file', char(filePath), 'fields', extraFields), token);
            data = obj.Response;
        end
    end

    methods (Access = private)
        function record(obj, method, endpoint, payload, token)
            obj.LastMethod   = string(method);
            obj.LastEndpoint = string(endpoint);
            obj.LastPayload  = payload;
            obj.LastToken    = string(token);
            obj.CallCount    = obj.CallCount + 1;
        end
    end
end
