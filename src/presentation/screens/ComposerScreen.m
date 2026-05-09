% ComposerScreen  Populates the Composer section panel.
%
%   v0.1 — skeleton. Renders a hero card describing the planned
%   Composer feature (gate palette, OpenQASM mirror, Templates gallery,
%   Inspect mode footer) and one "Bell state" template card to prove
%   the screen mounts cleanly into the navigation system. Click handler
%   on the template card is a stub that logs to the event log; the
%   actual save-to-project flow lands in v0.1.
%
%   Layout:
%     Row 1 (180px): Hero card — title + tagline + roadmap chips.
%     Row 2 (flex):  Template gallery panel — placeholder card grid
%                    with one working Bell-state entry.
function ComposerScreen(app)
    Logger.info('ComposerScreen', 'Building Composer tab UI');
    t = app.createSectionPage('Composer');

    g = uigridlayout(t, [2 1]);
    g.RowHeight     = {180, '1x'};
    g.Padding       = Theme.GRID_PADDING;
    g.RowSpacing    = 12;
    g.BackgroundColor = Theme.COLOR_BG;

    % ── Hero card ────────────────────────────────────────────────────────
    heroPanel = uipanel(g, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER);
    heroPanel.Layout.Row = 1; heroPanel.Layout.Column = 1;
    heroPanel.BackgroundColor = Theme.COLOR_CARD;

    hg = uigridlayout(heroPanel, [3 1]);
    hg.Padding = [24 18 24 18]; hg.RowSpacing = 6;
    hg.RowHeight = {28, 22, 'fit'};
    hg.BackgroundColor = Theme.COLOR_CARD;

    titleLbl = uilabel(hg, 'Text', ...
        Labels.get('composer_hero_title', ...
            [char(9998) ' Composer  ·  In-app circuit authoring']), ...
        'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING);
    titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

    sublineLbl = uilabel(hg, 'Text', ...
        Labels.get('composer_hero_subtitle', ...
            'Drag-and-drop gate palette + parameterized algorithm templates + step-through statevector inspection.'), ...
        'FontSize', 12, 'FontColor', Theme.COLOR_LABEL, ...
        'WordWrap', 'on');
    sublineLbl.Layout.Row = 2; sublineLbl.Layout.Column = 1;

    statusLbl = uilabel(hg, 'Text', ...
        Labels.get('composer_hero_status', ...
            'v0.1 (skeleton) — sidebar entry live; gate palette + Templates gallery + Inspect-mode statevector simulator land in follow-up sessions.'), ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on');
    statusLbl.Layout.Row = 3; statusLbl.Layout.Column = 1;

    % ── Template gallery placeholder ─────────────────────────────────────
    galleryPanel = uipanel(g, 'Title', ...
        Labels.get('composer_gallery_panel', 'Algorithm Templates'), ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    galleryPanel.Layout.Row = 2; galleryPanel.Layout.Column = 1;
    galleryPanel.BackgroundColor = Theme.COLOR_CARD;

    galleryGrid = uigridlayout(galleryPanel, [3 4]);
    galleryGrid.Padding = [16 12 16 12];
    galleryGrid.RowSpacing = 12; galleryGrid.ColumnSpacing = 12;
    galleryGrid.RowHeight   = {110, 110, 110};
    galleryGrid.ColumnWidth = {'1x', '1x', '1x', '1x'};
    galleryGrid.BackgroundColor = Theme.COLOR_CARD;

    % One working Bell-state card — proves the click pipeline. The other
    % 11 cards land in v0.1 alongside the actual gate palette.
    bellCard = makeTemplateCard(galleryGrid, 'bell', ...
        Labels.get('composer_template_bell', 'Bell State'), ...
        Labels.get('composer_template_bell_desc', '2-qubit maximally-entangled state (|Φ+⟩).'), ...
        2, app);
    bellCard.Layout.Row = 1; bellCard.Layout.Column = 1;

    % Coming-soon placeholders — visually communicate the planned roster
    % so the user understands what's pending without ambiguity.
    placeholders = {
        'GHZ',                'n-qubit GHZ entanglement (parameterized n).';
        'QFT',                'Quantum Fourier Transform (parameterized n).';
        'Grover',             'Grover search over k-bit oracle (parameterized).';
        'Bernstein-Vazirani', 'Hidden-string oracle test (parameterized).';
        'Deutsch-Jozsa',      'Constant-vs-balanced oracle (parameterized).';
        'Phase Estimation',   'Toy 4-qubit unitary phase readout.';
        'VQE H2',             '2-qubit hardware-efficient ansatz.';
        'QAOA',               '3-node Max-Cut (gamma, beta parameterized).';
        'Trotter',            'XY-model Trotter-step simulator.';
        'Teleportation',      '3-qubit quantum teleportation circuit.';
        'Superdense Coding',  '2-qubit message encoding circuit.';
    };
    slot = 1;  % bellCard already at (1,1) → start placeholders at (1,2)
    for i = 1:size(placeholders, 1)
        slot = slot + 1;
        if slot > 12; break; end  % grid is 3x4 = 12 slots total
        row = floor((slot - 1) / 4) + 1;
        col = mod((slot - 1), 4) + 1;
        card = makePlaceholderCard(galleryGrid, ...
            placeholders{i, 1}, placeholders{i, 2});
        card.Layout.Row = row; card.Layout.Column = col;
    end

    app.logEvent('UI', 'Composer screen mounted (v0.1 skeleton)');
end

% ── Helper: build a clickable template card ─────────────────────────────
function card = makeTemplateCard(parent, templateId, name, desc, qubits, app)
    card = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_PRIMARY);
    card.BackgroundColor = Theme.COLOR_CARD;

    cg = uigridlayout(card, [4 1]);
    cg.Padding = [10 8 10 8]; cg.RowSpacing = 4;
    cg.RowHeight = {18, 'fit', 16, 28};
    cg.BackgroundColor = Theme.COLOR_CARD;

    nameLbl = uilabel(cg, 'Text', name, ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_HEADING);
    nameLbl.Layout.Row = 1;

    descLbl = uilabel(cg, 'Text', desc, ...
        'FontSize', 11, 'FontColor', Theme.COLOR_LABEL, ...
        'WordWrap', 'on');
    descLbl.Layout.Row = 2;

    qbLbl = uilabel(cg, 'Text', sprintf('%d qubit(s)', qubits), ...
        'FontSize', 10, 'FontColor', Theme.COLOR_MUTED);
    qbLbl.Layout.Row = 3;

    btn = uibutton(cg, 'Text', ...
        Labels.get('composer_template_use_btn', 'Use template'), ...
        'ButtonPushedFcn', @(~,~) app.ComposerVm.onTemplateClicked(templateId));
    btn.Layout.Row = 4;
    app.styleBtn(btn, 'primary');
end

% ── Helper: build a non-interactive coming-soon card ────────────────────
function card = makePlaceholderCard(parent, name, desc)
    card = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
        'BorderColor', Theme.COLOR_DIVIDER);
    card.BackgroundColor = Theme.COLOR_CARD;

    cg = uigridlayout(card, [3 1]);
    cg.Padding = [10 8 10 8]; cg.RowSpacing = 4;
    cg.RowHeight = {18, 'fit', 16};
    cg.BackgroundColor = Theme.COLOR_CARD;

    nameLbl = uilabel(cg, 'Text', name, ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'FontColor', Theme.COLOR_MUTED);
    nameLbl.Layout.Row = 1;

    descLbl = uilabel(cg, 'Text', desc, ...
        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on');
    descLbl.Layout.Row = 2;

    badgeLbl = uilabel(cg, 'Text', ...
        Labels.get('composer_template_coming_soon', 'Coming in v0.1'), ...
        'FontSize', 10, 'FontColor', Theme.COLOR_MUTED, ...
        'FontAngle', 'italic');
    badgeLbl.Layout.Row = 3;
end
