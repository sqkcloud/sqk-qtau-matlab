classdef JsonHelper
    methods (Static)
        function out = pretty(data)
            try
                data = JsonHelper.decodeIfJson(data);
                if isstruct(data)
                    out = jsonencode(data);
                elseif iscell(data)
                    out = jsonencode(data);
                elseif isstring(data)
                    if isscalar(data)
                        out = char(data);
                    else
                        out = char(join(data, newline));
                    end
                elseif ischar(data)
                    out = data;
                else
                    out = evalc('disp(data)');
                end
            catch
                out = 'Unable to render response.';
            end
        end

        function value = pick(data, paths)
            value = "";
            data = JsonHelper.decodeIfJson(data);
            for i = 1:numel(paths)
                path = string(paths{i});
                value = JsonHelper.pickOne(data, path);
                if isstring(value)
                    if isscalar(value)
                        if strlength(value) ~= 0
                            return;
                        end
                    else
                        return;
                    end
                else
                    return;
                end
            end
        end

        function value = pickOne(data, path)
            value = "";
            parts = split(string(path), '.');
            cur = data;
            for k = 1:numel(parts)
                key = char(parts(k));
                if isstruct(cur)
                    if isfield(cur, key)
                        cur = cur.(key);
                    else
                        value = "";
                        return;
                    end
                else
                    value = "";
                    return;
                end
            end
            if isstring(cur)
                value = cur;
            elseif ischar(cur)
                value = string(cur);
            elseif isnumeric(cur)
                value = string(cur);
            elseif islogical(cur)
                value = string(cur);
            else
                try
                    value = string(jsonencode(cur));
                catch
                    value = "";
                end
            end
        end

        function rows = projectsToRows(data)
            data = JsonHelper.decodeIfJson(data);
            rows = cell(0,6);
            if isstruct(data)
                if isfield(data, 'projects')
                    items = data.projects;
                else
                    items = struct([]);
                end
            else
                items = struct([]);
            end
            n = numel(items);
            rows = cell(n,6);
            for i = 1:n
                rows{i,1} = char(JsonHelper.pick(items(i), {'project_id','id'}));
                rows{i,2} = char(JsonHelper.pick(items(i), {'name'}));
                rows{i,3} = char(JsonHelper.pick(items(i), {'owner_username'}));
                rows{i,4} = char(JsonHelper.pick(items(i), {'member_count'}));
                rows{i,5} = char(JsonHelper.pick(items(i), {'created_at'}));
                rows{i,6} = char(JsonHelper.pick(items(i), {'description'}));
            end
        end

        function data = decodeIfJson(data)
            try
                if isstring(data)
                    if isscalar(data)
                        data = char(data);
                    else
                        data = char(join(data, newline));
                    end
                end
                if ischar(data)
                    txt = strtrim(data);
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
            end
        end
    end
end
