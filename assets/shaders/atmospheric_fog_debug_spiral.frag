// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// Plan 03.1-07 — DEBUG-ONLY diagnostic spiral shader.
//
// Renders human-readable cell-index digits in a row-major grid keyed off
// the SAME `uPixelOrigin / uResolution` ratio that production
// `atmospheric_fog.frag` uses. While this shader is active in /sanity,
// what the user observes IS what the production shader's coordinate
// system is doing — translated to readable digits the human eye can
// decompose (translation? rotation? cells popping at random places?
// stretch at zoom transitions? cells 3x tighter than expected?).
//
// The "spiral" name is loose — the indexing is row-major (cell.x +
// cell.y * cellsPerRow). Sufficient for the diagnostic; a true
// Archimedean spiral adds no extra information.
//
// Sampler 1 = digit atlas (10x10 grid of digits 0..99 at 64x64 px each,
// rasterized at runtime via DigitAtlasBuilder). Distinct slot from the
// production shader's sampler 0 (SDF). The debug shader does NOT sample
// the SDF — only the digit atlas.

#version 460 core
#include <flutter/runtime_effect.glsl>

precision mediump float;

// ---------- DEPRECATED post-FOG-18 (Plan 03.1-12) ----------
// The DEBUG_SPIRAL_CELL_SIZE_PX (raw-pixel cell size) and
// DEBUG_SPIRAL_SCALE_FAR/MID/NEAR (octave scales — never actually
// used in this debug shader) are deprecated under FOG-18 — the cell
// size is now in meters (kDebugSpiralCellSizeMeters const float in
// main()) and the octave scales are not used. Retained as historical
// context; removable in future plan iterations.
//
// Cell size in raw pixels for the row-major debug grid (PRE-FOG-18).
// MUST stay in lockstep with `kPocDebugSpiralCellSizePx` in
// `lib/config/constants.dart` (constant-folded; not a uniform).
#define DEBUG_SPIRAL_CELL_SIZE_PX 80.0

// 10x10 digit atlas — digits 0..99. Two-digit cell labels handle the
// common Melun-walk regime (5x9 = 45 cells per viewport at zoom 13);
// labels modulo 100 wrap at high zoom, which the user sees as
// "everything is the 'X' cell" — a confirming symptom for the high-
// pixelOrigin failure modes (B-1 in particular).
#define ATLAS_DIGITS_PER_ROW 10.0
#define ATLAS_DIGIT_PX 64.0
#define ATLAS_TOTAL_PX 640.0

// Plan 03.1-07 Branch B-3 — production-shader noise-tile-period scale
// constants, replicated here so the debug-spiral coordinate system
// applies the SAME tile-period-aware `fract()` formulation as the
// production shader. Production reads these as runtime uniforms
// (slots 20..22 — `uScaleFar/Mid/Near`); the debug shader does not
// share that uniform layout (it only declares uResolution / uTime /
// uPixelOrigin / uDigitAtlas) so the values are constant-folded here.
// MUST stay in lockstep with `kMirkFogAtmosphericScaleFar/Mid/Near`
// in `lib/config/constants.dart` (currently 2.9 / 5.1 / 10.5). If
// those constants change, this shader must rebuild and the developer
// must re-walk the spiral observation under production gesture
// conditions.
#define DEBUG_SPIRAL_SCALE_FAR  2.9
#define DEBUG_SPIRAL_SCALE_MID  5.1
#define DEBUG_SPIRAL_SCALE_NEAR 10.5

// ---------- Uniforms (slots 0..4 match production shader) ----------

// Viewport size in screen pixels. Slot 0..1.
uniform vec2  uResolution;

// Time in seconds since session start. Slot 2.
uniform float uTime;

// World camera anchor in METER SPACE — bounded composite forwarded by
// the Dart-side painter after the meter-space integer/fractional
// decomposition (Plan 03.1-14 Fix B′ — FOG-19). Magnitude stays under
// `kPocFogIntegerWrapPeriodMeters + 1` = 4097 m. Pre-Plan-03.1-14 this
// uniform was named `uPixelOrigin` and carried raw pixelOrigin.
// Semantic flips to meter-space; slot 3..4 unchanged.
uniform vec2  uWorldMetersOrigin;

// World meters per raw pixel (Web-Mercator EPSG:3857). Used to
// convert worldPx to worldMeters so the spiral cells are physical
// squares of ground regardless of zoom (cells appear larger when
// zoomed in, smaller when zoomed out — visual confirmation that
// FOG-18 landed). Slot 5.
//
// Computed at the Dart painter via the same formula as the
// production fog: kWebMercatorMetersPerPxAtEquatorZ0 * cos(lat) /
// pow(2, zoom).
//
// FOG-18 (Plan 03.1-12) — closes Walk #4 Q5 zoom-scramble.
uniform float uMetersPerPixel;

// Digit atlas sampler — sampler slot 0. Flutter's FragmentShader
// `setImageSampler(N, image)` indexes samplers in declaration order,
// starting from 0; this shader declares only a single sampler so its
// slot is unconditionally 0. The original Plan 03.1-07 landing
// commented "slot 1 (production's sampler 0 is SDF)", which mis-read
// Flutter's binding model — slot numbering is PER-SHADER, not global,
// so the debug shader's only sampler is slot 0 regardless of what the
// production shader does. The Plan 03.1-08-FIX FIX 3 corrects this:
// the Dart call site now binds via `setImageSampler(0, atlas)`. Without
// this fix the atlas was never bound on iPhone Impeller (slot 1 was
// effectively unused; texture() reads on uDigitAtlas returned 0.0,
// rendering only the dark-grey background — the user's "no shader
// displayed" report on /sanity).
uniform sampler2D uDigitAtlas;

out vec4 fragColor;

// ---------- Helpers ----------

// Maps a single digit (0..9) to its (col, row) in the 10x10 atlas.
// Digit 0 lives at (col=0, row=0) (top-left); digit 9 at (col=9, row=0).
// Atlas row index increases DOWNWARD in atlas-UV space; the digit-builder
// docstring documents the same orientation.
vec2 digitAtlasOrigin(int digit) {
    int col = digit;
    int row = 0;
    return vec2(float(col), float(row));
}

// Samples the digit atlas at `digit` for sub-cell uv `subUv` in [0, 1].
// Returns the atlas pixel's red channel (digits are rasterized as white
// glyphs on transparent background — alpha == red == intensity).
float sampleDigit(int digit, vec2 subUv) {
    if (digit < 0 || digit > 9) {
        return 0.0;
    }
    vec2 atlasOrigin = digitAtlasOrigin(digit);
    vec2 atlasUv = (atlasOrigin + clamp(subUv, 0.0, 1.0)) / ATLAS_DIGITS_PER_ROW;
    return texture(uDigitAtlas, atlasUv).r;
}

void main() {
    vec2 fragUv = FlutterFragCoord().xy / uResolution;

    // OpenGLES Y-flip guard — mirror production shader's handling.
    #ifdef IMPELLER_TARGET_OPENGLES
        fragUv.y = 1.0 - fragUv.y;
    #endif

    // Plan 03.1-12 — FOG-18 world-meter anchor (mirror of production
    // fog's architectural completion). The spiral cell-numbering
    // reflects meter-space coordinates: cells are physical squares of
    // ground (kDebugSpiralCellSizeMeters = 200 m per cell at any zoom)
    // regardless of zoom level. Visual confirmation that FOG-18 landed:
    // cells appear larger when zoomed in, smaller when zoomed out
    // (matching the developer's Walk #4 Q5 expectation).
    //
    // Plan 03.1-14 Fix B′ — FOG-19 meter-space anchor (slot 3..4 rename
    // uPixelOrigin → uWorldMetersOrigin; semantic flip). Pre-Plan-03.1-14
    // (FOG-18 era):
    //   vec2 worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel;
    // Post-Plan-03.1-14 (FOG-19): the camera anchor is forwarded in METER
    // space directly; the fragment-offset-in-meters term is computed
    // inside the shader. Cell numbering at fixed map position is now
    // ALSO continuous across wrap boundaries because every wrap injects
    // a CONSTANT-magnitude phase shift INVARIANT across all wrap events
    // (Octave 1 bit-identical via hash3 period-1; Octaves 2 + 3 receive
    // a deterministic ≈ 11% fbm3-dynamic-range residual shift bounded
    // analytically; the constant-magnitude property eliminates the
    // pre-fix variable-magnitude stepping).
    //
    // See production atmospheric_fog.frag for the full FOG-18 + FOG-19
    // architectural rationale + zoom-invariance proof + continuity
    // proof.
    //
    // kNoiseTilePxMeters MUST stay in lockstep with
    // `kPocFogNoiseTilePxMeters` in `lib/config/constants.dart`
    // (1024.0). kDebugSpiralCellSizeMeters MUST stay in lockstep with
    // `kPocDebugSpiralCellSizeMeters` (200.0).
    const float kNoiseTilePxMeters = 1024.0;
    const float kDebugSpiralCellSizeMeters = 200.0;
    vec2 worldMeters = (fragUv * uResolution) * uMetersPerPixel + uWorldMetersOrigin;
    vec2 spiralCoord = worldMeters / kNoiseTilePxMeters;

    // Cell index in meter space — cells are physical squares of ground.
    // At z=15 lat 48.5° (metersPerPixel ≈ 3.16), one cell of 200 m on
    // ground is ≈ 63 raw px on screen — close to pre-FOG-17 80 raw px
    // (visual character preserved at the typical hike zoom).
    vec2 cellMeters = worldMeters;
    vec2 cellFloat = floor(cellMeters / kDebugSpiralCellSizeMeters);
    ivec2 cell = ivec2(cellFloat);

    // cellsPerRow at the current zoom — uResolution.x raw px /
    // (kDebugSpiralCellSizeMeters / metersPerPixel) raw px per cell.
    // At z=15 lat 48.5° ≈ 390 / 63 ≈ 6 cells per row. The `max(...,
    // 1e-4)` guard on uMetersPerPixel mirrors the Dart-side polar
    // clamp; the `max(..., 1.0)` floor on the px-per-cell ratio
    // prevents division-by-zero when zoomed out so far that
    // px-per-cell collapses to sub-pixel.
    int cellsPerRow = int(uResolution.x / max((kDebugSpiralCellSizeMeters / max(uMetersPerPixel, 1e-4)), 1.0)) + 1;
    int rawCellIndex = cell.x + cell.y * cellsPerRow;
    int cellIndex = int(mod(float(rawCellIndex), 100.0));
    if (cellIndex < 0) {
        cellIndex = cellIndex + 100;  // mod(-1, 100) can return -1 on some drivers; force [0, 100).
    }

    int tens = cellIndex / 10;
    int ones = cellIndex - tens * 10;

    // Local sub-cell uv in [0, 1] for atlas sampling. cellLocalMeters
    // is the position within the cell in meters; divide by cell size
    // to get [0, 1] uv.
    vec2 cellLocalMeters = cellMeters - cellFloat * kDebugSpiralCellSizeMeters;
    vec2 cellLocalUv = cellLocalMeters / kDebugSpiralCellSizeMeters;

    // Two-digit horizontal layout: tens digit occupies left half
    // [0.0, 0.5], ones digit right half [0.5, 1.0]. Each digit is
    // sampled in its own sub-uv space mapped from [0, 0.5] -> [0, 1].
    // Vertical band: digits centered vertically with 0.1 padding top
    // and bottom (so the cell border is visible between rows).
    float vertPadding = 0.1;
    float vertSpan = 1.0 - 2.0 * vertPadding;
    float vertLocal = (cellLocalUv.y - vertPadding) / vertSpan;

    float digitIntensity = 0.0;
    if (vertLocal >= 0.0 && vertLocal <= 1.0) {
        if (cellLocalUv.x < 0.5) {
            float subX = cellLocalUv.x / 0.5;
            digitIntensity = sampleDigit(tens, vec2(subX, vertLocal));
        } else {
            float subX = (cellLocalUv.x - 0.5) / 0.5;
            digitIntensity = sampleDigit(ones, vec2(subX, vertLocal));
        }
    }

    // Background colour: dark grey so the digits read with high contrast.
    // Digit colour: bright cyan-yellow gradient subtly tied to uTime so
    // the user can confirm uTime is advancing (a stuck uTime would
    // produce a uniform-coloured digit; pre-Phase-3 BUG-FROZEN-UTIME
    // failure mode). Time tint runs over a 1 Hz period.
    vec3 background = vec3(0.08, 0.08, 0.10);
    vec3 digitWarm = vec3(1.0, 0.95, 0.20);   // amber
    vec3 digitCool = vec3(0.20, 0.95, 1.00);  // cyan
    float timeTint = 0.5 + 0.5 * sin(uTime * 6.2831853);
    vec3 digitColour = mix(digitCool, digitWarm, timeTint);

    // Cell-border tint: thin band at the cell edge so the user can see
    // cell boundaries even when both digits at adjacent cells happen
    // to land in their padding region. Border is 1.5 raw-px-equivalent
    // wide in meter space:
    //   borderMeters = 1.5 * uMetersPerPixel
    //   borderUv     = borderMeters / kDebugSpiralCellSizeMeters
    // Defends against degenerate metersPerPixel via the same `max()`
    // guard as cellsPerRow (mirrors Dart-side polar clamp).
    float borderPx = 1.5;
    float borderUv = (borderPx * max(uMetersPerPixel, 1e-4)) / kDebugSpiralCellSizeMeters;
    bool onBorder = (cellLocalUv.x < borderUv) || (cellLocalUv.x > 1.0 - borderUv) ||
                    (cellLocalUv.y < borderUv) || (cellLocalUv.y > 1.0 - borderUv);

    vec3 finalColour = mix(background, digitColour, digitIntensity);
    if (onBorder) {
        finalColour = mix(finalColour, vec3(0.30, 0.30, 0.34), 0.6);
    }

    fragColor = vec4(finalColour, 1.0);
}
