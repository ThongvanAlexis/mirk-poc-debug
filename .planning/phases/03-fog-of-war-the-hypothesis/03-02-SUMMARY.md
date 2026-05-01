---
phase: 03-fog-of-war-the-hypothesis
plan: 02
subsystem: domain
tags: [haversine, change-notifier, latlong2, fog-of-war, wave-1]

# Dependency graph
requires:
  - phase: 03-fog-of-war-the-hypothesis
    provides: Plan 03-01 stubs (RevealDiscRepository, distanceMetres) + RED test files
provides:
  - "RevealDiscRepository.append/snapshot — in-memory ChangeNotifier with defensive-copy snapshot semantics (FOG-01)"
  - "distanceMetres(LatLng, LatLng) — Haversine helper using kEarthRadiusMeters (FOG-02)"
  - "5 RED → GREEN test flips (3 repository + 2 distanceMetres)"
affects:
  - "Plan 03-05 FogLayer (consumes snapshot for paint-time iteration)"
  - "Plan 03-07 MapScreen integration (calls append on every GPS fix; reads distanceMetres for the move-distance gate before spawning a new disc)"
  - "Plan 03-01 fog_layer_slot_count_gate_test (already GREEN — keeps proving the day-1 invariant against a real repository)"

# Tech tracking
tech-stack:
  added: []  # No new dependencies — pure Dart implementation against existing flutter/foundation + latlong2
  patterns:
    - "Defensive-copy snapshot pattern (List.unmodifiable view of live list) — paint-time iteration safe under concurrent mutation"
    - "Top-level Haversine helper (not LatLng extension) — preserves donor RevealDisc.distanceMetersTo (lat, lon) seam"

key-files:
  created: []
  modified:
    - "lib/domain/revealed/reveal_disc_repository.dart (stub → impl, 25 → 44 lines)"
    - "lib/domain/revealed/distance_metres.dart (stub → impl, 14 → 44 lines)"

key-decisions:
  - "Top-level distanceMetres function (not extension on LatLng) — donor RevealDisc.distanceMetersTo takes raw doubles, parallel top-level helper that takes LatLng is the cheapest seam for the GPS-fix listener path"
  - "Single source of truth for great-circle constants — kEarthRadiusMeters (WGS-84 6371008.8 m) reused from Phase 1 BOOT-08 donor port (lib/config/constants.dart) — same constant the donor reveal_disc.dart, revealed_sdf_builder.dart already consume"
  - "_degreesPerHalfTurn = 180.0 file-private constant (vs inline 180.0) — CLAUDE.md no-magic-numbers compliance, mirrors the donor reveal_disc.dart's same private constant"

patterns-established:
  - "Wave-1 RED-to-GREEN flip: TDD RED phase already committed in Plan 03-01 (Wave 0); Wave-1 plans implement only the GREEN flip — no new test code authored, just stub replacement and verification"
  - "Defensive-copy boundary documentation: docstring spells out the iterator/lifecycle contract so paint-time consumers (FogLayer.build) know snapshots do NOT observe future appends"

requirements-completed: [FOG-01, FOG-02]

# Metrics
duration: 5min
completed: 2026-05-01
---

# Phase 03 Plan 02: Reveal Disc Repository + Haversine Helper Summary

**In-memory RevealDiscRepository (ChangeNotifier with defensive-copy snapshot) and Haversine distanceMetres helper landed; 5 of Plan 03-01's RED tests flip to GREEN and FOG-01/FOG-02 are now production-ready for downstream FogLayer + MapScreen integration**

## Performance

- **Duration:** 5 min
- **Started:** 2026-05-01T15:02:01Z
- **Completed:** 2026-05-01T15:07:18Z
- **Tasks:** 2 (both `type="auto" tdd="true"` — TDD GREEN-flip phase only; Wave 0 already committed RED tests)
- **Files modified:** 2 (both production .dart — test files unchanged from Plan 03-01)

## Accomplishments

- **FOG-01 — RevealDiscRepository fully implemented.** `append(disc)` mutates `_discs` and calls `notifyListeners()` exactly once per call. `snapshot()` returns `List<RevealDisc>.unmodifiable(_discs)` — a defensive copy that does NOT observe future appends. 3/3 Plan 03-01 RED tests now GREEN.
- **FOG-02 — distanceMetres Haversine implementation.** At lat 48.5°, `distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km` (NOT ~111 km — defends against the degree-vs-meter regression). At the equator, `distanceMetres((0, 0), (0, 1)) ≈ 111.32 km`. Symmetric, zero on identical points. Uses `kEarthRadiusMeters` (Phase 1 BOOT-08 donor constant). 2/2 Plan 03-01 RED tests now GREEN.
- **Net falsification harness delta after Plan 03-02 alone: -5 RED, +5 GREEN.** Both surfaces are pure Dart, depend on no other Phase 3 component, and are ready for consumption by Plan 03-05 FogLayer (snapshot for paint-time iteration) and Plan 03-07 MapScreen integration (append on every GPS fix).

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement RevealDiscRepository (FOG-01)** — `cb58221` (feat)
2. **Task 2: Implement distanceMetres (FOG-02 defence)** — `3572b67` (feat)

**Plan metadata:** TBD (final commit captures SUMMARY.md + STATE.md + ROADMAP.md + REQUIREMENTS.md)

_Note: Plan 03-02 ran TDD GREEN-only — RED tests were authored and committed by Plan 03-01 (Wave 0 falsification harness commits `b8f49f0`, `5add4e5`). Wave 1 plans implement against pre-existing RED tests rather than re-authoring them._

## Files Created/Modified

- `lib/domain/revealed/reveal_disc_repository.dart` — Stub replaced with full ChangeNotifier impl (44 lines; private `_discs` list + `append` + `snapshot`; class docstring covers concurrency + lifecycle)
- `lib/domain/revealed/distance_metres.dart` — Stub replaced with Haversine impl (44 lines; top-level `distanceMetres(LatLng, LatLng)` + file-private `_degreesPerHalfTurn` constant; docstring spells out the FOG-02 defence and the rationale for top-level vs extension)

## Decisions Made

- **Top-level function, not extension on LatLng.** `LatLng` is third-party (latlong2) and an extension method risks colliding with future package additions; the donor `RevealDisc.distanceMetersTo(double otherLat, double otherLon)` takes raw doubles, so a parallel top-level helper that takes LatLng is the cheapest seam for the FOG-01 GPS-fix listener (which holds `Position` from geolocator and converts to LatLng for the blue-dot).
- **Reuse `kEarthRadiusMeters` from Phase 1 BOOT-08 constants.** Single source of truth for great-circle maths across the revealed-domain code — the donor `reveal_disc.dart`, `revealed_sdf_builder.dart` already consume the same WGS-84 mean radius (6371008.8 m). Avoids the well-known footgun of two implementations diverging on the radius constant after a copy-paste.
- **`_degreesPerHalfTurn = 180.0` file-private constant.** CLAUDE.md "Magic numbers — Aucun number magique" rule. Mirrors the same private constant in the donor `reveal_disc.dart`. Token-cost trivial; defends future readers from the implicit deg→rad coupling.
- **Defensive-copy snapshot via `List.unmodifiable(_discs)`.** Cheap (no allocation of a new backing list — just a wrapper view), but paint-time consumers iterate the snapshot and never the live list, so a GPS fix landing mid-paint cannot trigger `ConcurrentModificationError`. Pre-append snapshots remain empty even after `append` because the unmodifiable view's iterator is taken eagerly when the snapshot is iterated/expanded — the test `snapshot() taken before append does not change after append` verifies this end-to-end.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Convention compliance] Hoisted `180.0` literal into `_degreesPerHalfTurn` named constant**

- **Found during:** Task 2 (distanceMetres implementation)
- **Issue:** The plan-prescribed implementation used `180.0` literal four times for the deg→rad conversion. CLAUDE.md mandates "Aucun number magique" (no magic numbers); the donor `lib/domain/revealed/reveal_disc.dart` already extracts the same constant as `_degreesPerHalfTurn` for the same reason.
- **Fix:** Added `const double _degreesPerHalfTurn = 180.0;` as a file-private constant with a docstring linking it to the donor pattern. Replaced all four `180.0` occurrences inline. Zero cost-of-correctness — `dart format` happily collapsed the multi-line `h` computation to a single line under 160 chars after the rename.
- **Files modified:** lib/domain/revealed/distance_metres.dart
- **Verification:** `flutter test test/domain/revealed/distance_metres_test.dart` still GREEN (2/2); `flutter analyze` 0 issues; `dart format --line-length 160` clean.
- **Committed in:** 3572b67 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 convention compliance per CLAUDE.md no-magic-numbers rule)
**Impact on plan:** No scope creep. The plan-prescribed implementation would have analyse-clean-passed but violated a project convention; fixing it inline was cheaper than landing a known-future-cleanup commit.

## Issues Encountered

None. Both surfaces are pure Dart, deterministic, and the RED tests authored in Plan 03-01 had complete coverage of the implementation contract — no behavioural ambiguity surfaced during implementation.

## Out-of-scope observations (logged, not fixed)

- The full `flutter test` suite at HEAD reports `-2 RED` from `test/presentation/widgets/fog_clip_path_test.dart` (Plan 03-01 RED tests for FOG-04/05 `computeFogClipPath`, blocked on Plan 03-05 implementation). These are part of the designed Wave 0 falsification harness, NOT a Plan 03-02 regression — `computeFogClipPath` was not in this plan's scope.
- `flutter analyze` reports 16 errors in `test/infrastructure/mirk/frame_delta_probe_test.dart` (undefined `rollupInterval` named param + undefined `debugRecordRawDelta` method). These were introduced by the parallel Wave-1 sibling Plan 03-04's RED-test commit `5add4e5` while Plan 03-02 was executing — they're targets for Plan 03-04's GREEN flip and are explicitly out-of-scope for Plan 03-02 per the scope-boundary rule.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **FOG-01 ready for FOG-07 (MapScreen integration).** `RevealDiscRepository.append` is the API the GPS-fix listener will call on every fix that passes the move-distance gate.
- **FOG-02 ready for FOG-07 too.** `distanceMetres(currentFix, lastDiscCentre)` is the move-distance gate before append.
- **Both ready for Plan 03-05 FogLayer.** `snapshot()` is what the layer iterates at paint time; the defensive-copy contract is documented and tested.
- **No blockers introduced for downstream plans.** Plan 03-03 (SdfCache) and Plan 03-04 (FrameDeltaProbe) ran in parallel; their commits do not conflict with Plan 03-02's two production files.

## Self-Check: PASSED

Verification of claims in this summary:

- `lib/domain/revealed/reveal_disc_repository.dart` exists at HEAD with the documented `append`/`snapshot` impl: FOUND (44 lines, last modified 2026-05-01).
- `lib/domain/revealed/distance_metres.dart` exists at HEAD with the documented Haversine impl: FOUND (44 lines, last modified 2026-05-01).
- Commit `cb58221` (Task 1 — RevealDiscRepository): FOUND in `git log`.
- Commit `3572b67` (Task 2 — distanceMetres): FOUND in `git log`.
- `flutter test test/domain/revealed/`: 5/5 GREEN at HEAD.
- `flutter analyze lib/domain/revealed/ test/domain/revealed/`: 0 issues (analyze errors elsewhere are sibling-plan-scoped, documented above).
- `dart format --line-length 160 --set-exit-if-changed lib/domain/revealed/ test/domain/revealed/`: clean.

---
*Phase: 03-fog-of-war-the-hypothesis*
*Completed: 2026-05-01*
