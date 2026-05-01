// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Counts `MapCamera.of(context)` reads during widget tests by capturing
/// invocations of the `FogLayer.debugOnCameraRead` static seam (Plan 03-05).
///
/// Used by the FOG-07 keystone test to assert the "exactly 1 read per build"
/// architectural invariant — the cure that disambiguates BUG-014's white-
/// ellipse symptom from any future regression.
class CameraAccessCounter {
  /// Live read count. Caller wires `recordRead` to `FogLayer.debugOnCameraRead`
  /// before pumping the widget tree.
  int count = 0;

  /// Increment hook — pass this as the `FogLayer.debugOnCameraRead` callback.
  void recordRead() => count++;
}

/// Pumps a real `FlutterMap` containing [fogLayer] and returns a fresh
/// [CameraAccessCounter]. The caller is responsible for wiring
/// `FogLayer.debugOnCameraRead = counter.recordRead` BEFORE invoking this
/// helper — the counter is returned uninitialised here so tests can decide
/// whether to count from frame 0 or after a manual reset.
///
/// The map's initial centre / zoom default to Melun town centre (Phase 2 +
/// Phase 3 walk theatre); callers can override either parameter.
Future<CameraAccessCounter> pumpFlutterMapWithFogLayer(
  WidgetTester tester, {
  required Widget fogLayer,
  LatLng initialCenter = const LatLng(48.5397, 2.6553),
  double initialZoom = 13,
}) async {
  final counter = CameraAccessCounter();
  await tester.pumpWidget(
    MaterialApp(
      home: FlutterMap(
        options: MapOptions(initialCenter: initialCenter, initialZoom: initialZoom),
        children: <Widget>[fogLayer],
      ),
    ),
  );
  return counter;
}
