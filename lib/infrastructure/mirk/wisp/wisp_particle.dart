// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' show Offset;

import 'package:latlong2/latlong.dart';

/// One CPU-side wisp particle in the BUG-009 TIER 2 fog system.
///
/// Wisps are discrete tendrils of fog spawned at the boundary when
/// the user reveals new cells. Each wisp:
///   - lives for a few seconds
///   - drifts via curl-noise advection on the CPU side
///   - grows in radius as it ages (puff dispersing — Plan 04-04 painter)
///   - fades out at the end of life
///
/// Plain mutable class — performance-critical hot path. Freezed would
/// add allocations on every advection step (copyWith returns a new
/// instance per particle per frame). Mutable struct-style is the right
/// idiom here, hence the explicit deviation from the project's general
/// "prefer immutable models" rule.
///
/// Phase 4 POC port — TWO field-name deviations from the donor:
///
///   1. `Offset position` → `LatLng position` (WISP-01 dimensional
///      discipline). The donor stored screen-pixel positions; that
///      basis is zoom-fragile and was the trap behind Phase 3.1
///      BUG-014 (translucent screen-px deltas misalign on zoom). Wisps
///      live in WORLD coordinates and are projected to screen at paint
///      time using the same MapCamera snapshot the fog uses
///      (FOG-07 carry-over).
///
///   2. `Offset velocity` → `Offset velocityMetersPerSecond` (semantic
///      clarity — Offset is reused as the project's 2D-vector type for
///      the (dx, dy) components in m/s; the donor's px/s semantics are
///      GONE). Naming the unit in the field eliminates a class of
///      "wait, is this px/s or m/s?" bugs forever.
class WispParticle {
  /// Constructs a fresh wisp at [position] with initial
  /// [velocityMetersPerSecond] and [life] = [maxLife].
  WispParticle({required this.position, required this.velocityMetersPerSecond, required this.life, required this.maxLife});

  /// Current world-space position. WISP-01 dimensional discipline:
  /// LatLng (NOT screen-pixel Offset) — the painter projects this via
  /// `MapCamera.latLngToScreenPoint` at paint time.
  LatLng position;

  /// Current 2D velocity in metres / second. `Offset` is the reused
  /// 2D-vector type — `dx` is the eastward component, `dy` is the
  /// southward component (matching MapCamera projection conventions).
  Offset velocityMetersPerSecond;

  /// Remaining life in seconds. The particle is evicted at <= 0.
  double life;

  /// Original lifetime — used to compute the normalised age
  /// `1 - life / maxLife` for radius interpolation and alpha falloff.
  final double maxLife;

  /// Whether the particle should be evicted from the active list.
  /// Donor verbatim: `life <= 0`.
  bool get isDead => life <= 0;

  /// Normalised age in [0, 1]. 0 = just born, 1 = about to die.
  /// Donor verbatim: `1 - clamp(life/maxLife, 0, 1)`. The clamp ensures
  /// over-aged wisps (`life < 0` between integration and removal) report
  /// `age == 1.0` rather than `> 1.0`.
  double get age => 1.0 - (life / maxLife).clamp(0.0, 1.0);
}
