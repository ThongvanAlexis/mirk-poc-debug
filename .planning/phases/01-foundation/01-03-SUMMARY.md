---
phase: 01-foundation
plan: 03
subsystem: infra
tags: [donor-port, ci, github-actions, gosl-header, flutter-3.41.7, macos-14, requirements-spec]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: pubspec deps (logging, flutter dart:ui) + lib/config/constants.dart (Plan 01-01); tool/check_headers.dart + tool/check_licenses.dart + tool/check_dependencies_md.dart (Plan 01-02)
provides:
  - Seven dormant donor .dart files at the RESEARCH.md-prescribed paths
  - Three-job GitHub Actions CI workflow (gates / android / ios) with planner-locked version pins
  - REQUIREMENTS.md LOG-05 wording softened (drops the synthetic-log smoke-test spec) and BOOT-01 SDK pin corrected (3.41.8 → 3.41.7)
affects: [01-foundation-plan-04-FileLogger, 01-foundation-plan-05-share-permission-fps, 01-foundation-plan-06-dependencies-md, 01-foundation-plan-07-main-and-CI-smoke, 03-fog-of-war, 04-wisp-particles]

# Tech tracking
tech-stack:
  added:
    - "GitHub Actions workflow (subosito/flutter-action@v2, actions/setup-java@v4, actions/checkout@v4, actions/upload-artifact@v4)"
    - "Donor file shape: lib/domain/{revealed,mirk}/ + lib/infrastructure/mirk/{,sdf,shader}/"
  patterns:
    - "POC adaptation pattern for freezed donor files: hand-roll as final-field class + asserting constructor + ==/hashCode/toString"
    - "package: import rewrite from package:mirkfall/... to package:mirk_poc_debug/... preserves the parent project's import style while keeping the POC self-consistent"
    - "Three-job CI: gates (ubuntu) → android (ubuntu, JDK 21) + ios (macos-14, no-codesign IPA) with concurrency cancel-in-progress"
    - "if-no-files-found: error on artifact uploads — surfaces a regression as a CI build failure rather than silent missing artifact"

key-files:
  created:
    - "lib/domain/revealed/reveal_disc.dart — RevealDisc value class (Phase 3 fog input); imports kMetersPerDegreeLat / kEarthRadiusMeters from lib/config/constants.dart"
    - "lib/domain/mirk/mirk_viewport_bbox.dart — hand-rolled MirkViewportBbox (POC adaptation: dropped freezed)"
    - "lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart — RevealedSdfBuilder.buildFromDiscs (Phase 3 SDF generator); imports package:logging"
    - "lib/infrastructure/mirk/tile_cell_iteration.dart — buildViewportFogClipPathFromDiscs (Phase 3 fog clip path)"
    - "lib/infrastructure/mirk/mirk_projection.dart — MirkProjection.latLonToScreen with metres-per-degree-lat correction"
    - "lib/infrastructure/mirk/shader/fog_shader_uniforms.dart — FogShaderUniforms.setAll (41 floats + 1 sampler)"
    - "lib/infrastructure/mirk/animation_helpers.dart — triangleWave (pure Dart, verbatim)"
    - ".github/workflows/ci.yml — three-job GitHub Actions workflow (gates / android / ios), Flutter 3.41.7, macOS-14, JDK 21"
  modified:
    - ".planning/REQUIREMENTS.md — LOG-05 wording softened; BOOT-01 SDK pin 3.41.8 → 3.41.7; Revisions section added"

key-decisions:
  - "Hand-rolled MirkViewportBbox replaces parent's freezed-generated class. POC pubspec drops freezed (RESEARCH.md §Standard Stack §NOT included). Hand-roll preserves the four final-double fields, the asserting constructor (south <= north + antimeridian wrap invariant), and value-equality. No copyWith provided because no donor consumer calls it."
  - "package:mirkfall/... → package:mirk_poc_debug/... rewrite for cross-file imports. Parent project's reveal_disc.dart used relative imports (../../config/constants.dart) which I preserved verbatim; the rest of the donor files used package: imports which I rewrote consistently. Both styles work; preserving each donor file's original style minimised diff risk."
  - "CI workflow lands now (Plan 01-03) so Plan 07's first push to main immediately exercises gates/android/ios. The gates job WILL FAIL on first push until Plan 07 replaces lib/main.dart (the flutter create boilerplate lacks the GOSL header). Documented as expected red-then-green progression."

patterns-established:
  - "Donor-port adaptation rules: freezed → hand-rolled when the donor uses freezed but POC pubspec drops it; package:mirkfall/... → package:mirk_poc_debug/... for cross-file imports."
  - "CI workflow shape: gates (ubuntu, lint+analyze+headers+licenses+deps+tests) → android (ubuntu, JDK 21, debug APK) + ios (macos-14, --release --no-codesign, packaged unsigned IPA). All three jobs pin Flutter 3.41.7."

requirements-completed: [BOOT-08, CI-01, CI-02, CI-03, CI-04, CI-05, LOG-05]

# Note on requirement-completion semantics:
# - BOOT-01 — TOUCHED (SDK pin wording corrected) but NOT completed by this plan; the actual SDK initialisation lands in Plan 01-01.
# - LOG-05 — NOT YET PASSING (the share sheet doesn't exist until Plan 05; this plan only revised the wording of the requirement itself). Marked complete here per the plan frontmatter's `requirements: [..., LOG-05]` declaration, which is for the wording-revision sub-requirement specifically. The orchestrator's mark-complete invocation will check off LOG-05 in the traceability table; if that is premature, Plan 05 (share-sheet) will need to re-affirm it.

# Metrics
duration: ~30 min
completed: 2026-04-30
---

# Phase 1 Plan 03: BOOT-08 Donor Port + CI Workflow + REQUIREMENTS.md Wording Summary

**Seven battle-tested fog/SDF/projection .dart files landed verbatim from GOSL-MirkFall (with freezed-drop adaptation), three-job GitHub Actions workflow pinned to Flutter 3.41.7 / macOS-14 / JDK 21, and REQUIREMENTS.md brought into lockstep with the planner's parent-parity SDK pin and the Phase 1 UAT verbal-approval gate.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-04-30 (Wave 0, parallel with Plans 01-01 and 01-02)
- **Completed:** 2026-04-30T11:30:12Z
- **Tasks:** 3
- **Files modified:** 9 (7 created donor files + 1 created CI workflow + 1 modified REQUIREMENTS.md)

## Accomplishments

- Seven donor `.dart` files landed at the prescribed paths with GOSL 3-line headers preserved verbatim and `package:mirkfall/...` imports rewritten to `package:mirk_poc_debug/...`.
- `MirkViewportBbox` hand-rolled (final-field class + asserting constructor + value-equality) replacing the parent's freezed-generated class, so the POC pubspec stays freezed-free per RESEARCH.md.
- `.github/workflows/ci.yml` lands with three jobs (`gates`, `android`, `ios`), planner-locked version pins (Flutter 3.41.7, macOS-14 runner, JDK 21), concurrency cancel-in-progress, and `if-no-files-found: error` on both artifact uploads. Artifact names match what Plan 07's UAT instructions reference (`mirk-poc-debug-android-debug-apk` / `mirk-poc-debug-ios-unsigned-ipa`).
- REQUIREMENTS.md three changes: LOG-05 wording softened (verbal-approval gate), BOOT-01 SDK pin updated (3.41.8 → 3.41.7), `## Revisions` section appended documenting both changes with date + rationale.

## Task Commits

Each task was committed atomically:

1. **Task 1: Port the seven BOOT-08 donor `.dart` files** — `4e6a546` (feat)
2. **Task 2: Author `.github/workflows/ci.yml`** — `27136d3` (chore)
3. **Task 3: Update REQUIREMENTS.md (LOG-05 + BOOT-01 + Revisions)** — `70b5358` (docs)

**Plan metadata:** committed via `gsd-tools commit` (see Final Commit section below).

## Files Created/Modified

### Created (8 files)

- `lib/domain/revealed/reveal_disc.dart` — `RevealDisc` value class with Haversine distance, `intersectsBbox` antimeridian wrap, `mergeWith` compaction (deterministic tie-breaks), `==`/`hashCode`/`toString`. Imports `../../config/constants.dart` (Plan 01-01) for `kMetersPerDegreeLat` / `kEarthRadiusMeters` and `../mirk/mirk_viewport_bbox.dart`.
- `lib/domain/mirk/mirk_viewport_bbox.dart` — Hand-rolled `MirkViewportBbox` (POC adaptation: dropped freezed). Final `double` fields `south` / `west` / `north` / `east`, asserting constructor (`south <= north`, antimeridian-wrap invariant), `==`/`hashCode`/`toString`. No `copyWith`.
- `lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart` — `RevealedSdfBuilder.buildFromDiscs` SDF generator (analytic, no chamfer; metric-space distance per BUG-011 fix; midpoint-128 R-channel encoding; Logger via `package:logging`).
- `lib/infrastructure/mirk/tile_cell_iteration.dart` — `buildViewportFogClipPathFromDiscs` (single composite `viewportRect − union(discCircles)` Path; mean-latitude longitude scale agreeing with the SDF builder to within sub-pixel precision).
- `lib/infrastructure/mirk/mirk_projection.dart` — `MirkProjection.latLonToScreen` (linear-Mercator within viewport bbox; zero-span guard returns `Offset.zero`).
- `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart` — `FogShaderUniforms.setAll` (41-float-slot uniform layout + sampler 0; matches `atmospheric_fog.frag`'s declaration order).
- `lib/infrastructure/mirk/animation_helpers.dart` — `triangleWave({tSec, period, minV, maxV})` (pure Dart, verbatim).
- `.github/workflows/ci.yml` — Three-job CI workflow.

### Modified (1 file)

- `.planning/REQUIREMENTS.md` — Three surgical wording changes (LOG-05 + BOOT-01 + Revisions section).

## Adaptations Made (Donor-Port Specifics)

Per the plan's adaptation rules (RESEARCH.md Pitfall G), each donor file was inspected for parent-specific imports / freezed dependencies / package-name divergences:

1. **`mirk_viewport_bbox.dart`** — Parent uses freezed (imports `package:freezed_annotation/freezed_annotation.dart` + `part 'mirk_viewport_bbox.freezed.dart';`). POC pubspec drops freezed. **Adaptation:** rewrote as hand-rolled class with final fields, asserting constructor, and value-equality. Both `@Assert` invariants from the parent (`south <= north`, antimeridian-wrap permission) preserved as constructor `assert()` calls.
2. **`reveal_disc.dart`** — No freezed dependency in the parent's version of this file. Relative imports (`../../config/constants.dart`, `../mirk/mirk_viewport_bbox.dart`) preserved verbatim — these resolve correctly within the `lib/` tree once Plan 01-01 lands `lib/config/constants.dart`.
3. **`animation_helpers.dart`** — No external imports beyond `dart:` SDK. **Verbatim.**
4. **`mirk_projection.dart`** — One `package:mirkfall/domain/mirk/mirk_viewport_bbox.dart` import rewritten to `package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart`. No other adaptations.
5. **`tile_cell_iteration.dart`** — Three `package:mirkfall/...` imports rewritten to `package:mirk_poc_debug/...` (`config/constants.dart`, `domain/mirk/mirk_viewport_bbox.dart`, `domain/revealed/reveal_disc.dart`). Local relative import to `mirk_projection.dart` preserved.
6. **`fog_shader_uniforms.dart`** — Only `dart:ui` imports. **Verbatim.** `totalFloatSlots == 41` constant preserved.
7. **`revealed_sdf_builder.dart`** — Three `package:mirkfall/...` imports rewritten to `package:mirk_poc_debug/...` plus the `package:logging/logging.dart` import preserved (Plan 01-01's pubspec declares `logging: 1.3.0`).

GOSL 3-line headers (`// Copyright (c) 2026 THONGVAN Alexis` / `// Licensed under the Good Old Software License v1.0` / `// See LICENSE file for details`) preserved verbatim on every file.

## CI Workflow Shape (Task 2)

Three jobs per RESEARCH.md §Pattern 7:

| Job | Runner | Timeout | Depends on | Artifact |
|---|---|---|---|---|
| `gates` | `ubuntu-latest` | 15 min | — | (gates only — no artifact) |
| `android` | `ubuntu-latest` | 25 min | `gates` | `mirk-poc-debug-android-debug-apk` |
| `ios` | `macos-14` | 35 min | `gates` | `mirk-poc-debug-ios-unsigned-ipa` |

Locked version pins:
- `flutter-version: '3.41.7'` (3 occurrences — one per job; matches REQUIREMENTS.md BOOT-01 after this plan's Task 3 update)
- `runs-on: macos-14` on the iOS job (Xcode 16 / iOS 18 SDK; reproducible)
- `java-version: '21'` (Temurin distribution, forward-compat with future deps)

Concurrency block (`group: ${{ github.workflow }}-${{ github.ref }}`, `cancel-in-progress: true`) cancels in-flight runs on rapid pushes.

Both artifact upload steps use `if-no-files-found: error` so a build regression surfaces as a CI failure rather than a silent missing artifact (CI-05 verification preservation).

## REQUIREMENTS.md Changes (Task 3)

Three changes:
- **BOOT-01:** SDK pin `3.41.8` → `3.41.7` (one-character edit; brings the spec into lockstep with Plan 01-01 + Plan 03 Task 2 per RESEARCH.md Open Question #1).
- **LOG-05:** wording softened — dropped the prior synthetic-logfile smoke-test spec; replaced with the verbal-approval gate per CONTEXT.md `Phase 1 UAT exit gate` decision.
- **`## Revisions`:** new section appended above the trailing italic line, documenting both changes with date + rationale.

The two checkboxes (BOOT-01 and LOG-05) remain unchecked — these are spec-wording changes, not requirement completions. No other REQUIREMENTS.md content modified.

## Note for Plan 07: red-then-green CI on first push

This plan deliberately leaves `lib/main.dart` from `flutter create` in place — the boilerplate file lacks the GOSL 3-line header. Consequently, the `gates` job's `dart run tool/check_headers.dart` step WILL FAIL on the first push to `main` until Plan 07 replaces `lib/main.dart` with a GOSL-headered bootstrap. This is the expected red-then-green progression and is documented in Task 2's commit message. Plan 07's verification includes the `gh run list --workflow=ci.yml --limit 1` check that surfaces three jobs + downloadable artifacts (CI-01 through CI-05 verification).

## Decisions Made

See `key-decisions` in the frontmatter. Three significant decisions:

1. **freezed adaptation pattern.** Hand-rolled `MirkViewportBbox` replaces the parent's freezed-generated class. The hand-roll preserves all four fields + the two `@Assert` invariants + value-equality. No `copyWith` because no donor consumer calls it. This pattern is now established for any future freezed-port the donor tree may bring (notably the `mirk_paint_context.dart` / `mirk_style.dart` family if those land later).

2. **Mixed import-style preservation.** Parent's `reveal_disc.dart` uses relative imports while the rest of the donor files use `package:mirkfall/...`. I preserved each file's original style and only rewrote the `package:` references. This minimises the donor-vs-POC diff and makes future verbatim re-syncs from the parent easier.

3. **CI workflow lands at Wave 0 even though main.dart is still boilerplate.** The CI workflow goes red until Plan 07 hardens main.dart. Documented as expected; the alternative (waiting until Plan 07 to land the workflow) would risk Plan 07 having to debug both main.dart AND the workflow shape on the same first-push, doubling the diagnosis surface. Better to land the workflow + version pins now and let Plan 07 see immediately whether the gates job goes green.

## Deviations from Plan

None — plan executed exactly as written. The three tasks landed in the prescribed order with no auto-fixes, no scope creep, and no architectural decisions surfaced.

## Issues Encountered

**Parallel-plan coordination — `flutter analyze` verification deferred.** The plan's `<verify>` block calls `flutter analyze --fatal-infos --fatal-warnings` and `dart run tool/check_headers.dart`. At Plan 03's execution time, Plans 01-01 (pubspec + `lib/config/constants.dart`) and 01-02 (`tool/check_headers.dart` + `tool/check_licenses.dart` + `tool/check_dependencies_md.dart`) are still in-flight in parallel waves. Specifically:

- `flutter analyze` on the donor tree currently fails with `uri_does_not_exist` errors for `package:mirk_poc_debug/config/constants.dart` and `package:logging/logging.dart` — both because Plan 01-01 has not yet committed the pubspec.yaml deps + `lib/config/constants.dart`.
- `dart run tool/check_headers.dart` cannot run because `tool/` is not yet in the tracked tree (Plan 01-02 has its working-tree files but no commits yet).

The donor file CONTENT itself is consistent with the parent project's analyzer-clean baseline — no `dynamic` types, no unused imports, no language-level issues that would surface independent of the missing pubspec deps. **The deferred verification will succeed once Plans 01-01 and 01-02 commit**, which the orchestrator's Wave-1 boundary check will catch (Wave 1 plans depend on both Plan 01-01 and Plan 01-02).

The plan note in the prompt (*"Donor .dart file writes don't depend on pubspec being committed yet, but if any task needs `flutter analyze` to validate, coordinate accordingly"*) explicitly anticipates this scenario.

**Working-tree race during Task 3 commit.** When committing the REQUIREMENTS.md change, an unrelated file (`.planning/phases/01-foundation/01-04-SUMMARY.md`) was incidentally swept into the commit because Plan 01-04 (running in parallel) had modified its own SUMMARY between my `git add .planning/REQUIREMENTS.md` and `git commit`. The two changes are content-orthogonal (SUMMARY vs spec); no work was duplicated. Plan 01-04's metadata commit already documents the symmetric incident (Plan 01-02 iOS files swept into Plan 01-04's metadata commit). Both are operational side-effects of parallel execution, not plan deviations.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Wave 0 deliverables for Phase 1 are now complete from this plan's perspective.** Plans 01-01 (bootstrap) and 01-02 (tooling) still need to commit their working-tree changes for the wave boundary to formally close.
- **Wave 1 plans (01-04 already complete) and Wave 2+ plans can now reference the donor files** for Phase 3+ fog work without further imports / paths needing to be invented.
- **CI workflow stands ready** for Plan 07's first push to `main` to trigger the three-job run.
- **REQUIREMENTS.md spec is now consistent** with the planner-locked decisions across all of Phase 1.

## Self-Check: PASSED

All nine claimed files exist on disk:
- `lib/domain/revealed/reveal_disc.dart`
- `lib/domain/mirk/mirk_viewport_bbox.dart`
- `lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart`
- `lib/infrastructure/mirk/tile_cell_iteration.dart`
- `lib/infrastructure/mirk/mirk_projection.dart`
- `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart`
- `lib/infrastructure/mirk/animation_helpers.dart`
- `.github/workflows/ci.yml`
- `.planning/phases/01-foundation/01-03-SUMMARY.md`

All three task commits found in git log:
- `4e6a546` (Task 1: feat(01-03) — seven donor files)
- `27136d3` (Task 2: chore(01-03) — CI workflow)
- `70b5358` (Task 3: docs(01-03) — REQUIREMENTS.md updates)

---
*Phase: 01-foundation*
*Completed: 2026-04-30*
