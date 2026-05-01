---
phase: 02-map-no-fog
plan: 05
subsystem: ui
tags: [phase-2-wave-3, map-screen, flutter_map, vector_map_tiles, pmtiles, protomaps_themes, lifecycle, dispose, runAsync, map-02, map-03, map-04, map-05, map-06, loc-02-visibility]

# Dependency graph
requires:
  - phase: 02-map-no-fog
    plan: 01
    provides: Wave 0 stubs (MapScreen.fromServices placeholder, MapScreenServices DTO), constants block, ErrorScreen + /error route, RED scaffold tests
  - phase: 02-map-no-fog
    plan: 02
    provides: PmtilesAssetCopier.ensureCopied (gate-screen pre-navigation copy guarantees PMTiles is on disk before MapScreen mounts)
  - phase: 02-map-no-fog
    plan: 03
    provides: GeolocatorService.stream() (LOC-01 settings + INFO log) + BlueDotMarker.build (LOC-02 spec)
  - phase: 02-map-no-fog
    plan: 04
    provides: RecenterFab (LOC-04 + LOC-05) + MapCompass (bearing-stream sync + snap-to-north tween)
provides:
  - Fully wired MapScreen StatefulWidget — FlutterMap + VectorTileLayer + conditional CircleLayer/BlueDot + RecenterFab + MapCompass + FpsCounterOverlay all composed inside single Scaffold
  - Production /map route builder — FutureBuilder wraps `getApplicationSupportDirectory()` + binds GeolocatorService.stream factory
  - Synchronous void dispose() pattern — fire-and-forget for cancel() + archive.close(), MapController.dispose() last before super.dispose()
  - Robust MapCompass.initState — try/catches the camera-read so the widget can mount on the same frame as FlutterMap (was a latent bug from Plan 02-04)
  - 15 GREEN MapScreen tests (11 widget contract + 4 GPS lifecycle) using `tester.runAsync` for real dart:io archive open
  - 94 / 94 full test suite GREEN, 0 analyze warnings across lib/, test/, tool/
affects: [02-06-integration, perf-02-walk]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Vector-tile-renderer Theme imported with `as vtr` prefix to disambiguate from Material's Theme — `late final vtr.Theme _theme = ProtomapsThemes.lightV3()` built once in initState, NOT per build (RESEARCH §Anti-patterns)"
    - "Synchronous void dispose() with fire-and-forget Future-returning cleanup: `unawaited(_positionSubscription?.cancel() ?? Future.value())` + `unawaited(_tileProvider?.archive.close() ?? Future.value())` + `_mapController.dispose()` + `super.dispose()`. Awaiting inside an async-typed dispose is a silent leak (framework never awaits the result anyway), the synchronous shape is the only honest one"
    - "tester.runAsync wrapper for real dart:io futures: `tester.pump()` only advances frame callbacks + fake-async timers; `PmTilesArchive.from()` reads via `dart:io` which needs the real event loop. `tester.runAsync(() async { for...await Future.delayed; await tester.pump(); if(found) return; })` lets the real I/O complete and reflects the resulting setState in the element tree"
    - "Path-provider mock pattern reused: every test installs `_MockPathProviderPlatform` pointing all directory accessors at a single per-run temp dir, so vector_map_tiles' lazy `getTemporaryDirectory()` (cache resolver) doesn't crash on MissingPluginException"
    - "FlutterMap-dependency gating: widgets that read `mapController.camera` in initState (e.g. MapCompass) MUST NOT be mounted before FlutterMap has produced at least one frame, so MapScreen gates them on `_tileProvider != null` + the widgets themselves try/catch the camera-read as a defence-in-depth"

key-files:
  created: []
  modified:
    - lib/presentation/screens/map_screen.dart  # Phase 1 placeholder ColoredBox → full StatefulWidget with FlutterMap stack (~190 LOC)
    - lib/presentation/router.dart  # /map builder now constructs production MapScreenServices via FutureBuilder around getApplicationSupportDirectory + GeolocatorService.stream
    - lib/presentation/widgets/map_compass.dart  # initState try/catches camera read so the widget can mount on the same frame as FlutterMap (was a latent bug from Plan 02-04)
    - test/presentation/screens/map_screen_test.dart  # Wave 0 RED scaffold flipped GREEN — 11 tests pumping real bundled PMTiles via runAsync + path_provider mock
    - test/presentation/screens/map_screen_gps_test.dart  # Wave 0 RED scaffold flipped GREEN — 4 GPS lifecycle tests using runAsync + path_provider mock

key-decisions:
  - "Removed MapScreen.production factory (the plan called it `awkward; if the router builder constructs MapScreen.fromServices(...) directly with the live wiring, you can simply remove it`). Router /map builder constructs MapScreen.fromServices directly through a FutureBuilder around getApplicationSupportDirectory(). Single constructor — simplest shape. The test/DI constructor IS the only constructor."
  - "Theme prefix: `import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;` + `late final vtr.Theme _theme`. Picked the prefix path over relying on a re-export because (a) vector_map_tiles itself uses `import 'package:flutter/material.dart' hide Theme;` internally, signalling that the disambiguation is intended; (b) explicit prefix makes the type origin grep-able for future maintainers."
  - "Archive-close test seam was NOT added. The plan offered both options (custom test seam vs. relying on the real archive open). The real PMTiles archive opens fine in tests when given the bundled bytes via a temp file (1-time setUpAll cost); adding a seam would be cargo-cult complexity for what is conceptually a static factory. Source-level dispose pattern + the `dispose cancels the GPS subscription` test (which proves the dispose path is reached and runs to completion) are sufficient."
  - "dispose() is synchronous void per Flutter contract. The Future-returning cleanup calls (StreamSubscription.cancel, PmTilesArchive.close) are wrapped in `unawaited(... ?? Future<void>.value())`. The null-coalescing Future.value() is required because dart's `unawaited()` typedef is `void Function(Future<void>)` and the optional chain may return null."
  - "MapController.dispose() exists in flutter_map 7.0.2 (verified in src/map/controller/map_controller_impl.dart at line 776). Called LAST before super.dispose(), so the StreamSubscription + archive cleanup happen before the controller's internal ValueNotifier is disposed."
  - "Tests use `tester.runAsync` instead of `tester.pumpAndSettle`. pumpAndSettle would never return because the FpsCounterOverlay's 250 ms periodic Timer prevents settling. runAsync lets real I/O complete and we explicitly poll for FlutterMap's appearance with a 3-s budget."
  - "Bundled PMTiles asset (4.16 MB) is copied to a temp file in setUpAll once per test file run, then the temp file path is passed to MapScreenServices. `PmTilesArchive.from()` requires a real filesystem entry (dart:io); a synthetic in-memory bytes path won't work. The path-provider mock points every accessor at the same temp dir so vector_map_tiles' cache resolver doesn't crash."

patterns-established:
  - "Pattern: Wave-3 plans inherit Wave-2 widget bugs that only surface when the widgets compose in a real screen. The MapCompass camera-read crash was invisible at the unit-test level (Plan 02-04 used a fake controller that never threw) but immediately broke the screen-level test on first pump. Lesson: pump-the-real-tree integration tests catch this class of bug; all-fakes unit tests don't."
  - "Pattern: synchronous void dispose with explicit `unawaited(... ?? Future.value())` for any Future-returning cleanup, then `super.dispose()` last. Future POC subsystems with file handles / streams should follow this shape — the async-dispose alternative looks correct but silently fire-and-forgets the same Futures."
  - "Pattern: `tester.runAsync` is the right tool when a widget under test calls real `dart:io` (file open, socket connect, etc.) inside its initState. The pump-only approach works for `Future.value()` and `Future.delayed(Duration.zero)` microtasks but never advances real I/O."

requirements-completed: [MAP-02, MAP-03, MAP-04, MAP-05, MAP-06]

# Metrics
duration: 21min
completed: 2026-05-01
---

# Phase 2 Plan 5: MapScreen Wiring (MAP-02..06 + LOC-02 visibility) Summary

**MapScreen Phase-1 placeholder rewritten as a fully-wired FlutterMap stack: VectorTileLayer (ProtomapsThemes.lightV3, source key `protomaps`) + conditional CircleLayer with BlueDotMarker + RecenterFab + MapCompass + FpsCounterOverlay; synchronous void dispose with fire-and-forget cancel/close; production /map route builds services via FutureBuilder around getApplicationSupportDirectory; 94/94 tests GREEN.**

## Performance

- **Duration:** ~21 min
- **Started:** 2026-05-01T10:04:48Z
- **Completed:** 2026-05-01T10:25:48Z
- **Tasks:** 1 (`type="auto" tdd="true"` — Wave 0 RED tests already in place)
- **Files modified:** 5 (3 production + 2 test)

## Accomplishments

- **MapScreen** rewritten as `StatefulWidget` with `_MapScreenState` owning `MapController`, `Position? _lastFix`, `StreamSubscription<Position>?`, and `PmTilesVectorTileProvider?`. Initial loading state renders a dark `ColoredBox`; once `_loadTileProvider` resolves, the body switches to a `FlutterMap` with all four required children layers (vector tiles, conditional blue dot, FPS overlay, gated MapCompass).
- **Theme built once** via `late final vtr.Theme _theme = ProtomapsThemes.lightV3()` in initState — RESEARCH §Anti-patterns honoured. Material's `Theme` symbol disambiguated via `vector_tile_renderer as vtr` prefix.
- **MapOptions** populated with the exact Plan-prescribed values: initial center `(48.5397, 2.6553)` z=13, min/max zoom locked to `[10, 15]`, `CameraConstraint.contain` over the Melun bbox padded by `kPocPanBoundsPadDegrees` (0.02°) on each axis, `InteractionOptions(flags: InteractiveFlag.all)` with `enableMultiFingerGestureRace: false` (default).
- **Synchronous void dispose** — `_positionSubscription?.cancel()` + `_tileProvider?.archive.close()` + `_mapController.dispose()` + `super.dispose()`, all without `await`. Future-returning calls are `unawaited(... ?? Future<void>.value())` to satisfy strict typing without changing the synchronous shape.
- **Router /map builder** wraps `MapScreen.fromServices` in a `FutureBuilder<String>` around `getApplicationSupportDirectory()` so the absolute PMTiles path is resolved without making the route builder async. Loading frame is a `CircularProgressIndicator` (resolves <1 ms in practice; user perceives no flash). Failure path shows a `'Map data unavailable'` text fallback (the gate-screen pre-navigation copy + /error routing means this is unreachable in practice).
- **MapCompass.initState hardened** — wraps the `widget.mapController.camera.rotation` read in a try/catch so the widget can mount on the same frame as FlutterMap. Plan 02-04's tests didn't catch this because the test fake never threw; the screen-level test caught it on first pump.
- **Tests use `tester.runAsync`** to let real `dart:io` futures complete (PmTilesArchive.from reads a real file). The bundled `assets/maps/Fra_Melun.pmtile` (4.16 MB) is copied to a system temp file in `setUpAll`, the path is passed to `MapScreenServices`, and a `_MockPathProviderPlatform` covers vector_map_tiles' lazy cache-dir lookup.
- **Test contract pinned**: 11 widget tests in `map_screen_test.dart` (VectorTileLayer source key, MapOptions values, blue-dot conditional render, FAB disabled state, compass position at top:56 right:8, synchronous dispose) + 4 GPS lifecycle tests in `map_screen_gps_test.dart` (initState subscribes once, dispose cancels, fix triggers setState, post-dispose emit doesn't throw). All GREEN.

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire MapScreen FlutterMap stack — MAP-02..06 + LOC-02 visibility** — `3e09f24` (feat)
   - Note: Wave 0 RED tests were already committed (a5bf323 from Plan 02-01); this single GREEN commit covers (a) MapScreen rewrite, (b) router rewiring, (c) MapCompass camera-read hardening, (d) test scaffold flip from RED to GREEN. The TDD audit trail is preserved logically: Wave 0 had RED, this commit has GREEN.

**Plan metadata commit:** _to follow this SUMMARY_

## Files Created/Modified

### Modified (5)

- `lib/presentation/screens/map_screen.dart` — Phase 1 placeholder ColoredBox replaced with full StatefulWidget. ~190 LOC. Owns `MapController _mapController`, `late final vtr.Theme _theme`, `Position? _lastFix`, `StreamSubscription<Position>? _positionSubscription`, `PmTilesVectorTileProvider? _tileProvider`. Single constructor `MapScreen.fromServices(this.services, {super.key})` — production wiring goes through the router builder.
- `lib/presentation/router.dart` — `/map` route builder upgraded from `const MapScreen()` to a `FutureBuilder<String>` wrapping `MapScreen.fromServices(MapScreenServices(pmtilesPath: ..., positionStreamFactory: GeolocatorService.stream))`. Path resolved via private `_resolvePmtilesPath()` calling `getApplicationSupportDirectory() + p.join(kPmtilesMapsSubdir, kPmtilesBasename)`.
- `lib/presentation/widgets/map_compass.dart` — `initState` now wraps the `widget.mapController.camera.rotation` read in `try { ... } on Object { _bearingDegrees = 0; }`. Defence-in-depth — the next MapEventRotate immediately overwrites the seed via setState. (Rule 1 fix; documented in Deviations §1.)
- `test/presentation/screens/map_screen_test.dart` — Wave 0 RED scaffold replaced with 11 GREEN tests. Uses `tester.runAsync` + `_MockPathProviderPlatform` + bundled-PMTiles-temp-file pattern. New tests vs Wave 0: explicit CameraConstraint bounds assertion (south/north/west/east envelope), compass-position-under-FPS-overlay assertion, synchronous-dispose contract test.
- `test/presentation/screens/map_screen_gps_test.dart` — Wave 0 RED scaffold replaced with 4 GREEN tests using the same runAsync + path-provider-mock + PMTiles-temp-file pattern.

## Decisions Made

- **Dropped `MapScreen.production` factory** — the plan called it `awkward` and offered the option to remove it if the router builder constructs `MapScreen.fromServices` directly. Done. Single constructor surface; tests and production share the same entrypoint.
- **`vector_tile_renderer as vtr` prefix** — vector_map_tiles itself uses `import 'package:flutter/material.dart' hide Theme;` to disambiguate, signalling that the Theme/Theme collision is real and the recommended fix is a prefix. Applied symmetrically here. Material's Theme isn't referenced in `map_screen.dart`, but a future maintainer adding `Theme.of(context)` won't have to chase a confusing error.
- **Archive-close test seam was not added** — the plan offered the option to defer this assertion. The real PMTiles archive opens reliably from a temp file in tests (one-time setUpAll cost), and the dispose-cancels-GPS-subscription test already proves the dispose path runs to completion. Adding a seam wrapping `PmTilesVectorTileProvider.fromSource` would be cargo-cult complexity for a one-line static factory call.
- **`tester.runAsync` instead of `pumpAndSettle`** — the FpsCounterOverlay's 250 ms periodic Timer would prevent pumpAndSettle from ever returning. runAsync lets the real `dart:io` event loop run for the PMTiles open while we explicitly poll for FlutterMap's appearance with a 3-s budget. Test wall-clock cost ~50–250 ms per test for the I/O wait; full file runs in 4 s for 11 tests.
- **MapCompass try/catch around camera read** — minimal defence-in-depth. Plan 02-04's MapCompass crashed on first pump in MapScreen because the real MapController throws "FlutterMap widget rendered at least once" until FlutterMap has produced its first frame. Two complementary fixes landed: (a) MapScreen gates the MapCompass widget on `_tileProvider != null` so it only enters the tree when FlutterMap is also entering it; (b) MapCompass.initState try/catches the camera read and falls back to bearing 0 if the read throws. The next `MapEventRotate` overwrites the seed within milliseconds.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MapCompass.initState crashes when mounted on the same frame as FlutterMap**
- **Found during:** Task 1 (first run of `flutter test test/presentation/screens/map_screen_test.dart`)
- **Issue:** `MapCompass.initState` reads `widget.mapController.camera.rotation` to seed `_bearingDegrees`. The real `MapControllerImpl.camera` getter throws `Exception('You need to have the FlutterMap widget rendered at least once before using the MapController.')` if invoked before FlutterMap has produced its first frame. In MapScreen, the MapCompass enters the tree on the same setState call that puts FlutterMap into the tree — at that point FlutterMap hasn't rendered yet, so the camera-read throws and the whole frame fails. Plan 02-04's MapCompass tests didn't catch this because they used a fake `_RecordingMapController` that returned a synthetic camera regardless.
- **Fix:** Two complementary changes:
  - `lib/presentation/widgets/map_compass.dart` — wrap the camera read in `try { _bearingDegrees = widget.mapController.camera.rotation; } on Object { _bearingDegrees = 0; }`. The next MapEventRotate (which arrives within milliseconds once FlutterMap has rendered + the user rotates) overwrites this fallback via `setState`.
  - `lib/presentation/screens/map_screen.dart` — gate the MapCompass `Positioned(...)` on `if (_tileProvider != null)` so the widget only enters the tree when FlutterMap is also entering it. Defence-in-depth — if a future regression removes the try/catch, this gating still prevents the crash on the loading frame.
- **Files modified:** `lib/presentation/widgets/map_compass.dart`, `lib/presentation/screens/map_screen.dart`
- **Verification:** All 12 existing map_compass_test cases still GREEN. New screen-level test `compass widget rendered top-right under FPS overlay` confirms the compass appears post-load. Pre-fix: every MapScreen test failed with "FlutterMap never appeared in the tree". Post-fix: 11 / 11 MapScreen tests GREEN.
- **Committed in:** `3e09f24` (Task 1 commit — bundled because the MapCompass fix is causally required by the screen wiring).

**2. [Rule 3 - Blocking] tester.pump() doesn't advance real dart:io futures**
- **Found during:** Task 1 (initial test run after MapCompass fix — tests still failed with "FlutterMap never appeared in the tree" but no exception)
- **Issue:** `_loadTileProvider` calls `await PmTilesVectorTileProvider.fromSource(path)`, which internally calls `PmTilesArchive.from(path)` → `File(path).open()` (a real `dart:io` random-access read). `tester.pump()` only advances Flutter's frame scheduler + fake-async timers; it does NOT pump the real event loop, so the file-open Future never resolves. The test loop ran 30 × 50 ms pumps = 1.5 s wall clock without ever letting the I/O complete.
- **Fix:** Replaced the pump-only loop with a `tester.runAsync(() async { ... })` wrapper that uses real `Future.delayed` + nested `tester.pump()` calls. Inside `runAsync` the test framework allows the real event loop to advance, so `dart:io` futures complete normally; the resulting `setState` is reflected by the nested pumps. Budget: 60 × 50 ms = 3 s, generous for a 4 MB archive open on local SSD.
- **Files modified:** `test/presentation/screens/map_screen_test.dart`, `test/presentation/screens/map_screen_gps_test.dart`
- **Verification:** Pre-fix: 0 / 11 MapScreen tests passed (all timed out at "FlutterMap never appeared"). Post-fix: 11 / 11 tests GREEN, file runs in ~4 s.
- **Committed in:** `3e09f24` (Task 1 commit — the test-mechanism fix is part of flipping the Wave 0 RED scaffold to GREEN).

---

**Total deviations:** 2 auto-fixed (1 Rule 1 bug + 1 Rule 3 blocking).
**Impact on plan:** Both auto-fixes were necessary for the plan's success criterion (`flutter test` GREEN). Deviation 1 fixed a latent bug from Plan 02-04 that surfaced only when the widgets composed in a real screen tree — the kind of bug that only screen-level tests catch. Deviation 2 fixed a test-mechanism issue: the plan's test design used `tester.pump()` but the production code uses real `dart:io`, which `pump()` doesn't advance; `runAsync` is the standard tool for this scenario. No scope creep — every change was either bug fix or test-scaffolding adjustment to make the plan's prescribed assertions runnable.

## Issues Encountered

- **`tester.pump()` vs real I/O futures**: documented above as Deviation 2. Lesson for future widget tests: any production code that calls `dart:io`, `http`, or platform-channel methods inside a Future awaited during a State.initState body needs `tester.runAsync` in the test, not just `pump()`. `pump()` alone advances frame callbacks but not real-event-loop futures. (Phase 1 tests didn't hit this because they mocked everything at the platform interface; Phase 2's MapScreen is the first widget that opens a real file.)
- **Pump-and-settle deadlock with FpsCounterOverlay**: noted in key-decisions. The 250 ms periodic Timer in `FpsCounterOverlay` would prevent `tester.pumpAndSettle()` from ever returning. Tests use a bounded poll loop instead — same pattern Phase 1's `fps_counter_overlay_test.dart` already established.

## User Setup Required

None — no external service configuration required. PMTiles asset bundled in `pubspec.yaml`'s `flutter.assets:`; `getApplicationSupportDirectory()` is provided by `path_provider 2.1.5`.

## Next Phase Readiness

- **MAP-02..06 + LOC-02 visibility GREEN** at HEAD: `flutter test` 94/94 GREEN. `flutter analyze lib/ test/ tool/` 0 issues. `dart test tool/test/` (LOC-03 + license + deps + boot gates) GREEN.
- **Phase 2 Plan 06 (final integration + walk validation)** unblocked. Plan 06 will exercise the route end-to-end (`/` → `/map` after a pre-granted permission session) and run the on-device walk validation (PERF-02 ≥ 40 fps no-fog target on iPhone 17 Pro at z13–15). The MapScreen surface is now feature-complete; PERF-02 is the next gate.
- **MapScreen lifecycle leak-safe**: dispose path is single-frame synchronous, fire-and-forget for Futures. Pitfalls 2 + 5 honoured.
- **No new pubspec.yaml dependencies** — `pubspec.yaml` unchanged from Plan 01-02 baseline.
- **Open follow-ups** (deferred):
  - Archive-close test seam not implemented (intentional — see Decisions Made). If a future leak audit requires per-test verification of `archive.close()` invocation, add a `@visibleForTesting static Future<PmTilesVectorTileProvider> Function(String)? testTileProviderFromSourceOverride` static field on MapScreen and pump a fake provider that records its `close` calls.
  - Theme-built-once test was deferred (the `late final` keyword is the contract; runtime assertion would require exposing `_theme` via `@visibleForTesting`). Acceptable — the contract is enforced at the source level.

## Self-Check: PASSED

- All 5 plan-scope files present on disk: `lib/presentation/screens/map_screen.dart`, `lib/presentation/router.dart`, `lib/presentation/widgets/map_compass.dart`, `test/presentation/screens/map_screen_test.dart`, `test/presentation/screens/map_screen_gps_test.dart`.
- SUMMARY.md created at `.planning/phases/02-map-no-fog/02-05-SUMMARY.md`.
- Task commit `3e09f24` reachable from `git log --oneline --all`.
- Full `flutter test` 94/94 GREEN.
- `flutter analyze lib/ test/ tool/` 0 issues.

---
*Phase: 02-map-no-fog*
*Plan: 05 (MAP-02..06 + LOC-02 visibility)*
*Completed: 2026-05-01*
