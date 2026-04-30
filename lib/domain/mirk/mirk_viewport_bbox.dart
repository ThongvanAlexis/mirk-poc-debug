// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

/// Immutable lat/lon bbox decoupled from MapLibre / flutter_map types.
///
/// Represented as four doubles — NOT `LatLngBounds` — so consumers in
/// `lib/domain/` and the fog-rendering pipeline stay platform-type-free.
/// A thin adapter at the platform boundary (Phase 2+) will convert
/// `LatLngBounds` (from `flutter_map`) → [MirkViewportBbox] when needed.
///
/// ## Antimeridian wrap
///
/// `east < west` is permitted when the viewport crosses the ±180° line —
/// concretely when `west > 0 && east < 0` (e.g. west=170°, east=-170°).
/// Callers (notably [RevealDisc.intersectsBbox]) detect this convention by
/// comparing `west` and `east` and switching to the two-half longitude
/// predicate.
///
/// ## POC adaptation note
///
/// Parent project (GOSL-MirkFall) uses `freezed` to generate this class.
/// The POC drops freezed (per RESEARCH.md §Standard Stack §NOT included)
/// and hand-rolls the same shape: four `final double` fields, an asserting
/// constructor, and value-equality. No `copyWith` is provided because no
/// donor consumer calls it; if a future consumer needs it, add it then.
class MirkViewportBbox {
  /// Southern latitude of the bbox in degrees, range `[-90, 90]`.
  final double south;

  /// Western longitude of the bbox in degrees, range `[-180, 180]`.
  final double west;

  /// Northern latitude of the bbox in degrees, range `[-90, 90]`.
  final double north;

  /// Eastern longitude of the bbox in degrees, range `[-180, 180]`.
  /// May be `< west` on antimeridian wrap (see class docstring).
  final double east;

  /// Constructs a bbox. Asserts `south <= north` and the antimeridian-wrap
  /// invariant on `west`/`east` (mirroring the parent freezed `@Assert`s).
  MirkViewportBbox({required this.south, required this.west, required this.north, required this.east})
    : assert(south <= north, 'MirkViewportBbox: south must be <= north (got south=$south, north=$north)'),
      assert(west <= east || (west > 0 && east < 0), 'MirkViewportBbox: east < west only permitted on antimeridian wrap');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MirkViewportBbox && other.south == south && other.west == west && other.north == north && other.east == east;
  }

  @override
  int get hashCode => Object.hash(south, west, north, east);

  @override
  String toString() => 'MirkViewportBbox(south: $south, west: $west, north: $north, east: $east)';
}
