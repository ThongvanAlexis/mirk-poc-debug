// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// permission_handler_platform_interface is a transitive dep of permission_handler 12.0.1
// (declared in pubspec.lock but not pubspec.yaml). The platform-instance override is
// the documented test seam — see Plan 01-06 RESEARCH.md notes.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:mirk_poc_debug/infrastructure/pmtiles/pmtiles_asset_copier.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/error_screen.dart';
import 'package:mirk_poc_debug/presentation/screens/permission_gate_screen.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Test-only PermissionHandlerPlatform override that returns granted on both
/// the synchronous status read and the prompt request — simulates "user has
/// already granted" (lifecycle path) and "user accepts the iOS prompt" (CTA
/// path) without invoking the real platform channel.
class _GrantingPermissionPlatform extends PermissionHandlerPlatform {
  _GrantingPermissionPlatform({this.statusReturn = PermissionStatus.denied});

  PermissionStatus statusReturn;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async => statusReturn;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(List<Permission> permissions) async => <Permission, PermissionStatus>{
    for (final p in permissions) p: PermissionStatus.granted,
  };
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: <GoRoute>[
      GoRoute(path: '/', builder: (_, _) => const PermissionGateScreen()),
      GoRoute(
        path: '/map',
        builder: (_, _) => const Scaffold(body: Center(child: Text('MAP_STUB'))),
      ),
      GoRoute(
        path: '/denied',
        builder: (_, _) => const Scaffold(body: Center(child: Text('DENIED_STUB'))),
      ),
      GoRoute(
        path: '/error',
        builder: (_, GoRouterState state) {
          final extra = state.extra;
          final detail = extra is String ? extra : '<no detail>';
          return ErrorScreen(detail: detail);
        },
      ),
    ],
  );
}

Widget _wrap(GoRouter router) => MaterialApp.router(
  routerConfig: router,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
);

void main() {
  late List<LogRecord> logRecords;
  late StreamSubscription<LogRecord> logSub;

  setUp(() {
    logRecords = <LogRecord>[];
    Logger.root.level = Level.ALL;
    logSub = Logger.root.onRecord.listen(logRecords.add);
  });

  tearDown(() async {
    PmtilesAssetCopier.testEnsureCopiedOverride = null;
    await logSub.cancel();
  });

  testWidgets('MAP-01 CTA failure path: PMTiles copy FileSystemException routes to /error with detail', (tester) async {
    // Lifecycle path must NOT hit the failing override — initState fires
    // _checkAndMaybeNavigate; status is denied so it bails before ensureCopied.
    PermissionHandlerPlatform.instance = _GrantingPermissionPlatform();
    PmtilesAssetCopier.testEnsureCopiedOverride = () async => throw const FileSystemException('disk full');

    await tester.pumpWidget(_wrap(_buildRouter()));
    await tester.pumpAndSettle();
    expect(find.text('Allow location'), findsOneWidget);

    await tester.tap(find.text('Allow location'));
    await tester.pumpAndSettle();

    expect(
      find.byType(ErrorScreen),
      findsOneWidget,
      reason: 'After permission grant + ensureCopied throwing FileSystemException, gate screen MUST navigate to /error.',
    );
    expect(find.text('disk full'), findsOneWidget, reason: 'ErrorScreen MUST render the FileSystemException.message verbatim.');

    final severeLines = logRecords.where((r) => r.level >= Level.SEVERE && r.loggerName == 'presentation.screens.permission_gate');
    expect(severeLines, isNotEmpty, reason: 'Failure path MUST log at SEVERE on the gate screen logger.');
  });

  testWidgets('MAP-01 lifecycle failure path: pre-granted status + copy failure routes to /error', (tester) async {
    // Status is granted from the start — initState's _checkAndMaybeNavigate
    // hits ensureCopied directly without a CTA tap (CONTEXT mandate: lifecycle
    // and CTA paths must converge through the same copy hook).
    PermissionHandlerPlatform.instance = _GrantingPermissionPlatform(statusReturn: PermissionStatus.granted);
    PmtilesAssetCopier.testEnsureCopiedOverride = () async => throw const FileSystemException('read-only filesystem');

    await tester.pumpWidget(_wrap(_buildRouter()));
    await tester.pumpAndSettle();

    expect(
      find.byType(ErrorScreen),
      findsOneWidget,
      reason: 'Pre-granted status path MUST also hit ensureCopied and route to /error on failure.',
    );
    expect(find.text('read-only filesystem'), findsOneWidget);
  });

  testWidgets('MAP-01 CTA happy path: grant + successful copy routes to /map', (tester) async {
    PermissionHandlerPlatform.instance = _GrantingPermissionPlatform();
    PmtilesAssetCopier.testEnsureCopiedOverride = () async => '/fake/maps/Fra_Melun.pmtile';

    await tester.pumpWidget(_wrap(_buildRouter()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow location'));
    await tester.pumpAndSettle();

    expect(find.text('MAP_STUB'), findsOneWidget, reason: 'Successful ensureCopied MUST allow navigation to /map.');
    expect(find.byType(ErrorScreen), findsNothing);
  });
}
