classdef AppState < handle
    % AppState  Mutable session-scoped application context.
    %
    %   Single shared instance held by QTAUWorkbenchApp.  No business logic lives here —
    %   only raw values that survive across tab navigation.  All service classes
    %   receive the token / IDs they need as method arguments rather than reading
    %   this object directly, keeping the service layer testable in isolation.
    %
    %   The API base URL is loaded from resources/app.properties at construction
    %   time via AppConfig so it is configurable without changing source code.

    properties
        % ── Network ──────────────────────────────────────────────────────────
        % Loaded from resources/app.properties key "base_url".
        % Fallback: http://34.42.87.190:5715
        baseUrl string = "http://34.42.87.190:5715"

        % ── Authentication ───────────────────────────────────────────────────
        authToken    string = ""
        tokenType    string = "Bearer"
        currentUser  string = ""
        userRole     string = ""
        lastHealth   string = "Unknown"

        % ── Project context ───────────────────────────────────────────────────
        defaultProjectId    string = ""
        currentProjectId    string = ""
        currentProjectName  string = ""

        % ── Circuit pipeline context ──────────────────────────────────────────
        selectedFile        string = ""
        selectedCircuitId   string = ""
        selectedCircuitName string = ""

        % ── Backend selection ─────────────────────────────────────────────────
        selectedBackend string = ""
        backupBackend   string = ""

        % ── Benchmark configuration ───────────────────────────────────────────
        benchmarkShots      double = 4096
        benchmarkOptLevel   double = 3
        benchmarkMitigation string = "Measurement mitigation"
        benchmarkStrategy   string = "Fidelity optimized"

        % ── Job context ───────────────────────────────────────────────────────
        selectedJobId string = ""

        % ── Prediction context ────────────────────────────────────────────────
        predictionId string = ""

        % ── Report context ────────────────────────────────────────────────────
        reportId string = ""

        % ── Metrics / chip context ────────────────────────────────────────────
        selectedChipId string = ""

        % ── Session defaults ──────────────────────────────────────────────────
        defaultShots        double = 4096
        defaultOptimization double = 3
        defaultTimeout      double = 120
        logLevel            string = "info"

        % ── Cached notes ─────────────────────────────────────────────────────
        projectNotes string = ""
    end

    methods
        function obj = AppState()
            % Load base URL from app.properties; fall back to built-in default.
            configUrl = AppConfig.get('base_url', '');
            if ~isempty(configUrl)
                obj.baseUrl = string(configUrl);
                fprintf('[AppState] Base URL loaded from config: %s\n', configUrl);
            else
                fprintf('[AppState] Using built-in default base URL: %s\n', char(obj.baseUrl));
            end
        end

        % Predicate helpers so callers avoid duplicating strlength checks.

        function tf = isAuthenticated(obj)
            tf = strlength(strtrim(obj.authToken)) > 0;
        end

        function tf = hasProject(obj)
            tf = strlength(strtrim(obj.currentProjectId)) > 0;
        end

        function tf = hasCircuit(obj)
            tf = strlength(strtrim(obj.selectedCircuitId)) > 0;
        end

        function tf = hasJob(obj)
            tf = strlength(strtrim(obj.selectedJobId)) > 0;
        end

        % Returns the formatted Authorization header value.
        function hdr = bearerHeader(obj)
            hdr = ['Bearer ' char(obj.authToken)];
        end

        % Resets all pipeline IDs without touching auth so the user can start a
        % new run without logging in again.
        function resetPipeline(obj)
            obj.selectedFile        = "";
            obj.selectedCircuitId   = "";
            obj.selectedCircuitName = "";
            obj.selectedBackend     = "";
            obj.backupBackend       = "";
            obj.selectedJobId       = "";
            obj.predictionId        = "";
            obj.reportId            = "";
        end
    end
end
