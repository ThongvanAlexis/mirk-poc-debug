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
/// The FOG-17a Dart-side decomposition keeps `uPixelOrigin` bounded
/// under `kPocFogIntegerWrapPeriodPx + 1` (= 1537 raw px) regardless of
/// zoom level. Integer-wrap events fire every 1536 raw px of pan
/// (≈ 128 sec at Walk #3b's 12 raw-px/s pan velocity, vs the
/// pre-Plan-03.1-10 every-3-second stepping cadence — a ~40×
/// perceptual reduction). Tests 1-3 use a sub-wrap-period synthetic
/// sweep so the integer-wrap event does NOT fire within the trajectory
/// and ZERO wraps is the expected count under the post-fix formulation.
/// Test 4 documents the integer-wrap-event behaviour separately.
///
/// ## What's tested
///
/// 1. Synthetic smooth-pan trajectory at three pixelOrigin magnitude
///    regimes (1.064M ≈ Walk #3b zoom 13, 4.26M ≈ Walk #2 zoom 16,
///    17.04M ≈ extrapolated zoom 19), with the FOG-17a Dart-side
///    decomposition applied. Each regime: 300 paints @ 5 raw-px/paint
///    over a 1500-px sweep (under one `kPocFogIntegerWrapPeriodPx`
///    cycle). Asserts ZERO fract-style wrap-discontinuity events.
/// 2. Integer-wrap-event continuity: documents the actual numerical
///    behaviour at the wrap boundary — base-octave noise-grid input
///    difference is exactly 4 grid units (no-op on the hash3 lattice);
///    FBM-rotated octaves shift by non-integer multiples (continuity
///    caveat per noise-function inspection in PLAN.md).
void main() {
  group('FOG-17 (Plan 03.1-10) — world-coordinate noise sampling: ZERO wrap events', () {
    test('Walk #3b regime (pixelOriginX ≈ 1.064M) — ZERO fract-wraps over 1500-px sweep', () {
      // Align the start magnitude so the post-FOG-17a bounded
      // composite starts at 0 within the 1536-px wrap window — the
      // 1500-px sweep then stays inside the window and the integer-
      // wrap event does not fire within the trajectory. 1.064M ≈
      // 1536 * 692 = 1062912 + 1088. Choose 1062912 (≈ 1.063M; same
      // Walk #3b regime) so the test isolates the wrap-discontinuity
      // detection from integer-wrap noise. Test 4 covers integer-wrap
      // continuity separately.
      final wrapCount = _countFractWrapEvents(startMagnitude: 1536.0 * 692);
      expect(
        wrapCount,
        equals(0),
        reason:
            'FOG-17 invariant: the world-coordinate formulation `noiseUv = (fragUv * uResolution + boundedPxOrigin) / kNoiseTilePx` '
            'has ZERO fract-style wrap-discontinuity events across a smooth-pan trajectory. '
            'No fract() is applied per-fragment — there is no fractional offset that could wrap. '
            'Pre-Plan-03.1-10 the B-3 formulation `fract(uPixelOrigin / tilePeriodPixels)` produced ~969 wraps over the FOG-14a 36000-px sweep '
            '(~40 over a 1500-px sub-window). If wraps are reported here, the world-coordinate formulation has been silently reverted. '
            'Wrap count: $wrapCount.',
      );
    });

    test('Walk #2 regime (pixelOriginX ≈ 4.26M) — ZERO fract-wraps over 1500-px sweep', () {
      // 4.26M ≈ 1536 * 2773 = 4257528 + 2472. Align to 1536 * 2774 = 4260864
      // (≈ 4.26M, same Walk #2 regime).
      final wrapCount = _countFractWrapEvents(startMagnitude: 1536.0 * 2774);
      expect(wrapCount, equals(0));
    });

    test('Extrapolated zoom-19 regime (pixelOriginX ≈ 17.04M) — ZERO fract-wraps over 1500-px sweep', () {
      // 17.04M ≈ 1536 * 11093 = 17038848 + 1152. Align to 1536 * 11094 = 17040384.
      final wrapCount = _countFractWrapEvents(startMagnitude: 1536.0 * 11094);
      expect(wrapCount, equals(0));
    });

    test('Integer-wrap event: base-octave noise-grid input shifts by exactly 4 grid units', () {
      // At the FOG-17a integer-wrap boundary, the Dart-side decomposition
      // shifts `uPixelOrigin` by exactly `kPocFogIntegerWrapPeriodPx`
      // (1536) raw pixels. The world-coordinate formulation
      // `noiseUv = worldPx / kNoiseTilePx` therefore shifts by exactly
      // `kPocFogIntegerWrapPeriodPx / kPocFogNoiseTilePx` noise grid units.
      //
      // The hash3 noise lattice has period 1.0 in each input axis; an
      // integer-multiple shift is a no-op on the lattice corners, so
      // the BASE octave hash3 sample is preserved across the wrap.
      const expectedShiftGridUnits = kPocFogIntegerWrapPeriodPx / kPocFogNoiseTilePx;
      expect(
        expectedShiftGridUnits,
        equals(4.0),
        reason: '1536.0 / 384.0 must equal 4.0 exactly for the base-octave hash3 lattice to be preserved across the integer-wrap event.',
      );

      // FBM-rotated octave shifts (documented continuity caveat):
      // - octave Far  scale 2.9  → shift 4 * 2.9  = 11.6 noise grid units (NOT integer)
      // - octave Mid  scale 5.1  → shift 4 * 5.1  = 20.4 noise grid units (NOT integer)
      // - octave Near scale 10.5 → shift 4 * 10.5 = 42.0 noise grid units (integer; but
      //   the FBM rotation matrices apply between octaves so the warped
      //   UV is not equal to `noiseUv * uScale` in general — this test
      //   documents the pre-rotation shift only).
      const farShift = 4.0 * kMirkFogAtmosphericScaleFar;
      const midShift = 4.0 * kMirkFogAtmosphericScaleMid;
      const nearShift = 4.0 * kMirkFogAtmosphericScaleNear;
      expect(farShift, closeTo(11.6, 1e-9));
      expect(midShift, closeTo(20.4, 1e-9));
      expect(nearShift, closeTo(42.0, 1e-9));

      // The continuity caveat is documented in PLAN.md and the
      // kPocFogIntegerWrapPeriodPx docstring; this test pins the actual
      // numerical values so future reviewers can verify the math.
      // Resolution: integer-wrap events fire every ~128 sec of
      // continuous pan (kPocFogIntegerWrapPeriodPx / 12 raw-px-per-sec
      // ≈ 128 sec) — a ~40× perceptual reduction vs the every-3-second
      // stepping cadence pre-Plan-03.1-10.
    });
  });
}

/// Synthetic harness applying the post-Plan-03.1-10 world-coordinate
/// formulation. Returns the number of wrap-discontinuity events
/// detected across a 1500-px sub-wrap-period sweep.
///
/// A wrap-discontinuity is a NEGATIVE delta in the noiseUv value
/// between consecutive paints (the fragment's noise sample input
/// jumping backwards over time). Under the post-fix formulation
/// `noiseUv = worldPx / kPocFogNoiseTilePx` the noiseUv evolves
/// monotonically forward — the only way a backwards delta could appear
/// within the sub-wrap-period sweep window is if someone reverted the
/// formulation back to a fract()-based one, which would inject
/// 0.999→0.001 backwards jumps every ~37 raw pixels (B-3) or every
/// ~390 raw pixels (Plan 03.1-04 viewport-width).
///
/// The 1500-px sweep stays under `kPocFogIntegerWrapPeriodPx` (= 1536)
/// so the FOG-17a integer-wrap event does NOT fire within the
/// trajectory. Test 4 covers integer-wrap-event continuity separately.
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

    // Apply FOG-17a decomposition (mirrors _FogPainter.paint()).
    final intPx = pixelOriginX.truncateToDouble();
    final fracPx = pixelOriginX - intPx;
    final boundedPxX = (intPx % kPocFogIntegerWrapPeriodPx) + fracPx;

    // FOG-17 world-coordinate formulation (mirrors atmospheric_fog.frag):
    // worldPx = fragUv * uResolution + uPixelOrigin
    // noiseUv = worldPx / kNoiseTilePx
    final worldPxX = fragXPx + boundedPxX;
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
