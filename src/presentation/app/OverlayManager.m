classdef OverlayManager
    % OverlayManager  Manages loading spinners, auth overlay, event logging,
    %                  and error display for the QTAU Workspace.
    %
    %   Extracted from QTAUWorkbenchApp to reduce class size.
    %   All methods are static — call as OverlayManager.showLoading(app, msg).
    %
    % ┌────────────────────────────────────────────────────────────────────┐
    % │  LOADING-SCREEN CONVENTIONS  (Phase 6.4 — applies app-wide)        │
    % ├────────────────────────────────────────────────────────────────────┤
    % │ 1. Preferred entrypoint                                            │
    % │      app.runAsyncWithLoading(msg, work, onOk, onErr)               │
    % │      app.runSyncWithLoading(msg, fn)                               │
    % │    Both guarantee show + hide pairing including on the error path. │
    % │    Existing app.showLoading / app.hideLoading still work for       │
    % │    legacy paired call sites; do not migrate just for migration's   │
    % │    sake.                                                           │
    % │                                                                    │
    % │ 2. Message text                                                    │
    % │    Always go through Labels.get('loading_<scope>_<action>',        │
    % │                                  '<English fallback>').            │
    % │    Format: "<Verb-ing> <object>..."                                │
    % │      - 3 ASCII dots, NEVER U+2026 ellipsis (the idempotent guard   │
    % │        in showLoading is char-equal so a single Unicode mismatch   │
    % │        defeats the dedup and reintroduces the double-flicker).    │
    % │      - Capitalize the first letter, no trailing space.             │
    % │    Examples:                                                       │
    % │      loading_circuits_list   = Loading circuits...                 │
    % │      loading_jobs_submit     = Submitting job to IBM Quantum...    │
    % │      loading_em_report       = Generating Error Mitigation report. │
    % │                                                                    │
    % │ 3. Idempotency                                                     │
    % │    showLoading(msg) is a no-op when the overlay is already visible │
    % │    with that same msg + showTimer.  Calling show twice in a row    │
    % │    with the same args does NOT cause a CEF re-render flicker.      │
    % │    See the fast-path check inside showLoading below.               │
    % │                                                                    │
    % │ 4. Pairing rules                                                   │
    % │    Every showLoading must be matched by a hideLoading on every     │
    % │    code path (success, error, cancel).  The runAsync/runSync       │
    % │    helpers wire this for you.  A 20s safety timer                  │
    % │    (NavigationManager.armNavOverlayTimer) catches forgotten hides. │
    % │                                                                    │
    % │ 5. Where the overlay parents                                       │
    % │    By default the overlay parents to app.UIFigure.  When a modal   │
    % │    dialog is open (Quantum Monte Carlo / Error Mitigation popup)   │
    % │    the overlay re-parents to that dialog automatically — see the   │
    % │    QmcDialog check at the top of showLoading.  Other dialogs that  │
    % │    want overlay coverage should follow the same isprop+isvalid     │
    % │    pattern.                                                        │
    % └────────────────────────────────────────────────────────────────────┘

    methods (Static)

        function showLoading(app, msg, showTimer, bgTaskId)
            if nargin < 2; msg = 'Loading...'; end
            if nargin < 3; showTimer = false; end
            if nargin < 4; bgTaskId = ''; end
            % Any prior nav auto-dismiss timer is stale the moment a
            % fresh overlay is shown — clear it so it doesn't fire mid-
            % flight on this new overlay.
            try; NavigationManager.disarmNavOverlayTimer(app); catch; end
            try
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
                % Same isprop+isvalid pattern for the Quantum Error
                % Mitigation popup so its async refresh paths (estimate
                % sweep + calibration fetch on backend / level / form
                % change) get the standard spinner instead of an
                % unresponsive modal. Checked AFTER QmcDialog so an
                % EmDialog opened on top correctly takes priority.
                try
                    if isprop(app, 'EmDialog') && ~isempty(app.EmDialog) ...
                            && isvalid(app.EmDialog) && strcmp(app.EmDialog.Visible, 'on')
                        host = app.EmDialog;
                    end
                catch; end
                figW = host.Position(3);
                figH = host.Position(4);

                % Singleton overlay strategy: lazy-create one ActivityOverlay
                % per host figure and REUSE it across every show/hide cycle.
                % We never delete it during normal flow — only on a host
                % change (e.g. UIFigure → QmcDialog when a modal opens) do
                % we tear down the previous instance.
                %
                % Why: any delete() of a uihtml component races with
                % MATLAB's asynchronous JS↔server peerEvent bridge. Even a
                % drawnow + pause + drawnow drain isn't a hard guarantee —
                % the JS side can emit a new event in the window between
                % drawnow returning and delete() running, and the
                % dispatcher then throws "Invalid or deleted object" inside
                % HTMLController/getComponentToApplyButtonEvent. The only
                % bullet-proof fix is to keep the component alive for the
                % lifetime of its host. MATLAB tears children down when
                % the host figure dies, so leak-free.
                needCreate = isempty(app.ActivityOverlay) ...
                    || ~isvalid(app.ActivityOverlay);
                if ~needCreate
                    try
                        needCreate = ~isequal(app.ActivityOverlay.Parent, host);
                    catch
                        needCreate = true;
                    end
                end
                if needCreate
                    % Host change is the only path that still requires a
                    % delete. Drain first so this rare path is also safe.
                    if ~isempty(app.ActivityOverlay) && isvalid(app.ActivityOverlay)
                        try; app.ActivityOverlay.Visible = 'off'; catch; end
                        drawnow;
                        pause(0.1);
                        drawnow;
                        delete(app.ActivityOverlay);
                    end
                    app.ActivityOverlay = uihtml(host);
                    % Park the freshly-built overlay off-screen until we
                    % decide to actually show it. A new uihtml() spans
                    % its default rectangle and could swallow CEF clicks
                    % for a tick before we paint.
                    try
                        app.ActivityOverlay.Position = [-99999 -99999 1 1];
                    catch
                    end
                end
                % DELIBERATELY do NOT set Position to [0 0 figW figH] here.
                % It is assigned immediately before Visible='on' below,
                % so an exception or the idempotent fast-path return
                % cannot leave a zombie full-figure overlay with
                % Visible='off' — the prior failure mode that swallowed
                % uibutton / uitable / sidebar clicks on R2025b macOS.

                % ── Idempotent fast path ─────────────────────────────────
                % If the overlay is already visible with the same message
                % and showTimer flag, skip the HTMLSource rebuild.  Setting
                % HTMLSource forces the CEF browser to tear down + remount
                % the entire DOM, which produces a visible flicker on
                % every nav click (the "loading-twice" symptom: build-time
                % overlay -> autoLoadScreen overlay).  The cache lives on
                % the overlay's own UserData property so no new
                % QTAUWorkbenchApp property is needed.
                cachedMsg = '';
                cachedShowTimer = [];
                try
                    ud = app.ActivityOverlay.UserData;
                    if isstruct(ud)
                        if isfield(ud, 'lastMsg');       cachedMsg = ud.lastMsg; end
                        if isfield(ud, 'lastShowTimer'); cachedShowTimer = ud.lastShowTimer; end
                    end
                catch
                end
                alreadyShown = ~needCreate && ...
                    strcmp(app.ActivityOverlay.Visible, 'on');
                if alreadyShown && isequal(cachedMsg, char(msg)) ...
                        && isequal(cachedShowTimer, showTimer)
                    drawnow();
                    return;
                end
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
                % Size to full figure ONLY at the moment we are about
                % to flip Visible='on'. Pairs with the deferred-assign
                % comment above.
                app.ActivityOverlay.Position = [0 0 figW figH];
                app.ActivityOverlay.Visible = 'on';
                uistack(app.ActivityOverlay, 'top');
                % Persist (msg, showTimer) so the next showLoading call with
                % identical args can short-circuit via the idempotent fast
                % path above and skip the HTMLSource rebuild flicker.
                try
                    app.ActivityOverlay.UserData = struct( ...
                        'lastMsg', char(msg), 'lastShowTimer', showTimer);
                catch
                end

                % "Run in background" button — only shown when the caller
                % registered a background task whose poll keeps running
                % after the overlay is dismissed.
                OverlayManager.ensureOverlayBgButton(app, host, bgTaskId, figW, figH);

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
                    % Hide instead of delete — keeps the uihtml component
                    % alive so any subsequent peerEvents from MATLAB's HTML
                    % bridge land on a still-valid Model instead of throwing
                    % 'Invalid or deleted object' inside
                    % HTMLController/getComponentToApply… The component is
                    % torn down only when the host figure itself is closed,
                    % which is automatic.
                    app.ActivityOverlay.Visible = 'off';
                    % Move the still-alive uihtml off-screen. Visible='off'
                    % alone is NOT sufficient on R2025b uifigure (macOS
                    % especially): a hidden uihtml sitting at top of the
                    % Z-order with a full-figure Position still owns the
                    % CEF pointer hit-test rectangle and silently
                    % swallows uibutton / uieditfield clicks, the
                    % figure-level WindowButtonDownFcn, and uitable
                    % SelectionChangedFcn for everything underneath.
                    % We can't uistack(...,'bottom') because that
                    % triggers a CEF refresh across every HTML-backed
                    % component (the uitable rendered rows empty out)
                    % and we can't delete the component because the
                    % peerEvent bridge races with delete() (see the
                    % singleton-overlay comment in showLoading). The
                    % off-screen Position is the only safe escape: keeps
                    % the component alive for the peerEvent bridge,
                    % doesn't trigger any CEF refresh, and is physically
                    % incapable of capturing clicks. showLoading
                    % reassigns Position = [0 0 figW figH] on the next
                    % show (see line above), so this is self-restoring.
                    try
                        app.ActivityOverlay.Position = [-99999 -99999 1 1];
                    catch
                    end
                end
                try
                    if ~isempty(app.OverlayBgButton) && isvalid(app.OverlayBgButton)
                        app.OverlayBgButton.Visible = 'off';
                        % Same off-screen escape — ensureOverlayBgButton
                        % repositions on next show.
                        try
                            app.OverlayBgButton.Position = [-99999 -99999 1 1];
                        catch
                        end
                    end
                catch
                end
                drawnow();
            catch ME
                Logger.debug('OverlayManager', 'hideLoading: %s', ME.message);
            end
        end

        function ensureOverlayBgButton(app, host, bgTaskId, figW, figH)
            % Lazily create or reposition the "Run in background" uibutton
            % sitting on top of the activity overlay. Hidden when bgTaskId
            % is empty so non-background loads (the vast majority of
            % showLoading sites) keep the original look.
            try
                if isempty(bgTaskId)
                    if ~isempty(app.OverlayBgButton) && isvalid(app.OverlayBgButton)
                        app.OverlayBgButton.Visible = 'off';
                    end
                    return;
                end
                needCreate = isempty(app.OverlayBgButton) ...
                    || ~isvalid(app.OverlayBgButton) ...
                    || ~isequal(app.OverlayBgButton.Parent, host);
                if needCreate
                    if ~isempty(app.OverlayBgButton) && isvalid(app.OverlayBgButton)
                        try; delete(app.OverlayBgButton); catch; end
                    end
                    app.OverlayBgButton = uibutton(host, ...
                        'Text', 'Run in background', ...
                        'FontSize', 12, ...
                        'FontWeight', 'bold');
                    try
                        app.OverlayBgButton.BackgroundColor = Theme.OVERLAY_ACCENT;
                        app.OverlayBgButton.FontColor       = Theme.OVERLAY_TEXT;
                    catch
                    end
                end
                btnW = 180; btnH = 32;
                btnX = max(8, (figW - btnW) / 2);
                btnY = max(8, figH/2 - 86);
                app.OverlayBgButton.Position = [btnX btnY btnW btnH];
                app.OverlayBgButton.ButtonPushedFcn = ...
                    @(~,~) app.runInBackground(char(bgTaskId));
                app.OverlayBgButton.Visible = 'on';
                try; uistack(app.OverlayBgButton, 'top'); catch; end
            catch ME
                Logger.debug('OverlayManager', ...
                    'ensureOverlayBgButton: %s', ME.message);
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
            %    https://qtau.example.com/api/circuits/.../cutting/batches"
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
            % Rate-limit the EventLogArea repaint to ~100 ms intervals.
            % Setting `uitextarea.Value` to a 200-element cell marshals
            % every line across the JS↔CEF bridge and schedules a paint
            % (~10 ms each). A typical nav fires 5–8 logEvents (NAV +
            % API request + API response + completion + activity-log)
            % and would otherwise pay 50–80 ms of pure UI thread time
            % per nav — which the user perceives as "loading" delay.
            % The in-memory EventLog cell array above is updated
            % unthrottled so no message is ever lost; the visible
            % textarea catches up on the next non-throttled tick (any
            % subsequent logEvent more than 100 ms later).
            persistent lastUiUpdate;
            doUpdate = isempty(lastUiUpdate) || toc(lastUiUpdate) >= 0.1;
            if doUpdate
                try
                    if ~isempty(app.EventLogArea) && isvalid(app.EventLogArea)
                        app.EventLogArea.Value = app.EventLog(1:min(numel(app.EventLog), 200));
                        lastUiUpdate = tic;
                    end
                catch ME; fprintf('[QTAUWorkbenchApp] EventLogArea update: %s\n', ME.message); end
            end
        end

        function setStatus(area, lines)
            if ischar(lines) || isstring(lines)
                lines = cellstr(string(lines));
            end
            % Skip the write when content is unchanged. uitextarea
            % triggers a repaint on every Value assignment regardless of
            % whether the content actually changed, so a 5 s auto-
            % refresh that re-passes the same Live Monitor Notes lines
            % makes the panel flicker visibly. Compare against the
            % current Value first; only write when something differs.
            try
                cur = area.Value;
                if iscell(cur) && iscell(lines) && isequal(cur, lines)
                    return;
                end
            catch
                % If Value can't be read (deleted handle, racy nav, etc.)
                % fall through to the assignment — safe default.
            end
            area.Value = lines;
        end

    end
end
