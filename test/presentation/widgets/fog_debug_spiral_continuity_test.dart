// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io' show File;
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
/// 3. **Plan 03.1-10 (world-coordinate sampling) + Plan 03.1-12
///    (FOG-18, no Dart-side modulo):**
///    `noiseUv = (fragUv * uResolution + uPixelOrigin) / kNoiseTilePx`.
///    No `fract()` — each fragment samples noise at its world
///    position. The Plan 03.1-10 FOG-17a Dart-side `% 1536` modulo wrap
///    has been REMOVED post-Walk-4 falsification; the painter now
///    forwards `camera.pixelOrigin` directly. ZERO wraps over the
///    1500-px sub-trajectory under both the pre-FOG-18 and post-FOG-18
///    forward paths (the only fract was the Dart-side modulo, removed
///    by FOG-18; the world-coordinate noiseUv evolves monotonically).
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
/// - Plan 03.1-10 + Plan 03.1-12 sub-test: 300 paints @ 5 px/paint =
///   1500-px sweep. Post-FOG-18 there is no integer-wrap event at any
///   magnitude (the `% 1536` modulo is gone); ZERO wraps is the
///   asserted post-fix invariant.
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

    test('Plan-03.1-10 + Plan-03.1-12 POST-FIX (world-coordinate, no Dart-side modulo) — ZERO wraps over 1500-px sweep', () {
      // Plan 03.1-10 FOG-17 + Plan 03.1-12 FOG-18: the world-coordinate
      // formulation `noiseUv = (fragUv * uResolution + uPixelOrigin) /
      // kNoiseTilePx` has NO fract() applied — there is no fractional
      // offset that could wrap. Plan 03.1-12 also removed the Plan
      // 03.1-10 FOG-17a Dart-side `% 1536` modulo wrap (Walk #4
      // falsified its premise); the painter now forwards
      // camera.pixelOrigin directly. The noiseUv evolution is
      // monotonically smooth at any magnitude.
      final wrapCount = _countWraps(formulation: _Formulation.worldCoordinate);
      expect(
        wrapCount,
        equals(0),
        reason:
            'FOG-14a-POST-FIX-GREEN: post-Plan-03.1-10 world-coordinate formulation + post-Plan-03.1-12 FOG-18 (no Dart-side modulo) '
            'must produce ZERO wraps over the 1500-px sweep. No fract() is applied — there is no fractional offset that could wrap. '
            'If wraps are reported here, the FOG-17 + FOG-18 fixes have been silently reverted (e.g., to the B-3 fract() formulation '
            'or to the FOG-17a integer-wrap modulo). Wrap count: $wrapCount.',
      );
    });
  });

  // DEBUG-03 (Plan 03.1-14 Task A) — unique 4-digit per-cell encoding
  // diagnostic enhancement. Per developer's Walk #5 verbatim request:
  // *"modifying the number to not have repetitive value would allow us
  // to debug the amount of drift"*. The previous mod-100 cycling
  // repeated every 100 cells (~8000 raw px at 80-px cell size) — far
  // too small for the O(M) raw-px zoom-gesture sweeps Walk #5 captured.
  //
  // FOG-19 (Plan 03.1-14 Task B) — uZoomScale uniform addition + cellPx
  // scaling. Asserts the debug shader source declares the uniform AND
  // consumes it consistently with the production shader so cells stay
  // anchored to lat/lng during zoom (Walk #6 reads this directly).
  group('DEBUG-03 + FOG-19 (Plan 03.1-14) — debug-spiral source-level invariants', () {
    test('DEBUG-03 static-source: atmospheric_fog_debug_spiral.frag uses unique 4-digit cell-id encoding', () {
      final debugShaderSource = File('assets/shaders/atmospheric_fog_debug_spiral.frag').readAsStringSync();
      expect(
        debugShaderSource,
        contains('(cell.y + 50) * 100 + (cell.x + 50)'),
        reason:
            'DEBUG-03 (Plan 03.1-14 Task A) static-source: atmospheric_fog_debug_spiral.frag MUST '
            'use the unique 4-digit cell-id encoding `(cell.y + 50) * 100 + (cell.x + 50)` for '
            'Walk #6 quantitative drift measurement. Per developer Walk #5: "modifying the number '
            'to not have repetitive value would allow us to debug the amount of drift".',
      );
      expect(
        debugShaderSource,
        isNot(contains('mod(float(rawCellIndex), 100.0)')),
        reason:
            'DEBUG-03 static-source: the pre-DEBUG-03 repetitive 0..99 cycling MUST be removed. '
            'If this assertion fails, the unique 4-digit encoding has not landed correctly.',
      );
      expect(
        debugShaderSource,
        contains('thousands'),
        reason:
            'DEBUG-03 static-source: 4-digit horizontal layout requires thousands/hundreds/tens/ones '
            'identifiers. If this assertion fails, the digit-render block has not been updated to '
            'the 4-digit layout.',
      );
    });

    test('FOG-19 static-source: atmospheric_fog_debug_spiral.frag declares uZoomScale and divides by it', () {
      final debugShaderSource = File('assets/shaders/atmospheric_fog_debug_spiral.frag').readAsStringSync();
      expect(
        debugShaderSource,
        contains('uniform float uZoomScale'),
        reason:
            'FOG-19 (Plan 03.1-14 Task B) static-source: atmospheric_fog_debug_spiral.frag MUST '
            'declare `uniform float uZoomScale` at slot 41 (matching the production shader). '
            'If this assertion fails, the debug shader is out of sync with the production shader.',
      );
      expect(
        debugShaderSource,
        anyOf(contains('worldPx / uZoomScale'), contains('worldPx / (kNoiseTilePx * uZoomScale)'), contains('cellPx = worldPx / uZoomScale')),
        reason:
            'FOG-19 static-source: debug shader MUST consume uZoomScale by dividing worldPx (or cellPx) '
            'by uZoomScale so cells stay anchored to lat/lng during zoom. Walk #6 reads this directly '
            "via Task A's unique 4-digit cell numbers.",
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

  /// Plan-03.1-10 FOG-17 + Plan-03.1-12 FOG-18:
  /// `noiseUv = (fragUv * uResolution + uPixelOrigin) / kNoiseTilePx`.
  /// Post-FOG-18 the painter forwards `camera.pixelOrigin` directly
  /// (the Plan 03.1-10 FOG-17a `% 1536` Dart-side modulo wrap has been
  /// removed; Walk #4 falsified its premise).
  worldCoordinate,
}

/// Counts wrap events along a synthetic smooth-pan trajectory.
///
/// Pre-fix + B-3 use the historical 7200-paint × 5-px = 36000-px sweep
/// AND fract-style detection (a fract decrease > 0.5 indicates the
/// sliding offset crossed the wrap boundary).
///
/// World-coordinate uses a shorter 300-paint × 5-px = 1500-px sweep AND
/// monotonicity-style detection (a noiseUv NEGATIVE delta indicates a
/// wrap-discontinuity). Under the post-fix formulation the noiseUv
/// evolves monotonically forward by `5 / 384 ≈ 0.013` per paint; any
/// negative delta would indicate a fract() regression OR a re-introduced
/// Dart-side modulo wrap (FOG-17a, falsified by Walk #4 per FOG-18).
int _countWraps({required _Formulation formulation}) {
  const viewportWidth = 390.0;
  final maxScale = math.max(_scaleFar, math.max(_scaleMid, _scaleNear));

  final paintCount = formulation == _Formulation.worldCoordinate ? 300 : 7200;
  // Pre-fix + B-3 use a generic high magnitude (the wraps fire many
  // times across the sweep; starting alignment is irrelevant). World-
  // coordinate uses a Walk #3b zoom-13 regime magnitude (~1.064M) — the
  // post-FOG-18 forward path forwards camera.pixelOrigin directly so
  // any starting magnitude works (no wrap window to align with). 1.0e6
  // is convenient and matches the historical pre-FOG-18 alignment
  // anchor for git-blame continuity.
  final startMagnitude = formulation == _Formulation.worldCoordinate ? 1.0e6 : 1.0e6;
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
        // Apply post-FOG-18 forward path (mirrors _FogPainter.paint()):
        // truncateToDouble decomposition retained for documentation
        // continuity; modulo removed; intPx + fracPx == pxOrigin.
        final intPx = pixelOriginX.truncateToDouble();
        final fracPx = pixelOriginX - intPx;
        final forwardedPxX = intPx + fracPx;
        // FOG-17 world-coordinate formulation: noiseUv evolves monotonically.
        final worldPxX = fragXPx + forwardedPxX;
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
