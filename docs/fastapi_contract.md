# FastAPI Contract for QTAU MATLAB Add-on

## 1. Upload circuit
`POST /api/circuits/upload`

Request:
```json
{
  "project_name": "VQE H2O optimization",
  "filename": "vqe_h2o.qasm",
  "format": "openqasm3",
  "metadata": {
    "author": "Dr. Smith",
    "version": "2.1.0",
    "description": "VQE ansatz for H2O molecule",
    "tags": ["VQE", "chemistry", "12-qubit"]
  },
  "content_base64": "..."
}
```

Response:
```json
{
  "circuit_id": "cir_001",
  "project_id": "prj_001",
  "name": "vqe_h2o.qasm",
  "width": 12,
  "depth": 34,
  "gate_count": 156,
  "preview_text": "q_0: ─H──X─ ..."
}
```

## 2. Analyze circuit
`POST /api/circuits/analyze`

Request:
```json
{
  "circuit_id": "cir_001"
}
```

Response:
```json
{
  "features": {
    "depth": 34,
    "width": 12,
    "total_gates": 156,
    "single_qubit_gates": 98,
    "two_qubit_gates": 58,
    "gate_density": 0.38,
    "t_count": 42,
    "entanglement_capability": 0.82,
    "schmidt_rank_estimate": 8,
    "parallelization_factor": 0.69,
    "graph_connectivity": 0.71,
    "qubit_coupling_utilization": 0.66
  },
  "similarity_matches": [
    {"rank": 1, "circuit": "vqe_uccsd_12q", "similarity": 0.94, "type": "Chemistry VQE"},
    {"rank": 2, "circuit": "qaoa_maxcut_12q", "similarity": 0.82, "type": "Optimization"}
  ]
}
```

## 3. Backends
`GET /api/backends`

Response:
```json
{
  "updated_at": "2026-03-16T09:30:00Z",
  "backends": [
    {
      "name": "ibm_brisbane",
      "qubits": 127,
      "queue_min": 12,
      "predicted_fidelity": 94.2,
      "error_rate": 5.8,
      "kind": "hardware",
      "selected": false,
      "calibration": {
        "single_qubit_error": 0.0008,
        "ecr_error": 0.0061,
        "t1_us": 152.6,
        "t2_us": 143.2
      }
    }
  ]
}
```

## 4. Configure benchmark
`POST /api/benchmark/configure`

Request:
```json
{
  "circuit_id": "cir_001",
  "primary_backend": "ibm_brisbane",
  "backup_backend": "ibm_sherbrooke",
  "shots": 8192,
  "optimization_level": 3,
  "error_mitigation": ["readout", "dynamical_decoupling", "pauli_twirling"],
  "priority": "normal"
}
```

Response:
```json
{
  "estimated_cost": 4.10,
  "estimated_queue_min": 12,
  "strategies": [
    {"strategy": "Original Circuit", "depth": 34, "gates": 156, "predicted_fidelity": 92.4, "vs_original": 0.0},
    {"strategy": "IBM Level 3", "depth": 26, "gates": 138, "predicted_fidelity": 93.7, "vs_original": 1.3},
    {"strategy": "Noise-Adaptive", "depth": 25, "gates": 131, "predicted_fidelity": 94.2, "vs_original": 1.8}
  ],
  "recommended_strategy": "Noise-Adaptive"
}
```

## 5. Prediction
`POST /api/predictions`

Request:
```json
{
  "circuit_id": "cir_001",
  "backend": "ibm_brisbane",
  "strategy": "Noise-Adaptive"
}
```

Response:
```json
{
  "expected_fidelity": 94.2,
  "confidence_low": 92.9,
  "confidence_high": 95.9,
  "prediction_reliability": 93.0,
  "error_budget": {
    "gate": 63,
    "readout": 22,
    "decoherence": 12,
    "crosstalk": 3
  },
  "distribution": {
    "labels": ["0000", "0001", "0010", "0011"],
    "values": [0.03, 0.08, 0.14, 0.21]
  }
}
```

## 6. Jobs
`POST /api/jobs`

Request:
```json
{
  "circuit_id": "cir_001",
  "backend": "ibm_brisbane",
  "shots": 8192,
  "strategy": "Noise-Adaptive",
  "notify": true,
  "save_prediction": true
}
```

Response:
```json
{
  "job_id": "job_20260316_001",
  "status": "queued"
}
```

`GET /api/jobs/{job_id}` response:
```json
{
  "job_id": "job_20260316_001",
  "status": "running",
  "progress": 75,
  "phase": "Running on hardware",
  "submitted_at": "2026-03-16T08:32:15Z",
  "queued_at": "2026-03-16T08:32:18Z",
  "running_at": "2026-03-16T08:45:12Z",
  "estimated_done_at": "2026-03-16T09:02:00Z"
}
```

## 7. Results
`GET /api/results/{job_id}`

Response:
```json
{
  "actual_fidelity": 93.7,
  "predicted_fidelity": 94.2,
  "confidence": 95.0,
  "shots": 8192,
  "cost": 4.10,
  "execution_time_sec": 742,
  "distribution": {
    "labels": ["0000", "0001", "0010", "0011"],
    "measured": [0.04, 0.07, 0.16, 0.20],
    "ideal": [0.03, 0.08, 0.14, 0.21]
  }
}
```

## 8. Reports
`POST /api/reports/generate`

Request:
```json
{
  "job_id": "job_20260316_001",
  "format": "pdf",
  "audience": "technical",
  "sections": ["summary", "features", "prediction", "results", "comparison"],
  "notes": "Prepared for IBM Quantum validation review"
}
```

Response:
```json
{
  "report_id": "rpt_001",
  "status": "generated",
  "download_url": "/api/reports/rpt_001/file"
}
```
