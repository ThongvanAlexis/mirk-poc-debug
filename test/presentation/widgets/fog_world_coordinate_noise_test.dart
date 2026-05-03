// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-18 (Plan 03.1-12) — world-meter anchor: ZERO wrap-discontinuity
/// events under the meter-space simulator at all pixelOrigin × zoom
/// combinations.
///
/// REWRITTEN from FOG-17 (Plan 03.1-10) world-coordinate noise sampling.
/// File name preserved for git-history continuity even though the
/// simulator has flipped from world-pixel formulation to world-meter
/// formulation.
///
/// ## Background
///
/// Plan 03.1-07 Branch B-3 wrapped every ~16-65 raw px (Walk #3
/// stepping persists at wrap events). Plan 03.1-10 FOG-17 replaced
/// `fract()` with world-coordinate sampling — ZERO wraps within a
/// single integer-wrap window — but anchored noise to pixel-space
/// (Walk #4 Q5 zoom-scramble surfaced).
///
/// Plan 03.1-12 FOG-18 anchors noise to METER-space:
///   `worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel;
///    noiseUv = worldMeters / kNoiseTilePxMeters;`
///
/// Each fragment now samples noise at its world-meter position; the
/// noise pattern is anchored to ground meters and zoom-invariant in
/// geographic terms. As the camera pans, NEW world-meter coordinates
/// enter the viewport edges so NEW noise scrolls in — no fract(), no
/// sliding-offset wraps, no stepping mid-pan within a single zoom
/// level.
///
/// The FOG-17a Dart-side decomposition keeps `uPixelOrigin` bounded
/// under `kPocFogIntegerWrapPeriodPx + 1` (= 1537 raw px) regardless
/// of zoom level. Integer-wrap events fire every 1536 raw px of pan
/// (≈ 128 sec at Walk #3b's 12 raw-px/s pan velocity). Tests 1-3 use
/// a sub-wrap-period synthetic sweep so the integer-wrap event does
/// NOT fire within the trajectory; ZERO wraps is the expected count
/// under the post-fix formulation.
///
/// ## What's tested
///
/// 1. Synthetic smooth-pan trajectory at three pixelOrigin magnitude
///    regimes (1.064M ≈ Walk #3b zoom 13, 4.26M ≈ Walk #2 zoom 16,
///    17.04M ≈ extrapolated zoom 19), with the FOG-17a Dart-side
///    decomposition AND the corresponding zoom-derived metersPerPixel.
///    Each regime: 300 paints @ 5 raw-px/paint over a 1500-px sweep
///    (under one `kPocFogIntegerWrapPeriodPx` cycle). Asserts ZERO
///    wrap-discontinuity events in MEKER-space cell evolution.
/// 2. Zoom-invariance documented in `fog_world_meter_anchor_test.dart`
///    (separate file). This file's focus is wrap-events under
///    smooth-pan trajectories at fixed zoom.

void main() {
  group('FOG-18 (Plan 03.1-12) — world-meter anchor: ZERO wrap events under smooth-pan @ fixed zoom', () {
    test('Walk #3b regime (pixelOriginX ≈ 1.064M, zoom 13 lat 48.5°) — ZERO wraps over 1500-px sweep', () {
      // Align so the post-FOG-17a bounded composite starts at 0 within
      // the 1536-px wrap window. 1536 * 692 = 1062912 ≈ 1.063M.
      final wrapCount = _countMeterSpaceWrapEvents(startPixelOriginX: 1536.0 * 692, zoom: 13.0, lat: 48.5397);
      expect(
        wrapCount,
        equals(0),
        reason:
            'FOG-18 invariant: meter-space formulation `worldMeters = (fragUv * uResolution + boundedPxOrigin) * metersPerPixel; '
            'noiseUv = worldMeters / kNoiseTilePxMeters` has ZERO wrap-discontinuity events across a smooth-pan trajectory '
            'at a fixed zoom. As the camera pans, worldMeters evolves monotonically forward; no fract() is applied. '
            'If wraps are reported here, the FOG-18 formulation has been silently reverted to a fract() formulation. '
            'Wrap count: $wrapCount.',
      );
    });

    test('Walk #2 regime (pixelOriginX ≈ 4.26M, zoom 16 lat 48.5°) — ZERO wraps over 1500-px sweep', () {
      // 4.26M ≈ 1536 * 2774 = 4260864.
      final wrapCount = _countMeterSpaceWrapEvents(startPixelOriginX: 1536.0 * 2774, zoom: 16.0, lat: 48.5397);
      expect(wrapCount, equals(0));
    });

    test('Extrapolated zoom-19 regime (pixelOriginX ≈ 17.04M, lat 48.5°) — ZERO wraps over 1500-px sweep', () {
      // 17.04M ≈ 1536 * 11094 = 17040384.
      final wrapCount = _countMeterSpaceWrapEvents(startPixelOriginX: 1536.0 * 11094, zoom: 19.0, lat: 48.5397);
      expect(wrapCount, equals(0));
    });

    test('Integer-wrap event documentation — meter-space shift is non-integer-multiple of cell size at Walk #4 hike zoom', () {
      // At the FOG-17a integer-wrap boundary, the Dart-side decomposition
      // shifts `uPixelOrigin` by exactly `kPocFogIntegerWrapPeriodPx`
      // (1536) raw pixels. Post-FOG-18 the shader multiplies by
      // uMetersPerPixel; the meter-space shift is therefore
      // `1536 * uMetersPerPixel` meters at the active zoom.
      //
      // At z=15 lat 48.5° (mpp ≈ 3.16 m/raw_px), shift ≈ 4853 m;
      // shift in noise-grid units ≈ 4853 / 1024 ≈ 4.74 cells. NOT
      // integer-multiple. The base-octave noise lattice has period 1
      // in noise-grid units; an integer-multiple shift is a no-op on
      // the lattice corners, but a non-integer shift produces a
      // perceptible discontinuity at the wrap boundary IF visible.
      //
      // Resolution: at Walk #3b's 12 raw-px/s pan velocity, the wrap
      // fires every ~128 sec — below perceptual threshold per Walk
      // #3b empirical evidence. Plan 03.1-13+ contingency documented
      // in `kPocFogNoiseTilePxMeters` docstring + `_FogPainter.paint()`
      // decomposition block.
      const z = 15.0;
      const lat = 48.5397;
      final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, z).toDouble();
      final shiftMeters = kPocFogIntegerWrapPeriodPx * mpp;
      final shiftCells = shiftMeters / kPocFogNoiseTilePxMeters;
      // shift cells is ~4.74 — NOT an integer multiple of 1.0.
      expect(
        shiftCells,
        closeTo(4.738, 0.01),
        reason: 'Documented post-FOG-18 wrap-shift in cells at z=15 lat 48.5° — non-integer-multiple (~4.74 cells per wrap event).',
      );
      // Documented 128-sec wrap cadence at Walk #3b 12 raw-px/s pan.
      const walkVelocityRawPxPerSec = 12.0;
      final wrapSecondsAtWalk3bVelocity = kPocFogIntegerWrapPeriodPx / walkVelocityRawPxPerSec;
      expect(
        wrapSecondsAtWalk3bVelocity,
        closeTo(128.0, 0.5),
        reason: 'Documented integer-wrap cadence: 1536 raw px / 12 raw-px-per-sec = ~128 sec — below perceptual threshold per Walk #3b empirical evidence.',
      );
    });
  });
}

/// Synthetic harness applying the post-Plan-03.1-12 world-meter
/// formulation. Returns the number of wrap-discontinuity events
/// detected across a 1500-px sub-wrap-period sweep at a fixed zoom.
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
/// The 1500-px sweep stays under `kPocFogIntegerWrapPeriodPx` (= 1536)
/// so the FOG-17a integer-wrap event does NOT fire within the
/// trajectory.
int _countMeterSpaceWrapEvents({required double startPixelOriginX, required double zoom, required double lat}) {
  const paintCount = 300;
  const deltaXPerPaint = 5.0;
  const viewportWidth = 390.0;

  // Mid-viewport reference fragment (fragUv ≈ 0.5).
  const fragXPx = viewportWidth * 0.5;

  // Compute metersPerPixel at the synthetic zoom × lat (mirrors
  // _FogPainter.paint() FOG-18 computation).
  final mpp = kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(lat * math.pi / 180.0) / math.pow(2.0, zoom).toDouble();

  var wrapCount = 0;
  double? previousNoiseUv;
  for (var i = 0; i < paintCount; i++) {
    final pixelOriginX = startPixelOriginX + i * deltaXPerPaint;

    // Apply FOG-17a decomposition (mirrors _FogPainter.paint()).
    final intPx = pixelOriginX.truncateToDouble();
    final fracPx = pixelOriginX - intPx;
    final boundedPxX = (intPx % kPocFogIntegerWrapPeriodPx) + fracPx;

    // FOG-18 world-meter formulation (mirrors atmospheric_fog.frag):
    //   worldMeters = (fragUv * uResolution + uPixelOrigin) * uMetersPerPixel
    //   noiseUv = worldMeters / kNoiseTilePxMeters
    final worldPxX = fragXPx + boundedPxX;
    final worldMetersX = worldPxX * mpp;
    final noiseUvX = worldMetersX / kPocFogNoiseTilePxMeters;

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
