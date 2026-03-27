classdef FastAPIClient < handle
    % FastAPIClient  Low-level HTTP gateway for the QTAU REST backend.
    %
    %   Exposes typed primitives (get, getAuth, postAuthJson, putAuthJson,
    %   patchAuthJson, deleteAuth, uploadFileAuth) plus named convenience
    %   methods for auth and admin endpoints already in use.
    %
    %   All HTTP errors propagate as MException so callers can display them;
    %   the service layer (CircuitService, JobService, …) wraps these in
    %   domain-level errors with human-readable messages.
    %
    %   File upload uses matlab.net.http.* (R2016b+) to build a proper
    %   multipart/form-data body.  A system-curl fallback is attempted when
    %   the import fails (e.g. older MATLAB or restricted deployments).

    properties
        BaseUrl string
        Timeout double = 30
    end

    % ── Constructor / config ──────────────────────────────────────────────────
    methods
        function obj = FastAPIClient(baseUrl)
            obj.BaseUrl = string(baseUrl);
            Logger.info('FastAPIClient', 'Initialized — BaseUrl: %s', char(obj.BaseUrl));
        end

        function setBaseUrl(obj, baseUrl)
            old = char(obj.BaseUrl);
            obj.BaseUrl = string(baseUrl);
            Logger.info('FastAPIClient', 'BaseUrl changed: %s → %s', old, char(obj.BaseUrl));
        end
    end

    % ── Named convenience methods (existing + new) ────────────────────────────
    methods
        function data = openApi(obj)
            Logger.debug('FastAPIClient', 'openApi → GET /api/openapi.json');
            data = obj.get('/api/openapi.json');
        end

        function data = login(obj, username, password)
            % POST application/x-www-form-urlencoded with fields username, password.
            % Path comes from resources/app.properties key login_path (default /api/auth/login).
            loginPath = AppConfig.get('login_path', '/api/auth/login');
            if isempty(strtrim(loginPath))
                loginPath = '/api/auth/login';
            end
            loginPath = char(strtrim(loginPath));
            if loginPath(1) ~= '/'
                loginPath = ['/' loginPath];
            end
            Logger.info('FastAPIClient', 'login → POST %s (user: %s)', loginPath, char(username));
            url = char(obj.BaseUrl + string(loginPath));
            try
                % webwrite does not support application/x-www-form-urlencoded
                % as MediaType; use matlab.net.http to build the request.
                data = FastAPIClient.loginViaHttpNet(url, char(username), char(password), obj.Timeout);
                Logger.info('FastAPIClient', 'login → response received for user: %s', char(username));
            catch ME
                Logger.error('FastAPIClient', 'login FAILED (user: %s): %s', char(username), ME.message);
                rethrow(ME);
            end
        end

        function data = getMe(obj, token)
            Logger.debug('FastAPIClient', 'getMe → GET /api/auth/me');
            data = obj.getAuth('/api/auth/me', token);
        end

        function data = logout(obj, token)
            Logger.info('FastAPIClient', 'logout → POST /api/auth/logout');
            data = obj.postAuthJson('/api/auth/logout', struct(), token);
        end

        function data = listProjects(obj, token, skip, limit)
            ep = sprintf('/api/admin/projects?skip=%d&limit=%d', round(skip), round(limit));
            Logger.debug('FastAPIClient', 'listProjects → GET %s', ep);
            data = obj.getAuth(ep, token);
        end
    end

    % ── Generic HTTP primitives (public) ─────────────────────────────────────
    methods
        % GET without auth
        function data = get(obj, endpoint)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('GET', url);
            opts = weboptions('Timeout', obj.Timeout, ...
                'HeaderFields', {'Accept', 'application/json'});
            try
                raw  = webread(url, opts);
                data = FastAPIClient.normalizeJsonResponse(raw);
                Logger.debug('FastAPIClient', 'GET %s → OK', endpoint);
            catch ME
                Logger.error('FastAPIClient', 'GET %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end
        end

        % GET with Bearer token
        function data = getAuth(obj, endpoint, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('GET', url);
            opts = weboptions('Timeout', obj.Timeout, ...
                'HeaderFields', FastAPIClient.authHeaders(token));
            try
                raw  = webread(url, opts);
                data = FastAPIClient.normalizeJsonResponse(raw);
                Logger.debug('FastAPIClient', 'GET %s → OK', endpoint);
            catch ME
                Logger.error('FastAPIClient', 'GET %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end
        end

        % POST JSON with Bearer token
        function data = postAuthJson(obj, endpoint, payload, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('POST', url);
            opts = weboptions('Timeout', obj.Timeout, ...
                'MediaType', 'application/json', 'ContentType', 'json', ...
                'HeaderFields', FastAPIClient.authHeaders(token));
            try
                raw  = webwrite(url, payload, opts);
                data = FastAPIClient.normalizeJsonResponse(raw);
                Logger.debug('FastAPIClient', 'POST %s → OK', endpoint);
            catch ME
                Logger.error('FastAPIClient', 'POST %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end
        end

        % PUT JSON with Bearer token
        function data = putAuthJson(obj, endpoint, payload, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('PUT', url);
            opts = weboptions('Timeout', obj.Timeout, ...
                'MediaType', 'application/json', 'ContentType', 'json', ...
                'RequestMethod', 'put', ...
                'HeaderFields', FastAPIClient.authHeaders(token));
            try
                raw  = webwrite(url, payload, opts);
                data = FastAPIClient.normalizeJsonResponse(raw);
                Logger.debug('FastAPIClient', 'PUT %s → OK', endpoint);
            catch ME
                Logger.error('FastAPIClient', 'PUT %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end
        end

        % PATCH JSON with Bearer token
        function data = patchAuthJson(obj, endpoint, payload, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('PATCH', url);
            opts = weboptions('Timeout', obj.Timeout, ...
                'MediaType', 'application/json', 'ContentType', 'json', ...
                'RequestMethod', 'patch', ...
                'HeaderFields', FastAPIClient.authHeaders(token));
            try
                raw  = webwrite(url, payload, opts);
                data = FastAPIClient.normalizeJsonResponse(raw);
                Logger.debug('FastAPIClient', 'PATCH %s → OK', endpoint);
            catch ME
                Logger.error('FastAPIClient', 'PATCH %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end
        end

        % DELETE with Bearer token — treats 204 No Content as success
        function data = deleteAuth(obj, endpoint, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('DELETE', url);
            opts = weboptions('Timeout', obj.Timeout, ...
                'RequestMethod', 'delete', ...
                'HeaderFields', FastAPIClient.authHeaders(token));
            try
                raw  = webread(url, opts);
                data = FastAPIClient.normalizeJsonResponse(raw);
                Logger.debug('FastAPIClient', 'DELETE %s → OK', endpoint);
            catch ME
                % 204 No Content → webread raises; treat as success
                if FastAPIClient.isNoContent(ME)
                    Logger.info('FastAPIClient', 'DELETE %s → 204 No Content (treated as success)', endpoint);
                    data = struct('status', 'deleted');
                else
                    Logger.error('FastAPIClient', 'DELETE %s FAILED: %s', endpoint, ME.message);
                    rethrow(ME);
                end
            end
        end

        % POST multipart/form-data file upload with Bearer token.
        % extraFields: struct of additional string/numeric form fields.
        function data = uploadFileAuth(obj, endpoint, filePath, extraFields, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.info('FastAPIClient', 'uploadFileAuth → POST %s (file: %s)', endpoint, filePath);
            try
                data = FastAPIClient.uploadViaHttpNet(url, filePath, extraFields, token, obj.Timeout);
                Logger.info('FastAPIClient', 'uploadFileAuth → POST %s OK (via matlab.net.http)', endpoint);
            catch ME
                Logger.warn('FastAPIClient', 'matlab.net.http upload failed (%s); attempting curl fallback', ME.message);
                try
                    data = FastAPIClient.uploadViaCurl(url, filePath, extraFields, token);
                    Logger.info('FastAPIClient', 'uploadFileAuth → POST %s OK (via curl fallback)', endpoint);
                catch ME2
                    Logger.error('FastAPIClient', 'uploadFileAuth → POST %s FAILED (both methods): %s', endpoint, ME.message);
                    rethrow(ME);
                end
            end
        end
    end

    % ── Private static helpers ────────────────────────────────────────────────
    methods (Static, Access = private)

        function hdrs = authHeaders(token)
            hdrs = {'Authorization', ['Bearer ' char(token)]; 'Accept', 'application/json'};
        end

        function tf = isNoContent(ME)
            tf = contains(ME.message, '204') || contains(ME.message, 'No Content') || ...
                 contains(ME.identifier, 'URLREAD');
        end

        function out = urlEncode(str)
            import java.net.URLEncoder
            out = char(URLEncoder.encode(str, 'UTF-8'));
        end

        function data = normalizeJsonResponse(raw)
            data = raw;
            try
                if isstring(raw)
                    raw = char(raw(1));  % take first element if array
                end
                if ischar(raw)
                    txt = strtrim(raw);
                    if ~isempty(txt) && (txt(1) == '{' || txt(1) == '[')
                        data = jsondecode(txt);
                    end
                end
            catch
            end
        end

        function data = loginViaHttpNet(url, username, password, timeout)
            % POST application/x-www-form-urlencoded via matlab.net.http.
            % webwrite only accepts JSON MediaTypes, so we build the request
            % manually here.
            import matlab.net.http.*
            import matlab.net.http.field.*
            import matlab.net.*

            body    = ['username=' FastAPIClient.urlEncode(username) ...
                       '&password=' FastAPIClient.urlEncode(password)];
            headers = [ContentTypeField('application/x-www-form-urlencoded'), ...
                       GenericField('Accept', 'application/json')];
            req     = RequestMessage(RequestMethod.POST, headers, body);
            opts    = HTTPOptions('ConnectTimeout', timeout);
            resp    = req.send(URI(url), opts);

            bodyData = resp.Body.Data;
            if isa(bodyData, 'uint8')
                bodyData = char(bodyData');
            end
            data = FastAPIClient.normalizeJsonResponse(bodyData);
        end

        function data = uploadViaHttpNet(url, filePath, extraFields, token, timeout)
            % matlab.net.http multipart upload (R2016b+)
            import matlab.net.http.*
            import matlab.net.http.io.*
            import matlab.net.*

            [~, fname, ext] = fileparts(filePath);
            fileName = [fname ext];

            fid = fopen(filePath, 'rb');
            if fid < 0
                error('FastAPIClient:fileNotFound', 'Cannot open file: %s', filePath);
            end
            bytes = fread(fid, '*uint8');
            fclose(fid);

            dispValue = sprintf('form-data; name="file"; filename="%s"', fileName);

            filePart = FormField('file', bytes, ...
                field.ContentTypeField('application/octet-stream'), ...
                field.GenericField('Content-Disposition', dispValue));

            parts = {filePart};
            if isstruct(extraFields)
                fnames = fieldnames(extraFields);
                for i = 1:numel(fnames)
                    val = extraFields.(fnames{i});
                    if isnumeric(val); val = num2str(val); end
                    parts{end+1} = FormField(fnames{i}, char(val)); %#ok
                end
            end

            provider = MultipartFormProvider(parts{:});
            hdrs     = [field.GenericField('Authorization', ['Bearer ' char(token)]), ...
                        field.GenericField('Accept', 'application/json')];
            req      = RequestMessage(RequestMethod.POST, hdrs, provider);
            opts     = HTTPOptions('ConnectTimeout', timeout);
            resp     = req.send(URI(url), opts);

            bodyData = resp.Body.Data;
            if isa(bodyData, 'uint8')
                bodyData = char(bodyData');
            end
            data = FastAPIClient.normalizeJsonResponse(bodyData);
        end

        function data = uploadViaCurl(url, filePath, extraFields, token)
            % System curl fallback for environments without matlab.net.http
            extra = '';
            if isstruct(extraFields)
                fns = fieldnames(extraFields);
                for i = 1:numel(fns)
                    val = char(string(extraFields.(fns{i})));
                    extra = [extra sprintf(' -F "%s=%s"', fns{i}, val)]; %#ok
                end
            end
            cmd = sprintf('curl -s -X POST -H "Authorization: Bearer %s" -H "Accept: application/json" -F "file=@%s"%s "%s"', ...
                char(token), filePath, extra, url);
            Logger.debug('FastAPIClient', 'curl command: %s', cmd);
            [status, out] = system(cmd);
            if status ~= 0
                error('FastAPIClient:curlFailed', 'curl upload failed (exit %d): %s', status, out);
            end
            data = FastAPIClient.normalizeJsonResponse(out);
        end
    end
end
