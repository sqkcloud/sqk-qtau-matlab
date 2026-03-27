% buildUploadTab  Populates the Upload section panel.
%
%   Layout (3-column grid, 3 rows):
%     Row 1:      Circuit Upload panel spanning all columns — file input + preview.
%     Row 2, Col 1: Format and Metadata form.
%     Row 2, Col 2: 6 px resizable divider.
%     Row 2, Col 3: Circuit Statistics summary.
%     Row 3:      Full-width action bar (Next: Analysis / Back: Welcome).
function buildUploadTab(app)
    t = app.createSectionPage('Upload');

    % ── Root grid: 3 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [3 3]);
    g.RowHeight     = {'1x', 178, 72};      % file panel flexible; meta fixed; action bar fixed
    g.ColumnWidth   = {'1.15x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Circuit upload + preview (full width) ─────────────────────────────────
    dropPanel = uipanel(g,'Title','Circuit Upload & Manager');
    dropPanel.Layout.Row=1; dropPanel.Layout.Column=[1 3]; dropPanel.BackgroundColor=[1 1 1];

    dg=uigridlayout(dropPanel,[3 4]);
    dg.RowHeight={26,38,'1x'};
    dg.ColumnWidth={110,'1x',130,160};
    dg.Padding=[16 12 16 12];
    dg.RowSpacing=8;
    dg.BackgroundColor=[1 1 1];

    % Instruction label
    info=uilabel(dg,'Text','Upload via drag-and-drop or choose a file from disk.');
    info.FontSize=14; info.FontWeight='bold';
    info.Layout.Row=1; info.Layout.Column=[1 4]; info.WordWrap='on';

    % File path field + browse/upload buttons
    lbl=uilabel(dg,'Text','Circuit File'); lbl.FontColor=[0.35 0.42 0.52];
    lbl.Layout.Row=2; lbl.Layout.Column=1;
    app.UploadFileField=uieditfield(dg,'text','Value','bernstein_vazirani_27.qasm');
    app.UploadFileField.Layout.Row=2; app.UploadFileField.Layout.Column=2;
    app.BrowseButton=uibutton(dg,'Text','Browse','ButtonPushedFcn',@(~,~)app.onBrowseCircuit());
    app.BrowseButton.Layout.Row=2; app.BrowseButton.Layout.Column=3; app.styleBtn(app.BrowseButton,'ghost');
    app.UploadButton=uibutton(dg,'Text','Upload To FastAPI','ButtonPushedFcn',@(~,~)app.onUploadCircuit());
    app.UploadButton.Layout.Row=2; app.UploadButton.Layout.Column=4; app.styleBtn(app.UploadButton,'primary');

    % Inline QASM preview — editable so developers can tweak the circuit directly
    preview=uitextarea(dg,'Editable','on');
    preview.Layout.Row=3; preview.Layout.Column=[1 4];
    preview.FontName='Courier New'; preview.FontSize=13;
    preview.BackgroundColor=[0.97 0.98 1.00]; preview.FontColor=[0.14 0.18 0.26];
    preview.Value={ ...
        'OPENQASM 2.0;','include "qelib1.inc";','', ...
        'qreg q[27];','creg c[27];','', ...
        '// Bernstein-Vazirani oracle sketch', ...
        'h q[0];','for i = 1:26','    cx q[0], q[i];','end','measure q -> c;'};

    % ── Column divider ────────────────────────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=2; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Format and Metadata (left panel) ─────────────────────────────────────
    metaPanel=uipanel(g,'Title','Format and Metadata');
    metaPanel.Layout.Row=2; metaPanel.Layout.Column=1; metaPanel.BackgroundColor=[1 1 1];

    mg=uigridlayout(metaPanel,[5 2]);
    mg.RowHeight={28,28,28,28,'1x'};
    mg.ColumnWidth={130,'1x'};
    mg.Padding=[16 12 16 12];
    mg.RowSpacing=6;
    mg.BackgroundColor=[1 1 1];

    tmp=uilabel(mg,'Text','Input Format'); tmp.FontColor=[0.35 0.42 0.52]; tmp.Layout.Row=1; tmp.Layout.Column=1;
    tmp=uidropdown(mg,'Items',{'OpenQASM 2.0','OpenQASM 3','Qiskit JSON','MATLAB struct'},'Value','OpenQASM 2.0');
    tmp.Layout.Row=1; tmp.Layout.Column=2;

    tmp=uilabel(mg,'Text','Circuit Name'); tmp.FontColor=[0.35 0.42 0.52]; tmp.Layout.Row=2; tmp.Layout.Column=1;
    tmp=uieditfield(mg,'text','Value','bernstein_vazirani_27'); tmp.Layout.Row=2; tmp.Layout.Column=2;

    tmp=uilabel(mg,'Text','Category'); tmp.FontColor=[0.35 0.42 0.52]; tmp.Layout.Row=3; tmp.Layout.Column=1;
    tmp=uidropdown(mg,'Items',{'Oracle','Fourier','Sampling','Optimization'},'Value','Oracle');
    tmp.Layout.Row=3; tmp.Layout.Column=2;

    tmp=uilabel(mg,'Text','Metadata'); tmp.FontColor=[0.35 0.42 0.52]; tmp.Layout.Row=4; tmp.Layout.Column=1;
    mta=uitextarea(mg,'Value',{'Source: QASMBench inspired example','Owner: sqkadmin','Target use: storyboard demo'});
    mta.FontSize=12; mta.Layout.Row=4; mta.Layout.Column=2;

    % ── Circuit Statistics (right panel) ─────────────────────────────────────
    statsPanel=uipanel(g,'Title','Circuit Preview and Basic Statistics');
    statsPanel.Layout.Row=2; statsPanel.Layout.Column=3; statsPanel.BackgroundColor=[1 1 1];

    pg=uigridlayout(statsPanel,[1 1]);
    pg.Padding=[12 10 12 10]; pg.BackgroundColor=[1 1 1];
    app.CircuitStatsArea=uitextarea(pg,'Editable','off'); app.CircuitStatsArea.FontSize=12;
    app.CircuitStatsArea.Value={ ...
        'File: bernstein_vazirani_27.qasm', ...
        'Qubits: 27','Classical bits: 27','Depth: 128', ...
        'Single-qubit gates: 81','Two-qubit gates: 54', ...
        'Measurement operations: 27','Status: Parsed successfully'};

    % ── Action bar (full width) ───────────────────────────────────────────────
    actionPanel=uipanel(g,'Title','Next Step');
    actionPanel.Layout.Row=3; actionPanel.Layout.Column=[1 3];
    actionPanel.BackgroundColor=[0.94 0.97 1.00];

    ag=uigridlayout(actionPanel,[1 3]); ag.ColumnWidth={'1x',170,150};
    ag.Padding=[14 8 14 8]; ag.BackgroundColor=[0.94 0.97 1.00];
    msg=uilabel(ag,'Text','After upload, proceed to analysis to extract features and compare with QASMBench references.');
    msg.FontSize=13; msg.FontWeight='bold'; msg.Layout.Row=1; msg.Layout.Column=1;
    msg.VerticalAlignment='center'; msg.WordWrap='on';
    tmp=uibutton(ag,'Text','Next: Analysis','ButtonPushedFcn',@(~,~)app.onSelectSection('Analysis'));
    tmp.Layout.Row=1; tmp.Layout.Column=2; app.styleBtn(tmp,'primary');
    tmp=uibutton(ag,'Text','Back: Welcome','ButtonPushedFcn',@(~,~)app.onSelectSection('Welcome'));
    tmp.Layout.Row=1; tmp.Layout.Column=3; app.styleBtn(tmp,'ghost');
end
