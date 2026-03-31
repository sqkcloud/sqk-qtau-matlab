OPENQASM 2.0;
include "qelib1.inc";

// Quantum Teleportation Protocol — 3 qubits
// Teleports state of q[0] to q[2] using shared entanglement
qreg q[3];
creg c0[1];
creg c1[1];
creg c2[1];

// Prepare state to teleport on q[0]
h q[0];
t q[0];

// Create Bell pair between q[1] and q[2]
h q[1];
cx q[1], q[2];

// Alice's operations
cx q[0], q[1];
h q[0];

// Measure Alice's qubits
measure q[0] -> c0[0];
measure q[1] -> c1[0];

// Bob's corrections (classically controlled)
if(c1==1) x q[2];
if(c0==1) z q[2];

measure q[2] -> c2[0];
