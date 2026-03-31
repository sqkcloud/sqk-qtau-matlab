OPENQASM 2.0;
include "qelib1.inc";

// Quantum Fourier Transform — 4 qubits
// Transforms computational basis to frequency basis
qreg q[4];
creg c[4];

// Prepare input state |5> = |0101>
x q[0];
x q[2];

// QFT circuit
h q[0];
cu1(pi/2) q[1], q[0];
cu1(pi/4) q[2], q[0];
cu1(pi/8) q[3], q[0];
h q[1];
cu1(pi/2) q[2], q[1];
cu1(pi/4) q[3], q[1];
h q[2];
cu1(pi/2) q[3], q[2];
h q[3];

// Swap for bit reversal
swap q[0], q[3];
swap q[1], q[2];

measure q[0] -> c[0];
measure q[1] -> c[1];
measure q[2] -> c[2];
measure q[3] -> c[3];
