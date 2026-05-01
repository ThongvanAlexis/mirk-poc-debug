// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// 1-second JSONL rollup of SDF rebuild stats (FOG-03).
///
/// Per-rebuild lines are noise during 120 Hz pan; 1-second rollups give
/// post-walk grep enough resolution to correlate SDF activity with the
/// frame-delta probe rollup. Both rollup loggers (this one and the
/// `Logger('infrastructure.mirk.frame_delta')` from Plan 03-04) emit on
/// `now ~/ 1000` boundaries via wall-clock-aligned timers so post-walk
/// grep can join lines by `epochSecond`.
///
/// Idle seconds (no [recordRebuild] calls) emit nothing — keeps the log
/// sink calm when the user is standing still.
///
/// Sample stats are computed over the buffer's duration values:
/// median = sorted[len/2]; p95 = sorted[(len*0.95).floor()]; max = sorted.last.
class SdfRebuildLogger {
  /// [rollupInterval] is a test seam — defaults to 1 second
  /// ([kPocSdfLogRollupSeconds]) in production. Tests pass a shorter
  /// interval (e.g. 100 ms) to keep the suite fast.
  SdfRebuildLogger({Duration? rollupInterval}) : _rollupInterval = rollupInterval ?? const Duration(seconds: kPocSdfLogRollupSeconds);

  static final Logger _log = Logger('infrastructure.mirk.sdf');

  final Duration _rollupInterval;
  final List<double> _elapsedMsBuffer = <double>[];
  int _lastDiscCount = 0;
  int _lastIntersectingDiscCount = 0;
  Timer? _timer;

  /// Starts the rollup timer. Idempotent — calling start while running is a no-op.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_rollupInterval, (_) => _emitRollup());
  }

  /// Cancels the timer and emits a final rollup if the buffer is non-empty.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_elapsedMsBuffer.isNotEmpty) {
      _emitRollup();
    }
  }

  /// Records one rebuild's duration + disc context. Buffer clears on every emit.
  void recordRebuild({required double elapsedMs, required int discCount, required int intersectingDiscCount}) {
    _elapsedMsBuffer.add(elapsedMs);
    _lastDiscCount = discCount;
    _lastIntersectingDiscCount = intersectingDiscCount;
  }

  void _emitRollup() {
    if (_elapsedMsBuffer.isEmpty) return;
    final sorted = List<double>.from(_elapsedMsBuffer)..sort();
    final median = sorted[sorted.length ~/ 2];
    final p95Index = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    final p95 = sorted[p95Index];
    final maxMs = sorted.last;
    final epochSecond = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final line = json.encode(<String, Object>{
      'epochSecond': epochSecond,
      'discCount': _lastDiscCount,
      'intersectingDiscCount': _lastIntersectingDiscCount,
      'rebuildCount': _elapsedMsBuffer.length,
      'medianMs': double.parse(median.toStringAsFixed(3)),
      'p95Ms': double.parse(p95.toStringAsFixed(3)),
      'maxMs': double.parse(maxMs.toStringAsFixed(3)),
    });
    _log.info(line);
    _elapsedMsBuffer.clear();
  }
}
