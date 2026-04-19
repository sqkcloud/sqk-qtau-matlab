classdef Theme
    % Theme  Runtime-swappable color palette + layout constants.
    %
    %   15 curated themes: light, dark, solarized_light, solarized_dark, nord,
    %   dracula, high_contrast, classic_light, darcula, darcula_contrast,
    %   github, islands_dark, monokai, twilight, warm_neon. The active palette
    %   is a module-level persistent struct; switch with Theme.setActive(name).
    %   Changes survive app restart via MATLAB's preference store
    %   ('QTAUWorkbench' group).
    %
    %   Colors are exposed as zero-arg static methods so existing call sites
    %   like  panel.BackgroundColor = Theme.COLOR_BG  keep working unchanged
    %   — MATLAB resolves ClassName.method identically to property access for
    %   zero-arg static methods, but the value now comes from the live
    %   palette instead of a compile-time constant.
    %
    %   Layout/font-size constants stay as Constant properties (they don't
    %   vary with the theme).

    properties (Constant)
        % ── Font Sizes ────────────────────────────────────────────────────
        FONT_SIZE_SM     = 11
        FONT_SIZE        = 12
        FONT_SIZE_MD     = 13
        FONT_SIZE_LG     = 14
        FONT_SIZE_TITLE  = 15

        % ── Layout Sizes ──────────────────────────────────────────────────
        BTN_ROW_HEIGHT    = 34
        ACTION_BAR_HEIGHT = 72
        BTN_WIDTH         = 110
        DIVIDER_WIDTH     = 6
        GRID_PADDING      = [16 16 16 16]
        GRID_ROW_SPACING  = 12
        KPI_INNER_PAD     = [10 8 10 8]

        % ── Theme registry ────────────────────────────────────────────────
        % Each row: {id, display name}. Used by the Display dropdown and for
        % validation. Adding a new theme = add a row here and a paletteX()
        % private method.
        THEME_LIST = { ...
            'light',            'Light'; ...
            'dark',             'Dark'; ...
            'solarized_light',  'Solarized Light'; ...
            'solarized_dark',   'Solarized Dark'; ...
            'nord',             'Nord'; ...
            'dracula',          'Dracula'; ...
            'high_contrast',    'High Contrast'; ...
            'classic_light',    'Classic Light'; ...
            'darcula',          'Darcula'; ...
            'darcula_contrast', 'Darcula Contrast'; ...
            'github',           'Github'; ...
            'islands_dark',     'Islands Dark'; ...
            'monokai',          'Monokai'; ...
            'twilight',         'Twilight'; ...
            'warm_neon',        'WarmNeon'};
    end

    methods (Static)
        % ── Color accessors ───────────────────────────────────────────────
        % Retained uppercase method names so legacy call sites (e.g.
        %   panel.BackgroundColor = Theme.COLOR_BG) keep compiling.
        function c = COLOR_BG();         c = Theme.get('bg');           end
        function c = COLOR_CARD();       c = Theme.get('cardBg');       end
        function c = COLOR_DIVIDER();    c = Theme.get('divider');      end
        function c = COLOR_HEADING();    c = Theme.get('heading');      end
        function c = COLOR_LABEL();      c = Theme.get('label');        end
        function c = COLOR_MUTED();      c = Theme.get('muted');        end
        function c = COLOR_PRIMARY();    c = Theme.get('primary');      end
        function c = COLOR_SUCCESS();    c = Theme.get('success');      end
        function c = COLOR_DANGER();     c = Theme.get('danger');       end
        function c = COLOR_WARNING();    c = Theme.get('warning');      end
        function c = COLOR_PURPLE();     c = Theme.get('purple');       end
        function c = COLOR_AMBER();      c = Theme.get('amber');        end
        function c = COLOR_ACCENT_BG();  c = Theme.get('accentBg');     end

        % Button variant colors (consumed by StyleHelper.styleBtn).
        function c = BTN_BG_DEFAULT();   c = Theme.get('btnBg');        end
        function c = BTN_FG_DEFAULT();   c = Theme.get('btnFg');        end
        function c = BTN_BG_SECONDARY(); c = Theme.get('btnBgSecondary'); end
        function c = BTN_FG_SECONDARY(); c = Theme.get('btnFgSecondary'); end
        function c = BTN_BG_GHOST();     c = Theme.get('btnBgGhost');   end
        function c = BTN_FG_GHOST();     c = Theme.get('btnFgGhost');   end

        % Chart chrome (data-carrying plot colors are left to callers).
        function c = CHART_BG();         c = Theme.get('chartBg');      end
        function c = CHART_AXIS();       c = Theme.get('chartAxis');    end
        function c = CHART_GRID();       c = Theme.get('chartGrid');    end

        % Sidebar / nav.
        function c = NAV_BG();           c = Theme.get('navBg');        end
        function c = NAV_FG();           c = Theme.get('navFg');        end
        function c = NAV_HOVER_BG();     c = Theme.get('navHoverBg');   end
        function c = NAV_ACTIVE_BG();    c = Theme.get('navActiveBg');  end
        function c = NAV_ACTIVE_FG();    c = Theme.get('navActiveFg');  end

        % Overlays (loading, auth, modal dimming).
        function c = OVERLAY_BG();       c = Theme.get('overlayBg');    end
        function c = OVERLAY_TEXT();     c = Theme.get('overlayText');  end
        function c = OVERLAY_ACCENT();   c = Theme.get('overlayAccent'); end

        % Console / log pane — intentionally theme-independent (terminal look).
        function c = CONSOLE_BG();       c = [0.06 0.08 0.12];          end
        function c = CONSOLE_FG();       c = [0.72 0.94 0.64];          end

        % ── Palette switching ─────────────────────────────────────────────
        function setActive(name)
            name = char(lower(string(name)));
            validIds = Theme.THEME_LIST(:, 1);
            if ~any(strcmp(validIds, name))
                warning('Theme:unknown', ...
                    'Unknown theme "%s" — keeping current palette.', name);
                return;
            end
            pal = Theme.loadPalette(name);
            Theme.paletteStore(pal, name);  % mutate + remember
            try
                setpref('QTAUWorkbench', 'theme', name);
            catch ME
                % setpref can fail on read-only prefs dirs; log and move on.
                % Theme still changes for this session.
                fprintf('[Theme] could not persist preference: %s\n', ME.message);
            end
        end

        function name = activeName()
            [~, name] = Theme.paletteStore();
        end

        function name = loadPersisted()
            % Returns the saved theme name, or 'dark' if unset / invalid.
            name = 'dark';
            try
                if ispref('QTAUWorkbench', 'theme')
                    candidate = getpref('QTAUWorkbench', 'theme');
                    validIds = Theme.THEME_LIST(:, 1);
                    if any(strcmp(validIds, candidate))
                        name = candidate;
                    end
                end
            catch
                % Fall through with default.
            end
        end

        function items = listThemeDisplayNames()
            % Cell array of display names, indexed same as THEME_LIST.
            items = Theme.THEME_LIST(:, 2)';
        end

        function items = listThemeIds()
            items = Theme.THEME_LIST(:, 1)';
        end

        function id = displayNameToId(displayName)
            % Map a display name from the dropdown back to an id for setActive.
            id = 'light';
            for i = 1:size(Theme.THEME_LIST, 1)
                if strcmp(Theme.THEME_LIST{i, 2}, char(displayName))
                    id = Theme.THEME_LIST{i, 1}; return;
                end
            end
        end

        function name = idToDisplayName(id)
            name = 'Light';
            for i = 1:size(Theme.THEME_LIST, 1)
                if strcmp(Theme.THEME_LIST{i, 1}, char(id))
                    name = Theme.THEME_LIST{i, 2}; return;
                end
            end
        end

        function hex = toHex(color)
            % Convert a [r g b] triplet (0–1) to a CSS hex string '#rrggbb'.
            if numel(color) ~= 3
                hex = '#000000'; return;
            end
            rgb = round(max(0, min(1, color)) * 255);
            hex = sprintf('#%02x%02x%02x', rgb(1), rgb(2), rgb(3));
        end

        function mode = figureMode(paletteId)
            % Map a palette id to the value accepted by uifigure.Theme
            % (R2025a+). Setting this lets MATLAB cascade base styling to
            % every built-in component (uitable, uidropdown, uieditfield,
            % uiaxes defaults, scrollbars, focus rings, etc.) so our
            % per-palette overrides can focus on the bits MATLAB doesn't
            % auto-theme (custom uihtml, nav sidebar, overlays).
            switch char(lower(paletteId))
                case {'light', 'solarized_light', 'classic_light', 'github'}
                    mode = 'light';
                otherwise
                    mode = 'dark';   % dark, solarized_dark, nord, dracula,
                                     % high_contrast, darcula, darcula_contrast,
                                     % islands_dark, monokai, twilight, warm_neon
            end
        end

        function applyFigureMode(fig, paletteId)
            % Set the figure's built-in Theme property. Best-effort: on
            % releases where the property is absent, this is a no-op.
            if isempty(fig) || ~isvalid(fig); return; end
            try
                fig.Theme = Theme.figureMode(paletteId);
            catch
                % R2024b or earlier — built-in Theme property not
                % available. Our custom per-component palette still
                % paints the explicit surfaces.
            end
        end
    end

    methods (Static, Access = private)
        function c = get(key)
            pal = Theme.paletteStore();
            if ~isstruct(pal) || ~isfield(pal, key)
                % Fail visible: unknown key → bright magenta so missing
                % mappings show up at a glance in any theme.
                c = [1 0 1];
                return;
            end
            c = pal.(key);
        end

        function [pal, name] = paletteStore(newPal, newName)
            % Single persistent store shared by all Theme callers this session.
            % Called with no args → getter; with args → setter.
            persistent storedPal storedName;
            if nargin >= 1 && ~isempty(newPal)
                storedPal = newPal;
                if nargin >= 2; storedName = newName; end
            end
            if isempty(storedPal)
                storedName = Theme.loadPersisted();
                storedPal  = Theme.loadPalette(storedName);
            end
            pal  = storedPal;
            name = storedName;
        end

        function p = loadPalette(name)
            switch char(lower(name))
                case 'light';            p = Theme.paletteLight();
                case 'dark';             p = Theme.paletteDark();
                case 'solarized_light';  p = Theme.paletteSolarizedLight();
                case 'solarized_dark';   p = Theme.paletteSolarizedDark();
                case 'nord';             p = Theme.paletteNord();
                case 'dracula';          p = Theme.paletteDracula();
                case 'high_contrast';    p = Theme.paletteHighContrast();
                case 'classic_light';    p = Theme.paletteClassicLight();
                case 'darcula';          p = Theme.paletteDarcula();
                case 'darcula_contrast'; p = Theme.paletteDarculaContrast();
                case 'github';           p = Theme.paletteGithub();
                case 'islands_dark';     p = Theme.paletteIslandsDark();
                case 'monokai';          p = Theme.paletteMonokai();
                case 'twilight';         p = Theme.paletteTwilight();
                case 'warm_neon';        p = Theme.paletteWarmNeon();
                otherwise;               p = Theme.paletteLight();
            end
        end

        % ── Palette definitions ───────────────────────────────────────────
        % Every palette MUST expose the same set of fields. Missing fields
        % render bright magenta (see Theme.get) so regressions are visible.

        function p = paletteLight()
            % Modern Light theme — neutral grays for text (no blue cast),
            % crisp near-black headings, Tailwind-style accent colors for a
            % contemporary feel. Ghost-button bg matches page bg so ghost
            % buttons visually float rather than merge with surrounding
            % cards.
            p = struct();
            p.bg            = [0.98 0.98 0.99];  % #FAFAFB — airy off-white
            p.cardBg        = [1.00 1.00 1.00];  % pure white cards
            p.divider       = [0.90 0.91 0.93];  % #E6E8ED neutral gray
            p.heading       = [0.09 0.11 0.15];  % #172026 near-black, crisp
            p.label         = [0.24 0.27 0.31];  % #3E454F charcoal
            p.muted         = [0.45 0.48 0.53];  % #737A87 medium gray
            p.primary       = [0.15 0.39 0.92];  % #2663EB Tailwind blue-600
            p.success       = [0.08 0.50 0.24];  % #15803D green — WCAG AA on white
            p.danger        = [0.82 0.16 0.20];  % #D12933 red — WCAG AA on white
            p.warning       = [0.90 0.55 0.10];  % #E68C1A warm amber
            p.purple        = [0.56 0.32 0.85];  % #8F52D9 vivid purple
            p.amber         = [0.80 0.55 0.12];  % #CC8C1F
            p.accentBg      = [0.93 0.96 1.00];  % #EDF4FF soft blue tint
            p.btnBg         = [0.97 0.97 0.98];
            p.btnFg         = [0.13 0.14 0.16];
            p.btnBgSecondary= [0.97 0.97 0.98];
            p.btnFgSecondary= [0.13 0.14 0.16];
            p.btnBgGhost    = [0.98 0.98 0.99];  % match bg → true "ghost"
            p.btnFgGhost    = [0.35 0.38 0.42];
            p.chartBg       = [1.00 1.00 1.00];
            p.chartAxis     = [0.30 0.33 0.38];
            p.chartGrid     = [0.90 0.91 0.93];
            p.navBg         = [0.13 0.16 0.22];  % #21293A refined navy
            p.navFg         = [0.90 0.92 0.96];
            p.navHoverBg    = [0.19 0.23 0.30];
            p.navActiveBg   = [0.15 0.39 0.92];  % matches primary
            p.navActiveFg   = [1.00 1.00 1.00];
            p.overlayBg     = [0.00 0.00 0.00];  % black, 70% alpha in CSS
            p.overlayText   = [0.95 0.97 1.00];
            p.overlayAccent = [0.28 0.55 0.98];
        end

        function p = paletteDark()
            p = struct();
            p.bg            = [0.11 0.12 0.14];  % #1C1F24
            p.cardBg        = [0.15 0.17 0.20];  % #262B33
            p.divider       = [0.26 0.29 0.33];
            p.heading       = [0.92 0.94 0.98];
            p.label         = [0.78 0.82 0.88];
            p.muted         = [0.58 0.62 0.70];
            p.primary       = [0.38 0.65 0.98];  % #61A6FA
            p.success       = [0.44 0.80 0.58];
            p.danger        = [0.95 0.38 0.42];
            p.warning       = [0.98 0.72 0.30];
            p.purple        = [0.72 0.55 0.92];
            p.amber         = [0.95 0.68 0.25];
            p.accentBg      = [0.18 0.22 0.30];
            p.btnBg         = [0.22 0.25 0.30];
            p.btnFg         = [0.92 0.94 0.98];
            p.btnBgSecondary= [0.22 0.25 0.30];
            p.btnFgSecondary= [0.92 0.94 0.98];
            p.btnBgGhost    = [0.18 0.20 0.24];
            p.btnFgGhost    = [0.75 0.80 0.88];
            p.chartBg       = [0.15 0.17 0.20];
            p.chartAxis     = [0.75 0.80 0.88];
            p.chartGrid     = [0.30 0.34 0.40];
            p.navBg         = [0.08 0.09 0.11];
            p.navFg         = [0.85 0.88 0.92];
            p.navHoverBg    = [0.15 0.18 0.22];
            p.navActiveBg   = [0.28 0.45 0.72];
            p.navActiveFg   = [1.00 1.00 1.00];
            p.overlayBg     = [0.00 0.00 0.00];
            p.overlayText   = [0.92 0.94 0.98];
            p.overlayAccent = [0.38 0.65 0.98];
        end

        function p = paletteSolarizedLight()
            % Solarized Light — E. Schoonover.
            p = struct();
            p.bg            = [0.99 0.96 0.89];  % base3 #FDF6E3
            p.cardBg        = [0.93 0.91 0.84];  % base2 #EEE8D5
            p.divider       = [0.80 0.78 0.71];
            p.heading       = [0.00 0.17 0.21];  % base02 #073642
            p.label         = [0.35 0.43 0.46];  % base01 #586E75
            p.muted         = [0.51 0.58 0.59];  % base00 #657B83
            p.primary       = [0.15 0.55 0.82];  % blue #268BD2
            p.success       = [0.52 0.60 0.00];  % green #859900
            p.danger        = [0.86 0.20 0.18];  % red #DC322F
            p.warning       = [0.80 0.29 0.09];  % orange #CB4B16
            p.purple        = [0.42 0.44 0.77];  % violet #6C71C4
            p.amber         = [0.71 0.54 0.00];  % yellow #B58900
            p.accentBg      = [0.96 0.93 0.85];
            p.btnBg         = [0.93 0.91 0.84];
            p.btnFg         = [0.00 0.17 0.21];
            p.btnBgSecondary= [0.93 0.91 0.84];
            p.btnFgSecondary= [0.00 0.17 0.21];
            p.btnBgGhost    = [0.96 0.93 0.85];
            p.btnFgGhost    = [0.35 0.43 0.46];
            p.chartBg       = [0.99 0.96 0.89];
            p.chartAxis     = [0.35 0.43 0.46];
            p.chartGrid     = [0.80 0.78 0.71];
            p.navBg         = [0.00 0.17 0.21];  % base02
            p.navFg         = [0.93 0.91 0.84];
            p.navHoverBg    = [0.03 0.21 0.26];
            p.navActiveBg   = [0.15 0.55 0.82];
            p.navActiveFg   = [0.99 0.96 0.89];
            p.overlayBg     = [0.00 0.11 0.15];
            p.overlayText   = [0.93 0.91 0.84];
            p.overlayAccent = [0.15 0.55 0.82];
        end

        function p = paletteSolarizedDark()
            p = struct();
            p.bg            = [0.00 0.17 0.21];  % base03 #002B36
            p.cardBg        = [0.03 0.21 0.26];  % base02 #073642
            p.divider       = [0.12 0.29 0.34];
            p.heading       = [0.93 0.91 0.84];  % base2 #EEE8D5
            p.label         = [0.58 0.63 0.63];  % base1 #93A1A1
            p.muted         = [0.51 0.58 0.59];  % base0 #839496
            p.primary       = [0.15 0.55 0.82];  % blue
            p.success       = [0.52 0.60 0.00];  % green
            p.danger        = [0.86 0.20 0.18];
            p.warning       = [0.80 0.29 0.09];
            p.purple        = [0.42 0.44 0.77];
            p.amber         = [0.71 0.54 0.00];
            p.accentBg      = [0.05 0.24 0.30];
            p.btnBg         = [0.07 0.27 0.33];
            p.btnFg         = [0.93 0.91 0.84];
            p.btnBgSecondary= [0.07 0.27 0.33];
            p.btnFgSecondary= [0.93 0.91 0.84];
            p.btnBgGhost    = [0.05 0.22 0.27];
            p.btnFgGhost    = [0.58 0.63 0.63];
            p.chartBg       = [0.03 0.21 0.26];
            p.chartAxis     = [0.58 0.63 0.63];
            p.chartGrid     = [0.12 0.29 0.34];
            p.navBg         = [0.00 0.14 0.17];
            p.navFg         = [0.58 0.63 0.63];
            p.navHoverBg    = [0.05 0.22 0.27];
            p.navActiveBg   = [0.15 0.55 0.82];
            p.navActiveFg   = [0.99 0.96 0.89];
            p.overlayBg     = [0.00 0.08 0.11];
            p.overlayText   = [0.93 0.91 0.84];
            p.overlayAccent = [0.15 0.55 0.82];
        end

        function p = paletteNord()
            % Nord — Arctic Ice Studio.
            p = struct();
            p.bg            = [0.18 0.20 0.25];  % nord0 #2E3440
            p.cardBg        = [0.23 0.26 0.32];  % nord1 #3B4252
            p.divider       = [0.30 0.34 0.42];  % nord2 #434C5E
            p.heading       = [0.93 0.94 0.96];  % nord6 #ECEFF4
            p.label         = [0.85 0.87 0.91];  % nord5 #E5E9F0
            p.muted         = [0.65 0.70 0.76];
            p.primary       = [0.53 0.75 0.82];  % nord8 #88C0D0
            p.success       = [0.64 0.75 0.55];  % nord14 #A3BE8C
            p.danger        = [0.75 0.38 0.42];  % nord11 #BF616A
            p.warning       = [0.86 0.62 0.39];  % nord12 #D08770
            p.purple        = [0.70 0.56 0.72];  % nord15 #B48EAD
            p.amber         = [0.92 0.80 0.54];  % nord13 #EBCB8B
            p.accentBg      = [0.25 0.29 0.36];
            p.btnBg         = [0.30 0.34 0.42];
            p.btnFg         = [0.93 0.94 0.96];
            p.btnBgSecondary= [0.30 0.34 0.42];
            p.btnFgSecondary= [0.93 0.94 0.96];
            p.btnBgGhost    = [0.23 0.26 0.32];
            p.btnFgGhost    = [0.65 0.70 0.76];
            p.chartBg       = [0.23 0.26 0.32];
            p.chartAxis     = [0.85 0.87 0.91];
            p.chartGrid     = [0.30 0.34 0.42];
            p.navBg         = [0.14 0.16 0.20];
            p.navFg         = [0.85 0.87 0.91];
            p.navHoverBg    = [0.23 0.26 0.32];
            p.navActiveBg   = [0.37 0.51 0.67];  % nord10 #5E81AC
            p.navActiveFg   = [1.00 1.00 1.00];
            p.overlayBg     = [0.10 0.12 0.15];
            p.overlayText   = [0.93 0.94 0.96];
            p.overlayAccent = [0.53 0.75 0.82];
        end

        function p = paletteDracula()
            % Dracula — Zeno Rocha.
            p = struct();
            p.bg            = [0.16 0.16 0.21];  % #282A36
            p.cardBg        = [0.26 0.28 0.35];  % #44475A
            p.divider       = [0.36 0.38 0.45];
            p.heading       = [0.97 0.97 0.95];  % #F8F8F2
            p.label         = [0.90 0.90 0.88];
            p.muted         = [0.70 0.72 0.78];
            p.primary       = [0.74 0.58 0.98];  % purple #BD93F9
            p.success       = [0.31 0.98 0.48];  % green #50FA7B
            p.danger        = [1.00 0.33 0.33];  % red #FF5555
            p.warning       = [0.95 0.72 0.37];  % orange #FFB86C
            p.purple        = [0.74 0.58 0.98];
            p.amber         = [0.95 0.98 0.55];  % yellow #F1FA8C
            p.accentBg      = [0.21 0.22 0.28];
            p.btnBg         = [0.26 0.28 0.35];
            p.btnFg         = [0.97 0.97 0.95];
            p.btnBgSecondary= [0.26 0.28 0.35];
            p.btnFgSecondary= [0.97 0.97 0.95];
            p.btnBgGhost    = [0.21 0.22 0.28];
            p.btnFgGhost    = [0.70 0.72 0.78];
            p.chartBg       = [0.26 0.28 0.35];
            p.chartAxis     = [0.90 0.90 0.88];
            p.chartGrid     = [0.36 0.38 0.45];
            p.navBg         = [0.12 0.12 0.16];
            p.navFg         = [0.90 0.90 0.88];
            p.navHoverBg    = [0.21 0.22 0.28];
            p.navActiveBg   = [0.74 0.58 0.98];
            p.navActiveFg   = [0.16 0.16 0.21];
            p.overlayBg     = [0.08 0.08 0.12];
            p.overlayText   = [0.97 0.97 0.95];
            p.overlayAccent = [1.00 0.47 0.78];  % pink #FF79C6
        end

        function p = paletteHighContrast()
            % WCAG AAA target — pure black/white with a yellow focus hue.
            p = struct();
            p.bg            = [0.00 0.00 0.00];
            p.cardBg        = [0.07 0.07 0.07];
            p.divider       = [1.00 1.00 1.00];
            p.heading       = [1.00 1.00 1.00];
            p.label         = [1.00 1.00 1.00];
            p.muted         = [0.85 0.85 0.85];
            p.primary       = [1.00 1.00 0.00];  % yellow focus
            p.success       = [0.00 1.00 0.00];
            p.danger        = [1.00 0.00 0.00];
            p.warning       = [1.00 0.55 0.00];
            p.purple        = [1.00 0.00 1.00];
            p.amber         = [1.00 0.80 0.00];
            p.accentBg      = [0.10 0.10 0.10];
            p.btnBg         = [0.00 0.00 0.00];
            p.btnFg         = [1.00 1.00 1.00];
            p.btnBgSecondary= [0.00 0.00 0.00];
            p.btnFgSecondary= [1.00 1.00 1.00];
            p.btnBgGhost    = [0.00 0.00 0.00];
            p.btnFgGhost    = [1.00 1.00 0.00];
            p.chartBg       = [0.00 0.00 0.00];
            p.chartAxis     = [1.00 1.00 1.00];
            p.chartGrid     = [0.40 0.40 0.40];
            p.navBg         = [0.00 0.00 0.00];
            p.navFg         = [1.00 1.00 1.00];
            p.navHoverBg    = [0.15 0.15 0.15];
            p.navActiveBg   = [1.00 1.00 0.00];
            p.navActiveFg   = [0.00 0.00 0.00];
            p.overlayBg     = [0.00 0.00 0.00];
            p.overlayText   = [1.00 1.00 1.00];
            p.overlayAccent = [1.00 1.00 0.00];
        end

        function p = paletteClassicLight()
            % Neutral-gray light theme (no bluish tint like Light).
            p = struct();
            p.bg            = [0.96 0.96 0.96];
            p.cardBg        = [1.00 1.00 1.00];
            p.divider       = [0.86 0.86 0.86];
            p.heading       = [0.13 0.13 0.13];
            p.label         = [0.26 0.26 0.26];
            p.muted         = [0.45 0.45 0.45];
            p.primary       = [0.20 0.47 0.80];
            p.success       = [0.16 0.58 0.33];
            p.danger        = [0.76 0.21 0.22];
            p.warning       = [0.85 0.55 0.10];
            p.purple        = [0.50 0.35 0.78];
            p.amber         = [0.75 0.48 0.10];
            p.accentBg      = [0.93 0.93 0.93];
            p.btnBg         = [0.94 0.94 0.94];
            p.btnFg         = [0.13 0.13 0.13];
            p.btnBgSecondary= [0.94 0.94 0.94];
            p.btnFgSecondary= [0.13 0.13 0.13];
            p.btnBgGhost    = [0.94 0.94 0.94];
            p.btnFgGhost    = [0.26 0.26 0.26];
            p.chartBg       = [1.00 1.00 1.00];
            p.chartAxis     = [0.26 0.26 0.26];
            p.chartGrid     = [0.82 0.82 0.82];
            p.navBg         = [0.20 0.20 0.20];
            p.navFg         = [0.94 0.94 0.94];
            p.navHoverBg    = [0.27 0.27 0.27];
            p.navActiveBg   = [0.42 0.42 0.42];
            p.navActiveFg   = [1.00 1.00 1.00];
            p.overlayBg     = [0.00 0.00 0.00];
            p.overlayText   = [0.94 0.94 0.94];
            p.overlayAccent = [0.20 0.47 0.80];
        end

        function p = paletteDarcula()
            % JetBrains Darcula — distinct from Dracula (neutral grays,
            % orange/green accents).
            p = struct();
            p.bg            = [0.17 0.17 0.17];  % #2B2B2B
            p.cardBg        = [0.24 0.25 0.25];  % #3C3F41
            p.divider       = [0.34 0.36 0.38];
            p.heading       = [0.66 0.72 0.78];  % #A9B7C6
            p.label         = [0.73 0.77 0.82];
            p.muted         = [0.55 0.60 0.65];
            p.primary       = [0.80 0.47 0.20];  % orange #CC7832
            p.success       = [0.42 0.53 0.35];  % green #6A8759
            p.danger        = [0.78 0.37 0.40];
            p.warning       = [0.95 0.73 0.36];
            p.purple        = [0.63 0.48 0.73];
            p.amber         = [0.94 0.78 0.27];
            p.accentBg      = [0.22 0.23 0.24];
            p.btnBg         = [0.29 0.30 0.31];
            p.btnFg         = [0.82 0.85 0.88];
            p.btnBgSecondary= [0.29 0.30 0.31];
            p.btnFgSecondary= [0.82 0.85 0.88];
            p.btnBgGhost    = [0.20 0.21 0.22];
            p.btnFgGhost    = [0.66 0.72 0.78];
            p.chartBg       = [0.24 0.25 0.25];
            p.chartAxis     = [0.73 0.77 0.82];
            p.chartGrid     = [0.34 0.36 0.38];
            p.navBg         = [0.13 0.14 0.14];
            p.navFg         = [0.73 0.77 0.82];
            p.navHoverBg    = [0.22 0.23 0.24];
            p.navActiveBg   = [0.41 0.30 0.17];  % dim orange tint
            p.navActiveFg   = [0.97 0.88 0.73];
            p.overlayBg     = [0.09 0.09 0.09];
            p.overlayText   = [0.82 0.85 0.88];
            p.overlayAccent = [0.80 0.47 0.20];
        end

        function p = paletteDarculaContrast()
            % Darcula Contrast — deeper blacks, same accent family as
            % Darcula but pushed for sharper separation.
            p = struct();
            p.bg            = [0.08 0.08 0.09];
            p.cardBg        = [0.14 0.14 0.16];
            p.divider       = [0.28 0.30 0.32];
            p.heading       = [0.90 0.92 0.94];
            p.label         = [0.80 0.84 0.88];
            p.muted         = [0.60 0.65 0.70];
            p.primary       = [1.00 0.58 0.22];  % pushed orange
            p.success       = [0.56 0.78 0.42];
            p.danger        = [1.00 0.42 0.40];
            p.warning       = [1.00 0.78 0.38];
            p.purple        = [0.78 0.56 0.92];
            p.amber         = [1.00 0.82 0.30];
            p.accentBg      = [0.12 0.12 0.14];
            p.btnBg         = [0.18 0.18 0.20];
            p.btnFg         = [0.94 0.96 0.98];
            p.btnBgSecondary= [0.18 0.18 0.20];
            p.btnFgSecondary= [0.94 0.96 0.98];
            p.btnBgGhost    = [0.10 0.10 0.12];
            p.btnFgGhost    = [0.78 0.82 0.86];
            p.chartBg       = [0.14 0.14 0.16];
            p.chartAxis     = [0.80 0.84 0.88];
            p.chartGrid     = [0.28 0.30 0.32];
            p.navBg         = [0.03 0.03 0.04];
            p.navFg         = [0.82 0.86 0.90];
            p.navHoverBg    = [0.10 0.10 0.12];
            p.navActiveBg   = [0.50 0.28 0.08];
            p.navActiveFg   = [1.00 0.92 0.76];
            p.overlayBg     = [0.00 0.00 0.00];
            p.overlayText   = [0.94 0.96 0.98];
            p.overlayAccent = [1.00 0.58 0.22];
        end

        function p = paletteGithub()
            % GitHub Light — default github.com palette.
            p = struct();
            p.bg            = [1.00 1.00 1.00];
            p.cardBg        = [0.96 0.97 0.98];  % #F6F8FA
            p.divider       = [0.85 0.88 0.91];  % #D8DEE4
            p.heading       = [0.14 0.16 0.18];  % #24292F
            p.label         = [0.26 0.29 0.34];
            p.muted         = [0.40 0.44 0.49];  % #656D76
            p.primary       = [0.04 0.41 0.85];  % #0969DA
            p.success       = [0.10 0.50 0.22];  % #1A7F37
            p.danger        = [0.81 0.13 0.18];  % #CF222E
            p.warning       = [0.60 0.42 0.00];  % #9A6700
            p.purple        = [0.55 0.33 0.75];  % #8250DF
            p.amber         = [0.75 0.55 0.00];
            p.accentBg      = [0.92 0.96 1.00];  % #DDF4FF-ish
            p.btnBg         = [0.96 0.97 0.98];
            p.btnFg         = [0.14 0.16 0.18];
            p.btnBgSecondary= [0.96 0.97 0.98];
            p.btnFgSecondary= [0.14 0.16 0.18];
            p.btnBgGhost    = [0.96 0.97 0.98];
            p.btnFgGhost    = [0.26 0.29 0.34];
            p.chartBg       = [1.00 1.00 1.00];
            p.chartAxis     = [0.26 0.29 0.34];
            p.chartGrid     = [0.85 0.88 0.91];
            p.navBg         = [0.14 0.16 0.18];
            p.navFg         = [0.92 0.94 0.96];
            p.navHoverBg    = [0.20 0.22 0.25];
            p.navActiveBg   = [0.04 0.41 0.85];
            p.navActiveFg   = [1.00 1.00 1.00];
            p.overlayBg     = [0.00 0.00 0.00];
            p.overlayText   = [0.92 0.94 0.96];
            p.overlayAccent = [0.04 0.41 0.85];
        end

        function p = paletteIslandsDark()
            % Islands-style dark teal, inspired by JetBrains Islands.
            p = struct();
            p.bg            = [0.08 0.13 0.17];  % deep teal-ink
            p.cardBg        = [0.11 0.17 0.22];
            p.divider       = [0.18 0.27 0.34];
            p.heading       = [0.73 0.78 0.82];  % #BAC7D0
            p.label         = [0.82 0.86 0.89];
            p.muted         = [0.55 0.64 0.70];
            p.primary       = [0.42 0.76 0.92];  % bright cyan
            p.success       = [0.45 0.85 0.62];
            p.danger        = [0.95 0.45 0.48];
            p.warning       = [0.98 0.76 0.38];
            p.purple        = [0.62 0.56 0.92];
            p.amber         = [0.93 0.84 0.48];
            p.accentBg      = [0.12 0.20 0.26];
            p.btnBg         = [0.15 0.22 0.28];
            p.btnFg         = [0.88 0.92 0.95];
            p.btnBgSecondary= [0.15 0.22 0.28];
            p.btnFgSecondary= [0.88 0.92 0.95];
            p.btnBgGhost    = [0.11 0.17 0.22];
            p.btnFgGhost    = [0.70 0.78 0.84];
            p.chartBg       = [0.11 0.17 0.22];
            p.chartAxis     = [0.82 0.86 0.89];
            p.chartGrid     = [0.18 0.27 0.34];
            p.navBg         = [0.04 0.08 0.11];
            p.navFg         = [0.82 0.86 0.89];
            p.navHoverBg    = [0.11 0.17 0.22];
            p.navActiveBg   = [0.22 0.55 0.70];
            p.navActiveFg   = [1.00 1.00 1.00];
            p.overlayBg     = [0.02 0.04 0.06];
            p.overlayText   = [0.88 0.92 0.95];
            p.overlayAccent = [0.42 0.76 0.92];
        end

        function p = paletteMonokai()
            % Monokai classic — Wimer Hazenberg.
            p = struct();
            p.bg            = [0.15 0.16 0.13];  % #272822
            p.cardBg        = [0.24 0.24 0.20];  % #3E3D32
            p.divider       = [0.33 0.34 0.29];
            p.heading       = [0.97 0.97 0.95];  % #F8F8F2
            p.label         = [0.85 0.85 0.83];
            p.muted         = [0.60 0.61 0.56];  % #75715E
            p.primary       = [0.98 0.15 0.45];  % pink #F92672
            p.success       = [0.65 0.89 0.18];  % green #A6E22E
            p.danger        = [0.98 0.15 0.45];
            p.warning       = [0.99 0.59 0.12];  % orange #FD971F
            p.purple        = [0.68 0.51 1.00];  % #AE81FF
            p.amber         = [0.90 0.86 0.45];  % yellow #E6DB74
            p.accentBg      = [0.20 0.20 0.16];
            p.btnBg         = [0.28 0.28 0.24];
            p.btnFg         = [0.97 0.97 0.95];
            p.btnBgSecondary= [0.28 0.28 0.24];
            p.btnFgSecondary= [0.97 0.97 0.95];
            p.btnBgGhost    = [0.20 0.20 0.16];
            p.btnFgGhost    = [0.80 0.80 0.76];
            p.chartBg       = [0.24 0.24 0.20];
            p.chartAxis     = [0.85 0.85 0.83];
            p.chartGrid     = [0.33 0.34 0.29];
            p.navBg         = [0.11 0.12 0.10];
            p.navFg         = [0.85 0.85 0.83];
            p.navHoverBg    = [0.20 0.20 0.16];
            p.navActiveBg   = [0.40 0.68 0.24];  % dimmed green
            p.navActiveFg   = [0.15 0.16 0.13];
            p.overlayBg     = [0.08 0.08 0.06];
            p.overlayText   = [0.97 0.97 0.95];
            p.overlayAccent = [0.98 0.15 0.45];
        end

        function p = paletteTwilight()
            % TextMate Twilight — dark neutral w/ muted orange accent.
            p = struct();
            p.bg            = [0.08 0.08 0.08];
            p.cardBg        = [0.14 0.14 0.14];
            p.divider       = [0.25 0.25 0.25];
            p.heading       = [0.94 0.94 0.94];
            p.label         = [0.85 0.85 0.85];
            p.muted         = [0.60 0.60 0.60];
            p.primary       = [0.81 0.42 0.30];  % rust #CF6A4C
            p.success       = [0.55 0.75 0.48];
            p.danger        = [0.80 0.30 0.35];
            p.warning       = [0.95 0.70 0.30];
            p.purple        = [0.60 0.47 0.80];
            p.amber         = [0.92 0.80 0.38];
            p.accentBg      = [0.11 0.11 0.11];
            p.btnBg         = [0.18 0.18 0.18];
            p.btnFg         = [0.92 0.92 0.92];
            p.btnBgSecondary= [0.18 0.18 0.18];
            p.btnFgSecondary= [0.92 0.92 0.92];
            p.btnBgGhost    = [0.11 0.11 0.11];
            p.btnFgGhost    = [0.75 0.75 0.75];
            p.chartBg       = [0.14 0.14 0.14];
            p.chartAxis     = [0.85 0.85 0.85];
            p.chartGrid     = [0.25 0.25 0.25];
            p.navBg         = [0.04 0.04 0.04];
            p.navFg         = [0.85 0.85 0.85];
            p.navHoverBg    = [0.11 0.11 0.11];
            p.navActiveBg   = [0.50 0.24 0.16];
            p.navActiveFg   = [0.97 0.85 0.76];
            p.overlayBg     = [0.00 0.00 0.00];
            p.overlayText   = [0.92 0.92 0.92];
            p.overlayAccent = [0.81 0.42 0.30];
        end

        function p = paletteWarmNeon()
            % WarmNeon — warm dark backdrop with vibrant neon accents.
            p = struct();
            p.bg            = [0.11 0.08 0.06];
            p.cardBg        = [0.17 0.12 0.10];
            p.divider       = [0.35 0.25 0.22];
            p.heading       = [1.00 0.90 0.76];  % bisque
            p.label         = [0.95 0.85 0.72];
            p.muted         = [0.70 0.62 0.55];
            p.primary       = [1.00 0.00 0.78];  % neon magenta
            p.success       = [0.00 0.98 0.62];  % neon mint
            p.danger        = [1.00 0.22 0.42];  % hot pink
            p.warning       = [1.00 0.68 0.00];
            p.purple        = [0.78 0.40 1.00];
            p.amber         = [1.00 0.82 0.00];
            p.accentBg      = [0.18 0.13 0.10];
            p.btnBg         = [0.22 0.16 0.13];
            p.btnFg         = [1.00 0.92 0.80];
            p.btnBgSecondary= [0.22 0.16 0.13];
            p.btnFgSecondary= [1.00 0.92 0.80];
            p.btnBgGhost    = [0.15 0.11 0.09];
            p.btnFgGhost    = [0.88 0.78 0.65];
            p.chartBg       = [0.17 0.12 0.10];
            p.chartAxis     = [0.95 0.85 0.72];
            p.chartGrid     = [0.35 0.25 0.22];
            p.navBg         = [0.06 0.04 0.03];
            p.navFg         = [0.95 0.85 0.72];
            p.navHoverBg    = [0.15 0.11 0.09];
            p.navActiveBg   = [1.00 0.00 0.78];
            p.navActiveFg   = [0.11 0.08 0.06];
            p.overlayBg     = [0.04 0.02 0.02];
            p.overlayText   = [1.00 0.92 0.80];
            p.overlayAccent = [0.00 0.98 0.62];
        end
    end
end
