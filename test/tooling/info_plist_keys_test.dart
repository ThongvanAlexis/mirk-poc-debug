// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Verifies the iOS `Info.plist` carries the keys MirkFall POC depends on:
///
/// - AUTH-05: `NSLocationWhenInUseUsageDescription` is present with non-empty
///   FR rationale, AND `NSLocationAlwaysAndWhenInUseUsageDescription` is
///   ABSENT (POC scope is whenInUse only — Always permission would silently
///   broaden the iOS prompt and burn a SideStore App-ID slot if added later).
/// - AUTH-06: `ITSAppUsesNonExemptEncryption=false` (export-compliance gate;
///   without it App Store Connect uploads block on a manual encryption form).
/// - Pitfall E (RESEARCH.md): `CADisableMinimumFrameDurationOnPhone=true` —
///   without this key, iOS caps Flutter at 60 Hz on non-Apple-team apps even
///   on ProMotion devices, which would invalidate Phase 2's 90 Hz FPS gate.
///
/// Uses regex on the plist XML rather than an XML parser (`package:xml`) to
/// avoid pulling in a new transitive dependency for one test file. The regex
/// covers all four assertions; a future plan can swap to `package:xml` if
/// assertions get more sophisticated.
void main() {
  // Locate ios/Runner/Info.plist relative to repo root. `flutter test` runs
  // from the repo root, so a relative path works on every CI runner.
  final String plistFilename = p.join('ios', 'Runner', 'Info.plist');
  late String contents;

  setUpAll(() {
    final File f = File(plistFilename);
    expect(f.existsSync(), isTrue, reason: 'Info.plist must exist at $plistFilename');
    contents = f.readAsStringSync();
  });

  group('AUTH-05 — NSLocationWhenInUseUsageDescription present + non-empty', () {
    test('key is present', () {
      expect(contents, contains('<key>NSLocationWhenInUseUsageDescription</key>'));
    });

    test('value is a non-empty string', () {
      // Match the next <string>...</string> after the key. Plist XML is
      // strictly key-then-value pairs.
      final RegExp keyToValueRegex = RegExp(
        r'<key>NSLocationWhenInUseUsageDescription</key>\s*<string>([^<]+)</string>',
        multiLine: true,
      );
      final RegExpMatch? match = keyToValueRegex.firstMatch(contents);
      expect(match, isNotNull, reason: 'NSLocationWhenInUseUsageDescription must be followed by a <string> element');
      expect(match!.group(1)!.trim(), isNotEmpty, reason: 'rationale string must not be blank — App Store rejects empty usage descriptions');
    });
  });

  group('AUTH-05 — NSLocationAlwaysAndWhenInUseUsageDescription absent', () {
    test('key is NOT present (POC scope is whenInUse only)', () {
      expect(
        contents,
        isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')),
        reason: 'Always permission is out of POC scope; adding it broadens the iOS prompt and risks SideStore App-ID burn',
      );
    });
  });

  group('AUTH-06 — ITSAppUsesNonExemptEncryption=false', () {
    test('key is present with <false/> value', () {
      final RegExp regex = RegExp(
        r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false\s*/>',
        multiLine: true,
      );
      expect(
        regex.hasMatch(contents),
        isTrue,
        reason: 'Without ITSAppUsesNonExemptEncryption=false, App Store Connect blocks builds on the export-compliance form',
      );
    });
  });

  group('Pitfall E — ProMotion 120 Hz unlock', () {
    test('CADisableMinimumFrameDurationOnPhone=true is present', () {
      final RegExp regex = RegExp(
        r'<key>CADisableMinimumFrameDurationOnPhone</key>\s*<true\s*/>',
        multiLine: true,
      );
      expect(
        regex.hasMatch(contents),
        isTrue,
        reason: 'Without this key, iOS caps Flutter at 60 Hz on non-Apple-team apps even on ProMotion devices.',
      );
    });
  });
}
