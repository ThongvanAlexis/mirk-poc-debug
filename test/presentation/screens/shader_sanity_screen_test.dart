// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/screens/shader_sanity_screen.dart';

/// Plan 03-06 Task 2 — ShaderSanityScreen (pre-walk gate) tests.
///
/// The production path (`ui.FragmentProgram.fromAsset`) cannot be exercised
/// from a headless widget-test runner — it needs a real Impeller/Skia
/// backend. We use the constructor-injected `programLoaderOverride` test
/// seam to drive the loading-state and error-state transitions
/// deterministically. The actual fog-render output is validated by manual
/// UAT in Plan 03-08 (developer opens /sanity on iPhone 17 Pro and visually
/// confirms the atmospheric fog with central reveal hole).
void main() {
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
        home: ShaderSanityScreen(programLoaderOverride: () => pendingCompleter.future),
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
        home: ShaderSanityScreen(programLoaderOverride: () async => throw StateError('shader load failed')),
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
        home: ShaderSanityScreen(programLoaderOverride: () => pendingCompleter.future),
      ),
    );
    await tester.pump();
    expect(find.text('Vérification du shader'), findsOneWidget);
  });
}
