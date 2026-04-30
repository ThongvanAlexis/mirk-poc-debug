// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../check_dependencies_md.dart' as check_deps;

/// Fixture-based tests for `tool/check_dependencies_md.dart`.
const String _lockThreePackages = '''packages:
  a:
    dependency: "direct main"
    description:
      name: a
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  b:
    dependency: "direct main"
    description:
      name: b
      url: "https://pub.dev"
    source: hosted
    version: "2.0.0"
  c:
    dependency: transitive
    description:
      name: c
      url: "https://pub.dev"
    source: hosted
    version: "3.0.0"
sdks:
  dart: ">=3.0.0 <4.0.0"
''';

const String _depsMdComplete = '''# DEPENDENCIES

## Direct dependencies

| Package | Version | License | Source | Telemetry audit | Date |
|---------|---------|---------|--------|-----------------|------|
| a | 1.0.0 | MIT | https://pub.dev/packages/a | No network. | 2026-04-17 |
| b | 2.0.0 | BSD-3-Clause | https://pub.dev/packages/b | No network. | 2026-04-17 |

## Transitive dependencies

| Package | Version | License | Pulled in by | Notes | Date |
|---------|---------|---------|--------------|-------|------|
| c | 3.0.0 | MIT | a | OK | 2026-04-17 |
''';

const String _depsMdMissingAndExtra = '''# DEPENDENCIES

## Direct dependencies

| Package | Version | License | Source | Telemetry audit | Date |
|---------|---------|---------|--------|-----------------|------|
| a | 1.0.0 | MIT | https://pub.dev/packages/a | No network. | 2026-04-17 |
| b | 2.0.0 | BSD-3-Clause | https://pub.dev/packages/b | No network. | 2026-04-17 |
| z | 9.9.9 | MIT | https://pub.dev/packages/z | Ghost package. | 2026-04-17 |
''';

const String _depsMdVersionMismatch = '''# DEPENDENCIES

## Direct dependencies

| Package | Version | License | Source | Telemetry audit | Date |
|---------|---------|---------|--------|-----------------|------|
| a | 1.0.0 | MIT | https://pub.dev/packages/a | No network. | 2026-04-17 |
| b | 1.9.9 | BSD-3-Clause | https://pub.dev/packages/b | Wrong version. | 2026-04-17 |
| c | 3.0.0 | MIT | https://pub.dev/packages/c | OK | 2026-04-17 |
''';

void main() {
  group('check_dependencies_md.runCheck', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('check_deps_md_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns 0 when every lockfile entry is declared with matching version', () async {
      await File(p.join(tempDir.path, 'pubspec.lock')).writeAsString(_lockThreePackages);
      await File(p.join(tempDir.path, 'DEPENDENCIES.md')).writeAsString(_depsMdComplete);

      final int code = await check_deps.runCheck(<String>[tempDir.path]);
      expect(code, 0);
    });

    test('returns 1 when a package is missing and another is extra', () async {
      await File(p.join(tempDir.path, 'pubspec.lock')).writeAsString(_lockThreePackages);
      await File(p.join(tempDir.path, 'DEPENDENCIES.md')).writeAsString(_depsMdMissingAndExtra);

      final int code = await check_deps.runCheck(<String>[tempDir.path]);
      expect(code, 1);
    });

    test('returns 1 when the declared version does not match the lockfile', () async {
      await File(p.join(tempDir.path, 'pubspec.lock')).writeAsString(_lockThreePackages);
      await File(p.join(tempDir.path, 'DEPENDENCIES.md')).writeAsString(_depsMdVersionMismatch);

      final int code = await check_deps.runCheck(<String>[tempDir.path]);
      expect(code, 1);
    });

    test('returns 2 when DEPENDENCIES.md is missing', () async {
      await File(p.join(tempDir.path, 'pubspec.lock')).writeAsString(_lockThreePackages);
      // No DEPENDENCIES.md.

      final int code = await check_deps.runCheck(<String>[tempDir.path]);
      expect(code, 2);
    });

    test('returns 2 when pubspec.lock is missing', () async {
      // DEPENDENCIES.md present but pubspec.lock absent — second exit-2
      // branch that the Phase 01 test suite left uncovered.
      await File(p.join(tempDir.path, 'DEPENDENCIES.md')).writeAsString(_depsMdComplete);

      final int code = await check_deps.runCheck(<String>[tempDir.path]);
      expect(code, 2);
    });
  });
}
