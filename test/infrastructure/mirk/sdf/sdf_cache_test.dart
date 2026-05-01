// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';

/// FOG-03 — SdfCache hit/miss semantics.
///
/// Wave 0 contract: these tests compile against the Plan 03-01 stub (which
/// throws on getOrBuild) and report RED until Plan 03-03 ships the cache +
/// builder integration.
void main() {
  group('SdfCache (FOG-03)', () {
    test('same (discs, viewport) returns identical ui.Image (cache hit)', () async {
      final cache = SdfCache(rebuildLogger: SdfRebuildLogger());
      final discs = <RevealDisc>[_disc(id: 'rvd_a')];
      final viewport = MirkViewportBbox(south: 48.50, west: 2.60, north: 48.57, east: 2.72);
      final img1 = await cache.getOrBuild(discs: discs, viewport: viewport);
      final img2 = await cache.getOrBuild(discs: discs, viewport: viewport);
      expect(identical(img1, img2), isTrue, reason: 'cache hit must return the same ui.Image instance');
    });

    test('different disc list triggers rebuild (cache miss)', () async {
      final cache = SdfCache(rebuildLogger: SdfRebuildLogger());
      final viewport = MirkViewportBbox(south: 48.50, west: 2.60, north: 48.57, east: 2.72);
      final img1 = await cache.getOrBuild(
        discs: <RevealDisc>[_disc(id: 'rvd_a')],
        viewport: viewport,
      );
      final img2 = await cache.getOrBuild(
        discs: <RevealDisc>[
          _disc(id: 'rvd_a'),
          _disc(id: 'rvd_b'),
        ],
        viewport: viewport,
      );
      expect(identical(img1, img2), isFalse);
    });

    test('different viewport triggers rebuild (cache miss)', () async {
      final cache = SdfCache(rebuildLogger: SdfRebuildLogger());
      final discs = <RevealDisc>[_disc(id: 'rvd_a')];
      final img1 = await cache.getOrBuild(discs: discs, viewport: MirkViewportBbox(south: 48.50, west: 2.60, north: 48.57, east: 2.72));
      final img2 = await cache.getOrBuild(discs: discs, viewport: MirkViewportBbox(south: 48.51, west: 2.60, north: 48.57, east: 2.72));
      expect(identical(img1, img2), isFalse);
    });
  });
}

RevealDisc _disc({required String id}) => RevealDisc(id: id, sessionId: 'poc', lat: 48.54, lon: 2.66, radiusMeters: 25.0, fixedAtUtc: DateTime.utc(2026, 5, 1));
