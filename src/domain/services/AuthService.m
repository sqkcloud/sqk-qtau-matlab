classdef AuthService < handle
    % AuthService  Domain service for authentication operations.
    %
    %   Wraps /api/auth/* endpoints.  Keeps auth logic out of ViewModels
    %   and provides a single place for login, logout, and user-info calls.

    properties (Access = private)
        Client  % FastAPIClient instance (relaxed from typed property so tests can inject a StubFastAPIClient)
    end

    methods
        function obj = AuthService(client)
            obj.Client = client;
            Logger.info('AuthService', 'Initialized');
        end

        % Authenticate with username/password. Returns token response struct.
        function data = login(obj, username, password)
            maskedUser = Logger.maskUsername(username);
            Logger.info('AuthService', 'login → user: %s', maskedUser);
            try
                data = obj.Client.login(username, password);
                Logger.info('AuthService', 'login OK — user: %s', maskedUser);
            catch ME
                Logger.error('AuthService', 'login FAILED (user: %s): %s', maskedUser, ME.message);
                rethrow(ME);
            end
        end

        % Invalidate the current session token.
        function data = logout(obj, token)
            Logger.info('AuthService', 'logout requested');
            try
                data = obj.Client.logout(token);
                Logger.info('AuthService', 'logout OK');
            catch ME
                Logger.error('AuthService', 'logout FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

        % Fetch the current user profile.
        function data = getMe(obj, token)
            Logger.debug('AuthService', 'getMe → GET /api/auth/me');
            try
                data = obj.Client.getMe(token);
                Logger.debug('AuthService', 'getMe OK');
            catch ME
                Logger.error('AuthService', 'getMe FAILED: %s', ME.message);
                rethrow(ME);
            end
        end

    end

    methods
        % Fetch projects accessible by the authenticated user.
        function data = listProjects(obj, token, skip, limit)
            Logger.debug('AuthService', 'listProjects');
            try
                data = obj.Client.listProjects(token, skip, limit);
                Logger.debug('AuthService', 'listProjects OK');
            catch ME
                Logger.error('AuthService', 'listProjects FAILED: %s', ME.message);
                rethrow(ME);
            end
        end
    end
end
