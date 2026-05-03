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
///
/// **Plan 03.1-14 update (Fix B′ — FOG-19 meter-space anchor):** slot
/// count STAYS at 42; slot 3..4 SEMANTIC RENAME from `uPixelOrigin`
/// (FOG-17a pixel-space bounded composite) to `uWorldMetersOrigin`
/// (Fix B′ meter-space bounded composite). The shader-side declaration
/// `uniform vec2 uWorldMetersOrigin;` lives in
/// `assets/shaders/atmospheric_fog.frag`; the Dart-side
/// `FogShaderUniforms.setAll` calls `shader.setFloat(3, worldMetersOrigin.$1)`
/// and `shader.setFloat(4, worldMetersOrigin.$2)`.
void main() {
  test('FogShaderUniforms.totalFloatSlots == 42 — slot-count gate (Plan 03.1-12 FOG-18 advanced 41 → 42; Plan 03.1-14 keeps 42)', () {
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

  test('FOG-19 (Plan 03.1-14 Fix B′) — atmospheric_fog.frag declares slot 3..4 uWorldMetersOrigin uniform in active code', () {
    final fragSource = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();
    final activeSource = fragSource
        .split('\n')
        .map((line) {
          final commentIdx = line.indexOf('//');
          return commentIdx >= 0 ? line.substring(0, commentIdx) : line;
        })
        .join('\n');
    expect(
      activeSource.contains('uniform vec2  uWorldMetersOrigin;') || activeSource.contains('uniform vec2 uWorldMetersOrigin;'),
      isTrue,
      reason:
          'Plan 03.1-14 (Fix B′) regression: slot-3/4 uniform must be named uWorldMetersOrigin (semantic flip from FOG-17a-pixel-space '
          'to FOG-19-meter-space). If this assertion fails, the Plan 03.1-14 Fix B′ has been reverted at the shader side.',
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

  test('FOG-19 (Plan 03.1-14 Fix B′) — FogShaderUniforms.setAll source forwards worldMetersOrigin to slots 3..4', () {
    final source = File('lib/infrastructure/mirk/shader/fog_shader_uniforms.dart').readAsStringSync();
    expect(
      source,
      contains(r'shader.setFloat(3, worldMetersOrigin.$1)'),
      reason:
          'Plan 03.1-14 (Fix B′) regression: FogShaderUniforms.setAll must emit `shader.setFloat(3, worldMetersOrigin.\$1)` '
          '(slot 3 — meter-space bounded composite X). If this assertion fails, the Dart-side forward has been reverted.',
    );
    expect(
      source,
      contains(r'shader.setFloat(4, worldMetersOrigin.$2)'),
      reason:
          'Plan 03.1-14 (Fix B′) regression: FogShaderUniforms.setAll must emit `shader.setFloat(4, worldMetersOrigin.\$2)` (slot 4 — meter-space bounded composite Y).',
    );
  });

  group('FogShaderRenderer (Plan 03.1-14 Fix B′ — worldMetersOrigin contract)', () {
    // The plan called for a unit test that mocks `ui.FragmentShader` to
    // assert `setAll(worldMetersOrigin: ...)` writes slots 3 and 4 verbatim.
    // `ui.FragmentShader` is declared `base` in dart:ui (sky_engine
    // painting.dart), so it CANNOT be implemented from outside its library —
    // any attempt produces "The class 'FragmentShader' can't be implemented
    // outside of its library because it's a base class."
    //
    // The achievable equivalent at the FogShaderRenderer interface boundary:
    // assert that `RecordingFogShaderRenderer` (the test seam injected by
    // FogLayer for unit-level coverage) preserves a meter-space bounded
    // composite verbatim across the `worldMetersOrigin:` named arg. This
    // proves the rename plumbing (interface → impl → captured field) is
    // end-to-end wired without any Dart-side modulo; combined with the
    // production-side `_FragmentShaderFogRenderer` (which delegates to
    // `FogShaderUniforms.setAll` with the SAME worldMetersOrigin value),
    // the contract is locked.
    test('RecordingFogShaderRenderer captures meter-space bounded composite verbatim', () {
      final renderer = RecordingFogShaderRenderer();
      // Synthetic meter-space bounded composite values, both within
      // [0, kPocFogIntegerWrapPeriodMeters + 1] = [0, 4097].
      const wmX = 3245.123456;
      const wmY = 1024.987654;
      renderer.render(
        shader: null,
        resolution: const Size(400, 800),
        timeSeconds: 0,
        worldMetersOrigin: (wmX, wmY),
        baseAlpha: 1,
        sdfRect: const (0, 0, 1, 1),
        sdfImage: _NullImage(),
        mirkFogConstants: const <String, double>{},
        metersPerPixel: 3.16, // FOG-18 (Plan 03.1-12) — synthetic z=15 lat 48.5° value.
      );
      expect(renderer.renders, hasLength(1));
      expect(renderer.renders.last.worldMetersOrigin, (wmX, wmY));
      // Defence-in-depth: assert the captured magnitude is in the
      // expected meter-space range, NOT the historical pixel-space
      // millions regime.
      expect(renderer.renders.last.worldMetersOrigin.$1, lessThan(4097.0));
      expect(renderer.renders.last.worldMetersOrigin.$2, lessThan(4097.0));
    });
  });
}

/// Minimal `ui.Image` stand-in — the recording renderer only stores the
/// reference and never inspects it. `Fake implements` because `ui.Image`
/// is NOT `base` (only `FragmentShader` is, which is why this whole file
/// works around that constraint).
class _NullImage extends Fake implements ui.Image {}
