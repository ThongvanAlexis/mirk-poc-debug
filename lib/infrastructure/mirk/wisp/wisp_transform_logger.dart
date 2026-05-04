// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

/// 1-second JSONL rollup of per-paint wisp diagnostic state (WISP-05).
///
/// Sibling to `FogTransformLogger` (FOG-10), `SdfRebuildLogger` (FOG-03),
/// and `FrameDeltaProbe` (FOG-08). All four rollup loggers emit on
/// `now ~/ 1000` boundaries via wall-clock-aligned timers so post-walk
/// grep can join the four streams by `epochSecond`. This is the
/// load-bearing guarantee of CONTEXT §log-timeline-alignment.
///
/// Captured per paint (RESEARCH §Pattern 3 + Op 5):
///   - `activeCount` — wisps in flight
///   - `meanAge` — average normalised age across active wisps
///   - `latBounds` / `lonBounds` — wisp world-space envelope
///   - `screenXBounds` / `screenYBounds` — wisp screen-space envelope
///     (extracted from the painter's MapCamera projection — passed in as
///     already-derived (double, double) tuples to keep this logger free of
///     LatLng / Point imports per Op 5)
///   - `spawnRatePerSecond` — read from
///     `WispParticleSystem.spawnRatePerSecondAndReset()` once per rollup
///
/// Idle seconds (no [recordPaint] calls) emit nothing — same convention as
/// `FogTransformLogger` / `SdfRebuildLogger` / `FrameDeltaProbe`.
///
/// Permanent in production code per CONTEXT §Implementation Decisions —
/// debug-level always-on, NOT `--dart-define` gated. Cost ≈ 1 JSONL line
/// per active second; negligible against the 10 MB log smoke ceiling
/// (kMaxLogsDirBytes).
///
/// Buffer cap [kPocWispTransformBufferMaxSamples] (240 = 2 s × 120 Hz)
/// bounds memory; FIFO drop on overflow matches sibling-logger discipline.
///
/// Plan 04-01 ships the stub class shell; Plan 04-02 implements behaviour.
class WispTransformLogger {
  /// [rollupInterval] is a test seam — defaults to 1 second
  /// ([kPocWispTransformLogRollupSeconds]) in production. Tests pass a
  /// shorter interval (e.g. 100 ms) to keep the suite fast.
  WispTransformLogger({Duration? rollupInterval});

  /// Starts the rollup timer. Idempotent — calling start while running
  /// is a no-op. Plan 04-02 implements.
  void start() => throw UnimplementedError('Plan 04-02 implements');

  /// Cancels the timer and emits a final rollup if the buffer is non-empty.
  /// Synchronous flush guards against losing the final rollup if the
  /// owning widget's dispose runs mid-window. Plan 04-02 implements.
  void stop() => throw UnimplementedError('Plan 04-02 implements');

  /// Records one paint observation. Buffer overflow drops the oldest
  /// sample FIFO-style — same discipline as `FrameDeltaProbe._buffer`.
  /// Plan 04-02 implements.
  void recordPaint({
    required int activeCount,
    required double meanAge,
    required (double, double) latBounds,
    required (double, double) lonBounds,
    required (double, double) screenXBounds,
    required (double, double) screenYBounds,
    required double spawnRatePerSecond,
  }) => throw UnimplementedError('Plan 04-02 implements');
}
