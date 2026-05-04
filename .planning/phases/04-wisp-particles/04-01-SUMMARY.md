---
phase: 04-wisp-particles
plan: 01
subsystem: wisp-scaffolding
tags: [wisp, scaffolding, wave-0, red-tests, constants]
dependency-graph:
  requires: []
  provides:
    - "lib/config/constants.dart kMirkPocWisp* + kPocWispTransform* + WispRadiusBasis"
    - "lib/infrastructure/mirk/wisp/wisp_particle.dart (stub)"
    - "lib/infrastructure/mirk/wisp/wisp_particle_system.dart (stub)"
    - "lib/infrastructure/mirk/wisp/wisp_transform_logger.dart (stub)"
    - "test/infrastructure/mirk/wisp/* (RED tests)"
    - "test/wisp/* (Success Criterion RED tests)"
    - "test/presentation/widgets/fog_layer_{wisp_render,single_camera_snapshot}_test.dart (Wave-0-skip widget scaffolds)"
  affects:
    - "Plan 04-02 (WispTransformLogger impl) — flips test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart RED → GREEN"
    - "Plan 04-03 (WispParticleSystem impl) — flips test/infrastructure/mirk/wisp/wisp_particle_*.dart RED → GREEN"
    - "Plan 04-04 (FogLayer integration) — removes skip from fog_layer_wisp_render_test.dart + fog_layer_single_camera_snapshot_test.dart + test/wisp/wisp_no_fix_warmup_test.dart"
tech-stack:
  added: []
  patterns:
    - "Wave 0 RED scaffold via UnimplementedError-throwing stubs (Plan 03.1-12 Task 1 retrospective Rule 3)"
    - "Stopwatch test seam for warm-up gate control"
    - "skip: true with comment-block reason for tests gated on later-Wave constructor extensions (FOG-09 precedent)"
key-files:
  created:
    - "lib/infrastructure/mirk/wisp/wisp_particle.dart"
    - "lib/infrastructure/mirk/wisp/wisp_particle_system.dart"
    - "lib/infrastructure/mirk/wisp/wisp_transform_logger.dart"
    - "test/infrastructure/mirk/wisp/wisp_particle_test.dart"
    - "test/infrastructure/mirk/wisp/wisp_particle_system_test.dart"
    - "test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart"
    - "test/presentation/widgets/fog_layer_wisp_render_test.dart"
    - "test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart"
    - "test/wisp/wisp_pan_invariance_test.dart"
    - "test/wisp/wisp_no_fix_warmup_test.dart"
  modified:
    - "lib/config/constants.dart (+136 lines wisp constants block)"
    - ".planning/phases/04-wisp-particles/04-VALIDATION.md (per-task map populated; nyquist_compliant flipped true)"
decisions:
  - "Wave 0 widget scaffolds use skip:true (with reason comment) instead of compile-failing assertions, because the GREEN behaviour requires constructor parameters (wispParticleSystem on FogLayer + MapScreenServices) that Plan 04-04 will add — referencing them today would block compile of the entire test suite. Same Wave-0-skip discipline as existing FOG-09 fog_pan_translation_test.dart."
  - "WispParticle.position is LatLng (NOT donor's Offset) — WISP-01 dimensional discipline locked in stub. The RED scaffold's pan-invariance test PASSES today against the stub (no UnimplementedError path exercised) because the typing enforcement does not depend on Plan 04-03 logic."
  - "WispParticleSystem constructor accepts a Stopwatch test seam (`wallClock`) so unit tests can control the WISP-03 warm-up gate without sleeping. Plan 04-03 must honour this seam in its impl."
metrics:
  duration: ~10 min
  tasks: 2
  files: 11 (10 created + 1 modified — constants.dart)
  completed: 2026-05-05
---

# Phase 4 Plan 01: Wisp Wave-0 Scaffolds Summary

Wave 0 lands the constants + production stubs + RED test scaffolds for Phase 4, unblocking parallel Wave 1 execution of Plan 04-02 (WispTransformLogger impl) and Plan 04-03 (WispParticleSystem impl) without test-file shimming. Stubs throw `UnimplementedError` predictably; test assertions describe the GREEN behaviour Plans 04-02 / 04-03 / 04-04 must satisfy.

## Constants block landed

`lib/config/constants.dart` lines 480-616 (+136 lines after `kPocDebugSpiralCellSizePx`):

- 13 `kMirkPocWisp*` numeric constants (max-count=200, life=2.5 s, drift=1.5 m/s, peakAlpha=0.35, drag=0.30, birth/death radii, curl-noise force, dt-clamp, curl-input-scale, anchor lat/lon at Melun centre, tint ARGB).
- 1 `WispRadiusBasis` enum + `kMirkPocWispRadiusBasis` selector (paired metres + screenPx constants for A/B walk comparison per CONTEXT.md).
- 2 `kPocWispTransform*` constants (rollup interval = 1 s; buffer cap = 240 = 2 s × 120 Hz — aligned with existing FogTransform/SDF/FrameDelta logger discipline).

All `kMirkFog*` donor names DELIBERATELY NOT REUSED — POC vs MirkFall divergence per CONTEXT.md.

## Stub class signatures

**`WispParticle`** (`lib/infrastructure/mirk/wisp/wisp_particle.dart`, 65 LOC) — mutable struct port of donor's `wisp_particle.dart` with two field-name deviations: `Offset position` → `LatLng position` (WISP-01 dimensional discipline) and `Offset velocity` → `Offset velocityMetersPerSecond` (semantic clarity — Offset reused as 2D-vector for (dx, dy) m/s components). Constructor + mutable-field reads are real (compile + run); `isDead` and `age` getters throw `UnimplementedError('Plan 04-03 implements')`.

**`WispParticleSystem`** (`lib/infrastructure/mirk/wisp/wisp_particle_system.dart`, 137 LOC) — class shell with the public API Plans 04-03/04-04 consume: `wisps` / `activeCount` getters; `spawnAtNewDisc({discId, disc})` (idempotent, warm-up-gated via `wallClock` test seam); `advance(dt)`; `spawnRatePerSecondAndReset({sinceInterval})`; `clear()`. Constructor accepts `maxCount` (default `kMirkPocWispMaxCount`), `rngSeed` (default 1337), and an optional `Stopwatch? wallClock` seam for WISP-03 warm-up gate control from unit tests. All methods throw `UnimplementedError('Plan 04-03 implements')`.

**`WispTransformLogger`** (`lib/infrastructure/mirk/wisp/wisp_transform_logger.dart`, 67 LOC) — class shell mirroring `FogTransformLogger` shape with the WISP-05 9-field record: `activeCount`, `meanAge`, `latBounds`, `lonBounds`, `screenXBounds`, `screenYBounds`, `spawnRatePerSecond`. Constructor accepts optional `Duration? rollupInterval` test seam (default 1 s = `kPocWispTransformLogRollupSeconds`). All methods throw `UnimplementedError('Plan 04-02 implements')`. NO `LatLng` / `Point` imports here — the wisp-side bounds are passed as already-extracted `(double, double)` tuples per RESEARCH §Op 5.

## RED test count per file

| File | Test count | RED count | GREEN count | Skip count | Predictable signature |
|------|-----------:|----------:|------------:|-----------:|-----------------------|
| `test/infrastructure/mirk/wisp/wisp_particle_test.dart` | 3 | 2 | 1 | 0 | `UnimplementedError('Plan 04-03 implements')` from `isDead` / `age` getters; LatLng typing test passes today |
| `test/infrastructure/mirk/wisp/wisp_particle_system_test.dart` | 5 | 5 | 0 | 0 | `UnimplementedError('Plan 04-03 implements')` from `spawnAtNewDisc` / `advance` / `activeCount` |
| `test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart` | 4 | 4 | 0 | 0 | `UnimplementedError('Plan 04-02 implements')` from `start()` |
| `test/presentation/widgets/fog_layer_wisp_render_test.dart` | 2 | 0 | 0 | 2 | `skip: true` — gated on Plan 04-04 FogLayer constructor extension |
| `test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart` | 1 | 0 | 0 | 1 | `skip: true` — gated on Plan 04-04 FogLayer constructor extension |
| `test/wisp/wisp_pan_invariance_test.dart` | 1 | 0 | 1 | 0 | SC #1 LatLng-typing + projection-shift invariant — passes today against stub |
| `test/wisp/wisp_no_fix_warmup_test.dart` | 2 | 0 | 0 | 2 | `skip: true` — gated on Plan 04-04 MapScreenServices wispParticleSystem field |
| **Total** | **18** | **11** | **2** | **5** | |

Suite-wide pre-plan baseline: 180 passed + 1 skipped. Post-plan: 189 passed + 6 skipped + 11 RED (all wisp). Net additions consistent with Wave 0 spec.

## VALIDATION.md status update

`04-VALIDATION.md` per-task map populated with 7 rows spanning all 5 Phase-4 plans (Plan 04-01 T1 + T2 marked ✅ green / ✅ green-RED-as-spec; Plan 04-02 / 04-03 / 04-04 / 04-05 rows ⬜ pending). Frontmatter `nyquist_compliant: true` flipped (all tasks have `<automated>` verify or Wave 0 dependencies; sampling continuity preserved); `wave_0_complete: false` retained until the wave-completion checkbox is ticked at the closure of all Wave 0 work (this single plan IS the wave; the field flips true on the metadata commit OR Plan 04-02 / 04-03's first GREEN flip — left to the wave-1 plans to update per their commit discipline).

## Hand-off to Plans 04-02 + 04-03

**Parallel-safe Wave 1 — no file overlap** between the two plans:

- Plan 04-02 owns ONLY `lib/infrastructure/mirk/wisp/wisp_transform_logger.dart` + `test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart` (RED → GREEN flip; impl mirrors `FogTransformLogger` shape — RESEARCH §Pattern 3).
- Plan 04-03 owns `lib/infrastructure/mirk/wisp/wisp_particle.dart` + `lib/infrastructure/mirk/wisp/wisp_particle_system.dart` + `test/infrastructure/mirk/wisp/wisp_particle_test.dart` + `test/infrastructure/mirk/wisp/wisp_particle_system_test.dart` (RED → GREEN flip; impl ports donor's spawn + advance kinematics in LatLng-degree basis with the curl-noise constants this plan landed).

Plan 04-04 picks up after both Wave 1 plans land — extends `FogLayer` constructor with `wispParticleSystem` parameter, threads it through `_FogPainter`, and removes the `skip: true` annotations on the three Wave-0-skip test files. The `test/wisp/wisp_pan_invariance_test.dart` pure-Dart projection test stays GREEN unchanged across the wave transitions (no Plan 04-04 dependency — passes today).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] testWidgets `skip:` parameter type signature**
- **Found during:** Task 2 — `flutter analyze` after first draft of `fog_layer_single_camera_snapshot_test.dart` and `wisp_no_fix_warmup_test.dart`
- **Issue:** Plan body specified `skip: 'reason string'` but the `testWidgets` API only accepts `bool?` for skip (string-typed `skip:` is `test()` only, not `testWidgets()`).
- **Fix:** Switched to `skip: true` plus a multi-line comment block above each `skip:` line documenting the same reason text the plan specified. Same information density, compile-clean.
- **Files modified:** `test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart`, `test/wisp/wisp_no_fix_warmup_test.dart`
- **Commit:** 9d1ec4a (rolled into the Task 2 commit, fix lived in the same draft cycle)

**2. [Rule 1 - Bug] Unnecessary `dart:ui` imports + unused `meters100` constant**
- **Found during:** Task 2 — `flutter analyze` after first drafts
- **Issue:** Test files imported `dart:ui` for `Offset` even though `flutter_test` already re-exports it (linter `unnecessary_import`); pan-invariance test declared a `meters100` constant and never used it (the eastward-pan-deg-lon constant is the actual derived value).
- **Fix:** Removed the redundant imports + dropped the unused `meters100` declaration; kept the comment that documents the 100 m → degrees-longitude conversion math.
- **Files modified:** `test/infrastructure/mirk/wisp/wisp_particle_test.dart`, `test/wisp/wisp_pan_invariance_test.dart`
- **Commit:** 9d1ec4a (rolled into the Task 2 commit)

**3. [Rule 1 - Bug] Plan body's plan-time-error: original PLAN.md interface block referenced `WispParticleSystem.advanceFromWallClock` in the `kMirkPocWispMaxDtSeconds` docstring, but the system surface only exposes `advance(dt)`. Resolved by using `[WispParticleSystem.advance]` in the constants docstring instead.**
- **Found during:** Task 1 — drafting the constants block
- **Issue:** PLAN.md `<interfaces>` block had `void advance(double dt) => throw UnimplementedError('Plan 04-03');` (plain `advance`) but the `kMirkPocWispMaxDtSeconds` action-block docstring instructed "Consumed by `[WispParticleSystem.advanceFromWallClock]`". Two surfaces → docstring DRIFT. The plan's `<tasks>` action block tells me to populate the docstring; if I quoted the plan verbatim my dartdoc reference would resolve to a non-existent symbol.
- **Fix:** Pointed the docstring at `[WispParticleSystem.advance]` (the actual surface). Same semantic intent (the `dt` clamp is consumed inside the integration step regardless of whether the caller is wall-clock-derived or unit-test-injected).
- **Files modified:** `lib/config/constants.dart`
- **Commit:** 1538857

### Auth Gates Encountered

None.

## Self-Check: PASSED

Files created (verified on disk):
- FOUND: lib/infrastructure/mirk/wisp/wisp_particle.dart
- FOUND: lib/infrastructure/mirk/wisp/wisp_particle_system.dart
- FOUND: lib/infrastructure/mirk/wisp/wisp_transform_logger.dart
- FOUND: test/infrastructure/mirk/wisp/wisp_particle_test.dart
- FOUND: test/infrastructure/mirk/wisp/wisp_particle_system_test.dart
- FOUND: test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart
- FOUND: test/presentation/widgets/fog_layer_wisp_render_test.dart
- FOUND: test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart
- FOUND: test/wisp/wisp_pan_invariance_test.dart
- FOUND: test/wisp/wisp_no_fix_warmup_test.dart
- FOUND: lib/config/constants.dart (modified — +136 lines)
- FOUND: .planning/phases/04-wisp-particles/04-VALIDATION.md (modified — per-task map populated)

Commits (verified via `git log`):
- FOUND: 1538857 — feat(04-01): add Phase-4 wisp constants block
- FOUND: 9d1ec4a — feat(04-01): wave 0 wisp stubs + RED tests + VALIDATION map

Verifications run:
- `flutter analyze`: 0 issues across the entire workspace.
- `dart format --line-length 160 --set-exit-if-changed lib/ test/`: 0 changes (idempotent).
- `flutter test`: 189 passed + 6 skipped + 11 RED-as-spec; non-wisp tests stay GREEN (zero regressions).
