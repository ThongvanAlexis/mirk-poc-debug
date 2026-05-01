---
phase: 03-fog-of-war-the-hypothesis
plan: 07
subsystem: ui
tags: [flutter, integration, fog-of-war, fragment-shader, gps, custom-paint, map-screen, dependency-injection]

# Dependency graph
requires:
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 03-01 keystone — MapScreenServices DTO, /map + /sanity routes, Phase 3 constants block"
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 03-02 RevealDiscRepository (FOG-01 in-memory append)"
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 03-03 SdfCache + SdfRebuildLogger"
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 03-04 FrameDeltaProbe (FOG-08 lifecycle + 1 Hz rollups)"
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 03-05 FogLayer (FOG-04..07 same-Canvas + FOG-08 wire)"
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 03-06 FrameDeltaProbeOverlay (FOG-08 user-facing)"
  - phase: 03-fog-of-war-the-hypothesis
    provides: "Plan 01-03 BOOT-08 donor — RevealDisc class + atmospheric_fog.frag asset"
provides:
  - "MapScreen body composes Phase 3 surfaces — FogLayer mounted as a CHILD of FlutterMap (FOG-04 same-Canvas), FrameDeltaProbeOverlay positioned at top:104 right:8 under the FPS+compass cluster, GPS-fix → discRepository.append on every fix"
  - "Hand-rolled disc ID format `rvd_<microsSinceEpoch>_<randomU32>_<counter>` — replaces ulid dep per RESEARCH §Open Question 4"
  - "Frame-delta probe + SDF cache + SDF rebuild logger lifecycle owned by MapScreen.initState/dispose"
  - "fogProgramLoaderOverride MapScreenServices field — test seam isolating ui.FragmentProgram.fromAsset from headless test runners (mirrors Plan 03-06 ShaderSanityScreen.programLoaderOverride pattern)"
  - "In-body teardown discipline for stream + probe disposal (deterministic alternative to addTearDown for tests with broadcast StreamController + cancelled overlay listeners)"
affects: ["03-08-walk-IPA-+-falsification"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Async shader load via unawaited(Future) in initState; setState on completion; FogLayer mount gated on _fogShader != null && _sdfCache != null"
    - "Test seam pattern reused: optional Future<ui.FragmentProgram> Function()? loader override on the services DTO (production = null = real fromAsset)"
    - "Fire-and-forget probe.dispose() in synchronous void dispose (Stopwatch-cancel happens sync; Future-returning controller.close() runs concurrently)"
    - "Hand-rolled monotonic-counter disc ID generation (zero-dep ULID-equivalent for in-process uniqueness during a 5-min walk)"
    - "FlutterMap children-list ordering = z-order: tiles → fog → blue dot (FOG-04 keystone, locked by CONTEXT.md)"

key-files:
  created: []
  modified:
    - "lib/presentation/screens/map_screen.dart — Phase 2 placeholder → full Phase 2+3 integration (~280 lines, +85 net). New fields: _fogShader, _sdfCache, _sdfRebuildLogger, _discCounter, _random. New initState steps (probe.start, sdfRebuildLogger.start, sdfCache new, _loadFogShader). New dispose steps (sdfCache.dispose, sdfRebuildLogger.stop, probe.dispose unawaited). _subscribeToPositions extended with discRepository.append on every fix. build() Stack adds FrameDeltaProbeOverlay at top:104 right:8; FlutterMap children list adds FogLayer between tile + blue-dot."
    - "lib/domain/map/map_screen_services.dart — added optional fogProgramLoaderOverride field (FOG-04 test seam)"
    - "test/presentation/screens/map_screen_fog_test.dart — Plan 03-01 sketch (2 skipped placeholders) → 3 GREEN behavioural tests (FOG-01 disc-append-per-fix, FOG-08 overlay-Stack-position, post-dispose-no-op safety). In-body teardown discipline pinned by deviation note."
    - "test/presentation/screens/map_screen_test.dart — added fogProgramLoaderOverride to _services helper so all 9 Phase 2 screen tests survive the new MapScreen wiring without hanging on the platform shader compiler."
    - "test/presentation/screens/map_screen_gps_test.dart — same fogProgramLoaderOverride threading for the 4 GPS-lifecycle tests."

key-decisions:
  - "Hand-rolled disc ID format `rvd_<microsSinceEpoch>_<randomU32>_<counter>` (RESEARCH §Open Question 4 — no ulid dep). Triple of (micros, u32 random, monotonic per-screen counter) makes within-process collision impossible during a 5-min walk."
  - "fogProgramLoaderOverride DTO field rather than top-level test-only override or @visibleForTesting setter. Mirrors Plan 03-06 ShaderSanityScreen.programLoaderOverride; production callers leave null and pick up the real ui.FragmentProgram.fromAsset(kPocFogShaderAssetPath). Constructor injection keeps DI explicit per CLAUDE.md."
  - "Graceful degradation on shader load failure: catch + log severe, leave _fogShader null, FogLayer never mounts. The pre-walk /sanity smoke test (Plan 03-06) + Plan 03-08 falsification gate prevent shipping a broken IPA, so a runtime fallback is acceptable for the POC."
  - "In-body teardown for tests touching the FrameDeltaProbe broadcast StreamController. The await emitter.close() / await probe.dispose() pattern in addTearDown occasionally hangs flutter_test for 10 minutes when a now-cancelled overlay subscription is in-flight; awaiting close() inside the body after pumpWidget(SizedBox) is deterministic."
  - "MapScreen.dispose remains synchronous void per Flutter contract; probe.dispose's Future is fire-and-forget via unawaited(). The probe's stop() (timer cancel) runs synchronously inside the unawaited body so timer cleanup is immediate; only the controller.close() awaits."
  - "FogLayer mount gating on `_fogShader != null && _sdfCache != null`. The sdfCache check is technically redundant (it's set in initState before the first build) but defends against a future refactor that delays cache construction."
  - "FlutterMap children list ordering carved into stone per CONTEXT.md: VectorTileLayer → FogLayer → CircleLayer<blue dot>. Future contributors who want to reorder MUST first revisit the FOG-04 same-Canvas keystone."
  - "kPocPlaceholderSessionId = 'poc' constant — every disc carries this literal so RevealDisc.mergeWith() asserts cleanly during any future compaction work and so post-walk JSONL grep can filter on the POC tag."

patterns-established:
  - "Production-assembly screen pattern: route builder constructs all in-memory singletons (RevealDiscRepository, FrameDeltaProbe) and threads them through a services DTO. Screen owns lifecycle (start in initState, dispose in dispose); router doesn't touch lifecycle."
  - "Hand-rolled monotonic-counter ID: combines DateTime.now().microsecondsSinceEpoch + Random().nextInt(1<<32) + per-instance counter; format `prefix_us_random_counter`. Zero deps; collision-free for in-process use within a 5-min session."
  - "Test seam published on the services DTO (not the screen): keeps screen API minimal, lets test-wiring + production-wiring share one constructor."

requirements-completed: [FOG-01, FOG-04, FOG-08]

# Metrics
duration: 90min
completed: 2026-05-01
---

# Phase 3 Plan 7: MapScreen × Phase 3 Integration Summary

**The MapScreen now ships every Phase 3 surface integrated: every GPS fix appends a 25 m RevealDisc (FOG-01); FogLayer mounts as a child of the same FlutterMap as the tile layer (FOG-04 same-Canvas); FrameDeltaProbeOverlay sits at top:104 right:8 under the FPS+compass cluster (FOG-08); FrameDeltaProbe + SdfCache + SdfRebuildLogger lifecycles are owned by MapScreen.initState/dispose; an async shader load gates FogLayer mounting with graceful fallback to no-fog on failure.**

## Performance

- **Duration:** ~90 min (start 2026-05-01T15:34:14Z, end 2026-05-01T17:03:44Z)
- **Tasks:** 2 (Task 1 = `tdd="true"` MapScreen wiring; Task 2 = router verification, no code change)
- **Files modified:** 5 (1 production screen + 1 services DTO + 3 tests)
- **Net production lines added:** ~85 (MapScreen 195 → 280, services DTO 65 → 90)
- **Test count delta:** +3 fog tests GREEN (was 2 skipped placeholders), 13 Phase 2 tests still GREEN (after threading the override), full suite **126 GREEN / 0 RED / 0 SKIPPED**

## Accomplishments

- **MapScreen × Phase 3 wiring lands.** The Phase 2 placeholder grew into the production assembly point: every GPS fix appends a 25 m disc (FOG-01); the FogLayer mounts inside the FlutterMap children list between the tile layer and the blue dot (FOG-04 same-Canvas keystone); the FrameDeltaProbeOverlay shows the live HUD at top:104 right:8 (FOG-08).
- **Async shader load with graceful fallback.** `_loadFogShader()` calls `ui.FragmentProgram.fromAsset(kPocFogShaderAssetPath)` via `unawaited()` in initState. On success, `setState` flips `_fogShader` and the FogLayer enters the tree on the next build. On failure (asset missing, malformed bytecode, sideload not finished), the catch logs `severe`, `_fogShader` stays null, and the user sees a no-fog map — falsification still happens via the pre-walk /sanity gate (Plan 03-06) + Plan 03-08 sideload UAT.
- **Lifecycle ownership shifted to MapScreen.** `FrameDeltaProbe.start()` + `SdfRebuildLogger.start()` in initState; `_sdfCache?.dispose()`, `_sdfRebuildLogger?.stop()`, `unawaited(widget.services.frameDeltaProbe.dispose())` in dispose. The router builder is now stateless beyond the FutureBuilder — it constructs the services DTO and forgets.
- **`fogProgramLoaderOverride` test seam published on `MapScreenServices`.** Same constructor-injection pattern as Plan 03-06's `ShaderSanityScreen.programLoaderOverride`. Production wiring leaves it null; widget tests pass a `Completer<ui.FragmentProgram>().future` to keep the load pending. The real platform shader compiler hangs in headless `flutter test`, which would have hung the suite for 10 min per test before this seam landed (and did, during early TDD iteration).
- **Plan 03-01 sketch tests in `map_screen_fog_test.dart` flipped from RED to GREEN.** All 3 behavioural assertions land:
  - FOG-01 disc append per fix with `kPocRevealDiscRadiusMeters` + UTC `fixedAtUtc` + unique ID per fix
  - FOG-08 overlay mounted at the documented Stack position (top:`kPocFrameDeltaProbeOverlayTopPx`, right:`kPocFrameDeltaProbeOverlayRightPx`)
  - Post-dispose fix is a no-op (subscription cancelled in dispose)
- **Phase 2 regression survives the integration.** All 9 `map_screen_test.dart` tests + 4 `map_screen_gps_test.dart` tests + every other Phase 1+2 test still GREEN. No surface broken by the integration.

## Task Commits

Each TDD step was committed atomically:

1. **Task 1 RED — failing FOG-01 + FOG-08 tests** — `256447e`
2. **Task 1 GREEN — MapScreen Phase 3 wiring + services DTO override + Phase 2 test re-threading** — `43ca0b4`

Task 2 (router verification): no code change required — the `_buildMapRoute` builder already constructs production `RevealDiscRepository()` + `FrameDeltaProbe()` (Plan 03-01 keystone), and now those constructors point at the implementations from Plans 03-02 + 03-04 (no longer stubs). Verified via `flutter analyze --fatal-infos lib/presentation/router.dart` clean + 9 permission-gate tests still GREEN.

**Plan metadata commit:** `0173b15` (`docs(03-07): complete MapScreen × Phase 3 integration plan` — SUMMARY.md, STATE.md, ROADMAP.md, REQUIREMENTS.md)

## Files Created/Modified

- `lib/presentation/screens/map_screen.dart` — **Modified** (full Phase 2 placeholder rewritten as Phase 2+3 production assembly point). New imports: `dart:math` (Random for disc IDs), `dart:ui as ui` (FragmentProgram/FragmentShader), Plan 03-02 (RevealDisc), Plan 03-03 (SdfCache + SdfRebuildLogger), Plan 03-05 (FogLayer), Plan 03-06 (FrameDeltaProbeOverlay). New fields: `_fogShader`, `_sdfCache`, `_sdfRebuildLogger`, `_discCounter`, `_random`. New methods: `_loadFogShader()`, `_handRolledDiscId()`. `_subscribeToPositions` extended with disc-append on every fix. `dispose()` extended with sdfCache + sdfRebuildLogger + probe cleanup. `build()` Stack adds `FrameDeltaProbeOverlay` Positioned; `FlutterMap.children` adds conditional `FogLayer` between tile + blue-dot.
- `lib/domain/map/map_screen_services.dart` — **Modified** (added `fogProgramLoaderOverride` field — optional `Future<ui.FragmentProgram> Function()?`). Production wiring leaves null; tests inject a `Completer`-backed loader. DTO docstring updated to reflect 6 fields.
- `test/presentation/screens/map_screen_fog_test.dart` — **Modified** (Plan 03-01 sketch with 2 `skip: true` placeholders → 3 GREEN behavioural tests). Uses `_pendingFogProgram()` helper returning `Completer().future`. In-body teardown discipline (`emitter.close()` + `probe.dispose()` awaited after `pumpWidget(SizedBox)`) per top-of-file deviation note.
- `test/presentation/screens/map_screen_test.dart` — **Modified** (added `dart:ui` import + `_pendingFogProgram` helper + threaded `fogProgramLoaderOverride: _pendingFogProgram` into the `_services()` builder). All 9 existing Phase 2 tests survive without further changes.
- `test/presentation/screens/map_screen_gps_test.dart` — **Modified** (same threading as `map_screen_test.dart`). All 4 GPS lifecycle tests still GREEN.

## Decisions Made

- **Hand-rolled disc ID format** — `rvd_<microsSinceEpoch>_<randomU32>_<counter>` per RESEARCH §Open Question 4. The triple (timestamp + Random.nextInt(1 << 32) + monotonic per-screen counter) makes within-process collision impossible during the 5-min walk (~50 fixes). Zero new deps. The counter alone is sufficient for uniqueness; the timestamp + random are defence-in-depth for cross-restart.
- **fogProgramLoaderOverride on MapScreenServices** — same pattern as ShaderSanityScreen.programLoaderOverride; production callers leave null. The override lives on the DTO (not the screen) so test wiring + production wiring share one constructor and one DTO field — keeps the screen's surface area unchanged from a caller's POV.
- **Graceful no-fog fallback on shader load failure** — catch + `_log.severe(...)` + leave `_fogShader` null. Acceptable POC fallback because the pre-walk /sanity smoke test catches a broken shader before sideload — the user never sees this fallback in a healthy setup. Alternatives considered: `runtimeAssertion` style (crashes app — rejected, hostile UX); modal error dialog (rejected — out of scope, the user has /sanity for that). Chosen: graceful + logged.
- **FrameDeltaProbe.dispose() fire-and-forget in MapScreen.dispose** — matches existing Phase 2 pattern for `_positionSubscription?.cancel()` + `_tileProvider?.archive.close()`. The probe's `stop()` (timer cancel) is synchronous and runs inside the `unawaited()` body before the await yields, so timer cleanup is immediate; only the StreamController.close() awaits and does so off the main path.
- **kPocPlaceholderSessionId = 'poc' constant** — every disc carries this literal so (a) `RevealDisc.mergeWith()` assertion holds during any future compaction work, (b) post-walk JSONL grep can filter on the POC tag, (c) Plan 04+ can rename this to a real session ID without surgery throughout MapScreen.
- **In-body teardown for fog-test stream + probe disposal** — `addTearDown(() async => probe.dispose())` runs AFTER body completes. The probe's broadcast StreamController.close() future occasionally fails to resolve when an FrameDeltaProbeOverlay subscription is mid-cancel (the overlay's `cancel()` returns a Future that the void dispose doesn't await). Awaiting close() in the body, AFTER `pumpWidget(SizedBox)` has run MapScreen.dispose synchronously, makes the cleanup deterministic. See top-of-file deviation note in `map_screen_fog_test.dart` for the full rationale.
- **FogLayer mount gating** — `_fogShader != null && _sdfCache != null`. The sdfCache check is currently redundant (set in initState before first build) but defends against a future refactor that delays cache construction. Cheap belt-and-braces.
- **No `flutter pub` dependency change** — verified DEPENDENCIES.md needs no audit. All new imports point at first-party Dart SDK or already-audited packages.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] FragmentProgram.fromAsset hangs the headless test runner**
- **Found during:** Task 1 GREEN — first `flutter test test/presentation/screens/map_screen_fog_test.dart` run (10-min timeout per test, then the next test hits `assert(!inTest)` because the prior test left the binding mid-flight)
- **Issue:** The plan's `_loadFogShader()` calls `ui.FragmentProgram.fromAsset(kPocFogShaderAssetPath)` directly. In `flutter test`, no shader compiler is available; the future never completes. The unawaited call's pending future stays in the test zone and the binding's pending-microtask check hangs the test for the full 10-min default timeout. This is the same constraint Plan 03-06 documented for `ShaderSanityScreen` — the plan failed to anticipate that MapScreen has the same headless-runner problem.
- **Fix:** Added `fogProgramLoaderOverride` field to `MapScreenServices` (optional `Future<ui.FragmentProgram> Function()?`). Production wiring (router) leaves null and falls back to `ui.FragmentProgram.fromAsset(...)`. Tests inject `() => Completer<ui.FragmentProgram>().future` so the loader stays pending under test control. Mirrors the pattern Plan 03-06 already published.
- **Files modified:** `lib/domain/map/map_screen_services.dart` (added field), `lib/presentation/screens/map_screen.dart` (use override or fall back to fromAsset), `test/presentation/screens/map_screen_test.dart` + `map_screen_gps_test.dart` (thread override through `_services()` helper), `test/presentation/screens/map_screen_fog_test.dart` (use `_pendingFogProgram()`)
- **Verification:** all 126 tests GREEN; `flutter analyze` clean; `dart format` clean
- **Committed in:** `43ca0b4` (Task 1 GREEN commit)

**2. [Rule 3 — Blocking] In-body teardown discipline replaces addTearDown for stream + probe**
- **Found during:** Task 1 GREEN — second `flutter test` run, even with the program-loader override in place
- **Issue:** `addTearDown(() async => probe.dispose())` + `addTearDown(emitter.close)` ran AFTER the test body. The FrameDeltaProbe's broadcast StreamController.close() future occasionally hangs the test scheduler for 10 minutes when a now-cancelled FrameDeltaProbeOverlay subscription is in-flight. Diagnostic test isolated this: same code with `await probe.dispose()` + `await emitter.close()` IN BODY (after `pumpWidget(SizedBox)`) finishes in <1 s; same code with addTearDown hangs.
- **Fix:** Moved `await emitter.close()` + `await probe.dispose()` from `addTearDown` callbacks into the body, AFTER the `pumpWidget(SizedBox); pump();` pair that runs MapScreen.dispose synchronously. Documented the rationale in a top-of-file comment so future executors don't "fix" the test back into the hang.
- **Files modified:** `test/presentation/screens/map_screen_fog_test.dart`
- **Verification:** all 3 fog tests pass in <0.5 s each
- **Committed in:** `43ca0b4` (Task 1 GREEN commit)

**3. [Rule 1 — Bug] dart format reflowed a multi-line `find.byWidgetPredicate` call**
- **Found during:** post-Task-1 `dart format --line-length 160 --set-exit-if-changed` run
- **Issue:** my hand-formatted multi-line predicate fit on one line at 160 chars; `dart format` collapsed it.
- **Fix:** accepted the formatter's reflow; no semantic change.
- **Files modified:** `test/presentation/screens/map_screen_fog_test.dart`
- **Verification:** `dart format --set-exit-if-changed` clean
- **Committed in:** none separately — already part of `43ca0b4` after the formatter ran (re-staged before commit).

### Out-of-scope deferrals

- The plan called for an `addTearDown(() async => probe.dispose())` pattern for the fog tests. This pattern is now contraindicated by deviation #2 above — the in-body teardown discipline supersedes it. The Phase 2 `map_screen_test.dart` + `map_screen_gps_test.dart` files keep using `addTearDown` because their FrameDeltaProbe instances never have an FrameDeltaProbeOverlay subscriber (those tests don't emit on the probe stream and don't trigger the cancel-in-flight path that hangs). Honouring scope — Phase 2 test re-write would be churn beyond the plan's contract.

---

**Total deviations:** 3 auto-fixed (1 blocking-program-loader, 1 blocking-teardown-discipline, 1 dart-format-reflow) + 1 out-of-scope deferral (addTearDown contract for Phase 2 tests)
**Impact on plan:** All auto-fixes preserve the plan's intent — every behavioural assertion the plan called for is GREEN. The blocking fixes also EXTEND the test-seam pattern Plan 03-06 published, so future shader-backed widgets get the same DI hook for free.

## Issues Encountered

- **The platform shader compiler hangs flutter test.** Already-known constraint per Plan 03-06's ShaderSanityScreen, but Plan 03-07's plan didn't anticipate that MapScreen would re-encounter it. Resolution: same Completer-based pattern via the new `fogProgramLoaderOverride` DTO field.
- **flutter_test addTearDown + broadcast StreamController close = occasional 10-min hang.** Reproducible on Windows under flutter_test 3.41 + dart:async 3.41 with a FrameDeltaProbeOverlay subscription that was cancelled mid-build via pumpWidget(SizedBox). Fixed by moving teardown into the body (deterministic).
- **The plan's `flutter test test/presentation/screens/ -r expanded` verify command was run repeatedly during early iteration.** Each hung 10+ minutes before being killed, slowing the TDD cycle. Once the program-loader override + in-body teardown were in place, the entire screen suite runs in ~7 s.

## User Setup Required

None — no external service configuration required. The fog shader asset is already bundled (Phase 1); the `kPocFogShaderAssetPath` constant points at it; the production load path uses `ui.FragmentProgram.fromAsset` unchanged.

## Next Phase Readiness

- **Plan 03-08 (sideload UAT walk per CONTEXT.md falsification criteria A + B) unblocked.** The IPA built from `main` after THIS plan ships is the artefact the developer sideloads on iPhone 17 Pro. Required pre-walk steps before Plan 03-08 begins:
  - CI must succeed for the final 03-07 metadata commit (gates + android + ios jobs all green) — confirms the IPA artefact is downloadable
  - On-device pre-walk smoke: tap the science icon in AppBar → /sanity loads → confirm atmospheric fog with central reveal hole renders without errors → if green, proceed to walk; if red, abort and bug-investigate
- **Plan 03-08 falsification gate is now mechanically verifiable.** The walker reads three values during the walk: (a) FpsCounterOverlay (Phase 1) for top-line fps, (b) FrameDeltaProbeOverlay median/p95/max for camera-to-paint delta against the Criterion A thresholds, (c) visual lock between fog edge and tile features (Criterion B). All three are now wired into the sideloaded build.
- **No new blockers introduced.** Two latent risks for Plan 03-08:
  - **120 Hz device fps headroom** — Phase 2 verbal `approved` confirmed ~120 fps no-fog at z13–z15 in Melun; Plan 03-08 will measure with-fog. If with-fog drops below 40 fps the hypothesis is falsified per CONTEXT.md.
  - **Lock correctness during combined gestures** — the FOG-04 same-Canvas + FOG-07 single-MapCamera-snapshot + FOG-08 frame-delta evidence all reduce the BUG-014-equivalent risk, but only the on-device walk proves it.

---
*Phase: 03-fog-of-war-the-hypothesis*
*Plan: 07*
*Completed: 2026-05-01*

## Self-Check: PASSED

- All 5 modified files present on disk (`map_screen.dart`, `map_screen_services.dart`, `map_screen_fog_test.dart`, `map_screen_test.dart`, `map_screen_gps_test.dart`)
- All 2 task commits present in git log (`256447e` RED, `43ca0b4` GREEN)
- `flutter test` 126 GREEN / 0 SKIPPED / 0 RED on the full suite
- `flutter analyze --fatal-infos lib/ test/` clean
- `dart format --line-length 160 --set-exit-if-changed` clean on all 5 modified files
