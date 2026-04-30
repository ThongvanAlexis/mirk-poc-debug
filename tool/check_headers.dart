// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';
import 'dart:io';

/// CI gate: scans every non-generated `*.dart` file under the configured roots
/// (default: `lib/`, `test/`, `tool/`) and fails (exit 1) if any file does not
/// start with the exact GOSL v1.0 three-line header.
///
/// Matching is byte-exact — no regex fuzziness — so "close enough" headers
/// still fail. Excludes codegen outputs (`*.g.dart`, `*.freezed.dart`, etc.)
/// and conventional `generated/` / `build/` / `.dart_tool/` directories.
const String _expectedHeader = '''// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details''';

final List<RegExp> _excludePatterns = <RegExp>[
  // Build-generated files — explicitly exempt from the GOSL header rule per
  // CLAUDE.md convention. Every codegen tool in common use gets its own
  // suffix match; keep the list exhaustive so new generators in later phases
  // don't silently pollute the failure report.
  RegExp(r'\.g\.dart$'),
  RegExp(r'\.freezed\.dart$'),
  RegExp(r'\.gr\.dart$'),
  RegExp(r'\.config\.dart$'),
  RegExp(r'\.pb\.dart$'), // protobuf
  RegExp(r'\.pbenum\.dart$'), // protobuf enums
  RegExp(r'\.pbjson\.dart$'), // protobuf json
  RegExp(r'\.pbserver\.dart$'), // protobuf gRPC server stubs
  RegExp(r'\.swagger\.dart$'), // chopper swagger
  RegExp(r'\.chopper\.dart$'), // chopper
  RegExp(r'\.mocks\.dart$'), // mockito
  RegExp(r'[/\\]generated[/\\]'),
  // `test/generated_migrations/` holds drift_dev's auto-generated
  // SchemaVerifier helpers (schema.dart / schema_v{N}.dart). Same status as
  // the `.g.dart` suffix exclusion: produced by a codegen tool, not
  // hand-written.
  RegExp(r'[/\\]generated_migrations[/\\]'),
  RegExp(r'[/\\]\.dart_tool[/\\]'),
  RegExp(r'[/\\]build[/\\]'),
  // Plugin package `example/` fixtures and managed platform Dart files
  // (Flutter writes these under ios/ and android/ when configuring runners)
  // are third-party / platform-owned. Excluding them protects against a dev
  // accidentally running `dart run tool/check_headers.dart .` from the repo
  // root picking up nested Flutter example projects or managed platform
  // templates.
  RegExp(r'[/\\]ios[/\\]'),
  RegExp(r'[/\\]android[/\\]'),
  RegExp(r'[/\\]example[/\\]'),
];

const List<String> _defaultRoots = <String>[
  'lib',
  'test',
  'tool',
  // Phase 15 (integration_test/) will add e2e tests; include the root up-front
  // so any .dart file landing there is scanned without re-editing this list.
  'integration_test',
];

/// Runs the header check. Accepts an optional list of root directories — if
/// empty the default `lib/test/tool` roots are scanned. Recognises `--help` /
/// `-h` to print usage and exit 0; flags starting with `--` that aren't
/// recognised are silently dropped (forward-compat) rather than misinterpreted
/// as a root path. Returns the process exit code: 0 on success, 1 when at
/// least one file is missing the header, 2 if all roots are absent.
Future<int> runCheck(List<String> args) async {
  // Minimal CLI split: `--help` / `-h` prints usage and exits 0; other `--`
  // flags are stripped up front so a future `--verbose` addition doesn't
  // have to rearchitect the call shape. Positional args are the root paths.
  if (args.any((String a) => a == '--help' || a == '-h')) {
    stdout.writeln(
      'Usage: dart run tool/check_headers.dart [ROOTS...]\n'
      '  ROOTS    Directories to scan (default: lib test tool).\n'
      '  --help   Show this message and exit.',
    );
    return 0;
  }
  final List<String> positional = args.where((String a) => !a.startsWith('--')).toList();
  final List<String> roots = positional.isNotEmpty ? positional : _defaultRoots;
  final List<String> failures = <String>[];
  var scanned = 0;
  var rootsSeen = 0;

  for (final String rootPath in roots) {
    final Directory root = Directory(rootPath);
    if (!await root.exists()) continue;
    rootsSeen++;

    await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String normalized = entity.path.replaceAll('\\', '/');
      if (!normalized.endsWith('.dart')) continue;
      if (_excludePatterns.any((RegExp re) => re.hasMatch(normalized))) continue;

      scanned++;
      final String contents = await _readWithBomHandling(entity);
      // Strip leading BOM if present — some editors inject it silently.
      final String trimmed = contents.startsWith('﻿') ? contents.substring(1) : contents;
      if (!trimmed.startsWith(_expectedHeader)) {
        failures.add(entity.path);
        continue;
      }
      // The header match must be followed by a line break — otherwise a file
      // starting with `// Copyright ...details// hack injected on same line`
      // would pass the startsWith check while actually concatenating arbitrary
      // content onto the final header line (minor poison vector).
      final int headerEnd = _expectedHeader.length;
      if (trimmed.length == headerEnd) continue; // EOF right after header — acceptable.
      final String afterHeader = trimmed.substring(headerEnd);
      if (!afterHeader.startsWith('\n') && !afterHeader.startsWith('\r\n')) {
        failures.add(entity.path);
      }
    }
  }

  if (rootsSeen == 0) {
    stderr.writeln('check_headers: no roots found (tried: ${roots.join(', ')})');
    return 2;
  }

  if (failures.isEmpty) {
    stdout.writeln('check_headers: OK ($scanned files)');
    return 0;
  }
  stderr.writeln('check_headers: ${failures.length} file(s) missing GOSL v1.0 header:');
  for (final String f in failures) {
    stderr.writeln('  - $f');
  }
  stderr.writeln();
  stderr.writeln('Expected exact header (3 lines, no trailing blank):');
  stderr.writeln(_expectedHeader);
  return 1;
}

/// Reads [f] and returns its text, handling UTF-8 and UTF-16 LE BOMs.
///
/// Windows editors (notepad.exe, PowerShell `Out-File` default) ship UTF-16 LE
/// with a BOM `0xFF 0xFE`. Dart's default `readAsString` assumes UTF-8 and
/// fails with a confusing 'Missing extension byte' on those files. Detect
/// the BOM explicitly and decode with the right codec so the scanner doesn't
/// silently miss the header match on a file saved by a Windows editor.
Future<String> _readWithBomHandling(File f) async {
  final List<int> bytes = await f.readAsBytes();
  // UTF-16 LE BOM: 0xFF 0xFE
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final List<int> body = bytes.sublist(2);
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i + 1 < body.length; i += 2) {
      sb.writeCharCode(body[i] | (body[i + 1] << 8));
    }
    return sb.toString();
  }
  // UTF-16 BE BOM: 0xFE 0xFF (rare but well-defined)
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final List<int> body = bytes.sublist(2);
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i + 1 < body.length; i += 2) {
      sb.writeCharCode((body[i] << 8) | body[i + 1]);
    }
    return sb.toString();
  }
  // UTF-8 BOM (handled downstream by startsWith(﻿) strip) or plain UTF-8.
  return utf8.decode(bytes, allowMalformed: true);
}

Future<void> main(List<String> args) async {
  final int code = await runCheck(args);
  exitCode = code;
}
