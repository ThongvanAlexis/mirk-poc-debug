// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/fps_counter_overlay.dart';
import '../widgets/poc_app_bar.dart';

/// Generic error screen for Phase 2 PMTiles-copy failures and similar
/// non-recoverable infrastructure errors. Reached via
/// `context.go('/error', extra: <String detail>)`.
///
/// No retry button by design (CONTEXT.md §PMTiles copy lifecycle —
/// "Failure recovery"): if storage is broken, retrying won't help. POC
/// failure is visible, not silent. Layout mirrors `permission_denied_screen`
/// so failure-state screens stay structurally consistent.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.detail});

  /// Underlying error message — typically a `FileSystemException`'s `.message`.
  /// Rendered verbatim under the `errorScreenDetailLabel` header so a sideload
  /// tester can read the failure reason without attaching a debugger.
  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: buildPocAppBar(context),
      body: Stack(
        children: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline, size: 64),
                  const SizedBox(height: 24),
                  Text(l10n.errorScreenTitle, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(l10n.errorScreenBody, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  Text(l10n.errorScreenDetailLabel, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          const Positioned(top: 8, right: 8, child: FpsCounterOverlay()),
        ],
      ),
    );
  }
}
