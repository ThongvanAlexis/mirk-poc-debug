// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';

import '../../config/constants.dart';

/// Synthetic GPS emitter for indoor wisp / SDF / fog testing.
///
/// Replaces the live `Geolocator.getPositionStream` source with a Timer-driven
/// stream of synthetic [Position] events. Used by the AppBar walk-simulator
/// control to validate Phase 4 behaviour (wisp spawn, SDF reveal growth,
/// FOG-19 zoom anchoring during sustained pan) without leaving the desk.
///
/// Lifecycle: [running] is a [ValueNotifier] so MapScreen can swap its
/// position subscription in/out without prop-drilling state. AppBar starts /
/// stops via [start] / [stop]; MapScreen listens to [running] and re-targets
/// its subscription accordingly.
///
/// Singleton because the simulator's state is shared between the AppBar
/// control (cross-screen, lives in [buildPocAppBar]) and MapScreen's position
/// subscription (one per screen instance). [stream] is broadcast — multiple
/// listeners can attach without losing events.
class WalkSimulator {
  WalkSimulator._();

  /// Process-wide singleton. Mirrors the [debugSpiralEnabled] global pattern
  /// for cross-screen debug toggles.
  static final WalkSimulator instance = WalkSimulator._();

  static final Logger _log = Logger('infrastructure.location.walk_simulator');

  final StreamController<Position> _controller = StreamController<Position>.broadcast();
  Timer? _timer;

  double _lat = kPocInitialCameraLat;
  double _lon = kPocInitialCameraLon;
  double _bearingDeg = 0.0;
  double _speedMps = kPocWalkSimulatorDefaultSpeedMps;

  /// Notifies listeners when [start] / [stop] flip the simulator state.
  /// MapScreen listens here to swap its position-stream subscription.
  final ValueNotifier<bool> running = ValueNotifier<bool>(false);

  /// Broadcast stream of synthetic [Position] events. Emits the starting
  /// position immediately on [start], then every [kPocWalkSimulatorTickMs]
  /// while running. Stops emitting on [stop].
  Stream<Position> get stream => _controller.stream;

  double get lat => _lat;
  double get lon => _lon;
  double get bearingDeg => _bearingDeg;
  double get speedMps => _speedMps;

  /// Starts emitting synthetic fixes. If already running, restarts with the
  /// updated parameters. Any of [lat] / [lon] / [bearingDeg] / [speedMps] can
  /// be omitted to keep the prior value (or the constructor default).
  ///
  /// Emits the starting position immediately so the auto-recenter path fires
  /// without waiting for a full tick.
  void start({double? lat, double? lon, double? bearingDeg, double? speedMps}) {
    _timer?.cancel();
    if (lat != null) _lat = lat;
    if (lon != null) _lon = lon;
    if (bearingDeg != null) _bearingDeg = bearingDeg;
    if (speedMps != null) _speedMps = speedMps;
    _emit();
    _timer = Timer.periodic(const Duration(milliseconds: kPocWalkSimulatorTickMs), (_) {
      _advance();
      _emit();
    });
    if (!running.value) {
      running.value = true;
    }
    _log.info('start: lat=$_lat lon=$_lon bearingDeg=$_bearingDeg speedMps=$_speedMps');
  }

  /// Stops the timer and flips [running] to false. Safe to call when already
  /// stopped (no-op).
  void stop() {
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    if (running.value) {
      running.value = false;
    }
    _log.info('stop');
  }

  /// Updates the bearing without restarting the timer. Takes effect on the
  /// next tick.
  void setBearing(double deg) {
    _bearingDeg = deg;
    _log.info('setBearing: $deg');
  }

  /// Updates the speed without restarting the timer. Takes effect on the
  /// next tick.
  void setSpeed(double mps) {
    _speedMps = mps;
    _log.info('setSpeed: $mps');
  }

  void _advance() {
    final tickSeconds = kPocWalkSimulatorTickMs / 1000.0;
    final distMeters = _speedMps * tickSeconds;
    final bearingRad = _bearingDeg * math.pi / 180.0;
    final dxMeters = distMeters * math.sin(bearingRad);
    final dyMeters = distMeters * math.cos(bearingRad);
    final cosLat = math.cos(_lat * math.pi / 180.0);
    _lat += dyMeters / kMetersPerDegreeLat;
    _lon += dxMeters / (kMetersPerDegreeLat * cosLat);
  }

  void _emit() {
    _controller.add(
      Position(
        latitude: _lat,
        longitude: _lon,
        timestamp: DateTime.now().toUtc(),
        accuracy: 5.0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: _bearingDeg,
        headingAccuracy: 0,
        speed: _speedMps,
        speedAccuracy: 0,
      ),
    );
  }
}
