---
phase: 02-map-no-fog
verified: 2026-05-01T14:00:00Z
status: passed
score: 12/12 must-haves verified
re_verification: false
---

# Phase 2: Map (No Fog) Verification Report

**Phase Goal:** Land a working FlutterMap + VectorTileLayer screen rendering the bundled `Fra_Melun.pmtile` archive at zoom 13–15 on Melun, with GPS blue-dot tracking, recenter FAB, compass widget, and a sideload-verified PERF-02 >= 40 fps gate on iPhone 17 Pro — the gate that decides whether Phase 3 fog work is even testable.

**Verified:** 2026-05-01T14:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `Fra_Melun.pmtile` copied from `rootBundle` to `<appSupport>/maps/` exactly once on first launch; subsequent launches skip silently | VERIFIED | `PmtilesAssetCopier.ensureCopied()` in `pmtiles_asset_copier.dart` — size-parity idempotency logic present; `PmtilesAssetCopier_test.dart` covers first-launch, second-launch, size-mismatch, and failure paths |
| 2 | MapScreen renders PMTiles via `FlutterMap` + `VectorTileLayer` + `ProtomapsThemes.lightV3()`, centred on Melun (48.5397, 2.6553) at zoom 13 | VERIFIED | `map_screen.dart` ll.146–175 — `FlutterMap` with `initialCenter: LatLng(kPocInitialCameraLat, kPocInitialCameraLon)`, `initialZoom: kPocInitialZoom`; `VectorTileLayer` with `kPocTileProviderSourceKey: _tileProvider!`; `_theme = ProtomapsThemes.lightV3()` built once in `initState` |
| 3 | Pan, pinch-zoom, and combined pan+zoom gestures all enabled (MAP-04, MAP-05, MAP-06) | VERIFIED | `MapOptions.interactionOptions: const InteractionOptions(flags: InteractiveFlag.all)` at `map_screen.dart:159` — `enableMultiFingerGestureRace` left at default (false) per RESEARCH §Pitfall |
| 4 | Blue dot (radius 7 px, fill #2B7CD6, white stroke 2 px) tracks GPS fixes | VERIFIED | `BlueDotMarker.build()` in `blue_dot_marker.dart` — `kPocBlueDotRadiusPx=7`, `kPocBlueDotFillArgb=0xFF2B7CD6`, `borderStrokeWidth=kPocBlueDotStrokePx`, `borderColor=Colors.white`, `useRadiusInMeter=false`; rendered in `map_screen.dart:174` only when `_lastFix != null` |
| 5 | `_lastFix` cached from live GPS stream; `getLastKnownPosition` never called (LOC-03) | VERIFIED | `GeolocatorService.stream()` calls `Geolocator.getPositionStream(locationSettings: _settings)` — no `getLastKnownPosition` in executable code anywhere under `lib/`; LOC-03 static-source gate GREEN (comment-strip-aware); CI `dart test tool/test/` auto-discovers the gate |
| 6 | Recenter FAB animates camera to `_lastFix` at zoom 15 over 500 ms; disabled when `_lastFix == null` | VERIFIED | `recenter_fab.dart` — `AnimationController` with `kPocRecenterAnimationMs=500`, `Curves.easeInOut`, per-frame `mapController.move`; `onPressed: widget.lastFix == null ? null : _onPressed` (LOC-05); wired in `map_screen.dart:140` as `Scaffold.floatingActionButton` |
| 7 | MapCompass always visible top-right; tap snaps to north via shortest-path 250 ms tween; glyph tracks live bearing | VERIFIED | `map_compass.dart` — `mapEventStream` subscription on `MapEventRotate`; `mapCompassShortestPathToNorth()` top-level function; `AnimationController` with `kPocCompassAnimationMs=250`; `mapController.rotate` per frame; gated on `_tileProvider != null` in `map_screen.dart:184` (prevents camera read before FlutterMap first frame) |
| 8 | GPS subscription opened in `initState`, cancelled in `dispose`; mounted guard on stream listener | VERIFIED | `map_screen.dart:92–98` — `_subscribeToPositions()` in `initState`; `if (!mounted) return` inside listener; `unawaited(_positionSubscription?.cancel())` in `dispose` |
| 9 | `PmTilesVectorTileProvider.fromSource` opened after first frame in `initState`; `archive.close()` called in `dispose` | VERIFIED | `map_screen.dart:89` — `unawaited(_loadTileProvider())` in `initState`; `_tileProvider?.archive.close()` at `map_screen.dart:130`; mounted-guard protects the setState path; orphaned archive closed immediately if screen unmounts during load (l.107) |
| 10 | `dispose()` synchronous void; no async disposal | VERIFIED | `map_screen.dart:120–133` — method signature `void dispose()`; cleanup via `unawaited(... ?? Future<void>.value())` pattern; confirmed by test `'dispose returns void synchronously'` passing GREEN |
| 11 | PERF-02: sustained >= 40 fps on iPhone 17 Pro during pan/pinch/combined gestures at zoom 13–15 | VERIFIED | `02-UAT.md` — verdict `approved`; device iPhone 17 Pro (ProMotion 120 Hz); developer verbatim: *"everything works well, 120 fps when doing stuff, revert to 4 when not doing anything"*; CI run `25212559648`, SHA `46b8fcc`; walked 2026-05-01 |
| 12 | `flutter analyze lib/ test/ tool/test/` clean; `flutter test` 94/94 GREEN | VERIFIED | Confirmed locally during verification: `No issues found! (ran in 2.4s)` and `+94: All tests passed!` |

**Score:** 12/12 truths verified

---

## Required Artifacts

| Artifact | Provides | Status | Evidence |
|----------|----------|--------|----------|
| `lib/config/constants.dart` | Phase 2 constants block (kPocInitialCameraLat, kPocBlueDotFillArgb, kPocGpsDistanceFilterMeters, kPmtilesAssetPath, etc.) | VERIFIED | All 19 constants present; confirmed by grep |
| `lib/domain/map/map_screen_services.dart` | Immutable `MapScreenServices` DTO (pmtilesPath, positionStreamFactory, logger) | VERIFIED | File exists, `@immutable` class, GOSL header, 3 fields with docstrings |
| `lib/infrastructure/pmtiles/pmtiles_asset_copier.dart` | `PmtilesAssetCopier.ensureCopied()` — idempotent `rootBundle` → `getApplicationSupportDirectory()` copy | VERIFIED | File is fully implemented (not stub); `rootBundle.load`, `getApplicationSupportDirectory`, size-parity idempotency, `@visibleForTesting` test seam, structured logging at INFO/SEVERE |
| `lib/infrastructure/location/geolocator_service.dart` | `GeolocatorService.stream()` with pinned `LocationAccuracy.best`, `distanceFilter: 5` | VERIFIED | `Geolocator.getPositionStream(locationSettings: _settings)` present; logs at INFO under `domain.location` |
| `lib/presentation/widgets/blue_dot_marker.dart` | `BlueDotMarker.build(LatLng)` — LOC-02 spec (7 px, #2B7CD6, white stroke) | VERIFIED | All LOC-02 spec values from constants; `useRadiusInMeter: false` |
| `lib/presentation/widgets/recenter_fab.dart` | `RecenterFab` StatefulWidget with LOC-04 tween + LOC-05 disabled state | VERIFIED | `AnimationController`, `Curves.easeInOut`, 500 ms, `mapController.move` per frame; `onPressed: null` when `lastFix == null`; min_lines=50 satisfied (~83 LOC) |
| `lib/presentation/widgets/map_compass.dart` | `MapCompass` StatefulWidget with bearing-stream sync + shortest-path snap-to-north tween | VERIFIED | `mapEventStream` subscription, `MapEventRotate`, `mapCompassShortestPathToNorth()` top-level, 250 ms tween; min_lines=70 satisfied (~113 LOC) |
| `lib/presentation/screens/map_screen.dart` | Full `MapScreen` rewrite — FlutterMap + VectorTileLayer + blue dot + compass + FAB + FPS overlay | VERIFIED | Fully wired StatefulWidget; all sub-widgets composed; lifecycle correct; min_lines=100 satisfied (~195 LOC) |
| `lib/presentation/screens/error_screen.dart` | ErrorScreen for `/error` route — displays detail string from `FileSystemException` | VERIFIED | Exists with GOSL header, l10n keys, full implementation |
| `lib/presentation/router.dart` | 4-route GoRouter (/, /map, /denied, /error); `/map` wires production `MapScreenServices` | VERIFIED | All 4 routes present; `_buildMapRoute` FutureBuilder resolves path + binds `GeolocatorService.stream`; `/error` builder narrows `extra` to `String` |
| `tool/test/check_no_last_known_position_test.dart` | LOC-03 static-source CI gate — strips comments before checking | VERIFIED | File exists; comment-aware `_stripDartComments()` implemented; GREEN locally; auto-discovered by CI `dart test tool/test/` directory glob |
| `assets/maps/Fra_Melun.pmtile` | Bundled PMTiles archive (4.16 MB) | VERIFIED | `Fra_Melun.pmtile` present at path; 4,176,302 bytes |

---

## Key Link Verification

| From | To | Via | Status | Evidence |
|------|----|-----|--------|----------|
| `permission_gate_screen.dart` | `pmtiles_asset_copier.dart` | `await PmtilesAssetCopier.ensureCopied()` in `_ensureMapDataAndNavigate()` | WIRED | Called on both the in-app CTA path (`_onCtaPressed`) and the lifecycle resume path (`_checkAndMaybeNavigate`) — both converge on `_ensureMapDataAndNavigate()` at l.101 |
| `permission_gate_screen.dart` | `error_screen.dart` | `context.go('/error', extra: e.message)` in `FileSystemException` catch | WIRED | l.107 — single catch block routes to `/error` with exception message as `extra` |
| `map_screen.dart` | `geolocator_service.dart` | `services.positionStreamFactory()` in `_subscribeToPositions()` (called from `initState`) | WIRED | `positionStreamFactory` assigned in router as `GeolocatorService.stream`; called at `map_screen.dart:93`; subscription cancelled in dispose |
| `map_screen.dart` | `PmTilesVectorTileProvider.fromSource` | `_loadTileProvider()` called via `unawaited()` in `initState` | WIRED | `map_screen.dart:89` + `map_screen.dart:102`; `archive.close()` in `dispose` |
| `map_screen.dart` | `ProtomapsThemes.lightV3()` | `late final _theme = ProtomapsThemes.lightV3()` in `initState` | WIRED | Built once (`late final`), passed to `VectorTileLayer.theme` at l.169 |
| `router.dart` | `MapScreenServices` (production wiring) | `MapScreen.fromServices(MapScreenServices(pmtilesPath: pathOrNull, positionStreamFactory: GeolocatorService.stream))` | WIRED | `router.dart:72`; `_resolvePmtilesPath()` resolves path via `getApplicationSupportDirectory()`; `GeolocatorService.stream` function reference passed as factory |
| LOC-03 gate | `lib/**/*.dart` | `dart test tool/test/` directory glob in `.github/workflows/ci.yml:48` | WIRED | `grep` confirms `dart test tool/test/` at line 48 of CI YAML; gate auto-discovered; comment stripping prevents false positives from docstrings |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MAP-01 | 02-02 | `Fra_Melun.pmtile` copied from `rootBundle` to app support dir exactly once | SATISFIED | `PmtilesAssetCopier.ensureCopied()` fully implemented; size-parity idempotency; gate-screen hook on both grant paths; 4 unit tests GREEN |
| MAP-02 | 02-05 | Map renders PMTiles via `flutter_map 7.0.2` + `vector_map_tiles 8.0.0` + `vector_map_tiles_pmtiles 1.5.0` with default renderer style | SATISFIED | `VectorTileLayer` wired in `map_screen.dart`; `ProtomapsThemes.lightV3()` renderer style; source key `protomaps` per Pitfall 3 |
| MAP-03 | 02-05 | Initial camera centred on Melun (lat 48.5397, lon 2.6553, zoom 13) | SATISFIED | `MapOptions.initialCenter: LatLng(kPocInitialCameraLat, kPocInitialCameraLon)`, `initialZoom: kPocInitialZoom`; constants confirmed `48.5397`, `2.6553`, `13` |
| MAP-04 | 02-05 | User can pan with one-finger drag | SATISFIED | `InteractionOptions(flags: InteractiveFlag.all)` — includes `InteractiveFlag.drag`; verified in test `'InteractionOptions all flags'` |
| MAP-05 | 02-05 | User can zoom with pinch gesture | SATISFIED | `InteractiveFlag.all` includes `InteractiveFlag.pinchZoom`; verified in test `'pinch zoom flag set'` |
| MAP-06 | 02-05 | User can perform combined pan+zoom simultaneously | SATISFIED | `enableMultiFingerGestureRace: false` (default) per CONTEXT; `InteractiveFlag.all` enables both; verified in test `'combined gestures race disabled (default)'`; sideload UAT confirmed ~120 fps during combined gestures |
| LOC-01 | 02-03 | App subscribes to `Geolocator.getPositionStream` with `LocationAccuracy.best`, `distanceFilter: 5 m` | SATISFIED | `GeolocatorService.stream()` — `const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: kPocGpsDistanceFilterMeters)` where `kPocGpsDistanceFilterMeters = 5`; logs subscription at INFO under `domain.location` |
| LOC-02 | 02-03 | Blue dot — radius 7 px, fill `#2b7cd6`, white stroke 2 px at GPS fix | SATISFIED | `BlueDotMarker.build()` — `kPocBlueDotRadiusPx=7`, `Color(0xFF2B7CD6)`, `borderStrokeWidth=2.0`, `borderColor=Colors.white`, `useRadiusInMeter=false`; 5 unit tests GREEN |
| LOC-03 | 02-03 | No source in `lib/` calls `Geolocator.getLastKnownPosition` | SATISFIED | Static-source CI gate at `tool/test/check_no_last_known_position_test.dart` GREEN; comment-strip-aware so docstring mentions don't trigger; auto-discovered by `dart test tool/test/` glob |
| LOC-04 | 02-04 | Recenter FAB animates camera to `_lastFix` at zoom 15 over ~500 ms | SATISFIED | `RecenterFab._onPressed()` — `AnimationController(duration: Duration(milliseconds: kPocRecenterAnimationMs))`, `Curves.easeInOut`, per-frame `mapController.move`; wired to `Scaffold.floatingActionButton`; repeat-tap cancels in-flight controller |
| LOC-05 | 02-04 | Recenter FAB disabled when `_lastFix == null` | SATISFIED | `onPressed: widget.lastFix == null ? null : _onPressed` — Material auto-greys on `null` onPressed; test `'LOC-05: recenter FAB is disabled when no fix has arrived'` GREEN |
| PERF-02 | 02-06 | Pan-FPS without fog >= 40 on iPhone 17 Pro | SATISFIED | Sideload UAT on iPhone 17 Pro (ProMotion 120 Hz) against CI run `25212559648` (SHA `46b8fcc`); sustained ~120 fps observed (3x headroom); developer verbatim: *"everything works well, 120 fps when doing stuff, revert to 4 when not doing anything"*; `02-UAT.md` verdict: `approved`; idle ~4 fps documented as expected Flutter no-dirty-frames behaviour |

All 12 Phase 2 requirement IDs confirmed Complete in `REQUIREMENTS.md` traceability table.

---

## Anti-Patterns Found

| File | Pattern | Severity | Notes |
|------|---------|----------|-------|
| None detected | — | — | No TODO/FIXME/placeholder/return-null/stub anti-patterns found in Phase 2 production files |

Phase 2 stubs (Wave 0 plan 02-01) were all replaced by Wave 2 implementations. No residual stubs present in production code.

---

## Human Verification Required

PERF-02 was verified via a physical sideload UAT walk and is the only item in this phase that required human observation. It was completed on 2026-05-01 by the developer on iPhone 17 Pro against CI run `25212559648`. The verbal `approved` verdict is documented in `02-UAT.md` with the verbatim developer quote. No further human verification items are outstanding for Phase 2.

---

## Notable Cross-Plan Item

Commit `46b8fcc fix(02-05): swallow vector_map_tiles CancellationException in test teardown` is a test-scaffolding-only fix (helper `test/_helpers/swallow_vector_map_tiles_cancellation.dart` + two test-file additions). No production code was changed. The fix resolved a Linux CI flake where the `vector_map_tiles` renderer's legitimate `CancellationException` during test teardown was being attributed to the just-completed test by the runner. This is not a Phase 2 production-code gap.

---

## Summary

All 12 Phase 2 requirements (MAP-01..06, LOC-01..05, PERF-02) are verified as substantively implemented and correctly wired in the production codebase:

- `PmtilesAssetCopier.ensureCopied()` is fully implemented (not a stub) and hooked into both grant paths of `PermissionGateScreen`.
- `MapScreen` is a complete `StatefulWidget` with proper FlutterMap wiring, lifecycle management (PMTiles archive open/close, GPS subscribe/cancel), and all required sub-widgets composed.
- `BlueDotMarker`, `RecenterFab`, and `MapCompass` are all fully implemented (not stubs) with correct LOC-01..05 specs.
- The LOC-03 static-source gate is wired into CI and passing.
- `flutter analyze lib/ test/ tool/test/` exits clean (0 issues).
- `flutter test` passes 94/94.
- The PERF-02 sideload UAT was completed on 2026-05-01 with a verbal `approved` from the developer — sustained ~120 fps observed (3× the >= 40 fps gate), unblocking Phase 3.

**Phase 3 (Fog of War — THE HYPOTHESIS) is unblocked.**

---

_Verified: 2026-05-01T14:00:00Z_
_Verifier: Claude (gsd-verifier)_
