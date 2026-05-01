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
import 'package:mirk_poc_debug/infrastructure/pmtiles/pmtiles_asset_copier.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/permission_gate_screen.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Test-only PermissionHandlerPlatform override. Returns canned PermissionStatus
/// values without invoking real platform channels. Mutate [statusReturn] /
/// [requestReturn] mid-test to simulate post-Settings round-trip.
class _MockPermissionHandlerPlatform extends PermissionHandlerPlatform {
  _MockPermissionHandlerPlatform();

  PermissionStatus statusReturn = PermissionStatus.denied;
  PermissionStatus requestReturn = PermissionStatus.denied;
  int requestCallCount = 0;
  int statusCallCount = 0;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    statusCallCount++;
    return statusReturn;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(List<Permission> permissions) async {
    requestCallCount++;
    return <Permission, PermissionStatus>{for (final p in permissions) p: requestReturn};
  }
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
    ],
  );
}

Widget _wrap(GoRouter router) {
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
  );
}

void main() {
  late _MockPermissionHandlerPlatform mock;

  setUp(() {
    mock = _MockPermissionHandlerPlatform();
    PermissionHandlerPlatform.instance = mock;
    // Phase 2 Plan 02: gate screen now calls PmtilesAssetCopier.ensureCopied
    // on every grant path (CTA + lifecycle re-check). The override prevents
    // the test from hitting the real getApplicationSupportDirectory + asset
    // bundle, which would either flake or throw in the unit-test environment.
    PmtilesAssetCopier.testEnsureCopiedOverride = () async => '/fake/maps/Fra_Melun.pmtile';
  });

  tearDown(() {
    PmtilesAssetCopier.testEnsureCopiedOverride = null;
  });

  testWidgets('AUTH-01 — rationale screen renders icon + paragraph + CTA', (tester) async {
    await tester.pumpWidget(_wrap(_buildRouter()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    expect(find.textContaining('your location'), findsOneWidget);
    expect(find.text('Allow location'), findsOneWidget);
  });

  testWidgets('AUTH-02 — tapping CTA invokes requestPermissions', (tester) async {
    await tester.pumpWidget(_wrap(_buildRouter()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow location'));
    await tester.pumpAndSettle();
    expect(mock.requestCallCount, equals(1));
  });

  testWidgets('AUTH-03 — grant routes to /map', (tester) async {
    mock.requestReturn = PermissionStatus.granted;
    final router = _buildRouter();
    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow location'));
    await tester.pumpAndSettle();
    expect(find.text('MAP_STUB'), findsOneWidget);
  });

  testWidgets('Deny routes to /denied', (tester) async {
    mock.requestReturn = PermissionStatus.denied;
    final router = _buildRouter();
    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow location'));
    await tester.pumpAndSettle();
    expect(find.text('DENIED_STUB'), findsOneWidget);
  });

  testWidgets('Re-launch shortcut — already granted skips rationale', (tester) async {
    mock.statusReturn = PermissionStatus.granted;
    final router = _buildRouter();
    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    expect(find.text('MAP_STUB'), findsOneWidget);
    expect(find.text('Allow location'), findsNothing);
  });

  testWidgets('Lifecycle resume re-check — denied → granted in Settings → app resumes → auto-nav to /map (W-2 fix)', (tester) async {
    // Phase 1: initial status is denied. Screen MUST render the CTA (no auto-nav).
    mock.statusReturn = PermissionStatus.denied;
    final router = _buildRouter();
    await tester.pumpWidget(_wrap(router));
    await tester.pumpAndSettle();
    expect(find.text('Allow location'), findsOneWidget, reason: 'Initial denied status should render the rationale CTA, not auto-navigate.');
    expect(find.text('MAP_STUB'), findsNothing);

    // Phase 2: simulate user toggling permission ON in iOS Settings.
    // Flip the mock BEFORE firing the lifecycle event.
    mock.statusReturn = PermissionStatus.granted;

    // Phase 3: fire AppLifecycleState.resumed exactly as the platform would
    // when the user swipes back from iOS Settings into the app. The test
    // binding's handleAppLifecycleStateChanged dispatches through the same
    // observer chain real iOS uses (every WidgetsBindingObserver receives
    // didChangeAppLifecycleState).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Phase 4: the lifecycle observer must re-check status, see granted, and
    // navigate to /map. MAP_STUB indicates GoRouter is at /map; the CTA is
    // gone because the gate screen was popped.
    expect(find.text('MAP_STUB'), findsOneWidget, reason: 'After AppLifecycleState.resumed with granted status, screen MUST auto-navigate to /map.');
    expect(find.text('Allow location'), findsNothing, reason: 'CTA must be gone — gate screen replaced by /map.');
  });
}
