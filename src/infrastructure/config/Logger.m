classdef Logger
    % Logger  Lightweight static logger for service-layer classes.
    %
    %   Service classes do not hold a reference to QTAUWorkbenchApp, so they use this
    %   class to write structured log lines to the MATLAB Command Window.
    %   The format matches what QTAUWorkbenchApp.logEvent writes so that log streams
    %   from the UI and service layers are interleaved consistently.
    %
    %   Usage:
    %     Logger.info('CircuitService', 'Uploading file: %s', filePath)
    %     Logger.error('JobService', 'Cancel FAILED: %s', ME.message)
    %     Logger.debug('FastAPIClient', 'POST %s', url)

    methods (Static)

        % log  Core method — writes one line to the Command Window.
        function log(level, category, fmt, varargin)
            ts  = char(datetime('now', 'Format', 'HH:mm:ss.SSS'));
            if nargin > 3
                msg = sprintf(fmt, varargin{:});
            else
                msg = char(fmt);
            end
            fprintf('[%s] %-8s [%-18s] %s\n', ts, upper(char(level)), char(category), msg);
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

    end
end
