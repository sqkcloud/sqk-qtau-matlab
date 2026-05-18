# C2 — Calibration Sparklines + Compare Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add calibration sparklines + per-qubit telemetry drill-down to the existing `BackendsScreen`, and a Compare mode (2-up split with synced X-axes + diff strip) to the existing `ResultsScreen`. Both surfaces are backed by a new Mongo `CalibrationHistoryDocument` with a 7-day TTL on the server side. No new screens.

**Architecture:** C2 is read-only over data we already fetch on every Backends refresh, plus one new Beanie document recording per-`(backend, qubit)` calibration samples. Server side: write-through wrap of `BackendService.get_calibration` + new GET endpoint. Client side: extend `BackendsViewModel` with sparkline + telemetry painters, extend `ResultsViewModel` with compare-mode state, and add a small `JobPickerDialog`. Every fetch goes through the existing `AsyncRunner.run` infrastructure so the UI never blocks.

**Tech Stack:** FastAPI + Beanie (server) · pytest (server tests) · MATLAB R2025b `uigridlayout`/`uiaxes` + `AsyncRunner` (client) · `runtests` with `StubFastAPIClient` (client tests).

**Spec reference:** [docs/superpowers/specs/2026-05-09-c1-c2-composer-telemetry-design.md](../specs/2026-05-09-c1-c2-composer-telemetry-design.md)

---

## File map (locked before tasks)

**New (server):**
- `src/qdash/dbmodel/calibration_history.py` — Beanie `CalibrationHistoryDocument` + Settings (TTL index)
- `tests/test_calibration_history_model.py` — model construction + field validation
- `tests/test_calibration_history_writethrough.py` — write-through behavior of `BackendService.get_calibration`
- `tests/test_calibration_history_router.py` — `GET /api/backends/{name}/calibration_history` contract

**Modified (server):**
- `src/qdash/dbmodel/document_models.py` — register `CalibrationHistoryDocument` in the Beanie init list
- `src/qdash/api/schemas/backend.py` — add `CalibrationHistoryRecord` + `CalibrationHistoryResponse`
- `src/qdash/api/services/backend_service.py` — wrap `get_calibration` to write through to history
- `src/qdash/api/routers/backend.py` — add `GET /{name}/calibration_history`

**New (MATLAB client):**
- `tests/test_BackendsViewModel_sparklines.m` — empty/partial/full sparkline paint
- `tests/test_CompareMode.m` — 2-up toggle, diff strip math, close restores 1-column

**Modified (MATLAB client):**
- `src/infrastructure/http/FastAPIClient.m` — add `getCalibrationHistory(backend, days, token)`
- `src/presentation/viewmodels/BackendsViewModel.m` — add `fetchCalibrationHistory`, `paintInlineSparkline`, `populateTelemetryPanel`
- `src/presentation/screens/BackendsScreen.m` — sparkline column, Telemetry tab strip
- `src/presentation/viewmodels/ResultsViewModel.m` — compare-mode state, diff strip math, parallel job-load
- `src/presentation/screens/ResultsScreen.m` — `Compare with…` toolbar button + 2-up grid scaffolding
- `src/presentation/DialogBuilder.m` — add `buildJobPickerDialog`
- `tests/StubFastAPIClient.m` — stub the new `getCalibrationHistory` method
- `resources/labels.properties` — ~10 new keys (telemetry tabs, compare button, diff labels)
- `resources/app.properties` — `feature_compare_mode_enabled=true`

---

## Task 1 — Server: CalibrationHistoryDocument model + TTL index

**Files:**
- Create: `src/qdash/dbmodel/calibration_history.py`
- Create: `tests/test_calibration_history_model.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_calibration_history_model.py
import pytest
from datetime import datetime, timezone
from qdash.dbmodel.calibration_history import CalibrationHistoryDocument

def test_construct_with_required_fields():
    doc = CalibrationHistoryDocument(
        backend_name="ibm_marrakesh",
        qubit_index=0,
        sampled_at=datetime(2026, 5, 9, 12, 0, 0, tzinfo=timezone.utc),
        T1=1.5e-4,
        T2=8.0e-5,
        frequency=5.1e9,
        gate_error=2.3e-4,
        readout_error=1.1e-2,
        anharmonicity=-3.4e8,
    )
    assert doc.backend_name == "ibm_marrakesh"
    assert doc.qubit_index == 0
    assert doc.T1 == 1.5e-4
    assert doc.two_q_error is None  # nullable

def test_two_q_error_optional():
    doc = CalibrationHistoryDocument(
        backend_name="ibm_marrakesh",
        qubit_index=2,
        sampled_at=datetime(2026, 5, 9, 12, 0, 0, tzinfo=timezone.utc),
        T1=1.0e-4, T2=5.0e-5, frequency=5.0e9,
        gate_error=2.0e-4, readout_error=1.0e-2, anharmonicity=-3.0e8,
        two_q_error=8.5e-3,
    )
    assert doc.two_q_error == 8.5e-3

def test_settings_declares_ttl_on_sampled_at():
    settings = CalibrationHistoryDocument.Settings
    indexes = getattr(settings, "indexes", [])
    ttl_indexes = [
        idx for idx in indexes
        if hasattr(idx, "expireAfterSeconds") or "expireAfterSeconds" in str(idx)
    ]
    assert len(ttl_indexes) >= 1, f"Expected TTL index, got {indexes!r}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_calibration_history_model.py -v`
Expected: FAIL with `ModuleNotFoundError: qdash.dbmodel.calibration_history`.

- [ ] **Step 3: Write minimal implementation**

```python
# src/qdash/dbmodel/calibration_history.py
"""CalibrationHistoryDocument — per-(backend, qubit) calibration sample
with 7-day TTL eviction. Written through from BackendService.get_calibration
on every successful IBM-side fetch; consumed by the Backends screen's
sparkline column and Telemetry drill-down panel."""

from datetime import datetime
from typing import ClassVar

import pymongo
from beanie import Document
from pydantic import Field


SEVEN_DAYS_SECONDS: int = 7 * 24 * 60 * 60


class CalibrationHistoryDocument(Document):
    backend_name: str = Field(..., description="IBM backend name, e.g. ibm_marrakesh")
    qubit_index: int = Field(..., ge=0, description="0-based qubit index")
    sampled_at: datetime = Field(..., description="UTC ISO-8601 timestamp of fetch")
    T1: float = Field(..., description="Relaxation time, seconds")
    T2: float = Field(..., description="Dephasing time, seconds")
    frequency: float = Field(..., description="Qubit frequency, Hz")
    gate_error: float = Field(..., description="Single-qubit gate error rate")
    readout_error: float = Field(..., description="Readout error rate")
    anharmonicity: float = Field(..., description="Anharmonicity, Hz")
    two_q_error: float | None = Field(
        default=None,
        description="Mean 2-qubit gate error; nullable for non-2Q-eligible qubits",
    )

    class Settings:
        name = "calibration_history"
        indexes: ClassVar = [
            [("backend_name", pymongo.ASCENDING),
             ("qubit_index", pymongo.ASCENDING),
             ("sampled_at", pymongo.DESCENDING)],
            pymongo.IndexModel(
                [("sampled_at", pymongo.ASCENDING)],
                expireAfterSeconds=SEVEN_DAYS_SECONDS,
            ),
        ]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_calibration_history_model.py -v`
Expected: PASS — 3 tests green.

- [ ] **Step 5: Commit**

```bash
git add src/qdash/dbmodel/calibration_history.py tests/test_calibration_history_model.py
git commit -m "feat(dbmodel): add CalibrationHistoryDocument with 7-day TTL"
```

---

## Task 2 — Server: Register CalibrationHistoryDocument with Beanie

**Files:**
- Modify: `src/qdash/dbmodel/document_models.py`

- [ ] **Step 1: Find the existing document registration list**

Run: `grep -n "DOCUMENT_MODELS\|document_models\|Document\]" src/qdash/dbmodel/document_models.py | head -20`

Expected output: a list/tuple of Beanie `Document` subclasses registered for `init_beanie(...)`. Note the exact variable name and the imports above it.

- [ ] **Step 2: Add the import + registration**

In `src/qdash/dbmodel/document_models.py`, add the import alongside the other dbmodel imports:

```python
from qdash.dbmodel.calibration_history import CalibrationHistoryDocument
```

Then add `CalibrationHistoryDocument` to the existing document-models list (typically named `DOCUMENT_MODELS` — match the convention in the file you just inspected).

- [ ] **Step 3: Verify by running existing dbmodel tests**

Run: `pytest tests/ -k "document_models or beanie_init" -v`
Expected: existing tests still pass; no regression. If no test exercises `init_beanie`, run the API server briefly: `uvicorn qdash.api.main:app --reload` and confirm Beanie's startup logs include `CalibrationHistoryDocument`.

- [ ] **Step 4: Commit**

```bash
git add src/qdash/dbmodel/document_models.py
git commit -m "feat(dbmodel): register CalibrationHistoryDocument with Beanie init list"
```

---

## Task 3 — Server: Add CalibrationHistoryRecord + Response schemas

**Files:**
- Modify: `src/qdash/api/schemas/backend.py`

- [ ] **Step 1: Inspect the current schemas file**

Run: `grep -n "^class \|^from " src/qdash/api/schemas/backend.py | head -30`
Identify where to insert the new classes — typically after the existing `Calibration*` schemas if any.

- [ ] **Step 2: Add the schemas**

Append to `src/qdash/api/schemas/backend.py`:

```python
class CalibrationHistoryRecord(BaseModel):
    """One row from the calibration_history collection — flat shape so the
    MATLAB client can render directly without re-shaping."""
    backend_name: str
    qubit_index: int
    sampled_at: datetime
    T1: float
    T2: float
    frequency: float
    gate_error: float
    readout_error: float
    anharmonicity: float
    two_q_error: float | None = None


class CalibrationHistoryResponse(BaseModel):
    """Time-sorted (DESC) records for a single backend, optionally filtered
    to one qubit. Empty list is valid (e.g., backend offline for >7 days)."""
    backend_name: str
    qubit_index: int | None = None  # None = all qubits in response
    days: int
    records: list[CalibrationHistoryRecord]
```

If `BaseModel` and `datetime` are not already imported in this file, add at the top:

```python
from datetime import datetime
from pydantic import BaseModel
```

- [ ] **Step 3: Verify import works**

Run: `python -c "from qdash.api.schemas.backend import CalibrationHistoryRecord, CalibrationHistoryResponse; print('ok')"`
Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add src/qdash/api/schemas/backend.py
git commit -m "feat(schemas): add CalibrationHistoryRecord + Response schemas"
```

---

## Task 4 — Server: Write-through wrap of BackendService.get_calibration

**Files:**
- Modify: `src/qdash/api/services/backend_service.py`
- Create: `tests/test_calibration_history_writethrough.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_calibration_history_writethrough.py
import pytest
from datetime import datetime, timezone

from qdash.api.services.backend_service import BackendService
from qdash.dbmodel.calibration_history import CalibrationHistoryDocument


@pytest.mark.asyncio
async def test_get_calibration_writes_through_one_row_per_qubit(monkeypatch, mocker):
    fake_payload = {
        "backend_name": "ibm_test",
        "qubits": [
            {"qubit_index": 0, "T1": 1.5e-4, "T2": 8e-5, "frequency": 5.1e9,
             "gate_error": 2e-4, "readout_error": 1e-2, "anharmonicity": -3e8,
             "two_q_error": 8.5e-3},
            {"qubit_index": 1, "T1": 1.4e-4, "T2": 7e-5, "frequency": 5.0e9,
             "gate_error": 2.5e-4, "readout_error": 1.2e-2, "anharmonicity": -3.1e8,
             "two_q_error": 9.0e-3},
            {"qubit_index": 2, "T1": 1.3e-4, "T2": 6e-5, "frequency": 4.9e9,
             "gate_error": 3e-4, "readout_error": 1.5e-2, "anharmonicity": -3.2e8,
             "two_q_error": None},
        ],
    }
    mocker.patch.object(BackendService, "_fetch_ibm_calibration",
                        return_value=fake_payload)
    insert_calls = []

    async def _fake_insert(self):
        insert_calls.append(self)

    monkeypatch.setattr(CalibrationHistoryDocument, "insert", _fake_insert)

    svc = BackendService()
    out = await svc.get_calibration("ibm_test", token="t")
    assert out == fake_payload
    assert len(insert_calls) == 3
    assert {row.qubit_index for row in insert_calls} == {0, 1, 2}
    for row in insert_calls:
        assert row.backend_name == "ibm_test"
        assert (datetime.now(tz=timezone.utc) - row.sampled_at).total_seconds() < 5


@pytest.mark.asyncio
async def test_writethrough_failure_does_not_break_response(monkeypatch, mocker):
    fake_payload = {"backend_name": "ibm_test", "qubits": [
        {"qubit_index": 0, "T1": 1e-4, "T2": 5e-5, "frequency": 5e9,
         "gate_error": 2e-4, "readout_error": 1e-2, "anharmonicity": -3e8}]}
    mocker.patch.object(BackendService, "_fetch_ibm_calibration",
                        return_value=fake_payload)

    async def _broken_insert(self):
        raise RuntimeError("mongo down")

    monkeypatch.setattr(CalibrationHistoryDocument, "insert", _broken_insert)

    svc = BackendService()
    out = await svc.get_calibration("ibm_test", token="t")
    assert out == fake_payload  # caller still sees the IBM payload
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_calibration_history_writethrough.py -v`
Expected: FAIL — assertions fail because `BackendService.get_calibration` does not yet write through.

- [ ] **Step 3: Inspect the existing get_calibration implementation**

Run: `grep -n "get_calibration\|_fetch_ibm_calibration" src/qdash/api/services/backend_service.py`
Locate the existing method body. Note exact return type and any logging.

- [ ] **Step 4: Add the write-through wrap**

Modify `src/qdash/api/services/backend_service.py`. Add imports near the top:

```python
import logging
from datetime import datetime, timezone

from qdash.dbmodel.calibration_history import CalibrationHistoryDocument

logger = logging.getLogger(__name__)
```

Inside `class BackendService`, replace `get_calibration` (or add this version, refactoring the existing IBM-call portion into `_fetch_ibm_calibration`):

```python
async def get_calibration(self, backend_name: str, token: str) -> dict:
    payload = await self._fetch_ibm_calibration(backend_name, token)
    try:
        await self._write_calibration_history(payload)
    except Exception as exc:  # noqa: BLE001 — best-effort, never breaks response
        logger.debug("calibration_history write-through skipped: %s", exc)
    return payload


async def _write_calibration_history(self, payload: dict) -> None:
    backend_name = payload.get("backend_name", "")
    qubits = payload.get("qubits", []) or []
    sampled_at = datetime.now(tz=timezone.utc)
    for q in qubits:
        doc = CalibrationHistoryDocument(
            backend_name=backend_name,
            qubit_index=int(q["qubit_index"]),
            sampled_at=sampled_at,
            T1=float(q["T1"]),
            T2=float(q["T2"]),
            frequency=float(q["frequency"]),
            gate_error=float(q["gate_error"]),
            readout_error=float(q["readout_error"]),
            anharmonicity=float(q["anharmonicity"]),
            two_q_error=q.get("two_q_error"),
        )
        await doc.insert()
```

If the existing `get_calibration` directly hits IBM, refactor that body into `_fetch_ibm_calibration` so the public signature is unchanged.

- [ ] **Step 5: Run test to verify it passes**

Run: `pytest tests/test_calibration_history_writethrough.py -v`
Expected: PASS — both tests green.

- [ ] **Step 6: Commit**

```bash
git add src/qdash/api/services/backend_service.py tests/test_calibration_history_writethrough.py
git commit -m "feat(backend): write-through CalibrationHistoryDocument on get_calibration (best-effort)"
```

---

## Task 5 — Server: GET /api/backends/{name}/calibration_history endpoint

**Files:**
- Modify: `src/qdash/api/routers/backend.py`
- Create: `tests/test_calibration_history_router.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_calibration_history_router.py
import pytest
from datetime import datetime, timedelta, timezone
from httpx import AsyncClient
from qdash.api.main import app
from qdash.dbmodel.calibration_history import CalibrationHistoryDocument


@pytest.mark.asyncio
async def test_returns_time_sorted_desc(test_db, auth_headers):
    backend = "ibm_test"
    base = datetime.now(tz=timezone.utc)
    for i in range(5):
        await CalibrationHistoryDocument(
            backend_name=backend, qubit_index=0,
            sampled_at=base - timedelta(hours=i),
            T1=1e-4, T2=5e-5, frequency=5e9,
            gate_error=2e-4, readout_error=1e-2, anharmonicity=-3e8,
        ).insert()

    async with AsyncClient(app=app, base_url="http://test") as ac:
        r = await ac.get(f"/api/backends/{backend}/calibration_history?days=7",
                         headers=auth_headers)
    assert r.status_code == 200
    data = r.json()
    assert data["backend_name"] == backend
    assert data["qubit_index"] is None
    assert data["days"] == 7
    assert len(data["records"]) == 5
    timestamps = [datetime.fromisoformat(rec["sampled_at"].replace("Z", "+00:00"))
                  for rec in data["records"]]
    assert timestamps == sorted(timestamps, reverse=True)


@pytest.mark.asyncio
async def test_qubit_index_filter(test_db, auth_headers):
    backend = "ibm_test"
    base = datetime.now(tz=timezone.utc)
    for q in (0, 1, 2):
        await CalibrationHistoryDocument(
            backend_name=backend, qubit_index=q, sampled_at=base,
            T1=1e-4, T2=5e-5, frequency=5e9,
            gate_error=2e-4, readout_error=1e-2, anharmonicity=-3e8,
        ).insert()

    async with AsyncClient(app=app, base_url="http://test") as ac:
        r = await ac.get(f"/api/backends/{backend}/calibration_history?days=7&qubit_index=1",
                         headers=auth_headers)
    assert r.status_code == 200
    data = r.json()
    assert data["qubit_index"] == 1
    assert len(data["records"]) == 1
    assert data["records"][0]["qubit_index"] == 1


@pytest.mark.asyncio
async def test_days_clamps_to_max_30(test_db, auth_headers):
    async with AsyncClient(app=app, base_url="http://test") as ac:
        r = await ac.get("/api/backends/ibm_test/calibration_history?days=999",
                         headers=auth_headers)
    assert r.status_code == 422  # Pydantic should reject > 30
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_calibration_history_router.py -v`
Expected: FAIL — endpoint does not yet exist (404).

- [ ] **Step 3: Add the router endpoint**

In `src/qdash/api/routers/backend.py`, add the new endpoint after the existing `/{name}/calibration` route. Add imports if missing:

```python
from datetime import datetime, timedelta, timezone
from fastapi import Query

from qdash.api.schemas.backend import (
    CalibrationHistoryRecord,
    CalibrationHistoryResponse,
)
from qdash.dbmodel.calibration_history import CalibrationHistoryDocument
```

Then add:

```python
@router.get(
    "/{name}/calibration_history",
    response_model=CalibrationHistoryResponse,
)
async def get_calibration_history(
    name: str,
    days: int = Query(default=7, ge=1, le=30,
                      description="Lookback window, max 30 days"),
    qubit_index: int | None = Query(default=None, ge=0),
    _user=Depends(verified_user),  # match the existing auth dependency name in this file
) -> CalibrationHistoryResponse:
    cutoff = datetime.now(tz=timezone.utc) - timedelta(days=days)
    query = {"backend_name": name, "sampled_at": {"$gte": cutoff}}
    if qubit_index is not None:
        query["qubit_index"] = qubit_index
    docs = await (
        CalibrationHistoryDocument
        .find(query)
        .sort([("sampled_at", -1)])
        .to_list()
    )
    return CalibrationHistoryResponse(
        backend_name=name,
        qubit_index=qubit_index,
        days=days,
        records=[
            CalibrationHistoryRecord(
                backend_name=d.backend_name,
                qubit_index=d.qubit_index,
                sampled_at=d.sampled_at,
                T1=d.T1, T2=d.T2, frequency=d.frequency,
                gate_error=d.gate_error, readout_error=d.readout_error,
                anharmonicity=d.anharmonicity, two_q_error=d.two_q_error,
            )
            for d in docs
        ],
    )
```

Match the actual auth-dependency name (`verified_user` / `current_user` / etc.) by inspecting another protected route in the same file.

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_calibration_history_router.py -v`
Expected: PASS — 3 tests green.

- [ ] **Step 5: Commit**

```bash
git add src/qdash/api/routers/backend.py tests/test_calibration_history_router.py
git commit -m "feat(backend): GET /api/backends/{name}/calibration_history endpoint"
```

---

## Task 6 — Client: FastAPIClient.getCalibrationHistory method

**Files:**
- Modify: `src/infrastructure/http/FastAPIClient.m`
- Modify: `tests/StubFastAPIClient.m`

- [ ] **Step 1: Inspect existing getCalibration method shape**

Run: `grep -nA10 "function .* = getCalibration" src/infrastructure/http/FastAPIClient.m`
Note the existing endpoint construction pattern, error handling, and return shape.

- [ ] **Step 2: Add getCalibrationHistory to the real client**

In `src/infrastructure/http/FastAPIClient.m`, add the method near `getCalibration`:

```matlab
function data = getCalibrationHistory(obj, backendName, days, token)
    % getCalibrationHistory  GET /api/backends/{name}/calibration_history
    %   Returns time-sorted (DESC) calibration samples. `days` is
    %   clamped server-side to [1..30]; default 7 if empty.
    if nargin < 3 || isempty(days); days = 7; end
    name  = FastAPIClient.encodePathSegment(char(backendName));
    qs    = sprintf('?days=%d', round(double(days)));
    url   = sprintf('%s/api/backends/%s/calibration_history%s', ...
                    obj.BaseUrl, name, qs);
    opts  = weboptions('Timeout', obj.Timeout, ...
                       'HeaderFields', FastAPIClient.authHeaders(token, obj.ProjectId));
    raw   = webread(url, opts);
    data  = JsonHelper.decodeIfJson(raw);
end
```

- [ ] **Step 3: Add the same method to the stub**

In `tests/StubFastAPIClient.m`:

```matlab
function data = getCalibrationHistory(obj, backendName, days, ~)
    if isfield(obj.StubResponses, 'getCalibrationHistory')
        data = obj.StubResponses.getCalibrationHistory;
    else
        data = struct('backend_name', char(backendName), ...
                      'qubit_index', [], 'days', days, ...
                      'records', {{}});
    end
end
```

- [ ] **Step 4: Smoke test by importing**

In MATLAB:
```matlab
client = FastAPIClient('http://localhost:5715');
methods(client)
```
Expected: `getCalibrationHistory` appears in the method list.

- [ ] **Step 5: Commit**

```bash
git add src/infrastructure/http/FastAPIClient.m tests/StubFastAPIClient.m
git commit -m "feat(http): add FastAPIClient.getCalibrationHistory + stub mirror"
```

---

## Task 7 — Client: BackendsViewModel.fetchCalibrationHistory dispatcher

**Files:**
- Modify: `src/presentation/viewmodels/BackendsViewModel.m`
- Modify: `src/presentation/app/QTAUWorkbenchApp.m`

- [ ] **Step 1: Locate existing AsyncRunner pattern in the file**

Run: `grep -n "AsyncRunner.run" src/presentation/viewmodels/BackendsViewModel.m | head`

- [ ] **Step 2: Add the dispatcher + main-thread callback**

In `BackendsViewModel.m`:

```matlab
function fetchCalibrationHistory(obj, backendName, days)
    % Dispatches GET /api/backends/{name}/calibration_history asynchronously.
    % Result lands in onCalibrationHistoryLoaded which paints sparkline + telemetry.
    app   = obj.App;
    if ~app.State.isAuthenticated(); return; end
    if isempty(backendName); return; end
    if nargin < 3 || isempty(days); days = 7; end
    svc   = app.BackendSvc;
    token = app.State.authToken;
    AsyncRunner.run( ...
        @() svc.getCalibrationHistory(backendName, days, token), ...
        @(data) obj.onCalibrationHistoryLoaded(app, backendName, data), ...
        @(ME)   Logger.debug('BackendsViewModel', ...
                    'getCalibrationHistory(%s): %s', char(backendName), ME.message));
end

function onCalibrationHistoryLoaded(obj, app, backendName, data)
    if isempty(app.CalibrationHistoryCache)
        app.CalibrationHistoryCache = struct();
    end
    safeKey = matlab.lang.makeValidName(char(backendName));
    app.CalibrationHistoryCache.(safeKey) = data;
    obj.paintInlineSparkline(app, backendName);
    obj.populateTelemetryPanel(app, backendName);
end
```

- [ ] **Step 3: Add the cache property to QTAUWorkbenchApp**

In `src/presentation/app/QTAUWorkbenchApp.m`, in the Backends-tab properties block:

```matlab
CalibrationHistoryCache = []   % struct keyed by makeValidName(backend) → response
```

- [ ] **Step 4: Smoke check**

In MATLAB: `which BackendsViewModel.m` (should print path; file still parses).

- [ ] **Step 5: Commit**

```bash
git add src/presentation/viewmodels/BackendsViewModel.m src/presentation/app/QTAUWorkbenchApp.m
git commit -m "feat(backends): async calibration-history dispatcher + AppState cache"
```

---

## Task 8 — Client: BackendsViewModel.paintInlineSparkline

**Files:**
- Modify: `src/presentation/viewmodels/BackendsViewModel.m`
- Create: `tests/test_BackendsViewModel_sparklines.m`

- [ ] **Step 1: Write the failing test**

```matlab
% tests/test_BackendsViewModel_sparklines.m
classdef test_BackendsViewModel_sparklines < matlab.unittest.TestCase
    properties
        StubApp
    end

    methods (TestMethodSetup)
        function setup(testCase)
            testCase.StubApp = StubAnalysisApp();  % reuse existing stub
            testCase.StubApp.CalibrationHistoryCache = struct();
            testCase.StubApp.BackendSparklineAxes = struct();
        end
    end

    methods (Test)
        function paint_empty_history_renders_em_dash(testCase)
            vm = BackendsViewModel(testCase.StubApp);
            ax = uiaxes(uifigure());
            testCase.StubApp.BackendSparklineAxes.ibm_test = ax;
            testCase.StubApp.CalibrationHistoryCache.ibm_test = ...
                struct('records', {{}});
            vm.paintInlineSparkline(testCase.StubApp, 'ibm_test');
            txt = findobj(ax, 'Type', 'text');
            testCase.verifyNotEmpty(txt);
            testCase.verifyEqual(char(txt(1).String), char(8212));  % em-dash
        end

        function paint_full_history_plots_line(testCase)
            vm = BackendsViewModel(testCase.StubApp);
            ax = uiaxes(uifigure());
            testCase.StubApp.BackendSparklineAxes.ibm_test = ax;
            recs = cell(1, 7);
            for i = 1:7
                recs{i} = struct( ...
                    'sampled_at', datestr(datetime(2026, 5, 3+i, 12, 0, 0), ...
                                          'yyyy-mm-ddTHH:MM:SSZ'), ...
                    'two_q_error', 8e-3 + 0.1e-3 * i);
            end
            testCase.StubApp.CalibrationHistoryCache.ibm_test = ...
                struct('records', {recs});
            vm.paintInlineSparkline(testCase.StubApp, 'ibm_test');
            ln = findobj(ax, 'Type', 'line');
            testCase.verifyNotEmpty(ln);
            testCase.verifyEqual(numel(ln(1).XData), 7);
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

In MATLAB: `runtests('tests/test_BackendsViewModel_sparklines.m')`
Expected: FAIL — `paintInlineSparkline` not yet defined.

- [ ] **Step 3: Implement paintInlineSparkline**

Add to `BackendsViewModel.m`:

```matlab
function paintInlineSparkline(~, app, backendName)
    safeKey = matlab.lang.makeValidName(char(backendName));
    if ~isfield(app.BackendSparklineAxes, safeKey); return; end
    ax = app.BackendSparklineAxes.(safeKey);
    if isempty(ax) || ~isvalid(ax); return; end
    cla(ax);
    ax.XColor = 'none'; ax.YColor = 'none';
    ax.Toolbar.Visible = 'off';

    cache = app.CalibrationHistoryCache;
    if ~isfield(cache, safeKey) || isempty(cache.(safeKey).records)
        text(ax, 0.5, 0.5, char(8212), 'Units', 'normalized', ...
             'HorizontalAlignment', 'center', ...
             'Color', Theme.COLOR_MUTED, 'FontSize', 11);
        return;
    end
    recs = cache.(safeKey).records;
    if iscell(recs)
        n = numel(recs);
        ts = NaT(1, n); vals = nan(1, n);
        for i = 1:n
            r = recs{i};
            try
                ts(i) = datetime(strrep(char(r.sampled_at), 'Z', '+00:00'), ...
                                 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ssXXX', ...
                                 'TimeZone', 'UTC');
            catch; continue; end
            v = JsonHelper.pickNumeric(r, 'two_q_error', NaN);
            if ~isnan(v); vals(i) = v; end
        end
        valid = ~isnat(ts) & ~isnan(vals);
        ts = ts(valid); vals = vals(valid);
        [ts, idx] = sort(ts); vals = vals(idx);  % API DESC → ASC for left-to-right
        if isempty(ts)
            text(ax, 0.5, 0.5, char(8212), 'Units', 'normalized', ...
                 'HorizontalAlignment', 'center', ...
                 'Color', Theme.COLOR_MUTED);
            return;
        end
        plot(ax, ts, vals, '-', 'Color', Theme.COLOR_PRIMARY, 'LineWidth', 1.4);
    end
end
```

- [ ] **Step 4: Run test to verify it passes**

In MATLAB: `runtests('tests/test_BackendsViewModel_sparklines.m')`
Expected: PASS — 2 tests green.

- [ ] **Step 5: Commit**

```bash
git add src/presentation/viewmodels/BackendsViewModel.m tests/test_BackendsViewModel_sparklines.m
git commit -m "feat(backends): paintInlineSparkline (em-dash on empty, line plot on populated)"
```

---

## Task 9 — Client: populateTelemetryPanel (Per-Qubit + History)

**Files:**
- Modify: `src/presentation/viewmodels/BackendsViewModel.m`
- Modify: `src/presentation/app/QTAUWorkbenchApp.m`

- [ ] **Step 1: Add the painter methods**

Add to `BackendsViewModel.m`:

```matlab
function populateTelemetryPanel(obj, app, backendName)
    safeKey = matlab.lang.makeValidName(char(backendName));
    if ~isfield(app.CalibrationHistoryCache, safeKey); return; end
    data = app.CalibrationHistoryCache.(safeKey);
    obj.paintTelemetryPerQubitHeatGrid(app, data);
    obj.paintTelemetryHistoryCharts(app, data);
end

function paintTelemetryPerQubitHeatGrid(~, app, data)
    if isempty(app.TelemetryPerQubitGrid) || ...
            ~isvalid(app.TelemetryPerQubitGrid)
        return;
    end
    parent = app.TelemetryPerQubitGrid;
    delete(parent.Children);
    parent.RowHeight = repmat({22}, 1, 8);
    parent.ColumnWidth = repmat({60}, 1, 16);

    metrics = {'qubit', 'T1', 'T2', 'freq', 'gate_err', 'rd_err', '2Q_err'};
    recs = data.records;
    if iscell(recs); n = numel(recs); else; n = numel(recs); end
    per_qubit = containers.Map('KeyType', 'int32', 'ValueType', 'any');
    for i = 1:n
        r = recs(i); if iscell(recs); r = recs{i}; end
        qi = int32(JsonHelper.pickNumeric(r, 'qubit_index', -1));
        if qi < 0; continue; end
        if ~isKey(per_qubit, qi)
            per_qubit(qi) = r;
        end
    end
    qubits = sort(cell2mat(keys(per_qubit)));

    for c = 1:min(numel(qubits), 16)
        lbl = uilabel(parent, 'Text', sprintf('q[%d]', qubits(c)), ...
                      'FontSize', 10, 'FontWeight', 'bold');
        lbl.Layout.Row = 1; lbl.Layout.Column = c;
    end
    for m = 2:numel(metrics)
        for c = 1:min(numel(qubits), 16)
            r = per_qubit(qubits(c));
            switch metrics{m}
                case 'T1';       v = JsonHelper.pickNumeric(r, 'T1', NaN);
                case 'T2';       v = JsonHelper.pickNumeric(r, 'T2', NaN);
                case 'freq';     v = JsonHelper.pickNumeric(r, 'frequency', NaN);
                case 'gate_err'; v = JsonHelper.pickNumeric(r, 'gate_error', NaN);
                case 'rd_err';   v = JsonHelper.pickNumeric(r, 'readout_error', NaN);
                case '2Q_err';   v = JsonHelper.pickNumeric(r, 'two_q_error', NaN);
            end
            color = BackendsViewModel.healthColor(metrics{m}, v);
            lbl = uilabel(parent, ...
                'Text', BackendsViewModel.fmtMetric(metrics{m}, v), ...
                'FontSize', 10, 'BackgroundColor', color);
            lbl.Layout.Row = m; lbl.Layout.Column = c;
        end
    end
end

function paintTelemetryHistoryCharts(~, app, data)
    if isempty(app.TelemetryHistoryAxes) || numel(app.TelemetryHistoryAxes) < 3
        return;
    end
    fields = {'T1', 'T2', 'two_q_error'};
    titles = {'T1 (s)', 'T2 (s)', '2Q gate error'};
    recs   = data.records;
    if iscell(recs); n = numel(recs); else; n = numel(recs); end
    for k = 1:3
        ax = app.TelemetryHistoryAxes{k};
        if isempty(ax) || ~isvalid(ax); continue; end
        cla(ax); ax.Title.String = titles{k};
        ts = NaT(1, n); vals = nan(1, n);
        for i = 1:n
            r = recs(i); if iscell(recs); r = recs{i}; end
            try
                ts(i) = datetime(strrep(char(r.sampled_at), 'Z', '+00:00'), ...
                                 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ssXXX', ...
                                 'TimeZone', 'UTC');
            catch; continue; end
            vals(i) = JsonHelper.pickNumeric(r, fields{k}, NaN);
        end
        valid = ~isnat(ts) & ~isnan(vals);
        if any(valid)
            [tsS, idx] = sort(ts(valid)); vS = vals(valid); vS = vS(idx);
            plot(ax, tsS, vS, '-', 'Color', Theme.COLOR_PRIMARY, ...
                 'LineWidth', 1.4);
            ax.XGrid = 'on'; ax.YGrid = 'on';
        end
    end
end
```

Add static helpers at the bottom of the class (or to the existing static private block):

```matlab
methods (Static, Access = private)
    function c = healthColor(metric, v)
        c = Theme.COLOR_CARD;
        if isnan(v); return; end
        switch metric
            case {'gate_err','rd_err','2Q_err'}
                if v < 5e-3;       c = [0.85 0.95 0.85];
                elseif v < 2e-2;   c = [1.00 0.95 0.80];
                else;              c = [0.99 0.83 0.83];
                end
            case 'T1'
                if v > 1e-4;       c = [0.85 0.95 0.85];
                elseif v > 5e-5;   c = [1.00 0.95 0.80];
                else;              c = [0.99 0.83 0.83];
                end
            case 'T2'
                if v > 7e-5;       c = [0.85 0.95 0.85];
                elseif v > 3e-5;   c = [1.00 0.95 0.80];
                else;              c = [0.99 0.83 0.83];
                end
        end
    end
    function s = fmtMetric(metric, v)
        if isnan(v); s = char(8212); return; end
        switch metric
            case 'T1';       s = sprintf('%.0f us', v * 1e6);
            case 'T2';       s = sprintf('%.0f us', v * 1e6);
            case 'freq';     s = sprintf('%.2f GHz', v / 1e9);
            case 'gate_err'; s = sprintf('%.1e', v);
            case 'rd_err';   s = sprintf('%.1e', v);
            case '2Q_err';   s = sprintf('%.1e', v);
            otherwise;       s = sprintf('%g', v);
        end
    end
end
```

- [ ] **Step 2: Add new property handles to QTAUWorkbenchApp**

In the Backends-tab properties block:

```matlab
TelemetryPerQubitGrid    % uigridlayout for the Per-Qubit heat grid
TelemetryHistoryAxes     % {1×3} cell of uiaxes for History sparklines (T1/T2/2Q)
BackendSparklineAxes     % struct keyed by makeValidName(backend) → uiaxes
```

- [ ] **Step 3: Smoke check**

In MATLAB: `runtests('tests')` — existing tests still pass; no regression. The new painters are exercised once Task 10 wires them.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/viewmodels/BackendsViewModel.m src/presentation/app/QTAUWorkbenchApp.m
git commit -m "feat(backends): populateTelemetryPanel — Per-Qubit heat grid + 3 History sparklines"
```

---

## Task 10 — Client: BackendsScreen UI scaffolding (tab strip + sparkline column)

**Files:**
- Modify: `src/presentation/screens/BackendsScreen.m`

- [ ] **Step 1: Inspect current BackendStatusArea construction**

Run: `grep -nA20 "BackendStatusArea" src/presentation/screens/BackendsScreen.m | head -40`
Identify the parent grid where it lives. Note its `Layout.Row` and `Layout.Column` values.

- [ ] **Step 2: Replace BackendStatusArea with a uitabgroup**

In `BackendsScreen.m`, replace the line `app.BackendStatusArea = uitextarea(parent, ...)` with:

```matlab
% C2.B1 — Telemetry tab strip: Overview | Per-Qubit | History
tg = uitabgroup(parent);
tg.Layout.Row = oldRow; tg.Layout.Column = oldCol;  % use the prior values

tabOverview = uitab(tg, 'Title', Labels.get('backends_telemetry_overview', 'Overview'));
tabOverview.BackgroundColor = Theme.COLOR_CARD;
overviewGrid = uigridlayout(tabOverview, [1 1]);
overviewGrid.Padding = [12 8 12 8];
app.BackendStatusArea = uitextarea(overviewGrid, ...
    'Editable', 'off', 'FontSize', 12);

tabPerQubit = uitab(tg, 'Title', Labels.get('backends_telemetry_perqubit', 'Per-Qubit'));
tabPerQubit.BackgroundColor = Theme.COLOR_CARD;
app.TelemetryPerQubitGrid = uigridlayout(tabPerQubit, [8 16]);
app.TelemetryPerQubitGrid.Padding = [12 8 12 8];
app.TelemetryPerQubitGrid.RowSpacing = 2;
app.TelemetryPerQubitGrid.ColumnSpacing = 2;

tabHistory = uitab(tg, 'Title', Labels.get('backends_telemetry_history', 'History'));
tabHistory.BackgroundColor = Theme.COLOR_CARD;
historyGrid = uigridlayout(tabHistory, [3 1]);
historyGrid.Padding = [12 8 12 8];
app.TelemetryHistoryAxes = cell(1, 3);
for k = 1:3
    app.TelemetryHistoryAxes{k} = uiaxes(historyGrid);
    app.TelemetryHistoryAxes{k}.Layout.Row = k;
    app.TelemetryHistoryAxes{k}.Layout.Column = 1;
end
```

- [ ] **Step 3: Add the parallel sparkline-column overlay**

In the same file, near where the `BackendTable` is constructed, add:

```matlab
% Sparkline column overlay — one uiaxes per row, populated when the table loads.
maxRows = 50;
app.BackendSparklineGrid = uigridlayout(parentGridForSparklines, [maxRows 1]);
app.BackendSparklineGrid.RowHeight = repmat({22}, 1, maxRows);
app.BackendSparklineGrid.Padding = [0 0 0 0];
app.BackendSparklineAxes = struct();
```

(Use whatever parent grid hosts the table — typically `bodyGrid` or similar. The sparkline grid is a sibling that visually aligns with the table rows.)

- [ ] **Step 4: Add the new property handles to QTAUWorkbenchApp**

```matlab
BackendSparklineGrid     % overlay grid that mirrors the BackendTable rows
```

- [ ] **Step 5: Manual smoke**

In MATLAB: `run('QTAUWorkbenchLauncher.m')` → Login → Backends tab.
Expected: Overview / Per-Qubit / History tabs visible inside the panel that previously held the plain text area; tabs all empty initially.

- [ ] **Step 6: Commit**

```bash
git add src/presentation/screens/BackendsScreen.m src/presentation/app/QTAUWorkbenchApp.m
git commit -m "feat(backends): UI scaffolding — Telemetry tab strip + sparkline column overlay"
```

---

## Task 11 — Client: Wire sparkline rendering into table population

**Files:**
- Modify: `src/presentation/viewmodels/BackendsViewModel.m`

- [ ] **Step 1: Find the existing populate-table callback**

Run: `grep -n "BackendTable.Data\|populateBackend" src/presentation/viewmodels/BackendsViewModel.m`
Locate the method that assigns `app.BackendTable.Data = ...`.

- [ ] **Step 2: Append sparkline-axes creation + history dispatch**

Right after the `app.BackendTable.Data = ...` assignment in that method, add:

```matlab
% Create one uiaxes per backend row, then dispatch fetchCalibrationHistory async.
n = size(app.BackendTable.Data, 1);
for r = 1:n
    name = char(app.BackendTable.Data{r, 1});
    if isempty(name); continue; end
    safeKey = matlab.lang.makeValidName(name);
    ax = uiaxes(app.BackendSparklineGrid);
    ax.Layout.Row = r; ax.Layout.Column = 1;
    ax.XColor = 'none'; ax.YColor = 'none';
    ax.Toolbar.Visible = 'off';
    app.BackendSparklineAxes.(safeKey) = ax;
    obj.fetchCalibrationHistory(name, 7);
end
```

(Adjust column index `1` if the backend name is in a different table column.)

- [ ] **Step 3: Manual smoke**

Re-launch app → Backends tab. After ~2-5 s each row's sparkline renders either a tiny line plot (if 7 days of history exist) or an em-dash.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/viewmodels/BackendsViewModel.m
git commit -m "feat(backends): per-row sparkline axes + parallel history dispatch on table populate"
```

---

## Task 12 — Client: Compare-mode state on ResultsViewModel

**Files:**
- Modify: `src/presentation/viewmodels/ResultsViewModel.m`
- Create: `tests/test_CompareMode.m`

- [ ] **Step 1: Write the failing test for diff math**

```matlab
% tests/test_CompareMode.m
classdef test_CompareMode < matlab.unittest.TestCase
    methods (Test)
        function diff_strip_computes_deltas(testCase)
            left  = struct('fidelity', 0.92, 'shots', 4096, ...
                           'kl_divergence', 0.0042, 'success_rate', 0.88);
            right = struct('fidelity', 0.97, 'shots', 8192, ...
                           'kl_divergence', 0.0021, 'success_rate', 0.94);
            d = ResultsViewModel.computeDiffStrip(left, right);
            testCase.verifyEqual(d.dFidelity, 0.05, 'AbsTol', 1e-9);
            testCase.verifyEqual(d.dShots, 4096);
            testCase.verifyEqual(d.dKL, -0.0021, 'AbsTol', 1e-9);
            testCase.verifyEqual(d.dSuccess, 0.06, 'AbsTol', 1e-9);
        end

        function diff_handles_missing_fields(testCase)
            left  = struct('fidelity', 0.9);
            right = struct();
            d = ResultsViewModel.computeDiffStrip(left, right);
            testCase.verifyTrue(isnan(d.dFidelity));
        end
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

In MATLAB: `runtests('tests/test_CompareMode.m')`
Expected: FAIL — `computeDiffStrip` not defined.

- [ ] **Step 3: Add Compare state + diff math**

Add to the `properties (Access = private)` block in `ResultsViewModel.m`:

```matlab
CompareMode  logical = false
LeftJobData  = []
RightJobData = []
PendingLoadFlags = struct('left', false, 'right', false)
```

Add public callbacks in the main `methods` block:

```matlab
function onEnterCompareMode(obj)
    app = obj.App;
    DialogBuilder.buildJobPickerDialog(app, ...
        @(secondJobId) obj.onCompareJobPicked(app, secondJobId));
end

function onCompareJobPicked(obj, app, secondJobId)
    if isempty(secondJobId); return; end
    obj.CompareMode = true;
    obj.PendingLoadFlags = struct('left', false, 'right', false);
    leftJobId  = char(app.State.selectedJobId);
    rightJobId = char(secondJobId);
    svc   = app.JobSvc;
    token = app.State.authToken;
    AsyncRunner.run( ...
        @() svc.getJobResult(leftJobId, token), ...
        @(d) obj.onCompareJobLoaded(app, 'left', d), ...
        @(ME) obj.onCompareJobError(app, 'left', ME));
    AsyncRunner.run( ...
        @() svc.getJobResult(rightJobId, token), ...
        @(d) obj.onCompareJobLoaded(app, 'right', d), ...
        @(ME) obj.onCompareJobError(app, 'right', ME));
end

function onCompareJobLoaded(obj, app, side, data)
    if strcmp(side, 'left'); obj.LeftJobData = data;
    else;                    obj.RightJobData = data; end
    obj.PendingLoadFlags.(side) = true;
    if obj.PendingLoadFlags.left && obj.PendingLoadFlags.right
        obj.repaintCompareSplit(app);
    end
end

function onCompareJobError(~, app, side, ME)
    Logger.warn('ResultsViewModel', ...
        'Compare load (%s): %s', side, ME.message);
    app.showError('Compare', ME);
end

function onExitCompareMode(obj)
    obj.CompareMode  = false;
    obj.RightJobData = [];
    obj.repaintSingleColumn(obj.App);
end
```

Add static diff helpers:

```matlab
methods (Static)
    function d = computeDiffStrip(left, right)
        d = struct( ...
            'dFidelity', ResultsViewModel.deltaField(left, right, 'fidelity'), ...
            'dShots',    ResultsViewModel.deltaField(left, right, 'shots'), ...
            'dKL',       ResultsViewModel.deltaField(left, right, 'kl_divergence'), ...
            'dSuccess',  ResultsViewModel.deltaField(left, right, 'success_rate'));
    end
end

methods (Static, Access = private)
    function v = deltaField(a, b, field)
        if ~isfield(a, field) || ~isfield(b, field); v = NaN; return; end
        v = b.(field) - a.(field);
    end
end
```

(`repaintCompareSplit` and `repaintSingleColumn` are filled in Task 13. For now, add stubs that do nothing so the file parses:)

```matlab
function repaintCompareSplit(~, ~)
    % Filled in Task 13.
end

function repaintSingleColumn(~, ~)
    % Filled in Task 13.
end
```

- [ ] **Step 4: Run test to verify it passes**

In MATLAB: `runtests('tests/test_CompareMode.m')`
Expected: PASS — 2 tests green.

- [ ] **Step 5: Commit**

```bash
git add src/presentation/viewmodels/ResultsViewModel.m tests/test_CompareMode.m
git commit -m "feat(results): Compare-mode state + diff strip math"
```

---

## Task 13 — Client: ResultsScreen Compare button + 2-up grid + paint methods

**Files:**
- Modify: `src/presentation/screens/ResultsScreen.m`
- Modify: `src/presentation/viewmodels/ResultsViewModel.m`
- Modify: `src/presentation/app/QTAUWorkbenchApp.m`

- [ ] **Step 1: Add the Compare button + 2-up grid scaffolding to ResultsScreen.m**

Find the existing toolbar uigridlayout. Add:

```matlab
compareBtn = uibutton(toolbar, ...
    'Text', Labels.get('results_compare_button', [char(8644) ' Compare with' char(8230)]), ...
    'ButtonPushedFcn', @(~,~) app.ResultsVm.onEnterCompareMode());
compareBtn.Layout.Row = 1; compareBtn.Layout.Column = newColIndex;
if ~AppConfig.getBool('feature_compare_mode_enabled', true)
    compareBtn.Visible = 'off';
end
app.styleBtn(compareBtn, 'secondary');
app.ResultsCompareBtn = compareBtn;
```

Wrap the existing chart parent in a 2-column grid:

```matlab
app.ResultsSplitGrid = uigridlayout(card, [1 2]);
app.ResultsSplitGrid.ColumnWidth = {'1x', 0};
app.ResultsSplitGrid.Padding = [0 0 0 0];
app.ResultsSplitGrid.ColumnSpacing = 12;
app.ResultsLeftPanel  = uipanel(app.ResultsSplitGrid, 'Title', '', 'BorderType', 'none');
app.ResultsLeftPanel.Layout.Row = 1; app.ResultsLeftPanel.Layout.Column = 1;
app.ResultsRightPanel = uipanel(app.ResultsSplitGrid, 'Title', '', 'BorderType', 'none');
app.ResultsRightPanel.Layout.Row = 1; app.ResultsRightPanel.Layout.Column = 2;
```

Move the existing chart parent to be a child of `app.ResultsLeftPanel` (not the card directly).

Add the diff-strip panel above the split grid:

```matlab
app.ResultsDiffStrip = uipanel(card, 'Title', '', 'BorderType', 'none');
% Place it on the row immediately above ResultsSplitGrid.
```

- [ ] **Step 2: Add property handles to QTAUWorkbenchApp**

```matlab
ResultsCompareBtn
ResultsSplitGrid
ResultsLeftPanel
ResultsRightPanel
ResultsDiffStrip
ResultsCompareCloseBtn
```

- [ ] **Step 3: Replace the stubs in ResultsViewModel.m with real paint methods**

Replace `repaintCompareSplit` and `repaintSingleColumn` with:

```matlab
function repaintCompareSplit(obj, app)
    if isempty(app.ResultsSplitGrid) || ~isvalid(app.ResultsSplitGrid); return; end
    app.ResultsSplitGrid.ColumnWidth = {'1x', '1x'};
    obj.renderJobInto(app.ResultsLeftPanel,  obj.LeftJobData);
    obj.renderJobInto(app.ResultsRightPanel, obj.RightJobData);
    obj.paintDiffStrip(app);
    if isempty(app.ResultsCompareCloseBtn) || ~isvalid(app.ResultsCompareCloseBtn)
        app.ResultsCompareCloseBtn = uibutton(app.ResultsRightPanel, ...
            'Text', char(215), ...
            'Position', [10 10 22 22], ...
            'ButtonPushedFcn', @(~,~) obj.onExitCompareMode());
    else
        app.ResultsCompareCloseBtn.Visible = 'on';
    end
end

function repaintSingleColumn(~, app)
    if isempty(app.ResultsSplitGrid) || ~isvalid(app.ResultsSplitGrid); return; end
    app.ResultsSplitGrid.ColumnWidth = {'1x', 0};
    delete(app.ResultsRightPanel.Children);
    if ~isempty(app.ResultsCompareCloseBtn) && isvalid(app.ResultsCompareCloseBtn)
        app.ResultsCompareCloseBtn.Visible = 'off';
    end
end

function renderJobInto(~, parentPanel, jobData)
    delete(parentPanel.Children);
    if isempty(jobData); return; end
    g = uigridlayout(parentPanel, [3 1]);
    g.RowHeight = {120, '1x', 100};
    fidPanel  = uipanel(g, 'Title', '', 'BorderType', 'none'); fidPanel.Layout.Row  = 1;
    histPanel = uipanel(g, 'Title', '', 'BorderType', 'none'); histPanel.Layout.Row = 2;
    budgPanel = uipanel(g, 'Title', '', 'BorderType', 'none'); budgPanel.Layout.Row = 3;
    ResultsViewModel.renderFidelityCard(fidPanel, jobData);
    ResultsViewModel.renderResultsHistogram(histPanel, jobData);
    ResultsViewModel.renderErrorBudgetWaterfall(budgPanel, jobData);
end

function paintDiffStrip(obj, app)
    if isempty(app.ResultsDiffStrip) || ~isvalid(app.ResultsDiffStrip); return; end
    delete(app.ResultsDiffStrip.Children);
    d = ResultsViewModel.computeDiffStrip(obj.LeftJobData, obj.RightJobData);
    g = uigridlayout(app.ResultsDiffStrip, [1 4]);
    g.ColumnWidth = repmat({'1x'}, 1, 4); g.Padding = [4 4 4 4];
    obj.diffCell(g, 1, Labels.get('results_compare_diff_fidelity', 'Δ Fidelity'), ...
                 d.dFidelity, '%.4f', true);
    obj.diffCell(g, 2, Labels.get('results_compare_diff_shots', 'Δ Shots'), ...
                 d.dShots, '%d', false);
    obj.diffCell(g, 3, Labels.get('results_compare_diff_kl', 'Δ KL-div'), ...
                 d.dKL, '%.4f', false);
    obj.diffCell(g, 4, Labels.get('results_compare_diff_success', 'Δ Success %'), ...
                 d.dSuccess, '%.3f', true);
end

function diffCell(~, parent, col, label, value, fmt, biggerIsBetter)
    cell = uipanel(parent, 'Title', '', 'BorderType', 'line');
    cell.Layout.Row = 1; cell.Layout.Column = col;
    cellGrid = uigridlayout(cell, [2 1]); cellGrid.RowHeight = {16, 24};
    uilabel(cellGrid, 'Text', label, 'FontSize', 10, 'FontColor', Theme.COLOR_MUTED);
    if isnan(value)
        uilabel(cellGrid, 'Text', char(8212), 'FontSize', 16, ...
                'FontColor', Theme.COLOR_MUTED);
    else
        valueLbl = uilabel(cellGrid, 'Text', sprintf(fmt, value), ...
            'FontSize', 16, 'FontWeight', 'bold');
        better = (value > 0) == biggerIsBetter;
        if value == 0
            valueLbl.FontColor = Theme.COLOR_MUTED;
        elseif better
            valueLbl.FontColor = Theme.COLOR_SUCCESS;
        else
            valueLbl.FontColor = Theme.COLOR_DANGER;
        end
    end
end
```

- [ ] **Step 4: Manual smoke**

Launch app → run two jobs (or `run('scripts/seed_jobs.m')` if seed is wired) → Results tab → click `⇄ Compare with…` → JobPicker modal opens → pick a job → 2-up split renders with diff strip → click `×` → grid collapses.

- [ ] **Step 5: Commit**

```bash
git add src/presentation/screens/ResultsScreen.m src/presentation/viewmodels/ResultsViewModel.m src/presentation/app/QTAUWorkbenchApp.m
git commit -m "feat(results): Compare-mode UI — 2-up split + diff strip + close affordance"
```

---

## Task 14 — Client: JobPickerDialog modal builder

**Files:**
- Modify: `src/presentation/DialogBuilder.m`

- [ ] **Step 1: Add the dialog builder**

In `DialogBuilder.m`:

```matlab
function buildJobPickerDialog(app, callback)
    % Modal listing completed jobs in the project. callback(jobId) fires
    % on confirm; cancel closes silently.
    figPos = app.UIFigure.Position;
    w = 720; h = 480;
    pos = [figPos(1) + (figPos(3)-w)/2, figPos(2) + (figPos(4)-h)/2, w, h];
    dlg = uifigure('Name', Labels.get('results_compare_picker_title', ...
                       'Pick a job to compare with'), ...
                   'Position', pos, ...
                   'WindowStyle', 'modal', ...
                   'Color', Theme.COLOR_BG);

    g = uigridlayout(dlg, [3 1]);
    g.RowHeight = {28, '1x', 44};
    g.Padding = [16 12 16 12]; g.RowSpacing = 8;
    g.BackgroundColor = Theme.COLOR_CARD;

    uilabel(g, 'Text', 'Pick a completed job to compare against the currently-displayed result.', ...
            'FontSize', 12, 'FontColor', Theme.COLOR_MUTED);

    tbl = uitable(g, ...
        'ColumnName', {'Submitted', 'Job ID', 'Backend', 'Circuit', 'Fidelity'}, ...
        'ColumnWidth', {140, 220, 120, 160, 80}, ...
        'RowName', {}, ...
        'Data', cell(0, 5), ...
        'SelectionType', 'row', ...
        'Multiselect', 'off');
    tbl.Layout.Row = 2;

    footer = uigridlayout(g, [1 3]);
    footer.Layout.Row = 3;
    footer.ColumnWidth = {'1x', 100, 120}; footer.ColumnSpacing = 8;
    footer.BackgroundColor = Theme.COLOR_CARD;
    statusLbl = uilabel(footer, 'Text', 'Loading jobs...', ...
                        'FontSize', 11, 'FontColor', Theme.COLOR_MUTED);
    statusLbl.Layout.Row = 1; statusLbl.Layout.Column = 1;
    cancelBtn = uibutton(footer, 'Text', 'Cancel', ...
                         'ButtonPushedFcn', @(~,~) delete(dlg));
    cancelBtn.Layout.Row = 1; cancelBtn.Layout.Column = 2;
    pickBtn = uibutton(footer, 'Text', 'Use this job', 'Enable', 'off');
    pickBtn.Layout.Row = 1; pickBtn.Layout.Column = 3;
    app.styleBtn(pickBtn, 'primary');

    pickBtn.ButtonPushedFcn = @(~,~) onPick(tbl, dlg, callback);
    tbl.SelectionChangedFcn = @(src,~) toggleEnable(pickBtn, src);

    svc = app.JobSvc; token = app.State.authToken;
    currentJobId = char(app.State.selectedJobId);
    AsyncRunner.run( ...
        @() svc.listJobs(token, 0, 200), ...
        @(data) populate(tbl, statusLbl, data, currentJobId), ...
        @(ME)   onLoadError(statusLbl, ME));

    function toggleEnable(btn, src)
        if isempty(src.Selection); btn.Enable = 'off'; else; btn.Enable = 'on'; end
    end

    function onPick(tableHandle, dialog, cb)
        sel = tableHandle.Selection;
        if isempty(sel); return; end
        row = sel(1);
        jobId = char(tableHandle.Data{row, 2});
        delete(dialog);
        cb(jobId);
    end

    function populate(tableHandle, status, data, currentJob)
        items = JsonHelper.extractList(data, 'jobs');
        rows = cell(0, 5);
        n = numel(items);
        for i = 1:n
            it = items(i); if iscell(items); it = items{i}; end
            jid = char(JsonHelper.pick(it, {'job_id','id'}));
            if strcmp(jid, currentJob); continue; end
            stat = lower(char(JsonHelper.pick(it, {'status'}, '')));
            if ~strcmp(stat, 'completed'); continue; end
            rows{end+1, 1} = char(JsonHelper.pick(it, {'submitted_at','created_at'})); %#ok<AGROW>
            rows{end,   2} = jid;
            rows{end,   3} = char(JsonHelper.pick(it, {'backend_name','backend'}));
            rows{end,   4} = char(JsonHelper.pick(it, {'circuit_name','circuit'}));
            rows{end,   5} = char(JsonHelper.pick(it, {'fidelity'}));
        end
        tableHandle.Data = rows;
        if isempty(rows)
            status.Text = Labels.get('results_compare_picker_empty', ...
                'No other completed jobs in this project.');
        else
            status.Text = sprintf('%d completed job(s) available.', size(rows, 1));
        end
    end

    function onLoadError(status, ME)
        status.Text = sprintf('Failed to load jobs: %s', ME.message);
        status.FontColor = Theme.COLOR_DANGER;
    end
end
```

- [ ] **Step 2: Smoke check**

Launch app → Results tab → Compare button → JobPicker modal opens → list populates → pick a job → dialog closes → Compare flow runs.

- [ ] **Step 3: Commit**

```bash
git add src/presentation/DialogBuilder.m
git commit -m "feat(dialog): JobPickerDialog modal — async job-list load with current-job filter"
```

---

## Task 15 — Labels + feature flag

**Files:**
- Modify: `resources/labels.properties`
- Modify: `resources/app.properties`

- [ ] **Step 1: Add new label keys**

Append to `resources/labels.properties`:

```properties
# C2 telemetry + compare
backends_telemetry_overview        = Overview
backends_telemetry_perqubit        = Per-Qubit
backends_telemetry_history         = History
backends_telemetry_loading         = Loading calibration history…
backends_telemetry_empty           = No history yet — populates after the first 24 h of usage.
results_compare_button             = ⇄ Compare with…
results_compare_picker_title       = Pick a job to compare with
results_compare_picker_empty       = No other completed jobs in this project.
results_compare_diff_fidelity      = Δ Fidelity
results_compare_diff_shots         = Δ Shots
results_compare_diff_kl            = Δ KL-div
results_compare_diff_success       = Δ Success %
```

- [ ] **Step 2: Add the feature flag**

Append to `resources/app.properties`:

```properties
# C2 — Compare-mode toolbar button on Results screen.
# Set to false to roll back without redeploying.
feature_compare_mode_enabled = true
```

- [ ] **Step 3: Verify Labels.reload picks them up**

In MATLAB:
```matlab
Labels.reload();
disp(Labels.get('results_compare_button', 'fallback'))
```
Expected: `⇄ Compare with…`

- [ ] **Step 4: Commit**

```bash
git add resources/labels.properties resources/app.properties
git commit -m "feat(labels): C2 telemetry + compare-mode strings + feature flag"
```

---

## Task 16 — Final smoke + docs

- [ ] **Step 1: Run all tests**

```bash
# Server (in sqk-qtau repo)
pytest tests/ -v

# Client (in sqk-qtau-matlab repo, MATLAB R2025b)
runtests('tests')
```
Expected: all green; 4 new tests on server, 2 new test files on client.

- [ ] **Step 2: Walk the smoke checklist**

1. Login → Backends tab → Overview / Per-Qubit / History tabs visible.
2. Sparkline column shows em-dashes (or lines if 7+ days of history exist).
3. Click a backend row → Per-Qubit heat-grid populates color-coded; History tab shows up to 3 sparklines.
4. Run two jobs → Results tab.
5. Click `⇄ Compare with…` → JobPicker modal opens → list populates.
6. Select a job → Use this job → modal closes → 2-up split renders with diff strip.
7. Click `×` on the right panel → grid collapses to 1-column → second job dropped.
8. Set `feature_compare_mode_enabled = false` → `Labels.reload(); AppConfig.reload();` → Compare button hidden.

- [ ] **Step 3: Update CLAUDE.md**

Edit `CLAUDE.md`:
- Backends row in screens table: append "Now hosts Telemetry tab strip (Overview/Per-Qubit/History) + sparkline column."
- Results row in screens table: append "Now supports Compare mode (2-up split, diff strip)."
- Backend API section: add `GET /api/backends/{name}/calibration_history` with one-line description.

- [ ] **Step 4: Commit docs**

```bash
git add CLAUDE.md
git commit -m "docs(claude): note C2 — Telemetry tabs, Compare mode, /calibration_history endpoint"
```

---

## Self-review

- All 11 modified/created files in the spec's "Files inventory" map to tasks above (no gaps).
- Method signatures referenced in later tasks (`computeDiffStrip`, `paintInlineSparkline`, `populateTelemetryPanel`, `fetchCalibrationHistory`, `repaintCompareSplit`, `repaintSingleColumn`) match exactly across earlier definitions.
- Server-side write-through is best-effort with explicit log-and-continue.
- Compare mode is feature-flagged per the spec's roll-back requirement.
- No "TODO", no "implement later", no "verify behavior" placeholders — every step has actual code or actual command.

End of plan.
