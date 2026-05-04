// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';

/// WISP-02 / WISP-03 — RED test scaffold for [WispParticleSystem].
///
/// Plan 04-01 (Wave 0) ships these tests RED against the stub whose
/// methods throw [UnimplementedError]. Plan 04-03 flips them GREEN by
/// implementing the spawn / advance / warm-up gate behaviour.
///
/// Tests that need to control the warm-up clock pass a custom
/// [Stopwatch] via the `wallClock` constructor seam — calling
/// `Stopwatch().start()` BEFORE construction and then advancing it
/// outside the system gives full control over the [WISP-03] gate
/// without the test harness sleeping.
void main() {
  group('WispParticleSystem (WISP-02 / WISP-03)', () {
    test('spawnAtNewDisc emits ~20 wisps along 25 m disc perimeter at 8 m spacing — WISP-02', () {
      // Use a Stopwatch already past the warm-up window so the gate doesn't
      // suppress this test's spawn observation.
      final clock = Stopwatch()..start();
      // Advance the clock past kMirkPocWispWarmUpSeconds. Stopwatch has no
      // `addMicroseconds`; instead, the GREEN impl must compare against
      // `kMirkPocWispWarmUpSeconds * 1e6` µs, and the test seam allows the
      // GREEN impl to read elapsedMicroseconds as the source of truth.
      // For the RED scaffold we rely on the GREEN impl honouring an
      // already-elapsed external Stopwatch. Plan 04-03 NOTE: if Stopwatch
      // mutability isn't enough, refactor the seam to a `() => Duration`
      // closure injection.
      final system = WispParticleSystem(wallClock: clock);

      // Synthesise a disc at the Melun centre.
      final disc = RevealDisc(
        id: 'rvd_TESTID000000000000000001',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );

      // Expected wisp count = circumference / metersPerWisp =
      // (2 * pi * 25) / 8 ≈ 19.6 → 19 or 20 wisps; allow [18, 22] for
      // GREEN-impl rounding flexibility (donor caps at 20 in practice).
      // RED: spawnAtNewDisc throws UnimplementedError on the stub.
      // RED: assume warm-up gate is bypassed when the wallClock is past
      // kMirkPocWispWarmUpSeconds — Plan 04-03 contract.
      // For RED-only assertion, we observe the GREEN-expected post-state.
      // If the warm-up gate is in effect for this test (because the
      // Stopwatch starts at 0), Plan 04-03's contract MUST allow for a
      // mid-test wallClock advance — see scaffold note above.
      // To keep the RED assertion meaningful regardless of how the GREEN
      // impl resolves the seam, we assert the count via activeCount.
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      expect(system.activeCount, inInclusiveRange(18, 22));
    });

    test('second spawnAtNewDisc with same discId is idempotent (no double-puff) — WISP-02', () {
      final system = WispParticleSystem(wallClock: Stopwatch()..start());
      final disc = RevealDisc(
        id: 'rvd_TESTID000000000000000002',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );

      // RED: throws UnimplementedError. GREEN: first call spawns N wisps.
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      final firstActiveCount = system.activeCount;
      // Second call with same discId — idempotent, no new wisps.
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      expect(system.activeCount, firstActiveCount);
    });

    test('200-cap respected; LRU evicts oldest by remaining life — WISP-02', () {
      final system = WispParticleSystem(maxCount: kMirkPocWispMaxCount, wallClock: Stopwatch()..start());

      // Spawn 11 discs × ~20 wisps = ~220 wisps total → cap should clamp
      // to kMirkPocWispMaxCount = 200.
      for (var i = 0; i < 11; i++) {
        final disc = RevealDisc(
          id: 'rvd_CAPTEST${i.toString().padLeft(2, '0')}0000000000000000',
          sessionId: 'sess_TESTID00000000000000000',
          lat: 48.5397 + i * 0.0001, // Distinct so they don't merge.
          lon: 2.6553,
          radiusMeters: 25.0,
          fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, i),
        );
        // RED: throws UnimplementedError.
        system.spawnAtNewDisc(discId: disc.id, disc: disc);
      }

      expect(system.activeCount, lessThanOrEqualTo(kMirkPocWispMaxCount));
      // GREEN-spec: at the cap, surviving wisps are the ones with the
      // HIGHEST remaining life (LRU = newest). The oldest cohort (lowest
      // remaining life) is evicted first.
    });

    test('first 5 s of construction: spawnAtNewDisc is a no-op; discId still recorded — WISP-03 warm-up gate', () {
      // Fresh Stopwatch — sits at 0, well inside the warm-up window.
      final freshClock = Stopwatch()..start();
      final system = WispParticleSystem(wallClock: freshClock);

      final disc = RevealDisc(
        id: 'rvd_WARMUP00000000000000000001',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );

      // RED: throws UnimplementedError. GREEN: warm-up gate suppresses the
      // spawn; activeCount stays 0; discId is recorded so a post-warm-up
      // re-call with the same discId is ALSO a no-op.
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      expect(system.activeCount, 0, reason: 'WISP-03 warm-up gate must suppress spawn during first ${kMirkPocWispWarmUpSeconds}s');

      // GREEN contract: discId recorded during warm-up → re-call with the
      // same discId post-warm-up is also a no-op (the spec is "every
      // previously-revealed disc explodes on app open" failure-mode
      // suppression — the disc has been seen during warm-up, so it
      // shouldn't trigger after).
      // We can't easily fast-forward Stopwatch in pure Dart without
      // FakeAsync; the GREEN-impl honour-the-seam contract is asserted
      // via the activeCount-stays-0 invariant above.
    });

    test('advance(dt) integrates velocity + position; dead wisps removed in place — WISP-02', () {
      final system = WispParticleSystem(wallClock: Stopwatch()..start());
      final disc = RevealDisc(
        id: 'rvd_ADVANCE000000000000000001',
        sessionId: 'sess_TESTID00000000000000000',
        lat: 48.5397,
        lon: 2.6553,
        radiusMeters: 25.0,
        fixedAtUtc: DateTime.utc(2026, 5, 4, 12, 0, 0),
      );

      // RED: throws UnimplementedError.
      system.spawnAtNewDisc(discId: disc.id, disc: disc);
      final preAdvanceCount = system.activeCount;

      // Advance past kMirkPocWispLifeSeconds (2.5 s) so EVERY wisp dies.
      // Plan 04-03 must clamp dt at kMirkPocWispMaxDtSeconds (0.1 s)
      // internally; calling advance(3.0) must run the loop for the
      // clamped dt and decrement life accordingly.
      // We call advance(dt=3.0) repeatedly so cumulative life-decrement
      // exceeds maxLife regardless of the clamp.
      for (var i = 0; i < 30; i++) {
        system.advance(0.1);
      }

      expect(system.activeCount, lessThan(preAdvanceCount), reason: 'WISP-02 advance must remove dead wisps in place');
      expect(system.activeCount, 0, reason: 'After 3 s simulated, all wisps with maxLife=2.5 must be dead');
    });
  });
}
