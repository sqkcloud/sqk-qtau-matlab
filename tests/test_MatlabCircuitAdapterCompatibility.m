function tests = test_MatlabCircuitAdapterCompatibility
tests = functiontests(localfunctions);
end
function testCommonSubsetAccepted(testCase)
qasm = "OPENQASM 3; qubit[2] q; h q[0]; cx q[0], q[1];";
r = MatlabCircuitAdapter.compatibility(qasm);
verifyTrue(testCase,r.compatible);
end
function testCustomGateRejected(testCase)
qasm = "OPENQASM 3; gate foo a { h a; } qubit[1] q; foo q[0];";
r = MatlabCircuitAdapter.compatibility(qasm);
verifyFalse(testCase,r.compatible);
verifyNotEmpty(testCase,r.unsupportedConstructs);
end
