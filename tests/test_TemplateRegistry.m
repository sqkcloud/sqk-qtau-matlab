% test_TemplateRegistry.m ─────────────────────────────────────────────────────
% Unit tests for the TemplateRegistry catalogue — every template
% instantiates with default params and produces parser-valid QASM.
%
% Run from the project root:
%   >> runtests('tests/test_TemplateRegistry')
% ──────────────────────────────────────────────────────────────────────────────

function tests = test_TemplateRegistry
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    thisDir     = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(thisDir, '..');
    addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
    addpath(fullfile(projectRoot, 'src', 'domain', 'models'));
end

function test_list_returns_twelve(testCase)
    items = TemplateRegistry.list();
    testCase.assertEqual(numel(items), 12);
    expectedIds = {'bell','ghz','qft','grover','bv','dj', ...
                   'pe','vqe','qaoa','trotter','teleport','superdense'};
    actualIds = {items.id};
    for i = 1:numel(expectedIds)
        testCase.assertTrue(any(strcmp(actualIds, expectedIds{i})), ...
            sprintf('Missing template id: %s', expectedIds{i}));
    end
end

function test_find_returns_matching_metadata(testCase)
    meta = TemplateRegistry.find('bell');
    testCase.assertEqual(meta.id, 'bell');
    testCase.assertEqual(meta.qubits, 2);
end

function test_find_throws_on_unknown(testCase)
    testCase.verifyError(@() TemplateRegistry.find('nope'), 'TemplateRegistry:UnknownId');
end

function test_every_template_instantiates(testCase)
    items = TemplateRegistry.list();
    for i = 1:numel(items)
        meta = items(i);
        params = TemplateRegistry.defaultParams(meta.id);
        m = TemplateRegistry.instantiate(meta.id, params);
        testCase.assertGreaterThan(numel(m.Gates), 0, ...
            sprintf('Template %s instantiated with zero gates', meta.id));
        % Round-trip check: emitted QASM must parse back cleanly.
        txt = m.toQasm();
        parsed = CircuitModel.fromQasm(txt);
        testCase.assertEqual(numel(parsed.Gates), numel(m.Gates), ...
            sprintf('Template %s round-trip lost gates', meta.id));
    end
end

function test_bell_has_h_then_cx(testCase)
    m = TemplateRegistry.instantiate('bell');
    testCase.assertEqual(m.Gates(1).kind, 'h');
    testCase.assertEqual(m.Gates(2).kind, 'cx');
end

function test_ghz_n_widens_with_n(testCase)
    m3 = TemplateRegistry.instantiate('ghz', struct('n', 3));
    m5 = TemplateRegistry.instantiate('ghz', struct('n', 5));
    testCase.assertEqual(m3.NumQubits, 3);
    testCase.assertEqual(m5.NumQubits, 5);
    testCase.assertEqual(numel(m3.Gates), 3);   % H + 2 CX
    testCase.assertEqual(numel(m5.Gates), 5);   % H + 4 CX
end

function test_dj_constant_has_no_oracle(testCase)
    constM   = TemplateRegistry.instantiate('dj', struct('n', 2, 'balanced', 0));
    balanceM = TemplateRegistry.instantiate('dj', struct('n', 2, 'balanced', 1));
    testCase.assertGreaterThan(numel(balanceM.Gates), numel(constM.Gates));
end

function test_superdense_pads_message(testCase)
    m = TemplateRegistry.instantiate('superdense', struct('message', '1'));
    testCase.assertEqual(m.NumQubits, 2);
end
