---
phase: 02
slug: map-no-fog
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-01
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (SDK-bundled) + `package:test 1.30.0` for `tool/test/` static-source assertions |
| **Config file** | `analysis_options.yaml` (strict-casts/inference/raw-types) — Phase 1 patterns from `test/presentation/` and `test/infrastructure/logging/` |
| **Quick run command** | `flutter test test/presentation/screens/map_screen_test.dart test/infrastructure/pmtiles/ test/infrastructure/location/ test/presentation/widgets/recenter_fab_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds quick / ~90 seconds full |

---

## Sampling Rate

- **After every task commit:** Run quick command (touched-area subset)
- **After every plan wave:** Run `flutter test` (full suite)
- **Before `/gsd:verify-work`:** Full suite must be green on Windows + CI Android + CI iOS
- **Max feedback latency:** 30 seconds (quick) / 90 seconds (full)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-XX | 01 | 1 | MAP-01 | unit | `flutter test test/infrastructure/pmtiles/pmtiles_asset_copier_test.dart` | ❌ W0 | ⬜ pending |
| 02-01-XX | 01 | 1 | MAP-01 | widget | `flutter test test/presentation/screens/permission_gate_screen_pmtiles_failure_test.dart` | ❌ W0 | ⬜ pending |
| 02-02-XX | 02 | 2 | MAP-02 | widget | `flutter test test/presentation/screens/map_screen_test.dart --plain-name "VectorTileLayer wired"` | ❌ W0 | ⬜ pending |
| 02-02-XX | 02 | 2 | MAP-03 | widget | `flutter test test/presentation/screens/map_screen_test.dart --plain-name "initial camera Melun z13"` | ❌ W0 | ⬜ pending |
| 02-02-XX | 02 | 2 | MAP-04 | widget | `flutter test test/presentation/screens/map_screen_test.dart --plain-name "InteractionOptions all flags"` | ❌ W0 | ⬜ pending |
| 02-02-XX | 02 | 2 | MAP-05 | widget | `flutter test test/presentation/screens/map_screen_test.dart --plain-name "pinch zoom flag set"` | ❌ W0 | ⬜ pending |
| 02-02-XX | 02 | 2 | MAP-06 | widget | `flutter test test/presentation/screens/map_screen_test.dart --plain-name "combined gestures race disabled"` | ❌ W0 | ⬜ pending |
| 02-03-XX | 03 | 2 | LOC-01 | widget | `flutter test test/presentation/screens/map_screen_gps_test.dart` | ❌ W0 | ⬜ pending |
| 02-03-XX | 03 | 2 | LOC-02 | widget | `flutter test test/presentation/widgets/blue_dot_marker_test.dart` | ❌ W0 | ⬜ pending |
| 02-03-XX | 03 | 2 | LOC-03 | static-source | `dart test tool/test/check_no_last_known_position_test.dart` | ❌ W0 | ⬜ pending |
| 02-04-XX | 04 | 3 | LOC-04 | widget | `flutter test test/presentation/widgets/recenter_fab_test.dart --plain-name "animates to lastFix at z15 over 500ms"` | ❌ W0 | ⬜ pending |
| 02-04-XX | 04 | 3 | LOC-05 | widget | `flutter test test/presentation/widgets/recenter_fab_test.dart --plain-name "disabled when no fix"` | ❌ W0 | ⬜ pending |
| 02-04-XX | 04 | 3 | LOC-04 | widget | `flutter test test/presentation/widgets/recenter_fab_test.dart --plain-name "repeat tap during animation"` | ❌ W0 | ⬜ pending |
| 02-05-XX | 05 | 4 | PERF-02 | manual UAT | sideload IPA + 200 m walk in central Melun (zoom 13–15); FPS overlay ≥ 40 sustained | n/a (manual) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Test files (must exist before Wave 1 task commits):

- [ ] `test/infrastructure/pmtiles/pmtiles_asset_copier_test.dart` — MAP-01 (copy + idempotent + size-mismatch + FileSystemException paths) using temp dir + synthetic 4-byte fake asset
- [ ] `test/infrastructure/location/geolocator_service_test.dart` — LOC-01 settings (`LocationAccuracy.best`, `distanceFilter: 5`); mocked via `GeolocatorPlatform.instance` test seam
- [ ] `test/presentation/screens/map_screen_test.dart` — MAP-02..06 + LOC-02 + LOC-05; pumps `MapScreen.fromServices(fakeServices)` with fake stream factory + fake on-disk PMTiles file
- [ ] `test/presentation/screens/map_screen_gps_test.dart` — LOC-01 lifecycle (initState subscribe, dispose cancel, fix → setState)
- [ ] `test/presentation/screens/permission_gate_screen_pmtiles_failure_test.dart` — FileSystemException catch + error route in gate screen extension
- [ ] `test/presentation/widgets/recenter_fab_test.dart` — LOC-04 (duration + curve + final position) + LOC-05 (disabled state) + repeat-tap-cancellation edge case
- [ ] `test/presentation/widgets/map_compass_test.dart` — compass tween + bearing-stream-sync
- [ ] `test/presentation/widgets/blue_dot_marker_test.dart` — LOC-02 colour/stroke/radius + visibility-when-null
- [ ] `tool/test/check_no_last_known_position_test.dart` — LOC-03 static-source assertion CI gate (mirrors LOG-05 pattern from Phase 1 Plan 01-04 W-4)

Production files (new, required for tests to compile):

- [ ] `lib/domain/map/map_screen_services.dart` — services value object
- [ ] `lib/infrastructure/pmtiles/pmtiles_asset_copier.dart`
- [ ] `lib/infrastructure/location/geolocator_service.dart`
- [ ] `lib/presentation/widgets/recenter_fab.dart`
- [ ] `lib/presentation/widgets/map_compass.dart`
- [ ] `lib/presentation/widgets/blue_dot_marker.dart`
- [ ] `lib/presentation/screens/error_screen.dart` (or extend `permission_denied_screen.dart`) — error route landing
- [ ] Updated `lib/presentation/router.dart` — add `/error` route
- [ ] Updated `lib/config/constants.dart` — Phase 2 constants block
- [ ] Updated `lib/l10n/app_en.arb` + `app_fr.arb` — `recenterTooltip`, `compassTooltip`, `errorScreenTitle`, `errorScreenRetryHelp` strings + `flutter gen-l10n` regen

**No DEPENDENCIES.md row added** — Phase 2 introduces zero new direct dependencies (all packages already pinned in Phase 1).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Sustained pan-FPS ≥ 40 on iPhone 17 Pro at zoom 13–15 over central Melun PMTiles | PERF-02 | Requires real-device frame profiling under realistic walking GPS input + Protomaps tile density at the actual map view; no automated harness can stand in for a 200 m walking session with the user's hands on the device | (1) Build IPA via CI; (2) sideload to iPhone 17 Pro; (3) walk 200 m through central Melun at zoom 13–15; (4) perform ≥ 10 pure pans, ≥ 10 pure pinch-zooms, ≥ 10 combined pinch+pan gestures; (5) read FPS overlay sustained value; (6) PASS if ≥ 40 fps; (7) FAIL → Phase 3 blocked until label-thinning or other mitigation restores baseline |
| Tile repaint without persistent blank flashes on rapid z=15 → 8 → 15 | Phase 2 Success Criterion #4 | Visual judgment of cold-cache decode flicker vs sustained blanks is perceptual | Same walk session: rapid zoom-out then zoom-in gesture; PASS if tiles repaint without sustained blank flashes (brief decode flicker on cold cache is acceptable) |
| First-launch copy log message format | MAP-01 (success criterion #1) | Observation of log line during permission-grant flow on real device | Fresh-install IPA; observe log records `Copied Fra_Melun.pmtile (~4 MB) in <500 ms` exactly once during permission-grant; relaunch confirms no re-copy log |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies _(checker-confirmed 2026-05-01)_
- [x] Sampling continuity: no 3 consecutive tasks without automated verify _(checker-confirmed 2026-05-01)_
- [x] Wave 0 covers all MISSING references _(checker-confirmed 2026-05-01)_
- [x] No watch-mode flags _(checker-confirmed 2026-05-01)_
- [x] Feedback latency < 30s (quick) / < 90s (full)
- [x] `nyquist_compliant: true` set in frontmatter _(flipped 2026-05-01 per checker dimension 8 review)_

**Approval:** sign-off complete (pre-execution). `wave_0_complete: false` remains until Wave 0 actually runs.
