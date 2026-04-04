OPENQASM 3.0;

// Shor's 9-Qubit Error Correction Code (OpenQASM 3.0)
// The first quantum error correction code, proposed by Peter Shor in 1995.
// Encodes one logical qubit into 9 physical qubits.
// Corrects any single-qubit error (bit-flip, phase-flip, or both).
//
// Structure: Three blocks of 3 qubits each.
//   - Within each block: bit-flip code protects against X errors
//   - Across blocks: phase-flip code protects against Z errors
//
// |0_L⟩ = (|000⟩+|111⟩)(|000⟩+|111⟩)(|000⟩+|111⟩) / 2√2
// |1_L⟩ = (|000⟩-|111⟩)(|000⟩-|111⟩)(|000⟩-|111⟩) / 2√2
//
// Reference: QASMBench (PNNL) — seca benchmark

qubit[9] data;
qubit[8] syndrome;
bit[8] syn_result;
bit[1] output;

// Prepare logical state on qubit 0
h data[0];

// Phase-flip encoding: spread across 3 blocks
cx data[0], data[3];
cx data[0], data[6];

// Bit-flip encoding within each block
// Block 1: qubits 0,1,2
h data[0];
cx data[0], data[1];
cx data[0], data[2];

// Block 2: qubits 3,4,5
h data[3];
cx data[3], data[4];
cx data[3], data[5];

// Block 3: qubits 6,7,8
h data[6];
cx data[6], data[7];
cx data[6], data[8];

// Simulate an arbitrary single-qubit error on qubit 4
// (This is a bit-flip error in block 2)
x data[4];

// ── Syndrome extraction ──

// Bit-flip syndromes for Block 1 (qubits 0,1,2)
cx data[0], syndrome[0];
cx data[1], syndrome[0];
cx data[1], syndrome[1];
cx data[2], syndrome[1];

// Bit-flip syndromes for Block 2 (qubits 3,4,5)
cx data[3], syndrome[2];
cx data[4], syndrome[2];
cx data[4], syndrome[3];
cx data[5], syndrome[3];

// Bit-flip syndromes for Block 3 (qubits 6,7,8)
cx data[6], syndrome[4];
cx data[7], syndrome[4];
cx data[7], syndrome[5];
cx data[8], syndrome[5];

// Measure bit-flip syndromes
syn_result[0] = measure syndrome[0];
syn_result[1] = measure syndrome[1];
syn_result[2] = measure syndrome[2];
syn_result[3] = measure syndrome[3];
syn_result[4] = measure syndrome[4];
syn_result[5] = measure syndrome[5];

// Bit-flip correction: Block 1
if (syn_result[0] == 1 && syn_result[1] == 0) { x data[0]; }
if (syn_result[0] == 1 && syn_result[1] == 1) { x data[1]; }
if (syn_result[0] == 0 && syn_result[1] == 1) { x data[2]; }

// Bit-flip correction: Block 2
if (syn_result[2] == 1 && syn_result[3] == 0) { x data[3]; }
if (syn_result[2] == 1 && syn_result[3] == 1) { x data[4]; }
if (syn_result[2] == 0 && syn_result[3] == 1) { x data[5]; }

// Bit-flip correction: Block 3
if (syn_result[4] == 1 && syn_result[5] == 0) { x data[6]; }
if (syn_result[4] == 1 && syn_result[5] == 1) { x data[7]; }
if (syn_result[4] == 0 && syn_result[5] == 1) { x data[8]; }

// Decode bit-flip encoding within each block
cx data[0], data[2];
cx data[0], data[1];
h data[0];

cx data[3], data[5];
cx data[3], data[4];
h data[3];

cx data[6], data[8];
cx data[6], data[7];
h data[6];

// Phase-flip syndrome extraction
cx data[0], syndrome[6];
cx data[3], syndrome[6];
cx data[3], syndrome[7];
cx data[6], syndrome[7];

syn_result[6] = measure syndrome[6];
syn_result[7] = measure syndrome[7];

// Phase-flip correction
if (syn_result[6] == 1 && syn_result[7] == 0) { z data[0]; }
if (syn_result[6] == 1 && syn_result[7] == 1) { z data[3]; }
if (syn_result[6] == 0 && syn_result[7] == 1) { z data[6]; }

// Decode phase-flip encoding
cx data[0], data[6];
cx data[0], data[3];

output = measure data[0];
