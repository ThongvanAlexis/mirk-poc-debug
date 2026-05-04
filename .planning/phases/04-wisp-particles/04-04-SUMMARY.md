---
phase: 04-wisp-particles
plan: 04
subsystem: wisp-fog-integration
tags: [wisp, fog-painter, foglayer, mapscreen, mapscreenservices, router, fog-07, wisp-04, paint-sequence, latLngToScreenPoint, shader-agnostic, plan-04-05-uat-walk-handoff]
dependency-graph:
  requires:
    - phase: 04-wisp-particles plan 02
      provides: "WispTransformLogger (start/stop + recordPaint(activeCount, meanAge, latBounds, lonBounds, screenXBounds, screenYBounds, spawnRatePerSecond))"
    - phase: 04-wisp-particles plan 03
      provides: "WispParticleSystem (advanceFromWallClock + advance + spawnAtNewDisc + spawnRatePerSecondAndReset + .wisps iterable + activeCount + clear)"
  provides:
    - "_FogPainter._renderWisps method — renders every active wisp as additive-blended drawCircle inside the canvas.save/restore block, AFTER drawRect, BEFORE restore (~120 LOC including helpers)"
    - "_FogPainter constructor extension: 3 new required fields (wispParticleSystem, wispTransformLogger, wispWallClock) — constructor injection mirrors FOG-07 discipline"
    - "_FogPainter._resolveWispRadius (screenPx + meters basis) + _derivePxPerMetre helpers"
    - "FogLayer constructor extension: 2 new required fields (wispParticleSystem, wispTransformLogger)"
    - "MapScreenServices DTO extension: 2 new required fields (wispParticleSystem, wispTransformLogger) — DTO now 9 fields"
    - "MapScreen.initState/dispose: WispTransformLogger.start/stop lifecycle wired"
    - "MapScreen._subscribeToPositions: per-fix discId+disc captured BEFORE append; wispParticleSystem.spawnAtNewDisc called AFTER append"
    - "Router-side production wiring: WispParticleSystem() + WispTransformLogger() defaults threaded through MapScreenServices in /map route builder"
    - "5 widget tests for WISP-04 + FOG-07 keystone — all GREEN"
    - "2 active widget tests for WISP-03 / SC #2 (warm-up gate + (0, 0) anti-pattern guard) — flipped from skip"
    - "2 carry-over regression-guard widget tests in map_screen_test.dart (UX-02 + DEBUG-02 with wisps wired)"
  affects:
    - "Plan 04-05 (UAT walk validation) — software-complete; ready for pre-walk gate sequence + iPhone 17 Pro sideload Walk #1"
    - "MirkFall production import — Phase 4 wisp pipeline ready for port-back alongside the Phase 3.1 fix bundle"
tech-stack:
  added: []
  patterns:
    - "Cross-pipeline FOG-07 keystone reuse — _renderWisps consumes the SAME camera constructor field that the fog uses; camera.latLngToScreenPoint is the SAME call site as fog_clip_path.dart:83 (verified across Phase 3.1 Walks #4-#6)"
    - "Shader-agnosticism property — _renderWisps depends ONLY on MapCamera.latLngToScreenPoint + canvas.drawCircle + Paint + clipPath + identity-frame discipline (zero references to uPixelOrigin / uZoomScale / uTime / FogShaderUniforms / atmospheric_fog*); documented in method docstring per CONTEXT §Shader-agnosticism"
    - "Encapsulated per-paint dt — wispParticleSystem.advanceFromWallClock(wispWallClock) lives behind the system's API; the painter stays declarative and never computes dt itself (Pitfall 6 prevention)"
    - "Hoisted Paint outside per-wisp loop — additive BlendMode.plus + tint ARGB byte-decoded once; the per-wisp Paint mutation only updates color (Pitfall 3)"
    - "Static-source regex assertion in widget tests — for cases where the recording-canvas can't observe a particular call (drawRect with shader: null), assert the production source-line ordering directly via RegExp matching to defend against a future PR moving _renderWisps outside the save/restore block"
    - "Two-commit plan discipline — Task 1 GREEN (painter + cross-test fixtures) commits standalone leaving MapScreen analyzer-broken; Task 2 GREEN (services + screen + router + carry-over guards) closes the gap atomically"
key-files:
  created: []
  modified:
    - "lib/presentation/widgets/fog_layer.dart (+280 LOC — 3 new constructor fields on _FogPainter, _FogLayerState._wispWallClockSinceMount, _renderWisps + _resolveWispRadius + _derivePxPerMetre, file-private constants)"
    - "lib/domain/map/map_screen_services.dart (+25 LOC — 2 new required fields, docstring updated to 9-field composition)"
    - "lib/presentation/screens/map_screen.dart (+25 LOC — wispTransformLogger.start in initState, .stop in dispose, _subscribeToPositions refactored to capture discId+disc before append + spawnAtNewDisc after append, FogLayer construction gains 2 args)"
    - "lib/presentation/router.dart (+8 LOC — 2 imports + 2 instantiations in /map route builder)"
    - "test/presentation/widgets/fog_layer_wisp_render_test.dart (rewritten from RED Plan 04-01 stub to 4 active testWidgets — paint-sequence + per-wisp projection + empty-system no-op + constructor required-args check)"
    - "test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart (rewritten from RED Plan 04-01 stub to active FOG-07 keystone test with WispParticleSystem injected)"
    - "test/presentation/widgets/{fog_layer_camera_snapshot,fog_layer_test,fog_canvas_frame_alignment,fog_pan_translation,fog_pixel_origin_decomposition,fog_rect_viewport_coverage,fog_smooth_noise,fog_zoom_invariant_basis}_test.dart (8 fixtures updated to construct the new FogLayer constructor args)"
    - "test/wisp/wisp_no_fix_warmup_test.dart (flipped from skip to active — 2 testWidgets: warm-up gate + (0, 0) anti-pattern guard)"
    - "test/presentation/screens/map_screen_test.dart (+2 testWidgets in new 'MapScreen × Phase 4 carry-overs' group — UX-02 + DEBUG-02 regression guards with wisps wired)"
    - "test/presentation/screens/map_screen_fog_test.dart (3 fixtures updated)"
    - "test/presentation/screens/map_screen_gps_test.dart (1 fixture helper updated)"
key-decisions:
  - "_renderWisps slot placement: AFTER canvas.drawRect(...liveShader) and BEFORE canvas.restore() inside the existing canvas.save/restore block. Wisps inherit FOG-12 clipPath + FOG-13 canvas-translated frame + FOG-07 single MapCamera snapshot for free. Documented in plan §interfaces."
  - "Per-paint dt encapsulation: WispParticleSystem.advanceFromWallClock(wispWallClock) ships in Plan 04-03; this plan ONLY consumes it. Painter forwards the live Stopwatch by reference; system internally tracks _lastAdvanceMicros and clamps dt to kMirkPocWispMaxDtSeconds. Encapsulation keeps the painter declarative."
  - "_resolveWispRadius ships BOTH branches functional: screenPx (production default — raw-pixel interpolation; visual character zoom-invariant) AND meters (A/B comparison branch — metric interpolation × pxPerMetre; wisps shrink at high zoom). Per CONTEXT §Implementation Decisions Radius basis: enum + paired constants — single-constant flip for walks."
  - "pxPerMetre derivation: 1e-4° lat probe (~11.132 m at any latitude; safely within fp32 precision). Cosmetic-only; safe to compute against camera centre. Inlined as small probe rather than depend on fog_clip_path.dart helper to keep cross-file coupling minimal."
  - "shouldRepaint DELIBERATELY omits wisp checks (Pitfall 4): the SingleTickerProviderStateMixin Ticker drives per-frame paints; wisp internals mutate without identity changes that shouldRepaint could detect. Adding identity check on wispParticleSystem would be cargo-cult. Documented inline."
  - "Static-source regex assertion in fog_layer_wisp_render_test.dart for the drawRect→_renderWisps→restore source ordering. Required because widget tests pass shader: null (FragmentShader is a base class — cannot be implemented from test code), so the recording canvas never observes a drawRect call. The block-level invariants (clipPath → drawCircle → restore) are still asserted via the recording canvas; the source-line invariant defends against someone moving _renderWisps outside the save/restore block."
  - "_FakeStopwatch.elapsedMs final-fields lint: pre-existing prefer_final_fields warning fixed during the resume; field is never reassigned in the test file."
  - "fog_zoom_invariant_basis_test.dart adaptation completion: previous executor only added imports; resume completed the FogLayer(...) call-site to pass the new constructor args. Discovered via flutter analyze missing_required_argument."
patterns-established:
  - "Pattern: Cross-pipeline keystone reuse — when adding a second visual layer to an existing painter, thread the SAME camera constructor field through both render paths; a single MapCamera snapshot per build defends both layers from BUG-014's frame-lag class of bugs."
  - "Pattern: Shader-agnostic visual-secondary layer — additive-blend drawCircle on top of a shader-driven primary rendering, scoped to ONLY camera projection + canvas drawing primitives + the primary layer's clipPath; ZERO references to the primary's shader uniforms. Lets future POC swaps of the production fog shader leave the wisp pipeline untouched (CLAUDE.md MIRL solution shader-agnosticism)."
  - "Pattern: Two-task TDD plan with cross-test cascade — Task 1 lands the painter-side surface + the existing tests that need adapting because of the new constructor contract; Task 2 lands the lifecycle wiring + new tests + carry-over regression guards. Two atomic commits per plan-execution discipline; the temporary inter-commit analyzer-broken state is acceptable because both commits are produced in the same execution session."
requirements-completed: [WISP-01, WISP-02, WISP-03, WISP-04, WISP-05]
metrics:
  duration: ~52 min (resumed from API-disconnect mid-Task-2; previous executor ~30 min before disconnect; resume ~22 min)
  tasks: 2 (TDD: 3 commits — RED + GREEN-Task-1 + GREEN-Task-2)
  files: 14 modified (4 production + 10 test) + 0 created
  completed: 2026-05-05
---

# Phase 4 Plan 04: FogLayer Wisp Integration Summary

**WispParticleSystem + WispTransformLogger fully wired into _FogPainter via constructor injection; wisps render as additive-blended drawCircles inside the same canvas.save/restore block as the fog, projected via the SAME MapCamera snapshot (FOG-07 keystone preserved); MapScreen owns the spawn callsite + logger lifecycle; router-side production wiring complete; SC #1 (pan-invariance) + SC #2 (no-fix-warmup) GREEN.**

## Performance

- **Duration:** ~52 min total (previous executor ~30 min before API disconnect mid-Task-2; resume ~22 min including diagnosis + Task-2 execution + summary)
- **Started:** 2026-05-05T00:26 (Task 1 RED commit `1c043a9` from previous executor)
- **Completed:** 2026-05-05T01:18 (Task 2 GREEN commit `faf83de`)
- **Tasks:** 2 (each TDD; 3 atomic commits)
- **Files modified:** 14 (4 production + 10 test)

## Accomplishments

- Wisp render slot inside `_FogPainter.paint()` — drawCircle per active wisp, additive blend, alpha-fade `1 - age²`, hoisted Paint
- Cross-pipeline FOG-07 keystone reuse — wisps inherit the fog's MapCamera snapshot via the same `camera` constructor field; zero new `MapCamera.of(context)` reads added
- Shader-agnosticism property documented in `_renderWisps` docstring — wisps depend ONLY on camera projection + canvas drawing primitives + clipPath; ZERO fog-shader-specific symbols
- Two functional radius bases (screenPx + meters) — single-constant flip for A/B comparison during walks
- Per-paint dt encapsulation via `WispParticleSystem.advanceFromWallClock(wispWallClock)` — painter stays declarative; clamp at `kMirkPocWispMaxDtSeconds` lives in the system
- Spawn wiring: every GPS fix → discRepository.append + wispParticleSystem.spawnAtNewDisc(discId, disc); idempotency + 5-s warm-up gating live inside the system
- WispTransformLogger lifecycle: `start()` in MapScreen.initState (next to fogTransformLogger.start), `stop()` in dispose (unconditional, mirrors FogTransformLogger pattern)
- Router-side production wiring: `WispParticleSystem()` + `WispTransformLogger()` defaults threaded through `MapScreenServices` in the /map route builder
- 5 WISP-04 / FOG-07 widget tests GREEN; 2 SC #2 widget tests flipped from skip; 2 Phase-4-carry-over regression guards added

## Task Commits

Each task was committed atomically per TDD discipline:

1. **Task 1 RED:** `1c043a9` — `test(04-04): RED — _FogPainter wisp render + FOG-07 keystone tests (Phase 4)` (committed by previous executor before API disconnect)
2. **Task 1 GREEN:** `c46ed39` — `feat(04-04): GREEN — _FogPainter._renderWisps + FogLayer constructor extension (WISP-04, FOG-07 keystone)`
3. **Task 2:** `faf83de` — `feat(04-04): wire WispParticleSystem + WispTransformLogger through MapScreenServices + MapScreen + router; SC#1 + SC#2 GREEN`

**Plan metadata commit:** to follow (this SUMMARY + STATE/ROADMAP/REQUIREMENTS updates).

_Note: TDD discipline produced 3 task commits — RED, then 2 GREEN commits split across the two tasks defined in the plan._

## Files Created/Modified

### Production (4 files modified)

- `lib/presentation/widgets/fog_layer.dart` (+280 LOC) — `_FogPainter` constructor extension (3 new required fields: wispParticleSystem, wispTransformLogger, wispWallClock), `_FogLayerState._wispWallClockSinceMount` live Stopwatch, `_renderWisps` body (advance → early-return → hoisted Paint → pxPerMetre derivation → per-wisp loop with bounds accumulation → recordPaint emission), `_resolveWispRadius` (screenPx + meters branches), `_derivePxPerMetre` (1e-4° lat probe), file-private constants for tint ARGB shifts/mask + lat-probe degrees
- `lib/domain/map/map_screen_services.dart` (+25 LOC) — 2 new required fields (`wispParticleSystem`, `wispTransformLogger`), DTO docstring updated to reflect 9-field composition
- `lib/presentation/screens/map_screen.dart` (+25 LOC) — `wispTransformLogger.start()` in initState, `.stop()` in dispose, `_subscribeToPositions` refactored (capture discId+disc as locals before append, call `wispParticleSystem.spawnAtNewDisc(discId, disc)` after append), FogLayer construction gains 2 args
- `lib/presentation/router.dart` (+8 LOC) — 2 wisp imports + WispParticleSystem() + WispTransformLogger() instantiations threaded through MapScreenServices in /map route builder

### Tests (10 files modified)

- `test/presentation/widgets/fog_layer_wisp_render_test.dart` — 4 active testWidgets (paint-sequence with static-source regex assertions + per-wisp projection + empty-system no-op + constructor required-args check)
- `test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart` — 1 active testWidgets for FOG-07 keystone with WispParticleSystem injected
- `test/wisp/wisp_no_fix_warmup_test.dart` — flipped from skip to 2 active testWidgets (warm-up gate + (0, 0) anti-pattern guard)
- `test/presentation/screens/map_screen_test.dart` — 2 new testWidgets in `MapScreen × Phase 4 carry-overs (Plan 04-04)` group (UX-02 + DEBUG-02 with wisps wired)
- `test/presentation/widgets/{fog_layer_camera_snapshot,fog_layer_test,fog_canvas_frame_alignment,fog_pan_translation,fog_pixel_origin_decomposition,fog_rect_viewport_coverage,fog_smooth_noise,fog_zoom_invariant_basis}_test.dart` — 8 fixture updates to construct the new FogLayer constructor args
- `test/presentation/screens/map_screen_fog_test.dart` + `map_screen_gps_test.dart` — fixture updates for new MapScreenServices fields

## Decisions Made

See frontmatter `key-decisions` for the full list. Highlights:

- **_renderWisps slot placement** — AFTER `canvas.drawRect(...liveShader)` and BEFORE `canvas.restore()` inside the same save/restore block. Inherits FOG-12 clipPath + FOG-13 canvas-translated frame + FOG-07 single MapCamera snapshot for free.
- **Per-paint dt encapsulation lives in WispParticleSystem.advanceFromWallClock** (Plan 04-03); painter stays declarative.
- **Both radius bases ship functional** — single-constant flip for A/B comparison during walks (CONTEXT §Implementation Decisions).
- **Static-source regex assertion** for drawRect→_renderWisps→restore source ordering (recording-canvas can't see drawRect when shader: null).
- **shouldRepaint DELIBERATELY omits wisp checks** (Pitfall 4) — Ticker drives per-frame paints; wisp identity is stable for the screen lifetime.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Completed `fog_zoom_invariant_basis_test.dart` adaptation**
- **Found during:** Task 1 GREEN flip (resume diagnosis via `flutter analyze`)
- **Issue:** Previous executor (before API disconnect) added the wisp imports to `fog_zoom_invariant_basis_test.dart` but never updated the actual `FogLayer(...)` constructor call site at line 123. Analyzer reported `missing_required_argument` for `wispParticleSystem` + `wispTransformLogger`.
- **Fix:** Added `wispTransformLogger`/`wispParticleSystem` instances to the test helper (`_captureZoomScaleAtZoom`) and threaded them into the `FogLayer(...)` call.
- **Files modified:** `test/presentation/widgets/fog_zoom_invariant_basis_test.dart`
- **Verification:** `flutter analyze` 0 issues; full widget-test suite GREEN.
- **Committed in:** `c46ed39` (Task 1 GREEN flip)

**2. [Rule 1 - Bug] Fixed `_FakeStopwatch._elapsedMs` final-fields lint**
- **Found during:** Task 1 GREEN flip (resume diagnosis via `flutter analyze`)
- **Issue:** `prefer_final_fields` info on the `_elapsedMs` field in `fog_layer_wisp_render_test.dart`'s `_FakeStopwatch`. The field is never reassigned in the test file (the constructor takes `initialMs` and stores it; no mutation thereafter).
- **Fix:** Changed `int _elapsedMs;` to `final int _elapsedMs;`.
- **Files modified:** `test/presentation/widgets/fog_layer_wisp_render_test.dart`
- **Verification:** `flutter analyze` 0 issues.
- **Committed in:** `c46ed39` (Task 1 GREEN flip)

**3. [Rule 3 - Blocking] Resume diagnosis & two-commit recovery from API-disconnect mid-Task-2**
- **Found during:** Initial resume — partial work in working tree
- **Issue:** Previous executor lost API connection after committing Task 1 RED at `1c043a9` and producing ~280 LOC of fog_layer.dart impl + cross-test adaptations + a partial wisp_render_test rewrite, all uncommitted. Analyzer surfaced 4 missing-required-argument errors (1 in `fog_zoom_invariant_basis_test.dart` per Deviation 1, 2 in `lib/presentation/screens/map_screen.dart` because Task 2 was incomplete).
- **Fix:** Inspected the diff; established the work was sound and represented Task 1 GREEN + the cross-test cascade. Committed Task 1 GREEN atomically at `c46ed39`. Then executed Task 2 from scratch (MapScreenServices + MapScreen lifecycle + router + 2 active wisp tests + 2 Phase-4-carry-over regression guards + 4 fixture updates). Committed Task 2 at `faf83de`.
- **Files modified:** see Files Created/Modified.
- **Verification:** Plan-spec verification block executed — `flutter analyze` 0 issues; `flutter test` 211 passed / 1 skipped (pre-existing) / 0 failures; `dart format --line-length 160 --set-exit-if-changed lib/ test/` clean; plan-spec greps all match expected counts.
- **Committed in:** `c46ed39` + `faf83de`

---

**Total deviations:** 3 auto-fixed (1 bug, 0 missing critical, 2 blocking — including the resume-from-disconnect recovery itself).
**Impact on plan:** All deviations were resume-recovery + analyzer-fallout cleanup. No scope creep; no architectural changes. The plan executed as written; the deviations are mechanical hygiene applied during the recovery.

## Authentication Gates

None — Plan 04-04 is pure software work; no external services, no credentials.

## Issues Encountered

None during the resume execution. The previous executor's API disconnect was the upstream issue; the resume diagnosed the partial state, validated the in-progress work, and completed both tasks atomically.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 4 software-complete: WispParticleSystem + WispTransformLogger production-wired through the full stack from router to _FogPainter
- WISP-01..05 mechanically satisfied at unit/widget-test level
- Plan 04-05 unblocked — pre-walk gate sequence + iPhone 17 Pro sideload Walk #1 to validate at runtime on device
- No outstanding blockers; no deferred items beyond the standard Plan 04-05 walk-time validation

## Self-Check: PASSED

Verified all claims:

- `lib/presentation/widgets/fog_layer.dart` — present, modified, contains `_renderWisps`, `_resolveWispRadius`, `_derivePxPerMetre`, shader-agnosticism docstring property
- `lib/domain/map/map_screen_services.dart` — present, modified, has `wispParticleSystem` + `wispTransformLogger` fields
- `lib/presentation/screens/map_screen.dart` — present, modified, has `wispTransformLogger.start()` in initState (line 151), `.stop()` in dispose (line 323), `wispParticleSystem.spawnAtNewDisc` exactly once (line 244)
- `lib/presentation/router.dart` — present, modified, has WispParticleSystem() + WispTransformLogger() in /map builder
- `test/wisp/wisp_no_fix_warmup_test.dart` + `wisp_pan_invariance_test.dart` — both present, both running active (no skip)
- `test/presentation/widgets/fog_layer_wisp_render_test.dart` + `fog_layer_single_camera_snapshot_test.dart` — both present, both GREEN
- Commits `1c043a9`, `c46ed39`, `faf83de` all present in `git log` on branch `main`
- Plan-spec greps:
  - `MapCamera.of` in fog_layer.dart → 6 matches, all docstrings/comments + the existing line 310 read; ZERO new occurrences inside `_renderWisps`
  - `wispParticleSystem.spawnAtNewDisc` in map_screen.dart → exactly 1 match
  - `wispTransformLogger.start|stop` in map_screen.dart → exactly 2 matches
  - `advanceFromWallClock` in fog_layer.dart → multiple matches (docstrings + the actual line 697 call inside `_renderWisps`)

---
*Phase: 04-wisp-particles*
*Completed: 2026-05-05*
