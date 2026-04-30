// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../check_licenses.dart' as check_licenses;

/// Fixture-based tests for `tool/check_licenses.dart`.
///
/// Each test builds a tempDir that looks enough like a Dart project root to
/// make the checker happy: `pubspec.lock` + `.dart_tool/package_config.json`
/// + per-package sub-directories carrying a LICENSE file. We then assert on
/// the exit code returned by `runCheck` — the CI contract.
const String _mitLicense = '''MIT License

Copyright (c) 2026 Example

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
''';

const String _gplLicense = '''                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.
''';

const String _bsd3License = '''Copyright (c) 2026, Example Author
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.
''';

Future<void> _writeFixture(Directory root, Map<String, String> licensesByPackage) async {
  // pubspec.lock with one entry per fixture package, source: hosted.
  final StringBuffer buf = StringBuffer()..writeln('packages:');
  for (final String name in licensesByPackage.keys) {
    buf
      ..writeln('  $name:')
      ..writeln('    dependency: "direct main"')
      ..writeln('    description:')
      ..writeln('      name: $name')
      ..writeln('      url: "https://pub.dev"')
      ..writeln('    source: hosted')
      ..writeln('    version: "1.0.0"');
  }
  buf.writeln('sdks:');
  buf.writeln('  dart: ">=3.0.0 <4.0.0"');
  await File(p.join(root.path, 'pubspec.lock')).writeAsString(buf.toString());

  // package_config.json + per-package LICENSE.
  final Directory dartToolDir = Directory(p.join(root.path, '.dart_tool'));
  await dartToolDir.create(recursive: true);
  final List<Map<String, Object>> configPackages = <Map<String, Object>>[];
  for (final MapEntry<String, String> entry in licensesByPackage.entries) {
    final Directory pkgDir = Directory(p.join(root.path, entry.key));
    await pkgDir.create(recursive: true);
    await File(p.join(pkgDir.path, 'LICENSE')).writeAsString(entry.value);
    configPackages.add(<String, Object>{
      'name': entry.key,
      // rootUri relative to .dart_tool/ → go up one, then into pkg dir.
      'rootUri': '../${entry.key}',
      'packageUri': 'lib/',
    });
  }
  await File(p.join(dartToolDir.path, 'package_config.json')).writeAsString(jsonEncode(<String, Object>{'configVersion': 2, 'packages': configPackages}));
}

void main() {
  group('check_licenses.runCheck', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('check_licenses_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns 0 when every package is under an allowed SPDX', () async {
      await _writeFixture(tempDir, <String, String>{'pkg_mit': _mitLicense, 'pkg_bsd3': _bsd3License});

      final int code = await check_licenses.runCheck(<String>[tempDir.path]);
      expect(code, 0);
    });

    test('returns 1 when a GPL package is present', () async {
      await _writeFixture(tempDir, <String, String>{'pkg_mit': _mitLicense, 'pkg_gpl': _gplLicense, 'pkg_bsd3': _bsd3License});

      final int code = await check_licenses.runCheck(<String>[tempDir.path]);
      expect(code, 1);
    });

    test('returns 2 when pubspec.lock is missing', () async {
      // No fixture at all — checker should bail with 2.
      final int code = await check_licenses.runCheck(<String>[tempDir.path]);
      expect(code, 2);
    });

    test('returns 2 when package_config.json is missing', () async {
      // pubspec.lock present but .dart_tool/package_config.json absent —
      // second exit-2 branch that the Phase 01 test suite left uncovered.
      await File(p.join(tempDir.path, 'pubspec.lock')).writeAsString('packages: {}\nsdks:\n  dart: ">=3.0.0 <4.0.0"\n');
      final int code = await check_licenses.runCheck(<String>[tempDir.path]);
      expect(code, 2);
    });

    test('returns 0 when a package name matches _manualOverrides (override wins over LICENSE heuristic)', () async {
      // Exercise the manual-override escape hatch: use a package NAME that is
      // in _manualOverrides (dbus → MPL-2.0-Linux-only), but ship a GPL
      // LICENSE file. The override MUST short-circuit the LICENSE-text scan,
      // otherwise the forbidden-substring path would fire and return 1.
      // If this test ever breaks, the override mechanism has silently stopped
      // working — which would re-introduce the Linux-transitive MPL blocker.
      await _writeFixture(tempDir, <String, String>{'dbus': _gplLicense, 'pkg_mit': _mitLicense});

      final int code = await check_licenses.runCheck(<String>[tempDir.path]);
      expect(code, 0);
    });

    test('returns 0 when a package declares an OR-compound license with an allowed side', () async {
      // Exercise the OR-split logic at runCheck: 'Apache-2.0 OR BSD-3-Clause'
      // must resolve green when at least one side is in _allowedSpdx. Uses
      // the pubspec.yaml license: field path to inject a compound expression
      // directly (LICENSE files never carry OR compounds).
      final StringBuffer lockBuf = StringBuffer()
        ..writeln('packages:')
        ..writeln('  pkg_dual:')
        ..writeln('    dependency: "direct main"')
        ..writeln('    description:')
        ..writeln('      name: pkg_dual')
        ..writeln('      url: "https://pub.dev"')
        ..writeln('    source: hosted')
        ..writeln('    version: "1.0.0"')
        ..writeln('sdks:')
        ..writeln('  dart: ">=3.0.0 <4.0.0"');
      await File(p.join(tempDir.path, 'pubspec.lock')).writeAsString(lockBuf.toString());

      final Directory dartToolDir = Directory(p.join(tempDir.path, '.dart_tool'));
      await dartToolDir.create(recursive: true);
      final Directory pkgDir = Directory(p.join(tempDir.path, 'pkg_dual'));
      await pkgDir.create(recursive: true);
      // pubspec.yaml declares OR-compound, no LICENSE file → the resolver
      // drops through to the pubspec license: field.
      await File(p.join(pkgDir.path, 'pubspec.yaml')).writeAsString('name: pkg_dual\nversion: 1.0.0\nlicense: Apache-2.0 OR BSD-3-Clause\n');
      await File(p.join(dartToolDir.path, 'package_config.json')).writeAsString(
        jsonEncode(<String, Object>{
          'configVersion': 2,
          'packages': <Map<String, Object>>[
            <String, Object>{'name': 'pkg_dual', 'rootUri': '../pkg_dual', 'packageUri': 'lib/'},
          ],
        }),
      );

      final int code = await check_licenses.runCheck(<String>[tempDir.path]);
      expect(code, 0);
    });

    test('returns 1 when a package cannot be resolved (no LICENSE, no pubspec license field)', () async {
      // Build a fixture with one package whose package directory exists but
      // has no LICENSE file and no pubspec license field — exercises the
      // "unresolved" advisory path (runCheck returns 1, not 2).
      final StringBuffer lockBuf = StringBuffer()
        ..writeln('packages:')
        ..writeln('  pkg_unknown:')
        ..writeln('    dependency: "direct main"')
        ..writeln('    description:')
        ..writeln('      name: pkg_unknown')
        ..writeln('      url: "https://pub.dev"')
        ..writeln('    source: hosted')
        ..writeln('    version: "1.0.0"')
        ..writeln('sdks:')
        ..writeln('  dart: ">=3.0.0 <4.0.0"');
      await File(p.join(tempDir.path, 'pubspec.lock')).writeAsString(lockBuf.toString());

      final Directory dartToolDir = Directory(p.join(tempDir.path, '.dart_tool'));
      await dartToolDir.create(recursive: true);
      final Directory pkgDir = Directory(p.join(tempDir.path, 'pkg_unknown'));
      await pkgDir.create(recursive: true);
      // No LICENSE, no pubspec.yaml — resolver returns null, caller adds to
      // unresolved list and returns 1 with the "Add to _manualOverrides" hint.
      await File(p.join(dartToolDir.path, 'package_config.json')).writeAsString(
        jsonEncode(<String, Object>{
          'configVersion': 2,
          'packages': <Map<String, Object>>[
            <String, Object>{'name': 'pkg_unknown', 'rootUri': '../pkg_unknown', 'packageUri': 'lib/'},
          ],
        }),
      );

      final int code = await check_licenses.runCheck(<String>[tempDir.path]);
      expect(code, 1);
    });
  });
}
