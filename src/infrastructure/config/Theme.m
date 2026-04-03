classdef Theme
    % Theme  Centralized UI constants for the QTAU Workspace.
    %   Use Theme.COLOR_BG, Theme.BTN_HEIGHT, etc. to avoid magic numbers.

    properties (Constant)
        % Colors
        COLOR_BG         = [0.96 0.97 0.99]
        COLOR_CARD       = [1 1 1]
        COLOR_DIVIDER    = [0.87 0.90 0.93]
        COLOR_HEADING    = [0.18 0.26 0.40]
        COLOR_LABEL      = [0.28 0.36 0.48]
        COLOR_MUTED      = [0.38 0.46 0.58]

        % Sizes
        BTN_ROW_HEIGHT   = 34
        ACTION_BAR_HEIGHT = 72
        BTN_WIDTH        = 110
        FONT_SIZE        = 12
        GRID_PADDING     = [16 16 16 16]
    end
end
