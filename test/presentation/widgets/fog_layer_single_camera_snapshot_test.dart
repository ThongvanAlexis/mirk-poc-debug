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

/// FOG-07 KEYSTONE in Phase 4 — `MapCamera.of(context)` is called EXACTLY
/// ONCE per [FogLayer.build] invocation EVEN with a [WispParticleSystem]
/// injected.
///
/// Mirrors `test/presentation/widgets/fog_layer_camera_snapshot_test.dart`
/// (Plan 03-05); adds the Plan 04-04 `wispParticleSystem` +
/// `wispTransformLogger` constructor args to verify the FOG-07 firewall
/// still holds when wisps are wired.
///
/// A wisp painter that re-read `MapCamera.of(painterContext)` would
/// re-create BUG-014's white-ellipse symptom in the wisp pipeline — which
/// is the failure mode FOG-07 was designed to defend against in Phase 3.
/// This test pins the discipline forward into Phase 4.
void main() {
  testWidgets('FogLayer reads MapCamera.of(context) exactly once per build EVEN WITH WispParticleSystem present (FOG-07 keystone holds in Phase 4)', (tester) async {
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

    expect(readCount, 1, reason: 'FOG-07 (Phase 4): exactly one MapCamera.of(context) call per build with wisps wired.');

    await tester.tap(find.byKey(const Key('rebuild-trigger')));
    await tester.pump();
    expect(readCount, 2, reason: 'FOG-07: each forced rebuild bumps readCount by exactly 1, even with wisps in the mix.');

    await tester.tap(find.byKey(const Key('rebuild-trigger')));
    await tester.pump();
    expect(readCount, 3, reason: 'FOG-07: third rebuild → readCount == 3 (never more, never fewer); wisp render path MUST NOT add reads.');
  });
}
