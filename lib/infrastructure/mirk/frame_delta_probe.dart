// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// Per-second probe rollup payload — emitted at 1 Hz on the
/// [FrameDeltaProbe.rollups] stream and persisted as one JSONL line via
/// `Logger('infrastructure.mirk.frame_delta')`.
///
/// All `*Micros` fields are integer microseconds derived from a monotonic
/// `Stopwatch.elapsedMicroseconds` source (see [FrameDeltaProbe] dual-clock
/// discipline). The `*Ms` getters are 3-decimal convenience values that
/// match the millisecond convention used by `SdfRebuildLogger` so post-walk
/// tooling can read both formats with the same parser.
class FrameDeltaRollup {
  /// Constructs a rollup payload. All fields are required and non-null.
  const FrameDeltaRollup({required this.epochSecond, required this.sampleCount, required this.medianMicros, required this.p95Micros, required this.maxMicros});

  /// Wall-clock epoch second of this rollup window (`DateTime.now() / 1000`).
  /// Required for grep-correlation with `SdfRebuildLogger` (Plan 03-03),
  /// which uses the same wall-clock derivation. NEVER Stopwatch-derived.
  final int epochSecond;

  /// Number of raw samples that fed into this rollup. Always
  /// `≤ kPocFrameDeltaBufferMaxSamples` (240).
  final int sampleCount;

  /// Median camera-snapshot → fog-uniform-population delta in microseconds.
  final int medianMicros;

  /// p95 of the same delta in microseconds.
  final int p95Micros;

  /// Max of the same delta in microseconds.
  final int maxMicros;

  /// Median delta as a 3-decimal millisecond double (convenience for the
  /// overlay + post-walk tooling parity with `SdfRebuildLogger`).
  double get medianMs => medianMicros / 1000.0;

  /// p95 delta as a 3-decimal millisecond double.
  double get p95Ms => p95Micros / 1000.0;

  /// Max delta as a 3-decimal millisecond double.
  double get maxMs => maxMicros / 1000.0;
}

/// Frame-delta self-debug probe (FOG-08).
///
/// Records the per-frame delta between the moment FogLayer reads
/// `MapCamera.of(context)` (the camera snapshot) and the moment the painter
/// finishes populating `FogShaderUniforms.setAll(...)` (uniform population).
/// Aggregates raw samples into 1-second rollups, exposes them as a
/// broadcast `Stream<FrameDeltaRollup>` (consumed by FrameDeltaProbeOverlay
/// in Plan 03-06), and persists each rollup as a structured JSONL line via
/// `Logger('infrastructure.mirk.frame_delta')` for post-walk evidence in
/// 03-FALSIFICATION.md.
///
/// ## Wire flow (per RESEARCH.md Pattern 6)
///
/// 1. `FogLayer.build()` reads `MapCamera.of(context)` once, then calls
///    [recordCameraSnapshot] capturing the post-read Stopwatch microsecond
///    timestamp. The returned `int` is threaded into the painter's
///    constructor.
/// 2. `_FogPainter.paint()` calls [recordFogUniformPopulation] right before
///    `FogShaderUniforms.setAll(...)`. The probe records `(now - snap)` as
///    the per-frame camera-to-paint delta.
///
/// ## Dual-clock discipline (DO NOT collapse into one clock)
///
/// The probe holds TWO clocks ON PURPOSE:
///
/// * `_clock` (Stopwatch — monotonic, backed by `mach_absolute_time` on
///   iOS) — sole source for delta math: [recordCameraSnapshot],
///   [recordFogUniformPopulation], the contents of `_buffer`, and the
///   resulting `medianMicros`/`p95Micros`/`maxMicros`. Immune to NTP
///   corrections during a 5-min walk (RESEARCH.md Pitfall 4).
///   Defence-in-depth: a non-monotonic input (impossible from
///   `Stopwatch.elapsedMicroseconds` but possible via a probe bug
///   elsewhere) clamps the delta at 0 instead of throwing — never
///   crashes the paint path.
///
/// * `DateTime.now().millisecondsSinceEpoch` (wall-clock) — sole source
///   for the [FrameDeltaRollup.epochSecond] rollup tag. REQUIRED for
///   grep-correlation with `SdfRebuildLogger` (Plan 03-03), which also
///   derives its `epochSecond` from `DateTime.now()`. Without a shared
///   wall-clock tag, the two log streams could not be joined post-walk.
///
/// **Future executors: DO NOT "simplify" by switching the delta path to
/// `DateTime.now()`.** An NTP correction during the walk would emit
/// nonsense delta values (negative deltas, hour-long jumps). The two
/// clocks coexist on purpose; test #7 in
/// `frame_delta_probe_test.dart` defends this invariant.
///
/// Rollups emit at 1 Hz; idle seconds (empty buffer) emit nothing. Per-frame
/// raw lines would be ~120 lines/sec × 5 min ≈ 36 k lines — rolling up loses
/// outlier ms but the [FrameDeltaRollup.maxMicros] field preserves them.
class FrameDeltaProbe {
  /// Constructs a probe. The rollup timer does NOT start until [start] is
  /// called (idempotent).
  ///
  /// Test seams:
  /// * [rollupInterval] — defaults to `kPocFrameDeltaLogRollupSeconds`
  ///   (1 second). Tests use a short interval for fast emission.
  /// * [clock] — defaults to a fresh started Stopwatch. Tests can inject
  ///   a synthetic clock for deterministic timestamps. If passed, the
  ///   probe will start it if not already running.
  FrameDeltaProbe({Duration? rollupInterval, Stopwatch? clock})
    : _rollupInterval = rollupInterval ?? const Duration(seconds: kPocFrameDeltaLogRollupSeconds),
      _clock = clock ?? (Stopwatch()..start()) {
    if (!_clock.isRunning) _clock.start();
  }

  static final Logger _log = Logger('infrastructure.mirk.frame_delta');

  final Duration _rollupInterval;
  final Stopwatch _clock;
  final List<int> _buffer = <int>[];
  final StreamController<FrameDeltaRollup> _controller = StreamController<FrameDeltaRollup>.broadcast();

  Timer? _timer;

  /// Multi-subscriber stream of per-second rollups. Both
  /// `FrameDeltaProbeOverlay` (Plan 03-06) and post-walk inspectors can
  /// subscribe simultaneously without losing emissions.
  Stream<FrameDeltaRollup> get rollups => _controller.stream;

  /// Returns the monotonic Stopwatch microsecond reading at "right now".
  /// Pair each call with a later [recordFogUniformPopulation] passing this
  /// returned value. Cheap (no allocation, no syscall on iOS — Stopwatch
  /// reads `mach_absolute_time` directly).
  int recordCameraSnapshot() => _clock.elapsedMicroseconds;

  /// Records the per-frame delta `max(0, now - snapshotMicros)` into the
  /// ring buffer. Negative results clamp at 0 (defence-in-depth — Stopwatch
  /// is monotonic but a probe bug must NEVER crash the paint path).
  ///
  /// When the buffer reaches [kPocFrameDeltaBufferMaxSamples] (240),
  /// the oldest sample is dropped FIFO-style. This bounds memory at
  /// ~2 seconds of 120 Hz history.
  void recordFogUniformPopulation(int snapshotMicros) {
    final now = _clock.elapsedMicroseconds;
    final delta = math.max(0, now - snapshotMicros);
    _buffer.add(delta);
    while (_buffer.length > kPocFrameDeltaBufferMaxSamples) {
      _buffer.removeAt(0);
    }
  }

  /// Test-only seam — appends [micros] directly to the rolling buffer
  /// (clamped at `≥ 0`), bypassing the live Stopwatch read.
  ///
  /// This is the SUPPORTED way for tests to inject deterministic delta
  /// values; using `recordFogUniformPopulation(_clock.elapsedMicroseconds - X)`
  /// adds real-clock jitter (±N µs per call) which makes ±1 µs assertions
  /// race-y. Production code MUST NOT call this method.
  @visibleForTesting
  void debugRecordRawDelta(int micros) {
    final clamped = math.max(0, micros);
    _buffer.add(clamped);
    while (_buffer.length > kPocFrameDeltaBufferMaxSamples) {
      _buffer.removeAt(0);
    }
  }

  /// Schedules the periodic rollup timer. Idempotent — repeated calls do
  /// not stack timers.
  void start() {
    _timer ??= Timer.periodic(_rollupInterval, (_) => _emitRollup());
  }

  /// Cancels the rollup timer. The [rollups] stream stays open until
  /// [dispose].
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Cancels the timer, clears the ring buffer, and closes the rollup
  /// stream. Safe to await; idempotent if already disposed (the
  /// underlying StreamController.close is idempotent).
  Future<void> dispose() async {
    stop();
    _buffer.clear();
    await _controller.close();
  }

  /// Computes one rollup from the current buffer and emits it on both the
  /// stream and the JSONL logger. Idle seconds (empty buffer) skip emission
  /// entirely — overlay and JSONL tooling MUST handle gaps.
  void _emitRollup() {
    if (_buffer.isEmpty) return;
    final sorted = List<int>.from(_buffer)..sort();
    final medianMicros = sorted[sorted.length ~/ 2];
    final p95Index = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    final p95Micros = sorted[p95Index];
    final maxMicros = sorted.last;
    // WALL-CLOCK source — REQUIRED for grep-correlation with SdfRebuildLogger.
    // DO NOT switch to a Stopwatch-derived value (would break the post-walk join).
    final epochSecond = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rollup = FrameDeltaRollup(
      epochSecond: epochSecond,
      sampleCount: _buffer.length,
      medianMicros: medianMicros,
      p95Micros: p95Micros,
      maxMicros: maxMicros,
    );
    _controller.add(rollup);
    _log.info(
      json.encode(<String, Object>{
        'epochSecond': epochSecond,
        'sampleCount': rollup.sampleCount,
        'medianMicros': rollup.medianMicros,
        'p95Micros': rollup.p95Micros,
        'maxMicros': rollup.maxMicros,
        'medianMs': double.parse(rollup.medianMs.toStringAsFixed(3)),
        'p95Ms': double.parse(rollup.p95Ms.toStringAsFixed(3)),
        'maxMs': double.parse(rollup.maxMs.toStringAsFixed(3)),
      }),
    );
    _buffer.clear();
  }
}
