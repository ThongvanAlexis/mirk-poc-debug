---
status: fix-applied-pending-verification
trigger: "Pixel 4a Walk #1: whitish artefact with same shape as revealed disc, moves around during pan. Phone-agnostic expected since math; iPhone 17 Pro leg passed."
created: 2026-05-05T20:30:00Z
updated: 2026-05-15T00:30:00Z
---

## Current Focus

hypothesis: REVISED AGAIN after the cross-platform walk (2026-05-14, build a4dbd17 RED TINT diagnostic, IDENTICAL SHA both platforms). The prior "Mechanism 1 = SDF linear-bbox-vs-Mercator projection mismatch as DOMINANT + PERSISTENT + PLATFORM-AGNOSTIC cause" is **FALSIFIED**: that mechanism is platform-agnostic by construction (pure Dart math, same on iOS), so it would be equally visible on iOS — and the cross-platform walk shows iOS is essentially CORRECT (reveal + halo stay synced, both anchored to basemap; only minor fast-motion transient = Mechanism 2). A platform-agnostic math bug cannot produce a platform-SPECIFIC symptom. The real, decisive symptom is:

  ROOT CAUSE — ANDROID-SPECIFIC Y-AXIS FLIP OF SHADER-RENDERED CONTENT (the `IMPELLER_TARGET_OPENGLES` guard mis-fires / is absent for the actual Android backend).
  Same Dart code, same GLSL, correct on iOS (Impeller-Metal), Y-inverted on Android (Pixel 4a / Adreno 618 / Android 13). Developer's careful isolation: mirk and basemap move at the SAME SPEED (no scaling error), X-axis pan CORRECT, Y-axis INVERTED (pan up → mirk moves down), red halo "baked into the mirk" (no independent halo-vs-reveal offset — the WHOLE shader-rendered content is Y-flipped as one). The flip happens in the shader's `FlutterFragCoord().y` / SDF-texture-V coordinate space, NOT in the Dart-drawn clip path. See Evidence (Cross-platform walk) + Resolution below.

  MECHANISM 2 — STALE-SDF-DURING-REBUILD — still real, still minor, still secondary/TRANSIENT.
  While `buildFromDiscs` is in flight the painter keeps the PREVIOUS `_currentSdfImage` bound, adding a transient pan-speed-proportional wobble. On iOS this is the ONLY residual (small, snaps back on fast motion). On Android it rides on top of the Y-flip. Keep it as a throughput follow-up; it is NOT the steady offset.

  MECHANISM 1 (projection mismatch) — DROPPED as a visible cause. It would show identically on iOS; iOS is clean. At most it is a sub-pixel latent inaccuracy at viewport edges/high zoom that the Y-flip and stale-SDF dwarf. Do not file it as the Pixel 4a bug. (Retained as a note, not a root cause.)

test: Cross-platform parity on IDENTICAL SHA a4dbd17 is the decisive experiment. iOS clean + Android Y-inverted + X-correct + magnitude-correct ⇒ a backend coordinate-convention difference, the textbook Flutter fragment-shader Y-axis class. The shader ALREADY contains the canonical guard (`#ifdef IMPELLER_TARGET_OPENGLES { fragUv.y = 1.0 - fragUv.y; }`, atmospheric_fog.frag:267-269) — its existence proves the author knew the hazard; the bug is that the guard's CONDITION does not match the Pixel 4a's actual backend (either the device runs Impeller-Vulkan where the guard is correctly skipped but a flip is STILL needed for the engine-supplied `ui.Image` sampler / FlutterFragCoord on this path, or it runs a backend where the macro is not defined as expected). fog_transform invariants (canvasTx/Ty==0, uOffsetY==pixelOriginY bit-for-bit, all 24 rollups) still hold — and they are EXPECTED to hold: a GPU-side Y-convention flip is completely invisible to Dart-side logs because the Dart values are all correct; the divergence is purely in how the GPU interprets `FlutterFragCoord` / texture V.
expecting: CONFIRMED by cross-platform parity. Backend logcat capture (walk-2/backend-logcat.txt) showed Impeller (Vulkan logged first + GL context 17ms later) — NOT Skia. The `#ifdef IMPELLER_TARGET_OPENGLES` guard is therefore unreliable on this device either way (inert on Vulkan / active-but-insufficient on GLES). The fix does NOT depend on disambiguating the rasterizing backend: it replaces the macro guard with an explicit Dart-driven `Platform.isAndroid` uniform — backend-honest, one source of truth.
next_action: FIX APPLIED (FOG-20). Awaiting the developer's cross-platform verification walk on the same fix SHA — Android: up/down pan now anchored + red halo anchored to the reveal hole; iOS: pixel-identical to before. After the walk confirms, revert the RED TINT diagnostic and archive this session.

## Symptoms

expected: "phone agnostic since it's math". The reveal disc is anchored to the world (lat/lon), so it should remain stationary relative to the basemap during pan. Same as iPhone 17 Pro Walk #1 leg which the developer just confirmed "still working perfectly".
actual: During pan on Pixel 4a (Adreno 618, Android 13), a "whitish artefact" appears that has the SAME SHAPE as the revealed (de-fogged) disc but moves around with the pan. The actual revealed area appears correct (stationary relative to the map); the ghost is a separate visual layer that drifts.
errors: Zone mismatch warning at app boot (line 2 of log) — `BindingBase.debugCheckZone`, "The Flutter bindings were initialized in a different zone than is now being used." Possibly load-bearing for backend selection.
reproduction:
  - device: Pixel 4a (Adreno 618, Android 13)
  - build: sideload from `5e9f37d` (the only change since iPhone-pass: AndroidManifest location permissions, NO rendering code touched)
  - action: pan the map manually while the walk simulator is creating reveal discs
  - log: `walk-evidence/pixel4a-walk-1/20260505T180856Z_logs.txt` (607 KB, 1604 lines)
started: NEW failure mode on Pixel 4a Walk #1. Phase 4 closed entirely on iPhone — Pixel 4a was never walked before today. So the mechanism likely existed since shader pipeline was wired but never observed on iOS.

## Eliminated

- hypothesis: backend disposition (Impeller-Vulkan vs Skia-OpenGL ES) directly determines the bug
  evidence: log contains zero Impeller / OpenGL / EGL / Adreno / Skia / vulkan substrings — disposition not recorded by app logger. The mechanism we ultimately confirmed (stale SDF) is backend-AGNOSTIC; the bug would manifest on either backend at the same pace. Backend disposition is at most an indirect amplifier (Impeller may take longer to rasterize the SDF to ui.Image on Adreno 618, but the buildFromDiscs is pure Dart CPU work — `RevealedSdfBuilder` is analytic, no GPU involvement). Setting aside.
  timestamp: 2026-05-05T20:50:00Z

- hypothesis: large-magnitude `uPixelOrigin` (68M at zoom 19) causes FP32 precision degradation on Adreno 618 mediump, producing noise-pattern drift that LOOKS LIKE a moving shape
  evidence: ruled out because (a) the developer described the artefact as having the SAME SHAPE as the reveal disc — the disc shape is encoded in the SDF (256x256 ui.Image), NOT in the noise function. FP32 precision degradation in noise sampling would produce blocky / banded noise patterns, not disc-shaped silhouettes. (b) The shader's `worldPx = fragUv * uResolution + uPixelOrigin` puts `uPixelOrigin` (68M) directly into `worldPx`, then divides by `(kNoiseTilePx * uZoomScale) = (384 * 64) = 24576`, giving noiseUv ≈ 2766. FP32 mediump still has 4-5 decimal digits of fractional resolution at this magnitude — not catastrophic. (c) Confirmed cosmetic-only: noise pattern degradation would NOT manifest as a moving-disc-shape ghost.
  timestamp: 2026-05-05T20:50:00Z

- hypothesis: DebugSpiralLayer leaking into production paint path
  evidence: ruled out — `debugSpiralEnabled` is a top-level `ValueNotifier<bool>` defaulting to `false` (lib/state/debug_spiral_state.dart:37). map_screen.dart line 469 conditional: `if (debugSpiralEnabled.value && _debugSpiralShader != null && _debugSpiralAtlas != null) DebugSpiralLayer(...)  else if (...) FogLayer(...)`. Mutually exclusive; default OFF; log shows no debug-spiral toggle entries. Production fog path only.
  timestamp: 2026-05-05T20:50:00Z

- hypothesis: clip path computed at one camera snapshot, fog shader at a different camera snapshot
  evidence: ruled out — fog_layer.dart line 308-310 `final MapCamera camera = MapCamera.of(context)` called EXACTLY ONCE per build (FOG-07 KEYSTONE), captured into local final, passed by constructor to painter. Painter NEVER re-reads context. Both `computeFogClipPath(camera, discs)` (line 496) and `appliedPixelOrigin = camera.pixelOrigin` (line 566) consume THE SAME camera value. The dart-side math is correct; this is NOT a multi-snapshot issue.
  timestamp: 2026-05-05T20:55:00Z

- hypothesis: double-rendering / second pass of the reveal mask via a separate widget
  evidence: ruled out — only one CustomPaint with one painter (FogLayer's `_FogPainter`). The clip path and fog drawRect are inside one canvas.save/restore. Wisps render INSIDE the same save/restore, with their own LatLng → screen projection (correct, FOG-07 keystone). No second pass.
  timestamp: 2026-05-05T20:55:00Z

- hypothesis: vec4 component reordering on Impeller/Metal (BUG-014 regression)
  evidence: ruled out by code review — uSdfRect was decomposed into four scalar floats per-axis (slots 37-40) precisely to bypass this risk. Shader line 236-237: `vec2 sdfOrigin = vec2(uSdfRectOriginX, uSdfRectOriginY); vec2 sdfSize = vec2(uSdfRectSizeX, uSdfRectSizeY)`. Plus this is Android (Vulkan/OpenGL ES), not Metal. Even if a SPIR-V transpilation reordering occurred on Adreno SPIRV-Cross, the per-axis decomposition prevents it.
  timestamp: 2026-05-05T20:55:00Z

## Evidence

- timestamp: 2026-05-05T20:30:00Z
  checked: log file structure
  found: log is 1604 lines, structured as one JSON object per line. Loggers present: `infrastructure.logging.file_logger`, `flutter.error`, `presentation.screens.permission_gate`, `infrastructure.pmtiles`, `domain.location`, `infrastructure.mirk.sdf` (per-paint FINE + per-second INFO rollup), `infrastructure.mirk.frame_delta` (per-second rollup), `infrastructure.mirk.fog_transform` (per-second rollup), `infrastructure.mirk.wisp` (per-second rollup), `presentation.map`, `infrastructure.location.walk_simulator`. NO `dev_marker` entries (zero markers — clean run from instrumentation perspective). NO `Impeller` / `OpenGL` / `EGL` / `Adreno` / `vulkan` / `Skia` / `GraphicsBackend` substrings anywhere in the log → backend disposition is NOT recorded by the app's logger; we only know it's Android.
  implication: backend disposition (Impeller-Vulkan vs Skia-OpenGL ES) cannot be confirmed from the log; need to ask user OR infer from default behaviour. Flutter 3.29+ defaults to Impeller-Vulkan on Adreno 618 (Pixel 4a Android 13). Zero `dev_markers` means no instrumentation-detected anomaly (so e.g. canvasTx/Ty drift, NaN uniforms, etc. did NOT trigger). This is consistent with "math is fine; rendering is the source of truth".

- timestamp: 2026-05-05T20:30:00Z
  checked: `fog_transform` invariants (UX-02 + Phase 3.1 modulo elimination)
  found: in EVERY rollup, `canvasTxMin == canvasTxMedian == canvasTxMax == 0.000000`, same for canvasTy. AND `uOffsetXMedian == pixelOriginXMedian` exactly (and likewise X-min, X-max, Y-min, Y-medians, Y-max — bit-for-bit identical strings in the JSONL). Phase 3.1 modulo elimination invariant HOLDS. UX-02 (no canvas translation) HOLDS.
  implication: the dart-side math is correct on Android. The bug is NOT in `pixelOrigin` calculation, NOT in `Canvas.translate` leakage, NOT in the modulo-collapse logic. So the mechanism is either (a) shader-side sampling/coordinate, (b) compositing-layer split, (c) double paint from a debug overlay.

- timestamp: 2026-05-05T20:30:00Z
  checked: `pixelOrigin` trajectory during the recorded pan (lines 13–100 of log = first ~10 seconds)
  found: at t=0..3s, `pixelOriginX/Y` is stable around 68098635 / 46353357 (initial fix). At t=4s (line 50, second `1778004547`), `pixelOriginXMin` jumps to 63146482 (one outlier) but median is still 68098592. At t=5s (line 65), `pixelOriginXMin = 34463619`, median = 35788115, max = 57075329 — within a 1-second rollup, the value spans **22.6 million pixel-units**. By t=6s, min = 13M, median = 26M. By t=7s, min = 6.8M, median = 13.8M. By t=8s, min = 4.2M. The pan is moving the pixelOrigin by tens of millions of pixel-units within a single second.
  implication: the dart-side state is shifting by huge `pixelOrigin` deltas during pan. This is expected (panning across the world translates pixelOrigin), but: at HIGH zoom levels, the pixel-origin magnitude IS this large. The shader receives `uOffsetX = uOffsetY = pixelOrigin` (per Phase 3.1 collapse). On Android-Impeller-Vulkan, large-magnitude FP32 uniforms can lose precision in fragment-shader arithmetic (Adreno 618 has 32-bit float uniforms but interpolated `gl_FragCoord` arithmetic at e.g. value=68_000_000 has only ~2 significant digits in the fractional part). HOWEVER — the *shape* of the reveal disc is sampled from `sdf_image` (a 256x256 ui.Image), not computed from world-coords directly. So large-magnitude uOffset shouldn't deform the reveal disc's shape; it would only deform the noise pattern outside.

- timestamp: 2026-05-05T20:30:00Z
  checked: SDF rebuild cadence
  found: SDF rebuilds happen MUCH faster than 1/200ms during pan. e.g. lines 33–42 (one second of pan) show 5 rebuilds in ~500 ms (~100 ms apart). At lines 1207–1238 (heavy pan with 6→7 discs) the rebuild rate jumps to ~100ms each, and `frame_delta` at line 1221 reports `medianMicros: 73402` (73 ms median frame time, p95 80 ms). On Pixel 4a this is a frame stutter signal during pan but not a crash.
  implication: SDF rebuilds are happening per-pan-tick at viewport-bbox change, not at a fixed cadence. Each rebuild produces a NEW `ui.Image 256x256`. If the shader is sampling the OLD ui.Image while pan delivers a NEW pixelOrigin (or vice versa), we get a frame mismatch — UV(reveal-disc) computed with NEW transform but sampling OLD SDF texture. On Adreno-Impeller this could manifest as a shape-correct ghost lagging behind the new transform by ~1 frame. iPhone Metal frame fences are tighter so the swap is atomic from the user's POV.

- timestamp: 2026-05-05T20:30:00Z
  checked: project file layout
  found: production fog shader at `assets/shaders/atmospheric_fog.frag`. Debug shader at `assets/shaders/atmospheric_fog_debug_spiral.frag`. Dart code: `lib/presentation/widgets/fog_layer.dart`, `lib/presentation/widgets/debug_spiral_layer.dart`, `lib/presentation/widgets/fog_clip_path.dart`, `lib/state/debug_spiral_state.dart`, `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart`. Need to read these to map the paint pipeline.
  implication: the existence of `debug_spiral_layer.dart` + `debug_spiral_state.dart` means there IS a debug overlay system. Need to verify it's gated off in the build the developer is running.

## Evidence (continued)

- timestamp: 2026-05-05T20:50:00Z
  checked: SDF rebuild duration distribution across the full session
  found: 511 SDF rebuilds across 1m54s walk. Distribution: min=14ms, max=580ms, mean=90.5ms. Top-10 frame_delta `maxMicros`: 347, 357, 363, 391, 391, 405, 410, 414, 416, **429** ms. Last second of session: 43 discs, rebuild=415ms. The slowest rebuilds correlate with disc count (more discs → more circle-distance evaluations in the analytic SDF builder per pixel of the 256x256 grid). At 60 fps, a 415ms rebuild = 25 frames where the OLD SDF is bound to the shader; at 120 fps target = 50 frames.
  implication: stale SDF is bound to the shader for sustained windows during pan. Multiple consecutive long rebuilds (the developer pans → bbox changes → new rebuild → during rebuild user keeps panning → new bbox → rebuild kicks in again, queueing/race) compound the visual artifact.

- timestamp: 2026-05-05T20:55:00Z
  checked: code path for SDF rebuild → painter binding (`fog_layer.dart`)
  found: line 256-269: `_pendingSdfBuild` is reset on disc list change (`_onDiscsChanged`); line 319: `_pendingSdfBuild ??= _resolveSdfImage(discs, viewport)` — kicked off in build(). Line 333: `sdfImage: _currentSdfImage` is passed by reference to the painter. Lines 344-352: `_resolveSdfImage` AWAITS the cache then `setState` updates `_currentSdfImage`. **Critical**: while the await is pending, `_currentSdfImage` retains the PREVIOUS value. The Ticker (`_ticker.start()` line 260) fires per frame regardless, the painter's `_repaint` notifier triggers paint — every frame during rebuild paints with the STALE SDF.
  implication: this is the bug. The stale SDF lives in `_currentSdfImage` until the future completes. There is no "null out the stale image during rebuild" path — that would produce a one-frame "no fog" flash, which is why the current design keeps it pinned. But the trade-off (stale-but-still-rendered vs no-fog-flash) was made on the assumption that rebuilds complete within ~50ms (true on iOS); on Pixel 4a's much slower CPU, stale windows reach 580ms.

- timestamp: 2026-05-05T20:58:00Z
  checked: clip-path correctness during stale-SDF window
  found: `computeFogClipPath(camera: camera, discs: discs)` (fog_clip_path.dart line 71) computes the clip path from the current `discs` list and `camera.latLngToScreenPoint(disc.lat, disc.lon)`. This is fully world-anchored — disc holes appear at the CORRECT screen position regardless of SDF staleness. The clip removes the disc circle from the path → fog NOT drawn inside disc → basemap shows through.
  implication: the actual reveal hole IS at the correct world position. The "ghost" is NOT the reveal hole moving; it is a SECOND visual effect that has the same shape as the disc, displaced from the actual hole. Mechanism: the production fog shader applies boundary effects (lines 320-352, 406-433) keyed on `sdf` (sampled from the stale SDF at fragUv). When the stale SDF's "disc" sits at a different fragUv than the clip-path-cut disc, the shader paints "boundary glow + density boost + watercolour bleed" at the OLD UV. These effects BRIGHTEN the fog (`density *= 1.0 + boundaryGlow * uBoundaryDensityBoost` line 351 → boost=0.15 → 15% density bump near boundary; `boundaryAlpha = sharp + bleed` makes the fog slightly transparent within `uBoundarySharpDistance + uBoundaryBleedDistance = 0.04 + 0.12 = 0.16` of the SDF boundary on the OLD-SDF side). The "whitish" character matches the highlight palette `0xFF7C8AA3` (line 72 of constants.dart) which is what the fog tints toward in light density regions.

- timestamp: 2026-05-05T21:00:00Z
  checked: cross-platform parity — why iPhone 17 Pro Walk #1 passed
  found: iPhone 17 Pro (A19 Pro) is roughly 5-8× faster than Adreno 618 on single-thread CPU work. `RevealedSdfBuilder.buildFromDiscs` is analytic (no GPU); the cost is dominated by `for each pixel of 256x256 = 65_536 pixels: for each intersecting disc: compute meterDistance` plus the final `ImmutableBuffer` upload. At 5-8x perf differential, iPhone rebuilds for 43 discs ≈ 50-80ms instead of 415ms. At 50ms, stale-SDF window = 3-6 frames at 120Hz = imperceptible to the eye. At 415ms, stale-SDF window = 25-50 frames = clearly visible "ghost lagging behind during pan".
  implication: the bug is not platform-specific in mechanism; it is platform-specific in MAGNITUDE. The architectural assumption (stale SDF imperceptible because rebuilds are sub-frame) is broken on lower-end Android hardware. Adreno 618 / Pixel 4a is the floor of the targeted hardware spectrum; mid-range Android may also exhibit this to a lesser degree. PERF-06 budget (FrameDeltaProbe medianGreen ≤ 16ms, p95Green ≤ 32ms) was set assuming sub-frame SDF work; this assumption is invalidated for the Adreno 618 lower bound.

## Evidence (Walk #2 — 2026-05-14, build a4dbd17 RED TINT diagnostic)

- timestamp: 2026-05-14T22:10:00Z
  checked: Walk #2 log structure + scope — `20260514T195717Z_logs.txt/20260514T195717Z_logs.txt` (268 JSONL lines, ~54s session 21:57:17→21:57:51 of which ~31s is active gesture)
  found: 24 fog_transform rollups, 18 sdf rollups, 25 frame_delta rollups, 84 buildFromDiscs done-entries, 0 dev_marker entries, 1 presentation.map fix (48.52859, 2.65517 ±16m). discCount stays at 1 the whole walk (single reveal disc — the developer "did not move", only panned/pinched the map). intersecting `inside=` % falls 17.7% → 0.3% as the camera pans/zooms the disc toward a screen edge. Boot-time Zone-mismatch SHOUT present again (same as Walk #1, load-bearing-unknown but not implicated). Burst of ~7 `TileLoader._renderTile "Cancelled"` SHOUTs at 21:57:32 — benign vector_map_tiles tile-cancellation during fast pan, not fog-related.
  implication: clean instrumentation run. Single disc + "did not move" means the screenshot's offset CANNOT be a multi-disc or GPS-drift artefact — it is purely a projection/sampling issue on one stationary disc.

- timestamp: 2026-05-14T22:14:00Z
  checked: fog_transform invariants across all 24 Walk #2 rollups (re-verifying the Walk #1 Dart-math-is-correct finding on the new build)
  found: `canvasTxMin/Median/Max == canvasTyMin/Median/Max == 0.000000` in ALL 24 rollups. `uOffsetX{Min,Median,Max} == pixelOriginX{Min,Median,Max}` and `uOffsetY* == pixelOriginY*` BIT-FOR-BIT (identical strings) in ALL 24 rollups — script-checked, 24/24 hold. pixelOrigin magnitude ~68M at session start (zoom 19, kPocInitialZoom=19 → uZoomScale = pow(2,19-13) = 64), sweeping down through ~21M, ~9M as the developer zooms out / pans.
  implication: UX-02 (no canvas translation leak) and the Plan 03.1-04 "uOffset == full-precision pixelOrigin" invariant BOTH still hold on build a4dbd17. The Dart-side pixelOrigin forwarding and canvas-frame alignment are NOT the bug. Confirms the misalignment lives in the SDF texture's own coordinate space, not in uPixelOrigin or Canvas.translate.

- timestamp: 2026-05-14T22:18:00Z
  checked: RED TINT diagnostic outcome (commit a4dbd17 added `fogColor = mix(fogColor, vec3(1,0,0), boundaryGlow * 0.85)` at atmospheric_fog.frag line 415, purpose-built to make the SDF-derived boundaryGlow layer screaming red)
  found: developer screenshot — blue dot + small CORRECT reveal disc at bottom-center (clip-path hole world-anchored, stationary around the stationary blue dot exactly as expected); a large bright RED halo with white center grossly displaced to upper-left-center, ~half a screen away from the hole. The diagnostic was explicitly designed to disambiguate: "if the red halo is displaced from the hole, the SDF-driven boundary effects (Layer 1.5) are the misaligned layer." The halo IS displaced → CONFIRMED: the SDF-driven boundary layer is the misaligned thing; the clip-path reveal hole is correct.
  implication: Q1 ANSWERED. The reveal hole is genuinely world-anchored (clip path via `camera.latLngToScreenPoint`). Only the SDF-keyed boundary layer drifts. The "whitish ghost" of Walk #1 and the "red halo" of Walk #2 are the SAME layer — boundaryGlow / boundaryAlpha / density-boost — just recoloured by the diagnostic.

- timestamp: 2026-05-14T22:22:00Z
  checked: transient-vs-persistent — were SDF rebuilds in flight when the steady offset was observed? (Q3)
  found: session tail epochs 1778788669, 670, 671 (last 3 seconds, 21:57:48.3 → 21:57:51): pixelOriginX/Y BIT-IDENTICAL across all three rollups (9236367.866141 / 6287550.761233) → camera fully AT REST. frame_delta median collapses to 1.5-1.6ms (p95 3-6ms) → no paint stalls. The last buildFromDiscs `done` is at 21:57:48.304; the sdf rollup stream STOPS after epoch 1778788668 → ZERO SDF rebuilds during the at-rest tail. The developer's report ("the mirk isn't fixed on the map anymore... the revealed area does stay... the red halo is being offset") describes a SUSTAINED, steady offset. STALE-SDF-DURING-REBUILD predicts the offset would SNAP BACK ~200-580ms after motion stops and the rebuild completes — it does not. The offset is therefore PERSISTENT and present with NO rebuild in flight.
  implication: Q3 ANSWERED. STALE-SDF is NOT the whole story. There is a STEADY-STATE coordinate-space mismatch between SDF sampling and the clip path that exists at rest. STALE-SDF (now Mechanism 2) only adds a transient wobble on top during the rebuild storm.

- timestamp: 2026-05-14T22:26:00Z
  checked: SDF builder coordinate space vs shader uSdfRect vs clip-path projection (root-cause source review for Mechanism 1)
  found: `RevealedSdfBuilder.buildFromDiscs` (revealed_sdf_builder.dart lines 125-126, 162-163) builds the 256x256 SDF in a LINEAR viewport-bbox-normalized space: `dLat = north - south`, `dLon = east - west`, disc centre `cx = (disc.lon - viewport.west)/dLon * n`, `cy = (viewport.north - disc.lat)/dLat * n`. This is a straight linear remap of `camera.visibleBounds`. The shader (`atmospheric_fog.frag` lines 236-239) samples it with `sdfUv = (fragUv - sdfOrigin)/sdfSize` where uSdfRect is the IDENTITY (0,0,1,1) — hard-locked at `fog_layer.dart` line 617 `sdfRect: const (0.0, 0.0, 1.0, 1.0)` per "RESEARCH §Anti-Pattern 1". So the shader assumes SDF texel (u,v) maps 1:1 to screen fragment (u,v). MEANWHILE the clip path (`fog_clip_path.dart` line 83) positions the reveal hole with the TRUE projection `camera.latLngToScreenPoint(LatLng(disc.lat, disc.lon))`. The two disagree: (a) Web-Mercator screen-Y is NONLINEAR in latitude, so `(north - lat)/dLat` (linear) ≠ the true Mercator screen-Y fraction; (b) `camera.visibleBounds` is the axis-aligned bbox of the viewport, which does not necessarily map 1:1 onto the [0,1]² screen rect that `fragUv` spans (any viewport rotation, or flutter_map's bounds-vs-size relationship, breaks the assumption). The displacement is a FIXED function of (zoom, disc screen position) — it does not depend on rebuild state, which is exactly the at-rest steady offset observed.
  implication: ROOT CAUSE of Mechanism 1 identified. The identity uSdfRect is only valid if the SDF were built in true screen-projection space; it is built in linear-lat/lon space instead. This is a genuine coordinate-space bug, NOT merely a throughput/staleness symptom. It was iPhone-masked NOT because iOS projects differently, but because: at the zooms/positions the iPhone Walk #1 happened to use, the disc sat near screen-centre where linear-remap ≈ true-projection (error → 0 at the viewport centre and grows toward the edges); the Pixel 4a Walk #2 panned the disc toward a screen edge (`inside%` 17.7→0.3) where the linear-vs-Mercator error is large and visible. Magnitude also grows with zoom (zoom 19 here).

- timestamp: 2026-05-14T22:30:00Z
  checked: pan-vs-pinch (Q2) + FPS discrepancy (Q4) + iOS-clean reconciliation (Q5)
  found:
    Q2 (pan vs pinch): the log does NOT separate pan-translation from pinch-zoom as distinct event streams — fog_transform only rolls up pixelOrigin + center + canvasTx/Ty, and `uZoomScale` is NOT logged at all (it is derived in the painter at fog_layer.dart line 587 but never emitted). Inference from pixelOrigin trajectory: epochs show both translation (pixelOrigin X/Y sweeping) AND zoom (pixelOrigin magnitude collapsing 68M→21M→9M = zooming out). The developer's obs-2 ("it slides when I move/pinch") and obs-1 ("offset as I moved") are the SAME Mechanism-1 mismatch — pinch makes it WORSE because zoom changes both the Mercator-nonlinearity magnitude AND uZoomScale, but there is no SEPARATE pinch-only anchoring bug distinct from Mechanism 1. obs-2 "the mirk isn't fixed on the map anymore" is the developer re-describing the same displaced boundary/red layer as "the mirk", now noticing it tracks the gesture rather than the world. No third mechanism.
    Q4 (FPS discrepancy 13fps screen vs 2.3ms FrameDeltaProbe): FrameDeltaProbe (frame_delta_probe.dart) does NOT measure frame time. Per its docstring + `recordCameraSnapshot`/`recordFogUniformPopulation`, it measures ONLY the delta between FogLayer.build reading `MapCamera.of(context)` and `_FogPainter.paint()` reaching `recordFogUniformPopulation` — i.e. the camera-snapshot→uniform-population latency, a tiny CPU slice INSIDE one paint. It says nothing about raster thread, GPU, SDF-rebuild blocking, or actual frame cadence. Corroborating: frame_delta sampleCount is only ~12-15/sec, NOT ~60 — the probe only records on paints that actually ran, and during the rebuild storm many frames are dropped, so the probe's own median is survivorship-biased toward fast frames. The real ~75ms/frame (13fps) is the `buildFromDiscs` analytic CPU work (Walk #2 maxMs 680ms, many 200-525ms) running on the UI isolate via the `await` in `SdfCache.getOrBuild` called from `fog_layer.dart` line 319 — it blocks the platform/UI thread, starving the raster cadence. FrameDeltaProbe is the WRONG instrument for PERF-06 frame-rate claims; PERF-06 needs a real frame-callback delta or `SchedulerBinding` timing, not this probe.
    Q5 (iOS clean): reconciled WITHOUT any positional-code change. iOS is clean for TWO compounding reasons — (1) Mechanism 1: iPhone Walk #1 happened to keep the disc near screen-centre at its chosen zooms, where linear-remap ≈ true-projection (error vanishes at viewport centre); (2) Mechanism 2: A19 Pro rebuilds the SDF ~5-8× faster so the stale window is sub-perceptual. Neither requires different projection math on iOS — same code, the bug is just exercised harder by Pixel 4a's edge-panning + slow CPU. The diff 3326f4b..a4dbd17 (red mix + manifest only) confirms this is NOT a regression; both mechanisms predate the iPhone-only Phase 4 closure.
  implication: all five orchestrator questions answered. No regression. Two pre-existing mechanisms, Mechanism 1 dominant + persistent + a real coordinate bug, Mechanism 2 secondary + transient. FrameDeltaProbe mis-scoped for PERF-06.

## Evidence (Cross-platform walk — 2026-05-14, build a4dbd17 RED TINT, IDENTICAL SHA both devices)

- timestamp: 2026-05-14T23:40:00Z
  checked: cross-platform parity on identical SHA a4dbd17 — the decisive experiment that the prior Mechanism-1-dominant theory could not survive
  found:
    iOS (iPhone 17 Pro, Impeller-Metal): essentially CORRECT. The reveal hole AND the red boundary halo stay synced TOGETHER and both stay anchored to the basemap during pan and zoom. Only a small transient separation during FAST movement that snaps back together (consistent with minor Mechanism 2 stale-SDF on fast hardware). NO persistent offset, NO axis inversion.
    Android (Pixel 4a, Adreno 618, Android 13): after careful isolation by the developer — (a) the mirk/reveal layer and the basemap move at the SAME SPEED (rules out devicePixelRatio / any scaling error); (b) the X axis (left/right) pan is CORRECT; (c) the Y axis (up/down) is INVERTED (pan up → mirk moves down; pan down → mirk moves up); (d) the red halo is "baked into the mirk" — it moves consistently with the reveal content, there is NO independent halo-vs-reveal scaling offset; the whole shader-rendered content appears Y-inverted as one rigid block; (e) the earlier-session description "the red halo is offsetting itself from the revealed area" is the SAME Y-flip seen before the axis was isolated.
  implication: a platform-AGNOSTIC math bug (the prior Mechanism 1 — pure Dart linear-vs-Mercator remap, identical code on both platforms) CANNOT produce a platform-SPECIFIC symptom. iOS would show it identically. It does not. Therefore Mechanism 1 is FALSIFIED as the visible cause. The real signature — correct on Metal, Y-inverted on the Android backend, X unaffected, magnitude correct — is the textbook Flutter fragment-shader backend Y-axis-convention class.

- timestamp: 2026-05-14T23:45:00Z
  checked: where in the pipeline the Y-flip lives — shader-rendered content vs Dart-drawn clip path (the CRITICAL fix-location distinction)
  found: the developer reports the reveal AREA stays correct/anchored AND moves WITH the red halo. Two surfaces are involved and they are subject to DIFFERENT coordinate systems:
    1. The clip-path reveal HOLE — `computeFogClipPath` (fog_clip_path.dart:71-94) builds a `ui.Path` from `camera.latLngToScreenPoint(disc)` and `canvas.clipPath`es it. This is pure Canvas geometry; it inherits the Canvas transform, NOT `FlutterFragCoord`. Canvas geometry is Y-consistent across backends. → the hole is correct on both platforms.
    2. The shader-rendered CONTENT — the fog `drawRect` filled with the FragmentShader (fog_layer.dart:629). EVERYTHING the shader computes keys off `vec2 fragUv = FlutterFragCoord().xy / uResolution` (atmospheric_fog.frag:262): the noise `worldPx` AND `sampleSdf(fragUv)` → `texture(uSdf, sdfUv)` with identity uSdfRect so `sdfUv == fragUv`. If `FlutterFragCoord().y` (or the engine's texture-V convention) is flipped on the Android backend, the ENTIRE shader output — SDF reveal silhouette + boundaryGlow/boundaryAlpha + RED TINT + noise — is Y-mirrored together as one block, exactly matching "the red halo is baked into the mirk and the whole thing is Y-inverted."
    Resolution of the developer's slightly ambiguous wording: it is the SHADER-RENDERED CONTENT that is Y-inverted (FlutterFragCoord.y / SDF texture V), NOT the clip-path hole. The hole stays put; the shader-painted fog+boundary+noise inside/around it is the Y-flipped surface. Note the developer perceives the de-fogged disc as "staying" partly because the clip hole is correct AND, for a roughly-centred single disc, a Y-mirror of a near-symmetric blob is not obviously "moved" — but the boundary halo (asymmetric, off to one side) makes the flip unmistakable.
  implication: the fix belongs in the SHADER (or in how its inputs are conditioned), NOT in the clip path and NOT in `RevealedSdfBuilder`. This also means the bug is confined to the cosmetic boundary/noise layer — the reveal hole (the load-bearing "what is de-fogged") is correct on every platform.

- timestamp: 2026-05-14T23:50:00Z
  checked: WHY Android-specific — the exact backend coordinate-convention difference
  found: Flutter/Impeller documented behaviour (docs.flutter.dev fragment-shaders + flutter/engine impeller/docs/coordinate_system.md): Impeller's canonical coordinate system is the Metal one (top-left origin, Y-down). On iOS the backend IS Impeller-Metal → `FlutterFragCoord` and engine-supplied `ui.Image` samplers are in the canonical convention → the shader is correct. On the OpenGLES backend the Y axis is reversed and "when targeting OpenGLES the y-coordinates of the texture will be flipped so the fragment shader should un-flip the UVs" — the canonical guard is `#ifdef IMPELLER_TARGET_OPENGLES { uv.y = 1.0 - uv.y; }`. The shader at atmospheric_fog.frag:267-269 ALREADY HAS exactly this guard on `fragUv.y` — proving the author knew the hazard. So the bug is one of: (i) the Pixel 4a is on the OpenGLES backend and the `IMPELLER_TARGET_OPENGLES` macro IS being defined, but the single `fragUv.y` flip is not sufficient / is applied in the wrong place relative to the SDF texture sampling (a flip of `fragUv` flips BOTH the world-noise sampling AND the SDF-V together — but the SDF `ui.Image` texture's own V-origin may need an INDEPENDENT flip the engine applies differently from `FlutterFragCoord`); or (ii) the Pixel 4a is on Impeller-Vulkan (Adreno 618 + Android 13/API 33 supports Vulkan, which is the Impeller default) where `IMPELLER_TARGET_OPENGLES` is correctly NOT defined and the guard is correctly skipped — yet a Y-flip is STILL observed, pointing to the engine-supplied `ui.Image` sampler (`setImageSampler`) having a V-origin on the Android-Vulkan path that differs from the iOS-Metal path for `decodeImageFromPixels`-produced textures. Either way it is a backend texture/fragcoord Y-origin convention divergence; the macro-guarded single-line flip the author wrote does not cover the actual Android backend the Pixel 4a runs.
  implication: a positive backend identification is needed to choose the fix's `#ifdef` precisely. The app logger records NO backend string (confirmed: zero Impeller/Vulkan/GLES/Skia/Adreno/EGL substrings in BOTH walk logs) — a one-off `adb logcat | grep -iE "impeller|vulkan|gl_renderer|gles"` on the Pixel 4a at app start will name it. Without that, the fix must be written defensively (see fix section).

- timestamp: 2026-05-14T23:52:00Z
  checked: reconciliation with the prior agent's Dart-side log findings (uOffsetY == pixelOriginY bit-for-bit, canvasTx/Ty == 0 in all 24 rollups)
  found: those invariants still hold and are EXPECTED to hold under a backend-Y-flip. `fogTransformLogger` records Dart-side values: `camera.pixelOrigin`, `canvas.getTransform()`, the forwarded `appliedUOffset`. All of those ARE correct — the Dart code computes them right. A backend Y-convention flip happens entirely on the GPU, in how the fragment stage interprets `FlutterFragCoord` and samples the bound texture. It is structurally INVISIBLE to any Dart-side log. The prior agent correctly concluded "the Dart math is right"; the error sits one layer below the lowest thing the app instruments.
  implication: the existing instrumentation cannot see this bug. Confirming it on-device needs either the logcat backend capture (to name the backend) or a shader-level diagnostic (e.g. output `fragColor = vec4(FlutterFragCoord().y/uResolution.y)` as a gradient and check which corner is bright on each platform). No amount of fog_transform/sdf JSONL will surface it.

## Resolution

root_cause: ANDROID-SPECIFIC Y-AXIS FLIP OF THE SHADER-RENDERED FOG CONTENT — a backend coordinate-convention divergence, NOT a regression, NOT a Dart-math bug, NOT the previously-theorised projection mismatch.

  The decisive evidence is cross-platform parity on IDENTICAL SHA a4dbd17: iOS (Impeller-Metal) renders the fog + boundary halo correctly anchored to the basemap; Android (Pixel 4a / Adreno 618 / Android 13) renders the ENTIRE shader output Y-inverted as one rigid block — X-axis correct, magnitude correct (same pan speed as basemap), only the Y axis sign-flipped. A platform-agnostic Dart math bug cannot do this; a backend `FlutterFragCoord` / texture-V Y-origin convention difference is exactly this signature and is a documented Flutter fragment-shader hazard.

  WHERE: everything the shader paints keys off `vec2 fragUv = FlutterFragCoord().xy / uResolution` (atmospheric_fog.frag:262) — both the world-coordinate noise (`worldPx`) and `sampleSdf(fragUv)` → `texture(uSdf, sdfUv)` (identity uSdfRect ⇒ `sdfUv == fragUv`). So a Y-flip of `FlutterFragCoord().y` (or of the engine-supplied `ui.Image` sampler's V origin) mirrors the SDF reveal silhouette + boundaryGlow + boundaryAlpha + RED TINT + noise all together. The Dart-drawn clip-path reveal HOLE (`computeFogClipPath` via `camera.latLngToScreenPoint` + `canvas.clipPath`) is plain Canvas geometry, Y-consistent across backends, and is CORRECT on both platforms. So the bug is shader-rendered-content-only; the load-bearing reveal hole is fine everywhere.

  WHY ANDROID-ONLY: Impeller's canonical coordinate system is Metal's (top-left, Y-down) → iOS is correct by construction. On Android the backend is either Impeller-Vulkan (Adreno 618 + API 33 → Vulkan-capable → the Impeller default) or the legacy OpenGLES fallback; on the GLES path the engine flips texture/Y and shaders must `uv.y = 1.0 - uv.y` under `#ifdef IMPELLER_TARGET_OPENGLES`. The shader ALREADY contains exactly that guard (lines 267-269) on `fragUv.y` — proving the hazard was known — but the symptom proves the guard does not match the Pixel 4a's actual backend: either the macro is defined and the single `fragUv.y` flip does not also correct the SDF `ui.Image` sampler's V origin, or the device is on Impeller-Vulkan where the macro is (correctly) not defined yet a flip is still needed for the `setImageSampler`-bound `decodeImageFromPixels` texture on the Android-Vulkan path. Backend identification is currently INFERRED — the app logs no backend string (confirmed absent in both walk logs).

  WHY iPHONE-MASKED: not a coincidence of zoom/position (that was the falsified Mechanism-1 explanation) — it is structural. iOS runs Impeller-Metal, the canonical convention; the shader is simply correct there. Android runs a different backend whose `FlutterFragCoord`/texture-V Y origin the macro-guarded single-line flip does not cover.

  MECHANISM 2 (STALE-SDF-DURING-REBUILD) — RETAINED, real, secondary, transient. The painter keeps the previous `_currentSdfImage` bound while `buildFromDiscs` is in flight (fog_layer.dart:333/344-352). On iOS this is the only residual (small transient on fast motion, snaps back). On Android it rides on top of the Y-flip. It is a throughput follow-up, not the Pixel 4a root cause.

  MECHANISM 1 (SDF linear-bbox-vs-Mercator projection mismatch) — DROPPED as a visible cause. It is platform-agnostic by construction and iOS is clean, so it is not what the developer sees. It may remain a sub-pixel latent inaccuracy at viewport edges / high zoom, but it is dwarfed by the Y-flip and stale-SDF and must NOT be filed as the Pixel 4a bug.

fix: APPLIED 2026-05-15 (FOG-20). Backend-honest Dart-driven Y-flip uniform replacing the unreliable `#ifdef IMPELLER_TARGET_OPENGLES` compile-time guard.

  ## What was applied (FOG-20)

  Single source of truth for the shader Y-convention: a new float uniform `uFragCoordYFlip`, appended at the END of the ABI slot sequence (slot 42 — `uZoomScale` is slot 41) to minimise index churn. Set to `1.0` on Android, `0.0` on iOS, by `_FogPainter.paint()` via `Platform.isAndroid`. Applied to `fragUv.y` as `mix(fragUv.y, 1.0 - fragUv.y, uFragCoordYFlip)` BEFORE `fragUv` feeds both the noise `worldPx` path AND `sampleSdf(fragUv)` — confirmed both derive from the same `fragUv` (`atmospheric_fog.frag` lines ~316 `worldPx = fragUv * uResolution + uPixelOrigin` and ~324 `sampleSdf(fragUv)`), so the whole shader-painted layer (SDF silhouette + boundaryGlow + RED TINT + noise) is corrected together as one block. The prior `#ifdef IMPELLER_TARGET_OPENGLES { fragUv.y = 1.0 - fragUv.y; }` block was removed → exactly ONE Y-convention correction, zero double-flip risk on any backend.

  iOS path byte-identical: at `uFragCoordYFlip == 0.0`, `mix(fragUv.y, 1.0 - fragUv.y, 0.0) == fragUv.y` exactly — the iOS (Impeller-Metal) render path is unchanged.

  ## Files changed (every line)

  - `assets/shaders/atmospheric_fog.frag`
    - Added `uniform float uFragCoordYFlip;` (slot 42) with doc-comment, after the `uZoomScale` (slot 41) declaration, before `uniform sampler2D uSdf;`.
    - Replaced the `#ifdef IMPELLER_TARGET_OPENGLES { fragUv.y = 1.0 - fragUv.y; }` block in `main()` with `fragUv.y = mix(fragUv.y, 1.0 - fragUv.y, uFragCoordYFlip);` + doc-comment.
  - `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart`
    - Slot-layout doc-comment table: added `| 42 | uFragCoordYFlip | float |` row.
    - `totalFloatSlots` bumped 42 → 43 (with FOG-20 doc-comment).
    - `setAll(...)` signature: added `required double fragCoordYFlip` (after `zoomScale`, before `sdfImage`).
    - `setAll(...)` body: added `shader.setFloat(42, fragCoordYFlip);` after `setFloat(41, zoomScale)` and before `setImageSampler(0, sdfImage)`.
  - `lib/presentation/widgets/fog_layer.dart`
    - Added `import 'dart:io' show Platform;`.
    - `FogShaderRenderer.render(...)` interface: added `required double fragCoordYFlip` + doc-comment.
    - `_FragmentShaderFogRenderer.render(...)`: added the param + forwards `fragCoordYFlip: fragCoordYFlip` into `FogShaderUniforms.setAll`.
    - `_FogPainter.paint()`: derives `final uFragCoordYFlip = Platform.isAndroid ? 1.0 : 0.0;` (after the `uZoomScale` derivation) and forwards `fragCoordYFlip: uFragCoordYFlip` to `shaderRenderer.render(...)`.
  - `lib/presentation/screens/shader_sanity_screen.dart`
    - Added `import 'dart:io' show Platform;`.
    - `_FogSanityPainter.paint()` `FogShaderUniforms.setAll(...)` call: added `fragCoordYFlip: Platform.isAndroid ? 1.0 : 0.0` so /sanity mirrors the live map.
  - `test/_helpers/recording_fog_shader_renderer.dart`
    - `RecordedFogRender`: added `final double fragCoordYFlip;` field + constructor param + doc-comment.
    - `totalFloatSlotsObserved` getter: `2+1+2+1+4+1+...` → `2+1+2+1+4+1+1+...` (+1 for fragCoordYFlip) + doc-comment update (31→32 observed, 42→43 total).
    - `RecordingFogShaderRenderer.render(...)`: added the param + captures `fragCoordYFlip: fragCoordYFlip`.
  - `test/infrastructure/mirk/shader/fog_shader_uniforms_test.dart`
    - Slot-count gate: assertion + test name updated 42 → 43 (FOG-20).
    - Both `renderer.render(...)` calls: added `fragCoordYFlip: 0.0`.
  - `test/presentation/widgets/fog_tile_period_invariant_test.dart`
    - `totalFloatSlots` static-source assertion: `42` → `43` (FOG-20) + doc-comment update.

  ## ABI consistency check

  - New uniform APPENDED at slot 42 (end of sequence) — every pre-existing slot index (0..41) unchanged, zero index churn.
  - Dart `setFloat` sequence: slot 42 added after slot 41, before the sampler. Consistent.
  - Count constant `FogShaderUniforms.totalFloatSlots`: 42 → 43. The two tests that pin it (`fog_shader_uniforms_test.dart`, `fog_tile_period_invariant_test.dart`) both updated.
  - Sibling debug shader `atmospheric_fog_debug_spiral.frag`: NOT touched. It does NOT share the `FogShaderUniforms.setAll` ABI — `_DebugSpiralPainter.paint()` (shader_sanity_screen.dart) sets its own slots 0..4 + sampler directly. Adding slot 42 to the production shader + `FogShaderUniforms.setAll` does not affect it. (Note: the debug-spiral shader still carries its own independent `#ifdef IMPELLER_TARGET_OPENGLES` block — left as-is; out of scope for this fix and it is a debug-only shader.)
  - `RecordingFogShaderRenderer` (interface impl) + all `.render(...)` / `FogShaderUniforms.setAll(...)` call sites updated for the new required param.
  - `flutter analyze lib test` → "No issues found!"

  ## Original fix-location note (retained for context)
  `assets/shaders/atmospheric_fog.frag` — the Y-handling block at lines 262-269 (the `fragUv` definition + the existing `#ifdef IMPELLER_TARGET_OPENGLES` guard). The fix is a shader change; `RevealedSdfBuilder` and `fog_clip_path.dart` are CORRECT and must NOT be touched.

  ## The fix itself (one-line-ish, but MUST be backend-correct on BOTH platforms)
  The fix depends on the backend identification — which is why a logcat capture should precede it:

  - If the Pixel 4a is on the OpenGLES backend (macro IS defined): the existing `fragUv.y = 1.0 - fragUv.y` flips `fragUv` for BOTH noise and SDF sampling. If the SDF reveal silhouette is STILL inverted relative to the noise, the engine-supplied `ui.Image` sampler needs an INDEPENDENT V-flip inside `sampleSdf` — i.e. `sdfUv.y = 1.0 - sdfUv.y` under the same `#ifdef`, applied to `sdfUv` only (atmospheric_fog.frag:238-239 area). Whole-content flip ⇒ the existing guard is simply not being compiled in; partial flip ⇒ add the SDF-V flip.
  - If the Pixel 4a is on Impeller-Vulkan (macro NOT defined): the canonical guard never fires, yet a flip is observed ⇒ the `setImageSampler`-bound `decodeImageFromPixels` texture has a different V origin on the Android-Vulkan path. The correct fix is a flip of the SDF sample V coordinate gated on a condition that is TRUE on Android-Vulkan and FALSE on iOS-Metal. There is no `IMPELLER_TARGET_VULKAN` user macro; the robust options are (a) confirm via logcat that GLES is actually in use and rely on `IMPELLER_TARGET_OPENGLES` after all, or (b) pass an explicit `uSdfVFlip` float uniform (0.0/1.0) set from Dart by platform (`Platform.isAndroid`) — explicit, testable, and backend-honest. Option (b) is the safest "correct on both platforms" form because it does not rely on a macro whose definition we have not positively confirmed.

  CRITICAL — do NOT regress iOS: the current shader is CORRECT on iOS. Any flip MUST be conditional (macro or uniform) so the iOS path is byte-for-byte unchanged. A bare unconditional `1.0 - y` would fix Android and invert iOS — the classic "fixed one platform, broke the other." The fact that the author already wrapped the existing flip in `#ifdef IMPELLER_TARGET_OPENGLES` shows the discipline; the fix must preserve it.

  ## Verification that it does not break iOS
  1. Re-walk BOTH platforms on the fix build (same SHA on both, as this walk was).
  2. iOS must remain pixel-identical to its current-correct behaviour (reveal + halo synced, anchored to basemap). Because the fix is macro/uniform-gated to the Android backend, the iOS code path is provably unchanged — but confirm empirically.
  3. Android: reveal hole, boundary halo, and noise must all stay anchored to the basemap during up/down pan (the Y axis that is currently inverted). X was already correct; confirm it stays correct.
  4. Cheap pre-walk shader diagnostic: temporarily output `fragColor = vec4(vec3(fragUv.y), 1.0)` and `fragColor = vec4(vec3(sampleSdf-V), 1.0)` as gradients — verify the bright edge is at the same screen edge on both platforms before/after the fix. This isolates FlutterFragCoord-Y vs texture-V independently.

  ## Backend capture (recommended before the fix)
  `adb logcat` on the Pixel 4a at app launch, grep `-iE "impeller|vulkan|gl_renderer|opengl es|gles"`. This positively names the backend (Impeller-Vulkan vs OpenGLES fallback) and decides between the macro-based fix and the explicit-uniform fix. The app's own logger does not record it (confirmed absent in both walk logs); consider adding a one-line backend-string log at startup so future walks self-document.

  ## Mechanism 2 (secondary — throughput, unchanged from prior analysis)
  Direction 2A — move `SdfCache.getOrBuild` / `buildFromDiscs` to a worker isolate, swap atomically: removes the UI-thread block (the ~75ms/frame, ~13fps cause) and shrinks the stale window. Phase-5.1 scope. Direction 2B (throttle rebuild dispatch / coarser SDF resolution) stacks as mitigation.

  ## PERF-06 / FrameDeltaProbe note (unchanged)
  FrameDeltaProbe measures camera-snapshot→uniform-population latency INSIDE one paint — it does NOT measure frame cadence, and is survivorship-biased (~12-15 samples/sec). PERF-06 frame-rate claims need a real `SchedulerBinding` frame-callback delta. Re-scope independently of this bug.

verification: PENDING DEVELOPER VERIFICATION WALK (cross-platform, same fix SHA on both devices).

  Expected verification-walk result:
  - Android (Pixel 4a / Adreno 618 / Android 13): the previously Y-inverted up/down pan is now anchored — pan up moves the fog/boundary/noise up WITH the basemap. X-axis was already correct and stays correct. The RED TINT halo is anchored to the reveal hole (no longer "baked into the mirk" and displaced). `uFragCoordYFlip = 1.0` is forwarded on Android.
  - iOS (iPhone 17 Pro / Impeller-Metal): pixel-identical to the current-correct behaviour — reveal hole + red halo synced and anchored to the basemap during pan and zoom. `uFragCoordYFlip = 0.0` → `mix(y, 1-y, 0.0) == y` exactly → the shader's `fragUv` is untouched → iOS render path byte-identical to pre-FOG-20.
  - RED TINT diagnostic kept IN PLACE (atmospheric_fog.frag ~line 415) — it is the verification aid; the developer should see the red halo correctly anchored to the reveal hole on the fixed Android build. It gets reverted only after the fix is confirmed.

  Self-verified checks (cannot run on-device here):
  - `flutter analyze lib test` → "No issues found!" (0 warnings, 0 errors).
  - ABI: new uniform appended at slot 42 (end), zero index churn; `totalFloatSlots` 42→43; both pinning tests updated; all `.render()` / `setAll()` call sites updated.
  - iOS byte-identical by construction: `mix(fragUv.y, 1.0 - fragUv.y, 0.0)` is exactly `fragUv.y`.

files_changed:
  - assets/shaders/atmospheric_fog.frag
  - lib/infrastructure/mirk/shader/fog_shader_uniforms.dart
  - lib/presentation/widgets/fog_layer.dart
  - lib/presentation/screens/shader_sanity_screen.dart
  - test/_helpers/recording_fog_shader_renderer.dart
  - test/infrastructure/mirk/shader/fog_shader_uniforms_test.dart
  - test/presentation/widgets/fog_tile_period_invariant_test.dart
investigation_complete: true
fix_applied: true
recommended_path: |
  Phase 5 verdict: does NOT pass clean on Android. The Pixel 4a root cause is an
  ANDROID-SPECIFIC backend Y-axis-convention flip of the shader-rendered fog content
  (FlutterFragCoord.y / SDF texture V) — correct on iOS Impeller-Metal, Y-inverted on
  the Pixel 4a's Android backend, X-axis and magnitude both correct. It is a real
  rendering-correctness bug, but a NARROW and well-understood one: confined to the
  cosmetic fog/boundary/noise layer in atmospheric_fog.frag; the load-bearing reveal
  hole (clip path) is correct on every platform. NOT a regression (diff 3326f4b..a4dbd17
  is the RED TINT mix + manifest only). Recommend: (1) capture the Pixel 4a graphics
  backend via adb logcat to choose the fix's gate precisely; (2) apply the
  backend-gated Y-flip in atmospheric_fog.frag (existing #ifdef IMPELLER_TARGET_OPENGLES
  block, or an explicit Platform.isAndroid-set uSdfVFlip uniform if the device is on
  Impeller-Vulkan) — one-line-ish, MUST stay conditional so iOS is unchanged;
  (3) re-walk BOTH platforms on the same fix SHA to confirm Android fixed AND iOS not
  regressed; (4) schedule Direction 2A (SDF off the UI isolate) for the residual
  ~13fps / stale-SDF transient — separate, secondary; (5) drop the prior
  "Mechanism 1 projection mismatch" framing as the visible cause (falsified by iOS
  being clean on identical code) — keep it only as a possible sub-pixel latent note;
  (6) re-scope the PERF-06 FrameDeltaProbe (it does not measure frame rate). The
  same-Canvas + FOG-07 keystone + clip-path-as-hole-source-of-truth architecture
  remains sound; the defect is isolated to the shader's backend Y-convention handling.
