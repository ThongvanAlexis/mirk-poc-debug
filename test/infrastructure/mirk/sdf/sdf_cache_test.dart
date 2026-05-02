// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/domain/mirk/mirk_viewport_bbox.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';

/// FOG-03 — SdfCache hit/miss semantics.
///
/// Wave 0 contract: these tests compile against the Plan 03-01 stub (which
/// throws on getOrBuild) and report RED until Plan 03-03 ships the cache +
/// builder integration.
///
/// PERF-08 (Plan 03.1-05) augments this group with two viewport-quantisation
/// tests: sub-quantisation drift must HIT the cache; super-quantisation drift
/// must MISS. Pre-Plan-03.1-05 the raw bbox doubles invalidated the cache
/// per-paint during pan (12-115 rebuilds/sec per 03.1-FALSIFICATION.md
/// SDF Anomaly despite constant disc count).
void main() {
  // Logger.root must be at FINE or below for INFO-level rollup emissions to
  // surface through Logger.root.onRecord; default Level.WARNING swallows them.
  // Same gotcha as `sdf_rebuild_logger_test.dart`. Required by the PERF-08
  // tests below (which subscribe to the logger's emit stream to count
  // rebuilds across two getOrBuild calls).
  setUpAll(() {
    Logger.root.level = Level.ALL;
  });

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

    test('PERF-08 — same disc set + sub-quantisation viewport drift produces ONE rebuild (cache HIT)', () async {
      // Per 03.1-FALSIFICATION.md SDF Anomaly, the pre-Plan-03.1-05 cache key
      // included raw viewport doubles; per-paint micro-drift during pan
      // produced 12-115 rebuilds/sec despite constant disc count. The fix
      // quantises the bbox edges to 1e-4 lat/lon (~11 m at equator) so
      // sub-quantisation drift no longer invalidates the key.
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.sdf').listen(captured.add);
      try {
        // 100 ms rollup interval — same test seam as sdf_rebuild_logger_test.dart Test 1.
        final logger = SdfRebuildLogger(rollupInterval: const Duration(milliseconds: 100));
        logger.start();
        addTearDown(logger.stop);
        final cache = SdfCache(rebuildLogger: logger);
        addTearDown(cache.dispose);

        final discs = <RevealDisc>[_disc(id: 'rvd_a')];
        final viewportA = MirkViewportBbox(south: 48.50, west: 2.60, north: 48.57, east: 2.72);
        // Sub-quantisation drift: shift each edge by 5e-6 lat/lon (well under
        // the 1e-4 grid; rounds to the SAME quantised value as viewportA).
        final viewportB = MirkViewportBbox(south: 48.500005, west: 2.600005, north: 48.570005, east: 2.720005);

        // First call → MISS (cache empty); second call → HIT (sub-quantisation drift).
        await cache.getOrBuild(discs: discs, viewport: viewportA);
        await cache.getOrBuild(discs: discs, viewport: viewportB);

        // Wait > 2 rollup intervals so the timer fires deterministically and any
        // buffered rebuilds emit. Stop the logger to flush a final rollup.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        logger.stop();

        // Sum rebuildCount across all captured ROLLUP lines (JSON-shaped).
        // The donor RevealedSdfBuilder also emits non-JSON status lines on
        // the same logger name (`infrastructure.mirk.sdf`); filter those out
        // by checking the JSON-object prefix.
        final totalRebuilds = captured.where((rec) => rec.message.startsWith('{')).fold<int>(0, (acc, rec) {
          final parsed = json.decode(rec.message) as Map<String, Object?>;
          return acc + (parsed['rebuildCount']! as int);
        });
        expect(
          totalRebuilds,
          equals(1),
          reason: 'PERF-08: sub-quantisation viewport drift must NOT trigger a second rebuild (cache HIT — total rebuilds across both calls == 1).',
        );
      } finally {
        await sub.cancel();
      }
    });

    test('PERF-08 — same disc set + super-quantisation viewport drift produces TWO rebuilds (cache MISS)', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.sdf').listen(captured.add);
      try {
        final logger = SdfRebuildLogger(rollupInterval: const Duration(milliseconds: 100));
        logger.start();
        addTearDown(logger.stop);
        final cache = SdfCache(rebuildLogger: logger);
        addTearDown(cache.dispose);

        final discs = <RevealDisc>[_disc(id: 'rvd_a')];
        final viewportA = MirkViewportBbox(south: 48.50, west: 2.60, north: 48.57, east: 2.72);
        // Super-quantisation drift: shift by 5e-3 lat/lon (well over the 1e-4
        // grid; rounds to a DIFFERENT quantised value than viewportA).
        final viewportB = MirkViewportBbox(south: 48.505, west: 2.605, north: 48.575, east: 2.725);

        await cache.getOrBuild(discs: discs, viewport: viewportA);
        await cache.getOrBuild(discs: discs, viewport: viewportB);

        await Future<void>.delayed(const Duration(milliseconds: 250));
        logger.stop();

        // Filter for JSON-shaped rollup lines (the donor RevealedSdfBuilder
        // also emits non-JSON status lines on the same logger name).
        final totalRebuilds = captured.where((rec) => rec.message.startsWith('{')).fold<int>(0, (acc, rec) {
          final parsed = json.decode(rec.message) as Map<String, Object?>;
          return acc + (parsed['rebuildCount']! as int);
        });
        expect(
          totalRebuilds,
          equals(2),
          reason: 'PERF-08: super-quantisation viewport drift MUST trigger a second rebuild (cache MISS — total rebuilds across both calls == 2).',
        );
      } finally {
        await sub.cancel();
      }
    });
  });
}

RevealDisc _disc({required String id}) => RevealDisc(id: id, sessionId: 'poc', lat: 48.54, lon: 2.66, radiusMeters: 25.0, fixedAtUtc: DateTime.utc(2026, 5, 1));
