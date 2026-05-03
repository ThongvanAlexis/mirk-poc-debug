// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';

/// FOG-18 (Plan 03.1-12) — world-meter anchor noise sampling engineering
/// invariant.
///
/// REWRITTEN from FOG-17 (Plan 03.1-10) world-coordinate noise sampling.
/// The file name is preserved for git-history continuity even though the
/// test content has flipped to assert the post-Plan-03.1-12 world-meter
/// formulation. The "tile period" terminology is historical.
///
/// ## Background
///
/// Plan 03.1-10's FOG-17 formulation (`vec2 worldPx = fragUv *
/// uResolution + uPixelOrigin; vec2 noiseUv = worldPx / kNoiseTilePx`)
/// anchored noise to Web-Mercator world-pixel space. Walk #4 (Plan
/// 03.1-11) surfaced Q5 zoom-scramble: uPixelOrigin doubles per zoom
/// step → fragments under any given screen position sample completely
/// different noise positions per zoom step (fast sliding); raw-pixel
/// kNoiseTilePx kept cells screen-pinned, not meter-scaled.
///
/// Plan 03.1-12's FOG-18 fix replaces the pixel-space anchor with a
/// meter-space anchor: each fragment's worldMeters = (worldPx) *
/// uMetersPerPixel. At a fixed geographic point, worldMeters is
/// zoom-INVARIANT (the metersPerPixel-halving cancels the worldPx-
/// doubling exactly). Cells now scale on screen with zoom.
///
/// ## What's asserted
///
/// 1. Production shader (`atmospheric_fog.frag`) declares
///    `uniform float uMetersPerPixel;` (slot 41).
/// 2. Production shader contains the FOG-18 active-code formulation:
///    `vec2 worldMeters = (fragUv * uResolution + uPixelOrigin) *
///    uMetersPerPixel;` AND `vec2 noiseUv = worldMeters /
///    kNoiseTilePxMeters;` AND `const float kNoiseTilePxMeters = 1024.0;`.
/// 3. Production shader's ACTIVE CODE (line-comment-stripped) does NOT
///    contain the FOG-17 formulation `vec2 noiseUv = worldPx /
///    kNoiseTilePx;` — the pre-Plan-03.1-12 formulation must be removed
///    from active code. Allowed in comments documenting the historical
///    formulation.
/// 4. Debug-spiral shader (`atmospheric_fog_debug_spiral.frag`) mirrors
///    the post-Plan-03.1-12 formulation: declares `uniform float
///    uMetersPerPixel;`, contains the meter-space worldMeters
///    formulation, and uses `kDebugSpiralCellSizeMeters` for cell
///    indexing.
/// 5. `FogShaderUniforms.totalFloatSlots == 42` (post-FOG-18 — slot 41
///    `uMetersPerPixel` added).
void main() {
  group('FOG-18 (Plan 03.1-12) — world-meter anchor noise sampling engineering invariant', () {
    test('production shader contains the FOG-18 world-meter formulation', () {
      final source = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();

      expect(
        source,
        contains('uniform float uMetersPerPixel;'),
        reason:
            'FOG-18: production shader must declare `uniform float uMetersPerPixel;` (slot 41). '
            'If this assertion fails, the FOG-18 fix has been reverted at the shader-uniform level.',
      );

      expect(
        source,
        contains('const float kNoiseTilePxMeters = 1024.0;'),
        reason:
            'FOG-18: production shader must declare `const float kNoiseTilePxMeters = 1024.0;` (constant-folded, NOT a uniform). '
            'Value MUST stay in lockstep with `kPocFogNoiseTilePxMeters` in `lib/config/constants.dart`. '
            'If this assertion fails, the FOG-18 fix has been reverted or the constant has drifted from the Dart source.',
      );

      expect(
        source,
        contains('vec2 worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel;'),
        reason:
            'FOG-18: production shader must compute `worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel` (per-fragment world-meter position).',
      );

      expect(
        source,
        contains('vec2 noiseUv = worldMeters / kNoiseTilePxMeters;'),
        reason:
            'FOG-18: production shader `noiseUv` must use `worldMeters / kNoiseTilePxMeters` (world-meter noise sampling). '
            'If this assertion fails, the FOG-18 fix has been reverted to the FOG-17 pixel-space formulation.',
      );
    });

    test('production shader active code does NOT contain pre-Plan-03.1-12 FOG-17 pixel-space formulation', () {
      final source = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();

      // Strip line comments before the substring check. The
      // pre-Plan-03.1-12 formulation is allowed to appear in COMMENTS
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
        isNot(contains('vec2 noiseUv = worldPx / kNoiseTilePx;')),
        reason:
            'FOG-18: pre-Plan-03.1-12 FOG-17 formulation `vec2 noiseUv = worldPx / kNoiseTilePx;` MUST NOT appear in active code. '
            'Permitted only in comments documenting the historical shape. If this fires, the FOG-18 fix coexists with a stale '
            'shader-side formulation.',
      );

      // Defense-in-depth: the pre-FOG-17 fract formulations must also
      // be absent from active code.
      expect(
        activeCode,
        isNot(contains('fract(uPixelOrigin / tilePeriodPixels)')),
        reason: 'FOG-18: pre-Plan-03.1-10 B-3 formulation `fract(uPixelOrigin / tilePeriodPixels)` must remain absent from active code.',
      );
      expect(
        activeCode,
        isNot(contains('fract(uPixelOrigin / uResolution)')),
        reason: 'FOG-18: Plan-03.1-04 viewport-width fract formulation `fract(uPixelOrigin / uResolution)` must remain absent from active code.',
      );
    });

    test('debug-spiral shader mirrors the post-Plan-03.1-12 formulation', () {
      final source = File('assets/shaders/atmospheric_fog_debug_spiral.frag').readAsStringSync();

      expect(
        source,
        contains('uniform float uMetersPerPixel;'),
        reason: 'FOG-18: debug-spiral shader must declare `uniform float uMetersPerPixel;` (slot 5; debug-spiral has slots 0..5 + sampler).',
      );

      expect(
        source,
        contains('const float kNoiseTilePxMeters = 1024.0;'),
        reason:
            'FOG-18: debug-spiral shader must mirror the production `kNoiseTilePxMeters` const float so /sanity + /map debug observation reflects the post-fix coordinate system.',
      );

      expect(
        source,
        contains('const float kDebugSpiralCellSizeMeters = 200.0;'),
        reason: 'FOG-18: debug-spiral shader must declare `const float kDebugSpiralCellSizeMeters = 200.0;` for the meter-space cell size.',
      );

      expect(
        source,
        contains('vec2 worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel;'),
        reason: 'FOG-18: debug-spiral must mirror the production `worldMeters` computation.',
      );

      expect(
        source,
        contains('vec2 spiralCoord = worldMeters / kNoiseTilePxMeters;'),
        reason: 'FOG-18: debug-spiral `spiralCoord` must use `worldMeters / kNoiseTilePxMeters` (mirrors production `noiseUv`).',
      );

      expect(
        source,
        contains('vec2 cellMeters = worldMeters;'),
        reason: 'FOG-18: debug-spiral cellMeters must derive from `worldMeters` directly (cells are physical squares of ground).',
      );
    });

    test('debug-spiral shader active code does NOT contain pre-Plan-03.1-12 pixel-space cellPx formulation', () {
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
        isNot(contains('vec2 cellPx = worldPx;')),
        reason:
            'FOG-18: pre-Plan-03.1-12 debug-spiral formulation `vec2 cellPx = worldPx;` MUST NOT appear in active code (the meter-space formulation uses cellMeters).',
      );

      expect(
        activeCode,
        isNot(contains('vec2 spiralCoord = worldPx / kNoiseTilePx;')),
        reason: 'FOG-18: pre-Plan-03.1-12 debug-spiral spiralCoord formulation must remain absent from active code.',
      );
    });

    test('FogShaderUniforms.totalFloatSlots == 42 — slot count advances 41 → 42 with new uMetersPerPixel uniform', () {
      final source = File('lib/infrastructure/mirk/shader/fog_shader_uniforms.dart').readAsStringSync();
      expect(
        source,
        contains('static const int totalFloatSlots = 42;'),
        reason:
            'FOG-18: the slot budget advances 41 → 42 with the new `uMetersPerPixel` uniform at slot 41. If this assertion '
            'fails, either the slot budget did not advance or the layout has drifted from the shader.',
      );
    });
  });
}
