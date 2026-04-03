% SettingsTab  Populates the Settings section panel.
%
%   Layout (4-row grid):
%     Row 1 (258 px): IBM Quantum Account | Default Values.
%     Row 2 (178 px): Notifications       | Display.
%     Row 3 (168 px): Developer Event Console (full width).
%     Row 4 ( 52 px): Action bar — Save Settings / Verify IBM / Reset Defaults.
%
%   The API base URL field is pre-filled from resources/app.properties via
%   AppConfig.  All visible strings come from resources/labels.properties.
function SettingsScreen(app)
    Logger.info('SettingsScreen', 'Building Settings tab UI');
    t = app.createSectionPage('Settings');

    g = uigridlayout(t, [4 3]);
    g.RowHeight     = {258, 178, 168, 52};
    g.ColumnWidth   = {'1x', 6, '1.05x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Column divider (rows 1-2) ─────────────────────────────────────────────
    div = uipanel(g, 'Title', ''); div.Layout.Row = [1 2]; div.Layout.Column = 2;
    div.BackgroundColor = [0.87 0.90 0.93]; div.BorderType = 'none';
    app.attachColumnDivider(div, g);

    % ── IBM Quantum Account (row 1, left) ─────────────────────────────────────
    ibmPanel = uipanel(g, 'Title', Labels.get('settings_panel_ibm_account'));
    ibmPanel.Layout.Row = 1; ibmPanel.Layout.Column = 1; ibmPanel.BackgroundColor = [1 1 1];

    ig = uigridlayout(ibmPanel, [7 2]);
    ig.RowHeight = {28,28,28,28,28,34,'1x'};
    ig.ColumnWidth = {160,'1x'};
    ig.Padding = [14 10 14 10]; ig.RowSpacing = 5; ig.BackgroundColor = [1 1 1];

    lbl = uilabel(ig, 'Text', Labels.get('settings_label_ibm_email'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.IbmEmailField = uieditfield(ig, 'text', 'Value', Labels.get('settings_default_ibm_email', 'user@ibm.com'));
    app.IbmEmailField.Layout.Row = 1; app.IbmEmailField.Layout.Column = 2;

    lbl = uilabel(ig, 'Text', Labels.get('settings_label_api_token'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.IbmApiTokenField = uieditfield(ig, 'text', 'Value', '');
    app.IbmApiTokenField.Layout.Row = 2; app.IbmApiTokenField.Layout.Column = 2;
    app.IbmApiTokenField.Placeholder = Labels.get('settings_placeholder_api_token', 'Paste IBM Quantum API token');

    lbl = uilabel(ig, 'Text', Labels.get('settings_label_channel'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    app.IbmChannelDropdown = uidropdown(ig, ...
        'Items', Labels.items('settings_channel_items', {'ibm_quantum','ibm_cloud'}), ...
        'Value', Labels.get('settings_channel_default', 'ibm_quantum'));
    app.IbmChannelDropdown.Layout.Row = 3; app.IbmChannelDropdown.Layout.Column = 2;

    lbl = uilabel(ig, 'Text', Labels.get('settings_label_instance'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 4; lbl.Layout.Column = 1;
    app.IbmInstanceField = uieditfield(ig, 'text', 'Value', Labels.get('settings_default_instance', 'ibm-q/open/main'));
    app.IbmInstanceField.Layout.Row = 4; app.IbmInstanceField.Layout.Column = 2;

    lbl = uilabel(ig, 'Text', Labels.get('settings_label_base_url'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 5; lbl.Layout.Column = 1;
    % Base URL loaded from AppState (which reads app.properties at startup)
    app.SettingsBaseUrlField = uieditfield(ig, 'text', 'Value', char(app.State.baseUrl));
    app.SettingsBaseUrlField.Layout.Row = 5; app.SettingsBaseUrlField.Layout.Column = 2;
    app.SettingsBaseUrlField.ValueChangedFcn = @(src,~)app.SettingsVm.onSettingsUrlChanged(src);

    app.VerifyIbmButton = uibutton(ig, 'Text', [char(10003) ' ' Labels.get('settings_btn_verify_ibm')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.onVerifyIbm());
    app.VerifyIbmButton.Layout.Row = 6; app.VerifyIbmButton.Layout.Column = [1 2];
    app.styleBtn(app.VerifyIbmButton, 'secondary');
    app.VerifyIbmButton.Tooltip = 'POST /api/settings/verify-ibm';

    help1 = uitextarea(ig, 'Editable', 'off'); help1.FontSize = 11;
    help1.Layout.Row = 7; help1.Layout.Column = [1 2]; help1.WordWrap = 'on';
    help1.Value = {Labels.get('settings_ibm_help', 'Credentials are stored locally for this session only.')};

    % ── Default Values (row 1, right) ─────────────────────────────────────────
    defaultPanel = uipanel(g, 'Title', Labels.get('settings_panel_defaults'));
    defaultPanel.Layout.Row = 1; defaultPanel.Layout.Column = 3; defaultPanel.BackgroundColor = [1 1 1];

    dg2 = uigridlayout(defaultPanel, [6 2]);
    dg2.RowHeight = {28,28,28,28,34,'1x'};
    dg2.ColumnWidth = {160,'1x'};
    dg2.Padding = [14 10 14 10]; dg2.RowSpacing = 5; dg2.BackgroundColor = [1 1 1];

    lbl = uilabel(dg2, 'Text', Labels.get('settings_label_default_shots'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.DefaultShotsField = uieditfield(dg2, 'numeric', 'Value', 4096);
    app.DefaultShotsField.Layout.Row = 1; app.DefaultShotsField.Layout.Column = 2;

    lbl = uilabel(dg2, 'Text', Labels.get('settings_label_default_opt'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.DefaultOptField = uieditfield(dg2, 'numeric', 'Value', 3);
    app.DefaultOptField.Layout.Row = 2; app.DefaultOptField.Layout.Column = 2;
    app.DefaultOptField.Limits = [0 3];

    lbl = uilabel(dg2, 'Text', Labels.get('settings_label_timeout'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    app.SettingsTimeoutField = uieditfield(dg2, 'numeric', 'Value', 120);
    app.SettingsTimeoutField.Layout.Row = 3; app.SettingsTimeoutField.Layout.Column = 2;

    lbl = uilabel(dg2, 'Text', Labels.get('settings_label_log_level'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 4; lbl.Layout.Column = 1;
    app.SettingsLogLevelDropdown = uidropdown(dg2, ...
        'Items', Labels.items('settings_log_level_items', {'debug','info','warning','error'}), ...
        'Value', Labels.get('settings_log_level_default', 'info'));
    app.SettingsLogLevelDropdown.Layout.Row = 4; app.SettingsLogLevelDropdown.Layout.Column = 2;

    app.SaveSettingsButton = uibutton(dg2, 'Text', [char(10004) ' ' Labels.get('settings_btn_save_settings')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.onSaveSettings());
    app.SaveSettingsButton.Layout.Row = 5; app.SaveSettingsButton.Layout.Column = [1 2];
    app.styleBtn(app.SaveSettingsButton, 'primary');

    app.SettingsStatusArea = uitextarea(dg2, 'Editable', 'off'); app.SettingsStatusArea.FontSize = 11;
    app.SettingsStatusArea.Layout.Row = 6; app.SettingsStatusArea.Layout.Column = [1 2];
    app.SettingsStatusArea.Value = {Labels.get('settings_default_help', 'Changes are applied immediately to the current session.')};

    % ── Notifications (row 2, left) ───────────────────────────────────────────
    notifPanel = uipanel(g, 'Title', Labels.get('settings_panel_notifications'));
    notifPanel.Layout.Row = 2; notifPanel.Layout.Column = 1; notifPanel.BackgroundColor = [1 1 1];

    ng = uigridlayout(notifPanel, [4 2]);
    ng.RowHeight = {28,28,28,'1x'};
    ng.ColumnWidth = {160,'1x'};
    ng.Padding = [14 10 14 10]; ng.RowSpacing = 5; ng.BackgroundColor = [1 1 1];

    lbl = uilabel(ng, 'Text', Labels.get('settings_label_notify_on_comp'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    app.EmailNotifyCheck = uicheckbox(ng, 'Text', '', 'Value', true);
    app.EmailNotifyCheck.Layout.Row = 1; app.EmailNotifyCheck.Layout.Column = 2;

    lbl = uilabel(ng, 'Text', Labels.get('settings_label_notify_email'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    app.NotifyEmailField = uieditfield(ng, 'text', 'Value', Labels.get('settings_default_notify_email', 'user@example.com'));
    app.NotifyEmailField.Layout.Row = 2; app.NotifyEmailField.Layout.Column = 2;

    lbl = uilabel(ng, 'Text', Labels.get('settings_label_alert_threshold'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    app.AlertThresholdDropdown = uidropdown(ng, ...
        'Items', Labels.items('settings_alert_items', {'All events','Errors only','Job completed','None'}), ...
        'Value', Labels.get('settings_alert_default', 'Job completed'));
    app.AlertThresholdDropdown.Layout.Row = 3; app.AlertThresholdDropdown.Layout.Column = 2;

    help2 = uitextarea(ng, 'Editable', 'off'); help2.FontSize = 11;
    help2.Layout.Row = 4; help2.Layout.Column = [1 2]; help2.WordWrap = 'on';
    help2.Value = {Labels.get('settings_notif_help', 'Notification settings apply to all job submissions in this session.')};

    % ── Display preferences (row 2, right) ───────────────────────────────────
    displayPanel = uipanel(g, 'Title', Labels.get('settings_panel_display'));
    displayPanel.Layout.Row = 2; displayPanel.Layout.Column = 3; displayPanel.BackgroundColor = [1 1 1];

    dpg = uigridlayout(displayPanel, [4 2]);
    dpg.RowHeight = {28,28,28,'1x'};
    dpg.ColumnWidth = {160,'1x'};
    dpg.Padding = [14 10 14 10]; dpg.RowSpacing = 5; dpg.BackgroundColor = [1 1 1];

    lbl = uilabel(dpg, 'Text', Labels.get('settings_label_theme'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    tmp = uidropdown(dpg, 'Items', Labels.items('settings_theme_items', {'Default','Dark','High Contrast'}), 'Value', 'Default');
    tmp.Layout.Row = 1; tmp.Layout.Column = 2;

    lbl = uilabel(dpg, 'Text', Labels.get('settings_label_date_format'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 2; lbl.Layout.Column = 1;
    tmp = uidropdown(dpg, 'Items', Labels.items('settings_date_format_items', {'YYYY-MM-DD','DD/MM/YYYY','MM-DD-YYYY'}), 'Value', 'YYYY-MM-DD');
    tmp.Layout.Row = 2; tmp.Layout.Column = 2;

    lbl = uilabel(dpg, 'Text', Labels.get('settings_label_compact_mode'));
    lbl.FontColor = [0.35 0.42 0.52];
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;
    tmp = uicheckbox(dpg, 'Text', ''); tmp.Layout.Row = 3; tmp.Layout.Column = 2;

    help4 = uitextarea(dpg, 'Editable', 'off'); help4.FontSize = 11;
    help4.Layout.Row = 4; help4.Layout.Column = [1 2]; help4.WordWrap = 'on';
    help4.Value = {Labels.get('settings_display_help', 'Visual preferences are applied on next session restart.')};

    % ── Developer Event Console (row 3, full width) ───────────────────────────
    consolePanel = uipanel(g, 'Title', Labels.get('settings_panel_console'));
    consolePanel.Layout.Row = 3; consolePanel.Layout.Column = [1 3]; consolePanel.BackgroundColor = [1 1 1];

    cpg = uigridlayout(consolePanel, [2 3]);
    cpg.RowHeight = {34,'1x'}; cpg.ColumnWidth = {'1x',120,150};
    cpg.Padding = [10 8 10 8]; cpg.RowSpacing = 5; cpg.BackgroundColor = [1 1 1];

    info = uilabel(cpg, 'Text', Labels.get('settings_console_desc'));
    info.FontSize = 11; info.FontColor = [0.38 0.46 0.58];
    info.Layout.Row = 1; info.Layout.Column = 1; info.WordWrap = 'on';

    clrBtn = uibutton(cpg, 'Text', [char(10005) ' ' Labels.get('settings_btn_clear_log')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.onClearLog());
    clrBtn.Layout.Row = 1; clrBtn.Layout.Column = 2; app.styleBtn(clrBtn, 'ghost');

    copyBtn = uibutton(cpg, 'Text', [char(9112) ' ' Labels.get('settings_btn_copy_log')]);
    copyBtn.Layout.Row = 1; copyBtn.Layout.Column = 3; app.styleBtn(copyBtn, 'ghost');
    copyBtn.ButtonPushedFcn = @(~,~)clipboard('copy', strjoin(app.EventLog, newline));

    app.EventLogArea = uitextarea(cpg, 'Editable', 'off');
    app.EventLogArea.Layout.Row = 2; app.EventLogArea.Layout.Column = [1 3];
    app.EventLogArea.FontName = 'Courier New'; app.EventLogArea.FontSize = 11;
    app.EventLogArea.BackgroundColor = [0.06 0.08 0.12];
    app.EventLogArea.FontColor = [0.72 0.94 0.64];
    app.EventLogArea.Value = {'[HH:MM:SS.mmm] UI      QTAUWorkbenchApp started'};

    % ── Action bar (row 4) ────────────────────────────────────────────────────
    bottom = uipanel(g, 'Title', '');
    bottom.Layout.Row = 4; bottom.Layout.Column = [1 3];
    bottom.BackgroundColor = [0.94 0.97 1.00]; bottom.BorderType = 'none';

    bg = uigridlayout(bottom, [1 3]);
    bg.RowHeight = {34}; bg.ColumnWidth = {'1x', 170, 190};
    bg.Padding = [8 8 8 8]; bg.BackgroundColor = [0.94 0.97 1.00];
    desc = uilabel(bg, 'Text', Labels.get('settings_panel_action_label'));
    desc.FontSize = 13; desc.FontWeight = 'bold'; desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    tmp = uibutton(bg, 'Text', [char(8634) ' ' Labels.get('settings_btn_reset_defaults')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.onResetSettings());
    tmp.Layout.Row = 1; tmp.Layout.Column = 2; app.styleBtn(tmp, 'ghost');
    tmp = uibutton(bg, 'Text', [char(10005) ' ' Labels.get('settings_btn_clear_cache')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.onClearServerCache());
    tmp.Layout.Row = 1; tmp.Layout.Column = 3; app.styleBtn(tmp, 'secondary');
    tmp.Tooltip = 'DELETE /api/settings/cache';

    Logger.info('SettingsScreen', 'Settings tab UI built successfully');
end
