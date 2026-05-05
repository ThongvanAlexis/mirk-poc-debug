// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/infrastructure/location/walk_simulator.dart';

/// Resets the singleton between tests so timer state from one test does not
/// leak into the next. The singleton is process-wide by design (cross-screen
/// AppBar use case), so tests have to drive it deterministically.
void _resetSimulator() {
  final sim = WalkSimulator.instance;
  if (sim.running.value) sim.stop();
  // Reset bearing/speed so subsequent tests start from a known baseline.
  sim.setBearing(0);
  sim.setSpeed(kPocWalkSimulatorDefaultSpeedMps);
}

void main() {
  setUp(_resetSimulator);
  tearDown(_resetSimulator);

  group('WalkSimulator', () {
    test('start emits the starting position immediately on the broadcast stream', () {
      final sim = WalkSimulator.instance;
      final List<Position> emissions = <Position>[];
      final StreamSubscription<Position> sub = sim.stream.listen(emissions.add);
      addTearDown(sub.cancel);

      sim.start(lat: 48.5, lon: 2.65, bearingDeg: 0, speedMps: 1.4);

      // Microtask drain — broadcast controller delivers synchronously.
      return Future<void>.delayed(Duration.zero).then((_) {
        expect(emissions, hasLength(1), reason: 'start() emits the starting fix immediately');
        expect(emissions.first.latitude, closeTo(48.5, 1e-9));
        expect(emissions.first.longitude, closeTo(2.65, 1e-9));
      });
    });

    test('running flips true on start, false on stop', () {
      final sim = WalkSimulator.instance;
      expect(sim.running.value, isFalse);

      sim.start(lat: 48.5, lon: 2.65, bearingDeg: 0, speedMps: 1.0);
      expect(sim.running.value, isTrue);

      sim.stop();
      expect(sim.running.value, isFalse);
    });

    test('bearing 0° (north) advances latitude positively, longitude stable', () {
      fakeAsync((FakeAsync async) {
        final sim = WalkSimulator.instance;
        final List<Position> emissions = <Position>[];
        final StreamSubscription<Position> sub = sim.stream.listen(emissions.add);

        sim.start(lat: 48.5, lon: 2.65, bearingDeg: 0, speedMps: 1.4);
        async.flushMicrotasks();

        // Advance one tick.
        async.elapse(const Duration(milliseconds: kPocWalkSimulatorTickMs));

        expect(emissions.length, greaterThanOrEqualTo(2), reason: 'starting + one tick');
        final Position first = emissions.first;
        final Position second = emissions[1];
        expect(second.latitude, greaterThan(first.latitude), reason: 'north → lat increases');
        expect(second.longitude, closeTo(first.longitude, 1e-12), reason: 'north → lon unchanged');

        // 1.4 m/s × 1 s ÷ kMetersPerDegreeLat ≈ 1.26e-5 deg
        final double expectedDeltaDeg = (1.4 * (kPocWalkSimulatorTickMs / 1000.0)) / kMetersPerDegreeLat;
        expect(second.latitude - first.latitude, closeTo(expectedDeltaDeg, 1e-9));

        sim.stop();
        async.elapse(const Duration(seconds: 1));
        sub.cancel();
      });
    });

    test('bearing 90° (east) advances longitude positively, latitude stable', () {
      fakeAsync((FakeAsync async) {
        final sim = WalkSimulator.instance;
        final List<Position> emissions = <Position>[];
        final StreamSubscription<Position> sub = sim.stream.listen(emissions.add);

        sim.start(lat: 48.5, lon: 2.65, bearingDeg: 90, speedMps: 1.4);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: kPocWalkSimulatorTickMs));

        final Position first = emissions.first;
        final Position second = emissions[1];
        expect(second.longitude, greaterThan(first.longitude), reason: 'east → lon increases');
        expect(second.latitude, closeTo(first.latitude, 1e-12), reason: 'east → lat unchanged');

        sim.stop();
        async.elapse(const Duration(seconds: 1));
        sub.cancel();
      });
    });

    test('stop cancels the timer (no further emissions after stop)', () {
      fakeAsync((FakeAsync async) {
        final sim = WalkSimulator.instance;
        final List<Position> emissions = <Position>[];
        final StreamSubscription<Position> sub = sim.stream.listen(emissions.add);

        sim.start(lat: 48.5, lon: 2.65, bearingDeg: 0, speedMps: 1.4);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: kPocWalkSimulatorTickMs));
        final int countWhileRunning = emissions.length;

        sim.stop();
        async.elapse(const Duration(seconds: 5));
        expect(emissions.length, countWhileRunning, reason: 'no emissions after stop');

        sub.cancel();
      });
    });

    test('setBearing without restart updates the next tick direction', () {
      fakeAsync((FakeAsync async) {
        final sim = WalkSimulator.instance;
        final List<Position> emissions = <Position>[];
        final StreamSubscription<Position> sub = sim.stream.listen(emissions.add);

        sim.start(lat: 48.5, lon: 2.65, bearingDeg: 0, speedMps: 1.4);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: kPocWalkSimulatorTickMs)); // 1 north tick

        sim.setBearing(180); // flip to south
        async.elapse(const Duration(milliseconds: kPocWalkSimulatorTickMs)); // 1 south tick

        // emissions[1] = after 1 north tick (lat increased)
        // emissions[2] = after 1 south tick from emissions[1] (lat back near start)
        expect(emissions.length, greaterThanOrEqualTo(3));
        final double afterNorth = emissions[1].latitude;
        final double afterSouth = emissions[2].latitude;
        expect(afterSouth, lessThan(afterNorth), reason: 'south tick reduces latitude');

        sim.stop();
        async.elapse(const Duration(seconds: 1));
        sub.cancel();
      });
    });

    test('start while already running restarts the timer with new params (no double-fire)', () {
      fakeAsync((FakeAsync async) {
        final sim = WalkSimulator.instance;
        final List<Position> emissions = <Position>[];
        final StreamSubscription<Position> sub = sim.stream.listen(emissions.add);

        sim.start(lat: 48.5, lon: 2.65, bearingDeg: 0, speedMps: 1.4);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: kPocWalkSimulatorTickMs));

        // Restart at a different lat — emits one new "starting" fix.
        final int beforeRestart = emissions.length;
        sim.start(lat: 49.0, lon: 3.0);
        async.flushMicrotasks();
        expect(emissions.length, beforeRestart + 1);
        expect(emissions.last.latitude, closeTo(49.0, 1e-9));
        expect(emissions.last.longitude, closeTo(3.0, 1e-9));

        // One tick later — only ONE additional emission (proves the prior
        // timer was cancelled, not stacked).
        async.elapse(const Duration(milliseconds: kPocWalkSimulatorTickMs));
        expect(emissions.length, beforeRestart + 2);

        sim.stop();
        async.elapse(const Duration(seconds: 1));
        sub.cancel();
      });
    });
  });
}
