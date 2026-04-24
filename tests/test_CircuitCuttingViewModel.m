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

    end
end
