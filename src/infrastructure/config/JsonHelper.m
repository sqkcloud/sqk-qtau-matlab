classdef JsonHelper
    % JsonHelper  Static utilities for JSON decoding, pretty-printing,
    %             and transforming API response structs into table-row cell arrays.
    %
    %   All methods are stateless; call as JsonHelper.pick(data, paths).

    methods (Static)

        % pretty  Convert any MATLAB value to a human-readable string for
        %         display in a uitextarea.  JSON structs/arrays are encoded;
        %         plain strings are passed through unchanged.
        function out = pretty(data)
            try
                data = JsonHelper.decodeIfJson(data);
                if isstruct(data) || iscell(data)
                    out = jsonencode(data);
                elseif isstring(data)
                    out = char(strjoin(data, newline));
                elseif ischar(data)
                    out = data;
                else
                    out = strtrim(formattedDisplayText(data));
                end
            catch ME
                Logger.warn('JsonHelper', 'pretty() failed: %s', ME.message);
                out = 'Unable to render response.';
            end
        end

        % pick  Walk a dotted-path list and return the first non-empty value
        %       found in data.  Supports fallback chains:
        %         JsonHelper.pick(d, {'access_token', 'data.access_token'})
        function value = pick(data, paths)
            value = "";
            data  = JsonHelper.decodeIfJson(data);
            for i = 1:numel(paths)
                value = JsonHelper.pickOne(data, string(paths{i}));
                if strlength(strtrim(string(value))) > 0
                    return;
                end
            end
        end

        % pickOne  Navigate a single dotted path within a struct hierarchy.
        function value = pickOne(data, path)
            value  = "";
            parts  = split(string(path), '.');
            cursor = data;
            for k = 1:numel(parts)
                key = char(parts(k));
                if isstruct(cursor) && isfield(cursor, key)
                    cursor = cursor.(key);
                else
                    return;
                end
            end
            value = JsonHelper.toStr(cursor);
        end

        % ── DTO row mappers ───────────────────────────────────────────────────

        % projectsToRows  Map an /admin/projects response → 5-column cell matrix
        %   + a parallel cell vector of project IDs (stored in table UserData).
        %   Columns: Name | Tags | Member Count | Created At | Description
        function [rows, ids] = projectsToRows(data)
            rows  = cell(0, 5);
            ids   = {};
            items = JsonHelper.extractList(data, 'projects');
            n     = numel(items);
            if n == 0; return; end
            rows  = cell(n, 5);
            ids   = cell(n, 1);
            for i = 1:n
                ids{i}   = char(JsonHelper.pick(items(i), {'project_id','id'}));
                rows{i,1} = char(JsonHelper.pick(items(i), {'name'}));
                tags = JsonHelper.safeField(items(i), 'tags', {});
                if ischar(tags)
                    rows{i,2} = tags;
                elseif iscell(tags)
                    rows{i,2} = char(strjoin(string(tags), ', '));
                elseif isstring(tags)
                    rows{i,2} = char(strjoin(tags, ', '));
                else
                    rows{i,2} = '';
                end
                rows{i,3} = char(JsonHelper.pick(items(i), {'member_count'}));
                rows{i,4} = char(JsonHelper.pick(items(i), {'created_at'}));
                rows{i,5} = char(JsonHelper.pick(items(i), {'description'}));
            end
        end

        % backendsToRows  Map /backends response → 6-column cell matrix
        %   Name | Qubits | Status | Pred Fidelity | Queue | Notes
        function rows = backendsToRows(data)
            rows  = cell(0, 6);
            items = JsonHelper.extractList(data, 'backends');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0; return; end
            rows = cell(n, 6);
            for i = 1:n
                rows{i,1} = char(JsonHelper.pick(items(i), {'name','backend_name'}));
                q = JsonHelper.pick(items(i), {'num_qubits','qubits','n_qubits'});
                rows{i,2} = JsonHelper.toDouble(q);
                rows{i,3} = char(JsonHelper.pick(items(i), {'status','operational_status'}));
                f = JsonHelper.pick(items(i), {'predicted_fidelity','fidelity','avg_fidelity'});
                rows{i,4} = JsonHelper.toDouble(f);
                rows{i,5} = char(JsonHelper.pick(items(i), {'queue_length','queue','queue_status'}));
                rows{i,6} = char(JsonHelper.pick(items(i), {'role','notes','description'}));
            end
        end

        % jobsToRows  Map /jobs response → 5-column cell matrix
        %   Job ID | Backend | Status | Progress | Created
        function rows = jobsToRows(data)
            rows  = cell(0, 5);
            items = JsonHelper.extractList(data, 'jobs');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0; return; end
            rows = cell(n, 5);
            for i = 1:n
                rows{i,1} = char(JsonHelper.pick(items(i), {'job_record_id','job_id','id'}));
                rows{i,2} = char(JsonHelper.pick(items(i), {'backend_name','backend'}));
                rows{i,3} = char(JsonHelper.pick(items(i), {'status'}));
                pct = JsonHelper.pick(items(i), {'progress_pct','progress','completion_pct'});
                if isnumeric(pct)
                    rows{i,4} = sprintf('%.0f%%', pct * 100);
                else
                    rows{i,4} = char(pct);
                end
                rows{i,5} = char(JsonHelper.pick(items(i), {'created_at','submitted_at'}));
            end
        end

        % resultsToRows  Map job results → 5-column cell matrix
        %   Metric | Measured | Predicted | Ideal | Notes
        function rows = resultsToRows(data)
            rows = cell(0, 5);
            try
                data = JsonHelper.decodeIfJson(data);
                metrics = {};
                if isstruct(data)
                    if isfield(data, 'metrics'); metrics = data.metrics; end
                end
                if isempty(metrics); return; end
                n    = numel(metrics);
                rows = cell(n, 5);
                for i = 1:n
                    m = metrics(i);
                    rows{i,1} = char(JsonHelper.pick(m, {'name','metric'}));
                    rows{i,2} = JsonHelper.toDouble(JsonHelper.pick(m, {'measured'}));
                    rows{i,3} = JsonHelper.toDouble(JsonHelper.pick(m, {'predicted'}));
                    rows{i,4} = JsonHelper.toDouble(JsonHelper.pick(m, {'ideal'}));
                    rows{i,5} = char(JsonHelper.pick(m, {'notes','comment'}));
                end
            catch ME
                Logger.warn('JsonHelper', 'resultsToRows() failed: %s', ME.message);
            end
        end

        % benchmarkStrategyToRows  Map compare-strategies response → 5-column matrix
        %   Strategy | Depth | 2Q gates | Predicted fidelity | Comment
        function rows = benchmarkStrategyToRows(data)
            rows  = cell(0, 5);
            items = JsonHelper.extractList(data, 'strategies');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0; return; end
            rows = cell(n, 5);
            for i = 1:n
                rows{i,1} = char(JsonHelper.pick(items(i), {'name','strategy','strategy_name'}));
                rows{i,2} = JsonHelper.toDouble(JsonHelper.pick(items(i), {'depth'}));
                rows{i,3} = JsonHelper.toDouble(JsonHelper.pick(items(i), {'two_qubit_gates','cx_count','num_2q'}));
                rows{i,4} = JsonHelper.toDouble(JsonHelper.pick(items(i), {'predicted_fidelity','fidelity'}));
                rows{i,5} = char(JsonHelper.pick(items(i), {'comment','notes','description'}));
            end
        end

        % activityToRows  Map recent_activity array → 3-column cell matrix
        %   Time | Action | Status
        function rows = activityToRows(data)
            rows  = cell(0, 3);
            items = JsonHelper.extractList(data, 'recent_activity');
            if isempty(items); items = JsonHelper.asList(data); end
            n = numel(items);
            if n == 0; return; end
            rows = cell(n, 3);
            for i = 1:n
                rows{i,1} = char(JsonHelper.pick(items(i), {'timestamp','time','created_at'}));
                rows{i,2} = char(JsonHelper.pick(items(i), {'description','action','type'}));
                rows{i,3} = char(JsonHelper.pick(items(i), {'status'}));
            end
        end

        % predictionToLines  Map a prediction struct to display lines for uitextarea.
        function lines = predictionToLines(data)
            lines = {};
            try
                data = JsonHelper.decodeIfJson(data);
                fid  = char(JsonHelper.pick(data, {'predicted_fidelity','fidelity'}));
                prob = char(JsonHelper.pick(data, {'success_probability','prob_success'}));
                qt   = char(JsonHelper.pick(data, {'queue_time','expected_queue_time'}));
                rt   = char(JsonHelper.pick(data, {'runtime','estimated_runtime'}));
                lines = { ...
                    sprintf('Predicted fidelity: %s', fid), ...
                    sprintf('Expected success probability: %s', prob), ...
                    sprintf('Expected queue time: %s', qt), ...
                    sprintf('Estimated runtime: %s', rt)};
            catch ME
                Logger.warn('JsonHelper', 'predictionToLines() failed: %s', ME.message);
            end
        end

        % decodeIfJson  Parse a char/string value as JSON if it looks like
        %               a JSON object or array; pass through otherwise.
        function data = decodeIfJson(data)
            try
                if isstring(data) && ~isscalar(data)
                    data = char(strjoin(data, newline));
                elseif isstring(data)
                    data = char(data);
                end
                if ischar(data)
                    txt = strtrim(data);
                    if ~isempty(txt) && (txt(1) == '{' || txt(1) == '[')
                        data = jsondecode(txt);
                    end
                end
            catch ME
                Logger.warn('JsonHelper', 'decodeIfJson() failed: %s', ME.message);
            end
        end
    end

    % ── Public utility helpers ────────────────────────────────────────────────
    methods (Static)

        % safeField  Return a struct field value or a default if missing.
        function val = safeField(s, fieldName, default)
            if isstruct(s) && isfield(s, fieldName)
                val = s.(fieldName);
            else
                val = default;
            end
        end

        % toDouble  Safely convert any scalar JSON value to a MATLAB double.
        function d = toDouble(v)
            if isnumeric(v) && isscalar(v); d = v; return; end
            d = str2double(char(string(v)));
            if isnan(d); d = 0; end
        end

        % extractList  Return a struct array from a named list field or empty [].
        function items = extractList(data, fieldName)
            items = [];
            try
                data = JsonHelper.decodeIfJson(data);
                if isstruct(data) && isfield(data, fieldName)
                    items = data.(fieldName);
                end
            catch ME
                Logger.warn('JsonHelper', 'extractList(%s) failed: %s', fieldName, ME.message);
            end
        end

        % asList  Coerce a struct or cell array to a struct array.
        function items = asList(data)
            try
                data = JsonHelper.decodeIfJson(data);
                if isstruct(data); items = data;
                elseif iscell(data); items = [data{:}];
                else; items = [];
                end
            catch ME
                Logger.warn('JsonHelper', 'asList() failed: %s', ME.message);
                items = [];
            end
        end

    end

    % ── Private string helpers ────────────────────────────────────────────────
    methods (Static, Access = private)

        function val = toStr(v)
            if isstring(v) && isscalar(v); val = v; return; end
            if ischar(v);   val = string(v); return; end
            if isnumeric(v) && isscalar(v); val = string(v); return; end
            if islogical(v) && isscalar(v); val = string(v); return; end
            try; val = string(jsonencode(v)); catch ME; Logger.debug('JsonHelper', 'toStr fallback: %s', ME.message); val = ""; end
        end

    end
end
