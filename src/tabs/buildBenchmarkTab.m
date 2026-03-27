% buildBenchmarkTab  Populates the Benchmark section panel.
%
%   Layout (3-column grid, 3 rows):
%     Row 1, Col 1: Benchmark Configuration form — shots, optimisation, mitigation.
%     Row 1, Col 2: 6 px resizable divider.
%     Row 1, Col 3: Execution Plan summary text area.
%     Row 2:        Full-width Strategy Comparison table.
%     Row 3:        Full-width action bar (Next: Prediction / Back: Backends).
function buildBenchmarkTab(app)
    t = app.createSectionPage('Benchmark');

    % ── Root grid: 3 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {284, '1x', 72};
    g.ColumnWidth   = {'1.05x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Column divider (row 1 only) ───────────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=1; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Configuration form (left panel) ──────────────────────────────────────
    config=uipanel(g,'Title','Benchmark Configuration');
    config.Layout.Row=1; config.Layout.Column=1; config.BackgroundColor=[1 1 1];

    cg=uigridlayout(config,[5 2]);
    cg.RowHeight={40,40,40,40,36};   % last row fixed so Run Benchmark is never clipped
    cg.ColumnWidth={180,'1x'};
    cg.Padding=[16 12 16 12];
    cg.RowSpacing=8;
    cg.BackgroundColor=[1 1 1];

    % Shots — number of circuit executions per job
    tmp=uilabel(cg,'Text','Shots'); tmp.FontColor=[0.35 0.42 0.52]; tmp.Layout.Row=1; tmp.Layout.Column=1;
    app.BenchmarkShotsField=uieditfield(cg,'numeric','Value',4096);
    app.BenchmarkShotsField.Layout.Row=1; app.BenchmarkShotsField.Layout.Column=2;

    % Optimisation level (Qiskit transpiler 0–3)
    tmp=uilabel(cg,'Text','Optimization Level'); tmp.FontColor=[0.35 0.42 0.52]; tmp.Layout.Row=2; tmp.Layout.Column=1;
    app.BenchmarkOptField=uieditfield(cg,'numeric','Value',3);
    app.BenchmarkOptField.Layout.Row=2; app.BenchmarkOptField.Layout.Column=2;

    % Error mitigation strategy dropdown
    tmp=uilabel(cg,'Text','Error Mitigation'); tmp.FontColor=[0.35 0.42 0.52]; tmp.Layout.Row=3; tmp.Layout.Column=1;
    tmp=uidropdown(cg,'Items',{'None','Measurement mitigation','Zero-noise extrapolation','Readout calibration'}, ...
        'Value','Measurement mitigation');
    tmp.Layout.Row=3; tmp.Layout.Column=2;

    % Transpilation strategy dropdown
    tmp=uilabel(cg,'Text','Transpilation Strategy'); tmp.FontColor=[0.35 0.42 0.52]; tmp.Layout.Row=4; tmp.Layout.Column=1;
    tmp=uidropdown(cg,'Items',{'Balanced','Depth optimized','Fidelity optimized','Queue aware'}, ...
        'Value','Fidelity optimized');
    tmp.Layout.Row=4; tmp.Layout.Column=2;

    % Run button — triggers POST to /api/benchmark
    app.BenchmarkRunButton=uibutton(cg,'Text','Run Benchmark', ...
        'ButtonPushedFcn',@(~,~)app.onRunBenchmark());
    app.BenchmarkRunButton.Layout.Row=5; app.BenchmarkRunButton.Layout.Column=[1 2];
    app.styleBtn(app.BenchmarkRunButton,'primary');

    % ── Execution Plan (right panel) ──────────────────────────────────────────
    estimate=uipanel(g,'Title','Execution Plan');
    estimate.Layout.Row=1; estimate.Layout.Column=3; estimate.BackgroundColor=[1 1 1];

    eg=uigridlayout(estimate,[1 1]);
    eg.Padding=[16 12 16 12];
    eg.BackgroundColor=[1 1 1];
    app.BenchmarkStatusArea=uitextarea(eg,'Editable','off'); app.BenchmarkStatusArea.FontSize=12;
    app.BenchmarkStatusArea.Value={ ...
        'Cost estimate: 14.6 credits', ...
        'Estimated queue wait: 8 minutes', ...
        'Estimated execution time: 18 seconds', ...
        'Predicted best transpilation strategy: Fidelity optimized', ...
        'Suggested qubit layout: heavy-hex centered placement', ...
        'Ready to proceed to performance prediction'};

    % ── Strategy comparison table (full width) ────────────────────────────────
    % Side-by-side comparison of all four transpilation strategies to help the
    % operator choose the best trade-off between depth, fidelity, and queue time.
    comparePanel=uipanel(g,'Title','Transpilation Strategy Comparison');
    comparePanel.Layout.Row=2; comparePanel.Layout.Column=[1 3]; comparePanel.BackgroundColor=[1 1 1];
    comparePanel.Scrollable='on';       % scrollbar appears when window is too short

    comp=uigridlayout(comparePanel,[1 1]);
    comp.Padding=[12 10 12 10];
    comp.BackgroundColor=[1 1 1];
    tbl=uitable(comp);
    tbl.ColumnName={'Strategy','Depth','2Q gates','Predicted fidelity','Comment'};
    tbl.Data={ ...
        'Balanced',124,56,0.951,'Fast baseline'; ...
        'Depth optimized',109,61,0.945,'Shortest depth but noisier'; ...
        'Fidelity optimized',128,54,0.963,'Best overall score'; ...
        'Queue aware',130,55,0.958,'Good fallback for busy systems'};
    app.styleTable(tbl);

    % ── Action bar ────────────────────────────────────────────────────────────
    nextPanel=uipanel(g,'Title','Proceed to Prediction');
    nextPanel.Layout.Row=3; nextPanel.Layout.Column=[1 3];
    nextPanel.BackgroundColor=[0.94 0.97 1.00];

    ng=uigridlayout(nextPanel,[1 3]);
    ng.ColumnWidth={'1x',165,165};
    ng.Padding=[14 8 14 8];
    ng.BackgroundColor=[0.94 0.97 1.00];

    desc=uilabel(ng,'Text','Configure shots, optimization, mitigation, and strategy before moving to the prediction screen.');
    desc.FontSize=13; desc.FontWeight='bold'; desc.Layout.Row=1; desc.Layout.Column=1;
    desc.VerticalAlignment='center'; desc.WordWrap='on';
    tmp=uibutton(ng,'Text','Next: Prediction','ButtonPushedFcn',@(~,~)app.onSelectSection('Prediction'));
    tmp.Layout.Row=1; tmp.Layout.Column=2; app.styleBtn(tmp,'primary');
    tmp=uibutton(ng,'Text','Back: Backends','ButtonPushedFcn',@(~,~)app.onSelectSection('Backends'));
    tmp.Layout.Row=1; tmp.Layout.Column=3; app.styleBtn(tmp,'ghost');
end
