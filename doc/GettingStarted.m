%% Getting Started with QTAU Connector Workbench
% *QTAU Connector Workbench* is a MATLAB desktop client for managing
% quantum-circuit experiments through the QTAU FastAPI backend. This
% guide walks you through first launch, configuring your QTAU server
% connection, and a 5-minute tour of the main screens.
%
% *This file is the source draft. Open it in MATLAB, then save it
% as GettingStarted.mlx (File > Save As > Live Script .mlx) so the
% toolbox task can register it as the Getting Started guide.*

%% Prerequisites
% Before you start, make sure you have:
%
% * *MATLAB R2025a or later*. The workbench uses uifigure,
%   uicontextmenu, DoubleClickedFcn on uitable, and other UI features
%   that require R2025a or newer.
%
% * *Access to a running QTAU FastAPI server.* The toolbox does NOT
%   include the backend - it's the MATLAB client only. You need either:
%
%      * The URL of your organisation's hosted QTAU server (ask your
%        admin), OR
%      * A self-hosted QTAU FastAPI instance on your own machine or
%        network. See https://github.com/sqkcloud/qtau-fastapi for
%        the backend repo.
%
% * *Login credentials* (username + password) for that QTAU server.

%% Step 1 - Launch the Workbench
% Once the toolbox is installed, type the launcher at the MATLAB
% prompt:
%
%   QTAUWorkbenchLauncher
%
% The launcher configures the MATLAB path and opens the main window.
% The Dashboard screen appears followed by a Login dialog.

%% Step 2 - Set your QTAU server URL on first launch
% The shipped toolbox has an *empty* base URL by default. On first
% launch the app falls back to |http://localhost:5715|, which only
% works if you're running a QTAU FastAPI server on the same machine.
%
% To point the app at a different server:
%
% # On the *Login* dialog, find the *Base URL* field at the top
%   of the form.
% # Replace the default with your QTAU server URL, e.g.
%   |https://qtau.example.com:5715| or |http://10.0.0.42:5715|.
% # Enter your username + password and click *Sign In*.
%
% The URL is remembered for the rest of the session. To persist it
% across launches, open *Settings > Connection* once you're logged
% in and Save.

%% Step 3 - Quick tour of the main screens
% After login you land on *Dashboard*. The 20 screens in the left
% sidebar fall into three workflow groups.
%
% *Browse and author*
%
% * *Projects* - switch between projects you own or collaborate on.
% * *Circuits* - upload OpenQASM files, browse the QTAUBench corpus
%   (252 reference circuits), and pre-analyse a circuit before
%   submitting it.
% * *Composer* - in-app circuit authoring with click-to-place gates,
%   bidirectional OpenQASM 2.0 mirror, and a local statevector
%   simulator for circuits up to ~14 qubits.
%
% *Plan and submit*
%
% * *Backends* - explore IBM Quantum devices: per-qubit calibration
%   heatmap, T1/T2 history sparklines, force-directed topology graph.
% * *Benchmark* - pick circuit + backend + mitigation level + shots,
%   run a pre-flight check, and submit a job to IBM Quantum.
% * *Mitigation Compare* - side-by-side error-mitigation cost
%   estimates over your project's backends.
% * *Run Planner* - cost-aware run optimisation. Given a target
%   fidelity, picks the cheapest (backend x mitigation x shots)
%   configuration that meets it via a Pareto frontier.
% * *Resource Estimator* - fault-tolerant overhead planner (surface
%   code distance, physical-per-logical, T-state budget).
%
% *Monitor and analyse*
%
% * *Jobs* - live monitoring dashboard with 5-second auto-refresh,
%   right-click context menu (View Results / Detailed Analysis /
%   Cancel / Copy IBM Job ID / Open in IBM Quantum).
% * *Results* - measured-vs-ideal histogram, distribution review,
%   mitigation/timing/context tiles, cutting-batch list, PDF report
%   generation.
% * *Reports* - download generated PDF reports.
% * *Detailed Analysis* - heatmaps, drift, qubit metrics, cross-run
%   comparisons.

%% Step 4 - Try the workflow on a sample circuit
%
% # Open *Circuits*. Click *Upload* in the toolbar.
% # Browse to |samples/bell_state.qasm| (bundled with the toolbox).
% # Once uploaded, select the circuit and click *Analyse*. The
%   Analysis screen shows depth/width/2Q-gate count and a complexity
%   landscape relative to the QTAUBench corpus.
% # From the Analysis toolbar, click *Quantum Monte Carlo* to open
%   the QMC simulation popup. Pick *Statevector (local)* for a small
%   circuit like Bell state - it runs on your machine without
%   needing IBM Runtime.
% # Click *Run QMC*. Watch the progress overlay. Results appear in
%   the popup with loss-distribution + greeks + ZNE curve.
% # Click *Generate Report* to produce a PDF.

%% Where to get help
%
% * *In-app help* - every screen has a *(?)* icon in the top-right
%   corner that opens a contextual help dialog.
% * *Documentation* - see |docs/architecture.md|,
%   |docs/fastapi_contract.md|, and |docs/development_guide.md|
%   bundled in the toolbox.
% * *Issues + feedback* - open a ticket at the project's GitHub
%   repository.
% * *Backend setup* - if you need to host your own QTAU FastAPI
%   server, see the upstream QTAU backend repository.

%% License and attribution
%
% QTAU Connector Workbench is Copyright (c) 2026 SQK Cloud Inc.,
% released under the Apache License 2.0. See |LICENSE| and |NOTICE|
% in the toolbox folder for full terms and third-party attribution
% (including the bundled PNNL QASMBench corpus under
% |samples/qasmbench/|).
