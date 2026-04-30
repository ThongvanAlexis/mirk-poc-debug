// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async' show Completer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:logging/logging.dart';
import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';

final Logger _log = Logger('infrastructure.mirk.sdf');

/// Builds a CPU-side signed distance field (SDF) of the revealed area
/// for a given viewport, encoded as a `ui.Image` ready to be passed to
/// the fog shader as `sampler2D`.
///
/// Phase 09 BUG-009 (TIER 2). The SDF lets the shader's two-stop
/// watercolour boundary, curl-rotated edge field, and density-modulation
/// near the boundary react to the actual revealed silhouette — without
/// the renderer having to recompute geometry on the GPU.
///
/// Phase 09 BUG-010 Option B Commit 5 collapsed the builder to the
/// continuous-geometry path. Reveals are now exclusively a list of
/// [RevealDisc]s; the cell-bitmap chamfer path (and its `_markTileInSeed` /
/// `_chamferSignedDistance` helpers) are gone.
///
/// ## Sign convention
///
/// The SDF is stored in the R channel as an unsigned byte, but encodes
/// a SIGNED distance via a midpoint-128 convention:
///
///   - Byte value `128` → distance 0 (on the boundary).
///   - Bytes `0..127` → INSIDE the revealed area (clear), with `0`
///     being the deepest interior.
///   - Bytes `129..255` → INSIDE the fog area (unrevealed), with `255`
///     being the farthest fog.
///
/// The shader reads `texture(uSdf, uv).r * 2.0 - 1.0` to recover a
/// signed distance in [-1, 1].
///
/// ## Resolution
///
/// 256×256 (configurable via [kMirkFogSdfResolution]). The resolution
/// is independent of the viewport pixel size — the shader samples with
/// bilinear filtering, so a 256² SDF over a 1080×1920 viewport still
/// produces smooth distance gradients.
///
/// ## When to rebuild
///
/// The SDF only depends on the union of revealed discs + the viewport
/// bbox. The renderer should rebuild it when EITHER changes:
///
///   - The user walks → new disc fixed_at → disc list changes.
///   - The user pans/zooms → viewport bbox changes → projection of the
///     same discs onto the SDF plane shifts.
///
/// Rebuilding every frame is wasted work because GPS fixes arrive at
/// most once per second and viewport changes are throttled. The
/// renderer hashes both inputs and reuses the cached `ui.Image` when
/// the hash matches.
class RevealedSdfBuilder {
  /// Constructs a builder. Stateless — exists only as a class so tests
  /// can mock it via constructor injection in the renderer (Phase 09
  /// dependency-injection convention).
  const RevealedSdfBuilder();

  /// Resolution of the produced SDF image (square). Cached as a
  /// constant so callers can size their cache keys without recomputing.
  static const int resolution = kMirkFogSdfResolution;

  /// Builds an SDF `ui.Image` from a list of [RevealDisc]s — the
  /// continuous-geometry input replaced the chamfer/bitmap path in
  /// BUG-010 Option B Commit 5. The returned image follows the SAME
  /// byte encoding as the prior bitmap path (R-channel, midpoint-128,
  /// distance scaled to `[0..255]` via `distMaxPixels = resolution * 0.5`)
  /// so the consuming shader needs no change.
  ///
  /// Algorithm (analytic, no chamfer):
  ///
  ///   1. Empty `discs` → return all-fog SDF (`_emptySdfImage()`).
  ///   2. For each disc whose extent intersects [viewport]:
  ///       a. Project its centre to seed-grid coordinates.
  ///       b. Compute an anisotropic padded bounding box that accounts
  ///          for the latitude-dependent difference between
  ///          `metersPerPixelX` and `metersPerPixelY`.
  ///       c. Iterate the padded bbox and compute distance in METRES
  ///          (`dxMeters`, `dyMeters`, `distMeters`), then convert
  ///          back to pixel-equivalent units for the encoding step:
  ///          `candidate = (distMeters - disc.radiusMeters) / metersPerPixel`.
  ///   3. Encode `signed` to bytes using the same midpoint-128 mapping.
  ///
  /// BUG-011 fix: the inner loop used to compute pixel-space Euclidean
  /// distance (`sqrt(dx² + dy²)`), which produced a north-south oval at
  /// non-equatorial latitudes. Switching to metric-space distance makes
  /// the reveal boundary a true circle.
  ///
  /// Cost: per disc ≈ `(2·padPixels)²` pixel updates. For
  /// typical viewport scales (city-wide to building-scale), the pad is
  /// dominated by `distMaxPixels = 128`, so ~67 k updates per disc. A 4-hour
  /// session post-compaction holds < 1 k discs in viewport → ~67 M ops,
  /// well under 16 ms on Flutter's 2026 hardware. A spatial index would
  /// help for very large sessions; tagged in a TODO below for follow-up.
  ///
  /// [discs] iteration order does not affect the output (commutative `min`).
  // TODO(perf): for sessions with > a few thousand viewport-resident discs,
  // index discs in a uniform grid keyed by seed-grid pixel and only update
  // pixels in cells the disc actually touches. The current padded-bbox loop
  // is already cheap enough for the 4-hour-session budget but will dominate
  // once compaction is loosened or sessions span hours.
  Future<ui.Image> buildFromDiscs({required Iterable<RevealDisc> discs, required MirkViewportBbox viewport}) async {
    final discList = discs.toList(growable: false);
    final stopwatch = Stopwatch()..start();
    _log.fine(
      'buildFromDiscs(): start — ${discList.length} discs · viewport=[${viewport.south.toStringAsFixed(4)}, ${viewport.west.toStringAsFixed(4)} → ${viewport.north.toStringAsFixed(4)}, ${viewport.east.toStringAsFixed(4)}]',
    );
    if (discList.isEmpty) {
      _log.fine('buildFromDiscs(): empty disc list → all-fog SDF');
      return _emptySdfImage();
    }
    final n = resolution;
    final dLat = viewport.north - viewport.south;
    final dLon = viewport.east - viewport.west;
    if (dLat == 0 || dLon == 0) {
      _log.warning('buildFromDiscs(): degenerate viewport (dLat=$dLat dLon=$dLon) → all-fog SDF');
      return _emptySdfImage();
    }

    // Metres-per-pixel along each axis at the viewport's mean latitude.
    // Using the mean latitude (not the disc's own latitude) keeps the
    // metres-to-pixel mapping consistent across all discs in this build —
    // the SDF is rendered in viewport-normalised pixel space, so the
    // pixel cost of a metre is a property of the viewport, not the disc.
    final meanLatRad = (viewport.south + viewport.north) * 0.5 * math.pi / 180.0;
    final metersPerDegreeLon = kMetersPerDegreeLat * math.cos(meanLatRad);
    final metersPerPixelY = (dLat * kMetersPerDegreeLat) / n;
    final metersPerPixelX = (dLon * metersPerDegreeLon) / n;
    // Geometric mean: preserves disc area at the cost of a small
    // aspect-ratio compromise far from the equator. At MirkFall's
    // city-scale viewports (dLat ≪ 1°) the two axes agree to within a
    // fraction of a percent at any latitude north of the polar clamp.
    final metersPerPixel = math.sqrt(metersPerPixelX * metersPerPixelY);

    final distMaxPixels = n * 0.5;
    // Far-init to 1e9 so the first disc whose padded bbox touches a pixel
    // always wins the `min`. After the loop, any pixel still at 1e9 means
    // no disc reached it → encoded as max-fog (byte = 255).
    final signed = Float32List(n * n);
    for (var i = 0; i < n * n; i++) {
      signed[i] = 1e9;
    }

    var intersectingDiscCount = 0;
    for (final disc in discList) {
      if (!disc.intersectsBbox(viewport)) continue;
      intersectingDiscCount++;

      // Project disc centre to seed-grid pixel coordinates. North → row 0.
      final cx = (disc.lon - viewport.west) / dLon * n;
      final cy = (viewport.north - disc.lat) / dLat * n;
      // Anisotropic padding: at non-equatorial latitudes, one pixel of
      // latitude covers more metres than one pixel of longitude (by
      // 1/cos(lat)). The padded bbox must account for this difference
      // so that the distance computation reaches all pixels that could
      // be within (disc.radiusMeters + distMaxMeters) in metric space.
      final paddedMeters = disc.radiusMeters + distMaxPixels * metersPerPixel;
      final xPadPixels = paddedMeters / metersPerPixelX;
      final yPadPixels = paddedMeters / metersPerPixelY;
      final xMin = math.max(0, (cx - xPadPixels).floor());
      final xMax = math.min(n, (cx + xPadPixels).ceil());
      final yMin = math.max(0, (cy - yPadPixels).floor());
      final yMax = math.min(n, (cy + yPadPixels).ceil());
      if (xMin >= xMax || yMin >= yMax) continue;

      for (var y = yMin; y < yMax; y++) {
        // Pixel-centre sampling — distance computed in METRES, not pixels,
        // so the SDF boundary is a true metric circle at any latitude
        // (BUG-011 fix: pixel-space distance produced a north-south oval).
        final dy = (y + 0.5) - cy;
        final dyMeters = dy * metersPerPixelY;
        final rowOffset = y * n;
        for (var x = xMin; x < xMax; x++) {
          final dx = (x + 0.5) - cx;
          final dxMeters = dx * metersPerPixelX;
          final distMeters = math.sqrt(dxMeters * dxMeters + dyMeters * dyMeters);
          // Convert back to pixel-equivalent units (geometric-mean scale)
          // for the encoding step's distMaxPixels normalisation.
          final candidate = (distMeters - disc.radiusMeters) / metersPerPixel;
          if (candidate < signed[rowOffset + x]) {
            signed[rowOffset + x] = candidate;
          }
        }
      }
    }

    // Encode to bytes: same midpoint-128 mapping as the legacy path.
    final pixels = Uint8List(n * n * 4);
    var insideCount = 0;
    for (var i = 0; i < n * n; i++) {
      final clamped = signed[i].clamp(-distMaxPixels, distMaxPixels);
      final byte = (128.0 + (clamped / distMaxPixels) * 127.0).clamp(0.0, 255.0).toInt();
      if (signed[i] < 0) insideCount++;
      final idx = i * 4;
      pixels[idx] = byte;
      pixels[idx + 1] = byte;
      pixels[idx + 2] = byte;
      pixels[idx + 3] = 255;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, n, n, ui.PixelFormat.rgba8888, completer.complete);
    final image = await completer.future;
    final insidePct = (100.0 * insideCount / (n * n)).toStringAsFixed(1);
    _log.fine(
      'buildFromDiscs(): done in ${stopwatch.elapsedMilliseconds}ms — '
      '${discList.length} discs · $intersectingDiscCount intersected · '
      'inside=$insidePct% · ui.Image ${image.width}x${image.height}',
    );
    return image;
  }

  /// Returns an all-fog SDF (every byte = 255). Used for empty inputs
  /// + degenerate viewports — the shader then renders uniform fog
  /// without boundary effects.
  Future<ui.Image> _emptySdfImage() {
    final n = resolution;
    final pixels = Uint8List(n * n * 4);
    // Saturated R/G/B encodes "max fog distance"; alpha = 255 keeps the
    // texture opaque so the shader's sampler reads it cleanly.
    for (var i = 0; i < n * n; i++) {
      final idx = i * 4;
      pixels[idx] = 255;
      pixels[idx + 1] = 255;
      pixels[idx + 2] = 255;
      pixels[idx + 3] = 255;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, n, n, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }
}
