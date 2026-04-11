classdef BenchmarkViewModel < handle
    % BenchmarkViewModel  Callback handlers for the Benchmark screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = BenchmarkViewModel(app)
            obj.App = app;
        end

        function onRunBenchmark(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Benchmark', 'Icon', 'warning'); return;
            end
            shots    = round(app.BenchmarkShotsField.Value);
            opt      = round(app.BenchmarkOptField.Value);
            mitig    = char(app.BenchmarkMitigationDropdown.Value);
            strategy = char(app.BenchmarkStrategyDropdown.Value);

            app.State.benchmarkShots      = shots;
            app.State.benchmarkOptLevel   = opt;
            app.State.benchmarkMitigation = string(mitig);
            app.State.benchmarkStrategy   = string(strategy);

            app.logEvent('CONFIG', sprintf('Benchmark config updated — shots: %d  opt: %d  mitigation: %s  strategy: %s', ...
                shots, opt, mitig, strategy));

            hasBackend = strlength(app.State.selectedBackend) > 0;
            if app.State.hasProject() && app.State.hasCircuit() && hasBackend
                app.logEvent('API', sprintf('POST /api/projects/%s/benchmark-config — circuit: %s  backend: %s', ...
                    app.State.currentProjectId, app.State.selectedCircuitId, app.State.selectedBackend));
                app.showLoading(Labels.get('loading_benchmark', 'Running benchmark...'));
                try
                    app.ProjectSvc.saveBenchmarkConfig(app.State.currentProjectId, ...
                        app.State.selectedCircuitId, app.State.selectedBackend, ...
                        shots, opt, mitig, strategy, app.State.authToken);
                    app.logEvent('API', 'Benchmark config saved to server');
                    app.logEvent('API', sprintf('POST /api/projects/%s/compare-strategies — circuit: %s  backend: %s', ...
                        app.State.currentProjectId, app.State.selectedCircuitId, app.State.selectedBackend));
                    compData = app.ProjectSvc.compareStrategies(app.State.currentProjectId, ...
                        app.State.selectedCircuitId, app.State.selectedBackend, app.State.authToken);
                    rows = JsonHelper.benchmarkStrategyToRows(compData);
                    if ~isempty(rows) && ~isempty(app.BenchmarkStrategyTable)
                        app.BenchmarkStrategyTable.Data = rows;
                    end
                    plan = char(JsonHelper.pick(compData, {'execution_plan','plan','summary'}));
                    if ~isempty(plan)
                        app.setStatus(app.BenchmarkStatusArea, {plan});
                    else
                        app.setStatus(app.BenchmarkStatusArea, { ...
                            sprintf('Shots: %d  Opt level: %d', shots, opt), ...
                            sprintf('Mitigation: %s', mitig), ...
                            sprintf('Strategy: %s', strategy), ...
                            'Benchmark configuration saved.'});
                    end
                    app.logEvent('API', 'Benchmark config saved and strategies compared successfully');
                    app.State.logActivity('Run benchmark', 'Success');
                    app.hideLoading();
                catch ME
                    app.hideLoading();
                    app.logEvent('ERROR', sprintf('Benchmark API FAILED (project: %s): %s', ...
                        app.State.currentProjectId, ME.message));
                    app.setStatus(app.BenchmarkStatusArea, { ...
                        'Benchmark config saved to session (API call failed).', ME.message});
                    app.showError('Run Benchmark', ME);
                end
            else
                missing = {};
                if ~app.State.hasProject(); missing{end+1} = 'project'; end
                if ~app.State.hasCircuit(); missing{end+1} = 'circuit'; end
                if ~hasBackend;             missing{end+1} = 'backend'; end
                app.logEvent('CONFIG', sprintf('Benchmark config saved to session only — missing: %s', strjoin(missing, ', ')));
                app.setStatus(app.BenchmarkStatusArea, { ...
                    sprintf('Shots: %d  Opt level: %d', shots, opt), ...
                    sprintf('Mitigation: %s', mitig), ...
                    sprintf('Strategy: %s', strategy), ...
                    sprintf('Config saved to session (select %s first).', strjoin(missing, ', '))});
            end
        end
    end
end
