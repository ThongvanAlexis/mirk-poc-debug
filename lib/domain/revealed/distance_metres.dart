// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/config/constants.dart';

/// Great-circle distance in metres between two [LatLng] points (Haversine).
///
/// FOG-02 defence — the unit test asserts
/// `distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km` at lat 48.5° (NOT
/// ~111 km, which would mean degree-as-pixel math snuck back in). At the
/// equator the same delta yields ~111.32 km because longitude has its
/// full great-circle arc length there.
///
/// Uses [kEarthRadiusMeters] (WGS-84 mean radius, 6371008.8 m) — same
/// constant the donor `RevealDisc.distanceMetersTo` and `RevealedSdfBuilder`
/// already consume; one source of truth for great-circle maths across the
/// revealed-domain code.
///
/// Why a top-level function and not a method on [LatLng]? Because:
/// - [LatLng] is a third-party class (latlong2) we can't extend cleanly
///   without an extension that risks colliding with future package additions.
/// - The donor [RevealDisc.distanceMetersTo] takes raw `(lat, lon)` doubles,
///   not a LatLng — keeping a parallel top-level helper that takes LatLng is
///   the cheapest seam for the FOG-01 GPS-fix listener (which already holds
///   `Position` from geolocator and converts to LatLng for the blue-dot).
double distanceMetres(LatLng a, LatLng b) {
  final lat1Rad = a.latitude * math.pi / _degreesPerHalfTurn;
  final lat2Rad = b.latitude * math.pi / _degreesPerHalfTurn;
  final dLatRad = (b.latitude - a.latitude) * math.pi / _degreesPerHalfTurn;
  final dLonRad = (b.longitude - a.longitude) * math.pi / _degreesPerHalfTurn;
  final h = math.sin(dLatRad / 2) * math.sin(dLatRad / 2) + math.cos(lat1Rad) * math.cos(lat2Rad) * math.sin(dLonRad / 2) * math.sin(dLonRad / 2);
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return kEarthRadiusMeters * c;
}

/// Number of degrees in a half turn — denominator of the deg → rad conversion.
/// Hoisted as a named constant so the magic `180.0` does not appear inline
/// (mirrors `_degreesPerHalfTurn` in `reveal_disc.dart`).
const double _degreesPerHalfTurn = 180.0;
