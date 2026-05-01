// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../infrastructure/pmtiles/pmtiles_asset_copier.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/fps_counter_overlay.dart';
import '../widgets/poc_app_bar.dart';

/// Permission rationale screen (route '/').
///
/// Shows a rationale, requests `locationWhenInUse` on CTA, navigates to
/// `/map` on grant or `/denied` on deny. Re-checks status on app resume so
/// the developer can grant via Settings and return without an extra tap
/// (W-2 fix per CONTEXT.md — handles the denied → opened Settings → toggled
/// on → returned flow with zero extra taps).
class PermissionGateScreen extends StatefulWidget {
  const PermissionGateScreen({super.key});

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen> with WidgetsBindingObserver {
  static final Logger _log = Logger('presentation.screens.permission_gate');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkAndMaybeNavigate(reason: 'initState'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkAndMaybeNavigate(reason: 'didChangeAppLifecycleState=resumed'));
    }
  }

  /// Checks the current locationWhenInUse status. If already granted, hands off
  /// to [_ensureMapDataAndNavigate] which copies the PMTiles archive (Pitfall 6
  /// — map screen must mount with the file already on disk) and routes to
  /// `/map` on success or `/error` on failure. Called on initState (re-launch
  /// shortcut) and on resumed (post-Settings round-trip auto-navigation per
  /// CONTEXT.md decision).
  Future<void> _checkAndMaybeNavigate({required String reason}) async {
    final status = await Permission.locationWhenInUse.status;
    if (!mounted) return;
    _log.fine('Permission status check ($reason): $status');
    if (!status.isGranted) return;
    await _ensureMapDataAndNavigate();
  }

  /// CTA handler — requests locationWhenInUse and routes by outcome.
  /// Pitfall B: every `await` is followed by `if (!mounted) return;` BEFORE
  /// `context` is touched (lint enforced via use_build_context_synchronously).
  Future<void> _onCtaPressed() async {
    _log.info('Permission CTA pressed; requesting locationWhenInUse');
    final result = await Permission.locationWhenInUse.request();
    if (!mounted) return;
    _log.info('Permission request result: $result');
    if (!result.isGranted) {
      context.go('/denied');
      return;
    }
    await _ensureMapDataAndNavigate();
  }

  /// Common path between in-app grant + AppLifecycleState.resumed re-check.
  /// Awaits the PMTiles copy (Pitfall 6 — map screen must mount with file
  /// on disk), routes to `/error` on FileSystemException with the underlying
  /// message in `extra`, otherwise routes to `/map`.
  ///
  /// Both grant paths converge here per CONTEXT.md §Integration Points: "Both
  /// the in-app prompt path AND the AppLifecycleState.resumed re-check path
  /// must hit it."
  ///
  /// Race-condition note: if `_onCtaPressed` and the lifecycle handler both
  /// fire concurrently (theoretically possible if the user toggles between
  /// Settings and the app at the exact moment they tap the CTA),
  /// [PmtilesAssetCopier.ensureCopied] is idempotent so both calls succeed.
  /// The first to complete wins the navigation; the second's `mounted` guard
  /// catches the unmounted state. No locking needed.
  Future<void> _ensureMapDataAndNavigate() async {
    try {
      await PmtilesAssetCopier.ensureCopied();
      if (!mounted) return;
      context.go('/map');
    } on FileSystemException catch (e) {
      if (!mounted) return;
      _log.severe('PMTiles copy failed; routing to /error', e);
      context.go('/error', extra: e.message);
    }
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
                  const Icon(Icons.location_on_outlined, size: 64),
                  const SizedBox(height: 24),
                  Text(l10n.permissionRationaleParagraph, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _onCtaPressed, child: Text(l10n.permissionRationaleCta)),
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
