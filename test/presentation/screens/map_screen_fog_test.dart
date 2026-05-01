// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:mirk_poc_debug/domain/revealed/reveal_disc_repository.dart';
import 'package:mirk_poc_debug/presentation/widgets/fog_layer.dart';

/// MapScreen × Phase 3 integration — GPS fix → discRepository.append,
/// FogLayer mounting after shader load.
///
/// Wave 0 contract: these tests compile against the Plan 03-01 stubs and
/// will GREEN once Plan 03-07 wires the GPS-fix → discRepository.append
/// path AND the shader-load → FogLayer mount path inside MapScreen.
///
/// Test seams:
///   - Reuse the Phase 2 `_CapturingGeolocatorPlatform` pattern (see
///     `test/infrastructure/location/geolocator_service_test.dart`).
///   - Plan 03-07 must expose a constructor-injected FragmentProgram
///     loader so the test does not actually load the real .frag.
void main() {
  testWidgets('MapScreen calls discRepository.append on every GPS fix '
      '[skipped — Plan 03-07 wires MapScreen GPS-fix → discRepository.append (FOG-01) + '
      'shader-load → FogLayer mount]', (tester) async {
    final repo = RevealDiscRepository();
    final emitter = StreamController<Position>();
    // ... pump MapScreen.fromServices with services pointing at emitter.stream + repo ...
    emitter.add(_position(lat: 48.54, lon: 2.66));
    await tester.pump();
    expect(repo.snapshot(), hasLength(1));
    expect(repo.snapshot().first.lat, 48.54);
    await emitter.close();
  }, skip: true);

  testWidgets('FogLayer mounts inside FlutterMap once shader load completes '
      '[skipped — Plan 03-07 wires _fogShader load into MapScreen; FogLayer mounts only when '
      'both _tileProvider AND _fogShader are non-null]', (tester) async {
    // Plan 03-07 wires _fogShader load into MapScreen; FogLayer becomes a child
    // of FlutterMap when both _tileProvider AND _fogShader are non-null.
    // ... pump, await shader load, assert FogLayer is in the tree ...
    expect(find.byType(FogLayer), findsOneWidget);
  }, skip: true);
}

/// Builds a Position with fixed values — only lat/lon vary in these tests.
/// Mirrors the helper in test/presentation/screens/map_screen_gps_test.dart.
Position _position({required double lat, required double lon}) => Position(
  latitude: lat,
  longitude: lon,
  timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
