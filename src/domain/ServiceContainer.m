classdef ServiceContainer < handle
    % ServiceContainer  Creates and holds all domain services.
    %
    %   Centralizes service initialization so QTAUWorkbenchApp does not act
    %   as both a UI controller and a service factory.
    %
    %   Usage:
    %       container = ServiceContainer(baseUrl);
    %       svc = container.CircuitSvc;

    properties
        Client          % FastAPIClient
        AuthSvc         % AuthService
        CircuitSvc      % CircuitService
        BackendSvc      % BackendService
        JobSvc          % JobService
        ProjectSvc      % ProjectService
        PredictionSvc   % PredictionService
        ReportSvc       % ReportService
        SettingsSvc     % SettingsService
        QecEngine       % QecEngineService (local computation, no HTTP)
        BenchmarkSvc    % BenchmarkService
        QmcSvc          % QmcService (Quantum Amplitude Estimation / QMC)
        CuttingSvc      % CuttingService (circuit cutting + reconstruction)
        MitigationSvc   % MitigationService (QEM ladder, cost preview)
        WorkspaceSvc    % MatlabWorkspaceService (local, no HTTP)
        MatlabQuantumSvc % MatlabQuantumService (optional support package)
        SimulationSvc   % SimulationService (MATLAB/QTAU local provider)
        WorkspaceExportSvc % WorkspaceExportService
        HardwareRecommendationSvc % HardwareRecommendationService
    end

    methods
        function obj = ServiceContainer(baseUrl)
            Logger.info('ServiceContainer', 'Initializing services — baseUrl: %s', char(baseUrl));
            obj.Client        = FastAPIClient(baseUrl);
            obj.AuthSvc       = AuthService(obj.Client);
            obj.CircuitSvc    = CircuitService(obj.Client);
            obj.BackendSvc    = BackendService(obj.Client);
            obj.JobSvc        = JobService(obj.Client);
            obj.ProjectSvc    = ProjectService(obj.Client);
            obj.PredictionSvc = PredictionService(obj.Client);
            obj.ReportSvc     = ReportService(obj.Client);
            obj.SettingsSvc   = SettingsService(obj.Client);
            obj.QecEngine     = QecEngineService();
            obj.BenchmarkSvc  = BenchmarkService(obj.Client);
            obj.QmcSvc        = QmcService(obj.Client);
            obj.CuttingSvc    = CuttingService(obj.Client);
            obj.MitigationSvc = MitigationService(obj.Client);
            obj.WorkspaceSvc   = MatlabWorkspaceService();
            obj.MatlabQuantumSvc = MatlabQuantumService();
            obj.SimulationSvc  = SimulationService(obj.MatlabQuantumSvc);
            obj.WorkspaceExportSvc = WorkspaceExportService();
            obj.HardwareRecommendationSvc = HardwareRecommendationService();
            Logger.info('ServiceContainer', 'All services initialized');
        end
    end
end
