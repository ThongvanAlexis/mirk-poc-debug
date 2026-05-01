// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:latlong2/latlong.dart';

/// Great-circle distance in metres between two [LatLng] points.
///
/// FOG-02 defence — defends against the degree-vs-meter regression
/// (`distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km`, NOT ~111 km).
/// Wave 0 stub — Plan 03-02 ships the Haversine implementation.
double distanceMetres(LatLng a, LatLng b) {
  throw UnimplementedError('distanceMetres — Plan 03-02');
}
