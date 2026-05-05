---
phase: 05-decision-gate
plan: 01
subsystem: infra

tags: [hardening, dependencies, ci, audit, telemetry, license, falsification-stack-prereq]

# Dependency graph
requires:
  - phase: 04-wisp-particles
    provides: Same-Canvas keystone validated for a SECOND visual layer (wisp particles); Phase 5 unblocked at `eec9087`.
  - phase: 01-foundation
    provides: 7 CI hardening gates (.github/workflows/ci.yml — lint job + android job + ios job) + tool/check_*.dart scripts + DEPENDENCIES.md table layout.
provides:
  - Refreshed audit-date column on all 19 dependency rows in DEPENDENCIES.md (15 direct + 4 dev; fake_async untouched at 2026-05-05).
  - Closing SHA `3326f4b4e183b5b0bb41c600943cdc6bc0453163` on `main` with all 7 CI hardening gates GREEN locally + GREEN in CI.
  - CI run `25383915800` GREEN on all 3 jobs (Lint / License / Headers / Deps + Build Android APK debug + Build iOS no-codesign sideloadable).
  - Two artifacts ready for Plan 02 (iPhone walk) + Plan 03 (Pixel 4a walk) sideload via `gh run download`:
    - `mirk-poc-debug-android-debug-apk` (~83.7 MB).
    - `mirk-poc-debug-ios-unsigned-ipa` (~11.6 MB).
affects: [05-02-iphone-walk, 05-03-pixel-walk, 05-04-decision-verdict, 05-05-roadmap-handoff]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Audit-date refresh discipline (Pitfall 2): edit ONLY the rightmost Audit date column; verify diff is single-cell-per-row via `git diff --stat`."
    - "Telemetry re-grep word-boundary discipline: `\\b(Firebase|Crashlytics|Sentry|Mixpanel|Amplitude|AppsFlyer|Bugsnag)\\b` against pub-cache `<pkg>-<ver>/lib/` only (skip example/, test/) — eliminates false positives like `boundsAdjusted` matching `Adjust`."
    - "Verbal-attestation-with-mechanical-gate pattern: license + maintenance carried forward by attestation across short audit deltas (5 days here); `tool/check_licenses.dart` exit 0 is the mechanical floor."

key-files:
  created:
    - ".planning/phases/05-decision-gate/05-01-SUMMARY.md"
  modified:
    - "DEPENDENCIES.md (19 audit-date refreshes; date column only — no version / license / telemetry / transitive / maintenance / platform drift)"

key-decisions:
  - "Plan's row-count of 18 was off by one — actual refresh count is 19 (15 direct + 4 dev); fake_async-1.3.3 was the only dev-dep already at 2026-05-05 (committed in `eec9087`)."
  - "Telemetry re-grep against pub-cache returned a handful of raw-substring hits (flutter_map=80, vector_map_tiles=1, vector_tile_renderer=15, geolocator=1, go_router=6, path=4); switched to word-boundary regex limited to lib/ subtree → 0 real hits across 14 direct deps. The lone go_router lib/ hit is a docstring mention of `Firebase Analytics` as an example consumer of route name (not a runtime call)."
  - "License + maintenance status carried forward from Phase 1 audit by attestation (5-day delta; no upstream package change expected); `tool/check_licenses.dart` GREEN is the mechanical floor."
  - "Header line `Initial audit date: **2026-04-30**` LEFT UNTOUCHED — that is a historical marker (date of initial audit), not a refreshable cell. Plan only mandates the rightmost Audit date column of the dep tables."
  - "CLAUDE.md working-tree edit on the developer's side LEFT UNTOUCHED (developer-managed; precedent set in Phase 4 closure)."

patterns-established:
  - "Phase-5 hardening sweep pattern: Pitfall-2-disciplined audit-date refresh + 7-gate local sweep + push-to-main + CI watch + capture-SHA-and-run-ID-for-downstream-walks."
  - "Closing-SHA + run-ID forward-pointer: SUMMARY explicitly captures the artefact-download commands ready for downstream walk plans to copy-paste — eliminates rediscovery cost in Plans 02 + 03."

requirements-completed: []

# Metrics
duration: 11 min
completed: 2026-05-05
---

# Phase 5 Plan 01: Hardening Sweep + DEPENDENCIES.md Audit-Date Refresh + Closing SHA Capture Summary

**19 DEPENDENCIES.md audit-date stamps refreshed to 2026-05-05 (Pitfall-2-disciplined diff: date-cell-only, zero column drift); closing SHA `3326f4b` pushed to main; CI run `25383915800` GREEN on all 3 jobs (lint + android-apk + ios-unsigned-ipa); both artefacts uploaded and ready for Plan 02 + Plan 03 walk sideload via `gh run download`.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-05-05T14:50:29Z
- **Completed:** 2026-05-05T15:01:39Z
- **Tasks:** 1 (auto)
- **Files modified:** 1 (DEPENDENCIES.md)

## Accomplishments

- DEPENDENCIES.md audit-date column refreshed across all 19 dep rows (15 direct + 4 dev) to 2026-05-05; fake_async-1.3.3 stays untouched at 2026-05-05 (committed in `eec9087`). Diff is mechanically date-only: `19 insertions(+), 19 deletions(-)` per `git diff --stat`; every changed line is the same row with only the rightmost cell different.
- Telemetry re-confirmed clean across all 14 direct deps via pub-cache word-boundary grep on lib/ subtree — zero real hits; one go_router-16.0.0 docstring example mention of `Firebase Analytics` (not a runtime call) is the only word-boundary positive.
- All 7 CI hardening gates GREEN locally on the closing SHA: `dart format` (98 files lib/+test/, 105 files full tree), `flutter analyze --fatal-infos --fatal-warnings` (0 issues), `dart run tool/check_headers.dart` (102 files), `dart run tool/check_licenses.dart` (125 packages), `dart run tool/check_dependencies_md.dart` (125 packages), `dart test tool/test/` (18 tests passed), `flutter test` (218 passed, 1 skipped).
- CI run `25383915800` (https://github.com/ThongvanAlexis/mirk-poc-debug/actions/runs/25383915800) GREEN on all 3 jobs: Lint / License / Headers / Deps (130s), Build Android APK debug (262s), Build iOS no-codesign sideloadable (166s); both artefacts uploaded.

## Task Commits

1. **Task 1: Refresh DEPENDENCIES.md audit dates + spot-confirm telemetry status + hardening sweep + push CI run** — `3326f4b` (docs: 19-row audit-date refresh; closing SHA on main; CI run `25383915800` GREEN on all 3 jobs)

**Plan metadata commit:** authored after STATE.md + ROADMAP.md updates land (this SUMMARY + state cascade).

## Files Created/Modified

- `DEPENDENCIES.md` — 19 audit-date refreshes (date column only; no version / license / telemetry / transitive / maintenance / platform drift). The header line `Initial audit date: **2026-04-30**` is left untouched as historical record.
- `.planning/phases/05-decision-gate/05-01-SUMMARY.md` — this summary.

## Decisions Made

- **Audit-date refresh count:** Plan stated 18 rows; actual count is 19 (15 direct + 4 dev). Plan's "3 dev deps" undercounted by one — there are 4 dev deps (`flutter_test`, `flutter_lints`, `yaml`, `test`) plus the already-current `fake_async`. No deviation from Pitfall-2 discipline; the count discrepancy is informational only.
- **Telemetry re-grep methodology:** Plan's broad regex `Firebase|Crashlytics|...|Adjust|Bugsnag` produced false-positive substring hits in flutter_map (80), vector_map_tiles (1), vector_tile_renderer (15), geolocator (1), go_router (6), path (4) — common false positives include `boundsAdjusted`, `containsSegment`, `VisibleSegment`. Switched to word-boundary regex limited to `lib/` subtree (excludes `example/`, `test/`); zero real hits remained except one go_router docstring mention of "Firebase Analytics" as an example consumer of `GoRoute.name` at `lib/src/route_data.dart:409`. Manual inspection confirmed the docstring is descriptive only — no runtime Firebase call.
- **License + maintenance attestation:** Carried forward from Phase 1 audit (2026-04-30) by attestation across the 5-day delta. `tool/check_licenses.dart` exit-0 (125 packages including transitive surface) is the mechanical floor.
- **CLAUDE.md working-tree edit:** LEFT UNTOUCHED. The developer's `# current best version` removal during Phase 4 closure is developer-managed per the Phase-4-closure precedent in STATE.md. Only `DEPENDENCIES.md` was staged for this plan's commit.

## Deviations from Plan

**None — plan executed exactly as written.** The two informational notes above (audit-date count off by one; telemetry-grep methodology refinement to word-boundary) are within the plan's "INSPECT the matches manually — false positives include doc strings mentioning these brands as examples" instruction. No Rule 1-4 deviation triggered; no audit conclusion regressed.

## Issues Encountered

- **Telemetry-grep raw-substring false positives:** Plan's regex matched substrings in legitimate code (e.g., `Adjust` substring in `VisibleSegment.boundsAdjusted`). Resolved by adding word boundaries `\b...\b` and limiting search to package `lib/` subtree (excluding `example/` and `test/` which ship with several pub-cache packages). All resolved positives = false positives; no audit conclusion changed.
- **No other issues.**

## Forward-pointers for Plan 02 + Plan 03

**Closing SHA:** `3326f4b4e183b5b0bb41c600943cdc6bc0453163` (short: `3326f4b`)
**CI run-ID:** `25383915800`
**CI run URL:** https://github.com/ThongvanAlexis/mirk-poc-debug/actions/runs/25383915800

**Artefact download commands (copy-paste ready for Plans 02 + 03):**

```bash
# iPhone walk (Plan 02) — sideload via Apple Configurator / iMazing / Sideloadly
gh run download 25383915800 --name mirk-poc-debug-ios-unsigned-ipa --dir ./.uat-tmp/p05-02-ipa

# Android walk (Plan 03) — sideload via `adb install`
gh run download 25383915800 --name mirk-poc-debug-android-debug-apk --dir ./.uat-tmp/p05-03-apk
adb install ./.uat-tmp/p05-03-apk/app-debug.apk
```

**Artefact sizes:** iOS unsigned IPA ~11.6 MB; Android debug APK ~83.7 MB.

## User Setup Required

None — no external service configuration required. Walk plans (02 + 03) require physical devices + Mail-share log-export discipline per Phase 3.1 / Phase 4 walk precedent; no new credentials or secrets introduced by this plan.

## Next Phase Readiness

- **Plan 02 (iPhone walk) UNBLOCKS** — IPA artefact `mirk-poc-debug-ios-unsigned-ipa` ready at CI run `25383915800`; sideload via Apple Configurator / iMazing / Sideloadly; conduct walk per Phase-4-precedent (verbal-verdict-decisive-on-load-bearing-axis OR Mail-share + JSONL grep correlation if quantitative gate needed).
- **Plan 03 (Pixel 4a walk) UNBLOCKS** — APK artefact `mirk-poc-debug-android-debug-apk` ready at CI run `25383915800`; sideload via `adb install`; same walk discipline as Plan 02.
- **Plans 04 + 05 (decision verdict + roadmap handoff)** unblock contingent on Plans 02 + 03 walk verdicts; this plan delivers exactly the prerequisite artefacts.

---
*Phase: 05-decision-gate*
*Completed: 2026-05-05*

## Self-Check: PASSED

- [x] `.planning/phases/05-decision-gate/05-01-SUMMARY.md` — FOUND (this file).
- [x] Commit `3326f4b` — FOUND on main (`docs(05-01): refresh DEPENDENCIES.md audit dates to 2026-05-05`).
- [x] CI run `25383915800` — GREEN on all 3 jobs (verified via `gh run view`).
- [x] DEPENDENCIES.md diff is date-only across 19 rows (`git diff --stat` = `19 insertions(+), 19 deletions(-)`).
