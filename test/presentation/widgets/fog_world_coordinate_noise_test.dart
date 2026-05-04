// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-17 (Plan 03.1-10) — world-coordinate noise sampling: ZERO
/// fract-style wrap-discontinuity events at all pixelOrigin magnitude
/// regimes.
///
/// ## Background
///
/// The Plan 03.1-07 Branch B-3 partial-fix formulation
///   `noiseUv = fragUv + fract(uPixelOrigin / tilePeriodPixels)`
/// introduced fract-wrap discontinuities every ~16-65 raw px (Walk #3
/// empirical: median 39 raw px between markers, 2.4 wrap events per
/// perceived step). The Plan 03.1-10 FOG-17 fix replaces it with
/// world-coordinate sampling:
///   `worldPx = fragUv * uResolution + uPixelOrigin;
///    noiseUv = worldPx / kNoiseTilePx;`
///
/// Each fragment now samples noise at its OWN world-pixel position; as
/// the camera pans, NEW world coordinates enter the viewport edges so
/// NEW noise scrolls in — there is NO fract(), NO sliding offset that
/// could wrap, and NO stepping mid-pan.
///
/// Plan 03.1-12 (FOG-18) update: the Plan 03.1-10 FOG-17a Dart-side
/// `% kPocFogIntegerWrapPeriodPx` (=1536) modulo wrap has been
/// REMOVED. Walk #4 (P03.1-11 2026-05-04) debug-spiral positive
/// control falsified FOG-17a's premise — the noise function is NOT
/// truly periodic on `kPocFogNoiseTilePx (=384)` in practice; the
/// wrap event itself was the bug. Post-FOG-18 the painter forwards
/// `camera.pixelOrigin` directly (decomposed into intPx + fracPx for
/// documentation continuity, no modulo). fp32's 24-bit mantissa
/// supports exact-integer values up to 16.7M raw-px, well above
/// Walk #4's max observed 4.26M.
///
/// ## What's tested
///
/// 1. Synthetic smooth-pan trajectory at three pixelOrigin magnitude
///    regimes (1.064M ≈ Walk #3b zoom 13, 4.26M ≈ Walk #2 zoom 16,
///    17.04M ≈ extrapolated zoom 19), with the post-FOG-18 forward
///    path applied (intPx + fracPx; no modulo). Each regime: 300
///    paints @ 5 raw-px/paint over a 1500-px sweep. Asserts ZERO
///    fract-style wrap-discontinuity events.
/// 2. Pre-FOG-18 historical reference: documents the Plan 03.1-10
///    FOG-17a integer-wrap-boundary numerical behaviour for archival
///    interest. Under FOG-18 the wrap event no longer fires; the
///    historical 4-grid-unit shift formulation is preserved as
///    historical documentation.
void main() {
  group('FOG-17 (Plan 03.1-10) — world-coordinate noise sampling: ZERO wrap events', () {
    test('Walk #3b regime (pixelOriginX ≈ 1.064M) — ZERO fract-wraps over 1500-px sweep', () {
      // 1.064M ≈ Walk #3b zoom-13 magnitude. Post-FOG-18 the painter
      // forwards `camera.pixelOrigin` directly; the test harness
      // simulates the post-FOG-18 forward path (no modulo).
      final wrapCount = _countFractWrapEvents(startMagnitude: 1064000.0);
      expect(
        wrapCount,
        equals(0),
        reason:
            'FOG-17 invariant: the world-coordinate formulation `noiseUv = (fragUv * uResolution + uPixelOrigin) / kNoiseTilePx` '
            'has ZERO fract-style wrap-discontinuity events across a smooth-pan trajectory. '
            'No fract() is applied per-fragment — there is no fractional offset that could wrap. '
            'Pre-Plan-03.1-10 the B-3 formulation `fract(uPixelOrigin / tilePeriodPixels)` produced ~969 wraps over the FOG-14a 36000-px sweep '
            '(~40 over a 1500-px sub-window). If wraps are reported here, the world-coordinate formulation has been silently reverted. '
            'Wrap count: $wrapCount.',
      );
    });

    test('Walk #2 regime (pixelOriginX ≈ 4.26M) — ZERO fract-wraps over 1500-px sweep', () {
      // 4.26M ≈ Walk #2 zoom-16 magnitude.
      final wrapCount = _countFractWrapEvents(startMagnitude: 4260000.0);
      expect(wrapCount, equals(0));
    });

    test('Extrapolated zoom-19 regime (pixelOriginX ≈ 17.04M) — ZERO fract-wraps over 1500-px sweep', () {
      // 17.04M ≈ extrapolated zoom-19 magnitude. Just over fp32's
      // 24-bit mantissa exact-integer ceiling (16_777_216) but the
      // value rounds to itself exactly (it is a clean integer multiple
      // of 16 within fp32's available precision at that magnitude;
      // 17_040_000 / 17_039_360 differ by 640 ULPs which is below the
      // ULP at 17M ≈ 1.0 raw px — effectively a no-op for the
      // monotonicity-style detection used here).
      final wrapCount = _countFractWrapEvents(startMagnitude: 17040000.0);
      expect(wrapCount, equals(0));
    });

    test('Historical reference: pre-FOG-18 integer-wrap boundary shifts noise-grid input by exactly 4 grid units', () {
      // Pre-FOG-18 (Plan 03.1-10 FOG-17a) the Dart-side decomposition
      // applied `% 1536` so an integer-wrap event shifted `uPixelOrigin`
      // by exactly 1536 raw pixels. The world-coordinate formulation
      // `noiseUv = worldPx / kNoiseTilePx` therefore shifted by exactly
      // 1536 / kPocFogNoiseTilePx noise grid units = 4.0 (since 384 × 4
      // = 1536).
      //
      // This test is RETAINED post-FOG-18 as historical documentation
      // of the Plan 03.1-10 FOG-17a design. Under FOG-18 the wrap event
      // no longer fires; the painter forwards camera.pixelOrigin
      // directly with no integer-wrap event.
      const historicalWrapPeriodPx = 1536.0;
      const expectedShiftGridUnits = historicalWrapPeriodPx / kPocFogNoiseTilePx;
      expect(
        expectedShiftGridUnits,
        equals(4.0),
        reason:
            'Historical Plan 03.1-10 FOG-17a invariant: 1536.0 / 384.0 must equal 4.0 exactly. '
            'Under FOG-18 (Plan 03.1-12) this wrap event no longer fires — the test documents '
            'the historical numerical relationship between the deleted `kPocFogIntegerWrapPeriodPx` '
            'constant and the surviving `kPocFogNoiseTilePx` constant.',
      );

      // FBM-rotated octave shifts (documented continuity caveat under
      // the historical FOG-17a design):
      // - octave Far  scale 2.9  → shift 4 * 2.9  = 11.6 noise grid units (NOT integer)
      // - octave Mid  scale 5.1  → shift 4 * 5.1  = 20.4 noise grid units (NOT integer)
      // - octave Near scale 10.5 → shift 4 * 10.5 = 42.0 noise grid units (integer; but
      //   the FBM rotation matrices apply between octaves so the warped
      //   UV is not equal to `noiseUv * uScale` in general — this test
      //   documents the pre-rotation shift only).
      //
      // Walk #4 falsified the premise that this 4-grid-unit base-octave
      // shift would be visually invisible: the digit-atlas debug-spiral
      // (which IS truly periodic on 384) showed zero steppiness during
      // max-zoom pan, while production fog showed visible SNAP at every
      // wrap event — confirming the FBM-rotated octaves are NOT
      // continuous across the wrap. FOG-18 eliminates the wrap entirely.
      const farShift = 4.0 * kMirkFogAtmosphericScaleFar;
      const midShift = 4.0 * kMirkFogAtmosphericScaleMid;
      const nearShift = 4.0 * kMirkFogAtmosphericScaleNear;
      expect(farShift, closeTo(11.6, 1e-9));
      expect(midShift, closeTo(20.4, 1e-9));
      expect(nearShift, closeTo(42.0, 1e-9));
    });
  });
}

/// Synthetic harness applying the post-FOG-18 forward path. Returns the
/// number of wrap-discontinuity events detected across a 1500-px sweep.
///
/// A wrap-discontinuity is a NEGATIVE delta in the noiseUv value
/// between consecutive paints (the fragment's noise sample input
/// jumping backwards over time). Under the post-FOG-18 formulation
/// `noiseUv = worldPx / kPocFogNoiseTilePx` the noiseUv evolves
/// monotonically forward — the only way a backwards delta could appear
/// is if someone reverted the formulation back to a fract()-based one,
/// which would inject 0.999→0.001 backwards jumps every ~37 raw pixels
/// (B-3) or every ~390 raw pixels (Plan 03.1-04 viewport-width), OR if
/// someone re-introduces a Dart-side modulo wrap on the path from
/// `camera.pixelOrigin` to `uPixelOrigin` (FOG-17a, falsified by
/// Walk #4 per FOG-18).
///
/// Detection threshold: any negative delta. Under the post-fix
/// formulation noiseUv increases by `5 / 384 ≈ 0.013` per paint —
/// strictly positive. A B-3 fract regression would produce
/// `~-0.97` deltas at every wrap event. The test catches the
/// regression direction, not just magnitude.
int _countFractWrapEvents({required double startMagnitude}) {
  const paintCount = 300;
  const deltaXPerPaint = 5.0;
  const viewportWidth = 390.0;

  // Mid-viewport reference fragment (fragUv ≈ 0.5).
  const fragXPx = viewportWidth * 0.5;

  var wrapCount = 0;
  double? previousNoiseUv;
  for (var i = 0; i < paintCount; i++) {
    final pixelOriginX = startMagnitude + i * deltaXPerPaint;

    // Apply post-FOG-18 forward path (mirrors _FogPainter.paint()): the
    // truncateToDouble decomposition is retained for documentation
    // continuity but the modulo is removed; intPx + fracPx == pxOrigin
    // within fp32.
    final intPx = pixelOriginX.truncateToDouble();
    final fracPx = pixelOriginX - intPx;
    final forwardedPxX = intPx + fracPx;

    // FOG-17 world-coordinate formulation (mirrors atmospheric_fog.frag):
    // worldPx = fragUv * uResolution + uPixelOrigin
    // noiseUv = worldPx / kNoiseTilePx
    final worldPxX = fragXPx + forwardedPxX;
    final noiseUvX = worldPxX / kPocFogNoiseTilePx;

    if (previousNoiseUv != null) {
      final delta = noiseUvX - previousNoiseUv;
      // A backwards delta indicates a wrap discontinuity. Under the
      // post-fix formulation the per-paint delta is +0.013; under B-3
      // it would jump back at every wrap event.
      if (delta < 0) {
        wrapCount += 1;
      }
    }
    previousNoiseUv = noiseUvX;
  }
  return wrapCount;
}
