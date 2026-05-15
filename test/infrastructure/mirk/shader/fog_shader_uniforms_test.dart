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
/// file's `totalFloatSlots` invariant so that any future change which
/// reorders or adds/removes a slot in the `.frag` uniform declaration is
/// caught BEFORE it reaches a sideload UAT walk (defends against a future
/// BUG-014 Iter-2 regression).
///
/// FOG-19 (Plan 03.1-14 Task B) bumped totalFloatSlots from 41 to 42 to
/// accommodate the new `uZoomScale` uniform at slot 41 (between
/// `uSdfRectSizeY` at slot 40 and the SDF sampler at sampler index 0).
///
/// If a future iteration changes the uniform count, BOTH this constant and
/// the `.frag` declaration must be updated together (and the FogShaderUniforms.setAll
/// implementation reviewed) — that's the whole point of pinning the count here.
void main() {
  test('FogShaderUniforms.totalFloatSlots == 42 — slot-count gate (FOG-19 / Plan 03.1-14 Task B added uZoomScale at slot 41)', () {
    expect(
      FogShaderUniforms.totalFloatSlots,
      42,
      reason:
          'FOG-19 (Plan 03.1-14 Task B) added `uniform float uZoomScale` at slot 41 to BOTH '
          '`atmospheric_fog.frag` AND `atmospheric_fog_debug_spiral.frag`. The Dart-side total '
          'must match. If this assertion fails to match the shader-side declaration, the '
          'painter and shader will be out of sync and Impeller will fail at uniform-binding time.',
    );
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
        zoomScale: 1.0,
      );
      expect(renderer.renders, hasLength(1));
      expect(renderer.renders.last.pixelOrigin, (px, py));
      // Defence-in-depth: assert the captured magnitude is still in the
      // raw-pixel regime. A future regression that re-introduces a
      // Dart-side `% 1.0` would compress these into [0, 1) and trip this.
      expect(renderer.renders.last.pixelOrigin.$1, greaterThan(1e6));
      expect(renderer.renders.last.pixelOrigin.$2, greaterThan(1e6));
    });

    test('RecordingFogShaderRenderer captures zoomScale verbatim across renderer interface (FOG-19)', () {
      final renderer = RecordingFogShaderRenderer();
      // pow(2, 15 - 13) = 4.0 — synthetic zoom-15 value; matches the
      // expected forwarded value when camera.zoom is 15.
      const zs = 4.0;
      renderer.render(
        shader: null,
        resolution: const Size(400, 800),
        timeSeconds: 0,
        pixelOrigin: (1.0, 1.0),
        baseAlpha: 1,
        sdfRect: const (0, 0, 1, 1),
        sdfImage: _NullImage(),
        mirkFogConstants: const <String, double>{},
        zoomScale: zs,
      );
      expect(renderer.renders, hasLength(1));
      expect(renderer.renders.last.zoomScale, closeTo(zs, 1e-9));
    });
  });
}

/// Minimal `ui.Image` stand-in — the recording renderer only stores the
/// reference and never inspects it. `Fake implements` because `ui.Image`
/// is NOT `base` (only `FragmentShader` is, which is why this whole file
/// works around that constraint).
class _NullImage extends Fake implements ui.Image {}
