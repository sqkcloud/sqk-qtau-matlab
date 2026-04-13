classdef StubAnalysisApp < handle
    % StubAnalysisApp  Minimal app double for AnalysisViewModel tests.
    %
    %   AnalysisViewModel.buildQVHeatmap(data) — now exposed publicly as
    %   renderComplexityLandscape — reads only three things off the app:
    %     - QVHeatmapAxes   (uiaxes to render into)
    %     - QVInfoLabel     (uilabel to update with circuit metrics)
    %     - styleAxes(ax)   (styling delegate)
    %
    %   This stub satisfies that contract without needing a full
    %   QTAUWorkbenchApp instance. Tests create the uiaxes / uilabel
    %   inside a headless uifigure and attach them to the stub.

    properties
        QVHeatmapAxes
        QVInfoLabel
    end

    methods
        function styleAxes(~, ax)
            % Delegate to the real StyleHelper so the test exercises the
            % same styling code path used in production.
            StyleHelper.styleAxes(ax);
        end
    end
end
