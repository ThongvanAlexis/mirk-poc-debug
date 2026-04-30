// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// Phase 09 BUG-009 (TIER 2) — volumetric fog fragment shader.
//
// All seven TIER 2 quality dimensions:
//   1. 3D-sliced FBM      — base density via `fbm3(vec3(uv, t * driftZ))`.
//                           Noise BOILS in place over time, doesn't slide.
//   2. Curl-noise advect  — UVs warped by curl of a scalar potential field.
//                           Eddies and swirls (divergence-free).
//   3. Multi-octave parallax — 3 octaves at 3 scales / 3 drift speeds /
//                              3 opacities. Reads as depth on a 2D plane.
//   4. Faux directional shading — sample density twice (at pixel + at
//                                 pixel + lightDir * offset). Delta
//                                 modulates brightness. Free 3D look.
//   5. Sub-grey hue variation — second cheap noise channel modulates a
//                               tint shift between shadow and highlight.
//   6. Two-stop watercolour boundary — sharp inner gradient (0→0.7) +
//                                      long-tail bleed (0.7→1.0). Reads
//                                      cartographic, not engineered.
//   7. Curl-rotated edge field — near the boundary, rotate curl-noise
//                                sample ~90° so wisps spiral outward.
//
// Constraints honoured (per .planning/research/bug-009-fog-visual/
// flutter-shader-constraints.md):
//   - No mat3/4 / int / bool uniforms.
//   - No texelFetch / textureLod / dFdx / structs / GLSL array literals.
//   - FlutterFragCoord(), not gl_FragCoord.
//   - Sampler always TileMode.clamp.
//   - No unused uniforms (Impeller startup fail).
//   - Instructions ≤ ~400 ALU per fragment (60 fps mid-range mobile).

#version 460 core
#include <flutter/runtime_effect.glsl>

precision mediump float;

// ---------- Diagnostic toggle (BUG-009 follow-up, 2026-04-25) ----------
//
// When MIRK_FOG_DEBUG_OUTPUT_DENSITY is defined, the shader bypasses
// the colour-mix / boundary-alpha pipeline and outputs the raw post-FBM
// density `dN` as opaque grey. Lets the user verify on-device whether
// the noise itself is varying spatially or whether the colour-mix math
// is collapsing the contrast.
//
// MUST be kept in lockstep with `kMirkFogDebugOutputDensity` in
// `lib/config/constants.dart`. To activate: uncomment the #define below
// AND set the Dart constant to true, then rebuild the app.
//
// Default: commented out (production output).
//#define MIRK_FOG_DEBUG_OUTPUT_DENSITY

// ---------- Uniforms (vec2/vec3/vec4/float only — no int/bool/mat3/mat4) ----------

// Viewport size in screen pixels. Slot 0..1.
uniform vec2  uResolution;

// Time in seconds since session start. Slot 2.
uniform float uTime;

// World pan offset (in noise UV units). Lets the fog drift with the
// MapLibre camera so static fixtures don't appear to move when the user
// only pans. Slot 3..4.
uniform vec2  uOffset;

// Fog colour palette: base / highlight / shadow as RGBA. Alpha
// component of uBase carries the overall fog opacity. Slot 5..16.
uniform vec4  uBase;
uniform vec4  uHighlight;
uniform vec4  uShadow;

// 3D-FBM drift speeds for the three octaves (far / mid / near).
// Slot 17..19.
uniform float uDriftZFar;
uniform float uDriftZMid;
uniform float uDriftZNear;

// Spatial scales for the three octaves. Slot 20..22.
uniform float uScaleFar;
uniform float uScaleMid;
uniform float uScaleNear;

// Octave weights — sum to ~1.0. Slot 23..25.
uniform float uOpacityFar;
uniform float uOpacityMid;
uniform float uOpacityNear;

// Curl-noise tunables. Slot 26..27.
uniform float uCurlAmplitude;
uniform float uCurlScale;

// Faux directional shading. Slot 28..30.
uniform float uLightDirRadians;
uniform float uLightOffset;
uniform float uLightStrength;

// Hue variation. Slot 31..32.
uniform float uHueNoiseScale;
uniform float uHueStrength;

// Two-stop watercolour boundary. Slot 33..35.
uniform float uBoundarySharpDistance;
uniform float uBoundaryBleedDistance;
uniform float uBoundaryEdgeBand;

// "Watercolour pigment pool" — additive density multiplier inside the
// bleed band so the nearby fog visibly reacts to the boundary. Slot 36.
uniform float uBoundaryDensityBoost;

// SDF rectangle on screen — uv mapped from FlutterFragCoord/uResolution
// to SDF space via this rect. (originX, originY, sizeX, sizeY).
//
// BUG-014 follow-up: decomposed from a single vec4 into four scalar
// floats. On Impeller/Metal, the SPIR-V → MSL transpilation can
// reorder vec4 components when a sampler2D sits nearby in the
// declaration, causing the SDF rect to read with swapped axes during
// combined pan+zoom gestures. Four explicit floats bypass the vec4
// component-ordering ambiguity entirely — each uniform occupies exactly
// one slot with no room for transpiler reinterpretation.
//
// Slots 37..40 (unchanged from the Dart side).
uniform float uSdfRectOriginX;   // Slot 37
uniform float uSdfRectOriginY;   // Slot 38
uniform float uSdfRectSizeX;     // Slot 39
uniform float uSdfRectSizeY;     // Slot 40

// SDF sampler — R channel encodes signed distance via midpoint-128.
uniform sampler2D uSdf;

out vec4 fragColor;

// ---------- Noise primitives ----------

// Hash & value noise — cheap, no dependencies, deterministic per
// `vec3(p, z)` input. Avoids `texelFetch` / array constants per
// Impeller foot-gun list.

float hash3(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yxz + 19.19);
    return fract((p.x + p.y) * p.z);
}

// 3D value noise — trilinear interp of hash3 at the 8 unit-cube corners.
float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f); // smoothstep
    float n000 = hash3(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

// 2D value noise — used for the curl potential and the hue field. No
// time slice, evaluated as `noise3(vec3(p, 0.0))` to share machinery.
float noise2(vec2 p) {
    return noise3(vec3(p, 0.0));
}

// 3-octave 3D FBM. Conservative rotation between octaves to avoid
// axial alignment. Cost ~3 noise3 calls.
float fbm3(vec3 p) {
    float a = 0.5;
    float t = 0.0;
    // Octave 1
    t += a * noise3(p);
    p = p * 2.03 + vec3(13.7, 7.3, 5.1);
    a *= 0.5;
    // Octave 2
    t += a * noise3(p);
    p = p * 2.05 + vec3(-11.1, 17.9, 3.3);
    a *= 0.5;
    // Octave 3
    t += a * noise3(p);
    return t;
}

// Curl of a scalar 2D noise potential — gives a divergence-free vector
// field. 4 noise2 taps for central differences.
vec2 curl2(vec2 p) {
    const float e = 0.05;
    float n1 = noise2(p + vec2(0.0,  e));
    float n2 = noise2(p + vec2(0.0, -e));
    float n3 = noise2(p + vec2( e, 0.0));
    float n4 = noise2(p + vec2(-e, 0.0));
    return vec2(n1 - n2, -(n3 - n4)) / (2.0 * e);
}

// Returns the signed distance encoded in the SDF sampler at sdfUv.
// Decoded from midpoint-128: `texture.r` is in [0, 1] with 0.5 at
// the boundary; map to [-1, 1].
//
// BUG-009 follow-up (boundary watercolour, 2026-04-26): the SDF is an
// 8-bit texture (256 levels) stretched across the screen, which makes
// every byte step visible as a concentric "ring of light" around the
// boundary when consumed by smoothsteps with narrow edges. Add a
// 1-byte-amplitude ordered dither so the eye averages adjacent rings
// into a smooth gradient. Dither is applied BEFORE the [0,1] → [-1,1]
// remap so the ±0.5/256 perturbation translates to ±1/256 in signed
// distance — exactly one quantisation step, the minimum required to
// break visible banding.
float sampleSdf(vec2 fragUv) {
    // fragUv is in screen-normalised [0, 1] space. Map to SDF UV via
    // the four scalar SDF-rect uniforms (origin + size in
    // screen-normalised coords). BUG-014 follow-up: explicit per-axis
    // construction avoids any vec4 component-reordering ambiguity on
    // Impeller/Metal.
    vec2 sdfOrigin = vec2(uSdfRectOriginX, uSdfRectOriginY);
    vec2 sdfSize   = vec2(uSdfRectSizeX,   uSdfRectSizeY);
    vec2 sdfUv = (fragUv - sdfOrigin) / sdfSize;
    sdfUv = clamp(sdfUv, 0.0, 1.0);
    float r = texture(uSdf, sdfUv).r;
    // Hashed white-noise dither in [-0.5/256, +0.5/256] keyed on screen
    // position. Standard "blue-noise alternative" (cheap, deterministic
    // per pixel). FlutterFragCoord rather than gl_FragCoord per shader
    // contract.
    vec2 fragPx = FlutterFragCoord().xy;
    float ditherNoise = fract(sin(dot(fragPx, vec2(12.9898, 78.233))) * 43758.5453);
    float ditherPx = (ditherNoise - 0.5) * (1.0 / 256.0);
    return (r + ditherPx) * 2.0 - 1.0;
}

// ---------- Density assembly ----------

// Produces a single octave's density at uv with the given scale, drift
// speed, and curl-warped UVs. All octaves share the same curl field so
// the eddies are consistent across scales.
float octaveDensity(vec2 uv, vec2 curlVec, float scale, float driftZ) {
    vec2 warped = uv * scale + curlVec * uCurlAmplitude;
    return fbm3(vec3(warped, uTime * driftZ));
}

void main() {
    vec2 fragUv = FlutterFragCoord().xy / uResolution;

    // OpenGLES Y-flip guard — Android API <29 path can flip Y under
    // OpenGLES backend. Impeller+Vulkan / Impeller+Metal pass through
    // unchanged.
    #ifdef IMPELLER_TARGET_OPENGLES
        fragUv.y = 1.0 - fragUv.y;
    #endif

    // Apply world pan to the noise UV space (NOT to fragUv — fragUv is
    // screen-local for SDF sampling).
    vec2 noiseUv = fragUv + uOffset;

    // ---------- 7. Curl-rotated edge field ----------
    // Sample the SDF; near the boundary, locally rotate the curl-noise
    // sample by ~90° so the eddies appear to spiral OUT of the boundary
    // rather than through it. The rotation amount tapers smoothly
    // within `uBoundaryEdgeBand` of the boundary.
    float sdf = sampleSdf(fragUv);

    // Base curl vector at this UV.
    vec2 curlVec = curl2(noiseUv * uCurlScale);

    // Edge gating: smooth weight that is 1 right at the boundary and
    // 0 outside the band. abs(sdf) so it acts on both sides.
    float edgeGate = 1.0 - smoothstep(0.0, uBoundaryEdgeBand, abs(sdf));
    // Rotate curlVec by ~90° (perpendicular) when fully inside the
    // edge band.
    vec2 curlRot = vec2(-curlVec.y, curlVec.x);
    curlVec = mix(curlVec, curlRot, edgeGate * 0.7);

    // ---------- 1+2+3. 3D-sliced FBM × multi-octave parallax × curl ----------
    float dFar  = octaveDensity(noiseUv, curlVec, uScaleFar,  uDriftZFar);
    float dMid  = octaveDensity(noiseUv, curlVec, uScaleMid,  uDriftZMid);
    float dNear = octaveDensity(noiseUv, curlVec, uScaleNear, uDriftZNear);
    float density = dFar * uOpacityFar + dMid * uOpacityMid + dNear * uOpacityNear;

    // ---------- Watercolour pigment pool ----------
    // Within `uBoundaryBleedDistance` of the boundary on EITHER side,
    // bump the density so the nearby fog reads as visibly thicker —
    // the way watercolour pigment pools at the perimeter of a wash.
    // boundaryGlow = 1 right at the boundary, 0 at the bleed-band edge.
    // Guarded with `max(... , 1e-4)` so a 0 bleed band degrades to no
    // boost rather than dividing by zero.
    float boundaryGlow = 1.0 - smoothstep(0.0, max(uBoundaryBleedDistance, 1e-4), abs(sdf));
    density *= 1.0 + boundaryGlow * uBoundaryDensityBoost;

    // ---------- 4. Faux directional shading ----------
    // Sample density a second time at uv + lightDir * uLightOffset, take
    // the delta, use it to modulate brightness. Cheap fake-3D.
    vec2 lightDir = vec2(cos(uLightDirRadians), sin(uLightDirRadians));
    vec2 noiseUvLit = noiseUv + lightDir * uLightOffset;
    float dFarLit = octaveDensity(noiseUvLit, curlVec, uScaleFar, uDriftZFar);
    float densityLit = dFarLit * uOpacityFar + dMid * uOpacityMid + dNear * uOpacityNear;
    float shadeDelta = (densityLit - density) * uLightStrength;

    // ---------- 5. Sub-grey hue variation ----------
    // Cheap second noise channel — modulates the tint shift between
    // shadow and highlight palette (NOT density).
    float hueField = noise2(noiseUv * uHueNoiseScale + vec2(91.7, 33.1));
    // Map [0, 1] → [-1, 1] then scale by uHueStrength.
    float hueShift = (hueField - 0.5) * 2.0 * uHueStrength;

    // ---------- Colour mix ----------
    // BUG-009 follow-up #2 (2026-04-25): three math fixes after the
    // diagnostic toggle landed in 1b570d1.
    //
    // 1. Range fix. noise3 is built on hash3 which returns values in
    //    [0, 1] (NOT [-1, 1]). The 3-octave FBM accumulates with weights
    //    0.5 + 0.25 + 0.125 = 0.875, so `density` lives in [0, 0.875].
    //    The previous remap `density * 0.5 + 0.5` was designed for a
    //    [-1, 1] input and ended up clamping into [0.5, 0.94] — only
    //    the dark half of the highlight↔shadow gradient ever fired.
    //    Divide by 0.875 instead so dN spans the full [0, 1] range.
    //
    // 2. Hue strength was being applied twice — once when computing
    //    `hueShift` and again as the mix weight. Drop the second mul.
    //    Also: the previous `mix(fogColor, uBase.rgb, abs(hueShift))`
    //    flattened toward uBase regardless of sign — that's collapse,
    //    not tint. Use directional logic so hueShift > 0 pulls toward
    //    uHighlight and hueShift < 0 pulls toward uShadow.
    //
    // 3. uLightStrength was being applied twice — once in shadeDelta
    //    and again on the additive line. Drop the second mul.
    float dN = clamp(density / 0.875, 0.0, 1.0);
    // Where the noise is dense → tilt toward shadow (dark valleys).
    // Where it is sparse → tilt toward highlight (lit ridges).
    vec3 fogColor = mix(uHighlight.rgb, uShadow.rgb, dN);
    // Faux directional shading: brighten the side facing the light by
    // adding the highlight↔shadow swing scaled by shadeDelta. Negative
    // shadeDelta darkens — same swing applied with sign. shadeDelta
    // already contains uLightStrength.
    fogColor += (uHighlight.rgb - uShadow.rgb) * shadeDelta;
    // Hue variation: directional tint. Positive hueShift pulls toward
    // highlight, negative toward shadow. hueShift already contains
    // uHueStrength so the mix weights are pure |hueShift|.
    fogColor = mix(fogColor, uHighlight.rgb, max(hueShift, 0.0));
    fogColor = mix(fogColor, uShadow.rgb,    max(-hueShift, 0.0));
    fogColor = clamp(fogColor, 0.0, 1.0);

    // ---------- 6. Two-stop watercolour boundary ----------
    // Sharp inner gradient: 0 → 0.7 alpha over uBoundarySharpDistance.
    // Long-tail bleed:    0.7 → 1.0 alpha over uBoundaryBleedDistance.
    // The two ramps run from sdf = 0 (boundary) outward into fog.
    //
    // BUG-009 follow-up (2026-04-26): the previous bake set
    // `uBoundaryBleedDistance = 0.0`, which collapsed the second
    // smoothstep into a unit step at sdf = uBoundarySharpDistance — a
    // hard alpha jump 0.7 → 1.0 in one pixel that read as a stark
    // white edge. Combined with the 8-bit SDF banding, it surfaced as
    // concentric rings of light. The bleed default has been restored
    // to 0.12 so the long-tail fade actually fades; the
    // `max(..., 1e-4)` guard below keeps the math sane if the live
    // tuner pushes bleed to 0.
    float sharp = smoothstep(0.0, uBoundarySharpDistance, sdf) * 0.7;
    float bleedEnd = uBoundarySharpDistance + max(uBoundaryBleedDistance, 1e-4);
    float bleed = smoothstep(uBoundarySharpDistance, bleedEnd, sdf) * 0.3;
    float boundaryAlpha = sharp + bleed;
    // Inside revealed area (sdf < 0): smoothstep over a thin band so
    // the inside-edge transition is also watercolour-soft, not a hard
    // 0/1 mask. The band scales with the sharp distance so adjusting
    // the latter implicitly tunes the inside softness too. Guarded
    // with `min(..., -1e-4)` so a 0 sharp distance from the live tuner
    // still produces a valid (edge0 < edge1) smoothstep input rather
    // than undefined behaviour.
    float insideEdge = min(-uBoundarySharpDistance, -1e-4);
    float insideMask = smoothstep(insideEdge, 0.0, sdf);
    boundaryAlpha *= insideMask;

    // Final alpha: configured base alpha × density density-modulation ×
    // boundary alpha. The density modulation is now WIDE (0.55 → 1.0) so
    // light fog reads as roughly half-transparent (parallax / depth
    // suggestion) while dense fog stays fully opaque.
    float densityAlpha = mix(0.55, 1.0, dN);
    float finalAlpha = uBase.a * densityAlpha * boundaryAlpha;

    #ifdef MIRK_FOG_DEBUG_OUTPUT_DENSITY
        // DIAGNOSTIC: visualise raw density spatially. Should show a clear
        // noise pattern if the FBM stack is healthy. A uniform grey here
        // means the noise itself is degenerate (uTime stuck, uOffset
        // suspect, FBM sum collapsing). See lib/config/constants.dart
        // §kMirkFogDebugOutputDensity for the toggle protocol.
        fragColor = vec4(dN, dN, dN, 1.0);
    #else
        fragColor = vec4(fogColor, finalAlpha);
    #endif
}
