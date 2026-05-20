%% Example 3 - Programmatic connection and browsing (backend required)
% Drive the QTAU FastAPI backend from MATLAB without launching the
% workbench UI. Useful for unit-testing a script against a CI server
% or scripting a bulk operation across many projects.
%
% Prerequisites:
%   * A reachable QTAU FastAPI server (set its base URL on the prompt
%     below, or edit resources/app.properties).
%   * Valid login credentials for that server.

projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(projectRoot, 'src', 'infrastructure', 'http'));
addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
addpath(fullfile(projectRoot, 'src', 'domain'));
addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
addpath(fullfile(projectRoot, 'src', 'domain', 'models'));

%% Section 1 - Configure the HTTP client
% AppConfig reads resources/app.properties. If base_url is empty
% (default for the shipped toolbox), we prompt for one here so the
% script remains self-contained.
AppConfig.reload();
baseUrl = strtrim(char(AppConfig.get('base_url', '')));
if isempty(baseUrl)
    baseUrl = input('QTAU server URL (e.g. http://localhost:5715): ', 's');
end
client = FastAPIClient(baseUrl);
fprintf('Connected to %s\n', baseUrl);

%% Section 2 - Authenticate
% Replace these with your actual credentials. Best practice: read them
% from environment variables or an interactive prompt, NOT a checked-in
% file. The toolbox's resources/seed.properties is git-ignored for
% exactly this reason.
username = input('Username: ', 's');
password = input('Password: ', 's');  % consider getpass-style input
token    = client.login(username, password);
fprintf('Logged in (token length = %d chars)\n', numel(char(token)));

%% Section 3 - List projects
projectSvc = ProjectService(client);
projects   = projectSvc.listProjects(token);
fprintf('\nFound %d projects:\n', numel(projects));
for k = 1:numel(projects)
    p = projects(k);
    name = char(JsonHelper.pick(p, {'name','title','project_name'}));
    pid  = char(JsonHelper.pick(p, {'id','project_id'}));
    fprintf('  [%d] %-40s  id=%s\n', k, name, pid);
end

%% Section 4 - List circuits in the first project
if isempty(projects)
    fprintf('\nNo projects to browse - create one in the workbench first.\n');
    return;
end
firstProject = projects(1);
projectId    = char(JsonHelper.pick(firstProject, {'id','project_id'}));

circuitSvc = CircuitService(client);
circuits   = circuitSvc.listCircuits(projectId, token);
fprintf('\nProject %s contains %d circuits:\n', projectId, numel(circuits));
for k = 1:min(10, numel(circuits))
    c = circuits(k);
    name  = char(JsonHelper.pick(c, {'name','circuit_name'}));
    qbits = JsonHelper.toDouble(JsonHelper.pick(c, {'num_qubits','qubits','n_qubits'}));
    fprintf('  - %-30s  %d qubits\n', name, qbits);
end
if numel(circuits) > 10
    fprintf('  ... and %d more\n', numel(circuits) - 10);
end

%% Where to go next
% * The full service catalog lives under src/domain/services/. Same
%   pattern as above: instantiate FooService(client) and call its
%   methods with the auth token.
% * For interactive use, just launch the workbench:
%
%       >> QTAUWorkbenchLauncher
%
%   Programmatic and GUI flows share the exact same service classes,
%   so anything you do in the UI is also reachable from your scripts.
