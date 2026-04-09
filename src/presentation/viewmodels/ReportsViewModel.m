classdef ReportsViewModel < handle
    % ReportsViewModel  Callback handlers for the Reports screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = ReportsViewModel(app)
            obj.App = app;
        end

        function onGenerateReport(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Reports', 'Icon', 'warning'); return;
            end
            reportTitle = char(app.ReportTitleField.Value);
            fmt         = char(app.ReportFormatDropdown.Value);
            sections    = char(app.ReportSectionsField.Value);
            if app.State.hasProject()
                app.logEvent('API', sprintf('POST /api/projects/%s/reports — title: %s  format: %s', ...
                    app.State.currentProjectId, reportTitle, fmt));
            else
                app.logEvent('API', sprintf('POST /api/reports/generate — title: %s  format: %s  job: %s', ...
                    reportTitle, fmt, app.State.selectedJobId));
            end
            app.showLoading(Labels.get('loading_report', 'Generating report...'));
            try
                if app.State.hasProject()
                    data = app.ProjectSvc.generateReport(app.State.currentProjectId, ...
                        reportTitle, fmt, sections, app.State.authToken);
                else
                    data = app.ReportSvc.generateReport(reportTitle, fmt, sections, ...
                        app.State.selectedJobId, app.State.authToken);
                end
                app.State.reportId = string(JsonHelper.pick(data, {'report_id','id'}));
                reportFile = char(JsonHelper.pick(data, {'filename','file','report_file'}));
                app.setStatus(app.ReportStatusArea, { ...
                    sprintf('Report generated: %s', app.State.reportId), ...
                    sprintf('File: %s', reportFile), ...
                    sprintf('Format: %s', fmt)});
                if ~isempty(reportFile)
                    cur = app.GeneratedReportList.Items;
                    app.GeneratedReportList.Items = [{reportFile}, cur];
                end
                app.logEvent('API', sprintf('Report generated — id: %s  file: %s  format: %s', ...
                    app.State.reportId, reportFile, fmt));
                app.State.logActivity(sprintf('Generate report — %s', fmt), 'Success');
                app.hideLoading();
            catch ME
                app.hideLoading();
                app.logEvent('ERROR', sprintf('Report generation FAILED (format: %s): %s', fmt, ME.message));
                app.setStatus(app.ReportStatusArea, {'Report generation failed.', ME.message});
                app.showError('Generate Report', ME);
            end
        end

        function onOpenReport(obj)
            app = obj.App;
            try
                sel = app.GeneratedReportList.Value;
                if isempty(sel)
                    app.logEvent('UI', 'Open report triggered but no report selected');
                    app.setStatus(app.ReportStatusArea, {'No report selected in list.'});
                    return;
                end
                app.logEvent('UI', sprintf('Opening report: %s', sel));
                if app.State.isAuthenticated() && strlength(app.State.reportId) > 0
                    app.logEvent('API', sprintf('GET /api/reports/%s/download', app.State.reportId));
                    app.showLoading(Labels.get('loading_downloading', 'Downloading report...'));
                    try
                        data = app.ReportSvc.downloadReport(app.State.reportId, app.State.authToken);
                        url  = char(JsonHelper.pick(data, {'download_url','url','file_path'}));
                        if ~isempty(url)
                            app.logEvent('UI', sprintf('Opening report URL in browser: %s', url));
                            web(url, '-browser');
                        else
                            app.logEvent('WARN', 'Report download response contained no URL');
                        end
                        app.hideLoading();
                    catch ME
                        app.hideLoading();
                        app.logEvent('WARN', sprintf('Could not fetch report download URL: %s', ME.message));
                    end
                end
                app.setStatus(app.ReportStatusArea, {sprintf('Opening: %s', sel)});
            catch ME
                app.logEvent('ERROR', sprintf('Open report FAILED: %s', ME.message));
                app.setStatus(app.ReportStatusArea, {'Open report failed.', ME.message});
            end
        end
    end
end
