// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';
import 'package:mirk_poc_debug/infrastructure/logging/file_logger.dart';

void main() {
  group('FileLogger filename format (POC adaptation #1 — UTC ISO-8601 basic)', () {
    test('canonical case — DateTime.utc(2026, 4, 30, 14, 25, 3) → 20260430T142503Z', () {
      expect(FileLogger.formatFilenameTimestampForTest(DateTime.utc(2026, 4, 30, 14, 25, 3)), '20260430T142503Z');
    });

    test('local-time input is converted to UTC before formatting', () {
      // Build a known UTC instant; convert to local for the input. The format
      // function MUST re-convert to UTC internally so the resulting filename
      // stamps the UTC date/time, not the local one.
      final utcInstant = DateTime.utc(2026, 4, 30, 21, 30, 0);
      final localInput = utcInstant.toLocal();
      expect(
        FileLogger.formatFilenameTimestampForTest(localInput),
        '20260430T213000Z',
        reason: 'Filename MUST stamp UTC (not local) — defeats day-rollover ambiguity for an iOS sideload device that can be in any timezone.',
      );
    });

    test('zero padding on every component', () {
      expect(FileLogger.formatFilenameTimestampForTest(DateTime.utc(2026, 1, 5, 3, 7, 9)), '20260105T030709Z');
    });
  });
}
