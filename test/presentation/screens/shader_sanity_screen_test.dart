// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/shader_sanity_screen.dart';

/// Phase 3 pre-walk gate — ShaderSanityScreen smoke test.
///
/// Wave 0 contract: the FR-locale title test runs against the Plan 03-01
/// placeholder body and is GREEN now (it asserts the AppBar title via
/// l10n). The "no-exception" test pumps the placeholder; once Plan 03-06
/// loads the real shader, it will need a constructor-injected program
/// loader test seam (otherwise the test would actually load the .frag,
/// which is not loadable in a unit-test runner).
void main() {
  testWidgets('AppBar title via l10n (FR locale)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShaderSanityScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Vérification du shader'), findsOneWidget);
  });

  testWidgets('ShaderSanityScreen builds without exception (production path uses real FragmentProgram; test uses a fake) '
      '[skipped — Plan 03-06 introduces a constructor-injected FragmentProgram loader test seam so the test does '
      'not actually load the .frag]', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShaderSanityScreen(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, skip: true);
}
