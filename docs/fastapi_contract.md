# FastAPI Endpoint Contract — QTAU MATLAB Connector

This document describes the REST API endpoints consumed by the MATLAB client (`FastAPIClient.m` and service classes). The backend is a FastAPI server (default `http://34.42.87.190:5715`).

All authenticated endpoints require a `Bearer` token in the `Authorization` header and a `X-Project-Id` header for project-scoped operations.

---

## Table of Contents

1. [Authentication](#1-authentication)
2. [Projects](#2-projects)
3. [Circuits](#3-circuits)
4. [Backends](#4-backends)
5. [Benchmark](#5-benchmark)
6. [Predictions](#6-predictions)
7. [Jobs](#7-jobs)
8. [Reports](#8-reports)
9. [Settings](#9-settings)

---

## 1. Authentication

### POST /api/auth/login

Authenticate with username and password. Returns a Bearer token.

**Request** (`application/x-www-form-urlencoded`):
```
username=admin&password=secret
```

**Response** (200):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "bearer",
  "username": "admin",
  "default_project_id": "prj_001"
}
```

### GET /api/auth/me

Return the authenticated user's profile.

### POST /api/auth/logout

Invalidate the current session token.

---

## 2. Projects

### GET /api/projects

List all projects for the authenticated user. Supports pagination via `skip` and `limit` query params.

### POST /api/projects

Create a new project.

**Request**:
```json
{
  "name": "VQE H2O Optimization",
  "description": "Variational quantum eigensolver for water molecule",
  "tags": ["VQE", "chemistry"]
}
```

### GET /api/projects/{project_id}

Fetch a single project by ID.

### PATCH /api/projects/{project_id}

Update project metadata (name, description, tags).

### DELETE /api/projects/{project_id}

Delete a project and its associated data.

### GET /api/projects/{project_id}/dashboard

Aggregated dashboard data: circuit count, job status, recent activity, readiness indicators.

### GET /api/projects/{project_id}/activities

List project activity log entries.

### POST /api/projects/{project_id}/activities

Append an activity log entry.

### GET /api/projects/{project_id}/notes

Fetch project working notes (markdown).

### PUT /api/projects/{project_id}/notes

Save project working notes.

---

## 3. Circuits

### GET /api/circuits

List circuits for the active project. Paginated with `skip` (default 0) and `limit` (default 20, max 100).

**Response** (200):
```json
{
  "circuits": [
    {
      "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
      "name": "adder_n10.qasm",
      "format": "qasm2",
      "num_qubits": 10,
      "depth": 45,
      "is_valid": true,
      "category": "Arithmetic",
      "source": "QASMBench",
      "created_at": "2026-04-10T00:07:42Z"
    }
  ],
  "skip": 0,
  "limit": 20
}
```

### POST /api/circuits/upload

Upload a circuit as JSON with inline content.

**Request**:
```json
{
  "name": "bell_state_2q.qasm",
  "format": "qasm2",
  "content": "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[2];\nh q[0];\ncx q[0],q[1];\nmeasure q -> c;\n",
  "category": "Entanglement",
  "source": "QASMBench"
}
```

**Response** (200):
```json
{
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "is_valid": true,
  "validation_errors": [],
  "message": "Circuit uploaded successfully",
  "num_qubits": 2,
  "num_classical_bits": 2,
  "depth": 3,
  "single_qubit_gates": 1,
  "two_qubit_gates": 1,
  "measurement_ops": 2
}
```

**Error** (409 Conflict): Circuit with same name already exists in project.

### POST /api/circuits/upload/file

Upload a circuit as a multipart form (used by MATLAB desktop client).

**Request** (`multipart/form-data`):
- `file` — The `.qasm` file
- `name` — Circuit name (optional, defaults to filename)
- `format` — `qasm2`, `qasm3`, or `auto`
- `category` — Algorithm category (optional)
- `source` — Provenance (optional)

**Response**: Same as `POST /api/circuits/upload`.

### GET /api/circuits/{circuit_id}

Fetch full circuit details including raw content.

### PATCH /api/circuits/{circuit_id}

Update circuit metadata (name, category, source).

### DELETE /api/circuits/{circuit_id}

Delete a circuit.

### POST /api/circuits/{circuit_id}/analyze

Run feature extraction on a circuit via Qiskit. Returns structural metrics and benchmark similarity matches.

**Response** (200):
```json
{
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "num_qubits": 10,
  "depth": 45,
  "gate_counts": {"h": 5, "cx": 18, "t": 4, "measure": 10},
  "two_qubit_gate_ratio": 0.42,
  "t_count": 4,
  "features": { "...": "numerical feature vector" },
  "benchmark_matches": [
    {
      "name": "adder_n10",
      "source": "QASMBench",
      "similarity": 0.97,
      "num_qubits": 10,
      "depth": 45,
      "category": "Arithmetic",
      "notes": "Exact match from QASMBench small suite"
    }
  ]
}
```

### GET /api/circuits/{circuit_id}/analysis

Retrieve stored analysis results (no re-computation).

### GET /api/circuits/{circuit_id}/preview

Render an SVG circuit diagram via Qiskit.

**Response** (200):
```json
{
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "svg": "<svg xmlns=\"http://www.w3.org/2000/svg\" ...>...</svg>"
}
```

### POST /api/circuits/{circuit_id}/match-benchmarks

Find similar circuits in the benchmark corpus.

---

## 4. Backends

### GET /api/backends

List available IBM Quantum backends with status and calibration data.

**Response** (200):
```json
{
  "backends": [
    {
      "name": "ibm_brisbane",
      "num_qubits": 127,
      "queue_depth": 12,
      "predicted_fidelity": 0.942,
      "role": "primary",
      "operational": true,
      "status": "online",
      "queue": "short",
      "calibration_age_hours": 2.5
    }
  ]
}
```

### GET /api/backends/{backend_name}

Fetch detailed info for a single backend.

### GET /api/backends/{backend_name}/calibration

Fetch calibration data (T1, T2, gate errors, readout errors).

### GET /api/backends/{backend_name}/topology

Fetch qubit connectivity graph for visualization.

### POST /api/backends/compare

Compare multiple backends side-by-side for a given circuit.

### GET /api/projects/{project_id}/backend-selection

Fetch saved primary/backup backend selections for a project.

### POST /api/projects/{project_id}/backend-selection

Save primary/backup backend selections.

---

## 5. Benchmark

### POST /api/projects/{project_id}/benchmark-config

Configure benchmark execution parameters.

**Request**:
```json
{
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "backend_name": "ibm_brisbane",
  "shots": 8192,
  "optimization_level": 3,
  "error_mitigation": "readout",
  "transpilation_strategy": "sabre"
}
```

**Response** (200):
```json
{
  "project_id": "prj_001",
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "backend_name": "ibm_brisbane",
  "shots": 8192,
  "optimization_level": 3,
  "error_mitigation": "readout",
  "transpilation_strategy": "sabre",
  "status": "configured",
  "cost_estimate_credits": 4.10,
  "estimated_queue_minutes": 12,
  "estimated_runtime_seconds": 45,
  "recommended_strategy": "sabre",
  "suggested_qubit_layout": "linear [0,1,2,...,9]"
}
```

### GET /api/projects/{project_id}/benchmark-config

Retrieve saved benchmark configuration.

### POST /api/projects/{project_id}/benchmark-config/compare-strategies

Compare transpilation strategies (fidelity, depth, gate count).

### GET /api/benchmark/volumetric

Volumetric benchmark data (width vs depth vs fidelity).

**Response** (200):
```json
{
  "project_id": "prj_001",
  "data_points": [
    {
      "width": 5,
      "depth": 10,
      "fidelity": 0.95,
      "circuit_id": "...",
      "circuit_name": "qft_n4",
      "source": "prediction"
    }
  ],
  "qv_boundary": 32,
  "max_width": 127,
  "max_depth": 500
}
```

### GET /api/benchmark/system-metrics/{backend_name}

System-level performance metrics for a backend.

### GET /api/benchmark/scorecard

Backend ranking scorecard.

### GET /api/benchmark/regression

Fidelity regression analysis over time.

### GET /api/benchmark/classify/{circuit_id}

Classify a circuit against known benchmark families.

### GET /api/benchmark/prediction-calibration

Compare predicted vs actual fidelity across runs.

---

## 6. Predictions

### POST /api/predict

Request fidelity predictions for a circuit across one or more backends.

**Request**:
```json
{
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "backend_names": ["ibm_brisbane", "ibm_sherbrooke"],
  "shots": 8192,
  "optimization_level": 3
}
```

**Response** (200):
```json
{
  "prediction_id": "pred_001",
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "top_backend": "ibm_brisbane",
  "expected_success_probability": 0.942,
  "expected_queue_time_range": "10-15 min",
  "probability_distribution": {"0000": 0.48, "1111": 0.47, "...": "..."},
  "error_budget_breakdown": {"gate": 0.63, "readout": 0.22, "decoherence": 0.12, "crosstalk": 0.03},
  "backend_predictions": [
    {
      "backend_name": "ibm_brisbane",
      "predicted_fidelity": 0.942,
      "confidence": 0.93,
      "confidence_interval": [0.929, 0.959],
      "estimated_runtime_ms": 742000,
      "estimated_cost": 4.10,
      "risk_score": 0.08,
      "rank": 1
    }
  ],
  "created_at": "2026-04-10T08:32:15Z"
}
```

### GET /api/predict/{prediction_id}

Retrieve a stored prediction by ID.

### POST /api/projects/{project_id}/predict

Create a prediction scoped to a project.

### GET /api/projects/{project_id}/predict/latest

Retrieve the most recent prediction for a project.

### POST /api/optimize

Run circuit optimization (routing, decomposition) for a given backend.

---

## 7. Jobs

### POST /api/projects/{project_id}/jobs

Submit a quantum job for execution.

**Request**:
```json
{
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "backend_name": "ibm_brisbane",
  "shots": 8192,
  "optimization_level": 3,
  "error_mitigation": "readout"
}
```

**Response** (200):
```json
{
  "job_record_id": "job_001",
  "ibm_job_id": "crgn4d5g1t...",
  "status": "queued",
  "message": "Job submitted successfully"
}
```

### GET /api/projects/{project_id}/jobs

List jobs for a project. Paginated with `skip` and `limit`.

### GET /api/jobs

List all jobs (admin view). Paginated.

### GET /api/jobs/{job_record_id}

Fetch full job details.

### GET /api/jobs/{job_record_id}/status

Poll job status (queued, running, completed, failed, cancelled).

**Response** (200):
```json
{
  "job_record_id": "job_001",
  "status": "running",
  "progress": 75,
  "phase": "Running on hardware",
  "submitted_at": "2026-04-10T08:32:15Z",
  "running_at": "2026-04-10T08:45:12Z",
  "estimated_done_at": "2026-04-10T09:02:00Z"
}
```

### POST /api/jobs/{job_record_id}/cancel

Cancel a queued or running job.

### POST /api/jobs/{job_record_id}/pause

Pause a running job.

### GET /api/jobs/{job_record_id}/results

Fetch job execution results.

**Response** (200):
```json
{
  "actual_fidelity": 0.937,
  "predicted_fidelity": 0.942,
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

### GET /api/jobs/{job_record_id}/results/detailed

Extended results with per-qubit metrics.

### GET /api/jobs/{job_record_id}/error-trends

Error rate trends over time for a job's backend.

### GET /api/jobs/{job_record_id}/rb-decay

Randomized benchmarking decay curve data.

---

## 8. Reports

### POST /api/reports/generate

Generate a report from job/prediction data.

**Request**:
```json
{
  "title": "VQE H2O Experiment Report",
  "report_type": "technical",
  "format": "pdf",
  "circuit_id": "64e18caa-bd7f-4361-b434-f0dcb05944d6",
  "prediction_id": "pred_001",
  "job_record_id": "job_001",
  "sections": ["summary", "features", "prediction", "results", "comparison"],
  "notes": "Prepared for IBM Quantum validation review"
}
```

**Response** (200):
```json
{
  "report_id": "rpt_001",
  "status": "ready",
  "message": "Report generated successfully"
}
```

### GET /api/reports

List all reports. Paginated.

### GET /api/projects/{project_id}/reports

List reports for a specific project.

### POST /api/projects/{project_id}/reports

Generate a project-scoped report.

### GET /api/reports/{report_id}

Fetch report metadata.

### GET /api/reports/{report_id}/download

Download the generated report file (PDF/HTML).

### POST /api/reports/{report_id}/share

Share a report via email or link.

---

## 9. Settings

### GET /api/settings

Fetch global application settings.

### POST /api/settings

Save user settings.

**Request**:
```json
{
  "default_shots": 4096,
  "default_optimization": 2,
  "email_notifications": true,
  "notification_mode": "in_app",
  "ibm_account_email": "user@example.com",
  "default_backend_family": "ibm_eagle"
}
```

**Response** (200):
```json
{
  "status": "saved",
  "updated_at": "2026-04-10T12:00:00Z"
}
```

### GET /api/settings/preferences

Fetch user-specific preferences.

### POST /api/settings/verify-ibm

Verify IBM Quantum account credentials/token.

### DELETE /api/settings/cache

Clear cached results and calibration data.

---

## Endpoint Summary

| Category | Endpoints | Methods |
|---|---|---|
| Authentication | 3 | POST, GET |
| Projects | 12 | GET, POST, PATCH, PUT, DELETE |
| Circuits | 10 | GET, POST, PATCH, DELETE |
| Backends | 7 | GET, POST |
| Benchmark | 8 | GET, POST |
| Predictions | 5 | GET, POST |
| Jobs | 11 | GET, POST |
| Reports | 7 | GET, POST |
| Settings | 5 | GET, POST, DELETE |
| **Total** | **68** | |

For the full OpenAPI 3.0 specification, see [`openapi.json`](openapi.json).
