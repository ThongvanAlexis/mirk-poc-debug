// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

// permission_handler_platform_interface is a transitive dep of permission_handler 12.0.1
// (declared in pubspec.lock but not pubspec.yaml). The platform-instance override is
// the documented test seam — same pattern as permission_gate_screen_test.dart.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/permission_denied_screen.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Test-only override capturing openAppSettings invocations.
class _MockPermissionHandlerPlatform extends PermissionHandlerPlatform {
  int openAppSettingsCallCount = 0;

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCallCount++;
    return true;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  late _MockPermissionHandlerPlatform mock;

  setUp(() {
    mock = _MockPermissionHandlerPlatform();
    PermissionHandlerPlatform.instance = mock;
  });

  testWidgets('AUTH-04 — denied paragraph renders', (tester) async {
    await tester.pumpWidget(_wrap(const PermissionDeniedScreen()));
    expect(find.textContaining('Without permission'), findsOneWidget);
  });

  testWidgets('AUTH-04 — Open Settings button renders', (tester) async {
    await tester.pumpWidget(_wrap(const PermissionDeniedScreen()));
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('AUTH-04 — Open Settings button invokes openAppSettings', (tester) async {
    await tester.pumpWidget(_wrap(const PermissionDeniedScreen()));
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(mock.openAppSettingsCallCount, equals(1));
  });

  testWidgets('LOG-04 — share IconButton visible from denied screen', (tester) async {
    await tester.pumpWidget(_wrap(const PermissionDeniedScreen()));
    expect(find.byIcon(Icons.share), findsOneWidget);
  });

  testWidgets('PERF-01 — FpsCounterOverlay visible from denied screen', (tester) async {
    await tester.pumpWidget(_wrap(const PermissionDeniedScreen()));
    // FpsCounterOverlay renders Text containing 'fps'.
    expect(find.textContaining('fps'), findsOneWidget);
  });
}
