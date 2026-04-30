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
