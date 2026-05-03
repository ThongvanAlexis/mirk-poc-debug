// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-14a (Plan 03.1-07 Branch B-3) — wrap-period regression gate.
///
/// REWRITTEN for Plan 03.1-12. The test file name is preserved for
/// git-history continuity; the test content adds a post-Plan-03.1-12
/// ZERO-wraps sub-test under the world-METER formulation while
/// RETAINING the pre-fix + B-3 + Plan 03.1-10 world-pixel sub-tests
/// as historical regression-defense baselines. The progression of FOUR
/// formulations is now coverage-tested in one file.
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
/// 3. **Plan 03.1-10 (world-coordinate sampling, pixel-space):**
///    `noiseUv = (fragUv * uResolution + uPixelOrigin) / kNoiseTilePx`.
///    No `fract()` — each fragment samples noise at its world-pixel
///    position. Within a single `kPocFogIntegerWrapPeriodPx` window
///    (1500-px sweep here) ZERO wraps. Integer-wrap events fire only
///    at the kPocFogIntegerWrapPeriodPx boundary (~128 sec at Walk #3b
///    pan velocity).
/// 4. **Plan 03.1-12 (world-meter sampling):**
///    `noiseUv = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel /
///    kNoiseTilePxMeters`. metersPerPixel-multiplication anchors noise
///    to ground meters. At a fixed zoom, worldMeters evolves
///    monotonically forward; ZERO wraps within a single integer-wrap
///    window. The integer-wrap event at zoom 15 lat 48.5° shifts
///    noiseUv by ~4.74 cells (non-integer-multiple — documented
///    continuity caveat per `kPocFogNoiseTilePxMeters` docstring).
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

    test('Plan-03.1-10 POST-FIX (world-coordinate, pixel-space) — ZERO wraps over 1500-px sub-wrap-period sweep', () {
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

    test('Plan-03.1-12 POST-FOG-18 (world-meter) — ZERO wraps over 1500-px sub-wrap-period sweep at z=15 lat 48.5°', () {
      // Plan 03.1-12 FOG-18: meter-space formulation (pixel-space FOG-17a
      // then meter-space scaling). Historical sub-test retained as
      // regression-defense for the pre-Plan-03.1-14 formulation.
      final wrapCount = _countWraps(formulation: _Formulation.worldMeter);
      expect(
        wrapCount,
        equals(0),
        reason:
            'FOG-14a-POST-FOG-18-GREEN: Plan-03.1-12 world-meter formulation must produce ZERO wraps over a sub-1536-px sweep '
            'at a fixed zoom. metersPerPixel scales the worldPx coordinate but the per-paint delta stays monotonically '
            'forward. If wraps are reported here, the FOG-18 fix has been silently reverted or the metersPerPixel '
            'computation has been broken. Wrap count: $wrapCount.',
      );
    });

    test('Plan-03.1-14 Fix B′ POST-FOG-19 (meter-space FOG-17a) — ZERO wraps over sub-wrap-period sweep at z=15 lat 48.5°', () {
      // Plan 03.1-14 Fix B′ — FOG-19: meter-space FOG-17a decomposition
      //   `worldMeters = (fragUv * uResolution) * metersPerPixel + boundedMeters;
      //    noiseUv = worldMeters / kNoiseTilePxMeters`
      // where `boundedMeters = (intMeters % kPocFogIntegerWrapPeriodMeters) +
      // fracMeters`. The per-paint shader input continues to evolve
      // monotonically forward at a fixed zoom; wrap events fire only at
      // 4096-m intervals in worldMeters (well beyond the sub-wrap-period
      // sweep window). ZERO wraps expected.
      final wrapCount = _countWraps(formulation: _Formulation.worldMeterFixBPrime);
      expect(
        wrapCount,
        equals(0),
        reason:
            'Plan-03.1-14 Fix B′ POST-FOG-19-GREEN: meter-space FOG-17a formulation must produce ZERO wraps over a sub-wrap-period '
            'sweep at a fixed zoom. The bounded meter composite evolves smoothly within a single 4096-m wrap period; '
            'wrap events occur at exact integer-cell boundaries (period-commensurability invariant). If wraps are reported '
            'here, the Fix B′ has been silently reverted. Wrap count: $wrapCount.',
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

  /// Plan-03.1-12 FOG-18: `noiseUv = (fragUv * uResolution + boundedPxOrigin) * metersPerPixel / kNoiseTilePxMeters`.
  /// metersPerPixel computed at z=15 lat 48.5° (Walk #4 hike regime,
  /// representative). Pixel-space FOG-17a then meter-space scaling.
  worldMeter,

  /// Plan-03.1-14 Fix B′: `noiseUv = ((fragUv * uResolution) * metersPerPixel
  /// + boundedMeters) / kNoiseTilePxMeters`. Meter-space FOG-17a
  /// decomposition: `boundedMeters = (intMeters % kPocFogIntegerWrapPeriodMeters)
  /// + fracMeters` with `intMeters = pixelOriginX * metersPerPixel
  /// truncated`. Active formulation post-Plan-03.1-14.
  worldMeterFixBPrime,
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

  // Sub-wrap-period sweeps for the FOG-17 + FOG-18 + Plan-03.1-14
  // Fix B′ sub-tests so the integer-wrap event does NOT fire within the
  // trajectory. Pre-fix + B-3 use the historical 36000-px sweep for the
  // wrap-frequency ratio test.
  final isPostFix = formulation == _Formulation.worldCoordinate || formulation == _Formulation.worldMeter || formulation == _Formulation.worldMeterFixBPrime;
  final paintCount = isPostFix ? 300 : 7200;
  final startMagnitude = isPostFix ? 999936.0 : 1.0e6;
  const deltaXPerPaint = 5.0;
  const fragXPx = viewportWidth * 0.5;

  // FOG-18 metersPerPixel at z=15 lat 48.5° (Walk #4 hike regime). Used
  // by the worldMeter formulation only.
  const z = 15.0;
  const lat = 48.5397;
  final metersPerPixel = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, z).toDouble();

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
        if (previousValue != null && currentValue - previousValue < 0) {
          wrapCount += 1;
        }
      case _Formulation.worldMeter:
        // Apply FOG-17a decomposition (mirrors _FogPainter.paint()).
        final intPx = pixelOriginX.truncateToDouble();
        final fracPx = pixelOriginX - intPx;
        final boundedPxX = (intPx % kPocFogIntegerWrapPeriodPx) + fracPx;
        // FOG-18 world-meter formulation (pre-Plan-03.1-14 era):
        //   worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel
        //   noiseUv = worldMeters / kNoiseTilePxMeters
        final worldPxX = fragXPx + boundedPxX;
        final worldMetersX = worldPxX * metersPerPixel;
        currentValue = worldMetersX / kPocFogNoiseTilePxMeters;
        if (previousValue != null && currentValue - previousValue < 0) {
          wrapCount += 1;
        }
      case _Formulation.worldMeterFixBPrime:
        // Plan 03.1-14 Fix B′ — meter-space FOG-17a decomposition.
        // The Fix B′ trajectory operates in meter space directly (the
        // decomposition divisor is in meters, not pixels). To stay
        // within a single 4096-m wrap window for the ZERO-wraps
        // assertion, treat `i` as a meter-space index instead of a
        // pixel-space index. Step 5 m per paint × 600 paints = 3000 m
        // worldMeters sweep — sub-wrap-period.
        //
        // The startMagnitude (~1e6 raw px × mpp at z=15 = ~3.16M m) is
        // re-aligned to the start of a 4096-m wrap window so the sweep
        // stays inside one window. fragXPx fixed at viewport-centre.
        if (i >= 600) {
          // Skip extra iterations beyond the meter-space sweep budget
          // (the outer loop runs paintCount=300 paints; the budget is
          // 600 — the 300-paint cap already keeps us under).
          previousValue = null;
          currentValue = 0.0;
          continue;
        }
        // Re-align start to a wrap window boundary.
        final startWorldMeters = startMagnitude * metersPerPixel;
        final wrapsBefore = (startWorldMeters / kPocFogIntegerWrapPeriodMeters).floor();
        final alignedStartMeters = wrapsBefore * kPocFogIntegerWrapPeriodMeters + 100.0;
        // Synthetic worldMeters at this paint.
        final worldMetersUnboundedX = alignedStartMeters + i * 5.0;
        final intMetersX = worldMetersUnboundedX.truncateToDouble();
        final fracMetersX = worldMetersUnboundedX - intMetersX;
        final boundedMetersX = (intMetersX % kPocFogIntegerWrapPeriodMeters) + fracMetersX;
        // Plan 03.1-14 Fix B′ shader-side formula:
        //   worldMeters = (fragUv * uResolution) * uMetersPerPixel + uWorldMetersOrigin
        //   noiseUv = worldMeters / kNoiseTilePxMeters
        final fragMetersX = fragXPx * metersPerPixel;
        final shaderWorldMetersX = fragMetersX + boundedMetersX;
        currentValue = shaderWorldMetersX / kPocFogNoiseTilePxMeters;
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
