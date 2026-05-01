// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';

/// FOG-03 — SdfRebuildLogger 1-second JSONL rollup.
///
/// Plan 03-03 ships the per-second rollup + JSONL emission via
/// `Logger('infrastructure.mirk.sdf')`. Tests use a shorter [rollupInterval]
/// test seam to keep the suite fast — the production default is 1 s
/// (`kPocSdfLogRollupSeconds`).
void main() {
  // Logger.root must be at FINE or below for INFO-level emissions to surface
  // through Logger.root.onRecord; default Level.WARNING swallows INFO lines.
  setUpAll(() {
    Logger.root.level = Level.ALL;
  });

  group('SdfRebuildLogger (FOG-03)', () {
    test('recordRebuild buffers samples; emits one JSONL rollup per active second', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.sdf').listen(captured.add);
      try {
        // Test-seam: 100 ms rollup interval keeps the suite fast. Production
        // default is 1 s (kPocSdfLogRollupSeconds); the rollup logic is
        // identical at any interval.
        final logger = SdfRebuildLogger(rollupInterval: const Duration(milliseconds: 100));
        logger.start();
        logger.recordRebuild(elapsedMs: 1.2, discCount: 5, intersectingDiscCount: 2);
        logger.recordRebuild(elapsedMs: 0.8, discCount: 5, intersectingDiscCount: 2);
        // Wait at least 2 rollup intervals so the timer fires deterministically.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        logger.stop();
        expect(captured, hasLength(greaterThanOrEqualTo(1)));
        final firstLine = captured.first.message;
        expect(firstLine, contains('"rebuildCount":2'));
        expect(firstLine, contains('"discCount":5'));
        expect(firstLine, contains('"intersectingDiscCount":2'));
        expect(firstLine, contains('"medianMs"'));
        expect(firstLine, contains('"p95Ms"'));
        expect(firstLine, contains('"maxMs"'));
        expect(firstLine, contains('"epochSecond"'));
      } finally {
        await sub.cancel();
      }
    });

    test('idle seconds emit no log line', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.sdf').listen(captured.add);
      try {
        final logger = SdfRebuildLogger(rollupInterval: const Duration(milliseconds: 100));
        logger.start();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        logger.stop();
        expect(captured, isEmpty);
      } finally {
        await sub.cancel();
      }
    });

    test('stop flushes pending samples even before a timer tick', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.sdf').listen(captured.add);
      try {
        // Long interval ensures the timer never fires during this test —
        // proves stop() emits the final rollup synchronously.
        final logger = SdfRebuildLogger(rollupInterval: const Duration(seconds: 10));
        logger.start();
        logger.recordRebuild(elapsedMs: 2.5, discCount: 3, intersectingDiscCount: 1);
        logger.stop();
        // stop() emits via _log.info synchronously; onRecord delivery is
        // microtask-scheduled — pump the event loop once.
        await Future<void>.delayed(Duration.zero);
        expect(captured, hasLength(1));
        expect(captured.first.message, contains('"rebuildCount":1'));
        expect(captured.first.message, contains('"discCount":3'));
      } finally {
        await sub.cancel();
      }
    });
  });
}
