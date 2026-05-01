// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/revealed_sdf_builder.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';

/// Hash-keyed cache wrapping the donor [RevealedSdfBuilder] (FOG-03).
///
/// Hash key combines:
///   * disc list — length + per-disc (lat, lon, radiusMeters) quantised
///     to 6 decimals (sub-cm spatial granularity, well under POC scale)
///   * [MirkViewportBbox] value equality (donor type — already has
///     deterministic hashCode)
///
/// On miss, the prior cached `ui.Image` is disposed before being replaced
/// (otherwise GPU memory leaks under sustained pan).
///
/// At POC scale (~5–50 discs over a 5-min Melun walk; sub-ms rebuild per
/// CONTEXT.md), the cache is mostly hit; rebuild kicks in only when the
/// disc list mutates (new GPS fix) or the viewport bbox changes (pan/zoom).
class SdfCache {
  /// [builder] is a test seam — production wires the const donor builder;
  /// tests can inject a fake that returns a precomputed `ui.Image` to keep
  /// suite runtime predictable.
  SdfCache({required SdfRebuildLogger rebuildLogger, RevealedSdfBuilder? builder})
    : _rebuildLogger = rebuildLogger,
      _builder = builder ?? const RevealedSdfBuilder();

  final SdfRebuildLogger _rebuildLogger;
  final RevealedSdfBuilder _builder;

  ui.Image? _cachedImage;
  int? _cachedHash;

  /// Returns either the cached `ui.Image` (cache hit) or kicks off a
  /// rebuild via the donor builder (cache miss). Caller awaits the future.
  ///
  /// At POC scale (sub-ms per donor docstring), the await is acceptable
  /// inside the per-frame paint path. If walk evidence shows budget
  /// pressure, the fallback is a 60 Hz cap on the 120 Hz device (CONTEXT.md
  /// — default OFF; documented knob).
  Future<ui.Image> getOrBuild({required List<RevealDisc> discs, required MirkViewportBbox viewport}) async {
    final h = _hash(discs, viewport);
    final cached = _cachedImage;
    if (cached != null && h == _cachedHash) return cached;

    final stopwatch = Stopwatch()..start();
    final image = await _builder.buildFromDiscs(discs: discs, viewport: viewport);
    stopwatch.stop();

    _cachedImage?.dispose();
    _cachedImage = image;
    _cachedHash = h;

    final intersecting = discs.where((d) => d.intersectsBbox(viewport)).length;
    _rebuildLogger.recordRebuild(
      elapsedMs: stopwatch.elapsedMicroseconds / _microsecondsPerMillisecond,
      discCount: discs.length,
      intersectingDiscCount: intersecting,
    );

    return image;
  }

  /// Releases the cached `ui.Image`. Call from owner's dispose path.
  void dispose() {
    _cachedImage?.dispose();
    _cachedImage = null;
    _cachedHash = null;
  }

  int _hash(List<RevealDisc> discs, MirkViewportBbox viewport) {
    // Length + per-disc quantised lat/lon/radius. Quantisation tames any
    // floating-point drift between consecutive frames at the same fix.
    final discHashes = discs
        .map((d) {
          final qlat = (d.lat * _spatialQuantisationFactor).round();
          final qlon = (d.lon * _spatialQuantisationFactor).round();
          final qrad = (d.radiusMeters * _radiusQuantisationFactor).round();
          return Object.hash(qlat, qlon, qrad);
        })
        .toList(growable: false);
    return Object.hash(viewport, Object.hashAll(discHashes), discs.length);
  }
}

/// 1e6 → quantises lat/lon to 6 decimal places (~10 cm at the equator). Well
/// below GPS accuracy and the POC's 25 m disc radius — guards against
/// floating-point drift between consecutive frames at the same GPS fix.
const double _spatialQuantisationFactor = 1e6;

/// 1e3 → quantises radius to 1 mm. The POC radius is fixed at
/// `kPocRevealDiscRadiusMeters`; finer quantisation is unused but cheap.
const double _radiusQuantisationFactor = 1e3;

/// Stopwatch.elapsedMicroseconds → ms divisor. Hoisted out of the inline call
/// site so the magic 1000 doesn't appear in the rebuild-recording line.
const double _microsecondsPerMillisecond = 1000.0;
