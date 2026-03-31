OPENQASM 2.0;
include "qelib1.inc";

// VQE Ansatz for H2 Molecule — 2 qubits
// Hardware-efficient variational ansatz with parameterized rotations
// theta values represent one optimized iteration
qreg q[2];
creg c[2];

// Initial state |01> (Hartree-Fock reference)
x q[0];

// Parameterized layer 1
ry(0.7854) q[0];
ry(1.2310) q[1];
cx q[0], q[1];

// Parameterized layer 2
ry(-0.4521) q[0];
ry(0.8765) q[1];
cx q[0], q[1];

// Parameterized layer 3
rz(0.3142) q[0];
rz(-0.6283) q[1];

measure q[0] -> c[0];
measure q[1] -> c[1];
