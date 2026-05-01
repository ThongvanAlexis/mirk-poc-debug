// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';

import '../../_helpers/recording_fog_shader_renderer.dart';

/// FOG-04 — `FogLayer` is wrapped by `MobileLayerTransformer` when mounted
/// inside a `FlutterMap`.
///
/// Plan 03-05 ships the production wiring + the `RecordingFogShaderRenderer`
/// test seam (test/_helpers/) so the widget tree can be pumped without a
/// real `ui.FragmentShader`. `FogLayer.shader` is nullable because dart:ui's
/// `FragmentShader` is a `base` class — it cannot be implemented from a test
/// file. Tests pass `null` and rely on the recording renderer to assert
/// behavioural coverage; production callers ALWAYS pass a non-null shader.
void main() {
  testWidgets('FogLayer is wrapped by MobileLayerTransformer when mounted inside FlutterMap (FOG-04)', (tester) async {
    final probe = FrameDeltaProbe();
    addTearDown(() async => probe.dispose());
    final discRepository = RevealDiscRepository();
    addTearDown(discRepository.dispose);
    final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
    addTearDown(sdfCache.dispose);
    final renderer = RecordingFogShaderRenderer();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: FlutterMap(
              options: const MapOptions(initialCenter: LatLng(48.5397, 2.6553), initialZoom: 13),
              children: <Widget>[
                FogLayer(
                  discRepository: discRepository,
                  shader: null, // base-class — see file docstring.
                  sdfCache: sdfCache,
                  frameDeltaProbe: probe,
                  shaderRenderer: renderer,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Pump again to flush the post-frame callback that lets FlutterMap finish
    // its first layout pass; without this, the FogLayer's build may not have
    // executed yet and the descendant query returns nothing.
    await tester.pump();

    // FOG-04: FogLayer.build() returns `MobileLayerTransformer(child: CustomPaint(...))`
    // — so the transformer is a DESCENDANT of FogLayer, not an ancestor. (FlutterMap
    // does NOT auto-wrap its children in MobileLayerTransformer; each layer is
    // responsible for its own wrap. See flutter_map 7.0.2 lib/src/map/widget.dart
    // lines 97-108: children render directly inside a Stack.)
    expect(
      find.descendant(of: find.byType(FogLayer), matching: find.byType(MobileLayerTransformer)),
      findsOneWidget,
      reason: 'FOG-04: FogLayer.build() must wrap its CustomPaint in MobileLayerTransformer',
    );
  });
}
