// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/widgets/poc_app_bar.dart';
import 'package:mirk_poc_debug/state/debug_spiral_state.dart';

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
    // Phase 3 added a second IconButton (Icons.science → /sanity); narrow to
    // the share button via its icon so this LOG-04 assertion keeps holding.
    final shareIcon = find.ancestor(of: find.byIcon(Icons.share), matching: find.byType(IconButton));
    final iconButton = tester.widget<IconButton>(shareIcon);
    expect(iconButton.tooltip, equals('Share logs'));
  });

  testWidgets('French tooltip is "Partager les logs"', (tester) async {
    await tester.pumpWidget(_wrap(locale: const Locale('fr')));
    final shareIcon = find.ancestor(of: find.byIcon(Icons.share), matching: find.byType(IconButton));
    final iconButton = tester.widget<IconButton>(shareIcon);
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

  group('Plan 03.1-08-FIX FIX 2 — global debug-spiral toggle', () {
    setUp(() {
      debugSpiralEnabled.value = false;
    });
    tearDown(() {
      debugSpiralEnabled.value = false;
    });

    testWidgets('Switch is present in AppBar actions', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Switch), findsOneWidget, reason: 'Plan 03.1-08-FIX FIX 2: PocAppBar must expose a Switch.adaptive for the debug-spiral toggle.');
    });

    testWidgets('Switch defaults to OFF (debugSpiralEnabled.value == false)', (tester) async {
      await tester.pumpWidget(_wrap());
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse, reason: 'Default state must be OFF — production fog rendering unchanged when toggle is OFF.');
    });

    testWidgets('Switch is wrapped in Tooltip with debugSpiralToggleTooltip l10n string (EN)', (tester) async {
      await tester.pumpWidget(_wrap());
      final tooltipFinder = find.ancestor(of: find.byType(Switch), matching: find.byType(Tooltip));
      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, equals('Toggle debug spiral shader'));
    });

    testWidgets('flipping the Switch updates the global debugSpiralEnabled notifier', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(debugSpiralEnabled.value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(
        debugSpiralEnabled.value,
        isTrue,
        reason: 'Tapping the Switch must flip the shared notifier — value is the source of truth shared with /map and /sanity.',
      );
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(debugSpiralEnabled.value, isFalse, reason: 'Second tap must flip back to OFF.');
    });

    testWidgets('Switch reflects external notifier flips (cross-screen state propagation)', (tester) async {
      await tester.pumpWidget(_wrap());
      // Simulate /sanity flipping the notifier; /map's PocAppBar Switch
      // must rebuild to ON via ValueListenableBuilder.
      debugSpiralEnabled.value = true;
      await tester.pump();
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(
        switchWidget.value,
        isTrue,
        reason:
            'Plan 03.1-08-FIX FIX 2: PocAppBar Switch must rebuild via ValueListenableBuilder when the shared notifier flips externally — '
            'this is what keeps /map and /sanity toggle UI in lockstep across navigation.',
      );
    });
  });

  group('Plan 03.1-09-CORR — dev-observation marker button', () {
    setUpAll(() {
      // Logger.root must be at FINE or below for INFO-level emissions to
      // surface through Logger.root.onRecord; default Level.WARNING swallows
      // INFO lines. Same setup the infrastructure.mirk.* logger tests use.
      Logger.root.level = Level.ALL;
    });

    testWidgets('Icons.bug_report IconButton is present in AppBar actions', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(
        find.byIcon(Icons.bug_report),
        findsOneWidget,
        reason: 'Plan 03.1-09-CORR: PocAppBar must expose an Icons.bug_report IconButton for the dev-observation marker.',
      );
    });

    testWidgets('English tooltip is "Log dev observation marker"', (tester) async {
      await tester.pumpWidget(_wrap());
      final markerButton = find.ancestor(of: find.byIcon(Icons.bug_report), matching: find.byType(IconButton));
      final iconButton = tester.widget<IconButton>(markerButton);
      expect(iconButton.tooltip, equals('Log dev observation marker'));
    });

    testWidgets('French tooltip is "Marquer une observation de développeur"', (tester) async {
      await tester.pumpWidget(_wrap(locale: const Locale('fr')));
      final markerButton = find.ancestor(of: find.byIcon(Icons.bug_report), matching: find.byType(IconButton));
      final iconButton = tester.widget<IconButton>(markerButton);
      expect(iconButton.tooltip, equals('Marquer une observation de développeur'));
    });

    testWidgets('tap emits a dev_marker JSONL line on the infrastructure.mirk.dev_marker logger', (tester) async {
      // The `logging` package uses `StreamController.broadcast(sync: true)`
      // for `Logger.root.onRecord` (logging-1.3.0 logger.dart:307). We
      // attach the listener directly (no `.where()` transformation — that
      // wraps the sync source in an async stream and microtask scheduling
      // under flutter_test's fake-async clock makes the listener fire only
      // when `pump()` drains the microtask queue, which works but feels
      // fragile). Filtering happens in-listener, off the synchronous path.
      final captured = <LogRecord>[];
      final sub = Logger.root.onRecord.listen((LogRecord r) {
        if (r.loggerName == 'infrastructure.mirk.dev_marker') captured.add(r);
      });
      addTearDown(sub.cancel);

      await tester.pumpWidget(_wrap());
      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pump();
      expect(captured, hasLength(1), reason: 'One tap must produce exactly one dev_marker log record.');
      final decoded = json.decode(captured.single.message) as Map<String, Object?>;
      expect(decoded['event'], equals('dev_marker'));
      expect(decoded['tag'], equals('steppy_translation'), reason: 'Plan 03.1-09-CORR — Walk #4 hardcoded tag.');
      expect(decoded['epochMs'], isA<int>());
    });
  });
}
