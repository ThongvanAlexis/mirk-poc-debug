// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';

/// WISP-02 / WISP-03 — Plan 04-03 GREEN tests for [WispParticleSystem].
///
/// Plan 04-01 (Wave 0) shipped these tests RED against UnimplementedError-
/// throwing stubs. Plan 04-03 (this file) flips them GREEN by implementing
/// the spawn / advance / warm-up gate behaviour AND extends the suite with
/// the [WispParticleSystem.advanceFromWallClock] dt-clamp scenario (the
/// painter contract for Plan 04-04).
///
/// Tests that need to control the warm-up clock pass a [_FakeStopwatch]
/// via the `wallClock` constructor seam — bypasses real-time `await`s.
/// Suite runs in < 1 second total.
///
/// _FakeStopwatch is the ONLY noSuchMethod use in the plan; production code
/// uses real `Stopwatch` discipline. The fake exists so the suite can
/// assert on the WISP-03 warm-up gate AND the Plan 04-04 advanceFromWallClock
/// dt-clamp without `Future<void>.delayed(Duration(seconds: 5))`.
void main() {
  group('WispParticleSystem (WISP-02 / WISP-03)', () {
    test('spawnAtNewDisc emits ~20 wisps along 25 m disc perimeter at 8 m spacing — WISP-02', () {
      // _FakeStopwatch already past warm-up so the gate doesn't suppress.
      final clock = _FakeStopwatch(initialMs: 6000);
      final system = WispParticleSystem(wallClock: clock);

      final disc = RevealDisc(
        id: 'rvd_TESTID000000000000000001',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );

      // Expected wisp count = circumference / metersPerWisp =
      // (2 * pi * 25) / 8 ≈ 19.6 → 20 wisps; allow [18, 22] for impl
      // rounding flexibility.
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      expect(system.activeCount, inInclusiveRange(18, 22));

      // Perimeter span check — extract latitudes; min < centre < max
      // proves the wisps are distributed AROUND the disc centre rather
      // than collapsed onto one point.
      final latitudes = system.wisps.map((w) => w.position.latitude).toList();
      final latMin = latitudes.reduce((a, b) => a < b ? a : b);
      final latMax = latitudes.reduce((a, b) => a > b ? a : b);
      const epsilonDeg = 1e-6;
      expect(latMax, greaterThan(48.5397 + epsilonDeg), reason: 'Some wisps must spawn NORTH of the disc centre');
      expect(latMin, lessThan(48.5397 - epsilonDeg), reason: 'Some wisps must spawn SOUTH of the disc centre');
    });

    test('second spawnAtNewDisc with same discId is idempotent (no double-puff) — WISP-02', () {
      final system = WispParticleSystem(wallClock: _FakeStopwatch(initialMs: 6000));
      final disc = RevealDisc(
        id: 'rvd_TESTID000000000000000002',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );

      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      final firstActiveCount = system.activeCount;
      // Second call with same discId — idempotent, no new wisps.
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      expect(system.activeCount, firstActiveCount);
    });

    test('200-cap respected; LRU evicts oldest by remaining life — WISP-02', () {
      // Override maxCount to 5 so we can spawn ~80 wisps and verify only
      // 5 survive. With maxCount=200 we'd need 11 discs to exceed the cap;
      // the LRU semantics are identical at any cap.
      const testMaxCount = 5;
      final system = WispParticleSystem(maxCount: testMaxCount, wallClock: _FakeStopwatch(initialMs: 6000));

      // Spawn 4 distinct discs × ~20 wisps = ~80 wisps total; cap clamps
      // to 5.
      for (var i = 0; i < 4; i++) {
        final disc = RevealDisc(
          id: 'rvd_CAPTEST${i.toString().padLeft(2, '0')}0000000000000000',
          sessionId: 'sess_TESTID00000000000000000',
          lat: 48.5397 + i * 0.0001,
          lon: 2.6553,
          radiusMeters: 25.0,
          fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, i),
        );
        system.spawnAtNewDisc(discId: disc.id, disc: disc);
      }

      expect(system.activeCount, lessThanOrEqualTo(testMaxCount));
      expect(system.activeCount, testMaxCount, reason: 'Exactly maxCount wisps survive after exceeding the cap');

      // LRU semantics: surviving wisps are the YOUNGEST (highest remaining
      // life). All wisps spawned in the same advance step have the same
      // initial life = kMirkPocWispLifeSeconds, but the eviction sort by
      // life descending always keeps the freshest cohort.
      final lives = system.wisps.map((w) => w.life).toList();
      expect(lives.every((l) => l == kMirkPocWispLifeSeconds), isTrue, reason: 'All survivors are freshly-spawned (no advance() call between spawns)');
    });

    test('first 5 s of construction: spawnAtNewDisc is a no-op; discId recorded so post-warmup re-call no-ops too — WISP-03', () {
      // _FakeStopwatch sitting at 0 — well inside the warm-up window.
      final clock = _FakeStopwatch();
      final system = WispParticleSystem(wallClock: clock);

      final disc = RevealDisc(
        id: 'rvd_WARMUP00000000000000000001',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );

      // During warmup: spawn is a no-op; discId IS recorded.
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      expect(system.activeCount, 0, reason: 'WISP-03 warm-up gate must suppress spawn during first ${kMirkPocWispWarmUpSeconds}s');

      // Advance _FakeStopwatch past warmup; SAME discId re-call must
      // ALSO no-op (idempotency guard fires before warmup gate, so the
      // pre-recorded discId blocks the re-call).
      clock.advance(6000);
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      expect(system.activeCount, 0, reason: 'discId recorded during warmup blocks the post-warmup re-call (idempotency)');

      // Different discId post-warmup: spawns normally.
      final disc2 = RevealDisc(
        id: 'rvd_WARMUP00000000000000000002',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );
      system.spawnAtNewDisc(discId: disc2.id, disc: disc2);
      expect(system.activeCount, greaterThan(0), reason: 'Fresh discId post-warmup spawns normally');
    });

    test('advance(dt) integrates velocity + position; dead wisps removed in place — WISP-02', () {
      final system = WispParticleSystem(wallClock: _FakeStopwatch(initialMs: 6000));
      final disc = RevealDisc(
        id: 'rvd_ADVANCE000000000000000001',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );

      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      final preAdvanceCount = system.activeCount;
      expect(preAdvanceCount, greaterThan(0));

      // Capture position + velocity of the first wisp BEFORE advance.
      final firstWisp = system.wisps.first;
      final preLat = firstWisp.position.latitude;
      final preLon = firstWisp.position.longitude;
      final velY = firstWisp.velocityMetersPerSecond.dy;

      // Step by 0.1 s — within the kMirkPocWispMaxDtSeconds clamp.
      const dt = 0.1;
      system.advance(dt);

      // Position must change in the velocity direction. velY (m/s) × dt
      // converts to LatLng-degrees via kMetersPerDegreeLat.
      // We don't assert exact equality (curl-noise contributes a small
      // additional displacement); we assert the SIGN of the latitude
      // delta matches the SIGN of velY.
      final postLat = firstWisp.position.latitude;
      final postLon = firstWisp.position.longitude;
      if (velY != 0.0) {
        expect((postLat - preLat).sign, velY.sign, reason: 'Latitude delta sign matches velY sign');
      }
      // Coordinates DEFINITELY changed (sub-millimetre level).
      expect(postLat == preLat && postLon == preLon, isFalse, reason: 'advance(dt) must integrate position');

      // Now advance > total lifespan; all wisps die and are removed.
      for (var i = 0; i < 30; i++) {
        system.advance(0.1);
      }
      expect(system.activeCount, 0, reason: 'After 3 s simulated, all wisps with maxLife=2.5 must be dead');
    });

    test('advanceFromWallClock first call no-op; subsequent calls integrate dt; clamps stale dt to kMirkPocWispMaxDtSeconds — Plan 04-04 painter contract', () {
      final clock = _FakeStopwatch(initialMs: 6000);
      final system = WispParticleSystem(wallClock: clock);
      final disc = RevealDisc(
        id: 'rvd_WALLCLOCK000000000000000',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      expect(system.activeCount, greaterThan(0));

      // Capture pre-call position.
      final firstWisp = system.wisps.first;
      final lat0 = firstWisp.position.latitude;
      final lon0 = firstWisp.position.longitude;

      // First advanceFromWallClock call — records wallclock and returns.
      // No position change.
      clock.advance(100); // 6100 ms
      system.advanceFromWallClock(clock);
      expect(firstWisp.position.latitude, lat0, reason: 'First advanceFromWallClock call is a no-op (records baseline)');
      expect(firstWisp.position.longitude, lon0, reason: 'First advanceFromWallClock call is a no-op (records baseline)');

      // Second call — integrates dt = 100 ms = 0.1 s (within clamp).
      clock.advance(100); // 6200 ms
      system.advanceFromWallClock(clock);
      final lat1 = firstWisp.position.latitude;
      final lon1 = firstWisp.position.longitude;
      expect(lat1 == lat0 && lon1 == lon0, isFalse, reason: 'Second advanceFromWallClock call must integrate position over dt');

      // Capture the per-call delta for the 100 ms step (proxy for "what a
      // single 0.1 s step looks like").
      final delta100Ms = ((lat1 - lat0) * (lat1 - lat0) + (lon1 - lon0) * (lon1 - lon0));

      // Third call — simulate stale stopwatch: jump 5000 ms. The dt
      // clamp must cap the integration step at kMirkPocWispMaxDtSeconds
      // (= 0.1 s) so the delta is ROUGHLY equal to the previous 0.1 s
      // step, NOT 50× larger.
      clock.advance(5000); // 11200 ms — 5 s of stale clock
      system.advanceFromWallClock(clock);
      final lat2 = firstWisp.position.latitude;
      final lon2 = firstWisp.position.longitude;
      final delta5000Ms = ((lat2 - lat1) * (lat2 - lat1) + (lon2 - lon1) * (lon2 - lon1));

      // delta5000Ms ÷ delta100Ms must be < 10 (would be ~2500 if dt was
      // not clamped). curl-noise contributes a small variance per step
      // so we don't assert exact equality, just same order of magnitude.
      expect(
        delta5000Ms,
        lessThan(delta100Ms * 10.0),
        reason: 'Stale 5000 ms wallclock dt must clamp to kMirkPocWispMaxDtSeconds (0.1 s); delta should match prior 100 ms step',
      );
    });
  });
}

/// Test fake exposing controllable [elapsedMilliseconds] and
/// [elapsedMicroseconds]. Avoids `Future.delayed(Duration(seconds: 5))`
/// in the WISP-03 warm-up gate test (would push wisp-system suite to
/// ~30 s total runtime — unacceptable per 04-VALIDATION.md feedback budget).
///
/// Only [elapsedMilliseconds] / [elapsedMicroseconds] / [advance] are
/// implemented; other Stopwatch methods throw via [noSuchMethod] (the
/// production code only reads the elapsed-* getters).
class _FakeStopwatch implements Stopwatch {
  _FakeStopwatch({int initialMs = 0}) : _elapsedMs = initialMs;

  int _elapsedMs;

  /// Advances the fake clock forward by [milliseconds].
  void advance(int milliseconds) => _elapsedMs += milliseconds;

  @override
  int get elapsedMilliseconds => _elapsedMs;

  @override
  int get elapsedMicroseconds => _elapsedMs * 1000;

  // Production code only reads the two elapsed-* getters above; any other
  // method call from the SUT is a test-fake bug — fail loud.
  @override
  noSuchMethod(Invocation invocation) {
    throw UnimplementedError('_FakeStopwatch: ${invocation.memberName} not implemented (production code should not call this method)');
  }
}
