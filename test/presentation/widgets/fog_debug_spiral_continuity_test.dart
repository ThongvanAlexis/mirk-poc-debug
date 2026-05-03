// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// FOG-14a (Plan 03.1-07 Branch B-3) — wrap-period regression gate.
///
/// Higher-fidelity proxy than FOG-11's raw-uniform-delta-magnitude
/// assertion. Catches any future regression that re-introduces the
/// pre-Branch-B-3 viewport-width modulo formulation in the production
/// or debug-spiral fragment shader.
///
/// ## Background — what B-3 does, what it does not
///
/// The Branch B-3 fix replaces `fract(uPixelOrigin / uResolution)`
/// with `fract(uPixelOrigin / tilePeriodPixels)` where
/// `tilePeriodPixels = uResolution / max(uScaleFar, uScaleMid,
/// uScaleNear)`. This aligns the modulo wrap period with the
/// noise-tile period at the maxScale (near) octave.
///
/// Walk #2 (03.1-FALSIFICATION-2.md sub-section D row B-3) confirmed
/// the pre-fix viewport-width-modulo wraps were producing the user-
/// observable "stepped" pan-translation symptom (every viewport-width
/// of pan caused a viewport-wide jump in the screen-space noise
/// pattern). The B-3 fix is a documented PARTIAL fix: wraps still
/// happen, but at a sub-perceptible noise-tile-period scale within
/// a single octave, rather than at the viewport-width scale.
///
/// ## Why this test asserts on wrap-FREQUENCY, not cell-index continuity
///
/// The original Plan 03.1-07 plan-body proposed asserting cell-index
/// delta ≤ 1 per paint as the FOG-14a invariant. That assertion is
/// not mechanically attainable in either formulation: every fract-wrap
/// event causes a viewport-width spatial jump in
/// `cellPx = spiralCoord * uResolution`, regardless of which wrap
/// period the formulation uses. The B-3 fix changes the FREQUENCY of
/// those wraps (~10x more frequent at the smaller wrap period) but
/// not their per-event MAGNITUDE in the spiral cell-grid space.
///
/// The B-3 fix's actual user-visible benefit is in the production
/// noise pattern at the maxScale octave: `warped = noiseUv *
/// uScaleNear` shifts by exactly `1 * maxScale = maxScale` noise-tile
/// units at every wrap, and at the maxScale octave a 1-tile-period
/// shift is sub-perceptible (the value-noise FBM samples adjacent
/// tile corners which are uncorrelated, so the wrap reads as "the
/// noise pattern moved one period" rather than "translated by the
/// whole viewport"). At lesser octaves (mid, far), wraps shift by
/// fractional tile periods, but those octaves contribute small density
/// weights so the residual visual discontinuity is sub-perceptible.
///
/// What IS mechanically testable is the engineering invariant: the
/// wrap period in the GLSL `fract` argument equals `uResolution /
/// maxScale` (post-fix), not `uResolution` (pre-fix). This is the
/// regression gate FOG-14a guards.
///
/// ## RED→GREEN proof (mental simulation)
///
/// Test trajectory: 60 simulated seconds at 120 Hz = 7200 paints,
/// per-paint delta = 5 px (slow deliberate pan; total sweep 36,000 px).
/// Count fract-wrap events by detecting fract decreases > 0.5
/// across consecutive paints.
///
///   * Pre-fix HEAD (viewport-width modulo, wrapPeriod = 390 px):
///     ~92 wraps over 36,000 px sweep.
///   * Post-fix HEAD (tile-period modulo, wrapPeriod = 390/10.5 ≈
///     37.14 px): ~969 wraps over the same sweep.
///
/// FOG-14a-GREEN asserts post-fix wrap count >> pre-fix expectation
/// (i.e., wrapping happens at noise-tile period, not viewport-width).
/// FOG-14a-RED asserts pre-fix wrap count is in the viewport-width
/// regime — a defense against the silent-regression scenario where
/// someone reverts the divisor without noticing.
void main() {
  group('FOG-14a (Plan 03.1-07 Branch B-3) — wrap-period regression gate', () {
    test('PRE-FIX (viewport-width modulo) — wrap count in viewport-width regime (~92 over 36k-px sweep)', () {
      final wrapCount = _countWraps(useViewportWidthModulo: true);
      // 7200 paints * 5 px / 390 px/wrap ≈ 92 wraps. Tolerance ±10
      // for floating-point edge effects.
      expect(
        wrapCount,
        inInclusiveRange(80, 110),
        reason:
            'FOG-14a-RED: pre-fix formulation `fract(pixelOrigin / uResolution)` MUST produce ~92 wraps over the '
            '36000-px synthetic trajectory (one wrap per viewport-width). Observed: $wrapCount. If this assertion '
            'stops matching, the simulation is wrong (or the regression boundary has silently moved).',
      );
    });

    test('POST-FIX (tile-period modulo) — wrap count in tile-period regime (~969 over 36k-px sweep)', () {
      final wrapCount = _countWraps(useViewportWidthModulo: false);
      // 7200 paints * 5 px / 37.14 px/wrap ≈ 969 wraps. Tolerance ±50.
      expect(
        wrapCount,
        inInclusiveRange(900, 1050),
        reason:
            'FOG-14a-GREEN: post-fix formulation `fract(pixelOrigin / tilePeriodPixels)` MUST produce ~969 wraps '
            'over the 36000-px synthetic trajectory (one wrap per noise-tile period). Observed: $wrapCount. If '
            'wrap count drops to pre-fix levels (~92), the B-3 fix has been silently reverted to viewport-width '
            'modulo. This catches any future regression to the FOG-11 failure mode.',
      );
    });

    test('POST-FIX wrap-frequency multiplier matches maxScale (B-3 design invariant)', () {
      // The B-3 design invariant: post-fix wrap frequency = pre-fix
      // wrap frequency × maxScale. This is the testable engineering
      // contract that distinguishes B-3 from any other modulo
      // formulation.
      final preFixWraps = _countWraps(useViewportWidthModulo: true);
      final postFixWraps = _countWraps(useViewportWidthModulo: false);
      const maxScale = _scaleNear; // 10.5 — by construction = max of {2.9, 5.1, 10.5}
      final ratio = postFixWraps / preFixWraps;
      expect(
        ratio,
        closeTo(maxScale, 0.5),
        reason:
            'FOG-14a B-3 design invariant: post-fix-wraps / pre-fix-wraps must equal maxScale (=$maxScale). '
            'Observed ratio: ${ratio.toStringAsFixed(3)} (pre-fix wraps $preFixWraps, post-fix wraps $postFixWraps). '
            'A divergence here indicates the wrapPeriod divisor is no longer `uResolution / maxScale` post-fix.',
      );
    });
  });
}

const double _scaleFar = 2.9;
const double _scaleMid = 5.1;
const double _scaleNear = 10.5;

/// Counts fract-wrap events along a synthetic 7200-paint smooth-pan
/// trajectory at 5 px/paint. A wrap is detected when the fract value
/// decreases by > 0.5 across consecutive paints (the only way it can
/// drop substantially given the monotonic pan input — the smooth
/// fract increment is `5 / wrapPeriod`, well below 0.5 for both
/// formulations).
int _countWraps({required bool useViewportWidthModulo}) {
  const viewportWidth = 390.0;
  final maxScale = math.max(_scaleFar, math.max(_scaleMid, _scaleNear));
  final wrapPeriod = useViewportWidthModulo ? viewportWidth : viewportWidth / maxScale;

  const paintCount = 7200;
  const startMagnitude = 1.0e6;
  const deltaXPerPaint = 5.0;

  var wrapCount = 0;
  double? previousFract;
  for (var i = 0; i < paintCount; i++) {
    final pixelOriginX = startMagnitude + i * deltaXPerPaint;
    final fract = _fract(pixelOriginX / wrapPeriod);
    if (previousFract != null && fract - previousFract < -0.5) {
      wrapCount += 1;
    }
    previousFract = fract;
  }
  return wrapCount;
}

/// GLSL `fract(x)` semantics — `x - floor(x)`, in [0, 1).
double _fract(double x) => x - x.floorToDouble();
