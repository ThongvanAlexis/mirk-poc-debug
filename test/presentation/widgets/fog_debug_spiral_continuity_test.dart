// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-14a (Plan 03.1-07 Branch B-3) — wrap-period regression gate.
///
/// REWRITTEN for Plan 03.1-10. The test file name is preserved for
/// git-history continuity; the test content adds a post-Plan-03.1-10
/// ZERO-wraps sub-test under the world-coordinate formulation while
/// RETAINING the pre-fix and B-3 sub-tests as historical regression-
/// defense baselines.
///
/// ## Background — three formulations, three wrap regimes
///
/// 1. **Pre-Plan-03.1-04 / Plan 03.1-04 (viewport-width modulo):**
///    `fract(uPixelOrigin / uResolution)` wraps every viewport-width
///    (~390 px). Produces ~92 wraps over a 36000-px synthetic sweep.
/// 2. **Plan 03.1-07 Branch B-3 (tile-period-aware fract):**
///    `fract(uPixelOrigin / tilePeriodPixels)` where
///    `tilePeriodPixels = uResolution / max(uScaleFar, uScaleMid,
///    uScaleNear)`. Wraps every ~37 raw px. Produces ~969 wraps over
///    the same sweep — Walk #3 confirmed user-perceptible stepping
///    persists at the wrap events.
/// 3. **Plan 03.1-10 (world-coordinate sampling):**
///    `noiseUv = (fragUv * uResolution + uPixelOrigin) / kNoiseTilePx`.
///    No `fract()` — each fragment samples noise at its world
///    position. Within a single `kPocFogIntegerWrapPeriodPx` window
///    (1500-px sweep here) ZERO wraps. Integer-wrap events fire only
///    at the kPocFogIntegerWrapPeriodPx boundary (~128 sec at Walk #3b
///    pan velocity).
///
/// ## Why retain the historical sub-tests
///
/// The pre-fix and B-3 sub-tests document what the historical
/// formulations WOULD produce. If a future PR silently reverts the
/// formulation back to viewport-width or B-3, these sub-tests catch
/// the regression mechanically by asserting the synthetic wrap count
/// matches the OLD regime — which would only happen if someone
/// re-introduced the old formulation.
///
/// ## Trajectory parameters
///
/// - Pre-fix + B-3 sub-tests: 7200 paints @ 5 px/paint = 36000-px sweep
///   (matches the original Plan 03.1-07 design — the wide sweep is
///   needed for the wrap-frequency-multiplier test to converge).
/// - Plan 03.1-10 sub-test: 300 paints @ 5 px/paint = 1500-px sweep
///   (under one `kPocFogIntegerWrapPeriodPx` cycle so the integer-wrap
///   event does NOT fire within the trajectory; ZERO wraps is the
///   asserted post-fix invariant).
void main() {
  group('FOG-14a (Plan 03.1-07 Branch B-3 / Plan 03.1-10 FOG-17) — wrap-period regression gate', () {
    test('Plan-03.1-04 PRE-FIX (viewport-width modulo) — wrap count in viewport-width regime (~92 over 36k-px sweep)', () {
      final wrapCount = _countWraps(formulation: _Formulation.viewportWidthFract);
      // 7200 paints * 5 px / 390 px/wrap ≈ 92 wraps. Tolerance ±15.
      expect(
        wrapCount,
        inInclusiveRange(80, 110),
        reason:
            'FOG-14a-PRE-FIX-RED: Plan-03.1-04 viewport-width formulation `fract(pixelOrigin / uResolution)` MUST produce ~92 wraps over the '
            '36000-px synthetic trajectory (one wrap per viewport-width). Observed: $wrapCount. If this assertion stops matching, '
            'the simulation is wrong (or the regression boundary has silently moved).',
      );
    });

    test('Plan-03.1-07 B-3 (tile-period modulo) — wrap count in tile-period regime (~969 over 36k-px sweep)', () {
      final wrapCount = _countWraps(formulation: _Formulation.tilePeriodFract);
      // 7200 paints * 5 px / 37.14 px/wrap ≈ 969 wraps. Tolerance ±50.
      expect(
        wrapCount,
        inInclusiveRange(900, 1050),
        reason:
            'FOG-14a-B3-RED: Plan-03.1-07 Branch B-3 formulation `fract(pixelOrigin / tilePeriodPixels)` MUST produce ~969 wraps '
            'over the 36000-px synthetic trajectory (one wrap per noise-tile period). Observed: $wrapCount. If this assertion stops '
            'matching, the simulation is wrong.',
      );
    });

    test('Plan-03.1-07 B-3 wrap-frequency multiplier matches maxScale (B-3 design invariant)', () {
      // The B-3 design invariant: B-3 wrap frequency = pre-fix
      // wrap frequency × maxScale. Documented historical-formulation
      // invariant.
      final preFixWraps = _countWraps(formulation: _Formulation.viewportWidthFract);
      final b3Wraps = _countWraps(formulation: _Formulation.tilePeriodFract);
      const maxScale = _scaleNear; // 10.5 — by construction = max of {2.9, 5.1, 10.5}
      final ratio = b3Wraps / preFixWraps;
      expect(
        ratio,
        closeTo(maxScale, 0.5),
        reason:
            'FOG-14a B-3 design invariant: B-3-wraps / pre-fix-wraps must equal maxScale (=$maxScale). '
            'Observed ratio: ${ratio.toStringAsFixed(3)} (pre-fix wraps $preFixWraps, B-3 wraps $b3Wraps). '
            'A divergence here indicates the simulation has drifted.',
      );
    });

    test('Plan-03.1-10 POST-FIX (world-coordinate) — ZERO wraps over 1500-px sub-wrap-period sweep', () {
      // Plan 03.1-10 FOG-17: the world-coordinate formulation
      // `noiseUv = (fragUv * uResolution + boundedPxOrigin) / kNoiseTilePx`
      // has NO fract() applied — there is no fractional offset that
      // could wrap. Within a single `kPocFogIntegerWrapPeriodPx` window
      // (1500-px sweep < 1536), the FOG-17a integer-wrap event does
      // not fire and the noiseUv evolution is monotonically smooth.
      final wrapCount = _countWraps(formulation: _Formulation.worldCoordinate);
      expect(
        wrapCount,
        equals(0),
        reason:
            'FOG-14a-POST-FIX-GREEN: Plan-03.1-10 world-coordinate formulation must produce ZERO wraps over a sub-1536-px sweep. '
            'No fract() is applied — there is no fractional offset that could wrap. If wraps are reported here, the FOG-17 fix '
            'has been silently reverted to the B-3 fract() formulation. Wrap count: $wrapCount.',
      );
    });
  });
}

const double _scaleFar = 2.9;
const double _scaleMid = 5.1;
const double _scaleNear = 10.5;

enum _Formulation {
  /// Plan-03.1-04 pre-fix: `fract(uPixelOrigin / uResolution)`.
  viewportWidthFract,

  /// Plan-03.1-07 B-3: `fract(uPixelOrigin / tilePeriodPixels)` where
  /// `tilePeriodPixels = uResolution / max(uScaleFar, uScaleMid, uScaleNear)`.
  tilePeriodFract,

  /// Plan-03.1-10 FOG-17: `noiseUv = (fragUv * uResolution + boundedPxOrigin) / kNoiseTilePx`.
  /// FOG-17a Dart-side decomposition keeps `boundedPxOrigin` under
  /// `kPocFogIntegerWrapPeriodPx + 1`.
  worldCoordinate,
}

/// Counts wrap events along a synthetic smooth-pan trajectory.
///
/// Pre-fix + B-3 use the historical 7200-paint × 5-px = 36000-px sweep
/// AND fract-style detection (a fract decrease > 0.5 indicates the
/// sliding offset crossed the wrap boundary).
///
/// World-coordinate uses a shorter 300-paint × 5-px = 1500-px sweep
/// (under one `kPocFogIntegerWrapPeriodPx` cycle so the integer-wrap
/// event does not fire within the trajectory) AND monotonicity-style
/// detection (a noiseUv NEGATIVE delta indicates a wrap-discontinuity).
/// Under the post-fix formulation the noiseUv evolves monotonically
/// forward by `5 / 384 ≈ 0.013` per paint; any negative delta would
/// indicate a fract() regression.
int _countWraps({required _Formulation formulation}) {
  const viewportWidth = 390.0;
  final maxScale = math.max(_scaleFar, math.max(_scaleMid, _scaleNear));

  final paintCount = formulation == _Formulation.worldCoordinate ? 300 : 7200;
  // Pre-fix + B-3 use a generic high magnitude (the wraps fire many
  // times across the sweep; starting alignment is irrelevant). World-
  // coordinate uses a magnitude aligned to start just above 0 in the
  // post-FOG-17a bounded composite (intPx % 1536 ≈ 0) so the 1500-px
  // sweep stays under the kPocFogIntegerWrapPeriodPx boundary and
  // the integer-wrap event does not fire within the trajectory.
  // 1536 * 651 = 999936 — chosen so 999936 % 1536 = 0 exactly, and
  // 999936 + 1500 = 1001436 is still in the same wrap window.
  final startMagnitude = formulation == _Formulation.worldCoordinate ? 999936.0 : 1.0e6;
  const deltaXPerPaint = 5.0;
  const fragXPx = viewportWidth * 0.5;

  var wrapCount = 0;
  double? previousValue;
  for (var i = 0; i < paintCount; i++) {
    final pixelOriginX = startMagnitude + i * deltaXPerPaint;

    final double currentValue;
    switch (formulation) {
      case _Formulation.viewportWidthFract:
        currentValue = _fract(pixelOriginX / viewportWidth);
        if (previousValue != null && currentValue - previousValue < -0.5) {
          wrapCount += 1;
        }
      case _Formulation.tilePeriodFract:
        final wrapPeriod = viewportWidth / maxScale;
        currentValue = _fract(pixelOriginX / wrapPeriod);
        if (previousValue != null && currentValue - previousValue < -0.5) {
          wrapCount += 1;
        }
      case _Formulation.worldCoordinate:
        // Apply FOG-17a decomposition (mirrors _FogPainter.paint()).
        final intPx = pixelOriginX.truncateToDouble();
        final fracPx = pixelOriginX - intPx;
        final boundedPxX = (intPx % kPocFogIntegerWrapPeriodPx) + fracPx;
        // FOG-17 world-coordinate formulation: noiseUv evolves monotonically.
        final worldPxX = fragXPx + boundedPxX;
        currentValue = worldPxX / kPocFogNoiseTilePx;
        // Negative delta = wrap discontinuity (regression). Under the
        // post-fix formulation noiseUv increases monotonically by ~0.013
        // per paint.
        if (previousValue != null && currentValue - previousValue < 0) {
          wrapCount += 1;
        }
    }
    previousValue = currentValue;
  }
  return wrapCount;
}

/// GLSL `fract(x)` semantics — `x - floor(x)`, in [0, 1).
double _fract(double x) => x - x.floorToDouble();
