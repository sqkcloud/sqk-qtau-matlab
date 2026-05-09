classdef ComposerViewModel < handle
    % ComposerViewModel  Callback handlers for the Composer screen.
    %
    %   v0.1 — skeleton. The Composer screen renders a placeholder
    %   panel describing the planned features (gate palette, OpenQASM
    %   mirror, Templates gallery, Inspect mode footer). Wiring will
    %   land tier-by-tier in follow-up commits.
    %
    %   The screen still mounts cleanly into the existing
    %   NavigationManager / autoLoadScreen lifecycle so the new
    %   sidebar entry is fully functional (clickable, routes correctly,
    %   shows a real screen rather than a 404). LastRefresh is
    %   maintained for consistency with the freshness-check protocol
    %   used by every other ViewModel in the app.

    properties
        LastRefresh = []  % tic value — populated on first paint
    end

    properties (Access = private)
        App  % QTAUWorkbenchApp
    end

    methods
        function obj = ComposerViewModel(app)
            obj.App = app;
        end

        function onTemplateClicked(~, templateId)
            % Placeholder for v0.1 — clicking a template card will
            % instantiate its parameterized OpenQASM into the canvas.
            % v0.05 just logs which template was selected.
            Logger.info('ComposerViewModel', ...
                'Template clicked: %s (handler pending v0.1)', char(templateId));
        end
    end
end
