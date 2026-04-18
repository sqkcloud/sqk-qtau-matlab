% NotesTab  Populates the Notes section panel.
%
%   Layout:
%     Row 1 (toolbar, 42 px)   — heading + Save Notes / Load Notes / Clear buttons.
%     Row 2 ('1x')             — Markdown editor (left) | Pre-submission runbook (right).
%
%   All visible strings come from resources/labels.properties via Labels.
function NotesScreen(app)
    Logger.info('NotesScreen', 'Building Notes tab UI');
    t = app.createSectionPage('Notes');

    g = uigridlayout(t, [2 2]);
    g.RowHeight     = {34, '1x'};
    g.ColumnWidth   = {'1.2x', '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Toolbar ──────────────────────────────────────────────────────────────
    topRow = uigridlayout(g, [1 4]);
    topRow.Layout.Row = 1; topRow.Layout.Column = [1 2];
    topRow.ColumnWidth = {'1x', 90, 100, 80};
    topRow.Padding = [0 0 0 0];
    topRow.BackgroundColor = Theme.COLOR_BG;

    heading = uilabel(topRow, 'Text', Labels.get('notes_toolbar_title'));
    heading.FontSize = 16; heading.FontWeight = 'bold'; heading.FontColor = Theme.COLOR_HEADING;
    heading.Layout.Row = 1; heading.Layout.Column = 1;

    app.SaveNotesButton = uibutton(topRow, 'Text', [char(10004) ' ' Labels.get('notes_btn_save')], ...
        'ButtonPushedFcn', @(~,~)app.NotesVm.onSaveNotes());
    app.SaveNotesButton.Layout.Row = 1; app.SaveNotesButton.Layout.Column = 2;
    app.SaveNotesButton.FontSize = 14;
    app.styleBtn(app.SaveNotesButton, 'primary');
    app.SaveNotesButton.Tooltip = 'Persist notes to server (requires login)';

    loadBtn = uibutton(topRow, 'Text', [char(8635) ' ' Labels.get('notes_btn_load')], ...
        'ButtonPushedFcn', @(~,~)app.NotesVm.onLoadNotes());
    loadBtn.Layout.Row = 1; loadBtn.Layout.Column = 3;
    loadBtn.FontSize = 14;
    app.styleBtn(loadBtn, 'secondary');
    loadBtn.Tooltip = 'Fetch notes from server for current project';

    app.ClearNotesButton = uibutton(topRow, 'Text', [char(10005) ' ' Labels.get('notes_btn_clear')], ...
        'ButtonPushedFcn', @(~,~)app.NotesVm.onClearNotes());
    app.ClearNotesButton.Layout.Row = 1; app.ClearNotesButton.Layout.Column = 4;
    app.ClearNotesButton.FontSize = 14;
    app.styleBtn(app.ClearNotesButton, 'ghost');

    % ── Markdown notes editor (left) ─────────────────────────────────────────
    editorPanel = uipanel(g, 'Title', Labels.get('notes_panel_editor'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    editorPanel.Layout.Row = 2; editorPanel.Layout.Column = 1; editorPanel.BackgroundColor = Theme.COLOR_CARD;

    eg = uigridlayout(editorPanel, [1 1]);
    eg.Padding = [12 10 12 10]; eg.BackgroundColor = Theme.COLOR_CARD;
    app.NotesArea = uitextarea(eg, 'Editable', 'on');
    app.NotesArea.FontSize = 13; app.NotesArea.FontName = 'Courier New';
    app.NotesArea.BackgroundColor = Theme.COLOR_CARD;
    app.NotesArea.Value = { ...
        '# Run Notes', '', ...
        '## Objective', '', ...
        '## Pre-run checklist', ...
        '- [ ] Account credentials verified', ...
        '- [ ] Circuit uploaded and parsed', ...
        '- [ ] Backend confirmed available', ...
        '- [ ] Benchmark configured', '', ...
        '## Observations', '', ...
        '## Next steps', ''};

    % ── Pre-submission Runbook (right) ────────────────────────────────────────
    checkPanel = uipanel(g, 'Title', Labels.get('notes_panel_runbook'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    checkPanel.Layout.Row = 2; checkPanel.Layout.Column = 2; checkPanel.BackgroundColor = Theme.COLOR_CARD;

    cpg = uigridlayout(checkPanel, [2 1]);
    cpg.RowHeight = {'1x', 60};
    cpg.Padding = [12 10 12 10]; cpg.BackgroundColor = Theme.COLOR_CARD;

    app.NotesRunbookTable = uitable(cpg);
    app.NotesRunbookTable.ColumnName = Labels.cols('notes_table_cols_runbook', {'Check','Done'});
    app.NotesRunbookTable.ColumnEditable = [false true];
    app.NotesRunbookTable.Data = { ...
        'Credentials valid',   false; ...
        'Circuit uploaded',    false; ...
        'Backend selected',    false; ...
        'Benchmark configured',false; ...
        'Prediction reviewed', false; ...
        'Job submitted',       false; ...
        'Results reviewed',    false; ...
        'Report generated',    false};
    app.NotesRunbookTable.Layout.Row = 1; app.styleTable(app.NotesRunbookTable);

    hint = uitextarea(cpg, 'Editable', 'off'); hint.Layout.Row = 2; hint.FontSize = 12; hint.WordWrap = 'on';
    hint.Value = {Labels.get('notes_hint')};

    Logger.info('NotesScreen', 'Notes tab UI built successfully');
end
