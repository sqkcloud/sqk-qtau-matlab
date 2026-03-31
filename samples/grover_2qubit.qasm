OPENQASM 2.0;
include "qelib1.inc";

// Grover's Search — 2 qubits, target state |11>
// Single iteration finds the marked state with high probability
qreg q[2];
creg c[2];

// Initialize superposition
h q[0];
h q[1];

// Oracle: mark |11>
cz q[0], q[1];

// Diffusion operator
h q[0];
h q[1];
x q[0];
x q[1];
cz q[0], q[1];
x q[0];
x q[1];
h q[0];
h q[1];

measure q[0] -> c[0];
measure q[1] -> c[1];
