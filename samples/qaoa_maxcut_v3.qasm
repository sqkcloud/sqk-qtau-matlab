OPENQASM 3.0;

// QAOA MaxCut — 4-node graph, depth-1 ansatz (OpenQASM 3.0)
// Solves MaxCut on a 4-node ring graph using QAOA variational circuit

const int n = 4;
qubit[n] q;
bit[n] c;

// Optimized QAOA parameters (gamma, beta)
float[64] gamma = 0.6435;
float[64] beta = 0.3927;

// Initial superposition
for int i in [0:n-1] {
    h q[i];
}

// Cost unitary — ZZ interactions for ring graph edges (0-1, 1-2, 2-3, 3-0)
cx q[0], q[1];
rz(2*gamma) q[1];
cx q[0], q[1];

cx q[1], q[2];
rz(2*gamma) q[2];
cx q[1], q[2];

cx q[2], q[3];
rz(2*gamma) q[3];
cx q[2], q[3];

cx q[3], q[0];
rz(2*gamma) q[0];
cx q[3], q[0];

// Mixer unitary
for int i in [0:n-1] {
    rx(2*beta) q[i];
}

c = measure q;
