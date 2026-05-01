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
import 'package:mirk_poc_debug/l10n/app_localizations.dart';
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
/// the others throw to fail loudly if the implementation starts using them.
class _RecordingMapController implements MapController {
  // Initial camera state; the 'tween follows easeInOut curve' test relies on
  // delta = (49, 3) - (48, 2) = (+1, +1) so a midpoint sample = (48.5, 2.5).
  static const LatLng _initialCenter = LatLng(48.0, 2.0);
  static const double _initialZoom = 13;

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

  /// Returns a snapshot reflecting either the last [move] call or the initial
  /// center/zoom if no [move] has happened yet. RecenterFab reads this on tap
  /// to capture the "from" state of its tween.
  @override
  MapCamera get camera {
    final LatLng center = moveCalls.isEmpty ? _initialCenter : moveCalls.last.center;
    final double zoom = moveCalls.isEmpty ? _initialZoom : moveCalls.last.zoom;
    return MapCamera(crs: const Epsg3857(), center: center, zoom: zoom, rotation: 0, nonRotatedSize: MapCamera.kImpossibleSize);
  }

  @override
  void dispose() {
    _events.close();
  }
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  group('RecenterFab', () {
    testWidgets('animates to lastFix at z15 over 500ms', (tester) async {
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

      expect(
        controller.moveCalls.length,
        greaterThanOrEqualTo(5),
        reason: 'A 500 ms animation MUST emit several intermediate moves; >=5 confirms a real per-frame tween, not a single endpoint move.',
      );

      final last = controller.moveCalls.last;
      expect(last.center.latitude, closeTo(fix.latitude, 1e-6), reason: 'Final move MUST land on lastFix.latitude.');
      expect(last.center.longitude, closeTo(fix.longitude, 1e-6), reason: 'Final move MUST land on lastFix.longitude.');
      expect(last.zoom, closeTo(kPocRecenterZoom, 1e-6), reason: 'Final move MUST land at kPocRecenterZoom (15).');

      controller.dispose();
    });

    testWidgets('disabled when no fix', (tester) async {
      final controller = _RecordingMapController();

      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: null)));
      await tester.pumpAndSettle();

      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.onPressed, isNull, reason: 'LOC-05 mandates a disabled FAB while no fix has been received.');

      controller.dispose();
    });

    testWidgets('repeat tap during animation', (tester) async {
      final controller = _RecordingMapController();
      final firstFix = _pos(48.5397, 2.6553);
      final secondFix = _pos(48.5500, 2.6700);

      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: firstFix)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 200));

      // Swap in a newer fix (e.g. GPS produced a fresh reading mid-animation),
      // then tap again. Contract: prior AnimationController is disposed, a
      // new one starts, the final landing targets the newer fix.
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

    testWidgets('tween follows easeInOut curve', (tester) async {
      final controller = _RecordingMapController();
      final fix = _pos(49.0, 3.0); // delta = +1° lat, +1° lon from initial (48,2)

      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: fix)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      // Pump exactly half the animation (250 ms of 500 ms). easeInOut at t=0.5
      // is exactly 0.5, so latitude should be ~48.5 (midway).
      const halfMs = kPocRecenterAnimationMs ~/ 2;
      const stepMs = 16;
      for (var elapsed = 0; elapsed < halfMs; elapsed += stepMs) {
        await tester.pump(const Duration(milliseconds: stepMs));
      }

      // Sample the move call closest to t=0.5. easeInOut(0.5) = 0.5, so lat
      // should be 48.5 (start 48 + 0.5 * delta 1.0). ±0.1 generous tolerance.
      expect(controller.moveCalls, isNotEmpty);
      final lastBeforeHalf = controller.moveCalls.last;
      expect(lastBeforeHalf.center.latitude, inInclusiveRange(48.4, 48.6), reason: 'easeInOut at t≈0.5 should land near midpoint (48.5 ±0.1).');

      // Drain to settle so the test framework doesn't see an active timer.
      for (var elapsed = halfMs; elapsed <= kPocRecenterAnimationMs; elapsed += stepMs) {
        await tester.pump(const Duration(milliseconds: stepMs));
      }
      await tester.pumpAndSettle();

      controller.dispose();
    });

    testWidgets('first tap immediately moves the camera', (tester) async {
      final controller = _RecordingMapController();
      final fix = _pos(48.5397, 2.6553);

      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: fix)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      // One frame after tap: the AnimationController.forward + listener should
      // have emitted at least one move.
      expect(
        controller.moveCalls,
        isNotEmpty,
        reason: 'First pump after tap MUST yield at least one move; the tween listener fires on every frame including frame 0.',
      );

      // Drain to settle.
      for (var elapsed = 0; elapsed <= kPocRecenterAnimationMs; elapsed += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      controller.dispose();
    });

    testWidgets('tooltip is localized', (tester) async {
      final controller = _RecordingMapController();
      final fix = _pos(48.5397, 2.6553);

      await tester.pumpWidget(_wrap(RecenterFab(mapController: controller, lastFix: fix)));
      await tester.pumpAndSettle();

      final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fab.tooltip, equals('Recenter on my position'), reason: 'Tooltip MUST come from AppLocalizations.recenterTooltip (en).');

      controller.dispose();
    });
  });
}
