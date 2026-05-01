---
phase: 02-map-no-fog
plan: 02
subsystem: infra
tags: [pmtiles, asset-copy, idempotency, file-system-exception, permission-gate, lifecycle, path-provider, application-support, root-bundle, map-01]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: PermissionGateScreen (W-2 lifecycle hook + WidgetsBindingObserver), GoRouter (3 routes), FileLogger (Logger.root sink), AppLocalizations bootstrap, GOSL header CI gate
  - phase: 02-map-no-fog
    plan: 01
    provides: PmtilesAssetCopier stub, ErrorScreen + /error GoRoute, kPmtilesAssetPath/Basename/MapsSubdir constants, permission_gate_screen_pmtiles_failure_test RED scaffold, pmtiles_asset_copier_test RED scaffold
provides:
  - PmtilesAssetCopier.ensureCopied — full impl: idempotent rootBundle → <getApplicationSupportDirectory()>/maps/Fra_Melun.pmtile copy with size-parity check, INFO log on first launch only, FileSystemException routing
  - PmtilesAssetCopier.testEnsureCopiedOverride — @visibleForTesting test seam consumed by gate-screen widget tests + (future) MapScreen widget tests
  - PermissionGateScreen._ensureMapDataAndNavigate — single helper through which BOTH grant paths (in-app CTA + AppLifecycleState.resumed) converge before /map navigation
  - 3 GREEN MAP-01 widget tests asserting CTA failure, lifecycle failure, and CTA happy paths route correctly
affects: [02-03-LOC-01-LOC-02-gps-blue-dot, 02-04-LOC-04-LOC-05-recenter-compass, 02-05-MAP-02-06-map-screen-wiring, 02-06-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Idempotency via existence + size-parity check (NOT SHA256) — RESEARCH §ROB-02 deferral; truncated previous copy triggers re-copy because lengthSync() != bundled.lengthInBytes"
    - "@visibleForTesting test-override seam on PmtilesAssetCopier — production code calls testEnsureCopiedOverride?.call() ?? _realEnsureCopied(); widget tests inject success/failure without filesystem; mirrors PermissionHandlerPlatform.instance pattern from Plan 01-06"
    - "Both-paths converge via _ensureMapDataAndNavigate helper — CTA path and lifecycle resumed path both early-return on non-grant, then delegate to a single helper that awaits ensureCopied + routes by outcome. Prevents future drift between the two paths"
    - "FileSystemException catch wrapped around any non-FS throwable — non-IO failures in the copier are wrapped into FileSystemException so the caller (gate screen) keeps a single-type catch surface (CLAUDE.md §Error handling — periphery)"
    - "TestDefaultBinaryMessengerBinding mock on flutter/assets channel — pmtiles_asset_copier_test installs a synthetic 4-byte ByteData fixture for rootBundle.load(kPmtilesAssetPath) so the copier test never touches a real bundled asset"

key-files:
  created: []
  modified:
    - lib/infrastructure/pmtiles/pmtiles_asset_copier.dart (Wave 0 stub replaced with full ensureCopied implementation + testEnsureCopiedOverride seam)
    - lib/presentation/screens/permission_gate_screen.dart (_ensureMapDataAndNavigate helper added; both _onCtaPressed and _checkAndMaybeNavigate refactored to early-return on non-grant + delegate to the helper; dart:io + pmtiles_asset_copier imports added)
    - test/infrastructure/pmtiles/pmtiles_asset_copier_test.dart (added testEnsureCopiedOverride reset in setUp/tearDown + 5th test asserting override short-circuit + counting _CountingPathProviderPlatform fake)
    - test/presentation/screens/permission_gate_screen_pmtiles_failure_test.dart (Wave 0 RED scaffold expanded to 3 GREEN tests: CTA failure, lifecycle failure, CTA happy path; added logRecords capture + tearDown override clearing)
    - test/presentation/screens/permission_gate_screen_test.dart (Phase 1 test updated: setUp installs testEnsureCopiedOverride returning '/fake/maps/Fra_Melun.pmtile' so the new ensureCopied call on every grant path doesn't hit a real filesystem; tearDown clears the override; PmtilesAssetCopier import added)

key-decisions:
  - "Plan called for 5 PMTiles tests (first-launch, idempotent, mismatch, FileSystemException, override). Wave 0 scaffold landed only the first 4. Plan 02-02 added the 5th (testEnsureCopiedOverride short-circuit) using a counting _CountingPathProviderPlatform fake to prove zero filesystem operations slipped through when the override is set. Same file, same group — no test-name collision."
  - "FileSystemException test uses the path-provider-throw-flavoured approach (pre-create the support path AS A FILE so creating the maps/ subdirectory raises FileSystemException on every platform) — this was already the Wave 0 scaffold's choice. Cross-platform read-only-file workaround was the documented alternative; plan-suggested approach was kept because it works on Windows + macOS + Linux + iOS + Android with no platform branching."
  - "Both grant paths (_onCtaPressed + _checkAndMaybeNavigate) converge through a single private helper _ensureMapDataAndNavigate. The plan suggested the same helper name; kept verbatim. Each path retains its own early-return for the non-grant outcome (CTA → /denied, lifecycle → silent return) before delegating to the helper, so the helper is responsible only for the success-path branch + FileSystemException routing."
  - "Phase 1 permission_gate_screen_test.dart's setUp now installs testEnsureCopiedOverride returning a fake path — without this, the 6 Phase 1 tests would crash on the first await ensureCopied() because PathProviderPlatform isn't mocked in that file. The override path is silent (no filesystem, no logs) so the existing navigation assertions remain valid. Documented inline with a Phase 2 Plan 02 comment per the plan's instruction."
  - "Sibling-plan changes (recenter_fab.dart + recenter_fab_test.dart) were left uncommitted in the working tree per the coordination note. They belong to Plan 02-04 and will be committed by that plan's executor."

patterns-established:
  - "Plan 02-02 codifies the @visibleForTesting test-override pattern for any future asset/data copier in this project — production code defers to the override iff non-null, else does the real I/O. Avoids dependency-injection ceremony for what is conceptually a static utility"
  - "Both-grant-paths-converge-through-one-helper template — applies to any future screen that needs to gate navigation on async work after a permission/auth boundary"

requirements-completed: [MAP-01]

# Metrics
duration: 5min
completed: 2026-05-01
---

# Phase 2 Plan 02: PMTiles Copy + Permission Gate Hook Summary

**MAP-01 satisfied: idempotent rootBundle → Application Support PMTiles copy hooked into both grant paths of PermissionGateScreen, with FileSystemException routed to /error.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-01T09:47:52Z
- **Completed:** 2026-05-01T09:52:50Z
- **Tasks:** 2 (both TDD: RED already in place from Wave 0, plan flipped GREEN)
- **Files modified:** 5 (2 lib + 3 test)

## Accomplishments
- Replaced Wave 0 PmtilesAssetCopier stub with full ensureCopied: rootBundle.load → writeAsBytes(flush) to <getApplicationSupportDirectory()>/maps/Fra_Melun.pmtile, idempotent on size-parity, INFO log on first launch only, SEVERE-then-rethrow on FileSystemException
- Added @visibleForTesting testEnsureCopiedOverride static field — gate-screen widget tests inject success/failure without filesystem
- Refactored PermissionGateScreen so BOTH grant paths (_onCtaPressed + _checkAndMaybeNavigate) converge through a new _ensureMapDataAndNavigate helper that awaits ensureCopied + routes /map on success, /error on FileSystemException with extra==e.message
- Wave 0 RED test (permission_gate_screen_pmtiles_failure_test) expanded into 3 GREEN tests: CTA failure → /error with detail, lifecycle (pre-granted) failure → /error with detail, CTA happy path → /map
- Phase 1 permission_gate_screen_test updated with the override seam; 6 Phase 1 tests still GREEN (regression guard)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement PmtilesAssetCopier.ensureCopied (MAP-01 core)** — `11b576e` (feat)
2. **Task 2: Hook ensureCopied into PermissionGateScreen — both grant paths + /error route** — `8b04d75` (feat)

**Plan metadata commit:** _to follow this SUMMARY_

_Note: Both tasks were marked tdd="true". Wave 0 had already laid the RED scaffolding for both, so this plan went straight to GREEN-and-refactor — no separate RED commits needed (the RED commits land in Plan 02-01: a5bf323)._

## Files Created/Modified
- `lib/infrastructure/pmtiles/pmtiles_asset_copier.dart` — Wave 0 stub replaced with full implementation. Public surface: `static Future<String> ensureCopied()` and `@visibleForTesting static Future<String> Function()? testEnsureCopiedOverride`. Logger hierarchy `infrastructure.pmtiles`.
- `lib/presentation/screens/permission_gate_screen.dart` — both grant paths refactored to early-return on non-grant + delegate to new private `_ensureMapDataAndNavigate` helper that wraps `ensureCopied` in a `FileSystemException` catch; `dart:io` + pmtiles_asset_copier imports added.
- `test/infrastructure/pmtiles/pmtiles_asset_copier_test.dart` — added `setUp`/`tearDown` resets of `testEnsureCopiedOverride`, added 5th test asserting the override short-circuits BEFORE any path-provider lookup (counting fake `_CountingPathProviderPlatform` proves zero FS ops).
- `test/presentation/screens/permission_gate_screen_pmtiles_failure_test.dart` — Wave 0 RED scaffold (1 test, 1 route) expanded to 3 GREEN tests + 4 routes + log-record capture + override-clearing tearDown.
- `test/presentation/screens/permission_gate_screen_test.dart` — `setUp` now installs `testEnsureCopiedOverride` returning a fake path; `tearDown` clears it. Inline comment documents the Phase 2 Plan 02 reason. PmtilesAssetCopier import added.

## Decisions Made
- **5th PMTiles test was added by this plan, not Wave 0.** The plan called for 5 (first-launch, idempotent, mismatch, FileSystemException, override). Wave 0 only landed the first 4 because the override seam itself was deferred to this plan. Adding the 5th here keeps the override symbol's contract co-located with its definition.
- **FileSystemException test path: blocked-support-path approach kept verbatim from Wave 0.** Pre-creating the supportDir as a FILE (not a directory) makes `Directory.create(recursive: true)` raise FileSystemException on every platform with no branching. The plan offered read-only-file as an alternative; not needed.
- **Both paths converge through a single helper.** Plan-suggested name `_ensureMapDataAndNavigate` kept verbatim. CTA path and lifecycle path each retain their own early-return for the non-grant outcome before delegating to the helper.

## Log Line on First Launch

The exact INFO log line emitted by `PmtilesAssetCopier.ensureCopied` on first launch matches:

```
^Copied Fra_Melun\.pmtile \(~\d+\.\d MB\) in \d+ ms$
```

(at logger `infrastructure.pmtiles`, level `Level.INFO`). On second launch with size match: NO log line at all (CONTEXT mandate). On size mismatch: same first-launch line is re-emitted.

## Both Grant Paths Confirmed Hitting ensureCopied

Verified by 3 GREEN widget tests:

| Test | Path | Trigger |
|------|------|---------|
| `MAP-01 CTA failure path` | `_onCtaPressed` | `tester.tap(find.text('Allow location'))` |
| `MAP-01 lifecycle failure path` | `_checkAndMaybeNavigate('initState')` | `pumpWidget` with status pre-granted |
| `MAP-01 CTA happy path` | `_onCtaPressed` | tap CTA, override returns success |

The CONTEXT.md mandate is satisfied: "Both the in-app prompt path AND the AppLifecycleState.resumed re-check path must hit it."

## Deviations from Plan

None — plan executed exactly as written. The two minor "unspecified detail" calls (5th-test placement, FileSystemException test approach) were both already implicit in the Wave 0 scaffold and the plan body's suggestions, and both were resolved as the plan suggested.

**Total deviations:** 0
**Impact on plan:** None.

## Issues Encountered

- Other plans' Wave 0 RED tests (`map_screen_test.dart`, `map_screen_gps_test.dart`, `recenter_fab_test.dart`, etc.) remain RED in the full `flutter test` run — these belong to Plans 02-03/02-04/02-05 and are out of scope per the coordination note. My plan-scope tests (`test/infrastructure/pmtiles/`, `test/presentation/screens/permission_gate_screen*`) are 14/14 GREEN.
- A sibling plan's executor has uncommitted edits to `lib/presentation/widgets/recenter_fab.dart` + `test/presentation/widgets/recenter_fab_test.dart` in the working tree. Per the wave-2 coordination note, I left them alone — they belong to Plan 02-04 and will be committed by that plan's executor.

## Self-Check: PASSED

All 5 plan-scope files present on disk (2 lib + 3 test), SUMMARY.md created, both task commits (`11b576e`, `8b04d75`) reachable from `git log --oneline --all`.

## User Setup Required
None — no external service configuration required. PMTiles asset is bundled in `pubspec.yaml`'s `flutter.assets:` list (Plan 01-01).

## Next Phase Readiness

Plan 02-02 closes MAP-01. Wave 2 siblings (02-03 GeolocatorService + BlueDot, 02-04 RecenterFab + MapCompass) are unblocked by Plan 02-01's stubs and run in parallel; they do not depend on this plan's output. Plan 02-05 (MapScreen wiring) DOES depend on this plan — it expects the PMTiles file to exist on disk by the time `MapScreen.fromServices(services)` is mounted, which is now guaranteed by the gate-screen pre-navigation copy.

---
*Phase: 02-map-no-fog*
*Plan: 02 (MAP-01 — PMTiles asset copy + permission-gate wiring)*
*Completed: 2026-05-01*
