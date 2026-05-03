// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';

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
    //   3..4 → uPixelOrigin (REAL camera.pixelOrigin — the load-bearing
    //          difference vs. /sanity's synthetic trajectory)
    final pixelOrigin = camera.pixelOrigin;
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, uTimeSeconds);
    shader.setFloat(3, pixelOrigin.x.toDouble());
    shader.setFloat(4, pixelOrigin.y.toDouble());
    shader.setImageSampler(1, atlas);
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
