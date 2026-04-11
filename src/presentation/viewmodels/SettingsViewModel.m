classdef SettingsViewModel < handle
    % SettingsViewModel  Callback handlers for the Settings screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = SettingsViewModel(app)
            obj.App = app;
        end

        function onSaveSettings(obj)
            app = obj.App;
            app.logEvent('CONFIG', 'Settings save triggered');
            try
                if ~isempty(app.SettingsBaseUrlField) && isvalid(app.SettingsBaseUrlField)
                    app.State.baseUrl = string(app.SettingsBaseUrlField.Value);
                end
                app.syncClient();
                app.logEvent('CONFIG', sprintf('Base URL updated: %s', app.State.baseUrl));
            catch ME
                app.logEvent('WARN', sprintf('Could not update base URL: %s', ME.message));
            end
            if app.State.isAuthenticated()
                shots    = round(app.DefaultShotsField.Value);
                opt      = round(app.DefaultOptField.Value);
                logLevel = char(app.SettingsLogLevelDropdown.Value);
                app.logEvent('API', sprintf('POST /api/settings/preferences — shots: %d  opt: %d  logLevel: %s', ...
                    shots, opt, logLevel));
                app.showLoading(Labels.get('loading_saving_settings', 'Saving settings...'));
                try
                    prefs = struct( ...
                        'default_shots',      shots, ...
                        'optimization_level', opt, ...
                        'log_level',          logLevel);
                    app.SettingsSvc.savePreferences(prefs, app.State.authToken);
                    app.logEvent('API', 'Preferences saved to server successfully');
                    app.State.logActivity('Save settings', 'Success');
                    app.hideLoading();
                catch ME
                    app.hideLoading();
                    app.logEvent('ERROR', sprintf('Save preferences FAILED: %s', ME.message));
                    app.showError('Save Settings', ME);
                end
            else
                app.logEvent('CONFIG', 'Preferences not synced to server (not authenticated)');
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
            try
                data = app.SettingsSvc.verifyIbmCredentials(apiTok, channel, instance, app.State.authToken);
                ok   = char(JsonHelper.pick(data, {'valid','status','ok'}));
                if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                    app.SettingsStatusArea.Value = {sprintf('IBM credentials verified: %s', ok)};
                end
                app.logEvent('API', sprintf('IBM credentials verification result: %s', ok));
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('IBM verify FAILED (channel: %s): %s', channel, ME.message));
                if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                    app.SettingsStatusArea.Value = {'Verification failed.', ME.message};
                end
                app.showError('Verify IBM Credentials', ME);
            end
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
                app.State.baseUrl = newUrl;
                app.syncClient();
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
            try
                app.SettingsSvc.clearCache(app.State.authToken);
                app.logEvent('API', 'Server cache cleared successfully');
                if ~isempty(app.SettingsStatusArea) && isvalid(app.SettingsStatusArea)
                    app.SettingsStatusArea.Value = {'Server-side cache cleared.'};
                end
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Clear cache FAILED: %s', ME.message));
                app.showError('Clear Server Cache', ME);
            end
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
end
