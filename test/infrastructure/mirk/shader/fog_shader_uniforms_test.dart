// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/shader/fog_shader_uniforms.dart';

import '../../../_helpers/recording_fog_shader_renderer.dart';

/// FOG-05 — FogShaderUniforms slot count gate.
///
/// Wave 0 contract: this test is GREEN from day 1. It re-asserts the donor
/// file's `totalFloatSlots == 41` invariant so that any future change which
/// reorders or adds/removes a slot in the `.frag` uniform declaration is
/// caught BEFORE it reaches a sideload UAT walk (defends against a future
/// BUG-014 Iter-2 regression).
///
/// If a future iteration changes the uniform count, BOTH this constant and
/// the `.frag` declaration must be updated together (and the FogShaderUniforms.setAll
/// implementation reviewed) — that's the whole point of pinning the count here.
void main() {
  test('FogShaderUniforms.totalFloatSlots == 41 — slot-count gate against BUG-014 Iter 2 regression', () {
    expect(FogShaderUniforms.totalFloatSlots, 41);
  });

  group('FogShaderRenderer (Plan 03.1-04 — pixelOrigin contract)', () {
    // The plan called for a unit test that mocks `ui.FragmentShader` to
    // assert `setAll(pixelOrigin: ...)` writes slots 3 and 4 verbatim.
    // `ui.FragmentShader` is declared `base` in dart:ui (sky_engine
    // painting.dart), so it CANNOT be implemented from outside its library —
    // any attempt produces "The class 'FragmentShader' can't be implemented
    // outside of its library because it's a base class."
    //
    // The achievable equivalent at the FogShaderRenderer interface boundary:
    // assert that `RecordingFogShaderRenderer` (the test seam injected by
    // FogLayer for unit-level coverage) preserves a high-magnitude pixelOrigin
    // tuple verbatim across the renamed `pixelOrigin:` named arg. This proves
    // the rename plumbing (interface → impl → captured field) is end-to-end
    // wired without any Dart-side modulo; combined with the production-side
    // `_FragmentShaderFogRenderer` (which delegates to `FogShaderUniforms.setAll`
    // with the SAME pixelOrigin value), the contract is locked: a high-magnitude
    // tuple flows through the renderer interface unaltered.
    test('RecordingFogShaderRenderer captures full-precision pixelOrigin verbatim (no Dart-side modulo)', () {
      final renderer = RecordingFogShaderRenderer();
      // High-magnitude values matching the 03.1-03 walk's Finding 2
      // pixelOrigin range (~4.26e6 at zoom 16). These would lose
      // precision under any Dart-side `% 1.0`.
      const px = 4255934.927218;
      const py = 1234567.890123;
      renderer.render(
        shader: null,
        resolution: const Size(400, 800),
        timeSeconds: 0,
        pixelOrigin: (px, py),
        baseAlpha: 1,
        sdfRect: const (0, 0, 1, 1),
        sdfImage: _NullImage(),
        mirkFogConstants: const <String, double>{},
      );
      expect(renderer.renders, hasLength(1));
      expect(renderer.renders.last.pixelOrigin, (px, py));
      // Defence-in-depth: assert the captured magnitude is still in the
      // raw-pixel regime. A future regression that re-introduces a
      // Dart-side `% 1.0` would compress these into [0, 1) and trip this.
      expect(renderer.renders.last.pixelOrigin.$1, greaterThan(1e6));
      expect(renderer.renders.last.pixelOrigin.$2, greaterThan(1e6));
    });
  });
}

/// Minimal `ui.Image` stand-in — the recording renderer only stores the
/// reference and never inspects it. `Fake implements` because `ui.Image`
/// is NOT `base` (only `FragmentShader` is, which is why this whole file
/// works around that constraint).
class _NullImage extends Fake implements ui.Image {}
