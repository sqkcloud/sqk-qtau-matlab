classdef Logger
    % Logger  Lightweight static logger for service-layer classes.
    %
    %   Service classes do not hold a reference to QTAUWorkbenchApp, so they use this
    %   class to write structured log lines to the MATLAB Command Window.
    %   The format matches what QTAUWorkbenchApp.logEvent writes so that log streams
    %   from the UI and service layers are interleaved consistently.
    %
    %   Log-level filtering: set Logger.setLevel('WARN') to suppress DEBUG and
    %   INFO messages.  Default level is DEBUG (all messages printed).
    %
    %   Usage:
    %     Logger.info('CircuitService', 'Uploading file: %s', filePath)
    %     Logger.error('JobService', 'Cancel FAILED: %s', ME.message)
    %     Logger.debug('FastAPIClient', 'POST %s', url)
    %     Logger.setLevel('INFO')   % suppress DEBUG messages

    properties (Constant, Access = private)
        % Numeric priority for each level (higher = more severe).
        LEVEL_MAP = struct('DEBUG', 0, 'HTTP', 0, 'INFO', 1, 'WARN', 2, 'ERROR', 3)
    end

    methods (Static)

        % setLevel  Change the minimum log level.  Messages below this
        %           threshold are silently dropped.
        %   Valid values: 'DEBUG', 'INFO', 'WARN', 'ERROR'
        function setLevel(level)
            Logger.currentLevel(upper(char(level)));
        end

        % getLevel  Return the current minimum log level as a char.
        function lvl = getLevel()
            lvl = Logger.currentLevel();
        end

        % log  Core method — writes one line to the Command Window if the
        %      message level meets the current threshold.
        function log(level, category, fmt, varargin)
            levelStr = upper(char(level));
            if ~Logger.shouldLog(levelStr)
                return;
            end
            ts  = char(datetime('now', 'Format', 'HH:mm:ss.SSS'));
            if nargin > 3
                msg = sprintf(fmt, varargin{:});
            else
                msg = char(fmt);
            end
            fprintf('[%s] %-8s [%-18s] %s\n', ts, levelStr, char(category), Logger.redact(msg));
        end

        function debug(category, fmt, varargin)
            Logger.log('DEBUG', category, fmt, varargin{:});
        end

        function info(category, fmt, varargin)
            Logger.log('INFO', category, fmt, varargin{:});
        end

        function warn(category, fmt, varargin)
            Logger.log('WARN', category, fmt, varargin{:});
        end

        function error(category, fmt, varargin)
            Logger.log('ERROR', category, fmt, varargin{:});
        end

        % http  Log an outgoing HTTP request (method + URL).
        function http(method, url)
            Logger.log('HTTP', 'FastAPIClient', '%s %s', upper(char(method)), char(url));
        end

        % httpResponse  Log an HTTP response summary.
        function httpResponse(method, url, statusOrInfo)
            Logger.log('HTTP', 'FastAPIClient', '%s %s → %s', ...
                upper(char(method)), char(url), char(string(statusOrInfo)));
        end

        % reload  Re-read the log level from AppConfig.  Call this after
        %         AppConfig.reload() if the config file has changed.
        function reload()
            % Default raised from DEBUG to INFO. With DEBUG, every
            % HTTP request prints a line via Logger.http (mapped to
            % priority 0 in LEVEL_MAP), which on data-heavy screens
            % like Backends fan-out produces ~80 fprintf calls per
            % visit and contributes to the perceived sluggishness
            % via the synchronous stdout write + EventLog cell-array
            % prepend. Set log_level=DEBUG in app.properties to opt
            % back into verbose logging during development.
            try
                lvl = upper(AppConfig.get('log_level', 'INFO'));
                Logger.setLevel(lvl);
            catch
                Logger.setLevel('INFO');
            end
        end

        % maskUsername  Mask a username for safe logging: show first char + '***'.
        function masked = maskUsername(username)
            u = char(username);
            if isempty(u)
                masked = '***';
            else
                masked = [u(1) '***'];
            end
        end

        % redact  Strip Bearer tokens and credential-bearing query params
        %         from a log message so sensitive material never reaches
        %         stdout.  Applied automatically by Logger.log; callers can
        %         also invoke it directly when composing custom output.
        function out = redact(s)
            out = char(string(s));
            % "Bearer <token>"  →  "Bearer ***"
            out = regexprep(out, '(?i)(Bearer\s+)\S+',                       '$1***');
            % "Authorization: Bearer <token>"  →  "Authorization: Bearer ***"
            out = regexprep(out, '(?i)(Authorization:\s*Bearer\s+)\S+',      '$1***');
            % "?access_token=...&token=..." → masked values
            out = regexprep(out, '(?i)([?&](access_token|token|api_key)=)[^&\s]+', '$1***');
        end

    end

    methods (Static, Access = private)

        function lvl = currentLevel(newLevel)
            % Persistent storage for the active log level.
            % Initial value raised to INFO so any boot-time logger
            % call that fires BEFORE Logger.reload() runs (e.g. very
            % early in QTAUWorkbenchApp construction or inside
            % AppConfig.loadProps) still respects the quieter
            % default. Setting log_level=DEBUG in app.properties or
            % calling Logger.setLevel('DEBUG') restores verbose
            % output.
            persistent storedLevel;
            if isempty(storedLevel)
                storedLevel = 'INFO';
            end
            if nargin > 0
                storedLevel = upper(char(newLevel));
            end
            lvl = storedLevel;
        end

        function tf = shouldLog(levelStr)
            % Return true if levelStr meets the current threshold.
            map = Logger.LEVEL_MAP;
            cur = Logger.currentLevel();
            if isfield(map, levelStr)
                msgPri = map.(levelStr);
            else
                msgPri = 1;  % unknown levels default to INFO priority
            end
            if isfield(map, cur)
                curPri = map.(cur);
            else
                curPri = 0;  % unknown threshold → show everything
            end
            tf = msgPri >= curPri;
        end

    end
end
