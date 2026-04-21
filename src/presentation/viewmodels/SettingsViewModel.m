classdef SettingsViewModel < handle
    % SettingsViewModel  Callback handlers for the Settings screen.
    %
    %   The Settings screen shows 4 category buttons (IBM Quantum Account,
    %   Default Values, Notifications, Display) + a Developer Event Console.
    %   Clicking a category button opens a modal uifigure dialog built by
    %   open*Dialog() below. Dialog fields are wired to app.*Field
    %   properties for compatibility with existing handlers (onVerifyIbm,
    %   onSaveSettings, ...) and are nulled when the dialog closes.
    %
    %   Between opens, the canonical setting values live in obj.Values so
    %   each dialog opens with the last-entered content, not with defaults.

    properties
        LastRefresh = []  % tic value — used by autoLoadScreen for freshness caching
        Values struct = struct()  % Canonical settings state (persists across dialog opens)
    end
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end

    methods
        function obj = SettingsViewModel(app)
            obj.App = app;
            obj.Values = SettingsViewModel.defaultValues(app);
        end

        % Called when navigating to the Settings screen — fetch server IBM
        % config so app.ServerIbmConfig (consumed by BackendsViewModel and
        % others) stays fresh. No inline UI to update.
        function onEnter(obj)
            app = obj.App;
            if ~app.State.isAuthenticated(); return; end
            svc   = app.SettingsSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.getIbmConfig(token), ...
                @(data) obj.onIbmConfigComplete(app, data), ...
                @(ME)   obj.onIbmConfigError(app, ME));
        end

        function onIbmConfigComplete(obj, app, data)
            try; app.hideLoading(); catch; end
            backends = JsonHelper.safeField(data, 'backends', {});
            if ischar(backends); backends = {backends}; end
            if ~iscell(backends); backends = num2cell(string(backends)); end
            hasToken   = logical(JsonHelper.safeField(data, 'has_token', false));
            brokenFlag = logical(JsonHelper.safeField(data, 'runtime_broken', false));
            brokenMsg  = char(JsonHelper.safeField(data, 'runtime_broken_reason', ''));
            app.ServerIbmConfig = struct( ...
                'channel',  string(JsonHelper.pick(data, {'channel'})), ...
                'instance', string(JsonHelper.pick(data, {'instance'})), ...
                'backends', {backends}, ...
                'has_token', hasToken, ...
                'runtime_broken', brokenFlag, ...
                'runtime_broken_reason', string(brokenMsg));
            obj.LastRefresh = tic;
        end

        function onIbmConfigError(~, app, ME)
            try; app.hideLoading(); catch; end
            app.logEvent('WARN', sprintf('getIbmConfig failed: %s', ME.message));
        end

        % ── IBM Quantum Account dialog ───────────────────────────────────
        function openIbmDialog(obj)
            app = obj.App;
            [dlg, g, footer] = obj.openDialog( ...
                [char(9883) '  ' Labels.get('settings_panel_ibm_account')], ...
                560, {32,32,32,32}, 200);

            SettingsViewModel.addFormLabel(g, 1, 1, Labels.get('settings_label_ibm_email'));
            app.IbmEmailField = uieditfield(g, 'text', 'Value', char(obj.Values.ibmEmail));
            app.IbmEmailField.Layout.Row = 1; app.IbmEmailField.Layout.Column = 2;

            SettingsViewModel.addFormLabel(g, 2, 1, Labels.get('settings_label_api_token'));
            app.IbmApiTokenField = uieditfield(g, 'text', 'Value', char(obj.Values.ibmToken));
            app.IbmApiTokenField.Layout.Row = 2; app.IbmApiTokenField.Layout.Column = 2;
            app.IbmApiTokenField.Placeholder = ...
                Labels.get('settings_placeholder_api_token', 'Paste IBM Quantum API token');

            SettingsViewModel.addFormLabel(g, 3, 1, Labels.get('settings_label_instance'));
            app.IbmInstanceField = uieditfield(g, 'text', 'Value', char(obj.Values.ibmInstance));
            app.IbmInstanceField.Layout.Row = 3; app.IbmInstanceField.Layout.Column = 2;

            SettingsViewModel.addFormLabel(g, 4, 1, Labels.get('settings_label_channel'));
            channelItems = Labels.items('settings_channel_items', {'ibm_quantum','ibm_cloud'});
            ch = char(obj.Values.ibmChannel);
            if ~any(strcmp(channelItems, ch)); ch = channelItems{1}; end
            app.IbmChannelDropdown = uidropdown(g, 'Items', channelItems, 'Value', ch);
            app.IbmChannelDropdown.Layout.Row = 4; app.IbmChannelDropdown.Layout.Column = 2;

            app.VerifyIbmButton = uibutton(footer, ...
                'Text', [char(10003) ' ' Labels.get('settings_btn_verify_ibm')], ...
                'ButtonPushedFcn', @(~,~)obj.onVerifyIbm(dlg));
            app.VerifyIbmButton.Layout.Column = 2; app.styleBtn(app.VerifyIbmButton, 'secondary');
            app.VerifyIbmButton.Tooltip = 'POST /api/settings/verify-ibm';

            closeBtn = uibutton(footer, 'Text', Labels.get('settings_btn_close', 'Close'), ...
                'ButtonPushedFcn', @(~,~)obj.closeIbmDialog(dlg));
            closeBtn.Layout.Column = 3; app.styleBtn(closeBtn, 'ghost');

            dlg.CloseRequestFcn = @(~,~)obj.closeIbmDialog(dlg);
        end

        % ── Default Values dialog ────────────────────────────────────────
        function openDefaultsDialog(obj)
            app = obj.App;
            [dlg, g, footer] = obj.openDialog( ...
                [char(9881) '  ' Labels.get('settings_panel_defaults')], ...
                520, {32,32,32,32}, 150);

            SettingsViewModel.addFormLabel(g, 1, 1, Labels.get('settings_label_default_shots'));
            app.DefaultShotsField = uieditfield(g, 'numeric', 'Value', obj.Values.defaultShots);
            app.DefaultShotsField.Layout.Row = 1; app.DefaultShotsField.Layout.Column = 2;

            SettingsViewModel.addFormLabel(g, 2, 1, Labels.get('settings_label_default_opt'));
            app.DefaultOptField = uieditfield(g, 'numeric', 'Value', obj.Values.defaultOpt);
            app.DefaultOptField.Layout.Row = 2; app.DefaultOptField.Layout.Column = 2;
            app.DefaultOptField.Limits = [0 3];

            SettingsViewModel.addFormLabel(g, 3, 1, Labels.get('settings_label_timeout'));
            app.SettingsTimeoutField = uieditfield(g, 'numeric', 'Value', obj.Values.timeoutSec);
            app.SettingsTimeoutField.Layout.Row = 3; app.SettingsTimeoutField.Layout.Column = 2;

            SettingsViewModel.addFormLabel(g, 4, 1, Labels.get('settings_label_log_level'));
            logItems = Labels.items('settings_log_level_items', {'debug','info','warning','error'});
            lvl = char(obj.Values.logLevel);
            if ~any(strcmp(logItems, lvl)); lvl = 'info'; end
            app.SettingsLogLevelDropdown = uidropdown(g, 'Items', logItems, 'Value', lvl);
            app.SettingsLogLevelDropdown.Layout.Row = 4; app.SettingsLogLevelDropdown.Layout.Column = 2;

            app.SaveSettingsButton = uibutton(footer, ...
                'Text', [char(10004) ' ' Labels.get('settings_btn_save_settings')], ...
                'ButtonPushedFcn', @(~,~)obj.onSaveSettings(dlg));
            app.SaveSettingsButton.Layout.Column = 2; app.styleBtn(app.SaveSettingsButton, 'secondary');

            closeBtn = uibutton(footer, 'Text', Labels.get('settings_btn_close', 'Close'), ...
                'ButtonPushedFcn', @(~,~)obj.closeDefaultsDialog(dlg));
            closeBtn.Layout.Column = 3; app.styleBtn(closeBtn, 'ghost');

            dlg.CloseRequestFcn = @(~,~)obj.closeDefaultsDialog(dlg);
        end

        % ── Notifications dialog ─────────────────────────────────────────
        function openNotificationsDialog(obj)
            app = obj.App;
            [dlg, g, footer] = obj.openDialog( ...
                [char(9993) '  ' Labels.get('settings_panel_notifications')], ...
                520, {32,32,32}, 150);

            SettingsViewModel.addFormLabel(g, 1, 1, Labels.get('settings_label_notify_on_comp'));
            app.EmailNotifyCheck = uicheckbox(g, 'Text', '', 'Value', obj.Values.notifyOnCompletion);
            app.EmailNotifyCheck.Layout.Row = 1; app.EmailNotifyCheck.Layout.Column = 2;

            SettingsViewModel.addFormLabel(g, 2, 1, Labels.get('settings_label_notify_email'));
            app.NotifyEmailField = uieditfield(g, 'text', 'Value', char(obj.Values.notificationEmail));
            app.NotifyEmailField.Layout.Row = 2; app.NotifyEmailField.Layout.Column = 2;

            SettingsViewModel.addFormLabel(g, 3, 1, Labels.get('settings_label_alert_threshold'));
            alertItems = Labels.items('settings_alert_items', ...
                {'All events','Errors only','Job completed','None'});
            at = char(obj.Values.alertThreshold);
            if ~any(strcmp(alertItems, at)); at = 'Job completed'; end
            app.AlertThresholdDropdown = uidropdown(g, 'Items', alertItems, 'Value', at);
            app.AlertThresholdDropdown.Layout.Row = 3; app.AlertThresholdDropdown.Layout.Column = 2;

            saveBtn = uibutton(footer, ...
                'Text', [char(10004) ' ' Labels.get('settings_btn_save_settings', 'Save')], ...
                'ButtonPushedFcn', @(~,~)obj.onSaveNotifications(dlg));
            saveBtn.Layout.Column = 2; app.styleBtn(saveBtn, 'secondary');

            closeBtn = uibutton(footer, 'Text', Labels.get('settings_btn_close', 'Close'), ...
                'ButtonPushedFcn', @(~,~)obj.closeNotificationsDialog(dlg));
            closeBtn.Layout.Column = 3; app.styleBtn(closeBtn, 'ghost');

            dlg.CloseRequestFcn = @(~,~)obj.closeNotificationsDialog(dlg);
        end

        % ── Display dialog ───────────────────────────────────────────────
        function openDisplayDialog(obj)
            app = obj.App;
            [dlg, g, footer] = obj.openDialog( ...
                [char(9788) '  ' Labels.get('settings_panel_display')], ...
                520, {32,32,32}, 150);

            SettingsViewModel.addFormLabel(g, 1, 1, Labels.get('settings_label_theme'));
            % Source themes from Theme.THEME_LIST so additions / renames
            % don't need a label-file edit.
            themeItems = Theme.listThemeDisplayNames();
            currentDisplay = Theme.idToDisplayName(Theme.activeName());
            themeDd = uidropdown(g, 'Items', themeItems, 'Value', currentDisplay);
            themeDd.Layout.Row = 1; themeDd.Layout.Column = 2;

            SettingsViewModel.addFormLabel(g, 2, 1, Labels.get('settings_label_date_format'));
            dfItems = Labels.items('settings_date_format_items', {'YYYY-MM-DD','DD/MM/YYYY','MM-DD-YYYY'});
            df = char(obj.Values.dateFormat);
            if ~any(strcmp(dfItems, df)); df = 'YYYY-MM-DD'; end
            dfDd = uidropdown(g, 'Items', dfItems, 'Value', df);
            dfDd.Layout.Row = 2; dfDd.Layout.Column = 2;

            SettingsViewModel.addFormLabel(g, 3, 1, Labels.get('settings_label_compact_mode'));
            compactCb = uicheckbox(g, 'Text', '', 'Value', obj.Values.compactMode);
            compactCb.Layout.Row = 3; compactCb.Layout.Column = 2;

            saveBtn = uibutton(footer, ...
                'Text', [char(10004) ' ' Labels.get('settings_btn_save_settings', 'Save')], ...
                'ButtonPushedFcn', @(~,~)obj.onSaveDisplay(dlg, themeDd, dfDd, compactCb));
            saveBtn.Layout.Column = 2; app.styleBtn(saveBtn, 'secondary');

            closeBtn = uibutton(footer, 'Text', Labels.get('settings_btn_close', 'Close'), ...
                'ButtonPushedFcn', @(~,~)obj.closeDisplayDialog(dlg, themeDd, dfDd, compactCb));
            closeBtn.Layout.Column = 3; app.styleBtn(closeBtn, 'ghost');

            dlg.CloseRequestFcn = @(~,~)obj.closeDisplayDialog(dlg, themeDd, dfDd, compactCb);
        end

        % ── Save / Verify handlers ───────────────────────────────────────

        function onSaveSettings(obj, dlg)
            if nargin < 2; dlg = []; end
            app = obj.App;
            parent = app.UIFigure;
            if ~isempty(dlg) && isvalid(dlg); parent = dlg; end
            app.logEvent('CONFIG', 'Settings save triggered');

            if ~isempty(app.DefaultShotsField) && isvalid(app.DefaultShotsField)
                obj.Values.defaultShots = round(app.DefaultShotsField.Value);
            end
            if ~isempty(app.DefaultOptField) && isvalid(app.DefaultOptField)
                obj.Values.defaultOpt = round(app.DefaultOptField.Value);
            end
            if ~isempty(app.SettingsTimeoutField) && isvalid(app.SettingsTimeoutField)
                obj.Values.timeoutSec = round(app.SettingsTimeoutField.Value);
            end
            if ~isempty(app.SettingsLogLevelDropdown) && isvalid(app.SettingsLogLevelDropdown)
                obj.Values.logLevel = string(app.SettingsLogLevelDropdown.Value);
            end

            app.State.defaultShots        = obj.Values.defaultShots;
            app.State.defaultOptimization = obj.Values.defaultOpt;
            app.logEvent('CONFIG', sprintf('Session settings updated — shots: %d  opt: %d', ...
                obj.Values.defaultShots, obj.Values.defaultOpt));

            try
                Logger.setLevel(upper(char(obj.Values.logLevel)));
            catch ME
                Logger.debug('SettingsViewModel', 'setLevel: %s', ME.message);
            end

            if app.State.isAuthenticated()
                app.logEvent('API', sprintf('POST /api/settings — shots: %d  opt: %d  logLevel: %s', ...
                    obj.Values.defaultShots, obj.Values.defaultOpt, char(obj.Values.logLevel)));
                app.showLoading(Labels.get('loading_saving_settings', 'Saving settings...'));
                % Field names must match the server's SaveSettingsRequest schema.
                prefs = struct( ...
                    'default_shots',        obj.Values.defaultShots, ...
                    'default_optimization', obj.Values.defaultOpt);
                svc   = app.SettingsSvc;
                token = app.State.authToken;
                AsyncRunner.run( ...
                    @() svc.savePreferences(prefs, token), ...
                    @(~) obj.onSavePrefsComplete(app, parent), ...
                    @(ME) obj.onSavePrefsError(app, ME, parent));
            else
                app.logEvent('CONFIG', 'Preferences not synced to server (not authenticated)');
                uialert(parent, Labels.get('settings_saved_session', 'Settings saved for this session.'), ...
                    'Settings', 'Icon', 'success');
            end
        end

        function onVerifyIbm(obj, dlg)
            if nargin < 2; dlg = []; end
            app = obj.App;
            parent = app.UIFigure;
            if ~isempty(dlg) && isvalid(dlg); parent = dlg; end
            if ~app.State.isAuthenticated()
                uialert(parent, Labels.get('error_not_authenticated'), ...
                    'Verify IBM', 'Icon', 'warning');
                return;
            end
            apiTok   = char(app.IbmApiTokenField.Value);
            channel  = char(app.IbmChannelDropdown.Value);
            instance = char(app.IbmInstanceField.Value);
            % Persist to Values so next open shows the same content.
            obj.Values.ibmEmail    = string(app.IbmEmailField.Value);
            obj.Values.ibmToken    = string(apiTok);
            obj.Values.ibmChannel  = string(channel);
            obj.Values.ibmInstance = string(instance);

            app.logEvent('API', sprintf('POST /api/settings/verify-ibm — channel: %s  instance: %s', ...
                channel, instance));
            app.showLoading(Labels.get('loading_verifying', 'Verifying IBM credentials...'));
            svc   = app.SettingsSvc;
            token = app.State.authToken;
            AsyncRunner.run( ...
                @() svc.verifyIbmCredentials(apiTok, channel, instance, token), ...
                @(data) obj.onVerifyIbmComplete(app, data, parent), ...
                @(ME)   obj.onVerifyIbmError(app, channel, ME, parent));
        end

        function onResetSettings(obj)
            app = obj.App;
            defaults = SettingsViewModel.defaultValues(app);
            obj.Values.defaultShots = defaults.defaultShots;
            obj.Values.defaultOpt   = defaults.defaultOpt;
            obj.Values.timeoutSec   = defaults.timeoutSec;
            obj.Values.logLevel     = defaults.logLevel;
            % Reflect into an open Defaults dialog if one is visible.
            if ~isempty(app.DefaultShotsField) && isvalid(app.DefaultShotsField)
                app.DefaultShotsField.Value = obj.Values.defaultShots;
            end
            if ~isempty(app.DefaultOptField) && isvalid(app.DefaultOptField)
                app.DefaultOptField.Value = obj.Values.defaultOpt;
            end
            if ~isempty(app.SettingsTimeoutField) && isvalid(app.SettingsTimeoutField)
                app.SettingsTimeoutField.Value = obj.Values.timeoutSec;
            end
            if ~isempty(app.SettingsLogLevelDropdown) && isvalid(app.SettingsLogLevelDropdown)
                app.SettingsLogLevelDropdown.Value = char(obj.Values.logLevel);
            end
            app.logEvent('CONFIG', sprintf('Settings reset to defaults — shots: %d  opt: %d  timeout: %d  logLevel: %s', ...
                obj.Values.defaultShots, obj.Values.defaultOpt, obj.Values.timeoutSec, char(obj.Values.logLevel)));
            uialert(app.UIFigure, ...
                Labels.get('settings_reset_ok', 'Settings reset to defaults.'), ...
                'Settings', 'Icon', 'info');
        end

        function onClearServerCache(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), ...
                    'Clear Cache', 'Icon', 'warning');
                return;
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
        function [dlg, formGrid, footerGrid] = openDialog(obj, title, w, formRows, primaryW)
            % Build a right-sized modal dialog with a form area, a thin
            % separator line, and a footer bar that holds a primary action
            % and a Close button.
            %
            %   title       — dialog window title.
            %   w           — dialog width in pixels.
            %   formRows    — cell array of row heights for the form area
            %                 (one per label+field row).
            %   primaryW    — width of the primary action button in the
            %                 footer. The Close button is 110 px.
            %
            % Returns the (dialog, form grid, footer grid) so callers can
            % populate the form and the footer without further plumbing.
            app = obj.App;
            if nargin < 5 || isempty(primaryW); primaryW = 180; end
            nRows    = numel(formRows);
            formPad  = 16 + 16;       % top + bottom inside form grid
            formGap  = max(0, nRows - 1) * 8;
            formH    = formPad + sum([formRows{:}]) + formGap;
            sepH     = 1;
            footerH  = 50;
            h        = formH + sepH + footerH;

            dlg = uifigure('Name', title, 'WindowStyle', 'modal', ...
                'Resize', 'off', 'Color', Theme.COLOR_BG);
            Theme.applyFigureMode(dlg, Theme.activeName());
            try
                parentPos = app.UIFigure.Position;
                x = parentPos(1) + (parentPos(3) - w) / 2;
                y = parentPos(2) + (parentPos(4) - h) / 2;
                dlg.Position = [max(1, x), max(1, y), w, h];
            catch
                dlg.Position = [200, 200, w, h];
            end

            % Outer frame: form | separator | footer — all fixed heights
            % so the dialog window has no trailing whitespace.
            outer = uigridlayout(dlg, [3 1]);
            outer.RowHeight    = {formH, sepH, footerH};
            outer.ColumnWidth  = {'1x'};
            outer.Padding      = [0 0 0 0];
            outer.RowSpacing   = 0;
            outer.BackgroundColor = Theme.COLOR_BG;

            % Form area — caller populates (labels in col 1, fields in col 2).
            formGrid = uigridlayout(outer, [nRows 2]);
            formGrid.RowHeight     = formRows;
            formGrid.ColumnWidth   = {160, '1x'};
            formGrid.Padding       = [16 16 16 16];
            formGrid.RowSpacing    = 8;
            formGrid.BackgroundColor = Theme.COLOR_BG;
            formGrid.Layout.Row    = 1;

            % Hairline separator between content and footer.
            sep = uipanel(outer, 'Title', '', 'BorderType', 'none');
            sep.BackgroundColor = Theme.COLOR_DIVIDER;
            sep.Layout.Row      = 2;

            % Footer bar with a subtle tint so the action zone reads as a
            % distinct region from the form above it.
            footerPanel = uipanel(outer, 'Title', '', 'BorderType', 'none');
            footerPanel.BackgroundColor = Theme.COLOR_ACCENT_BG;
            footerPanel.Layout.Row      = 3;

            footerGrid = uigridlayout(footerPanel, [1 3]);
            footerGrid.RowHeight     = {34};
            footerGrid.ColumnWidth   = {'1x', primaryW, 110};
            footerGrid.ColumnSpacing = 8;
            footerGrid.Padding       = [16 8 16 8];
            footerGrid.BackgroundColor = Theme.COLOR_ACCENT_BG;
        end

        function onSavePrefsComplete(~, app, parent)
            app.hideLoading();
            app.logEvent('API', 'Preferences saved to server successfully');
            app.State.logActivity('Save settings', 'Success');
            if nargin < 3 || isempty(parent) || ~isvalid(parent); parent = app.UIFigure; end
            uialert(parent, Labels.get('settings_saved_session', 'Settings saved for this session.'), ...
                'Settings', 'Icon', 'success');
        end

        function onSavePrefsError(~, app, ME, parent)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Save preferences FAILED: %s', ME.message));
            if nargin < 4 || isempty(parent) || ~isvalid(parent); parent = app.UIFigure; end
            uialert(parent, sprintf('Save failed: %s', ME.message), ...
                'Save Settings', 'Icon', 'error');
        end

        function onVerifyIbmComplete(~, app, data, parent)
            app.hideLoading();
            if nargin < 4 || isempty(parent) || ~isvalid(parent); parent = app.UIFigure; end
            connected = logical(JsonHelper.safeField(data, 'connected', false));
            status    = char(JsonHelper.pick(data, {'status'}));
            message   = char(JsonHelper.pick(data, {'message'}));
            nBackends = JsonHelper.safeField(data, 'available_backends', []);
            app.logEvent('API', sprintf('IBM credentials verification — connected: %d  status: %s', ...
                connected, status));
            if connected
                lines = {'IBM credentials verified successfully.'};
                if ~isempty(nBackends) && isnumeric(nBackends)
                    lines{end+1} = sprintf('Available backends: %d', round(nBackends));
                end
                if ~isempty(message); lines{end+1} = message; end
                uialert(parent, lines, 'Verify IBM Credentials', 'Icon', 'success');
            else
                msg = message;
                if isempty(msg); msg = 'Verification failed.'; end
                uialert(parent, msg, 'Verify IBM Credentials', 'Icon', 'error');
            end
        end

        function onVerifyIbmError(~, app, channel, ME, parent)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('IBM verify FAILED (channel: %s): %s', channel, ME.message));
            if nargin < 5 || isempty(parent) || ~isvalid(parent); parent = app.UIFigure; end
            uialert(parent, sprintf('Verification failed: %s', ME.message), ...
                'Verify IBM Credentials', 'Icon', 'error');
        end

        function onClearCacheComplete(~, app)
            app.hideLoading();
            app.logEvent('API', 'Server cache cleared successfully');
            uialert(app.UIFigure, ...
                Labels.get('settings_cache_cleared', 'Server-side cache cleared.'), ...
                'Clear Cache', 'Icon', 'success');
        end

        function onClearCacheError(~, app, ME)
            app.hideLoading();
            app.logEvent('ERROR', sprintf('Clear cache FAILED: %s', ME.message));
            uialert(app.UIFigure, sprintf('Clear cache failed: %s', ME.message), ...
                'Clear Server Cache', 'Icon', 'error');
        end

        function onSaveNotifications(obj, dlg)
            app = obj.App;
            if ~isempty(app.EmailNotifyCheck) && isvalid(app.EmailNotifyCheck)
                obj.Values.notifyOnCompletion = logical(app.EmailNotifyCheck.Value);
            end
            if ~isempty(app.NotifyEmailField) && isvalid(app.NotifyEmailField)
                obj.Values.notificationEmail = string(app.NotifyEmailField.Value);
            end
            if ~isempty(app.AlertThresholdDropdown) && isvalid(app.AlertThresholdDropdown)
                obj.Values.alertThreshold = string(app.AlertThresholdDropdown.Value);
            end
            app.logEvent('CONFIG', sprintf('Notifications updated — enabled: %d  email: %s  threshold: %s', ...
                obj.Values.notifyOnCompletion, char(obj.Values.notificationEmail), char(obj.Values.alertThreshold)));
            uialert(dlg, Labels.get('settings_saved_session', 'Settings saved for this session.'), ...
                'Notifications', 'Icon', 'success');
        end

        function onSaveDisplay(obj, dlg, themeDd, dfDd, compactCb)
            app = obj.App;
            themeDisplayName = '';
            if isvalid(themeDd); themeDisplayName = char(themeDd.Value); end
            if isvalid(dfDd);      obj.Values.dateFormat  = string(dfDd.Value);       end
            if isvalid(compactCb); obj.Values.compactMode = logical(compactCb.Value); end

            if ~isempty(themeDisplayName)
                newId = Theme.displayNameToId(themeDisplayName);
                obj.Values.theme = string(themeDisplayName);
                if ~strcmp(newId, Theme.activeName())
                    % Hot-swap: close this dialog first (applyTheme also
                    % closes modals, but doing it explicitly avoids a brief
                    % flash of the dialog in the old palette), then rebuild.
                    app.logEvent('CONFIG', sprintf('Display updated — theme: %s  date: %s  compact: %d', ...
                        char(obj.Values.theme), char(obj.Values.dateFormat), obj.Values.compactMode));
                    if isvalid(dlg); delete(dlg); end
                    app.applyTheme(newId);
                    return;
                end
            end

            app.logEvent('CONFIG', sprintf('Display updated — theme: %s  date: %s  compact: %d', ...
                char(obj.Values.theme), char(obj.Values.dateFormat), obj.Values.compactMode));
            uialert(dlg, Labels.get('settings_display_saved', ...
                'Display preferences saved.'), ...
                'Display', 'Icon', 'success');
        end

        function closeIbmDialog(obj, dlg)
            app = obj.App;
            if ~isempty(app.IbmEmailField) && isvalid(app.IbmEmailField)
                obj.Values.ibmEmail = string(app.IbmEmailField.Value);
            end
            if ~isempty(app.IbmApiTokenField) && isvalid(app.IbmApiTokenField)
                obj.Values.ibmToken = string(app.IbmApiTokenField.Value);
            end
            if ~isempty(app.IbmInstanceField) && isvalid(app.IbmInstanceField)
                obj.Values.ibmInstance = string(app.IbmInstanceField.Value);
            end
            if ~isempty(app.IbmChannelDropdown) && isvalid(app.IbmChannelDropdown)
                obj.Values.ibmChannel = string(app.IbmChannelDropdown.Value);
            end
            app.IbmEmailField      = [];
            app.IbmApiTokenField   = [];
            app.IbmInstanceField   = [];
            app.IbmChannelDropdown = [];
            app.VerifyIbmButton    = [];
            if isvalid(dlg); delete(dlg); end
        end

        function closeDefaultsDialog(obj, dlg)
            app = obj.App;
            if ~isempty(app.DefaultShotsField) && isvalid(app.DefaultShotsField)
                obj.Values.defaultShots = round(app.DefaultShotsField.Value);
            end
            if ~isempty(app.DefaultOptField) && isvalid(app.DefaultOptField)
                obj.Values.defaultOpt = round(app.DefaultOptField.Value);
            end
            if ~isempty(app.SettingsTimeoutField) && isvalid(app.SettingsTimeoutField)
                obj.Values.timeoutSec = round(app.SettingsTimeoutField.Value);
            end
            if ~isempty(app.SettingsLogLevelDropdown) && isvalid(app.SettingsLogLevelDropdown)
                obj.Values.logLevel = string(app.SettingsLogLevelDropdown.Value);
            end
            app.DefaultShotsField        = [];
            app.DefaultOptField          = [];
            app.SettingsTimeoutField     = [];
            app.SettingsLogLevelDropdown = [];
            app.SaveSettingsButton       = [];
            if isvalid(dlg); delete(dlg); end
        end

        function closeNotificationsDialog(obj, dlg)
            app = obj.App;
            if ~isempty(app.EmailNotifyCheck) && isvalid(app.EmailNotifyCheck)
                obj.Values.notifyOnCompletion = logical(app.EmailNotifyCheck.Value);
            end
            if ~isempty(app.NotifyEmailField) && isvalid(app.NotifyEmailField)
                obj.Values.notificationEmail = string(app.NotifyEmailField.Value);
            end
            if ~isempty(app.AlertThresholdDropdown) && isvalid(app.AlertThresholdDropdown)
                obj.Values.alertThreshold = string(app.AlertThresholdDropdown.Value);
            end
            app.EmailNotifyCheck       = [];
            app.NotifyEmailField       = [];
            app.AlertThresholdDropdown = [];
            if isvalid(dlg); delete(dlg); end
        end

        function closeDisplayDialog(obj, dlg, themeDd, dfDd, compactCb)
            if isvalid(themeDd);   obj.Values.theme       = string(themeDd.Value);    end
            if isvalid(dfDd);      obj.Values.dateFormat  = string(dfDd.Value);       end
            if isvalid(compactCb); obj.Values.compactMode = logical(compactCb.Value); end
            if isvalid(dlg); delete(dlg); end
        end
    end

    methods (Static, Access = private)
        function v = defaultValues(app)
            % Seed the settings struct from env / AppState / label defaults.
            v = struct( ...
                'ibmEmail',            string(Labels.get('settings_default_ibm_email', 'user@ibm.com')), ...
                'ibmToken',            string(AppConfig.env('IBM_QUANTUM_TOKEN', '')), ...
                'ibmInstance',         string(AppConfig.env('IBM_QUANTUM_INSTANCE', ...
                                              Labels.get('settings_default_instance', 'ibm-q/open/main'))), ...
                'ibmChannel',          string(AppConfig.env('IBM_CHANNEL', ...
                                              Labels.get('settings_channel_default', 'ibm_cloud'))), ...
                'defaultShots',        app.State.defaultShots, ...
                'defaultOpt',          app.State.defaultOptimization, ...
                'timeoutSec',          120, ...
                'logLevel',            string(Labels.get('settings_log_level_default', 'info')), ...
                'notifyOnCompletion',  true, ...
                'notificationEmail',   string(Labels.get('settings_default_notify_email', 'user@example.com')), ...
                'alertThreshold',      string(Labels.get('settings_alert_default', 'Job completed')), ...
                'theme',               string(Theme.idToDisplayName(Theme.activeName())), ...
                'dateFormat',          "YYYY-MM-DD", ...
                'compactMode',         false);
        end

        function addFormLabel(g, row, col, text)
            lbl = uilabel(g, 'Text', text);
            lbl.FontColor = Theme.COLOR_LABEL;
            lbl.VerticalAlignment = 'center';
            lbl.Layout.Row = row; lbl.Layout.Column = col;
        end
    end
end
