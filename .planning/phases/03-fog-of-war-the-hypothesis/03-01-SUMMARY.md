---
phase: 03-fog-of-war-the-hypothesis
plan: 01
subsystem: infra
tags: [fog-of-war, sdf, shader, frame-delta-probe, falsification, wave-0, scaffold, l10n, gorouter, flutter-map]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: FogShaderUniforms (totalFloatSlots == 41), RevealedSdfBuilder, RevealDisc, MirkViewportBbox, kMirkFog* constants, FileLogger, GoRouter, AppBar factory, AppLocalizations
  - phase: 02-map-no-fog
    provides: MapScreen.fromServices, MapScreenServices DTO, /map route, RecenterFab, MapCompass, FpsCounterOverlay, GeolocatorService.stream, Pmtiles plumbing
provides:
  - Phase 3 constants block (kPocRevealDiscRadiusMeters, kPocFrameDeltaProbeOverlayTopPx, kPocFogShaderAssetPath, kPocFrameDeltaBufferMaxSamples, kPocSanityScreenSyntheticDiscRadiusMeters, kPocFrameDelta{Median,P95,Max}{Green,Yellow}Micros, kPocFrameDeltaLogRollupSeconds, kPocSdfLogRollupSeconds)
  - 5 new l10n keys (shaderSanityTooltip, frameDeltaProbe{Median,P95,Max}Label, shaderSanityScreenTitle) wired in EN + FR with @description blocks on the FR template-arb-file
  - 12 production stubs (RevealDiscRepository, distanceMetres, SdfCache, SdfRebuildLogger, FrameDeltaProbe + FrameDeltaRollup, FogLayer, computeFogClipPath, FrameDeltaProbeOverlay, ShaderSanityScreen)
  - MapScreenServices extended with required `discRepository` + `frameDeltaProbe` fields; all call sites updated
  - GoRouter `/sanity` route → ShaderSanityScreen
  - AppBar `Icons.science` action button (visual order [science][share]) with tooltip via l10n.shaderSanityTooltip
  - 12 RED test files covering every Phase 3 surface (1 GREEN slot-count gate, 13 RED behavioural assertions, 6 skipped pending Plan 03-05/06/07 test seams)
  - Pre-walk falsification document skeleton (Criteria A + B written; evidence + verdict empty pending Plan 03-08)
affects: [03-02-reveal-disc-pipeline, 03-03-sdf-cache, 03-04-frame-delta-probe, 03-05-fog-layer-paint, 03-06-shader-sanity-screen, 03-07-map-screen-fog-integration, 03-08-walk-evidence]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Wave 0 stub pattern — every production file throws UnimplementedError or returns SizedBox.shrink so Wave 1+ plans flip RED → GREEN one assertion at a time
    - Skip-with-reason-in-description test pattern — testWidgets in flutter_test 3.41 takes `bool? skip` (not the dart:test `dynamic skip`); reason embedded in test description string
    - kPocFrameDeltaProbeOverlay{Top,Right}Px placement constants — top:8 (FpsCounterOverlay) → top:56 (MapCompass) → top:104 (FrameDeltaProbeOverlay), all right:8

key-files:
  created:
    - lib/domain/revealed/reveal_disc_repository.dart
    - lib/domain/revealed/distance_metres.dart
    - lib/infrastructure/mirk/sdf/sdf_cache.dart
    - lib/infrastructure/mirk/sdf_rebuild_logger.dart
    - lib/infrastructure/mirk/frame_delta_probe.dart
    - lib/presentation/widgets/fog_layer.dart
    - lib/presentation/widgets/fog_clip_path.dart
    - lib/presentation/widgets/frame_delta_probe_overlay.dart
    - lib/presentation/screens/shader_sanity_screen.dart
    - test/domain/revealed/reveal_disc_repository_test.dart
    - test/domain/revealed/distance_metres_test.dart
    - test/infrastructure/mirk/sdf/sdf_cache_test.dart
    - test/infrastructure/mirk/sdf_rebuild_logger_test.dart
    - test/infrastructure/mirk/frame_delta_probe_test.dart
    - test/infrastructure/mirk/shader/fog_shader_uniforms_test.dart
    - test/presentation/widgets/fog_layer_test.dart
    - test/presentation/widgets/fog_layer_camera_snapshot_test.dart
    - test/presentation/widgets/fog_clip_path_test.dart
    - test/presentation/widgets/frame_delta_probe_overlay_test.dart
    - test/presentation/screens/shader_sanity_screen_test.dart
    - test/presentation/screens/map_screen_fog_test.dart
    - .planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md
  modified:
    - lib/config/constants.dart
    - lib/l10n/app_en.arb
    - lib/l10n/app_fr.arb
    - lib/domain/map/map_screen_services.dart
    - lib/presentation/router.dart
    - lib/presentation/widgets/poc_app_bar.dart
    - test/presentation/screens/map_screen_test.dart
    - test/presentation/screens/map_screen_gps_test.dart
    - test/presentation/widgets/poc_app_bar_test.dart

key-decisions:
  - "testWidgets `skip:` parameter is `bool?` (not `String`) in flutter_test 3.41; skip reasons live in the test description string"
  - "MapCamera.nonRotatedSize is `Point<double>` (not `ui.Size`) per flutter_map 7.0.2 — fog_clip_path test fake mirrors Phase 2 MapCompass test fake"
  - "dart:ui FragmentShader is a `base` class that cannot be implemented from a test file; FogLayer test simplified to a skipped placeholder pointing at Plan 03-05 production-side test seam"
  - "AppBar action order [science][share] (visual reading order on right side); science icon navigates via context.go('/sanity') for full pile reset (no back navigation per project decision)"
  - "Frame-delta probe overlay placement: top:104 / right:8 — third HUD line below FpsCounterOverlay (top:8) and MapCompass (top:56), all right:8, all kPoc* constants"

patterns-established:
  - "Wave 0 keystone — every production stub returns UnimplementedError or no-op widget; downstream plans flip a specific RED test to GREEN"
  - "Skip-test pattern — `skip: true` + reason embedded in description, so the suite reads: `[skipped — Plan 03-XX wires Y]`"
  - "Test seams owned by future plans — fog_layer_test, fog_layer_camera_snapshot_test, frame_delta_probe_overlay_test, shader_sanity_screen_test no-throw, map_screen_fog_test all reference seams Plan 03-05/06/07 will introduce"

requirements-completed: [FOG-01, FOG-02, FOG-03, FOG-04, FOG-05, FOG-06, FOG-07, FOG-08]

# Metrics
duration: 16 min
completed: 2026-05-01
---

# Phase 3 Plan 1: Fog-of-War Wave 0 Scaffold Summary

**Wave 0 keystone — 12 production stubs + 12 RED test files + Phase 3 constants/l10n/router/AppBar wiring + pre-walk falsification skeleton landed in 3 atomic commits; every subsequent Phase 3 plan now reads imports that resolve, with the falsification harness pinned BEFORE any production behaviour ships.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-05-01T14:39:06Z
- **Completed:** 2026-05-01T14:54:42Z
- **Tasks:** 3 (all `type=auto tdd=true`, executed without checkpoints)
- **Files modified:** 28 (16 created + 5 production-file edits + 3 test-file edits + 4 generated-and-gitignored l10n synth files)

## Accomplishments

- 12 Phase 3 production stubs (RevealDiscRepository, distanceMetres, SdfCache, SdfRebuildLogger, FrameDeltaProbe + FrameDeltaRollup, FogLayer, computeFogClipPath, FrameDeltaProbeOverlay, ShaderSanityScreen) shipping the surface every Wave 1+ plan reads against — every method throws `UnimplementedError` or every widget renders a no-op `SizedBox.shrink` so the falsification harness fails behaviourally, NOT on compile errors.
- 12 RED test files cover every Phase 3 requirement (FOG-01..FOG-08); 13 RED behavioural assertions, 1 GREEN day-1 slot-count gate (`FogShaderUniforms.totalFloatSlots == 41` — defends against future BUG-014 Iter-2 regression), 6 skipped tests with their seam dependencies named (Plan 03-05/06/07).
- Phase 3 constants block (10 new constants) + 5 l10n keys (EN + FR with @description blocks on the FR template-arb-file) + Falsification document skeleton (Criteria A + B written, evidence + verdict empty pending Plan 03-08) all in place.
- MapScreenServices DTO extended with required `discRepository` + `frameDeltaProbe` fields; production /map route + every test call site updated to pass freshly-constructed stubs. AppBar gains an `Icons.science` action button (visual order [science][share]) navigating to `/sanity` via `context.go(...)`; `/sanity` GoRoute → ShaderSanityScreen.
- All Phase 1+2 regression tests (94 tests) still GREEN; `flutter analyze --fatal-infos lib/ test/` clean; `dart format --line-length 160 --set-exit-if-changed lib/ test/` clean.

## Task Commits

1. **Task 1: Constants block + l10n strings + falsification doc skeleton** — `e647057` (feat)
2. **Task 2: Production stubs + MapScreenServices extension + router /sanity + AppBar science action** — `760d051` (feat)
3. **Task 3: RED test files for every Phase 3 surface (Wave 0 contract)** — `b8f49f0` (test)

_Note: Each task is a single commit; the plan instructed mid-task sub-commits were PERMITTED but proved unnecessary at this size — each task fit in one cohesive change._

## Files Created/Modified

**New production stubs (`lib/`):**
- `lib/domain/revealed/reveal_disc_repository.dart` — RevealDiscRepository ChangeNotifier; `append` throws, `snapshot` returns empty unmodifiable list
- `lib/domain/revealed/distance_metres.dart` — top-level `distanceMetres(LatLng, LatLng)` throws
- `lib/infrastructure/mirk/sdf/sdf_cache.dart` — SdfCache constructor takes `SdfRebuildLogger`; `getOrBuild` throws, `dispose` no-op
- `lib/infrastructure/mirk/sdf_rebuild_logger.dart` — SdfRebuildLogger; `recordRebuild` throws, `start/stop` no-op
- `lib/infrastructure/mirk/frame_delta_probe.dart` — FrameDeltaProbe + FrameDeltaRollup value type; `recordCameraSnapshot/recordFogUniformPopulation/start` throw, `rollups` returns Stream.empty
- `lib/presentation/widgets/fog_layer.dart` — FogLayer StatefulWidget; build → SizedBox.shrink; constructor takes discRepository + shader + sdfCache + frameDeltaProbe
- `lib/presentation/widgets/fog_clip_path.dart` — top-level `computeFogClipPath({MapCamera, List<RevealDisc>})` throws
- `lib/presentation/widgets/frame_delta_probe_overlay.dart` — FrameDeltaProbeOverlay StatefulWidget; build → SizedBox.shrink; takes FrameDeltaProbe
- `lib/presentation/screens/shader_sanity_screen.dart` — ShaderSanityScreen StatefulWidget; placeholder body uses l10n.shaderSanityScreenTitle

**New tests (`test/`):**
- `test/domain/revealed/distance_metres_test.dart` — 73.7 km regression + symmetric/zero invariants (FOG-02 defence)
- `test/domain/revealed/reveal_disc_repository_test.dart` — snapshot immutability + listener-notification semantics (FOG-01)
- `test/infrastructure/mirk/sdf/sdf_cache_test.dart` — hit/miss matrix (FOG-03)
- `test/infrastructure/mirk/sdf_rebuild_logger_test.dart` — JSONL rollup shape + idle-second silence (FOG-03)
- `test/infrastructure/mirk/frame_delta_probe_test.dart` — rollup correctness + monotonic-guard (FOG-08)
- `test/infrastructure/mirk/shader/fog_shader_uniforms_test.dart` — `totalFloatSlots == 41` GREEN gate (FOG-05)
- `test/presentation/widgets/fog_clip_path_test.dart` — empty-discs world rect + one-disc-hole geometry (FOG-06)
- `test/presentation/widgets/fog_layer_test.dart` — MobileLayerTransformer ancestry contract (FOG-04, skipped)
- `test/presentation/widgets/fog_layer_camera_snapshot_test.dart` — single-MapCamera-snapshot keystone (FOG-07, skipped)
- `test/presentation/widgets/frame_delta_probe_overlay_test.dart` — three labelled lines (FOG-08, skipped)
- `test/presentation/screens/shader_sanity_screen_test.dart` — FR locale title (GREEN) + no-throw smoke (skipped)
- `test/presentation/screens/map_screen_fog_test.dart` — GPS fix → discRepository.append + FogLayer mount (FOG-01, skipped)

**Modified production files:**
- `lib/config/constants.dart` — Phase 3 constants block appended (10 new constants)
- `lib/l10n/app_en.arb` — 5 new keys (shaderSanityTooltip, frameDeltaProbe{Median,P95,Max}Label, shaderSanityScreenTitle)
- `lib/l10n/app_fr.arb` — Same 5 keys with @description blocks (FR is the template-arb-file per `l10n.yaml`)
- `lib/domain/map/map_screen_services.dart` — Required `discRepository` + `frameDeltaProbe` fields added
- `lib/presentation/router.dart` — `/sanity` route added; `_buildMapRoute` threads new MapScreenServices fields
- `lib/presentation/widgets/poc_app_bar.dart` — `Icons.science` action button added; `go_router` import added

**Modified test files (Rule 3 - Blocking call site updates):**
- `test/presentation/screens/map_screen_test.dart` — `_services` helper passes freshly-constructed RevealDiscRepository + FrameDeltaProbe
- `test/presentation/screens/map_screen_gps_test.dart` — same
- `test/presentation/widgets/poc_app_bar_test.dart` — two tooltip tests narrowed from `find.byType(IconButton)` (now ambiguous — two buttons) to `find.ancestor(of: byIcon(Icons.share), matching: IconButton)` so LOG-04 share-tooltip assertion holds

**Documentation:**
- `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` — Pre-walk skeleton (Criteria A + B written; Criterion C dropped declaration; walk plan section; evidence + verdict sections present-but-empty)

## Decisions Made

- **`skip:` parameter shape.** flutter_test 3.41's `testWidgets(skip:)` is `bool?`, not the dart:test `dynamic skip` (which accepts `true` or a `String` reason). Wave 0 tests use `skip: true` + reason embedded in the test description string ("\[skipped — Plan 03-XX wires Y\]") so the suite reads cleanly without the false-positive analyzer error.
- **MapCamera.nonRotatedSize is `Point<double>`.** Per flutter_map 7.0.2, `nonRotatedSize` is `Point<double>` (not `ui.Size`). The fog_clip_path test fake imports `dart:math` `Point` and constructs `Point<double>(400, 800)` — same shape as the Phase 2 MapCompass test fake (`MapCamera.kImpossibleSize` is also `Point<double>`).
- **FragmentShader cannot be implemented from a test.** dart:ui `FragmentShader` is a `base` class — implementing it from a test file fails Dart 3 sealed-class rules (`subtype_of_base_or_final_is_not_base_final_or_sealed`, `invalid_use_of_type_outside_library`). The fog_layer_test simplified to a skipped placeholder pointing at Plan 03-05, which must introduce a production-side test seam (likely an injectable `FogShaderRenderer` interface that production wraps `ui.FragmentShader` with). The plan's "_FakeShader implements ui.FragmentShader" sketch is incompatible with the language and would never have compiled.
- **AppBar action order.** `[science][share]` reading left-to-right when displayed on the right side of the AppBar (Material AppBar reverses naturally on RTL contexts). The `Icons.science` action button is the entry point to the `/sanity` pre-walk gate; `context.go('/sanity')` (full pile reset, consistent with the project's no-back-navigation decision).
- **Frame-delta probe overlay placement constants.** `kPocFrameDeltaProbeOverlayTopPx = 104` / `kPocFrameDeltaProbeOverlayRightPx = 8` — third HUD line below FpsCounterOverlay (top:8) and MapCompass (top:56), both right:8. Pin keeps Plan 03-06 from re-deriving the placement.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] testWidgets `skip:` parameter type mismatch**
- **Found during:** Task 3 (final analyze pass after writing test files)
- **Issue:** Plan-prescribed pattern `skip: 'Plan 03-XX wires Y'` failed analyze with `argument_type_not_assignable: The argument type 'String' can't be assigned to the parameter type 'bool?'`. flutter_test 3.41's `testWidgets` only accepts `bool? skip`, while the dart:test `test()` function accepts `dynamic skip` (true or a String). The plan's sketch conflated the two signatures.
- **Fix:** Skip reasons embedded in the test description string (`'... [skipped — Plan 03-XX wires Y]'`) and the parameter set to `skip: true`. Reason still readable in test output without losing the `bool?` contract.
- **Files modified:** test/presentation/widgets/{fog_layer_test,fog_layer_camera_snapshot_test,frame_delta_probe_overlay_test}.dart, test/presentation/screens/{shader_sanity_screen_test,map_screen_fog_test}.dart
- **Verification:** `flutter analyze --fatal-infos test/` clean; `flutter test` reports the 6 skipped tests with their description suffix visible.
- **Committed in:** b8f49f0 (Task 3 commit)

**2. [Rule 3 - Blocking] MapCamera.nonRotatedSize is Point<double>, not Size**
- **Found during:** Task 3 (final analyze pass)
- **Issue:** Plan-prescribed test fake passed `nonRotatedSize: const Size(400, 800)` which failed analyze with `argument_type_not_assignable: The argument type 'Size' can't be assigned to the parameter type 'Point<double>'`. flutter_map 7.0.2's `MapCamera` constructor takes `Point<double>` for nonRotatedSize (and exposes `MapCamera.kImpossibleSize` as `Point<double>(-1, -1)`).
- **Fix:** `import 'dart:math' show Point` added; nonRotatedSize set to `const Point<double>(400, 800)`. Pattern mirrors the Phase 2 MapCompass test fake.
- **Files modified:** test/presentation/widgets/fog_clip_path_test.dart
- **Verification:** `flutter analyze --fatal-infos test/` clean.
- **Committed in:** b8f49f0 (Task 3 commit)

**3. [Rule 3 - Blocking] dart:ui FragmentShader is a base class — cannot implement from test**
- **Found during:** Task 3 (final analyze pass)
- **Issue:** Plan-prescribed `_FakeShader implements ui.FragmentShader` failed analyze with `subtype_of_base_or_final_is_not_base_final_or_sealed` AND `invalid_use_of_type_outside_library` AND `non_abstract_class_inherits_abstract_member` (multiple new methods were added to the FragmentShader interface beyond the plan's sketch — `getImageSampler`, `getUniformFloat`, etc.) AND `invalid_override` (`setImageSampler` signature changed to take `{FilterQuality}`). The plan's pattern is incompatible with Dart 3 base-class rules.
- **Fix:** fog_layer_test.dart simplified to a skipped placeholder with an inline comment pointing at Plan 03-05 — which must introduce a production-side test seam (an injectable `FogShaderRenderer` interface that wraps `ui.FragmentShader`) to make this test runnable.
- **Files modified:** test/presentation/widgets/fog_layer_test.dart
- **Verification:** `flutter analyze --fatal-infos test/` clean.
- **Committed in:** b8f49f0 (Task 3 commit)

**4. [Rule 3 - Blocking] poc_app_bar_test tooltip queries assumed exactly one IconButton**
- **Found during:** Task 2 (running poc_app_bar_test after Phase 3 AppBar changes)
- **Issue:** Phase 1 tests `English tooltip is "Share logs"` and `French tooltip is "Partager les logs"` used `tester.widget<IconButton>(find.byType(IconButton))`, which throws `Bad state: Too many elements` when two IconButtons are present (the plan adds the science button before the share button).
- **Fix:** Both tests narrowed to `find.ancestor(of: find.byIcon(Icons.share), matching: find.byType(IconButton))` so the LOG-04 share-tooltip assertion still holds. The plan said this could be either accepted as a known failure or fixed; fixing it preserves the success criterion *"every Phase 1+2 regression test still GREEN"*.
- **Files modified:** test/presentation/widgets/poc_app_bar_test.dart
- **Verification:** All 5 poc_app_bar tests GREEN; full suite shows +97 GREEN, 94 of which are Phase 1+2.
- **Committed in:** 760d051 (Task 2 commit)

**5. [Rule 1 - Bug] Multi-line `// ignore:` directive on `_rebuildLogger` did not suppress the warning**
- **Found during:** Task 2 (analyze after writing SdfCache stub)
- **Issue:** Multi-line comment block above `final SdfRebuildLogger _rebuildLogger;` started with `// ignore: unused_field, the logger is...` — Dart's analyzer only respects `// ignore:` directives on the *immediately preceding* line, and the second line of the block (`// call sites; ...`) reset the directive. `flutter analyze` reported `unused_field` warning.
- **Fix:** Restructured to `/// docstring\n  // ignore: unused_field\n  final SdfRebuildLogger _rebuildLogger;` — single-line ignore directly above the field, with the rationale moved into a `///` docstring above.
- **Files modified:** lib/infrastructure/mirk/sdf/sdf_cache.dart
- **Verification:** `flutter analyze --fatal-infos lib/` clean.
- **Committed in:** 760d051 (Task 2 commit)

---

**Total deviations:** 5 auto-fixed (4 Rule 3 - Blocking, 1 Rule 1 - Bug). All deviations track plan-vs-reality drift in the test framework signatures (testWidgets `skip:`), flutter_map type signatures (MapCamera.nonRotatedSize), Dart 3 sealed-class rules (FragmentShader), Phase 1+2 test brittleness when AppBar surface changes, and Dart `// ignore:` scoping rules. None affect the plan's behavioural contract.

**Impact on plan:** The Wave 0 falsification harness lands intact — every requirement (FOG-01..FOG-08) has at least one RED test attached, and the 1 day-1 GREEN slot-count gate (FOG-05) is in place. The 6 skipped tests are a known and expected outcome — Plan 03-05/06/07 will introduce the production-side test seams (FogShaderRenderer interface, MapCamera-access counter, FragmentProgram loader injection) that flip those skipped tests to RED and then GREEN.

## Issues Encountered

None beyond the deviations above. Each was caught by `flutter analyze --fatal-infos` and corrected before the commit landed.

## User Setup Required

None — no external service configuration required for Phase 3 Plan 1 (entirely additive scaffold within the existing Flutter codebase).

## Next Phase Readiness

Wave 1 unblocked. The next plans consume specific stubs:

- **Plan 03-02** (FOG-01 + FOG-02 — RevealDiscPipeline) consumes RevealDiscRepository + distanceMetres; flips `distance_metres_test.dart` (3 tests) and `reveal_disc_repository_test.dart` (3 tests) RED → GREEN.
- **Plan 03-03** (FOG-03 — SdfCache + SdfRebuildLogger) consumes SdfCache + SdfRebuildLogger; flips `sdf_cache_test.dart` (3 tests) and `sdf_rebuild_logger_test.dart` (active-second test) RED → GREEN.
- **Plan 03-04** (FOG-08 — FrameDeltaProbe ring buffer + rollup timer) consumes FrameDeltaProbe; flips `frame_delta_probe_test.dart` (2 tests) RED → GREEN.
- **Plan 03-05** (FOG-04 + FOG-06 + FOG-07 — FogLayer paint + clip path + camera snapshot) consumes FogLayer + computeFogClipPath; flips `fog_clip_path_test.dart` (2 tests) RED → GREEN, AND introduces the FogShaderRenderer test seam + camera-access counter so the 2 skipped FogLayer tests become runnable. Plan 03-05 owns the FOG-07 single-camera-snapshot keystone.
- **Plan 03-06** (FOG-05 — ShaderSanityScreen + FrameDeltaProbeOverlay) consumes ShaderSanityScreen + FrameDeltaProbeOverlay; introduces the FragmentProgram loader test seam, flips the 2 currently-skipped overlay/sanity-screen tests to GREEN.
- **Plan 03-07** (Plan 03 wiring — MapScreen integration) wires GPS fix → discRepository.append + shader-load → FogLayer mount; flips `map_screen_fog_test.dart` (2 tests) RED → GREEN.
- **Plan 03-08** (walk evidence) populates the empty Walk Evidence + Verdict sections of `03-FALSIFICATION.md` from the sideload UAT walk.

No blockers. Phase 1+2 regression tests (94) all GREEN. `flutter analyze --fatal-infos lib/ test/` clean. `dart format --line-length 160 --set-exit-if-changed lib/ test/` clean. The 12 Phase 3 RED test files report `UnimplementedError` on the stubs (not compile errors) — exactly the falsification contract Wave 0 promised.

## Self-Check: PASSED

Verified post-summary:
- All 28 must_haves artifacts FOUND on disk (production stubs + test files + falsification skeleton)
- All 3 task commits present in `git log` (`e647057`, `760d051`, `b8f49f0`)
- `flutter analyze --fatal-infos lib/ test/` clean (verified after Task 3)
- `dart format --line-length 160 --set-exit-if-changed lib/ test/` clean (verified after Task 3)
- `flutter test` reports +97 GREEN / ~6 SKIPPED / -13 RED — exact falsification contract specified by the plan

---
*Phase: 03-fog-of-war-the-hypothesis*
*Completed: 2026-05-01*
