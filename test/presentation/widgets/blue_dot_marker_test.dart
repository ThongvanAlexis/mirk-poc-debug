// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/presentation/widgets/blue_dot_marker.dart';

/// LOC-02 specifies the blue-dot CircleMarker exactly:
///   - radius:           7 px (NOT metres)
///   - useRadiusInMeter: false
///   - fill colour:      0xFF2B7CD6 (Apple-Maps azure)
///   - border colour:    Colors.white
///   - border stroke:    2 px
///
/// Wave 0 stub returns a near-zero transparent CircleMarker, so every test
/// here is RED until Plan 02-03 lands the spec implementation.
void main() {
  group('BlueDotMarker.build', () {
    test('LOC-02: fill colour is 0xFF2B7CD6', () {
      final marker = BlueDotMarker.build(const LatLng(0, 0));
      // Compare via Color(int) reconstruction so the test stays stable across
      // Flutter SDKs that deprecate Color.value (the structural Color equality
      // covers ARGB round-trip exactly).
      expect(marker.color, equals(const Color(kPocBlueDotFillArgb)));
    });

    test('LOC-02: border colour is Colors.white', () {
      final marker = BlueDotMarker.build(const LatLng(0, 0));
      expect(marker.borderColor, equals(Colors.white));
    });

    test('LOC-02: border stroke width is kPocBlueDotStrokePx (2)', () {
      final marker = BlueDotMarker.build(const LatLng(0, 0));
      expect(marker.borderStrokeWidth, equals(kPocBlueDotStrokePx));
    });

    test('LOC-02: radius is kPocBlueDotRadiusPx (7)', () {
      final marker = BlueDotMarker.build(const LatLng(0, 0));
      expect(marker.radius, equals(kPocBlueDotRadiusPx));
    });

    test('LOC-02: useRadiusInMeter is false (pixels, not metres)', () {
      final marker = BlueDotMarker.build(const LatLng(0, 0));
      expect(marker.useRadiusInMeter, isFalse);
    });

    test('LOC-02: point round-trips the input LatLng', () {
      const expected = LatLng(48.5397, 2.6553);
      final marker = BlueDotMarker.build(expected);
      expect(marker.point, equals(expected));
    });
  });
}
