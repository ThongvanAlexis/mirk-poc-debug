// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart' show FogShaderRenderer;

/// Snapshot of every named arg passed to a single `FogShaderRenderer.render(...)`
/// invocation. Tests inspect this to assert FOG-05 invariants:
///
///   * 41-slot float coverage: [totalFloatSlotsObserved] must be `>= 41`.
///   * Identity `uSdfRect`: [sdfRect] must be `(0.0, 0.0, 1.0, 1.0)` (per
///     CONTEXT.md non-negotiable — RESEARCH §Anti-Pattern 1).
///   * Live `uTime` per paint: callers can compare [timeSeconds] across
///     successive recorded renders to assert the painter reads the wall-clock
///     stopwatch fresh per `paint()` (PERF-03 idle-fog-animation gate).
@immutable
class RecordedFogRender {
  /// Captures a render invocation. All fields mirror named args of
  /// `FogShaderRenderer.render(...)`.
  const RecordedFogRender({
    required this.resolution,
    required this.timeSeconds,
    required this.pixelOrigin,
    required this.baseAlpha,
    required this.sdfRect,
    required this.sdfImage,
    required this.namedFloatArgs,
    required this.zoomScale,
    required this.fragCoordYFlip,
  });

  /// Painter `size` argument — drives the `uResolution` uniform.
  final Size resolution;

  /// LIVE `uTime` value at the moment of paint.
  final double timeSeconds;

  /// `uPixelOrigin` 2-tuple — full-precision world-pixel origin from the
  /// painter's `camera.pixelOrigin` (Plan 03.1-04 contract). The shader
  /// applies `fract()` per-fragment; the Dart call site forwards the
  /// values verbatim without any modulo.
  final (double, double) pixelOrigin;

  /// Base-colour alpha — slot 8 in the FogShaderUniforms layout.
  final double baseAlpha;

  /// Identity-rect tuple — must be `(0.0, 0.0, 1.0, 1.0)` per FOG-05.
  final (double, double, double, double) sdfRect;

  /// SDF sampler — production: 256² R-channel midpoint-128; tests: any
  /// `ui.Image`. Captured by reference; never inspected by [RecordedFogRender]
  /// itself — tests can `identical()` against an image they pre-loaded.
  final ui.Image sdfImage;

  /// Map of every kMirkFog* float by named key → value. Test asserts on
  /// presence of all 20 entries (`driftZFar` … `boundaryDensityBoost`).
  final Map<String, double> namedFloatArgs;

  /// FOG-19 (Plan 03.1-14 Task B) — uZoomScale at slot 41. Forwarded by
  /// the painter as `pow(2, camera.zoom - kPocFogReferenceZoom)`. At
  /// camera.zoom == kPocFogReferenceZoom (=13.0), zoomScale = 1.0 and
  /// the shader noise sampling is bit-identical to the pre-FOG-19
  /// formulation (MIRL visual-identity-preservation rule per CLAUDE.md
  /// `# MIRL solution` updated 2026-05-04).
  final double zoomScale;

  /// FOG-20 (Pixel 4a Y-flip fix, 2026-05-14) — uFragCoordYFlip at slot
  /// 42. Forwarded by the painter as `1.0` on Android, `0.0` on iOS.
  /// Drives the shader's single `mix`-based Y-axis correction for the
  /// Pixel 4a backend Y-flip; at `0.0` the iOS render path is
  /// byte-identical to pre-FOG-20.
  final double fragCoordYFlip;

  /// Counts every distinct float slot observed. The recording renderer
  /// records:
  ///
  ///   * 2 floats from [resolution] (width, height)
  ///   * 1 float from [timeSeconds]
  ///   * 2 floats from [pixelOrigin]
  ///   * 1 float from [baseAlpha]
  ///   * 4 floats from [sdfRect]
  ///   * 1 float from [zoomScale] — FOG-19 / Plan 03.1-14 Task B (slot 41)
  ///   * 1 float from [fragCoordYFlip] — FOG-20 / Pixel 4a Y-flip fix (slot 42)
  ///   * `namedFloatArgs.length` floats (kMirkFog* constants)
  ///
  /// At kMirkFog* count = 20 (Plan 03-05 baseline) + zoomScale +
  /// fragCoordYFlip, total is `2+1+2+1+4+1+1+20 = 32`. FOG-05's "43 slots"
  /// invariant counts every uniform float in
  /// `FogShaderUniforms.totalFloatSlots` (resolution=2 + time=1 +
  /// pixelOrigin=2 + uBase=4 + uHighlight=4 + uShadow=4 + 20 kMirkFog
  /// floats + sdfRect=4 + zoomScale=1 + fragCoordYFlip=1 = 43).
  /// The recording renderer does NOT record uHighlight / uShadow because the
  /// production code path passes those as compile-time constants (ARGB ints
  /// hard-coded in `_FragmentShaderFogRenderer`); tests assert FOG-05 by
  /// inspecting the production renderer source, while THIS getter measures
  /// what flowed through the renderer interface for behavioural coverage.
  int get totalFloatSlotsObserved => 2 + 1 + 2 + 1 + 4 + 1 + 1 + namedFloatArgs.length;
}

/// Test impl of [FogShaderRenderer] — records every `render(...)` call into
/// [renders] instead of touching a real `ui.FragmentShader` (which can't be
/// instantiated in headless test envs because `FragmentProgram.fromAsset`
/// requires the asset bundle + a working GPU).
///
/// Production impl is `_FragmentShaderFogRenderer` inside
/// `lib/presentation/widgets/fog_layer.dart`; widget tests inject this
/// recording variant via the `FogLayer(shaderRenderer: ...)` constructor seam.
class RecordingFogShaderRenderer implements FogShaderRenderer {
  /// All recorded renders, in invocation order. The most recent paint is
  /// `renders.last`; the very first paint is `renders.first`.
  final List<RecordedFogRender> renders = <RecordedFogRender>[];

  @override
  void render({
    required ui.FragmentShader? shader,
    required Size resolution,
    required double timeSeconds,
    required (double, double) pixelOrigin,
    required double baseAlpha,
    required (double, double, double, double) sdfRect,
    required ui.Image sdfImage,
    required Map<String, double> mirkFogConstants,
    required double zoomScale,
    required double fragCoordYFlip,
  }) {
    renders.add(
      RecordedFogRender(
        resolution: resolution,
        timeSeconds: timeSeconds,
        pixelOrigin: pixelOrigin,
        baseAlpha: baseAlpha,
        sdfRect: sdfRect,
        sdfImage: sdfImage,
        namedFloatArgs: Map<String, double>.from(mirkFogConstants),
        zoomScale: zoomScale,
        fragCoordYFlip: fragCoordYFlip,
      ),
    );
  }
}
