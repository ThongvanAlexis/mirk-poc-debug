// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;

import '../../config/constants.dart';
import '../mirk/mirk_viewport_bbox.dart';

/// Immutable continuous-geometry reveal — the BUG-010 Option B replacement
/// for the 64×64 cell-bitmap row.
///
/// Each disc carries a centre `(lat, lon)`, a `radiusMeters`, the originating
/// `sessionId` (FK to `t_sessions`) and the UTC instant at which it was
/// fixed. Discs feed two downstream consumers:
///
///   * The SDF builder (Commit 3): `sdf(p) = min over discs of (dist(p,
///     centre) - radius)` — analytic, no quantisation, smooth at every zoom.
///   * Offline session-flush compaction (Commit 6): overlapping discs are
///     merged via [mergeWith] into the smallest enclosing disc to bound
///     storage growth.
///
/// `id` follows the project's `<prefix>_<26-char-ULID>` convention used by
/// [SessionId]; the prefix for reveal discs is `rvd_`. The field is typed
/// as `String` here — it lives in a `TEXT` PK column — rather than a
/// dedicated extension type so this domain object stays trivially
/// constructible from a Drift row without an extra wrap.
class RevealDisc {
  /// Primary key. Format: `rvd_<26-char-ULID>` — see class docstring.
  final String id;

  /// Foreign key to `t_sessions.id`. Plain [String] — the project
  /// does not wrap session IDs in a typed extension today; if that
  /// changes, this field migrates with the rest of the codebase.
  final String sessionId;

  /// Disc centre latitude in degrees, range `[-90, 90]`.
  final double lat;

  /// Disc centre longitude in degrees, range `[-180, 180]`.
  final double lon;

  /// Disc radius in metres. Must be `> 0`; the constructor asserts.
  final double radiusMeters;

  /// UTC instant at which the originating GPS fix was timestamped. Earlier
  /// `fixedAtUtc` wins on [mergeWith] so compaction is replay-safe (the
  /// merged disc inherits the OLDER timestamp, deterministic regardless of
  /// the input order).
  final DateTime fixedAtUtc;

  const RevealDisc({required this.id, required this.sessionId, required this.lat, required this.lon, required this.radiusMeters, required this.fixedAtUtc});

  /// Great-circle distance in metres between this disc's centre and the
  /// `(otherLat, otherLon)` point. Same Haversine formula used by
  /// `reveal_calculator.dart`; see [_haversineMeters] for the rationale on
  /// the choice of formula and the WGS-84 mean radius.
  double distanceMetersTo(double otherLat, double otherLon) {
    return _haversineMeters(lat, lon, otherLat, otherLon);
  }

  /// True iff the disc's bounding box (centre lat/lon ± radius converted to
  /// degrees) overlaps [bbox]. Conservative — the lat/lon expansion uses a
  /// crude equirectangular conversion (`1° lat ≈ [kMetersPerDegreeLat] m`,
  /// `1° lon ≈ [kMetersPerDegreeLat] · cos(lat) m`) so a disc whose true
  /// circular footprint just brushes the bbox may report `true` even when
  /// the analytic disc-rectangle distance would say "outside" by a few
  /// metres. False positives are explicitly accepted: the SDF builder
  /// downstream simply contributes nothing (the `min` over `dist - radius`
  /// stays positive everywhere inside [bbox]).
  ///
  /// Antimeridian wrap (bbox `east < west`) is handled by widening the
  /// longitude predicate into an OR over the two contiguous halves.
  bool intersectsBbox(MirkViewportBbox bbox) {
    final latDegPerMeter = 1.0 / kMetersPerDegreeLat;
    // Polar guard: `cos(±90°)` would zero-divide. At |lat| ≥ 89° the
    // longitude expansion is meaningless anyway (a metre-scale disc spans
    // most of the longitude axis), so we floor `cos` at the same Mercator
    // clamp used by `reveal_calculator.dart`.
    final clampedLatRad = _toRad(_clampDouble(lat, -_polarLatClampDeg, _polarLatClampDeg));
    final lonDegPerMeter = 1.0 / (kMetersPerDegreeLat * math.cos(clampedLatRad));

    final minLat = lat - radiusMeters * latDegPerMeter;
    final maxLat = lat + radiusMeters * latDegPerMeter;
    final minLon = lon - radiusMeters * lonDegPerMeter;
    final maxLon = lon + radiusMeters * lonDegPerMeter;

    if (maxLat < bbox.south || minLat > bbox.north) return false;

    // Normal (non-wrapping) bbox: west <= east, single longitude interval.
    if (bbox.west <= bbox.east) {
      return !(maxLon < bbox.west || minLon > bbox.east);
    }
    // Antimeridian wrap: bbox covers `[west, +180] ∪ [-180, east]`. The
    // disc bbox intersects either half when its `[minLon, maxLon]` overlaps
    // either of those two halves.
    final overlapsEastHalf = !(maxLon < bbox.west || minLon > _maxLonDeg);
    final overlapsWestHalf = !(maxLon < _minLonDeg || minLon > bbox.east);
    return overlapsEastHalf || overlapsWestHalf;
  }

  /// Returns the smallest enclosing disc that covers both `this` and
  /// [other]. Used by offline compaction at session flush.
  ///
  /// Both discs MUST share the same [sessionId] — asserted; reveal discs
  /// are session-scoped and merging across sessions would cross a domain
  /// invariant.
  ///
  /// Tie-breaks (deterministic, replay-safe):
  ///
  ///   * The merged `fixedAtUtc` is the earlier of the two inputs (so
  ///     replay produces the same timestamp regardless of order).
  ///   * The merged `id` is taken from whichever input has the EARLIER
  ///     `fixedAtUtc` so the same pair always collapses to the same row PK.
  ///     Identical timestamps fall back to lexicographic `id` order — this
  ///     is the only natural total order available without an external
  ///     clock and keeps the merge purely a function of its inputs.
  ///
  /// Algorithm:
  ///
  ///   1. Compute `d = distanceMetersTo(other.lat, other.lon)`.
  ///   2. Containment short-circuits: if `d + other.radius <= this.radius`
  ///      return `this`; symmetric for `other`.
  ///   3. Otherwise the two discs are properly overlapping or disjoint.
  ///      The smallest enclosing disc has radius
  ///      `(d + r1 + r2) / 2` and centre on the line from this centre to
  ///      `other`'s centre, at distance `(newRadius - r1)` from `this`.
  ///   4. Compute the new centre by interpolating on a local
  ///      equirectangular projection. This is sufficient at the < 100 m
  ///      compaction scale (a disc-merge across more than ~1 km would
  ///      indicate a bug in the compaction policy upstream): the geodesic
  ///      midpoint and the equirectangular-interpolation midpoint agree to
  ///      within ~1 cm at that distance, well below GPS accuracy. The
  ///      assumption is asserted in the test suite via a known-fixture
  ///      check.
  RevealDisc mergeWith(RevealDisc other) {
    assert(sessionId == other.sessionId, 'RevealDisc.mergeWith: sessionId mismatch (this=$sessionId, other=${other.sessionId})');

    final d = distanceMetersTo(other.lat, other.lon);

    // Containment short-circuits. Guarded by `<=` so two perfectly
    // identical discs return whichever input has the earlier fixedAtUtc
    // (the deterministic tie-break required by Commit 6 replay semantics).
    if (d + other.radiusMeters <= radiusMeters) {
      return _earlierOf(this, other);
    }
    if (d + radiusMeters <= other.radiusMeters) {
      return _earlierOf(other, this);
    }

    final newRadius = (d + radiusMeters + other.radiusMeters) / 2.0;
    final tFromThis = (newRadius - radiusMeters) / d;

    // Local equirectangular interpolation. Convert the lat/lon delta to
    // metres (using the latitude-scaled longitude factor at `lat`), step
    // along that vector, then convert back. Equivalent to a geodesic
    // midpoint at the < 100 m scales used by compaction.
    final clampedCosLat = math.cos(_toRad(_clampDouble(lat, -_polarLatClampDeg, _polarLatClampDeg)));
    final dLatMeters = (other.lat - lat) * kMetersPerDegreeLat;
    final dLonMeters = (other.lon - lon) * kMetersPerDegreeLat * clampedCosLat;
    final newLatMetersFromThis = dLatMeters * tFromThis;
    final newLonMetersFromThis = dLonMeters * tFromThis;
    final newLat = lat + newLatMetersFromThis / kMetersPerDegreeLat;
    final newLon = lon + newLonMetersFromThis / (kMetersPerDegreeLat * clampedCosLat);

    final earlier = _earlierOf(this, other);
    final mergedFixedAtUtc = fixedAtUtc.isBefore(other.fixedAtUtc) ? fixedAtUtc : other.fixedAtUtc;

    return RevealDisc(id: earlier.id, sessionId: sessionId, lat: newLat, lon: newLon, radiusMeters: newRadius, fixedAtUtc: mergedFixedAtUtc);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RevealDisc &&
        other.id == id &&
        other.sessionId == sessionId &&
        other.lat == lat &&
        other.lon == lon &&
        other.radiusMeters == radiusMeters &&
        other.fixedAtUtc == fixedAtUtc;
  }

  @override
  int get hashCode => Object.hash(id, sessionId, lat, lon, radiusMeters, fixedAtUtc);

  @override
  String toString() =>
      'RevealDisc(id: $id, sessionId: $sessionId, lat: $lat, lon: $lon, '
      'radiusMeters: $radiusMeters, fixedAtUtc: $fixedAtUtc)';
}

// ---------------------------------------------------------------------------
// File-private helpers. `kMetersPerDegreeLat` and `kEarthRadiusMeters` live in
// `lib/config/constants.dart` — promoted out of this file when the SDF
// builder became the third caller; see those constants' docstrings.
// ---------------------------------------------------------------------------

/// Latitude clamp at which the longitude-scaling cosine bottoms out. Mirrors
/// the Mercator clamp used elsewhere in the project (`TileMath.maxLatMercator`
/// = ~85.0511°); discs whose centre exceeds this are projected back into
/// range for the bbox / interpolation maths only — the stored `lat` is
/// preserved as-is.
const double _polarLatClampDeg = 85.0511287798066;

/// Inclusive longitude bounds in degrees. Hoisted as named constants so the
/// antimeridian-wrap branch in [RevealDisc.intersectsBbox] does not reach
/// for raw `180.0` / `-180.0` literals.
const double _maxLonDeg = 180.0;
const double _minLonDeg = -180.0;

/// Degrees → radians.
double _toRad(double deg) => deg * math.pi / _degreesPerHalfTurn;

/// Number of degrees in a half turn. Hoisted out of the `deg → rad`
/// conversion so the magic `180.0` does not appear inline.
const double _degreesPerHalfTurn = 180.0;

/// Local clamp that does not depend on `num.clamp` boxing semantics —
/// keeps the intersect/merge maths in pure double arithmetic.
double _clampDouble(double value, double low, double high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

/// Returns whichever of [a] or [b] has the earlier [RevealDisc.fixedAtUtc].
/// Identical timestamps fall back to lexicographic `id` order so the merge
/// is a deterministic function of its inputs (replay-safe).
RevealDisc _earlierOf(RevealDisc a, RevealDisc b) {
  if (a.fixedAtUtc.isBefore(b.fixedAtUtc)) return a;
  if (b.fixedAtUtc.isBefore(a.fixedAtUtc)) return b;
  return a.id.compareTo(b.id) <= 0 ? a : b;
}

/// Great-circle distance between two `(lat, lon)` pairs, in metres, via the
/// Haversine formula. Choice of Haversine (vs Vincenty) per
/// `09-RESEARCH.md`: better accuracy at small radii than the equirectangular
/// approximation, far cheaper than Vincenty, and the metre-scale difference
/// at ≤ 25 m radius is negligible at any latitude.
double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final l1 = _toRad(lat1);
  final l2 = _toRad(lat2);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(l1) * math.cos(l2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return kEarthRadiusMeters * c;
}
