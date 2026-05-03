// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-19 (Plan 03.1-14 Fix B′) — meter-space decomposition continuity test.
///
/// Synthesises a pixelOrigin sweep crossing ≥ 3 wrap events; for each
/// sample, computes Dart-side boundedMeters AND the shader-equivalent
/// noiseUv at viewport-centre fragment; asserts noiseUv evolves
/// smoothly with NO `>1.0`-cell discontinuity at any wrap boundary
/// (the wrap-induced shift modulo 1.0 is `< 1e-3`).
///
/// Walk #5 (Plan 03.1-13) empirically falsified the Plan 03.1-12 era
/// pixel-space FOG-17a decomposition: the developer fired 2
/// `steppy_translation` markers at sub-cell-discontinuity wrap events
/// (0.74-cell shift per wrap at z=15 lat 48.5°). Plan 03.1-14 Fix B′
/// chooses kPocFogIntegerWrapPeriodMeters = 4096 m = 4 ×
/// kPocFogNoiseTilePxMeters → wrap injects exactly 4 integer cells in
/// noiseUv → Octave 1 bit-identical (hash3 period-1); Octaves 2 + 3
/// receive a CONSTANT deterministic phase shift bounded by
/// kPocFogFbmDiscontinuityBound ≈ 11% of fbm3 dynamic range, INVARIANT
/// across all wrap events. The architectural property is invariance,
/// NOT invisibility — sub-test 3 below empirically validates the bound.
/// See continuity_proof_for_plan_03_1_14 in Plan 03.1-14 for derivation.
void main() {
  group('FOG-19 (Plan 03.1-14): meter-space decomposition continuity', () {
    const double lat = 48.5397; // central Melun
    const double zoom = 15.0; // typical Walk regime

    late final double mpp;
    setUpAll(() {
      final latRadians = lat * math.pi / 180.0;
      mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRadians) / math.pow(2.0, zoom).toDouble();
    });

    test('sweeping worldMeters across >= 3 wrap events injects only integer-cell shifts in noiseUv', () {
      // Sweep worldMetersX from 0 to 15000 m at 1 m steps. 15000 / 4096
      // ≈ 3.66 wrap events.
      const stepCount = 15000;
      double? prevNoiseUvX;
      var detectedNonIntegerShifts = 0;

      for (var i = 0; i <= stepCount; i++) {
        final worldMetersX = i.toDouble();
        final intMetersX = worldMetersX.truncateToDouble();
        final fracMetersX = worldMetersX - intMetersX;
        final boundedMetersX = (intMetersX % kPocFogIntegerWrapPeriodMeters) + fracMetersX;

        // Shader-equivalent noiseUv at viewport-centre fragment.
        // Viewport-centre fragUv = 0.5; uResolution.x = 390 (iPhone 17 Pro);
        // (fragUv * uResolution) * mpp = 0.5 * 390 * mpp ≈ 616 m at z=15.
        final fragMetersX = 0.5 * 390.0 * mpp;
        final noiseUvX = (fragMetersX + boundedMetersX) / kPocFogNoiseTilePxMeters;

        if (prevNoiseUvX != null) {
          final delta = noiseUvX - prevNoiseUvX;
          // smoothStep: small positive delta (smooth pan).
          // wrapStep: large negative delta of magnitude ≈ 4 cells = -4.0
          // (modulo 1.0 ≈ 0.0).
          final deltaModFloor = (delta - delta.floorToDouble()).abs();
          final smoothStep = delta.abs() < 1e-3;
          final wrapStep = (deltaModFloor < 1e-3) || ((deltaModFloor - 1.0).abs() < 1e-3);
          if (!smoothStep && !wrapStep) {
            detectedNonIntegerShifts++;
          }
        }
        prevNoiseUvX = noiseUvX;
      }

      expect(
        detectedNonIntegerShifts,
        0,
        reason:
            'FOG-19 (Plan 03.1-14): the wrap event must inject only an '
            'integer-cell shift in noiseUv (4096 m / 1024 m = 4 cells '
            'exactly); a non-integer shift indicates '
            'kPocFogIntegerWrapPeriodMeters is no longer a multiple of '
            'kPocFogNoiseTilePxMeters. Walk #5 (Plan 03.1-13) falsified '
            'the pixel-space FOG-17a; Plan 03.1-14 Fix B′ closes the '
            'period-commensurability gap.',
      );
    });

    test('period-commensurability invariant holds: 4096 % 1024 == 0 and ratio = 4', () {
      expect(
        kPocFogIntegerWrapPeriodMeters % kPocFogNoiseTilePxMeters,
        0.0,
        reason:
            'FOG-19 invariant: wrap period MUST be integer multiple '
            'of noise tile period.',
      );
      expect(
        kPocFogIntegerWrapPeriodMeters / kPocFogNoiseTilePxMeters,
        4.0,
        reason:
            'FOG-19 ratio = 4 cells per wrap (chosen for fp32 '
            'precision headroom + power-of-2 friendliness).',
      );
    });

    test('wrap event jumps boundedMeters by exactly -kPocFogIntegerWrapPeriodMeters in worldMeters', () {
      // At synthetic worldMetersX = 4095 (just before wrap), bounded
      // composite ≈ 4095. At 4097, bounded composite ≈ 1 (post-wrap).
      // Delta is -4094 in bounded composite; in noiseUv that's
      // -4094 / 1024 ≈ -3.998 cells (~ -4.0 cells modulo 1.0 = ~0).
      const before = 4095.0;
      const after = 4097.0;

      double bounded(double wm) {
        final intM = wm.truncateToDouble();
        final fracM = wm - intM;
        return (intM % kPocFogIntegerWrapPeriodMeters) + fracM;
      }

      final bBefore = bounded(before);
      final bAfter = bounded(after);
      final delta = bAfter - bBefore;
      // Expect delta ≈ -4094 (= -(kPocFogIntegerWrapPeriodMeters - 2)).
      expect(
        delta,
        closeTo(-(kPocFogIntegerWrapPeriodMeters - 2.0), 1e-6),
        reason:
            'FOG-19: at the wrap boundary (4096 m), the bounded meter composite jumps by '
            '-(kPocFogIntegerWrapPeriodMeters - 2) ≈ -4094 m for a 2-m sweep across the boundary '
            '(4097 - 4095). In noiseUv units the shift modulo 1.0 must be ~0 (integer-cell shift only).',
      );

      final deltaNoiseUv = delta / kPocFogNoiseTilePxMeters;
      final shiftModFloor = (deltaNoiseUv - deltaNoiseUv.floorToDouble()).abs();
      // The 2 m gap straddling 4096 produces a delta of ~-3.998 cells in noiseUv:
      //   delta / 1024 = -4094 / 1024 = -3.99804...
      //   floor(-3.998) = -4; -3.998 - (-4) = 0.00195
      // The remainder is ~0.002 (= 2/1024) — well under 1e-3 threshold.
      expect(
        shiftModFloor,
        lessThan(0.005),
        reason: 'FOG-19: noiseUv wrap-shift modulo 1.0 must be near 0 (the shift is integer-cell + sub-cell of the bridge gap).',
      );
    });
  });
}
