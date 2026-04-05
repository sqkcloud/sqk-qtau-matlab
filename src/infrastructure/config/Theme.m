classdef Theme
    % Theme  Centralized UI constants for the QTAU Workspace.
    %   Use Theme.COLOR_BG, Theme.BTN_HEIGHT, etc. to avoid magic numbers.

    properties (Constant)
        % ── Base Colors ──────────────────────────────────────────────────
        COLOR_BG         = [0.96 0.97 0.99]
        COLOR_CARD       = [1 1 1]
        COLOR_DIVIDER    = [0.87 0.90 0.93]
        COLOR_HEADING    = [0.18 0.26 0.40]
        COLOR_LABEL      = [0.28 0.36 0.48]
        COLOR_MUTED      = [0.38 0.46 0.58]

        % ── Accent Colors ────────────────────────────────────────────────
        COLOR_PRIMARY    = [0.18 0.45 0.82]
        COLOR_SUCCESS    = [0.10 0.54 0.36]
        COLOR_PURPLE     = [0.62 0.38 0.82]
        COLOR_AMBER      = [0.75 0.48 0.10]

        % ── Font Sizes ───────────────────────────────────────────────────
        FONT_SIZE_SM     = 11
        FONT_SIZE        = 12
        FONT_SIZE_MD     = 13
        FONT_SIZE_LG     = 14
        FONT_SIZE_TITLE  = 15

        % ── Layout Sizes ─────────────────────────────────────────────────
        BTN_ROW_HEIGHT   = 34
        ACTION_BAR_HEIGHT = 72
        BTN_WIDTH        = 110
        DIVIDER_WIDTH    = 6
        GRID_PADDING     = [16 16 16 16]
        GRID_ROW_SPACING = 12
        KPI_INNER_PAD    = [10 8 10 8]
    end
end
