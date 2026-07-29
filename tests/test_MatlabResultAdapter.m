function tests = test_MatlabResultAdapter
tests = functiontests(localfunctions);
end
function testStructToTable(testCase)
t = MatlabResultAdapter.toTable(struct('backend','sim','fidelity',0.99));
verifyTrue(testCase, istable(t));
verifyEqual(testCase, t.fidelity, 0.99);
end
