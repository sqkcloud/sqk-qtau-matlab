% SettingsScreen  Populates the Settings section panel.
%
%   Layout (3 rows):
%     Row 1 ( 44 px): 4 category buttons (IBM / Defaults / Notifications / Display).
%     Row 2 ('1x'):   Developer Event Console (fills remaining vertical space).
%     Row 3 ( 52 px): Action bar — Reset Defaults / Clear Server Cache.
%
%   All three rows share ColumnSpacing = 8, button RowHeight = 34, and a
%   leftmost '1x' spacer column so every right-aligned button lands on the
%   same vertical line. Row 1 is tighter (44 vs 52) so the toolbar sits
%   close to the outline top and the console starts just below.
%
%   Each category button opens a modal dialog (see SettingsViewModel/open*Dialog)
%   where the corresponding fields, Save/Verify, and Close buttons live. UI
%   field properties on the app (IbmApiTokenField, DefaultShotsField, etc.)
%   are created on-demand by the dialog and torn down to [] when it closes.
%   Session values are cached in SettingsViewModel.Values between opens.
%
%   Category icons (kept constant across the app so any screen that exposes
%   the same concept can reuse the glyph):
%     ⚛  (char 9883)  IBM Quantum Account
%     ⚙  (char 9881)  Default Values
%     ✉  (char 9993)  Notifications
%     ☼  (char 9788)  Display
function SettingsScreen(app)
    Logger.info('SettingsScreen', 'Building Settings tab UI');
    t = app.createSectionPage('Settings');

    g = uigridlayout(t, [3 1]);
    g.RowHeight     = {44, '1x', 52};
    g.ColumnWidth   = {'1x'};
    % Padding = [left bottom right top]. Top is tighter so the button row
    % sits closer to the outline border.
    g.Padding       = [16 16 16 6];
    g.RowSpacing    = 4;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Row 1: four category buttons (uniform width, right-aligned) ───────────
    btnPanel = uipanel(g, 'Title', '');
    btnPanel.Layout.Row = 1; btnPanel.BorderType = 'none';
    btnPanel.BackgroundColor = Theme.COLOR_BG;

    % Col 1 ('1x') is a flexible spacer that pushes the 4 fixed-width buttons
    % to the right edge, sharing the inset of the action bar below so all
    % three right-aligned groups (this row, console toolbar, action bar)
    % land on the same vertical line.
    BTN_W = 180;  % uniform button width across all 4 categories
    bg = uigridlayout(btnPanel, [1 5]);
    bg.RowHeight     = {34};
    bg.ColumnWidth   = {'1x', BTN_W, BTN_W, BTN_W, BTN_W};
    bg.ColumnSpacing = 8;
    % Tight vertical padding — the outer grid already handles the gap from
    % the section outline; this panel just centers the buttons in their row.
    bg.Padding       = [8 4 8 4];
    bg.BackgroundColor = Theme.COLOR_BG;

    btnIbm = uibutton(bg, ...
        'Text', [char(9883) '  ' Labels.get('settings_panel_ibm_account')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.openIbmDialog());
    btnIbm.Layout.Row = 1; btnIbm.Layout.Column = 2;
    app.styleBtn(btnIbm, 'secondary');

    btnDef = uibutton(bg, ...
        'Text', [char(9881) '  ' Labels.get('settings_panel_defaults')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.openDefaultsDialog());
    btnDef.Layout.Row = 1; btnDef.Layout.Column = 3;
    app.styleBtn(btnDef, 'secondary');

    btnNot = uibutton(bg, ...
        'Text', [char(9993) '  ' Labels.get('settings_panel_notifications')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.openNotificationsDialog());
    btnNot.Layout.Row = 1; btnNot.Layout.Column = 4;
    app.styleBtn(btnNot, 'secondary');

    btnDisp = uibutton(bg, ...
        'Text', [char(9788) '  ' Labels.get('settings_panel_display')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.openDisplayDialog());
    btnDisp.Layout.Row = 1; btnDisp.Layout.Column = 5;
    app.styleBtn(btnDisp, 'secondary');

    % Field properties are dialog-scoped — clear any stale handles from a
    % prior build so VM guards (isempty/isvalid) behave.
    app.IbmEmailField              = [];
    app.IbmApiTokenField           = [];
    app.IbmChannelDropdown         = [];
    app.IbmInstanceField           = [];
    app.SettingsBaseUrlField       = [];
    app.DefaultShotsField          = [];
    app.DefaultOptField            = [];
    app.SettingsTimeoutField       = [];
    app.SettingsLogLevelDropdown   = [];
    app.EmailNotifyCheck           = [];
    app.NotifyEmailField           = [];
    app.AlertThresholdDropdown     = [];
    app.SaveSettingsButton         = [];
    app.VerifyIbmButton            = [];
    app.SettingsStatusArea         = [];
    app.ServerIbmStatusArea        = [];

    % ── Row 2: Developer Event Console ────────────────────────────────────────
    consolePanel = uipanel(g, 'Title', Labels.get('settings_panel_console'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    consolePanel.Layout.Row = 2; consolePanel.BackgroundColor = Theme.COLOR_CARD;

    cpg = uigridlayout(consolePanel, [2 3]);
    cpg.RowHeight = {34,'1x'}; cpg.ColumnWidth = {'1x',160,160};
    cpg.Padding = [8 8 8 8]; cpg.RowSpacing = 8; cpg.BackgroundColor = Theme.COLOR_CARD;

    info = uilabel(cpg, 'Text', Labels.get('settings_console_desc'));
    info.FontSize = 11; info.FontColor = Theme.COLOR_MUTED;
    info.VerticalAlignment = 'center';
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
    app.EventLogArea.BackgroundColor = Theme.CONSOLE_BG;
    app.EventLogArea.FontColor = Theme.CONSOLE_FG;
    %  Disable word-wrap so long log lines (POST bodies, full-UUID
    %  payload dumps) don't soft-wrap into a multi-line tangle that's
    %  harder to scan. WordWrap='off' makes uitextarea show a
    %  horizontal scrollbar for overflowing lines instead. Vertical
    %  scrolling between log entries is native to uitextarea and
    %  unaffected by this property.
    app.EventLogArea.WordWrap = 'off';
    app.EventLogArea.Value = {'[HH:MM:SS.mmm] UI      QTAUWorkbenchApp started'};

    % ── Row 3: Action bar ─────────────────────────────────────────────────────
    bottom = uipanel(g, 'Title', '', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    bottom.Layout.Row = 3;
    bottom.BackgroundColor = Theme.COLOR_CARD;

    abg = uigridlayout(bottom, [1 3]);
    abg.RowHeight = {34}; abg.ColumnWidth = {'1x', 180, 180};
    abg.ColumnSpacing = 8;
    abg.Padding = [8 8 8 8]; abg.BackgroundColor = Theme.COLOR_CARD;
    desc = uilabel(abg, 'Text', Labels.get('settings_panel_action_label'));
    desc.FontSize = 13; desc.FontWeight = 'bold';
    desc.Layout.Row = 1; desc.Layout.Column = 1;
    desc.VerticalAlignment = 'center'; desc.WordWrap = 'on';
    resetBtn = uibutton(abg, 'Text', [char(8634) ' ' Labels.get('settings_btn_reset_defaults')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.onResetSettings());
    resetBtn.Layout.Row = 1; resetBtn.Layout.Column = 2; app.styleBtn(resetBtn, 'ghost');
    cacheBtn = uibutton(abg, 'Text', [char(10005) ' ' Labels.get('settings_btn_clear_cache')], ...
        'ButtonPushedFcn', @(~,~)app.SettingsVm.onClearServerCache());
    cacheBtn.Layout.Row = 1; cacheBtn.Layout.Column = 3; app.styleBtn(cacheBtn, 'secondary');
    cacheBtn.Tooltip = 'Clear locally cached data';

    Logger.info('SettingsScreen', 'Settings tab UI built successfully');
end
