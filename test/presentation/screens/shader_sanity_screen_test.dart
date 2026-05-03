// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/shader_sanity_screen.dart';
import 'package:mirk_poc_debug/state/debug_spiral_state.dart';

/// Plan 03-06 Task 2 — ShaderSanityScreen (pre-walk gate) tests.
///
/// The production path (`ui.FragmentProgram.fromAsset`) cannot be exercised
/// from a headless widget-test runner — it needs a real Impeller/Skia
/// backend. We use the constructor-injected `programLoaderOverride` test
/// seam to drive the loading-state and error-state transitions
/// deterministically. The actual fog-render output is validated by manual
/// UAT in Plan 03-08 (developer opens /sanity on iPhone 17 Pro and visually
/// confirms the atmospheric fog with central reveal hole).
///
/// Plan 03.1-05 Task 3 — UX-01 augment: AppBar back button pops `/sanity`
/// to the previous route. Catches the SANITY-NO-BACK-BUTTON failure mode
/// from `03.1-FALSIFICATION.md` observation 5 (developer had to force-close
/// the app to return from `/sanity` during the 03.1-03 walk).
///
/// Plan 03.1-07 — Adds the debug-spiral toggle test group. Asserts the
/// toggle defaults to OFF, flipping ON re-loads the shader with the
/// debug-spiral asset path, flipping OFF restores the production path.
///
/// Plan 03.1-08-FIX FIX 2 — the toggle state moved from a per-screen
/// `bool _useDebugSpiral` field to a top-level `ValueNotifier<bool>`
/// (`lib/state/debug_spiral_state.dart`) shared with the MapScreen
/// PocAppBar Switch. Tests reset the notifier in `setUp` so each test
/// starts from a known OFF state — without the reset, a leaking flipped
/// state from a prior test would corrupt later assertions.
void main() {
  setUp(() {
    debugSpiralEnabled.value = false;
  });
  tearDown(() {
    debugSpiralEnabled.value = false;
  });

  testWidgets('shows CircularProgressIndicator while program is loading', (tester) async {
    // Hold the loader future open with a Completer so the screen stays in
    // the loading state under the test's full control.
    final pendingCompleter = Completer<ui.FragmentProgram>();
    addTearDown(() {
      // Settle the future so its async chain unwinds before the next test.
      // We complete with an error because we can't instantiate a real
      // FragmentProgram — the screen handles the error path via _loadError.
      if (!pendingCompleter.isCompleted) pendingCompleter.completeError(StateError('test teardown'));
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShaderSanityScreen(programLoaderOverride: (_) => pendingCompleter.future),
      ),
    );
    // First frame: loader is still pending → spinner is up.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows error message when programLoaderOverride throws', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShaderSanityScreen(programLoaderOverride: (_) async => throw StateError('shader load failed')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('shader load failed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('AppBar title via l10n (FR locale)', (tester) async {
    // Keep the loader pending so we don't trip into the real
    // FragmentProgram.fromAsset path during the title-only assertion.
    final pendingCompleter = Completer<ui.FragmentProgram>();
    addTearDown(() {
      if (!pendingCompleter.isCompleted) pendingCompleter.completeError(StateError('test teardown'));
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShaderSanityScreen(programLoaderOverride: (_) => pendingCompleter.future),
      ),
    );
    await tester.pump();
    expect(find.text('Vérification du shader'), findsOneWidget);
  });

  group('UX-01 (Plan 03.1-05)', () {
    testWidgets('AppBar back button pops /sanity to previous route', (tester) async {
      // Two-route router stack — `/` (placeholder home) + `/sanity`
      // (ShaderSanityScreen). The test pushes to `/sanity` then taps the
      // AppBar back button; the previous route must reappear.
      //
      // Inject a never-completing loader so the screen sits in the loading
      // state — we only test AppBar nav, not the shader-load path.
      final pendingCompleter = Completer<ui.FragmentProgram>();
      addTearDown(() {
        if (!pendingCompleter.isCompleted) pendingCompleter.completeError(StateError('test teardown'));
      });

      final router = GoRouter(
        initialLocation: '/',
        routes: <GoRoute>[
          GoRoute(path: '/', builder: (_, _) => const _PlaceholderHome()),
          GoRoute(
            path: '/sanity',
            builder: (_, _) => ShaderSanityScreen(programLoaderOverride: (_) => pendingCompleter.future),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
      // pump() not pumpAndSettle() — the home screen has no animations to
      // settle, and the sanity screen (when navigated below) holds an
      // in-flight CircularProgressIndicator that pumpAndSettle would chase
      // forever (the loader Completer never completes by design).
      await tester.pump();
      expect(find.byType(_PlaceholderHome), findsOneWidget);

      // Push to /sanity from the home placeholder, then assert the screen
      // and its back-button are present. `router.push` returns a Future
      // (route value when the route eventually pops); we don't await it
      // because the route is still on the stack when the back button is
      // tapped below.
      unawaited(router.push('/sanity'));
      // Two pumps to settle the GoRouter route transition; pumpAndSettle
      // would block on the CircularProgressIndicator's repaint loop.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(ShaderSanityScreen), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Tap the back button → pop to '/'.
      await tester.tap(find.byIcon(Icons.arrow_back));
      // Pump several frames so the GoRouter pop transition + Navigator route
      // disposal fully settle. We can't pumpAndSettle (the sanity screen
      // holds an in-flight CircularProgressIndicator) — use a finite
      // sequence of long-duration pumps that exceed the default Material
      // page transition (300 ms) without chasing the spinner forever.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(_PlaceholderHome), findsOneWidget, reason: 'UX-01: tapping the back button on /sanity must pop to the previous route.');
      expect(find.byType(ShaderSanityScreen), findsNothing);
    });
  });

  group('Plan 03.1-07 debug-spiral toggle', () {
    testWidgets('toggle defaults to OFF on first build', (tester) async {
      final pendingCompleter = Completer<ui.FragmentProgram>();
      addTearDown(() {
        if (!pendingCompleter.isCompleted) pendingCompleter.completeError(StateError('test teardown'));
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShaderSanityScreen(programLoaderOverride: (_) => pendingCompleter.future),
        ),
      );
      await tester.pump();
      // Find the Switch.adaptive in the AppBar actions and assert its
      // initial value is false.
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse, reason: 'Plan 03.1-07: debug-spiral toggle must default to OFF — production fog at /sanity unchanged.');
    });

    testWidgets('toggling ON re-loads with the debug-spiral asset path', (tester) async {
      // Track every shader path requested via the loader override so the
      // test can assert which path was loaded after the toggle flip.
      // Inline-closure pattern (no separate RecordingProgramLoader helper
      // class — single-test scope, sufficient for the assertion).
      final loadedPaths = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShaderSanityScreen(
            programLoaderOverride: (path) {
              loadedPaths.add(path);
              // Return a never-completing future so we don't trip into
              // the SDF-build / atlas-build async chain that needs
              // tester.runAsync.
              return Completer<ui.FragmentProgram>().future;
            },
          ),
        ),
      );
      await tester.pump();
      expect(loadedPaths, equals(<String>[kPocFogShaderAssetPath]), reason: 'Plan 03.1-07: initial load must request the production fog shader.');

      // Tap the Switch.adaptive. Its onChanged setState triggers a
      // re-load via _load() with the debug-spiral asset path.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(loadedPaths.last, equals(kPocDebugSpiralShaderAssetPath), reason: 'Plan 03.1-07: toggling ON must request the debug-spiral shader path.');

      // Tap again — toggle OFF. Loader must be invoked with the
      // production path again.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(loadedPaths.last, equals(kPocFogShaderAssetPath), reason: 'Plan 03.1-07: toggling OFF must restore the production fog shader path.');
    });

    testWidgets('toggle exposes a Tooltip with the debugSpiralToggleTooltip l10n key', (tester) async {
      final pendingCompleter = Completer<ui.FragmentProgram>();
      addTearDown(() {
        if (!pendingCompleter.isCompleted) pendingCompleter.completeError(StateError('test teardown'));
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShaderSanityScreen(programLoaderOverride: (_) => pendingCompleter.future),
        ),
      );
      await tester.pump();
      // Find the Tooltip wrapping the Switch (we put it as the actions[0]
      // child). Assert the message matches the l10n EN string.
      final tooltipFinder = find.ancestor(of: find.byType(Switch), matching: find.byType(Tooltip));
      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(
        tooltip.message,
        equals('Toggle debug spiral shader'),
        reason: 'Plan 03.1-07: Switch must be wrapped in a Tooltip with the debugSpiralToggleTooltip l10n string.',
      );
    });
  });
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('home')));
}
