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
                % Open the save dialog at the OS Downloads folder by
                % default — see Exporter.defaultDir for the resolution
                % rules. Callers can still type any path in the dialog.
                [fname, fpath] = uiputfile( ...
                    {'*.json', 'JSON files (*.json)'; ...
                     '*.*',    'All files (*.*)'}, ...
                    'Save as JSON', Exporter.savePath(defaultName));
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

        function s = minuteStamp()
            % YYYYMMDD_HHMM timestamp helper for filename suffixes.
            % Used by Report_*.pdf and Results_*.{csv,json} downloads
            % so two exports made in the same day don't collide on
            % disk and so chronological sort matches recency.
            s = char(datetime('now', 'Format', 'yyyyMMdd_HHmm'));
        end

        function p = defaultDir()
            % Resolve the OS-conventional Downloads folder for save
            % dialogs so PDFs / JSON / CSV exports don't dirty the
            % project working directory by default.
            %
            %   macOS / Linux: ~/Downloads          via $HOME
            %   Windows:       %USERPROFILE%\Downloads
            %
            % Fallback chain (each step skipped if its target is
            % missing): Downloads → home → pwd. The final fallback
            % preserves legacy behavior so callers always get a
            % usable path back.
            home = '';
            if ispc
                home = getenv('USERPROFILE');
            end
            if isempty(home)
                home = getenv('HOME');
            end
            if isempty(home)
                try
                    home = char(java.lang.System.getProperty('user.home'));
                catch
                    home = '';
                end
            end
            p = '';
            if ~isempty(home)
                candidate = fullfile(home, 'Downloads');
                if exist(candidate, 'dir') == 7
                    p = candidate;
                else
                    p = home;
                end
            end
            if isempty(p) || exist(p, 'dir') ~= 7
                p = pwd;
            end
        end

        function full = savePath(name)
            % Compose `Exporter.defaultDir() / name` so callsites can
            % pass a one-shot starting path to uiputfile. Letting the
            % directory part of the third arg control the dialog's
            % opening folder is documented MATLAB behavior.
            full = fullfile(Exporter.defaultDir(), char(name));
        end
    end
end
