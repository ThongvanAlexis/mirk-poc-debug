// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/dev_marker_logger.dart';

/// Plan 03.1-09-CORR — DevMarkerLogger unit tests.
///
/// Validates the JSONL contract the post-walk grep pipeline depends on:
/// every `Logger('infrastructure.mirk.dev_marker').info(...)` line must be a
/// valid JSON object with exactly the keys `event`, `tag`, `epochMs` and the
/// types the correlator expects.
void main() {
  // Logger.root must be at FINE or below for INFO-level emissions to surface
  // through Logger.root.onRecord; default Level.WARNING swallows INFO lines.
  // Same convention as sdf_rebuild_logger_test.dart and the rest of the
  // infrastructure.mirk.* test suite.
  setUpAll(() {
    Logger.root.level = Level.ALL;
  });

  group('DevMarkerLogger.emit', () {
    test('emits a single INFO record on the infrastructure.mirk.dev_marker logger', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.dev_marker').listen(captured.add);
      try {
        DevMarkerLogger.emit(tag: 'steppy_translation');
        // onRecord delivery is microtask-scheduled — pump the event loop once.
        await Future<void>.delayed(Duration.zero);
        expect(captured, hasLength(1));
        expect(captured.single.level, equals(Level.INFO));
        expect(captured.single.loggerName, equals('infrastructure.mirk.dev_marker'));
      } finally {
        await sub.cancel();
      }
    });

    test('payload is a JSON object with event=dev_marker, the supplied tag, and an epochMs near now', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.dev_marker').listen(captured.add);
      try {
        final beforeMs = DateTime.now().millisecondsSinceEpoch;
        DevMarkerLogger.emit(tag: 'steppy_translation');
        await Future<void>.delayed(Duration.zero);
        final afterMs = DateTime.now().millisecondsSinceEpoch;
        expect(captured, hasLength(1));
        final decoded = json.decode(captured.single.message) as Map<String, Object?>;
        expect(decoded['event'], equals('dev_marker'));
        expect(decoded['tag'], equals('steppy_translation'));
        // Verify int + plausible bound (no clock skew tolerance — the logger
        // reads DateTime.now() once, must land between before/after).
        final epochMs = decoded['epochMs'];
        expect(epochMs, isA<int>());
        expect(epochMs, greaterThanOrEqualTo(beforeMs));
        expect(epochMs, lessThanOrEqualTo(afterMs));
      } finally {
        await sub.cancel();
      }
    });

    test('two emits in a row produce two distinct records (no buffering)', () async {
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.where((r) => r.loggerName == 'infrastructure.mirk.dev_marker').listen(captured.add);
      try {
        DevMarkerLogger.emit(tag: 'steppy_translation');
        DevMarkerLogger.emit(tag: 'rotation_fog_gap');
        await Future<void>.delayed(Duration.zero);
        expect(captured, hasLength(2));
        final firstTag = (json.decode(captured[0].message) as Map<String, Object?>)['tag'];
        final secondTag = (json.decode(captured[1].message) as Map<String, Object?>)['tag'];
        expect(firstTag, equals('steppy_translation'));
        expect(secondTag, equals('rotation_fog_gap'));
      } finally {
        await sub.cancel();
      }
    });
  });
}
