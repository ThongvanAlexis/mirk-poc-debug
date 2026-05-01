// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/domain/revealed/distance_metres.dart';

/// FOG-02 defence — degree-vs-meter regression test.
///
/// Wave 0 contract: these tests compile against the
/// `lib/domain/revealed/distance_metres.dart` stub (which throws
/// UnimplementedError) and report RED until Plan 03-02 ships the Haversine
/// implementation.
void main() {
  group('distanceMetres (FOG-02)', () {
    test('distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km — defends against degree-vs-meter regression', () {
      final m = distanceMetres(const LatLng(48.5, 2.6), const LatLng(48.5, 3.6));
      // Haversine truth at lat 48.5°: 1° lon × cos(48.5°) × 111320 m/° ≈ 73.7 km
      // NOT ~111 km (would mean naive degree-as-pixel math).
      expect(m, closeTo(73700, 200));
      // Sanity inverse — equator: 1° lon at lat 0 ≈ 111.32 km.
      final mEq = distanceMetres(const LatLng(0.0, 0.0), const LatLng(0.0, 1.0));
      expect(mEq, closeTo(111320, 200));
    });

    test('distanceMetres is symmetric and zero on identical points', () {
      const p = LatLng(48.5397, 2.6553);
      expect(distanceMetres(p, p), closeTo(0, 0.001));
      expect(distanceMetres(p, const LatLng(48.5500, 2.6700)), closeTo(distanceMetres(const LatLng(48.5500, 2.6700), p), 0.001));
    });
  });
}
