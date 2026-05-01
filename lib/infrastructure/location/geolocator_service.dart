// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// Wraps `Geolocator.getPositionStream` with the project-pinned
/// [LocationSettings] (CONTEXT §GPS subscription).
///
/// Subscribe exactly once per [MapScreen] lifecycle (initState subscribe,
/// dispose cancel — Pitfall 5). Cache the latest [Position] in
/// `_lastFix` per LOC-03; do NOT call `Geolocator.getLastKnownPosition`
/// (unreliable on iOS — known plugin issue, enforced by the static-source
/// CI gate at `tool/test/check_no_last_known_position_test.dart`).
class GeolocatorService {
  static final Logger _log = Logger('domain.location');

  /// Pinned settings — `accuracy: best` (~10 m on iPhone outdoors)
  /// + 5 m distance filter (CONTEXT-locked).
  static const LocationSettings _settings = LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: kPocGpsDistanceFilterMeters);

  /// Returns a fresh stream — caller subscribes once per [MapScreen]
  /// instance (Pitfall 5: cancel the subscription in dispose).
  ///
  /// iOS `whenInUse` permission + no `UIBackgroundModes:location` in
  /// Info.plist (Phase 1 AUTH-05) means iOS suspends the stream on
  /// backgrounding automatically — no app-side pause-on-background
  /// code needed (CONTEXT decision honoured).
  static Stream<Position> stream() {
    _log.info('Subscribing to Geolocator.getPositionStream(accuracy=best, distanceFilter=$kPocGpsDistanceFilterMeters)');
    return Geolocator.getPositionStream(locationSettings: _settings);
  }
}
