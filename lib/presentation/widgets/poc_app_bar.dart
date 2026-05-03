// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../infrastructure/logging/file_logger.dart';
import '../../l10n/app_localizations.dart';
import '../../state/debug_spiral_state.dart';

/// AppBar factory shared across every Phase 1+2+3 Scaffold (LOG-04 + Phase 3
/// shader-sanity entry point + Plan 03.1-08-FIX FIX 2 debug-spiral toggle).
///
/// Returns a Material 3 AppBar with the following actions:
///   1. `Switch.adaptive` (Plan 03.1-08-FIX FIX 2) — toggles the global
///      [debugSpiralEnabled] notifier. When ON, both `/map` and `/sanity`
///      render the debug-spiral diagnostic shader (Plan 03.1-07 /
///      DEBUG-01) instead of the production atmospheric fog. Default OFF;
///      production fog rendering unchanged. Wrapped in
///      [ValueListenableBuilder] so the Switch's `value:` reflects the
///      shared notifier state across both screens.
///   2. `Icons.science` → navigates to `/sanity` via `context.push(...)` so
///      a back button on the sanity screen can `pop()` to return to the
///      previous route (UX-01, Plan 03.1-05). Per CLAUDE.md GoRouter rule:
///      "if the word retour has meaning in UX → push" (Phase 3 pre-walk
///      gate — see ShaderSanityScreen).
///   3. `Icons.share` → gzips [FileLogger.activeFilename] to a temp `.gz`
///      file and routes it through the system share sheet (LOG-04). The
///      button's `onPressed` is null when no active log exists, leaving it
///      visually disabled.
///
/// When [title] is null the AppBar falls back to [AppLocalizations.appTitle].
///
/// Encapsulating these actions in this factory enforces the LOG-04 contract —
/// share is reachable from EVERY screen — keeps the science action
/// declaration in a single place (the only entry point to the /sanity
/// pre-walk gate), AND makes the debug-spiral toggle universally
/// accessible (Plan 03.1-08-FIX FIX 2).
PreferredSizeWidget buildPocAppBar(BuildContext context, {String? title}) {
  final l10n = AppLocalizations.of(context)!;
  final activeFilename = FileLogger.activeFilename;
  return AppBar(
    title: Text(title ?? l10n.appTitle),
    actions: <Widget>[
      // Plan 03.1-08-FIX FIX 2 — global debug-spiral toggle. Same widget
      // visible from /map AND /sanity so the diagnostic observation can
      // happen under production gesture conditions on /map (where
      // camera.pixelOrigin actually jumps with zoom — the synthetic
      // /sanity trajectory does not reproduce that). Listens to the
      // top-level ValueNotifier so flipping the Switch on either screen
      // updates the other when the user navigates back.
      Tooltip(
        message: l10n.debugSpiralToggleTooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: ValueListenableBuilder<bool>(
            valueListenable: debugSpiralEnabled,
            builder: (BuildContext context, bool enabled, Widget? _) {
              return Switch.adaptive(value: enabled, onChanged: (bool value) => debugSpiralEnabled.value = value);
            },
          ),
        ),
      ),
      IconButton(icon: const Icon(Icons.science), tooltip: l10n.shaderSanityTooltip, onPressed: () => context.push('/sanity')),
      IconButton(
        icon: const Icon(Icons.share),
        tooltip: l10n.shareLogsTooltip,
        onPressed: activeFilename == null ? null : () => _onSharePressed(context, activeFilename),
      ),
    ],
  );
}

final Logger _shareLogger = Logger('presentation.widgets.poc_app_bar.share');

/// Reads the active log file, gzips it in-memory, writes the gzipped bytes
/// to a temp `.txt.gz` file, and invokes the system share sheet.
///
/// Logs raw + gzipped byte counts at INFO level — establishes the
/// receiver-side baseline for the LOG-05 manual UAT (Pitfall D — Mail
/// attachment integrity check). On a missing log file, logs a warning and
/// returns silently (no UI banner per CONTEXT.md "On log write failure:
/// silent fallback"). After every `await`, checks `if (!context.mounted)
/// return;` before reusing context (Pitfall B — analyzer rule
/// `use_build_context_synchronously: error`).
Future<void> _onSharePressed(BuildContext context, String activeFilename) async {
  final logFile = File(activeFilename);
  if (!await logFile.exists()) {
    _shareLogger.warning('Share invoked but log file does not exist: $activeFilename');
    return;
  }
  final bytes = await logFile.readAsBytes();
  if (!context.mounted) return;
  final gzipped = GZipCodec().encode(bytes);
  final tmpDir = await getTemporaryDirectory();
  if (!context.mounted) return;
  final basename = p.basenameWithoutExtension(activeFilename);
  final outFilename = p.join(tmpDir.path, '$basename.txt.gz');
  await File(outFilename).writeAsBytes(gzipped, flush: true);
  if (!context.mounted) return;
  _shareLogger.info('Sharing log: ${bytes.length} bytes raw, ${gzipped.length} bytes gzipped, file=$outFilename');
  // share_plus 12.0.2 deprecates Share.shareXFiles in favour of
  // SharePlus.instance.share(ShareParams(files: ...)). The ShareParams API
  // is the only non-deprecated path forward in this version of the lib.
  await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(outFilename, mimeType: 'application/gzip')]));
}
