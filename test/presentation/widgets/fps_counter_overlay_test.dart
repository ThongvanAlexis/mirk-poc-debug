// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirk_poc_debug/presentation/widgets/fps_counter_overlay.dart';

void main() {
  testWidgets('PERF-01 — renders fps text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: FpsCounterOverlay())),
    ));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, isNotNull);
    expect(text.data!, contains('fps'));
  });

  testWidgets('Pitfall E — renders Hz text (ProMotion-aware)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: FpsCounterOverlay())),
    ));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data!, contains('Hz'));
  });

  testWidgets('Pitfall E — refresh rate read from PlatformDispatcher (not hardcoded)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: FpsCounterOverlay())),
    ));
    final expectedRefresh = WidgetsBinding.instance.platformDispatcher.views.first.display.refreshRate.toStringAsFixed(0);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data!, contains('$expectedRefresh Hz'));
  });

  testWidgets('Initial fps reading is 0 (graceful empty state)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: FpsCounterOverlay())),
    ));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data!, startsWith('0 fps'));
  });
}
