# Screenshots — source files for FEX listing + Getting Started guide

This directory holds the source PNGs used in two places:

1. **MATLAB File Exchange listing page** — uploaded to the FEX submission form's image gallery (max ≈ 7 images; pick the 5 hero shots from the table below).
2. **`doc/GettingStarted.mlx`** — embedded inline via Live Editor's *Insert → Image* so end-users see them when they open the Getting Started guide from *Manage Add-Ons → Options*.

The PNGs **do not ship inside the `.mltbx`**. Two layers of defence:
- `scripts/package_release.m`'s `iShouldExclude` excludes everything under `doc/` except `GettingStarted.*`.
- The same rule list excludes any top-level `screenshots/` directory (defensive — see [Why two locations](#why-not-screenshots-at-the-repo-root)).

Live Editor embeds image bytes directly into the OOXML container when you *Insert → Image*, so the `.mlx` is self-contained after embedding.

---

## Current inventory (25 screenshots, captured at 3200×1736 RGBA ≈ 500–900 KB each)

| Screen | File |
|---|---|
| Project (post-login landing) | `project.png` |
| Dashboard | `dashboard.png` |
| Circuits list | `circuit.png` |
| Circuit upload | `circuit_upload.png` |
| Circuit upload preview | `circuit_upload_preview.png` |
| Composer | `circuit_composer.png` |
| Composer template gallery | `circuit_templates.png` |
| Circuit visualisation | `circuit_visualization.png` |
| Analysis | `analysis.png` |
| Detailed Analysis | `detailed_analysis.png` |
| Backends | `backend.png` |
| Benchmark | `benchmark.png` |
| Benchmark data | `benchmark_data.png` |
| Circuit Cutting | `circuit_cutting.png` |
| Prediction | `prediction.png` |
| Mitigation Compare (error mitigation) | `quantum_error_mitigation.png` |
| Jobs | `jobs.png` |
| Jobs context menu | `jobs_context_menu.png` |
| Results | `results.png` |
| Results data | `results_data.png` |
| Reports | `reports.png` |
| QMC popup | `quantum_monte_carlo_simulation.png` |
| QEC Simulation | `qec_simulation.png` |
| QEC Visualisation | `qec_visualization.png` |
| Background Tasks tray | `background_tasks.png` |

---

## Recommended top-5 for the FEX listing gallery

FEX accepts up to ~7 images and renders them as a horizontal carousel above the description. The carousel is the single biggest driver of download conversion — pick shots that tell a complete story left-to-right.

| Position | File | Why this one |
|---|---|---|
| 1 | `project.png` | First impression. The post-login landing screen — answers "what does this thing actually look like?" |
| 2 | `dashboard.png` | The "real product" shot — KPI strip + workflow stepper + Run Readiness in a single dense pane. |
| 3 | `circuit_composer.png` | Visual identity. The gate palette + canvas is unlike any other MATLAB FEX submission. |
| 4 | `quantum_monte_carlo_simulation.png` | Advanced-feature signal — IBM Runtime, ZNE controls, vector-chart PDF builder. |
| 5 | `quantum_error_mitigation.png` | The Tier-3 moat — cost-aware mitigation comparator no competitor ships. |

Strong alternates if you want a different narrative:
- Replace #3 with `circuit_templates.png` to emphasise authoring over hand-drawing.
- Replace #5 with `prediction.png` for a more numeric/quantitative feel.
- Swap #2 for `analysis.png` if you want the technical-depth angle over the polished-overview angle.

---

## Recommended embeds for `doc/GettingStarted.mlx`

A 5-shot embed mirrors the listing gallery and adds context to each step. Open the file in Live Editor (`>> open('doc/GettingStarted.mlx')`), navigate to the section, then *Insert → Image* and pick the matching PNG.

| Step / section in the guide | Image |
|---|---|
| *Step 1 — Launch the Workbench* | `project.png` (first thing they see post-login) |
| *Step 2 — Set your QTAU server URL on first launch* | A Login-dialog capture (re-capture if needed via `scripts/capture_screenshots.m`) |
| *Step 3 — Tour the Dashboard* | `dashboard.png` |
| *Step 4 — Build a circuit* | `circuit_composer.png` |
| *Step 5 — Run Quantum Monte Carlo analytics* | `quantum_monte_carlo_simulation.png` |

If those sections don't yet exist in the `.mlx`, add new section breaks (`Ctrl/Cmd+Alt+Enter` in Live Editor) where needed.

---

## ⚠️ Downsample before embedding into `.mlx`

The current PNGs are **3200×1736 Retina captures (≈ 500–900 KB each)**. Live Editor does *not* auto-downsample on *Insert → Image* — it embeds the raw bytes. Embedding 5 raw masters would balloon `GettingStarted.mlx` from 5.6 KB to ≈ 3 MB.

Two viable approaches:

### Option A — pre-shrink to 1600×868 (4× smaller, still Retina-friendly on standard displays)

```bash
# macOS / Linux via ImageMagick
brew install imagemagick  # if not already installed
mkdir -p doc/screenshots/embed
for f in project dashboard circuit_composer quantum_monte_carlo_simulation quantum_error_mitigation; do
    magick doc/screenshots/${f}.png -resize 1600x868 doc/screenshots/embed/${f}.png
done
```

Then *Insert → Image* from `doc/screenshots/embed/*.png` instead of the masters. Final `.mlx` size ≈ 800 KB – 1 MB.

### Option B — just embed the masters and live with a ~3 MB `.mlx`

Fine for the toolbox; the install-time impact is negligible. Use this if you don't want a build step.

The `doc/screenshots/embed/` directory (Option A's output) is also excluded from the `.mltbx` by the same `doc/` filter, so no further packaging changes needed.

---

## Why not `screenshots/` at the repo root?

An earlier capture run landed PNGs at `screenshots/` at the repo root, which was **not** covered by the `doc/`-only exclusion rule. Repackaging from that state would have shipped 26 MB of images inside the `.mltbx`. As of the current `package_release.m`, top-level `screenshots/` is also explicitly excluded as a safety net, but the canonical convention is **`doc/screenshots/`**.

If you re-run `scripts/capture_screenshots.m`, double-check the output path — the helper creates `doc/screenshots/` by default.

---

## FEX listing form upload

On https://www.mathworks.com/matlabcentral/fileexchange/new_file, the **Images** field accepts multiple PNGs. Upload the 5 hero shots in the order from the table above — File Exchange renders them as a left-to-right carousel above the description.

The **toolbox image** field (the listing thumbnail) is separate and uses `resources/toolbox-icon.png` — don't confuse the two.

---

## Refreshing after UI changes

Re-run `scripts/capture_screenshots.m` (or use macOS Cmd+Shift+4 manual capture and save under the same filenames) to overwrite. Live Editor embeds are pixel snapshots — they don't auto-refresh — so re-`Insert → Image` each updated screenshot and save the `.mlx`. Bump the toolbox version in `scripts/package_release.m:91` and re-publish.
