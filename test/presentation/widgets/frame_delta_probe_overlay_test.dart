// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/widgets/frame_delta_probe_overlay.dart';

/// FOG-08 — FrameDeltaProbeOverlay tests.
///
/// Plan 03-06 ships the real overlay: subscribes to `probe.rollups`,
/// renders three colour-coded lines (med / p95 / max) localised via
/// [AppLocalizations]. Pre-rollup placeholder uses a dash + neutral white;
/// post-rollup colours follow the [kPocFrameDeltaMedianGreenMicros] /
/// [kPocFrameDeltaMedianYellowMicros] family of thresholds.
void main() {
  testWidgets('renders 3 lines with localized labels and placeholder values before first rollup', (tester) async {
    final probe = FrameDeltaProbe();
    addTearDown(() async => probe.dispose());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: FrameDeltaProbeOverlay(probe: probe)),
      ),
    );
    expect(find.textContaining('med'), findsOneWidget);
    expect(find.textContaining('p95'), findsOneWidget);
    expect(find.textContaining('max'), findsOneWidget);
    // Placeholder dash before any rollup — three lines, three dashes.
    expect(find.textContaining('–'), findsAtLeastNWidgets(3));
  });

  testWidgets('renders rollup values and applies green/yellow/red color coding', (tester) async {
    final probe = FrameDeltaProbe(rollupInterval: const Duration(milliseconds: 50));
    addTearDown(() async => probe.dispose());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: FrameDeltaProbeOverlay(probe: probe)),
      ),
    );

    // Inject deterministic deltas via Plan 03-04's debugRecordRawDelta seam:
    //   * 10 samples of 8000 µs (8 ms)  → median ≤ 16 ms green threshold  → greenAccent
    //   * Worst sample 40000 µs (40 ms) → p95 ∈ (32, 48] ms yellow band   → amberAccent
    //   * Single 100000 µs (100 ms) sample → max > 72 ms red zone          → redAccent
    for (var i = 0; i < 10; i++) {
      probe.debugRecordRawDelta(8000);
    }
    probe.debugRecordRawDelta(40000);
    probe.debugRecordRawDelta(100000);
    probe.start();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(); // let the StreamController emission flush through setState

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final medText = tester.widget<Text>(find.textContaining(l10n.frameDeltaProbeMedianLabel));
    expect(medText.style?.color, Colors.greenAccent, reason: 'median 8 ms is in the green zone (≤ 16 ms)');

    final p95Text = tester.widget<Text>(find.textContaining(l10n.frameDeltaProbeP95Label));
    expect(p95Text.style?.color, Colors.amberAccent, reason: 'p95 40 ms is in the yellow band (32 ms < p95 ≤ 48 ms)');

    final maxText = tester.widget<Text>(find.textContaining(l10n.frameDeltaProbeMaxLabel));
    expect(maxText.style?.color, Colors.redAccent, reason: 'max 100 ms is in the red zone (> 72 ms)');
  });
}
