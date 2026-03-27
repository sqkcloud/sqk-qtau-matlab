% buildBackendsTab  Populates the Backends section panel.
%
%   Layout (3-column grid, 3 rows):
%     Row 1:      Backend Explorer card spanning all columns — 4 summary metrics.
%     Row 2, Col 1: Available Backends table with refresh and select buttons.
%     Row 2, Col 2: 6 px resizable divider.
%     Row 2, Col 3: Calibration and Selection Notes text area.
%     Row 3:      Full-width action bar (Next: Benchmark / Back: Analysis).
function buildBackendsTab(app)
    t = app.createSectionPage('Backends');

    % ── Root grid: 3 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {118, '1x', 72};
    g.ColumnWidth   = {'1.3x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Backend summary cards (full width) ────────────────────────────────────
    % Four cards mirror the KPI card pattern from the Dashboard, showing the
    % most important backend selection signals at a glance.
    cards=uipanel(g,'Title','Backend Explorer & Selection');
    cards.Layout.Row=1; cards.Layout.Column=[1 3]; cards.BackgroundColor=[1 1 1];

    cg=uigridlayout(cards,[2 4]);
    cg.RowHeight={26,'1x'};
    cg.ColumnWidth={'1x','1x','1x','1x'};
    cg.Padding=[16 12 16 12];
    cg.BackgroundColor=[1 1 1];

    ttl=uilabel(cg,'Text','Browse live backends, compare predicted fidelity, and choose primary/backup systems');
    ttl.FontSize=15; ttl.FontWeight='bold'; ttl.Layout.Row=1; ttl.Layout.Column=[1 4]; ttl.WordWrap='on';

    names={'Recommended Primary','Recommended Backup','Best Predicted Fidelity','Current Calibration Age'};
    vals={'ibm_brisbane','ibm_kyiv','0.963','2.4 hours'};
    accents={[0.18 0.45 0.82],[0.28 0.48 0.72],[0.10 0.54 0.36],[0.62 0.38 0.82]};
    for i=1:4
        p=uipanel(cg,'Title',''); p.Layout.Row=2; p.Layout.Column=i;
        p.BackgroundColor=[0.96 0.97 0.99];
        pg=uigridlayout(p,[1 2]); pg.ColumnWidth={5,'1x'}; pg.Padding=[0 0 0 0];
        pg.ColumnSpacing=0; pg.BackgroundColor=[0.96 0.97 0.99];
        strip=uipanel(pg,'Title',''); strip.Layout.Row=1; strip.Layout.Column=1;
        strip.BackgroundColor=accents{i};
        inner=uigridlayout(pg,[2 1]); inner.Layout.Row=1; inner.Layout.Column=2;
        inner.RowHeight={18,'1x'}; inner.Padding=[8 8 8 8]; inner.BackgroundColor=[0.96 0.97 0.99];
        uilabel(inner,'Text',names{i},'FontColor',[0.38 0.46 0.58],'FontSize',11);
        uilabel(inner,'Text',vals{i},'FontWeight','bold','FontSize',17,'WordWrap','on');
    end

    % ── Column divider ────────────────────────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=2; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Available Backends table (left panel) ─────────────────────────────────
    tablePanel=uipanel(g,'Title','Available Backends');
    tablePanel.Layout.Row=2; tablePanel.Layout.Column=1; tablePanel.BackgroundColor=[1 1 1];

    tg=uigridlayout(tablePanel,[2 1]);
    tg.RowHeight={44,'1x'};
    tg.Padding=[12 10 12 10];
    tg.BackgroundColor=[1 1 1];

    % Top toolbar: refresh and select buttons
    top=uigridlayout(tg,[1 2]);
    top.ColumnWidth={'1x','1x'}; top.Padding=[0 0 0 0]; top.BackgroundColor=[1 1 1];
    app.RefreshBackendsButton=uibutton(top,'Text','Refresh Backends', ...
        'ButtonPushedFcn',@(~,~)app.onRefreshBackends());
    app.styleBtn(app.RefreshBackendsButton,'ghost');
    app.RefreshBackendsButton.Tooltip='Fetch live backend list from /api/backends';
    app.SelectBackendButton=uibutton(top,'Text','Select Highlighted Backend', ...
        'ButtonPushedFcn',@(~,~)app.onSelectBackend());
    app.styleBtn(app.SelectBackendButton,'primary');
    app.SelectBackendButton.Tooltip='Set the selected backend as primary target';

    % Backend comparison table
    app.BackendTable=uitable(tg);
    app.BackendTable.ColumnName={'Name','Qubits','Status','Predicted fidelity','Queue','Role'};
    app.BackendTable.Data={ ...
        'ibm_brisbane',127,'online',0.963,'short','primary candidate'; ...
        'ibm_kyiv',127,'online',0.954,'medium','backup candidate'; ...
        'ibm_sherbrooke',127,'busy',0.949,'long','stable alternative'};
    app.styleTable(app.BackendTable);

    % ── Calibration notes (right panel) ──────────────────────────────────────
    detailPanel=uipanel(g,'Title','Calibration and Selection Notes');
    detailPanel.Layout.Row=2; detailPanel.Layout.Column=3; detailPanel.BackgroundColor=[1 1 1];

    dg2=uigridlayout(detailPanel,[1 1]);
    dg2.Padding=[12 10 12 10]; dg2.BackgroundColor=[1 1 1];
    app.BackendStatusArea=uitextarea(dg2,'Editable','off'); app.BackendStatusArea.FontSize=12;
    app.BackendStatusArea.Value={ ...
        'ibm_brisbane', ...
        '- 127 qubits, online', ...
        '- Predicted fidelity for current circuit: 0.963', ...
        '- Best tradeoff across queue length and calibration freshness', ...
        '', ...
        'ibm_kyiv', ...
        '- Backup selection with slightly lower fidelity but similar qubit count'};

    % ── Action bar ────────────────────────────────────────────────────────────
    nextPanel=uipanel(g,'Title','Proceed to Benchmark Configuration');
    nextPanel.Layout.Row=3; nextPanel.Layout.Column=[1 3];
    nextPanel.BackgroundColor=[0.94 0.97 1.00];

    ng=uigridlayout(nextPanel,[1 3]);
    ng.ColumnWidth={'1x',175,150};
    ng.Padding=[14 8 14 8];
    ng.BackgroundColor=[0.94 0.97 1.00];

    desc=uilabel(ng,'Text','Browse backends, review predicted fidelity, select primary/backup, then configure benchmarking.');
    desc.FontSize=13; desc.FontWeight='bold'; desc.Layout.Row=1; desc.Layout.Column=1;
    desc.VerticalAlignment='center'; desc.WordWrap='on';
    tmp=uibutton(ng,'Text','Next: Benchmark','ButtonPushedFcn',@(~,~)app.onSelectSection('Benchmark'));
    tmp.Layout.Row=1; tmp.Layout.Column=2; app.styleBtn(tmp,'primary');
    tmp=uibutton(ng,'Text','Back: Analysis','ButtonPushedFcn',@(~,~)app.onSelectSection('Analysis'));
    tmp.Layout.Row=1; tmp.Layout.Column=3; app.styleBtn(tmp,'ghost');
end
