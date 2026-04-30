// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/fps_counter_overlay.dart';
import '../widgets/poc_app_bar.dart';

/// Permission denied screen (route '/denied').
///
/// Single Open-Settings button (no Try-Again per CONTEXT.md — iOS caches the
/// first-prompt result, so re-requesting in-app cannot re-show the system
/// prompt). The PermissionGateScreen owns the lifecycle resume re-check, so
/// the user only needs to grant in Settings + return; the app auto-navigates
/// to /map without an extra tap.
class PermissionDeniedScreen extends StatelessWidget {
  const PermissionDeniedScreen({super.key});

  static final Logger _log = Logger('presentation.screens.permission_denied');

  /// Routes the user to the system app-settings page. Logs the platform's
  /// returned bool for diagnostics. No `await`-then-`context` use, so no
  /// Pitfall B guard needed.
  Future<void> _onOpenSettingsPressed() async {
    _log.info('Open Settings pressed; calling openAppSettings');
    final opened = await openAppSettings();
    _log.fine('openAppSettings returned: $opened');
  }

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
                  const Icon(Icons.location_off_outlined, size: 64),
                  const SizedBox(height: 24),
                  Text(l10n.permissionDeniedParagraph, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _onOpenSettingsPressed, child: Text(l10n.permissionDeniedOpenSettings)),
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
