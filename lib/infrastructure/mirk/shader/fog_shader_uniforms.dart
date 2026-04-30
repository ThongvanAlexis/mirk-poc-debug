// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui show FragmentShader, Image;
import 'dart:ui' show Size;

/// Sets all uniforms on a `ui.FragmentShader` instance for the
/// volumetric fog `.frag`.
///
/// Phase 09 BUG-009 (TIER 2). Hand-counted slot indices match the
/// uniform declaration order in `assets/shaders/atmospheric_fog.frag`.
/// The single source of truth for the shader's uniform layout — if
/// either side changes, BOTH update together.
///
/// ## Slot layout (must match `.frag` uniform order)
///
/// | Slot  | Uniform                  | Type   |
/// |-------|--------------------------|--------|
/// | 0..1  | uResolution              | vec2   |
/// | 2     | uTime                    | float  |
/// | 3..4  | uOffset                  | vec2   |
/// | 5..8  | uBase                    | vec4   |
/// | 9..12 | uHighlight               | vec4   |
/// | 13..16| uShadow                  | vec4   |
/// | 17    | uDriftZFar               | float  |
/// | 18    | uDriftZMid               | float  |
/// | 19    | uDriftZNear              | float  |
/// | 20    | uScaleFar                | float  |
/// | 21    | uScaleMid                | float  |
/// | 22    | uScaleNear               | float  |
/// | 23    | uOpacityFar              | float  |
/// | 24    | uOpacityMid              | float  |
/// | 25    | uOpacityNear             | float  |
/// | 26    | uCurlAmplitude           | float  |
/// | 27    | uCurlScale               | float  |
/// | 28    | uLightDirRadians         | float  |
/// | 29    | uLightOffset             | float  |
/// | 30    | uLightStrength           | float  |
/// | 31    | uHueNoiseScale           | float  |
/// | 32    | uHueStrength             | float  |
/// | 33    | uBoundarySharpDistance   | float  |
/// | 34    | uBoundaryBleedDistance   | float  |
/// | 35    | uBoundaryEdgeBand        | float  |
/// | 36    | uBoundaryDensityBoost    | float  |
/// | 37    | uSdfRectOriginX          | float  |
/// | 38    | uSdfRectOriginY          | float  |
/// | 39    | uSdfRectSizeX            | float  |
/// | 40    | uSdfRectSizeY            | float  |
///
/// Sampler 0: uSdf — set via `setImageSampler(0, sdfImage)`.
class FogShaderUniforms {
  const FogShaderUniforms._();

  /// Total number of float uniform slots. Useful for tests that want
  /// to assert the layout shape.
  static const int totalFloatSlots = 41;

  /// Sets every uniform on [shader] in one call. Caller supplies
  /// already-decoded scalars / colours / records — no re-parsing inside.
  static void setAll(
    ui.FragmentShader shader, {
    required Size resolution,
    required double time,
    required (double, double) offset,
    required int baseArgb,
    required double baseAlpha,
    required int highlightArgb,
    required int shadowArgb,
    required double driftZFar,
    required double driftZMid,
    required double driftZNear,
    required double scaleFar,
    required double scaleMid,
    required double scaleNear,
    required double opacityFar,
    required double opacityMid,
    required double opacityNear,
    required double curlAmplitude,
    required double curlScale,
    required double lightDirRadians,
    required double lightOffset,
    required double lightStrength,
    required double hueNoiseScale,
    required double hueStrength,
    required double boundarySharpDistance,
    required double boundaryBleedDistance,
    required double boundaryEdgeBand,
    required double boundaryDensityBoost,
    required (double, double, double, double) sdfRect,
    required ui.Image sdfImage,
  }) {
    // uResolution — slots 0, 1
    shader.setFloat(0, resolution.width);
    shader.setFloat(1, resolution.height);
    // uTime — slot 2
    shader.setFloat(2, time);
    // uOffset — slots 3, 4
    shader.setFloat(3, offset.$1);
    shader.setFloat(4, offset.$2);
    // uBase — slots 5..8 (RGB from ARGB int + supplied alpha)
    final baseR = ((baseArgb >> 16) & 0xFF) / 255.0;
    final baseG = ((baseArgb >> 8) & 0xFF) / 255.0;
    final baseB = (baseArgb & 0xFF) / 255.0;
    shader.setFloat(5, baseR);
    shader.setFloat(6, baseG);
    shader.setFloat(7, baseB);
    shader.setFloat(8, baseAlpha);
    // uHighlight — slots 9..12 (alpha hard-coded 1; shader only reads .rgb)
    final hlR = ((highlightArgb >> 16) & 0xFF) / 255.0;
    final hlG = ((highlightArgb >> 8) & 0xFF) / 255.0;
    final hlB = (highlightArgb & 0xFF) / 255.0;
    shader.setFloat(9, hlR);
    shader.setFloat(10, hlG);
    shader.setFloat(11, hlB);
    shader.setFloat(12, 1.0);
    // uShadow — slots 13..16
    final shR = ((shadowArgb >> 16) & 0xFF) / 255.0;
    final shG = ((shadowArgb >> 8) & 0xFF) / 255.0;
    final shB = (shadowArgb & 0xFF) / 255.0;
    shader.setFloat(13, shR);
    shader.setFloat(14, shG);
    shader.setFloat(15, shB);
    shader.setFloat(16, 1.0);
    // Drift Z — slots 17..19
    shader.setFloat(17, driftZFar);
    shader.setFloat(18, driftZMid);
    shader.setFloat(19, driftZNear);
    // Scales — slots 20..22
    shader.setFloat(20, scaleFar);
    shader.setFloat(21, scaleMid);
    shader.setFloat(22, scaleNear);
    // Opacities — slots 23..25
    shader.setFloat(23, opacityFar);
    shader.setFloat(24, opacityMid);
    shader.setFloat(25, opacityNear);
    // Curl — slots 26..27
    shader.setFloat(26, curlAmplitude);
    shader.setFloat(27, curlScale);
    // Light — slots 28..30
    shader.setFloat(28, lightDirRadians);
    shader.setFloat(29, lightOffset);
    shader.setFloat(30, lightStrength);
    // Hue — slots 31..32
    shader.setFloat(31, hueNoiseScale);
    shader.setFloat(32, hueStrength);
    // Boundary — slots 33..35
    shader.setFloat(33, boundarySharpDistance);
    shader.setFloat(34, boundaryBleedDistance);
    shader.setFloat(35, boundaryEdgeBand);
    // Boundary density boost — slot 36 (BUG-009 follow-up 2026-04-26)
    shader.setFloat(36, boundaryDensityBoost);
    // SDF rect — slots 37..40 (BUG-014 follow-up: decomposed from vec4
    // to four floats to avoid Impeller/Metal vec4 component reordering)
    shader.setFloat(37, sdfRect.$1);
    shader.setFloat(38, sdfRect.$2);
    shader.setFloat(39, sdfRect.$3);
    shader.setFloat(40, sdfRect.$4);
    // SDF sampler — index 0
    shader.setImageSampler(0, sdfImage);
  }
}
