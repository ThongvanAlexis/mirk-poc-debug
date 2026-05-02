// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' show Point;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Offset, Rect;
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_clip_path.dart';

/// FOG-06 — `computeFogClipPath` geometry.
///
/// Plan 03-05 ships the implementation: world-rect-minus-disc-circles,
/// projected through a real flutter_map `MapCamera` with `Epsg3857` CRS.
/// The fake camera mirrors the Phase 2 MapCompass test fake (real
/// `MapCamera` constructor with `nonRotatedSize` as `Point<double>`).
void main() {
  group('computeFogClipPath (FOG-06)', () {
    test('empty discs returns the world rect (no holes)', () {
      final camera = _fakeCamera();
      final path = computeFogClipPath(camera: camera, discs: const <RevealDisc>[]);
      expect(path.getBounds(), equals(const Rect.fromLTWH(0, 0, 400, 800)));
      // Every interior point is inside the path (no holes).
      expect(path.contains(const Offset(200, 400)), isTrue);
      expect(path.contains(const Offset(10, 10)), isTrue);
    });

    test('one disc at viewport centre carves a circular hole', () {
      final camera = _fakeCamera();
      final path = computeFogClipPath(
        camera: camera,
        discs: <RevealDisc>[RevealDisc(id: 'rvd_a', sessionId: 'poc', lat: 48.5397, lon: 2.6553, radiusMeters: 100.0, fixedAtUtc: DateTime.utc(2026, 5, 1))],
      );
      // Path bounds remain the viewport rect — the hole is INSIDE.
      expect(path.getBounds(), equals(const Rect.fromLTWH(0, 0, 400, 800)));
      // The disc centre (viewport centre at this camera) is OUTSIDE the path
      // (i.e. inside the hole — fog NOT drawn there).
      expect(path.contains(const Offset(200, 400)), isFalse);
      // A point near the corner is INSIDE the path (still fog).
      expect(path.contains(const Offset(10, 10)), isTrue);
    });

    test('disc far outside viewport produces a path that still contains every interior point', () {
      final camera = _fakeCamera();
      // 1° north of the viewport centre at z13/400×800 → discontiguous from
      // the viewport. The disc's screen-projected centre lies far above the
      // top edge; the radius (100 m) is far smaller than that vertical gap.
      // Expectation: the disc's screen-space oval does not intersect the
      // viewport rect; every interior point of the path remains "fog drawn".
      final path = computeFogClipPath(
        camera: camera,
        discs: <RevealDisc>[RevealDisc(id: 'rvd_far', sessionId: 'poc', lat: 49.5397, lon: 2.6553, radiusMeters: 100.0, fixedAtUtc: DateTime.utc(2026, 5, 1))],
      );
      expect(path.contains(const Offset(200, 400)), isTrue, reason: 'far disc → centre still fog-drawn');
      expect(path.contains(const Offset(10, 10)), isTrue, reason: 'far disc → corner still fog-drawn');
    });

    test('CANVAS-FRAME-ALIGNMENT (FOG-12 unit) — canvasOffset subtraction shifts disc-hole centers and worldRect by -canvasOffset', () {
      // Pre-Plan-03.1-05 the painter ignored `canvas.getTransform()`. Per
      // 03.1-FALSIFICATION.md Finding 1 the local Canvas was at
      // `(canvasTx, canvasTy) = (5.035, -44.198)` mid-session — the reveal
      // hole then drifted from the blue dot by exactly that translation.
      //
      // After this plan, `computeFogClipPath(canvasOffset: ...)` pre-shifts
      // BOTH the world rect AND every disc-hole center by `-canvasOffset`.
      // After the painter's Canvas applies its translation T, the holes
      // appear at `(rawCenter - canvasOffset) + T = rawCenter` — co-located
      // with the sibling blue-dot CircleLayer rendered at `rawCenter` in its
      // UNTRANSLATED Canvas.
      final camera = _fakeCamera();
      final disc = RevealDisc(id: 'rvd_canvas_offset', sessionId: 't', lat: 48.5397, lon: 2.6553, radiusMeters: 100.0, fixedAtUtc: DateTime.utc(2026, 5, 1));
      final pathWithoutOffset = computeFogClipPath(camera: camera, discs: <RevealDisc>[disc]);
      final pathWithOffset = computeFogClipPath(camera: camera, discs: <RevealDisc>[disc], canvasOffset: const Offset(5, -44));
      final boundsZero = pathWithoutOffset.getBounds();
      final boundsOffset = pathWithOffset.getBounds();
      // The world rect's left edge was originally at 0; after `canvasOffset.dx = 5`
      // it shifts to -5. Likewise top was 0; after `canvasOffset.dy = -44` it
      // shifts to +44.
      expect(
        (boundsOffset.left - (boundsZero.left - 5)).abs(),
        lessThan(kPocCanvasTransformEpsilon),
        reason: 'CANVAS-FRAME-ALIGNMENT (FOG-12): clip path bounds left edge must shift by -canvasOffset.dx.',
      );
      expect(
        (boundsOffset.top - (boundsZero.top - (-44))).abs(),
        lessThan(kPocCanvasTransformEpsilon),
        reason: 'CANVAS-FRAME-ALIGNMENT (FOG-12): clip path bounds top edge must shift by -canvasOffset.dy.',
      );
    });
  });
}

/// Builds a synthetic MapCamera at Melun centre / z13 / 400×800 viewport.
/// Mirrors the Phase 2 MapCompass test fake pattern (real `MapCamera`
/// constructor with `Epsg3857` + explicit `nonRotatedSize`). The
/// `nonRotatedSize` is a `Point<double>` (flutter_map convention).
MapCamera _fakeCamera() =>
    MapCamera(crs: const Epsg3857(), center: const LatLng(48.5397, 2.6553), zoom: 13, rotation: 0, nonRotatedSize: const Point<double>(400, 800));
