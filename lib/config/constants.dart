// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// Donor constants subset ported from `C:/claude_checkouts/GOSL-MirkFall/lib/config/constants.dart`.
//
// Only the constants referenced by the Phase 1 + BOOT-08 donor `.dart` files are
// included here — the parent's full constants file is ~880 lines and most of it
// concerns Phase 2+ subsystems (DB pragmas, download throttling, candlelight
// renderer tunables, etc.) that the POC does not exercise.
//
// Subset rationale:
// - [kMaxLogsDirBytes]: required by `lib/infrastructure/logging/file_logger.dart`
//   from Plan 01-04 (FileLogger prune-on-bootstrap).
// - [kMetersPerDegreeLat], [kEarthRadiusMeters]: required by
//   `lib/domain/revealed/reveal_disc.dart`,
//   `lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart`, and
//   `lib/infrastructure/mirk/tile_cell_iteration.dart` from Plan 01-03 (BOOT-08
//   donor port).
// - [kMirkFogSdfResolution] + the `kMirkFog*` palette/drift/shading subset:
//   required by `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart` and
//   `lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart` (Plan 01-03 BOOT-08
//   donor port). The Phase 3 fog renderer reads these uniforms verbatim from
//   the parent project's tuning sessions; values preserved unchanged.

// ---------------------------------------------------------------------------
// Logging — consumed by lib/infrastructure/logging/file_logger.dart (Plan 01-04).
// ---------------------------------------------------------------------------

/// Hard cap on total bytes used by `<app_docs>/logs/` after startup prune.
const int kMaxLogsDirBytes = 10 * 1024 * 1024; // 10 MB

// ---------------------------------------------------------------------------
// Geo conversions — consumed by lib/domain/revealed/reveal_disc.dart and
// lib/infrastructure/mirk/{sdf,tile_cell_iteration,mirk_projection}.dart
// (Plan 01-03 BOOT-08 donor port).
// ---------------------------------------------------------------------------

/// WGS-84 mean Earth radius in metres (per IUGG). Single source of truth for
/// great-circle distance maths across the revealed-domain code (`reveal_disc.dart`,
/// `revealed_sdf_builder.dart`).
const double kEarthRadiusMeters = 6371008.8;

/// Approximate metres per degree of latitude (WGS-84, equator-aligned).
/// Constant globally because a meridian is a great circle — accurate to
/// ~0.5 % at any latitude. Used by the analytic
/// `RevealedSdfBuilder.buildFromDiscs` and by `RevealDisc.intersectsBbox`
/// to convert metres ↔ degrees ↔ pixel space.
const double kMetersPerDegreeLat = 111320.0;

// ---------------------------------------------------------------------------
// Phase 3 fog shader uniforms — consumed by
// lib/infrastructure/mirk/shader/fog_shader_uniforms.dart and
// lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart (Plan 01-03 BOOT-08
// donor port). Values preserved verbatim from the parent project's
// 2026-04-26 tuner walk N+M bake — see GOSL-MirkFall §BUG-009 follow-up.
// ---------------------------------------------------------------------------

/// Resolution (square) of the CPU-built SDF texture passed to the fog shader as
/// `sampler2D`. 256² is a good cost/quality balance — the SDF is rebuilt only
/// when revealed cells change (user walks), not every frame.
const int kMirkFogSdfResolution = 256;

// Palette — Northern atlas indigo (research v2 Reference 11 / palette A).

/// Atmospheric base fog colour (ARGB). Cool desaturated indigo,
/// reads cartographic-mystic over both light and dark OSM tiles.
const int kMirkFogAtmosphericBaseColorArgb = 0xFF3A4358;

/// Atmospheric highlight colour — what bright, sun-facing fog regions
/// shade towards. Lighter blue-grey of the indigo palette.
const int kMirkFogAtmosphericHighlightColorArgb = 0xFF7C8AA3;

/// Atmospheric shadow colour — what dim, sun-shadowed fog regions
/// shade towards. Darker indigo end of the same palette.
const int kMirkFogAtmosphericShadowColorArgb = 0xFF1E2536;

/// Heavenly clouds base colour. Light dawn-grey with a slight warm
/// touch (Hebridean dawn split — research v2 palette B).
const int kMirkFogHeavenlyBaseColorArgb = 0xFFA8B5C4;

/// Heavenly clouds highlight — warm cream sun-side accent.
const int kMirkFogHeavenlyHighlightColorArgb = 0xFFE8DCC8;

/// Heavenly clouds shadow — cool grey-blue away-from-sun accent.
const int kMirkFogHeavenlyShadowColorArgb = 0xFF5D6878;

// Z-axis (time-slice) drift speeds — multi-rate motion (Reference 12).

/// Atmospheric far-octave (coarse) drift speed.
const double kMirkFogAtmosphericDriftZFar = 0.23;

/// Atmospheric mid-octave drift speed.
const double kMirkFogAtmosphericDriftZMid = 0.24;

/// Atmospheric near-octave (fine surface boil) drift speed.
const double kMirkFogAtmosphericDriftZNear = 0.23;

/// Heavenly far-octave drift.
const double kMirkFogHeavenlyDriftZFar = 0.11;

/// Heavenly mid-octave drift.
const double kMirkFogHeavenlyDriftZMid = 0.24;

/// Heavenly near-octave drift.
const double kMirkFogHeavenlyDriftZNear = 0.46;

// Spatial scales per octave.

/// Atmospheric far-octave spatial scale (big lazy blobs).
const double kMirkFogAtmosphericScaleFar = 2.9;

/// Atmospheric mid-octave spatial scale.
const double kMirkFogAtmosphericScaleMid = 5.1;

/// Atmospheric near-octave spatial scale (fine surface texture).
const double kMirkFogAtmosphericScaleNear = 10.5;

/// Heavenly far-octave scale.
const double kMirkFogHeavenlyScaleFar = 0.8;

/// Heavenly mid-octave scale.
const double kMirkFogHeavenlyScaleMid = 1.8;

/// Heavenly near-octave scale.
const double kMirkFogHeavenlyScaleNear = 3.6;

// Per-octave opacity weights.

/// Far-octave weight in the final density mix.
const double kMirkFogOpacityFar = 0.58;

/// Mid-octave weight.
const double kMirkFogOpacityMid = 0.58;

/// Near-octave weight.
const double kMirkFogOpacityNear = 0.58;

// Curl-noise advection.

/// Curl-noise warp amplitude (in noise UV units).
const double kMirkFogCurlAmplitude = 1.0;

/// Curl-noise potential field spatial frequency (static fallback when curlScale
/// auto-animation is disabled).
const double kMirkFogCurlScale = 0.8;

// Faux directional shading.

/// Faux-light direction (radians, 0 = +x). Slightly off-axis for NW-light.
const double kMirkFogLightDirRadians = -1.11;

/// Distance (in noise UV units) offset between the two density samples for faux
/// shading.
const double kMirkFogLightOffset = 0.46;

/// Strength of the faux-shading brightness modulation. Values >1.0 are intentional.
const double kMirkFogLightStrength = 1.67;

// Sub-grey hue variation.

/// Spatial scale of the hue-variation noise (coarser than density noise).
const double kMirkFogHueNoiseScale = 1.6;

/// Strength of the hue tint (0 = pure grey, 1 = pull fully toward base palette).
const double kMirkFogHueStrength = 0.44;

// Two-stop watercolour boundary.

/// Distance (SDF units) over which the SHARP inner gradient ramps from 0 to 0.7
/// alpha. Small → crisp watercolour core.
const double kMirkFogBoundarySharpDistance = 0.04;

/// Distance over which the LONG-TAIL bleed ramps from 0.7 to 1.0 alpha.
const double kMirkFogBoundaryBleedDistance = 0.12;

/// Width (SDF units) of the curl-rotated edge field.
const double kMirkFogBoundaryEdgeBand = 0.17;

/// "Watercolour pigment pool" boost — multiplier applied to fog density inside
/// the boundary bleed band.
const double kMirkFogBoundaryDensityBoost = 0.15;

// ─── Phase 2: Map (no fog) ────────────────────────────────────────────
// Initial camera + zoom envelope (CONTEXT §Map camera bounds & gestures).

/// Initial camera latitude — Melun town centre (Phase 2 walk theatre).
const double kPocInitialCameraLat = 48.5397;

/// Initial camera longitude — Melun town centre.
const double kPocInitialCameraLon = 2.6553;

/// Zoom level on first map render.
const double kPocInitialZoom = 19;

/// Minimum allowed zoom — clamps user pinch-out so the camera cannot escape
/// the bbox into world view (where the bundled PMTiles archive has no tiles).
const double kPocMinZoom = 10;

/// Maximum allowed zoom. The bundled PMTiles vector archive bakes tiles up
/// to z15; past z15 `vector_map_tiles_pmtiles` upscales the z15 geometry
/// (vector tiles stay sharp, just with less detail than a hypothetical z16+
/// bake would carry).
const double kPocMaxZoom = 20;

// Pan bounds — Melun bbox + soft pad (CONTEXT §Pan bounds).
//
// DEBUG-02 (Plan 03.1-12 Task 2) — STRESS-TEST DISABLED: the
// `MapOptions.cameraConstraint` parameter has been REMOVED from
// `lib/presentation/screens/map_screen.dart` (Walk #4 stress-test
// diagnostic per developer's verbatim request — see DEBUG-02 in
// `.planning/REQUIREMENTS.md`). The `kPocBboxLat*` + `kPocBboxLon*`
// + `kPocPanBoundsPadDegrees` constants below are RETAINED but
// currently unreferenced by any production code path. Re-enabling
// the bbox constraint is a Phase 5 hardening concern (just re-add
// the `cameraConstraint: CameraConstraint.contain(...)` parameter
// on `MapOptions` and these constants light up again).

/// Pan bound: minimum latitude (Melun bbox south edge).
/// DEBUG-02: stress-test disabled — see header comment above.
const double kPocBboxLatMin = 48.50;

/// Pan bound: maximum latitude (Melun bbox north edge).
/// DEBUG-02: stress-test disabled — see header comment above.
const double kPocBboxLatMax = 48.57;

/// Pan bound: minimum longitude (Melun bbox west edge).
/// DEBUG-02: stress-test disabled — see header comment above.
const double kPocBboxLonMin = 2.60;

/// Pan bound: maximum longitude (Melun bbox east edge).
/// DEBUG-02: stress-test disabled — see header comment above.
const double kPocBboxLonMax = 2.72;

/// Soft pad in degrees applied around the Melun bbox so the user sees a small
/// rubber-band region before the camera hard-stops.
/// DEBUG-02: stress-test disabled — see header comment above.
const double kPocPanBoundsPadDegrees = 0.02;

// Animation timing (CONTEXT §Recenter FAB UX, §Compass UI).

/// Recenter-FAB animation duration in milliseconds (LOC-04 — 500 ms target).
const int kPocRecenterAnimationMs = 500;

/// Compass snap-to-north animation duration in milliseconds.
const int kPocCompassAnimationMs = 250;

// GPS subscription (CONTEXT §GPS subscription).

/// Distance filter (metres) on `Geolocator.getPositionStream` — the OS only
/// emits a new fix when the device has moved at least this far. 5 m matches
/// CONTEXT.md's spec; lower values would burn battery without meaningfully
/// improving the blue-dot smoothness at z13–15.
const int kPocGpsDistanceFilterMeters = 5;

// PMTiles asset (CONTEXT §PMTiles copy lifecycle).

/// Bundled rootBundle key for the Melun PMTiles archive (asset side of the
/// copy). Must stay in lock-step with `pubspec.yaml` `flutter.assets:` list.
const String kPmtilesAssetPath = 'assets/maps/Fra_Melun.pmtile';

/// Filesystem basename used both as the copy destination filename AND as the
/// idempotency key (size-match check on second launch).
const String kPmtilesBasename = 'Fra_Melun.pmtile';

/// Subdirectory under `getApplicationSupportDirectory()` where the copied
/// archive lives. Isolates map data from logs and other infrastructure caches.
const String kPmtilesMapsSubdir = 'maps';

/// Tile-provider source-key. Must match the source name baked into the
/// vector_map_tiles `ProtomapsThemes.lightV3()` style bundle (RESEARCH §Pitfall
/// 3 — mismatch yields a silent empty layer).
const String kPocTileProviderSourceKey = 'protomaps';

// Blue dot (LOC-02 — CONTEXT §Blue dot rendering).

/// Blue-dot radius in pixels (NOT metres — see [kPocBlueDotUseRadiusInMeter]).
const double kPocBlueDotRadiusPx = 7;

/// Blue-dot stroke width in pixels.
const double kPocBlueDotStrokePx = 2;

/// Blue-dot fill ARGB. Apple-Maps-style azure (0xFF2B7CD6).
const int kPocBlueDotFillArgb = 0xFF2B7CD6;

// ─── Phase 3: Fog of War (the hypothesis) ────────────────────────────
// Reveal disc lifecycle (FOG-01).

/// Radius in metres of the disc spawned at every GPS fix (FOG-01).
const double kPocRevealDiscRadiusMeters = 25.0;

/// Synthetic disc radius for the shader-sanity screen — one disc at the
/// viewport centre, large enough that the reveal hole is visible at typical
/// device sizes.
const double kPocSanityScreenSyntheticDiscRadiusMeters = 80.0;

// Frame-delta probe (FOG-08) — overlay placement + log cadence + buffer.

/// Top-px placement of the FrameDeltaProbeOverlay (right-aligned HUD cluster
/// — FpsCounterOverlay top:8, MapCompass top:56, this overlay top:104).
const double kPocFrameDeltaProbeOverlayTopPx = 104;

/// Right-px placement (matches FpsCounterOverlay + MapCompass).
const double kPocFrameDeltaProbeOverlayRightPx = 8;

/// Cadence of the per-second JSONL rollup for the frame-delta probe.
const int kPocFrameDeltaLogRollupSeconds = 1;

/// Cadence of the per-second JSONL rollup for the SDF rebuild logger.
const int kPocSdfLogRollupSeconds = 1;

/// Ring-buffer cap on raw probe samples (2 s × 120 Hz = 240).
const int kPocFrameDeltaBufferMaxSamples = 240;

/// Probe colour-coding thresholds (microseconds) — median axis. Green ≤ first,
/// yellow ≤ second, red > second. Green is the Criterion A target (16 ms);
/// yellow is +50 % over green, red is anything above.
const int kPocFrameDeltaMedianGreenMicros = 16000;
const int kPocFrameDeltaMedianYellowMicros = 24000;

/// Probe colour-coding thresholds (microseconds) — p95 axis. Green is the
/// Criterion A target (32 ms); yellow is +50 % over green.
const int kPocFrameDeltaP95GreenMicros = 32000;
const int kPocFrameDeltaP95YellowMicros = 48000;

/// Probe colour-coding thresholds (microseconds) — max axis. Green is the
/// Criterion A target (48 ms); yellow is +50 % over green.
const int kPocFrameDeltaMaxGreenMicros = 48000;
const int kPocFrameDeltaMaxYellowMicros = 72000;

// Phase 3.1 fog-transform diagnostic logger (FOG-10).

/// Cadence of the per-second JSONL rollup for the fog-transform diagnostic
/// logger. Aligned with [kPocFrameDeltaLogRollupSeconds] and
/// [kPocSdfLogRollupSeconds] so post-walk grep can join all three rollup
/// streams on the same `epochSecond` boundary (CONTEXT §log-timeline-alignment).
const int kPocFogTransformLogRollupSeconds = 1;

/// Ring-buffer cap on raw fog-transform paint observations (matches
/// [kPocFrameDeltaBufferMaxSamples] discipline — 2 s × 120 Hz = 240).
/// FIFO drop-oldest on overflow.
const int kPocFogTransformBufferMaxSamples = 240;

/// Epsilon for transform-equality comparisons in the FOG-09 regression
/// test. Used in two distinct contexts:
/// (1) raw world-pixel units when comparing `(pixelOrigin.x, pixelOrigin.y)`
///     deltas across two camera positions (post-Plan-03.1-04 the painter
///     forwards `camera.pixelOrigin` verbatim — full-precision world-pixel
///     magnitudes, e.g. ~411 raw pixels for a 1.5 km pan at zoom 13);
/// (2) `Canvas.getTransform()` matrix-element comparisons that test for
///     matrix-identity (the painter's local Canvas is at identity inside
///     `MobileLayerTransformer` at rotation=0 per RESEARCH §Pitfall D).
/// 1e-6 is comfortably below the smallest expected real delta in either
/// regime while above floating-point noise.
const double kPocCanvasTransformEpsilon = 1e-6;

/// FOG-17 (Plan 03.1-10) — noise tile period in raw pixels for the
/// world-coordinate noise sampling formulation. The shader's
/// `noiseUv = worldPx / kNoiseTilePx` sets the cell size of the
/// hash3 noise grid in screen-pixel space.
///
/// MUST stay in lockstep with `kNoiseTilePx` const float in
/// `assets/shaders/atmospheric_fog.frag` AND
/// `assets/shaders/atmospheric_fog_debug_spiral.frag`. The shader
/// shadows this value as a `const float` (NOT a uniform — slot
/// count stays at 41 per FogShaderUniforms.totalFloatSlots lock).
/// If this constant changes, BOTH shader sources must be hand-edited
/// to match (the build pipeline does not substitute Dart constants
/// into shader source).
///
/// 384.0 raw px chosen to preserve on-screen noise frequency parity
/// with the pre-Plan-03.1-10 Branch B-3 formulation. Derivation:
///
/// - Pre-fix B-3 on-screen noise cell ≈ `uResolution.x / maxScale`
///   ≈ `390 / 10.5 ≈ 37 raw px` (where maxScale = 10.5 is
///   `kMirkFogAtmosphericScaleNear`, the dominant octave scale).
/// - Post-fix on-screen noise cell ≈ `kNoiseTilePx / maxScale`
///   ≈ `384 / 10.5 ≈ 36.6 raw px`.
/// - Visual character continuity preserved: texture density / grain
///   size at the dominant octave perceptually equivalent to pre-fix.
///
/// 384 = 1.5 × 256 (power-of-2-friendly, close to typical viewport
/// widths in the 360-430 raw-px range). The hash3 noise grid is
/// unitless so any positive value works, but values close to the
/// viewport width keep the integer-wrap-period arithmetic exact in
/// fp32 AND match pre-fix visual character.
///
/// Earlier draft considered `kPocFogNoiseTilePx = 64.0` — REJECTED
/// on grounds that 64 raw px (one octave-divided unit at uScale=10.5
/// ≈ 6.1 on-screen raw px per cell) would produce a meaningfully
/// finer-grained noise pattern (factor of ~6×) vs the pre-fix
/// formulation, breaking visual character continuity across the
/// fix. See revision context 2026-05-XX (plan-checker WARNING 1).
///
/// Plan 03.1-12 (FOG-18) note: the previously-paired constant
/// `kPocFogIntegerWrapPeriodPx (=1536)` has been deleted (the FOG-17a
/// integer-wrap-modulo was falsified by Walk #4's debug-spiral
/// positive control); `kPocFogNoiseTilePx` continues to live on its
/// own as the noise-tile period for FOG-17 world-coordinate sampling.
const double kPocFogNoiseTilePx = 384.0;

/// FOG-11 — maximum acceptable consecutive-paint delta in pixelOrigin
/// (raw world-pixel units) before declaring a discontinuity. Used in the
/// behavioural smooth-noise-coordinate-evolution test (Plan 03.1-04
/// `test/presentation/widgets/fog_smooth_noise_test.dart`) to catch any
/// future regression where the Dart call site re-introduces a modulo
/// wrap (or any other discontinuous transformation) on the path from
/// `camera.pixelOrigin` to the shader's `uPixelOrigin` slot 3..4.
///
/// Post-Plan-03.1-12 (FOG-18) regime: the painter forwards
/// `camera.pixelOrigin` directly (no modulo). Walk #4's debug-spiral
/// positive control falsified FOG-17a's premise — the noise function
/// is NOT truly periodic on `kPocFogNoiseTilePx (=384)` in practice,
/// so the wrap event at every 1536 raw-px was itself the bug, not
/// the precision penalty it was designed to address. fp32's 24-bit
/// mantissa supports exact-integer values up to 16.7M raw-px, well
/// above Walk #4's max observed pixelOrigin magnitude of ~4.26M.
///
/// At Walk #4 max-zoom pan velocity (~47 raw-px/s; deliberate
/// stress-test) typical consecutive-paint delta is < 1 raw px.
/// 2000 raw-px gives ~3 orders of magnitude headroom for normal use
/// while still catching a regression that re-introduces a wrap
/// (which would produce a delta of `kPocFogNoiseTilePx (=384)` or
/// a multiple thereof on the wrap frame).
const double kPocFogSmoothCoordinateMaxDelta = 2000.0;

/// FOG-19 (Plan 03.1-14 Task B) — reference zoom level used to compute
/// the `uZoomScale` uniform forwarded to the fog shader.
///
/// Walk #5 surfaced Q1b zoom-gesture residual ("numbers sliding /
/// incorrect scaling" during deliberate zoom in/out transitions). Root
/// cause: the shader's `worldPx = fragUv * uResolution + uPixelOrigin`
/// formula combines screen-px-relative (uResolution) with world-px-
/// relative (uPixelOrigin from `camera.pixelOrigin`) basis values.
/// `camera.pixelOrigin` jumps O(1M) raw px between zoom-snap boundaries
/// because flutter_map maintains world-px coordinates relative to a
/// zoom-dependent world-px-per-screen-px ratio — so the noise pattern's
/// spatial frequency relative to map-features changes across zooms.
///
/// Fix: forward `uZoomScale = pow(2, camera.zoom - kPocFogReferenceZoom)`
/// to BOTH `atmospheric_fog.frag` AND `atmospheric_fog_debug_spiral.frag`;
/// shader divides `worldPx` by `(kNoiseTilePx * uZoomScale)` (production)
/// or `cellPx` by `uZoomScale` (debug-spiral). Result: noise samples
/// anchor to lat/lng, NOT screen coordinates.
///
/// 13.0 chosen as reference because it was the Walks #1-#5 default-zoom
/// regime baseline (initial Melun centre at zoom 13 puts pxOriginX
/// ~1.064M; the FOG-17 noise pattern's character was visually verified
/// at this zoom across all walks).
///
/// MIRL visual-identity preservation: at `camera.zoom ==
/// kPocFogReferenceZoom`, `uZoomScale = pow(2, 0) = 1.0` and the
/// shader's noise sampling is bit-identical to the pre-fix formulation.
/// Per CLAUDE.md `# MIRL solution` updated 2026-05-04: visual identity
/// at any settled (zoom, position) post-fix matches pre-fix at SOME
/// equivalent (zoom, position) — passes the Shadertoy-equivalence test.
const double kPocFogReferenceZoom = 13.0;

// Fog shader asset path (FOG-04..06).

/// rootBundle key for the volumetric fog `.frag`. Must match
/// `pubspec.yaml` `flutter.shaders` entry exactly.
const String kPocFogShaderAssetPath = 'assets/shaders/atmospheric_fog.frag';

/// Plan 03.1-07 — DEBUG-ONLY diagnostic spiral shader. Renders human-readable
/// cell-index digits in a row-major grid keyed off the same uPixelOrigin /
/// uResolution coordinate system as production fog. Toggled on at /sanity
/// for mechanism investigation; production fog rendering UNCHANGED.
const String kPocDebugSpiralShaderAssetPath = 'assets/shaders/atmospheric_fog_debug_spiral.frag';

/// Plan 03.1-07 — Cell size in raw pixels for the debug-spiral row-major
/// grid. Picked to be readable at typical iPhone-in-hand viewing distance
/// while small enough that a 390-px-wide viewport shows ~5 cells across.
/// MUST stay in lockstep with `DEBUG_SPIRAL_CELL_SIZE_PX` in
/// `assets/shaders/atmospheric_fog_debug_spiral.frag`.
const double kPocDebugSpiralCellSizePx = 80.0;

// ─── Phase 4: Wisp Particles (WISP-01..05) ───────────────────────────

/// WISP-02 — global active-wisp ceiling. Donor verbatim
/// (kMirkFogWispMaxCount = 200). LRU evicts oldest particles when the
/// cap is exceeded. ~50 µs/frame at the cap on iPhone 17 Pro.
const int kMirkPocWispMaxCount = 200;

/// WISP-02 — life span of a single wisp in seconds. Donor verbatim.
/// Total drift over life at kMirkPocWispDriftMetersPerSecond = ~3.75 m
/// — visually consistent with "puff bursting outward from new reveal".
const double kMirkPocWispLifeSeconds = 2.5;

/// WISP-02 — outer-spawn-spacing along the 25 m disc perimeter, in metres.
/// World-anchored — donor verbatim (the only kinematic donor accidentally
/// got right). 8 m × 2π × 25 m radius ≈ 19.6 → ~20 wisps per puff.
const double kMirkPocWispMetersPerWisp = 8.0;

/// WISP-03 — wall-clock-since-construction window during which
/// spawnAtNewDisc is a no-op. Donor verbatim. Suppresses the
/// "every previously-revealed disc explodes on app open" failure
/// mode. Disc IDs ARE recorded in `_alreadySpawnedDiscIds` during
/// the window so they don't re-trigger post-warmup.
const double kMirkPocWispWarmUpSeconds = 5.0;

/// WISP-02 — peak alpha at age = 0. Alpha curve = `1 - age²`
/// multiplied by this value × tint.a. Donor verbatim. Wisps additive-
/// blend on top of fog (BlendMode.plus) so peak alpha 0.35 brightens
/// the fog without saturating.
const double kMirkPocWispPeakAlpha = 0.35;

/// WISP-02 — initial drift speed in metres / second. RE-CALIBRATED
/// from donor's 18 px/s screen-pixel basis (which at zoom 15 ≈
/// 86 m/s = 310 km/h — donor was never stress-tested at the zooms
/// Phase 3.1 surfaced). 1.5 m/s ≈ cinematic walking-pace; total
/// drift over kMirkPocWispLifeSeconds ≈ 3.75 m. Per CONTEXT.md
/// §Implementation Decisions kinematic-units table.
const double kMirkPocWispDriftMetersPerSecond = 1.5;

/// WISP-02 — wisp visual-radius basis selector. CONTEXT.md decision:
/// cosmetic property — wisp center stays at correct LatLng so
/// no position-drift risk. Default screenPx for zoom-invariant
/// visual character; flipping to `meters` switches to true-ground
/// distance basis for A/B comparison during walks.
enum WispRadiusBasis { screenPx, meters }

/// WISP-02 — selected radius basis. See [WispRadiusBasis].
const WispRadiusBasis kMirkPocWispRadiusBasis = WispRadiusBasis.screenPx;

/// WISP-02 — wisp visual radius at age = 0 in screen-pixels. Donor
/// verbatim. Active when [kMirkPocWispRadiusBasis] == screenPx.
const double kMirkPocWispBirthRadiusPx = 6.0;

/// WISP-02 — wisp visual radius at age = 1 in screen-pixels. Donor
/// verbatim. Active when [kMirkPocWispRadiusBasis] == screenPx.
const double kMirkPocWispDeathRadiusPx = 22.0;

/// WISP-02 — wisp visual radius at age = 0 in metres. Active only
/// when [kMirkPocWispRadiusBasis] == meters. Calibrated at planning
/// time per CONTEXT.md §Claude's Discretion: at zoom 13 default
/// regime (Melun centre, ~9.55 m / raw-px), 6 px ≈ 57 m. Picking
/// 60 m as a round value keeps the visible character within ±5 %
/// of the screenPx default at the reference zoom; at zoom 15 the
/// same metres-radius shrinks to ~2.5 raw px (the cosmetic
/// "smaller wisps when zoomed in" effect).
const double kMirkPocWispBirthRadiusMeters = 60.0;

/// WISP-02 — wisp visual radius at age = 1 in metres. Calibrated to
/// preserve the donor's 22 / 6 ≈ 3.67× growth ratio over wisp life:
/// 60 m × (22/6) = 220 m.
const double kMirkPocWispDeathRadiusMeters = 220.0;

/// WISP-02 — curl-noise force magnitude in m/sec². Re-derived from
/// donor's 8.0 px/sec² screen-pixel basis. 0.5 m/sec² target per
/// CONTEXT.md §Claude's Discretion — initial value; calibrate by
/// walk feedback. At low magnitudes wisps drift cinematically;
/// higher values produce "swarming bees" character.
const double kMirkPocWispCurlAccelMetersPerSecondSquared = 0.5;

/// WISP-02 — linear drag coefficient (per second). Donor verbatim.
/// Combined with curl-noise force, creates organic
/// "drifting then dispersing" motion. Visually validated on MirkFall.
const double kMirkPocWispDragPerSecond = 0.30;

// ─── Phase 4: WispTransformLogger (WISP-05) ──────────────────────────

/// WISP-05 — cadence of the per-second JSONL rollup for the wisp
/// transform diagnostic logger. Aligned with
/// [kPocFogTransformLogRollupSeconds] / [kPocFrameDeltaLogRollupSeconds]
/// / [kPocSdfLogRollupSeconds] so post-walk grep can join all four
/// rollup streams on the same `epochSecond` boundary
/// (CONTEXT §log-timeline-alignment + Phase 3.1 retrospective
/// lesson #4 "ship the diagnostic before you need it").
const int kPocWispTransformLogRollupSeconds = 1;

/// WISP-05 — ring-buffer cap on raw wisp-paint observations. Matches
/// [kPocFogTransformBufferMaxSamples] discipline (2 s × 120 Hz = 240).
/// FIFO drop-oldest on overflow.
const int kPocWispTransformBufferMaxSamples = 240;

/// WISP-02 — default wisp tint colour (ARGB). Donor white-blue
/// hint; visible during walk; trivial to retune via constant flip.
/// Uses const Color via .fromARGB to avoid material.dart import in
/// constants.dart.
const int kMirkPocWispTintArgb = 0xFFC8DCFF; // #C8DCFF — pale blue

// ─── Phase 4: Wisp dt + curl-noise constants (Plans 04-03 / 04-04 consume) ───

/// WISP-02 — maximum dt (in seconds) a single advance call integrates
/// over. Bounds the integration step on first paint or after a paused
/// painter resumes; prevents snap-jumping wisps on a stale Stopwatch.
/// Consumed by [WispParticleSystem.advance] (Plan 04-03).
const double kMirkPocWispMaxDtSeconds = 0.1;

/// WISP-02 — anchor latitude for the curl-noise input projection.
/// Choosing the Melun centre as the curl-noise anchor keeps the
/// noise field deterministic at the same world position regardless
/// of the wisp's individual age. The exact anchor doesn't matter
/// (curl noise is translation-invariant in character); what matters
/// is that ALL wisps in a session sample from the same field.
/// Consumed by [WispParticleSystem.advance] (Plan 04-03).
const double kMelunCenterLatForCurlNoise = kPocInitialCameraLat;

/// WISP-02 — anchor longitude for the curl-noise input projection.
/// Sibling to [kMelunCenterLatForCurlNoise]; same rationale.
const double kMelunCenterLonForCurlNoise = kPocInitialCameraLon;

/// WISP-02 — input-position scale factor for the curl-noise sampler.
/// Donor used `position * 0.005` in screen-px basis (at zoom 13,
/// 1 raw px ≈ 9.55 m → 0.005 px⁻¹ ≈ 5.2e-4 m⁻¹). For LatLng-degree
/// basis we want comparable visual character: 1° ≈ 111 km, so
/// scale ≈ 5.2e-4 × 111000 ≈ 58 → round to 50 for a slightly slower
/// curl variation that reads as 'drifting' not 'swarming'. Per
/// CONTEXT §Claude's Discretion — calibrate by walk feedback.
/// Consumed by [WispParticleSystem.advance] (Plan 04-03).
const double kMirkPocWispCurlInputScale = 50.0;
