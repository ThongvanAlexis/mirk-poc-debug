// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';

/// FOG-19 (Plan 03.1-14 Fix B′) — meter-space anchor noise sampling
/// engineering invariant.
///
/// **Plan 03.1-14 (Fix B′) re-write:** flipped the static-source-grep
/// from Plan 03.1-12 era pixel-space-then-multiply formulation
/// `vec2 worldMeters = (fragUv * uResolution + uPixelOrigin) *
/// uMetersPerPixel` to Plan 03.1-14 active formulation
/// `vec2 worldMeters = (fragUv * uResolution) * uMetersPerPixel +
/// uWorldMetersOrigin`. Slot 3..4 NAME assertion flips from
/// `uPixelOrigin` to `uWorldMetersOrigin`. FogShaderUniforms.totalFloatSlots
/// == 42 unchanged.
///
/// File name preserved for git-history continuity.
///
/// ## Background
///
/// Plan 03.1-12's FOG-18 fix anchored noise to meter-space but RETAINED
/// the FOG-17a integer/fractional decomposition in pixel space; Walk #5
/// (Plan 03.1-13) empirically falsified that design via the period-
/// commensurability gap (1536 raw px wrap × mpp at z=15 lat 48.5°
/// produces 4.74-cell shift in noiseUv — non-integer-multiple).
///
/// Plan 03.1-14 Fix B′ moves the integer/fractional decomposition to
/// METER space. Wrap period is `kPocFogIntegerWrapPeriodMeters = 4096 m
/// = 4 × kPocFogNoiseTilePxMeters`. Wrap injects exactly +4 integer
/// cells in noiseUv → Octave 1 bit-identical (hash3 period-1).
///
/// ## What's asserted
///
/// 1. Production shader (`atmospheric_fog.frag`) declares
///    `uniform vec2 uWorldMetersOrigin;` (slot 3..4 — semantic rename).
/// 2. Production shader contains the Plan 03.1-14 Fix B′ active-code
///    formulation: `vec2 worldMeters = (fragUv * uResolution) *
///    uMetersPerPixel + uWorldMetersOrigin;` AND `vec2 noiseUv =
///    worldMeters / kNoiseTilePxMeters;` AND `const float
///    kNoiseTilePxMeters = 1024.0;`.
/// 3. Production shader's ACTIVE CODE (line-comment-stripped) does NOT
///    contain the Plan 03.1-12 era formulation `vec2 worldMeters =
///    (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel;` — must
///    be removed from active code (allowed in comments documenting the
///    historical formulation).
/// 4. Debug-spiral shader (`atmospheric_fog_debug_spiral.frag`) mirrors
///    the post-Plan-03.1-14 formulation: declares `uniform vec2
///    uWorldMetersOrigin;`, contains the meter-space worldMeters
///    formulation.
/// 5. `FogShaderUniforms.totalFloatSlots == 42` (unchanged; Plan 03.1-14
///    is a slot-3/4 rename, NOT a slot count change).
void main() {
  group('FOG-19 (Plan 03.1-14 Fix B′) — meter-space anchor noise sampling engineering invariant', () {
    test('production shader declares uniform vec2 uWorldMetersOrigin (slot 3..4 rename)', () {
      final source = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();

      // Strip line comments to scan active code only.
      final activeCode = source
          .split('\n')
          .map((line) {
            final commentIdx = line.indexOf('//');
            return commentIdx >= 0 ? line.substring(0, commentIdx) : line;
          })
          .join('\n');

      expect(
        activeCode.contains('uniform vec2  uWorldMetersOrigin;') || activeCode.contains('uniform vec2 uWorldMetersOrigin;'),
        isTrue,
        reason:
            'Plan 03.1-14 Fix B′: production shader must declare `uniform vec2 uWorldMetersOrigin;` (slot 3..4 — '
            'semantic rename from FOG-17a-pixel-space `uPixelOrigin` to FOG-19-meter-space `uWorldMetersOrigin`). '
            'If this assertion fails, the Plan 03.1-14 Fix B′ has been reverted at the shader-uniform level.',
      );

      expect(
        source,
        contains('uniform float uMetersPerPixel;'),
        reason: 'FOG-18: production shader must declare `uniform float uMetersPerPixel;` (slot 41) — UNCHANGED by Plan 03.1-14.',
      );

      expect(
        source,
        contains('const float kNoiseTilePxMeters = 1024.0;'),
        reason:
            'FOG-18: production shader must declare `const float kNoiseTilePxMeters = 1024.0;` (constant-folded, NOT a uniform). '
            'Value MUST stay in lockstep with `kPocFogNoiseTilePxMeters` in `lib/config/constants.dart`. '
            'Plan 03.1-14 Fix B′: the noise tile period is unchanged at 1024 m; only the integer wrap period flipped to meter-space.',
      );

      expect(
        source,
        contains('vec2 worldMeters = (fragUv * uResolution) * uMetersPerPixel + uWorldMetersOrigin;'),
        reason:
            'Plan 03.1-14 Fix B′: production shader must compute `worldMeters = (fragUv * uResolution) * uMetersPerPixel + uWorldMetersOrigin` '
            '(Fix B′ active formulation; the camera anchor is forwarded in METER space directly).',
      );

      expect(
        source,
        contains('vec2 noiseUv = worldMeters / kNoiseTilePxMeters;'),
        reason: 'FOG-18: production shader `noiseUv` must use `worldMeters / kNoiseTilePxMeters` (world-meter noise sampling; UNCHANGED by Plan 03.1-14).',
      );
    });

    test('production shader active code does NOT contain pre-Plan-03.1-14 pixel-space-then-multiply formulation', () {
      final source = File('assets/shaders/atmospheric_fog.frag').readAsStringSync();

      // Strip line comments before the substring check. The pre-Plan-
      // 03.1-14 formulation is allowed to appear in COMMENTS documenting
      // the historical shape; it is NOT allowed in active code.
      final activeCode = source
          .split('\n')
          .map((line) {
            final commentIdx = line.indexOf('//');
            return commentIdx >= 0 ? line.substring(0, commentIdx) : line;
          })
          .join('\n');

      expect(
        activeCode,
        isNot(contains('vec2 worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel;')),
        reason:
            'Plan 03.1-14 Fix B′: pre-Plan-03.1-14 Plan 03.1-12 era formulation `vec2 worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel;` '
            'MUST NOT appear in active code. Permitted only in comments documenting the historical shape. If this fires, the Fix B′ coexists with a stale '
            'shader-side formulation.',
      );

      expect(
        activeCode,
        isNot(contains('vec2 noiseUv = worldPx / kNoiseTilePx;')),
        reason: 'FOG-18: pre-Plan-03.1-12 FOG-17 formulation `vec2 noiseUv = worldPx / kNoiseTilePx;` MUST NOT appear in active code.',
      );

      // Defense-in-depth: the pre-FOG-17 fract formulations must also
      // be absent from active code.
      expect(
        activeCode,
        isNot(contains('fract(uPixelOrigin / tilePeriodPixels)')),
        reason: 'pre-Plan-03.1-10 B-3 formulation `fract(uPixelOrigin / tilePeriodPixels)` must remain absent from active code.',
      );
      expect(
        activeCode,
        isNot(contains('fract(uPixelOrigin / uResolution)')),
        reason: 'Plan-03.1-04 viewport-width fract formulation `fract(uPixelOrigin / uResolution)` must remain absent from active code.',
      );
    });

    test('debug-spiral shader mirrors the post-Plan-03.1-14 formulation', () {
      final source = File('assets/shaders/atmospheric_fog_debug_spiral.frag').readAsStringSync();
      final activeCode = source
          .split('\n')
          .map((line) {
            final commentIdx = line.indexOf('//');
            return commentIdx >= 0 ? line.substring(0, commentIdx) : line;
          })
          .join('\n');

      expect(
        activeCode.contains('uniform vec2  uWorldMetersOrigin;') || activeCode.contains('uniform vec2 uWorldMetersOrigin;'),
        isTrue,
        reason: 'Plan 03.1-14 Fix B′: debug-spiral shader must declare `uniform vec2 uWorldMetersOrigin;` (slot 3..4 — semantic rename mirrors production).',
      );

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
        contains('vec2 worldMeters = (fragUv * uResolution) * uMetersPerPixel + uWorldMetersOrigin;'),
        reason: 'Plan 03.1-14 Fix B′: debug-spiral must mirror the production active-formulation `worldMeters` computation.',
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

    test('debug-spiral shader active code does NOT contain pre-Plan-03.1-14 pixel-space-then-multiply formulation', () {
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
        isNot(contains('vec2 worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel;')),
        reason: 'Plan 03.1-14 Fix B′: pre-Plan-03.1-14 Plan 03.1-12 era debug-spiral formulation must NOT appear in active code.',
      );

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

    test('FogShaderUniforms.totalFloatSlots == 42 — slot count UNCHANGED by Plan 03.1-14 (Fix B′ is a slot-3/4 rename, not a count change)', () {
      final source = File('lib/infrastructure/mirk/shader/fog_shader_uniforms.dart').readAsStringSync();
      expect(
        source,
        contains('static const int totalFloatSlots = 42;'),
        reason:
            'Plan 03.1-14 Fix B′: the slot budget STAYS at 42 — the Fix B′ is a slot-3/4 SEMANTIC RENAME (uPixelOrigin → uWorldMetersOrigin), '
            'NOT a slot count change. If this assertion fails, either Plan 03.1-14 has been mis-applied (a new uniform slot accidentally added) '
            'or the FOG-18 slot 41 has been reverted.',
      );
    });
  });
}
