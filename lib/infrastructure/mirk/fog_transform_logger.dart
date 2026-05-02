// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// 1-second JSONL rollup of per-paint fog Canvas-transform vs camera-pixelOrigin
/// vs applied-uOffset diagnostics (FOG-10).
///
/// Sibling to `SdfRebuildLogger` (FOG-03) and `FrameDeltaProbe` (FOG-08).
/// All three rollup loggers emit on `now ~/ 1000` boundaries via wall-clock-aligned
/// timers so post-walk grep can join the three streams by `epochSecond`. This is
/// the load-bearing guarantee of CONTEXT §log-timeline-alignment.
///
/// Captured per paint: 8 diagnostic doubles (canvasTx, canvasTy, pixelOriginX,
/// pixelOriginY, centerLat, centerLon, uOffsetX, uOffsetY). The rollup emits
/// min, median, and max for each field — 24 numeric values plus epochSecond +
/// sampleCount = 26 keys total per JSONL line.
///
/// Idle seconds (no [recordPaint] calls) emit nothing — same convention as
/// `SdfRebuildLogger` + `FrameDeltaProbe` (RESEARCH §Pattern B).
///
/// Permanent in production code per CONTEXT §Implementation Decisions —
/// debug-level always-on, NOT `--dart-define` gated. Cost ≈ 1 JSONL line per
/// active second, ≤ ~600 bytes; negligible against the 10 MB log smoke ceiling
/// (kMaxLogsDirBytes).
///
/// Buffer cap [kPocFogTransformBufferMaxSamples] (240 = 2 s × 120 Hz) bounds
/// memory; FIFO drop on overflow matches `FrameDeltaProbe` discipline.
class FogTransformLogger {
  /// [rollupInterval] is a test seam — defaults to 1 second
  /// ([kPocFogTransformLogRollupSeconds]) in production. Tests pass a shorter
  /// interval (e.g. 100 ms) to keep the suite fast.
  FogTransformLogger({Duration? rollupInterval}) : _rollupInterval = rollupInterval ?? const Duration(seconds: kPocFogTransformLogRollupSeconds);

  static final Logger _log = Logger('infrastructure.mirk.fog_transform');

  final Duration _rollupInterval;
  final List<_FogTransformSample> _buffer = <_FogTransformSample>[];
  Timer? _timer;
  int _frameCounter = 0;

  /// Starts the rollup timer. Idempotent — calling start while running is a no-op.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_rollupInterval, (_) => _emitRollup());
  }

  /// Cancels the timer and emits a final rollup if the buffer is non-empty.
  /// Synchronous flush guards against losing the final rollup if the owning
  /// widget's dispose runs mid-window.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isNotEmpty) {
      _emitRollup();
    }
  }

  /// Records one paint observation. Captures 8 diagnostic doubles extracted
  /// from the four named arguments:
  /// * `canvasTransform[12]` and `[13]` — column-major translation slots from
  ///   `Canvas.getTransform()` (RESEARCH §Pitfall D).
  /// * `cameraPixelOrigin.x/y` — `MapCamera.pixelOrigin` (the world-pixel
  ///   origin of the visible viewport at the current zoom).
  /// * `cameraCenter.latitude/longitude` — `MapCamera.center` (the camera's
  ///   geographic centre).
  /// * `appliedUOffset.$1/$2` — the (uOffsetX, uOffsetY) value the painter
  ///   forwarded to the shader.
  ///
  /// Buffer overflow drops the oldest sample FIFO-style — same discipline as
  /// `FrameDeltaProbe._buffer`.
  void recordPaint({
    required Float64List canvasTransform,
    required Point<double> cameraPixelOrigin,
    required LatLng cameraCenter,
    required (double, double) appliedUOffset,
  }) {
    _frameCounter += 1;
    _buffer.add(
      _FogTransformSample(
        frameCounter: _frameCounter,
        canvasTx: canvasTransform[12],
        canvasTy: canvasTransform[13],
        pixelOriginX: cameraPixelOrigin.x,
        pixelOriginY: cameraPixelOrigin.y,
        centerLat: cameraCenter.latitude,
        centerLon: cameraCenter.longitude,
        uOffsetX: appliedUOffset.$1,
        uOffsetY: appliedUOffset.$2,
      ),
    );
    while (_buffer.length > kPocFogTransformBufferMaxSamples) {
      _buffer.removeAt(0);
    }
  }

  /// Computes (min, median, max) from a non-empty list of doubles.
  ///
  /// The input must be pre-sorted ascending. Static + `@visibleForTesting`
  /// for unit-level coverage of the stat math without standing up a full logger.
  @visibleForTesting
  static (double min, double median, double max) computeStats(List<double> sortedAscending) {
    assert(sortedAscending.isNotEmpty, 'computeStats requires a non-empty sorted list');
    return (sortedAscending.first, sortedAscending[sortedAscending.length ~/ 2], sortedAscending.last);
  }

  void _emitRollup() {
    if (_buffer.isEmpty) return;
    final sampleCount = _buffer.length;
    // Materialise eight sorted column-views once per emit. O(8 × N × log N) per
    // second — at N=240 that's ~8 × 240 × 8 ≈ 15 k comparisons, well under the
    // JSONL-emit budget per RESEARCH §Pattern B sample-rate tradeoff.
    final canvasTxStats = computeStats(_buffer.map((s) => s.canvasTx).toList()..sort());
    final canvasTyStats = computeStats(_buffer.map((s) => s.canvasTy).toList()..sort());
    final pixelOriginXStats = computeStats(_buffer.map((s) => s.pixelOriginX).toList()..sort());
    final pixelOriginYStats = computeStats(_buffer.map((s) => s.pixelOriginY).toList()..sort());
    final centerLatStats = computeStats(_buffer.map((s) => s.centerLat).toList()..sort());
    final centerLonStats = computeStats(_buffer.map((s) => s.centerLon).toList()..sort());
    final uOffsetXStats = computeStats(_buffer.map((s) => s.uOffsetX).toList()..sort());
    final uOffsetYStats = computeStats(_buffer.map((s) => s.uOffsetY).toList()..sort());

    // WALL-CLOCK source — REQUIRED for grep-correlation with SdfRebuildLogger
    // and FrameDeltaProbe, both of which derive epochSecond identically.
    // DO NOT switch to a Stopwatch-derived value (would break the post-walk join).
    final epochSecond = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final line = json.encode(<String, Object>{
      'epochSecond': epochSecond,
      'sampleCount': sampleCount,
      'canvasTxMin': canvasTxStats.$1.toStringAsFixed(6),
      'canvasTxMedian': canvasTxStats.$2.toStringAsFixed(6),
      'canvasTxMax': canvasTxStats.$3.toStringAsFixed(6),
      'canvasTyMin': canvasTyStats.$1.toStringAsFixed(6),
      'canvasTyMedian': canvasTyStats.$2.toStringAsFixed(6),
      'canvasTyMax': canvasTyStats.$3.toStringAsFixed(6),
      'pixelOriginXMin': pixelOriginXStats.$1.toStringAsFixed(6),
      'pixelOriginXMedian': pixelOriginXStats.$2.toStringAsFixed(6),
      'pixelOriginXMax': pixelOriginXStats.$3.toStringAsFixed(6),
      'pixelOriginYMin': pixelOriginYStats.$1.toStringAsFixed(6),
      'pixelOriginYMedian': pixelOriginYStats.$2.toStringAsFixed(6),
      'pixelOriginYMax': pixelOriginYStats.$3.toStringAsFixed(6),
      'centerLatMin': centerLatStats.$1.toStringAsFixed(6),
      'centerLatMedian': centerLatStats.$2.toStringAsFixed(6),
      'centerLatMax': centerLatStats.$3.toStringAsFixed(6),
      'centerLonMin': centerLonStats.$1.toStringAsFixed(6),
      'centerLonMedian': centerLonStats.$2.toStringAsFixed(6),
      'centerLonMax': centerLonStats.$3.toStringAsFixed(6),
      'uOffsetXMin': uOffsetXStats.$1.toStringAsFixed(6),
      'uOffsetXMedian': uOffsetXStats.$2.toStringAsFixed(6),
      'uOffsetXMax': uOffsetXStats.$3.toStringAsFixed(6),
      'uOffsetYMin': uOffsetYStats.$1.toStringAsFixed(6),
      'uOffsetYMedian': uOffsetYStats.$2.toStringAsFixed(6),
      'uOffsetYMax': uOffsetYStats.$3.toStringAsFixed(6),
    });
    _log.info(line);
    _buffer.clear();
  }
}

/// Immutable per-paint observation. Nine final fields (frameCounter +
/// 8 diagnostic doubles) — kept private because the JSONL rollup is the only
/// supported consumer outside the logger.
@immutable
class _FogTransformSample {
  const _FogTransformSample({
    required this.frameCounter,
    required this.canvasTx,
    required this.canvasTy,
    required this.pixelOriginX,
    required this.pixelOriginY,
    required this.centerLat,
    required this.centerLon,
    required this.uOffsetX,
    required this.uOffsetY,
  });

  final int frameCounter;
  final double canvasTx;
  final double canvasTy;
  final double pixelOriginX;
  final double pixelOriginY;
  final double centerLat;
  final double centerLon;
  final double uOffsetX;
  final double uOffsetY;
}
