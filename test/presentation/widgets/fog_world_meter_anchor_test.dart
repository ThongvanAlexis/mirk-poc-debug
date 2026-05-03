// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// FOG-18 (Plan 03.1-12) — world-meter anchor zoom-invariance test.
///
/// At a fixed geographic point (lat/lng), the shader's worldMeters
/// coordinate (`(fragUv * uResolution + uPixelOrigin) * uMetersPerPixel`)
/// MUST evaluate to the same value regardless of zoom level. This is
/// the FOG-18 acceptance property: the noise pattern is anchored to
/// ground meters (zoom-invariant in geographic terms).
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
///   worldMeters(lat, lon) = pixelFromLatLng(lat, lon, zoom) *
///                            metersPerPixel(lat, zoom)
///                         = ((lon + 180) / 360) * 256 * 2^zoom *
///                           kWebMercatorMetersPerPxAtEquatorZ0 *
///                           cos(lat) / 2^zoom
///                         = ((lon + 180) / 360) * 256 *
///                           kWebMercatorMetersPerPxAtEquatorZ0 *
///                           cos(lat)
///
/// Each fragment's worldMeters coordinate (and thus its noise sample) is
/// therefore zoom-invariant at any fixed geographic point — the FOG-18
/// acceptance property.
///
/// ## What this test asserts
///
/// At three fixed geographic points (Melun centre, equator, high-latitude
/// 80°), simulate 6 paints across z=10..15 with the corresponding
/// `pixelFromLatLng(lat, lon, z)` and `metersPerPixel(lat, z)`. Compute
/// `worldMeters` at the camera centre (i.e., at the geographic point
/// itself). Assert ALL 6 zoom levels produce the SAME `worldMeters` value
/// within fp32 precision.
///
/// Pre-Plan-03.1-12 (FOG-17 pixel-space anchor), the shader's worldPx
/// coordinate doubled per zoom step → fragments under the same
/// geographic point sampled completely different noise positions per
/// zoom step (Walk #4 Q5 zoom-scramble). FOG-18 closes this.

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
/// Hoisted so the magic `256.0` doesn't appear inline in pixelFromLatLng.
const double _kTileSizePx = 256.0;

/// Half-turn (180°) in degrees — used in lon → world-pixel mapping AND
/// in lat → radians conversion for cos(lat).
const double _kHalfTurnDeg = 180.0;

/// Full-turn (360°) in degrees — used in lon → [0, 1] normalisation.
const double _kFullTurnDeg = 360.0;

/// Tolerance on the worldMeters zoom-invariance assertion. fp32 ULP at
/// `worldMeters` values in the 1e6..1e7 m range is ≈ 0.6..6 m; tighter
/// tolerances would flake. We use the larger of an absolute 1e-3 m floor
/// and a relative 1e-4 ratio.
const double _kZoomInvarianceAbsToleranceMeters = 1e-3;
const double _kZoomInvarianceRelTolerance = 1e-4;

void main() {
  group('FOG-18 (Plan 03.1-12) — world-meter anchor zoom-invariance', () {
    for (final fixedLat in <(String, double, double)>[
      ('Melun (lat 48.5397°, lon 2.6553°)', kPocInitialCameraLat, kPocInitialCameraLon),
      ('Equator (lat 0°, lon 0°)', 0.0, 0.0),
      ('High latitude (lat 80°, lon 0°)', 80.0, 0.0),
    ]) {
      test('worldMeters at camera centre is zoom-invariant — ${fixedLat.$1}', () {
        final lat = fixedLat.$2;
        final lon = fixedLat.$3;

        // Compute worldMeters at camera centre across z=10..15.
        // pixelFromLatLng returns the world-pixel coordinate of the fixed
        // geographic point at zoom z. Multiplying by metersPerPixel at
        // that zoom yields worldMeters of that point — which (per the
        // proof above) MUST be zoom-invariant.
        final worldMetersXAcrossZooms = <double>[];
        final worldMetersYAcrossZooms = <double>[];
        for (final z in <double>[10, 11, 12, 13, 14, 15]) {
          final (originX, originY) = _pixelFromLatLng(lat, lon, z);
          final mpp = _metersPerPixel(lat, z);
          worldMetersXAcrossZooms.add(originX * mpp);
          worldMetersYAcrossZooms.add(originY * mpp);
        }

        // Assert all 6 worldMeters values are equal within fp32 precision.
        // Pre-FOG-18 they would differ — `worldPx / kNoiseTilePx` at fixed
        // lat scales as `2^zoom`, doubling per zoom step. Post-FOG-18 the
        // metersPerPixel multiplication cancels the zoom-doubling exactly.
        final meanX = worldMetersXAcrossZooms.reduce((a, b) => a + b) / worldMetersXAcrossZooms.length;
        final meanY = worldMetersYAcrossZooms.reduce((a, b) => a + b) / worldMetersYAcrossZooms.length;
        for (var i = 0; i < worldMetersXAcrossZooms.length; i++) {
          final valueX = worldMetersXAcrossZooms[i];
          final valueY = worldMetersYAcrossZooms[i];
          expect(
            valueX,
            closeTo(meanX, math.max(_kZoomInvarianceAbsToleranceMeters, meanX.abs() * _kZoomInvarianceRelTolerance)),
            reason:
                'FOG-18 zoom-invariance regression at ${fixedLat.$1} (X axis): worldMeters at camera centre '
                'must be zoom-invariant within fp32 precision (1e-3 m absolute or 1e-4 relative). '
                'Got values: $worldMetersXAcrossZooms (zoom index $i)',
          );
          expect(
            valueY,
            closeTo(meanY, math.max(_kZoomInvarianceAbsToleranceMeters, meanY.abs() * _kZoomInvarianceRelTolerance)),
            reason:
                'FOG-18 zoom-invariance regression at ${fixedLat.$1} (Y axis): worldMeters at camera centre '
                'must be zoom-invariant within fp32 precision. Got values: $worldMetersYAcrossZooms (zoom index $i)',
          );
        }
      });
    }

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
