classdef ChartHelper
    % ChartHelper  Reusable chart-rendering primitives for Workbench screens.
    %
    %   All methods are static and stateless — call as
    %   ChartHelper.drawRadarChart(ax, names, sims, colors).
    %
    %   Extracted from AnalysisViewModel to keep that class focused on
    %   orchestration and to make the chart primitives reusable from
    %   other screens (DetailedAnalysis, Benchmark, etc.).

    methods (Static)

        function drawRadarChart(ax, names, sims, colors)
            % Draw a radar/spider chart on the given axes.
            n = numel(names);
            angles = linspace(0, 2*pi, n + 1);
            angles = angles(1:n);

            cla(ax); hold(ax, 'on');
            ax.Visible = 'off';

            % Draw concentric grid rings
            gridLevels = [0.2, 0.4, 0.6, 0.8, 1.0];
            for gl = gridLevels
                theta = linspace(0, 2*pi, 100);
                plot(ax, gl * cos(theta), gl * sin(theta), '-', ...
                    'Color', [0.85 0.85 0.85], 'LineWidth', 0.5);
                text(ax, 0.03, gl + 0.04, sprintf('%.0f%%', gl*100), ...
                    'FontSize', 8, 'Color', [0.5 0.5 0.5], 'Interpreter', 'none');
            end

            % Draw axis spokes and labels
            for i = 1:n
                cx = cos(angles(i)); cy = sin(angles(i));
                plot(ax, [0 cx], [0 cy], '-', 'Color', [0.82 0.82 0.82], 'LineWidth', 0.5);
                lbl = names{i};
                if length(lbl) > 18; lbl = [lbl(1:16) '..']; end
                ha = 'center';
                if cx > 0.1; ha = 'left'; elseif cx < -0.1; ha = 'right'; end
                text(ax, cx * 1.22, cy * 1.22, lbl, ...
                    'FontSize', 10, 'FontWeight', 'bold', ...
                    'HorizontalAlignment', ha, ...
                    'VerticalAlignment', 'middle', ...
                    'Color', [0.20 0.25 0.38], 'Interpreter', 'none');
            end

            % Draw filled polygon
            rx = sims .* cos(angles(:));
            ry = sims .* sin(angles(:));
            fill(ax, [rx; rx(1)], [ry; ry(1)], [0.23 0.53 0.87], ...
                'FaceAlpha', 0.20, 'EdgeColor', [0.15 0.40 0.78], 'LineWidth', 2);

            % Draw data points with score labels
            for i = 1:n
                plot(ax, rx(i), ry(i), 'o', 'MarkerSize', 8, ...
                    'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', [1 1 1], 'LineWidth', 1.5);
            end

            hold(ax, 'off');
            ax.XLim = [-1.5 1.5]; ax.YLim = [-1.5 1.5];
            ax.DataAspectRatio = [1 1 1];
            title(ax, 'Radar — Similarity Profile', 'FontSize', 14, ...
                'FontWeight', 'bold', 'Visible', 'on');
        end

        function drawCategoryDonut(ax, cats, sims, uniqueCats, palette)
            % Draw a donut chart showing average similarity per category.
            nCats = numel(uniqueCats);
            avgSims = zeros(nCats, 1);
            counts  = zeros(nCats, 1);
            for i = 1:numel(cats)
                ci = find(strcmp(uniqueCats, cats{i}), 1);
                avgSims(ci) = avgSims(ci) + sims(i);
                counts(ci)  = counts(ci) + 1;
            end
            avgSims = avgSims ./ max(counts, 1);

            cla(ax); hold(ax, 'on');
            ax.Visible = 'off';

            % Pie angles
            total = sum(counts);
            startAngle = pi/2;
            for ci = 1:nCats
                frac = counts(ci) / total;
                endAngle = startAngle - frac * 2 * pi;
                theta = linspace(startAngle, endAngle, 80);
                outerR = 0.9;
                innerR = 0.50;
                xOuter = outerR * cos(theta);
                yOuter = outerR * sin(theta);
                xInner = innerR * cos(flip(theta));
                yInner = innerR * sin(flip(theta));
                clr = palette(mod(ci-1, size(palette,1)) + 1, :);
                fill(ax, [xOuter, xInner], [yOuter, yInner], clr, ...
                    'EdgeColor', [1 1 1], 'LineWidth', 2, 'FaceAlpha', 0.88);

                % Label outside the arc with a connecting line
                midAngle = (startAngle + endAngle) / 2;
                outerLabelR = 1.2;
                lx = outerLabelR * cos(midAngle);
                ly = outerLabelR * sin(midAngle);
                % Connector from arc edge to label
                edgeX = (outerR + 0.04) * cos(midAngle);
                edgeY = (outerR + 0.04) * sin(midAngle);
                plot(ax, [edgeX lx], [edgeY ly], '-', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8);
                ha = 'left';
                if lx < 0; ha = 'right'; end
                text(ax, lx, ly, sprintf('%s (%.0f%%)', uniqueCats{ci}, avgSims(ci)*100), ...
                    'FontSize', 10, 'FontWeight', 'bold', 'Color', clr, ...
                    'HorizontalAlignment', ha, 'VerticalAlignment', 'middle', ...
                    'Interpreter', 'none');
                startAngle = endAngle;
            end

            % Center label — overall average
            text(ax, 0, 0.06, sprintf('%.1f%%', mean(sims)*100), ...
                'FontSize', 22, 'FontWeight', 'bold', 'Color', [0.18 0.28 0.50], ...
                'HorizontalAlignment', 'center', 'Interpreter', 'none');
            text(ax, 0, -0.14, 'avg similarity', ...
                'FontSize', 10, 'Color', [0.5 0.5 0.6], ...
                'HorizontalAlignment', 'center', 'Interpreter', 'none');

            hold(ax, 'off');
            ax.XLim = [-1.7 1.7]; ax.YLim = [-1.5 1.5];
            ax.DataAspectRatio = [1 1 1];
            title(ax, 'Category Breakdown', 'FontSize', 14, ...
                'FontWeight', 'bold', 'Visible', 'on');
        end

    end
end
