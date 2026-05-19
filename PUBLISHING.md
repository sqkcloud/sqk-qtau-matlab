# Publishing Guide — QTAU Connector Workbench → MATLAB Central File Exchange

This document is the operational runbook for taking the current repo state and turning it into a published toolbox on **MATLAB Central File Exchange**. Follow it top-to-bottom on the day of release.

**Estimated total time**: ~90 minutes (60 min in MATLAB + 30 min on the File Exchange web form), assuming all prep is done.

---

## Table of contents

0. [Pre-flight checklist](#0-pre-flight-checklist)
1. [Refresh the MATLAB Project file](#1-refresh-the-matlab-project-file)
2. [Create the toolbox icon (PNG)](#2-create-the-toolbox-icon-png)
3. [Convert `GettingStarted.m` → `GettingStarted.mlx`](#3-convert-gettingstartedm--gettingstartedmlx)
4. [Configure the toolbox task](#4-configure-the-toolbox-task)
5. [Reanalyze + package](#5-reanalyze--package)
6. [Smoke-test on a clean MATLAB instance](#6-smoke-test-on-a-clean-matlab-instance)
7. [Sign in to MATLAB Central](#7-sign-in-to-matlab-central)
8. [Submit to File Exchange](#8-submit-to-file-exchange)
9. [After acceptance — maintenance + updates](#9-after-acceptance--maintenance--updates)
10. [Troubleshooting common rejections](#10-troubleshooting-common-rejections)
11. [Programmatic packaging (optional follow-up)](#11-programmatic-packaging-optional-follow-up)

---

## 0. Pre-flight checklist

Before opening MATLAB, verify these are all true. If any one is **NO**, fix it first.

- [ ] Working tree is clean (`git status` shows only files you intend to ship).
- [ ] All tests pass: `runtests('tests')` returns zero failures.
- [ ] App launches end-to-end against the dev backend: `QTAUWorkbenchLauncher` → Login → Dashboard.
- [ ] `LICENSE` and `NOTICE` exist at the repo root and have the correct copyright year (© 2026 SQK Cloud Inc).
- [ ] `resources/app.properties` has `base_url=` (empty).
- [ ] `src/domain/models/AppState.m` line 130 falls back to `http://localhost:5715`, not the dev IP.
- [ ] `resources/seed.properties` is **not** tracked (`git ls-files resources/seed.properties` returns nothing).
- [ ] No `Report_*.pdf`, `EmAnalysis_*.json`, `ExecLog_*.jsonl` at repo root (`.gitignore` blocks them; `git ls-files | grep -E 'Report_|EmAnalysis_|ExecLog_'` returns nothing).
- [ ] `doc/GettingStarted.m` exists (draft for conversion in Step 3).
- [ ] You have credentials for a live QTAU server you can point the install test at (Step 6).
- [ ] You have a MathWorks account with author privileges on File Exchange (set up in Step 7 if not).

If the answer to any item is unclear, open the file in question and read it before continuing.

---

## 1. Refresh the MATLAB Project file

The committed `sqk-qtau-matlab.prj` is R2025b schema but the `<ProjectFile>` list points at **pre-refactor paths** (`src/QTAUWorkbenchApp.m`, `src/tabs/*Tab.m`, etc.). This is **not** a pre-R2025a toolbox file — the auto-upgrade flow doesn't apply. You need to recreate it from the current folder layout.

### 1.1. Close any open project

In MATLAB:

1. **Project** tab → **Close Project**.
2. If MATLAB asks to save changes, click **Discard**.

### 1.2. Delete the stale `.prj`

In MATLAB's **Current Folder** panel:

1. Right-click `sqk-qtau-matlab.prj` → **Delete**.
2. Confirm.

Or from the OS shell:

```bash
rm sqk-qtau-matlab.prj
```

### 1.3. Recreate from folder

In MATLAB:

1. **Home** tab → **New** dropdown → **Project** → **From Folder**.
2. Browse to the repo root (`sqk-qtau-matlab/`).
3. **Project Name**: `QTAU Connector Workbench`
4. Click **Create**.

MATLAB scans the folder, indexes every `.m` / `.mlx` / `.properties` file, and creates a fresh `.prj` (it may be named differently — rename to `sqk-qtau-matlab.prj` if you want to preserve the existing name).

### 1.4. Verify

In the new project, the **Project Files** view should list:

- `QTAUWorkbenchLauncher.m`
- All current files under `src/` (about 50 `.m` files)
- All files under `resources/`, `samples/`, `doc/`, `tests/`, `scripts/`

If any of the OLD pre-refactor paths still show up as "missing files" warnings, right-click → **Remove from Project**.

Commit the new `.prj`:

```bash
git add sqk-qtau-matlab.prj
git commit -m "chore(project): refresh .prj for post-refactor file layout"
```

---

## 2. Create the toolbox icon (PNG)

The MathWorks doc requires the toolbox image to live **inside the project folder**. The existing logo is SVG; you need a raster PNG.

### 2.1. Source

`resources/sqk-logo-kokkos-white1-reordered.svg` is the SQK logo.

### 2.2. Target

`resources/toolbox-icon.png`, **256×256 px**, transparent background, PNG (8-bit RGB+alpha).

### 2.3. How to render

**Option A (RECOMMENDED) — Python generator script** (already in the repo):

```bash
python3 scripts/build_icon.py
```

Produces `resources/toolbox-icon.png` from scratch via PIL — no SVG→PNG conversion needed because the script composes a purpose-built square icon (STIX Bold "QTAU" wordmark + "SQK CLOUD" subtitle on a dark navy rounded card, matching the (?) help-icon ghost style and the app's `Theme.NAV_BG`). Reproducible across machines, tunable via the design-parameter block at the top of the script. Requires only Python 3 + Pillow.

Skip the remaining options unless you need to refresh the icon with a different design.

**Option B — macOS Preview**:

1. Double-click the SVG → opens in Preview.
2. **File → Export...** → format: PNG → resolution: 144 dpi → save as `resources/toolbox-icon.png`.
3. If the result isn't 256×256, open the PNG and *Tools → Adjust Size* → Width 256, Height 256, Resolution 144 dpi.

**Option C — Inkscape (cross-platform)**:

```bash
inkscape resources/sqk-logo-kokkos-white1-reordered.svg \
  --export-type=png \
  --export-width=256 \
  --export-height=256 \
  --export-filename=resources/toolbox-icon.png
```

**Option D — ImageMagick (if installed)**:

```bash
magick convert -background none -resize 256x256 \
  resources/sqk-logo-kokkos-white1-reordered.svg \
  resources/toolbox-icon.png
```

### 2.4. Verify

```bash
file resources/toolbox-icon.png
# Expected: PNG image data, 256 x 256, 8-bit/color RGBA, non-interlaced
```

Commit:

```bash
git add resources/toolbox-icon.png
git commit -m "feat(packaging): add 256x256 PNG toolbox icon rendered from SVG logo"
```

---

## 3. Convert `GettingStarted.m` → `GettingStarted.mlx`

The toolbox task requires a `.mlx` live script, not a `.m` file.

### 3.1. Open the draft in Live Editor

1. In MATLAB **Current Folder** panel, navigate to `doc/`.
2. Double-click `GettingStarted.m`. MATLAB Editor opens.
3. The file has `%%` cell markers — MATLAB will recognize them as Live Editor sections.

### 3.2. Save as live script

1. **File → Save As...**
2. Change *Save as type* to **MATLAB Live Code Files (`.mlx`)**.
3. Filename: `GettingStarted.mlx`. Path: `doc/`.
4. Click **Save**.
5. **Verify**: the editor switches to Live Editor mode and the cell markers render as section headings.

### 3.3. Polish (optional but recommended)

Open `doc/GettingStarted.mlx` in Live Editor:

- Add screenshots (e.g. of the Login dialog with the Base URL field highlighted).
- Add hyperlinks to your GitHub repo + issue tracker.
- Replace the placeholder GitHub URL in *Where to get help* with your actual repo URL.

### 3.4. Delete the source `.m`

Once the `.mlx` looks correct:

```bash
git rm doc/GettingStarted.m
git add doc/GettingStarted.mlx
git commit -m "docs(getting-started): convert source draft to live script"
```

---

## 4. Configure the toolbox task

This is the GUI-heavy step. Most of it is filling in fields in the Package Toolbox task editor.

### 4.1. Open the project

```matlab
matlab.project.openProject('sqk-qtau-matlab.prj')
```

Or **Home → Open → Open Project** → select the file.

### 4.2. Open the toolbox task

1. In the project toolstrip, click the **Project** tab.
2. In the **Tools** section, click **Package Toolbox**.
3. MATLAB creates a toolbox task with the same name as the project and opens it in the document area.

If a toolbox task already exists from a prior attempt, it will reopen instead of being recreated.

### 4.3. Toolbox Folder section

1. Verify the **Toolbox Folder** field shows the repo root (e.g. `/Users/.../sqk-qtau-matlab`).
2. If empty, click **Add Toolbox Folder** and select the repo root.
3. The **preview** below shows every file MATLAB will include. Scroll through — confirm:
   - `src/`, `resources/`, `samples/`, `doc/` are listed.
   - `LICENSE`, `NOTICE`, `README.md`, `QTAUWorkbenchLauncher.m` are listed.
4. Click **Edit Exclusions** and paste this verbatim into the text file:

   ```
   .git
   .github
   .gitignore
   .gitattributes
   .claude
   .serena
   .DS_Store
   resources/seed.properties
   EmAnalysis_*.json
   Report_*.pdf
   ExecLog_*.jsonl
   Results_*.json
   Reconstruction_*.json
   output
   scripts
   tests
   doc/keys.txt
   *.mex*
   *.token
   .env
   release
   *.mltbx
   CLAUDE.md
   ```

   Save the file. The toolbox-folder preview refreshes — those entries should now be greyed out / removed.

### 4.4. Toolbox Information section

Fill in exactly:

| Field | Value |
|---|---|
| **Toolbox name** | `QTAU Connector Workbench` |
| **Version** | `1.0.0` (use `1.0.0.0` if MATLAB requires 4 segments) |
| **Author name** | Your name |
| **Author email** | Your maintainer email |
| **Company** | `SQK Cloud Inc` |
| **Toolbox image** | Click **Browse** → `resources/toolbox-icon.png` |
| **Summary** | `MATLAB desktop client for managing IBM Quantum experiments through the QTAU FastAPI backend. Includes circuit composer, Quantum Monte Carlo simulator, error mitigation cost planner, and cost-aware run optimiser.` |
| **Description** | Paste from `README.md` top section. Keep under 4000 characters. |

### 4.5. Toolbox Requirements section

1. **Required Add-Ons**: leave empty. The app uses only base MATLAB.
2. **Discovered Requirements**: click **Reanalyze**. MATLAB scans the code dependencies.
   - Expected result: empty list.
   - If MATLAB reports files outside the toolbox folder, click **View Analysis** to open the Dependency Analyzer and fix the offending `addpath` / `fullfile` reference in the code.

### 4.6. Install Actions section

#### MATLAB Path

Click **Manage Project Path** (or directly edit the path list). Add **these 11 entries**, all relative to the toolbox install root:

```
<toolbox root>
<toolbox root>/src/presentation
<toolbox root>/src/presentation/app
<toolbox root>/src/presentation/screens
<toolbox root>/src/presentation/viewmodels
<toolbox root>/src/domain
<toolbox root>/src/domain/models
<toolbox root>/src/domain/services
<toolbox root>/src/infrastructure
<toolbox root>/src/infrastructure/http
<toolbox root>/src/infrastructure/config
```

These match exactly what `QTAUWorkbenchLauncher.m` adds at runtime (lines 48-59), so the install-time path and the launcher's runtime path are idempotent.

**Do NOT add** `tests/`, `scripts/`, `resources/`, `samples/`, `doc/`, `output/`. They're bundled in the toolbox folder and accessed via relative paths from code — they don't need to be on the user's MATLAB path.

#### Java Classpath

Leave empty.

#### Apps

Leave empty. The repo has no `.mlapp` files. (If you later create an App Designer wrapper, register it here.)

#### Getting Started Guide

1. In the **Getting Started Guide** field, click **Add** (or **Browse**) → select `doc/GettingStarted.mlx`.
2. **Verify**: the file path resolves correctly in the field.

Alternatively, in the Project panel right-click `doc/GettingStarted.mlx` → **Add Label** → **Getting Started Guide** in the toolbox task menu.

### 4.7. Toolbox Portability section

1. **Supported Platforms**: tick all four:
   - Windows
   - macOS
   - Linux
   - MATLAB Online
2. **Release Compatibility**: pick **R2025a or later**. (If your dev / smoke-test environment is R2025b, set R2025b instead — but the code is compatible with R2025a per the doc page 5 toolbox-task minimum.)

### 4.8. Output Settings section

1. Leave the default filename `QTAUConnectorWorkbench.mltbx`.
2. Leave the default path `release/`.
3. Click **Browse** if you want a different output location, but the default is fine.

---

## 5. Reanalyze + package

1. At the top of the toolbox task, click **Reanalyze**.
2. Wait for the green checkmark. If any red errors appear, fix them (likely candidates: missing files referenced by `addpath`, broken `LICENSE` path, missing `toolbox-icon.png`).
3. Click **Package Toolbox**.
4. Watch the progress bar at the bottom. Packaging takes 30-90 seconds depending on repo size.
5. When done, MATLAB shows a confirmation dialog with a link to the output file.

### 5.1. Verify the output

```bash
ls -la release/
# Expected: QTAUConnectorWorkbench.mltbx (typically 3-10 MB)
```

Inspect the contents (a `.mltbx` is a ZIP):

```bash
unzip -l release/QTAUConnectorWorkbench.mltbx | head -30
```

Look for:
- `metadata/` directory (toolbox metadata XML)
- `fsroot/` directory (your bundled files)
- `fsroot/QTAUWorkbenchLauncher.m`
- `fsroot/LICENSE`, `fsroot/NOTICE`
- `fsroot/doc/GettingStarted.mlx`
- `fsroot/resources/toolbox-icon.png`
- `fsroot/src/...` (full source tree)

Confirm **excluded** files are absent:
- No `fsroot/.git*`
- No `fsroot/tests/*`
- No `fsroot/scripts/*`
- No `fsroot/resources/seed.properties`
- No `fsroot/CLAUDE.md`

---

## 6. Smoke-test on a clean MATLAB instance

This step catches packaging errors that don't show up in the dev environment because your path is already set up.

### 6.1. Use a fresh MATLAB profile

**Option A — different machine** (best): a VM, another physical machine, or a colleague's MATLAB install.

**Option B — same machine, fresh prefdir**:

```matlab
% Find your prefdir
prefdir
% Quit MATLAB, rename that folder (e.g. add a .bak suffix), reopen MATLAB.
% MATLAB will start with no recent files, no path additions, no installed add-ons.
```

### 6.2. Install the `.mltbx`

1. Open the fresh MATLAB.
2. In the file explorer (Finder / Windows Explorer / etc.), navigate to your `release/` directory.
3. Double-click `QTAUConnectorWorkbench.mltbx`. MATLAB pops up the **Install Add-On** dialog.
4. Click **Install**. MATLAB extracts the toolbox to `~/Documents/MATLAB/Add-Ons/Toolboxes/QTAU Connector Workbench/`.
5. The install completes silently. No error → good.

### 6.3. Verify install actions worked

```matlab
which QTAUWorkbenchLauncher       % should resolve to the install dir
which QTAUWorkbenchApp             % should resolve to install/src/presentation/app
```

If either returns "not found", the MATLAB Path install action didn't fire. Revisit Step 4.6.

### 6.4. Launch the app

```matlab
QTAUWorkbenchLauncher
```

Watch for the boot banner:

```
  ╔══════════════════════════════════════════════════╗
  ║   QDash Workbench — QTAU Connector Workspace     ║
  ╚══════════════════════════════════════════════════╝
  Starting application...
```

The Login dialog should appear.

### 6.5. Verify the empty-base-URL behaviour (Option C)

1. In the Login dialog, **confirm the Base URL field is empty** (or shows the localhost fallback).
2. Enter your test QTAU server URL.
3. Enter username + password.
4. Click **Sign In**.

### 6.6. Smoke-test the main workflow

A 5-minute path that touches the critical screens:

1. **Dashboard** → loads without errors.
2. **Circuits** → upload `samples/bell_state.qasm` from the toolbox install directory.
3. **Analysis** → analyse the uploaded circuit. The complexity landscape should render.
4. **Backends** → list of backends loads.
5. **Jobs** → submit a job from Benchmark, wait for it to complete, view results.
6. **Settings** → save a base URL.

### 6.7. Verify Getting Started is registered

1. **Home tab → Add-Ons → Manage Add-Ons**.
2. Find **QTAU Connector Workbench** in the list.
3. Click the **gear icon** → **Getting Started**.
4. The `doc/GettingStarted.mlx` should open in the Live Editor.

### 6.8. Uninstall test

1. In Manage Add-Ons, click the gear icon next to QTAU Connector Workbench → **Uninstall**.
2. Confirm. MATLAB removes the toolbox.
3. Restart MATLAB. `which QTAUWorkbenchLauncher` → should now be "not found".

If all eight steps pass, you're ready to publish.

---

## 7. Sign in to MATLAB Central

### 7.1. Account

Go to https://www.mathworks.com/login. Sign in with the MathWorks account that should own the File Exchange submission (e.g. an account belonging to SQK Cloud Inc, not a personal account).

If you don't have an SQK Cloud Inc account, create one at https://www.mathworks.com/mwaccount/account/create. Use a company email.

### 7.2. Author profile

Go to https://www.mathworks.com/matlabcentral/profile. Make sure your profile has:

- **Display name**: `SQK Cloud Inc` (or your name as maintainer)
- **Bio**: one paragraph about SQK Cloud Inc and what the toolbox does
- **Affiliation**: SQK Cloud Inc
- **Website**: company URL
- **Avatar**: company logo or your headshot

A populated author profile increases trust for users browsing File Exchange.

---

## 8. Submit to File Exchange

### 8.1. Open the submission form

Go to https://www.mathworks.com/matlabcentral/fileexchange/new_file.

### 8.2. Fill in the form

| Field | Value |
|---|---|
| **File** | Upload `release/QTAUConnectorWorkbench.mltbx` |
| **Title** | `QTAU Connector Workbench` |
| **Summary** | `MATLAB desktop client for managing IBM Quantum experiments through the QTAU FastAPI backend.` |
| **Description** | Copy the top section of `README.md`. Markdown is supported. Keep under 4000 characters. Include: what it is, who it's for, prerequisites (running QTAU FastAPI server), the empty-base-URL first-launch behaviour, link to the upstream backend repo, link to your support / issue tracker. |
| **Tags** | Pick up to 5 of these (max-5 limit): `quantum-computing`, `quantum`, `ibm-quantum`, `qiskit`, `fastapi`, `mltbx`, `dashboard` |
| **Source code link** | Your GitHub URL: `https://github.com/sqkcloud/sqk-qtau-matlab` (helps with version updates) |
| **License** | Select **Apache 2.0** from the dropdown. File Exchange will detect it from your `LICENSE` file automatically. |
| **Authors** | Add yourself (auto-populated). Optionally add co-authors. |
| **Image** | Upload `resources/toolbox-icon.png` (the same 256×256 PNG you used in the toolbox task). |
| **Required Products** | Tick **MATLAB**. Optionally tick required toolboxes if your code uses any (currently none). |
| **Categories** | Pick relevant ones, e.g. *Sciences > Physics > Quantum Mechanics*, *Engineering > Optimization*. |

### 8.3. Discussion preferences

- **Allow discussions**: ✅ yes (gives you feedback channel).
- **Email notifications**: ✅ yes (so you see issues quickly).

### 8.4. Preview + submit

1. Click **Preview** at the bottom. Review every field for typos.
2. Click **Submit**. File Exchange runs an automated scan (looks for MEX files, viruses, etc.) — takes ~30 seconds.
3. If the automated scan passes, your submission is **published immediately**. You'll get a URL like `https://www.mathworks.com/matlabcentral/fileexchange/12345-qtau-connector-workbench`.
4. If the automated scan flags something, you'll get an email — see [Section 10](#10-troubleshooting-common-rejections).

### 8.5. Manual review (sometimes)

For first-time submitters, File Exchange may queue your submission for manual moderator review (typically 1-3 business days). You'll receive an email when it's approved.

---

## 9. After acceptance — maintenance + updates

### 9.1. Bookmark your File Exchange URL

The URL format is `https://www.mathworks.com/matlabcentral/fileexchange/<id>-<slug>`. Save it.

### 9.2. Watch downloads + ratings

Your submission's page shows: download count, rating stars (1-5), reviews, comments. Respond to comments within a few days — File Exchange's algorithm boosts active submissions.

### 9.3. Publishing updates

When you ship a new version:

1. Bump the **Toolbox Version** in the project task (Step 4.4) — increment `1.0.0` → `1.1.0` or `1.0.1`.
2. Re-run **Reanalyze** → **Package Toolbox**.
3. On the File Exchange submission page, click **Update Submission**.
4. Upload the new `QTAUConnectorWorkbench.mltbx`.
5. Add a **changelog note** in the "What's new in this version" field.
6. Click **Submit**.

Existing installations don't auto-update; users see "Update available" in **Manage Add-Ons** and can install the new version with one click.

### 9.4. Versioning convention

Follow **semantic versioning** (`MAJOR.MINOR.PATCH`):

- `MAJOR` — breaking API changes (URL format, login flow rework).
- `MINOR` — new screens, new features (backward-compatible).
- `PATCH` — bug fixes, no new features.

---

## 10. Troubleshooting common rejections

### "Submission contains executable files"

File Exchange rejects MEX (`*.mex*`), DLLs (`*.dll`), and ActiveX controls (`.ocx`).

- Check: `unzip -l release/QTAUConnectorWorkbench.mltbx | grep -iE '\.(mex|dll|ocx|exe|so|dylib)$'`
- If any match, find them in the source tree and add to **Exclusions** in Step 4.3, then repackage.

### "Missing license declaration"

- Confirm `LICENSE` is at the repo root (in the `fsroot/LICENSE` path inside the `.mltbx`).
- Confirm the submission form's **License** field is set to Apache 2.0 (not "Other" or blank).

### "Description is too vague"

File Exchange moderators want concrete information:
- What the toolbox does (1-2 sentences).
- Who the audience is.
- What prerequisites are needed (your backend dependency!).
- How to launch (`QTAUWorkbenchLauncher`).
- Link to documentation.

Update via **Update Submission**.

### "Cannot install — file conflict"

Means the toolbox unpacks files into paths that already exist in MATLAB's `Add-Ons/Toolboxes/`. Increment the version number (Step 9.3) and republish.

### "Required products not detected"

If you use functions from optional toolboxes (Symbolic Math, Optimization, etc.), File Exchange's static analyzer should detect them. If something is missing or extra, tick/untick the relevant toolboxes in the **Required Products** field.

### "Toolbox image too small / too large"

256×256 PNG is the sweet spot. 64×64 also works but looks pixelated. Above 512×512 may be downscaled by File Exchange.

### App fails to launch after install (`QTAUWorkbenchApp not found`)

Means the MATLAB Path install action didn't add `src/presentation/app/` to the path. Revisit Step 4.6 — make sure all 11 path entries are listed.

### "Pre-launch checks failed — empty `base_url`"

This is the **expected** Option C behaviour. The user must set the Base URL on the Login dialog. If users complain, clarify in the **Description** that the toolbox needs a separate QTAU FastAPI backend to connect to.

---

## 11. Programmatic packaging (replaces Step 4 + Step 5)

Steps 4-5 (configure the toolbox task → reanalyze → package) can be reduced to a single command using the included **`scripts/package_release.m`** helper. It uses `matlab.addons.toolbox.ToolboxOptions` (R2023a+) and `matlab.addons.toolbox.packageToolbox` to do exactly what the GUI does, with every value pre-populated from this guide.

### Usage

After Steps 0-3 are complete (icon PNG, GettingStarted.mlx, blank `base_url`):

```matlab
>> run('scripts/package_release.m')
```

Expected output:

```
Project root: /Users/.../sqk-qtau-matlab
Filtering files (start: ~1200)... end: ~250 (~950 excluded)

Packaging QTAU Connector Workbench v1.0.0
  Identifier:   d4f2a8e9-3c1b-4e5d-9a6c-7b3d2f8e1a4c
  Files:        ~250
  Path entries: 11
  Min release:  R2025a
  Output:       /Users/.../release/QTAUConnectorWorkbench.mltbx
  Running matlab.addons.toolbox.packageToolbox...

Done — 4.32 MB at /Users/.../release/QTAUConnectorWorkbench.mltbx
Next: smoke-test on a clean MATLAB (PUBLISHING.md Section 6).
```

Now jump to [Section 6](#6-smoke-test-on-a-clean-matlab-instance).

### What the script does

- Verifies the four pre-requisites (icon PNG / GettingStarted.mlx / blank `base_url` / LICENSE+NOTICE) and errors with an actionable message if any are missing.
- Auto-discovers every file under the project root via `ToolboxOptions(projectRoot, identifier)`.
- Filters the file list against the same exclusion rules as Section 4.3 (dir prefixes / exact matches / root-level artifact prefixes / suffix patterns) — see the `iShouldExclude` local function for the source of truth.
- Sets all Toolbox Information fields (name, version, author, summary, description, image).
- Adds the 11 MATLAB Path entries that match `QTAUWorkbenchLauncher.m`'s runtime addpath set.
- Registers `doc/GettingStarted.mlx` as the Getting Started Guide.
- Declares portability: Windows / macOS / Linux / MATLAB Online, R2025a minimum.
- Writes `release/QTAUConnectorWorkbench.mltbx` and prints its size.

### Editing the script

Update these values inside `scripts/package_release.m` when:

- **Releasing a new version**: change `opts.ToolboxVersion`. Follow semver (Section 9.4).
- **Maintainer changes**: change `opts.AuthorEmail`. (Default is `contact@sqkcloud.com`.)
- **Description updates**: edit the multi-line `opts.Description = sprintf([...])` block.
- **Adding new install actions**: e.g. when you ship the App Designer wrapper from Section 6 of the appendix, populate `opts.AppGalleryFiles`.

**Never change** the `TOOLBOX_IDENTIFIER` constant. The same UUID across releases is what tells MATLAB "this is an updated version of the same toolbox" — change it and existing installs will not see updates, and File Exchange would treat it as a new submission.

### When the script is NOT enough

The GUI flow (Section 4) is still useful for first-time exploration of MathWorks' toolbox task options or for verifying the auto-discovered files manually. After that, the script is the source of truth and the GUI flow can be skipped.

A bare-minimum GUI fallback (no `ToolboxOptions` API) is sketched in [Section 4](#4-configure-the-toolbox-task).

---

## Appendix — what NOT to do

- **Don't** publish with an internal/private `base_url` filled in inside `app.properties`. Ship it empty (`base_url=`) so each installer is prompted on first launch — otherwise every install would hit your dev server.
- **Don't** include `resources/seed.properties` in the package. It contains real credentials.
- **Don't** include the `.git/` folder. Wastes File Exchange storage and may leak commit metadata.
- **Don't** use a personal MathWorks account for the SQK Cloud Inc submission. If you leave the company the listing becomes hard to manage.
- **Don't** rely on screenshots that include real backend URLs in your File Exchange description. Use placeholders like `qtau.example.com`.
- **Don't** forget to bump the version when publishing updates. File Exchange's "Update" workflow requires a new version number.
- **Don't** skip the smoke test (Section 6). Catches 80% of packaging bugs.

---

## Quick reference — every artifact this guide references

| Path | Purpose |
|---|---|
| `LICENSE` | Apache 2.0 declaration, © SQK Cloud Inc 2026 |
| `NOTICE` | Third-party attribution (PNNL QASMBench BSD-3 + MathWorks trademarks) |
| `README.md` | Top section = end-user install; bottom section = packaging checklist (this doc supersedes for the publishing flow) |
| `doc/GettingStarted.mlx` | Live-script Getting Started guide, registered in Install Actions |
| `resources/toolbox-icon.png` | 256×256 PNG toolbox image |
| `resources/app.properties` | `base_url=` empty (Option C default) |
| `src/domain/models/AppState.m` | Falls back to `http://localhost:5715` when `base_url=` is empty |
| `sqk-qtau-matlab.prj` | MATLAB Project file (refreshed in Step 1) |
| `release/QTAUConnectorWorkbench.mltbx` | The artifact you upload to File Exchange |
| `.gitignore` | Blocks `release/`, `*.mltbx`, session artifacts |
