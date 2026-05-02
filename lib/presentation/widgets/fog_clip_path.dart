// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' show Point;
import 'dart:ui' as ui show Path;
import 'dart:ui' show Offset, PathOperation, Rect, Size;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';

/// World-rect-minus-disc-circles clip path in screen pixel space (FOG-06).
///
/// Returns `ui.Path.combine(PathOperation.difference, worldRect, discCircles)`
/// projected through [camera]:
///
///   * inside-disc pixels → outside the path → not clipped → fog NOT drawn
///     (the reveal hole).
///   * outside-disc pixels → inside the path → clipped in → fog DRAWN.
///
/// Each disc's screen-space radius is computed via metric-distance arithmetic
/// (matches the donor `RevealedSdfBuilder`'s metres-per-pixel discipline —
/// pixel-space distance produces a north-south oval at non-equatorial
/// latitudes per BUG-011 fix). [_metersToPixels] does the projection by
/// sampling `camera.latLngToScreenPoint` at two points one metre apart along
/// the latitude axis, robust against camera rotation + zoom.
///
/// Empty disc list → returns the world rect itself (full fog, no holes).
///
/// ## CANVAS-FRAME-ALIGNMENT (FOG-12, Plan 03.1-05)
///
/// Optional [canvasOffset] pre-shifts BOTH the world rect AND every
/// disc-hole center by `-canvasOffset`. This matters when the painter's
/// local Canvas already has a non-zero translation T applied at paint
/// time (per `03.1-FALSIFICATION.md` Finding 1, `MobileLayerTransformer`
/// applies `(canvasTx, canvasTy) = (5.035, -44.198)` mid-session under
/// pan/zoom — invalidating RESEARCH §Pitfall D's "Canvas at identity"
/// claim).
///
/// After the painter's Canvas applies its translation T, the holes appear
/// at `(rawCenter - canvasOffset) + T = rawCenter` — co-located with
/// whatever sibling layer (the blue-dot CircleLayer) renders at
/// `rawCenter` in an UNTRANSLATED Canvas. Pre-Plan-03.1-05 the holes
/// appeared at `rawCenter + T` in screen space while the blue dot at
/// `rawCenter` — a divergence of T (e.g., Finding 1's `(5.035, -44.198)`),
/// the developer's "the revealed area is being offsetted from the blue
/// dot during pan/zoom" failure mode (observation 4).
///
/// When [canvasOffset] is `Offset.zero` (default) the math collapses to
/// the original Plan 03-05 behaviour.
///
/// ## flutter_map 7.0.2 API note
///
/// flutter_map's `MapCamera.size` is `Point<double>` (NOT `ui.Size`); we
/// convert via `Size(size.x, size.y)` for the dart:ui `Rect.fromLTWH`
/// constructor. Likewise `MapCamera.latLngToScreenPoint(latLng)` returns
/// `Point<double>` — convert to `Offset` via `Offset(p.x, p.y)`.
///
/// `Path` is qualified `ui.Path` to disambiguate from `latlong2`'s
/// `Path<T extends LatLng>` polyline class which is transitively re-exported
/// through the flutter_map import.
ui.Path computeFogClipPath({required MapCamera camera, required List<RevealDisc> discs, Offset canvasOffset = Offset.zero}) {
  final cameraSize = Size(camera.size.x, camera.size.y);
  // Subtract canvasOffset from the world rect's origin so the rect occupies
  // the same screen region after the painter's Canvas applies its
  // translation T. When canvasOffset = (0, 0) this collapses to
  // `Offset.zero & cameraSize` — the original Plan 03-05 behaviour.
  final viewportRect = Rect.fromLTWH(-canvasOffset.dx, -canvasOffset.dy, cameraSize.width, cameraSize.height);
  final worldPath = ui.Path()..addRect(viewportRect);
  if (discs.isEmpty) return worldPath;

  final holesPath = ui.Path();
  for (final disc in discs) {
    final rawCenter = _pointToOffset(camera.latLngToScreenPoint(LatLng(disc.lat, disc.lon)));
    // Pre-shift the hole center by -canvasOffset. After the painter's
    // Canvas applies its translation T, the hole appears at
    // (rawCenter - canvasOffset) + T = rawCenter (the world-space
    // position the sibling blue-dot CircleLayer renders at in its
    // UNTRANSLATED Canvas).
    final shiftedCenter = rawCenter - canvasOffset;
    final pixelRadius = _metersToPixels(disc.radiusMeters, disc.lat, camera);
    holesPath.addOval(Rect.fromCircle(center: shiftedCenter, radius: pixelRadius));
  }
  return ui.Path.combine(PathOperation.difference, worldPath, holesPath);
}

/// Converts a metric radius to a screen-pixel radius at [lat] using
/// `camera.latLngToScreenPoint` of two points 1 m apart along the latitude
/// axis.
///
/// Why latitude axis: a meridian is a great circle, so 1 m of latitude
/// equals `1.0 / kMetersPerDegreeLat` degrees globally (accurate to ~0.5%
/// at any latitude, well below GPS accuracy). The longitude axis would
/// require a `cos(lat)` correction; the latitude axis sidesteps it.
double _metersToPixels(double radiusMeters, double lat, MapCamera camera) {
  final p0 = camera.latLngToScreenPoint(LatLng(lat, 0));
  final p1 = camera.latLngToScreenPoint(LatLng(lat + 1.0 / kMetersPerDegreeLat, 0));
  final pxPerMeter = p0.distanceTo(p1);
  return radiusMeters * pxPerMeter;
}

/// `Point<double> → Offset` shim — flutter_map projection methods return
/// `Point<double>` (vector_math/dart:math convention) but dart:ui's path
/// operations want `Offset`. Hoisted as a named helper so the conversion
/// idiom is single-source.
Offset _pointToOffset(Point<double> p) => Offset(p.x, p.y);
