---
phase: 02-map-no-fog
plan: 03
subsystem: location
tags: [geolocator, flutter_map, latlong2, logging, tdd, loc-01, loc-02, loc-03, circle-marker]

# Dependency graph
requires:
  - phase: 02-map-no-fog
    provides: Wave 0 stubs (GeolocatorService, BlueDotMarker), constants (kPocGpsDistanceFilterMeters, kPocBlueDot* triplet), RED tests (LOC-01, LOC-02), LOC-03 static-source CI gate
provides:
  - GeolocatorService.stream() — fully implemented, pinned LocationSettings(accuracy: best, distanceFilter: 5), Logger('domain.location') INFO log per subscribe
  - BlueDotMarker.build(LatLng) — fully implemented, 7 px CircleMarker (#2B7CD6) with 2 px white stroke, useRadiusInMeter: false
  - LOC-03 static-source CI gate hardened with Dart-comment stripping (educational `do NOT call` docstrings allowed; only code references trigger)
affects: [02-05-map-screen-wiring, future location-aware features]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Test seam: GeolocatorPlatform.instance swap via MockPlatformInterfaceMixin (mirrors Phase 1 PermissionHandlerPlatform.instance pattern; zero new dev_dependencies)"
    - "Logger.root onRecord listener pattern for unit-testing log emission without booting FileLogger"
    - "Static-source CI gates strip Dart comments before substring checks to permit educational forbidden-API docstrings"

key-files:
  created: []
  modified:
    - lib/infrastructure/location/geolocator_service.dart  # Wave 0 stub → real LOC-01 impl
    - lib/presentation/widgets/blue_dot_marker.dart        # Wave 0 stub → real LOC-02 impl
    - test/infrastructure/location/geolocator_service_test.dart  # +2 tests (INFO log, LOC-03 runtime guard)
    - tool/test/check_no_last_known_position_test.dart    # comment-aware scan

key-decisions:
  - "Hand-rolled _CapturingGeolocatorPlatform fake instead of adding a mockito dev_dependency — mirrors Phase 1 PermissionHandlerPlatform pattern, zero supply-chain audit cost, ~10 LOC"
  - "LOC-03 static-source gate refined to skip Dart comments (// /// /* */) so the plan-prescribed educational docstring (do NOT call Geolocator.getLastKnownPosition) doesn't false-positive — preserves the warning's documentary value while keeping the gate functional for actual code references"
  - "Geolocator.getLastKnownPosition runtime cross-check added to unit suite (counts platform-fake calls) — defence in depth alongside the static-source gate"

patterns-established:
  - "Pattern: GeolocatorPlatform.instance swap (test seam) — same shape as PermissionHandlerPlatform.instance from Phase 1; future location features can reuse the _CapturingGeolocatorPlatform fixture"
  - "Pattern: Comment-stripping static-source gates — when a docstring must reference a forbidden API by name (educational `do NOT call`), the gate scans only executable code"

requirements-completed: [LOC-01, LOC-02, LOC-03]

# Metrics
duration: 4 min
completed: 2026-05-01
---

# Phase 2 Plan 3: GPS subscription + blue-dot marker (LOC-01/02/03) Summary

**Pinned `Geolocator.getPositionStream(accuracy=best, distanceFilter=5)` with INFO-level `Logger('domain.location')` audit trail; LOC-02 spec `CircleMarker` (7 px / `#2B7CD6` / 2 px white stroke / pixels-not-metres); LOC-03 static-source CI gate hardened to comment-aware scanning.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-05-01T09:47:56Z
- **Completed:** 2026-05-01T09:52:41Z
- **Tasks:** 2 (both `tdd="true"`)
- **Files modified:** 4

## Accomplishments

- `GeolocatorService.stream()` replaces the Wave 0 empty-stream stub; emits the canonical INFO log `Subscribing to Geolocator.getPositionStream(accuracy=best, distanceFilter=5)` per subscribe, returns the platform stream with the LOC-01 settings.
- `BlueDotMarker.build(LatLng)` replaces the Wave 0 transparent-zero-radius stub; returns a `CircleMarker` whose every property reads from `lib/config/constants.dart` (`kPocBlueDotRadiusPx`, `kPocBlueDotFillArgb`, `kPocBlueDotStrokePx`) — zero magic numbers per CLAUDE.md.
- LOC-03 static-source CI gate now strips Dart comments before scanning, so the plan-mandated `do NOT call \`Geolocator.getLastKnownPosition\`` warning in the GeolocatorService docstring is allowed while real code references still fail the build.
- 9 of 9 plan tests GREEN: 3 LOC-01 + 6 LOC-02 (the Wave 0 file split border colour from border stroke into separate tests; both pass).

## Task Commits

1. **RED tests for LOC-01 INFO log + LOC-03 runtime guard** — `35ffe61` (test)
2. **GeolocatorService.stream() implementation + comment-aware LOC-03 gate** — `12b5ef4` (feat, includes Rule 3 deviation fix)
3. **BlueDotMarker.build implementation** — `840dd85` (feat, originally `e46c331` then amended to remove an inadvertently-staged sibling-plan file)

_Note: TDD task 1 produced 2 commits (test → feat); TDD task 2 was a single feat commit because the Wave 0 RED tests already encoded the full LOC-02 spec — only the GREEN step remained._

## Files Created/Modified

- `lib/infrastructure/location/geolocator_service.dart` — Replaced Wave 0 stub. New impl: `static const LocationSettings _settings = LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: kPocGpsDistanceFilterMeters);`, `static Stream<Position> stream() { _log.info(...); return Geolocator.getPositionStream(locationSettings: _settings); }`. `Logger _log = Logger('domain.location')` field.
- `lib/presentation/widgets/blue_dot_marker.dart` — Replaced Wave 0 stub. New impl returns `CircleMarker(point, radius: kPocBlueDotRadiusPx, useRadiusInMeter: false, color: Color(kPocBlueDotFillArgb), borderStrokeWidth: kPocBlueDotStrokePx, borderColor: Colors.white)`.
- `test/infrastructure/location/geolocator_service_test.dart` — Added 2 tests (`logs the subscription event at INFO`, `LOC-03 runtime guard`). Extended `_CapturingGeolocatorPlatform` fake with a `getLastKnownPosition` override + counter so the runtime guard can assert zero calls.
- `tool/test/check_no_last_known_position_test.dart` — Refined to strip `// ... \n`, `/// ...`, and `/* ... */` before substring search. New `_stripDartComments` helper (~30 LOC, naive but sufficient for GOSL-headed `.dart` files).

## Decisions Made

- **Test seam: hand-rolled fake, not mockito.** The plan offered both options. mockito would have required adding a strict-pinned dev_dependency + DEPENDENCIES.md audit row. The hand-rolled `_CapturingGeolocatorPlatform extends GeolocatorPlatform with MockPlatformInterfaceMixin` is ~10 LOC, mirrors the Phase 1 `PermissionHandlerPlatform.instance` pattern, and ships zero supply-chain debt. Trade-off accepted: any future test that needs richer mock semantics (e.g. method-call sequence verification) will need to extend the fake by hand. For LOC-01's three assertions (settings capture, log emission, lastKnownPosition counter), a hand-rolled fake is plainly enough.
- **LOC-03 static-source gate hardened, not bypassed.** The Plan 02-01 gate scanned with raw `String.contains('getLastKnownPosition')`, which over-matched on the Plan 02-03-prescribed docstring (`do NOT call \`Geolocator.getLastKnownPosition\``). Two options: (a) strip the API name from the docstring (loses the educational value — future maintainers might reach for `getLastKnownPosition` because no comment told them not to), or (b) make the gate Dart-comment-aware. Chose (b) — the gate's whole job is to catch real code references, and a 30-LOC `_stripDartComments` helper is a cheaper fix than degrading every future docstring that wants to name forbidden APIs.
- **Belt-and-braces runtime LOC-03 check.** Even though the static-source gate enforces the contract at CI time, the unit test's runtime assertion (`mock.lastKnownPositionCallCount == 0`) documents the expected behaviour at the unit-test level. Costs nothing, catches accidental mocking-layer regressions where a refactor might bypass the static gate.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] LOC-03 static-source CI gate over-matched on the prescribed docstring**
- **Found during:** Task 1 (Geolocator implementation)
- **Issue:** The Plan 02-01 `tool/test/check_no_last_known_position_test.dart` gate uses `src.contains('getLastKnownPosition')` — a raw substring scan with no comment awareness. The Plan 02-03 action prescribes a docstring that reads `do NOT call \`Geolocator.getLastKnownPosition\` (unreliable on iOS — known plugin issue, enforced by the static-source CI gate)`. After landing the GeolocatorService impl, the gate flagged the docstring as a code reference: `Offenders: ['lib\\infrastructure\\location\\geolocator_service.dart']` — a paradox where the docstring documenting the rule causes the rule to fail.
- **Fix:** Refined `tool/test/check_no_last_known_position_test.dart` with a `_stripDartComments` helper that removes `//` line comments, `///` doc comments, and `/* ... */` block comments before the substring search. Documented the hardening in the gate's docstring so future maintainers understand the comment-aware behaviour is intentional.
- **Files modified:** `tool/test/check_no_last_known_position_test.dart`
- **Verification:** Re-ran `dart test tool/test/check_no_last_known_position_test.dart` after each change; gate stays GREEN with the docstring in place. `flutter analyze tool/test/check_no_last_known_position_test.dart` clean.
- **Committed in:** `12b5ef4` (Task 1 commit — bundled because the gate refinement and the GeolocatorService impl are causally linked: the impl needs the docstring; the docstring needs the comment-aware gate).

**2. [Rule 3 - Blocking] Wave-2 parallel-execution race: sibling plan's WIP staged into my Task 2 commit**
- **Found during:** Task 2 commit immediately after Plan 02-04's WIP modifications to `test/presentation/widgets/recenter_fab_test.dart` were already in the working tree (and apparently auto-staged by some intermediate operation between my `git add lib/presentation/widgets/blue_dot_marker.dart` and `git commit`). The Task 2 commit `e46c331` accidentally included that sibling-plan file.
- **Issue:** Coordination contract violated — Plan 02-04's RecenterFab test work attributed to Plan 02-03's commit message, polluting both git history and Plan 02-04's later commit boundary.
- **Fix:** `git checkout 11b576e -- test/presentation/widgets/recenter_fab_test.dart` (restored to the file state just before my Task 2 work) → `git commit --amend --no-edit` → restored Plan 02-04's WIP back into the working tree as unstaged. Final Task 2 commit `840dd85` contains only `lib/presentation/widgets/blue_dot_marker.dart`.
- **Files modified:** None (the amend reverted an accidental inclusion, then the working tree was restored).
- **Verification:** `git show --name-only 840dd85` shows only `lib/presentation/widgets/blue_dot_marker.dart`. `git status` shows `recenter_fab_test.dart` back as unstaged-modified, ready for Plan 02-04's own commit. `flutter test test/presentation/widgets/blue_dot_marker_test.dart` re-run after the amend — all 6 GREEN.
- **Committed in:** `840dd85` (final Task 2 commit, post-amend).

---

**Total deviations:** 2 auto-fixed (2 blocking).
**Impact on plan:** Both auto-fixes were necessary (gate bug + parallel-execution race). No scope creep — the gate refinement is a pure improvement to a Plan 02-01 deliverable that the planner couldn't have foreseen would over-match its own prescribed docstring; the wave-2 race fix preserves both my plan's commit cleanliness and the sibling plan's pending work.

## Issues Encountered

- **Wave-2 parallel-execution race (recenter_fab_test.dart pollution).** Documented above as Deviation 2. Lesson for future Wave-2 plans: even with `git add <specific file>`, pre-staged or working-tree-modified sibling files can leak into a commit if the parallel agent has touched files in the index. Mitigation: `git status --porcelain` before commit, and explicitly `git restore --staged <file>` for any non-plan files that show as staged.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- LOC-01, LOC-02, LOC-03 fully landed. `GeolocatorService.stream()` is ready for `MapScreen.initState` to consume in Plan 02-05.
- `BlueDotMarker.build(LatLng)` is ready for `MapScreen` to render inside a `CircleLayer` (gated on `_lastFix != null` per LOC-05).
- LOC-03 static-source gate is now CI-stable and educational-docstring-tolerant.
- No new dependencies — `pubspec.yaml` unchanged from Plan 01 baseline.
- Wave-2 sibling plans (02-02 PMTiles copier, 02-04 RecenterFab + MapCompass) ran in parallel; Plan 02-02's commits visible in the log (`11b576e`); Plan 02-04's WIP preserved in the working tree as unstaged.

## Self-Check: PASSED

- All 5 expected files present on disk (2 lib/, 1 test/, 1 tool/, 1 .planning/).
- All 3 task commits (`35ffe61`, `12b5ef4`, `840dd85`) present in git log.

---
*Phase: 02-map-no-fog*
*Completed: 2026-05-01*
