// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// Plan 03.1-08-FIX FIX 2 — DEBUG-ONLY diagnostic layer for `/map`.
///
/// Renders `assets/shaders/atmospheric_fog_debug_spiral.frag` driven by
/// the REAL `MapCamera.pixelOrigin` (instead of the synthetic time-driven
/// trajectory used by `_DebugSpiralPainter` on `/sanity`). This is the
/// load-bearing diagnostic surface — the user observes the spiral while
/// performing real pan/pinch gestures on `/map`, and the rendered cells
/// directly visualise what `camera.pixelOrigin / size` is doing under
/// production gesture conditions (the synthetic `/sanity` trajectory does
/// NOT reproduce zoom-correlated pixelOrigin jumps where the production
/// shimmer mechanism actually lives).
///
/// **Architecture mirrors [FogLayer]:**
///
///   * Single-MapCamera-snapshot lock (FOG-07 KEYSTONE). `MapCamera.of`
///     called EXACTLY ONCE per `build`; the painter NEVER re-reads
///     context.
///   * Per-frame Ticker → [Listenable] repaint. The painter takes
///     `repaint:` so paint cycles bypass build (RESEARCH §Pattern 1).
///   * LIVE Stopwatch passed BY REFERENCE; painter reads
///     `elapsedMicroseconds` fresh per `paint()` (anti-frozen-uTime
///     invariant — same discipline as FogLayer).
///   * Wrapped in [MobileLayerTransformer] by the caller (see MapScreen)
///     so the canvas frame matches the production fog path: the same
///     canvas-translate compensation pattern (Plan 03.1-08-FIX FIX 1)
///     applies — `canvas.translate(-canvasOffset)` at the TOP of paint().
///
/// **No SDF.** The debug shader does not sample the SDF — only the digit
/// atlas as sampler 1. `[atlas]` is process-cached by `DigitAtlasBuilder`;
/// the parent MapScreen resolves it before mounting this layer.
class DebugSpiralLayer extends StatefulWidget {
  /// Constructs the debug-spiral layer with a pre-loaded shader and a
  /// pre-resolved digit atlas image.
  const DebugSpiralLayer({super.key, required this.shader, required this.atlas});

  /// Pre-loaded `atmospheric_fog_debug_spiral.frag` fragment shader.
  /// Production callers ALWAYS pass a non-null shader; the painter still
  /// guards before calling `canvas.drawRect(..., Paint()..shader = shader)`.
  final ui.FragmentShader shader;

  /// Pre-resolved 10x10 digit atlas (`DigitAtlasBuilder.atlas`). Bound to
  /// sampler slot 1 on each paint.
  final ui.Image atlas;

  @override
  State<DebugSpiralLayer> createState() => _DebugSpiralLayerState();
}

class _DebugSpiralLayerState extends State<DebugSpiralLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _wallClockSinceMount = Stopwatch()..start();
  final _DebugSpiralRepaint _repaint = _DebugSpiralRepaint();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _repaint.notifyListeners());
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Single-MapCamera-snapshot — mirrors FOG-07 KEYSTONE. Camera passed
    // BY VALUE to the painter; never re-read inside paint().
    final MapCamera camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _DebugSpiralMapPainter(camera: camera, shader: widget.shader, atlas: widget.atlas, wallClock: _wallClockSinceMount, repaint: _repaint),
        size: Size.infinite,
      ),
    );
  }
}

/// Per-frame paint trigger fed by the Ticker. Mirrors [FogLayer]'s
/// `_Repaint`. The Ticker calls `notifyListeners()` once per frame; the
/// painter takes this as its `repaint:` Listenable so paint cycles bypass
/// build.
class _DebugSpiralRepaint extends ChangeNotifier {
  @override
  void notifyListeners() => super.notifyListeners();
}

/// CustomPainter for the debug-spiral on `/map`. Mirrors [FogLayer]'s
/// `_FogPainter` shape: reads `canvas.getTransform()` once, normalises
/// the canvas to the world frame via `canvas.translate(-canvasOffset)`
/// at the TOP of paint() (Plan 03.1-08-FIX discipline), then draws the
/// spiral covering the entire viewport.
class _DebugSpiralMapPainter extends CustomPainter {
  _DebugSpiralMapPainter({required this.camera, required this.shader, required this.atlas, required this.wallClock, required Listenable repaint})
    : super(repaint: repaint);

  final MapCamera camera;
  final ui.FragmentShader shader;
  final ui.Image atlas;
  final Stopwatch wallClock;

  @override
  void paint(Canvas canvas, Size size) {
    final uTimeSeconds = wallClock.elapsedMicroseconds / _microsecondsPerSecond;

    // Single canvas.getTransform() snapshot — same single-snapshot
    // discipline as _FogPainter (mirrors FOG-12). Read once, reuse
    // for the canvas-translate compensation.
    final canvasTransform = canvas.getTransform();
    final canvasOffset = Offset(canvasTransform[_canvasTransformTxIndex], canvasTransform[_canvasTransformTyIndex]);

    canvas.save();
    // Normalise prevailing transform to identity at the TOP of paint()
    // (Plan 03.1-08-FIX). Subsequent drawRect lands at the world-frame
    // origin → full viewport coverage on screen regardless of
    // MobileLayerTransformer's translation magnitude.
    canvas.translate(-canvasOffset.dx, -canvasOffset.dy);

    // Slot map matches production fog slots 0..4 verbatim (and matches the
    // /sanity-screen _DebugSpiralPainter):
    //   0..1 → uResolution
    //   2    → uTime
    //   3..4 → uWorldMetersOrigin (Plan 03.1-14 Fix B′ — meter-space bounded
    //          composite; was uPixelOrigin pre-Plan-03.1-14)
    //
    // Sampler slot 0 (NOT 1) — Flutter's setImageSampler indexes per-
    // shader from 0 in declaration order. The debug-spiral shader has
    // only one declared sampler (uDigitAtlas) so its slot is 0. Plan
    // 03.1-08-FIX FIX 3 — the Plan 03.1-07 landing bound at slot 1,
    // leaving the atlas effectively unbound on iPhone Impeller; same
    // mistake propagated into this layer when it was ported from the
    // /sanity-screen _DebugSpiralPainter.
    //
    // Plan 03.1-14 (Fix B′ — FOG-19) — debug-spiral mirrors production
    // fog's meter-space FOG-17a decomposition. Compute metersPerPixel
    // via the Web-Mercator ground-resolution formula; convert
    // pixelOrigin to meter-space FIRST, then decompose. Slots 3..4 now
    // forward `boundedMetersX/Y` (a meter-space bounded composite under
    // kPocFogIntegerWrapPeriodMeters + 1 = 4097 m) instead of raw
    // pixelOrigin. The shader's noiseUv computation flipped to
    // `(fragUv * uResolution) * uMetersPerPixel + uWorldMetersOrigin`
    // (slot indices 3..4 unchanged; semantic flips to meter-space).
    //
    // The debug-spiral shader's cell-numbering reflects the meter-space
    // coordinate system: cells are physical squares of ground (200 m
    // per cell at any zoom — kPocDebugSpiralCellSizeMeters) regardless
    // of zoom level. Cell numbering at fixed map position is now ALSO
    // continuous across wrap boundaries because every wrap injects a
    // CONSTANT-magnitude phase shift INVARIANT across all wrap events
    // (Octave 1 bit-identical via hash3 period-1; Octaves 2 + 3 receive
    // a deterministic ≈ 11% fbm3-dynamic-range residual shift bounded
    // analytically).
    final clampedLatDeg = camera.center.latitude.clamp(-_kDebugSpiralPolarLatClampDeg, _kDebugSpiralPolarLatClampDeg);
    final latRadians = clampedLatDeg * math.pi / _kDebugSpiralDegreesPerHalfTurn;
    final metersPerPixel = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRadians) / math.pow(2.0, camera.zoom).toDouble();

    // Plan 03.1-14 Fix B′ — meter-space FOG-17a decomposition (mirror of
    // _FogPainter.paint()).
    final pixelOrigin = camera.pixelOrigin;
    final worldMetersX = pixelOrigin.x * metersPerPixel;
    final worldMetersY = pixelOrigin.y * metersPerPixel;
    final intMetersX = worldMetersX.truncateToDouble();
    final intMetersY = worldMetersY.truncateToDouble();
    final fracMetersX = worldMetersX - intMetersX;
    final fracMetersY = worldMetersY - intMetersY;
    final boundedMetersX = (intMetersX % kPocFogIntegerWrapPeriodMeters) + fracMetersX;
    final boundedMetersY = (intMetersY % kPocFogIntegerWrapPeriodMeters) + fracMetersY;

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, uTimeSeconds);
    shader.setFloat(3, boundedMetersX); // ← Plan 03.1-14 Fix B′ — meter-space bounded composite (was raw pixelOrigin.x pre-Plan-03.1-14).
    shader.setFloat(4, boundedMetersY); // ← Plan 03.1-14 Fix B′ — meter-space bounded composite (was raw pixelOrigin.y pre-Plan-03.1-14).
    shader.setFloat(5, metersPerPixel); // ← FOG-18 slot 5 (debug-spiral has slots 0..5 + sampler).
    shader.setImageSampler(0, atlas);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DebugSpiralMapPainter oldDelegate) {
    // The Listenable `repaint:` argument drives per-frame redraws.
    // shouldRepaint gates whether a NEW painter instance triggers a
    // paint. Compare on identity of camera + shader + atlas — anything
    // else is a no-op repaint.
    return !identical(oldDelegate.camera, camera) || !identical(oldDelegate.shader, shader) || !identical(oldDelegate.atlas, atlas);
  }
}

/// `Stopwatch.elapsedMicroseconds → seconds` divisor. Hoisted to avoid
/// a magic `1e6` inline in `paint()`.
const double _microsecondsPerSecond = 1e6;

/// Column-major index of the `tx` translation component in a 4x4
/// Float64List matrix returned by `Canvas.getTransform()`. Mirrors
/// [FogLayer]'s constants (kept here so the debug layer is fully
/// self-contained — diagnostic-only, no cross-file dependency).
const int _canvasTransformTxIndex = 12;
const int _canvasTransformTyIndex = 13;

/// Polar latitude clamp for the FOG-18 metersPerPixel computation in the debug
/// spiral painter. Mirrors `_FogPainter`'s clamp; cos(±90°) → 0 would zero out
/// the spiral coordinate.
const double _kDebugSpiralPolarLatClampDeg = 89.0;

/// Degrees-per-half-turn — `lat * π / 180.0` converts latitude in degrees to
/// radians for the FOG-18 metersPerPixel computation.
const double _kDebugSpiralDegreesPerHalfTurn = 180.0;
