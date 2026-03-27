% buildNotesTab  Populates the Notes section panel.
%
%   Layout (2-row × 3-col grid):
%     Row 1:      Full-width top bar — heading label + Save/Clear buttons.
%     Row 2, Col 1: Markdown-style notes editor.
%     Row 2, Col 2: 6 px resizable divider.
%     Row 2, Col 3: Pre-submission Runbook checklist table.
function buildNotesTab(app)
    t = app.createSectionPage('Notes');

    % ── Root grid: 2 rows × 3 cols ───────────────────────────────────────────
    g = uigridlayout(t, [2 3]);
    g.RowHeight     = {42, '1x'};
    g.ColumnWidth   = {'1.2x', 6, '1x'};
    g.Padding       = [16 16 16 16];
    g.RowSpacing    = 12;
    g.ColumnSpacing = 4;
    g.BackgroundColor = [0.96 0.97 0.99];

    % ── Top bar (full width) ──────────────────────────────────────────────────
    topRow=uigridlayout(g,[1 3]);
    topRow.Layout.Row=1; topRow.Layout.Column=[1 3];
    topRow.ColumnWidth={'1x','1x','1x'};
    topRow.Padding=[0 0 0 0];
    topRow.BackgroundColor=[0.96 0.97 0.99];

    % Section heading (not a panel title — inlined in the toolbar grid)
    heading=uilabel(topRow,'Text','Notes and Runbook');
    heading.FontSize=16; heading.FontWeight='bold'; heading.FontColor=[0.18 0.26 0.40];

    % Save preserves the current notes to session state
    tmp=uibutton(topRow,'Text','Save Notes'); app.styleBtn(tmp,'primary');
    tmp.Tooltip='Save current notes to session state';

    tmp=uibutton(topRow,'Text','Clear Notes'); app.styleBtn(tmp,'ghost');

    % ── Column divider ────────────────────────────────────────────────────────
    div=uipanel(g,'Title',''); div.Layout.Row=2; div.Layout.Column=2;
    div.BackgroundColor=[0.87 0.90 0.93]; div.BorderType='none';
    app.attachColumnDivider(div, g);

    % ── Notes editor (left panel) ─────────────────────────────────────────────
    % Editable free-text area using Courier New — resembles a lightweight
    % Markdown editor for informal run notes, observations, and checklists.
    editorPanel=uipanel(g,'Title','Markdown-style Notes');
    editorPanel.Layout.Row=2; editorPanel.Layout.Column=1; editorPanel.BackgroundColor=[1 1 1];

    eg=uigridlayout(editorPanel,[1 1]);
    eg.Padding=[12 10 12 10];
    eg.BackgroundColor=[1 1 1];
    app.NotesArea=uitextarea(eg,'Editable','on'); app.NotesArea.FontSize=13;
    app.NotesArea.BackgroundColor=[1 1 1]; app.NotesArea.FontName='Courier New';
    app.NotesArea.Value={ ...
        '# BV-27 Run Notes — March 2026', '', ...
        '## Objective', ...
        'Run Bernstein-Vazirani oracle circuit on IBM heavy-hex backends.', '', ...
        '## Pre-run checklist', ...
        '- [x] Account credentials verified', ...
        '- [x] Circuit uploaded and parsed', ...
        '- [x] Backend ibm_brisbane confirmed available', ...
        '- [x] Benchmark config set: shots=4096, opt=3', '', ...
        '## Observations', ...
        '- Fidelity came in at 0.947 vs predicted 0.963', ...
        '- Readout error at Q14/Q22 slightly elevated', ...
        '- Run time: 18s — within estimate', '', ...
        '## Next steps', ...
        '- Review qubit layout and apply targeted mitigation', ...
        '- Re-run with readout calibration enabled'};

    % ── Pre-submission Runbook (right panel) ─────────────────────────────────
    % Boolean checklist table tracking completion of each pipeline stage.
    checkPanel=uipanel(g,'Title','Pre-submission Runbook');
    checkPanel.Layout.Row=2; checkPanel.Layout.Column=3; checkPanel.BackgroundColor=[1 1 1];

    cpg=uigridlayout(checkPanel,[2 1]);
    cpg.RowHeight={'1x',60};
    cpg.Padding=[12 10 12 10];
    cpg.BackgroundColor=[1 1 1];

    tbl=uitable(cpg);
    tbl.ColumnName={'Check','Done'};
    tbl.Data={ ...
        'Credentials valid',true; ...
        'Circuit uploaded',true; ...
        'Backend selected',true; ...
        'Benchmark configured',true; ...
        'Prediction reviewed',true; ...
        'Job submitted',false; ...
        'Results reviewed',false; ...
        'Report generated',false};
    tbl.Layout.Row=1; app.styleTable(tbl);

    % Guidance note below the checklist
    notes=uitextarea(cpg,'Editable','off'); notes.Layout.Row=2; notes.FontSize=12; notes.WordWrap='on';
    notes.Value={'Use the checklist to track pipeline completion. Tick each item from the corresponding tab screen before advancing.'};
end
