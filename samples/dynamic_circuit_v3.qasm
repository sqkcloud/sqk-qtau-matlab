OPENQASM 3.0;

// Dynamic Circuit with Mid-Circuit Measurement (OpenQASM 3.0)
// Demonstrates real-time classical feedback:
// prepare |+>, measure, conditionally apply correction,
// then entangle with a second qubit

qubit[3] q;
bit[3] result;

// Prepare q[0] in |+> state
h q[0];

// Mid-circuit measurement
bit m0;
m0 = measure q[0];

// Classical feedback: if measured |1>, reset and re-prepare
if (m0 == 1) {
    reset q[0];
    h q[0];
}

// Now entangle q[0] with q[1] and q[2] to form GHZ
cx q[0], q[1];
cx q[0], q[2];

// Second mid-circuit measurement on ancilla q[2]
bit m2;
m2 = measure q[2];

// Conditional phase correction
if (m2 == 1) {
    z q[0];
    reset q[2];
    h q[2];
    cx q[0], q[2];
}

result = measure q;
