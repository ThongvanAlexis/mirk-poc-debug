// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Builds the LOC-02 blue-dot [CircleMarker] (7 px fill `#2B7CD6`,
/// 2 px white stroke).
///
/// Real implementation lands in Plan 02-03 (LOC-02). This Wave 0 stub returns
/// a placeholder zero-radius transparent marker so `map_screen_test.dart` can
/// pump a `CircleLayer` containing it without NPEing; the LOC-02
/// colour/stroke/radius tests fail (RED) against this placeholder until
/// Plan 02-03 lands.
class BlueDotMarker {
  /// Builds a [CircleMarker] centred at [point]. Stub returns a near-invisible
  /// placeholder; production will return the LOC-02 spec marker.
  static CircleMarker build(LatLng point) {
    // Placeholder: zero-radius transparent marker so widget trees pumping a
    // CircleLayer with this marker render without errors. Plan 02-03 replaces
    // with the LOC-02 spec (radius 7 px, fill 0xFF2B7CD6, white stroke 2 px).
    return CircleMarker(point: point, radius: 0, color: const Color(0x00000000));
  }
}
