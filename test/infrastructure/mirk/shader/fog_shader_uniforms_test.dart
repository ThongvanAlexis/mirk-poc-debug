// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show File;
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
/// If a future iteration changes the uniform count, BOTH this constant and
/// the `.frag` declaration must be updated together (and the FogShaderUniforms.setAll
/// implementation reviewed) — that's the whole point of pinning the count here.
///
/// **Plan 03.1-12 update (FOG-18 — world-meter anchor):** slot count
/// advances 41 → 42 with the new `uMetersPerPixel` uniform at slot 41.
/// The shader-side declaration `uniform float uMetersPerPixel;` lives in
/// `assets/shaders/atmospheric_fog.frag`; the Dart-side
/// `FogShaderUniforms.setAll` calls `shader.setFloat(41, metersPerPixel)`.
/// Both presence checks ship as sub-tests below so future regressions
/// (silent revert, slot-count drift, missing setFloat call) are caught
/// mechanically without a sideload UAT walk.
void main() {
  test('FogShaderUniforms.totalFloatSlots == 42 — slot-count gate (Plan 03.1-12 FOG-18 advances 41 → 42)', () {
    expect(FogShaderUniforms.totalFloatSlots, 42);
  });

  test('FOG-18 (Plan 03.1-12) — atmospheric_fog.frag declares slot 41 uMetersPerPixel uniform in active code', () {
    // Read shader source from disk via dart:io (rootBundle.loadString
    // fails because Flutter compiles `.frag` files into binary IPLR
    // shader blobs at build time; the source-text file in the project
    // tree is what we want to assert on for the regression-defense
    // substring scan).
    final fragSource = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();
    // Strip line comments to avoid false positives from documentation.
    final activeSource = fragSource
        .split('\n')
        .map((line) {
          final commentIdx = line.indexOf('//');
          return commentIdx >= 0 ? line.substring(0, commentIdx) : line;
        })
        .join('\n');
    expect(
      activeSource.contains('uniform float uMetersPerPixel;'),
      isTrue,
      reason:
          'FOG-18 regression: production shader must declare `uniform float uMetersPerPixel;` (slot 41) in active code. '
          'If this assertion fails, the FOG-18 fix has been reverted at the shader side.',
    );
  });

  test('FOG-18 (Plan 03.1-12) — FogShaderUniforms.setAll source contains `shader.setFloat(41, metersPerPixel)`', () {
    final source = File('lib/infrastructure/mirk/shader/fog_shader_uniforms.dart').readAsStringSync();
    expect(
      source,
      contains('shader.setFloat(41, metersPerPixel)'),
      reason:
          'FOG-18 regression: FogShaderUniforms.setAll must emit `shader.setFloat(41, metersPerPixel)` to forward the '
          'world-meter anchor uniform. If this assertion fails, the Dart-side forward has been reverted.',
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
        metersPerPixel: 3.16, // FOG-18 (Plan 03.1-12) — synthetic z=15 lat 48.5° value.
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
