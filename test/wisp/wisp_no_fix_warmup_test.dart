// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';

/// Success Criterion #2 — RED test for WISP-03 warm-up gate +
/// no-synthetic-(0, 0) anti-pattern guard.
///
/// Two invariants:
///
///   1. No wisps appear during the first [kMirkPocWispWarmUpSeconds]
///      of MapScreen lifetime (warm-up). The "every previously-revealed
///      disc explodes on app open" failure mode is suppressed by the
///      WispParticleSystem's wall-clock-since-construction gate.
///   2. No wisps appear at synthetic (0, 0) coordinates if a GPS fix
///      has not yet arrived. The Phase 2 GPS subsystem MUST NOT emit
///      a default-zero Position; the WispParticleSystem MUST NOT spawn
///      anything triggered by a (lat = 0, lon = 0) disc that materialised
///      from an uninitialised stream.
///
/// Plan 04-01 (Wave 0) ships these RED-via-skip — the assertion harness
/// requires `MapScreen.fromServices(...)` to accept a
/// [WispParticleSystem] field on [MapScreenServices], which Plan 04-04
/// adds. The skip annotations document the pending Plan 04-04 work; the
/// assertion bodies are self-documenting GREEN-flip contracts.
///
/// Same Wave-0-skip discipline as `fog_layer_wisp_render_test.dart` and
/// `fog_layer_single_camera_snapshot_test.dart`.
void main() {
  group('Wisp no-fix-warmup (Success Criterion #2)', () {
    testWidgets(
      'No wisps appear during first 5 s of MapScreen lifetime (warm-up) — WISP-03 / SC #2',
      (tester) async {
        // GREEN-flip contract (Plan 04-04 + Plan 04-03):
        //
        //   1. Construct a fake `MapScreenServices` with:
        //      - `positionStreamFactory: () => StreamController<Position>().stream` (never emits).
        //      - `wispParticleSystem: WispParticleSystem(wallClock: Stopwatch()..start())`
        //        (NEW field added by Plan 04-04).
        //   2. `await tester.pumpWidget(MaterialApp(home: MapScreen.fromServices(services)));`
        //   3. `await tester.pumpAndSettle(const Duration(seconds: 1));`
        //   4. Assert `services.wispParticleSystem.activeCount == 0` —
        //      the warm-up gate suppressed all spawns even if some
        //      latent disc-replay tried to fire.
        //
        // For Wave 0, we just confirm the system constructs.
        final system = WispParticleSystem(wallClock: Stopwatch()..start());
        expect(system, isNotNull);
      },
      // Skip reason: Plan 04-04 adds `wispParticleSystem` to MapScreenServices;
      // Plan 04-03 implements the warm-up gate this test verifies.
      skip: true,
    );

    testWidgets(
      'No wisps appear at synthetic (0, 0) coordinates if a fix has not yet arrived — SC #2 anti-pattern guard',
      (tester) async {
        // GREEN-flip contract (Plan 04-04 + Plan 04-03):
        //
        //   1. Same fake `MapScreenServices` as above; positionStream
        //      emits NOTHING.
        //   2. `await tester.pumpAndSettle();`
        //   3. Verify `services.discRepository.snapshot()` is empty (no
        //      synthetic 0,0 disc materialised).
        //   4. Verify `services.wispParticleSystem.activeCount == 0`.
        //
        // The assertion defends Phase 2's GPS subsystem AND Plan 04-03's
        // warm-up gate AND Plan 04-04's wiring discipline simultaneously.
        // A regression in any of those three layers would surface as
        // wisps spawning at (lat=0, lon=0) — visually catastrophic.
        final system = WispParticleSystem(wallClock: Stopwatch()..start());
        expect(system, isNotNull);
      },
      // Skip reason: Plan 04-04 adds `wispParticleSystem` to MapScreenServices;
      // the (0,0)-guard chains across MapScreen subscription wiring + Plan
      // 04-03 warm-up gate.
      skip: true,
    );
  });
}
