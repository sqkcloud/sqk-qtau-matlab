classdef Theme
    % Theme  Runtime-swappable color palette + layout constants.
    %
    %   7 curated themes: light, dark, solarized_light, solarized_dark, nord,
    %   dracula, high_contrast. The active palette is a module-level
    %   persistent struct; switch with Theme.setActive(name). Changes survive
    %   app restart via MATLAB's preference store ('QTAUWorkbench' group).
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
            'high_contrast',    'High Contrast'};
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
            % Returns the saved theme name, or 'light' if unset / invalid.
            name = 'light';
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
                case {'light', 'solarized_light'}
                    mode = 'light';
                otherwise
                    mode = 'dark';   % dark, solarized_dark, nord, dracula, high_contrast
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
                storedPal  = Theme.loadPalette('light');
                storedName = 'light';
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
                otherwise;               p = Theme.paletteLight();
            end
        end

        % ── Palette definitions ───────────────────────────────────────────
        % Every palette MUST expose the same set of fields. Missing fields
        % render bright magenta (see Theme.get) so regressions are visible.

        function p = paletteLight()
            p = struct();
            p.bg            = [0.96 0.97 0.99];
            p.cardBg        = [1.00 1.00 1.00];
            p.divider       = [0.87 0.90 0.93];
            p.heading       = [0.18 0.26 0.40];
            p.label         = [0.28 0.36 0.48];
            p.muted         = [0.38 0.46 0.58];
            p.primary       = [0.18 0.45 0.82];
            p.success       = [0.10 0.54 0.36];
            p.danger        = [0.70 0.15 0.15];
            p.warning       = [0.85 0.55 0.10];
            p.purple        = [0.62 0.38 0.82];
            p.amber         = [0.75 0.48 0.10];
            p.accentBg      = [0.94 0.97 1.00];
            p.btnBg         = [0.96 0.96 0.97];
            p.btnFg         = [0.15 0.15 0.15];
            p.btnBgSecondary= [0.96 0.96 0.97];
            p.btnFgSecondary= [0.15 0.15 0.15];
            p.btnBgGhost    = [0.96 0.96 0.97];
            p.btnFgGhost    = [0.25 0.25 0.28];
            p.chartBg       = [1.00 1.00 1.00];
            p.chartAxis     = [0.28 0.36 0.48];
            p.chartGrid     = [0.82 0.86 0.92];
            p.navBg         = [0.16 0.24 0.39];
            p.navFg         = [0.92 0.96 1.00];
            p.navHoverBg    = [0.20 0.31 0.48];
            p.navActiveBg   = [0.29 0.49 0.82];
            p.navActiveFg   = [1.00 1.00 1.00];
            p.overlayBg     = [0.00 0.00 0.00];  % black, 70% alpha in CSS
            p.overlayText   = [0.90 0.94 1.00];
            p.overlayAccent = [0.38 0.65 0.98];
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
    end
end
