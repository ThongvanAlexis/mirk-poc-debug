// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:ui' as ui;

import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';

/// Hash-keyed cache wrapping `RevealedSdfBuilder` (FOG-03).
///
/// Same `(discs, viewport)` key returns the cached `ui.Image`; different keys
/// trigger a rebuild and dispose the prior image. Plan 03-03 ships the
/// implementation; this Wave 0 stub exposes the surface downstream callers
/// need (FogLayer, ShaderSanityScreen).
class SdfCache {
  SdfCache({required SdfRebuildLogger rebuildLogger}) : _rebuildLogger = rebuildLogger;

  /// Wired through here so downstream call sites (FogLayer.initState,
  /// ShaderSanityScreen) can construct the cache with the right logger;
  /// Plan 03-03 starts emitting rebuild samples to it.
  // ignore: unused_field
  final SdfRebuildLogger _rebuildLogger;

  /// Returns the cached SDF image for `(discs, viewport)` or builds a new one.
  /// Stub throws — Plan 03-03 ships the cache + builder integration.
  Future<ui.Image> getOrBuild({required List<RevealDisc> discs, required MirkViewportBbox viewport}) {
    throw UnimplementedError('SdfCache.getOrBuild — Plan 03-03');
  }

  /// Disposes the cached `ui.Image` (if any). Plan 03-03 wires this so the
  /// FogLayer.dispose chain can release GPU memory deterministically.
  void dispose() {
    // Plan 03-03: dispose cached ui.Image.
  }
}
