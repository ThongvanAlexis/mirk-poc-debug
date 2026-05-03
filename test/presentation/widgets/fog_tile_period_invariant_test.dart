// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';

/// FOG-17 (Plan 03.1-10) — world-coordinate noise sampling engineering
/// invariant.
///
/// REWRITTEN from FOG-14b (Plan 03.1-07 Branch B-3 tile-period-aware
/// fract). The file name is preserved for git-history continuity even
/// though the test content has flipped to assert the post-Plan-03.1-10
/// world-coordinate formulation. The "tile period" terminology is
/// historical; the post-fix formulation has no tile-period fract — it
/// has a noise-tile divisor (`kNoiseTilePx`) which sets the noise
/// grid scale in screen-pixel space.
///
/// ## Background
///
/// The Plan 03.1-07 Branch B-3 fix moved the wrap period from
/// viewport-width (~390 px) to noise-tile period (~16-65 px) but kept
/// the per-event wrap MAGNITUDE the same (Walk #3 confirmed). The
/// Plan 03.1-10 FOG-17 fix replaces `fract()` entirely with
/// world-coordinate sampling: each fragment samples noise at its OWN
/// world-pixel position, so as the camera pans NEW world coordinates
/// enter the viewport edges and NEW noise scrolls in — no fract(), no
/// wraps, no stepping.
///
/// ## What's asserted
///
/// 1. Production shader (`atmospheric_fog.frag`) contains the
///    `kNoiseTilePx` const float declaration AND the
///    `worldPx = fragUv * uResolution + uPixelOrigin` line AND the
///    `noiseUv = worldPx / kNoiseTilePx` line.
/// 2. Production shader's ACTIVE CODE (line-comment-stripped) does NOT
///    contain `fract(uPixelOrigin / tilePeriodPixels)` — the
///    pre-Plan-03.1-10 B-3 formulation must be removed from active
///    code. Allowed in comments documenting the historical formulation.
/// 3. Debug-spiral shader (`atmospheric_fog_debug_spiral.frag`) mirrors
///    the post-Plan-03.1-10 formulation so /sanity spiral observation
///    reflects the production coordinate system.
/// 4. `FogShaderUniforms.totalFloatSlots == 41` (no new uniform — the
///    `kNoiseTilePx` value is constant-folded as a `const float` in
///    the shader, NOT added as a runtime uniform).
void main() {
  group('FOG-17 (Plan 03.1-10) — world-coordinate noise sampling engineering invariant', () {
    test('production shader contains the FOG-17 world-coordinate formulation', () {
      final source = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();

      expect(
        source,
        contains('const float kNoiseTilePx = 384.0;'),
        reason:
            'FOG-17: production shader must declare `const float kNoiseTilePx = 384.0;` (constant-folded, NOT a uniform). '
            'Value MUST stay in lockstep with `kPocFogNoiseTilePx` in `lib/config/constants.dart`. '
            'If this assertion fails, the FOG-17 fix has been reverted or the constant has drifted from the Dart source.',
      );

      expect(
        source,
        contains('vec2 worldPx = fragUv * uResolution + uPixelOrigin;'),
        reason: 'FOG-17: production shader must compute `worldPx = fragUv * uResolution + uPixelOrigin` (per-fragment world position).',
      );

      expect(
        source,
        contains('vec2 noiseUv = worldPx / kNoiseTilePx;'),
        reason:
            'FOG-17: production shader `noiseUv` must use `worldPx / kNoiseTilePx` (world-coordinate noise sampling). '
            'If this assertion fails, the FOG-17 fix has been reverted to the B-3 fract() formulation.',
      );
    });

    test('production shader active code does NOT contain pre-Plan-03.1-10 fract(uPixelOrigin / tilePeriodPixels)', () {
      final source = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();

      // Strip line comments before the substring check. The
      // pre-Plan-03.1-10 formulation is allowed to appear in COMMENTS
      // documenting the historical shape; it is NOT allowed in active
      // code.
      final activeCode = source
          .split('\n')
          .map((line) {
            final commentIdx = line.indexOf('//');
            return commentIdx >= 0 ? line.substring(0, commentIdx) : line;
          })
          .join('\n');

      expect(
        activeCode,
        isNot(contains('fract(uPixelOrigin / tilePeriodPixels)')),
        reason:
            'FOG-17: pre-Plan-03.1-10 B-3 formulation `fract(uPixelOrigin / tilePeriodPixels)` MUST NOT appear in active code. '
            'Permitted only in comments documenting the historical shape. If this fires, the FOG-17 fix coexists with a stale '
            'call site that may shadow it.',
      );

      // Defense-in-depth: the Plan 03.1-04 viewport-width formulation
      // (the formulation B-3 replaced) must also be absent from active
      // code.
      expect(
        activeCode,
        isNot(contains('fract(uPixelOrigin / uResolution)')),
        reason: 'FOG-17: Plan-03.1-04 viewport-width fract formulation `fract(uPixelOrigin / uResolution)` must also be absent from active code.',
      );
    });

    test('debug-spiral shader mirrors the post-Plan-03.1-10 formulation', () {
      final source = File('assets/shaders/atmospheric_fog_debug_spiral.frag').readAsStringSync();

      expect(
        source,
        contains('const float kNoiseTilePx = 384.0;'),
        reason:
            'FOG-17: debug-spiral shader must mirror the production `kNoiseTilePx` const float so /sanity observation reflects the post-fix coordinate system.',
      );

      expect(
        source,
        contains('vec2 worldPx = fragUv * uResolution + uPixelOrigin;'),
        reason: 'FOG-17: debug-spiral must mirror the production `worldPx` computation.',
      );

      expect(
        source,
        contains('vec2 spiralCoord = worldPx / kNoiseTilePx;'),
        reason: 'FOG-17: debug-spiral `spiralCoord` must use `worldPx / kNoiseTilePx` (mirrors production `noiseUv`).',
      );

      expect(
        source,
        contains('vec2 cellPx = worldPx;'),
        reason: 'FOG-17: debug-spiral cellPx must derive from `worldPx` directly (already in raw pixels post-fix).',
      );
    });

    test('debug-spiral shader active code does NOT contain pre-Plan-03.1-10 fract(uPixelOrigin / tilePeriodPixels)', () {
      final source = File('assets/shaders/atmospheric_fog_debug_spiral.frag').readAsStringSync();
      final activeCode = source
          .split('\n')
          .map((line) {
            final commentIdx = line.indexOf('//');
            return commentIdx >= 0 ? line.substring(0, commentIdx) : line;
          })
          .join('\n');

      expect(
        activeCode,
        isNot(contains('fract(uPixelOrigin / tilePeriodPixels)')),
        reason: 'FOG-17: debug-spiral active code must not retain the B-3 fract formulation.',
      );
    });

    test('FogShaderUniforms.totalFloatSlots == 41 — kNoiseTilePx is constant-folded (no new uniform)', () {
      final source = File('lib/infrastructure/mirk/shader/fog_shader_uniforms.dart').readAsStringSync();
      expect(
        source,
        contains('static const int totalFloatSlots = 41;'),
        reason:
            'FOG-17: the 41-slot float uniform layout is locked. The `kNoiseTilePx` value is constant-folded as a '
            '`const float` in the shader, NOT added as a runtime uniform. If this assertion fails, the slot budget grew '
            'and the layout is no longer in lockstep with the shader.',
      );
    });
  });
}
