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
        % Fallback: http://localhost:5715
        baseUrl string = ""

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
        benchmarkMitigation string = "measurement_mitigation"
        benchmarkStrategy   string = "sabre"

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

        % ── Activity log ─────────────────────────────────────────────────────
        % Cell array of {timestamp, action, status} rows for Recent Activity.
        ActivityLog cell = {}

        % ── Cached notes ─────────────────────────────────────────────────────
        projectNotes string = ""

        % ── Benchmark dashboard state ────────────────────────────────────────
        benchmarkScorecardData struct = struct()
        volumetricData         struct = struct()
        systemMetrics          struct = struct()
        regressionData         struct = struct()
        calibrationData        struct = struct()
        circuitClassification  struct = struct()
    end

    methods
        function obj = AppState()
            % Load base URL from app.properties; fall back to localhost.
            obj.baseUrl = string(AppConfig.get('base_url', 'http://localhost:5715'));
            fprintf('[AppState] Base URL loaded from config: %s\n', char(obj.baseUrl));
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

        function logActivity(obj, action, status)
            % logActivity  Record a user-facing activity for Recent Activity display.
            %   obj.logActivity('Upload circuit', 'Success')
            ts = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            row = {ts, char(action), char(status)};
            obj.ActivityLog = [row; obj.ActivityLog];
            % Cap at 500 entries
            if size(obj.ActivityLog, 1) > 500
                obj.ActivityLog = obj.ActivityLog(1:500, :);
            end
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
