function tests = test_SimulationServiceProviders
tests = functiontests(localfunctions);
end
function testProvidersAlwaysContainFallback(testCase)
t = SimulationService().providers();
verifyEqual(testCase,height(t),2);
verifyTrue(testCase,t.Available(t.Provider=="qtau"));
end
function testUnknownEngineRejected(testCase)
verifyError(testCase,@()SimulationService().simulate([], 'bad-engine', 0), ...
    'SimulationService:UnknownEngine');
end
