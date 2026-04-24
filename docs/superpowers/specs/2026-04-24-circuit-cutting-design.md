# Circuit Cutting + Distributed Reconstruction — Design Spec

**Status:** Approved · **Date:** 2026-04-24 · **Repos touched:** `sqk-qtau` (backend), `sqk-qtau-matlab` (UI).

## Problem

Current IBM Quantum fleet caps at ~127–156 qubits per backend, but real workloads (medical imaging, QMC, materials simulation) need circuits wider than any single chip. The app must let users

1. run a circuit too large for one backend by splitting it into *k* subcircuits,
2. submit the *k* subcircuits concurrently across *k* backends,
3. reconstruct the original circuit's observables (or domain-specific outputs) from the subcircuit measurements.

## Decisions

| # | Decision |
|---|----------|
| 1 | Two-phase delivery: **Phase 1** ships a generic cutting platform (Option A); **Phase 2** adds a preset layer for domain-specific workflows (Option C — e.g. the existing 160Q/3-QPU CT imaging notebook) as thin subclasses of the generic pipeline. Option B (only expose the notebook) is rejected because the app is a workbench, not a single-experiment runner. |
| 2 | UX placement is **F**: a dedicated "Circuit Cutting" screen in the sidebar, plus yellow banners on Benchmark / Prediction screens when `circuit.num_qubits > max(pool qubits)` that deep-link into it. |
| 3 | Three execution modes on the Cutting screen: **Automatic** (one click, everything auto), **Assisted** (defaults pre-filled, user can override any field — *default mode*), **Manual** (empty form, user enters cuts / backends / observables). All three share the same backend pipeline; only the UI auto-fill differs. |
| 4 | Output format is **L**: expectation values of Pauli observables as the default (native to `qiskit-addon-cutting`), opt-in full bitstring-distribution reconstruction as a checkbox (extra shots + shadow-style post-processing), preset-specific output (e.g. CT image) as Option C hook. |
| 5 | Backend orchestration is **O** (mode-aware): Automatic mode uses pool auto-assignment with self-healing retry on spares; Assisted mode pre-fills with the top-*k* suggestions the user can swap; Manual mode is pure user-picks-*k* with no auto-assignment. |
| 6 | Architecture is **A2**: three layers — `CuttingService` (stateless math), `CuttingBatchService` (orchestration + persistence), `CuttingPipeline` (5-stage abstract class with `GenericPipeline` default; Option C presets subclass it). Child subcircuit runs are regular `IBMJobDocument` rows tagged `batch_id` + `cut_role` so they surface on the Jobs screen with a `⤴ batch` badge. |

## Architecture

### Layered components (backend)

```
qdash/api/
├── services/
│   ├── cutting_service.py         # stateless: analyze / partition / reconstruct math
│   ├── cutting_batch_service.py   # orchestrator: lifecycle, poll children, persist
│   └── cutting/
│       ├── base.py                # CuttingPipeline ABC + GenericPipeline
│       └── presets.py             # PRESETS dict; Option C subclasses
├── schemas/cutting.py             # Pydantic DTOs
└── routers/cutting.py             # /api/cutting/* endpoints

qdash/dbmodel/cutting_batch.py     # CuttingBatchDocument
qdash/repository/cutting_batch.py  # Mongo repo
```

`IBMJobDocument` gains two optional fields — `batch_id: str | None` and `cut_role: str | None` (e.g. `"subcircuit_0"`).

### Data model — `CuttingBatchDocument`

```python
project_id: str
circuit_id: str
batch_id: str                              # uuid4
mode: Literal["automatic", "assisted", "manual"]
preset: str                                # default "generic"; "ct_imaging_160q" for Option C
cut_plan: dict                             # {cuts: [...], k: int, sampling_overhead: float}
backend_assignments: list[BackendAssignment]   # [{subcircuit_idx, backend_name, shots}]
observables: list[str]                     # Pauli strings; [] = default all-Z
opt_in_distribution: bool
child_job_ids: list[str]
status: Literal["queued", "partitioning", "executing", "reconstructing",
                "completed", "partial_failure", "failed", "cancelled"]
progress_pct: int                          # 0-100, derived from child states
reconstruction: dict | None                # {expectations: [...], distribution?, preset_output?}
error: str | None
timeout_hours: float                       # default 6.0
retry_strategy: Literal["none", "auto_spare_2x"]   # auto in Automatic mode
created_at, submitted_at, completed_at: datetime
```

### Pipeline stages

```python
class CuttingPipeline(ABC):
    meta: ClassVar[PresetMeta]          # id, name, qubit_range, output_type, required_structure

    @abstractmethod
    def analyze_cuts(self, circuit, target_k) -> CutPlan: ...
    @abstractmethod
    def partition(self, circuit, cut_plan) -> list[Subcircuit]: ...
    @abstractmethod
    def select_backends(self, subcircuits, pool, mode) -> list[BackendAssignment]: ...
    @abstractmethod
    def reconstruct_expectations(self, subcircuit_results, observables) -> dict: ...

    def post_process(self, reconstruction, context) -> dict:
        """Optional preset-specific transformation. Identity by default."""
        return reconstruction
```

`GenericPipeline(CuttingPipeline)` uses `qiskit-addon-cutting` helpers (`find_cuts`, `partition_circuit_qpd`, `reconstruct_expectation_values`).

`CTImaging160QPipeline(GenericPipeline)` (Phase 2) overrides `analyze_cuts` (fixed 54+53+53 split) and `post_process` (CT image reconstruction from subcircuit measurements — sourced from the existing notebook).

### API endpoints

| Method | Path | Purpose | Auth |
|---|---|---|---|
| `POST` | `/api/cutting/analyze` | Return cut candidates + overhead estimates + suggested k for a given circuit | Bearer |
| `GET` | `/api/cutting/presets` | List registered presets with metadata | Bearer |
| `POST` | `/api/circuits/{circuit_id}/cutting/batches` | Create + submit a batch → `202 {batch_id}` | Bearer |
| `GET` | `/api/cutting/batches/{batch_id}` | Poll status + progress + per-child state | Bearer |
| `GET` | `/api/cutting/batches/{batch_id}/result` | Reconstructed output (expectations + optional distribution + optional preset_output) | Bearer |
| `DELETE` | `/api/cutting/batches/{batch_id}` | Cancel all running child jobs | Bearer |
| `GET` | `/api/cutting/batches?project_id=…` | List recent batches for a project | Bearer |

### Async lifecycle

1. Client `POST /circuits/{id}/cutting/batches` with `{mode, preset, cut_plan, backend_assignments, observables, opt_in_distribution}`.
2. Backend creates `CuttingBatchDocument` with `status='queued'`, returns `202 {batch_id}` immediately.
3. Background worker: `status='partitioning'` → run `pipeline.partition(...)` → for each subcircuit submit an IBM Runtime job (reusing existing `JobService` submission path) tagged with `batch_id` + `cut_role` → `status='executing'`.
4. Batch watcher (lazy refresh on poll, matching the Jobs-screen pattern) updates child statuses + `progress_pct`; when all children land, flips to `status='reconstructing'`, calls `pipeline.reconstruct_expectations(...)` + `pipeline.post_process(...)`, persists result, flips to `status='completed'` (or `'partial_failure'` if any child failed after retries).
5. MATLAB client polls `GET /cutting/batches/{batch_id}` on a 3 s timer, stops on terminal state.

### MATLAB UI — `CircuitCuttingScreen`

Sidebar slot: between **Benchmark** and **Jobs**. Row layout:

1. Toolbar — Circuit dropdown · Mode segmented (`Automatic | Assisted | Manual`) · Preset dropdown · Refresh
2. Status line — `k subcircuits · overhead 7.2× · pool: 5 backends · preset: Generic` (mirrors Benchmark Dashboard)
3. Split row — **Cut Plan** panel (circuit diagram with cut markers + summary + `Analyze Cuts` button) | **Backend Assignments** panel (per-subcircuit backend dropdowns)
4. **Observables** panel — Pauli-string editor + `[Use default all-Z]` button + per-subcircuit shots
5. **Options** panel — `☐ Also reconstruct bitstring distribution` · `Timeout (h)` · `Retry strategy (none | auto × 2)`
6. Action row — `Cancel Batch` · `Run Cutting` (primary)
7. **Results** panel (hidden until batch terminal) — expectation values table · optional distribution histogram · optional preset-specific output view (e.g. CT image preview for Option C)

Mode effect on layout:
- **Automatic** — collapses rows 3–5 into a single read-only "Defaults applied" summary; only circuit dropdown + `Run Cutting` are interactive.
- **Assisted** — all rows visible, pre-filled from `POST /cutting/analyze` suggestions; user can override any field.
- **Manual** — all rows visible, blank; user clicks circuit diagram to mark cut points, fills backends + observables by hand.

Banners on other screens:
- **Benchmark**, **Prediction** — when `circuit.num_qubits > max(backend pool qubits)`, show yellow banner "This circuit needs cutting. [Open Cutting Screen →]".
- **Jobs** — child subcircuit rows show a `⤴ batch` badge in their row; clicking it navigates to the parent batch's Cutting Results.

New MATLAB files:
- `src/presentation/screens/CircuitCuttingScreen.m`
- `src/presentation/viewmodels/CircuitCuttingViewModel.m`
- `src/domain/services/CuttingService.m`
- Integration edits in `QTAUWorkbenchApp.m`, `NavigationManager.m`, `ServiceContainer.m`.

## Error handling

- **Partial subcircuit failure** — batch marked `partial_failure`; Automatic mode auto-retries up to 2× on a spare backend from the pool; Assisted/Manual show per-child status with a `Retry` button on the failed child.
- **Reconstruction failure** — batch marked `failed`; raw subcircuit measurements are preserved so the user can re-run only the reconstruction step without re-running hardware.
- **Global timeout** (default 6 h) — pending children cancelled; batch marked `failed` with a timeout error.
- **Backend pool < k** — `POST /batches` rejects early with a helpful message ("Need ≥ 3 backends in pool, have 2").
- **Preset incompatibility** — preset's `qubit_range` / `required_structure` checked at `POST /batches`; rejection message names the violated constraint.
- **Cancellation** — `DELETE /batches/{id}` calls `job.cancel()` on each running child via IBM Runtime, stops the watcher, flips status to `cancelled`.

## Edge cases

- Circuit fits on a single backend → UI shows "Cutting not needed for this circuit" hint, `Run Cutting` disabled, Benchmark screen recommended.
- Only 1 backend in pool → auto-degrades to `k=1` (plain submission, no cutting).
- Observable syntax errors → client-side validation against a shared Pauli regex before POST.
- App closed mid-batch → server continues; batch visible in the History tab when the user returns.

## Testing

### Backend (pytest, mock `qiskit-addon-cutting`)

- `test_cutting_service.py` — analyze / partition / reconstruct math on a small synthetic circuit.
- `test_cutting_batch_service.py` — full batch lifecycle (queued → executing → reconstructing → completed), partial-failure path, cancellation, timeout.
- `test_cutting_pipeline.py` — `GenericPipeline` stage defaults; preset-metadata registration.
- `test_cutting_router.py` — endpoint contract (test_client + mock service).
- `test_ct_imaging_preset.py` (Phase 2) — preset registration + `analyze_cuts` override returns fixed 160Q/3-way plan.

### MATLAB (matlab.unittest, StubFastAPIClient)

- `test_CuttingService.m` — HTTP endpoint contract (mirrors `test_BenchmarkService.m`).
- `test_CircuitCuttingViewModel.m` — mode switcher behavior, preset dropdown formatting, formatKpi-equivalent rendering for overhead / progress.

## Phasing

- **Phase 1 (this PR):** Option A complete — generic pipeline, all 3 modes, expectation values + opt-in distribution, banners, Jobs-screen badge. Ships when Python + MATLAB tests are green.
- **Phase 2 (follow-up PR):** Option C — `CTImaging160QPipeline` preset sourced from `docs/success-hybrid_ct_mc_vs_qmc_qpatch_clean_rebuild_160q_async3.ipynb`, preset-specific output panel renders the reconstructed CT image alongside the expectation-value table.

## Out of scope (explicit)

- **Probabilistic error cancellation (PEC)** or **zero-noise extrapolation (ZNE)** *on top of* cutting — ZNE already exists in the QMC popup; layering it on cutting is a Phase 3+ concern.
- **Third-party preset plugins** — presets are plain Python subclasses in `presets.py`. No dynamic loading, no JSON schema, no entry-point registration.
- **Cross-project batch sharing** — batches are scoped to a single `project_id`.
- **Quantum state tomography** — caps at ~8–10 qubits, doesn't scale to the "large circuit" use case this spec targets.
