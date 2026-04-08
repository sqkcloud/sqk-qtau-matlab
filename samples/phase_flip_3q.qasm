OPENQASM 3.0;

// 3-Qubit Phase-Flip Error Correction Code (OpenQASM 3.0)
// Encodes one logical qubit into three physical qubits,
// detects and corrects a single phase-flip (Z) error.
// Dual of the bit-flip code — operates in the Hadamard basis.

qubit[3] data;
qubit[2] syndrome;
bit[2] syn_result;
bit output;

// Prepare logical |+> state
h data[0];

// Encode into Hadamard basis: |ψ⟩ → α|+++⟩ + β|−−−⟩
cx data[0], data[1];
cx data[0], data[2];
h data[0];
h data[1];
h data[2];

// Simulate a phase-flip error on qubit 1
z data[1];

// Transform to computational basis for syndrome extraction
h data[0];
h data[1];
h data[2];

// Syndrome extraction (same as bit-flip in computational basis)
cx data[0], syndrome[0];
cx data[1], syndrome[0];
cx data[1], syndrome[1];
cx data[2], syndrome[1];

syn_result = measure syndrome;

// Correction based on syndrome (bit-flip correction in H-basis = phase-flip correction)
if (syn_result == 1) {
    x data[2];
}
if (syn_result == 2) {
    x data[0];
}
if (syn_result == 3) {
    x data[1];
}

// Transform back to original basis
h data[0];
h data[1];
h data[2];

// Decode
cx data[0], data[2];
cx data[0], data[1];

output = measure data[0];
