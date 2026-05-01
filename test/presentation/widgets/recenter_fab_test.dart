// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/presentation/widgets/recenter_fab.dart';

/// Simple Position constructor for tests — supplies sane defaults for every
/// required Geolocator field so the test only spells out latitude/longitude.
Position _pos(double lat, double lon) => Position(
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

/// Records every `move` call so tests can inspect the animation trajectory
/// (intermediate frames and final landing point) without rendering a real
/// FlutterMap. Only the methods exercised by RecenterFab are implemented;
/// the others throw to fail loudly if Plan 02-04 starts using them.
class _RecordingMapController implements MapController {
  final List<({LatLng center, double zoom})> moveCalls = <({LatLng center, double zoom})>[];
  final StreamController<MapEvent> _events = StreamController<MapEvent>.broadcast();

  @override
  bool move(LatLng center, double zoom, {Offset offset = Offset.zero, String? id}) {
    moveCalls.add((center: center, zoom: zoom));
    return true;
  }

  @override
  Stream<MapEvent> get mapEventStream => _events.stream;

  @override
  bool rotate(double degree, {String? id}) => throw UnimplementedError('Test fake: rotate not used by RecenterFab');

  // MoveAndRotateResult is a non-exported typedef in flutter_map 7.0.2 — see
  // lib/src/misc/move_and_rotate_result.dart. Spelling it as the structural
  // record type satisfies the abstract MapController interface without
  // depending on a private import.
  @override
  ({bool moveSuccess, bool rotateSuccess}) rotateAroundPoint(double degree, {Point<double>? point, Offset? offset, String? id}) =>
      throw UnimplementedError('Test fake: rotateAroundPoint not used by RecenterFab');

  @override
  ({bool moveSuccess, bool rotateSuccess}) moveAndRotate(LatLng center, double zoom, double degree, {String? id}) =>
      throw UnimplementedError('Test fake: moveAndRotate not used by RecenterFab');

  @override
  bool fitCamera(CameraFit cameraFit) => throw UnimplementedError('Test fake: fitCamera not used by RecenterFab');

  @override
  MapCamera get camera => throw UnimplementedError('Test fake: camera getter not exercised in these tests');

  @override
  void dispose() {
    _events.close();
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('RecenterFab', () {
    testWidgets('LOC-04: animates to lastFix at zoom 15 over kPocRecenterAnimationMs', (tester) async {
      final controller = _RecordingMapController();
      final fix = _pos(48.5397, 2.6553);

      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: fix)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      // Pump one animation frame at a time across the full duration so the
      // recorder captures every intermediate move.
      const totalMs = kPocRecenterAnimationMs;
      const stepMs = 16; // ~60 Hz; fine for trajectory sampling.
      for (var elapsed = 0; elapsed <= totalMs; elapsed += stepMs) {
        await tester.pump(const Duration(milliseconds: stepMs));
      }
      await tester.pumpAndSettle();

      expect(controller.moveCalls, isNotEmpty, reason: 'Tap MUST drive at least one MapController.move during the animation.');
      expect(controller.moveCalls.length, greaterThan(1), reason: 'A 500 ms animation MUST emit several intermediate moves, not just the final landing.');

      final last = controller.moveCalls.last;
      expect(last.center.latitude, closeTo(fix.latitude, 1e-6), reason: 'Final move MUST land on lastFix.latitude.');
      expect(last.center.longitude, closeTo(fix.longitude, 1e-6), reason: 'Final move MUST land on lastFix.longitude.');
      expect(last.zoom, equals(kPocRecenterZoom), reason: 'Final move MUST land at kPocRecenterZoom (15).');

      controller.dispose();
    });

    testWidgets('LOC-05: FAB is disabled when lastFix is null', (tester) async {
      final controller = _RecordingMapController();

      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: null)));
      await tester.pumpAndSettle();

      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.onPressed, isNull, reason: 'LOC-05 mandates a disabled FAB while no fix has been received.');

      controller.dispose();
    });

    testWidgets('repeat tap during animation cancels prior tween and targets the newer fix', (tester) async {
      final controller = _RecordingMapController();
      final firstFix = _pos(48.5397, 2.6553);
      final secondFix = _pos(48.5500, 2.6700);

      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: firstFix)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Swap in a newer fix (e.g. GPS produced a fresh reading mid-animation),
      // then tap again. Plan 02-04 contract: prior AnimationController is
      // disposed, a new one starts, the final landing targets the newer fix.
      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: secondFix)));
      await tester.tap(find.byType(FloatingActionButton));
      for (var elapsed = 0; elapsed <= kPocRecenterAnimationMs; elapsed += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      final last = controller.moveCalls.last;
      expect(last.center.latitude, closeTo(secondFix.latitude, 1e-6), reason: 'Repeat-tap MUST retarget the newer fix, not finish the old animation.');
      expect(last.center.longitude, closeTo(secondFix.longitude, 1e-6));

      controller.dispose();
    });
  });
}
