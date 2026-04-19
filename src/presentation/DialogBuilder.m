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
            Logger.info('DialogBuilder', 'Login dialog shown');
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
            dlgW = min(1150, max(900, round(figPos(3) * 0.82)));
            dlgH = min(720,  max(560, round(figPos(4) * 0.82)));
            dlgX = figPos(1) + (figPos(3) - dlgW) / 2;
            dlgY = figPos(2) + (figPos(4) - dlgH) / 2;

            bgColor    = Theme.COLOR_BG;
            cardBg     = Theme.COLOR_CARD;
            cardBorder = Theme.COLOR_DIVIDER;
            titleColor = Theme.COLOR_HEADING;
            labelColor = Theme.COLOR_LABEL;

            app.QmcDialog = uifigure( ...
                'Name', 'Quantum Monte Carlo Simulation (Quantum Amplitude Estimation)', ...
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

            % Inside the card: header / body / footer.
            cg = uigridlayout(card, [3 1]);
            cg.RowHeight = {40, '1x', 52};
            cg.ColumnWidth = {'1x'};
            cg.Padding = [18 14 18 14];
            cg.RowSpacing = 10;
            cg.BackgroundColor = cardBg;

            % ── Header ─────────────────────────────────────────────────
            headerRow = uigridlayout(cg, [1 2]);
            headerRow.Layout.Row = 1; headerRow.Layout.Column = 1;
            headerRow.ColumnWidth = {'1x', 110};
            headerRow.Padding = [0 0 0 0]; headerRow.ColumnSpacing = 8;
            headerRow.BackgroundColor = cardBg;

            titleLbl = uilabel(headerRow, ...
                'Text', 'Quantum Monte Carlo Simulation (Quantum Amplitude Estimation)', ...
                'FontSize', 16, 'FontWeight', 'bold', 'FontColor', titleColor, ...
                'VerticalAlignment', 'center');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;

            closeTopBtn = uibutton(headerRow, ...
                'Text', [char(10005) ' Close'], ...
                'ButtonPushedFcn', @(~,~) delete(app.QmcDialog));
            closeTopBtn.Layout.Row = 1; closeTopBtn.Layout.Column = 2;
            app.styleBtn(closeTopBtn, 'ghost');

            % ── Body: controls+KPI (left)  |  plots (right) ────────────
            body = uigridlayout(cg, [1 2]);
            body.Layout.Row = 2; body.Layout.Column = 1;
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
                'Value',     'statevector');

            uilabel(form, 'Text', 'Backend (runtime)', 'FontColor', labelColor);
            app.QmcBackendField = uieditfield(form, 'text', 'Value', 'ibm_marrakesh');

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
                'Value',     'none');

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

            % Right: 3x2 grid of charts — full QMC / QAE story including
            % Zero-Noise Extrapolation.
            %   (1) Loss distribution with VaR95/VaR99 threshold lines
            %   (2) Cumulative Distribution Function (CDF) overlay
            %   (3) Convergence: QAE vs classical MC sample complexity
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
            title(app.QmcConvergenceAxes, 'Convergence: QAE 1/N vs classical MC 1/\surd{N}');
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

            % ── Footer: Run / Generate Report / Close ─────────────────
            footer = uigridlayout(cg, [1 4]);
            footer.Layout.Row = 3; footer.Layout.Column = 1;
            footer.ColumnWidth = {'1x', 200, 200, 120};
            footer.Padding = [0 0 0 0]; footer.ColumnSpacing = 10;
            footer.BackgroundColor = cardBg;

            uilabel(footer, 'Text', ...
                'Statevector runs locally. Switch to IBM Runtime for real-hardware shots.', ...
                'FontSize', 11, 'FontColor', Theme.COLOR_MUTED, 'WordWrap', 'on');

            app.QmcRunButton = uibutton(footer, ...
                'Text', [char(9883) ' Run QMC / QAE'], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onRunQaeAnalysis());
            app.QmcRunButton.Layout.Row = 1; app.QmcRunButton.Layout.Column = 2;
            app.styleBtn(app.QmcRunButton, 'primary');
            app.QmcRunButton.FontSize = 14;
            app.QmcRunButton.Tooltip = 'POST /api/circuits/{id}/qae/analyze';

            app.QmcReportButton = uibutton(footer, ...
                'Text', [char(9636) ' Generate Report'], ...
                'ButtonPushedFcn', @(~,~)app.AnalysisVm.onGenerateQaeReport());
            app.QmcReportButton.Layout.Row = 1; app.QmcReportButton.Layout.Column = 3;
            app.styleBtn(app.QmcReportButton, 'secondary');
            app.QmcReportButton.FontSize = 14;
            app.QmcReportButton.Tooltip = 'Generate PDF (also available from Reports screen)';

            closeBtn = uibutton(footer, ...
                'Text', [char(10005) ' Close'], ...
                'ButtonPushedFcn', @(~,~) delete(app.QmcDialog));
            closeBtn.Layout.Row = 1; closeBtn.Layout.Column = 4;
            app.styleBtn(closeBtn, 'ghost');

            % Rehydration (render of any cached result) is performed by
            % the caller in AnalysisViewModel.onOpenQaeDialog so the
            % private renderQmcResult method stays encapsulated.

            Logger.info('DialogBuilder', 'Quantum Monte Carlo / QAE dialog shown');
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
    end
end
