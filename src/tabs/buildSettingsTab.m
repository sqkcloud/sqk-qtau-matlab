% buildSettingsTab  Populates the Settings section panel.
%
%   Single 4-row grid sized to fit the standard 940 px window without
%   scrolling, so the action bar (Reset All to Defaults) is always visible:
%
%     Row 1 (258 px): IBM Quantum Account | Default Values.
%     Row 2 (178 px): Notifications       | Display.
%     Row 3 (168 px): Developer Event Console (full width).
%     Row 4 ( 52 px): Action bar — pinned at the bottom.
%     Col 2 (  6 px): Resizable divider spanning rows 1-2.
%
%   Total content height: 258+178+168+52 + 3×12 spacing + 2×16 padding
%   = 656 + 36 + 32 = 724 px — fits inside the ~750 px content area.
function buildSettingsTab(app)
    t = app.createSectionPage('Settings');

    % ── Root grid (single level — no outer wrapper needed) ────────────────────
    g = uigridlayout(t, [4 3]);
    g.RowHeight     = {258, 178, 168, 52};  % all fixed; sums to 724 px
    g.ColumnWidth   = {'1x', 6, '1.05x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Column divider (spans rows 1-2 only) ──────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=[1 2]; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── IBM Quantum Account (row 1, left) ─────────────────────────────────────
    ibmPanel=uipanel(g,'Title','IBM Quantum Account');
    ibmPanel.Layout.Row=1; ibmPanel.Layout.Column=1; ibmPanel.BackgroundColor=[1 1 1];

    ig=uigridlayout(ibmPanel,[6 2]);
    ig.RowHeight={28,28,28,28,28,'1x'};     % 5 compact form rows + flex hint
    ig.ColumnWidth={150,'1x'};
    ig.Padding=[14 10 14 10];
    ig.RowSpacing=5;
    ig.BackgroundColor=[1 1 1];

    tmp=uilabel(ig,'Text','IBM Account Email'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=1; tmp.Layout.Column=1;
    app.IbmEmailField=uieditfield(ig,'text','Value','user@ibm.com');
    app.IbmEmailField.Layout.Row=1; app.IbmEmailField.Layout.Column=2;

    tmp=uilabel(ig,'Text','API Token'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=2; tmp.Layout.Column=1;
    tmp=uieditfield(ig,'text','Value','****-****-****');
    tmp.Layout.Row=2; tmp.Layout.Column=2;

    tmp=uilabel(ig,'Text','Channel'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=3; tmp.Layout.Column=1;
    tmp=uidropdown(ig,'Items',{'ibm_quantum','ibm_cloud'},'Value','ibm_quantum');
    tmp.Layout.Row=3; tmp.Layout.Column=2;

    tmp=uilabel(ig,'Text','Instance'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=4; tmp.Layout.Column=1;
    tmp=uieditfield(ig,'text','Value','ibm-q/open/main');
    tmp.Layout.Row=4; tmp.Layout.Column=2;

    tmp=uilabel(ig,'Text','Hub / Group'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=5; tmp.Layout.Column=1;
    tmp=uieditfield(ig,'text','Value','ibm-q / open / main');
    tmp.Layout.Row=5; tmp.Layout.Column=2;

    % Flex row — session disclaimer, shrinks gracefully on small windows
    help1=uitextarea(ig,'Editable','off'); help1.FontSize=11;
    help1.Layout.Row=6; help1.Layout.Column=[1 2]; help1.WordWrap='on';
    help1.Value={'Credentials are stored locally for this session only.'};

    % ── Notifications (row 2, left) ───────────────────────────────────────────
    notifPanel=uipanel(g,'Title','Notifications');
    notifPanel.Layout.Row=2; notifPanel.Layout.Column=1; notifPanel.BackgroundColor=[1 1 1];

    ng=uigridlayout(notifPanel,[4 2]);
    ng.RowHeight={28,28,28,'1x'};
    ng.ColumnWidth={160,'1x'};
    ng.Padding=[14 10 14 10];
    ng.RowSpacing=5;
    ng.BackgroundColor=[1 1 1];

    tmp=uilabel(ng,'Text','Notify on completion'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=1; tmp.Layout.Column=1;
    tmp=uicheckbox(ng,'Text','','Value',true); tmp.Layout.Row=1; tmp.Layout.Column=2;

    tmp=uilabel(ng,'Text','Notification email'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=2; tmp.Layout.Column=1;
    tmp=uieditfield(ng,'text','Value','user@example.com');
    tmp.Layout.Row=2; tmp.Layout.Column=2;

    tmp=uilabel(ng,'Text','Alert threshold'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=3; tmp.Layout.Column=1;
    tmp=uidropdown(ng,'Items',{'All events','Errors only','Job completed','None'}, ...
        'Value','Job completed');
    tmp.Layout.Row=3; tmp.Layout.Column=2;

    help2=uitextarea(ng,'Editable','off'); help2.FontSize=11;
    help2.Layout.Row=4; help2.Layout.Column=[1 2]; help2.WordWrap='on';
    help2.Value={'Notification settings apply to all job submissions in this session.'};

    % ── Default Values (row 1, right) ────────────────────────────────────────
    defaultPanel=uipanel(g,'Title','Default Values');
    defaultPanel.Layout.Row=1; defaultPanel.Layout.Column=3; defaultPanel.BackgroundColor=[1 1 1];

    dg2=uigridlayout(defaultPanel,[6 2]);
    dg2.RowHeight={28,28,28,28,34,'1x'};    % save button 34 px; flex hint at bottom
    dg2.ColumnWidth={160,'1x'};
    dg2.Padding=[14 10 14 10];
    dg2.RowSpacing=5;
    dg2.BackgroundColor=[1 1 1];

    tmp=uilabel(dg2,'Text','Default shots'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=1; tmp.Layout.Column=1;
    tmp=uieditfield(dg2,'numeric','Value',4096); tmp.Layout.Row=1; tmp.Layout.Column=2;

    tmp=uilabel(dg2,'Text','Default opt level'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=2; tmp.Layout.Column=1;
    tmp=uieditfield(dg2,'numeric','Value',3); tmp.Layout.Row=2; tmp.Layout.Column=2;

    tmp=uilabel(dg2,'Text','Timeout (s)'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=3; tmp.Layout.Column=1;
    tmp=uieditfield(dg2,'numeric','Value',120); tmp.Layout.Row=3; tmp.Layout.Column=2;

    tmp=uilabel(dg2,'Text','Log level'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=4; tmp.Layout.Column=1;
    tmp=uidropdown(dg2,'Items',{'debug','info','warning','error'},'Value','info');
    tmp.Layout.Row=4; tmp.Layout.Column=2;

    % Save Settings button — 34 px fixed height, spans both columns
    app.SaveSettingsButton=uibutton(dg2,'Text','Save Settings', ...
        'ButtonPushedFcn',@(~,~)app.onSaveSettings());
    app.SaveSettingsButton.Layout.Row=5; app.SaveSettingsButton.Layout.Column=[1 2];
    app.styleBtn(app.SaveSettingsButton,'primary');

    help3=uitextarea(dg2,'Editable','off'); help3.FontSize=11;
    help3.Layout.Row=6; help3.Layout.Column=[1 2]; help3.WordWrap='on';
    help3.Value={'Changes are applied immediately to the current session.'};

    % ── Display preferences (row 2, right) ────────────────────────────────────
    displayPanel=uipanel(g,'Title','Display');
    displayPanel.Layout.Row=2; displayPanel.Layout.Column=3; displayPanel.BackgroundColor=[1 1 1];

    dpg=uigridlayout(displayPanel,[4 2]);
    dpg.RowHeight={28,28,28,'1x'};
    dpg.ColumnWidth={160,'1x'};
    dpg.Padding=[14 10 14 10];
    dpg.RowSpacing=5;
    dpg.BackgroundColor=[1 1 1];

    tmp=uilabel(dpg,'Text','Theme'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=1; tmp.Layout.Column=1;
    tmp=uidropdown(dpg,'Items',{'Default','Dark','High Contrast'},'Value','Default');
    tmp.Layout.Row=1; tmp.Layout.Column=2;

    tmp=uilabel(dpg,'Text','Date format'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=2; tmp.Layout.Column=1;
    tmp=uidropdown(dpg,'Items',{'YYYY-MM-DD','DD/MM/YYYY','MM-DD-YYYY'},'Value','YYYY-MM-DD');
    tmp.Layout.Row=2; tmp.Layout.Column=2;

    tmp=uilabel(dpg,'Text','Compact mode'); tmp.FontColor=[0.35 0.42 0.52];
    tmp.Layout.Row=3; tmp.Layout.Column=1;
    tmp=uicheckbox(dpg,'Text',''); tmp.Layout.Row=3; tmp.Layout.Column=2;

    help4=uitextarea(dpg,'Editable','off'); help4.FontSize=11;
    help4.Layout.Row=4; help4.Layout.Column=[1 2]; help4.WordWrap='on';
    help4.Value={'Visual preferences are applied on next session restart.'};

    % ── Developer Event Console (row 3, full width) ───────────────────────────
    consolePanel=uipanel(g,'Title','Developer Event Console');
    consolePanel.Layout.Row=3; consolePanel.Layout.Column=[1 3]; consolePanel.BackgroundColor=[1 1 1];

    cpg=uigridlayout(consolePanel,[2 3]);
    cpg.RowHeight={30,'1x'};
    cpg.ColumnWidth={'1x',120,150};
    cpg.Padding=[10 8 10 8];
    cpg.RowSpacing=5;
    cpg.BackgroundColor=[1 1 1];

    info=uilabel(cpg,'Text','Live event log (newest first) — mirrored to MATLAB Command Window');
    info.FontSize=11; info.FontColor=[0.38 0.46 0.58];
    info.Layout.Row=1; info.Layout.Column=1; info.WordWrap='on';

    clrBtn=uibutton(cpg,'Text','Clear Log','ButtonPushedFcn',@(~,~)app.onClearLog());
    clrBtn.Layout.Row=1; clrBtn.Layout.Column=2; app.styleBtn(clrBtn,'ghost');

    copyBtn=uibutton(cpg,'Text','Copy to Clipboard');
    copyBtn.Layout.Row=1; copyBtn.Layout.Column=3; app.styleBtn(copyBtn,'ghost');
    copyBtn.ButtonPushedFcn = @(~,~)clipboard('copy', strjoin(app.EventLog, newline));

    app.EventLogArea=uitextarea(cpg,'Editable','off');
    app.EventLogArea.Layout.Row=2; app.EventLogArea.Layout.Column=[1 3];
    app.EventLogArea.FontName='Courier New'; app.EventLogArea.FontSize=11;
    app.EventLogArea.BackgroundColor=[0.06 0.08 0.12];
    app.EventLogArea.FontColor=[0.72 0.94 0.64];
    app.EventLogArea.Value={'[HH:MM:SS.mmm] UI      QTAUApp started — storyboard mode active'};

    % ── Action bar (row 4, full width) ────────────────────────────────────────
    % Row height is fixed at 52 px; the button inside is capped at 36 px via
    % RowHeight so it always renders at the same size as buttons on other screens.
    bottom=uipanel(g,'Title','');
    bottom.Layout.Row=4; bottom.Layout.Column=[1 3];
    bottom.BackgroundColor=[0.94 0.97 1.00]; bottom.BorderType='none';

    bg=uigridlayout(bottom,[1 2]);
    bg.RowHeight={36};              % standard button height — matches rest of app
    bg.ColumnWidth={'1x',170};
    bg.Padding=[8 8 8 8];
    bg.BackgroundColor=[0.94 0.97 1.00];

    desc=uilabel(bg,'Text','All settings are applied immediately to the current session profile.');
    desc.FontSize=13; desc.FontWeight='bold'; desc.Layout.Row=1; desc.Layout.Column=1;
    desc.VerticalAlignment='center'; desc.WordWrap='on';
    tmp=uibutton(bg,'Text','Reset All to Defaults');
    tmp.Layout.Row=1; tmp.Layout.Column=2; app.styleBtn(tmp,'ghost');
end
