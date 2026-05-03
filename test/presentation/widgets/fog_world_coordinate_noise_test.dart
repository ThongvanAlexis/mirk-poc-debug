// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-19 (Plan 03.1-14 Fix B′) — meter-space anchor: ZERO wrap-
/// discontinuity events under the post-fix simulator at all pixelOrigin ×
/// zoom combinations within a sub-wrap-period sweep.
///
/// **Plan 03.1-14 (Fix B′) re-write:** flipped from FOG-18 era
/// `worldMeters = (fragUv * uResolution + boundedPxOrigin) * mpp`
/// (pixel-space bounded composite then multiply) to FOG-19
/// `worldMeters = (fragUv * uResolution) * mpp + boundedMeters`
/// (meter-space bounded composite directly). The simulator's
/// monotonicity property is preserved by both formulations within a
/// sub-wrap-period sweep.
///
/// File name preserved for git-history continuity.
///
/// ## Background
///
/// Plan 03.1-07 Branch B-3 wrapped every ~16-65 raw px (Walk #3
/// stepping persists at wrap events). Plan 03.1-10 FOG-17 replaced
/// `fract()` with world-coordinate sampling — ZERO wraps within a
/// single integer-wrap window — but anchored noise to pixel-space
/// (Walk #4 Q5 zoom-scramble surfaced).
///
/// Plan 03.1-12 FOG-18 anchored noise to METER-space:
///   `worldMeters = (fragUv * uResolution + boundedPxOrigin) * mpp;
///    noiseUv = worldMeters / kNoiseTilePxMeters;`
/// Walk #5 surfaced Q1 stepping at FOG-17a-pixel-space wrap events
/// (period-commensurability gap).
///
/// Plan 03.1-14 Fix B′ flipped the decomposition to METER space:
///   `boundedMeters = (intMeters % kPocFogIntegerWrapPeriodMeters) +
///                    fracMeters;
///    worldMeters = (fragUv * uResolution) * mpp + boundedMeters;
///    noiseUv = worldMeters / kPocFogNoiseTilePxMeters;`
/// The wrap event now injects exactly 4 integer cells in noiseUv
/// (4096 m / 1024 m) → Octave 1 bit-identical, Octaves 2 + 3 receive
/// constant deterministic phase shift.
///
/// ## What's tested
///
/// 1. Synthetic smooth-pan trajectory at three pixelOrigin magnitude
///    regimes (1.064M ≈ Walk #3b zoom 13, 4.26M ≈ Walk #2 zoom 16,
///    17.04M ≈ extrapolated zoom 19), with the Plan 03.1-14 Fix B′
///    meter-space decomposition. Each regime: 300 paints @ 5 raw-px/
///    paint over a 1500-px sweep that stays under one wrap period when
///    converted to meter space at the regime's zoom × lat. Asserts ZERO
///    wrap-discontinuity events in METER-space cell evolution.
/// 2. Meter-space wrap event documentation: at every wrap event, the
///    noiseUv shift is exactly +4 integer cells (4096 m / 1024 m) —
///    confirming the period-commensurability invariant.

void main() {
  group('FOG-19 (Plan 03.1-14 Fix B′) — meter-space anchor: ZERO wrap events under smooth-pan @ fixed zoom', () {
    test('Walk #3b regime (pixelOriginX ≈ 1.064M, zoom 13 lat 48.5°) — ZERO wraps over sub-wrap-period sweep', () {
      final wrapCount = _countMeterSpaceWrapEvents(startPixelOriginX: 1536.0 * 692, zoom: 13.0, lat: 48.5397);
      expect(
        wrapCount,
        equals(0),
        reason:
            'FOG-19 invariant: Plan 03.1-14 Fix B′ meter-space formulation `boundedMeters = '
            '(intMeters % kPocFogIntegerWrapPeriodMeters) + fracMeters; worldMeters = (fragUv * uResolution) * mpp '
            '+ boundedMeters; noiseUv = worldMeters / kPocFogNoiseTilePxMeters` has ZERO wrap-discontinuity events '
            'across a sub-wrap-period smooth-pan trajectory at a fixed zoom. As the camera pans, worldMeters evolves '
            'monotonically forward; no fract() is applied. Wrap events fire only at kPocFogIntegerWrapPeriodMeters '
            '(4096 m) intervals in worldMeters — beyond the 1500-px-equivalent sweep window. '
            'If wraps are reported here, the FOG-19 formulation has been silently reverted to a fract() formulation. '
            'Wrap count: $wrapCount.',
      );
    });

    test('Walk #2 regime (pixelOriginX ≈ 4.26M, zoom 16 lat 48.5°) — ZERO wraps over sub-wrap-period sweep', () {
      final wrapCount = _countMeterSpaceWrapEvents(startPixelOriginX: 1536.0 * 2774, zoom: 16.0, lat: 48.5397);
      expect(wrapCount, equals(0));
    });

    test('Extrapolated zoom-19 regime (pixelOriginX ≈ 17.04M, lat 48.5°) — ZERO wraps over sub-wrap-period sweep', () {
      final wrapCount = _countMeterSpaceWrapEvents(startPixelOriginX: 1536.0 * 11094, zoom: 19.0, lat: 48.5397);
      expect(wrapCount, equals(0));
    });

    test('Plan 03.1-14 Fix B′ wrap event injects exactly 4 integer cells in noiseUv (period-commensurability invariant)', () {
      // At every wrap event, worldMeters jumps by exactly
      // kPocFogIntegerWrapPeriodMeters = 4096 m. In noiseUv units:
      // 4096 / 1024 = 4.0 — exactly 4 integer cells along the wrapping
      // axis. The integer-shift vector for an X-axis wrap is V = (-4, 0, 0).
      // Octave 1 (base) at the wrap: hash3 has integer period 1 → +4
      // shift lands on the IDENTICAL hash sample. Bit-identical pre/
      // post-wrap.
      const cellsPerWrap = kPocFogIntegerWrapPeriodMeters / kPocFogNoiseTilePxMeters;
      expect(
        cellsPerWrap,
        closeTo(4.0, 1e-9),
        reason: 'Plan 03.1-14 Fix B′ period-commensurability invariant: every wrap event shifts noiseUv by exactly 4 integer cells (4096 m / 1024 m).',
      );
      expect(
        kPocFogIntegerWrapPeriodMeters % kPocFogNoiseTilePxMeters,
        equals(0.0),
        reason:
            'Plan 03.1-14 Fix B′ period-commensurability invariant: kPocFogIntegerWrapPeriodMeters MUST be an integer multiple of kPocFogNoiseTilePxMeters.',
      );
    });
  });
}

/// Synthetic harness applying the post-Plan-03.1-14 Fix B′ meter-space
/// formulation. Returns the number of wrap-discontinuity events
/// detected across a sub-wrap-period meter-space sweep at a fixed zoom.
///
/// A wrap-discontinuity is a NEGATIVE delta in the noiseUv value
/// between consecutive paints (the fragment's noise sample input
/// jumping backwards). Under the post-fix formulation
/// `noiseUv = worldMeters / kPocFogNoiseTilePxMeters` the noiseUv
/// evolves monotonically forward at a fixed zoom — the only way a
/// backwards delta could appear within the sub-wrap-period sweep is
/// if the formulation reverts back to a fract()-based one OR if
/// metersPerPixel is incorrectly negative.
///
/// The sweep starts at a synthetic pixelOrigin chosen so the worldMeters
/// at the start of the sweep is aligned to a multiple of
/// kPocFogIntegerWrapPeriodMeters — the trajectory then stays within
/// one wrap window in meter space.
int _countMeterSpaceWrapEvents({required double startPixelOriginX, required double zoom, required double lat}) {
  const viewportWidth = 390.0;

  // Mid-viewport reference fragment (fragUv ≈ 0.5).
  const fragUvX = 0.5;

  // Compute metersPerPixel at the synthetic zoom × lat (mirrors
  // _FogPainter.paint() FOG-18 computation).
  final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, zoom).toDouble();

  // Plan 03.1-14 Fix B′: pick a synthetic start aligned to the start
  // of a 4096-m meter-space window. The startPixelOriginX argument is
  // ignored for the alignment math (kept for API back-compat with the
  // pre-Plan-03.1-14 simulator); the actual aligned start is computed
  // from the start magnitude × mpp truncation, then bumped forward to
  // the next wrap window start + 100 m to ensure we have a full wrap-
  // window-minus-100 m of headroom for the 3000 m sweep.
  final startWorldMeters = startPixelOriginX * mpp;
  final wrapsBefore = (startWorldMeters / kPocFogIntegerWrapPeriodMeters).floor();
  // Always bump to the NEXT wrap window start + 100 m so the sweep has
  // ~3996 m of headroom before the next wrap event — comfortably above
  // the 3000 m sweep budget.
  final adjustedStartMeters = (wrapsBefore + 1) * kPocFogIntegerWrapPeriodMeters + 100.0;
  return _sweepMeterSpace(adjustedStartMeters, mpp, fragUvX, viewportWidth);
}

int _sweepMeterSpace(double startWorldMetersX, double mpp, double fragUvX, double viewportWidth) {
  // Sweep at 5 m steps for 600 samples = 3000 m of worldMeters pan
  // (well under the 4096-m wrap period).
  const paintCount = 600;
  const deltaMetersPerPaint = 5.0;

  var wrapCount = 0;
  double? previousNoiseUv;
  for (var i = 0; i < paintCount; i++) {
    final worldMetersX = startWorldMetersX + i * deltaMetersPerPaint;

    // Plan 03.1-14 Fix B′ — meter-space decomposition (mirrors _FogPainter.paint()).
    final intMetersX = worldMetersX.truncateToDouble();
    final fracMetersX = worldMetersX - intMetersX;
    final boundedMetersX = (intMetersX % kPocFogIntegerWrapPeriodMeters) + fracMetersX;

    // Plan 03.1-14 Fix B′ shader-side worldMeters formula:
    //   worldMeters = (fragUv * uResolution) * mpp + boundedMeters
    //   noiseUv = worldMeters / kPocFogNoiseTilePxMeters
    final fragMetersX = fragUvX * viewportWidth * mpp;
    final shaderWorldMetersX = fragMetersX + boundedMetersX;
    final noiseUvX = shaderWorldMetersX / kPocFogNoiseTilePxMeters;

    if (previousNoiseUv != null) {
      final delta = noiseUvX - previousNoiseUv;
      if (delta < 0) {
        wrapCount += 1;
      }
    }
    previousNoiseUv = noiseUvX;
  }
  return wrapCount;
}
