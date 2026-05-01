// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
import 'package:mirk_poc_debug/presentation/widgets/frame_delta_probe_overlay.dart';

/// FOG-08 — FrameDeltaProbeOverlay smoke test.
///
/// Wave 0 contract: this test compiles against the Plan 03-01 stub (which
/// returns SizedBox.shrink). Plan 03-06 ships the real overlay that
/// subscribes to probe.rollups and renders three labelled lines (med / p95
/// / max) — at which point this test transitions from skipped to GREEN.
void main() {
  testWidgets('overlay renders 3 lines with med/p95/max prefixes '
      '[skipped — Plan 03-06 wires FrameDeltaProbeOverlay to probe.rollups + l10n labels; '
      'Wave 0 stub returns SizedBox.shrink]', (tester) async {
    final probe = FrameDeltaProbe();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: FrameDeltaProbeOverlay(probe: probe)),
      ),
    );
    // Initial state — no rollup yet — render must not throw.
    // After 1 s with synthetic samples, the overlay should display labels.
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('med'), findsOneWidget);
    expect(find.textContaining('p95'), findsOneWidget);
    expect(find.textContaining('max'), findsOneWidget);
  }, skip: true);
}
