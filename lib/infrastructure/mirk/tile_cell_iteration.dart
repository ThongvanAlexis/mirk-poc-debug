// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;
import 'dart:ui' show Path, PathOperation, Rect, Size;

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';

import 'mirk_projection.dart';

/// Builds a SINGLE composite fog Path covering the entire viewport rect
/// with every [RevealDisc] subtracted as a circular hole — the BUG-010
/// Option B continuous-geometry fog clip path. Phase 09 Commit 5
/// retired the bitmap-based `buildFogClipPath` / `buildViewportFogClipPath`
/// helpers along with the rest of the cell-bitmap reveal layer; this
/// function is now the single source of truth for "what region is fog
/// this frame".
///
/// The returned path is `viewportRect − union(discCircles_in_screen_space)`.
/// Each disc's screen-space radius is computed from the viewport's
/// average metres-per-pixel, mirroring [`RevealedSdfBuilder.buildFromDiscs`]'s
/// projection so the clip path and the SDF agree on disc extents to
/// within sub-pixel precision.
///
/// ## Inputs
///
///   * [discs] — every disc the SDF builder will consume this frame.
///     Empty list yields a non-empty path equal to the viewport rect
///     (whole canvas reads as fog — there is nothing revealed).
///   * [viewport] / [canvasSize] — projection inputs. Same convention as
///     the prior bitmap helper: viewport.north → screen y=0,
///     viewport.south → screen y=canvasSize.height.
///
/// ## Returns
///
/// A non-null [Path]. With [discs] empty the path equals the viewport
/// rect; with at least one intersecting disc, the path is the rect
/// minus the union of disc circles. Caller still checks
/// `path.getBounds().isEmpty` to short-circuit (rare — the viewport
/// rect would have to be degenerate).
Path buildViewportFogClipPathFromDiscs({required Iterable<RevealDisc> discs, required MirkViewportBbox viewport, required Size canvasSize}) {
  final viewportRect = Path()..addRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height));

  final dLat = viewport.north - viewport.south;
  final dLon = viewport.east - viewport.west;
  if (dLat <= 0 || dLon <= 0 || canvasSize.width <= 0 || canvasSize.height <= 0) {
    // Degenerate viewport — fog covers the (degenerate) rect, no holes.
    return viewportRect;
  }

  // Mean-latitude longitude scale + geometric-mean metres-per-pixel
  // — matches `RevealedSdfBuilder.buildFromDiscs` so the clip-path edge
  // and the SDF zero-isoline coincide.
  final meanLatRad = (viewport.south + viewport.north) * 0.5 * math.pi / 180.0;
  final cosMeanLat = math.cos(meanLatRad);
  final metersPerPixelY = (dLat * kMetersPerDegreeLat) / canvasSize.height;
  final metersPerPixelX = (dLon * kMetersPerDegreeLat * cosMeanLat) / canvasSize.width;
  final metersPerPixel = math.sqrt(metersPerPixelX * metersPerPixelY);
  if (metersPerPixel <= 0) return viewportRect;

  final holesPath = Path();
  var hasAnyHole = false;
  for (final disc in discs) {
    if (!disc.intersectsBbox(viewport)) continue;
    final centre = MirkProjection.latLonToScreen(lat: disc.lat, lon: disc.lon, viewport: viewport, size: canvasSize);
    final radiusPx = disc.radiusMeters / metersPerPixel;
    if (radiusPx <= 0) continue;
    holesPath.addOval(Rect.fromCircle(center: centre, radius: radiusPx));
    hasAnyHole = true;
  }
  if (!hasAnyHole) return viewportRect;
  return Path.combine(PathOperation.difference, viewportRect, holesPath);
}
