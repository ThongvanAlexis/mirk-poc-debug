// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';

/// FOG-14b (Plan 03.1-07 Branch B-3) — tile-period-aware fract-period
/// engineering invariant.
///
/// Companion to FOG-14a. Where FOG-14a tests the BEHAVIOURAL property
/// (wrap frequency aligned with noise-tile period under a synthetic
/// trajectory), FOG-14b tests the STRUCTURAL property: the production
/// fragment shader's `noiseUv` line uses the tile-period divisor, not
/// the viewport divisor. This is the engineering invariant the FOG-15
/// fix delivers; it must not regress at the source level.
///
/// ## Why a static-source assertion?
///
/// The B-3 fix is a single-line shader edit. Asserting on the shader
/// source content is the cheapest, most direct way to guard against
/// silent reverts (e.g., a future PR that "simplifies" the
/// `tilePeriodPixels` computation back to `uResolution`). Mirrors the
/// project's LOC-03 / BOOT-02 static-source CI-gate pattern: when the
/// invariant is a single string in a single file, a substring assertion
/// is the right tool.
///
/// ## What's asserted
///
/// 1. The production shader (`atmospheric_fog.frag`) contains the
///    `tilePeriodPixels = uResolution / maxScale` line.
/// 2. The production shader's `noiseUv` is computed via
///    `fract(uPixelOrigin / tilePeriodPixels)`, NOT the pre-fix
///    `fract(uPixelOrigin / uResolution)`.
/// 3. The debug-spiral shader applies the same B-3 formulation so
///    Walk #3 spiral observation reflects the post-fix coordinate
///    system.
/// 4. `FogShaderUniforms.totalFloatSlots` is still 41 — Branch B-3
///    derives `tilePeriodPixels` in-shader from existing slots and
///    does NOT introduce a new uniform.
void main() {
  group('FOG-14b (Plan 03.1-07 Branch B-3) — tile-period-aware fract-period engineering invariant', () {
    test('production shader noiseUv uses tilePeriodPixels (not uResolution) divisor', () {
      final source = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();

      // Post-fix presence: tilePeriodPixels derivation line.
      expect(
        source,
        contains('tilePeriodPixels = uResolution / maxScale'),
        reason:
            'FOG-14b: production shader must derive `tilePeriodPixels = uResolution / maxScale` per Branch B-3. '
            'If this assertion fails, the B-3 fix has been reverted to viewport-width modulo.',
      );

      // Post-fix presence: noiseUv assignment uses tilePeriodPixels.
      expect(
        source,
        contains('vec2 noiseUv = fragUv + fract(uPixelOrigin / tilePeriodPixels);'),
        reason:
            'FOG-14b: production shader `noiseUv` must use `fract(uPixelOrigin / tilePeriodPixels)` divisor. '
            'If this assertion fails, the B-3 fix has been reverted.',
      );

      // Pre-fix absence: the viewport-width formulation must NOT
      // appear anywhere in the active code path. This guards against
      // dead-code reverts that leave the new line in place but
      // re-introduce the old computation under a different name.
      // (The pre-fix `fract(uPixelOrigin / uResolution)` is allowed to
      // appear in COMMENTS describing the historical formulation;
      // strip line comments before the substring check.)
      final activeCode = source
          .split('\n')
          .map((line) {
            final commentIdx = line.indexOf('//');
            return commentIdx >= 0 ? line.substring(0, commentIdx) : line;
          })
          .join('\n');
      expect(
        activeCode,
        isNot(contains('fract(uPixelOrigin / uResolution)')),
        reason:
            'FOG-14b: pre-Branch-B-3 formulation `fract(uPixelOrigin / uResolution)` MUST NOT appear in the '
            'active code path of `atmospheric_fog.frag`. Permitted only in comments documenting the historical '
            'shape. If this fires, the B-3 fix coexists with a stale call site that may shadow it.',
      );
    });

    test('debug-spiral shader applies the same B-3 formulation', () {
      final source = File('assets/shaders/atmospheric_fog_debug_spiral.frag').readAsStringSync();
      // The debug shader uses #define DEBUG_SPIRAL_SCALE_* constants
      // rather than runtime uniforms, so the divisor is computed from
      // the constant-folded scales. The key invariant: `tilePeriodPixels`
      // is derived from `uResolution / maxScale`, not directly from
      // `uResolution`.
      expect(
        source,
        contains('tilePeriodPixels = uResolution / maxScale'),
        reason:
            'FOG-14b: debug-spiral shader must mirror the production B-3 formulation so Walk #3 spiral '
            'observation reflects the post-fix coordinate system.',
      );
      expect(
        source,
        contains('vec2 spiralCoord = fragUv + fract(uPixelOrigin / tilePeriodPixels);'),
        reason: 'FOG-14b: debug-spiral `spiralCoord` must use the B-3 tile-period-aware `fract()` divisor.',
      );
    });

    test('FogShaderUniforms.totalFloatSlots == 41 — B-3 derives tilePeriodPixels in-shader (no new uniform)', () {
      final source = File('lib/infrastructure/mirk/shader/fog_shader_uniforms.dart').readAsStringSync();
      expect(
        source,
        contains('static const int totalFloatSlots = 41;'),
        reason:
            'FOG-14b: the 41-slot float uniform layout is locked. Branch B-3 derives `tilePeriodPixels` '
            'in-shader from existing slots `uScaleFar/Mid/Near` (slots 20..22) — it must NOT introduce a new '
            'uniform. If this assertion fails, the slot budget grew and the layout is no longer in lockstep '
            'with the shader.',
      );
    });
  });
}
