classdef FastAPIClient < handle
    properties
        BaseUrl string
        Timeout double = 20
    end

    methods
        function obj = FastAPIClient(baseUrl)
            obj.BaseUrl = string(baseUrl);
        end

        function setBaseUrl(obj, baseUrl)
            obj.BaseUrl = string(baseUrl);
        end

        function data = openApi(obj)
            data = obj.get('/api/openapi.json');
        end

        function data = login(obj, username, password)
            url = char(obj.BaseUrl + "/api/auth/login");
            formBody = ['username=' FastAPIClient.urlEncode(char(username)) '&password=' FastAPIClient.urlEncode(char(password))];
            options = weboptions('Timeout', obj.Timeout, 'MediaType', 'application/x-www-form-urlencoded', 'RequestMethod', 'post', ...
                'ContentType', 'text', 'HeaderFields', {'Content-Type', 'application/x-www-form-urlencoded'; 'Accept', 'application/json'});
            raw = webwrite(url, formBody, options);
            data = FastAPIClient.normalizeJsonResponse(raw);
        end

        function data = getMe(obj, token)
            data = obj.getAuth('/api/auth/me', token);
        end

        function data = logout(obj, token)
            data = obj.postAuthJson('/api/auth/logout', struct(), token);
        end

        function data = listProjects(obj, token, skip, limit)
            endpoint = sprintf('/api/admin/projects?skip=%d&limit=%d', round(skip), round(limit));
            data = obj.getAuth(endpoint, token);
        end

        function data = get(obj, endpoint)
            url = char(obj.BaseUrl + string(endpoint));
            options = weboptions('Timeout', obj.Timeout, 'HeaderFields', {'Accept', 'application/json'});
            raw = webread(url, options);
            data = FastAPIClient.normalizeJsonResponse(raw);
        end

        function data = getAuth(obj, endpoint, token)
            url = char(obj.BaseUrl + string(endpoint));
            authHeader = ['Bearer ' char(token)];
            options = weboptions('Timeout', obj.Timeout, 'HeaderFields', {'Authorization', authHeader; 'Accept', 'application/json'});
            raw = webread(url, options);
            data = FastAPIClient.normalizeJsonResponse(raw);
        end

        function data = postAuthJson(obj, endpoint, payload, token)
            url = char(obj.BaseUrl + string(endpoint));
            authHeader = ['Bearer ' char(token)];
            options = weboptions('Timeout', obj.Timeout, 'MediaType', 'application/json', 'ContentType', 'json', ...
                'HeaderFields', {'Authorization', authHeader; 'Accept', 'application/json'});
            raw = webwrite(url, payload, options);
            data = FastAPIClient.normalizeJsonResponse(raw);
        end
    end

    methods (Static, Access = private)
        function out = urlEncode(str)
            import java.net.URLEncoder
            out = char(URLEncoder.encode(str, 'UTF-8'));
        end

        function data = normalizeJsonResponse(raw)
            data = raw;
            try
                if isstring(raw)
                    if isscalar(raw)
                        raw = char(raw);
                    else
                        raw = char(join(raw, newline));
                    end
                end
                if ischar(raw)
                    txt = strtrim(raw);
                    if ~isempty(txt)
                        firstChar = txt(1);
                        if firstChar == '{'
                            data = jsondecode(txt);
                        elseif firstChar == '['
                            data = jsondecode(txt);
                        end
                    end
                end
            catch
                data = raw;
            end
        end
    end
end
