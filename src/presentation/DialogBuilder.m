classdef DialogBuilder
    % DialogBuilder  Factory for modal dialogs (Login, NewProject, EditProject).
    %
    %   Extracted from QTAUWorkbenchApp to reduce God-class complexity.
    %   Each static method builds UI into the app's dialog properties so
    %   that ViewModels can read them unchanged.
    %
    %   Usage:
    %       DialogBuilder.buildLoginDialog(app);
    %       DialogBuilder.buildNewProjectDialog(app);
    %       DialogBuilder.buildEditProjectDialog(app, id, name, desc, tags);

    methods (Static)

        function buildLoginDialog(app)
            % Create modal login dialog — Google-inspired professional layout.
            % Colors come from the active Theme so the dialog matches dark /
            % solarized / nord / dracula / high-contrast palettes.
            figPos = app.UIFigure.Position;
            dlgW = 480; dlgH = 520;
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor     = Theme.COLOR_BG;
            cardBg      = Theme.COLOR_CARD;
            cardBorder  = Theme.COLOR_DIVIDER;
            titleColor  = Theme.COLOR_HEADING;
            subtColor   = Theme.COLOR_MUTED;
            labelColor  = Theme.COLOR_LABEL;
            accentBlue  = Theme.COLOR_PRIMARY;
            errorRed    = Theme.COLOR_DANGER;
            footerColor = Theme.COLOR_MUTED;

            app.LoginDialog = uifigure( ...
                'Name', Labels.get('login_dlg_title', 'Sign In'), ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'off', ...
                'Color', bgColor);
            Theme.applyFigureMode(app.LoginDialog, Theme.activeName());

            outerGrid = uigridlayout(app.LoginDialog, [3 3]);
            outerGrid.RowHeight   = {16, '1x', 28};
            outerGrid.ColumnWidth = {36, '1x', 36};
            outerGrid.Padding     = [0 0 0 0];
            outerGrid.RowSpacing  = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = bgColor;

            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, ...
                'HighlightColor', cardBorder, ...
                'BorderColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            cg = uigridlayout(card, [15 1]);
            cg.RowHeight = {32, 20, 12, 16, 36, 8, 16, 36, 8, 16, 36, 20, 12, 40, 'fit'};
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [32 24 32 18];
            cg.RowSpacing  = 2;
            cg.BackgroundColor = cardBg;

            titleLbl = uilabel(cg, 'Text', Labels.get('login_dlg_sign_in', 'Sign in'), ...
                'FontSize', 24, 'FontWeight', 'bold', ...
                'FontColor', titleColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            subLbl = uilabel(cg, ...
                'Text', Labels.get('login_dlg_subtitle', 'to continue to QTAU Connector'), ...
                'FontSize', 13, 'FontColor', subtColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            urlLbl = uilabel(cg, ...
                'Text', Labels.get('welcome_label_base_url', 'Server URL'), ...
                'FontSize', 12, 'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            urlLbl.Layout.Row = 4; urlLbl.Layout.Column = 1;

            initUrl = char(app.State.baseUrl);
            app.LoginDlgBaseUrlValue = initUrl;
            app.LoginDlgBaseUrlField = uihtml(cg);
            app.LoginDlgBaseUrlField.Layout.Row = 5;
            app.LoginDlgBaseUrlField.Layout.Column = 1;
            app.LoginDlgBaseUrlField.HTMLSource = DialogBuilder.textInputHtml( ...
                Labels.get('login_dlg_placeholder_url', 'https://your-server:port'), initUrl);
            app.LoginDlgBaseUrlField.DataChangedFcn = @(~,~) app.onTextFieldHtmlData('baseUrl');

            userLbl = uilabel(cg, ...
                'Text', Labels.get('welcome_label_username', 'Username'), ...
                'FontSize', 12, 'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            userLbl.Layout.Row = 7; userLbl.Layout.Column = 1;

            app.LoginDlgUsernameValue = '';
            app.LoginDlgUsernameField = uihtml(cg);
            app.LoginDlgUsernameField.Layout.Row = 8;
            app.LoginDlgUsernameField.Layout.Column = 1;
            app.LoginDlgUsernameField.HTMLSource = DialogBuilder.textInputHtml( ...
                Labels.get('login_dlg_placeholder_user', 'Enter your username'), '');
            app.LoginDlgUsernameField.DataChangedFcn = @(~,~) app.onTextFieldHtmlData('username');

            passLbl = uilabel(cg, ...
                'Text', Labels.get('welcome_label_password', 'Password'), ...
                'FontSize', 12, 'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            passLbl.Layout.Row = 10; passLbl.Layout.Column = 1;

            app.LoginDlgPasswordReal    = '';

            placeholder = Labels.get('login_dlg_placeholder_pass', 'Enter your password');
            inputBg      = Theme.toHex(Theme.COLOR_BG);
            inputFg      = Theme.toHex(Theme.COLOR_HEADING);
            % Rest-state border matches the field bg so the box disappears
            % into the card; on focus it swaps to the primary accent.
            inputBorder  = inputBg;
            inputFocus   = Theme.toHex(Theme.COLOR_PRIMARY);
            placeholderC = Theme.toHex(Theme.COLOR_MUTED);
            eyeColor     = Theme.toHex(Theme.COLOR_MUTED);
            eyeSvgOpen  = ['<svg viewBox="0 0 24 24" width="20" height="20"><path fill="' eyeColor '" d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zm0 12.5c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z"/></svg>'];
            eyeSvgSlash = ['<svg viewBox="0 0 24 24" width="20" height="20"><path fill="' eyeColor '" d="M12 7c2.76 0 5 2.24 5 5 0 .65-.13 1.26-.36 1.83l2.92 2.92c1.51-1.26 2.7-2.89 3.43-4.75-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16C11.74 7.13 12.35 7 12 7zM2 4.27l2.28 2.28.46.46C3.08 8.3 1.78 10.02 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84l.42.42L19.73 22 21 20.73 3.27 3 2 4.27zM7.53 9.8l1.55 1.55c-.05.21-.08.43-.08.65 0 1.66 1.34 3 3 3 .22 0 .44-.03.65-.08l1.55 1.55c-.67.33-1.41.53-2.2.53-2.76 0-5-2.24-5-5 0-.79.2-1.53.53-2.2zm4.31-.78l3.15 3.15.02-.16c0-1.66-1.34-3-3-3l-.17.01z"/></svg>'];

            pwHtml = [ ...
                '<html><head><style>' ...
                '*{box-sizing:border-box;margin:0;padding:0;}' ...
                'html,body{height:100%;background:transparent;color-scheme:dark;}' ...
                'body{display:flex;align-items:center;' ...
                'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;}' ...
                '.pw-wrap{position:relative;width:100%;display:flex;align-items:center;}' ...
                'input{width:100%;height:34px;padding:6px 38px 6px 10px;font-size:14px;' ...
                '-webkit-appearance:none;appearance:none;' ...
                'color:' inputFg ';border:1px solid ' inputBorder ';border-radius:6px;outline:none;background:' inputBg ';}' ...
                'input:focus{border-color:' inputFocus ';box-shadow:0 0 0 2px rgba(67,97,238,0.18);}' ...
                'input::placeholder{color:' placeholderC ';}' ...
                '.eye-btn{position:absolute;right:4px;top:50%;transform:translateY(-50%);' ...
                'cursor:pointer;background:none;border:none;padding:4px;display:flex;' ...
                'align-items:center;justify-content:center;opacity:0.5;border-radius:4px;}' ...
                '.eye-btn:hover{opacity:0.85;background:rgba(127,127,127,0.12);}' ...
                '</style></head><body>' ...
                '<div class="pw-wrap">' ...
                '<input type="password" id="pw" placeholder="' placeholder '" autocomplete="off" spellcheck="false">' ...
                '<button class="eye-btn" id="eye" type="button" tabindex="-1"></button>' ...
                '</div>' ...
                '<script>' ...
                'function setup(comp){' ...
                'var pw=document.getElementById("pw");' ...
                'var eye=document.getElementById("eye");' ...
                'var vis=false;' ...
                'var svgOpen=''' strrep(eyeSvgOpen, '''', '\''') ''';' ...
                'var svgSlash=''' strrep(eyeSvgSlash, '''', '\''') ''';' ...
                'eye.innerHTML=svgSlash;' ...
                'pw.addEventListener("input",function(){' ...
                'comp.Data={a:"i",v:pw.value};});' ...
                'pw.addEventListener("keydown",function(e){' ...
                'if(e.key==="Enter"){comp.Data={a:"enter",v:pw.value};}});' ...
                'eye.addEventListener("click",function(){' ...
                'vis=!vis;pw.type=vis?"text":"password";' ...
                'eye.innerHTML=vis?svgOpen:svgSlash;pw.focus();});' ...
                'comp.addEventListener("DataChanged",function(){' ...
                'var d=comp.Data;if(!d)return;' ...
                'if(d.a==="clear"){pw.value="";vis=false;pw.type="password";eye.innerHTML=svgSlash;}' ...
                'if(d.a==="focus"){pw.focus();}});' ...
                '}' ...
                '</script></body></html>'];

            app.LoginDlgPasswordField = uihtml(cg);
            app.LoginDlgPasswordField.Layout.Row = 11;
            app.LoginDlgPasswordField.Layout.Column = 1;
            app.LoginDlgPasswordField.HTMLSource = pwHtml;
            app.LoginDlgPasswordField.DataChangedFcn = @(~,evt) app.onPasswordHtmlData(evt);

            helpLbl = uilabel(cg, ...
                'Text', Labels.get('login_dlg_forgot', 'Forgot credentials? Contact your admin.'), ...
                'FontSize', 11, 'FontColor', accentBlue, ...
                'HorizontalAlignment', 'left', 'VerticalAlignment', 'center');
            helpLbl.Layout.Row = 12; helpLbl.Layout.Column = 1;

            loginBtn = uibutton(cg, ...
                'Text', Labels.get('welcome_btn_login', 'Sign In'), ...
                'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', [1 1 1], ...
                'BackgroundColor', accentBlue, ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onLogin());
            loginBtn.Layout.Row = 14; loginBtn.Layout.Column = 1;

            app.LoginDlgStatusLabel = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', errorRed, ...
                'WordWrap', 'on', 'HorizontalAlignment', 'center');
            app.LoginDlgStatusLabel.Layout.Row = 15;
            app.LoginDlgStatusLabel.Layout.Column = 1;

            verLbl = uilabel(outerGrid, ...
                'Text', Labels.get('login_dlg_version', 'QTAU Connector Workspace v2026'), ...
                'FontSize', 9, 'FontColor', footerColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
            verLbl.Layout.Row = 3; verLbl.Layout.Column = 2;

            app.LoginDialog.KeyPressFcn = @(~, evt) app.onLoginKeyPress(evt);
            % User-initiated close (X button): detach uihtml callbacks and
            % drain the event queue before deleting so trailing browser
            % events don't fire against deleted handles (same race class
            % as the login-success path in WelcomeViewModel.onLogin).
            app.LoginDialog.CloseRequestFcn = @(src,~) DialogBuilder.closeLoginDialog(app, src);
            Logger.info('DialogBuilder', 'Login dialog shown');
        end

        function resetLoginDialog(app)
            % Clear sensitive state on a re-shown LoginDialog.
            %   - Password field (security): always cleared.
            %   - Status label: cleared so a prior error doesn't haunt
            %     the next attempt.
            %   - Username & baseUrl: intentionally NOT cleared — users
            %     typically retry the same account, and baseUrl rarely
            %     changes between attempts (Settings has its own editor).
            if isprop(app, 'LoginDlgPasswordReal')
                app.LoginDlgPasswordReal = '';
            end
            if isprop(app, 'LoginDlgPasswordField') ...
                    && ~isempty(app.LoginDlgPasswordField) ...
                    && isvalid(app.LoginDlgPasswordField)
                try app.LoginDlgPasswordField.Data = struct('a', 'clear'); catch; end
            end
            if isprop(app, 'LoginDlgStatusLabel') ...
                    && ~isempty(app.LoginDlgStatusLabel) ...
                    && isvalid(app.LoginDlgStatusLabel)
                try app.LoginDlgStatusLabel.Text = ''; catch; end
            end
        end

        function closeLoginDialog(app, src)
            % Reuse-not-delete: hide the dialog and reset sensitive
            % state. The previous teardown ceremony existed to drain
            % uihtml peerEvents before a delete() that no longer
            % happens. With no delete there is no LabelController /
            % PushButtonController lifecycle race to drain against, so
            % the dialog can re-show in well under a second on the
            % next click instead of paying the 4–18 s cold rebuild.
            DialogBuilder.resetLoginDialog(app);
            if ~isempty(src) && isvalid(src)
                try src.Visible = 'off'; catch; end
            end
        end

        function buildNewProjectDialog(app)
            % Create modal New Project dialog — modern card layout
            figPos = app.UIFigure.Position;
            dlgW = 480; dlgH = 520;
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor    = Theme.COLOR_BG;
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;
            titleColor = Theme.COLOR_HEADING;
            subtColor  = Theme.COLOR_MUTED;
            labelColor = Theme.COLOR_LABEL;
            errorRed   = Theme.COLOR_DANGER;

            app.NewProjectDialog = uifigure( ...
                'Name', Labels.get('new_proj_dlg_title', 'New Project'), ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'off', ...
                'Color', bgColor);
            Theme.applyFigureMode(app.NewProjectDialog, Theme.activeName());

            outerGrid = uigridlayout(app.NewProjectDialog, [3 3]);
            outerGrid.RowHeight     = {16, '1x', 16};
            outerGrid.ColumnWidth   = {24, '1x', 24};
            outerGrid.Padding       = [0 0 0 0];
            outerGrid.RowSpacing    = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = bgColor;

            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, ...
                'HighlightColor', cardBorder, ...
                'BorderColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            cg = uigridlayout(card, [12 1]);
            cg.RowHeight = {28, 18, 10, 16, 34, 16, 90, 16, 34, 14, 42, 20};
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [36 24 36 20];
            cg.RowSpacing  = 2;
            cg.BackgroundColor = cardBg;

            titleLbl = uilabel(cg, 'Text', Labels.get('new_proj_dlg_heading', 'Create New Project'), ...
                'FontSize', 19, 'FontWeight', 'bold', ...
                'FontColor', titleColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            subLbl = uilabel(cg, 'Text', Labels.get('new_proj_dlg_subtitle', 'Set up a new quantum experiment workspace'), ...
                'FontSize', 11, 'FontColor', subtColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            nameLbl = uilabel(cg, 'Text', Labels.get('new_proj_label_name', 'Project Name'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            nameLbl.Layout.Row = 4; nameLbl.Layout.Column = 1;

            app.NewProjNameField = uieditfield(cg, 'text', 'Value', '', ...
                'Placeholder', Labels.get('new_proj_placeholder_name', 'e.g. BV-27 Fidelity Study'), ...
                'FontSize', 13);
            app.NewProjNameField.Layout.Row = 5; app.NewProjNameField.Layout.Column = 1;

            descLbl = uilabel(cg, 'Text', Labels.get('new_proj_label_desc', 'Description'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            descLbl.Layout.Row = 6; descLbl.Layout.Column = 1;

            app.NewProjDescField = uitextarea(cg, 'Value', '', ...
                'Placeholder', Labels.get('new_proj_placeholder_desc', 'Describe the purpose and scope of this project...'), ...
                'FontSize', 13);
            app.NewProjDescField.Layout.Row = 7; app.NewProjDescField.Layout.Column = 1;

            tagsLbl = uilabel(cg, 'Text', Labels.get('new_proj_label_tags', 'Tags (comma-separated)'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            tagsLbl.Layout.Row = 8; tagsLbl.Layout.Column = 1;

            app.NewProjTagsField = uieditfield(cg, 'text', 'Value', '', ...
                'Placeholder', Labels.get('new_proj_placeholder_tags', 'e.g. calibration, 27-qubit, fidelity'), ...
                'FontSize', 13);
            app.NewProjTagsField.Layout.Row = 9; app.NewProjTagsField.Layout.Column = 1;

            btnBar = uigridlayout(cg, [1 2]);
            btnBar.Layout.Row = 11; btnBar.Layout.Column = 1;
            btnBar.ColumnWidth = {'1x', '1x'};
            btnBar.Padding = [0 0 0 0]; btnBar.ColumnSpacing = 12;
            btnBar.BackgroundColor = cardBg;

            cancelBtn = uibutton(btnBar, 'Text', Labels.get('new_proj_btn_cancel', 'Cancel'), ...
                'ButtonPushedFcn', @(~,~)delete(app.NewProjectDialog));
            cancelBtn.Layout.Row = 1; cancelBtn.Layout.Column = 1;
            app.styleBtn(cancelBtn, 'ghost');

            createBtn = uibutton(btnBar, 'Text', Labels.get('new_proj_btn_create', 'Create'), ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onCreateProject());
            createBtn.Layout.Row = 1; createBtn.Layout.Column = 2;
            app.styleBtn(createBtn, 'primary');

            app.NewProjStatusLabel = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', errorRed, ...
                'WordWrap', 'on', 'HorizontalAlignment', 'center');
            app.NewProjStatusLabel.Layout.Row = 12; app.NewProjStatusLabel.Layout.Column = 1;

            Logger.info('DialogBuilder', 'New Project dialog shown');
        end

        function buildEditProjectDialog(app, projectId, projName, projDesc, projTags)
            % Create modal Edit Project dialog pre-filled with existing data
            app.EditProjId = projectId;
            figPos = app.UIFigure.Position;
            dlgW = 480; dlgH = 520;
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor    = Theme.COLOR_BG;
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;
            titleColor = Theme.COLOR_HEADING;
            subtColor  = Theme.COLOR_MUTED;
            labelColor = Theme.COLOR_LABEL;
            errorRed   = Theme.COLOR_DANGER;

            app.EditProjectDialog = uifigure( ...
                'Name', Labels.get('edit_proj_dlg_title', 'Edit Project'), ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'off', ...
                'Color', bgColor);
            Theme.applyFigureMode(app.EditProjectDialog, Theme.activeName());

            outerGrid = uigridlayout(app.EditProjectDialog, [3 3]);
            outerGrid.RowHeight     = {16, '1x', 16};
            outerGrid.ColumnWidth   = {24, '1x', 24};
            outerGrid.Padding       = [0 0 0 0];
            outerGrid.RowSpacing    = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = bgColor;

            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, ...
                'HighlightColor', cardBorder, ...
                'BorderColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            cg = uigridlayout(card, [12 1]);
            cg.RowHeight = {28, 18, 10, 16, 34, 16, 90, 16, 34, 14, 42, 20};
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [36 24 36 20];
            cg.RowSpacing  = 2;
            cg.BackgroundColor = cardBg;

            titleLbl = uilabel(cg, 'Text', Labels.get('edit_proj_dlg_heading', 'Edit Project'), ...
                'FontSize', 19, 'FontWeight', 'bold', ...
                'FontColor', titleColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            subLbl = uilabel(cg, 'Text', Labels.get('edit_proj_dlg_subtitle', 'Update project information'), ...
                'FontSize', 11, 'FontColor', subtColor, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            nameLbl = uilabel(cg, 'Text', Labels.get('edit_proj_label_name', 'Project Name'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            nameLbl.Layout.Row = 4; nameLbl.Layout.Column = 1;

            app.EditProjNameField = uieditfield(cg, 'text', 'Value', char(projName), ...
                'FontSize', 13);
            app.EditProjNameField.Layout.Row = 5; app.EditProjNameField.Layout.Column = 1;

            descLbl = uilabel(cg, 'Text', Labels.get('edit_proj_label_desc', 'Description'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            descLbl.Layout.Row = 6; descLbl.Layout.Column = 1;

            app.EditProjDescField = uitextarea(cg, 'Value', char(projDesc), ...
                'FontSize', 13);
            app.EditProjDescField.Layout.Row = 7; app.EditProjDescField.Layout.Column = 1;

            tagsLbl = uilabel(cg, 'Text', Labels.get('edit_proj_label_tags', 'Tags (comma-separated)'), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', labelColor, ...
                'VerticalAlignment', 'bottom');
            tagsLbl.Layout.Row = 8; tagsLbl.Layout.Column = 1;

            app.EditProjTagsField = uieditfield(cg, 'text', 'Value', char(projTags), ...
                'FontSize', 13);
            app.EditProjTagsField.Layout.Row = 9; app.EditProjTagsField.Layout.Column = 1;

            btnBar = uigridlayout(cg, [1 2]);
            btnBar.Layout.Row = 11; btnBar.Layout.Column = 1;
            btnBar.ColumnWidth = {'1x', '1x'};
            btnBar.Padding = [0 0 0 0]; btnBar.ColumnSpacing = 12;
            btnBar.BackgroundColor = cardBg;

            cancelBtn = uibutton(btnBar, 'Text', [char(10006) ' ' Labels.get('edit_proj_btn_cancel', 'Cancel')], ...
                'ButtonPushedFcn', @(~,~)delete(app.EditProjectDialog));
            cancelBtn.Layout.Row = 1; cancelBtn.Layout.Column = 1;
            app.styleBtn(cancelBtn, 'ghost');

            saveBtn = uibutton(btnBar, 'Text', [char(10004) ' ' Labels.get('edit_proj_btn_save', 'Save')], ...
                'ButtonPushedFcn', @(~,~)app.WelcomeVm.onSaveProject());
            saveBtn.Layout.Row = 1; saveBtn.Layout.Column = 2;
            app.styleBtn(saveBtn, 'primary');

            app.EditProjStatusLabel = uilabel(cg, 'Text', '', ...
                'FontSize', 11, 'FontColor', errorRed, ...
                'WordWrap', 'on', 'HorizontalAlignment', 'center');
            app.EditProjStatusLabel.Layout.Row = 12; app.EditProjStatusLabel.Layout.Column = 1;

            Logger.info('DialogBuilder', 'Edit Project dialog shown for: %s', char(projectId));
        end

        function buildQmcDialog(app)
            % Modal popup hosting the Quantum Monte Carlo Simulation
            %   (Quantum Amplitude Estimation) UI. Called from the Analysis
            %   screen's launcher button. The controls + plots that live
            %   inside (app.QmcModeDropdown, QmcRunButton, QmcPathAxes,
            %   QmcConvergenceAxes, QmcKpiLabels, ...) are populated here
            %   so AnalysisViewModel.renderQmcResult can continue to update
            %   them via the cached app handles.
            figPos = app.UIFigure.Position;
            dlgW = min(1500, max(1200, round(figPos(3) * 0.92)));
            dlgH = min(1080, max(880,  round(figPos(4) * 0.95)));
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor    = Theme.COLOR_BG;
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;
            titleColor = Theme.COLOR_HEADING;
            labelColor = Theme.COLOR_LABEL;

            app.QmcDialog = uifigure( ...
                'Name', 'Quantum Monte Carlo Simulation', ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'on', ...
                'Color', bgColor, ...
                'CloseRequestFcn', @(src,~) delete(src));
            Theme.applyFigureMode(app.QmcDialog, Theme.activeName());

            outerGrid = uigridlayout(app.QmcDialog, [3 3]);
            outerGrid.RowHeight     = {16, '1x', 16};
            outerGrid.ColumnWidth   = {24, '1x', 24};
            outerGrid.Padding       = [0 0 0 0];
            outerGrid.RowSpacing    = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = bgColor;

            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, ...
                'HighlightColor', cardBorder, ...
                'BorderColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            % Inside the card: header / banner / body / divider / footer.
            % The banner row is hidden by default and toggled visible by
            % AnalysisViewModel.applyQmcViability when the active circuit
            % can't run in either Statevector (≤30q) or any available
            % IBM Runtime backend. Footer row stays tuned so the Run /
            % Generate Report / Close buttons render at the same ~44 px
            % height as other action-bar buttons in the app (e.g. the
            % Analysis screen's Next / Visualize row).
            cg = uigridlayout(card, [5 1]);
            cg.RowHeight = {40, 'fit', '1x', 1, 52};
            cg.ColumnWidth = {'1x'};
            cg.Padding = [18 14 18 14];
            cg.RowSpacing = 10;
            cg.BackgroundColor = cardBg;

            % ── Header ─────────────────────────────────────────────────
            headerRow = uigridlayout(cg, [1 1]);
            headerRow.Layout.Row = 1; headerRow.Layout.Column = 1;
            headerRow.ColumnWidth = {'1x'};
            headerRow.Padding = [0 0 0 0]; headerRow.ColumnSpacing = 8;
            headerRow.BackgroundColor = cardBg;

            titleLbl = uilabel(headerRow, ...
                'Text', 'Quantum Monte Carlo Simulation', ...
                'FontSize', 16, 'FontWeight', 'bold', 'FontColor', titleColor, ...
                'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            % ── Viability banner (hidden by default) ───────────────────
            % Shown when the active circuit can't be analysed in any
            % mode — e.g. a 255q QASMBench benchmark with no IBM device
            % wide enough and beyond local-statevector reach. Driven by
            % AnalysisViewModel.applyQmcViability after the backend list
            % loads and on every Mode/Backend dropdown change.
            app.QmcBanner = uigridlayout(cg, [1 1]);
            app.QmcBanner.Layout.Row = 2; app.QmcBanner.Layout.Column = 1;
            app.QmcBanner.ColumnWidth = {'1x'};
            app.QmcBanner.Padding = [12 10 12 10];
            app.QmcBanner.BackgroundColor = [0.36 0.27 0.10];  % amber on dark
            app.QmcBanner.Visible = 'off';
            app.QmcBannerLabel = uilabel(app.QmcBanner, ...
                'Text', '', ...
                'FontColor', [1.00 0.92 0.74], ...
                'WordWrap', 'on', ...
                'VerticalAlignment', 'top');

            % ── Body: controls+KPI (left)  |  plots (right) ────────────
            body = uigridlayout(cg, [1 2]);
            body.Layout.Row = 3; body.Layout.Column = 1;
            body.ColumnWidth = {320, '1x'};
            body.Padding = [0 0 0 0]; body.ColumnSpacing = Theme.GRID_ROW_SPACING;
            body.BackgroundColor = cardBg;

            left = uigridlayout(body, [3 1]);
            left.Layout.Row = 1; left.Layout.Column = 1;
            left.RowHeight = {'1x', 'fit', 'fit'};
            left.Padding = [0 0 0 0]; left.RowSpacing = 10;
            left.BackgroundColor = cardBg;

            % Controls form — scrollable so the advanced block fits.
            left.Scrollable = 'on';
            form = uigridlayout(left, [16 2]);
            form.Layout.Row = 1; form.Layout.Column = 1;
            form.RowHeight = repmat({28}, 1, 16);
            form.ColumnWidth = {130, '1x'};
            form.Padding = [0 0 0 0]; form.RowSpacing = 5; form.ColumnSpacing = 8;
            form.BackgroundColor = cardBg;

            uilabel(form, 'Text', 'Execution mode', 'FontColor', labelColor);
            app.QmcModeDropdown = uidropdown(form, ...
                'Items',     {'Statevector (local)', 'IBM Runtime'}, ...
                'ItemsData', {'statevector',          'runtime'}, ...
                'Value',     'runtime', ...
                'ValueChangedFcn', @(~,~) app.AnalysisVm.refreshQmcViability());

            uilabel(form, 'Text', 'Backend (runtime)', 'FontColor', labelColor);
            % Populated from BackendService at open time; see
            % AnalysisViewModel.loadQmcBackends. Starts with a placeholder
            % so the dropdown is usable before the async call completes.
            app.QmcBackendField = uidropdown(form, ...
                'Items',     {'(loading...)'}, ...
                'ItemsData', {''}, ...
                'Value',     '', ...
                'ValueChangedFcn', @(~,~) app.AnalysisVm.refreshQmcViability());

            uilabel(form, 'Text', 'Shots', 'FontColor', labelColor);
            app.QmcShotsField = uispinner(form, ...
                'Value', 4096, 'Limits', [128 100000], 'Step', 512);

            uilabel(form, 'Text', 'Epsilon', 'FontColor', labelColor);
            app.QmcEpsilonField = uispinner(form, ...
                'Value', 0.01, 'Limits', [0.001 0.5], 'Step', 0.005, ...
                'ValueDisplayFormat', '%.3f');

            uilabel(form, 'Text', 'Confidence', 'FontColor', labelColor);
            app.QmcConfidenceField = uispinner(form, ...
                'Value', 0.95, 'Limits', [0.80 0.999], 'Step', 0.01, ...
                'ValueDisplayFormat', '%.3f');

            uilabel(form, 'Text', 'Risk metric', 'FontColor', labelColor);
            app.QmcRiskDropdown = uidropdown(form, ...
                'Items',     {'Option price',  'VaR 95%', 'VaR 99%', 'CVaR 95%'}, ...
                'ItemsData', {'option_price',  'var_95',  'var_99',  'cvar_95'}, ...
                'Value',     'var_95');

            % ── Advanced section heading ─────────────────────────────
            sep1 = uilabel(form, 'Text', 'Error mitigation', ...
                'FontWeight', 'bold', 'FontColor', titleColor);
            sep1.Layout.Column = [1 2];

            uilabel(form, 'Text', 'Mitigation', 'FontColor', labelColor);
            app.QmcMitigationDropdown = uidropdown(form, ...
                'Items',     {'None', 'Zero-Noise Extrapolation', 'Probabilistic Error Cancellation'}, ...
                'ItemsData', {'none',  'zne',                       'pec'}, ...
                'Value',     'zne');

            sep2 = uilabel(form, 'Text', 'Market scenario (real-time)', ...
                'FontWeight', 'bold', 'FontColor', titleColor);
            sep2.Layout.Column = [1 2];

            uilabel(form, 'Text', 'Spot / Strike', 'FontColor', labelColor);
            ssRow = uigridlayout(form, [1 2]);
            ssRow.ColumnWidth = {'1x', '1x'}; ssRow.ColumnSpacing = 6;
            ssRow.Padding = [0 0 0 0]; ssRow.BackgroundColor = cardBg;
            app.QmcSpotField   = uispinner(ssRow, 'Value', 100, 'Limits', [0.01 1e6], 'Step', 1, 'ValueDisplayFormat', '%.2f');
            app.QmcStrikeField = uispinner(ssRow, 'Value', 100, 'Limits', [0.01 1e6], 'Step', 1, 'ValueDisplayFormat', '%.2f');

            uilabel(form, 'Text', 'Volatility σ', 'FontColor', labelColor);
            app.QmcVolField = uispinner(form, 'Value', 0.20, 'Limits', [0.01 2.0], 'Step', 0.01, 'ValueDisplayFormat', '%.3f');

            uilabel(form, 'Text', 'Risk-free rate r', 'FontColor', labelColor);
            app.QmcRateField = uispinner(form, 'Value', 0.05, 'Limits', [-0.05 0.50], 'Step', 0.005, 'ValueDisplayFormat', '%.3f');

            uilabel(form, 'Text', 'Maturity T (yr)', 'FontColor', labelColor);
            app.QmcTenorField = uispinner(form, 'Value', 0.0833, 'Limits', [0.0027 5.0], 'Step', 0.01, 'ValueDisplayFormat', '%.4f');

            uilabel(form, 'Text', 'Option type', 'FontColor', labelColor);
            app.QmcOptionTypeDropdown = uidropdown(form, ...
                'Items', {'Call', 'Put'}, 'ItemsData', {'call', 'put'}, 'Value', 'call');

            uilabel(form, 'Text', 'Notional', 'FontColor', labelColor);
            app.QmcNotionalField = uispinner(form, 'Value', 100, 'Limits', [1 1e9], 'Step', 10, 'ValueDisplayFormat', '%.0f');

            % KPI strip (5 cards)
            kpi = uigridlayout(left, [1 5]);
            kpi.Layout.Row = 2; kpi.Layout.Column = 1;
            kpi.ColumnWidth = {'1x','1x','1x','1x','1x'};
            kpi.Padding = [0 0 0 0]; kpi.ColumnSpacing = 4;
            kpi.BackgroundColor = cardBg;

            kpiTitles  = {'Amplitude', 'Expected', 'VaR 95%', 'VaR 99%', 'Speed ×'};
            kpiDefault = {'—', '—', '—', '—', '—'};
            app.QmcKpiLabels = cell(1, 5);
            for i = 1:5
                p = uipanel(kpi, 'Title', '', 'BorderType', 'line', ...
                    'BorderColor', cardBorder);
                p.Layout.Row = 1; p.Layout.Column = i;
                p.BackgroundColor = cardBg;
                pg = uigridlayout(p, [2 1]);
                pg.RowHeight = {14, '1x'};
                pg.Padding = [4 4 4 4];
                pg.BackgroundColor = cardBg;
                uilabel(pg, 'Text', kpiTitles{i}, 'FontSize', 10, 'FontColor', Theme.COLOR_MUTED);
                l2 = uilabel(pg, 'Text', kpiDefault{i}, ...
                    'FontSize', 14, 'FontWeight', 'bold', 'WordWrap', 'on');
                app.QmcKpiLabels{i} = l2;
            end

            % Greeks strip (5 cards: Delta / Gamma / Vega / Theta / Rho)
            greeks = uigridlayout(left, [1 5]);
            greeks.Layout.Row = 3; greeks.Layout.Column = 1;
            greeks.ColumnWidth = {'1x','1x','1x','1x','1x'};
            greeks.Padding = [0 0 0 0]; greeks.ColumnSpacing = 4;
            greeks.BackgroundColor = cardBg;
            gTitles  = {'Δ Delta', 'Γ Gamma', 'Vega', 'Θ Theta', 'ρ Rho'};
            app.QmcGreeksLabels = cell(1, 5);
            for i = 1:5
                p = uipanel(greeks, 'Title', '', 'BorderType', 'line', ...
                    'BorderColor', cardBorder);
                p.Layout.Row = 1; p.Layout.Column = i;
                p.BackgroundColor = cardBg;
                pg = uigridlayout(p, [2 1]);
                pg.RowHeight = {14, '1x'};
                pg.Padding = [4 4 4 4];
                pg.BackgroundColor = cardBg;
                uilabel(pg, 'Text', gTitles{i}, 'FontSize', 10, 'FontColor', Theme.COLOR_MUTED);
                l2 = uilabel(pg, 'Text', '—', 'FontSize', 13, 'FontWeight', 'bold', 'WordWrap', 'on');
                app.QmcGreeksLabels{i} = l2;
            end

            % Right: 3x2 grid of charts — full QMC / QMC story including
            % Zero-Noise Extrapolation.
            %   (1) Loss distribution with VaR95/VaR99 threshold lines
            %   (2) Cumulative Distribution Function (CDF) overlay
            %   (3) Convergence: QMC vs classical MC sample complexity
            %   (4) Amplitude-estimation bar chart
            %   (5) ZNE extrapolation curve (spans both bottom columns)
            plots = uigridlayout(body, [3 2]);
            plots.Layout.Row = 1; plots.Layout.Column = 2;
            plots.RowHeight = {'1x', '1x', '0.7x'};
            plots.ColumnWidth = {'1x', '1x'};
            plots.Padding = [0 0 0 0];
            plots.RowSpacing = 8; plots.ColumnSpacing = 8;
            plots.BackgroundColor = cardBg;

            app.QmcPathAxes = uiaxes(plots);
            app.QmcPathAxes.Layout.Row = 1; app.QmcPathAxes.Layout.Column = 1;
            app.styleAxes(app.QmcPathAxes);
            title(app.QmcPathAxes, 'Loss distribution with VaR thresholds');
            xlabel(app.QmcPathAxes, 'Loss (negative = P&L down)');
            ylabel(app.QmcPathAxes, 'Probability');

            app.QmcCdfAxes = uiaxes(plots);
            app.QmcCdfAxes.Layout.Row = 1; app.QmcCdfAxes.Layout.Column = 2;
            app.styleAxes(app.QmcCdfAxes);
            title(app.QmcCdfAxes, 'Cumulative loss distribution (CDF)');
            xlabel(app.QmcCdfAxes, 'Loss (negative = P&L down)');
            ylabel(app.QmcCdfAxes, 'P(loss \leq x)');

            app.QmcConvergenceAxes = uiaxes(plots);
            app.QmcConvergenceAxes.Layout.Row = 2; app.QmcConvergenceAxes.Layout.Column = 1;
            app.styleAxes(app.QmcConvergenceAxes);
            title(app.QmcConvergenceAxes, 'Convergence: QMC 1/N vs classical MC 1/\surd{N}');
            xlabel(app.QmcConvergenceAxes, 'Samples (log scale)');
            ylabel(app.QmcConvergenceAxes, 'Estimation error (log scale)');

            app.QmcAmpAxes = uiaxes(plots);
            app.QmcAmpAxes.Layout.Row = 2; app.QmcAmpAxes.Layout.Column = 2;
            app.styleAxes(app.QmcAmpAxes);
            title(app.QmcAmpAxes, 'Objective-qubit amplitude estimate');
            xlabel(app.QmcAmpAxes, 'Measured basis state');
            ylabel(app.QmcAmpAxes, 'Probability');

            app.QmcZneAxes = uiaxes(plots);
            app.QmcZneAxes.Layout.Row = 3; app.QmcZneAxes.Layout.Column = [1 2];
            app.styleAxes(app.QmcZneAxes);
            title(app.QmcZneAxes, 'Zero-Noise Extrapolation — amplitude vs noise factor');
            xlabel(app.QmcZneAxes, 'Noise factor (1.0 = native hardware)');
            ylabel(app.QmcZneAxes, 'Amplitude estimate');

            % ── Divider: 1px horizontal rule between body and footer ──
            divider = uipanel(cg, ...
                'BorderType', 'none', ...
                'BackgroundColor', Theme.COLOR_DIVIDER);
            divider.Layout.Row = 4; divider.Layout.Column = 1;

            % ── Footer: Run / Download IBM Log / Generate Report / Close ──
            % Column widths (120 / 150 / 160 / 100) and padding ([8 8 8 8])
            % + an explicit footer row height (36) pin these buttons to
            % the same footprint as other action bars in the app (e.g.
            % the Analysis screen's Next / Back / Visualize row).
            % M9 — footer grid grows from 5 → 6 cols to fit a new
            % "Download Results" button between Run QMC and Download
            % IBM Log. The three export buttons (Download Results /
            % Download IBM Log / Generate Report) start hidden — the
            % column widths are set to 0 initially so there is no
            % visual gap. AnalysisVm.revealQmcResultButtons flips
            % Visible='on' AND restores the column widths after a
            % successful Run QMC; resetQmcUi reverses both on re-run.
            footer = uigridlayout(cg, [1 6]);
            footer.Layout.Row = 5; footer.Layout.Column = 1;
            footer.RowHeight = {36};
            footer.ColumnWidth = {'1x', 200, 0, 0, 0, 100};
            footer.Padding = [8 8 8 8]; footer.ColumnSpacing = 10;
            footer.BackgroundColor = cardBg;
            % Stash the footer handle so the VM can resize columns
            % when toggling visibility.
            app.QmcFooterGrid = footer;

            uilabel(footer, 'Text', ...
                'Statevector runs locally. Switch to IBM Runtime for real-hardware shots.', ...
                'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');

            app.QmcRunButton = uibutton(footer, ...
                'Text', [char(9883) ' Run QMC'], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onRunQmcAnalysis());
            app.QmcRunButton.Layout.Row = 1; app.QmcRunButton.Layout.Column = 2;
            app.styleBtn(app.QmcRunButton, 'primary');
            app.QmcRunButton.Tooltip = 'POST /api/circuits/{id}/qae/analyze';

            app.QmcDownloadResultsBtn = uibutton(footer, ...
                'Text', [char(8681) ' Download Results'], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onDownloadQmcResults());
            app.QmcDownloadResultsBtn.Layout.Row = 1;
            app.QmcDownloadResultsBtn.Layout.Column = 3;
            app.styleBtn(app.QmcDownloadResultsBtn, 'ghost');
            app.QmcDownloadResultsBtn.Visible = 'off';
            app.QmcDownloadResultsBtn.Tooltip = ...
                'Save the cached QMC result struct to a .json file.';

            app.QmcDownloadLogButton = uibutton(footer, ...
                'Text', [char(8681) ' Download IBM Log'], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onDownloadIbmLog());
            app.QmcDownloadLogButton.Layout.Row = 1; app.QmcDownloadLogButton.Layout.Column = 4;
            app.styleBtn(app.QmcDownloadLogButton, 'ghost');
            app.QmcDownloadLogButton.Enable = 'off';
            app.QmcDownloadLogButton.Visible = 'off';
            app.QmcDownloadLogButton.Tooltip = ...
                'GET /api/circuits/{id}/qae/ibm-log — available after a successful IBM Runtime run';

            app.QmcReportButton = uibutton(footer, ...
                'Text', [char(9636) ' Generate Report'], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onGenerateQmcReport());
            app.QmcReportButton.Layout.Row = 1; app.QmcReportButton.Layout.Column = 5;
            app.styleBtn(app.QmcReportButton, 'secondary');
            app.QmcReportButton.Visible = 'off';
            app.QmcReportButton.Tooltip = 'Generate PDF (also available from Reports screen)';

            closeBtn = uibutton(footer, ...
                'Text', [char(10005) ' Close'], ...
                'ButtonPushedFcn', @(~,~) app.AnalysisVm.onCloseQmcDialog());
            closeBtn.Layout.Row = 1; closeBtn.Layout.Column = 6;
            app.styleBtn(closeBtn, 'ghost');

            % Clicking the window "X" also routes through the same
            % teardown path so any in-flight QMC poll timer is stopped.
            app.QmcDialog.CloseRequestFcn = @(~,~) app.AnalysisVm.onCloseQmcDialog();

            % Rehydration (render of any cached result) is performed by
            % the caller in AnalysisViewModel.onOpenQmcDialog so the
            % private renderQmcResult method stays encapsulated.

            Logger.info('DialogBuilder', 'Quantum Monte Carlo / QMC dialog shown');
        end

        function buildErrorMitigationDialog(app)
            % Modal popup hosting the Quantum Error Mitigation (QEM) analysis
            %   UI. Read-only over the FastAPI mitigation/QAE/cutting endpoints
            %   - does not submit jobs of its own. Visualizations:
            %     KPI strip       - qubits, depth, 2Q, gammabar, advantage
            %     ZNE panel       - measured <O> vs noise factor (cached qae)
            %     gammabar^depth  - PEC sampling-overhead feasibility curve
            %     Overhead vs k   - cutting sampling-overhead sweep
            %     Technique table - per-strategy overhead/wall preview
            %     Raw vs Mitig.   - bitstring distribution (when sibling exists)
            %     Recommendation  - heuristic auto-pick stack
            %   Driven by AnalysisViewModel.onOpenEmDialog and friends.
            figPos = app.UIFigure.Position;
            dlgW = min(1500, max(1200, round(figPos(3) * 0.92)));
            dlgH = min(1080, max(880,  round(figPos(4) * 0.95)));
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor    = Theme.COLOR_BG;
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;
            titleColor = Theme.COLOR_HEADING;
            labelColor = Theme.COLOR_LABEL;
            mutedColor = Theme.COLOR_MUTED;

            app.EmDialog = uifigure( ...
                'Name', Labels.get('analysis_em_dialog_title', ...
                                   'Quantum Error Mitigation Analysis'), ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'on', ...
                'Color', bgColor, ...
                'CloseRequestFcn', @(~,~) app.AnalysisVm.onCloseEmDialog());
            Theme.applyFigureMode(app.EmDialog, Theme.activeName());

            outerGrid = uigridlayout(app.EmDialog, [3 3]);
            outerGrid.RowHeight     = {16, '1x', 16};
            outerGrid.ColumnWidth   = {24, '1x', 24};
            outerGrid.Padding       = [0 0 0 0];
            outerGrid.RowSpacing    = 0;
            outerGrid.ColumnSpacing = 0;
            outerGrid.BackgroundColor = bgColor;

            card = uipanel(outerGrid, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, ...
                'HighlightColor', cardBorder, ...
                'BorderColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            cg = uigridlayout(card, [4 1]);
            cg.RowHeight = {40, '1x', 1, 52};
            cg.ColumnWidth = {'1x'};
            cg.Padding = [18 14 18 14];
            cg.RowSpacing = 10;
            cg.BackgroundColor = cardBg;

            % Header
            headerRow = uigridlayout(cg, [1 1]);
            headerRow.Layout.Row = 1; headerRow.Layout.Column = 1;
            headerRow.ColumnWidth = {'1x'};
            headerRow.Padding = [0 0 0 0]; headerRow.ColumnSpacing = 8;
            headerRow.BackgroundColor = cardBg;

            titleLbl = uilabel(headerRow, ...
                'Text', Labels.get('analysis_em_dialog_title', ...
                                   'Quantum Error Mitigation Analysis'), ...
                'FontSize', 16, 'FontWeight', 'bold', 'FontColor', titleColor, ...
                'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            % Body: form (left) | charts (right)
            body = uigridlayout(cg, [1 2]);
            body.Layout.Row = 2; body.Layout.Column = 1;
            body.ColumnWidth = {340, '1x'};
            body.Padding = [0 0 0 0]; body.ColumnSpacing = Theme.GRID_ROW_SPACING;
            body.BackgroundColor = cardBg;

            left = uigridlayout(body, [3 1]);
            left.Layout.Row = 1; left.Layout.Column = 1;
            % Each child sized to fit its natural content so the parent
            % can detect overflow and scroll. Was {'1x', 'fit', 'fit'} —
            % '1x' compresses the form into the available cell so the
            % outer Scrollable never engages; the bottom of the form
            % (Estimated Cost) gets clipped on shorter screens. Switched
            % to all-'fit' so total content height = sum of children, and
            % left.Scrollable = 'on' below activates a vertical scrollbar
            % whenever the dialog is shorter than that.
            left.RowHeight = {'fit', 'fit', 'fit'};
            left.Padding = [0 0 0 0]; left.RowSpacing = 10;
            left.BackgroundColor = cardBg;

            % Controls form -- scrollable so every section fits at any size.
            left.Scrollable = 'on';
            form = uigridlayout(left, [18 2]);
            form.Layout.Row = 1; form.Layout.Column = 1;
            form.RowHeight = repmat({28}, 1, 18);
            form.ColumnWidth = {130, '1x'};
            form.Padding = [0 0 0 0]; form.RowSpacing = 5; form.ColumnSpacing = 8;
            form.BackgroundColor = cardBg;

            % Section: Circuit (read-only summary line)
            sCirc = uilabel(form, ...
                'Text', Labels.get('em_section_circuit', 'Circuit'), ...
                'FontWeight', 'bold', 'FontColor', titleColor);
            sCirc.Layout.Column = [1 2];

            app.EmCircuitInfoLabel = uilabel(form, ...
                'Text', '-', 'FontColor', labelColor, 'WordWrap', 'on');
            app.EmCircuitInfoLabel.Layout.Column = [1 2];

            % Section: Mitigation Strategy
            sStrat = uilabel(form, ...
                'Text', Labels.get('em_section_strategy', 'Mitigation Strategy'), ...
                'FontWeight', 'bold', 'FontColor', titleColor);
            sStrat.Layout.Column = [1 2];

            uilabel(form, ...
                'Text', Labels.get('em_label_backend', 'Backend'), ...
                'FontColor', labelColor);
            app.EmBackendDropdown = uidropdown(form, ...
                'Items', {'(loading...)'}, 'ItemsData', {''}, 'Value', '', ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());

            uilabel(form, ...
                'Text', Labels.get('em_label_primitive', 'Primitive'), ...
                'FontColor', labelColor);
            app.EmPrimitiveDropdown = uidropdown(form, ...
                'Items', {'Sampler', 'Estimator'}, ...
                'ItemsData', {'sampler', 'estimator'}, ...
                'Value', 'sampler', ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());

            uilabel(form, ...
                'Text', Labels.get('em_label_base_shots', 'Base shots'), ...
                'FontColor', labelColor);
            app.EmBaseShotsField = uispinner(form, ...
                'Value', 4096, 'Limits', [128 100000], 'Step', 512, ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());

            uilabel(form, ...
                'Text', Labels.get('em_label_level', 'Mitigation level'), ...
                'FontColor', labelColor);
            app.EmLevelDropdown = uidropdown(form, ...
                'Items', {'(loading...)'}, 'ItemsData', {-1}, 'Value', -1, ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());

            % Section: Advanced (Custom level only)
            sAdv = uilabel(form, ...
                'Text', Labels.get('em_section_advanced', 'Advanced (Custom)'), ...
                'FontWeight', 'bold', 'FontColor', titleColor);
            sAdv.Layout.Column = [1 2];

            uilabel(form, ...
                'Text', Labels.get('em_label_zne_factors', 'ZNE noise factors'), ...
                'FontColor', labelColor);
            app.EmZneFactorsField = uieditfield(form, 'text', ...
                'Value', '1.0, 3.0, 5.0', ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());

            uilabel(form, ...
                'Text', Labels.get('em_label_zne_extrapolator', 'ZNE extrapolator'), ...
                'FontColor', labelColor);
            app.EmExtrapolatorDropdown = uidropdown(form, ...
                'Items', {'Linear', 'Polynomial', 'Exponential', 'Richardson'}, ...
                'ItemsData', {'linear', 'polynomial', 'exponential', 'richardson'}, ...
                'Value', 'exponential', ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());

            uilabel(form, ...
                'Text', Labels.get('em_label_dd_sequence', 'DD sequence'), ...
                'FontColor', labelColor);
            app.EmDdSequenceDropdown = uidropdown(form, ...
                'Items', {'XpXm', 'XY4', 'XY8', '(disabled)'}, ...
                'ItemsData', {'XpXm', 'XY4', 'XY8', ''}, ...
                'Value', 'XY4', ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());

            app.EmTwirlGatesCheckbox = uicheckbox(form, ...
                'Text', Labels.get('em_label_twirling_gates', 'Twirl gates'), ...
                'Value', true, 'FontColor', labelColor, ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());
            app.EmTwirlGatesCheckbox.Layout.Column = [1 2];

            app.EmTwirlMeasureCheckbox = uicheckbox(form, ...
                'Text', Labels.get('em_label_twirling_measure', 'Twirl measurement'), ...
                'Value', true, 'FontColor', labelColor, ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());
            app.EmTwirlMeasureCheckbox.Layout.Column = [1 2];

            app.EmTemCheckbox = uicheckbox(form, ...
                'Text', Labels.get('em_label_tem_enable', 'TEM'), ...
                'Value', false, 'FontColor', labelColor, ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());
            app.EmTemCheckbox.Layout.Column = [1 2];

            app.EmAlsoRunRawCheckbox = uicheckbox(form, ...
                'Text', Labels.get('em_label_also_run_raw', 'Also run raw sibling'), ...
                'Value', false, 'FontColor', labelColor, ...
                'ValueChangedFcn', @(~,~)app.AnalysisVm.onEmFormChanged());
            app.EmAlsoRunRawCheckbox.Layout.Column = [1 2];

            % Section: Estimated Cost
            sCost = uilabel(form, ...
                'Text', Labels.get('em_section_cost', 'Estimated Cost'), ...
                'FontWeight', 'bold', 'FontColor', titleColor);
            sCost.Layout.Column = [1 2];

            app.EmCostSummaryLabel = uilabel(form, ...
                'Text', '-', 'FontColor', labelColor, 'WordWrap', 'on');
            app.EmCostSummaryLabel.Layout.Column = [1 2];

            app.EmConflictLabel = uilabel(form, ...
                'Text', '', 'FontColor', Theme.COLOR_DANGER, 'WordWrap', 'on');
            app.EmConflictLabel.Layout.Column = [1 2];

            % KPI strip (5 cards)
            kpi = uigridlayout(left, [1 5]);
            kpi.Layout.Row = 2; kpi.Layout.Column = 1;
            kpi.ColumnWidth = {'1x','1x','1x','1x','1x'};
            kpi.Padding = [0 0 0 0]; kpi.ColumnSpacing = 4;
            kpi.BackgroundColor = cardBg;

            kpiTitles = { ...
                Labels.get('em_kpi_qubits', 'Qubits'), ...
                Labels.get('em_kpi_depth', 'Depth'), ...
                Labels.get('em_kpi_2q', '2Q gates'), ...
                Labels.get('em_kpi_gammabar', 'gammabar Score'), ...
                Labels.get('em_kpi_advantage', 'Advantage')};
            app.EmKpiLabels = cell(1, 5);
            for i = 1:5
                p = uipanel(kpi, 'Title', '', 'BorderType', 'line', ...
                    'BorderColor', cardBorder);
                p.Layout.Row = 1; p.Layout.Column = i;
                p.BackgroundColor = cardBg;
                pg = uigridlayout(p, [2 1]);
                pg.RowHeight = {14, '1x'};
                pg.Padding = [4 4 4 4];
                pg.BackgroundColor = cardBg;
                uilabel(pg, 'Text', kpiTitles{i}, 'FontSize', 10, ...
                    'FontColor', mutedColor);
                l2 = uilabel(pg, 'Text', '-', 'FontSize', 11, ...
                    'FontWeight', 'bold', 'WordWrap', 'on');
                app.EmKpiLabels{i} = l2;
            end

            % Status banner (microcopy below KPI strip)
            app.EmStatusBanner = uilabel(left, ...
                'Text', Labels.get('em_status_loading', ...
                                   'Loading mitigation analysis...'), ...
                'FontSize', 11, 'FontColor', mutedColor, 'WordWrap', 'on');
            app.EmStatusBanner.Layout.Row = 3; app.EmStatusBanner.Layout.Column = 1;

            % Right: 3x2 chart grid
            plots = uigridlayout(body, [3 2]);
            plots.Layout.Row = 1; plots.Layout.Column = 2;
            plots.RowHeight = {'1x', '1x', '1x'};
            plots.ColumnWidth = {'1x', '1x'};
            plots.Padding = [0 0 0 0];
            plots.RowSpacing = 8; plots.ColumnSpacing = 8;
            plots.BackgroundColor = cardBg;

            app.EmZneAxes = uiaxes(plots);
            app.EmZneAxes.Layout.Row = 1; app.EmZneAxes.Layout.Column = 1;
            app.styleAxes(app.EmZneAxes);
            title(app.EmZneAxes,  Labels.get('em_axes_zne_title', ...
                'ZNE - measured <O> vs noise factor'), 'Interpreter', 'none');
            xlabel(app.EmZneAxes, Labels.get('em_axes_zne_xlabel', ...
                'Noise scale factor'), 'Interpreter', 'none');
            ylabel(app.EmZneAxes, Labels.get('em_axes_zne_ylabel', ...
                'Expectation value <O>'), 'Interpreter', 'none');

            app.EmGammaDepthAxes = uiaxes(plots);
            app.EmGammaDepthAxes.Layout.Row = 1; app.EmGammaDepthAxes.Layout.Column = 2;
            app.styleAxes(app.EmGammaDepthAxes);
            title(app.EmGammaDepthAxes,  Labels.get('em_axes_gamma_depth_title', ...
                'PEC sampling overhead gammabar^depth'), 'Interpreter', 'none');
            xlabel(app.EmGammaDepthAxes, Labels.get('em_axes_gamma_depth_xlabel', ...
                'Layered-gate depth'), 'Interpreter', 'none');
            ylabel(app.EmGammaDepthAxes, Labels.get('em_axes_gamma_depth_ylabel', ...
                'Sampling overhead (x shots)'), 'Interpreter', 'none');

            app.EmOverheadCutsAxes = uiaxes(plots);
            app.EmOverheadCutsAxes.Layout.Row = 2; app.EmOverheadCutsAxes.Layout.Column = 1;
            app.styleAxes(app.EmOverheadCutsAxes);
            title(app.EmOverheadCutsAxes,  Labels.get('em_axes_overhead_cuts_title', ...
                'Cutting sampling overhead vs target k'), 'Interpreter', 'none');
            xlabel(app.EmOverheadCutsAxes, Labels.get('em_axes_overhead_cuts_xlabel', ...
                'Number of cuts (k)'), 'Interpreter', 'none');
            ylabel(app.EmOverheadCutsAxes, Labels.get('em_axes_overhead_cuts_ylabel', ...
                'Sampling overhead (x shots)'), 'Interpreter', 'none');

            % Technique table
            app.EmTechniqueTable = uitable(plots);
            app.EmTechniqueTable.Layout.Row = 2; app.EmTechniqueTable.Layout.Column = 2;
            app.EmTechniqueTable.ColumnName = Labels.cols('em_table_technique_cols', ...
                {'Technique', 'Bias', 'Overhead x', 'Wall (s)', 'Pick'});
            app.EmTechniqueTable.Data = {};
            app.EmTechniqueTable.RowName = {};
            app.styleTable(app.EmTechniqueTable);

            app.EmHistogramAxes = uiaxes(plots);
            app.EmHistogramAxes.Layout.Row = 3; app.EmHistogramAxes.Layout.Column = 1;
            app.styleAxes(app.EmHistogramAxes);
            title(app.EmHistogramAxes,  Labels.get('em_axes_histogram_title', ...
                'Raw vs Mitigated counts (top bitstrings)'), 'Interpreter', 'none');
            xlabel(app.EmHistogramAxes, Labels.get('em_axes_histogram_xlabel', ...
                'Bitstring'), 'Interpreter', 'none');
            ylabel(app.EmHistogramAxes, Labels.get('em_axes_histogram_ylabel', ...
                'Probability'), 'Interpreter', 'none');

            % Recommendation card
            recPanel = uipanel(plots, 'Title', '', 'BorderType', 'line', ...
                'BorderColor', cardBorder, 'BackgroundColor', cardBg);
            recPanel.Layout.Row = 3; recPanel.Layout.Column = 2;
            recGrid = uigridlayout(recPanel, [2 1]);
            recGrid.RowHeight = {20, '1x'};
            recGrid.Padding = [10 8 10 8];
            recGrid.BackgroundColor = cardBg;
            uilabel(recGrid, 'Text', ...
                Labels.get('em_recommendation_title', 'Recommended mitigation stack'), ...
                'FontWeight', 'bold', 'FontColor', titleColor);
            app.EmRecommendationLabel = uilabel(recGrid, ...
                'Text', Labels.get('em_recommendation_empty', ...
                    'Pick a backend and circuit to see a recommendation.'), ...
                'FontColor', labelColor, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top');

            % Divider
            divider = uipanel(cg, ...
                'BorderType', 'none', ...
                'BackgroundColor', Theme.COLOR_DIVIDER);
            divider.Layout.Row = 3; divider.Layout.Column = 1;

            % Footer
            footer = uigridlayout(cg, [1 6]);
            footer.Layout.Row = 4; footer.Layout.Column = 1;
            footer.RowHeight = {36};
            footer.ColumnWidth = {'1x', 110, 170, 130, 150, 100};
            footer.Padding = [8 8 8 8]; footer.ColumnSpacing = 10;
            footer.BackgroundColor = cardBg;

            uilabel(footer, ...
                'Text', Labels.get('em_footer_hint', ''), ...
                'FontSize', 11, 'FontColor', mutedColor, 'WordWrap', 'on');

            app.EmRunButton = uibutton(footer, ...
                'Text', [char(8634) ' ' Labels.get('em_btn_run', 'Estimate')], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onEmRefreshEstimate());
            app.EmRunButton.Layout.Row = 1; app.EmRunButton.Layout.Column = 2;
            app.styleBtn(app.EmRunButton, 'primary');
            app.EmRunButton.Tooltip = ...
                'Re-run /api/mitigation/estimate over every technique and refresh the panels';

            app.EmApplyButton = uibutton(footer, ...
                'Text', [char(9004) ' ' Labels.get('em_btn_apply', 'Apply to Benchmark')], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onEmApplyToBenchmark());
            app.EmApplyButton.Layout.Row = 1; app.EmApplyButton.Layout.Column = 3;
            app.styleBtn(app.EmApplyButton, 'secondary');
            app.EmApplyButton.Tooltip = ...
                'Pre-fill the Benchmark screen with the recommended mitigation strategy';

            app.EmExportButton = uibutton(footer, ...
                'Text', [char(8681) ' ' Labels.get('em_btn_export', 'Export JSON')], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onEmExportJson());
            app.EmExportButton.Layout.Row = 1; app.EmExportButton.Layout.Column = 4;
            app.styleBtn(app.EmExportButton, 'ghost');

            app.EmReportButton = uibutton(footer, ...
                'Text', [char(9636) ' ' Labels.get('em_btn_report', 'Generate Report')], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onEmGenerateReport());
            app.EmReportButton.Layout.Row = 1; app.EmReportButton.Layout.Column = 5;
            app.styleBtn(app.EmReportButton, 'secondary');

            closeBtn = uibutton(footer, ...
                'Text', [char(10005) ' ' Labels.get('em_btn_close', 'Close')], ...
                'ButtonPushedFcn', @(~,~) app.AnalysisVm.onCloseEmDialog());
            closeBtn.Layout.Row = 1; closeBtn.Layout.Column = 6;
            app.styleBtn(closeBtn, 'ghost');

            Logger.info('DialogBuilder', 'Quantum Error Mitigation dialog shown');
        end

        function html = textInputHtml(placeholder, initialValue)
            %textInputHtml  Inline HTML for a styled <input type="text">.
            %   Returns an HTML string for use with uihtml. JS sends
            %   {a:"i",v:value} on input and {a:"enter",v:value} on Enter.
            %   MATLAB can send {a:"set",v:newValue} or {a:"clear"} via Data.
            %   CSS colors are resolved from the active Theme so the field
            %   blends into dark / solarized / nord / etc. palettes.
            if nargin < 2, initialValue = ''; end
            inputBg      = Theme.toHex(Theme.COLOR_BG);
            inputFg      = Theme.toHex(Theme.COLOR_HEADING);
            % Rest-state border matches the field bg so the box disappears
            % into the card; on focus it swaps to the primary accent.
            inputBorder  = inputBg;
            inputFocus   = Theme.toHex(Theme.COLOR_PRIMARY);
            placeholderC = Theme.toHex(Theme.COLOR_MUTED);
            html = [ ...
                '<html><head><style>' ...
                '*{box-sizing:border-box;margin:0;padding:0;}' ...
                'html,body{height:100%;background:transparent;color-scheme:dark;}' ...
                'body{display:flex;align-items:center;' ...
                'font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;}' ...
                'input{width:100%;height:34px;padding:6px 10px;font-size:14px;' ...
                '-webkit-appearance:none;appearance:none;' ...
                'color:' inputFg ';border:1px solid ' inputBorder ';border-radius:6px;outline:none;background:' inputBg ';}' ...
                'input:focus{border-color:' inputFocus ';box-shadow:0 0 0 2px rgba(67,97,238,0.18);}' ...
                'input::placeholder{color:' placeholderC ';}' ...
                '</style></head><body>' ...
                '<input type="text" id="tf" placeholder="' placeholder '"' ...
                ' value="' strrep(initialValue, '"', '&quot;') '"' ...
                ' autocomplete="off" spellcheck="false">' ...
                '<script>' ...
                'function setup(comp){' ...
                'var tf=document.getElementById("tf");' ...
                'tf.addEventListener("input",function(){' ...
                'comp.Data={a:"i",v:tf.value};});' ...
                'tf.addEventListener("keydown",function(e){' ...
                'if(e.key==="Enter"){comp.Data={a:"enter",v:tf.value};}});' ...
                'comp.addEventListener("DataChanged",function(){' ...
                'var d=comp.Data;if(!d)return;' ...
                'if(d.a==="clear"){tf.value="";}' ...
                'if(d.a==="set"&&d.v!==undefined){tf.value=d.v;}' ...
                'if(d.a==="focus"){tf.focus();}});' ...
                '}' ...
                '</script></body></html>'];
        end

        function buildReconstructionDialog(app, bid, status, data)
            % Polished modal for a cutting batch's reconstruction. Tier 2
            % layout: status pill, top-level KPI strip (subcircuits /
            % backends / total shots / observables submitted-vs-
            % reconstructed), a Cut Topology panel (γ + log10(γ) +
            % recommended shots, a qubit-strip showing per-qubit
            % partition labels, and per-subcircuit cards listing
            % backend / shots / sub-experiments / status), an
            % Expectation values table with Pauli strings prettified
            % (Z(x)156 notation), and a diagnostic callout when one or
            % more values came back as NaN. The topology panel is
            % collapsed (RowHeight=0) for legacy batches whose result
            % payload predates the partition_labels / subcircuits
            % fields, so the dialog renders cleanly against either.
            figPos = app.UIFigure.Position;
            dlgW = min(1180, max(960, round(figPos(3) * 0.78)));
            dlgH = min(900,  max(680, round(figPos(4) * 0.86)));
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor    = Theme.COLOR_BG;
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;
            titleColor = Theme.COLOR_HEADING;
            labelColor = Theme.COLOR_LABEL;

            dlg = uifigure( ...
                'Name', 'Reconstruction Summary', ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', 'Resize', 'on', ...
                'Color', bgColor, ...
                'CloseRequestFcn', @(src,~) delete(src));
            try; Theme.applyFigureMode(dlg, Theme.activeName()); catch; end

            outer = uigridlayout(dlg, [3 3]);
            outer.RowHeight     = {16, '1x', 16};
            outer.ColumnWidth   = {18, '1x', 18};
            outer.Padding       = [0 0 0 0];
            outer.RowSpacing    = 0;
            outer.ColumnSpacing = 0;
            outer.BackgroundColor = bgColor;

            card = uipanel(outer, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, 'BorderColor', cardBorder, ...
                'HighlightColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            % Row 1: header. Row 2: top KPI cards. Row 3: Cut Topology
            % panel (collapses to 0 when no partition_labels). Row 4:
            % body (table + diag). Row 5: 1-px divider. Row 6: footer.
            partLabels = JsonHelper.pick(data, 'partition_labels', {});
            subList    = JsonHelper.pick(data, 'subcircuits', {});
            haveTopo   = (~isempty(partLabels) && ~all(cellfun('isempty', ...
                DialogBuilder.cellOrEmpty(partLabels)))) ...
                || ~isempty(DialogBuilder.cellOrEmpty(subList));
            if haveTopo
                topoRowHeight = 'fit';
            else
                topoRowHeight = 0;
            end
            cg = uigridlayout(card, [6 1]);
            cg.RowHeight   = {62, 84, topoRowHeight, '1x', 1, 52};
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [20 14 20 14];
            cg.RowSpacing  = 12;
            cg.BackgroundColor = cardBg;

            % ── Header
            header = uigridlayout(cg, [2 1]);
            header.Layout.Row = 1; header.Layout.Column = 1;
            header.RowHeight = {28, 22};
            header.RowSpacing = 4; header.Padding = [0 0 0 0];
            header.BackgroundColor = cardBg;

            titleLbl = uilabel(header, ...
                'Text', 'Reconstruction Summary', ...
                'FontSize', 18, 'FontWeight', 'bold', ...
                'FontColor', titleColor, 'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1;

            subLbl = uilabel(header, ...
                'Text', sprintf('Batch  %s   %c   Status: %s', ...
                    bid, char(8226), upper(char(status))), ...
                'FontSize', 12, 'FontColor', labelColor, ...
                'VerticalAlignment', 'center');
            subLbl.Layout.Row = 2;

            % ── Execution context: cards that explain what was cut, run,
            %    and reconstructed. These read the new BatchResultResponse
            %    fields (subcircuit_count, backends_used, total_shots,
            %    observables_submitted); old payloads without them just
            %    render '--'.
            exps  = JsonHelper.pick(data, 'expectations', {});
            items = DialogBuilder.normaliseExpectations(exps);
            [nObs, nFinite, nNaN] = DialogBuilder.tallyExpectations(items);

            kSub   = JsonHelper.pick(data, 'subcircuit_count', []);
            beList = JsonHelper.pick(data, 'backends_used', {});
            shots  = JsonHelper.pick(data, 'total_shots', []);
            nSubmitted = JsonHelper.pick(data, 'observables_submitted', []);

            kpis = uigridlayout(cg, [1 4]);
            kpis.Layout.Row = 2; kpis.Layout.Column = 1;
            kpis.ColumnWidth = {'1x', '1.4x', '1x', '1x'};
            kpis.ColumnSpacing = 12; kpis.Padding = [0 0 0 0];
            kpis.BackgroundColor = cardBg;

            DialogBuilder.metaCard(kpis, 1, 'Subcircuits', ...
                DialogBuilder.formatIntOrDash(kSub), Theme.COLOR_PRIMARY);
            DialogBuilder.metaCard(kpis, 2, 'Backends', ...
                DialogBuilder.formatBackendsValue(beList), Theme.COLOR_PURPLE);
            DialogBuilder.metaCard(kpis, 3, 'Total shots', ...
                DialogBuilder.formatIntOrDash(shots), Theme.COLOR_AMBER);
            obsLabel = sprintf('%s submitted %c %d reconstructed', ...
                DialogBuilder.formatIntOrDash(nSubmitted), char(8226), nFinite);
            if nNaN > 0
                obsAccent = Theme.COLOR_DANGER;
            else
                obsAccent = Theme.COLOR_SUCCESS;
            end
            DialogBuilder.metaCard(kpis, 4, 'Observables', ...
                obsLabel, obsAccent);

            % ── Cut Topology panel (Tier 2). Renders γ KPIs +
            %    qubit-colour-strip + per-subcircuit cards. Collapses
            %    silently when the result payload doesn't carry
            %    partition_labels / subcircuits (legacy batches).
            if haveTopo
                topoPanel = uipanel(cg, ...
                    'Title', '', 'BorderType', 'line', ...
                    'BorderColor', cardBorder, ...
                    'BackgroundColor', cardBg);
                topoPanel.Layout.Row = 3; topoPanel.Layout.Column = 1;
                DialogBuilder.renderTopologyPanel(topoPanel, data);
            else
                % Reserve the row but draw nothing — keeps the rest of
                % the layout stable when topology data is absent.
                spacer = uipanel(cg, ...
                    'Title', '', 'BorderType', 'none', ...
                    'BackgroundColor', cardBg);
                spacer.Layout.Row = 3; spacer.Layout.Column = 1;
            end

            % ── Body: table + (optional) diagnostic
            body = uigridlayout(cg, [2 1]);
            body.Layout.Row = 4; body.Layout.Column = 1;
            if nNaN > 0
                body.RowHeight = {'1x', 96};
            else
                body.RowHeight = {'1x', 0};
            end
            body.RowSpacing = 10; body.Padding = [0 0 0 0];
            body.BackgroundColor = cardBg;

            tablePanel = uipanel(body, 'Title', 'Expectation values', ...
                'BorderType', 'line', 'BorderColor', cardBorder, ...
                'BackgroundColor', cardBg);
            tablePanel.Layout.Row = 1;

            tg = uigridlayout(tablePanel, [1 1]);
            tg.Padding = [10 8 10 8]; tg.BackgroundColor = cardBg;

            tbl = uitable(tg);
            tbl.ColumnName  = {'#', 'Observable', 'Value', 'Std err', 'Status'};
            tbl.ColumnWidth = {40, 460, 120, 110, 90};
            tbl.RowName     = {};
            tbl.Data        = DialogBuilder.expectationsToRows(items);
            try; StyleHelper.styleTable(tbl); catch; end

            if nNaN > 0
                diag = uipanel(body, 'Title', '', 'BorderType', 'line', ...
                    'BorderColor', Theme.COLOR_DANGER, ...
                    'BackgroundColor', cardBg);
                diag.Layout.Row = 2;

                dg = uigridlayout(diag, [1 2]);
                dg.ColumnWidth = {6, '1x'};
                dg.Padding = [0 0 0 0]; dg.ColumnSpacing = 0;
                dg.BackgroundColor = cardBg;

                strip = uipanel(dg, 'Title', '', 'BorderType', 'none');
                strip.Layout.Column = 1;
                strip.BackgroundColor = Theme.COLOR_DANGER;

                txt = uigridlayout(dg, [2 1]);
                txt.Layout.Column = 2;
                txt.RowHeight = {22, '1x'};
                txt.RowSpacing = 4; txt.Padding = [12 8 12 8];
                txt.BackgroundColor = cardBg;

                isMissingObs = DialogBuilder.expectationsHaveStatus( ...
                    items, 'no_observables_submitted');
                if isMissingObs
                    headerTxt = 'No observables were submitted with this batch';
                    bodyTxt = ['The batch was created without an ' ...
                         'explicit observables list, so the server has ' ...
                         'nothing to reconstruct against. Re-create the ' ...
                         'batch via POST /api/cutting/batches and pass ' ...
                         'observables=["Z","X","ZZ",...] - one Pauli ' ...
                         'string per observable of interest, each ' ...
                         'aligned with the original circuit width. ' ...
                         'Use Copy JSON to inspect the raw payload.'];
                else
                    headerTxt = sprintf('%d observable(s) returned NaN', nNaN);
                    bodyTxt = ['Possible causes: missing or empty ' ...
                         'primitive results from one of the cut ' ...
                         'subcircuits, observables that do not align ' ...
                         'with the cut plan, or per-subcircuit shot ' ...
                         'count too low for a stable estimate. ' ...
                         'Re-run the batch with more shots or use Copy ' ...
                         'JSON to confirm every cut label produced a ' ...
                         'non-empty distribution.'];
                end

                hdr = uilabel(txt, 'Text', headerTxt, ...
                    'FontWeight', 'bold', ...
                    'FontColor', Theme.COLOR_DANGER, 'FontSize', 13);
                hdr.Layout.Row = 1;

                msg = uilabel(txt, 'Text', bodyTxt, ...
                    'WordWrap', 'on', 'FontColor', labelColor, 'FontSize', 12);
                msg.Layout.Row = 2;
            end

            % ── Divider: 1-px hairline separating body from footer.
            divider = uipanel(cg, ...
                'BorderType', 'none', ...
                'BackgroundColor', Theme.COLOR_DIVIDER);
            divider.Layout.Row = 5; divider.Layout.Column = 1;

            % ── Footer.
            % RowHeight 36 + Padding [8 8 8 8] match the QmcDialog footer
            % so the buttons render at the same height as the rest of the
            % app's action bars (Refresh / View Reconstruction / etc.).
            footer = uigridlayout(cg, [1 3]);
            footer.Layout.Row = 6; footer.Layout.Column = 1;
            footer.RowHeight = {36};
            footer.ColumnWidth = {'1x', 140, 100};
            footer.ColumnSpacing = 10; footer.Padding = [8 8 8 8];
            footer.BackgroundColor = cardBg;

            uilabel(footer, 'Text', '');

            % Glyphs picked from the same Unicode dingbats block as the
            % rest of the action-bar buttons so they render reliably
            % across platforms (no emoji fallback boxes on macOS).
            copyBtn = uibutton(footer, ...
                'Text', [char(8689) ' Copy JSON'], ...
                'ButtonPushedFcn', @(~,~) DialogBuilder.copyReconstructionJson(data));
            copyBtn.Layout.Column = 2;
            copyBtn.Tooltip = 'Copy the raw BatchResultResponse to the clipboard.';
            try; StyleHelper.styleBtn(copyBtn, 'secondary'); catch; end

            closeBtn = uibutton(footer, ...
                'Text', [char(10005) ' Close'], ...
                'ButtonPushedFcn', @(~,~) delete(dlg));
            closeBtn.Layout.Column = 3;
            try; StyleHelper.styleBtn(closeBtn, 'primary'); catch; end
        end

        function renderTopologyPanel(parent, data)
            % Tier 2 panel: γ summary card row, qubit-strip showing
            % which partition each qubit landed in, and per-subcircuit
            % cards listing backend / shots / sub-experiments / status.
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;

            outer = uigridlayout(parent, [3 1]);
            outer.RowHeight = {22, 'fit', 'fit'};
            outer.RowSpacing = 8;
            outer.Padding = [12 10 12 12];
            outer.BackgroundColor = cardBg;

            uilabel(outer, 'Text', 'Cut topology', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'FontColor', Theme.COLOR_HEADING);

            % γ + log10(γ) + recommended-shots strip (compact mini-KPIs).
            gammaRow = uigridlayout(outer, [1 3]);
            gammaRow.ColumnWidth = {'1x', '1x', '1.4x'};
            gammaRow.ColumnSpacing = 10;
            gammaRow.Padding = [0 0 0 0];
            gammaRow.BackgroundColor = cardBg;

            gamma     = JsonHelper.pickNumeric(data, 'sampling_overhead', NaN);
            gammaLog  = JsonHelper.pickNumeric(data, 'sampling_overhead_log10', NaN);
            recShots  = DialogBuilder.formatRecommendedShots(gamma);
            DialogBuilder.miniKpi(gammaRow, 1, 'Sampling overhead γ', ...
                DialogBuilder.formatGamma(gamma, gammaLog), Theme.COLOR_AMBER);
            if isfinite(gammaLog)
                logTxt = sprintf('%.3f', gammaLog);
            elseif isfinite(gamma) && gamma > 0
                logTxt = sprintf('%.3f', log10(gamma));
            else
                logTxt = char(8212);
            end
            DialogBuilder.miniKpi(gammaRow, 2, 'log10(γ)', logTxt, Theme.COLOR_PURPLE);
            DialogBuilder.miniKpi(gammaRow, 3, 'Recommended shots / sub-experiment', ...
                recShots, Theme.COLOR_PRIMARY);

            % Qubit strip + per-subcircuit cards. Use a 2-row layout
            % rather than two flat children so the strip can flex full
            % width while the cards self-size.
            stack = uigridlayout(outer, [2 1]);
            stack.RowHeight = {'fit', 'fit'};
            stack.RowSpacing = 8;
            stack.Padding = [0 0 0 0];
            stack.BackgroundColor = cardBg;

            DialogBuilder.renderQubitStrip(stack, data, cardBorder);
            DialogBuilder.renderSubcircuitCards(stack, data);
        end

        function miniKpi(parent, col, label, value, accent)
            % Compact inline KPI used inside the Cut Topology panel —
            % thinner than metaCard, no accent strip, label-on-top.
            p = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
                'BorderColor', Theme.COLOR_DIVIDER, ...
                'BackgroundColor', Theme.COLOR_CARD);
            p.Layout.Row = 1; p.Layout.Column = col;

            g = uigridlayout(p, [1 2]);
            g.ColumnWidth = {4, '1x'};
            g.Padding = [0 0 0 0]; g.ColumnSpacing = 0;
            g.BackgroundColor = Theme.COLOR_CARD;

            strip = uipanel(g, 'Title', '', 'BorderType', 'none');
            strip.Layout.Column = 1;
            strip.BackgroundColor = accent;

            inner = uigridlayout(g, [2 1]);
            inner.Layout.Column = 2;
            inner.RowHeight = {16, '1x'};
            inner.Padding = [10 4 10 4]; inner.RowSpacing = 0;
            inner.BackgroundColor = Theme.COLOR_CARD;

            uilabel(inner, 'Text', label, ...
                'FontSize', 11, 'FontColor', Theme.COLOR_MUTED);
            uilabel(inner, 'Text', value, ...
                'FontWeight', 'bold', 'FontSize', 16, ...
                'FontColor', Theme.COLOR_HEADING);
        end

        function renderQubitStrip(parent, data, borderCol)
            % Horizontal strip of n cells (n = circuit width) coloured
            % by partition label. Each cell's tooltip names the qubit
            % index and its assigned subcircuit so a 255-wide strip
            % stays inspectable. Falls back to a caption when no
            % partition labels are present.
            cardBg = Theme.COLOR_CARD;
            row = uigridlayout(parent, [2 1]);
            row.RowHeight = {18, 28};
            row.RowSpacing = 4;
            row.Padding = [0 0 0 0];
            row.BackgroundColor = cardBg;

            uilabel(row, 'Text', 'Partition map (one cell per qubit, coloured by subcircuit)', ...
                'FontSize', 11, 'FontColor', Theme.COLOR_MUTED);

            partLabels = DialogBuilder.cellOrEmpty( ...
                JsonHelper.pick(data, 'partition_labels', {}));
            n = numel(partLabels);
            if n == 0
                uilabel(row, 'Text', '(no partition labels available)', ...
                    'FontColor', Theme.COLOR_MUTED, 'FontSize', 12);
                return;
            end
            % Distinct labels in stable order so colour mapping is
            % deterministic across renders.
            uniq = {};
            for i = 1:n
                lbl = char(string(partLabels{i}));
                if ~any(strcmp(uniq, lbl)); uniq{end+1} = lbl; end %#ok<AGROW>
            end

            stripGrid = uigridlayout(row, [1 n]);
            stripGrid.ColumnWidth = repmat({'1x'}, 1, n);
            stripGrid.ColumnSpacing = 0;
            stripGrid.Padding = [0 0 0 0];
            stripGrid.BackgroundColor = cardBg;

            for i = 1:n
                lbl = char(string(partLabels{i}));
                idx = find(strcmp(uniq, lbl), 1);
                accent = DialogBuilder.subcircuitAccent(idx);
                cell = uipanel(stripGrid, 'Title', '', 'BorderType', 'none', ...
                    'BackgroundColor', accent);
                cell.Layout.Column = i;
                cell.Tooltip = sprintf('Qubit %d  →  %s', i - 1, lbl);
            end
            % Row 2 is a hidden divider so the strip vertical-aligns
            % cleanly above the per-subcircuit cards.
            sep = uipanel(row, 'Title', '', 'BorderType', 'none', ...
                'BackgroundColor', borderCol);
            sep.Layout.Row = 2;
            sep.Visible = 'off';
        end

        function renderSubcircuitCards(parent, data)
            % One card per subcircuit. Layout: 1 row, k columns. Each
            % card shows label / qubit count / backend / shots /
            % sub-experiments / status with a colour strip matching
            % the qubit-strip palette so the user can read across.
            cardBg = Theme.COLOR_CARD;
            subList = DialogBuilder.cellOrEmpty( ...
                JsonHelper.pick(data, 'subcircuits', {}));
            perQubits = DialogBuilder.cellOrEmpty( ...
                JsonHelper.pick(data, 'per_subcircuit_qubits', {}));
            k = numel(subList);
            if k == 0
                lbl = uilabel(parent, ...
                    'Text', '(per-subcircuit detail unavailable)', ...
                    'FontColor', Theme.COLOR_MUTED, 'FontSize', 12);
                lbl.Layout.Row = 2;
                return;
            end
            cards = uigridlayout(parent, [1 k]);
            cards.ColumnWidth = repmat({'1x'}, 1, k);
            cards.ColumnSpacing = 8;
            cards.Padding = [0 0 0 0];
            cards.BackgroundColor = cardBg;

            for i = 1:k
                e = subList{i};
                lbl = char(string(JsonHelper.pick(e, 'label', sprintf('s%d', i-1))));
                backend = char(string(JsonHelper.pick(e, 'backend', '')));
                shots   = JsonHelper.pickNumeric(e, 'shots', 0);
                nExp    = JsonHelper.pickNumeric(e, 'num_subexperiments', 0);
                stat    = char(string(JsonHelper.pick(e, 'status', '')));
                if i <= numel(perQubits)
                    nq = JsonHelper.toDouble(perQubits{i});
                else
                    nq = NaN;
                end

                card = uipanel(cards, 'Title', '', 'BorderType', 'line', ...
                    'BorderColor', Theme.COLOR_DIVIDER, ...
                    'BackgroundColor', cardBg);
                card.Layout.Column = i;

                cardGrid = uigridlayout(card, [1 2]);
                cardGrid.ColumnWidth = {5, '1x'};
                cardGrid.Padding = [0 0 0 0]; cardGrid.ColumnSpacing = 0;
                cardGrid.BackgroundColor = cardBg;

                strip = uipanel(cardGrid, 'Title', '', 'BorderType', 'none', ...
                    'BackgroundColor', DialogBuilder.subcircuitAccent(i));
                strip.Layout.Column = 1;

                inner = uigridlayout(cardGrid, [5 1]);
                inner.Layout.Column = 2;
                inner.RowHeight = {18, 16, 16, 16, 18};
                inner.RowSpacing = 2;
                inner.Padding = [10 6 10 6];
                inner.BackgroundColor = cardBg;

                if isfinite(nq) && nq > 0
                    titleTxt = sprintf('%s  %c  %d qubits', lbl, char(8226), round(nq));
                else
                    titleTxt = lbl;
                end
                uilabel(inner, 'Text', titleTxt, ...
                    'FontWeight', 'bold', 'FontSize', 13, ...
                    'FontColor', Theme.COLOR_HEADING);

                if isempty(backend); backend = char(8212); end
                uilabel(inner, 'Text', sprintf('Backend: %s', backend), ...
                    'FontSize', 11, 'FontColor', Theme.COLOR_LABEL);
                uilabel(inner, 'Text', sprintf('Shots: %s', ...
                    DialogBuilder.formatIntOrDash(shots)), ...
                    'FontSize', 11, 'FontColor', Theme.COLOR_LABEL);
                uilabel(inner, 'Text', sprintf('Sub-experiments: %s', ...
                    DialogBuilder.formatIntOrDash(nExp)), ...
                    'FontSize', 11, 'FontColor', Theme.COLOR_LABEL);

                statTxt = upper(stat);
                if isempty(strtrim(statTxt)); statTxt = char(8212); end
                statColor = DialogBuilder.statusAccent(stat);
                uilabel(inner, 'Text', sprintf('Status: %s', statTxt), ...
                    'FontSize', 11, 'FontWeight', 'bold', ...
                    'FontColor', statColor);
            end
        end

        function c = subcircuitAccent(idx)
            % Stable accent palette for subcircuit cards / strip cells.
            % Cycles through 6 distinct colours so even a 6-cut batch
            % stays distinguishable.
            palette = [ ...
                Theme.COLOR_PRIMARY; ...
                Theme.COLOR_SUCCESS; ...
                Theme.COLOR_AMBER;   ...
                Theme.COLOR_PURPLE;  ...
                Theme.COLOR_DANGER;  ...
                [0.25 0.62 0.85]];
            n = size(palette, 1);
            i = mod(max(0, idx - 1), n) + 1;
            c = palette(i, :);
        end

        function c = statusAccent(stat)
            % Map IBM-job status strings to the existing job-status
            % palette used elsewhere in the app.
            switch lower(strtrim(char(stat)))
                case 'completed'; c = Theme.COLOR_SUCCESS;
                case {'running', 'executing'}; c = Theme.COLOR_PRIMARY;
                case {'queued', 'pending', 'partitioning', 'reconstructing'}
                    c = Theme.COLOR_AMBER;
                case {'failed', 'cancelled', 'partial_failure'}
                    c = Theme.COLOR_DANGER;
                otherwise; c = Theme.COLOR_MUTED;
            end
        end

        function s = formatGamma(gamma, gammaLog)
            % Render γ in scientific form when it's huge (the cutting
            % addon's own ceiling is 1e6 — anything above ~1e3 is
            % already operationally rough), plain decimal otherwise.
            if isfinite(gamma) && gamma > 0
                if gamma >= 1e3
                    s = sprintf('%.2e', gamma);
                else
                    s = sprintf('%.1f', gamma);
                end
                return;
            end
            if isfinite(gammaLog) && gammaLog > 0
                s = sprintf('10^%.1f', gammaLog);
                return;
            end
            s = char(8212);
        end

        function s = formatRecommendedShots(gamma)
            % Rule-of-thumb shot guidance: each sub-experiment needs
            % roughly γ × 10^4 shots to recover simulator-level
            % precision after QPD reconstruction. We round up to the
            % next power of 2 (4096, 8192, 16384, ...) for IBM-friendly
            % numbers and cap at 1e6 — above that any single-batch run
            % is operationally infeasible and the operator should cut
            % differently or accept high std_err.
            if ~isfinite(gamma) || gamma <= 0
                s = char(8212);
                return;
            end
            target = gamma * 1e4;
            target = min(target, 1e6);
            rec = 2 ^ ceil(log2(max(target, 1)));
            if rec >= 1e6
                s = sprintf('%.1e (capped)', rec);
            else
                s = sprintf('%d', round(rec));
            end
        end

        function out = cellOrEmpty(v)
            % Coerce a JSON-decoded list field into a cell array. webread
            % returns either a cell, a struct array (for homogeneous
            % object lists), a numeric array, or an empty/struct/[] for
            % missing fields. The dialog renderers all want a cell.
            if isempty(v); out = {}; return; end
            if iscell(v); out = v; return; end
            if isstruct(v); out = num2cell(v(:).'); return; end
            if isnumeric(v) || islogical(v); out = num2cell(v(:).'); return; end
            if isstring(v); out = cellstr(v(:).'); return; end
            if ischar(v); out = {v}; return; end
            out = {};
        end

        function metaCard(parent, col, label, value, accent)
            % One KPI tile inside the Reconstruction Summary header.
            % Mirrors the accent-strip + label-on-top + big-number-below
            % pattern used elsewhere in the app.
            p = uipanel(parent, 'Title', '', 'BorderType', 'line', ...
                'BorderColor', Theme.COLOR_DIVIDER, ...
                'BackgroundColor', Theme.COLOR_CARD);
            p.Layout.Row = 1; p.Layout.Column = col;

            g = uigridlayout(p, [1 2]);
            g.ColumnWidth = {5, '1x'};
            g.Padding = [0 0 0 0]; g.ColumnSpacing = 0;
            g.BackgroundColor = Theme.COLOR_CARD;

            strip = uipanel(g, 'Title', '', 'BorderType', 'none');
            strip.Layout.Column = 1;
            strip.BackgroundColor = accent;

            inner = uigridlayout(g, [2 1]);
            inner.Layout.Column = 2;
            inner.RowHeight = {18, '1x'};
            inner.Padding = [10 8 10 8]; inner.RowSpacing = 0;
            inner.BackgroundColor = Theme.COLOR_CARD;

            uilabel(inner, 'Text', label, ...
                'FontSize', 11, 'FontColor', Theme.COLOR_MUTED);
            uilabel(inner, 'Text', value, ...
                'FontWeight', 'bold', 'FontSize', 22, ...
                'FontColor', Theme.COLOR_HEADING);
        end

        function items = normaliseExpectations(exps)
            % Coerce the JSON-decoded `expectations` field into a 1xN
            % cell array of structs regardless of whether webread gave
            % us a struct array, a cell of structs, or empty.
            if iscell(exps); items = exps;
            elseif isstruct(exps); items = num2cell(exps(:).');
            else; items = {};
            end
        end

        function [nObs, nFinite, nNaN] = tallyExpectations(items)
            nObs = numel(items);
            nFinite = 0; nNaN = 0;
            for i = 1:nObs
                v = JsonHelper.pick(items{i}, 'value', NaN);
                if ~isnumeric(v); v = str2double(v); end
                if isempty(v) || all(isnan(v))
                    nNaN = nNaN + 1;
                else
                    nFinite = nFinite + 1;
                end
            end
        end

        function rows = expectationsToRows(items)
            % Build 5-column table data for the popup. NaN values render
            % as em-dash; the Status column carries the explicit "NaN"
            % label so the failure mode stays obvious at a glance.
            n = numel(items);
            rows = cell(n, 5);
            for i = 1:n
                e   = items{i};
                obs = char(string(JsonHelper.pick(e, 'observable', '')));
                val = JsonHelper.pick(e, 'value', NaN);
                err = JsonHelper.pick(e, 'std_err', 0);
                st  = char(string(JsonHelper.pick(e, 'status', 'ok')));
                if ~isnumeric(val); val = str2double(val); end
                if ~isnumeric(err); err = str2double(err); end

                if isempty(val) || all(isnan(val))
                    valStr = char(8212);
                    if strcmpi(st, 'ok'); st = 'NaN'; end
                else
                    valStr = sprintf('%.4f', double(val));
                end
                errStr = sprintf('%c %.4f', char(177), double(err));

                rows{i, 1} = sprintf('%d', i);
                rows{i, 2} = DialogBuilder.prettyObservable(obs);
                rows{i, 3} = valStr;
                rows{i, 4} = errStr;
                rows{i, 5} = upper(st);
            end
        end

        function s = prettyObservable(obs)
            % Compress 156-char Pauli strings down to something readable.
            %   all-Z, n>=30 -> "Z(x)156 (default fallback - no observable specified?)"
            %   all-Z, small -> "Z(x)N (all qubits)"
            %   all-I        -> "I(x)N (identity)"
            %   sparse-Z     -> "Z[3, 17, 42] (156 qubits)"
            %   long mix     -> "ZIZI...IZIZ (156 qubits)"
            %   short        -> raw string
            %
            % The "default fallback" tag fires on long all-Z strings
            % because the backend invents `"Z" * total_qubits` when the
            % cutting batch was submitted without an explicit observables
            % list (cutting/base.py:reconstruct_expectations). Calling
            % that out in the table makes the diagnostic actionable.
            if isempty(obs); s = '(none)'; return; end
            n = numel(obs);
            tensor = char(8855);
            uniq = unique(obs);
            if numel(uniq) == 1
                p = uniq;
                if p == 'I'
                    s = sprintf('I%c%d (identity)', tensor, n);
                elseif p == 'Z' && n >= 30
                    s = sprintf( ...
                        'Z%c%d (default fallback - no observable specified?)', ...
                        tensor, n);
                else
                    s = sprintf('%c%c%d (all qubits)', p, tensor, n);
                end
                return;
            end
            isPauli = obs ~= 'I';
            idx = find(isPauli);
            paulis = obs(idx);
            if numel(idx) <= 6 && all(paulis == paulis(1))
                idxStr = strjoin( ...
                    arrayfun(@(k) sprintf('%d', k-1), idx, ...
                        'UniformOutput', false), ', ');
                s = sprintf('%c[%s] (%d qubits)', paulis(1), idxStr, n);
                return;
            end
            if n <= 36
                s = obs;
            else
                s = sprintf('%s...%s (%d qubits)', ...
                    obs(1:14), obs(end-13:end), n);
            end
        end

        function copyReconstructionJson(data)
            try
                payload = jsonencode(data);
                clipboard('copy', payload);
            catch ME
                Logger.warn('DialogBuilder', ...
                    'copyReconstructionJson: %s', ME.message);
            end
        end

        function s = formatIntOrDash(v)
            % Render an integer-ish field as text, or em-dash when the
            % value is missing / null / not a number. Used by the
            % execution-context KPI cards so old payloads without the
            % new fields don't render as 'NaN'.
            if isempty(v); s = char(8212); return; end
            if iscell(v) && isempty(v); s = char(8212); return; end
            if ischar(v) || isstring(v)
                t = str2double(v);
                if isnan(t); s = char(string(v)); else; s = sprintf('%d', round(t)); end
                return;
            end
            if ~isnumeric(v); s = char(8212); return; end
            if all(isnan(v)); s = char(8212); return; end
            s = sprintf('%d', round(double(v)));
        end

        function s = formatBackendsValue(items)
            % Render the distinct-backends list as a comma-joined string
            % capped at three entries followed by '+N more' so a 6-way
            % cut still fits on one KPI card.
            list = {};
            if iscell(items)
                list = items;
            elseif isstring(items)
                list = cellstr(items);
            elseif ischar(items)
                list = {items};
            end
            list = list(~cellfun('isempty', list));
            if isempty(list); s = char(8212); return; end
            shown = min(3, numel(list));
            head = strjoin(cellfun(@char, list(1:shown), 'UniformOutput', false), ', ');
            extra = numel(list) - shown;
            if extra > 0
                s = sprintf('%s  +%d', head, extra);
            else
                s = head;
            end
        end

        function flag = expectationsHaveStatus(items, statusName)
            % Return true if any expectation entry has the given status
            % (case-insensitive). Used to drive the no-observables
            % diagnostic callout.
            flag = false;
            target = lower(char(statusName));
            for i = 1:numel(items)
                st = lower(char(string(JsonHelper.pick(items{i}, 'status', ''))));
                if strcmp(st, target); flag = true; return; end
            end
        end

        function buildCompatibleCircuitPicker(app, qubitCeiling, onPickFcn)
            % QMC oracle picker. Opens a modal listing the current
            %   project's circuits filtered to qubits <= qubitCeiling
            %   (the wider of statevector=30 / max IBM Runtime backend
            %   qubit count). Used by AnalysisViewModel when the active
            %   circuit can't run QMC in any mode — gives the operator
            %   a one-click way to swap to a compatible amplitude
            %   oracle without leaving the dialog flow.
            %
            % Arguments
            %   app           — QTAUWorkbenchApp host (theme + services)
            %   qubitCeiling  — int; max qubit count to allow
            %   onPickFcn     — @(circuit) ... fired with the picked
            %                   struct {id, name, qubits, gates, depth}
            %                   when "Use Selected" is clicked
            if nargin < 2 || isempty(qubitCeiling); qubitCeiling = 30; end
            if nargin < 3 || isempty(onPickFcn);    onPickFcn = @(~) []; end

            figPos = app.UIFigure.Position;
            dlgW = 720;
            dlgH = 520;
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor    = Theme.COLOR_BG;
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;
            titleColor = Theme.COLOR_HEADING;
            mutedColor = Theme.COLOR_MUTED;
            labelColor = Theme.COLOR_LABEL;

            pick = uifigure( ...
                'Name', 'Choose Compatible Circuit', ...
                'Position', [dlgX dlgY dlgW dlgH], ...
                'WindowStyle', 'modal', ...
                'Resize', 'on', ...
                'Color', bgColor);
            Theme.applyFigureMode(pick, Theme.activeName());

            outer = uigridlayout(pick, [3 3]);
            outer.RowHeight     = {16, '1x', 16};
            outer.ColumnWidth   = {16, '1x', 16};
            outer.Padding       = [0 0 0 0];
            outer.RowSpacing    = 0;
            outer.ColumnSpacing = 0;
            outer.BackgroundColor = bgColor;

            card = uipanel(outer, 'Title', '', 'BorderType', 'line', ...
                'BackgroundColor', cardBg, ...
                'HighlightColor', cardBorder, ...
                'BorderColor', cardBorder);
            card.Layout.Row = 2; card.Layout.Column = 2;

            cg = uigridlayout(card, [4 1]);
            cg.RowHeight   = {32, 47, '1x', 44};
            cg.ColumnWidth = {'1x'};
            cg.Padding     = [16 12 16 12];
            cg.RowSpacing  = 8;
            cg.BackgroundColor = cardBg;

            titleLbl = uilabel(cg, ...
                'Text', sprintf('Choose a circuit compatible with QMC  ·  ≤ %dq', ...
                    round(qubitCeiling)), ...
                'FontSize', 16, 'FontWeight', 'bold', 'FontColor', titleColor);
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            subLbl = uilabel(cg, ...
                'Text', sprintf(['Pick a circuit that fits the widest available execution mode. ' ...
                                 'Bundled QMC oracles live under samples/aqs-qmc/ ' ...
                                 '(e.g. aqs_qmc_var_7q_*.qasm).']), ...
                'FontSize', 11, 'FontColor', mutedColor, 'WordWrap', 'on');
            subLbl.Layout.Row = 2; subLbl.Layout.Column = 1;

            tbl = uitable(cg, ...
                'ColumnName',  {'Name', 'Qubits', 'Gates', 'Depth'}, ...
                'ColumnWidth', {'4x', '1x', '1x', '1x'}, ...
                'RowName',     {}, ...
                'Data',        cell(0, 4), ...
                'SelectionType', 'row', ...
                'Multiselect',   'off');
            tbl.Layout.Row = 3; tbl.Layout.Column = 1;
            app.styleTable(tbl);

            footer = uigridlayout(cg, [1 4]);
            footer.Layout.Row = 4; footer.Layout.Column = 1;
            footer.ColumnWidth = {'1x', 16, 100, 160};
            footer.RowHeight = {36};
            footer.Padding = [0 4 0 4]; footer.ColumnSpacing = 8;
            footer.BackgroundColor = cardBg;

            statusLbl = uilabel(footer, ...
                'Text', 'Loading project circuits…', ...
                'FontSize', 11, 'FontColor', mutedColor, ...
                'VerticalAlignment', 'center');
            statusLbl.Layout.Row = 1; statusLbl.Layout.Column = 1;

            cancelBtn = uibutton(footer, ...
                'Text', [char(10005) ' Cancel'], ...
                'ButtonPushedFcn', @(~,~) delete(pick));
            cancelBtn.Layout.Row = 1; cancelBtn.Layout.Column = 3;
            app.styleBtn(cancelBtn, 'ghost');

            useBtn = uibutton(footer, ...
                'Text', [char(10003) ' Use Selected'], ...
                'Enable', 'off');
            useBtn.Layout.Row = 1; useBtn.Layout.Column = 4;
            app.styleBtn(useBtn, 'primary');

            %  Stash the row→circuit mapping on the table's UserData
            %  so the Use button reads the picked struct via the
            %  current row Selection. Cleaner than maintaining a
            %  parallel cell array in scope.
            tbl.UserData = struct('rows', {{}});

            tbl.SelectionChangedFcn = @(src,~) localOnRowSelected(src, useBtn);
            useBtn.ButtonPushedFcn = @(~,~) localOnUseClicked(tbl, pick, onPickFcn);

            %  Async fetch — fill table on completion. The async path
            %  matches the pattern used elsewhere (no UI blocking).
            try
                token = app.State.authToken;
                circuitSvc = app.CircuitSvc;
                AsyncRunner.run( ...
                    @() circuitSvc.listCircuits(token), ...
                    @(data) localOnCircuitsLoaded(tbl, statusLbl, useBtn, ...
                        data, qubitCeiling, labelColor, mutedColor), ...
                    @(ME)   localOnCircuitsError(statusLbl, ME, labelColor));
            catch ME
                localOnCircuitsError(statusLbl, ME, labelColor);
            end

            Logger.info('DialogBuilder', ...
                'Compatible Circuit Picker shown (ceiling = %dq)', round(qubitCeiling));
        end

        % ----------------------------------------------------------------
        % Per-screen help dialog
        % ----------------------------------------------------------------
        function buildScreenHelpDialog(app, key)
            % buildScreenHelpDialog  Open a non-modal help dialog for the
            %   currently-visible screen. Content (purpose / what it does
            %   / measurements / formulas / notes) comes from
            %   HelpContent.bodyFor(key); rendering uses uihtml so
            %   bullet lists, formula blocks, and headings show with
            %   proper formatting.
            try
                if nargin < 2 || isempty(key)
                    try; key = char(app.LastSectionKey); catch; key = ''; end
                end
                key = char(key);
                try
                    displayName = NavigationManager.displayLabelFor(key);
                catch
                    displayName = key;
                end
                if isempty(displayName); displayName = key; end

                body = HelpContent.bodyFor(key);

                figW = 720; figH = 620;
                try
                    mainPos = app.UIFigure.Position;
                    x = max(0, mainPos(1) + (mainPos(3) - figW) / 2);
                    y = max(0, mainPos(2) + (mainPos(4) - figH) / 2);
                catch
                    x = 200; y = 200;
                end

                dlg = uifigure( ...
                    'Name', sprintf('Help — %s', char(displayName)), ...
                    'Position', [x y figW figH], ...
                    'Resize', 'on');
                try; dlg.Color = Theme.COLOR_CARD; catch; end

                g = uigridlayout(dlg, [3 1]);
                g.RowHeight   = {'1x', 1, 56};
                g.Padding     = [0 0 0 0];
                g.RowSpacing  = 0;
                try; g.BackgroundColor = Theme.COLOR_CARD; catch; end

                html = uihtml(g);
                html.Layout.Row = 1; html.Layout.Column = 1;
                html.HTMLSource = HelpContent.renderHtml(displayName, body);

                % Hairline divider above the footer so the Close button
                % feels like a proper footer instead of floating below
                % the body.
                divider = uipanel(g, 'BorderType', 'none');
                divider.Layout.Row = 2; divider.Layout.Column = 1;
                try; divider.BackgroundColor = Theme.COLOR_DIVIDER; catch; end

                btnRow = uigridlayout(g, [1 2]);
                btnRow.Layout.Row = 3; btnRow.Layout.Column = 1;
                btnRow.ColumnWidth = {'1x', 120};
                btnRow.RowHeight   = {'1x'};
                btnRow.Padding     = [20 10 20 12];
                try; btnRow.BackgroundColor = Theme.COLOR_CARD; catch; end

                closeBtn = uibutton(btnRow, ...
                    'Text', 'Close', ...
                    'FontSize', 13, 'FontWeight', 'bold', ...
                    'ButtonPushedFcn', @(~,~) delete(dlg));
                closeBtn.Layout.Row = 1; closeBtn.Layout.Column = 2;
                try; StyleHelper.styleBtn(closeBtn, 'primary'); catch; end

                try; figure(dlg); catch; end
            catch ME
                try; Logger.warn('DialogBuilder', ...
                    'buildScreenHelpDialog(%s): %s', char(key), ME.message); catch; end
            end
        end

        % ----------------------------------------------------------------
        % App-level help dialog ("About this workspace")
        % ----------------------------------------------------------------
        function buildAppHelpDialog(app)
            % buildAppHelpDialog  Open the application-wide help dialog.
            %   Content comes from HelpContent.appBody() + appLabels()
            %   and is rendered with the same uihtml stylesheet as the
            %   per-screen dialog so both surfaces feel like one
            %   coherent documentation system. End-user-oriented — no
            %   code, no project structure, no internal endpoint names.
            try
                body   = HelpContent.appBody();
                labels = HelpContent.appLabels();
                displayName = 'QTAU Connector Workspace';

                figW = 760; figH = 660;
                try
                    mainPos = app.UIFigure.Position;
                    x = max(0, mainPos(1) + (mainPos(3) - figW) / 2);
                    y = max(0, mainPos(2) + (mainPos(4) - figH) / 2);
                catch
                    x = 200; y = 200;
                end

                dlg = uifigure( ...
                    'Name', sprintf('About — %s', displayName), ...
                    'Position', [x y figW figH], ...
                    'Resize', 'on');
                try; dlg.Color = Theme.COLOR_CARD; catch; end

                g = uigridlayout(dlg, [3 1]);
                g.RowHeight  = {'1x', 1, 56};
                g.Padding    = [0 0 0 0];
                g.RowSpacing = 0;
                try; g.BackgroundColor = Theme.COLOR_CARD; catch; end

                html = uihtml(g);
                html.Layout.Row = 1; html.Layout.Column = 1;
                html.HTMLSource = HelpContent.renderHtml(displayName, body, labels);

                divider = uipanel(g, 'BorderType', 'none');
                divider.Layout.Row = 2; divider.Layout.Column = 1;
                try; divider.BackgroundColor = Theme.COLOR_DIVIDER; catch; end

                btnRow = uigridlayout(g, [1 2]);
                btnRow.Layout.Row = 3; btnRow.Layout.Column = 1;
                btnRow.ColumnWidth = {'1x', 120};
                btnRow.RowHeight   = {'1x'};
                btnRow.Padding     = [20 10 20 12];
                try; btnRow.BackgroundColor = Theme.COLOR_CARD; catch; end

                closeBtn = uibutton(btnRow, ...
                    'Text', 'Close', ...
                    'FontSize', 13, 'FontWeight', 'bold', ...
                    'ButtonPushedFcn', @(~,~) delete(dlg));
                closeBtn.Layout.Row = 1; closeBtn.Layout.Column = 2;
                try; StyleHelper.styleBtn(closeBtn, 'primary'); catch; end

                try; figure(dlg); catch; end
            catch ME
                try; Logger.warn('DialogBuilder', ...
                    'buildAppHelpDialog: %s', ME.message); catch; end
            end
        end
    end
end

% ── Local helpers for buildCompatibleCircuitPicker ─────────────────────
function localOnCircuitsLoaded(tbl, statusLbl, useBtn, data, ceiling, labelColor, mutedColor) %#ok<INUSD>
    if ~isvalid(tbl); return; end
    items = JsonHelper.extractListSafe(data, 'circuits');
    n = numel(items);
    rows  = {};
    metas = {};
    for i = 1:n
        if iscell(items); it = items{i}; else; it = items(i); end
        nq = JsonHelper.toDouble(JsonHelper.pick(it, ...
            {'num_qubits','qubits','n_qubits'}));
        if isnan(nq); nq = 0; end
        if nq <= 0 || nq > ceiling; continue; end
        nm = char(JsonHelper.pick(it, {'name','circuit_name'}, ''));
        cid = char(JsonHelper.pick(it, {'circuit_id','id'}, ''));
        ng = JsonHelper.toDouble(JsonHelper.pick(it, ...
            {'gate_count','num_gates','total_gates'}));
        if isnan(ng); ng = 0; end
        nd = JsonHelper.toDouble(JsonHelper.pick(it, {'depth'}));
        if isnan(nd); nd = 0; end
        rows(end+1, :) = {nm, int32(nq), int32(ng), int32(nd)}; %#ok<AGROW>
        metas{end+1}   = struct('id', cid, 'name', nm, ...
            'qubits', nq, 'gates', ng, 'depth', nd); %#ok<AGROW>
    end
    if isempty(rows)
        if isvalid(statusLbl)
            statusLbl.Text = sprintf(['No project circuits ≤ %dq. Upload a smaller ' ...
                'amplitude-oracle (samples/aqs-qmc/aqs_qmc_var_7q_*.qasm).'], ...
                round(ceiling));
            statusLbl.FontColor = [0.95 0.78 0.40];   % amber hint
        end
        return;
    end
    %  Sort qubits desc — the largest fitting circuit is usually the
    %  most interesting QAE oracle (closer to hardware ceiling).
    qcol = cell2mat(rows(:, 2));
    [~, ord] = sort(qcol, 'descend');
    rows  = rows(ord, :);
    metas = metas(ord);
    tbl.Data = rows;
    tbl.UserData = struct('rows', {metas});
    if isvalid(statusLbl)
        statusLbl.Text = sprintf('%d circuit%s available', ...
            size(rows, 1), repmat('s', 1, size(rows,1) ~= 1));
    end
    if isvalid(useBtn); useBtn.Enable = 'off'; end   % until row picked
end

function localOnCircuitsError(statusLbl, ME, labelColor) %#ok<INUSD>
    if ~isvalid(statusLbl); return; end
    statusLbl.Text = sprintf('Failed to load circuits: %s', ME.message);
    statusLbl.FontColor = [0.95 0.40 0.40];
end

function localOnRowSelected(tbl, useBtn)
    sel = tbl.Selection;
    if ~isempty(sel) && isvalid(useBtn)
        useBtn.Enable = 'on';
    end
end

function localOnUseClicked(tbl, pick, onPickFcn)
    sel = tbl.Selection;
    if isempty(sel); return; end
    rowIdx = sel(1);
    metas = {};
    try; metas = tbl.UserData.rows; catch; end
    if rowIdx < 1 || rowIdx > numel(metas); return; end
    chosen = metas{rowIdx};
    delete(pick);
    try
        onPickFcn(chosen);
    catch ME
        Logger.warn('DialogBuilder', ...
            'Compatible-circuit pick callback failed: %s', ME.message);
    end
end
