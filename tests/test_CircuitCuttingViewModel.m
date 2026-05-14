classdef test_CircuitCuttingViewModel < matlab.unittest.TestCase
    % test_CircuitCuttingViewModel  Pin the VM's private formatter contract
    % so a regression of the null-handling + Unicode-width bugs can't sneak
    % back in. Uses TestCircuitCuttingVmProbe to reach the private helpers
    % without spinning up a full QTAUWorkbenchApp instance.

    methods (TestClassSetup)
        function addPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'presentation', 'viewmodels'));
            addpath(fullfile(projectRoot, 'tests'));
        end
    end

    methods (Test)

        function testFormatOverheadHandlesEmpty(tc)
            vm = TestCircuitCuttingVmProbe();
            tc.verifyEqual(vm.probeFormatOverhead([]), '--');
            tc.verifyEqual(vm.probeFormatOverhead(NaN), '--');
            tc.verifyEqual(vm.probeFormatOverhead(7.2), '7.2x');
            tc.verifyEqual(vm.probeFormatOverhead(1.0), '1.0x');
        end

        function testFormatPerSubHandlesCellAndArray(tc)
            vm = TestCircuitCuttingVmProbe();
            tc.verifyEqual(vm.probeFormatPerSub({}), '(unknown)');
            tc.verifyEqual(vm.probeFormatPerSub({54, 53, 53}), '(54+53+53)');
            tc.verifyEqual(vm.probeFormatPerSub([64, 64]), '(64+64)');
        end

        function testDefaultModeIsAssisted(tc)
            vm = TestCircuitCuttingVmProbe();
            tc.verifyEqual(vm.probeDefaultMode(), 'assisted');
        end

        function testParseObservableLinesReturnsEmptyForPlaceholderOnly(tc)
            ph = '(default: all-Z over full circuit width)';
            obs = CircuitCuttingViewModel.parseObservableLines({ph}, ph);
            tc.verifyEqual(obs, {});
        end

        function testParseObservableLinesDropsBlanksAndPlaceholder(tc)
            ph = '(default: all-Z over full circuit width)';
            obs = CircuitCuttingViewModel.parseObservableLines( ...
                {'ZZZZ', '', '  XYXY  ', ph, ' '}, ph);
            tc.verifyEqual(obs, {'ZZZZ', 'XYXY'});
        end

        function testParseObservableLinesHandlesStringAndChar(tc)
            obs = CircuitCuttingViewModel.parseObservableLines('ZZZ', '');
            tc.verifyEqual(obs, {'ZZZ'});
            obs = CircuitCuttingViewModel.parseObservableLines( ...
                string({'XX', '', 'YY'}), '');
            tc.verifyEqual(obs, {'XX', 'YY'});
        end

        function testParseObservableLinesHandlesEmptyInput(tc)
            tc.verifyEqual( ...
                CircuitCuttingViewModel.parseObservableLines({}, ''), {});
            tc.verifyEqual( ...
                CircuitCuttingViewModel.parseObservableLines([], ''), {});
            tc.verifyEqual( ...
                CircuitCuttingViewModel.parseObservableLines('', ''), {});
        end

        function testCheckQasmCuttableAllowsTerminalMeasure(tc)
            qasm = sprintf([ ...
                'OPENQASM 2.0;\n' ...
                'include "qelib1.inc";\n' ...
                'qreg q[2];\n' ...
                'creg c[2];\n' ...
                'h q[0];\n' ...
                'cx q[0],q[1];\n' ...
                'measure q[0] -> c[0];\n' ...
                'measure q[1] -> c[1];\n']);
            res = CircuitCuttingViewModel.checkQasmCuttable(qasm);
            tc.verifyTrue(res.ok);
            tc.verifyEqual(res.severity, 'ok');
        end

        function testCheckQasmCuttableFlagsClassicalControl(tc)
            qasm = sprintf([ ...
                'OPENQASM 2.0;\n' ...
                'include "qelib1.inc";\n' ...
                'qreg q[2];\n' ...
                'creg c[1];\n' ...
                'h q[0];\n' ...
                'measure q[0] -> c[0];\n' ...
                'if (c==1) x q[1];\n']);
            res = CircuitCuttingViewModel.checkQasmCuttable(qasm);
            tc.verifyFalse(res.ok);
            tc.verifyEqual(res.severity, 'error');
            tc.verifyTrue(contains(res.reason, 'classical-controlled', 'IgnoreCase', true));
        end

        function testCheckQasmCuttableFlagsBB84Pattern(tc)
            % BB84 prepares + measures + classically conditions. Even
            % without an explicit if(), measuring a qubit and then
            % operating on it is mid-circuit measurement and must be
            % flagged.
            qasm = sprintf([ ...
                'OPENQASM 2.0;\n' ...
                'include "qelib1.inc";\n' ...
                'qreg q[2];\n' ...
                'creg c[2];\n' ...
                'h q[0];\n' ...
                'measure q[0] -> c[0];\n' ...
                'x q[0];\n' ...           % <- mid-circuit op on q[0]
                'measure q[0] -> c[0];\n']);
            res = CircuitCuttingViewModel.checkQasmCuttable(qasm);
            tc.verifyFalse(res.ok);
            tc.verifyEqual(res.severity, 'error');
            tc.verifyTrue(contains(res.reason, 'mid-circuit', 'IgnoreCase', true));
        end

        function testCheckQasmCuttableFlagsReset(tc)
            qasm = sprintf([ ...
                'OPENQASM 2.0;\n' ...
                'include "qelib1.inc";\n' ...
                'qreg q[1];\n' ...
                'h q[0];\n' ...
                'reset q[0];\n']);
            res = CircuitCuttingViewModel.checkQasmCuttable(qasm);
            tc.verifyFalse(res.ok);
            tc.verifyEqual(res.severity, 'error');
            tc.verifyTrue(contains(res.reason, 'reset', 'IgnoreCase', true));
        end

        function testCheckQasmCuttableHandlesEmpty(tc)
            res = CircuitCuttingViewModel.checkQasmCuttable('');
            tc.verifyTrue(res.ok);
        end

    end
end
