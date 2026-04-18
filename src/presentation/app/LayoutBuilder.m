classdef LayoutBuilder
    % LayoutBuilder  One-time UI construction for the QTAU Workspace.
    %
    %   Extracted from QTAUWorkbenchApp to reduce class size.
    %   Builds the header, body (sidebar + content shell), and startup
    %   loading overlay.  All methods are static — call as
    %   LayoutBuilder.buildHeader(app).

    methods (Static)

        function buildHeader(app)
            app.HeaderGrid = uigridlayout(app.RootGrid, [1 3]);
            app.HeaderGrid.Layout.Row    = 1;
            app.HeaderGrid.Layout.Column = 1;
            app.HeaderGrid.ColumnWidth   = {250, '1x', 'fit'};
            app.HeaderGrid.RowHeight     = {52};
            app.HeaderGrid.Padding       = [0 0 12 2];
            app.HeaderGrid.BackgroundColor = Theme.NAV_BG;

            logoHost = uigridlayout(app.HeaderGrid, [1 1]);
            logoHost.Layout.Row = 1; logoHost.Layout.Column = 1;
            logoHost.RowHeight = {'1x'}; logoHost.ColumnWidth = {'1x'};
            logoHost.Padding = [0 0 10 0];
            logoHost.RowSpacing = 0; logoHost.ColumnSpacing = 0;
            logoHost.BackgroundColor = Theme.NAV_BG;

            logoPath = fullfile(fileparts(mfilename('fullpath')), '..', '..', '..', ...
                'resources', 'sqk-logo-kokkos-white1-reordered.svg');
            brandWrap = uigridlayout(logoHost, [1 2]);
            brandWrap.Layout.Row = 1; brandWrap.Layout.Column = 1;
            brandWrap.RowHeight = {'1x'}; brandWrap.ColumnWidth = {108, '1x'};
            brandWrap.Padding = [0 0 10 0];
            brandWrap.RowSpacing = 0; brandWrap.ColumnSpacing = 0;
            brandWrap.BackgroundColor = Theme.NAV_BG;
            try
                brand = uiimage(brandWrap);
                brand.ImageSource = logoPath;
                brand.ScaleMethod = 'fit';
                brand.Tooltip = 'SQK';
                brand.Layout.Row = 1; brand.Layout.Column = 1;
            catch
                brand = uilabel(brandWrap, 'Text', 'SQK');
                brand.FontSize = 14; brand.FontWeight = 'bold';
                brand.FontColor = Theme.NAV_FG;
                brand.HorizontalAlignment = 'left';
                brand.VerticalAlignment   = 'bottom';
                brand.Layout.Row = 1; brand.Layout.Column = 1;
            end

            subtitle = uilabel(app.HeaderGrid, 'Text', 'Connector Workspace');
            subtitle.FontSize = 14; subtitle.FontWeight = 'bold';
            subtitle.HorizontalAlignment = 'center';
            subtitle.FontColor = Theme.NAV_FG;
            subtitle.Layout.Row = 1; subtitle.Layout.Column = 2;

            headerRight = uigridlayout(app.HeaderGrid, [1 3]);
            headerRight.Layout.Row = 1; headerRight.Layout.Column = 3;
            headerRight.ColumnWidth = {'fit', 'fit', 'fit'};
            headerRight.Padding = [0 0 4 0]; headerRight.ColumnSpacing = 10;
            headerRight.BackgroundColor = Theme.NAV_BG;

            userBadge = uilabel(headerRight, 'Text', 'SQK Admin Workspace');
            userBadge.FontSize = 13; userBadge.FontWeight = 'bold';
            userBadge.HorizontalAlignment = 'right';
            userBadge.FontColor = Theme.NAV_FG;
            userBadge.Layout.Row = 1; userBadge.Layout.Column = 1;
            userBadge.Tooltip = 'QTAU Connector v2026';

            app.HeaderLoginButton = uihyperlink(headerRight, ...
                'Text', Labels.get('header_btn_login', 'Login'), ...
                'URL', '', ...
                'HyperlinkClickedFcn', @(~,~)app.showLoginDialog(), ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', Theme.NAV_FG, ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
            app.HeaderLoginButton.Layout.Row = 1; app.HeaderLoginButton.Layout.Column = 2;
            app.HeaderLoginButton.VisitedColor = Theme.NAV_FG;

            app.HeaderUserLabel = uihyperlink(headerRight, ...
                'Text', '', ...
                'URL', '', ...
                'HyperlinkClickedFcn', @(~,~)app.toggleHeaderUserMenu(), ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', Theme.NAV_FG, ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
            app.HeaderUserLabel.Layout.Row = 1; app.HeaderUserLabel.Layout.Column = 3;
            app.HeaderUserLabel.Visible = 'off';
            app.HeaderUserLabel.VisitedColor = Theme.NAV_FG;

            app.HeaderUserMenuPanel = uipanel(app.UIFigure, 'Title', '', ...
                'Position', [0 0 180 76], 'Visible', 'off', ...
                'BackgroundColor', Theme.COLOR_CARD, 'BorderType', 'line');
            mg = uigridlayout(app.HeaderUserMenuPanel, [2 1]);
            mg.RowHeight = {32, 32}; mg.ColumnWidth = {'1x'};
            mg.Padding = [4 4 4 4]; mg.RowSpacing = 2;
            mg.BackgroundColor = Theme.COLOR_CARD;

            accountBtn = uibutton(mg, 'Text', [char(9881) '  ' Labels.get('header_menu_my_account', 'My Account')], ...
                'HorizontalAlignment', 'left', 'FontSize', 15, ...
                'FontColor', Theme.COLOR_HEADING, 'BackgroundColor', Theme.COLOR_CARD, ...
                'ButtonPushedFcn', @(~,~)app.onHeaderMenuAction('account'));
            accountBtn.Layout.Row = 1; accountBtn.Layout.Column = 1;

            logoutBtn = uibutton(mg, 'Text', [char(9211) '  ' Labels.get('header_menu_logout', 'Logout')], ...
                'HorizontalAlignment', 'left', 'FontSize', 15, ...
                'FontColor', Theme.COLOR_DANGER, 'BackgroundColor', Theme.COLOR_CARD, ...
                'ButtonPushedFcn', @(~,~)app.onHeaderMenuAction('logout'));
            logoutBtn.Layout.Row = 2; logoutBtn.Layout.Column = 1;
        end

        function buildBody(app)
            app.BodyGrid = uigridlayout(app.RootGrid, [1 2]);
            app.BodyGrid.Layout.Row    = 2;
            app.BodyGrid.Layout.Column = 1;
            app.BodyGrid.ColumnWidth   = {260, '1x'};
            app.BodyGrid.RowHeight     = {'1x'};
            app.BodyGrid.Padding       = [0 0 0 0];
            app.BodyGrid.ColumnSpacing = 0;
            app.BodyGrid.BackgroundColor = Theme.COLOR_BG;

            % Sidebar
            app.NavPanel = uipanel(app.BodyGrid, 'Title', '');
            app.NavPanel.Layout.Row = 1; app.NavPanel.Layout.Column = 1;
            app.NavPanel.BackgroundColor = Theme.NAV_BG;

            navGrid = uigridlayout(app.NavPanel, [4 1]);
            navGrid.RowHeight = {44, 1, '1x', 28};
            navGrid.Padding = [10 10 10 10];
            navGrid.BackgroundColor = Theme.NAV_BG;

            topRow = uigridlayout(navGrid, [1 2]);
            topRow.Layout.Row = 1; topRow.Layout.Column = 1;
            topRow.ColumnWidth = {0, '1x'};
            topRow.Padding = [0 0 0 0];
            topRow.BackgroundColor = Theme.NAV_BG;

            navBrand = uilabel(topRow, 'Text', '');
            navBrand.Visible = 'off';
            navBrand.Layout.Row = 1; navBrand.Layout.Column = 1;

            app.NavToggleButton = uibutton(topRow, 'push', 'Text', char(8801), ...
                'ButtonPushedFcn', @(~,~)app.onToggleNav());
            app.NavToggleButton.Layout.Row = 1; app.NavToggleButton.Layout.Column = 2;
            app.NavToggleButton.FontSize = 18; app.NavToggleButton.FontWeight = 'bold';
            app.NavToggleButton.BackgroundColor = Theme.NAV_HOVER_BG;
            app.NavToggleButton.FontColor = Theme.NAV_FG;

            navSep = uipanel(navGrid, 'Title', '');
            navSep.Layout.Row = 2; navSep.Layout.Column = 1;
            navSep.BackgroundColor = Theme.COLOR_DIVIDER;
            navSep.BorderType = 'none';

            % Nav menu rendered via uihtml for consistent icon sizing
            app.NavHtml = uihtml(navGrid);
            app.NavHtml.Layout.Row = 3; app.NavHtml.Layout.Column = 1;
            app.NavHtml.DataChangedFcn = @(src, ~) NavigationManager.onNavHtmlClick(app, src);
            app.NavButtons = [];  % legacy — no longer used
            NavigationManager.renderNavHtml(app, 'Welcome', false);

            app.NavList = uilistbox(navGrid, 'Items', NavigationManager.navNames(), 'Visible', 'off');
            app.NavList.Value = 'Welcome';
            app.NavList.Layout.Row = 4; app.NavList.Layout.Column = 1;
            app.NavList.ValueChangedFcn = @(src,~)app.onSelectSection(string(src.Value));

            % Content shell
            app.ContentShell = uipanel(app.BodyGrid, 'Title', '');
            app.ContentShell.Layout.Row = 1; app.ContentShell.Layout.Column = 2;
            app.ContentShell.BackgroundColor = Theme.COLOR_BG;

            shellGrid = uigridlayout(app.ContentShell, [3 1]);
            shellGrid.RowHeight  = {82, 1, '1x'};
            shellGrid.Padding    = [20 16 20 16];
            shellGrid.RowSpacing = 12;
            shellGrid.BackgroundColor = Theme.COLOR_BG;
            app.ShellGrid = shellGrid;

            headerPanel = uipanel(shellGrid, 'Title', '', ...
                'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
            headerPanel.Layout.Row = 1; headerPanel.Layout.Column = 1;
            headerPanel.BackgroundColor = Theme.COLOR_CARD;
            app.HeaderSectionPanel = headerPanel;
            hg = uigridlayout(headerPanel, [2 1]);
            hg.RowHeight = {28, 20}; hg.Padding = [16 10 16 10];
            hg.BackgroundColor = Theme.COLOR_CARD;
            app.HeaderSectionGrid = hg;
            app.SectionTitleLabel = uilabel(hg, 'Text', 'Welcome');
            app.SectionTitleLabel.FontSize = 18; app.SectionTitleLabel.FontWeight = 'bold';
            app.SectionTitleLabel.FontColor = Theme.COLOR_HEADING;
            app.SectionTitleLabel.Layout.Row = 1; app.SectionTitleLabel.Layout.Column = 1;
            app.SectionSubtitleLabel = uilabel(hg, 'Text', 'Server authentication and project access');
            app.SectionSubtitleLabel.FontSize = 12;
            app.SectionSubtitleLabel.FontColor = Theme.COLOR_MUTED;
            app.SectionSubtitleLabel.Layout.Row = 2; app.SectionSubtitleLabel.Layout.Column = 1;

            sep = uipanel(shellGrid, 'Title', '');
            sep.Layout.Row = 2; sep.Layout.Column = 1;
            sep.BackgroundColor = Theme.COLOR_DIVIDER;
            app.HeaderSectionSep = sep;

            app.ContentContainer = uipanel(shellGrid, 'Title', '');
            app.ContentContainer.Layout.Row = 3; app.ContentContainer.Layout.Column = 1;
            app.ContentContainer.BackgroundColor = Theme.COLOR_BG;
            app.ContentContainer.AutoResizeChildren = 'off';
            app.ContentContainer.SizeChangedFcn = @(~,~)app.onResizeUI();

            app.SectionPanels = struct();
        end

        function repaintChrome(app)
            % Re-apply the active Theme to every chrome surface outside the
            % screen panels — header bar, nav rail, shell, section title
            % card, divider, toggle button, header user menu. The screen
            % panels themselves are destroyed and rebuilt separately.
            %
            % MATLAB caches the RGB triplet on each container at creation
            % time; Theme.COLOR_* is re-evaluated here so the surfaces
            % pick up the new palette.

            navBg    = Theme.NAV_BG;
            navFg    = Theme.NAV_FG;
            navHover = Theme.NAV_HOVER_BG;
            bg       = Theme.COLOR_BG;
            cardBg   = Theme.COLOR_CARD;
            divider  = Theme.COLOR_DIVIDER;

            setBg = @(h, c) LayoutBuilder.trySetProp(h, 'BackgroundColor', c);
            setFg = @(h, c) LayoutBuilder.trySetProp(h, 'FontColor', c);

            % Top header bar — walk every descendant so the inner grids
            % (logoHost, brandWrap, headerRight) get repainted too.
            if ~isempty(app.HeaderGrid) && isvalid(app.HeaderGrid)
                setBg(app.HeaderGrid, navBg);
                kids = findall(app.HeaderGrid);
                for i = 1:numel(kids)
                    k = kids(i);
                    if ~isvalid(k); continue; end
                    switch class(k)
                        case {'matlab.ui.container.GridLayout', 'matlab.ui.container.Panel'}
                            setBg(k, navBg);
                        case 'matlab.ui.control.Label'
                            setFg(k, navFg);
                        case 'matlab.ui.control.Hyperlink'
                            setFg(k, navFg);
                            LayoutBuilder.trySetProp(k, 'VisitedColor', navFg);
                    end
                end
            end

            % Nav rail (uipanel + its inner grids + toggle button).
            if ~isempty(app.NavPanel) && isvalid(app.NavPanel)
                setBg(app.NavPanel, navBg);
                kids = findall(app.NavPanel);
                for i = 1:numel(kids)
                    k = kids(i);
                    if ~isvalid(k); continue; end
                    if isa(k, 'matlab.ui.container.GridLayout')
                        setBg(k, navBg);
                    elseif isa(k, 'matlab.ui.container.Panel') && ~isequal(k, app.NavPanel)
                        % Inner nav separators — let them keep divider color.
                    end
                end
            end
            if ~isempty(app.NavToggleButton) && isvalid(app.NavToggleButton)
                setBg(app.NavToggleButton, navHover);
                setFg(app.NavToggleButton, navFg);
            end

            % Content shell — the light band around the section header card.
            setBg(app.ContentShell,     bg);
            setBg(app.ShellGrid,        bg);
            setBg(app.ContentContainer, bg);

            % Section title card — the biggest offender in dark mode,
            % where it used to stay white with faded text.
            setBg(app.HeaderSectionPanel, cardBg);
            LayoutBuilder.trySetProp(app.HeaderSectionPanel, 'BorderColor', divider);
            setBg(app.HeaderSectionGrid,  cardBg);
            setBg(app.HeaderSectionSep,   divider);
            setFg(app.SectionTitleLabel,    Theme.COLOR_HEADING);
            setFg(app.SectionSubtitleLabel, Theme.COLOR_MUTED);

            % Header popup menu (My Account / Logout).
            if ~isempty(app.HeaderUserMenuPanel) && isvalid(app.HeaderUserMenuPanel)
                setBg(app.HeaderUserMenuPanel, cardBg);
                kids = findall(app.HeaderUserMenuPanel);
                for i = 1:numel(kids)
                    k = kids(i);
                    if ~isvalid(k); continue; end
                    switch class(k)
                        case 'matlab.ui.container.GridLayout'
                            setBg(k, cardBg);
                        case 'matlab.ui.control.Button'
                            setBg(k, cardBg);
                    end
                end
            end

            % Root chrome — also covered in applyTheme but kept here so
            % repaintChrome is self-contained.
            LayoutBuilder.trySetProp(app.UIFigure, 'Color', bg);
            setBg(app.RootGrid, bg);
            setBg(app.BodyGrid, bg);
        end

        function trySetProp(h, prop, val)
            % Best-effort property set that skips invalid handles and
            % swallows errors from missing properties on a given widget
            % type — lets repaintChrome iterate heterogeneous children
            % without per-class guards at every call site.
            if isempty(h); return; end
            try
                if ~isvalid(h); return; end
                h.(prop) = val;
            catch
                % property missing on this widget class; ignore.
            end
        end

        function buildLoadingOverlay(app)
            figW = app.UIFigure.Position(3);
            figH = app.UIFigure.Position(4);
            app.LoadingOverlay = uihtml(app.UIFigure);
            app.LoadingOverlay.Position = [0 0 figW figH];
            app.LoadingOverlay.HTMLSource = LayoutBuilder.loadingOverlayHtml( ...
                Labels.get('loading_workspace', 'Loading workspace...'));
        end

        function html = loadingOverlayHtml(msg)
            % Extracted so re-theming can regenerate the HTML from the live
            % palette without reconstructing the uihtml element.
            overlayBg = Theme.toHex(Theme.OVERLAY_BG);
            spinnerBorder = Theme.toHex(Theme.COLOR_DIVIDER);
            spinnerAccent = Theme.toHex(Theme.OVERLAY_ACCENT);
            msgColor      = Theme.toHex(Theme.OVERLAY_TEXT);
            html = [ ...
                '<html><head><style>' ...
                'body{margin:0;padding:0;height:100%;overflow:hidden;' ...
                'font-family:-apple-system,"Segoe UI",Arial,sans-serif;}' ...
                '.overlay{position:fixed;top:0;left:0;width:100%;height:100%;' ...
                'background:' overlayBg 'b3;display:flex;' ...
                'align-items:center;justify-content:center;' ...
                'backdrop-filter:blur(2px);-webkit-backdrop-filter:blur(2px);}' ...
                '.content{text-align:center;}' ...
                '.spinner{width:46px;height:46px;border:5px solid ' spinnerBorder ';' ...
                'border-top-color:' spinnerAccent ';border-radius:50%;' ...
                'animation:spin 0.85s linear infinite;margin:0 auto;}' ...
                '@keyframes spin{to{transform:rotate(360deg)}}' ...
                '.msg{margin-top:18px;font-size:13px;color:' msgColor ';' ...
                'letter-spacing:0.03em;font-weight:500;}' ...
                '</style></head><body>' ...
                '<div class="overlay"><div class="content">' ...
                '<div class="spinner"></div>' ...
                '<p class="msg">' char(msg) '</p>' ...
                '</div></div></body></html>'];
        end

        function buildAuthOverlay(app)
            pos = app.ContentContainer.Position;
            app.AuthOverlay = uipanel(app.ContentContainer, 'Title', '', ...
                'BorderType', 'none', 'BackgroundColor', Theme.COLOR_BG);
            app.AuthOverlay.AutoResizeChildren = 'on';
            app.AuthOverlay.Position = [0 0 max(1, pos(3)) max(1, pos(4))];

            og = uigridlayout(app.AuthOverlay, [3 3]);
            og.RowHeight   = {'1x', 180, '1x'};
            og.ColumnWidth = {'1x', 320, '1x'};
            og.Padding     = [0 0 0 0];
            og.BackgroundColor = Theme.COLOR_BG;

            card = uipanel(og, 'Title', '');
            card.Layout.Row = 2; card.Layout.Column = 2;
            card.BackgroundColor = Theme.COLOR_CARD;

            cg = uigridlayout(card, [4 1]);
            cg.RowHeight  = {40, 24, 20, 34};
            cg.Padding    = [24 20 24 20];
            cg.RowSpacing = 10;
            cg.BackgroundColor = Theme.COLOR_CARD;

            icon = uilabel(cg, 'Text', char(9888));
            icon.FontSize = 28; icon.HorizontalAlignment = 'center';
            icon.FontColor = Theme.COLOR_HEADING;
            icon.Layout.Row = 1; icon.Layout.Column = 1;

            ttl = uilabel(cg, 'Text', Labels.get('auth_overlay_title', 'Authentication Required'));
            ttl.FontSize = 16; ttl.FontWeight = 'bold';
            ttl.FontColor = Theme.COLOR_HEADING;
            ttl.HorizontalAlignment = 'center';
            ttl.Layout.Row = 2; ttl.Layout.Column = 1;

            sub = uilabel(cg, 'Text', Labels.get('auth_overlay_subtitle', 'Please sign in to access the workspace'));
            sub.FontSize = 12; sub.FontColor = Theme.COLOR_LABEL;
            sub.HorizontalAlignment = 'center';
            sub.Layout.Row = 3; sub.Layout.Column = 1;

            btn = uibutton(cg, 'Text', Labels.get('auth_overlay_btn', 'Sign In'));
            btn.Layout.Row = 4; btn.Layout.Column = 1;
            app.styleBtn(btn, 'primary');
            btn.ButtonPushedFcn = @(~,~)app.showLoginDialog();
        end

    end
end
