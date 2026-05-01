// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';

/// FOG-08 — FrameDeltaProbe rollup correctness + monotonic guard.
///
/// Wave 0 contract: these tests compile against the Plan 03-01 stub (which
/// throws on recordCameraSnapshot/recordFogUniformPopulation/start) and
/// report RED until Plan 03-04 ships the ring buffer + rollup timer.
///
/// The "synthetic-samples" test seam (driving deltas without going through
/// real Stopwatch microsecond reads) is specified in Plan 03-04. This file
/// pins the contract; Plan 03-04 will add a `@visibleForTesting` constructor
/// or static factory that lets tests inject pre-computed samples.
void main() {
  group('FrameDeltaProbe (FOG-08)', () {
    test('emitRollup computes correct median/p95/max from in-buffer deltas', () async {
      final probe = FrameDeltaProbe();
      probe.start();
      // Plan 03-04 will expose a seam to push synthetic samples; Wave 0
      // exercises the start() call which currently throws.
      final rollup = await probe.rollups.first.timeout(const Duration(seconds: 2));
      expect(rollup.medianMicros, isPositive);
      expect(rollup.p95Micros, greaterThanOrEqualTo(rollup.medianMicros));
      expect(rollup.maxMicros, greaterThanOrEqualTo(rollup.p95Micros));
    });

    test('rejects non-monotonic timestamps (defence-in-depth — Stopwatch is monotonic but assert anyway)', () {
      final probe = FrameDeltaProbe();
      // If Plan 03-04 implements `recordFogUniformPopulation(int cameraSnapshotMicros)`
      // and computes (paint - snapshot), passing a snapshot value GREATER than
      // the current Stopwatch reading should NOT yield a negative delta in
      // the rollup. Plan 03-04 implementation MUST clamp delta at 0 (or
      // throw assertion in debug); both behaviours satisfy this contract.
      expect(() => probe.recordFogUniformPopulation(_farFutureMicros), returnsNormally);
    });
  });
}

/// A microsecond reading far enough in the future that a real Stopwatch.elapsedMicroseconds
/// can never exceed it during the test run — exercises the monotonic guard.
const int _farFutureMicros = 1 << 50;
