// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:geolocator/geolocator.dart';

/// Wraps `Geolocator.getPositionStream` with the project-pinned
/// [LocationSettings] (CONTEXT §GPS subscription).
///
/// Real implementation lands in Plan 02-03 (LOC-01). This Wave 0 stub exists
/// so `map_screen.dart` (Plan 02-05) and the LOC-01 test can import the symbol
/// — the stub returns an empty stream so widget tests that pump `MapScreen`
/// don't deadlock waiting for a fix that will never arrive.
class GeolocatorService {
  /// Returns a fresh stream of [Position] events. Subscribe once per
  /// `MapScreen` instance.
  ///
  /// Stub: returns `const Stream<Position>.empty()`. Real settings
  /// (`LocationAccuracy.best`, `distanceFilter: kPocGpsDistanceFilterMeters`)
  /// land in Plan 02-03 (LOC-01).
  static Stream<Position> stream() {
    return const Stream<Position>.empty();
  }
}
