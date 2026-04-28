classdef OverlayManager
    % OverlayManager  Manages loading spinners, auth overlay, event logging,
    %                  and error display for the QTAU Workspace.
    %
    %   Extracted from QTAUWorkbenchApp to reduce class size.
    %   All methods are static — call as OverlayManager.showLoading(app, msg).

    methods (Static)

        function showLoading(app, msg, showTimer)
            if nargin < 2; msg = 'Loading...'; end
            if nargin < 3; showTimer = false; end
            % Any prior nav auto-dismiss timer is stale the moment a
            % fresh overlay is shown — clear it so it doesn't fire mid-
            % flight on this new overlay.
            try; NavigationManager.disarmNavOverlayTimer(app); catch; end
            try
                if ~isempty(app.ActivityOverlay) && isvalid(app.ActivityOverlay)
                    % Drain any in-flight peerEvents (size-change /
                    % position-update messages from MATLAB's HTML
                    % bridge) BEFORE deleting the overlay. A bare
                    % delete() races with those queued events and the
                    % dispatcher then hits a deleted Model, surfacing
                    % the noisy "Invalid or deleted object" trace
                    % through HTMLController/getComponentToApply…
                    drawnow;
                    pause(0.05);
                    drawnow;
                    delete(app.ActivityOverlay);
                end
                % When a modal secondary dialog (e.g. the Quantum Monte Carlo
                % popup) is open, MATLAB renders it in its own window so an
                % overlay parented to the main UIFigure would sit behind it.
                % Parent the overlay to whichever figure is currently on top.
                host = app.UIFigure;
                try
                    if isprop(app, 'QmcDialog') && ~isempty(app.QmcDialog) ...
                            && isvalid(app.QmcDialog) && strcmp(app.QmcDialog.Visible, 'on')
                        host = app.QmcDialog;
                    end
                catch; end
                figW = host.Position(3);
                figH = host.Position(4);
                % Use uihtml as a full-figure overlay with semi-transparent backdrop
                app.ActivityOverlay = uihtml(host);
                app.ActivityOverlay.Position = [0 0 figW figH];
                % Elapsed timer JS (only rendered when showTimer is true)
                if showTimer
                    timerHtml = [ ...
                        '<p class="elapsed" id="elapsed">0s elapsed</p>' ...
                        '<script>' ...
                        'var t=0;setInterval(function(){t++;' ...
                        'var m=Math.floor(t/60),s=t%60;' ...
                        'document.getElementById("elapsed").textContent=' ...
                        'm>0?(m+"m "+s+"s elapsed"):(s+"s elapsed");' ...
                        '},1000);' ...
                        '</script>'];
                else
                    timerHtml = '';
                end
                overlayBg     = Theme.toHex(Theme.OVERLAY_BG);
                spinnerBorder = Theme.toHex(Theme.COLOR_DIVIDER);
                spinnerAccent = Theme.toHex(Theme.OVERLAY_ACCENT);
                msgColor      = Theme.toHex(Theme.OVERLAY_TEXT);
                subColor      = Theme.toHex(Theme.COLOR_MUTED);
                app.ActivityOverlay.HTMLSource = [ ...
                    '<html><head><style>' ...
                    'body{margin:0;padding:0;height:100%;overflow:hidden;' ...
                    'font-family:-apple-system,"Segoe UI",Arial,sans-serif;}' ...
                    '.overlay{position:fixed;top:0;left:0;width:100%;height:100%;' ...
                    'background:' overlayBg 'b3;display:flex;' ...
                    'align-items:center;justify-content:center;' ...
                    'backdrop-filter:blur(2px);-webkit-backdrop-filter:blur(2px);}' ...
                    '.content{text-align:center;}' ...
                    '.spinner{width:36px;height:36px;border:4px solid ' spinnerBorder ';' ...
                    'border-top-color:' spinnerAccent ';border-radius:50%;' ...
                    'animation:spin 0.85s linear infinite;margin:0 auto;}' ...
                    '@keyframes spin{to{transform:rotate(360deg)}}' ...
                    '.msg{margin-top:14px;font-size:13px;color:' msgColor ';' ...
                    'letter-spacing:0.03em;font-weight:500;}' ...
                    '.elapsed{margin-top:6px;font-size:11px;color:' subColor ';' ...
                    'font-variant-numeric:tabular-nums;}' ...
                    '</style></head><body>' ...
                    '<div class="overlay"><div class="content">' ...
                    '<div class="spinner"></div>' ...
                    '<p class="msg">' char(msg) '</p>' ...
                    timerHtml ...
                    '</div></div></body></html>'];
                uistack(app.ActivityOverlay, 'top');
                drawnow();
            catch ME
                Logger.debug('OverlayManager', 'showLoading: %s', ME.message);
            end
        end

        function hideLoading(app)
            % Dismiss the safety timer so a late fire can't pop an
            % unrelated overlay on a subsequent nav.
            try; NavigationManager.disarmNavOverlayTimer(app); catch; end
            try
                if ~isempty(app.ActivityOverlay) && isvalid(app.ActivityOverlay)
                    % Drain in-flight peerEvents so the dispatcher
                    % doesn't race with delete() — same fix as the
                    % showLoading() pre-delete above.
                    drawnow;
                    pause(0.05);
                    drawnow;
                    delete(app.ActivityOverlay);
                    app.ActivityOverlay = [];
                end
                drawnow();
            catch ME
                Logger.debug('OverlayManager', 'hideLoading: %s', ME.message);
            end
        end

        function showAuthOverlay(app)
            if ~isempty(app.AuthOverlay) && isvalid(app.AuthOverlay)
                OverlayManager.fitAuthOverlay(app);
                app.AuthOverlay.Visible = 'on';
                uistack(app.AuthOverlay, 'top');
            end
        end

        function hideAuthOverlay(app)
            if ~isempty(app.AuthOverlay) && isvalid(app.AuthOverlay)
                app.AuthOverlay.Visible = 'off';
            end
        end

        function fitAuthOverlay(app)
            if ~isempty(app.AuthOverlay) && isvalid(app.AuthOverlay)
                pos = app.ContentContainer.Position;
                app.AuthOverlay.Position = [0 0 max(1, pos(3)) max(1, pos(4))];
            end
        end

        function showError(app, context, ME)
            % Display a standardized error popup with title "Error".
            % Strips internal server hosts from MATLAB's webread error
            % messages so deployment internals don't leak into the
            % user-visible popup. The full URL still hits the event
            % log for operator debugging.
            detail = OverlayManager.sanitizeErrorMessage(ME.message);
            msg = sprintf('%s\n\nDetails:\n%s\n\nIdentifier: %s', ...
                char(context), detail, ME.identifier);
            OverlayManager.logEvent(app, 'ERROR', sprintf('[%s] %s', char(context), ME.message));
            uialert(app.UIFigure, msg, Labels.get('error_title', 'Error'), 'Icon', 'error');
        end

        function out = sanitizeErrorMessage(text)
            % Replace the host:port portion of any embedded URL with
            % nothing (keeping the path) so the server's internal
            % address never reaches the popup. MATLAB's webservices
            % errors look like:
            %   "... in response to the request to URL
            %    http://34.42.87.190:5715/api/circuits/.../cutting/batches"
            % After sanitization:
            %   "... in response to the request to URL
            %    /api/circuits/.../cutting/batches"
            % The path is still informative for triage; the host stays
            % private.
            try
                out = regexprep(char(text), 'https?://[^/\s]+', '');
            catch
                out = char(text);
            end
        end

        function logEvent(app, category, msg)
            ts   = char(datetime('now', 'Format', 'HH:mm:ss.SSS'));
            line = sprintf('[%s] %-8s [QTAUWorkbenchApp] %s', ts, upper(char(category)), char(msg));
            if isempty(app.EventLog)
                app.EventLog = {line};
            else
                app.EventLog = [{line}; app.EventLog(1:min(end, 999))];
            end
            fprintf('%s\n', line);
            try
                if ~isempty(app.EventLogArea) && isvalid(app.EventLogArea)
                    app.EventLogArea.Value = app.EventLog(1:min(numel(app.EventLog), 200));
                end
            catch ME; fprintf('[QTAUWorkbenchApp] EventLogArea update: %s\n', ME.message); end
        end

        function setStatus(area, lines)
            if ischar(lines) || isstring(lines)
                lines = cellstr(string(lines));
            end
            area.Value = lines;
        end

    end
end
