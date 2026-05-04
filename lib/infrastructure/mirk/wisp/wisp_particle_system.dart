// Copyright (c) 2026 THONGVAN Alexis
// Licensed under the Good Old Software License v1.0
// See LICENSE file for details

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
///      snapshot (FOG-07 carry-over).
///   2. WISP-02 — kinematic basis is metres / second / metres²; donor's
///      screen-pixel basis was zoom-fragile and never stress-tested at
///      Phase 3.1 zoom range.
///   3. WISP-03 — 5-s warm-up gate (`kMirkPocWispWarmUpSeconds`) suppresses
///      the "every previously-revealed disc explodes on app open" failure
///      mode. Disc IDs ARE recorded during the gate so post-warmup
///      re-calls don't re-trigger.
///   4. WISP-05 — `spawnRatePerSecondAndReset` is a side-effecting accessor
///      consumed by the painter once per [WispTransformLogger] rollup
///      interval. Single source of truth for the spawn rate.
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
/// 2. [advance] integrates every active wisp and decrements life.
///    Dead wisps are removed in-place.
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
  WispParticleSystem({int maxCount = kMirkPocWispMaxCount, int rngSeed = 1337, Stopwatch? wallClock});

  /// Read-only view for tests / debug. Plan 04-03 implements.
  Iterable<WispParticle> get wisps => throw UnimplementedError('Plan 04-03 implements');

  /// Number of currently active wisps. Plan 04-03 implements.
  int get activeCount => throw UnimplementedError('Plan 04-03 implements');

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
  /// new disc IDs; the [discId] is recorded in `_alreadySpawnedDiscIds`
  /// during the gate so a post-warm-up call with the SAME [discId]
  /// is ALSO a no-op (the warm-up gate covers the "every previously-
  /// revealed disc explodes on app open" failure mode without leaving
  /// a follow-up trigger).
  ///
  /// Plan 04-03 implements.
  void spawnAtNewDisc({required String discId, required RevealDisc disc}) => throw UnimplementedError('Plan 04-03 implements');

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
  /// [dt] is clamped at [kMirkPocWispMaxDtSeconds] to bound the
  /// integration step on first paint or after a paused painter resumes
  /// (prevents snap-jumping wisps on a stale Stopwatch).
  ///
  /// Plan 04-03 implements.
  void advance(double dt) => throw UnimplementedError('Plan 04-03 implements');

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
  ///
  /// Plan 04-03 implements.
  double spawnRatePerSecondAndReset({Duration? sinceInterval}) => throw UnimplementedError('Plan 04-03 implements');

  /// Removes all active wisps. Useful when the session ends or the
  /// renderer is disposed. Plan 04-03 implements.
  void clear() => throw UnimplementedError('Plan 04-03 implements');
}
