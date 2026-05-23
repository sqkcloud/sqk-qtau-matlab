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
    %   multipart/form-data body.

    properties
        BaseUrl   string
        Timeout   double = 30
        ProjectId string = ""
    end

    % ── Constructor / config ──────────────────────────────────────────────────
    methods
        function obj = FastAPIClient(baseUrl)
            url = FastAPIClient.normalizeBaseUrl(baseUrl);
            FastAPIClient.assertSafeBaseUrl(url);
            obj.BaseUrl = url;
            Logger.info('FastAPIClient', 'Initialized — BaseUrl: %s', char(obj.BaseUrl));
        end

        function setBaseUrl(obj, baseUrl)
            url = FastAPIClient.normalizeBaseUrl(baseUrl);
            FastAPIClient.assertSafeBaseUrl(url);
            old = char(obj.BaseUrl);
            obj.BaseUrl = url;
            Logger.info('FastAPIClient', 'BaseUrl changed: %s → %s', old, char(obj.BaseUrl));
        end
    end

    % ── Named convenience methods (existing + new) ────────────────────────────
    methods
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
            maskedUser = Logger.maskUsername(username);
            Logger.info('FastAPIClient', 'login → POST %s (user: %s)', loginPath, maskedUser);
            url = char(obj.BaseUrl + string(loginPath));
            try
                % webwrite does not support application/x-www-form-urlencoded
                % as MediaType; use matlab.net.http to build the request.
                data = FastAPIClient.loginViaHttpNet(url, char(username), char(password), obj.Timeout);
                Logger.info('FastAPIClient', 'login → response received for user: %s', maskedUser);
            catch ME
                Logger.error('FastAPIClient', 'login FAILED (user: %s): %s', maskedUser, ME.message);
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

        function data = listProjects(obj, token, ~, ~)
            ep = '/api/projects';
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
                % HTTP 404 on a GET is the canonical "does this resource
                % exist?" probe (e.g. GET .../qae/result → 404 means
                % "no cached QMC result yet"). Logging at ERROR floods
                % the event log with red lines for what callers already
                % handle as routine control flow at DEBUG. Demote 404
                % to DEBUG; everything else (5xx, 4xx other than 404,
                % network/timeout failures) stays at ERROR.
                if contains(ME.identifier, 'HTTP404')
                    Logger.debug('FastAPIClient', 'GET %s → 404 Not Found', endpoint);
                else
                    Logger.error('FastAPIClient', 'GET %s FAILED: %s', endpoint, ME.message);
                end
                rethrow(ME);
            end
        end

        % GET with Bearer token
        function data = getAuth(obj, endpoint, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('GET', url);
            opts = weboptions('Timeout', obj.Timeout, ...
                'HeaderFields', FastAPIClient.authHeaders(token, obj.ProjectId));
            try
                raw  = webread(url, opts);
                data = FastAPIClient.normalizeJsonResponse(raw);
                Logger.debug('FastAPIClient', 'GET %s → OK', endpoint);
            catch ME
                % See the matching note in get() above — 404 on GET is
                % a routine "does this resource exist?" signal (e.g.
                % the QMC cache probe at GET .../qae/result). Demote
                % to DEBUG so the event log isn't noisy with red ERROR
                % lines for what's actually expected control flow.
                if contains(ME.identifier, 'HTTP404')
                    Logger.debug('FastAPIClient', 'GET %s → 404 Not Found', endpoint);
                else
                    Logger.error('FastAPIClient', 'GET %s FAILED: %s', endpoint, ME.message);
                end
                rethrow(ME);
            end
        end

        % GET with Bearer token → save response body to a local file.
        % Used for binary downloads (PDF, HTML, JSON report files) where
        % the server replies with a FileResponse stream.
        function localPath = downloadFileAuth(obj, endpoint, token, localPath)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('GET(download)', url);
            opts = weboptions('Timeout', max(obj.Timeout, 120), ...
                'ContentType', 'raw', ...
                'HeaderFields', FastAPIClient.authHeaders(token, obj.ProjectId));
            try
                websave(char(localPath), url, opts);
                Logger.debug('FastAPIClient', 'DOWNLOAD %s → %s', endpoint, char(localPath));
            catch ME
                Logger.error('FastAPIClient', 'DOWNLOAD %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end
        end

        % POST JSON with Bearer token. Optional timeoutSec overrides
        % the default obj.Timeout for long-running endpoints (e.g. IBM
        % Runtime QMC where the server waits on QPU execution).
        %
        % Routes through matlab.net.http (instead of webwrite) so the
        % FastAPI {"detail": "..."} body is captured on non-2xx responses
        % — webwrite drops the body before throwing, so callers only ever
        % saw "Unprocessable Entity" with no actionable reason. The thrown
        % MException keeps the canonical identifier shape
        % MATLAB:webservices:HTTP<code>StatusCodeError so existing
        % showError/identifier handling stays compatible.
        function data = postAuthJson(obj, endpoint, payload, token, timeoutSec)
            if nargin < 5 || isempty(timeoutSec); timeoutSec = obj.Timeout; end
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('POST', url);

            import matlab.net.http.*
            import matlab.net.http.field.*
            import matlab.net.*

            headers = [ContentTypeField(MediaType('application/json')), ...
                       GenericField('Accept', 'application/json'), ...
                       GenericField('Authorization', ['Bearer ' char(token)])];
            if strlength(string(obj.ProjectId)) > 0
                headers = [headers, GenericField('X-Project-Id', char(obj.ProjectId))];
            end
            msgBody = MessageBody();
            % unicode2native(..., 'UTF-8') NOT uint8(...). uint8 on a MATLAB
            % string casts each char to char & 0xFF, so multibyte
            % characters (em-dash U+2014, smart quotes, anything outside
            % ASCII) get truncated to a single garbage byte. The server's
            % UTF-8 JSON parser then rejects the body with HTTP 400
            % "There was an error parsing the body" — visible in the API
            % logs as a � replacement char where the original
            % character should be. unicode2native emits the correct
            % multi-byte UTF-8 sequence so any valid Unicode string in a
            % POST payload (cut_plan.feasibility_reason, report titles,
            % etc.) round-trips cleanly.
            msgBody.Payload = unicode2native(jsonencode(payload), 'UTF-8');
            req  = RequestMessage(RequestMethod.POST, headers, msgBody);
            opts = HTTPOptions('ConnectTimeout', double(timeoutSec));

            try
                resp = req.send(URI(url), opts);
            catch ME
                Logger.error('FastAPIClient', 'POST %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end

            httpStatus = double(resp.StatusCode);
            bodyData = resp.Body.Data;
            if isa(bodyData, 'uint8'); bodyData = char(bodyData'); end

            if httpStatus >= 400
                Logger.error('FastAPIClient', 'POST %s FAILED: HTTP %d', endpoint, httpStatus);
                FastAPIClient.throwHttpError(httpStatus, resp.StatusCode, url, bodyData);
            end

            data = FastAPIClient.normalizeJsonResponse(bodyData);
            Logger.debug('FastAPIClient', 'POST %s → OK', endpoint);
        end

        % PUT JSON with Bearer token
        function data = putAuthJson(obj, endpoint, payload, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('PUT', url);
            opts = weboptions('Timeout', obj.Timeout, ...
                'MediaType', 'application/json', 'ContentType', 'json', ...
                'RequestMethod', 'put', ...
                'HeaderFields', FastAPIClient.authHeaders(token, obj.ProjectId));
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
                'HeaderFields', FastAPIClient.authHeaders(token, obj.ProjectId));
            try
                raw  = webwrite(url, payload, opts);
                data = FastAPIClient.normalizeJsonResponse(raw);
                Logger.debug('FastAPIClient', 'PATCH %s → OK', endpoint);
            catch ME
                Logger.error('FastAPIClient', 'PATCH %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end
        end

        % PATCH with a pre-encoded JSON string body and Bearer token.
        % Use this when the payload contains arrays that jsonencode would
        % flatten (e.g. single-element cell arrays).
        function data = patchAuthRaw(obj, endpoint, jsonBody, token)
            url = char(obj.BaseUrl + string(endpoint));
            Logger.http('PATCH', url);
            import matlab.net.http.*
            import matlab.net.http.field.*
            import matlab.net.http.io.*
            import matlab.net.*

            hdrs = [GenericField('Authorization', ['Bearer ' char(token)]), ...
                    GenericField('Accept', 'application/json'), ...
                    ContentTypeField(MediaType('application/json'))];
            if strlength(string(obj.ProjectId)) > 0
                hdrs = [hdrs, GenericField('X-Project-Id', char(obj.ProjectId))];
            end
            provider = StringProvider(jsonBody, 'UTF-8');
            req  = RequestMessage(RequestMethod('PATCH'), hdrs, provider);
            opts = HTTPOptions('ConnectTimeout', obj.Timeout);
            try
                resp = req.send(URI(url), opts);
                httpStatus = double(resp.StatusCode);
                bodyData = resp.Body.Data;
                if isa(bodyData, 'uint8')
                    bodyData = char(bodyData');
                end
                if httpStatus >= 400
                    errMsg = FastAPIClient.extractErrorMessage(bodyData, httpStatus);
                    Logger.error('FastAPIClient', 'PATCH %s FAILED (HTTP %d): %s', endpoint, httpStatus, errMsg);
                    error('FastAPIClient:httpError', 'HTTP %d: %s', httpStatus, errMsg);
                end
                data = FastAPIClient.normalizeJsonResponse(bodyData);
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
                'HeaderFields', FastAPIClient.authHeaders(token, obj.ProjectId));
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
                data = FastAPIClient.uploadViaHttpNet(url, filePath, extraFields, token, obj.Timeout, obj.ProjectId);
                Logger.info('FastAPIClient', 'uploadFileAuth → POST %s OK', endpoint);
            catch ME
                Logger.error('FastAPIClient', 'uploadFileAuth → POST %s FAILED: %s', endpoint, ME.message);
                rethrow(ME);
            end
        end
    end

    % ── Public static helpers ─────────────────────────────────────────────────
    methods (Static)
        function url = normalizeBaseUrl(raw)
            % normalizeBaseUrl  Strip surrounding whitespace AND any
            %   trailing slashes from a base URL. End users pasting a
            %   URL from a browser commonly include a trailing '/';
            %   concatenating with a leading-slash endpoint like
            %   '/api/auth/login' would produce '//api/auth/login',
            %   which FastAPI's router does not match and returns
            %   HTTP 404. Normalising at the FastAPIClient boundary
            %   means every endpoint composition stays canonical no
            %   matter how the operator entered the URL.
            url = strtrim(string(raw));
            if strlength(url) == 0; return; end
            % Strip one OR MORE trailing forward slashes.
            url = string(regexprep(char(url), '/+$', ''));
        end

        function assertSafeBaseUrl(url)
            % assertSafeBaseUrl  Reject base URLs that would send credentials
            %   over an insecure transport.  HTTPS is always allowed; plain
            %   HTTP is permitted only for the loopback interface (development
            %   convenience).  All other plain-HTTP URLs throw.
            s = char(string(url));
            if isempty(s)
                error('FastAPIClient:invalidBaseUrl', 'Base URL is empty.');
            end
            if startsWith(s, 'https://', 'IgnoreCase', true)
                return;
            end
            if startsWith(s, 'http://localhost', 'IgnoreCase', true) || ...
               startsWith(s, 'http://127.0.0.1', 'IgnoreCase', true) || ...
               startsWith(s, 'http://[::1]',     'IgnoreCase', true)
                Logger.warn('FastAPIClient', ...
                    'Plain HTTP allowed for loopback only: %s', s);
                return;
            end
            allowInsecure = strcmpi(strtrim(AppConfig.get('allow_insecure_base_url', 'false')), 'true');
            if allowInsecure && startsWith(s, 'http://', 'IgnoreCase', true)
                Logger.warn('FastAPIClient', ...
                    'Plain HTTP base URL allowed via allow_insecure_base_url=true: %s (credentials sent unencrypted)', s);
                return;
            end
            error('FastAPIClient:insecureBaseUrl', ...
                ['Refusing non-HTTPS base URL: %s. ' ...
                 'Use https:// (or http://localhost for local development). ' ...
                 'To permit plain HTTP to a remote host, set allow_insecure_base_url=true in resources/app.properties.'], s);
        end

        function s = encodePathSegment(seg)
            % encodePathSegment  Percent-encode a single URL path segment.
            %   Encodes characters outside the unreserved set (RFC 3986) so that
            %   user-supplied IDs cannot alter the URL path structure.
            seg = char(string(seg));
            out = '';
            for i = 1:numel(seg)
                c = seg(i);
                if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || ...
                   (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~'
                    out = [out c]; %#ok
                else
                    out = [out sprintf('%%%02X', uint8(c))]; %#ok
                end
            end
            s = out;
        end
    end

    % ── Private static helpers ────────────────────────────────────────────────
    methods (Static, Access = private)

        function hdrs = authHeaders(token, projectId)
            hdrs = {'Authorization', ['Bearer ' char(token)]; 'Accept', 'application/json'};
            if nargin >= 2 && strlength(string(projectId)) > 0
                hdrs = [hdrs; {'X-Project-Id', char(projectId)}];
            end
        end

        function tf = isNoContent(ME)
            % Detect HTTP 204 No Content responses.  MATLAB webread throws on
            % empty responses, so we inspect both the error identifier and
            % message.  We use regexp to match the status code as a whole
            % number (avoiding false positives like port 2040).
            tf = ~isempty(regexp(ME.message, '\b204\b', 'once')) || ...
                 contains(ME.message, 'No Content', 'IgnoreCase', true) || ...
                 contains(ME.identifier, 'URLREAD');
        end

        function throwHttpError(httpStatus, statusCode, url, bodyData)
            % Throw an MException whose identifier matches the shape MATLAB's
            % webread/webwrite uses on non-2xx responses, but whose message
            % includes the FastAPI `detail` body when present so the UI's
            % showError dialog gets actionable text instead of just the bare
            % status phrase ("Unprocessable Entity", "Internal Server Error").
            phrase = FastAPIClient.humanStatusPhrase(statusCode);
            base = sprintf(['The server returned the status %d with message ' ...
                            '"%s" in response to the request to URL %s.'], ...
                            httpStatus, phrase, url);
            detail = FastAPIClient.extractErrorMessage(bodyData, httpStatus);
            fallback = sprintf('Request failed with status %d', httpStatus);
            if isempty(detail) || strcmp(detail, fallback)
                msg = base;
            else
                msg = sprintf('%s\n\nDetails:\n%s', base, detail);
            end
            id = sprintf('MATLAB:webservices:HTTP%dStatusCodeError', httpStatus);
            err = MException(id, '%s', msg);
            throw(err);
        end

        function phrase = humanStatusPhrase(statusCode)
            % Convert a matlab.net.http.StatusCode enum (or numeric/string
            % fallback) into the human reason phrase MATLAB's webread shows
            % — e.g. StatusCode.UnprocessableEntity → "Unprocessable Entity".
            % NOTE: char(enum) returns the enum NAME ("Unauthorized"), while
            % string(enum) coerces to its underlying numeric value ("401")
            % on R2025b. We want the name so the regex below produces
            % "Unauthorized" → "Unauthorized" / "InternalServerError" →
            % "Internal Server Error" matching webread's display style.
            try
                name = char(statusCode);
            catch
                name = '';
            end
            if isempty(name)
                phrase = 'Error';
                return;
            end
            % Insert a space between lowercase→uppercase boundaries so
            % "InternalServerError" → "Internal Server Error". Two-letter
            % acronyms like "OK" are unaffected by the regex.
            phrase = regexprep(name, '([a-z])([A-Z])', '$1 $2');
        end

        function msg = extractErrorMessage(bodyData, httpStatus)
            % Try to extract a human-readable message from a JSON error body.
            % bodyData may be a char array (raw JSON), a struct (auto-parsed
            % by matlab.net.http), or uint8.
            msg = sprintf('Request failed with status %d', httpStatus);
            try
                if isstruct(bodyData)
                    parsed = bodyData;
                elseif ischar(bodyData) && ~isempty(strtrim(bodyData))
                    parsed = jsondecode(strtrim(bodyData));
                elseif isstring(bodyData)
                    parsed = jsondecode(char(bodyData));
                else
                    return;
                end
                if isstruct(parsed) && isfield(parsed, 'detail')
                    detail = parsed.detail;
                    if ischar(detail)
                        msg = detail;
                    elseif isstring(detail)
                        msg = char(detail);
                    elseif iscell(detail) && ~isempty(detail)
                        msg = char(jsonencode(detail));
                    end
                end
            catch ME
                Logger.debug('FastAPIClient', 'error detail normalization: %s', ME.message);
            end
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
            catch ME
                Logger.debug('FastAPIClient', 'JSON parse: %s', ME.message);
            end
        end

        function data = loginViaHttpNet(url, username, password, timeout)
            % POST application/x-www-form-urlencoded via matlab.net.http.
            % Uses FormProvider for proper form encoding and response decoding.
            import matlab.net.http.*
            import matlab.net.http.field.*
            import matlab.net.http.io.*
            import matlab.net.*

            body    = FormProvider('username', username, 'password', password);
            headers = [ContentTypeField(MediaType('application/x-www-form-urlencoded')), ...
                       GenericField('Accept', 'application/json')];
            req     = RequestMessage(RequestMethod.POST, headers, body);
            opts    = HTTPOptions('ConnectTimeout', timeout);
            resp    = req.send(URI(url), opts);

            httpStatus = double(resp.StatusCode);
            bodyData = resp.Body.Data;
            if isa(bodyData, 'uint8')
                bodyData = char(bodyData');
            end
            if httpStatus >= 400
                errMsg = FastAPIClient.extractErrorMessage(bodyData, httpStatus);
                error('FastAPIClient:httpError', 'HTTP %d: %s', httpStatus, errMsg);
            end
            data = FastAPIClient.normalizeJsonResponse(bodyData);
        end

        function data = uploadViaHttpNet(url, filePath, extraFields, token, timeout, projectId)
            % matlab.net.http multipart upload.
            %   Builds the multipart/form-data body manually (raw bytes +
            %   custom boundary) to avoid depending on the FormField /
            %   MultipartFormProvider constructor signatures, which have
            %   shifted between MATLAB releases (R2025b currently rejects
            %   the 4-arg FormField ctor that worked in earlier versions).
            import matlab.net.http.*
            import matlab.net.http.field.*
            import matlab.net.*

            [~, fname, ext] = fileparts(filePath);
            fileName = [fname ext];

            fid = fopen(filePath, 'rb');
            if fid < 0
                error('FastAPIClient:fileNotFound', 'Cannot open file: %s', filePath);
            end
            closeFile = onCleanup(@() fclose(fid));
            fileBytes = fread(fid, '*uint8')';  % row vector uint8

            % Unique boundary marker, unlikely to collide with file contents.
            boundary = sprintf('----QDashBoundary%s%06d', ...
                datestr(now, 'yyyymmddHHMMSSFFF'), randi(999999));
            CRLF = uint8([13 10]);

            body = uint8([]);
            % Extra text fields come first (order doesn't matter to FastAPI).
            if isstruct(extraFields)
                fnames = fieldnames(extraFields);
                for i = 1:numel(fnames)
                    val = extraFields.(fnames{i});
                    if isnumeric(val); val = num2str(val); end
                    header = sprintf(['--%s\r\n' ...
                                      'Content-Disposition: form-data; name="%s"\r\n' ...
                                      '\r\n'], boundary, fnames{i});
                    body = [body, uint8(header), uint8(char(val)), CRLF]; %#ok<AGROW>
                end
            end
            % File part last.
            fileHeader = sprintf(['--%s\r\n' ...
                                  'Content-Disposition: form-data; name="file"; filename="%s"\r\n' ...
                                  'Content-Type: application/octet-stream\r\n' ...
                                  '\r\n'], boundary, fileName);
            body = [body, uint8(fileHeader), fileBytes, CRLF];
            % Closing boundary.
            body = [body, uint8(sprintf('--%s--\r\n', boundary))];

            hdrs = [ContentTypeField(['multipart/form-data; boundary=' boundary]), ...
                    GenericField('Authorization', ['Bearer ' char(token)]), ...
                    GenericField('Accept', 'application/json')];
            if nargin >= 6 && strlength(string(projectId)) > 0
                hdrs = [hdrs, GenericField('X-Project-Id', char(projectId))];
            end

            msgBody = MessageBody();
            msgBody.Payload = body;
            req  = RequestMessage(RequestMethod.POST, hdrs, msgBody);
            opts = HTTPOptions('ConnectTimeout', timeout);
            resp = req.send(URI(url), opts);

            httpStatus = double(resp.StatusCode);
            bodyData = resp.Body.Data;
            if isa(bodyData, 'uint8')
                bodyData = char(bodyData');
            end
            if httpStatus >= 400
                errMsg = FastAPIClient.extractErrorMessage(bodyData, httpStatus);
                error('FastAPIClient:httpError', 'HTTP %d: %s', httpStatus, errMsg);
            end
            data = FastAPIClient.normalizeJsonResponse(bodyData);
        end

    end
end
