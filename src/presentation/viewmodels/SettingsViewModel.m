classdef SettingsViewModel < handle
    % SettingsViewModel  Callback handlers for the Settings screen.
    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = SettingsViewModel(app)
            obj.App = app;
        end

        % Called when navigating to the Settings screen — fetch server IBM config
        % so the UI can display which channel / instance / backends the server
        % is using and whether a token is present.
        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            if isempty(app.ServerIbmStatusArea) || ~isvalid(app.ServerIbmStatusArea); return; end
            app.ServerIbmStatusArea.Value = {Labels.get('settings_server_ibm_loading', 'Loading server IBM configuration...')};
            svc   = app.SettingsSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getIbmConfig(token), ...
                @(data) obj.onIbmConfigComplete(app, data), ...
                @(ME)   obj.onIbmConfigError(app, ME));
        end

        function onIbmConfigComplete(obj, app, data)
            if ~isvalid(app.ServerIbmStatusArea); return; end
            channel  = char(JsonHelper.pick(data, {'channel'}));
            instance = char(JsonHelper.pick(data, {'instance'}));
            if isempty(instance); instance = '(not set)'; end
            backends = JsonHelper.safeField(data, 'backends', {});
            if ischar(backends); backends = {backends}; end
            if ~iscell(backends); backends = num2cell(string(backends)); end
            backendStr = char(strjoin(string(backends), ', '));
            if isempty(backendStr); backendStr = '(default family)'; end
            hasToken = logical(JsonHelper.safeField(data, 'has_token', false));
            brokenFlag = logical(JsonHelper.safeField(data, 'runtime_broken', false));
            brokenMsg  = char(JsonHelper.safeField(data, 'runtime_broken_reason', ''));
            % Store for downstream consumers (dashboard, backends screen)
            app.ServerIbmConfig = struct( ...
                'channel',  string(channel), ...
                'instance', string(instance), ...
                'backends', {backends}, ...
                'has_token', hasToken, ...
                'runtime_broken', brokenFlag, ...
                'runtime_broken_reason', string(brokenMsg));
            if brokenFlag
                badge = sprintf('IBM runtime unavailable — %s', brokenMsg);
            elseif hasToken
                badge = Labels.get('settings_server_ibm_ok', 'Token configured on server.');
            else
                badge = Labels.get('settings_server_ibm_missing', 'No IBM_QUANTUM_TOKEN on server — submissions will fail.');
            end
            app.ServerIbmStatusArea.Value = { ...
                sprintf('Channel:  %s', channel), ...
                sprintf('Instance: %s', instance), ...
                sprintf('Backends: %s', backendStr), ...
                badge};
            obj.LastRefresh = tic;
        end

        function onIbmConfigError(~, app, ME)
            if isvalid(app.ServerIbmStatusArea)
                app.ServerIbmStatusArea.Value = {sprintf(Labels.get('settings_server_ibm_fail', ...
                    'Could not fetch server IBM config: %s'), ME.message)};
            end
            app.logEvent('WARN', sprintf('getIbmConfig failed: %s', ME.message));
        end

        function onSaveSettings(obj)
            app = obj.App;
            app.logEvent('CONFIG', 'Settings save triggered');
            try
                prevUrl = app.State.baseUrl;
                if ~isempty(app.SettingsBaseUrlField) && isvalid(app.SettingsBaseUrlField)
                    app.State.baseUrl = string(app.SettingsBaseUrlField.Value);
                end
                try
                    app.syncClient();
                catch urlErr
                    if strcmp(urlErr.identifier, 'FastAPIClient:insecureBaseUrl') || ...
                       strcmp(urlErr.identifier, 'FastAPIClient:invalidBaseUrl')
                        app.State.baseUrl = prevUrl;  % revert
                        uialert(app.UIFigure, ...
                            sprintf('%s\n\nThe base URL was reverted.', urlErr.message), ...
                            'Insecure URL', 'Icon', 'error');
                        return;
                    end
                    rethrow(urlErr);
                end
                app.logEvent('CONFIG', sprintf('Base URL updated: %s', app.State.baseUrl));
            catch ME
                app.logEvent('WARN', sprintf('Could not update base URL: %s', ME.message));
            end
            if app.State.isAuthenticated()
                shots    = round(app.DefaultShotsField.Value);
                opt      = round(app.DefaultOptField.Value);
                logLevel = char(app.SettingsLogLevelDropdown.Value);
                app.logEvent('API', sprintf('POST /api/settings — shots: %d  opt: %d  logLevel: %s', ...
                    shots, opt, logLevel));
                app.showLoading(Labels.get('loading_saving_settings', 'Saving settings...'));
                % Field names must match the server's SaveSettingsRequest
                % schema (qdash.api.schemas.user_preferences). Pydantic
                % silently drops unknown keys, so a mismatch here means
                % user preferences are never actually persisted. log_level
                % is not a supported field server-side and is therefore
                % kept session-local only.
                prefs = struct( ...
                    'default_shots',        shots, ...
                    'default_optimization', opt);
                svc   = app.SettingsSvc;
                token = app.State.authToken;
                AsyncRunner.run( ...
                    @() svc.savePreferences(prefs, token), ...
                    @(~) obj.onSavePrefsComplete(app), ...
                    @(ME) obj.onSavePrefsError(app, ME));
            else
                app.logEvent('CONFIG', 'Preferences not synced to server (not authenticated)');
            end
            % log level is session-local (applied via Logger.setLevel below)
            try
                Logger.setLevel(upper(char(app.SettingsLogLevelDropdown.Value)));
            catch ME
                Logger.debug('SettingsViewModel', 'setLevel: %s', ME.message);
            end
            app.State.defaultShots        = round(app.DefaultShotsField.Value);
            app.State.defaultOptimization = round(app.DefaultOptField.Value);
            app.logEvent('CONFIG', sprintf('Session settings updated — shots: %d  opt: %d', ...
                app.State.defaultShots, app.State.defaultOptimization));
            if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                app.SettingsStatusArea.Value = {'Settings saved.'};
            end
            uialert(app.UIFigure, Labels.get('settings_saved_session', 'Settings saved for this session.'), 'Settings', 'Icon', 'success');
        end

        function onVerifyIbm(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Verify IBM', 'Icon', 'warning'); return;
            end
            apiTok   = char(app.IbmApiTokenField.Value);
            channel  = char(app.IbmChannelDropdown.Value);
            instance = char(app.IbmInstanceField.Value);
            app.logEvent('API', sprintf('POST /api/settings/verify-ibm — channel: %s  instance: %s', ...
                channel, instance));
            app.showLoading(Labels.get('loading_verifying', 'Verifying IBM credentials...'));
            svc   = app.SettingsSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.verifyIbmCredentials(apiTok, channel, instance, token), ...
                @(data) obj.onVerifyIbmComplete(app, data), ...
                @(ME)   obj.onVerifyIbmError(app, channel, ME));
        end

        function onSettingsUrlChanged(obj, src)
            app = obj.App;
            try
                newUrl = string(src.Value);
                if ~startsWith(newUrl, 'http://') && ~startsWith(newUrl, 'https://')
                    uialert(app.UIFigure, ...
                        'Base URL must start with http:// or https://.', ...
                        'Invalid URL', 'Icon', 'warning');
                    return;
                end
                prevUrl = app.State.baseUrl;
                app.State.baseUrl = newUrl;
                try
                    app.syncClient();
                catch urlErr
                    if strcmp(urlErr.identifier, 'FastAPIClient:insecureBaseUrl') || ...
                       strcmp(urlErr.identifier, 'FastAPIClient:invalidBaseUrl')
                        app.State.baseUrl = prevUrl;  % revert
                        uialert(app.UIFigure, ...
                            sprintf('%s\n\nThe base URL was reverted.', urlErr.message), ...
                            'Insecure URL', 'Icon', 'error');
                        return;
                    end
                    rethrow(urlErr);
                end
                app.logEvent('CONFIG', sprintf('Base URL updated from Settings tab: %s', newUrl));
            catch ME
                app.logEvent('WARN', sprintf('Settings URL change handler error: %s', ME.message));
            end
        end

        function onResetSettings(obj)
            app = obj.App;
            app.DefaultShotsField.Value        = 4096;
            app.DefaultOptField.Value          = 3;
            app.SettingsTimeoutField.Value     = 120;
            app.SettingsLogLevelDropdown.Value = 'info';
            app.logEvent('CONFIG', 'Settings reset to defaults — shots: 4096  opt: 3  timeout: 120  logLevel: info');
            if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                app.SettingsStatusArea.Value = {'Settings reset to defaults.'};
            end
        end

        function onClearServerCache(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Clear Cache', 'Icon', 'warning'); return;
            end
            app.logEvent('API', 'DELETE /api/settings/cache');
            app.showLoading(Labels.get('loading_clearing_cache', 'Clearing cache...'));
            svc   = app.SettingsSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.clearCache(token), ...
                @(~) obj.onClearCacheComplete(app), ...
                @(ME) obj.onClearCacheError(app, ME));
        end

        function onRestartPipeline(obj)
            app = obj.App;
            app.logEvent('UI', sprintf('Pipeline restart triggered — current circuit: %s  job: %s  prediction: %s', ...
                app.State.selectedCircuitId, app.State.selectedJobId, app.State.predictionId));
            app.State.resetPipeline();
            app.logEvent('UI', 'Pipeline restarted — circuit/job/prediction IDs cleared');
            app.onSelectSection('Welcome');
        end

        function onClearLog(obj)
            app = obj.App;
            prevCount = numel(app.EventLog);
            app.EventLog = {};
            try
                if ~isempty(app.EventLogArea) && isvalid(app.EventLogArea)
                    app.EventLogArea.Value = {'Log cleared.'};
                end
            catch ME
                Logger.warn('SettingsViewModel', 'onClearLog UI update failed: %s', ME.message);
            end
            fprintf('[%s] UI       Event log cleared (%d entries removed)\n', ...
                char(datetime('now', 'Format', 'HH:mm:ss.SSS')), prevCount);
        end
    end

    methods (Access = private)
        function onSavePrefsComplete(~, app)
            app.logEvent('API', 'Preferences saved to server successfully');
            app.State.logActivity('Save settings', 'Success');
            app.hideLoading();
        end

        function onSavePrefsError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Save preferences FAILED: %s', ME.message));
            app.showError('Save Settings', ME);
        end

        function onVerifyIbmComplete(~, app, data)
            ok = char(JsonHelper.pick(data, {'valid','status','ok'}));
            if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                app.SettingsStatusArea.Value = {sprintf('IBM credentials verified: %s', ok)};
            end
            app.logEvent('API', sprintf('IBM credentials verification result: %s', ok));
            app.hideLoading();
        end

        function onVerifyIbmError(~, app, channel, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('IBM verify FAILED (channel: %s): %s', channel, ME.message));
            if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                app.SettingsStatusArea.Value = {'Verification failed.', ME.message};
            end
            app.showError('Verify IBM Credentials', ME);
        end

        function onClearCacheComplete(~, app)
            app.logEvent('API', 'Server cache cleared successfully');
            if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                app.SettingsStatusArea.Value = {'Server-side cache cleared.'};
            end
            app.hideLoading();
        end

        function onClearCacheError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Clear cache FAILED: %s', ME.message));
            app.showError('Clear Server Cache', ME);
        end
    end
end
