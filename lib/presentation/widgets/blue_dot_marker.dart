// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// Builds the LOC-02 blue-dot [CircleMarker]: 7 px filled circle
/// (`#2B7CD6`) with a 2 px white stroke at the user's GPS fix.
///
/// Used by [MapScreen] (Plan 02-05) inside a `CircleLayer` only when
/// `_lastFix != null` (LOC-05 paired). Per Pitfall §LOC-02 the marker
/// uses pixel units (`useRadiusInMeter: false`) — the spec specifies
/// 7 px, not 7 m.
class BlueDotMarker {
  /// Returns the canonical LOC-02 marker at [point].
  ///
  /// Stateless / pure factory — safe to call per build (no controllers,
  /// no listeners). The caller wraps the result in a `CircleLayer`.
  static CircleMarker build(LatLng point) {
    return CircleMarker(
      point: point,
      radius: kPocBlueDotRadiusPx,
      useRadiusInMeter: false,
      color: const Color(kPocBlueDotFillArgb),
      borderStrokeWidth: kPocBlueDotStrokePx,
      borderColor: Colors.white,
    );
  }
}
