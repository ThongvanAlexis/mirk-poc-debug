// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// CI gate: cross-references `pubspec.lock` against the markdown tables in
/// `DEPENDENCIES.md`. Every non-SDK package present in the lockfile MUST
/// have a row in one of the `DEPENDENCIES.md` tables with the matching
/// version. Reports diff-style errors for missing, extra, and mismatched
/// entries.
///
/// Markdown parsing is intentionally simple: any line starting with `| ` and
/// containing at least 7 pipe-separated cells is considered a table row.
/// Header / separator rows are filtered by value.
Future<int> runCheck(List<String> args) async {
  final String repoRoot = args.isNotEmpty ? args.first : '.';
  final String lockPath = p.join(repoRoot, 'pubspec.lock');
  final String depsMdPath = p.join(repoRoot, 'DEPENDENCIES.md');

  final File lockFile = File(lockPath);
  final File mdFile = File(depsMdPath);
  if (!await lockFile.exists()) {
    stderr.writeln('check_dependencies_md: pubspec.lock not found at $lockPath');
    return 2;
  }
  if (!await mdFile.exists()) {
    stderr.writeln('check_dependencies_md: DEPENDENCIES.md not found at $depsMdPath');
    return 2;
  }

  final YamlMap lock = loadYaml(await lockFile.readAsString()) as YamlMap;
  final YamlMap lockPackages = (lock['packages'] as YamlMap?) ?? YamlMap();

  // Build the "expected" map {name -> version} from pubspec.lock (skip SDK).
  final Map<String, String> expected = <String, String>{};
  for (final MapEntry<dynamic, dynamic> entry in lockPackages.entries) {
    final String name = entry.key as String;
    final YamlMap meta = entry.value as YamlMap;
    final String source = meta['source'] as String? ?? 'unknown';
    if (source == 'sdk') continue;
    final String version = meta['version'] as String? ?? '';
    expected[name] = version;
  }

  // Parse DEPENDENCIES.md: keep the last-seen version per package name.
  // Track the current section header (e.g. `## Direct dependencies`,
  // `## Tooling / GitHub Actions`) so we can skip rows that aren't
  // pubspec-correlated up front, instead of relying on the fragile
  // name-contains-slash heuristic Phase 01 used.
  final String mdText = await mdFile.readAsString();
  final Map<String, String> declared = <String, String>{};
  // Lowercase section-header substrings that indicate pub.dev-correlated rows.
  // Only rows under one of these headers are cross-referenced with pubspec.lock.
  const Set<String> pubspecSections = <String>{'direct dependencies', 'dev dependencies', 'transitive dependencies'};
  bool inPubspecSection = false;
  for (final String rawLine in mdText.split('\n')) {
    final String line = rawLine.trimRight();
    if (line.startsWith('## ')) {
      final String section = line.substring(3).trim().toLowerCase();
      inPubspecSection = pubspecSections.any(section.contains);
      continue;
    }
    if (!inPubspecSection) continue;
    // Accept any leading `|` — `| a |` (markdown-conventional, with space)
    // and `|a|` (collapsed by a markdownlint fix) both describe the same row.
    // Phase 01's `startsWith('| ')` was fragile: a future markdownlint rule
    // that removes the space would make every table row invisible and the
    // gate would flip from green to reporting "everything in lock is missing".
    if (!line.startsWith('|')) continue;
    final List<String> cells = line.split('|').map((String c) => c.trim()).toList();
    // Expected shape from the `| Package | Version | License | Source | ... |`
    // template: at least 4 `|` → 5 cells where cells[0] and cells[last] are
    // empty (artifacts of the leading/trailing pipes). Guard both the column
    // count AND the existence of cells[1]/cells[2] explicitly so a schema
    // evolution (e.g. reorder columns) fails noisily instead of silently
    // reading the wrong cells.
    if (cells.length < 5) continue;
    final String name = cells[1];
    final String version = cells[2];
    // Filter out header + separator rows.
    if (name.isEmpty || name == 'Package' || name == 'Action') continue;
    if (name.startsWith('-')) continue;
    if (version.isEmpty || version == 'Version' || version.startsWith('-')) continue;
    declared[name] = version;
  }

  final List<String> missing = <String>[];
  final List<String> extra = <String>[];
  final List<String> mismatched = <String>[];

  for (final MapEntry<String, String> e in expected.entries) {
    if (!declared.containsKey(e.key)) {
      missing.add('${e.key} ${e.value}');
    } else if (declared[e.key] != e.value) {
      mismatched.add('${e.key}: lock=${e.value} md=${declared[e.key]}');
    }
  }
  for (final String d in declared.keys) {
    // Section-header filter already excluded the Tooling table rows — any
    // package name left here belongs to a pubspec section. If it's not in
    // pubspec.lock, it's a stale entry.
    if (!expected.containsKey(d)) {
      extra.add(d);
    }
  }

  if (missing.isEmpty && extra.isEmpty && mismatched.isEmpty) {
    stdout.writeln('check_dependencies_md: OK (${expected.length} packages)');
    return 0;
  }

  if (missing.isNotEmpty) {
    stderr.writeln('check_dependencies_md: ${missing.length} package(s) in pubspec.lock MISSING from DEPENDENCIES.md:');
    for (final String m in missing) {
      stderr.writeln('  - $m');
    }
  }
  if (extra.isNotEmpty) {
    stderr.writeln('check_dependencies_md: ${extra.length} package(s) in DEPENDENCIES.md NOT in pubspec.lock:');
    for (final String m in extra) {
      stderr.writeln('  - $m');
    }
  }
  if (mismatched.isNotEmpty) {
    stderr.writeln('check_dependencies_md: ${mismatched.length} version mismatch(es):');
    for (final String m in mismatched) {
      stderr.writeln('  - $m');
    }
  }
  return 1;
}

Future<void> main(List<String> args) async {
  final int code = await runCheck(args);
  exitCode = code;
}
