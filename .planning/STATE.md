---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: in-progress
last_activity_summary: Plans 02-02 + 02-03 + 02-04 closed (Wave 2 complete); Plan 02-05 (MapScreen wiring) unblocked
stopped_at: Completed 02-04-PLAN.md (LOC-04 + LOC-05; RecenterFab + MapCompass)
last_updated: "2026-05-01T10:01:39.897Z"
last_activity: 2026-05-01 — Plan 02-04 complete (LOC-04 + LOC-05; RecenterFab + MapCompass; 18 GREEN tests)
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 13
  completed_plans: 11
  percent: 85
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-30)

**Core value:** The fog-of-war stays perfectly locked to the map during pan, zoom, and combined gestures on a sideloaded iOS build.
**Current focus:** Phase 1 — Foundation **CLOSED**. Phase 2 (Map, no fog) unblocked.

## Current Position

Phase: 2 of 5 (Map, no fog) — **IN PROGRESS**
Plan: 4 of 6 in current phase — **COMPLETE** (LOC-04 + LOC-05; RecenterFab + MapCompass)
Status: Plans 02-02 + 02-03 + 02-04 closed (Wave 2 fully complete); Plan 02-05 (MapScreen wiring) unblocked
Last activity: 2026-05-01 — Plan 02-04 complete (LOC-04 + LOC-05; RecenterFab + MapCompass; 18 GREEN tests)

Progress: [█████████░] 85% (11 of 13 plans complete; Phase 1 closed, Phase 2 4/6)

## Performance Metrics

**Velocity:**
- Total Phase 1 plans completed: 7 of 7
- Average duration (excluding Plan 07 sideload-UAT cycle): ~10 min/plan
- Total Phase 1 execution time: ~5h (including the 4h Plan 07 cycle)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation | 7/7 | ~5h | ~43 min/plan (Plan 07 dominates due to sideload UAT cycle) |

**Recent Trend:**
- Last 5 plans: P03 (30 min), P04 (4 min), P05 (5 min), P06 (10 min), P07 (~4h with sideload UAT)
- Trend: short for software-only plans (4-10 min), long for plans with manual UAT (P03 30 min for CI workflow round-trip; P07 ~4h for full sideload + 16-step walk)

*Updated after each plan completion*
| Phase 01-foundation P04 | 4 min | 2 tasks | 5 files |
| Phase 01-foundation P02 | 9 min | 3 tasks | 10 files |
| Phase 01-foundation P03 | 30 min | 3 tasks | 9 files |
| Phase 01 P01 | 7 min | 3 tasks | 12 files |
| Phase 01-foundation P05 | 5 min | 2 tasks | 4 files |
| Phase 01-foundation P06 | 10 min | 2 tasks | 4 files |
| Phase 01-foundation P07 | ~4h | 2 tasks (1 auto + 1 checkpoint:human-verify) | 11 files (4 created + 2 sideload-prep + 1 docs + 4 modified) |
| Phase 02-map-no-fog P01 | 59 min | 3 tasks | 21 files (16 created + 5 modified) |
| Phase 02-map-no-fog P03 | 4 min | 2 tasks | 4 files |
| Phase 02-map-no-fog P02 | 5 min | 2 tasks | 5 files |
| Phase 02-map-no-fog P04 | 8 min | 2 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmapping: Stack locked to `flutter_map 7.0.2` + `vector_map_tiles 8.0.0` + `vector_map_tiles_pmtiles 1.5.0` (only resolvable chain); state mgmt = plain `StatefulWidget` + `setState` + constructor-injected services; iOS-primary on iPhone 17 Pro (ProMotion 120 Hz), Pixel 4a only at Phase 3 + Phase 5.
- Roadmapping: Falsification Criterion C (parent-FPS comparison) DROPPED — POC stands on absolute FPS + lock-correctness alone.
- Roadmapping: 5-phase structure under coarse granularity; Bootstrap + CI + logger + share + FPS counter + permission gate folded into a single walkable Phase 1 ("install → permission screen → share logs").
- Roadmapping: Phase 2 PERF-02 (≥ 40 fps no-fog on iPhone 17 Pro) is the hard gate before Phase 3 fog work begins; failing it forces label-thinning before the hypothesis is testable.
- [Phase 01-foundation]: Plan 01-04: ported FileLogger verbatim with three POC adaptations (UTC ISO-8601 basic filename, hardcoded Level.ALL, shared_preferences dropped). Every other line preserved from parent — RandomAccessFile + flushSync per record, synchronous Stream.listen handler. ~14 tests authored across 3 files. — Production-fatal subsystem — parent's logger is the result of debugging two iOS-fatal bugs (jetsam page-cache loss, Stream.listen re-entrancy). Re-implementing from scratch would re-introduce both. Tests cover bootstrap, level, ms precision, idempotency, prune, FileSystemException handling (static-source assertion per W-4), UTC format, and lifecycle flush behaviour.
- [Phase 01-foundation]: Plan 01-02: ported tool/* CI gates verbatim from parent project (header/license/deps-md), authored DEPENDENCIES.md telemetry table, rewrote ios/Runner/Info.plist with whenInUse-only location + ITSAppUsesNonExemptEncryption=false, created PrivacyInfo.xcprivacy with Required Reason API declarations
- [Phase 01-foundation]: Plan 01-03: hand-rolled MirkViewportBbox replaces freezed-generated parent class; package:mirkfall imports rewritten to package:mirk_poc_debug; CI workflow lands at Wave 0 (red-then-green until Plan 07 hardens main.dart). — POC pubspec drops freezed per RESEARCH.md §Standard Stack §NOT included; preserving each donor file's import-style minimises diff for future verbatim re-syncs from parent; landing CI at Wave 0 lets Plan 07 see immediately whether gates job goes green on the first push.
- [Phase 01-foundation]: Plan 01-01: adopted existing Flutter scaffold instead of running flutter create (Rule 3 deviation — scaffold from prior session matched user-approved bundle ID com.thongvan.mirkPocDebug). Strict-pinned Path A pubspec.yaml committed with test: 1.30.0 added per Plan 01-02 coordination flag. Constants port: 30 of parent's 880 constants — only what Phase 1 + BOOT-08 donor files reference. Asset bundle test for shader uses IPLR magic-byte verification (not loadString) because Flutter's shaders: block compiles to binary at build time. — scaffold-adoption avoids overwriting Plan 01-02 parallel work; test 1.30.0 enables Plan 01-02 tool tests; constants subset prevents Phase 2+ dead code; IPLR-aware test mirrors the runtime FragmentProgram.fromAsset idiom
- [Phase 01-foundation]: Plan 01-05: buildPocAppBar PreferredSizeWidget factory + FpsCounterOverlay StatefulWidget landed (LOG-04 + PERF-01). 9 widget tests green, strict analyze clean, GOSL headers verified. Three Rule 1 deviations: (1) SharePlus.instance.share(ShareParams) replaces deprecated Share.shareXFiles in share_plus 12.0.2; (2) dropped unnecessary dart:ui FontFeature import; (3) AppLocalizations import via package:mirk_poc_debug/l10n (Plan 01-01 deferred-items pre-flagged this).
- [Phase 01-foundation]: Plan 01-06: PermissionGateScreen (StatefulWidget + WidgetsBindingObserver lifecycle re-check — W-2 fix) + PermissionDeniedScreen (Stateless single Open-Settings) landed (AUTH-01..04). 11 widget tests green; strict analyze clean on lib/presentation + test/presentation. Pattern established: tester.binding.handleAppLifecycleStateChanged + mid-test mock mutation simulates the post-Settings round-trip without a real iOS device. PermissionHandlerPlatform.instance test seam reused as the zero-dep mock pattern. — Lifecycle re-check is THE differentiator vs. cold-restart UX; per CONTEXT.md user must NOT need to re-open the app to escape the denied screen. Single suppression `// ignore_for_file: depend_on_referenced_packages` on test files (transitive permission_handler_platform_interface) follows Plan 01-04 pattern; production lib carries no suppressions.
- [Phase 01-foundation]: Plan 01-07: lib/main.dart bootstrap (LOG-03 ordering: WidgetsFlutterBinding.ensureInitialized → await FileLogger.bootstrap → addObserver(FileLoggerLifecycleObserver) → FlutterError.onError → runZonedGuarded(runApp(MirkPocApp))) + lib/app.dart MirkPocApp + lib/presentation/router.dart 3-route GoRouter (all context.go) + lib/presentation/screens/map_screen.dart placeholder all landed. CI green on `main` (gates+android+ios), both APK+IPA artifacts downloadable. iPhone 17 Pro sideload UAT: verbal `approved` — LOG-05 (Mail round-trip with valid JSONL log) ✓, PERF-01 (FPS counter `<value> fps / 120 Hz` ProMotion-aware) ✓, AUDIT-03 (DEPENDENCIES.md zero `Yes/automatic` rows) ✓; AUTH-04 round-trip marked complete-with-known-limitation (cold-restart-from-/denied auto-nav routing bug deferred per user's POC-scope call). 8 deviations: 6 during Task 1 (l10n import correction, deferred-items analyze gates resolved, Windows file_logger_test fix, CI gate scripts against POC dep graph, CI pre-format gen-l10n, remote main bootstrap merge); 2 sideload-time fixes (CFBundleName mirk_poc_debug → MirkPocDebug for SideStore re-sign per docs/flutter-ios-specifics.md §2; ios/Podfile committed with PERMISSION_LOCATION=1 macro per §1). New 744-line `docs/flutter-ios-specifics.md` captures all recurring iOS Flutter recipes (Podfile macros, CFBundleName, FileLogger anatomy, gen-l10n CI gotcha, location 2-step pattern with auto-resume hook) for future projects.
- [Phase 02-map-no-fog]: Plan 02-01: Wave 0 scaffold landed — 16 new files (7 production stubs + 9 RED test files) + 5 file edits (constants, l10n EN/FR, router /error route, MapScreen.fromServices stub). MapScreenServices immutable DTO (lib/domain/map/map_screen_services.dart) is the constructor-injection seam; ErrorScreen is the only fully-implemented Phase 2 production widget. 19 new constants (camera/zoom/pan envelope, animation timing, GPS distanceFilter, PMTiles paths, blue-dot spec). 5 new l10n keys (recenterTooltip, compassTooltip, errorScreenTitle/Body/DetailLabel) in EN + FR. LOC-03 static-source CI gate auto-discovered by existing `dart test tool/test/` step. flutter analyze clean across lib/test/tool. flutter test (30s/test): 48 passed (Phase 1 untouched + 1 trivial mounted-guard) / 27 RED Phase 2 assertions / 0 hangs. 2 deviations (Rule 3 — Blocking: MapScreen.fromServices named-constructor stub added so screen tests compile; Rule 1 — Bug: replaced synthetic temp-file pmtilesPath with literal placeholder string after first test run hung the suite for 10 min on vector_map_tiles parsing of empty file). Plan 02-02 (MAP-01 PMTiles copier impl + permission-gate wiring + @visibleForTesting testOverride seam) unblocked.
- [Phase 02-map-no-fog]: Plan 02-03: GeolocatorService.stream() with pinned LocationSettings(accuracy: best, distanceFilter: 5) + Logger('domain.location') INFO emission. BlueDotMarker.build returns CircleMarker(7 px / #2B7CD6 / 2 px white stroke / pixels-not-metres) — every value sourced from kPocBlueDot* constants. LOC-03 static-source CI gate hardened to strip Dart // /// /* */ comments before substring scan, so the educational 'do NOT call `Geolocator.getLastKnownPosition`' docstring is preserved without false-positiving. Test seam: hand-rolled _CapturingGeolocatorPlatform fake (mirrors Phase 1 PermissionHandlerPlatform.instance pattern), zero new dev_dependencies. 2 deviations (Rule 3 - Blocking: comment-aware gate fix; Rule 3 - Blocking: wave-2 race amend to remove sibling's recenter_fab_test.dart from my Task 2 commit).
- [Phase 02-map-no-fog]: Plan 02-02: MAP-01 PMTiles copy fully implemented + hooked into both grant paths of PermissionGateScreen. Idempotency = existence + size-parity (no SHA256 per ROB-02 deferral). @visibleForTesting testEnsureCopiedOverride seam keeps gate-screen widget tests off the real filesystem. Both _onCtaPressed (CTA grant) and _checkAndMaybeNavigate (initState + AppLifecycleState.resumed) converge through a single _ensureMapDataAndNavigate helper per CONTEXT.md mandate. FileSystemException routes to /error with extra==e.message. 5 PMTiles tests + 3 MAP-01 widget tests + 6 Phase 1 regression tests all GREEN; flutter analyze + LOC-03 + BOOT-02 CI gates clean. 0 deviations.
- [Phase 02-map-no-fog]: Plan 02-04: RecenterFab (LOC-04 + LOC-05) + MapCompass landed. Hand-rolled AnimationController + CurvedAnimation listener pattern for both widgets — no flutter_map_animations dependency added. Top-level mapCompassShortestPathToNorth(double) helper exposes the formula ((-current + 540) % 360) - 180 and pins RESEARCH Open Question #2 with 6 unit tests (350°→+10°, 10°→-10°, 180°→±180°, 270°→+90°, etc.). MapEventRotate plumbing: production reads event.camera.rotation (degrees), test fake constructs real MapCamera(crs: const Epsg3857(), nonRotatedSize: kImpossibleSize, rotation: degrees). 18 GREEN tests (6 RecenterFab widget + 6 MapCompass widget + 6 helper unit). 3 deviations: 1 parallel-sibling git-state recovery (Task 1 RED commit absorbed into GREEN), 2 Wave-0 RED-test bug fixes (MapEventRotate noSuchMethod fake → real constructor; cancels-on-dispose baseline capture moved post-pumpAndSettle).

### Pending Todos

[From .planning/todos/pending/ — ideas captured during sessions]

None yet.

### Blockers/Concerns

[Issues that affect future work]

- Phase 2 vector-tile FPS on iOS at zoom 13–15 has no published numbers; the Phase 2 walk IS the research, and is the highest-probability project-blocking risk.
- AUTH-04 cross-restart auto-resume routing bug (deferred per Plan 01-07 SUMMARY + deferred-items.md). Not blocking Phase 1 closure (POC scope; revoking GPS perms during a GPS-needed POC is artificial). May resurface if a downstream phase exercises the cross-restart re-grant flow.

## Session Continuity

Last session: 2026-05-01T10:00:53.100Z
Stopped at: Completed 02-04-PLAN.md (LOC-04 + LOC-05; RecenterFab + MapCompass)
Resume file: None
