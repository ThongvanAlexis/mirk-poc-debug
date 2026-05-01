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
/// moment any `lib/**/*.dart` file references the forbidden API in code, so
/// future maintainers can't reintroduce the regression silently.
///
/// Mirrors the parent project's `tool/test/check_headers_test.dart` static-
/// source-scan pattern. Runs via `dart test tool/test/` (the existing CI
/// step's directory glob — no workflow YAML edit needed for auto-discovery).
///
/// **Comment-aware scan:** This gate strips Dart line comments (`//` and
/// `///`) and block comments (`/* ... */`) before checking. Docstrings
/// referencing the forbidden API by name (e.g. "do NOT call
/// `Geolocator.getLastKnownPosition`") are educational and allowed; only
/// actual code references trigger the gate. This was hardened in Plan 02-03
/// after the original substring-only scan over-matched on the Plan-prescribed
/// docstring.
void main() {
  test('LOC-03: lib/ never references Geolocator.getLastKnownPosition in code', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib/ directory must exist for the gate to run.');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      final stripped = _stripDartComments(src);
      if (stripped.contains('getLastKnownPosition')) {
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

/// Strips Dart `//` line comments, `///` doc comments, and `/* ... */` block
/// comments from [src] so the LOC-03 gate only inspects executable code.
///
/// Naive but sufficient for the project's GOSL-headed `.dart` files: no
/// string-literal escaping, no nested block-comment handling. Edge cases (a
/// `//` inside a string literal) would over-strip but don't affect the
/// substring search this is feeding — false negatives in code mention are
/// the only theoretical risk and would require constructing a string
/// literally equal to `getLastKnownPosition`, which is itself the forbidden
/// pattern.
String _stripDartComments(String src) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < src.length) {
    // Block comment: /* ... */
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '*') {
      final end = src.indexOf('*/', i + 2);
      if (end == -1) {
        i = src.length; // unterminated — drop the rest
      } else {
        i = end + 2;
      }
      continue;
    }
    // Line comment: // ... \n  (also covers /// docstrings)
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '/') {
      final end = src.indexOf('\n', i + 2);
      if (end == -1) {
        i = src.length;
      } else {
        i = end; // keep the newline so structure is preserved
      }
      continue;
    }
    buffer.write(src[i]);
    i++;
  }
  return buffer.toString();
}
