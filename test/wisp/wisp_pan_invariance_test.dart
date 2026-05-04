// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' show Point;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle.dart';

/// Success Criterion #1 — RED test for WISP-01 dimensional discipline.
///
/// Defends against the verbatim-port pixel-space regression: a wisp's
/// LatLng position MUST be invariant under camera pan; the projected
/// screen Offset MUST shift by the corresponding pixel delta.
///
/// If the donor's `Offset position` semantics ever creep back in, this
/// test catches it: a 100 m camera pan would produce a wisp that LOOKS
/// stationary on screen because its `position` is in screen-pixel space
/// — and SC #1 explicitly requires the opposite (the wisp tracks the
/// underlying map feature, not the viewport).
///
/// Plan 04-01 (Wave 0) ships RED — `WispParticle.position` is LatLng on
/// the stub already, but the test exercises the FULL projection-shift
/// invariant which Plan 04-04 is responsible for keeping intact when it
/// integrates the painter-side projection. Wave 0 keeps the assertion
/// LIVE (no skip) because the LatLng-not-Offset typing is enforceable
/// today against the stub.
void main() {
  group('Wisp pan invariance (Success Criterion #1)', () {
    test('100 m camera pan does NOT change wisp LatLng position; projected screen Offset moves by corresponding pixel delta', () {
      // Step 1: spawn a wisp at the Melun centre.
      final wisp = WispParticle(position: const LatLng(48.5397, 2.6553), velocityMetersPerSecond: const Offset(0.0, 0.0), life: 2.5, maxLife: 2.5);
      // Snapshot the LatLng for later bit-equality comparison.
      final positionBeforePan = wisp.position;

      // Step 2: build two synthetic MapCameras at the same zoom/size,
      // differing by a 100 m eastward pan.
      // 1° lat ≈ 111320 m → 100 m ≈ 0.000898°. At Melun's latitude the
      // longitude conversion factor is `1° lon ≈ 111320 m × cos(48.5°)`
      // → 100 m east ≈ 0.001357°.
      const eastwardPanDegLon = 0.001357;
      final cameraBefore = _fakeCamera(centerLat: 48.5397, centerLon: 2.6553);
      final cameraAfter = _fakeCamera(centerLat: 48.5397, centerLon: 2.6553 + eastwardPanDegLon);

      // Step 3: project the wisp's LatLng through both cameras.
      final screenBefore = cameraBefore.latLngToScreenPoint(wisp.position);
      final screenAfter = cameraAfter.latLngToScreenPoint(wisp.position);

      // Step 4 (Invariant A): the wisp's stored LatLng did NOT change.
      // This is the SC #1 anti-regression: pure-Dart pan must not touch
      // any wisp field.
      expect(wisp.position.latitude, positionBeforePan.latitude, reason: 'SC #1: 100 m camera pan must NOT mutate wisp.position.latitude');
      expect(wisp.position.longitude, positionBeforePan.longitude, reason: 'SC #1: 100 m camera pan must NOT mutate wisp.position.longitude');

      // Step 5 (Invariant B): the screen Offset DID move by ~100 m worth
      // of pixels (the wisp tracks the underlying world feature; a pan
      // moves the viewport, so the wisp's projected screen position
      // must shift in the OPPOSITE direction by the same magnitude).
      // At zoom 13 in EPSG:3857 the pixel-per-metre at Melun's latitude
      // is roughly 1 / 9.55 ≈ 0.105 px/m → 100 m ≈ 10.5 raw px. We
      // assert the magnitude of the screen-x delta is non-trivial and
      // points in the expected direction (eastward pan moves features
      // LEFTWARD on screen → screen-x delta is NEGATIVE).
      final dxScreen = screenAfter.x - screenBefore.x;
      expect(dxScreen, isNot(closeTo(0.0, 1.0)), reason: 'SC #1: 100 m pan must shift the wisp\'s projected screen-x by a measurable amount (>1 raw px)');
      expect(
        dxScreen,
        lessThan(0.0),
        reason: 'SC #1: eastward camera pan moves the viewport east → world features (and the wisp) appear to move west on screen (negative dx)',
      );
    });
  });
}

/// Builds a synthetic MapCamera at the given centre, z13, 400×800
/// viewport. Mirrors the `fog_clip_path_test.dart` pattern: real
/// `MapCamera` constructor with `Epsg3857` + explicit `nonRotatedSize`.
MapCamera _fakeCamera({required double centerLat, required double centerLon}) =>
    MapCamera(crs: const Epsg3857(), center: LatLng(centerLat, centerLon), zoom: 13, rotation: 0, nonRotatedSize: const Point<double>(400, 800));
