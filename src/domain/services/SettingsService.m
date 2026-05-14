classdef SettingsService < handle
    % SettingsService  Domain service for server and user preference management.
    %
    %   Covers /api/settings/* endpoints for retrieving and persisting
    %   user preferences and verifying IBM Quantum credentials.

    properties (Access = private)
        Client  % FastAPIClient instance (relaxed from typed property so tests can inject a StubFastAPIClient)
    end

    methods
        function obj = SettingsService(client)
            obj.Client = client;
            Logger.info('SettingsService', 'Initialized');
        end

        % Fetch current user preferences from the server.
        function data = getPreferences(obj, token)
            Logger.info('SettingsService', 'getPreferences → GET /api/settings/preferences');
            try
                data = obj.Client.getAuth('/api/settings/preferences', token);
                Logger.info('SettingsService', 'getPreferences → preferences received');
            catch ME
                Logger.error('SettingsService', 'getPreferences FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Retrieve server-side configuration (read-only admin view).
        function data = getServerConfig(obj, token)
            Logger.info('SettingsService', 'getServerConfig → GET /api/settings');
            try
                data = obj.Client.getAuth('/api/settings', token);
                Logger.info('SettingsService', 'getServerConfig → server config received');
            catch ME
                Logger.error('SettingsService', 'getServerConfig FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Persist user preferences.
        function data = savePreferences(obj, prefs, token)
            Logger.info('SettingsService', 'savePreferences → POST /api/settings');
            try
                data = obj.Client.postAuthJson('/api/settings', prefs, token);
                Logger.info('SettingsService', 'savePreferences → preferences saved');
            catch ME
                Logger.error('SettingsService', 'savePreferences FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Fetch the server's current IBM Quantum configuration summary.
        % Returns struct with fields: channel, instance, backends, has_token.
        % The token itself is never returned — only whether one is configured.
        function data = getIbmConfig(obj, token)
            Logger.info('SettingsService', 'getIbmConfig → GET /api/settings/ibm-config');
            try
                data = obj.Client.getAuth('/api/settings/ibm-config', token);
                Logger.info('SettingsService', 'getIbmConfig → response received');
            catch ME
                Logger.error('SettingsService', 'getIbmConfig FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Verify IBM Quantum API token / instance are reachable.
        function data = verifyIbmCredentials(obj, apiToken, channel, instance, token)
            Logger.info('SettingsService', 'verifyIbmCredentials → POST /api/settings/verify-ibm (channel: %s)', char(channel));
            payload = struct( ...
                'api_token', char(apiToken), ...
                'channel',   char(channel), ...
                'instance',  char(instance));
            try
                data = obj.Client.postAuthJson('/api/settings/verify-ibm', payload, token);
                Logger.info('SettingsService', 'verifyIbmCredentials → verification response received');
            catch ME
                Logger.error('SettingsService', 'verifyIbmCredentials FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Clear the server-side service cache.
        function data = clearCache(obj, token)
            Logger.info('SettingsService', 'clearCache → DELETE /api/settings/cache');
            try
                data = obj.Client.deleteAuth('/api/settings/cache', token);
                Logger.info('SettingsService', 'clearCache → server cache cleared');
            catch ME
                Logger.error('SettingsService', 'clearCache FAILED: %s', ME.message);
                rethrow(ME);
            end
        end
    end
end
