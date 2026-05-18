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
        % Width of the currently-selected circuit. Populated whenever a
        % circuit doc is loaded (Analyze, list, getCircuit). Used by the
        % QMC pre-flight check to reject runtime submissions that would
        % overflow the chosen IBM backend's coupling map.
        selectedCircuitQubits double = 0

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
        % Pinned job id set by an explicit operator gesture on the Jobs
        % screen (right-click → View Results, or double-click a
        % terminal row). ResultsViewModel.onRefreshResults consumes
        % and clears this on render, bypassing its default
        % "first-completed in /api/jobs" autodiscovery so the operator
        % sees the exact job they picked even when the queue has
        % several completed siblings.
        pinnedJobId   string = ""

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
        % Phase 3.6: persisted user preference for the QEM ladder
        % level. Cutting toolbar dropdown initialises from this; the
        % Settings → Defaults dialog edits it. -1 = Custom, 0 = Raw,
        % 1 = Standard (default), 2 = Aggressive, 3 = TEM.
        preferredMitigationLevel double = 1

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

        % ── Session-level response caches ────────────────────────────────────
        % Several screens (Backends, Circuit Cutting, Benchmark Dashboard,
        % Prediction, Mitigation Compare, Run Planner, Resource Estimator)
        % all hit /api/circuits, /api/backends, and /api/mitigation/levels
        % on entry — those rarely change inside a session, so caching them
        % here saves 0.3–1.5 s per nav. Caches are checked by callers
        % before they issue a fetch; helper methods below provide a
        % uniform fresh/set/invalidate interface.
        %
        % CircuitListCache       — raw /api/circuits response envelope.
        %                          Wrapped by JsonHelper.extractListSafe at
        %                          read-time by the consuming VM.
        % BackendPoolCache       — normalized {name,num_qubits,simulator}
        %                          struct array used by Circuit Cutting's
        %                          per-row pickers. DIFFERENT shape than
        %                          BackendListCache — kept separate to
        %                          preserve the existing CircuitCutting
        %                          call site. Uses datetime('now') stamps.
        % BackendListCache       — raw /api/backends response envelope.
        % MitigationLevelsCache  — raw /api/mitigation/levels response.
        CircuitListCache         = []
        CircuitListCacheAt       = []
        BackendPoolCache         = []
        BackendPoolCacheAt       = []
        BackendListCache         = []
        BackendListCacheAt       = []
        MitigationLevelsCache    = []
        MitigationLevelsCacheAt  = []
    end

    methods
        function obj = AppState()
            % Load base URL from app.properties; fall back to a
            % localhost default so a shipped toolbox with an empty
            % base_url= line doesn't hard-code any specific server.
            % End-users override via Settings → Connection or via
            % the URL field on the Login dialog.
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

        % ── Session cache helpers ────────────────────────────────────────────
        % Uniform fresh/set/invalidate for the shared lookup caches above.
        % Uses datetime('now') + seconds(...) to match the legacy
        % BackendPoolCache convention in CircuitCuttingViewModel.

        function tf = isCircuitsListCacheFresh(obj, ttlSec)
            tf = ~isempty(obj.CircuitListCache) ...
                && ~isempty(obj.CircuitListCacheAt) ...
                && seconds(datetime('now') - obj.CircuitListCacheAt) < ttlSec;
        end
        function setCircuitsListCache(obj, val)
            obj.CircuitListCache   = val;
            obj.CircuitListCacheAt = datetime('now');
        end
        function invalidateCircuitsListCache(obj)
            obj.CircuitListCache   = [];
            obj.CircuitListCacheAt = [];
        end

        function tf = isBackendsListCacheFresh(obj, ttlSec)
            tf = ~isempty(obj.BackendListCache) ...
                && ~isempty(obj.BackendListCacheAt) ...
                && seconds(datetime('now') - obj.BackendListCacheAt) < ttlSec;
        end
        function setBackendsListCache(obj, val)
            obj.BackendListCache   = val;
            obj.BackendListCacheAt = datetime('now');
        end
        function invalidateBackendsListCache(obj)
            obj.BackendListCache   = [];
            obj.BackendListCacheAt = [];
        end

        function tf = isMitigationLevelsCacheFresh(obj, ttlSec)
            tf = ~isempty(obj.MitigationLevelsCache) ...
                && ~isempty(obj.MitigationLevelsCacheAt) ...
                && seconds(datetime('now') - obj.MitigationLevelsCacheAt) < ttlSec;
        end
        function setMitigationLevelsCache(obj, val)
            obj.MitigationLevelsCache   = val;
            obj.MitigationLevelsCacheAt = datetime('now');
        end
        function invalidateMitigationLevelsCache(obj)
            obj.MitigationLevelsCache   = [];
            obj.MitigationLevelsCacheAt = [];
        end

        % Resets all pipeline IDs without touching auth so the user can start a
        % new run without logging in again.
        function resetPipeline(obj)
            obj.selectedFile          = "";
            obj.selectedCircuitId     = "";
            obj.selectedCircuitName   = "";
            obj.selectedCircuitQubits = 0;
            obj.selectedBackend       = "";
            obj.backupBackend       = "";
            obj.selectedJobId       = "";
            obj.pinnedJobId         = "";
            obj.predictionId        = "";
            obj.reportId            = "";
        end
    end
end
