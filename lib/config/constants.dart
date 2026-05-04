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

/// Zoom level on first map render. Mid-range so the user immediately sees both
/// road network and labels without panning.
const double kPocInitialZoom = 13;

/// Zoom level used by the recenter FAB animation target (LOC-04). Tighter than
/// initial so a "where am I?" tap zooms in rather than just re-centring.
const double kPocRecenterZoom = 15;

/// Minimum allowed zoom — clamps user pinch-out so the camera cannot escape
/// the bbox into world view (where the bundled PMTiles archive has no tiles).
const double kPocMinZoom = 10;

/// Maximum allowed zoom — clamps pinch-in so the camera cannot zoom past the
/// archive's deepest level (PMTiles bake stops at z15).
const double kPocMaxZoom = 15;

// Pan bounds — Melun bbox + soft pad (CONTEXT §Pan bounds).

/// Pan bound: minimum latitude (Melun bbox south edge).
const double kPocBboxLatMin = 48.50;

/// Pan bound: maximum latitude (Melun bbox north edge).
const double kPocBboxLatMax = 48.57;

/// Pan bound: minimum longitude (Melun bbox west edge).
const double kPocBboxLonMin = 2.60;

/// Pan bound: maximum longitude (Melun bbox east edge).
const double kPocBboxLonMax = 2.72;

/// Soft pad in degrees applied around the Melun bbox so the user sees a small
/// rubber-band region before the camera hard-stops.
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
