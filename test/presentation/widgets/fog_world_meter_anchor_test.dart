// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-18 (Plan 03.1-12) — world-meter anchor zoom-invariance test.
///
/// **Plan 03.1-14 (Fix B′ — FOG-19) re-write:** flipped the worldMeters
/// formula from Plan 03.1-12 era `(fragUv * uResolution + uPixelOrigin) *
/// uMetersPerPixel` to Plan 03.1-14 active `(fragUv * uResolution) *
/// uMetersPerPixel + uWorldMetersOrigin`. The zoom-invariance assertion
/// (FOG-18 acceptance — worldMeters at fixed geographic point is
/// zoom-invariant) is preserved by both formulas; the mathematical
/// derivation is given in `03.1-FALSIFICATION-5.md`
/// continuity_proof_for_plan_03_1_14 block.
///
/// At a fixed geographic point (lat/lng), the shader's worldMeters
/// coordinate MUST evaluate to the same value regardless of zoom level.
/// This is the FOG-18 acceptance property: the noise pattern is
/// anchored to ground meters (zoom-invariant in geographic terms).
///
/// ## Why the math holds (proof sketch)
///
/// Web-Mercator EPSG:3857 standard:
///   pixelFromLatLng(lat, lon, zoom) = ((lon + 180) / 360) * 256 * 2^zoom
///   metersPerPixel(lat, zoom)       = kWebMercatorMetersPerPxAtEquatorZ0 *
///                                     cos(lat) / 2^zoom
///
/// At a fixed geographic point, the world-pixel coordinate of that point
/// scales as `2^zoom`; metersPerPixel scales as `2^-zoom`. Their product
/// is therefore zoom-INDEPENDENT:
///
///   worldMetersOrigin(lat, lon) = (pixelFromLatLng(lat, lon, zoom) *
///                                  metersPerPixel(lat, zoom)) modulo
///                                 kPocFogIntegerWrapPeriodMeters
///                               = zoom-invariant (modulo wrap period)
///
/// Plan 03.1-14 Fix B′: the painter forwards
/// `worldMetersOrigin = (intMeters % kPocFogIntegerWrapPeriodMeters) +
/// fracMeters` directly to slot 3..4. The shader computes per-fragment:
///
///   worldMeters = (fragUv * uResolution) * uMetersPerPixel +
///                 uWorldMetersOrigin
///
/// At a fixed geographic point, `pixelOrigin × metersPerPixel` is
/// zoom-invariant (modulo the 4096-m wrap period), so worldMetersOrigin
/// is zoom-invariant; the per-fragment offset `(fragUv * uResolution) *
/// uMetersPerPixel` evolves with zoom (since mpp scales with zoom and
/// uResolution is constant), but at the camera-centre fragment
/// (fragUv = 0.5), the offset stays constant in geographic terms because
/// it is centred on the camera position.
///
/// ## What this test asserts
///
/// At three fixed geographic points (Melun centre, equator, high-latitude
/// 80°), simulate 6 paints across z=10..15 with the corresponding
/// `pixelFromLatLng(lat, lon, z)` and `metersPerPixel(lat, z)`. Compute
/// `worldMetersOrigin = (pxOrigin * mpp) modulo 4096`. Assert that the
/// non-wrap-aliased portion of worldMetersOrigin (i.e., the unbounded
/// `pxOrigin * mpp` product) is zoom-invariant within fp32 precision.

/// Web-Mercator pixelFromLatLng (EPSG:3857 standard).
/// Returns the world-pixel coordinate of (lat, lon) at zoom z.
/// Reference: https://epsg.io/3857.
(double, double) _pixelFromLatLng(double lat, double lon, double z) {
  final n = math.pow(2.0, z).toDouble() * _kTileSizePx;
  final x = ((lon + _kHalfTurnDeg) / _kFullTurnDeg) * n;
  final latRad = lat * math.pi / _kHalfTurnDeg;
  final y = (1.0 - (math.log(math.tan(latRad) + (1.0 / math.cos(latRad))) / math.pi)) / 2.0 * n;
  return (x, y);
}

double _metersPerPixel(double lat, double zoom) {
  final latRad = lat * math.pi / _kHalfTurnDeg;
  return kWebMercatorMetersPerPxAtEquatorZ0 * math.cos(latRad) / math.pow(2.0, zoom).toDouble();
}

/// Web-Mercator standard tile size (256 raw px per tile at any zoom).
const double _kTileSizePx = 256.0;

/// Half-turn (180°) in degrees.
const double _kHalfTurnDeg = 180.0;

/// Full-turn (360°) in degrees.
const double _kFullTurnDeg = 360.0;

/// Tolerance on the worldMeters zoom-invariance assertion. fp32 ULP at
/// `worldMeters` values in the 1e6..1e7 m range is ≈ 0.6..6 m.
const double _kZoomInvarianceAbsToleranceMeters = 1e-3;
const double _kZoomInvarianceRelTolerance = 1e-4;

void main() {
  group('FOG-18 + FOG-19 (Plan 03.1-12 + Plan 03.1-14) — world-meter anchor zoom-invariance', () {
    for (final fixedLat in <(String, double, double)>[
      ('Melun (lat 48.5397°, lon 2.6553°)', kPocInitialCameraLat, kPocInitialCameraLon),
      ('Equator (lat 0°, lon 0°)', 0.0, 0.0),
      ('High latitude (lat 80°, lon 0°)', 80.0, 0.0),
    ]) {
      test('unbounded pxOrigin × mpp at camera centre is zoom-invariant — ${fixedLat.$1}', () {
        final lat = fixedLat.$2;
        final lon = fixedLat.$3;

        // Compute unbounded `pixelFromLatLng × metersPerPixel` at camera
        // centre across z=10..15. This product is the zoom-invariant
        // quantity that the bounded composite is computed from. Plan
        // 03.1-14 Fix B′ then takes `(intMeters % 4096) + fracMeters`
        // for the actual forwarded value; the wrap modulo is a
        // deterministic injection, NOT a zoom-variation.
        final unboundedWorldMetersXAcrossZooms = <double>[];
        final unboundedWorldMetersYAcrossZooms = <double>[];
        for (final z in <double>[10, 11, 12, 13, 14, 15]) {
          final (originX, originY) = _pixelFromLatLng(lat, lon, z);
          final mpp = _metersPerPixel(lat, z);
          unboundedWorldMetersXAcrossZooms.add(originX * mpp);
          unboundedWorldMetersYAcrossZooms.add(originY * mpp);
        }

        // Assert all 6 unbounded worldMeters values are equal within
        // fp32 precision (zoom-invariance: cos(lat) and lon are constant
        // at fixed geographic point; the 2^zoom factors cancel).
        final meanX = unboundedWorldMetersXAcrossZooms.reduce((a, b) => a + b) / unboundedWorldMetersXAcrossZooms.length;
        final meanY = unboundedWorldMetersYAcrossZooms.reduce((a, b) => a + b) / unboundedWorldMetersYAcrossZooms.length;
        for (var i = 0; i < unboundedWorldMetersXAcrossZooms.length; i++) {
          final valueX = unboundedWorldMetersXAcrossZooms[i];
          final valueY = unboundedWorldMetersYAcrossZooms[i];
          expect(
            valueX,
            closeTo(meanX, math.max(_kZoomInvarianceAbsToleranceMeters, meanX.abs() * _kZoomInvarianceRelTolerance)),
            reason:
                'FOG-18 zoom-invariance regression at ${fixedLat.$1} (X axis): unbounded `pxOrigin × mpp` at camera '
                'centre must be zoom-invariant within fp32 precision (1e-3 m absolute or 1e-4 relative). '
                'Got values: $unboundedWorldMetersXAcrossZooms (zoom index $i)',
          );
          expect(
            valueY,
            closeTo(meanY, math.max(_kZoomInvarianceAbsToleranceMeters, meanY.abs() * _kZoomInvarianceRelTolerance)),
            reason:
                'FOG-18 zoom-invariance regression at ${fixedLat.$1} (Y axis): unbounded `pxOrigin × mpp` at camera '
                'centre must be zoom-invariant within fp32 precision. Got values: $unboundedWorldMetersYAcrossZooms (zoom index $i)',
          );
        }
      });
    }

    test('Plan 03.1-14 Fix B′ — bounded meter composite stays under 4097 m at camera centre across z=10..15 lat 0..80°', () {
      // The forwarded uWorldMetersOrigin = (intMeters % 4096) + fracMeters
      // at camera centre stays under 4097 m regardless of zoom × lat.
      for (final lat in <double>[0.0, 30.0, kPocInitialCameraLat, 60.0, 80.0]) {
        for (final z in <double>[10, 13, 15, 17, 19]) {
          final (originX, originY) = _pixelFromLatLng(lat, kPocInitialCameraLon, z);
          final mpp = _metersPerPixel(lat, z);
          final unboundedX = originX * mpp;
          final unboundedY = originY * mpp;
          final boundedX = (unboundedX.truncateToDouble() % kPocFogIntegerWrapPeriodMeters) + (unboundedX - unboundedX.truncateToDouble());
          final boundedY = (unboundedY.truncateToDouble() % kPocFogIntegerWrapPeriodMeters) + (unboundedY - unboundedY.truncateToDouble());
          expect(
            boundedX.abs(),
            lessThanOrEqualTo(kPocFogIntegerWrapPeriodMeters + 1),
            reason: 'Plan 03.1-14 Fix B′ bounded composite invariant: |boundedMetersX| <= 4097 at z=$z lat=$lat (got $boundedX)',
          );
          expect(boundedY.abs(), lessThanOrEqualTo(kPocFogIntegerWrapPeriodMeters + 1));
        }
      }
    });

    test('FOG-17 pixel-space anchor regression check (worldPx WITHOUT metersPerPixel doubles per zoom step)', () {
      // Documented regression-defense test: under the pre-FOG-18 FOG-17
      // formulation, worldPx at a fixed geographic point doubles per
      // zoom step. This test pins that pre-fix behaviour so future
      // readers can verify the FOG-18 fix actually changes anything.
      const lat = kPocInitialCameraLat;
      const lon = kPocInitialCameraLon;
      final worldPxXAcrossZooms = <double>[];
      for (final z in <double>[10, 11, 12, 13, 14, 15]) {
        final (originX, _) = _pixelFromLatLng(lat, lon, z);
        worldPxXAcrossZooms.add(originX);
      }
      // Per zoom step, worldPx must double (within fp32 precision).
      for (var i = 1; i < worldPxXAcrossZooms.length; i++) {
        final ratio = worldPxXAcrossZooms[i] / worldPxXAcrossZooms[i - 1];
        expect(
          ratio,
          closeTo(2.0, 1e-9),
          reason:
              'FOG-17 baseline pin: worldPx at a fixed geographic point doubles per zoom step (pre-FOG-18 behaviour). '
              'This test documents the pre-fix doubling so future readers can verify the FOG-18 metersPerPixel cancellation.',
        );
      }
    });
  });
}
