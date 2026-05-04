// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/fog_transform_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/frame_delta_probe.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf/sdf_cache.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/sdf_rebuild_logger.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_particle_system.dart';
import 'package:mirk_poc_debug/infrastructure/mirk/wisp/wisp_transform_logger.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';

import '../../_helpers/recording_fog_shader_renderer.dart';

/// FOG-07 KEYSTONE — `MapCamera.of(context)` is called EXACTLY ONCE per
/// `FogLayer.build` invocation.
///
/// This is the single most important Phase 3 unit test — it directly
/// defends against the BUG-014 family where the SDF rect, the clip path,
/// and the shader uniforms each read a slightly-different `MapCamera`,
/// producing the slide-then-snap fog artefact that Phase 3 sets out to
/// disprove.
///
/// The test seam is `FogLayer.debugOnCameraRead` — a `static void Function()?`
/// invoked exactly once per build right before `MapCamera.of(context)`.
/// Tests count invocations to enforce the "exactly one read per build"
/// invariant. Production: null, zero overhead.
///
/// `FogLayer.shader` is passed as `null` (dart:ui's `FragmentShader` is a
/// `base` class — implementing it from a test file is forbidden). The
/// recording renderer ignores the shader argument.
void main() {
  testWidgets('FogLayer reads MapCamera.of(context) exactly once per build (FOG-07 KEYSTONE)', (tester) async {
    var readCount = 0;
    FogLayer.debugOnCameraRead = () => readCount++;
    addTearDown(() => FogLayer.debugOnCameraRead = null);

    final probe = FrameDeltaProbe();
    addTearDown(() async => probe.dispose());
    final discRepository = RevealDiscRepository();
    addTearDown(discRepository.dispose);
    final sdfCache = SdfCache(rebuildLogger: SdfRebuildLogger());
    addTearDown(sdfCache.dispose);
    final fogTransformLogger = FogTransformLogger();
    addTearDown(fogTransformLogger.stop);
    final wispTransformLogger = WispTransformLogger();
    addTearDown(wispTransformLogger.stop);
    final wispParticleSystem = WispParticleSystem();
    final renderer = RecordingFogShaderRenderer();

    // Build harness with a controlled rebuild trigger — a ValueKey on the
    // FlutterMap mutates via setState in a wrapper; that forces FogLayer
    // to rebuild without involving the gesture system.
    var rebuildKey = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  Expanded(
                    child: FlutterMap(
                      key: ValueKey<int>(rebuildKey),
                      options: const MapOptions(initialCenter: LatLng(48.5397, 2.6553), initialZoom: 13),
                      children: <Widget>[
                        FogLayer(
                          discRepository: discRepository,
                          shader: null,
                          sdfCache: sdfCache,
                          frameDeltaProbe: probe,
                          fogTransformLogger: fogTransformLogger,
                          wispParticleSystem: wispParticleSystem,
                          wispTransformLogger: wispTransformLogger,
                          shaderRenderer: renderer,
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(key: const Key('rebuild-trigger'), onPressed: () => setState(() => rebuildKey++), child: const Text('rebuild')),
                ],
              ),
            ),
          );
        },
      ),
    );

    // Initial pump → exactly 1 read.
    expect(readCount, 1, reason: 'FOG-07: exactly one MapCamera.of(context) call per build');

    // Force a rebuild via setState on the key. Each rebuild MUST produce
    // exactly one additional read.
    await tester.tap(find.byKey(const Key('rebuild-trigger')));
    await tester.pump();
    expect(readCount, 2, reason: 'FOG-07: each forced rebuild bumps readCount by exactly 1');

    await tester.tap(find.byKey(const Key('rebuild-trigger')));
    await tester.pump();
    expect(readCount, 3, reason: 'FOG-07: third rebuild → readCount == 3 (never more, never fewer)');
  });
}
