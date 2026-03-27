% buildAnalysisTab  Populates the Analysis section panel.
%
%   Layout (3-column grid, 3 rows):
%     Row 1:      Full-width Analyze button.
%     Row 2, Col 1: Extracted Circuit Features tree + annotation text.
%     Row 2, Col 2: 6 px resizable divider.
%     Row 2, Col 3: QASMBench Similarity Results table + comparison notes.
%     Row 3:      Full-width action bar (Next: Backends / Back: Upload).
function buildAnalysisTab(app)
    t = app.createSectionPage('Analysis');

    % ── Root grid: 3 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {44, '1x', 72};
    g.ColumnWidth   = {'1x', 6, '1.15x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % Primary action button spanning all columns
    app.AnalyzeButton=uibutton(g,'Text','Analyze Circuit', ...
        'ButtonPushedFcn',@(~,~)app.onAnalyzeCircuit());
    app.AnalyzeButton.Layout.Row=1; app.AnalyzeButton.Layout.Column=[1 3];
    app.styleBtn(app.AnalyzeButton,'primary');
    app.AnalyzeButton.Tooltip='Extract circuit features and run QASMBench similarity search';

    % ── Column divider ────────────────────────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=2; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Extracted Features (left panel) ──────────────────────────────────────
    % Tree widget shows the hierarchical circuit feature breakdown (structure,
    % gate counts, quantum metrics).  The right sub-column holds a text summary.
    p1=uipanel(g,'Title','Extracted Circuit Features');
    p1.Layout.Row=2; p1.Layout.Column=1; p1.BackgroundColor=[1 1 1];

    g1=uigridlayout(p1,[1 2]);
    g1.ColumnWidth={'1x',192};
    g1.Padding=[12 10 12 10];
    g1.BackgroundColor=[1 1 1];

    app.FeatureTree=uitree(g1); app.FeatureTree.FontSize=12;
    root=uitreenode(app.FeatureTree,'Text','bernstein_vazirani_27');
    arch=uitreenode(root,'Text','Structure');
        uitreenode(arch,'Text','Depth: 128');
        uitreenode(arch,'Text','Width: 27 qubits');
        uitreenode(arch,'Text','Entangling layers: 18');
    gates=uitreenode(root,'Text','Gate counts');
        uitreenode(gates,'Text','Single-qubit: 81');
        uitreenode(gates,'Text','Two-qubit: 54');
        uitreenode(gates,'Text','Measurement: 27');
    qf=uitreenode(root,'Text','Quantum features');
        uitreenode(qf,'Text','Parallelism score: 0.71');
        uitreenode(qf,'Text','Coupling pressure: medium');
    expand(root); expand(arch); expand(gates); expand(qf);

    % Feature annotation summary alongside the tree
    info=uitextarea(g1,'Editable','off'); info.FontSize=12;
    info.Value={ ...
        'Feature summary', ...
        '- Oracle-style circuit', ...
        '- Moderate entanglement footprint', ...
        '- Heavy use of CX on central qubits', ...
        '- Suitable for backend ranking and prediction'};

    % ── QASMBench Similarity Results (right panel) ────────────────────────────
    p2=uipanel(g,'Title','QASMBench Similarity Results');
    p2.Layout.Row=2; p2.Layout.Column=3; p2.BackgroundColor=[1 1 1];

    g2=uigridlayout(p2,[2 1]);
    g2.RowHeight={'1x',96};
    g2.Padding=[12 10 12 10];
    g2.BackgroundColor=[1 1 1];

    app.SimilarityTable=uitable(g2);
    app.SimilarityTable.ColumnName={'Benchmark','Similarity','Category','Notes'};
    app.SimilarityTable.Data={ ...
        'BV-27',0.91,'Oracle','Closest algorithmic structure'; ...
        'QFT-27',0.63,'Fourier','Higher depth but similar width'; ...
        'Grover-20',0.52,'Search','Lower similarity, different entanglement'};
    app.SimilarityTable.Layout.Row=1; app.SimilarityTable.Layout.Column=1;
    app.styleTable(app.SimilarityTable);

    % Detailed comparison notes below the table
    compare=uitextarea(g2,'Editable','off'); compare.Layout.Row=2; compare.FontSize=12;
    compare.Value={ ...
        'Detailed comparison:', ...
        'BV-27 aligns best in width, gate profile, and oracle pattern.', ...
        'QFT-27 shows stronger depth pressure and denser 2Q activity.', ...
        'Recommendation: continue with BV-like backend/prediction defaults.'};

    % ── Action bar ────────────────────────────────────────────────────────────
    exportPanel=uipanel(g,'Title','Decision');
    exportPanel.Layout.Row=3; exportPanel.Layout.Column=[1 3];
    exportPanel.BackgroundColor=[0.94 0.97 1.00];

    eg=uigridlayout(exportPanel,[1 3]);
    eg.ColumnWidth={'1x',160,150};
    eg.Padding=[14 8 14 8];
    eg.BackgroundColor=[0.94 0.97 1.00];

    desc=uilabel(eg,'Text','Review extracted features, similarity matches, and then continue to backend exploration.');
    desc.FontSize=13; desc.FontWeight='bold'; desc.Layout.Row=1; desc.Layout.Column=1;
    desc.VerticalAlignment='center'; desc.WordWrap='on';
    tmp=uibutton(eg,'Text','Next: Backends','ButtonPushedFcn',@(~,~)app.onSelectSection('Backends'));
    tmp.Layout.Row=1; tmp.Layout.Column=2; app.styleBtn(tmp,'primary');
    tmp=uibutton(eg,'Text','Back: Upload','ButtonPushedFcn',@(~,~)app.onSelectSection('Upload'));
    tmp.Layout.Row=1; tmp.Layout.Column=3; app.styleBtn(tmp,'ghost');
end
