classdef StyleHelper
    % StyleHelper  Centralized component styling for the QTAU Workspace.
    %
    %   Extracted from QTAUWorkbenchApp to reduce class size.
    %   All methods are static — call as StyleHelper.styleBtn(btn, 'primary').

    methods (Static)

        function styleBtn(btn, variant)
            % Apply a consistent palette to any uibutton.
            %   variant: 'primary' | 'secondary' | 'success' | 'danger' | 'ghost'
            btn.FontSize = 14;
            btn.FontWeight = 'normal';
            btn.BackgroundColor = [1 1 1];
            btn.FontColor       = [0.15 0.15 0.15];
            switch lower(char(variant))
                case 'primary'
                    btn.BackgroundColor = [0.93 0.95 1.00];
                    btn.FontColor       = [0.13 0.33 0.73];
                    btn.FontWeight      = 'bold';
                case 'secondary'
                    btn.BackgroundColor = [0.96 0.96 0.97];
                    btn.FontColor       = [0.15 0.15 0.15];
                case 'success'
                    btn.BackgroundColor = [0.93 0.98 0.94];
                    btn.FontColor       = [0.13 0.40 0.18];
                    btn.FontWeight      = 'bold';
                case 'danger'
                    btn.BackgroundColor = [0.99 0.93 0.93];
                    btn.FontColor       = [0.70 0.15 0.15];
                    btn.FontWeight      = 'bold';
                case 'ghost'
                    btn.BackgroundColor = [0.96 0.96 0.97];
                    btn.FontColor       = [0.25 0.25 0.28];
            end
        end

        function styleAxes(ax)
            ax.Box = 'off'; ax.XGrid = 'on'; ax.YGrid = 'on';
            ax.GridColor = [0.82 0.86 0.92]; ax.GridAlpha = 0.9;
            ax.FontSize  = 11; ax.LineWidth = 1;
            ax.Color = [1 1 1];
            ax.XColor = [0.28 0.36 0.48]; ax.YColor = [0.28 0.36 0.48];
            try; axtoolbar(ax, {'zoom','pan','datacursor','restoreview'}); catch; end
        end

        function styleTable(tbl)
            try; tbl.RowStriping = 'on'; catch; end
            try; tbl.ColumnSortable = true(1, numel(tbl.ColumnName)); catch; end
        end

    end
end
