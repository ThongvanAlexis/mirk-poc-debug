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
///   - grows in radius as it ages (puff dispersing)
///   - fades out at the end of life
///
/// Plain mutable class — performance-critical hot path. Freezed would
/// add allocations on every advection step (copyWith returns a new
/// instance per particle per frame). Mutable struct-style is the right
/// idiom here, hence the explicit deviation from the project's general
/// "prefer immutable models" rule.
///
/// Phase 4 POC port (Plan 04-01 stub; Plan 04-03 implements behaviour) —
/// TWO field-name deviations from the donor:
///   1. `Offset position` → `LatLng position` (WISP-01 dimensional
///      discipline — wisps live in WORLD coordinates and are projected
///      to screen at paint time using the same MapCamera snapshot the
///      fog uses, FOG-07 carry-over).
///   2. `Offset velocity` → `Offset velocityMetersPerSecond` (semantic
///      clarity — Offset is reused as a 2D-vector type for the (dx, dy)
///      components in m/s; the donor's px/s semantics are GONE).
class WispParticle {
  /// Constructs a fresh wisp at [position] with initial
  /// [velocityMetersPerSecond].
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
  /// Plan 04-03 implements.
  bool get isDead => throw UnimplementedError('Plan 04-03 implements');

  /// Normalised age in [0, 1]. 0 = just born, 1 = about to die.
  /// Plan 04-03 implements.
  double get age => throw UnimplementedError('Plan 04-03 implements');
}
