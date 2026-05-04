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

// Cell size in raw pixels for the row-major debug grid. Picked to be
// readable at typical iPhone-in-hand viewing distance while small
// enough that a 390-px-wide viewport shows ~5 cells across. MUST stay
// in lockstep with `kPocDebugSpiralCellSizePx` in
// `lib/config/constants.dart` (constant-folded; not a uniform).
#define DEBUG_SPIRAL_CELL_SIZE_PX 80.0

// 10x10 digit atlas — digits 0..9 in row 0. Plan 03.1-14 Task A
// (DEBUG-03) replaced the previous repetitive two-digit labels (mod 100
// cycling) with unique 4-digit per-cell encoding for quantitative drift
// measurement during Walk #6 zoom transitions. The atlas image itself
// is unchanged (10 digits 0..9 in the top row); only the shader's
// per-cell sampling logic now reads 4 horizontal digit slots per cell
// instead of 2.
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

// World pixel-origin — same name + slot as production for direct
// comparison. Slot 3..4. Sanity-screen feeds a synthetic time-driven
// trajectory; production-screen would feed `camera.pixelOrigin`.
uniform vec2  uPixelOrigin;

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

    // Plan 03.1-10 — FOG-17 world-coordinate noise sampling.
    // Mirrors production atmospheric_fog.frag: the debug-spiral
    // observation reflects the post-Plan-03.1-10 coordinate system.
    // See production shader for the full rationale + Walk #3b
    // empirical anchor + FOG-17a precision pairing.
    //
    // kNoiseTilePx MUST stay in lockstep with `kPocFogNoiseTilePx`
    // in `lib/config/constants.dart` (currently 384.0). The debug-
    // spiral cell size remains `DEBUG_SPIRAL_CELL_SIZE_PX` (80.0)
    // — the cell grid is for digit-readability, not for noise
    // sampling; the cell-index computation still uses
    // `cellPx / DEBUG_SPIRAL_CELL_SIZE_PX` below.
    const float kNoiseTilePx = 384.0;
    vec2 worldPx = fragUv * uResolution + uPixelOrigin;
    vec2 spiralCoord = worldPx / kNoiseTilePx;

    // Convert worldPx (already in raw pixels) directly to cell-grid
    // space. Pre-Plan-03.1-10 we computed `cellPx = spiralCoord *
    // uResolution` — that worked when `spiralCoord = fragUv +
    // fract(...)` had magnitude ~1 across the viewport. Post-Plan-
    // 03.1-10 `spiralCoord = worldPx / kNoiseTilePx` is in noise-
    // grid units (~1-2 across the viewport given kNoiseTilePx ≈
    // uResolution.x), so multiplying by uResolution would inflate
    // cellPx by ~kNoiseTilePx and shrink the visible cells-per-
    // viewport count to a single cell. Use worldPx directly — it
    // is already in raw pixels regardless of the spiralCoord
    // formulation.
    vec2 cellPx = worldPx;
    vec2 cellFloat = floor(cellPx / DEBUG_SPIRAL_CELL_SIZE_PX);
    ivec2 cell = ivec2(cellFloat);

    // DEBUG-03 (Plan 03.1-14 Task A) — unique 4-digit per-cell encoding
    // for quantitative drift measurement during Walk #6 zoom transitions.
    // Per developer's Walk #5 verbatim request: "modifying the number to
    // not have repetitive value would allow us to debug the amount of
    // drift". The previous mod-100 cycling repeated every 100 cells
    // (~8000 raw px at 80-px cell size) — far too small for the O(M)
    // raw-px zoom-gesture sweeps Walk #5 captured. Encoding:
    // (cell.y + 50) * 100 + (cell.x + 50) gives unique IDs for cells in
    // the +/-50 cell range from world-origin (covers ~8000 raw px in
    // each axis at 80-px cell size, more than a single Melun-anchored
    // Walk #6 session needs). Cells outside +/-50 are clamped to
    // [0, 9999] — boundary cells share IDs but the diagnostic is
    // meaningful only within the active session region.
    int cellId = (cell.y + 50) * 100 + (cell.x + 50);
    cellId = clamp(cellId, 0, 9999);

    int thousands = cellId / 1000;
    int hundreds = (cellId / 100) - thousands * 10;
    int tens = (cellId / 10) - thousands * 100 - hundreds * 10;
    int ones = cellId - thousands * 1000 - hundreds * 100 - tens * 10;

    // Local sub-cell uv in [0, 1] for atlas sampling.
    vec2 cellLocalPx = cellPx - cellFloat * DEBUG_SPIRAL_CELL_SIZE_PX;
    vec2 cellLocalUv = cellLocalPx / DEBUG_SPIRAL_CELL_SIZE_PX;

    // DEBUG-03 (Plan 03.1-14 Task A) — 4-digit horizontal layout. Each
    // sub-x band of 0.25 width carries one digit. Order: thousands (left)
    // -> hundreds -> tens -> ones (right). Vertical band identical to the
    // pre-DEBUG-03 layout (uses the same vertPadding / vertSpan).
    float vertPadding = 0.1;
    float vertSpan = 1.0 - 2.0 * vertPadding;
    float vertLocal = (cellLocalUv.y - vertPadding) / vertSpan;

    float digitIntensity = 0.0;
    if (vertLocal >= 0.0 && vertLocal <= 1.0) {
        int activeDigit;
        float subX;
        if (cellLocalUv.x < 0.25) {
            activeDigit = thousands;
            subX = cellLocalUv.x / 0.25;
        } else if (cellLocalUv.x < 0.5) {
            activeDigit = hundreds;
            subX = (cellLocalUv.x - 0.25) / 0.25;
        } else if (cellLocalUv.x < 0.75) {
            activeDigit = tens;
            subX = (cellLocalUv.x - 0.5) / 0.25;
        } else {
            activeDigit = ones;
            subX = (cellLocalUv.x - 0.75) / 0.25;
        }
        digitIntensity = sampleDigit(activeDigit, vec2(subX, vertLocal));
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
    // to land in their padding region. Border is 1.5 px wide in raw
    // pixels (independent of cell size).
    float borderPx = 1.5;
    float borderUv = borderPx / DEBUG_SPIRAL_CELL_SIZE_PX;
    bool onBorder = (cellLocalUv.x < borderUv) || (cellLocalUv.x > 1.0 - borderUv) ||
                    (cellLocalUv.y < borderUv) || (cellLocalUv.y > 1.0 - borderUv);

    vec3 finalColour = mix(background, digitColour, digitIntensity);
    if (onBorder) {
        finalColour = mix(finalColour, vec3(0.30, 0.30, 0.34), 0.6);
    }

    fragColor = vec4(finalColour, 1.0);
}
