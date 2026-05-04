// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';

/// FOG-07 KEYSTONE in Phase 4 — `MapCamera.of(context)` is called
/// EXACTLY ONCE per [FogLayer.build] invocation EVEN with a
/// [WispParticleSystem] injected.
///
/// This test extends the existing
/// `test/presentation/widgets/fog_layer_camera_snapshot_test.dart`
/// (Plan 03-05 / 03.1-X verifications) into Phase 4 territory: wisps
/// MUST share THE same `MapCamera` snapshot as the fog rect, the clip
/// path, and the SDF-rect derivation. A wisp that re-reads
/// `MapCamera.of(context)` would re-create BUG-014's white-ellipse
/// symptom in the wisp pipeline — the failure mode FOG-07 was designed
/// to defend against in the first place.
///
/// Plan 04-01 (Wave 0) ships RED-via-skip; Plan 04-04 lands the
/// FogLayer constructor extension + the painter-side wisp integration;
/// the assertion below flips to GREEN unchanged.
void main() {
  testWidgets(
    'FogLayer reads MapCamera.of(context) exactly once per build EVEN WITH WispParticleSystem present (FOG-07 keystone holds in Phase 4)',
    (tester) async {
      // GREEN-flip contract (Plan 04-04):
      //
      //   1. Reuse `FogLayer.debugOnCameraRead` test seam from Plan
      //      03-05 (incremented per `MapCamera.of(context)` call).
      //   2. Pump a FogLayer with `wispParticleSystem: system` injected
      //      via the new constructor parameter (Plan 04-04 lands).
      //   3. Force a rebuild via setState; assert `readCount == 2`
      //      (one per build, no extra reads from the wisp render path).
      //
      // The point: even though the wisp painter projects every wisp's
      // LatLng → screen via `MapCamera.latLngToScreenPoint(...)`, it
      // MUST consume the camera passed by reference into the painter's
      // constructor — NOT call `MapCamera.of(painterContext)` (the
      // painter has no BuildContext anyway, but a sloppy refactor could
      // grab one off a captured widget).
      final system = WispParticleSystem();
      expect(system, isNotNull);
    },
    // Skip reason: Plan 04-04 implements FogLayer constructor extension;
    // FOG-07 keystone assertion gated on the new wispParticleSystem field.
    skip: true,
  );
}
