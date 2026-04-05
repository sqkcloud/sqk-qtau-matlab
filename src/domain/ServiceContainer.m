classdef ServiceContainer < handle
    % ServiceContainer  Creates and holds all domain services.
    %
    %   Centralizes service initialization so QTAUWorkbenchApp does not act
    %   as both a UI controller and a service factory.
    %
    %   Usage:
    %       container = ServiceContainer(baseUrl);
    %       svc = container.CircuitSvc;
    %
    %   Call syncClient(newUrl) to update the base URL and propagate it
    %   to the underlying FastAPIClient.

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
            Logger.info('ServiceContainer', 'All services initialized');
        end

        function syncClient(obj, newUrl)
            % Update the base URL on the existing FastAPIClient.
            obj.Client.BaseUrl = newUrl;
        end
    end
end
