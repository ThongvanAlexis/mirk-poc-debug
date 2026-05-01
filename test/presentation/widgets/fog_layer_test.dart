// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter_test/flutter_test.dart';

/// FOG-04 — FogLayer wrapped by MobileLayerTransformer when mounted inside
/// FlutterMap.
///
/// Wave 0 contract: this test compiles and is skipped because the
/// FogLayer stub returns SizedBox.shrink (no MobileLayerTransformer
/// ancestry yet). Plan 03-05 wires the layer's build to wrap its child in
/// MobileLayerTransformer AND introduces a `_FakeShader` test seam (the
/// dart:ui `FragmentShader` is a `base` class — implementing it from a
/// test file requires the seam to be defined inside the production
/// library).
///
/// When Plan 03-05 lands, the body becomes (in pseudo-Dart):
/// ```
/// await tester.pumpWidget(
///   MaterialApp(home: FlutterMap(options: MapOptions(...), children: [
///     FogLayer(discRepository: ..., shader: ..., sdfCache: ..., frameDeltaProbe: ...),
///   ])),
/// );
/// expect(find.ancestor(of: find.byType(FogLayer), matching: find.byType(MobileLayerTransformer)),
///        findsOneWidget,
///        reason: 'FOG-04: FogLayer must be wrapped by MobileLayerTransformer inside its build');
/// ```
void main() {
  testWidgets('FogLayer is wrapped by MobileLayerTransformer when mounted inside FlutterMap '
      '[skipped — Plan 03-05 wires FogLayer.build + introduces FragmentShader test seam]', (tester) async {
    // Body fleshed out by Plan 03-05; current stub returns SizedBox.shrink.
    expect(true, isTrue);
  }, skip: true);
}
