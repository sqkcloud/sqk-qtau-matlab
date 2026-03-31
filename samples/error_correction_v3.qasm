OPENQASM 3.0;

// 3-Qubit Bit-Flip Error Correction Code (OpenQASM 3.0)
// Encodes one logical qubit into three physical qubits,
// detects and corrects a single bit-flip error

qubit[3] data;
qubit[2] syndrome;
bit[2] syn_result;
bit[1] output;

// Prepare logical |+> state
h data[0];

// Encode: |psi> -> |psi psi psi>
cx data[0], data[1];
cx data[0], data[2];

// Simulate a bit-flip error on qubit 1
x data[1];

// Syndrome extraction
cx data[0], syndrome[0];
cx data[1], syndrome[0];
cx data[1], syndrome[1];
cx data[2], syndrome[1];

syn_result = measure syndrome;

// Correction based on syndrome
if (syn_result == 1) {
    x data[2];
}
if (syn_result == 2) {
    x data[0];
}
if (syn_result == 3) {
    x data[1];
}

// Decode
cx data[0], data[2];
cx data[0], data[1];

output = measure data[0];
