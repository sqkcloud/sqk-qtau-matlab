classdef MatlabQuantumBridge
    % MatlabQuantumBridge  Interop between the app's CircuitModel and the
    %   MATLAB Support Package for Quantum Computing (`quantumCircuit`).
    %   The ONLY module that references Support-Package API — every other
    %   feature degrades gracefully when the add-on is absent.
    %
    %   Index convention: internal CircuitModel qubits are 0-indexed
    %   (QASM style); quantumCircuit qubits are 1-indexed. The ±1 shift is
    %   applied in fromQuantumCircuit / kindToGate only.

    methods (Static)
        function tf = isAvailable()
            tf = exist('quantumCircuit', 'class') == 8;
        end
    end
end
