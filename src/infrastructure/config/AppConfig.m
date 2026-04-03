classdef AppConfig
    % AppConfig  Reads runtime configuration from resources/app.properties.
    %
    %   The properties file is located at:
    %     <workspace_root>/resources/app.properties
    %
    %   File format: key=value  (one per line; lines starting with '#' or '!'
    %   are comments; leading/trailing whitespace around key and value is trimmed).
    %
    %   Usage:
    %     url     = AppConfig.get('base_url')
    %     timeout = AppConfig.getDouble('http_timeout', 30)
    %
    %   Values are cached after the first read.  Call AppConfig.reload() to
    %   force a fresh read from disk (useful during development).

    methods (Static)

        % get  Return the string value for a key, or defaultValue if not found.
        function value = get(key, defaultValue)
            if nargin < 2; defaultValue = ''; end
            try
                props = AppConfig.loadProps();
                safeKey = matlab.lang.makeValidName(char(key));
                if isfield(props, safeKey)
                    value = props.(safeKey);
                else
                    value = char(defaultValue);
                    Logger.debug('AppConfig', 'Key not found: "%s" — using default: "%s"', key, char(defaultValue));
                end
            catch ME
                Logger.error('AppConfig', 'Reading config key "%s": %s', key, ME.message);
                value = char(defaultValue);
            end
        end

        % getDouble  Return a numeric value for a key, or defaultValue if missing/invalid.
        function value = getDouble(key, defaultValue)
            if nargin < 2; defaultValue = 0; end
            raw = AppConfig.get(key, '');
            if isempty(raw)
                value = defaultValue;
            else
                parsed = str2double(raw);
                if isnan(parsed)
                    Logger.warn('AppConfig', 'Key "%s" value "%s" is not numeric — using default: %g', ...
                        key, raw, defaultValue);
                    value = defaultValue;
                else
                    value = parsed;
                end
            end
        end

        % reload  Force the cache to be cleared so the file is re-read on next call.
        function reload()
            AppConfig.loadProps(true);
            Logger.info('AppConfig', 'Configuration cache cleared — will reload on next access.');
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
            filePath = AppConfig.resolveFile('app.properties');

            if ~isfile(filePath)
                Logger.warn('AppConfig', 'Properties file not found at: %s — falling back to built-in defaults.', filePath);
                cachedProps = props;
                return;
            end

            fid = fopen(filePath, 'r', 'n', 'UTF-8');
            if fid < 0
                Logger.error('AppConfig', 'Cannot open: %s', filePath);
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
                Logger.info('AppConfig', 'Loaded %d config entries from: %s', count, filePath);
            catch ME
                fclose(fid);
                Logger.error('AppConfig', 'Parsing properties file: %s', ME.message);
                cachedProps = props;
            end
        end

        function path = resolveFile(filename)
            % Navigate from src/infrastructure/config/ up three levels to the
            % workspace root, then into resources/.
            thisDir = fileparts(mfilename('fullpath'));
            path    = fullfile(thisDir, '..', '..', '..', 'resources', filename);
        end

    end
end
