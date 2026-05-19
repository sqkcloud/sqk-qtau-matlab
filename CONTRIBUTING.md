# Contributing to QTAU Connector Workbench

Thanks for your interest in improving QTAU Connector Workbench. This document describes how to file issues, propose changes, and submit pull requests.

## Code of conduct

Be respectful and constructive. Harassment, discrimination, or personal attacks will not be tolerated. Maintainers reserve the right to remove comments and close PRs that violate this standard.

## Reporting issues

Before opening an issue, please:

1. **Search existing issues** to avoid duplicates.
2. **Reproduce on a clean install** — open the project, run `QTAUWorkbenchLauncher`, and confirm the bug appears without local modifications.
3. **Include**:
   - MATLAB release (`>> version`).
   - Operating system + version.
   - Backend reachability (does `>> ping <your_qtau_host>` succeed?).
   - Steps to reproduce, expected behaviour, actual behaviour.
   - Console output and the relevant log excerpt (toolbox logs are structured: `[HH:MM:SS.FFF] LEVEL [Category] Message`).

## Proposing changes

1. **Open a discussion or issue first** for non-trivial work — feature additions, refactors, new screens, new services. This avoids duplicate effort and gives maintainers a chance to weigh in on the design before code is written.
2. **Fork the repo** and create a topic branch:
   ```
   git checkout -b feature/short-descriptive-name
   ```
3. **Match existing conventions** documented in [`CLAUDE.md`](CLAUDE.md):
   - Classes `PascalCase`, methods/properties `camelCase`, config keys `snake_case`.
   - Screens are functions, ViewModels are classes, Services receive `FastAPIClient` via constructor.
   - No hardcoded UI strings — every label comes from `resources/labels.properties`.
   - Errors propagate as `MException` from HTTP → Service → ViewModel; the ViewModel surfaces them via `uialert`.
4. **Add a test** in `tests/` for any non-trivial change. Tests must run against `StubFastAPIClient` — no live backend.
5. **Run the suite**:
   ```matlab
   runtests('tests')
   ```
   All tests must pass before opening a PR.

## Pull request checklist

- [ ] Branch is rebased on the latest `main`.
- [ ] `runtests('tests')` passes.
- [ ] No new lint/analysis warnings introduced (MATLAB Code Analyzer).
- [ ] `CHANGELOG.md` updated under the next *Unreleased* section.
- [ ] No hardcoded URLs, IPs, tokens, or credentials in committed code.
- [ ] No internal/private host references in comments, strings, or test fixtures.
- [ ] No `cd` calls, no `clear all`, no global variables introduced.
- [ ] User-facing strings go through `Labels.get(...)`.

## Releasing

Releases are cut by maintainers. The flow is:

1. Bump `opts.ToolboxVersion` in `scripts/package_release.m`.
2. Bump `app_version` in `resources/app.properties`.
3. Add a new `## [x.y.z]` section to `CHANGELOG.md`.
4. Tag `vX.Y.Z` and push.
5. Build the `.mltbx` (`scripts/package_release.m`) and upload to MATLAB Central File Exchange.

See [`PUBLISHING.md`](PUBLISHING.md) for the full release runbook.

## License

By contributing you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE), the same terms that cover the rest of the project.
