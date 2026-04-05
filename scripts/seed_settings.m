% seed_settings.m ──────────────────────────────────────────────────────────────
% Saves user preferences and verifies IBM credentials via the REST API.
%
% Usage:
%   >> run('scripts/seed_settings.m')
%
% Provides data for: Settings screen (preferences panel, IBM account section)
% Prerequisites: none (only needs valid auth)
% ──────────────────────────────────────────────────────────────────────────────

fprintf('\n=== QTAU Seed: Configuring user settings ===\n\n');

% ── Configuration ────────────────────────────────────────────────────────────
cfg      = seed_helpers.loadConfig();
BASE_URL = cfg.base_url;

% ── Step 1: Authenticate ────────────────────────────────────────────────────
fprintf('[1/2] Logging in as "%s" ... ', cfg.username);
try
    token = seed_helpers.login(BASE_URL, cfg.login_path, cfg.username, cfg.password);
    fprintf('OK\n');
catch ME
    fprintf('FAILED\n  %s\n', ME.message);
    return;
end

postOpts = seed_helpers.postOpts(token);

% ── Step 2: Save preferences ─────────────────────────────────────────────────
fprintf('[2/2] Saving preferences ...\n');

% 2a. Save admin preferences
fprintf('  Saving admin preferences ... ');
prefs = struct( ...
    'default_shots',        4096, ...
    'default_optimization', 2, ...
    'email_notifications',  true, ...
    'cache_policy',         'normal', ...
    'notification_mode',    'in_app');

try
    webwrite([BASE_URL '/api/settings'], prefs, postOpts);
    fprintf('OK\n');
catch ME
    fprintf('FAILED (%s)\n', ME.message);
end

% 2b. Verify IBM credentials (test with placeholder — demonstrates the flow)
fprintf('  Testing IBM credential verification ... ');
ibmPayload = struct( ...
    'token',    'test_placeholder_token_for_demo', ...
    'channel',  'ibm_quantum', ...
    'instance', 'ibm-q/open/main');

try
    resp = webwrite([BASE_URL '/api/settings/verify-ibm'], ibmPayload, postOpts);
    % This will likely return invalid, which is expected
    if isstruct(resp) && isfield(resp, 'valid')
        fprintf('response received (valid=%s)\n', string(resp.valid));
    else
        fprintf('response received\n');
    end
catch ME
    fprintf('responded (%s)\n', ME.message);
end

% 2c. Read back current preferences to verify
fprintf('  Verifying saved preferences ... ');
getOpts = seed_helpers.getOpts(token);
try
    savedPrefs = webread([BASE_URL '/api/settings/preferences'], getOpts);
    fprintf('OK (shots=%d, opt=%d)\n', ...
        savedPrefs.default_shots, savedPrefs.default_optimization);
catch ME
    fprintf('FAILED (%s)\n', ME.message);
end

fprintf('\n=== Done: User settings configured ===\n\n');
