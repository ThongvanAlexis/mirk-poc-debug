// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' show Offset, Size;

import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';

/// Projects lat/lon to a screen offset for the current viewport + canvas size.
///
/// Linear-Mercator within the viewport bbox — sufficient for the fog
/// overlay because the underlying MapLibre canvas does its own
/// web-mercator projection at the platform layer. Here we just need
/// "put this cell rectangle on the screen where MapLibre has it".
///
/// ## Coordinate convention
///
/// * Screen `(0, 0)` = top-left of the canvas.
/// * Screen y grows DOWN (south on the map → larger y on screen),
///   hence the `(north - lat) / dLat` form (subtracting from `north`
///   ensures `lat=north` → `y=0` and `lat=south` → `y=size.height`).
///
/// ## Outside-viewport handling
///
/// Coordinates outside the viewport return offsets outside the canvas
/// (e.g. negative `dx` for points west of the bbox, `dy > size.height`
/// for points south). The caller's drawing primitives (`CustomPainter`,
/// `Canvas` clip) handle off-screen rendering natively — clamping here
/// would distort the geometry that the MapLibre layer beneath has
/// already rendered correctly.
///
/// ## Defensive zero-span guard
///
/// When `dLat == 0` or `dLon == 0` (both bbox corners coincide on a
/// given axis), we return `Offset.zero` instead of dividing by zero.
/// This case should never occur in production (a viewport always has
/// non-zero lat/lon span) but the guard keeps tests + adversarial
/// fixtures from blowing up at the projection boundary.
class MirkProjection {
  const MirkProjection._();

  /// Returns the screen offset for ([lat], [lon]) given the current
  /// [viewport] and canvas [size]. Offset `(0, 0)` = top-left of canvas.
  ///
  /// See class-level docstring for the outside-viewport / zero-span
  /// guard rationale.
  static Offset latLonToScreen({required double lat, required double lon, required MirkViewportBbox viewport, required Size size}) {
    final dLat = viewport.north - viewport.south;
    final dLon = viewport.east - viewport.west;
    // Defensive: a zero-span bbox would produce NaN/Infinity on the
    // division below. Returning Offset.zero is a deliberate sentinel
    // that callers can detect (or simply paint at origin without
    // crashing).
    if (dLat == 0 || dLon == 0) return Offset.zero;
    final x = ((lon - viewport.west) / dLon) * size.width;
    final y = ((viewport.north - lat) / dLat) * size.height;
    return Offset(x, y);
  }
}
