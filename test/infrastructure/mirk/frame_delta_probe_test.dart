// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';

/// FOG-08 — FrameDeltaProbe rollup correctness + dual-clock discipline.
///
/// All tests drive synthetic samples via the `debugRecordRawDelta(micros)`
/// `@visibleForTesting` seam — pushing micros directly to the ring buffer,
/// bypassing the live Stopwatch read. Driving deltas via the production
/// `recordFogUniformPopulation(t0 - syntheticDelta)` path adds real-clock
/// jitter (±N µs per call) which makes ±1 µs assertions race-y.
///
/// The production methods (`recordCameraSnapshot` / `recordFogUniformPopulation`)
/// stay UNTOUCHED — they read the live Stopwatch on every call.
void main() {
  group('FrameDeltaProbe (FOG-08)', () {
    test('emitRollup computes correct median/p95/max from injected deltas', () async {
      final probe = FrameDeltaProbe(rollupInterval: const Duration(milliseconds: 100));
      addTearDown(() async => probe.dispose());
      for (var i = 1; i <= 10; i++) {
        probe.debugRecordRawDelta(i * 1000); // 1ms, 2ms, ..., 10ms
      }
      probe.start();
      final rollup = await probe.rollups.first.timeout(const Duration(seconds: 1));
      expect(rollup.sampleCount, 10);
      // sorted indices: [1000, 2000, ..., 10000]; sorted[10 ~/ 2] = sorted[5] = 6000.
      expect(rollup.medianMicros, 6000);
      // sorted[(10*0.95).floor()] = sorted[9] = 10000.
      expect(rollup.p95Micros, 10000);
      expect(rollup.maxMicros, 10000);
    });

    test('idle second emits nothing (empty buffer skips rollup)', () async {
      final probe = FrameDeltaProbe(rollupInterval: const Duration(milliseconds: 100));
      addTearDown(() async => probe.dispose());
      var emissionCount = 0;
      final subscription = probe.rollups.listen((_) => emissionCount++);
      addTearDown(subscription.cancel);
      probe.start();
      // Wait 250 ms (>2× rollupInterval) without injecting anything.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(emissionCount, 0);
    });

    test('non-monotonic input clamps at 0 (production path, no throw)', () async {
      final probe = FrameDeltaProbe(rollupInterval: const Duration(milliseconds: 100));
      addTearDown(() async => probe.dispose());
      // Real production-method call: a snapshotMicros far in the future.
      // The implementation MUST clamp the resulting delta at 0, not throw.
      expect(() => probe.recordFogUniformPopulation(_farFutureMicros), returnsNormally);
      // Make sure the buffer is non-empty so a rollup actually fires.
      probe.debugRecordRawDelta(5000);
      probe.start();
      final rollup = await probe.rollups.first.timeout(const Duration(seconds: 1));
      // Sorted buffer is [0, 5000]; median = sorted[2 ~/ 2] = sorted[1] = 5000.
      expect(rollup.medianMicros, greaterThanOrEqualTo(0));
      expect(rollup.maxMicros, 5000);
    });

    test('JSONL line via Logger contains all 8 keys', () async {
      // Capture the logger output. Logger.root must allow ALL levels for tests.
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previousLevel);

      final captured = <String>[];
      final logSubscription = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.frame_delta').listen((r) => captured.add(r.message));
      addTearDown(logSubscription.cancel);

      final probe = FrameDeltaProbe(rollupInterval: const Duration(milliseconds: 100));
      addTearDown(() async => probe.dispose());

      probe.debugRecordRawDelta(1000);
      probe.debugRecordRawDelta(2000);
      probe.start();

      // Wait for the rollup stream to fire — that guarantees the logger was called.
      await probe.rollups.first.timeout(const Duration(seconds: 1));

      expect(captured, isNotEmpty);
      final decoded = json.decode(captured.first) as Map<String, Object?>;
      expect(decoded.keys, containsAll(<String>['epochSecond', 'sampleCount', 'medianMicros', 'p95Micros', 'maxMicros', 'medianMs', 'p95Ms', 'maxMs']));
      expect(decoded['sampleCount'], 2);
    });

    test('buffer caps at kPocFrameDeltaBufferMaxSamples (240) — oldest dropped FIFO', () async {
      final probe = FrameDeltaProbe(rollupInterval: const Duration(milliseconds: 100));
      addTearDown(() async => probe.dispose());
      // Inject 300 samples; only the last 240 should remain.
      for (var i = 0; i < 300; i++) {
        probe.debugRecordRawDelta(1000 + i);
      }
      probe.start();
      final rollup = await probe.rollups.first.timeout(const Duration(seconds: 1));
      expect(rollup.sampleCount, 240);
      // Oldest 60 (1000..1059) were dropped — max should be 1299 (= 1000 + 299).
      expect(rollup.maxMicros, 1299);
    });

    test('dispose() closes the stream', () async {
      final probe = FrameDeltaProbe(rollupInterval: const Duration(milliseconds: 100));
      // Capture the stream BEFORE dispose so the broadcast subscription latches before close.
      final streamFuture = expectLater(probe.rollups, emitsDone);
      await probe.dispose();
      await streamFuture;
    });

    test('wall-clock epochSecond ≈ DateTime.now() (dual-clock invariant)', () async {
      final probe = FrameDeltaProbe(rollupInterval: const Duration(milliseconds: 100));
      addTearDown(() async => probe.dispose());
      probe.debugRecordRawDelta(5000);
      probe.start();
      final rollup = await probe.rollups.first.timeout(const Duration(seconds: 1));
      final wallClockNow = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Defends against an executor accidentally switching the rollup tag to a
      // Stopwatch-derived value (which would be tiny, e.g. 0–2 seconds since
      // probe construction, not 1.7 billion since epoch). Tolerance ±1 s.
      expect((wallClockNow - rollup.epochSecond).abs(), lessThanOrEqualTo(1));
      // And sanity: a Stopwatch.elapsedMicroseconds ~/ 1_000_000 would be tiny
      // (we just constructed the probe). Asserting the magnitude pins the
      // dual-clock invariant — anyone "simplifying" by reading the Stopwatch
      // here would fail this assertion.
      expect(rollup.epochSecond, greaterThan(1_700_000_000));
    });
  });
}

/// A microsecond reading far enough in the future that a real
/// Stopwatch.elapsedMicroseconds can never exceed it during the test run —
/// exercises the monotonic guard in `recordFogUniformPopulation`.
const int _farFutureMicros = 1 << 50;
