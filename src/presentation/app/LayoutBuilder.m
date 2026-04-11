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
            app.HeaderGrid.BackgroundColor = [0.10 0.17 0.30];

            logoHost = uigridlayout(app.HeaderGrid, [1 1]);
            logoHost.Layout.Row = 1; logoHost.Layout.Column = 1;
            logoHost.RowHeight = {'1x'}; logoHost.ColumnWidth = {'1x'};
            logoHost.Padding = [0 0 10 0];
            logoHost.RowSpacing = 0; logoHost.ColumnSpacing = 0;
            logoHost.BackgroundColor = [0.10 0.17 0.30];

            logoPath = fullfile(fileparts(mfilename('fullpath')), '..', '..', '..', ...
                'resources', 'sqk-logo-kokkos-white1-reordered.svg');
            brandWrap = uigridlayout(logoHost, [1 2]);
            brandWrap.Layout.Row = 1; brandWrap.Layout.Column = 1;
            brandWrap.RowHeight = {'1x'}; brandWrap.ColumnWidth = {108, '1x'};
            brandWrap.Padding = [0 0 10 0];
            brandWrap.RowSpacing = 0; brandWrap.ColumnSpacing = 0;
            brandWrap.BackgroundColor = [0.10 0.17 0.30];
            try
                brand = uiimage(brandWrap);
                brand.ImageSource = logoPath;
                brand.ScaleMethod = 'fit';
                brand.Tooltip = 'SQK';
                brand.Layout.Row = 1; brand.Layout.Column = 1;
            catch
                brand = uilabel(brandWrap, 'Text', 'SQK');
                brand.FontSize = 14; brand.FontWeight = 'bold';
                brand.FontColor = [1 1 1];
                brand.HorizontalAlignment = 'left';
                brand.VerticalAlignment   = 'bottom';
                brand.Layout.Row = 1; brand.Layout.Column = 1;
            end

            subtitle = uilabel(app.HeaderGrid, 'Text', 'Connector Workspace');
            subtitle.FontSize = 14; subtitle.FontWeight = 'bold';
            subtitle.HorizontalAlignment = 'center';
            subtitle.FontColor = [0.80 0.87 0.97];
            subtitle.Layout.Row = 1; subtitle.Layout.Column = 2;

            headerRight = uigridlayout(app.HeaderGrid, [1 3]);
            headerRight.Layout.Row = 1; headerRight.Layout.Column = 3;
            headerRight.ColumnWidth = {'fit', 'fit', 'fit'};
            headerRight.Padding = [0 0 4 0]; headerRight.ColumnSpacing = 10;
            headerRight.BackgroundColor = [0.10 0.17 0.30];

            userBadge = uilabel(headerRight, 'Text', 'SQK Admin Workspace');
            userBadge.FontSize = 13; userBadge.FontWeight = 'bold';
            userBadge.HorizontalAlignment = 'right';
            userBadge.FontColor = [1 1 1];
            userBadge.Layout.Row = 1; userBadge.Layout.Column = 1;
            userBadge.Tooltip = 'QTAU Connector v2026';

            app.HeaderLoginButton = uihyperlink(headerRight, ...
                'Text', Labels.get('header_btn_login', 'Login'), ...
                'URL', '', ...
                'HyperlinkClickedFcn', @(~,~)app.showLoginDialog(), ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0.85 0.92 1.00], ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
            app.HeaderLoginButton.Layout.Row = 1; app.HeaderLoginButton.Layout.Column = 2;
            app.HeaderLoginButton.VisitedColor = [0.85 0.92 1.00];

            app.HeaderUserLabel = uihyperlink(headerRight, ...
                'Text', '', ...
                'URL', '', ...
                'HyperlinkClickedFcn', @(~,~)app.toggleHeaderUserMenu(), ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', [0.85 0.92 1.00], ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');
            app.HeaderUserLabel.Layout.Row = 1; app.HeaderUserLabel.Layout.Column = 3;
            app.HeaderUserLabel.Visible = 'off';
            app.HeaderUserLabel.VisitedColor = [0.85 0.92 1.00];

            app.HeaderUserMenuPanel = uipanel(app.UIFigure, 'Title', '', ...
                'Position', [0 0 180 76], 'Visible', 'off', ...
                'BackgroundColor', [1 1 1], 'BorderType', 'line');
            mg = uigridlayout(app.HeaderUserMenuPanel, [2 1]);
            mg.RowHeight = {32, 32}; mg.ColumnWidth = {'1x'};
            mg.Padding = [4 4 4 4]; mg.RowSpacing = 2;
            mg.BackgroundColor = [1 1 1];

            accountBtn = uibutton(mg, 'Text', [char(9881) '  ' Labels.get('header_menu_my_account', 'My Account')], ...
                'HorizontalAlignment', 'left', 'FontSize', 15, ...
                'FontColor', [0.20 0.20 0.25], 'BackgroundColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~)app.onHeaderMenuAction('account'));
            accountBtn.Layout.Row = 1; accountBtn.Layout.Column = 1;

            logoutBtn = uibutton(mg, 'Text', [char(9211) '  ' Labels.get('header_menu_logout', 'Logout')], ...
                'HorizontalAlignment', 'left', 'FontSize', 15, ...
                'FontColor', [0.70 0.15 0.15], 'BackgroundColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~)app.onHeaderMenuAction('logout'));
            logoutBtn.Layout.Row = 2; logoutBtn.Layout.Column = 1;
        end

        function buildBody(app)
            app.BodyGrid = uigridlayout(app.RootGrid, [1 2]);
            app.BodyGrid.Layout.Row    = 2;
            app.BodyGrid.Layout.Column = 1;
            app.BodyGrid.ColumnWidth   = {230, '1x'};
            app.BodyGrid.RowHeight     = {'1x'};
            app.BodyGrid.Padding       = [0 0 0 0];
            app.BodyGrid.ColumnSpacing = 0;
            app.BodyGrid.BackgroundColor = [0.93 0.95 0.98];

            % Sidebar
            app.NavPanel = uipanel(app.BodyGrid, 'Title', '');
            app.NavPanel.Layout.Row = 1; app.NavPanel.Layout.Column = 1;
            app.NavPanel.BackgroundColor = [0.12 0.19 0.31];

            navGrid = uigridlayout(app.NavPanel, [4 1]);
            navGrid.RowHeight = {44, 1, '1x', 28};
            navGrid.Padding = [10 10 10 10];
            navGrid.BackgroundColor = [0.12 0.19 0.31];

            topRow = uigridlayout(navGrid, [1 2]);
            topRow.Layout.Row = 1; topRow.Layout.Column = 1;
            topRow.ColumnWidth = {0, '1x'};
            topRow.Padding = [0 0 0 0];
            topRow.BackgroundColor = [0.12 0.19 0.31];

            navBrand = uilabel(topRow, 'Text', '');
            navBrand.Visible = 'off';
            navBrand.Layout.Row = 1; navBrand.Layout.Column = 1;

            app.NavToggleButton = uibutton(topRow, 'push', 'Text', char(8801), ...
                'ButtonPushedFcn', @(~,~)app.onToggleNav());
            app.NavToggleButton.Layout.Row = 1; app.NavToggleButton.Layout.Column = 2;
            app.NavToggleButton.FontSize = 18; app.NavToggleButton.FontWeight = 'bold';
            app.NavToggleButton.BackgroundColor = [0.20 0.31 0.49];
            app.NavToggleButton.FontColor = [1 1 1];

            navSep = uipanel(navGrid, 'Title', '');
            navSep.Layout.Row = 2; navSep.Layout.Column = 1;
            navSep.BackgroundColor = [0.30 0.40 0.55];
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

            hint = uilabel(navGrid, 'Text', Labels.get('nav_hint_collapse', char(47803)));
            hint.FontSize = 10; hint.FontColor = [0.72 0.80 0.92];
            hint.VerticalAlignment = 'top';
            hint.Layout.Row = 4; hint.Layout.Column = 1;

            % Content shell
            app.ContentShell = uipanel(app.BodyGrid, 'Title', '');
            app.ContentShell.Layout.Row = 1; app.ContentShell.Layout.Column = 2;
            app.ContentShell.BackgroundColor = [0.96 0.97 0.99];

            shellGrid = uigridlayout(app.ContentShell, [3 1]);
            shellGrid.RowHeight  = {82, 1, '1x'};
            shellGrid.Padding    = [20 16 20 16];
            shellGrid.RowSpacing = 12;
            shellGrid.BackgroundColor = [0.96 0.97 0.99];

            headerPanel = uipanel(shellGrid, 'Title', '');
            headerPanel.Layout.Row = 1; headerPanel.Layout.Column = 1;
            headerPanel.BackgroundColor = [1 1 1];
            hg = uigridlayout(headerPanel, [2 1]);
            hg.RowHeight = {28, 20}; hg.Padding = [16 10 16 10];
            hg.BackgroundColor = [1 1 1];
            app.SectionTitleLabel = uilabel(hg, 'Text', 'Welcome');
            app.SectionTitleLabel.FontSize = 18; app.SectionTitleLabel.FontWeight = 'bold';
            app.SectionTitleLabel.Layout.Row = 1; app.SectionTitleLabel.Layout.Column = 1;
            app.SectionSubtitleLabel = uilabel(hg, 'Text', 'Server authentication and project access');
            app.SectionSubtitleLabel.FontSize = 12;
            app.SectionSubtitleLabel.FontColor = [0.35 0.40 0.48];
            app.SectionSubtitleLabel.Layout.Row = 2; app.SectionSubtitleLabel.Layout.Column = 1;

            sep = uipanel(shellGrid, 'Title', '');
            sep.Layout.Row = 2; sep.Layout.Column = 1;
            sep.BackgroundColor = [0.87 0.90 0.95];

            app.ContentContainer = uipanel(shellGrid, 'Title', '');
            app.ContentContainer.Layout.Row = 3; app.ContentContainer.Layout.Column = 1;
            app.ContentContainer.BackgroundColor = [0.96 0.97 0.99];
            app.ContentContainer.AutoResizeChildren = 'off';
            app.ContentContainer.SizeChangedFcn = @(~,~)app.onResizeUI();

            app.SectionPanels = struct();
        end

        function buildLoadingOverlay(app)
            figW = app.UIFigure.Position(3);
            figH = app.UIFigure.Position(4);
            app.LoadingOverlay = uihtml(app.UIFigure);
            app.LoadingOverlay.Position = [0 0 figW figH];
            app.LoadingOverlay.HTMLSource = [ ...
                '<html><head><style>' ...
                'body{margin:0;padding:0;height:100%;overflow:hidden;' ...
                'font-family:-apple-system,"Segoe UI",Arial,sans-serif;}' ...
                '.overlay{position:fixed;top:0;left:0;width:100%;height:100%;' ...
                'background:rgba(0,0,0,0.70);display:flex;' ...
                'align-items:center;justify-content:center;' ...
                'backdrop-filter:blur(2px);-webkit-backdrop-filter:blur(2px);}' ...
                '.content{text-align:center;}' ...
                '.spinner{width:46px;height:46px;border:5px solid #333;' ...
                'border-top-color:#60a5fa;border-radius:50%;' ...
                'animation:spin 0.85s linear infinite;margin:0 auto;}' ...
                '@keyframes spin{to{transform:rotate(360deg)}}' ...
                '.msg{margin-top:18px;font-size:13px;color:#e5e7eb;' ...
                'letter-spacing:0.03em;font-weight:500;}' ...
                '</style></head><body>' ...
                '<div class="overlay"><div class="content">' ...
                '<div class="spinner"></div>' ...
                '<p class="msg">Loading workspace...</p>' ...
                '</div></div></body></html>'];
        end

        function buildAuthOverlay(app)
            pos = app.ContentContainer.Position;
            app.AuthOverlay = uipanel(app.ContentContainer, 'Title', '', ...
                'BorderType', 'none', 'BackgroundColor', [0.96 0.97 0.99]);
            app.AuthOverlay.AutoResizeChildren = 'on';
            app.AuthOverlay.Position = [0 0 max(1, pos(3)) max(1, pos(4))];

            og = uigridlayout(app.AuthOverlay, [3 3]);
            og.RowHeight   = {'1x', 180, '1x'};
            og.ColumnWidth = {'1x', 320, '1x'};
            og.Padding     = [0 0 0 0];
            og.BackgroundColor = [0.96 0.97 0.99];

            card = uipanel(og, 'Title', '');
            card.Layout.Row = 2; card.Layout.Column = 2;
            card.BackgroundColor = [1 1 1];

            cg = uigridlayout(card, [4 1]);
            cg.RowHeight  = {40, 24, 20, 34};
            cg.Padding    = [24 20 24 20];
            cg.RowSpacing = 10;
            cg.BackgroundColor = [1 1 1];

            icon = uilabel(cg, 'Text', char(9888));
            icon.FontSize = 28; icon.HorizontalAlignment = 'center';
            icon.Layout.Row = 1; icon.Layout.Column = 1;

            ttl = uilabel(cg, 'Text', Labels.get('auth_overlay_title', 'Authentication Required'));
            ttl.FontSize = 16; ttl.FontWeight = 'bold';
            ttl.HorizontalAlignment = 'center';
            ttl.Layout.Row = 2; ttl.Layout.Column = 1;

            sub = uilabel(cg, 'Text', Labels.get('auth_overlay_subtitle', 'Please sign in to access the workspace'));
            sub.FontSize = 12; sub.FontColor = [0.35 0.40 0.48];
            sub.HorizontalAlignment = 'center';
            sub.Layout.Row = 3; sub.Layout.Column = 1;

            btn = uibutton(cg, 'Text', Labels.get('auth_overlay_btn', 'Sign In'));
            btn.Layout.Row = 4; btn.Layout.Column = 1;
            app.styleBtn(btn, 'primary');
            btn.ButtonPushedFcn = @(~,~)app.showLoginDialog();
        end

    end
end
