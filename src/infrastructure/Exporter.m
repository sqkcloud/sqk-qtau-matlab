classdef Exporter
    % Exporter  Static helpers for downloading in-memory data to disk.
    %
    %   Used by the Results / Analysis / Detailed Analysis screens to
    %   support a "Download JSON" button. Wraps uiputfile + jsonencode
    %   so callers don't have to repeat the dialog + error-handling
    %   boilerplate.
    %
    %   Usage:
    %       fname = Exporter.suggestFilename('Results', ...
    %           {'ghz_state_n255', '1975a064', Exporter.todayStamp()});
    %       % → 'Results_ghz_state_n255_1975a064_20260504.json'
    %       ok = Exporter.toJsonFile(data, fname, app.UIFigure);
    %
    %   No constructor — call methods directly.

    methods (Static)
        function ok = toJsonFile(data, defaultName, parent)
            % Prompt the user for a save location and write data as
            % pretty-printed JSON. Returns true on success, false when
            % the user cancelled or an error occurred.
            ok = false;
            if nargin < 3 || isempty(parent); parent = []; end
            if nargin < 2 || isempty(defaultName)
                defaultName = sprintf('export_%s.json', ...
                    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
            end
            try
                [fname, fpath] = uiputfile( ...
                    {'*.json', 'JSON files (*.json)'; ...
                     '*.*',    'All files (*.*)'}, ...
                    'Save as JSON', defaultName);
                if isequal(fname, 0) || isequal(fpath, 0)
                    return;  % user cancelled
                end
                full = fullfile(fpath, fname);
                % Pretty-print: jsonencode(struct, 'PrettyPrint', true)
                % is supported on R2021a+. Fall back to plain encode
                % when running on older runtimes.
                try
                    payload = jsonencode(data, 'PrettyPrint', true);
                catch
                    payload = jsonencode(data);
                end
                fid = fopen(full, 'w');
                if fid < 0
                    error('Exporter:OpenFailed', ...
                        'Could not open %s for writing.', full);
                end
                cleanup = onCleanup(@() fclose(fid));
                fwrite(fid, payload, 'char');
                clear cleanup;  %#ok<CLCLN>
                ok = true;
            catch ME
                Logger.warn('Exporter', 'toJsonFile: %s', ME.message);
                if ~isempty(parent) && isvalid(parent)
                    try
                        uialert(parent, ME.message, 'Save JSON', ...
                            'Icon', 'error');
                    catch
                    end
                end
            end
        end

        function name = suggestFilename(prefix, parts)
            % Compose a download-friendly filename from a prefix and a
            % cell of parts, replacing path-unfriendly chars and
            % appending ".json". Empty parts are dropped.
            %   suggestFilename('Results', {'ghz_state_n255', '1975a06'})
            %   → 'Results_ghz_state_n255_1975a06.json'
            if nargin < 2 || isempty(parts); parts = {}; end
            if iscell(parts)
                cleaned = cell(1, numel(parts));
                k = 0;
                for i = 1:numel(parts)
                    p = strtrim(char(string(parts{i})));
                    if isempty(p); continue; end
                    p = regexprep(p, '[^A-Za-z0-9_.-]', '_');
                    k = k + 1;
                    cleaned{k} = p;
                end
                cleaned = cleaned(1:k);
            else
                cleaned = {};
            end
            base = char(string(prefix));
            base = regexprep(base, '[^A-Za-z0-9_.-]', '_');
            if isempty(cleaned)
                name = sprintf('%s.json', base);
            else
                name = sprintf('%s_%s.json', base, strjoin(cleaned, '_'));
            end
        end

        function s = todayStamp()
            % YYYYMMDD timestamp helper for filename suffixes.
            s = char(datetime('now', 'Format', 'yyyyMMdd'));
        end
    end
end
