classdef PredictionViewModel < handle
    % PredictionViewModel  Callback handlers for the Prediction screen.
    properties (Access = private)
        App  % QTAUWorkbenchApp
    end
    methods
        function obj = PredictionViewModel(app)
            obj.App = app;
        end

        function onRunPrediction(obj)
            app = obj.App;
            if ~app.State.isAuthenticated()
                uialert(app.UIFigure, Labels.get('error_not_authenticated'), 'Prediction', 'Icon', 'warning'); return;
            end
            if ~app.State.hasCircuit()
                uialert(app.UIFigure, Labels.get('error_no_circuit'), 'Prediction', 'Icon', 'warning');
                return;
            end
            app.logEvent('API', sprintf('POST /api/predict — circuit: %s  backend: %s  shots: %d  opt: %d', ...
                app.State.selectedCircuitId, app.State.selectedBackend, ...
                app.State.benchmarkShots, app.State.benchmarkOptLevel));
            try
                data = app.PredictionSvc.predict( ...
                    app.State.selectedCircuitId, ...
                    app.State.selectedBackend, ...
                    app.State.benchmarkShots, ...
                    app.State.benchmarkOptLevel, ...
                    app.State.authToken);
                app.State.predictionId = string(JsonHelper.pick(data, {'prediction_id','id'}));
                obj.applyPredictionData(data);
                app.logEvent('API', sprintf('Prediction complete — id: %s  circuit: %s  backend: %s', ...
                    app.State.predictionId, app.State.selectedCircuitId, app.State.selectedBackend));
            catch ME
                app.logEvent('ERROR', sprintf('Prediction FAILED (circuit: %s  backend: %s): %s', ...
                    app.State.selectedCircuitId, app.State.selectedBackend, ME.message));
                app.showError('Run Prediction', ME);
            end
        end
    end

    methods (Access = private)
        function applyPredictionData(obj, data)
            app = obj.App;
            try
                fid  = char(JsonHelper.pick(data, {'predicted_fidelity','fidelity'}));
                prob = char(JsonHelper.pick(data, {'success_probability','prob_success'}));
                qt   = char(JsonHelper.pick(data, {'queue_time','expected_queue_time','queue_minutes'}));
                rt   = char(JsonHelper.pick(data, {'runtime_seconds','runtime','estimated_runtime'}));
                rows = { ...
                    'Predicted fidelity',         fid; ...
                    'Expected success probability', prob; ...
                    'Expected queue time',         qt; ...
                    'Estimated runtime',           rt; ...
                    'Notification mode',           'Email + in-app'};
                app.PredictionTable.Data = rows;

                dist  = char(JsonHelper.pick(data, {'distribution_summary','distribution'}));
                ebudg = char(JsonHelper.pick(data, {'error_budget','error_breakdown'}));
                lines = {'Prediction results loaded.'};
                if ~isempty(dist);  lines{end+1} = dist;  end
                if ~isempty(ebudg); lines{end+1} = ebudg; end
                app.setStatus(app.PredictionTextArea, lines);
            catch
                app.setStatus(app.PredictionTextArea, {JsonHelper.pretty(data)});
            end
        end
    end
end
