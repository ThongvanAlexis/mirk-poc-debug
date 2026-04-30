// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// CI gate: scans `pubspec.lock` and resolves the SPDX license of every
/// non-SDK package via its LICENSE file (or `pubspec.yaml` `license:` field,
/// or a manual override). Fails (exit 1) if any license is not in the
/// GOSL-compatible allowlist, or if the LICENSE text carries a known-forbidden
/// copyleft marker (GPL/AGPL/MPL).
///
/// Allowlist is from CLAUDE.md §Licences acceptées: MIT, BSD-2-Clause,
/// BSD-3-Clause, Apache-2.0, Unlicense, CC0-1.0, ISC, Zlib.
const Set<String> _allowedSpdx = <String>{
  'MIT',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'Apache-2.0',
  'Unlicense',
  'CC0-1.0',
  'ISC',
  'Zlib',
  // Synthetic SPDX reserved for narrow manual overrides where an MPL-2.0
  // package appears as a LINUX-ONLY platform transitive and doesn't ship in
  // Android/iOS binaries (MirkFall's target platforms). Every use MUST be
  // accompanied by an entry in _manualOverrides with the Linux-only rationale.
  'MPL-2.0-Linux-only',
};

/// Manual SPDX overrides for packages whose LICENSE file defeats the heuristic
/// (non-standard wording, dual-licensed with unusual wording, etc.).
/// Every entry MUST carry a comment with a pub.dev URL citing the license.
const Map<String, String> _manualOverrides = <String, String>{
  // flutter_plugin_android_lifecycle ships a BSD-3-Clause LICENSE file that
  // lacks the `Redistributions of source code must retain` prefix in its
  // first 120 chars (header block has a preamble). Confirmed BSD-3-Clause at
  // https://pub.dev/packages/flutter_plugin_android_lifecycle/license.
  'flutter_plugin_android_lifecycle': 'BSD-3-Clause',
  // dbus 0.7.12 — MPL-2.0. LINUX-ONLY transitive pulled by
  // geolocator_linux, flutter_local_notifications_linux, gsettings.
  // MirkFall ships Android + iOS only; Linux plugin surfaces never execute
  // at runtime on target platforms. MPL-2.0 is file-level weak-copyleft —
  // does NOT contaminate combined work under other licenses. Allowed as
  // MPL-2.0 override narrowly for the Linux-only transitive surface.
  // https://pub.dev/packages/dbus/license
  'dbus': 'MPL-2.0-Linux-only',
  // geoclue 0.1.1 — MPL-2.0. LINUX-ONLY transitive of geolocator_linux.
  // Same rationale as dbus above — not in Android/iOS ship graph.
  // https://pub.dev/packages/geoclue/license
  'geoclue': 'MPL-2.0-Linux-only',
  // gsettings 0.2.8 — MPL-2.0. LINUX-ONLY transitive of geolocator_linux.
  // Same rationale as dbus above — not in Android/iOS ship graph.
  // https://pub.dev/packages/gsettings/license
  'gsettings': 'MPL-2.0-Linux-only',
};

/// Forbidden substrings in LICENSE text — automatic fail. MPL is listed as
/// weak copyleft; flag conservatively and let a human confirm via override
/// if a specific case is genuinely OK.
const List<String> _forbiddenSubstrings = <String>[
  'GNU GENERAL PUBLIC LICENSE',
  'GNU LESSER GENERAL PUBLIC LICENSE',
  'GNU AFFERO GENERAL PUBLIC LICENSE',
  'Mozilla Public License',
];

/// Upper bound on LICENSE bytes we read per package. All the forbidden
/// markers and heuristic signatures appear in the first few KB of a standard
/// LICENSE preamble; reading beyond that is only wasted memory on pathological
/// multi-MB LICENSE files found occasionally in pub-cache.
const int _kMaxLicenseReadBytes = 64 * 1024;

/// Runs the license scan at the given repo root (default: current dir).
/// Returns 0 when every non-SDK package resolves to an allowed SPDX,
/// 1 on violation or unresolved package, 2 on missing input files.
Future<int> runCheck(List<String> args) async {
  final String repoRoot = args.isNotEmpty ? args.first : '.';
  final String lockPath = p.join(repoRoot, 'pubspec.lock');
  final String configPath = p.join(repoRoot, '.dart_tool', 'package_config.json');

  final File lockFile = File(lockPath);
  final File configFile = File(configPath);
  if (!await lockFile.exists()) {
    stderr.writeln('check_licenses: pubspec.lock not found at $lockPath');
    return 2;
  }
  if (!await configFile.exists()) {
    stderr.writeln('check_licenses: .dart_tool/package_config.json not found. Run `flutter pub get` first.');
    return 2;
  }

  final YamlMap lock = loadYaml(await lockFile.readAsString()) as YamlMap;
  final YamlMap packages = (lock['packages'] as YamlMap?) ?? YamlMap();

  final Map<String, Object?> configJson = jsonDecode(await configFile.readAsString()) as Map<String, Object?>;
  final Map<String, String> rootUriByPackage = <String, String>{};
  final List<Object?> configPackages = configJson['packages'] as List<Object?>;
  for (final Object? pkg in configPackages) {
    if (pkg is Map<String, Object?>) {
      final String? name = pkg['name'] as String?;
      final String? rootUri = pkg['rootUri'] as String?;
      if (name != null && rootUri != null) {
        rootUriByPackage[name] = rootUri;
      }
    }
  }

  final List<String> violations = <String>[];
  final List<String> unresolved = <String>[];
  var ok = 0;

  for (final MapEntry<dynamic, dynamic> entry in packages.entries) {
    final String name = entry.key as String;
    final YamlMap meta = entry.value as YamlMap;
    final String source = meta['source'] as String? ?? 'unknown';
    // Flutter / Dart SDK bundled packages are BSD-3-Clause by construction and
    // live outside pub-cache, so we skip them entirely.
    if (source == 'sdk') continue;

    final String? spdx = _manualOverrides[name] ?? await _resolveSpdx(name, rootUriByPackage[name], configPath);

    if (spdx == null) {
      unresolved.add(name);
      continue;
    }

    // Parse compound SPDX expressions. Normalise outer parentheses so
    // `(MIT OR Apache-2.0)` matches identically to `MIT OR Apache-2.0`.
    // Real SPDX expressions (e.g. `GPL-2.0 AND Classpath-exception-2.0`) need
    // a proper parser; this tree has none today, so detect AND/WITH up front
    // and flag them as unresolved — never silently pass a monolithic string
    // through the allowlist contains check.
    final String normalized = _stripOuterParens(spdx.trim());
    // `LicenseRef-*` is the SPDX escape hatch for non-standard / proprietary
    // licenses. We can't reason about those automatically — surface a hint.
    if (normalized.toLowerCase().startsWith('licenseref-')) {
      violations.add(
        '$name: $spdx — LicenseRef-* is non-standard; add a manual override mapping "$name" to the effective SPDX id if the license is compatible.',
      );
      continue;
    }
    if (RegExp(r'\s+AND\s+', caseSensitive: false).hasMatch(normalized) || RegExp(r'\s+WITH\s+', caseSensitive: false).hasMatch(normalized)) {
      violations.add('$name: $spdx — compound SPDX (AND/WITH) not supported; add a manual override with the effective SPDX.');
      continue;
    }
    // Split compound OR expressions: "Apache-2.0 OR BSD-3-Clause" passes when
    // either side is allowed.
    // Case-insensitive match: upstream publishers occasionally lowercase the
    // SPDX id (e.g. `license: apache-2.0`); treat them the same as canonical.
    final List<String> ids = normalized.split(RegExp(r'\s+OR\s+', caseSensitive: false)).map((String s) => _stripOuterParens(s.trim())).toList();
    final Set<String> allowedLower = _allowedSpdx.map((String s) => s.toLowerCase()).toSet();
    final bool allowed = ids.any((String id) => allowedLower.contains(id.toLowerCase()));
    if (!allowed) {
      violations.add('$name: $spdx NOT in allowlist');
    } else {
      ok++;
    }
  }

  if (violations.isEmpty && unresolved.isEmpty) {
    stdout.writeln('check_licenses: OK ($ok packages)');
    return 0;
  }
  if (violations.isNotEmpty) {
    stderr.writeln('check_licenses: ${violations.length} violation(s):');
    for (final String v in violations) {
      stderr.writeln('  - $v');
    }
  }
  if (unresolved.isNotEmpty) {
    stderr.writeln('check_licenses: ${unresolved.length} package(s) could not be resolved.');
    stderr.writeln('Add to _manualOverrides with a pub.dev source comment:');
    for (final String n in unresolved) {
      stderr.writeln('  - $n');
    }
  }
  return 1;
}

/// Attempts to resolve a package's SPDX identifier by:
/// 1. scanning LICENSE for forbidden copyleft markers FIRST (belt-and-braces
///    against pubspec `license:` field divergence from repo source),
/// 2. reading the `pubspec.yaml` `license:` field when present,
/// 3. reading LICENSE / LICENSE.md / LICENSE.txt and heuristic-matching on
///    signature phrases.
/// Returns `null` when no method can identify the license.
Future<String?> _resolveSpdx(String name, String? rootUri, String configPath) async {
  if (rootUri == null) return null;

  // rootUri is either `file:///...` (absolute) or a relative path such as
  // `../../pkg_x/` — resolve against the directory of package_config.json
  // (typically `<repo>/.dart_tool/`).
  final String configDir = p.dirname(configPath);
  final Uri uri = Uri.parse(rootUri);
  final String packageDir = uri.scheme == 'file' ? uri.toFilePath() : p.normalize(p.join(configDir, uri.path));

  // 1. Belt-and-braces: scan LICENSE text for forbidden markers FIRST, even
  //    when pubspec.yaml declares a benign SPDX. A package declaring
  //    `license: MIT` in pubspec but shipping a GPL LICENSE file must NOT
  //    bypass the forbidden-substring scan — CLAUDE.md §Audit obligatoire
  //    flags exactly this "divergence between pub.dev and repo source" risk.
  //    Case-insensitive so a LICENSE titled `Gnu General Public License`
  //    (non-standard casing) is caught the same as the canonical ALL-CAPS.
  for (final String candidate in <String>['LICENSE', 'LICENSE.md', 'LICENSE.txt']) {
    final File f = File(p.join(packageDir, candidate));
    if (!await f.exists()) continue;
    final String text = await _readLicenseHead(f);
    final String textLower = text.toLowerCase();
    for (final String bad in _forbiddenSubstrings) {
      if (textLower.contains(bad.toLowerCase())) {
        // MPL is weak copyleft and CAN ship if the package is a Linux-only
        // platform transitive (see _manualOverrides). Surface a hint for that
        // case instead of the same generic message GPL/AGPL/LGPL get.
        if (bad == 'Mozilla Public License') {
          return 'UNKNOWN-FORBIDDEN-MARKER: Mozilla Public License — '
              'add an _manualOverrides entry mapping "$name" to "MPL-2.0-Linux-only" '
              'if this is a Linux-only transitive (see dbus/geoclue/gsettings precedents); '
              'otherwise reject the dependency.';
        }
        return 'UNKNOWN-FORBIDDEN-MARKER: $bad';
      }
    }
  }

  // 2. Check pubspec.yaml `license:` field (rare but authoritative).
  final File pubspecFile = File(p.join(packageDir, 'pubspec.yaml'));
  if (await pubspecFile.exists()) {
    final Object? parsed = loadYaml(await pubspecFile.readAsString());
    if (parsed is YamlMap) {
      final Object? declared = parsed['license'];
      if (declared is String) {
        final String trimmed = declared.trim();
        // Placeholder values ("See LICENSE file", "unknown", "TBD", etc.) are
        // NOT real SPDX ids — treat them as unresolved so the caller surfaces
        // the "manual audit needed" advisory instead of failing the allowlist
        // check with a confusing literal.
        if (trimmed.isNotEmpty && !_isPlaceholderLicense(trimmed)) return trimmed;
      }
    }
  }

  // 3. Read LICENSE / LICENSE.md / LICENSE.txt with heuristic SPDX match.
  for (final String candidate in <String>['LICENSE', 'LICENSE.md', 'LICENSE.txt']) {
    final File f = File(p.join(packageDir, candidate));
    if (!await f.exists()) continue;

    final String text = await _readLicenseHead(f);
    // Forbidden marker scan was done above — keep this as a fallback for
    // unusual file orderings. Case-insensitive match for symmetry with step 1.
    final String textLower = text.toLowerCase();
    for (final String bad in _forbiddenSubstrings) {
      if (textLower.contains(bad.toLowerCase())) {
        return 'UNKNOWN-FORBIDDEN-MARKER: $bad';
      }
    }

    // Heuristic matches — ordered from most distinctive to most generic.
    if (text.contains('Apache License') && text.contains('Version 2.0')) return 'Apache-2.0';

    final bool bsdMarker = text.contains('Redistributions of source code must retain');
    final bool mitMarker = text.contains('MIT License') || text.contains('Permission is hereby granted, free of charge,');

    if (mitMarker) {
      if (bsdMarker) {
        // BSD families also carry the MIT "Permission is hereby" line sometimes,
        // so disambiguate on the BSD-specific redistribution clause first.
        return text.contains('Neither the name of') ? 'BSD-3-Clause' : 'BSD-2-Clause';
      }
      return 'MIT';
    }

    if (bsdMarker) {
      return text.contains('Neither the name of') ? 'BSD-3-Clause' : 'BSD-2-Clause';
    }
    if (text.contains('ISC License') || text.contains('ISC license')) return 'ISC';
    if (text.contains('Unlicense')) return 'Unlicense';
    if (text.contains('CC0 1.0 Universal')) return 'CC0-1.0';
    if (text.contains('zlib License') || text.contains('zlib license')) return 'Zlib';
  }

  return null;
}

/// Reads up to [_kMaxLicenseReadBytes] of [f] as UTF-8 — caps memory for
/// pathologically large LICENSE files in pub-cache. All recognisable markers
/// (SPDX signatures + forbidden copyleft titles) appear in the first KB of a
/// normal LICENSE preamble, so truncation has no semantic effect in practice.
Future<String> _readLicenseHead(File f) async {
  final RandomAccessFile raf = await f.open();
  try {
    final int len = await raf.length();
    final int toRead = len < _kMaxLicenseReadBytes ? len : _kMaxLicenseReadBytes;
    final List<int> bytes = await raf.read(toRead);
    // allowMalformed keeps odd LICENSE encodings from throwing mid-scan.
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    await raf.close();
  }
}

/// Returns true when a `license:` field string is a placeholder rather than a
/// real SPDX id (e.g. `"See LICENSE file"`, `"unknown"`, `"TBD"`, `"n/a"`).
bool _isPlaceholderLicense(String s) {
  final String lower = s.toLowerCase().trim();
  // Exact placeholders the pub ecosystem has been observed to ship.
  const Set<String> placeholders = <String>{'unknown', 'tbd', 'n/a', 'na', 'none', 'proprietary'};
  if (placeholders.contains(lower)) return true;
  // Sentences pointing at the LICENSE file rather than declaring an SPDX id.
  if (lower.contains('see license') || lower.contains('see the license') || lower.contains('see licen')) return true;
  if (lower == 'see the accompanying license' || lower.startsWith('see license')) return true;
  return false;
}

/// Strips a single matching pair of outer parentheses from an SPDX expression.
/// `(MIT)` → `MIT`; `(MIT OR Apache-2.0)` → `MIT OR Apache-2.0`; `(MIT) OR (BSD)`
/// is left untouched (the outer parens aren't balanced around the whole string).
String _stripOuterParens(String s) {
  if (s.length < 2 || !s.startsWith('(') || !s.endsWith(')')) return s;
  // Verify the parens are actually balanced around the entire string.
  var depth = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') depth--;
    if (depth == 0 && i < s.length - 1) return s;
  }
  return s.substring(1, s.length - 1).trim();
}

Future<void> main(List<String> args) async {
  final int code = await runCheck(args);
  exitCode = code;
}
