classdef seed_helpers
    % seed_helpers  Shared utilities for seed scripts.
    %
    %   Provides login, config loading, and common weboptions builders
    %   so that seed_*.m scripts don't duplicate auth and HTTP setup.

    methods (Static)

        function props = loadConfig()
            % Load seed credentials from resources/seed.properties.
            % Falls back to resources/app.properties for base_url.
            propsFile = fullfile(fileparts(mfilename('fullpath')), '..', 'resources', 'seed.properties');
            appFile   = fullfile(fileparts(mfilename('fullpath')), '..', 'resources', 'app.properties');

            props = struct('base_url', '', ...
                           'login_path', '/api/auth/login', ...
                           'username', '', ...
                           'password', '');

            % Load app.properties for base_url and login_path
            if isfile(appFile)
                lines = seed_helpers.readProps(appFile);
                if isfield(lines, 'base_url') && ~isempty(lines.base_url)
                    props.base_url = lines.base_url;
                end
                if isfield(lines, 'login_path') && ~isempty(lines.login_path)
                    props.login_path = lines.login_path;
                end
            end

            % Load seed.properties for credentials
            if ~isfile(propsFile)
                error('seed_helpers:configMissing', ...
                    'resources/seed.properties not found.\nCopy resources/seed.properties.example → resources/seed.properties and fill in credentials.');
            end
            lines = seed_helpers.readProps(propsFile);
            if isfield(lines, 'seed_username') && ~isempty(lines.seed_username)
                props.username = lines.seed_username;
            end
            if isfield(lines, 'seed_password') && ~isempty(lines.seed_password)
                props.password = lines.seed_password;
            end

            % Validate required fields
            if isempty(props.base_url)
                error('seed_helpers:configMissing', 'base_url not set in app.properties');
            end
            if isempty(props.username) || isempty(props.password)
                error('seed_helpers:configMissing', 'seed_username / seed_password not set in resources/seed.properties');
            end
        end

        function token = login(baseUrl, loginPath, username, password)
            % Authenticate and return the Bearer token string.
            import matlab.net.http.*
            import matlab.net.http.field.*
            import matlab.net.http.io.*

            body = FormProvider('username', username, 'password', password);
            req  = RequestMessage('POST', ...
                [ContentTypeField(MediaType('application/x-www-form-urlencoded'))], body);
            resp = req.send(matlab.net.URI([baseUrl loginPath]));
            if resp.StatusCode ~= 200
                error('seed_helpers:loginFailed', 'Login failed with status %d', int32(resp.StatusCode));
            end
            token = string(resp.Body.Data.access_token);
        end

        function opts = getOpts(token)
            % Build weboptions for authenticated GET requests.
            opts = weboptions('Timeout', 30, 'ContentType', 'json', ...
                'HeaderFields', {'Authorization', char("Bearer " + token); ...
                                 'Accept', 'application/json'});
        end

        function opts = postOpts(token)
            % Build weboptions for authenticated POST (JSON) requests.
            opts = weboptions('Timeout', 30, ...
                'MediaType', 'application/json', 'ContentType', 'json', ...
                'HeaderFields', {'Authorization', char("Bearer " + token); ...
                                 'Accept', 'application/json'});
        end

        function opts = putOpts(token)
            % Build weboptions for authenticated PUT (JSON) requests.
            opts = weboptions('Timeout', 30, ...
                'MediaType', 'application/json', 'ContentType', 'json', ...
                'RequestMethod', 'put', ...
                'HeaderFields', {'Authorization', char("Bearer " + token); ...
                                 'Accept', 'application/json'});
        end
    end

    methods (Static, Access = private)
        function kvs = readProps(filePath)
            % Parse a key=value .properties file into a struct.
            kvs = struct();
            fid = fopen(filePath, 'r');
            if fid < 0; return; end
            cleanup = onCleanup(@() fclose(fid));
            while ~feof(fid)
                line = strtrim(fgetl(fid));
                if isempty(line) || line(1) == '#' || line(1) == '!'; continue; end
                eqIdx = strfind(line, '=');
                if isempty(eqIdx); continue; end
                key = strtrim(line(1:eqIdx(1)-1));
                val = strtrim(line(eqIdx(1)+1:end));
                key = strrep(key, '.', '_');
                kvs.(key) = val;
            end
        end
    end
end
