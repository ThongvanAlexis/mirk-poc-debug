# Roadmap: MirkFall Same-Canvas POC

## Overview

This POC answers one architectural question: does rendering the MirkFall map, fog-of-war shader, and wisp particles in a single unified Flutter Canvas pipeline eliminate the camera-tracking lag that BUG-014 left unfixed in the parent project? The roadmap front-loads the iOS feedback loop so that every subsequent phase produces a sideloadable IPA the developer can walk on iPhone. Risk de-risking drives the order: vector-tile rendering performance is the second-biggest unknown after the hypothesis itself, so it is gated before the fog work begins. The fog phase carries the falsification criteria; the wisp phase confirms cross-pipeline parity; the final phase converts walk evidence into the formal go/no-go verdict for the MirkFall migration.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation** - Bootstrap, CI, logger, share, FPS counter, permission gate — first walkable IPA
- [x] **Phase 2: Map (no fog)** - PMTiles, gestures, blue dot, recenter; no-fog FPS gate before fog work
- [x] **Phase 3: Fog of War — THE HYPOTHESIS** - Same-Canvas fog layer + frame-delta probe + falsification walk — **HYPOTHESIS DENIED 2026-05-01** (fog renders + rotates with camera but does NOT translate during pan; structural FOG-04 test passes but Canvas-transform sharing does not follow). See `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md`. Phase 3.1 gap-closure recommended before Phase 4 unblocks.
- [ ] **Phase 4: Wisp Particles** - World-locked wisps composited in the same paint pass as fog — **BLOCKED on Phase 3.1 gap-closure outcome**
- [ ] **Phase 5: Decision Gate** - Final hardening, Pixel 4a sanity walk, formal POC verdict — **BLOCKED on Phase 3.1 gap-closure outcome**

**Phase 3.1 verdict (P03.1-03 Walk #1 2026-05-02): ITERATING-WITH-MAJOR-PROGRESS** — fix is partial; constant-zero failure mode structurally addressed and CI-gated by FOG-09; new failure modes (per-paint modulo-wrap shimmer + Canvas-frame reveal-hole offset) surfaced by post-fix walk and resolved to 2 specific candidate root causes for Plan 03.1-04. See `.planning/phases/03.1-fix-fog-pan-translation/03.1-FALSIFICATION.md`.

**Phase 3.1 verdict (P03.1-06 Walk #2 2026-05-02): ITERATING-WITH-PARTIAL-PROGRESS** — 3 of 4 fixes confirmed (PERF-07 re-validated 3.9-5.4× headroom; FOG-12 reveal-hole alignment confirmed; UX-01 back button confirmed). FOG-11 SHADER-MODULO-WRAP CI test GREEN but user-observable shimmer persists ("rotating 90° / translated fast repetitively") — CI-test-vs-walk-symptom mismatch (key learning). PERF-08 SDF-CACHE quantisation 1e-4 NOT closing per-paint thrash empirically (1-121 rebuilds/sec). NEW failure mode introduced by Plan 03.1-05: fog-rect viewport-coverage (clip-path compensation worked but `canvas.drawRect` is subject to canvas transform too) — top-right + bottom-right diagonal strips of un-fogged map at high zoom. Two new requirements: FOG-13 (fog-rect symmetric compensation) + FOG-14 (higher-fidelity noise-pattern stability test). See `.planning/phases/03.1-fix-fog-pan-translation/03.1-FALSIFICATION-2.md`. Next: `/gsd:plan-phase 3.1 --gaps` for Plan 03.1-07.

**Phase 3.1 verdict (P03.1-09 Walk #3 2026-05-03): ITERATING-WITH-PARTIAL-PROGRESS-AND-ROTATION-REGRESSION** — fourth Phase 3.1 iteration. Two findings: (1) **Q1 PARTIAL** — Plan 03.1-07 Branch B-3 reduced wrap frequency (from viewport-width ~390 px to noise-tile period ~16-65 px); panning smooth between wrap events but stepping discontinuity persists at wrap events. Documented Plan 03.1-07 SUMMARY partial-fix outcome — wrap MAGNITUDE in cell-grid space stays same, only FREQUENCY changes. Developer's intent-correct iteration framing: *"if I pan right forever the shader should not be moved to be where I'm going, I should see a new area of the shader"* — world-coordinate-noise rewrite (D-1 + D-1a) is the Plan 03.1-10 path. (2) **Q2 NEW failure mode (rotation-correlated)** — Plan 03.1-08's `canvas.translate(-canvasOffset)` compensates ONLY translation; rotation (matrix[0,1,4,5]) untouched. Pinch-zoom-rotate causes fog rect to rotate with canvas leaving wedges at viewport corners. Developer-endorsed mitigation: disable map rotation (UX-02 scope reduction). Three new requirements: **FOG-16** (rotation handling), **FOG-17** (world-coordinate noise sampling), **UX-02** (disable rotation). Walk #3 limitation: no session log Mail-shared this walk; verbal evidence only. PERF-07 + PERF-08 statuses retained at Walk #2 levels. See `.planning/phases/03.1-fix-fog-pan-translation/03.1-FALSIFICATION-3.md`. Next: `/gsd:plan-phase 3.1 --gaps` for Plan 03.1-10 (world-coordinate noise + rotation handling).

## Phase Details

### Phase 1: Foundation
**Goal**: First sideloadable IPA where the developer walks through permission, sees the FPS counter, and shares the session log back to themselves over Mail. Establishes the iOS feedback loop end-to-end before any map code is written.
**Depends on**: Nothing (first phase)
**Requirements**: BOOT-01, BOOT-02, BOOT-03, BOOT-04, BOOT-05, BOOT-06, BOOT-07, BOOT-08, AUDIT-01, AUDIT-02, AUDIT-03, CI-01, CI-02, CI-03, CI-04, CI-05, AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06, LOG-01, LOG-02, LOG-03, LOG-04, LOG-05, PERF-01
**Success Criteria** (what must be TRUE):
  1. Developer pushes to `main`; the GitHub Actions run page shows three green jobs (lint on ubuntu, debug APK on ubuntu, unsigned IPA on macos) and the IPA + APK artifacts are downloadable from that run.
  2. Developer sideloads the IPA via SideStore on iPhone 17 Pro, launches the app, and sees the permission rationale screen explaining why `locationWhenInUse` is needed for the fog-of-war.
  3. Developer grants permission and lands on a placeholder map screen with a visible FPS counter (showing fps + the device refresh rate, 120 Hz on ProMotion) in the corner; denying instead routes to a denied screen whose "Open Settings" button rounds-trips through iOS Settings and re-checks permission on resume.
  4. Developer taps the share-logs button, picks Mail, and the session's `yyyymmdd_hhmmss_logs.txt` arrives in their inbox with byte-count matching the on-device file (50 MB synthetic-log smoke test passed at least once with a content-marker at byte 47 MB present in the received attachment).
  5. CI license-check job fails any future PR that introduces a non-allowlisted license (allowlist: MIT, BSD-2/3, Apache 2.0, ISC, zlib, CC0, Unlicense); first-pass `DEPENDENCIES.md` rows present for every direct dependency in `pubspec.yaml`, with telemetry audit showing zero automatic network egress at app launch.
**Plans**: 7 plans
  - [x] 01-01-PLAN.md — Bootstrap: pubspec, analysis_options, LICENSE, l10n scaffold, donor constants + binary assets
  - [x] 01-02-PLAN.md — Tooling: port tool/check_* + tool/test/* scripts, DEPENDENCIES.md skeleton, iOS Info.plist + PrivacyInfo.xcprivacy
  - [x] 01-03-PLAN.md — BOOT-08 donor source files port, three-job CI workflow, REQUIREMENTS.md LOG-05 wording update
  - [x] 01-04-PLAN.md — FileLogger + FileLoggerLifecycleObserver port-with-three-POC-adaptations + tests
  - [x] 01-05-PLAN.md — buildPocAppBar share-logs helper + FpsCounterOverlay (ProMotion-aware) + widget tests
  - [x] 01-06-PLAN.md — PermissionGateScreen (lifecycle resume re-check) + PermissionDeniedScreen + widget tests
  - [x] 01-07-PLAN.md — main wiring: lib/main.dart + app.dart + router.dart + MapScreen placeholder + LOG-05 manual UAT checkpoint

### Phase 2: Map (no fog)
**Goal**: A walkable map that loads `Fra_Melun.pmtile` from `getApplicationSupportDirectory()`, accepts pan/zoom/combined gestures, shows a blue dot following GPS, and recentres on demand — sustaining ≥ 40 fps on iPhone 17 Pro without fog. This is the gate that decides whether `vector_map_tiles` 8.0.0 is performant enough on this PMTiles at zoom 13–15 to make the Phase 3 hypothesis test meaningful.
**Depends on**: Phase 1
**Requirements**: MAP-01, MAP-02, MAP-03, MAP-04, MAP-05, MAP-06, LOC-01, LOC-02, LOC-03, LOC-04, LOC-05, PERF-02
**Success Criteria** (what must be TRUE):
  1. Developer launches the app fresh-installed; the log records `Copied Fra_Melun.pmtile (~4 MB) in <500 ms` exactly once during the permission-grant flow, and subsequent launches do NOT re-copy (idempotent existence check passes).
  2. Developer walks 200 m through central Melun (zoom 13–15); the map renders the bundled tiles with the renderer's default style, the blue dot follows each GPS fix, and the recenter FAB animates the camera to `_lastFix` at zoom 15 (and is disabled while `_lastFix` is null).
  3. Developer performs at least 10 pure pans, 10 pure pinch-zooms, and 10 combined pinch-zoom-and-pan gestures during the walk; the FPS counter shows pan-FPS ≥ 40 sustained on iPhone 17 Pro (PERF-02 gate). If this fails, Phase 3 does not start until label-thinning or another mitigation restores the baseline.
  4. Developer rapidly zooms out (z=15 → 8) and back in (z=8 → 15); tiles repaint without persistent blank flashes (brief decode flicker on cold cache is acceptable; sustained blanks are not).
**Plans**: 6 plans
  - [x] 02-01-PLAN.md — Wave 0 scaffolds: constants + l10n + services DTO + /error route + production stubs + RED test files
  - [x] 02-02-PLAN.md — MAP-01: PmtilesAssetCopier impl + PermissionGateScreen ensureCopied hook (both grant paths)
  - [x] 02-03-PLAN.md — LOC-01/02/03: GeolocatorService impl + BlueDotMarker impl + LOC-03 static-source gate verified
  - [x] 02-04-PLAN.md — LOC-04/05: RecenterFab (500 ms easeInOut tween) + MapCompass (250 ms snap-to-north, shortest-path math)
  - [x] 02-05-PLAN.md — MAP-02..06: MapScreen rewrite — FlutterMap stack with VectorTileLayer + blue dot + compass + recenter FAB; router /map builder updated
  - [x] 02-06-PLAN.md — PERF-02: sideload UAT walk on iPhone 17 Pro (verbal approved exit gate)

### Phase 3: Fog of War — THE HYPOTHESIS
**Goal**: Render the atmospheric fog shader in the same Flutter Canvas as the tile layer, driven by an in-memory disc list and a 256×256 R-channel SDF. Wire the frame-delta self-debug probe. Walk the falsification criteria on iPhone 17 Pro. The phase's deliverable is a binary answer to the architectural hypothesis: same-Canvas eliminates the lag, or it does not. A "denied" outcome here is a valid scientific result that terminates the project; a "confirmed" outcome unlocks Phase 4.
**Depends on**: Phase 2
**Requirements**: FOG-01, FOG-02, FOG-03, FOG-04, FOG-05, FOG-06, FOG-07, FOG-08, PERF-03, PERF-04, PERF-05
**Success Criteria** (what must be TRUE):
  1. Pre-walk gates pass: a unit test asserts `distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km` (not ~111 km, defending against degree-distance regression); a unit test asserts SDF rect, clip path, and shader uniforms all derive from the same `MapCamera` instance captured once per `FogLayer` build (FOG-07 enforced); a shader-sanity screen renders the 41-uniform shader on the iOS device with hardcoded inputs before the walk.
  2. Developer walks ≥ 5 minutes through Melun on iPhone 17 Pro with at least 10 deliberate combined pinch-zoom-and-pan gestures and at least 3 recenter taps; pan-FPS with fog active stays ≥ 30 and idle-fog-animation FPS stays ≥ 50 (PERF-03).
  3. Frame-delta probe (FOG-08) over the same walk reports rolling median camera-to-fog-paint delta ≤ 16 ms, p95 ≤ 32 ms, max ≤ 48 ms across the ≥ 10 combined gestures (PERF-04). The probe values are visible on the on-screen overlay and persisted to the session log.
  4. Developer's subjective verdict at the end of the walk: no visible fog slide-then-snap, no white-ellipse artefact during fast pinch-zoom, no perceptible reveal-hole lag behind the blue dot, and no inversion at any zoom level (PERF-05).
  5. Falsification criteria for the hypothesis (Criterion A: frame-delta thresholds; Criterion B: subjective lock — Criterion C dropped per locked decisions) are written down in the repo before the walk and the walk evidence is appended to the same document at the end.
**Plans**: 8 plans
  - [x] 03-01-PLAN.md — Wave 0 scaffolds: constants + l10n + production stubs + RED test files + falsification doc skeleton
  - [x] 03-02-PLAN.md — FOG-01 + FOG-02 defence: RevealDiscRepository + distanceMetres helper
  - [x] 03-03-PLAN.md — FOG-03: SdfCache (hash invalidation) + SdfRebuildLogger (1 Hz JSONL rollup)
  - [x] 03-04-PLAN.md — FOG-08: FrameDeltaProbe (Stopwatch monotonic, broadcast Stream<FrameDeltaRollup>, JSONL log)
  - [x] 03-05-PLAN.md — FOG-04..07: FogLayer + computeFogClipPath + KEYSTONE single-MapCamera-snapshot test
  - [x] 03-06-PLAN.md — FrameDeltaProbeOverlay (live HUD) + ShaderSanityScreen (pre-walk gate at /sanity)
  - [x] 03-07-PLAN.md — MapScreen integration: GPS fix → discRepository.append; FogLayer + probe overlay mount
  - [x] 03-08-PLAN.md — Pre-walk gates + iPhone 17 Pro UAT walk + falsification verdict — **DENIED 2026-05-01** (fog static during pan; Phase 3.1 gap-closure required)

### Phase 03.1: Fix Fog Pan-Translation (INSERTED)

**Goal:** Diagnose why the same-Canvas fog renders + rotates correctly with the camera but does NOT translate during pan, apply a fix, and re-validate the falsification criteria on iPhone 17 Pro. Phase 3.1 either reverses the Plan 03-08 `DENIED` verdict to `CONFIRMED-AFTER-FIX` (unblocking Phase 4 + Phase 5) or strengthens it to `DENIED-FINAL` with deeper architectural diagnosis. Research (HIGH confidence) traced the bug to `_FogPainter.paint()` passing `offset: const (0.0, 0.0)` to the shader — a 3-line fix derives `uOffset` from `camera.pixelOrigin / size`. Phase 3.1 ships the fix, a CI-gating behavioural regression test, and permanent diagnostic instrumentation alongside.
**Requirements**: FOG-09, FOG-10, FOG-11, FOG-12, FOG-13, FOG-14, FOG-15, FOG-16, FOG-17, PERF-07, PERF-08, UX-01, UX-02, DEBUG-01 (DEBUG-01 + FOG-15 added 2026-05-03 via Plan 03.1-07; FOG-14 refined; FOG-16 + FOG-17 + UX-02 added 2026-05-03 via Plan 03.1-09 Walk #3)
**Depends on**: Phase 3
**Plans**: 9 plans landed + Plans 03.1-10 + 03.1-11 planned 2026-05-XX via /gsd:plan-phase 3.1 --gaps (Walk #3 closed `iterating-with-partial-progress-and-rotation-regression` 2026-05-03; per CONTEXT §Iteration policy no hard cap on walk count — Plans 03.1-10 software fix + 03.1-11 Walk #4 pending execution)
  - [x] 03.1-01-PLAN.md — FogTransformLogger + Phase 3.1 constants + REQUIREMENTS/ROADMAP stub finalisation
  - [x] 03.1-02-PLAN.md — Apply 3-line fix in `_FogPainter.paint()` + wire `FogTransformLogger` + FOG-09 behavioural transform-equality regression test + FOG-04 docstring augmentation + VALIDATION.md per-task map populated
  - [x] 03.1-03-PLAN.md — Pre-walk gates + iPhone 17 Pro UAT Walk #1 + `03.1-FALSIFICATION.md` — **VERDICT ITERATING-WITH-MAJOR-PROGRESS 2026-05-02** (PERF-07 GREEN; constant-zero failure mode structurally addressed; new modulo-wrap shimmer + Canvas-frame reveal-offset modes surfaced — Plan 03.1-04 follow-up required)
  - [x] 03.1-04-PLAN.md — SHADER-MODULO-WRAP fix: rename uOffset→uPixelOrigin; per-fragment fract() inside shader; FOG-11 behavioural smooth-noise test
  - [x] 03.1-05-PLAN.md — CANVAS-FRAME-ALIGNMENT (FOG-12) + SDF-CACHE-VIEWPORT-THRASH (PERF-08) + SANITY-NO-BACK-BUTTON (UX-01)
  - [x] 03.1-06-PLAN.md — Pre-walk gates + iPhone 17 Pro UAT Walk #2 + `03.1-FALSIFICATION-2.md` — **VERDICT ITERATING-WITH-PARTIAL-PROGRESS 2026-05-02** (PERF-07 re-validated; FOG-12 + UX-01 confirmed-by-walk; FOG-11 falsified-by-walk-2; PERF-08 falsified-by-walk-2; new fog-rect viewport-coverage regression introduced by P03.1-05 → FOG-13 + FOG-14 requirements opened)
  - [x] 03.1-07-PLAN.md — Mechanism investigation via debug-spiral shader (DEBUG-01) + iPhone observation checkpoint (B-0 gating step) + post-checkpoint mechanism-specific fix — **Branch B-3 (noise-tile-period mismatch) SELECTED + LANDED 2026-05-03** per developer's iPhone 17 Pro Walk #2 production-conditions observation: *"the translation isn't smooth, it's 'stepped'... while zooming it's being translated a lot"*. Fix: `fract(uPixelOrigin / tilePeriodPixels)` where `tilePeriodPixels = uResolution / max(uScaleFar, uScaleMid, uScaleNear)`; derived in-shader, no new uniform, `totalFloatSlots = 41` preserved. Applied to both `atmospheric_fog.frag` (production) and `atmospheric_fog_debug_spiral.frag` (debug). FOG-14 closes via test pair (`fog_debug_spiral_continuity_test.dart` 3/3 GREEN + `fog_tile_period_invariant_test.dart` 3/3 GREEN). FOG-15 closes via the structural fix landing GREEN. Documented partial-fix: wraps still happen at sub-perceptible noise-tile period (~16-65 px); if Walk #3 surfaces residual high-zoom stepping, Plan 03.1-10 may need a world-coordinate-noise rewrite.
  - [x] 03.1-08-PLAN.md — FOG-13 fog-rect viewport-coverage symmetric compensation: `canvas.translate(-canvasOffset)` at top of `_FogPainter.paint()` (Option b from FALSIFICATION-2 sub-section D row C-1) — landed 2026-05-03 (3 atomic commits; new `fog_rect_viewport_coverage_test.dart` flips RED → GREEN; FOG-12 stays GREEN with mock-canvas no-op translate override; full suite 146 GREEN / 1 SKIPPED)
  - [x] 03.1-09-PLAN.md — Pre-walk gates + iPhone 17 Pro UAT Walk #3 + `03.1-FALSIFICATION-3.md` — **VERDICT ITERATING-WITH-PARTIAL-PROGRESS-AND-ROTATION-REGRESSION 2026-05-03** (4th Phase 3.1 iteration). Walk #3 against CI run 25275979318 (SHA 0625ba5). Two findings: (1) Q1 PARTIAL — B-3 reduced wrap frequency (~390 px → ~16-65 px) but stepping discontinuity persists at wrap events ("now when panning it is smooth, but every x amount of pan you get a hard step") — confirms Plan 03.1-07 SUMMARY partial-fix framing; world-coordinate-noise rewrite (FOG-17 NEW + FOG-17a precision pairing) is the Plan 03.1-10 path. (2) Q2 NEW failure — Plan 03.1-08's translation-only `canvas.translate(-canvasOffset)` doesn't compensate canvas rotation; pinch-zoom-rotate causes fog rect to rotate with canvas leaving wedges of un-fogged map at viewport corners. Developer-endorsed mitigation: disable rotation (UX-02 NEW). FOG-16 NEW captures the rotation-handling axis. Walk #3 limitation: no log Mail-shared; verbal evidence only. FOG-13 + FOG-15 demoted to Verified-by-test-only. PERF-07 + PERF-08 retained at Walk #2 levels. Phases 4 + 5 stay BLOCKED. Walk #1 + Walk #2 + Phase 3 historical records UNTOUCHED.
  - [x] 03.1-10-PLAN.md — Software-fix landing 2026-05-03: UX-02 disable rotation (closes FOG-16 path (a)) + FOG-17 world-coordinate noise sampling in BOTH atmospheric_fog.frag + atmospheric_fog_debug_spiral.frag + FOG-17a CPU-side integer/fractional decomposition in `_FogPainter.paint()` (keeps shader input bounded under ~1537 raw px regardless of zoom). New tests: fog_world_coordinate_noise_test.dart (4 sub-tests) + fog_pixel_origin_decomposition_test.dart (7 sub-tests) + map_screen_test.dart UX-02 rotation-disabled assertion. Rewritten: fog_tile_period_invariant_test.dart + fog_debug_spiral_continuity_test.dart. Touched: fog_smooth_noise_test.dart + fog_pan_translation_test.dart (assertion + reason-string accuracy). Constants: kPocFogNoiseTilePx = 384.0 + kPocFogIntegerWrapPeriodPx = 1536.0 (invariant: kPocFogIntegerWrapPeriodPx % kPocFogNoiseTilePx == 0; 1536 = 4 × 384). Full suite GREEN (180 tests + 1 skipped); flutter analyze 0 issues; dart format clean. FOG-04..07 + FOG-11 + FOG-15 retain Falsified-in-production until Plan 03.1-11 Walk #4. Per CONTEXT §Iteration policy no hard cap; Walk #4 next.
  - [ ] 03.1-11-PLAN.md — Pre-walk gates + iPhone 17 Pro UAT Walk #4 + `03.1-FALSIFICATION-4.md` + verdict authoring (CONFIRMED-AFTER-FIX | DENIED-FINAL | ITERATING). Walk #4 procedure includes explicit dev-marker-button taps for any residual symptom + ≥ 60-second sustained one-direction pan (validates Q1 across integer-wrap window) + deliberate two-finger rotate-attempt gesture (validates UX-02) + post-walk Mail-share discipline RE-ESTABLISHED (Walk #3 broke this; the diagnostic anchor depends on the JSONL streams). Plan ready 2026-05-XX; pending Plan 03.1-10 execute → Walk #4 sideload.

### Phase 4: Wisp Particles
**Goal**: Composite the wisp particle system after the fog in the same Canvas, with positions stored in `LatLng` (world space) and projected to screen via the same `MapCamera` snapshot the fog uses. Confirms that the same-Canvas discipline established in Phase 3 generalises to a second visual layer — the cross-pipeline parity check that completes the code-donor package for porting back to MirkFall.
**Depends on**: Phase 3
**Requirements**: WISP-01, WISP-02, WISP-03, WISP-04
**Success Criteria** (what must be TRUE):
  1. A unit test asserts that simulating a 100 m camera pan does NOT change a wisp's logical `LatLng` position, and that the wisp's projected screen Offset moves by the corresponding screen-pixel delta (defending against the verbatim-port pixel-space regression).
  2. Developer launches the app; no wisps appear during the 5 s warm-up before the first GPS fix arrives, and no wisps appear at synthetic (0, 0) coordinates.
  3. Developer walks the same Melun route from Phase 3; wisps spawn along disc perimeters as new discs appear, drift outward over their 2.5 s life, fade out, and remain anchored to the underlying map during pan/zoom/combined gestures. Maximum 200 wisps active simultaneously.
  4. FPS during the walk holds the Phase 3 thresholds (pan-FPS with fog + wisps active ≥ 30 on iPhone 17 Pro); fog lock from Phase 3 is preserved (re-confirming the hypothesis was not regression-broken by the wisp work).
**Plans**: TBD

### Phase 5: Decision Gate
**Goal**: Lock everything down for code-donor port-back to MirkFall and produce the formal POC verdict (hypothesis confirmed / denied → MirkFall migration go / no-go). One final iPhone walk re-runs the Phase 3 + Phase 4 criteria; one Pixel 4a walk satisfies the cross-platform sanity requirement; the verdict document is committed to the repo as the final artefact.
**Depends on**: Phase 4
**Requirements**: PERF-06
**Success Criteria** (what must be TRUE):
  1. Final iPhone 17 Pro walk re-confirms Phase 3 fog lock + Phase 4 wisp anchoring + ≥ 30 fps with fog + wisps active; share-logs round-trip still works; FPS counter still visible.
  2. Pixel 4a (Adreno 618) walk: app launches without crash, fog renders, wisps render, app does not crash during a 5-minute walk; informational FPS recorded in the verdict document for cross-platform reference (no hard pass criterion — PERF-06).
  3. Repository hardening passes: `flutter analyze` zero warnings, `dart format --line-length 160 --set-exit-if-changed` clean, every `.dart` file in `lib/` and `test/` carries the GOSL v1.0 copyright header (re-verified as a CI gate), `DEPENDENCIES.md` covers every package in `pubspec.lock` with current audit dates, and the CI license-check job is green on `main`.
  4. Formal POC verdict document is committed at the repo root: states "hypothesis confirmed" or "hypothesis denied" backed by the Phase 3 frame-delta numbers + subjective walk notes, names the iPhone model and Flutter version, and ends with an explicit MirkFall-migration recommendation (port back / do not port back / port back with caveats).
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 7/7 | Complete | 2026-05-01 |
| 2. Map (no fog) | 6/6 | Complete | 2026-05-01 |
| 3. Fog of War — THE HYPOTHESIS | 8/8 | Complete (HYPOTHESIS DENIED) | 2026-05-01 |
| 03.1. Fix Fog Pan-Translation | 10/11 | In Progress|  |
| 4. Wisp Particles | 0/TBD | Blocked on Phase 3.1 | - |
| 5. Decision Gate | 0/TBD | Blocked on Phase 3.1 | - |

---
*Roadmap created: 2026-04-30*
*Granularity: coarse (5 phases)*
*Coverage: 70/70 v1 requirements mapped*

