// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle.dart';

/// WISP-01 / WISP-02 — RED test scaffold for [WispParticle].
///
/// Plan 04-01 (Wave 0) ships these tests RED against the
/// `lib/infrastructure/mirk/wisp/wisp_particle.dart` stubs whose `isDead`
/// + `age` getters throw [UnimplementedError]. Plan 04-03 flips them
/// GREEN by implementing the behaviour the assertions describe — no test
/// edits required between Wave 0 and Wave 1 (see Plan 03.1-12 Task 1
/// retrospective Rule 3 — "write the assertions as the GREEN behaviour
/// expects, not as throwsA(UnimplementedError)").
void main() {
  group('WispParticle (WISP-01 / WISP-02)', () {
    test('WispParticle stores LatLng position (NOT Offset) — WISP-01 dimensional discipline', () {
      // Constructor + mutable-field reads are real Dart code in the stub.
      // This test passes against the stub already (no UnimplementedError
      // path exercised) — it locks WISP-01's typing contract for the
      // refactor from donor's `Offset position` to LatLng.
      final wisp = WispParticle(
        position: const LatLng(48.5397, 2.6553), // Melun centre.
        velocityMetersPerSecond: const Offset(1.5, 0.0),
        life: 2.5,
        maxLife: 2.5,
      );
      expect(wisp.position, isA<LatLng>());
      expect(wisp.position.latitude, 48.5397);
      expect(wisp.position.longitude, 2.6553);
    });

    test('WispParticle.life decays per advance — isDead at life <= 0 — WISP-02', () {
      final freshWisp = WispParticle(position: const LatLng(48.5397, 2.6553), velocityMetersPerSecond: Offset.zero, life: 2.5, maxLife: 2.5);
      // RED: isDead getter throws UnimplementedError on the stub. GREEN
      // (Plan 04-03): returns life <= 0.0.
      expect(freshWisp.isDead, isFalse);

      final deadWisp = WispParticle(position: const LatLng(48.5397, 2.6553), velocityMetersPerSecond: Offset.zero, life: 0.0, maxLife: 2.5);
      expect(deadWisp.isDead, isTrue);

      final negativeLifeWisp = WispParticle(position: const LatLng(48.5397, 2.6553), velocityMetersPerSecond: Offset.zero, life: -0.1, maxLife: 2.5);
      expect(negativeLifeWisp.isDead, isTrue);
    });

    test('WispParticle.age follows 1 - life/maxLife clamp [0, 1] — WISP-02', () {
      // Just-born wisp: life == maxLife → age == 0.
      final justBorn = WispParticle(position: const LatLng(48.5397, 2.6553), velocityMetersPerSecond: Offset.zero, life: 2.5, maxLife: 2.5);
      // RED: age getter throws UnimplementedError on the stub.
      expect(justBorn.age, closeTo(0.0, 1e-9));

      // Mid-life: life == 1.25, maxLife == 2.5 → age == 0.5.
      final midLife = WispParticle(position: const LatLng(48.5397, 2.6553), velocityMetersPerSecond: Offset.zero, life: 1.25, maxLife: 2.5);
      expect(midLife.age, closeTo(0.5, 1e-9));

      // About to die: life == 0 → age == 1.0.
      final aboutToDie = WispParticle(position: const LatLng(48.5397, 2.6553), velocityMetersPerSecond: Offset.zero, life: 0.0, maxLife: 2.5);
      expect(aboutToDie.age, closeTo(1.0, 1e-9));

      // Beyond death: life negative → age clamped to 1.0 per donor spec.
      final beyondDeath = WispParticle(position: const LatLng(48.5397, 2.6553), velocityMetersPerSecond: Offset.zero, life: -1.0, maxLife: 2.5);
      expect(beyondDeath.age, closeTo(1.0, 1e-9));
    });
  });
}
