---
phase: 03-fog-of-war-the-hypothesis
plan: 04
subsystem: infra
tags: [stopwatch, monotonic-clock, ring-buffer, jsonl-logging, dart-async, broadcast-stream]

# Dependency graph
requires:
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 03-01 Wave 0 stub (FrameDeltaProbe + FrameDeltaRollup throw-on-call) + kPocFrameDeltaBufferMaxSamples / kPocFrameDeltaLogRollupSeconds constants"
provides:
  - "FrameDeltaProbe full surface — recordCameraSnapshot / recordFogUniformPopulation / start / stop / dispose / rollups stream + JSONL emission"
  - "@visibleForTesting debugRecordRawDelta seam (deterministic δ injection bypassing live Stopwatch)"
  - "FrameDeltaRollup payload with both *Micros (int) and *Ms (double, 3-decimal) field families — parser parity with SdfRebuildLogger"
  - "Dual-clock contract enforced by code dartdoc + test #7 (epochSecond MUST be DateTime.now()-derived, never Stopwatch-derived)"
affects: ["03-05-fog-layer", "03-06-frame-delta-overlay", "03-07-shader-sanity-screen", "03-08-falsification"]

# Tech tracking
tech-stack:
  added: []  # No new pubspec deps — all surface area uses dart:async + dart:convert + package:logging + package:flutter/foundation already in pubspec.lock
  patterns:
    - "Dual-clock probe: Stopwatch (monotonic) for delta math + DateTime.now() (wall-clock) for grep-correlation tag — both clocks coexist on purpose"
    - "@visibleForTesting deterministic test seam (debugRecordRawDelta) keeps production methods untouched while letting tests assert ±0 µs precision"
    - "Defence-in-depth clamping: non-monotonic input clamps δ at 0 instead of throwing — paint path never crashes on a probe bug"
    - "Broadcast StreamController (multiple subscribers OK — overlay + post-walk inspectors)"
    - "FIFO ring-buffer trim via while-loop (length > cap → removeAt(0)) — bounds memory at ~2 s of 120 Hz history"

key-files:
  created: []
  modified:
    - "lib/infrastructure/mirk/frame_delta_probe.dart — Plan 03-01 stub (68 LoC, throws) → full impl (231 LoC, 0 issues)"
    - "test/infrastructure/mirk/frame_delta_probe_test.dart — Plan 03-01 placeholder (47 LoC, 2 RED) → full suite (138 LoC, 7 GREEN)"

key-decisions:
  - "Honor dual-clock discipline: Stopwatch for delta math, DateTime.now() for the epochSecond rollup tag — pinned by dartdoc warning + test #7 magnitude assertion (epochSecond > 1.7e9). A future executor 'simplifying' to one clock would fail test #7 on the first run."
  - "@visibleForTesting debugRecordRawDelta seam over the alternative 'recordFogUniformPopulation(_clock.elapsedMicroseconds - X)' approach: real-clock jitter adds ±N µs per call which makes ±1 µs assertions race-y. The seam guarantees ±0 µs precision on the median/p95/max math."
  - "Defence-in-depth clamp at 0 (not assertion-throw): Stopwatch.elapsedMicroseconds IS monotonic, so a negative δ is impossible from production callers — but a probe-bug elsewhere must NEVER crash the paint path. `math.max(0, now - snapshotMicros)` is the cheap defensive choice."
  - "Both *Micros (int, source-of-truth precision) and *Ms (double, 3-decimal convenience) field families on FrameDeltaRollup: matches the millisecond convention used by SdfRebuildLogger so post-walk grep tooling parses both formats with the same regex/JSON parser."

patterns-established:
  - "Dual-clock probe pattern: monotonic Stopwatch for delta math + wall-clock DateTime.now() for cross-stream join keys. Documented in dartdoc, defended by a test that asserts the magnitude of epochSecond. Reusable across other probes that need both 'how long did this take' AND 'when in wall-clock terms'."
  - "Test-seam-via-@visibleForTesting: production methods stay untouched, tests get a deterministic injection point. Mirrors the parent project's Stream.listen / RandomAccessFile probe pattern but adapted to per-frame delta math."

requirements-completed: [FOG-08]

# Metrics
duration: 4 min
completed: 2026-05-01
---

# Phase 03 Plan 04: FOG-08 FrameDeltaProbe Summary

**Stopwatch-backed monotonic frame-delta probe with 1-Hz JSONL rollups (median/p95/max in µs and ms), broadcast Stream<FrameDeltaRollup> for Plan 03-06 overlay, dual-clock discipline (Stopwatch for delta math, DateTime.now() for grep-correlation tag), and a @visibleForTesting deterministic δ-injection seam.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-05-01T15:02:22Z
- **Completed:** 2026-05-01T15:06:56Z
- **Tasks:** 1 (TDD: RED → GREEN, no REFACTOR needed — implementation was clean on first GREEN)
- **Files modified:** 2 (lib/.../frame_delta_probe.dart 68 → 231 LoC; test/.../frame_delta_probe_test.dart 47 → 138 LoC)

## Accomplishments

- **FOG-08 implementation complete.** Full FrameDeltaProbe surface ships: `recordCameraSnapshot()` returns monotonic Stopwatch µs, `recordFogUniformPopulation(snap)` records `max(0, now - snap)` to a 240-cap ring buffer, `start()` schedules an idempotent 1-Hz rollup timer, `stop()` cancels, `dispose()` closes the stream + clears the buffer.
- **1-Hz rollup math correct** — sorted middle is the median, `(len*0.95).floor().clamp(0, len-1)` is the p95 index, `sorted.last` is max. All three asserted on the deterministic 1k-10k µs synthetic data set (test #1).
- **JSONL persistence wired.** Each rollup emits one JSON line via `Logger('infrastructure.mirk.frame_delta').info(...)` with all 8 keys: `epochSecond`, `sampleCount`, `medianMicros`, `p95Micros`, `maxMicros`, `medianMs`, `p95Ms`, `maxMs` (the *Ms fields are 3-decimal doubles for parser parity with SdfRebuildLogger).
- **Dual-clock contract locked into both code AND tests.** Dartdoc on the class explicitly forbids future executors from "simplifying" by collapsing to one clock; test #7 asserts `epochSecond > 1.7e9` which would fail the moment anyone replaces the wall-clock derivation with a Stopwatch read.
- **Test seam exposed for downstream plans.** `@visibleForTesting void debugRecordRawDelta(int micros)` lets Plan 03-05 (FogLayer paint-path tests) and Plan 03-06 (overlay widget tests) inject deterministic δ values without going through the live Stopwatch. Constructor named args `rollupInterval` + `clock` are also exposed (tests use `Duration(milliseconds: 100)` for fast emission).

## Task Commits

Each task was committed atomically (TDD RED → GREEN):

1. **Task 1 RED: 7 failing tests for FOG-08** — `5add4e5` (test) — replaced 2-test Plan 03-01 stub with full 7-test suite using `@visibleForTesting` `debugRecordRawDelta` seam; tests fail to compile against the throwing stub (expected RED).
2. **Task 1 GREEN: full FrameDeltaProbe implementation** — `e20165a` (feat) — Stopwatch-backed monotonic clock + dual-clock invariant + ring buffer FIFO + 1-Hz Timer.periodic + broadcast StreamController + JSONL via Logger; all 7 tests GREEN; flutter analyze + dart format clean.

**Plan metadata:** _(pending — created at end-of-plan commit)_

_Note: No REFACTOR commit — the GREEN implementation was already clean (no duplication, single-purpose methods, clear separation between production methods and the @visibleForTesting seam). REFACTOR would have been busywork._

## Files Created/Modified

- `lib/infrastructure/mirk/frame_delta_probe.dart` — **modified** (68 → 231 LoC). Plan 03-01 stub replaced with full implementation: Stopwatch-backed monotonic clock, ring buffer with FIFO trim at `kPocFrameDeltaBufferMaxSamples` (240), idempotent `start()` with `Timer.periodic` of `_rollupInterval`, broadcast `StreamController<FrameDeltaRollup>` for multi-subscriber consumption, JSONL emission via `Logger('infrastructure.mirk.frame_delta').info(json.encode(...))`, `@visibleForTesting debugRecordRawDelta` seam, defence-in-depth `math.max(0, ...)` delta clamp, dual-clock dartdoc warning.
- `test/infrastructure/mirk/frame_delta_probe_test.dart` — **modified** (47 → 138 LoC). Plan 03-01 2-test placeholder replaced with full 7-test suite covering: (1) median/p95/max correctness on a 10-sample 1-10ms synthetic set, (2) idle seconds emit nothing, (3) non-monotonic production-path input clamps at 0 without throwing, (4) JSONL line contains all 8 keys, (5) buffer caps at 240 with FIFO trim, (6) `dispose()` closes the stream (emitsDone), (7) wall-clock `epochSecond` invariant (`epochSecond > 1.7e9` AND within ±1 s of `DateTime.now() ~/ 1000`).

## Decisions Made

See frontmatter `key-decisions:` for the four decisions taken during this plan, all documented inline in code (dartdoc) and tests:

1. **Dual-clock discipline** — Stopwatch for δ math, DateTime.now() for the epochSecond rollup tag. Documented in 25 lines of dartdoc on the class itself; pinned by test #7 which would fail if anyone collapses the two clocks.
2. **`@visibleForTesting debugRecordRawDelta` seam** — chosen over the `recordFogUniformPopulation(t0 - X)` approach to eliminate real-clock jitter (±N µs per call) from test assertions.
3. **Defence-in-depth clamp at 0, not assertion-throw** — Stopwatch IS monotonic, so a negative δ is impossible from production callers; but the paint path must NEVER crash on a probe bug, so `math.max(0, ...)` is cheaper and safer than `assert()`.
4. **Both *Micros (int) and *Ms (double 3-decimal) field families** — parser parity with SdfRebuildLogger means post-walk tooling can read both rollup formats with the same regex / JSON.decode logic.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unnecessary `dart:async` import in test file**
- **Found during:** Task 1 GREEN (after `flutter analyze`)
- **Issue:** `flutter_test` already re-exports `Future`/`Stream`/`Completer`/etc., so an explicit `import 'dart:async';` produces an `unnecessary_import` info-level warning under the project's strict analysis_options.yaml. Plan-prescribed code didn't account for this transitive re-export.
- **Fix:** Removed `import 'dart:async';` from `test/infrastructure/mirk/frame_delta_probe_test.dart`. Used `Future<void>.delayed(...)` (works because flutter_test re-exports Future).
- **Files modified:** `test/infrastructure/mirk/frame_delta_probe_test.dart`
- **Verification:** `flutter analyze lib/ test/` reports `No issues found! (ran in 3.1s)`. All 7 tests still GREEN.
- **Committed in:** `e20165a` (Task 1 GREEN commit, alongside the production implementation)

---

**Total deviations:** 1 auto-fixed (1 Rule 1 - Bug)
**Impact on plan:** Trivial. The plan didn't account for flutter_test's transitive `dart:async` re-export; removing the unnecessary import keeps `flutter analyze --fatal-infos` clean. No scope creep, no behavioural change.

## Issues Encountered

None. The plan was tightly specified — RED → GREEN on the first try with all 7 tests passing immediately, no debug rounds needed.

## Test Seam Surface for Plans 03-05 + 03-06

Plans 03-05 (FogLayer paint-path) and 03-06 (FrameDeltaProbeOverlay widget) consume this probe. The exposed test seams are:

- **`FrameDeltaProbe({Duration? rollupInterval, Stopwatch? clock})` constructor named args** — pass `rollupInterval: Duration(milliseconds: N)` for fast test emission; pass a synthetic `Stopwatch` for fully-deterministic timing.
- **`@visibleForTesting void debugRecordRawDelta(int micros)`** — append a δ value (clamped at ≥ 0) directly to the ring buffer, bypassing the live Stopwatch read. This is the ONLY supported deterministic injection seam; production callers MUST NOT use it.
- **`Stream<FrameDeltaRollup> get rollups`** — broadcast stream, multiple subscribers OK. Plan 03-06 overlay subscribes; tests can subscribe in parallel for assertion.
- **`FrameDeltaRollup` payload exposes both `*Micros` (int, precision-correct) and `*Ms` (double, 3-decimal) getters** — overlay can render whichever format it prefers.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 03-04 contract complete.** FOG-08 ring buffer + 1-Hz rollup + JSONL log fully implemented and tested. ✓
- **Plan 03-05 unblocked** — FogLayer paint path can now thread `probe.recordCameraSnapshot()` through the painter constructor, and `_FogPainter.paint()` can call `probe.recordFogUniformPopulation(snap)` right before `FogShaderUniforms.setAll(...)` per RESEARCH.md Pattern 6.
- **Plan 03-06 unblocked** — FrameDeltaProbeOverlay can now `StreamBuilder<FrameDeltaRollup>(stream: probe.rollups, ...)` and render the live median/p95/max with the colour-coding thresholds already in `lib/config/constants.dart` (`kPocFrameDeltaMedianGreenMicros`/`YellowMicros`, etc.).
- **Phase 3 RED test count after Plan 03-04:** 2 RED remain (`fog_clip_path_test.dart` — FOG-06, scheduled for Plan 03-05). Down from 13 RED at end of Plan 03-01. Wave 1 (Plans 03-02 + 03-03 + 03-04) is COMPLETE.
- **No blockers** for Wave 2 (Plans 03-05 + 03-06 + 03-07).

## Self-Check: PASSED

- `lib/infrastructure/mirk/frame_delta_probe.dart` — FOUND
- `test/infrastructure/mirk/frame_delta_probe_test.dart` — FOUND
- `.planning/phases/03-fog-of-war-the-hypothesis/03-04-SUMMARY.md` — FOUND
- Commit `5add4e5` (RED tests) — FOUND
- Commit `e20165a` (GREEN implementation) — FOUND

---
*Phase: 03-fog-of-war-the-hypothesis*
*Completed: 2026-05-01*
