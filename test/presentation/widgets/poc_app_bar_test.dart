// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/widgets/poc_app_bar.dart';

/// Pumps a MaterialApp with AppLocalizations wired so that buildPocAppBar
/// can resolve l10n strings during widget tests.
Widget _wrap({Widget? body, Locale locale = const Locale('en'), String? title}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: buildPocAppBar(context, title: title),
        body: body ?? const SizedBox.shrink(),
      ),
    ),
  );
}

void main() {
  testWidgets('LOG-04 — share IconButton is present in AppBar actions', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.byIcon(Icons.share), findsOneWidget);
  });

  testWidgets('English tooltip is "Share logs"', (tester) async {
    await tester.pumpWidget(_wrap());
    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    expect(iconButton.tooltip, equals('Share logs'));
  });

  testWidgets('French tooltip is "Partager les logs"', (tester) async {
    await tester.pumpWidget(_wrap(locale: const Locale('fr')));
    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    expect(iconButton.tooltip, equals('Partager les logs'));
  });

  testWidgets('Default title falls back to AppLocalizations.appTitle', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.text('MirkFall POC'), findsOneWidget);
  });

  testWidgets('Custom title overrides appTitle default', (tester) async {
    await tester.pumpWidget(_wrap(title: 'Custom'));
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('MirkFall POC'), findsNothing);
  });
}
