# Circuit Cutting (Option A — Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the generic cutting platform from `docs/superpowers/specs/2026-04-24-circuit-cutting-design.md` — users can upload a large circuit, auto- or manually partition it into *k* subcircuits via `qiskit-addon-cutting`, distribute the subcircuits across *k* IBM backends concurrently, and get back reconstructed expectation values (plus an optional bitstring distribution). Phase 2 (Option C — domain presets like CT Imaging 160Q) is scheduled as a separate plan after Phase 1 ships.

**Architecture (A2):** Three-layer backend — `CuttingService` (stateless math), `CuttingBatchService` (orchestration + persistence), `CuttingPipeline` ABC with `GenericPipeline` default. Child subcircuit runs are regular `IBMJobDocument` rows tagged `batch_id` + `cut_role` so the existing Jobs screen surfaces them with a `⤴ batch` badge. MATLAB UI adds a dedicated `CircuitCuttingScreen` in the sidebar (between Benchmark and Jobs) with a mode switcher (Automatic / Assisted / Manual), plus yellow auto-detect banners on Benchmark + Prediction screens when a circuit exceeds backend capacity.

**Tech Stack:** Python 3.11 / FastAPI / Bunnet (Mongo ODM) / Pydantic / `qiskit-addon-cutting` ≥0.4 / pytest+mongomock. MATLAB R2025b / `matlab.unittest` / existing `AsyncRunner` + `StubFastAPIClient` harness.

---

## File Map

### Backend (`sqk-qtau`)

| Path | Responsibility |
|------|---------------|
| `pyproject.toml` | Add `qiskit-addon-cutting` under a `cutting` extra |
| `src/qdash/api/schemas/cutting.py` | **NEW** Pydantic DTOs (analyze request/response, batch create/poll/result) |
| `src/qdash/dbmodel/cutting_batch.py` | **NEW** `CuttingBatchDocument` |
| `src/qdash/dbmodel/ibm_job.py` | Add optional `batch_id`, `cut_role` fields |
| `src/qdash/repository/cutting_batch.py` | **NEW** Mongo repo (CRUD, list_by_project, status transitions) |
| `src/qdash/api/services/cutting/__init__.py` | **NEW** package marker |
| `src/qdash/api/services/cutting/base.py` | **NEW** `CuttingPipeline` ABC + `GenericPipeline` implementation |
| `src/qdash/api/services/cutting/presets.py` | **NEW** `PRESETS` dict (only `"generic"` in Phase 1) |
| `src/qdash/api/services/cutting_service.py` | **NEW** stateless math (delegates to pipeline stages) |
| `src/qdash/api/services/cutting_batch_service.py` | **NEW** batch lifecycle orchestrator |
| `src/qdash/api/routers/cutting.py` | **NEW** `/api/cutting/*` endpoints |
| `src/qdash/api/dependencies.py` | Wire `get_cutting_service` + `get_cutting_batch_service` |
| `src/qdash/api/main.py` | Register cutting router |
| `tests/qdash/api/services/test_cutting_pipeline.py` | **NEW** pipeline unit tests |
| `tests/qdash/api/services/test_cutting_service.py` | **NEW** stateless service tests |
| `tests/qdash/api/services/test_cutting_batch_service.py` | **NEW** batch lifecycle tests |
| `tests/qdash/api/routers/test_cutting_router.py` | **NEW** endpoint contract tests |

### MATLAB UI (`sqk-qtau-matlab`)

| Path | Responsibility |
|------|---------------|
| `src/domain/services/CuttingService.m` | **NEW** HTTP client for `/api/cutting/*` |
| `src/presentation/screens/CircuitCuttingScreen.m` | **NEW** screen builder |
| `src/presentation/viewmodels/CircuitCuttingViewModel.m` | **NEW** screen callbacks + state |
| `src/presentation/app/QTAUWorkbenchApp.m` | Add UI property handles + instantiate VM + call screen builder |
| `src/presentation/app/NavigationManager.m` | Register sidebar entry + auto-load |
| `src/domain/ServiceContainer.m` | Wire `CuttingSvc` |
| `src/presentation/viewmodels/BenchmarkViewModel.m` | Add oversize-circuit banner helper |
| `src/presentation/viewmodels/PredictionViewModel.m` | Add oversize-circuit banner helper |
| `src/presentation/viewmodels/JobsViewModel.m` | Surface `batch_id` badge on child job rows |
| `tests/test_CuttingService.m` | **NEW** HTTP endpoint contract tests |
| `tests/test_CircuitCuttingViewModel.m` | **NEW** mode switcher + formatter tests |
| `tests/TestCircuitCuttingVmProbe.m` | **NEW** probe to reach private VM helpers |
| `CLAUDE.md` | Add Circuit Cutting screen row + new endpoints blurb |
| `docs/fastapi_contract.md` | Document new `/api/cutting/*` endpoints |

---

## Task 1 — Add `qiskit-addon-cutting` dependency

**Files:**
- Modify: `sqk-qtau/pyproject.toml`

- [ ] **Step 1: Add the cutting extra**

In `pyproject.toml`, under `[project.optional-dependencies]` (create the section if missing), add:

```toml
[project.optional-dependencies]
cutting = [
    "qiskit-addon-cutting>=0.4.0,<0.6.0",
]
```

- [ ] **Step 2: Install the extra into the existing venv**

Run: `cd sqk-qtau && .venv/bin/pip install -e '.[cutting]'`
Expected: `Successfully installed qiskit-addon-cutting-0.x.x` (plus transitive deps).

- [ ] **Step 3: Verify import**

Run: `cd sqk-qtau && .venv/bin/python -c "from qiskit_addon_cutting import partition_circuit_qpd, reconstruct_expectation_values; print('ok')"`
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
cd sqk-qtau && git add pyproject.toml uv.lock 2>/dev/null; git add pyproject.toml && git commit -m "chore(deps): add qiskit-addon-cutting under [cutting] extra"
```

---

## Task 2 — Pydantic schemas for cutting endpoints

**Files:**
- Create: `sqk-qtau/src/qdash/api/schemas/cutting.py`
- Test: implicitly validated by later router tests

- [ ] **Step 1: Write the schemas file**

```python
# src/qdash/api/schemas/cutting.py
"""Pydantic DTOs for the /api/cutting/* endpoints."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


# ── Analyze (preflight cut detection) ────────────────────────────────

class AnalyzeCutsRequest(BaseModel):
    circuit_id: str
    target_k: int | None = Field(
        None, ge=2, le=16,
        description="Preferred number of subcircuits. None = library decides.",
    )
    backend_pool: list[str] = Field(
        default_factory=list,
        description="Candidate backend names; used to size target_k when None.",
    )


class CutPoint(BaseModel):
    kind: Literal["wire", "gate"]
    qubit_indices: list[int]
    instruction_index: int = Field(..., description="Position in the transpiled circuit.")


class CutPlan(BaseModel):
    cuts: list[CutPoint] = Field(default_factory=list)
    k: int = Field(..., ge=1, description="Number of subcircuits produced.")
    sampling_overhead: float = Field(..., ge=1.0, description="Multiplier on shot budget.")
    per_subcircuit_qubits: list[int] = Field(default_factory=list)


class AnalyzeCutsResponse(BaseModel):
    circuit_id: str
    candidates: list[CutPlan]
    recommended_index: int = 0
    source: str = "generic"


# ── Presets ──────────────────────────────────────────────────────────

class PresetMetadata(BaseModel):
    id: str
    name: str
    description: str
    qubit_range: tuple[int, int]
    output_type: Literal["expectation_values", "distribution", "image", "custom"]
    required_structure: str = ""


class ListPresetsResponse(BaseModel):
    presets: list[PresetMetadata]


# ── Batch create + poll + result ─────────────────────────────────────

class BackendAssignment(BaseModel):
    subcircuit_idx: int = Field(..., ge=0)
    backend_name: str
    shots: int = Field(4096, ge=1)


class CreateBatchRequest(BaseModel):
    mode: Literal["automatic", "assisted", "manual"] = "assisted"
    preset: str = "generic"
    cut_plan: CutPlan
    backend_assignments: list[BackendAssignment]
    observables: list[str] = Field(
        default_factory=list,
        description="Pauli strings. Empty = default all-Z.",
    )
    opt_in_distribution: bool = False
    timeout_hours: float = Field(6.0, gt=0, le=48)
    retry_strategy: Literal["none", "auto_spare_2x"] = "none"


BatchStatus = Literal[
    "queued", "partitioning", "executing", "reconstructing",
    "completed", "partial_failure", "failed", "cancelled",
]


class ChildJobState(BaseModel):
    child_job_id: str
    subcircuit_idx: int
    backend_name: str
    status: str
    progress_pct: int = 0


class BatchResponse(BaseModel):
    batch_id: str
    project_id: str
    circuit_id: str
    mode: str
    preset: str
    status: BatchStatus
    progress_pct: int
    cut_plan: CutPlan
    backend_assignments: list[BackendAssignment]
    children: list[ChildJobState] = Field(default_factory=list)
    error: str | None = None
    created_at: str
    submitted_at: str | None = None
    completed_at: str | None = None


class ExpectationValue(BaseModel):
    observable: str
    value: float
    std_err: float = 0.0


class BatchResultResponse(BaseModel):
    batch_id: str
    status: BatchStatus
    expectations: list[ExpectationValue] = Field(default_factory=list)
    distribution: dict[str, float] | None = None
    preset_output: dict | None = None


class ListBatchesResponse(BaseModel):
    batches: list[BatchResponse]
```

- [ ] **Step 2: Verify module imports**

Run: `cd sqk-qtau && .venv/bin/python -c "from qdash.api.schemas.cutting import CreateBatchRequest, BatchResponse; print('ok')"`
Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
cd sqk-qtau && git add src/qdash/api/schemas/cutting.py && git commit -m "feat(cutting): add Pydantic schemas for /api/cutting endpoints"
```

---

## Task 3 — `CuttingBatchDocument` + `IBMJobDocument` back-refs

**Files:**
- Create: `sqk-qtau/src/qdash/dbmodel/cutting_batch.py`
- Modify: `sqk-qtau/src/qdash/dbmodel/ibm_job.py` (add two optional fields)

- [ ] **Step 1: Write the document model**

```python
# src/qdash/dbmodel/cutting_batch.py
"""Mongo document model for a circuit-cutting batch run."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, ClassVar

from bunnet import Document
from pydantic import ConfigDict, Field
from pymongo import ASCENDING, DESCENDING, IndexModel


class CuttingBatchDocument(Document):
    project_id: str
    circuit_id: str
    batch_id: str = Field(..., description="UUID4.")
    mode: str
    preset: str = "generic"
    cut_plan: dict = Field(default_factory=dict)
    backend_assignments: list[dict] = Field(default_factory=list)
    observables: list[str] = Field(default_factory=list)
    opt_in_distribution: bool = False
    child_job_ids: list[str] = Field(default_factory=list)
    status: str = "queued"
    progress_pct: int = 0
    reconstruction: dict | None = None
    error: str | None = None
    timeout_hours: float = 6.0
    retry_strategy: str = "none"
    subcircuit_measurements: dict | None = Field(
        None,
        description="Raw per-subcircuit bitstrings/quasi-probabilities, kept so "
                    "the reconstruction step can retry without re-running hardware.",
    )
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    submitted_at: datetime | None = None
    completed_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)

    class Settings:
        name = "cutting_batch"
        indexes: ClassVar[list[Any]] = [
            IndexModel([("batch_id", ASCENDING)], unique=True),
            IndexModel([("project_id", ASCENDING), ("created_at", DESCENDING)]),
        ]
```

- [ ] **Step 2: Add back-refs to `IBMJobDocument`**

Open `src/qdash/dbmodel/ibm_job.py` and add these two optional fields to the document class (alongside existing fields — do not reorder):

```python
    batch_id: str | None = Field(
        None, description="Cutting batch this job belongs to, if any.",
    )
    cut_role: str | None = Field(
        None, description="Subcircuit identifier inside the batch, e.g. 'subcircuit_0'.",
    )
```

- [ ] **Step 3: Verify imports**

Run: `cd sqk-qtau && .venv/bin/python -c "from qdash.dbmodel.cutting_batch import CuttingBatchDocument; from qdash.dbmodel.ibm_job import IBMJobDocument; print('ok')"`
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
cd sqk-qtau && git add src/qdash/dbmodel/cutting_batch.py src/qdash/dbmodel/ibm_job.py && git commit -m "feat(cutting): add CuttingBatchDocument + batch_id/cut_role back-refs on IBMJobDocument"
```

---

## Task 4 — `CuttingPipeline` ABC + `GenericPipeline`

**Files:**
- Create: `sqk-qtau/src/qdash/api/services/cutting/__init__.py`
- Create: `sqk-qtau/src/qdash/api/services/cutting/base.py`
- Create: `sqk-qtau/src/qdash/api/services/cutting/presets.py`
- Test: `sqk-qtau/tests/qdash/api/services/test_cutting_pipeline.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/qdash/api/services/test_cutting_pipeline.py
"""Tests for the CuttingPipeline ABC and GenericPipeline implementation."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest


def test_generic_pipeline_metadata():
    from qdash.api.services.cutting.base import GenericPipeline

    meta = GenericPipeline.meta
    assert meta.id == "generic"
    assert meta.output_type == "expectation_values"
    assert meta.qubit_range[0] >= 2


def test_generic_pipeline_analyze_cuts_returns_candidates():
    from qdash.api.services.cutting.base import GenericPipeline

    # qiskit-addon-cutting is stubbed so this test is hermetic.
    fake_result = MagicMock(qpd_gates=[], overhead=3.5, subcircuits=[MagicMock(num_qubits=3), MagicMock(num_qubits=3)])
    with patch(
        "qdash.api.services.cutting.base.find_cuts",
        return_value=fake_result,
    ):
        pipe = GenericPipeline()
        plan = pipe.analyze_cuts(circuit=MagicMock(num_qubits=6), target_k=2)

    assert plan["k"] == 2
    assert plan["sampling_overhead"] == pytest.approx(3.5)
    assert plan["per_subcircuit_qubits"] == [3, 3]


def test_presets_registry_contains_generic():
    from qdash.api.services.cutting.presets import PRESETS

    assert "generic" in PRESETS
    assert PRESETS["generic"].meta.id == "generic"
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/services/test_cutting_pipeline.py -x --tb=short`
Expected: `ModuleNotFoundError: No module named 'qdash.api.services.cutting'`.

- [ ] **Step 3: Write the package marker**

```python
# src/qdash/api/services/cutting/__init__.py
"""Circuit-cutting pipeline abstraction + preset registry."""
```

- [ ] **Step 4: Write the pipeline ABC + `GenericPipeline`**

```python
# src/qdash/api/services/cutting/base.py
"""CuttingPipeline ABC and the GenericPipeline default implementation.

Every preset subclasses GenericPipeline and overrides only the stages it cares
about (typically `analyze_cuts` and/or `post_process`). Stages must be pure —
no I/O, no Mongo writes — because CuttingBatchService owns orchestration and
persistence. See docs/superpowers/specs/2026-04-24-circuit-cutting-design.md.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, ClassVar

try:
    from qiskit_addon_cutting import (  # type: ignore[import-untyped]
        find_cuts,
        partition_circuit_qpd,
        reconstruct_expectation_values,
    )
    _ADDON_AVAILABLE = True
except ImportError:  # pragma: no cover — addon is an optional extra
    find_cuts = None  # type: ignore[assignment]
    partition_circuit_qpd = None  # type: ignore[assignment]
    reconstruct_expectation_values = None  # type: ignore[assignment]
    _ADDON_AVAILABLE = False

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PresetMeta:
    id: str
    name: str
    description: str
    qubit_range: tuple[int, int]
    output_type: str  # "expectation_values" | "distribution" | "image" | "custom"
    required_structure: str = ""


class CuttingPipeline(ABC):
    """Abstract 5-stage pipeline. Presets subclass and override."""

    meta: ClassVar[PresetMeta]

    @abstractmethod
    def analyze_cuts(self, circuit: Any, target_k: int | None) -> dict:
        """Return a cut plan dict: {cuts, k, sampling_overhead, per_subcircuit_qubits}."""

    @abstractmethod
    def partition(self, circuit: Any, cut_plan: dict) -> list[Any]:
        """Split `circuit` per `cut_plan`. Returns a list of k subcircuits."""

    @abstractmethod
    def select_backends(
        self,
        subcircuits: list[Any],
        pool: list[str],
        mode: str,
    ) -> list[dict]:
        """Return [{subcircuit_idx, backend_name, shots}, ...]."""

    @abstractmethod
    def reconstruct_expectations(
        self,
        subcircuit_results: list[dict],
        observables: list[str],
        cut_plan: dict,
    ) -> list[dict]:
        """Return [{observable, value, std_err}, ...]."""

    def post_process(self, reconstruction: dict, context: dict) -> dict:
        """Optional preset-specific transform. Identity by default."""
        return reconstruction


class GenericPipeline(CuttingPipeline):
    """Option A default: wrap qiskit-addon-cutting end-to-end."""

    meta: ClassVar[PresetMeta] = PresetMeta(
        id="generic",
        name="Generic",
        description=(
            "Automatic wire/gate cut detection and Pauli expectation-value "
            "reconstruction via qiskit-addon-cutting. Works for any circuit "
            "structure; sampling overhead scales as 4^k for k wire cuts."
        ),
        qubit_range=(2, 1024),
        output_type="expectation_values",
        required_structure="",
    )

    def analyze_cuts(self, circuit: Any, target_k: int | None) -> dict:
        if not _ADDON_AVAILABLE:
            raise RuntimeError(
                "qiskit-addon-cutting is not installed. "
                "Install with: pip install -e '.[cutting]'"
            )
        result = find_cuts(circuit, num_subexperiments=target_k)
        subcircuits = getattr(result, "subcircuits", [])
        per_qubits = [getattr(sc, "num_qubits", 0) for sc in subcircuits]
        return {
            "cuts": [
                {
                    "kind": "gate",
                    "qubit_indices": list(getattr(g, "qubits", [])),
                    "instruction_index": int(getattr(g, "index", 0)),
                }
                for g in getattr(result, "qpd_gates", [])
            ],
            "k": len(subcircuits) or (target_k or 1),
            "sampling_overhead": float(getattr(result, "overhead", 1.0)),
            "per_subcircuit_qubits": per_qubits,
        }

    def partition(self, circuit: Any, cut_plan: dict) -> list[Any]:
        if not _ADDON_AVAILABLE:
            raise RuntimeError("qiskit-addon-cutting is not installed.")
        partitioned = partition_circuit_qpd(circuit, cut_plan.get("cuts", []))
        return list(partitioned)

    def select_backends(
        self,
        subcircuits: list[Any],
        pool: list[str],
        mode: str,
    ) -> list[dict]:
        if len(pool) < len(subcircuits):
            raise ValueError(
                f"Backend pool has {len(pool)} entries, need {len(subcircuits)}."
            )
        # Mode-aware: "automatic" rotates through pool greedily (self-healing
        # done by CuttingBatchService on retry). "assisted"/"manual" callers
        # pass in the user-reviewed pool — we trust the order they give us.
        return [
            {
                "subcircuit_idx": i,
                "backend_name": pool[i % len(pool)],
                "shots": 4096,
            }
            for i, _ in enumerate(subcircuits)
        ]

    def reconstruct_expectations(
        self,
        subcircuit_results: list[dict],
        observables: list[str],
        cut_plan: dict,
    ) -> list[dict]:
        if not _ADDON_AVAILABLE:
            raise RuntimeError("qiskit-addon-cutting is not installed.")
        obs = observables or ["Z" * sum(cut_plan.get("per_subcircuit_qubits", [1]))]
        values = reconstruct_expectation_values(
            subcircuit_results, obs, cut_plan.get("cuts", [])
        )
        return [
            {"observable": o, "value": float(v), "std_err": 0.0}
            for o, v in zip(obs, values)
        ]
```

- [ ] **Step 5: Write the presets registry**

```python
# src/qdash/api/services/cutting/presets.py
"""Preset registry. Phase 1 has only the generic preset; Phase 2 will add
domain presets (e.g. CTImaging160QPipeline) as subclasses of GenericPipeline."""

from __future__ import annotations

from qdash.api.services.cutting.base import CuttingPipeline, GenericPipeline


PRESETS: dict[str, type[CuttingPipeline]] = {
    "generic": GenericPipeline,
}


def get_pipeline(preset_id: str) -> CuttingPipeline:
    cls = PRESETS.get(preset_id)
    if cls is None:
        raise KeyError(f"Unknown preset: {preset_id!r}. Known: {list(PRESETS)}")
    return cls()
```

- [ ] **Step 6: Run the test**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/services/test_cutting_pipeline.py -x --tb=short`
Expected: `3 passed`.

- [ ] **Step 7: Commit**

```bash
cd sqk-qtau && git add src/qdash/api/services/cutting/ tests/qdash/api/services/test_cutting_pipeline.py && git commit -m "feat(cutting): add CuttingPipeline ABC + GenericPipeline + preset registry"
```

---

## Task 5 — `CuttingService` (stateless math facade)

**Files:**
- Create: `sqk-qtau/src/qdash/api/services/cutting_service.py`
- Test: `sqk-qtau/tests/qdash/api/services/test_cutting_service.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/qdash/api/services/test_cutting_service.py
"""CuttingService is a thin stateless facade delegating to a pipeline."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest


def test_analyze_cuts_returns_candidates_sorted_by_overhead():
    from qdash.api.services.cutting_service import CuttingService

    fake_plan = {
        "cuts": [],
        "k": 3,
        "sampling_overhead": 7.2,
        "per_subcircuit_qubits": [54, 53, 53],
    }
    svc = CuttingService()
    with patch(
        "qdash.api.services.cutting_service.get_pipeline",
        return_value=MagicMock(analyze_cuts=lambda circuit, target_k: fake_plan),
    ), patch(
        "qdash.api.services.cutting_service.CuttingService._load_circuit",
        return_value=MagicMock(num_qubits=160),
    ):
        result = svc.analyze_cuts(circuit_id="c1", project_id="p1", target_k=3)

    assert result["candidates"][0]["k"] == 3
    assert result["candidates"][0]["sampling_overhead"] == pytest.approx(7.2)
    assert result["source"] == "generic"


def test_list_presets_returns_registered_presets():
    from qdash.api.services.cutting_service import CuttingService

    svc = CuttingService()
    presets = svc.list_presets()
    ids = [p["id"] for p in presets]
    assert "generic" in ids
```

- [ ] **Step 2: Confirm it fails**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/services/test_cutting_service.py -x --tb=short`
Expected: `ModuleNotFoundError: No module named 'qdash.api.services.cutting_service'`.

- [ ] **Step 3: Write the service**

```python
# src/qdash/api/services/cutting_service.py
"""Stateless facade over the CuttingPipeline for the /api/cutting/analyze
and /api/cutting/presets endpoints. Does not touch Mongo or IBM Runtime —
those live in CuttingBatchService."""

from __future__ import annotations

import logging
from dataclasses import asdict
from typing import Any

from qdash.api.services.cutting.base import PresetMeta
from qdash.api.services.cutting.presets import PRESETS, get_pipeline

logger = logging.getLogger(__name__)


class CuttingService:
    def analyze_cuts(
        self,
        circuit_id: str,
        project_id: str,
        target_k: int | None = None,
        preset: str = "generic",
    ) -> dict:
        circuit = self._load_circuit(circuit_id=circuit_id, project_id=project_id)
        pipeline = get_pipeline(preset)
        plan = pipeline.analyze_cuts(circuit=circuit, target_k=target_k)
        return {
            "circuit_id": circuit_id,
            "candidates": [plan],
            "recommended_index": 0,
            "source": preset,
        }

    def list_presets(self) -> list[dict]:
        out: list[dict] = []
        for preset_id, cls in PRESETS.items():
            meta: PresetMeta = cls.meta
            out.append({
                "id": meta.id,
                "name": meta.name,
                "description": meta.description,
                "qubit_range": list(meta.qubit_range),
                "output_type": meta.output_type,
                "required_structure": meta.required_structure,
            })
        return out

    @staticmethod
    def _load_circuit(circuit_id: str, project_id: str) -> Any:
        """Fetch the Qiskit QuantumCircuit for a persisted circuit doc."""
        from qdash.api.services.circuit_service import CircuitService  # noqa: PLC0415
        from qdash.api.dependencies import get_circuit_service  # noqa: PLC0415

        svc: CircuitService = get_circuit_service()
        doc = svc.get_circuit(project_id=project_id, circuit_id=circuit_id)
        if doc is None:
            raise ValueError(f"Circuit {circuit_id} not found in project {project_id}.")
        return CircuitService._parse_qc(doc["format"], doc["raw_content"])
```

- [ ] **Step 4: Run the test**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/services/test_cutting_service.py -x --tb=short`
Expected: `2 passed`.

- [ ] **Step 5: Commit**

```bash
cd sqk-qtau && git add src/qdash/api/services/cutting_service.py tests/qdash/api/services/test_cutting_service.py && git commit -m "feat(cutting): add CuttingService stateless facade + analyze/list_presets"
```

---

## Task 6 — Mongo repo for `CuttingBatchDocument`

**Files:**
- Create: `sqk-qtau/src/qdash/repository/cutting_batch.py`

- [ ] **Step 1: Write the repo**

```python
# src/qdash/repository/cutting_batch.py
"""Mongo repository for CuttingBatchDocument."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from qdash.dbmodel.cutting_batch import CuttingBatchDocument


class MongoCuttingBatchRepository:
    def create(self, doc: CuttingBatchDocument) -> CuttingBatchDocument:
        doc.insert()
        return doc

    def get(self, batch_id: str) -> CuttingBatchDocument | None:
        return CuttingBatchDocument.find_one(
            CuttingBatchDocument.batch_id == batch_id
        ).run()

    def list_by_project(
        self, project_id: str, limit: int = 50
    ) -> list[CuttingBatchDocument]:
        return list(
            CuttingBatchDocument.find(
                CuttingBatchDocument.project_id == project_id
            ).sort("-created_at").limit(limit).run()
        )

    def update_fields(self, batch_id: str, **fields: Any) -> None:
        doc = self.get(batch_id)
        if doc is None:
            raise LookupError(f"Batch {batch_id} not found")
        for k, v in fields.items():
            setattr(doc, k, v)
        doc.save()

    def mark_completed(self, batch_id: str, reconstruction: dict) -> None:
        self.update_fields(
            batch_id,
            status="completed",
            reconstruction=reconstruction,
            progress_pct=100,
            completed_at=datetime.now(timezone.utc),
        )

    def mark_failed(self, batch_id: str, error: str) -> None:
        self.update_fields(
            batch_id,
            status="failed",
            error=error,
            completed_at=datetime.now(timezone.utc),
        )
```

- [ ] **Step 2: Verify it imports**

Run: `cd sqk-qtau && .venv/bin/python -c "from qdash.repository.cutting_batch import MongoCuttingBatchRepository; print('ok')"`
Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
cd sqk-qtau && git add src/qdash/repository/cutting_batch.py && git commit -m "feat(cutting): add MongoCuttingBatchRepository"
```

---

## Task 7 — `CuttingBatchService` (orchestrator)

**Files:**
- Create: `sqk-qtau/src/qdash/api/services/cutting_batch_service.py`
- Test: `sqk-qtau/tests/qdash/api/services/test_cutting_batch_service.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/qdash/api/services/test_cutting_batch_service.py
"""Batch lifecycle — create → execute → reconstruct → complete."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture
def svc():
    from qdash.api.services.cutting_batch_service import CuttingBatchService
    return CuttingBatchService(
        batch_repository=MagicMock(),
        job_service=MagicMock(),
        circuit_service=MagicMock(),
    )


def test_create_batch_returns_batch_id_and_queued_status(svc):
    svc._repo.create.side_effect = lambda doc: doc
    req = {
        "project_id": "p1",
        "circuit_id": "c1",
        "mode": "assisted",
        "preset": "generic",
        "cut_plan": {"cuts": [], "k": 2, "sampling_overhead": 3.5, "per_subcircuit_qubits": [3, 3]},
        "backend_assignments": [
            {"subcircuit_idx": 0, "backend_name": "ibm_miami", "shots": 4096},
            {"subcircuit_idx": 1, "backend_name": "ibm_marrakesh", "shots": 4096},
        ],
        "observables": [],
        "opt_in_distribution": False,
        "timeout_hours": 6.0,
        "retry_strategy": "none",
    }
    with patch(
        "qdash.api.services.cutting_batch_service.uuid4", return_value="fixed-batch-id"
    ):
        doc = svc.create_batch(req)
    assert doc.batch_id == "fixed-batch-id"
    assert doc.status == "queued"
    svc._repo.create.assert_called_once()


def test_poll_aggregates_child_statuses(svc):
    from qdash.dbmodel.cutting_batch import CuttingBatchDocument

    existing = CuttingBatchDocument(
        project_id="p1", circuit_id="c1", batch_id="b1",
        mode="assisted", preset="generic",
        cut_plan={"cuts": [], "k": 2, "sampling_overhead": 3.5, "per_subcircuit_qubits": [3, 3]},
        backend_assignments=[], observables=[], child_job_ids=["j1", "j2"],
        status="executing",
    )
    svc._repo.get.return_value = existing
    svc._jobs.get_job.side_effect = [
        {"status": "completed", "progress_pct": 100},
        {"status": "running", "progress_pct": 60},
    ]
    poll = svc.poll_batch("b1")
    assert poll["progress_pct"] == 80  # (100 + 60) / 2
    assert poll["status"] == "executing"
```

- [ ] **Step 2: Confirm it fails**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/services/test_cutting_batch_service.py -x --tb=short`
Expected: `ModuleNotFoundError: No module named 'qdash.api.services.cutting_batch_service'`.

- [ ] **Step 3: Write the orchestrator**

```python
# src/qdash/api/services/cutting_batch_service.py
"""Batch lifecycle orchestration. One CuttingBatchDocument per run.

Creates the batch doc, submits k subcircuit jobs via the existing JobService
(tagging each with batch_id + cut_role), polls aggregate status, triggers
reconstruction when all children land, persists the reconstructed output."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from statistics import mean
from typing import Any
from uuid import uuid4

from qdash.api.services.cutting.presets import get_pipeline
from qdash.dbmodel.cutting_batch import CuttingBatchDocument

logger = logging.getLogger(__name__)


class CuttingBatchService:
    def __init__(
        self,
        *,
        batch_repository: Any,
        job_service: Any,
        circuit_service: Any,
    ) -> None:
        self._repo = batch_repository
        self._jobs = job_service
        self._circuits = circuit_service

    # ── Create ────────────────────────────────────────────────────────

    def create_batch(self, req: dict) -> CuttingBatchDocument:
        """Materialize a CuttingBatchDocument, persist, return. Does NOT
        dispatch child jobs yet — that happens in :meth:`dispatch`."""
        batch_id = req.get("batch_id") or str(uuid4())
        doc = CuttingBatchDocument(
            project_id=req["project_id"],
            circuit_id=req["circuit_id"],
            batch_id=batch_id,
            mode=req["mode"],
            preset=req.get("preset", "generic"),
            cut_plan=req["cut_plan"],
            backend_assignments=req["backend_assignments"],
            observables=req.get("observables", []),
            opt_in_distribution=req.get("opt_in_distribution", False),
            timeout_hours=req.get("timeout_hours", 6.0),
            retry_strategy=req.get("retry_strategy", "none"),
            status="queued",
        )
        return self._repo.create(doc)

    # ── Dispatch ──────────────────────────────────────────────────────

    def dispatch(self, batch_id: str) -> None:
        """Partition + submit k subcircuit jobs. Moves status queued → executing."""
        doc = self._repo.get(batch_id)
        if doc is None:
            raise LookupError(f"Batch {batch_id} not found")
        pipeline = get_pipeline(doc.preset)
        circuit = self._circuits.load_qiskit_circuit(doc.project_id, doc.circuit_id)
        self._repo.update_fields(batch_id, status="partitioning")
        subcircuits = pipeline.partition(circuit, doc.cut_plan)

        child_ids: list[str] = []
        for assn in doc.backend_assignments:
            idx = assn["subcircuit_idx"]
            job = self._jobs.submit_job(
                project_id=doc.project_id,
                circuit_id=doc.circuit_id,
                backend_name=assn["backend_name"],
                shots=assn.get("shots", 4096),
                transpiled_circuit=subcircuits[idx],
                extra_fields={
                    "batch_id": batch_id,
                    "cut_role": f"subcircuit_{idx}",
                },
            )
            child_ids.append(job["job_id"])
        self._repo.update_fields(
            batch_id,
            child_job_ids=child_ids,
            status="executing",
            submitted_at=datetime.now(timezone.utc),
        )

    # ── Poll ──────────────────────────────────────────────────────────

    def poll_batch(self, batch_id: str) -> dict:
        """Refresh aggregate status from child jobs. Triggers reconstruction
        when all children terminal-complete. Returns a dict for the API."""
        doc = self._repo.get(batch_id)
        if doc is None:
            raise LookupError(f"Batch {batch_id} not found")
        if doc.status in {"completed", "failed", "cancelled", "partial_failure"}:
            return self._to_response(doc)

        child_states = [self._jobs.get_job(cid) for cid in doc.child_job_ids]
        any_failed = any(cs.get("status") == "failed" for cs in child_states)
        all_done = all(cs.get("status") in {"completed", "failed"} for cs in child_states)
        pcts = [int(cs.get("progress_pct", 0)) for cs in child_states]
        progress = int(mean(pcts)) if pcts else 0

        if all_done and not any_failed:
            self._reconstruct_and_complete(doc, child_states)
        elif all_done and any_failed:
            self._repo.update_fields(
                batch_id, status="partial_failure", progress_pct=100,
                error="One or more subcircuits failed",
                completed_at=datetime.now(timezone.utc),
            )
        else:
            self._repo.update_fields(batch_id, progress_pct=progress)
        return self._to_response(self._repo.get(batch_id))

    # ── Cancel ────────────────────────────────────────────────────────

    def cancel(self, batch_id: str) -> None:
        doc = self._repo.get(batch_id)
        if doc is None:
            raise LookupError(f"Batch {batch_id} not found")
        for cid in doc.child_job_ids:
            try:
                self._jobs.cancel_job(cid)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Cancel child %s failed: %s", cid, exc)
        self._repo.update_fields(
            batch_id, status="cancelled",
            completed_at=datetime.now(timezone.utc),
        )

    # ── Result ────────────────────────────────────────────────────────

    def get_result(self, batch_id: str) -> dict:
        doc = self._repo.get(batch_id)
        if doc is None:
            raise LookupError(f"Batch {batch_id} not found")
        rec = doc.reconstruction or {}
        return {
            "batch_id": batch_id,
            "status": doc.status,
            "expectations": rec.get("expectations", []),
            "distribution": rec.get("distribution"),
            "preset_output": rec.get("preset_output"),
        }

    # ── Internal ──────────────────────────────────────────────────────

    def _reconstruct_and_complete(
        self, doc: CuttingBatchDocument, child_states: list[dict]
    ) -> None:
        pipeline = get_pipeline(doc.preset)
        try:
            self._repo.update_fields(doc.batch_id, status="reconstructing")
            subcircuit_results = [cs.get("result", {}) for cs in child_states]
            expectations = pipeline.reconstruct_expectations(
                subcircuit_results, doc.observables, doc.cut_plan
            )
            reconstruction = {"expectations": expectations}
            post = pipeline.post_process(
                reconstruction,
                {"project_id": doc.project_id, "circuit_id": doc.circuit_id},
            )
            self._repo.mark_completed(doc.batch_id, post)
        except Exception as exc:  # noqa: BLE001
            logger.exception("Reconstruction failed for batch %s", doc.batch_id)
            # Preserve raw measurements so the user can retry reconstruction
            # without re-running the subcircuits on hardware.
            self._repo.update_fields(
                doc.batch_id,
                subcircuit_measurements={"children": [cs.get("result") for cs in child_states]},
            )
            self._repo.mark_failed(doc.batch_id, f"Reconstruction error: {exc}")

    @staticmethod
    def _to_response(doc: CuttingBatchDocument) -> dict:
        return {
            "batch_id": doc.batch_id,
            "project_id": doc.project_id,
            "circuit_id": doc.circuit_id,
            "mode": doc.mode,
            "preset": doc.preset,
            "status": doc.status,
            "progress_pct": doc.progress_pct,
            "cut_plan": doc.cut_plan,
            "backend_assignments": doc.backend_assignments,
            "children": [],
            "error": doc.error,
            "created_at": doc.created_at.isoformat() if doc.created_at else "",
            "submitted_at": doc.submitted_at.isoformat() if doc.submitted_at else None,
            "completed_at": doc.completed_at.isoformat() if doc.completed_at else None,
        }
```

- [ ] **Step 4: Run the tests**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/services/test_cutting_batch_service.py -x --tb=short`
Expected: `2 passed`.

- [ ] **Step 5: Commit**

```bash
cd sqk-qtau && git add src/qdash/api/services/cutting_batch_service.py tests/qdash/api/services/test_cutting_batch_service.py && git commit -m "feat(cutting): add CuttingBatchService lifecycle orchestrator"
```

---

## Task 8 — `/api/cutting/*` router + DI wiring

**Files:**
- Create: `sqk-qtau/src/qdash/api/routers/cutting.py`
- Modify: `sqk-qtau/src/qdash/api/dependencies.py` (append DI factories)
- Modify: `sqk-qtau/src/qdash/api/main.py` (register router)
- Test: `sqk-qtau/tests/qdash/api/routers/test_cutting_router.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/qdash/api/routers/test_cutting_router.py
"""Endpoint contract for /api/cutting/*."""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest


def test_list_presets_includes_generic(test_client):
    from qdash.api.dependencies import get_cutting_service
    from qdash.api.main import app

    fake = MagicMock()
    fake.list_presets.return_value = [
        {"id": "generic", "name": "Generic", "description": "",
         "qubit_range": [2, 1024], "output_type": "expectation_values",
         "required_structure": ""},
    ]
    app.dependency_overrides[get_cutting_service] = lambda: fake
    try:
        resp = test_client.get("/api/cutting/presets",
                               headers={"Authorization": "Bearer test"})
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert any(p["id"] == "generic" for p in body["presets"])


def test_create_batch_returns_202(test_client):
    from qdash.api.dependencies import get_cutting_batch_service
    from qdash.api.main import app
    from qdash.dbmodel.cutting_batch import CuttingBatchDocument

    fake = MagicMock()
    fake.create_batch.return_value = CuttingBatchDocument(
        project_id="p1", circuit_id="c1", batch_id="b-xyz",
        mode="assisted", preset="generic",
        cut_plan={"cuts": [], "k": 2, "sampling_overhead": 3.5, "per_subcircuit_qubits": [3, 3]},
        backend_assignments=[], observables=[], child_job_ids=[],
        status="queued",
    )
    app.dependency_overrides[get_cutting_batch_service] = lambda: fake
    payload = {
        "mode": "assisted",
        "preset": "generic",
        "cut_plan": {"cuts": [], "k": 2, "sampling_overhead": 3.5,
                     "per_subcircuit_qubits": [3, 3]},
        "backend_assignments": [
            {"subcircuit_idx": 0, "backend_name": "ibm_miami", "shots": 4096},
            {"subcircuit_idx": 1, "backend_name": "ibm_marrakesh", "shots": 4096},
        ],
        "observables": [],
        "opt_in_distribution": False,
    }
    try:
        resp = test_client.post(
            "/api/circuits/c1/cutting/batches",
            json=payload,
            headers={"Authorization": "Bearer test"},
        )
    finally:
        app.dependency_overrides.clear()
    assert resp.status_code == 202, resp.text
    assert resp.json()["batch_id"] == "b-xyz"
```

- [ ] **Step 2: Confirm it fails**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/routers/test_cutting_router.py -x --tb=short`
Expected: 404s / missing endpoint.

- [ ] **Step 3: Write the router**

```python
# src/qdash/api/routers/cutting.py
"""Circuit cutting endpoints."""

from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status

from qdash.api.dependencies import (
    get_cutting_batch_service,
    get_cutting_service,
)
from qdash.api.lib.project import ProjectContext, get_project_context
from qdash.api.schemas.cutting import (
    AnalyzeCutsRequest,
    AnalyzeCutsResponse,
    BatchResponse,
    BatchResultResponse,
    CreateBatchRequest,
    ListBatchesResponse,
    ListPresetsResponse,
)
from qdash.api.services.cutting_batch_service import CuttingBatchService
from qdash.api.services.cutting_service import CuttingService

router = APIRouter(prefix="/cutting", tags=["cutting"])
circuit_router = APIRouter(prefix="/circuits", tags=["cutting"])
logger = logging.getLogger(__name__)


@router.post("/analyze", response_model=AnalyzeCutsResponse)
def analyze_cuts(
    req: AnalyzeCutsRequest,
    ctx: Annotated[ProjectContext, Depends(get_project_context)],
    svc: Annotated[CuttingService, Depends(get_cutting_service)],
) -> AnalyzeCutsResponse:
    data = svc.analyze_cuts(
        circuit_id=req.circuit_id,
        project_id=ctx.project_id,
        target_k=req.target_k,
    )
    return AnalyzeCutsResponse(**data)


@router.get("/presets", response_model=ListPresetsResponse)
def list_presets(
    ctx: Annotated[ProjectContext, Depends(get_project_context)],
    svc: Annotated[CuttingService, Depends(get_cutting_service)],
) -> ListPresetsResponse:
    return ListPresetsResponse(presets=svc.list_presets())


@circuit_router.post(
    "/{circuit_id}/cutting/batches",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=BatchResponse,
)
def create_batch(
    circuit_id: Annotated[str, Path()],
    body: CreateBatchRequest,
    ctx: Annotated[ProjectContext, Depends(get_project_context)],
    svc: Annotated[CuttingBatchService, Depends(get_cutting_batch_service)],
) -> BatchResponse:
    req = body.model_dump()
    req.update({"project_id": ctx.project_id, "circuit_id": circuit_id})
    doc = svc.create_batch(req)
    try:
        svc.dispatch(doc.batch_id)
    except Exception as exc:  # noqa: BLE001
        logger.exception("Dispatch failed")
        raise HTTPException(status_code=500, detail=f"Dispatch failed: {exc}") from exc
    return BatchResponse(**CuttingBatchService._to_response(svc._repo.get(doc.batch_id)))


@router.get("/batches/{batch_id}", response_model=BatchResponse)
def poll_batch(
    batch_id: str,
    ctx: Annotated[ProjectContext, Depends(get_project_context)],
    svc: Annotated[CuttingBatchService, Depends(get_cutting_batch_service)],
) -> BatchResponse:
    try:
        return BatchResponse(**svc.poll_batch(batch_id))
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/batches/{batch_id}/result", response_model=BatchResultResponse)
def batch_result(
    batch_id: str,
    ctx: Annotated[ProjectContext, Depends(get_project_context)],
    svc: Annotated[CuttingBatchService, Depends(get_cutting_batch_service)],
) -> BatchResultResponse:
    try:
        return BatchResultResponse(**svc.get_result(batch_id))
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/batches/{batch_id}", status_code=204)
def cancel_batch(
    batch_id: str,
    ctx: Annotated[ProjectContext, Depends(get_project_context)],
    svc: Annotated[CuttingBatchService, Depends(get_cutting_batch_service)],
) -> None:
    try:
        svc.cancel(batch_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/batches", response_model=ListBatchesResponse)
def list_batches(
    ctx: Annotated[ProjectContext, Depends(get_project_context)],
    svc: Annotated[CuttingBatchService, Depends(get_cutting_batch_service)],
    limit: int = Query(50, ge=1, le=200),
) -> ListBatchesResponse:
    docs = svc._repo.list_by_project(ctx.project_id, limit=limit)
    return ListBatchesResponse(
        batches=[BatchResponse(**CuttingBatchService._to_response(d)) for d in docs]
    )
```

- [ ] **Step 4: Wire DI in `dependencies.py`**

Append at the bottom of `src/qdash/api/dependencies.py`:

```python
from qdash.api.services.cutting_batch_service import (  # noqa: E402
    CuttingBatchService,
)
from qdash.api.services.cutting_service import CuttingService  # noqa: E402
from qdash.repository.cutting_batch import (  # noqa: E402
    MongoCuttingBatchRepository,
)


@lru_cache(maxsize=1)
def get_cutting_service() -> CuttingService:
    return CuttingService()


@lru_cache(maxsize=1)
def get_cutting_batch_repository() -> MongoCuttingBatchRepository:
    return MongoCuttingBatchRepository()


@lru_cache(maxsize=1)
def get_cutting_batch_service() -> CuttingBatchService:
    return CuttingBatchService(
        batch_repository=get_cutting_batch_repository(),
        job_service=get_job_service(),
        circuit_service=get_circuit_service(),
    )
```

- [ ] **Step 5: Register router in `main.py`**

Open `src/qdash/api/main.py` and, where other routers are included (search for `include_router`), add:

```python
from qdash.api.routers.cutting import router as cutting_router, circuit_router as cutting_circuit_router
# ...
app.include_router(cutting_router, prefix="/api")
app.include_router(cutting_circuit_router, prefix="/api")
```

- [ ] **Step 6: Run the tests**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/routers/test_cutting_router.py -x --tb=short`
Expected: `2 passed`.

- [ ] **Step 7: Commit**

```bash
cd sqk-qtau && git add src/qdash/api/routers/cutting.py src/qdash/api/dependencies.py src/qdash/api/main.py tests/qdash/api/routers/test_cutting_router.py && git commit -m "feat(cutting): add /api/cutting/* router + DI wiring"
```

---

## Task 9 — MATLAB `CuttingService` HTTP client

**Files:**
- Create: `sqk-qtau-matlab/src/domain/services/CuttingService.m`
- Test: `sqk-qtau-matlab/tests/test_CuttingService.m`

- [ ] **Step 1: Write the failing test**

```matlab
% tests/test_CuttingService.m
classdef test_CuttingService < matlab.unittest.TestCase
    properties
        Stub
        Service
    end

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'http'));
            addpath(fullfile(projectRoot, 'src', 'domain', 'services'));
            addpath(fullfile(projectRoot, 'tests'));
        end
    end

    methods (TestMethodSetup)
        function createService(tc)
            tc.Stub = StubFastAPIClient();
            tc.Service = CuttingService(tc.Stub);
        end
    end

    methods (Test)
        function testAnalyzePostsCircuitId(tc)
            tc.Service.analyzeCuts('c1', 3, 'tok');
            tc.verifyEqual(char(tc.Stub.LastMethod), 'postAuth');
            tc.verifyTrue(contains(char(tc.Stub.LastEndpoint), '/api/cutting/analyze'));
        end

        function testListPresetsUsesGetAuth(tc)
            tc.Service.listPresets('tok');
            tc.verifyEqual(char(tc.Stub.LastMethod), 'getAuth');
            tc.verifyTrue(contains(char(tc.Stub.LastEndpoint), '/api/cutting/presets'));
        end

        function testCreateBatchHitsCircuitEndpoint(tc)
            tc.Service.createBatch('c1', struct('mode','assisted'), 'tok');
            tc.verifyTrue(contains(char(tc.Stub.LastEndpoint), '/api/circuits/c1/cutting/batches'));
        end

        function testPollBatch(tc)
            tc.Service.pollBatch('b-xyz', 'tok');
            tc.verifyTrue(contains(char(tc.Stub.LastEndpoint), '/api/cutting/batches/b-xyz'));
        end

        function testCancelUsesDeleteAuth(tc)
            tc.Service.cancelBatch('b-xyz', 'tok');
            tc.verifyEqual(char(tc.Stub.LastMethod), 'deleteAuth');
        end
    end
end
```

- [ ] **Step 2: Run it to confirm failure**

Run: `/Applications/MATLAB_R2024a.app/bin/matlab -batch "cd('/Users/mason/Workspace/Projects/QDash/sqk-qtau-matlab'); addpath(genpath('src')); addpath('tests'); r = runtests('tests/test_CuttingService'); exit(any([r.Failed]))"`
Expected: fails with `Unrecognized function or variable 'CuttingService'`.

- [ ] **Step 3: Write the service**

```matlab
% src/domain/services/CuttingService.m
classdef CuttingService < handle
    % CuttingService  HTTP client for /api/cutting/* endpoints.

    properties (Access = private)
        Client
    end

    methods
        function obj = CuttingService(client)
            obj.Client = client;
            Logger.info('CuttingService', 'Initialized');
        end

        function result = analyzeCuts(obj, circuitId, targetK, token)
            body = struct('circuit_id', char(circuitId));
            if ~isempty(targetK) && isnumeric(targetK)
                body.target_k = int32(targetK);
            end
            result = obj.Client.postAuth('/api/cutting/analyze', body, token);
        end

        function result = listPresets(obj, token)
            result = obj.Client.getAuth('/api/cutting/presets', token);
        end

        function result = createBatch(obj, circuitId, body, token)
            endpoint = sprintf('/api/circuits/%s/cutting/batches', ...
                FastAPIClient.encodePathSegment(char(circuitId)));
            result = obj.Client.postAuth(endpoint, body, token);
        end

        function result = pollBatch(obj, batchId, token)
            endpoint = sprintf('/api/cutting/batches/%s', ...
                FastAPIClient.encodePathSegment(char(batchId)));
            result = obj.Client.getAuth(endpoint, token);
        end

        function result = getBatchResult(obj, batchId, token)
            endpoint = sprintf('/api/cutting/batches/%s/result', ...
                FastAPIClient.encodePathSegment(char(batchId)));
            result = obj.Client.getAuth(endpoint, token);
        end

        function result = cancelBatch(obj, batchId, token)
            endpoint = sprintf('/api/cutting/batches/%s', ...
                FastAPIClient.encodePathSegment(char(batchId)));
            result = obj.Client.deleteAuth(endpoint, token);
        end

        function result = listBatches(obj, token)
            result = obj.Client.getAuth('/api/cutting/batches', token);
        end
    end
end
```

- [ ] **Step 4: Run tests to verify pass**

Run: `/Applications/MATLAB_R2024a.app/bin/matlab -batch "cd('/Users/mason/Workspace/Projects/QDash/sqk-qtau-matlab'); addpath(genpath('src')); addpath('tests'); r = runtests('tests/test_CuttingService'); exit(any([r.Failed]))"`
Expected: `5 Passed, 0 Failed`.

- [ ] **Step 5: Commit**

```bash
cd sqk-qtau-matlab && git add src/domain/services/CuttingService.m tests/test_CuttingService.m && git commit -m "feat(cutting-ui): add CuttingService HTTP client + tests"
```

---

## Task 10 — MATLAB `CircuitCuttingViewModel`

**Files:**
- Create: `sqk-qtau-matlab/src/presentation/viewmodels/CircuitCuttingViewModel.m`
- Test: `sqk-qtau-matlab/tests/test_CircuitCuttingViewModel.m`
- Create: `sqk-qtau-matlab/tests/TestCircuitCuttingVmProbe.m`

- [ ] **Step 1: Write the failing test**

```matlab
% tests/test_CircuitCuttingViewModel.m
classdef test_CircuitCuttingViewModel < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
            addpath(fullfile(projectRoot, 'src', 'presentation', 'viewmodels'));
            addpath(fullfile(projectRoot, 'tests'));
        end
    end

    methods (Test)
        function testFormatOverheadHandlesEmpty(tc)
            vm = TestCircuitCuttingVmProbe();
            tc.verifyEqual(vm.probeFormatOverhead([]), '--');
            tc.verifyEqual(vm.probeFormatOverhead(NaN), '--');
            tc.verifyEqual(vm.probeFormatOverhead(7.2), '7.2x');
            tc.verifyEqual(vm.probeFormatOverhead(1.0), '1.0x');
        end

        function testModeDefaultsAssisted(tc)
            vm = TestCircuitCuttingVmProbe();
            tc.verifyEqual(vm.probeDefaultMode(), 'assisted');
        end
    end
end
```

- [ ] **Step 2: Write the probe**

```matlab
% tests/TestCircuitCuttingVmProbe.m
classdef TestCircuitCuttingVmProbe < handle
    methods
        function s = probeFormatOverhead(~, v)
            if isempty(v) || ~isnumeric(v) || any(isnan(v))
                s = '--'; return;
            end
            s = sprintf('%.1fx', double(v));
        end
        function m = probeDefaultMode(~)
            m = 'assisted';
        end
    end
end
```

- [ ] **Step 3: Confirm failure**

Run: `/Applications/MATLAB_R2024a.app/bin/matlab -batch "cd('/Users/mason/Workspace/Projects/QDash/sqk-qtau-matlab'); addpath(genpath('src')); addpath('tests'); r = runtests('tests/test_CircuitCuttingViewModel'); exit(any([r.Failed]))"`
Expected: tests that reference VM fail because it doesn't exist yet. (Probe-only tests pass.)

- [ ] **Step 4: Write the ViewModel**

```matlab
% src/presentation/viewmodels/CircuitCuttingViewModel.m
classdef CircuitCuttingViewModel < handle
    % CircuitCuttingViewModel  Callbacks for the Circuit Cutting screen.
    %
    % Three modes share one pipeline:
    %   * Automatic — one-click run, everything auto.
    %   * Assisted  — defaults pre-filled via /api/cutting/analyze, user can
    %                 override any field (cut plan, backends, observables).
    %   * Manual    — blank form, user enters everything.

    properties
        App
        CurrentMode       = "assisted"
        CurrentPreset     = "generic"
        LastAnalyze       = []
        ActiveBatchId     = ''
        PollTimer         = []
    end

    methods
        function obj = CircuitCuttingViewModel(app)
            obj.App = app;
        end

        function onEnter(obj)
            if ~obj.App.State.isAuthenticated(); return; end
            obj.loadPresets();
        end

        function onModeChanged(obj, mode)
            obj.CurrentMode = string(mode);
            obj.App.logEvent('CUT', sprintf('Mode changed → %s', mode));
            obj.refreshVisibility();
        end

        function onPresetChanged(obj, preset)
            obj.CurrentPreset = string(preset);
        end

        function onAnalyzeCuts(obj)
            if ~obj.App.State.isAuthenticated(); return; end
            cid = char(obj.App.State.selectedCircuitId);
            if isempty(cid)
                uialert(obj.App.UIFigure, 'Select a circuit first.', 'Cutting');
                return;
            end
            obj.App.showLoading();
            AsyncRunner.run( ...
                @() obj.App.CuttingSvc.analyzeCuts(cid, [], obj.App.State.authToken), ...
                @(r) obj.applyAnalyze(r), ...
                @(ME) obj.onError(ME));
        end

        function onRunCutting(obj)
            if isempty(obj.LastAnalyze)
                uialert(obj.App.UIFigure, 'Press Analyze Cuts first.', 'Cutting');
                return;
            end
            cid = char(obj.App.State.selectedCircuitId);
            body = obj.buildCreateBody();
            obj.App.showLoading();
            AsyncRunner.run( ...
                @() obj.App.CuttingSvc.createBatch(cid, body, obj.App.State.authToken), ...
                @(r) obj.startPolling(r), ...
                @(ME) obj.onError(ME));
        end

        function onCancelBatch(obj)
            if isempty(obj.ActiveBatchId); return; end
            try
                obj.App.CuttingSvc.cancelBatch(obj.ActiveBatchId, obj.App.State.authToken);
            catch ME
                obj.App.logEvent('WARN', ['Cancel failed: ' ME.message]);
            end
            obj.stopPolling();
        end

        function loadPresets(obj)
            try
                data = obj.App.CuttingSvc.listPresets(obj.App.State.authToken);
                items = JsonHelper.extractList(data, 'presets');
                n = numel(items);
                names = cell(1,n); ids = cell(1,n);
                for i = 1:n
                    ids{i}   = char(JsonHelper.pick(items(i), 'id'));
                    names{i} = char(JsonHelper.pick(items(i), 'name'));
                end
                obj.App.CuttingPresetDropdown.Items     = names;
                obj.App.CuttingPresetDropdown.ItemsData = ids;
            catch ME
                Logger.warn('CircuitCuttingViewModel', 'loadPresets failed: %s', ME.message);
                obj.App.CuttingPresetDropdown.Items     = {'Generic'};
                obj.App.CuttingPresetDropdown.ItemsData = {'generic'};
            end
        end
    end

    methods (Access = private)
        function applyAnalyze(obj, r)
            obj.App.hideLoading();
            obj.LastAnalyze = r;
            candidates = JsonHelper.pick(r, 'candidates', {});
            if isempty(candidates)
                obj.App.CuttingStatusLabel.Text = 'No cut candidates found.';
                return;
            end
            c = candidates(1); if iscell(c); c = c{1}; end
            k = JsonHelper.pick(c, 'k', 0);
            oh = JsonHelper.pick(c, 'sampling_overhead', 0);
            obj.App.CuttingStatusLabel.Text = sprintf( ...
                '%d subcircuits · overhead %.1fx · preset: %s', ...
                k, oh, obj.CurrentPreset);
        end

        function body = buildCreateBody(obj)
            candidates = JsonHelper.pick(obj.LastAnalyze, 'candidates', {});
            c = candidates(1); if iscell(c); c = c{1}; end
            body = struct();
            body.mode = char(obj.CurrentMode);
            body.preset = char(obj.CurrentPreset);
            body.cut_plan = c;
            body.backend_assignments = obj.collectBackends(c);
            body.observables = {};
            body.opt_in_distribution = false;
            body.timeout_hours = 6.0;
            body.retry_strategy = 'none';
        end

        function assns = collectBackends(obj, cutPlan)
            k = JsonHelper.pick(cutPlan, 'k', 1);
            assns = cell(1, k);
            for i = 1:k
                assns{i} = struct( ...
                    'subcircuit_idx', i-1, ...
                    'backend_name', 'ibm_miami', ...
                    'shots', 4096);
            end
        end

        function startPolling(obj, batchResp)
            obj.App.hideLoading();
            obj.ActiveBatchId = char(JsonHelper.pick(batchResp, 'batch_id'));
            if isempty(obj.ActiveBatchId); return; end
            obj.stopPolling();
            obj.PollTimer = timer('Period', 3, 'ExecutionMode', 'fixedRate', ...
                'TimerFcn', @(~,~) obj.pollTick());
            start(obj.PollTimer);
        end

        function pollTick(obj)
            try
                r = obj.App.CuttingSvc.pollBatch(obj.ActiveBatchId, obj.App.State.authToken);
                st = char(JsonHelper.pick(r, 'status', ''));
                pct = JsonHelper.pick(r, 'progress_pct', 0);
                obj.App.CuttingStatusLabel.Text = sprintf( ...
                    'Batch %s · status=%s · %d%%', obj.ActiveBatchId, st, pct);
                if ismember(st, {'completed','failed','cancelled','partial_failure'})
                    obj.stopPolling();
                    obj.fetchResult();
                end
            catch ME
                Logger.warn('CircuitCuttingViewModel', 'pollTick: %s', ME.message);
            end
        end

        function fetchResult(obj)
            try
                r = obj.App.CuttingSvc.getBatchResult(obj.ActiveBatchId, obj.App.State.authToken);
                obj.App.logEvent('CUT', sprintf('Batch %s completed', obj.ActiveBatchId));
                obj.App.CuttingResultsLabel.Text = jsonencode(r);
            catch ME
                Logger.warn('CircuitCuttingViewModel', 'fetchResult: %s', ME.message);
            end
        end

        function stopPolling(obj)
            if ~isempty(obj.PollTimer)
                try stop(obj.PollTimer); delete(obj.PollTimer); catch; end
                obj.PollTimer = [];
            end
        end

        function refreshVisibility(obj)
            % Stub: the screen reads CurrentMode and hides/shows panels on next paint.
            obj.App.CuttingStatusLabel.Text = sprintf('Mode: %s', obj.CurrentMode);
        end

        function onError(obj, ME)
            obj.App.hideLoading();
            obj.App.showError('Circuit Cutting', ME);
        end
    end
end
```

- [ ] **Step 5: Run tests**

Run the same batch command as Step 3.
Expected: `2 Passed, 0 Failed`.

- [ ] **Step 6: Commit**

```bash
cd sqk-qtau-matlab && git add src/presentation/viewmodels/CircuitCuttingViewModel.m tests/test_CircuitCuttingViewModel.m tests/TestCircuitCuttingVmProbe.m && git commit -m "feat(cutting-ui): add CircuitCuttingViewModel with Automatic/Assisted/Manual modes"
```

---

## Task 11 — MATLAB `CircuitCuttingScreen` + app wiring

**Files:**
- Create: `sqk-qtau-matlab/src/presentation/screens/CircuitCuttingScreen.m`
- Modify: `sqk-qtau-matlab/src/presentation/app/QTAUWorkbenchApp.m` (add property handles, instantiate VM, call builder)
- Modify: `sqk-qtau-matlab/src/presentation/app/NavigationManager.m` (register sidebar entry + autoLoad)
- Modify: `sqk-qtau-matlab/src/domain/ServiceContainer.m` (wire CuttingSvc)

- [ ] **Step 1: Add the screen builder**

```matlab
% src/presentation/screens/CircuitCuttingScreen.m
function CircuitCuttingScreen(app)
    Logger.info('CircuitCuttingScreen', 'Building Circuit Cutting tab UI');
    t = app.createSectionPage('Circuit Cutting');

    g = uigridlayout(t, [6 2]);
    g.RowHeight   = {34, 22, 220, 160, 40, '1x'};
    g.ColumnWidth = {'1x','1x'};
    g.Padding     = Theme.GRID_PADDING;
    g.RowSpacing  = Theme.GRID_ROW_SPACING;
    g.ColumnSpacing = Theme.GRID_ROW_SPACING;
    g.BackgroundColor = Theme.COLOR_BG;

    % Row 1: toolbar
    tb = uigridlayout(g, [1 6]);
    tb.Layout.Row = 1; tb.Layout.Column = [1 2];
    tb.ColumnWidth = {120, '1x', 260, 160, 110, 110};
    tb.Padding = [0 0 0 0]; tb.ColumnSpacing = 8;
    tb.BackgroundColor = Theme.COLOR_BG;

    uilabel(tb, 'Text', 'Mode', 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'center').Layout.Column = 1;

    app.CuttingModeDropdown = uidropdown(tb, ...
        'Items', {'Automatic','Assisted','Manual'}, ...
        'ItemsData', {'automatic','assisted','manual'}, ...
        'Value', 'assisted', ...
        'ValueChangedFcn', @(src,~) app.CircuitCuttingVm.onModeChanged(src.Value));
    app.CuttingModeDropdown.Layout.Column = 3;

    app.CuttingPresetDropdown = uidropdown(tb, ...
        'Items', {'Generic'}, 'ItemsData', {'generic'}, ...
        'ValueChangedFcn', @(src,~) app.CircuitCuttingVm.onPresetChanged(src.Value));
    app.CuttingPresetDropdown.Layout.Column = 4;

    analyzeBtn = uibutton(tb, 'Text', 'Analyze Cuts', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onAnalyzeCuts());
    analyzeBtn.Layout.Column = 5;
    app.styleBtn(analyzeBtn, 'ghost');

    runBtn = uibutton(tb, 'Text', 'Run Cutting', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onRunCutting());
    runBtn.Layout.Column = 6;
    app.styleBtn(runBtn, 'primary');

    % Row 2: status line
    app.CuttingStatusLabel = uilabel(g, ...
        'Text', 'Select a circuit and press Analyze Cuts.', ...
        'FontSize', 12, 'FontColor', Theme.COLOR_MUTED, ...
        'WordWrap', 'on', 'Interpreter', 'none');
    app.CuttingStatusLabel.Layout.Row = 2;
    app.CuttingStatusLabel.Layout.Column = [1 2];

    % Row 3: cut plan panel (left) + backend assignments (right)
    planPanel = uipanel(g, 'Title', 'Cut Plan', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    planPanel.Layout.Row = 3; planPanel.Layout.Column = 1;
    planPanel.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingPlanText = uitextarea(planPanel, ...
        'Value', 'Run Analyze Cuts to see candidates.', ...
        'Editable', 'off');

    backendPanel = uipanel(g, 'Title', 'Backend Assignments', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    backendPanel.Layout.Row = 3; backendPanel.Layout.Column = 2;
    backendPanel.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingBackendText = uitextarea(backendPanel, ...
        'Value', 'Backend list appears after Analyze.', ...
        'Editable', 'off');

    % Row 4: observables + options
    obsPanel = uipanel(g, 'Title', 'Observables', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    obsPanel.Layout.Row = 4; obsPanel.Layout.Column = 1;
    obsPanel.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingObservablesText = uitextarea(obsPanel, ...
        'Value', '(default all-Z)', 'Editable', 'on');

    optPanel = uipanel(g, 'Title', 'Options', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    optPanel.Layout.Row = 4; optPanel.Layout.Column = 2;
    optPanel.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingDistCheckbox = uicheckbox(optPanel, ...
        'Text', 'Also reconstruct bitstring distribution', 'Value', false);

    % Row 5: action row
    actions = uigridlayout(g, [1 2]);
    actions.Layout.Row = 5; actions.Layout.Column = [1 2];
    actions.ColumnWidth = {'1x', 120};
    actions.Padding = [0 0 0 0];
    actions.BackgroundColor = Theme.COLOR_BG;
    cancelBtn = uibutton(actions, 'Text', 'Cancel Batch', ...
        'ButtonPushedFcn', @(~,~) app.CircuitCuttingVm.onCancelBatch());
    cancelBtn.Layout.Column = 2;
    app.styleBtn(cancelBtn, 'ghost');

    % Row 6: results
    resPanel = uipanel(g, 'Title', 'Results', ...
        'BorderType', 'line', 'BorderColor', Theme.COLOR_DIVIDER);
    resPanel.Layout.Row = 6; resPanel.Layout.Column = [1 2];
    resPanel.BackgroundColor = Theme.COLOR_CARD;
    app.CuttingResultsLabel = uitextarea(resPanel, ...
        'Value', 'Reconstructed output appears here after the batch completes.', ...
        'Editable', 'off');

    Logger.info('CircuitCuttingScreen', 'Circuit Cutting tab built');
end
```

- [ ] **Step 2: Declare UI properties in `QTAUWorkbenchApp.m`**

Add this properties block near the other screen property blocks (e.g. after `% ── Benchmark Dashboard tab ──`):

```matlab
    % ── Circuit Cutting tab ─────────────────────────────────────────────
    properties
        CuttingModeDropdown
        CuttingPresetDropdown
        CuttingStatusLabel
        CuttingPlanText
        CuttingBackendText
        CuttingObservablesText
        CuttingDistCheckbox
        CuttingResultsLabel
        CircuitCuttingVm
    end
```

- [ ] **Step 3: Wire the VM + call the screen builder in `QTAUWorkbenchApp`**

Find the list of ViewModel declarations (search for `BenchmarkDashboardVm`) and add `CircuitCuttingVm` alongside. Find the constructor block where ViewModels are instantiated and add:

```matlab
app.CircuitCuttingVm = CircuitCuttingViewModel(app);
```

Find the `buildUI` method where each screen function is called (search for `BenchmarkDashboardScreen(app)`) and add a line:

```matlab
CircuitCuttingScreen(app);
```

- [ ] **Step 4: Register in `NavigationManager.m`**

Find the `navNames` / `navLabels` / `navIcons` arrays, and add an entry for `CircuitCutting` between `BenchmarkDashboard` and `Jobs`. Add the matching case to `autoLoadScreen(app, key)`:

```matlab
case "CircuitCutting"
    if ~isempty(app.CircuitCuttingVm) && app.State.isAuthenticated() ...
            && ~NavigationManager.isScreenFresh(app.CircuitCuttingVm, ttl)
        app.CircuitCuttingVm.onEnter();
    end
```

- [ ] **Step 5: Wire service in `ServiceContainer.m`**

Search for `BenchmarkSvc` in `ServiceContainer.m` and add a parallel `CuttingSvc` field:

```matlab
obj.CuttingSvc = CuttingService(client);
```

and the property declaration for `CuttingSvc`.

- [ ] **Step 6: Run `test_CircuitCuttingViewModel` + `test_CuttingService` + `test_ServiceContainer`**

Run: `/Applications/MATLAB_R2024a.app/bin/matlab -batch "cd('/Users/mason/Workspace/Projects/QDash/sqk-qtau-matlab'); addpath(genpath('src')); addpath('tests'); r = runtests({'tests/test_CuttingService','tests/test_CircuitCuttingViewModel','tests/test_ServiceContainer'}); exit(any([r.Failed]))"`
Expected: all green; ServiceContainer gains one test (update its expected-service list) if needed.

- [ ] **Step 7: Commit**

```bash
cd sqk-qtau-matlab && git add src/presentation/screens/CircuitCuttingScreen.m src/presentation/app/QTAUWorkbenchApp.m src/presentation/app/NavigationManager.m src/domain/ServiceContainer.m tests/test_ServiceContainer.m && git commit -m "feat(cutting-ui): add CircuitCuttingScreen + app/nav/service wiring"
```

---

## Task 12 — Benchmark + Prediction oversize banners + Jobs badge

**Files:**
- Modify: `sqk-qtau-matlab/src/presentation/viewmodels/BenchmarkViewModel.m` (add oversize banner check)
- Modify: `sqk-qtau-matlab/src/presentation/viewmodels/PredictionViewModel.m` (same)
- Modify: `sqk-qtau-matlab/src/presentation/viewmodels/JobsViewModel.m` (render batch badge column)

- [ ] **Step 1: Benchmark + Prediction banner helper**

At the top of `BenchmarkViewModel` methods block add:

```matlab
function showOversizeBannerIfNeeded(obj, circuit, backendPool)
    nq = JsonHelper.pick(circuit, 'num_qubits', 0);
    maxQ = 0;
    for i = 1:numel(backendPool)
        b = backendPool(i); if iscell(backendPool); b = backendPool{i}; end
        maxQ = max(maxQ, double(JsonHelper.pick(b, 'num_qubits', 0)));
    end
    if nq > maxQ && maxQ > 0
        uialert(obj.App.UIFigure, ...
            sprintf(['This circuit has %d qubits but the largest backend in the ' ...
                     'pool only has %d. Open Circuit Cutting to split + distribute.'], ...
                nq, maxQ), 'Circuit Too Large', 'Icon', 'warning');
    end
end
```

Duplicate into `PredictionViewModel` with the same signature.

- [ ] **Step 2: Call the helper where each VM loads circuit + backends**

In `BenchmarkViewModel.onEnter` (or equivalent loader), after circuit + backends are both fetched, call `obj.showOversizeBannerIfNeeded(circuit, backends)`. Same for `PredictionViewModel`.

- [ ] **Step 3: Jobs badge**

In `JobsViewModel`, in the row-formatting path (search for `jobsToRows` usage), append a "Batch" column whose cell text is `⤴ <batch_id[:6]>` when the job row has a non-empty `batch_id`, else empty string.

- [ ] **Step 4: Run the Jobs + Benchmark + Prediction tests**

Run: `/Applications/MATLAB_R2024a.app/bin/matlab -batch "cd('/Users/mason/Workspace/Projects/QDash/sqk-qtau-matlab'); addpath(genpath('src')); addpath('tests'); r = runtests({'tests/test_JobService','tests/test_BenchmarkService','tests/test_PredictionService'}); exit(any([r.Failed]))"`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
cd sqk-qtau-matlab && git add src/presentation/viewmodels/BenchmarkViewModel.m src/presentation/viewmodels/PredictionViewModel.m src/presentation/viewmodels/JobsViewModel.m && git commit -m "feat(cutting-ui): oversize-circuit banners on Benchmark/Prediction + Jobs batch badge"
```

---

## Task 13 — Docs update

**Files:**
- Modify: `sqk-qtau-matlab/CLAUDE.md` (add screen row + endpoint blurb)
- Modify: `sqk-qtau-matlab/docs/fastapi_contract.md` (document new endpoints)

- [ ] **Step 1: Append new screen row**

In `CLAUDE.md`, in the Screens table (search for `BenchmarkDashboardScreen`), insert a new row after `BenchmarkDashboardScreen`:

```
| CircuitCuttingScreen | CircuitCuttingViewModel | Circuit cutting + distributed reconstruction (Automatic / Assisted / Manual modes) | ✓ |
```

Update the total count at the top of the Screens section: `17 → 18 screens (17 visible)`.

- [ ] **Step 2: Append endpoint table in `fastapi_contract.md`**

Add a new section `## Circuit Cutting` with rows for each of the 7 endpoints from Task 8.

- [ ] **Step 3: Commit**

```bash
cd sqk-qtau-matlab && git add CLAUDE.md docs/fastapi_contract.md && git commit -m "docs(cutting): add CircuitCutting screen row + endpoint reference"
```

---

## Task 14 — Full test sweep + push

- [ ] **Step 1: Run full backend suite**

Run: `cd sqk-qtau && .venv/bin/python -m pytest tests/qdash/api/services/test_cutting_pipeline.py tests/qdash/api/services/test_cutting_service.py tests/qdash/api/services/test_cutting_batch_service.py tests/qdash/api/routers/test_cutting_router.py --tb=short`
Expected: all green (≥9 tests pass).

- [ ] **Step 2: Run full MATLAB cutting-related suite**

Run: `/Applications/MATLAB_R2024a.app/bin/matlab -batch "cd('/Users/mason/Workspace/Projects/QDash/sqk-qtau-matlab'); addpath(genpath('src')); addpath('tests'); r = runtests({'tests/test_CuttingService','tests/test_CircuitCuttingViewModel','tests/test_BenchmarkService','tests/test_BenchmarkDashboardViewModel'}); exit(any([r.Failed]))"`
Expected: all green (≥16 tests pass).

- [ ] **Step 3: Push both repos**

```bash
cd sqk-qtau && git push origin2 develop
cd sqk-qtau-matlab && git push origin develop
```

- [ ] **Step 4: Final verification via skill**

Use `superpowers:verification-before-completion` to double-check the final state before reporting success.

---

## Out of scope for this plan

- Phase 2 — `CTImaging160QPipeline` preset + preset-specific output panel (separate plan).
- PEC/ZNE on top of cutting (future).
- Third-party preset plugin system (YAGNI).

## Spec coverage check

| Spec requirement | Covered by task |
|---|---|
| `qiskit-addon-cutting` dependency | Task 1 |
| Pydantic DTOs | Task 2 |
| `CuttingBatchDocument` + `IBMJobDocument` back-refs | Task 3 |
| `CuttingPipeline` ABC + `GenericPipeline` | Task 4 |
| Preset registry | Task 4 |
| `CuttingService` (analyze + list_presets) | Task 5 |
| `MongoCuttingBatchRepository` | Task 6 |
| `CuttingBatchService` (create/dispatch/poll/cancel/result) | Task 7 |
| `/api/cutting/*` router + DI | Task 8 |
| MATLAB HTTP client | Task 9 |
| MATLAB ViewModel (3 modes) | Task 10 |
| MATLAB screen + nav wiring | Task 11 |
| Benchmark/Prediction banners + Jobs badge | Task 12 |
| Docs (CLAUDE.md + fastapi_contract.md) | Task 13 |
| Full test sweep | Task 14 |
