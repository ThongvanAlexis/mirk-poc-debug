// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:latlong2/latlong.dart';

import 'package:mirk_poc_debug/config/constants.dart';
import 'package:mirk_poc_debug/domain/revealed/reveal_disc.dart';

import 'wisp_particle.dart';

/// CPU-side wisp particle system — Phase 4 BUG-009 (TIER 2) POC port.
///
/// Spawns short-lived particles at the SDF boundary when the user
/// reveals new cells, integrates them via curl-noise advection on
/// the Dart side, and (in Plan 04-04) is rendered via additive blending
/// inside `_FogPainter.paint()` after the fog draw rect, before
/// `canvas.restore()`.
///
/// Reference 1 (earth.nullschool flow physics) + Reference 9 (Foundry
/// VTT animated mist) inspiration. ~200 wisps cap is invisible cost
/// on any 2026 mobile GPU and dense enough that the eye latches onto
/// motion as the user walks.
///
/// ## Phase 4 POC port deviations from donor (MirkFall)
///
///   1. WISP-01 — particle position is [LatLng] not screen-pixel [Offset];
///      projection happens at paint time via the painter's MapCamera
///      snapshot (FOG-07 carry-over). This class deliberately does NOT
///      import `flutter_map` or call `latLngToScreenPoint` — that is a
///      Pitfall 1 / Pitfall 2 firewall.
///   2. WISP-02 — kinematic basis is metres / second / metres²; donor's
///      screen-pixel basis was zoom-fragile and never stress-tested at
///      Phase 3.1 zoom range.
///   3. WISP-03 — 5-s warm-up gate ([kMirkPocWispWarmUpSeconds]) suppresses
///      the "every previously-revealed disc explodes on app open" failure
///      mode. Disc IDs ARE recorded during the gate so post-warmup
///      re-calls with the SAME id don't re-trigger.
///   4. WISP-05 — [spawnRatePerSecondAndReset] is a side-effecting accessor
///      consumed by the painter once per [WispTransformLogger] rollup
///      interval. Single source of truth for the spawn rate.
///   5. The donor's `render(canvas, tint)` method is GONE — projection +
///      drawing live in Plan 04-04's `_FogPainter._renderWisps(canvas,
///      camera)` (the painter holds the MapCamera snapshot; this class
///      stays pure-Dart and shader-agnostic).
///
/// ## Thread safety
///
/// NOT thread-safe. Owned by a single MapScreen lifetime; called from the
/// CustomPainter.paint() pump on the platform UI isolate. No mutexes
/// or concurrent access.
///
/// ## Lifecycle
///
/// 1. [spawnAtNewDisc] is called by the painter (Plan 04-04) once per newly
///    appended `RevealDisc` — N evenly-spaced wisps land along the disc
///    perimeter so the user sees a "puff bursting outward from the new
///    reveal" the moment the GPS fix lands.
/// 2. [advance] (or [advanceFromWallClock] from the painter) integrates
///    every active wisp and decrements life. Dead wisps are removed in-place.
/// 3. The painter draws each active wisp as an additive-blended soft circle
///    (Plan 04-04 — `_renderWisps` after `canvas.drawRect(...shader)`,
///    before `canvas.restore()`).
///
/// All three operations are O(N) over the active count; the cap
/// ([kMirkPocWispMaxCount] = 200) makes worst-case ~50 µs per frame
/// — negligible at 60 fps.
class WispParticleSystem {
  /// Constructs an empty system.
  ///
  /// [maxCount] caps the active particle count (LRU eviction beyond cap;
  /// default [kMirkPocWispMaxCount]). [rngSeed] seeds the deterministic
  /// jitter / speed-factor RNG (default 1337).
  ///
  /// [wallClock] is a TEST SEAM — pass an external `Stopwatch` to control
  /// the warm-up gate from a unit test. Production callers omit it; the
  /// system constructs `Stopwatch()..start()` internally.
  WispParticleSystem({int maxCount = kMirkPocWispMaxCount, int rngSeed = 1337, Stopwatch? wallClock})
    : _maxCount = maxCount,
      _rng = math.Random(rngSeed),
      _wallClock = wallClock ?? (Stopwatch()..start());

  final int _maxCount;
  final math.Random _rng;
  final Stopwatch _wallClock;

  /// Currently alive wisps. `final` because we mutate in place; size
  /// fluctuates as wisps spawn and die.
  final List<WispParticle> _wisps = <WispParticle>[];

  /// Disc IDs already processed by [spawnAtNewDisc]. Recorded BEFORE
  /// the warm-up gate so post-warmup re-calls with the same id are
  /// idempotent (WISP-03 contract).
  final Set<String> _alreadySpawnedDiscIdSet = <String>{};

  /// Counter for [spawnRatePerSecondAndReset]. Reset on each call.
  int _spawnCounterSinceLastRollup = 0;

  /// Wall-clock baseline for [advanceFromWallClock]. 0 means "first call
  /// not yet observed" — first call records the current micros and
  /// returns without integrating.
  int _lastAdvanceMicros = 0;

  /// Read-only view for tests / debug. Iterating during [advance] is
  /// undefined (advance mutates the underlying list); callers must
  /// not interleave.
  Iterable<WispParticle> get wisps => _wisps;

  /// Number of currently active wisps.
  int get activeCount => _wisps.length;

  /// Spawns ~`(2 * pi * disc.radiusMeters) / kMirkPocWispMetersPerWisp`
  /// wisps along the disc perimeter (WISP-02 puff burst).
  ///
  /// Idempotent on [discId] — calling twice with the same ID is a no-op
  /// (the painter forwards the disc lifecycle naively; idempotency is
  /// enforced HERE so the painter does not have to track which discs
  /// have been spawn-processed).
  ///
  /// During the first [kMirkPocWispWarmUpSeconds] of the system's
  /// wall-clock lifetime (WISP-03), this method is a no-op even on
  /// new disc IDs; the [discId] is recorded in `_alreadySpawnedDiscIdSet`
  /// during the gate so a post-warm-up call with the SAME [discId]
  /// is ALSO a no-op (the warm-up gate covers the "every previously-
  /// revealed disc explodes on app open" failure mode without leaving
  /// a follow-up trigger).
  void spawnAtNewDisc({required String discId, required RevealDisc disc}) {
    // Idempotency guard FIRST — short-circuit before any further work.
    if (_alreadySpawnedDiscIdSet.contains(discId)) return;
    _alreadySpawnedDiscIdSet.add(discId);

    // WISP-03 warm-up gate AFTER recording the discId. The disc stays
    // in the already-seen set so post-warmup re-calls hit the
    // idempotency guard above and don't fire either.
    if (_wallClock.elapsedMilliseconds < (kMirkPocWispWarmUpSeconds * _millisecondsPerSecond).round()) {
      return;
    }

    _spawnAlongPerimeter(disc);
  }

  /// Spawns one wisp per perimeter-sample-point along [disc]. Sample
  /// count = `circumferenceMeters / kMirkPocWispMetersPerWisp` rounded —
  /// 25 m radius × 2π / 8 m ≈ 19.6 → 20 wisps.
  void _spawnAlongPerimeter(RevealDisc disc) {
    final radiusMeters = disc.radiusMeters;
    final circumferenceMeters = _twoPi * radiusMeters;
    final sampleCount = (circumferenceMeters / kMirkPocWispMetersPerWisp).round();
    final cosLatAtDisc = math.cos(disc.lat * math.pi / _degreesPerHalfTurn);

    for (var i = 0; i < sampleCount; i++) {
      final theta = (i / sampleCount) * _twoPi;
      // Offset from disc centre in metres, projected to LatLng-degrees.
      final dLatDeg = radiusMeters * math.sin(theta) / kMetersPerDegreeLat;
      final dLonDeg = radiusMeters * math.cos(theta) / (kMetersPerDegreeLat * cosLatAtDisc);
      final spawnLatLng = LatLng(disc.lat + dLatDeg, disc.lon + dLonDeg);
      // Outward unit normal at this perimeter point — wisps stream
      // OUT of the revealed area into the fog.
      final unitDirection = Offset(math.cos(theta), math.sin(theta));
      _spawnAtPosition(position: spawnLatLng, direction: unitDirection, atLatForLonScale: disc.lat);
      _spawnCounterSinceLastRollup += 1;
    }
  }

  /// Spawns one wisp at [position] with initial velocity along
  /// [direction] (unit vector). Adds ±0.5 m position jitter + ±20 %
  /// speed jitter so a multi-particle burst doesn't move in lockstep.
  ///
  /// [atLatForLonScale] is the latitude at which the longitude-degree
  /// scaling factor is computed (cos(lat) shrinks the longitude
  /// degree-per-metre at higher absolute latitudes). Passed in
  /// explicitly rather than read from [position] so the perimeter loop
  /// uses ONE consistent latitude basis for all spawn points along a
  /// single 25 m disc — avoids a sub-millimetre asymmetry that would
  /// be invisible to the user but pollutes the test assertions.
  void _spawnAtPosition({required LatLng position, required Offset direction, required double atLatForLonScale}) {
    // ±0.5 m position jitter — donor's ±2 px translated to a small
    // metre-equivalent fraction of the 25 m disc radius.
    final jitterMetersX = (_rng.nextDouble() - _jitterCentre) * _jitterSpanMeters;
    final jitterMetersY = (_rng.nextDouble() - _jitterCentre) * _jitterSpanMeters;
    final cosLat = math.cos(atLatForLonScale * math.pi / _degreesPerHalfTurn);
    final jitterDLatDeg = jitterMetersY / kMetersPerDegreeLat;
    final jitterDLonDeg = jitterMetersX / (kMetersPerDegreeLat * cosLat);
    final jitteredPosition = LatLng(position.latitude + jitterDLatDeg, position.longitude + jitterDLonDeg);

    // ±20 % speed factor — donor verbatim: 0.8 + nextDouble() × 0.4 ∈ [0.8, 1.2).
    final speedFactor = _speedJitterMin + _rng.nextDouble() * _speedJitterSpan;
    final velocity = Offset(direction.dx * kMirkPocWispDriftMetersPerSecond * speedFactor, direction.dy * kMirkPocWispDriftMetersPerSecond * speedFactor);
    _wisps.add(WispParticle(position: jitteredPosition, velocityMetersPerSecond: velocity, life: kMirkPocWispLifeSeconds, maxLife: kMirkPocWispLifeSeconds));
    _enforceCap();
  }

  /// Removes the OLDEST wisps (lowest remaining life) until the
  /// active count is <= [_maxCount]. LRU semantics — newer particles
  /// always win the budget. Donor pattern (sort by life descending,
  /// removeRange tail).
  void _enforceCap() {
    if (_wisps.length <= _maxCount) return;
    _wisps.sort((a, b) => b.life.compareTo(a.life));
    _wisps.removeRange(_maxCount, _wisps.length);
  }

  /// Production convenience — wraps [advance] with dt computed from
  /// the wall-clock Stopwatch. Used by `_FogPainter._renderWisps`
  /// (Plan 04-04). Tests prefer the underlying [advance] with explicit
  /// dt for determinism.
  ///
  /// First-call guard: if `_lastAdvanceMicros == 0` we just record the
  /// current wall-clock and skip integration (no dt to integrate over).
  /// Subsequent calls: dt = (current - last) / 1e6, clamped to
  /// [0, [kMirkPocWispMaxDtSeconds]] (= 0.1 s) so a paused-then-resumed
  /// painter doesn't snap-integrate over multiple seconds.
  void advanceFromWallClock(Stopwatch wallClock) {
    final currentMicros = wallClock.elapsedMicroseconds;
    if (_lastAdvanceMicros == 0) {
      _lastAdvanceMicros = currentMicros;
      return;
    }
    final dtSeconds = ((currentMicros - _lastAdvanceMicros) / _microsecondsPerSecond).clamp(0.0, kMirkPocWispMaxDtSeconds);
    _lastAdvanceMicros = currentMicros;
    if (dtSeconds > 0.0) {
      advance(dtSeconds);
    }
  }

  /// Integrates the system forward by [dt] seconds (WISP-02).
  ///
  /// Each wisp:
  ///   - applies a per-particle curl-noise force in m/sec² (computed
  ///     in LatLng-degree space via [kMirkPocWispCurlInputScale])
  ///   - integrates velocity and position via Euler step
  ///   - decrements life
  ///
  /// Dead wisps are removed in place. After this call, [activeCount]
  /// reflects the post-step count.
  ///
  /// dt is NOT internally clamped here (the caller is expected to clamp
  /// upstream — the painter via [advanceFromWallClock], tests via the
  /// explicit dt they pass). Pure integration step.
  void advance(double dt) {
    // Iterate in REVERSE so removeAt doesn't shift active indices.
    // Documented exception to CLAUDE.md "ne jamais muter une collection
    // pendant son itération" — single-item removal at N≤200, the
    // collect-then-remove pattern would allocate a List per call.
    for (var i = _wisps.length - 1; i >= 0; i--) {
      final w = _wisps[i];

      // Curl-noise input projection: LatLng → local-tangent-plane-ish
      // 2D basis. Anchoring at Melun centre keeps the noise field
      // deterministic at the same world position regardless of the
      // wisp's individual age. kMirkPocWispCurlInputScale = 50 brings
      // the input into a curl-noise-friendly scale (donor used
      // `position * 0.005` in screen-px basis at zoom 13 where
      // 1 raw px ≈ 9.55 m → 0.005 px⁻¹ ≈ 5.2e-4 m⁻¹; for a degree
      // basis 1° ≈ 111 km so 50 deg⁻¹ ≈ 4.5e-4 m⁻¹ produces
      // visually similar 'organic drift' character).
      final curlInput = Offset(
        (w.position.longitude - kMelunCenterLonForCurlNoise) * kMirkPocWispCurlInputScale,
        (w.position.latitude - kMelunCenterLatForCurlNoise) * kMirkPocWispCurlInputScale,
      );
      final curl = _curlNoise(curlInput);

      // Linear-approximation drag = 1 - dragRate × dt (valid for small dt;
      // donor pattern). Combined with curl-noise force: organic drift.
      final dragFactor = 1.0 - kMirkPocWispDragPerSecond * dt;
      final newVx = w.velocityMetersPerSecond.dx * dragFactor + curl.dx * kMirkPocWispCurlAccelMetersPerSecondSquared * dt;
      final newVy = w.velocityMetersPerSecond.dy * dragFactor + curl.dy * kMirkPocWispCurlAccelMetersPerSecondSquared * dt;
      w.velocityMetersPerSecond = Offset(newVx, newVy);

      // Position integration: velocity (m/s) × dt → metres → LatLng-deg.
      final cosLat = math.cos(w.position.latitude * math.pi / _degreesPerHalfTurn);
      final dLatDeg = (w.velocityMetersPerSecond.dy * dt) / kMetersPerDegreeLat;
      final dLonDeg = (w.velocityMetersPerSecond.dx * dt) / (kMetersPerDegreeLat * cosLat);
      w.position = LatLng(w.position.latitude + dLatDeg, w.position.longitude + dLonDeg);

      w.life -= dt;
      if (w.isDead) {
        _wisps.removeAt(i);
      }
    }
  }

  /// Returns spawns-since-last-call divided by [sinceInterval];
  /// resets the counter (WISP-05).
  ///
  /// Called by the painter once per [WispTransformLogger] rollup interval.
  /// Side-effecting reset is intentional — single source of truth for the
  /// rate (the painter forwards the value into the rollup record without
  /// owning the counter).
  ///
  /// [sinceInterval] defaults to 1 second
  /// ([kPocWispTransformLogRollupSeconds]).
  double spawnRatePerSecondAndReset({Duration? sinceInterval}) {
    final intervalSeconds = (sinceInterval ?? const Duration(seconds: kPocWispTransformLogRollupSeconds)).inMilliseconds / _millisecondsPerSecond;
    final rate = _spawnCounterSinceLastRollup / intervalSeconds;
    _spawnCounterSinceLastRollup = 0;
    return rate;
  }

  /// Removes all active wisps and resets idempotency / counter state.
  /// Useful when the session ends or the renderer is disposed.
  void clear() {
    _wisps.clear();
    _alreadySpawnedDiscIdSet.clear();
    _spawnCounterSinceLastRollup = 0;
  }

  // ─── Curl-noise helpers — DONOR VERBATIM ────────────────────────────
  // Lines 181-216 of MirkFall's wisp_particle_system.dart. Pure-math
  // hash-based scalar noise + central-differences curl. No behavioural
  // change — visually consistent with the shader's curl2() so wisps
  // and the production fog drift on the same field character.

  /// Cheap deterministic 2D curl-noise vector field (hash + central
  /// differences). Same algorithm as the .frag's curl2() — visually
  /// consistent with the shader's curl advection.
  Offset _curlNoise(Offset p) {
    const e = _curlNoiseEpsilon;
    final n1 = _scalarNoise(p + const Offset(0, e));
    final n2 = _scalarNoise(p + const Offset(0, -e));
    final n3 = _scalarNoise(p + const Offset(e, 0));
    final n4 = _scalarNoise(p + const Offset(-e, 0));
    return Offset(n1 - n2, -(n3 - n4)) / (2.0 * e);
  }

  /// Cheap hash-based scalar noise. Not strictly simplex — uses a
  /// trilinear-blended hash3 in the same style as the shader's
  /// noise2(). Performance > realism: this drives wisp drift, the
  /// user perceives the motion not the noise function.
  double _scalarNoise(Offset p) {
    final ix = p.dx.floor();
    final iy = p.dy.floor();
    final fx = p.dx - ix;
    final fy = p.dy - iy;
    final ux = fx * fx * (3.0 - 2.0 * fx);
    final uy = fy * fy * (3.0 - 2.0 * fy);
    final h00 = _hash2(ix, iy);
    final h10 = _hash2(ix + 1, iy);
    final h01 = _hash2(ix, iy + 1);
    final h11 = _hash2(ix + 1, iy + 1);
    final n0 = h00 * (1.0 - ux) + h10 * ux;
    final n1 = h01 * (1.0 - ux) + h11 * ux;
    return n0 * (1.0 - uy) + n1 * uy;
  }

  /// Cheap 2D-int hash → [0, 1).
  double _hash2(int x, int y) {
    var h = x * _hash2PrimeX + y * _hash2PrimeY;
    h = (h ^ (h >> _hash2ShiftBits)) * _hash2MultiplierC;
    h = h & _hash2Mask31;
    return (h % _hash2Modulo) / _hash2Modulo.toDouble();
  }
}

// ─── File-private numeric constants ────────────────────────────────────
// Hoisted out of the kinematic / curl-noise math so the magic numbers
// don't appear inline (CLAUDE.md "Aucun number magique"). Donor names
// kept where applicable for grep-correlation against MirkFall.

const double _twoPi = 2.0 * math.pi;
const double _degreesPerHalfTurn = 180.0;
const double _millisecondsPerSecond = 1000.0;
const double _microsecondsPerSecond = 1000000.0;

/// ±0.5 m spawn jitter — donor's ±2 px translated to a small metre
/// fraction of the 25 m disc radius. Centre-offset (0.5) shifts the
/// uniform [0, 1) random into [-0.5, 0.5).
const double _jitterCentre = 0.5;
const double _jitterSpanMeters = 1.0;

/// Speed jitter span — donor's `0.8 + rand × 0.4` ∈ [0.8, 1.2). Min
/// + span pair preserves the donor character verbatim.
const double _speedJitterMin = 0.8;
const double _speedJitterSpan = 0.4;

/// Curl-noise central-differences epsilon. Donor verbatim (0.05).
const double _curlNoiseEpsilon = 0.05;

/// Hash-2 primes + bit-mixing constants. Donor verbatim — visual
/// character of the curl field depends on these specific values.
const int _hash2PrimeX = 374761393;
const int _hash2PrimeY = 668265263;
const int _hash2MultiplierC = 1274126177;
const int _hash2ShiftBits = 13;
const int _hash2Mask31 = 0x7FFFFFFF;
const int _hash2Modulo = 10000;
