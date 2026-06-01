classdef StyleHelper
    % StyleHelper  Centralized component styling for the QTAU Workspace.
    %
    %   All button / axes colors are derived from the active Theme palette
    %   so theme switches take effect on the next rebuild of the component.

    methods (Static)

        function styleBtn(btn, variant)
            % Apply the active-palette style to any uibutton.
            %   variant: 'primary' | 'secondary' | 'success' | 'danger' | 'ghost'
            %   All variants share the same FontColor and FontWeight —
            %   only the BackgroundColor differentiates variants.
            btn.FontSize   = 14;
            btn.FontWeight = 'normal';
            btn.BackgroundColor = Theme.BTN_BG_DEFAULT;
            btn.FontColor       = Theme.BTN_FG_DEFAULT;
            switch lower(char(variant))
                case 'primary'
                    btn.BackgroundColor = Theme.COLOR_ACCENT_BG;
                case 'secondary'
                    btn.BackgroundColor = Theme.BTN_BG_SECONDARY;
                case 'success'
                    btn.BackgroundColor = StyleHelper.tintBg(Theme.COLOR_SUCCESS, 0.85);
                case 'danger'
                    btn.BackgroundColor = StyleHelper.tintBg(Theme.COLOR_DANGER, 0.85);
                case 'ghost'
                    btn.BackgroundColor = Theme.BTN_BG_GHOST;
            end
        end

        function styleAxes(ax)
            % Chrome-only theming: grid, axis colors, background. Plot trace
            % colors are left to the caller so measured data always renders
            % with its intended meaning across themes.
            ax.Box = 'off'; ax.XGrid = 'on'; ax.YGrid = 'on';
            ax.GridColor  = Theme.CHART_GRID;
            ax.GridAlpha  = 0.9;
            ax.FontSize   = 11; ax.LineWidth = 1;
            ax.Color      = Theme.CHART_BG;
            ax.XColor     = Theme.CHART_AXIS;
            ax.YColor     = Theme.CHART_AXIS;
            StyleHelper.hideAxesToolbar(ax);
        end

        function hideAxesToolbar(ax)
            % Hide the floating axes hover-toolbar (datatip / pan / zoom /
            % home / restore) and disable default interactivity. Charts in
            % this app are static read-only views — the toolbar adds visual
            % noise without affording anything users need.
            try; ax.Toolbar.Visible = 'off'; catch; end
            try; ax.Interactions = []; catch; end
            try; disableDefaultInteractivity(ax); catch; end
        end

        function styleTable(tbl)
            try; tbl.RowStriping = 'on'; catch; end
            try; tbl.ColumnSortable = true(1, numel(tbl.ColumnName)); catch; end
        end

    end

    methods (Static, Access = private)
        function c = tintBg(color, mix)
            % Blend a color toward white by `mix` (0 = color, 1 = white).
            % Used so accent buttons get a subtle, palette-consistent tint.
            % On dark themes the white blend would wash out; blend toward
            % the card bg instead so success/danger buttons remain legible.
            cardBg = Theme.COLOR_CARD;
            if mean(cardBg) < 0.5
                target = cardBg;
            else
                target = [1 1 1];
            end
            c = mix * target + (1 - mix) * color;
        end
    end
end
