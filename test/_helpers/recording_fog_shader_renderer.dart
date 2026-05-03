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
    required this.worldMetersOrigin,
    required this.baseAlpha,
    required this.sdfRect,
    required this.sdfImage,
    required this.namedFloatArgs,
    required this.metersPerPixel,
  });

  /// Painter `size` argument — drives the `uResolution` uniform.
  final Size resolution;

  /// LIVE `uTime` value at the moment of paint.
  final double timeSeconds;

  /// Plan 03.1-14 (Fix B′ — FOG-19) — meter-space bounded composite
  /// forwarded to the shader as the slot-3/4 uniform `uWorldMetersOrigin`.
  /// Computed at the painter as `(intMeters % kPocFogIntegerWrapPeriodMeters)
  /// + fracMeters`. Magnitude is under `kPocFogIntegerWrapPeriodMeters + 1`
  /// = 4097 m regardless of pixelOrigin magnitude. Pre-Plan-03.1-14, this
  /// field was named `pixelOrigin` and carried the FOG-17a pixel-space
  /// bounded composite — flipped semantically by Plan 03.1-14 to close
  /// the period-commensurability gap that Walk #5 surfaced.
  final (double, double) worldMetersOrigin;

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

  /// FOG-18 (Plan 03.1-12) — world-meter anchor `uMetersPerPixel` value
  /// (slot 41). Computed at the painter as
  /// `kWebMercatorMetersPerPxAtEquatorZ0 * cos(lat) / pow(2, zoom)`.
  /// Tests assert that this value is non-zero AND that it changes
  /// across paints when the synthetic camera's zoom changes (defends
  /// against a hardcoded-cached regression at the painter level).
  final double metersPerPixel;

  /// Counts every distinct float slot observed. The recording renderer
  /// records:
  ///
  ///   * 2 floats from [resolution] (width, height)
  ///   * 1 float from [timeSeconds]
  ///   * 2 floats from [worldMetersOrigin]
  ///   * 1 float from [baseAlpha]
  ///   * 4 floats from [sdfRect]
  ///   * `namedFloatArgs.length` floats (kMirkFog* constants)
  ///   * 1 float from [metersPerPixel] (FOG-18 slot 41)
  ///
  /// At kMirkFog* count = 20 + post-FOG-18 metersPerPixel, total is
  /// `2+1+2+1+4+20+1 = 31`. Production FogShaderUniforms.totalFloatSlots
  /// is 42 (post-FOG-18 — adds slot 41 uMetersPerPixel; resolution=2 +
  /// time=1 + worldMetersOrigin=2 + uBase=4 + uHighlight=4 + uShadow=4 + 20
  /// kMirkFog floats + sdfRect=4 + metersPerPixel=1 = 42). The recording
  /// renderer does NOT record uHighlight / uShadow because the
  /// production code path passes those as compile-time constants (ARGB
  /// ints hard-coded in `_FragmentShaderFogRenderer`); tests assert
  /// FOG-05 by inspecting the production renderer source, while THIS
  /// getter measures what flowed through the renderer interface for
  /// behavioural coverage.
  int get totalFloatSlotsObserved => 2 + 1 + 2 + 1 + 4 + namedFloatArgs.length + 1;
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
    required (double, double) worldMetersOrigin,
    required double baseAlpha,
    required (double, double, double, double) sdfRect,
    required ui.Image sdfImage,
    required Map<String, double> mirkFogConstants,
    required double metersPerPixel,
  }) {
    renders.add(
      RecordedFogRender(
        resolution: resolution,
        timeSeconds: timeSeconds,
        worldMetersOrigin: worldMetersOrigin,
        baseAlpha: baseAlpha,
        sdfRect: sdfRect,
        sdfImage: sdfImage,
        namedFloatArgs: Map<String, double>.from(mirkFogConstants),
        metersPerPixel: metersPerPixel,
      ),
    );
  }
}
