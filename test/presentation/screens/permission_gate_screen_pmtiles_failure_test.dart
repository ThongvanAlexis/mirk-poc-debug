// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// permission_handler_platform_interface is a transitive dep of permission_handler 12.0.1
// (declared in pubspec.lock but not pubspec.yaml). The platform-instance override is
// the documented test seam — see Plan 01-06 RESEARCH.md notes.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/error_screen.dart';
import 'package:mirk_poc_debug/presentation/screens/permission_gate_screen.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Test-only PermissionHandlerPlatform override that returns granted on
/// request, simulating "user accepts the iOS prompt".
class _GrantingPermissionPlatform extends PermissionHandlerPlatform {
  _GrantingPermissionPlatform();

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async => PermissionStatus.denied;

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
  setUp(() {
    PermissionHandlerPlatform.instance = _GrantingPermissionPlatform();
  });

  testWidgets('MAP-01 failure path: PMTiles copy FileSystemException routes to /error with detail', (tester) async {
    // CONTRACT (Plan 02-02 turns this GREEN):
    //   1. User taps "Allow location" CTA on the gate screen.
    //   2. Permission grant returns granted.
    //   3. Gate screen awaits PmtilesAssetCopier.ensureCopied().
    //   4. ensureCopied throws FileSystemException — Plan 02-02 wires a
    //      @visibleForTesting test override field on PmtilesAssetCopier;
    //      production calls land in Plan 02-02 in real code.
    //   5. Gate screen catches FileSystemException, navigates to '/error'
    //      with extra == exception.message.
    //
    // Wave 0 RED state: gate screen does NOT yet call ensureCopied between
    // grant and /map, so this test fails at the final navigation assertion
    // (it lands on /map instead of /error). Plan 02-02 flips RED → GREEN.

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
  });
}
