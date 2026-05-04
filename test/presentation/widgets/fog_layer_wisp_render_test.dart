// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';

/// WISP-04 — RED test scaffold for FogLayer wisp paint sequence + projection.
///
/// Plan 04-01 (Wave 0) ships these tests RED-via-skip against the
/// CURRENT [FogLayer] constructor (which does NOT yet accept a
/// [WispParticleSystem] field). Plan 04-04 extends the FogLayer
/// constructor to thread a WispParticleSystem through to
/// `_FogPainter._renderWisps`, which is called between the
/// `canvas.drawRect(...shader)` line and `canvas.restore()`.
///
/// Wave 0 (this plan) ships them with `skip: 'Plan 04-04 implements'`
/// so the suite stays green; Plan 04-04 removes the skip + lands the
/// production integration; the assertions below must pass UNCHANGED.
///
/// Why skip instead of assert-fail:
///
/// The test's GREEN behaviour requires the FogLayer constructor to
/// accept a `wispParticleSystem` parameter that does not exist yet —
/// any test body referencing it would not compile. Writing the test
/// against the future API and skip-gating it preserves the RED →
/// GREEN flip path (Plan 04-04 unsets the skip + flips test colour).
/// Same Wave-0-skip discipline as the existing FOG-09
/// `fog_pan_translation_test.dart` `skip: true` row.
void main() {
  group('FogLayer wisp render (WISP-04)', () {
    test(
      '_FogPainter.paint() calls _renderWisps after canvas.drawRect(...shader) and before canvas.restore() — WISP-04 paint sequence',
      () {
        // GREEN-flip contract (Plan 04-04):
        //
        //   1. Mount a FogLayer with a real WispParticleSystem injected
        //      via the new `wispParticleSystem` constructor parameter.
        //   2. Use a painter test seam (e.g. `_FogPainter.debugRenderTrace`
        //      list of strings) populated with marker entries on each
        //      sub-step: 'fog_drawRect', 'render_wisps', 'restore'.
        //   3. Assert order: ['fog_drawRect', 'render_wisps', 'restore'].
        //
        // Today (Wave 0): we just construct the WispParticleSystem to
        // confirm it compiles + the constructor signature lines up with
        // CONTEXT.md preview. The stub's `wisps` getter throws
        // UnimplementedError under Plan 04-03; this scaffold doesn't
        // exercise that path yet.
        final system = WispParticleSystem();
        expect(system, isNotNull);
      },
      skip: 'Plan 04-04 implements FogLayer constructor extension + paint sequence assertion',
    );

    test(
      'wisp drawCircle calls happen at MapCamera.latLngToScreenPoint(LatLng) for each wisp position — WISP-04 projection path',
      () {
        // GREEN-flip contract (Plan 04-04):
        //
        //   1. Spawn N wisps at known LatLngs.
        //   2. Mount a FogLayer with the system; pump one frame.
        //   3. Use a recording Canvas test seam to capture every
        //      `drawCircle(center, radius, paint)` call.
        //   4. Assert each `center` equals `MapCamera.latLngToScreenPoint(
        //      wisp.position)` from the painter's MapCamera snapshot
        //      (FOG-07 single-snapshot — no fresh `MapCamera.of(context)`
        //      reads inside the painter).
        //
        // The point is to defend WISP-01: wisps live in LatLng; the
        // projection happens at paint time using the SAME MapCamera the
        // fog uses; a regression to screen-pixel-space wisps would
        // produce drawCircle centres that DON'T match the projected
        // LatLng → screen Offset for any non-default zoom.
        final system = WispParticleSystem();
        expect(system, isNotNull);
      },
      skip: 'Plan 04-04 implements FogLayer constructor extension + projection-path assertion',
    );
  });
}
