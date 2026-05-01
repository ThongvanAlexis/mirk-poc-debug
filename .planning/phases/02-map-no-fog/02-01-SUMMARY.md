---
phase: 02-map-no-fog
plan: 01
subsystem: testing
tags: [phase-2-wave-0, scaffold, red-tests, dto, l10n, error-screen, pmtiles, geolocator, flutter_map, vector_map_tiles]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: GoRouter, PermissionGateScreen, PermissionDeniedScreen, FpsCounterOverlay, buildPocAppBar, MapScreen placeholder, FileLogger, l10n bootstrap, GOSL header check, lib/config/constants.dart
provides:
  - Phase 2 constants block (camera bounds, zoom envelope, pan bbox, animation timing, GPS distance filter, PMTiles paths, blue-dot spec)
  - 5 new l10n keys (recenterTooltip, compassTooltip, errorScreenTitle/Body/DetailLabel) in en + fr
  - MapScreenServices immutable DTO (lib/domain/map/map_screen_services.dart)
  - ErrorScreen + /error GoRoute
  - 5 production stubs (PmtilesAssetCopier, GeolocatorService, BlueDotMarker, RecenterFab, MapCompass)
  - MapScreen.fromServices(...) named constructor (Wave 0 stub — Plan 02-05 wires the body)
  - 9 RED Phase 2 test files compiling against the stubs
  - LOC-03 static-source CI gate (auto-discovered by existing dart test tool/test/ glob)
affects: [02-02-MAP-01-pmtiles-copy, 02-03-LOC-01-LOC-02-gps-blue-dot, 02-04-LOC-04-LOC-05-recenter-compass, 02-05-MAP-02-06-map-screen-wiring, 02-06-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wave 0 scaffold pattern: every test imports the production stubs so impl plans flip RED → GREEN per requirement, never having to invent new types or add new dependencies"
    - "Constructor-injected services DTO (MapScreenServices) — value object with three fields (path, factory closure, optional logger). Lets MapScreen accept one positional arg instead of three; lets tests pump MapScreen.fromServices(fakeServices) without globals"
    - "@visibleForTesting deferred to Plan 02-02 — pmtiles failure test asserts the contract today and fails RED; impl plan adds the testOverride seam alongside the real ensureCopied implementation"
    - "Test-fake MapController via implements MapController + record-list — uses the structural record type ({bool moveSuccess, bool rotateSuccess}) directly because MoveAndRotateResult is a non-exported typedef in flutter_map 7.0.2"
    - "LOC-03 static-source CI gate — mirrors tool/test/check_headers_test.dart pattern; scans lib/**/*.dart for forbidden API references; auto-discovered by the existing dart test tool/test/ workflow step (no YAML edit needed)"

key-files:
  created:
    - lib/domain/map/map_screen_services.dart
    - lib/presentation/screens/error_screen.dart
    - lib/infrastructure/pmtiles/pmtiles_asset_copier.dart
    - lib/infrastructure/location/geolocator_service.dart
    - lib/presentation/widgets/blue_dot_marker.dart
    - lib/presentation/widgets/recenter_fab.dart
    - lib/presentation/widgets/map_compass.dart
    - test/infrastructure/pmtiles/pmtiles_asset_copier_test.dart
    - test/infrastructure/location/geolocator_service_test.dart
    - test/presentation/screens/map_screen_test.dart
    - test/presentation/screens/map_screen_gps_test.dart
    - test/presentation/screens/permission_gate_screen_pmtiles_failure_test.dart
    - test/presentation/widgets/recenter_fab_test.dart
    - test/presentation/widgets/map_compass_test.dart
    - test/presentation/widgets/blue_dot_marker_test.dart
    - tool/test/check_no_last_known_position_test.dart
  modified:
    - lib/config/constants.dart (Phase 2 constants block appended — 19 new constants)
    - lib/l10n/app_en.arb (5 new keys)
    - lib/l10n/app_fr.arb (5 new keys + descriptions)
    - lib/presentation/router.dart (/error GoRoute added)
    - lib/presentation/screens/map_screen.dart (MapScreen.fromServices named constructor stub — Rule 3 blocking fix)

key-decisions:
  - "MapScreen.fromServices(...) named constructor stub added in Wave 0 (Rule 3 — Blocking) so Phase 2 widget tests compile. Body still renders the Phase 1 placeholder ColoredBox; Plan 02-05 swaps in FlutterMap. Default const MapScreen() preserved for the router."
  - "ErrorScreen renders detail verbatim (no retry button) per CONTEXT.md §PMTiles copy lifecycle 'failure recovery'; layout mirrors PermissionDeniedScreen so failure-state screens stay visually consistent."
  - "@visibleForTesting test-override seam on PmtilesAssetCopier deferred to Plan 02-02 (per plan body). The Wave 0 permission-gate failure test asserts the contract end-state and fails RED today; impl plan adds the seam alongside the real implementation rather than introducing a Wave 0 test-only API surface."
  - "MapScreen.fromServices test pmtilesPath is '/dev/null/poc-wave0-placeholder.pmtile' rather than a real synthetic temp file — Wave 0 widget tests assert structural properties (FlutterMap exists, options.initialCenter etc.) which fail fast at find.byType. Real synthetic PMTiles bytes land in Plan 02-05's GREEN tests where the screen actually parses the archive."
  - "Test-fake MapController declares ({bool moveSuccess, bool rotateSuccess}) directly instead of importing MoveAndRotateResult, because that typedef lives at lib/src/misc/move_and_rotate_result.dart and isn't re-exported by package:flutter_map/flutter_map.dart. Spelling the structural record satisfies the abstract MapController interface without depending on a private import path."

patterns-established:
  - "Wave 0 / Wave 1 split for multi-requirement phases: Wave 0 lands all test files + production-stub class shapes + DTOs + l10n + constants; subsequent waves fill in the production logic per requirement and flip individual RED tests to GREEN"
  - "Static-source CI gates for forbidden APIs: cheap (one File scan), auto-discovered by 'dart test tool/test/', and surface intent-violations as build failures rather than runtime bugs"

requirements-completed: []  # Per the plan, Wave 0 lands the scaffold but does NOT implement any of MAP-01..06 / LOC-01..05; impl plans 02-02..02-06 mark requirements complete as their tests flip GREEN.

# Metrics
duration: 59 min
completed: 2026-05-01
---

# Phase 02 Plan 01: Wave 0 Map Scaffold Summary

**Phase 2 Wave 0 scaffold — 16 new files (7 production + 9 test) plus 5 file edits land every Phase 2 contract (DTO, l10n, /error route, error screen, 5 production stubs, 9 RED tests, LOC-03 static-source gate) so impl plans 02-02..02-06 can flip individual requirements RED → GREEN without reinventing types.**

## Performance

- **Duration:** 59 min
- **Started:** 2026-05-01T08:42:59Z
- **Completed:** 2026-05-01T09:42:17Z
- **Tasks:** 3 (all `type="auto"`)
- **Files created:** 16
- **Files modified:** 5
- **Phase 2 RED tests authored:** 9 files / ~33 test cases

## Accomplishments

- Phase 2 constants block (19 named constants) appended to `lib/config/constants.dart` covering camera/zoom/pan envelope, animation timing, GPS distance filter, PMTiles paths, and blue-dot spec — every magic number Phase 2 needs is a named constant per CLAUDE.md mandate.
- 5 new l10n keys (`recenterTooltip`, `compassTooltip`, `errorScreenTitle`, `errorScreenBody`, `errorScreenDetailLabel`) in EN + FR with descriptions — `flutter gen-l10n` regenerates `app_localizations*.dart` cleanly (gitignored, regen on every CI build per Plan 01-01 pattern).
- `MapScreenServices` immutable DTO at `lib/domain/map/map_screen_services.dart` — the constructor-injection seam for Plan 02-05's `MapScreen.fromServices(services)` rewrite.
- Fully-implemented `ErrorScreen` + `/error` GoRoute (the only Phase 2 screen production-ready in Wave 0; layout mirrors `PermissionDeniedScreen` for visual consistency).
- 5 production stubs (`PmtilesAssetCopier`, `GeolocatorService`, `BlueDotMarker`, `RecenterFab`, `MapCompass`) — every public class + method carries the GOSL header, full docstrings, strict types; analyzer green.
- 9 RED Phase 2 test files covering MAP-01..06 + LOC-01..05 — every test compiles against the Wave 0 stubs and fails at runtime with assertion errors only (no compilation errors, no hangs at the 30 s per-test timeout).
- `tool/test/check_no_last_known_position_test.dart` — LOC-03 CI gate; today GREEN (no `getLastKnownPosition` references in `lib/`); auto-discovered by the existing `dart test tool/test/` step in `.github/workflows/ci.yml`.

## Task Commits

Each task committed atomically:

1. **Task 1: Constants + l10n + services DTO + error screen + /error route** — `d553b2f` (feat)
2. **Task 2: Production stubs (PmtilesAssetCopier, GeolocatorService, BlueDotMarker, RecenterFab, MapCompass)** — `afe04de` (feat)
3. **Task 3: All 9 Phase 2 RED test files + LOC-03 static-source CI gate + MapScreen.fromServices stub** — `a5bf323` (test)

**Plan metadata commit:** to follow this SUMMARY.

## Files Created/Modified

### Created (16)

- `lib/domain/map/map_screen_services.dart` — Immutable DTO injected into `MapScreen.fromServices`.
- `lib/presentation/screens/error_screen.dart` — `/error` route target; renders icon + title + body + detail label + verbatim detail.
- `lib/infrastructure/pmtiles/pmtiles_asset_copier.dart` — Stub `static Future<String> ensureCopied()` (throws `UnimplementedError`; impl in Plan 02-02).
- `lib/infrastructure/location/geolocator_service.dart` — Stub `static Stream<Position> stream()` (returns empty stream; impl in Plan 02-03).
- `lib/presentation/widgets/blue_dot_marker.dart` — Stub `static CircleMarker build(LatLng)` (placeholder zero-radius marker; impl in Plan 02-03).
- `lib/presentation/widgets/recenter_fab.dart` — Stub StatefulWidget rendering disabled FAB (impl in Plan 02-04).
- `lib/presentation/widgets/map_compass.dart` — Stub StatefulWidget rendering `SizedBox.shrink()` (impl in Plan 02-04).
- `test/infrastructure/pmtiles/pmtiles_asset_copier_test.dart` — 4 cases for MAP-01 (first-launch copy + log, second-launch silence, size-mismatch re-copy, FileSystemException SEVERE-then-rethrow).
- `test/infrastructure/location/geolocator_service_test.dart` — LOC-01 LocationSettings spec (accuracy=best, distanceFilter=`kPocGpsDistanceFilterMeters`).
- `test/presentation/screens/map_screen_test.dart` — 9 widget tests for MAP-02..06 + LOC-02 + LOC-05.
- `test/presentation/screens/map_screen_gps_test.dart` — 4 tests for LOC-01 lifecycle.
- `test/presentation/screens/permission_gate_screen_pmtiles_failure_test.dart` — MAP-01 failure path → /error route navigation.
- `test/presentation/widgets/recenter_fab_test.dart` — 3 tests (LOC-04 animation, LOC-05 disabled, repeat-tap retargeting).
- `test/presentation/widgets/map_compass_test.dart` — 3 tests (snap-to-north over 250 ms, MapEventRotate triggers rebuild, shortest-path snap from 350°).
- `test/presentation/widgets/blue_dot_marker_test.dart` — 6 tests for LOC-02 spec (radius 7 px, fill 0xFF2B7CD6, white 2 px stroke, pixels-not-metres, point round-trip).
- `tool/test/check_no_last_known_position_test.dart` — LOC-03 static-source CI gate (lib/ scan).

### Modified (5)

- `lib/config/constants.dart` — Phase 2 constants block (19 new constants).
- `lib/l10n/app_en.arb` — 5 new keys.
- `lib/l10n/app_fr.arb` — 5 new keys with descriptions.
- `lib/presentation/router.dart` — `/error` GoRoute reading `state.extra` as `String detail` with `'<no detail>'` sentinel fallback.
- `lib/presentation/screens/map_screen.dart` — `MapScreen.fromServices(MapScreenServices services)` named-constructor stub (Rule 3 blocker; body still renders Phase 1 placeholder until Plan 02-05).

## Decisions Made

- **Wave 0 stays type-safe under strict-typing** — Test fakes for the abstract `MapController` use the structural record type `({bool moveSuccess, bool rotateSuccess})` directly because `flutter_map 7.0.2` doesn't re-export the `MoveAndRotateResult` typedef. Documented inline in both `recenter_fab_test.dart` and `map_compass_test.dart`.
- **Synthetic PMTiles for widget tests deferred to Plan 02-05** — Wave 0 `map_screen_test.dart` uses a placeholder pmtilesPath (`/dev/null/poc-wave0-placeholder.pmtile`); the structural assertions (`find.byType(FlutterMap)`, `find.byType(VectorTileLayer)`) fail fast against the placeholder body without triggering any async PMTiles parsing. Plan 02-05's GREEN tests will use real synthetic-bytes archives.
- **`@visibleForTesting` testOverride seam on `PmtilesAssetCopier` deferred to Plan 02-02** — The Wave 0 `permission_gate_screen_pmtiles_failure_test` asserts the end-state contract (PermissionGate must navigate to `/error` after grant + ensureCopied throwing FileSystemException). It fails RED today because PermissionGateScreen doesn't yet call `ensureCopied`. Plan 02-02 lands both the testOverride seam AND the gate-screen wiring in one atomic commit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Add `MapScreen.fromServices(MapScreenServices services)` named constructor stub**
- **Found during:** Task 3, while authoring `test/presentation/screens/map_screen_test.dart` and `map_screen_gps_test.dart`.
- **Issue:** The plan's `<interfaces>` block specifies that screen tests pump `MapScreen.fromServices(fakeServices)`. Without that constructor, none of the screen tests compile, blocking Task 3 entirely. The plan's `files_modified` list also doesn't include `lib/presentation/screens/map_screen.dart`, so this is genuinely a missed entry.
- **Fix:** Added a `const MapScreen.fromServices(MapScreenServices services, {super.key})` named constructor on the existing `MapScreen` widget. Body still renders the Phase 1 placeholder `ColoredBox` (Wave 0 stub philosophy preserved); Plan 02-05 swaps the body for `FlutterMap(...)` and starts consuming `services` at that point. Default `const MapScreen()` constructor preserved verbatim for the router.
- **Files modified:** `lib/presentation/screens/map_screen.dart`.
- **Verification:** `flutter analyze lib/` zero warnings; Phase 1 widget tests still green; 9 Wave 0 screen tests now compile and fail RED with assertion errors.
- **Committed in:** `a5bf323` (Task 3 commit).

**2. [Rule 1 — Bug] Drop dynamic temp-file synthetic PMTiles archive in screen tests to prevent test-suite hang**
- **Found during:** Task 3, during the first end-to-end `flutter test` run.
- **Issue:** The plan's first draft of `map_screen_test.dart` used `_syntheticPmtiles()` (a temp `Fra_Melun.pmtile` file with zero bytes) passed via `MapScreenServices.pmtilesPath`. The first test (`VectorTileLayer wired with kPocTileProviderSourceKey source key`) hung the entire suite for 10 minutes (test-runner timeout) — likely because `vector_map_tiles` started awaiting PMTiles parsing during the `pumpAndSettle` flow and never resolved against the empty file.
- **Fix:** Replaced the synthetic temp-file pattern with a literal placeholder string (`'/dev/null/poc-wave0-placeholder.pmtile'`). Wave 0 widget tests assert structural properties via `find.byType(...)` which fail fast against the Phase 1 placeholder body without awaiting any async PMTiles work. Plan 02-05's GREEN tests will reintroduce a real synthetic-bytes archive once `MapScreen` actually reads from `services.pmtilesPath`.
- **Files modified:** `test/presentation/screens/map_screen_test.dart`, `test/presentation/screens/map_screen_gps_test.dart`.
- **Verification:** Full `flutter test --timeout 30s` completes in 4 seconds, 48 passed / 27 RED Phase 2 assertions / no hangs.
- **Committed in:** `a5bf323` (Task 3 commit).

---

**Total deviations:** 2 auto-fixed (1 blocking missing-constructor, 1 runtime-hang bugfix)
**Impact on plan:** Both deviations were necessary to satisfy the plan's own contract ("flutter test must run; tests must fail with assertion errors, not compilation errors and not hangs"). No scope creep — the `MapScreen.fromServices` body still renders the Phase 1 placeholder; only the constructor surface was added.

## Issues Encountered

- The first iteration of `map_screen_test.dart` hung the test suite for 10 minutes (suite-level timeout). Diagnosed as `vector_map_tiles` awaiting PMTiles parsing on an empty synthetic file. Fixed inline (deviation #2 above).
- `dart format --set-exit-if-changed` reformatted six test/lib files post-author (collapsed multi-line constructors, consolidated long lines on multi-arg DTOs). Format is the source of truth — the reformatted versions were retained.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Wave 0 scaffold complete: 16 new files + 5 edits, all analyzer-clean, all RED tests fail with assertion errors only.
- Plan 02-02 (MAP-01: PMTiles copier + permission-gate wiring) can begin immediately. Its impl will:
  - Replace `PmtilesAssetCopier.ensureCopied`'s `UnimplementedError` body with the real bundle-to-disk copy + size-match idempotency check.
  - Add the `@visibleForTesting` `testOverride` seam (deferred from Wave 0).
  - Edit `PermissionGateScreen` to await `ensureCopied()` between grant and `/map` navigation, catching `FileSystemException` → `context.go('/error', extra: e.message)`.
- CI on the next push will be RED on `flutter test` (expected — Phase 2 RED tests). Plans 02-02..02-06 turn it GREEN incrementally.
- LOC-03 static-source CI gate is GREEN today; will stay GREEN as long as future plans cache `_lastFix` from the live stream rather than calling `Geolocator.getLastKnownPosition`.

---
*Phase: 02-map-no-fog*
*Completed: 2026-05-01*

## Self-Check: PASSED

- All 7 created lib files verified on disk
- All 9 created test files verified on disk
- All 5 modified lib files verified on disk
- All 3 task commits verified in git log (`d553b2f`, `afe04de`, `a5bf323`)
