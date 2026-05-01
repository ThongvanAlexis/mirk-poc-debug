// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';

/// FOG-03 — SdfRebuildLogger 1-second JSONL rollup.
///
/// Wave 0 contract: these tests compile against the Plan 03-01 stub (which
/// throws on recordRebuild) and report RED until Plan 03-03 ships the
/// per-second rollup + JSONL emission via Logger('infrastructure.mirk.sdf').
void main() {
  group('SdfRebuildLogger (FOG-03)', () {
    test('recordRebuild buffers samples; emits one JSONL rollup per active second', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.sdf').listen(captured.add);
      try {
        final logger = SdfRebuildLogger();
        logger.start();
        logger.recordRebuild(elapsedMs: 1.2, discCount: 5, intersectingDiscCount: 2);
        logger.recordRebuild(elapsedMs: 0.8, discCount: 5, intersectingDiscCount: 2);
        // Wait at least 1 second. Plan 03-03 may switch this test to FakeAsync
        // when it makes the timer injectable.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        logger.stop();
        expect(captured, hasLength(greaterThanOrEqualTo(1)));
        final firstLine = captured.first.message;
        expect(firstLine, contains('"rebuildCount":2'));
        expect(firstLine, contains('"discCount":5'));
        expect(firstLine, contains('"medianMs"'));
        expect(firstLine, contains('"p95Ms"'));
        expect(firstLine, contains('"maxMs"'));
      } finally {
        await sub.cancel();
      }
    });

    test('idle seconds emit no log line', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.sdf').listen(captured.add);
      try {
        final logger = SdfRebuildLogger();
        logger.start();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        logger.stop();
        expect(captured, isEmpty);
      } finally {
        await sub.cancel();
      }
    });
  });
}
