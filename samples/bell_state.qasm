OPENQASM 2.0;
include "qelib1.inc";

// Bell State (EPR pair) — 2 qubits
// Creates maximally entangled |00> + |11> state
qreg q[2];
creg c[2];

h q[0];
cx q[0], q[1];

measure q[0] -> c[0];
measure q[1] -> c[1];
