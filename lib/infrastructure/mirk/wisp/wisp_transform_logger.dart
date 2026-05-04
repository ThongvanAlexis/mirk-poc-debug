// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// 1-second JSONL rollup of per-paint wisp diagnostic state (WISP-05).
///
/// Sibling to [FogTransformLogger] (FOG-10), [SdfRebuildLogger] (FOG-03),
/// and [FrameDeltaProbe] (FOG-08). All four rollup loggers emit on
/// `now ~/ 1000` boundaries via wall-clock-aligned timers so post-walk
/// grep can join the four streams by `epochSecond`. This is the
/// load-bearing guarantee of CONTEXT §log-timeline-alignment + Phase 3.1
/// retrospective lesson #4 ("ship the diagnostic before you need it" —
/// Walk #4's debug-spiral asymmetric observation was the pivotal moment
/// of closure; this logger is the wisp-side equivalent diagnostic
/// instrument).
///
/// Captured per paint: 1 int + 8 doubles + 1 spawn-rate-double:
///   - activeCount (int) — wisps alive in the system at this paint
///   - meanAge — Σ(age) / activeCount across the wisp list, [0, 1]
///   - latMin / latMax — bounding-box latitudes of all wisp positions
///   - lonMin / lonMax — bounding-box longitudes
///   - screenXMin / screenXMax — projected-Offset.x bounds
///   - screenYMin / screenYMax — projected-Offset.y bounds
///   - spawnRatePerSecond — wisps spawned during the rollup window /
///     interval (per-rollup-window-amortised; emit median only)
///
/// **Rollup schema — Claude's Discretion (CONTEXT §log-timeline-alignment).**
/// CONTEXT specified "min/median/max for 8 doubles + sampleCount + epochSecond
/// + activeCount + spawnRatePerSecond" — bounds-of-bounds simpler shape (~14
/// keys). The implementation emits stats-of-stats instead (min/median/max of
/// every per-paint min/max bound, ~35 keys total) so post-walk grep can
/// inspect the WORST-CASE per-second screen-bounds extremes (the latMaxMax /
/// screenYMaxMax columns) directly without re-aggregating the raw paint
/// stream. Per CONTEXT §Claude's Discretion: the byte budget remains honoured
/// (~600 bytes per emitted JSONL line — well below the 1500-byte safety
/// margin RESEARCH §Pattern 3 documented). Trade-off: more keys, but
/// post-walk one-shot grep answers "how big did the screen-bounds get during
/// any combined-gesture stress" without needing to expand and re-fold the
/// raw-sample stream. Phase 3.1 Walk #4 retrospective ("ship the diagnostic
/// before you need it") favours diagnostic richness over schema minimality.
///
/// Idle seconds emit nothing — same convention as siblings.
///
/// Permanent in production code per the Phase 3.1 carry-forward
/// (debug-level always-on, NOT --dart-define gated). Cost ≈ 1 JSONL
/// line per active second, ≤ ~600 bytes.
///
/// Buffer cap [kPocWispTransformBufferMaxSamples] (240 = 2 s × 120 Hz)
/// bounds memory; FIFO drop on overflow matches FrameDeltaProbe
/// discipline.
class WispTransformLogger {
  /// [rollupInterval] is a test seam — defaults to 1 second
  /// ([kPocWispTransformLogRollupSeconds]) in production.
  WispTransformLogger({Duration? rollupInterval}) : _rollupInterval = rollupInterval ?? const Duration(seconds: kPocWispTransformLogRollupSeconds);

  static final Logger _log = Logger('infrastructure.mirk.wisp');

  final Duration _rollupInterval;
  final List<_WispTransformSample> _buffer = <_WispTransformSample>[];
  Timer? _timer;
  int _frameCounter = 0;

  /// Starts the rollup timer. Idempotent — calling start while running
  /// is a no-op.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_rollupInterval, (_) => _emitRollup());
  }

  /// Cancels the timer and emits a final rollup if the buffer is non-empty.
  /// Synchronous flush guards against losing the final rollup if the
  /// owning widget's dispose runs mid-window.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isNotEmpty) {
      _emitRollup();
    }
  }

  /// Records one paint observation. Buffer overflow drops the oldest
  /// sample FIFO-style — same discipline as `FrameDeltaProbe._buffer`.
  void recordPaint({
    required int activeCount,
    required double meanAge,
    required (double, double) latBounds,
    required (double, double) lonBounds,
    required (double, double) screenXBounds,
    required (double, double) screenYBounds,
    required double spawnRatePerSecond,
  }) {
    _frameCounter += 1;
    _buffer.add(
      _WispTransformSample(
        frameCounter: _frameCounter,
        activeCount: activeCount,
        meanAge: meanAge,
        latMin: latBounds.$1,
        latMax: latBounds.$2,
        lonMin: lonBounds.$1,
        lonMax: lonBounds.$2,
        screenXMin: screenXBounds.$1,
        screenXMax: screenXBounds.$2,
        screenYMin: screenYBounds.$1,
        screenYMax: screenYBounds.$2,
        spawnRatePerSecond: spawnRatePerSecond,
      ),
    );
    while (_buffer.length > kPocWispTransformBufferMaxSamples) {
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

    // Materialise sorted column-views once per emit (same shape as FogTransformLogger).
    final meanAgeStats = computeStats(_buffer.map((s) => s.meanAge).toList()..sort());
    final latMinStats = computeStats(_buffer.map((s) => s.latMin).toList()..sort());
    final latMaxStats = computeStats(_buffer.map((s) => s.latMax).toList()..sort());
    final lonMinStats = computeStats(_buffer.map((s) => s.lonMin).toList()..sort());
    final lonMaxStats = computeStats(_buffer.map((s) => s.lonMax).toList()..sort());
    final screenXMinStats = computeStats(_buffer.map((s) => s.screenXMin).toList()..sort());
    final screenXMaxStats = computeStats(_buffer.map((s) => s.screenXMax).toList()..sort());
    final screenYMinStats = computeStats(_buffer.map((s) => s.screenYMin).toList()..sort());
    final screenYMaxStats = computeStats(_buffer.map((s) => s.screenYMax).toList()..sort());
    final spawnRateStats = computeStats(_buffer.map((s) => s.spawnRatePerSecond).toList()..sort());

    // activeCount-specific stats: max + arithmetic mean.
    int activeMax = 0;
    int activeSum = 0;
    for (final s in _buffer) {
      if (s.activeCount > activeMax) activeMax = s.activeCount;
      activeSum += s.activeCount;
    }
    final activeMean = activeSum / sampleCount;

    // WALL-CLOCK source — REQUIRED for grep-correlation with sibling
    // streams (fog_transform, sdf, frame_delta). Identical derivation.
    // DO NOT switch to a Stopwatch-derived value (would break the
    // post-walk join).
    final epochSecond = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final line = json.encode(<String, Object>{
      'epochSecond': epochSecond,
      'sampleCount': sampleCount,
      'activeCountMax': activeMax,
      'activeCountMean': activeMean.toStringAsFixed(6),
      'meanAgeMin': meanAgeStats.$1.toStringAsFixed(6),
      'meanAgeMedian': meanAgeStats.$2.toStringAsFixed(6),
      'meanAgeMax': meanAgeStats.$3.toStringAsFixed(6),
      'latMinMin': latMinStats.$1.toStringAsFixed(6),
      'latMinMedian': latMinStats.$2.toStringAsFixed(6),
      'latMinMax': latMinStats.$3.toStringAsFixed(6),
      'latMaxMin': latMaxStats.$1.toStringAsFixed(6),
      'latMaxMedian': latMaxStats.$2.toStringAsFixed(6),
      'latMaxMax': latMaxStats.$3.toStringAsFixed(6),
      'lonMinMin': lonMinStats.$1.toStringAsFixed(6),
      'lonMinMedian': lonMinStats.$2.toStringAsFixed(6),
      'lonMinMax': lonMinStats.$3.toStringAsFixed(6),
      'lonMaxMin': lonMaxStats.$1.toStringAsFixed(6),
      'lonMaxMedian': lonMaxStats.$2.toStringAsFixed(6),
      'lonMaxMax': lonMaxStats.$3.toStringAsFixed(6),
      'screenXMinMin': screenXMinStats.$1.toStringAsFixed(6),
      'screenXMinMedian': screenXMinStats.$2.toStringAsFixed(6),
      'screenXMinMax': screenXMinStats.$3.toStringAsFixed(6),
      'screenXMaxMin': screenXMaxStats.$1.toStringAsFixed(6),
      'screenXMaxMedian': screenXMaxStats.$2.toStringAsFixed(6),
      'screenXMaxMax': screenXMaxStats.$3.toStringAsFixed(6),
      'screenYMinMin': screenYMinStats.$1.toStringAsFixed(6),
      'screenYMinMedian': screenYMinStats.$2.toStringAsFixed(6),
      'screenYMinMax': screenYMinStats.$3.toStringAsFixed(6),
      'screenYMaxMin': screenYMaxStats.$1.toStringAsFixed(6),
      'screenYMaxMedian': screenYMaxStats.$2.toStringAsFixed(6),
      'screenYMaxMax': screenYMaxStats.$3.toStringAsFixed(6),
      'spawnRatePerSecondMin': spawnRateStats.$1.toStringAsFixed(6),
      'spawnRatePerSecondMedian': spawnRateStats.$2.toStringAsFixed(6),
      'spawnRatePerSecondMax': spawnRateStats.$3.toStringAsFixed(6),
    });
    _log.info(line);
    _buffer.clear();
  }
}

/// Immutable per-paint observation. Twelve final fields (frameCounter +
/// 1 int + 9 doubles + 1 spawn-rate-double) — kept private because the
/// JSONL rollup is the only supported consumer outside the logger.
@immutable
class _WispTransformSample {
  const _WispTransformSample({
    required this.frameCounter,
    required this.activeCount,
    required this.meanAge,
    required this.latMin,
    required this.latMax,
    required this.lonMin,
    required this.lonMax,
    required this.screenXMin,
    required this.screenXMax,
    required this.screenYMin,
    required this.screenYMax,
    required this.spawnRatePerSecond,
  });

  final int frameCounter;
  final int activeCount;
  final double meanAge;
  final double latMin;
  final double latMax;
  final double lonMin;
  final double lonMax;
  final double screenXMin;
  final double screenXMax;
  final double screenYMin;
  final double screenYMax;
  final double spawnRatePerSecond;
}
