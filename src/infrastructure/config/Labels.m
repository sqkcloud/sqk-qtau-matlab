classdef Labels
    % Labels  Provides UI label strings loaded from resources/labels.properties.
    %
    %   All user-visible text is defined in the properties file so that labels
    %   can be changed without modifying source code.
    %
    %   Usage:
    %     text = Labels.get('welcome_btn_login')          % single string
    %     cols = Labels.cols('welcome_table_cols_projects') % cell array
    %
    %   If a key is not found, Labels.get returns the key itself so the UI
    %   still shows something recognisable.  A warning is printed to the
    %   MATLAB Command Window to alert the developer.
    %
    %   Values are cached after the first read.  Call Labels.reload() to
    %   force a fresh read from disk.

    methods (Static)

        % get  Return the string value for a key.  Falls back to the key name.
        function value = get(key, defaultValue)
            if nargin < 2; defaultValue = char(key); end
            try
                props = Labels.loadProps();
                safeKey = matlab.lang.makeValidName(char(key));
                if isfield(props, safeKey)
                    value = props.(safeKey);
                else
                    value = char(defaultValue);
                    fprintf('[Labels] Key not found: "%s"\n', key);
                end
            catch ME
                fprintf('[Labels] ERROR reading label "%s": %s\n', key, ME.message);
                value = char(defaultValue);
            end
        end

        % cols  Return a cell array by splitting a comma-separated label value.
        function result = cols(key, defaultValue)
            if nargin < 2; defaultValue = {}; end
            raw = Labels.get(key, '');
            if isempty(raw)
                result = defaultValue;
            else
                parts  = strsplit(raw, ',');
                result = strtrim(parts);
            end
        end

        % items  Alias for cols — used for dropdown/listbox Items arrays.
        function result = items(key, defaultValue)
            if nargin < 2; defaultValue = {}; end
            result = Labels.cols(key, defaultValue);
        end

        % reload  Clear the label cache so the file is re-read on next access.
        function reload()
            Labels.loadProps(true);
            fprintf('[Labels] Label cache cleared — will reload on next access.\n');
        end

    end

    methods (Static, Access = private)

        function props = loadProps(forceReload)
            persistent cachedProps;
            if nargin < 1; forceReload = false; end
            if ~forceReload && ~isempty(cachedProps)
                props = cachedProps;
                return;
            end

            props    = struct();
            filePath = Labels.resolveFile('labels.properties');

            if ~isfile(filePath)
                fprintf('[Labels] WARNING: labels file not found at: %s\n', filePath);
                cachedProps = props;
                return;
            end

            fid = fopen(filePath, 'r', 'n', 'UTF-8');
            if fid < 0
                fprintf('[Labels] ERROR: cannot open: %s\n', filePath);
                cachedProps = props;
                return;
            end

            count = 0;
            try
                while ~feof(fid)
                    raw = fgetl(fid);
                    if ~ischar(raw); continue; end
                    line = strtrim(raw);
                    if isempty(line); continue; end
                    if line(1) == '#' || line(1) == '!'; continue; end
                    eqIdx = strfind(line, '=');
                    if isempty(eqIdx); continue; end
                    key = strtrim(line(1 : eqIdx(1)-1));
                    val = strtrim(line(eqIdx(1)+1 : end));
                    safeKey = matlab.lang.makeValidName(key);
                    if ~isempty(safeKey)
                        props.(safeKey) = val;
                        count = count + 1;
                    end
                end
                fclose(fid);
                cachedProps = props;
                fprintf('[Labels] Loaded %d label entries from: %s\n', count, filePath);
            catch ME
                fclose(fid);
                fprintf('[Labels] ERROR parsing labels file: %s\n', ME.message);
                cachedProps = props;
            end
        end

        function path = resolveFile(filename)
            thisDir = fileparts(mfilename('fullpath'));
            path    = fullfile(thisDir, '..', '..', '..', 'resources', filename);
        end

    end
end
