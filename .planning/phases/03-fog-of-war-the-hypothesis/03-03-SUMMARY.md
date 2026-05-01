---
phase: 03-fog-of-war-the-hypothesis
plan: 03
subsystem: infra
tags: [fog-of-war, sdf, cache, jsonl-logging, hash-key, ui-image-disposal, FOG-03]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: RevealedSdfBuilder (256² midpoint-128 SDF, BUG-011 metric-distance fix), RevealDisc.intersectsBbox, MirkViewportBbox value-equality, package:logging Logger, kPocSdfLogRollupSeconds constant
  - phase: 03-fog-of-war-the-hypothesis (Plan 03-01 — Wave 0 keystone)
    provides: SdfCache + SdfRebuildLogger production stubs, RED tests in test/infrastructure/mirk/sdf/ + test/infrastructure/mirk/sdf_rebuild_logger_test.dart
provides:
  - SdfCache.getOrBuild — hash-keyed wrapper around RevealedSdfBuilder; same (discs, viewport) returns identical ui.Image; miss triggers rebuild + dispose-prior-image + record-rebuild-duration
  - SdfRebuildLogger.start/stop/recordRebuild — 1-second JSONL rollup writer (medianMs/p95Ms/maxMs/rebuildCount/discCount/intersectingDiscCount/epochSecond); idle seconds emit nothing; stop() flushes pending samples synchronously
  - rollupInterval test seam on SdfRebuildLogger (Duration? in constructor; defaults to const Duration(seconds: kPocSdfLogRollupSeconds))
  - builder injection seam on SdfCache (RevealedSdfBuilder? in constructor; defaults to const RevealedSdfBuilder())
affects: [03-05-fog-layer-paint, 03-06-shader-sanity-screen, 03-07-map-screen-fog-integration, 03-08-walk-evidence]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Quantised hash key — disc (lat, lon, radius) multiplied by 1e6 / 1e3 then rounded to int before Object.hash; tames floating-point drift between consecutive frames at the same GPS fix"
    - "rollupInterval test-seam pattern — production constructor exposes optional Duration that defaults to a kPoc* constant; tests pass a shorter duration (100 ms) to keep the suite fast without changing rollup logic"
    - "Hoisted file-private constants for magic numbers — _spatialQuantisationFactor (1e6), _radiusQuantisationFactor (1e3), _microsecondsPerMillisecond (1000.0) — keeps the inline call sites docstring-free of bare numbers per CLAUDE.md magic-number rule"

key-files:
  created: []
  modified:
    - lib/infrastructure/mirk/sdf_rebuild_logger.dart
    - lib/infrastructure/mirk/sdf/sdf_cache.dart
    - test/infrastructure/mirk/sdf_rebuild_logger_test.dart

key-decisions:
  - "Hash composition: Object.hash(viewport, Object.hashAll(discHashes), discs.length) — three components with discs.length included separately so a length-1 list and a length-2 list with the first disc identical can never collide via partial hash overlap"
  - "Spatial quantisation 6 decimals (~10 cm at equator, ~7 cm at Melun's 48.5°N latitude) — well below GPS accuracy (5-15 m typical) and the POC's 25 m disc radius; defends against same-fix consecutive-frame drift causing spurious cache misses"
  - "stop() flushes pending samples synchronously even before a timer tick — guards against losing the final rollup if SdfCache.dispose runs in the middle of a 1-second window (e.g., user backgrounds the app or navigates away from /map)"
  - "Logger.root.level = Level.ALL set in test setUpAll() — package:logging defaults to Level.WARNING; without this, INFO-level rollup lines never reach Logger.root.onRecord and the active-rollup test reports zero captured records"

patterns-established:
  - "Wave 0 → Wave 1+ flip pattern: each Wave 1 plan replaces a Plan 03-01 stub by writing the full file (Write tool, not Edit) and updates the matching RED test file with any new test seams the production code exposes; commit message format `feat(03-XX): implement {Class} ...` references the requirement IDs the plan owns"
  - "Test-seam discovery during impl: Plan 03-01's RED test for SdfRebuildLogger relied on a real 1100 ms wall-clock delay; Plan 03-03 surfaced rollupInterval as an injectable Duration so the same test now finishes in ~250 ms (4× faster suite)"

requirements-completed: [FOG-03]

# Metrics
duration: 5 min
completed: 2026-05-01
---

# Phase 3 Plan 3: SDF Cache + Rebuild Logger Summary

**FOG-03 hash-keyed SdfCache + 1-second JSONL SdfRebuildLogger landed: cache returns identical `ui.Image` on (discs, viewport) match, disposes prior image on miss, records rebuild duration; logger aggregates per-active-second to `Logger('infrastructure.mirk.sdf')` with median/p95/max ms — idle seconds silent.**

## Performance

- **Duration:** 5 min (plan execution; bracketing 15:02 → 15:07 UTC)
- **Started:** 2026-05-01T15:02:12Z
- **Completed:** 2026-05-01T15:06:43Z
- **Tasks:** 2 (both `type=auto tdd=true`, executed without checkpoints)
- **Files modified:** 3 (2 production stubs replaced + 1 test file expanded with rollupInterval seam + new stop-flush test)

## Accomplishments

- **SdfRebuildLogger** ships per-second JSONL rollup with 7 fields (`epochSecond`, `discCount`, `intersectingDiscCount`, `rebuildCount`, `medianMs`, `p95Ms`, `maxMs`); idle seconds emit nothing; `stop()` flushes pending samples even before a timer tick. 3 tests GREEN (active rollup, idle silence, stop-flush). 82 lines of production code.
- **SdfCache** ships hit/miss matrix wrapping the const donor `RevealedSdfBuilder`: same `(discs, viewport)` hash returns identical `ui.Image` (cache hit, no rebuild work); different disc list OR different viewport bbox triggers rebuild via `_builder.buildFromDiscs(...)`, disposes prior `ui.Image`, records duration via injected `SdfRebuildLogger`. 3 tests GREEN (identical-on-hit, different-on-disc-change, different-on-viewport-change). 103 lines of production code.
- **rollupInterval test seam** speeds the SdfRebuildLogger test suite from ~1100 ms wall-clock per active-rollup test to ~250 ms (4× faster); production default unchanged at 1 s (`kPocSdfLogRollupSeconds`).
- All 6 SdfCache + SdfRebuildLogger tests GREEN; `flutter analyze` clean across `lib/` + `test/` (0 issues); `dart format --line-length 160` clean across all touched files.

## Task Commits

Each task was committed atomically:

1. **Task 1: SdfRebuildLogger 1-second JSONL rollup** — `318c9d1` (feat)
2. **Task 2: SdfCache hash-keyed wrapper around RevealedSdfBuilder** — `f990b27` (feat)

_Note: Both tasks were `tdd="true"`; the existing Plan 03-01 RED tests served as the RED step (verified RED before implementation), so each task GREEN-ed in a single commit (test seam expanded in Task 1's commit alongside the production code; Task 2's tests were already in their final shape from Plan 03-01 and just flipped GREEN). REFACTOR step applied automatically by `dart format` (one minor `.map(...).toList(...)` chain restructure in Task 2)._

## Files Created/Modified

**Production code (replaced Plan 03-01 stubs):**
- `lib/infrastructure/mirk/sdf_rebuild_logger.dart` — 82 lines. `SdfRebuildLogger({Duration? rollupInterval})`; `start()` (idempotent — Timer.periodic on `_rollupInterval`); `stop()` (cancel + final-flush); `recordRebuild({elapsedMs, discCount, intersectingDiscCount})` (buffer append); `_emitRollup()` (sort, compute median/p95/max, json.encode, `Logger('infrastructure.mirk.sdf').info(...)`, clear buffer).
- `lib/infrastructure/mirk/sdf/sdf_cache.dart` — 103 lines. `SdfCache({required SdfRebuildLogger rebuildLogger, RevealedSdfBuilder? builder})`; `getOrBuild({required List<RevealDisc> discs, required MirkViewportBbox viewport})` (hash → if hit return cached; else Stopwatch + await builder + dispose-prior + record); `dispose()` (release cached `ui.Image`); `_hash` (Object.hash over discs.length + per-disc quantised lat/lon/radius + viewport).

**Tests (expanded RED → GREEN with new test seam):**
- `test/infrastructure/mirk/sdf_rebuild_logger_test.dart` — 87 lines. 3 tests:
  - `recordRebuild buffers samples; emits one JSONL rollup per active second` — uses `rollupInterval: Duration(milliseconds: 100)` test seam, asserts all 7 JSONL fields present.
  - `idle seconds emit no log line` — start, wait 350 ms (3+ rollup intervals), stop, expect captured.isEmpty.
  - `stop flushes pending samples even before a timer tick` (NEW) — uses `rollupInterval: Duration(seconds: 10)` (so timer never fires), records one sample, calls stop, asserts the synchronous final-flush emitted.
- `test/infrastructure/mirk/sdf/sdf_cache_test.dart` — UNCHANGED from Plan 03-01 (the 3 RED tests just flipped GREEN against the new production code).

## Decisions Made

- **Spatial quantisation factor `1e6` (6 decimal places).** ~10 cm at the equator, ~7 cm at Melun's 48.5°N latitude. Well below GPS accuracy (5-15 m typical for iPhone CL), well below the POC's 25 m disc radius (`kPocRevealDiscRadiusMeters`). Tames floating-point drift between consecutive frames reading the same GPS fix.
- **Radius quantisation factor `1e3` (1 mm).** The POC radius is fixed at 25 m, so this is unused but cheap insurance against future variable-radius discs.
- **Hash composition: `Object.hash(viewport, Object.hashAll(discHashes), discs.length)`.** Three separate components — including `discs.length` separately so length-1 vs length-2 lists with the first disc identical cannot accidentally collide via partial hash overlap. `MirkViewportBbox` already has value-equality (Phase 1 BOOT-08).
- **`stop()` flushes synchronously.** Guards against losing the final rollup if `SdfCache.dispose` runs mid-window (e.g., user backgrounds the app or `MapScreen.dispose` runs before the next 1-second tick). The new `stop flushes pending samples` test pins this contract — added beyond the plan's prescribed test set, but justified by the donor-SDF builder's docstring that documents per-frame rebuild during pan (so any pan-then-dispose sequence produces a partial-window rollup that would be lost without synchronous flush).
- **`Logger.root.level = Level.ALL` in test `setUpAll()`.** package:logging defaults to `Level.WARNING`; without this, `Logger.info(...)` calls inside `_emitRollup` never surface through `Logger.root.onRecord`. Mirrors the pattern from Phase 1 `file_logger_test.dart` and Phase 2 `geolocator_service_test.dart`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added `Logger.root.level = Level.ALL` to test setUpAll**
- **Found during:** Task 1 (initial RED-verification run before implementing the production code)
- **Issue:** package:logging's root logger defaults to `Level.WARNING`, meaning `Logger('infrastructure.mirk.sdf').info(...)` calls in production never surface through `Logger.root.onRecord` in tests. Without this fix, the `recordRebuild buffers samples; emits one JSONL rollup per active second` test would report `captured: []` even when the rollup logic is fully correct — a false-negative test that masks the real GREEN state.
- **Fix:** Added `setUpAll(() { Logger.root.level = Level.ALL; });` at the top of the test group. Mirrors the established pattern from `test/infrastructure/logging/file_logger_test.dart` (Phase 1) and `test/infrastructure/location/geolocator_service_test.dart` (Phase 2).
- **Files modified:** `test/infrastructure/mirk/sdf_rebuild_logger_test.dart`
- **Verification:** All 3 SdfRebuildLogger tests GREEN; without the setUpAll, the active-rollup test would fail with `Expected: an object with length of a value greater than or equal to <1>, Actual: []`.
- **Committed in:** `318c9d1` (Task 1 commit)

**2. [Rule 2 - Missing Critical] Added `stop flushes pending samples even before a timer tick` test (test seam coverage)**
- **Found during:** Task 1 (writing the production code; noticed `stop()` has a non-trivial behaviour — synchronous final-flush — that the plan-prescribed tests didn't cover)
- **Issue:** Plan 03-01's RED tests only cover the periodic-timer rollup path. The `stop()` final-flush branch is critical for not losing data when MapScreen disposes mid-window (e.g., user navigates away during pan); without a test, a future refactor could quietly remove the final-flush and the suite would still report all-GREEN.
- **Fix:** Added third test using `rollupInterval: Duration(seconds: 10)` (timer never fires during the test) + `recordRebuild` + `stop()` + assertion that exactly one rollup was captured. Pins the synchronous final-flush contract.
- **Files modified:** `test/infrastructure/mirk/sdf_rebuild_logger_test.dart`
- **Verification:** Test GREEN against the production implementation; would FAIL if the `stop()` body removed its final-flush branch.
- **Committed in:** `318c9d1` (Task 1 commit)

**3. [Rule 1 - Bug] Hoisted three magic numbers into file-private named constants**
- **Found during:** Task 2 (writing `_hash` and the rebuild-recording line in `getOrBuild`)
- **Issue:** Plan-prescribed code had `1e6`, `1e3`, and `1000.0` as bare literals inside the inline call sites. CLAUDE.md "Magic numbers" rule: "Aucun number magique. Stocker dans une variable nommée (locale si usage unique, constante partagée sinon)."
- **Fix:** Hoisted to file-private const doubles with docstrings explaining the chosen quantisation:
  - `_spatialQuantisationFactor = 1e6` — lat/lon → 6 decimals (~10 cm)
  - `_radiusQuantisationFactor = 1e3` — radius → 1 mm
  - `_microsecondsPerMillisecond = 1000.0` — Stopwatch divisor
- **Files modified:** `lib/infrastructure/mirk/sdf/sdf_cache.dart`
- **Verification:** `flutter analyze --fatal-infos` clean; `dart format` clean.
- **Committed in:** `f990b27` (Task 2 commit)

**4. [Rule 3 - Blocking format-fix] dart format restructured `.map(...).toList(...)` chain in `_hash`**
- **Found during:** Task 2 (post-implementation `dart format --set-exit-if-changed` check)
- **Issue:** Original layout had the `.map(...) .toList(growable: false)` on one line that exceeded the 160-char limit; formatter split into a multi-line chain.
- **Fix:** Accepted formatter output (no semantic change). Re-ran tests + analyze post-format to confirm no regression.
- **Files modified:** `lib/infrastructure/mirk/sdf/sdf_cache.dart`
- **Verification:** `dart format --set-exit-if-changed` clean after re-run; all 3 SdfCache tests still GREEN.
- **Committed in:** `f990b27` (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (2 Rule 2 - Missing Critical, 1 Rule 1 - Bug, 1 Rule 3 - Blocking). All deviations track plan-vs-reality drift around package:logging defaults (Logger level), CLAUDE.md magic-number rule, dart format restructuring, and one beyond-plan test seam (`stop()` flush) that closes a non-trivial production-code branch. None affect the plan's behavioural contract — every must_haves truth still holds.

**Impact on plan:** Plan-prescribed behaviour ships intact. Test suite is faster (rollupInterval seam: ~1100 ms → ~250 ms per active-rollup test, 4× speedup) AND more thorough (the stop-flush test catches a regression class the plan missed). Production code adds 3 named constants that improve readability with zero runtime cost.

## Issues Encountered

None beyond the deviations above. Each was caught by `flutter analyze --fatal-infos` or `flutter test` before the commit landed.

**Pre-existing test failures observed but OUT OF SCOPE for Plan 03-03 (verified pre-existing on `git stash`):**
- `test/infrastructure/mirk/frame_delta_probe_test.dart` — compile error: `No named parameter with the name 'rollupInterval'` on `FrameDeltaProbe(...)`. Owned by Plan 03-04 (`FrameDeltaProbe` ring buffer + rollup timer). Not caused by Plan 03-03.
- `test/presentation/widgets/fog_clip_path_test.dart` — `UnimplementedError: computeFogClipPath — Plan 03-05`. Owned by Plan 03-05 (FogLayer paint + clip path). Not caused by Plan 03-03.

Per `<deviation_rules>` SCOPE BOUNDARY: "Only auto-fix issues DIRECTLY caused by the current task's changes." Both failures are Wave 0 RED tests pinned to future Plans 03-04 / 03-05 by Plan 03-01's falsification harness — exactly the contract Wave 0 promised, exactly the work Wave 1+ flips RED → GREEN one plan at a time.

## User Setup Required

None — no external service configuration required for Plan 03-03 (entirely additive code within the existing Flutter codebase; no new dependencies, no new env vars, no new asset files).

## Next Phase Readiness

- **Plan 03-04 unblocked**: SdfRebuildLogger's 1-second cadence + `epochSecond` field is the timeline-correlation handshake the FrameDeltaProbe rollup will mirror (both emit on `now ~/ 1000` boundaries via wall-clock-aligned `Timer.periodic`). Plan 03-04 reads the rollupInterval test-seam pattern from this plan and applies it identically to FrameDeltaProbe.
- **Plan 03-05 unblocked (FOG-04 + FOG-06 + FOG-07)**: FogLayer.build will consume `SdfCache.getOrBuild(discs: ..., viewport: ...)` per the plan's "Plan 03-05 dependency note": the future-returning signature requires the two-step pattern from RESEARCH.md Pattern 5 — async cache lookup → ValueNotifier-backed image → painter reads most-recent-completed. SdfCache's hash-key contract guarantees stable instance identity across consecutive build() calls at the same (discs, viewport), so Plan 03-05 can call `cache.getOrBuild(...)` from inside `FogLayer.build()` without worrying about thrash.
- **Plan 03-06 unblocked**: ShaderSanityScreen will instantiate `SdfCache(rebuildLogger: SdfRebuildLogger())` for the synthetic 80 m disc and let the cache's first-call miss-then-build path produce the test image.
- No blockers. Phase 1+2 regression: 100% of Phase 1+2 tests still GREEN (verified by full `flutter test` run; the only RED items are the Wave 0 falsification tests pinned to Plans 03-04 / 03-05).

## Self-Check: PASSED

Verified post-summary:
- All 5 must_haves artifacts FOUND on disk (2 production files + 2 test files + this SUMMARY)
- Both task commits present in `git log` (`318c9d1`, `f990b27`)
- `flutter test test/infrastructure/mirk/sdf/ test/infrastructure/mirk/sdf_rebuild_logger_test.dart` reports 6 GREEN / 0 RED / 0 SKIPPED
- `flutter analyze` clean (0 issues across `lib/` + `test/`)
- `dart format --line-length 160 --set-exit-if-changed lib/infrastructure/mirk/sdf/ lib/infrastructure/mirk/sdf_rebuild_logger.dart test/infrastructure/mirk/` clean

---
*Phase: 03-fog-of-war-the-hypothesis*
*Completed: 2026-05-01*
