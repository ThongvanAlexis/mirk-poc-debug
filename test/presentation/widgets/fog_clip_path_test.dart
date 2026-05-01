// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' show Point;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_clip_path.dart';

/// FOG-06 — computeFogClipPath geometry.
///
/// Wave 0 contract: these tests compile against the Plan 03-01 stub (which
/// throws UnimplementedError) and report RED until Plan 03-05 ships the
/// world-rect-minus-disc-circles geometry.
///
/// The MapCamera test fake mirrors the Phase 2 MapCompass test fake:
/// real `MapCamera` constructor with `Epsg3857` CRS + explicit
/// `nonRotatedSize` so screen-coordinate projection is deterministic.
void main() {
  group('computeFogClipPath (FOG-06)', () {
    test('computeFogClipPath with empty discs returns the world rect (no holes)', () {
      final camera = _fakeCamera();
      final path = computeFogClipPath(camera: camera, discs: const <RevealDisc>[]);
      // Bounding rect equals the viewport rect — no subtractions.
      expect(path.getBounds(), equals(const Rect.fromLTWH(0, 0, 400, 800)));
    });

    test('computeFogClipPath with one disc returns world rect minus one circular hole', () {
      final camera = _fakeCamera();
      final path = computeFogClipPath(
        camera: camera,
        discs: <RevealDisc>[RevealDisc(id: 'rvd_a', sessionId: 'poc', lat: 48.5397, lon: 2.6553, radiusMeters: 100.0, fixedAtUtc: DateTime.utc(2026, 5, 1))],
      );
      // Path bounds are still the viewport rect (the hole is INSIDE).
      expect(path.getBounds(), equals(const Rect.fromLTWH(0, 0, 400, 800)));
      // The disc centre (viewport centre at this camera) is OUTSIDE the path
      // (it's inside the hole).
      expect(path.contains(const Offset(200, 400)), isFalse);
      // A point near the corner is INSIDE the path (still fog).
      expect(path.contains(const Offset(10, 10)), isTrue);
    });
  });
}

/// Builds a synthetic MapCamera at Melun centre / z13 / 400x800 viewport.
/// Mirrors the Phase 2 MapCompass test fake pattern (real `MapCamera`
/// constructor with `Epsg3857` + explicit `nonRotatedSize`). The
/// `nonRotatedSize` is a `Point<double>` (flutter_map convention), not a
/// `ui.Size` — the dimensions match the Rect.fromLTWH below.
MapCamera _fakeCamera() =>
    MapCamera(crs: const Epsg3857(), center: const LatLng(48.5397, 2.6553), zoom: 13, rotation: 0, nonRotatedSize: const Point<double>(400, 800));
