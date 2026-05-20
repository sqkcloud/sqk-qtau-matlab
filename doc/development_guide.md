# QTAU Connector Workbench — Development Guide

How to update existing screens and add new ones. Pair this with [`architecture.md`](./architecture.md) for the high-level picture, and [`fastapi_contract.md`](./fastapi_contract.md) for endpoint shapes.

---

## 0. Before you start

```matlab
% Open the project so paths resolve
matlab.project.openProject('sqk-qtau-matlab.prj')

% Launch the app
run('QTAUWorkbenchLauncher.m')

% Run all tests (20 suites)
runtests('tests')

% Hot-reload config / labels without restarting
AppConfig.reload(); Labels.reload();
```

There is no build step, lint, or CI. MATLAB interprets `.m` directly, so every edit is live on next launch.

---

## 1. Changing UI text (labels, titles, tooltips)

1. Add or edit the key in `resources/labels.properties`.
2. Reference it from code:

   ```matlab
   btn.Text = Labels.get('jobs_btn_refresh', 'Refresh');     % fallback
   ```

3. **Never** hard-code user-facing text. Tests grep for string literals.

Reload in a running app: `Labels.reload();` — no restart.

---

## 2. Changing the HTTP base URL or timeout

Edit `resources/app.properties`:

```ini
base_url = http://34.42.87.190:5715
http_timeout_seconds = 60
screen_cache_ttl = 30
```

Then `AppConfig.reload();`. The Welcome screen Server URL field writes through to `AppState.baseUrl` → `FastAPIClient.setBaseUrl` at login time, so most users change it from the UI and never edit the properties file.

---

## 3. Adding a feature to an *existing* screen

### Step 1 — find the three layers

| You change | When |
|---|---|
| `src/presentation/screens/FooScreen.m` | new button, new field, new table column (UI layout only) |
| `src/presentation/viewmodels/FooViewModel.m` | new callback, new data transform, new dialog flow |
| `src/domain/services/BarService.m` | new endpoint, new HTTP payload, new response shape |

### Step 2 — wire the data path

1. **Service** — add a method on the relevant `*Service` class. Keep it UI-free; take plain args, return a parsed struct:

   ```matlab
   function cfg = getBenchmarkConfig(obj, projectId, token)
       url = sprintf('%s/api/projects/%s/benchmark-config', obj.Client.BaseUrl, projectId);
       cfg = obj.Client.get(url, token);
   end
   ```

2. **ViewModel** — call the service, feed results into UI state. Use `JsonHelper.pick` for resilient field mapping:

   ```matlab
   function onLoadConfig(obj)
       app = obj.App;
       cfg = app.BenchmarkSvc.getBenchmarkConfig(app.State.currentProjectId, app.State.authToken);
       app.BmStrategyLabel.Text = char(JsonHelper.pick(cfg, {'strategy','mitigation_strategy'}, 'none'));
   end
   ```

3. **Screen** — declare the UI control in `QTAUWorkbenchApp` properties, instantiate in the screen builder, wire the callback:

   ```matlab
   app.BmLoadCfgButton = uibutton(grid, ...
       'Text', Labels.get('bm_btn_load_cfg', 'Load Config'), ...
       'ButtonPushedFcn', @(~,~) app.BenchmarkVm.onLoadConfig());
   ```

### Step 3 — wrap long work in `AsyncRunner`

Anything that hits the network should not block the UI thread:

```matlab
app.showLoading(Labels.get('bm_loading_cfg', 'Loading config…'));
AsyncRunner.run(...
    @() app.BenchmarkSvc.getBenchmarkConfig(pid, tok), ...
    @(cfg) obj.onCfgLoaded(cfg), ...
    @(err) obj.onCfgError(err));
```

Every completion and error branch **must** call `app.hideLoading()`.

### Step 4 — decide caching

If the new data is expensive and screen-scoped, record `obj.LastLoaded = datetime('now')` at the end of your `onFetch` method. `NavigationManager.isScreenFresh(vm, ttl)` will then let rapid re-navigation skip the re-fetch.

### Step 5 — test

Add a unit test under `tests/`:

```matlab
classdef test_BenchmarkService < matlab.unittest.TestCase
    methods (Test)
        function getConfig_returnsStrategy(tc)
            stub = StubFastAPIClient('/api/projects/p/benchmark-config', ...
                struct('strategy','readout_mitigation'));
            svc = BenchmarkService(stub);
            cfg = svc.getBenchmarkConfig('p','t');
            tc.verifyEqual(char(cfg.strategy), 'readout_mitigation');
        end
    end
end
```

`runtests('tests/test_BenchmarkService')` to run just this file.

---

## 4. Adding a *new* screen

Adding a screen always touches four places. Miss one and the screen won't appear or won't load data.

### 1. Screen builder — `src/presentation/screens/FooScreen.m`

```matlab
function FooScreen(app)
    pg = app.createSectionPage('Foo');
    g  = uigridlayout(pg, [3 1]);
    g.RowHeight = {'fit','1x','fit'};

    hdr = uilabel(g, 'Text', Labels.get('foo_hdr', 'Foo dashboard'), ...
                     'FontSize', 18, 'FontWeight', 'bold');

    app.FooTable = uitable(g, 'ColumnName', {'Metric','Value'});
    app.FooTable.Layout.Row = 2;

    app.FooRefreshButton = uibutton(g, ...
        'Text', Labels.get('foo_btn_refresh', 'Refresh'), ...
        'ButtonPushedFcn', @(~,~) app.FooVm.onRefresh());
end
```

### 2. ViewModel — `src/presentation/viewmodels/FooViewModel.m`

```matlab
classdef FooViewModel < handle
    properties
        App
        LastLoaded = NaT
    end
    methods
        function obj = FooViewModel(app); obj.App = app; end

        function onRefresh(obj)
            app = obj.App;
            app.showLoading(Labels.get('foo_loading', 'Loading Foo…'));
            AsyncRunner.run(...
                @() app.ProjectSvc.fetchFoo(app.State.currentProjectId, app.State.authToken), ...
                @(data) obj.onLoaded(data), ...
                @(err)  obj.onError(err));
        end

        function onLoaded(obj, data)
            app = obj.App;
            app.FooTable.Data = JsonHelper.fooToRows(data);
            obj.LastLoaded = datetime('now');
            app.hideLoading();
        end

        function onError(obj, err)
            app = obj.App;
            uialert(app.UIFigure, err.message, Labels.get('foo_err_title','Foo failed'));
            app.hideLoading();
        end
    end
end
```

### 3. Main app — `src/presentation/app/QTAUWorkbenchApp.m`

Three edits:

```matlab
% (a) Add UI control properties
properties
    FooTable
    FooRefreshButton
    FooVm
end

% (b) Instantiate VM in the constructor (after ServiceContainer is wired)
app.FooVm = FooViewModel(app);

% (c) Build the screen in buildUI()
FooScreen(app);
```

### 4. Navigation — `src/presentation/app/NavigationManager.m`

```matlab
function n = navNames();   n = {'Welcome','…','Foo','Settings'}; end
function n = navLabels();  n = {Labels.get('nav_welcome',…),…,Labels.get('nav_foo','Foo'),…}; end
function n = navIcons();   n = {char(8962),…,char(9750),char(9881)}; end
```

Add an `autoLoadScreen` case so first-visit fetches data automatically:

```matlab
case 'Foo'
    if ~isempty(app.FooVm) && ~NavigationManager.isScreenFresh(app.FooVm, ttl)
        NavigationManager.showNavLoading(app, 'Foo');
        app.FooVm.onRefresh();
    end
```

### 5. Labels — `resources/labels.properties`

```properties
nav_foo = Foo
foo_hdr = Foo dashboard
foo_btn_refresh = Refresh
foo_loading = Loading Foo…
foo_err_title = Foo failed
```

### 6. Test — `tests/test_FooService.m`

Mirror one of the existing `test_*Service` suites using `StubFastAPIClient.m`.

---

## 5. Adding a new service (new endpoint family)

1. **Service class** — `src/domain/services/FooService.m`:

   ```matlab
   classdef FooService < handle
       properties; Client; end
       methods
           function obj = FooService(client); obj.Client = client; end

           function data = fetchFoo(obj, projectId, token)
               url = sprintf('%s/api/foo?project_id=%s', obj.Client.BaseUrl, projectId);
               data = obj.Client.get(url, token);
           end
       end
   end
   ```

2. **ServiceContainer.m** — wire it:

   ```matlab
   svcs.FooSvc = FooService(client);
   ```

3. **QTAUWorkbenchApp** — `app.FooSvc = svcs.FooSvc;` in the constructor (after `buildServices`).

4. **Labels / docs** — add relevant label keys; if this is a public endpoint, update `docs/fastapi_contract.md`.

5. **Test** — add a `tests/test_FooService.m` using `StubFastAPIClient`.

---

## 6. Seed / demo data

The API ships with no fixtures. The MATLAB repo has 14 seed scripts under `scripts/`:

```matlab
run('scripts/seed_all.m')           % full orchestration (runs everything below)

run('scripts/seed_projects.m')
run('scripts/seed_circuits.m')
run('scripts/seed_qasmbench.m')     % 113+ QTAUBench circuits
run('scripts/seed_qasmbench_invalid.m')
run('scripts/seed_backends.m')
run('scripts/seed_benchmarks.m')
run('scripts/seed_predictions.m')
run('scripts/seed_jobs.m')
run('scripts/seed_reports.m')
run('scripts/seed_notes.m')
run('scripts/seed_settings.m')
run('scripts/seed_qae.m')           % QMC circuit + IBM-log baseline
```

Each script uses `seed_helpers.m` for auth (reads `resources/seed.properties` — copy from `seed.properties.example`).

Scripts are idempotent: a "list-and-reuse" pattern checks for existing items by name and skips re-upload, so re-running never triggers 409 Conflicts.

---

## 7. Async timers — starting & stopping safely

Two long-running timers exist; both are owned by their VM and must be stopped when the screen goes away.

| Timer | VM | Period | Stop condition |
|---|---|---|---|
| Jobs auto-refresh | `JobsViewModel.startAutoRefresh` | 5 s | all jobs terminal OR user navigates away |
| QMC poll | `AnalysisViewModel.startQmcPoll` | 3 s | server returns terminal status OR user closes QMC dialog |
| Cutting batch poll | `CircuitCuttingViewModel.pollTick` | 3 s | batch reaches terminal status |

When adding a new timer, follow the pattern:

```matlab
obj.PollTimer = timer( ...
    'ExecutionMode', 'fixedSpacing', ...
    'Period', 5, ...
    'TimerFcn', @(~,~) obj.onTimerTick(), ...
    'ErrorFcn', @(~,~) obj.stopPollTimer());

function stopPollTimer(obj)
    if ~isempty(obj.PollTimer) && isvalid(obj.PollTimer)
        stop(obj.PollTimer); delete(obj.PollTimer); obj.PollTimer = [];
    end
end
```

`stopPollTimer` should be called from every exit path, including the `onError` branch and the ViewModel's destructor.

---

## 8. Dialogs

- Add the builder as a static method on `DialogBuilder`.
- Store the dialog handle on the app: `app.FooDialog = uifigure(…)`.
- Always set `CloseRequestFcn` — for uihtml-bearing dialogs, include the detach-DCF-drawnow-delete dance (see `DialogBuilder.closeLoginDialog`).
- Controls inside the dialog live on `app.FooDlg…` properties so ViewModels can read them by name.

---

## 9. Logging

```matlab
Logger.info('MyCategory',  'Fetched %d rows', n);
Logger.warn('MyCategory',  'Retrying: %s', err.message);
Logger.error('MyCategory', 'Give up: %s', err.message);
Logger.nav('QTAUWorkbenchApp', 'Navigating to: %s', key);
Logger.auth('QTAUWorkbenchApp', 'Login OK — user: %s', user);
Logger.api('QTAUWorkbenchApp', 'GET /api/projects');
Logger.http('FastAPIClient', '%s %s', verb, url);
Logger.ui('QTAUWorkbenchApp', 'Circuit selected: %s', name);
Logger.debug('AnalysisViewModel', 'QmcAsyncResult: %s', char(jsonencode(res)));
```

Format is `[HH:MM:SS.FFF] LEVEL [Category] Message`.

Use the highest level that makes sense: `error` for hard stops, `warn` for recoverable issues, `info` for user-visible milestones, `debug` for anything you'd only want while diagnosing. `api`, `http`, `ui`, `nav`, `auth` are category aliases — they render as their own level tag for grep-friendliness.

---

## 10. Testing

- 20 suites live in `tests/`. Every `*Service` class has one.
- `tests/StubFastAPIClient.m` is a drop-in mock client — takes a `Map` of URL→response and plays them back.
- Good starter read: `tests/test_CircuitService.m`.

```matlab
runtests('tests')                      % all
runtests('tests/test_CircuitService')  % one
```

---

## 11. Common tasks — recipes

### Re-enable the Notes screen

1. Add `'Notes'` back to `NavigationManager.navNames()` / `navLabels()` / `navIcons()` at position 4.
2. Done — `NotesScreen` / `NotesViewModel` are still instantiated, so the tab lights up immediately.

### Change the nav icon for a screen

Edit the Unicode codepoint in `NavigationManager.navIcons()`. Use `char(0x…)` or `char(1234)` — CEF renders them as font glyphs without external assets.

### Swap the default theme

Call `Theme.setActive('dracula')` anywhere — `Theme.applyFigureMode` is invoked by the repaint pipeline so every uifigure reflects the change.

### Add a new nav-loading overlay message

`NavigationManager.showNavLoading(app, key)` uses `Labels.get(['nav_loading_' lower(key)], …)` so adding a label key `nav_loading_foo = Loading Foo dashboard…` is all that's required.

### Add a Circuit-selector toolbar dropdown to a screen

Copy the pattern from `PredictionScreen.m`: `uidropdown(topBar, 'Items', {…})` bound to `app.State.selectedCircuitId` with a `ValueChangedFcn` that re-triggers the VM's `onRefresh`.

### Ship a bug-fix for a VM method while the app is running

MATLAB caches classes. After editing a `.m` file:

```matlab
clear classes      % flushes the cached classdef
run('QTAUWorkbenchLauncher.m')
```

---

## 12. Things to avoid

- Don't reassign `app.NavHtml.HTMLSource` on every nav click — use `Data` push (see `updateNavStyles`).
- Don't delete a uifigure with HTML fields without detaching `DataChangedFcn` first.
- Don't call `webread` / `webwrite` from a ViewModel — always go through a service.
- Don't hard-code user-visible strings — always `Labels.get`.
- Don't cache counts / fidelity / predictions in the ViewModel and assume they're fresh — the server is authoritative. Use `isScreenFresh` with a short TTL instead.
- Don't add a new endpoint to `FastAPIClient.m` — put it on the service that owns the feature.
