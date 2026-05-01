// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io';

import 'package:test/test.dart';

/// LOC-03 static-source CI gate.
///
/// Geolocator.getLastKnownPosition is unreliable on iOS — the plugin returns
/// stale or null values across app cold-restarts (known issue, see
/// flutter-geolocator#XXXX). Phase 2 mandates caching the latest fix from the
/// live `Geolocator.getPositionStream` instead. This test fails the build the
/// moment any `lib/**/*.dart` file references the forbidden API, so future
/// maintainers can't reintroduce the regression silently.
///
/// Mirrors the parent project's `tool/test/check_headers_test.dart` static-
/// source-scan pattern. Runs via `dart test tool/test/` (the existing CI
/// step's directory glob — no workflow YAML edit needed for auto-discovery).
void main() {
  test('LOC-03: lib/ never references Geolocator.getLastKnownPosition', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ directory must exist for the gate to run.');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      if (src.contains('getLastKnownPosition')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'LOC-03 forbids Geolocator.getLastKnownPosition (unreliable on iOS — known plugin issue). '
          'Cache `_lastFix` from the live stream instead. Offenders: $offenders',
    );
  });
}
