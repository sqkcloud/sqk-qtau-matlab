% buildResultsTab  Populates the Results section panel.
%
%   Layout (3-column grid, 3 rows):
%     Row 1:      Results Analysis card (KPI cards) spanning all columns.
%     Row 2, Col 1: Measured vs Predicted Summary table + execution notes.
%     Row 2, Col 2: 6 px resizable divider.
%     Row 2, Col 3: Distribution Review table + action notes.
%     Row 3:      Full-width action bar (Next: Detailed Analysis / Back: Jobs).
function buildResultsTab(app)
    t = app.createSectionPage('Results');

    % ── Root grid: 3 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {120, '1x', 72};
    g.ColumnWidth   = {'1.15x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Results KPI cards (full width) ───────────────────────────────────────
    % Four metric cards mirror the Dashboard KPI pattern for visual consistency.
    hero=uipanel(g,'Title','Results Analysis');
    hero.Layout.Row=1; hero.Layout.Column=[1 3]; hero.BackgroundColor=[1 1 1];

    hg=uigridlayout(hero,[2 4]);
    hg.RowHeight={26,'1x'};
    hg.ColumnWidth={'1x','1x','1x','1x'};
    hg.Padding=[16 12 16 12];
    hg.BackgroundColor=[1 1 1];

    titleLabel=uilabel(hg,'Text','Compare measured outcomes against ideal and predicted behavior');
    titleLabel.FontSize=15; titleLabel.FontWeight='bold';
    titleLabel.Layout.Row=1; titleLabel.Layout.Column=[1 4]; titleLabel.WordWrap='on';

    cards={ ...
        'Measured fidelity','0.947',[0.18 0.45 0.82]; ...
        'Predicted fidelity','0.963 ± 0.012',[0.10 0.54 0.36]; ...
        'Ideal overlap','0.982',[0.62 0.38 0.82]; ...
        'Validation status','Within tolerance',[0.75 0.48 0.10]};
    for i=1:4
        p=uipanel(hg,'Title',''); p.Layout.Row=2; p.Layout.Column=i;
        p.BackgroundColor=[0.96 0.97 0.99];
        pg=uigridlayout(p,[1 2]); pg.ColumnWidth={5,'1x'}; pg.Padding=[0 0 0 0];
        pg.ColumnSpacing=0; pg.BackgroundColor=[0.96 0.97 0.99];
        strip=uipanel(pg,'Title',''); strip.Layout.Row=1; strip.Layout.Column=1;
        strip.BackgroundColor=cards{i,3};
        inner=uigridlayout(pg,[2 1]); inner.Layout.Row=1; inner.Layout.Column=2;
        inner.RowHeight={18,'1x'}; inner.Padding=[8 8 8 8]; inner.BackgroundColor=[0.96 0.97 0.99];
        uilabel(inner,'Text',cards{i,1},'FontSize',11,'FontColor',[0.38 0.46 0.58]);
        uilabel(inner,'Text',cards{i,2},'FontWeight','bold','FontSize',17,'WordWrap','on');
    end

    % ── Column divider ────────────────────────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=2; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Measured vs Predicted Summary (left panel) ────────────────────────────
    summaryPanel=uipanel(g,'Title','Measured vs Predicted Summary');
    summaryPanel.Layout.Row=2; summaryPanel.Layout.Column=1; summaryPanel.BackgroundColor=[1 1 1];

    sg=uigridlayout(summaryPanel,[2 1]);
    sg.RowHeight={'1x',122};
    sg.Padding=[12 10 12 10];
    sg.BackgroundColor=[1 1 1];

    app.ResultsTable=uitable(sg);
    app.ResultsTable.ColumnName={'Metric','Measured','Predicted','Ideal','Notes'};
    app.ResultsTable.Data={ ...
        'Success probability',0.941,0.952,1.000,'Close to model'; ...
        'Dominant state mass',0.760,0.774,0.801,'Minor readout loss'; ...
        'Two-qubit error impact',0.041,0.038,0.000,'Slightly above expectation'; ...
        'Readout contribution',0.034,0.032,0.000,'Stable'};
    app.styleTable(app.ResultsTable);

    % Execution notes below the table
    app.ResultJsonArea=uitextarea(sg,'Editable','off');
    app.ResultJsonArea.Layout.Row=2; app.ResultJsonArea.FontSize=12;
    app.ResultJsonArea.Value={ ...
        'Execution summary', ...
        '- Backend: ibm_brisbane', ...
        '- Job ID: job-001', ...
        '- Status: completed', ...
        '- Predicted vs measured agreement: acceptable', ...
        '- Export raw data or continue to detailed analysis'};

    % ── Distribution Review (right panel) ────────────────────────────────────
    comparePanel=uipanel(g,'Title','Distribution Review');
    comparePanel.Layout.Row=2; comparePanel.Layout.Column=3; comparePanel.BackgroundColor=[1 1 1];

    cg=uigridlayout(comparePanel,[2 1]);
    cg.RowHeight={'1x',104};
    cg.Padding=[12 10 12 10];
    cg.BackgroundColor=[1 1 1];

    topTable=uitable(cg);
    topTable.ColumnName={'State','Measured','Predicted','Ideal'};
    topTable.Data={ ...
        '000000...',0.760,0.774,0.801; ...
        '000001...',0.083,0.078,0.061; ...
        '100000...',0.052,0.049,0.041; ...
        'other',0.105,0.099,0.097};
    app.styleTable(topTable);

    notes=uitextarea(cg,'Editable','off'); notes.Layout.Row=2; notes.FontSize=12;
    notes.Value={ ...
        'Storyboard actions represented:', ...
        '- Review execution summary', ...
        '- Compare measured vs ideal distributions', ...
        '- Validate against prior predictions', ...
        '- Export raw result data'};

    % ── Action bar ────────────────────────────────────────────────────────────
    bottom=uipanel(g,'Title','Next Step');
    bottom.Layout.Row=3; bottom.Layout.Column=[1 3];
    bottom.BackgroundColor=[0.94 0.97 1.00];

    bg=uigridlayout(bottom,[1 3]);
    bg.ColumnWidth={'1x',195,150};
    bg.Padding=[14 8 14 8];
    bg.BackgroundColor=[0.94 0.97 1.00];

    desc=uilabel(bg,'Text','Use this screen to decide whether the run is good enough or whether deeper investigation is needed.');
    desc.FontSize=13; desc.FontWeight='bold'; desc.Layout.Row=1; desc.Layout.Column=1;
    desc.VerticalAlignment='center'; desc.WordWrap='on';
    tmp=uibutton(bg,'Text','Next: Detailed Analysis', ...
        'ButtonPushedFcn',@(~,~)app.onSelectSection('Detailed Analysis'));
    tmp.Layout.Row=1; tmp.Layout.Column=2; app.styleBtn(tmp,'primary');
    tmp=uibutton(bg,'Text','Back: Jobs','ButtonPushedFcn',@(~,~)app.onSelectSection('Jobs'));
    tmp.Layout.Row=1; tmp.Layout.Column=3; app.styleBtn(tmp,'ghost');
end
