---
phase: 04-wisp-particles
plan: 03
subsystem: wisp-kinematics
tags: [wisp, latlng, m-per-second, curl-noise, lru, warmup-gate, advanceFromWallClock, plan-04-04-painter-contract]
dependency-graph:
  requires:
    - phase: 04-wisp-particles plan 01
      provides: "WispParticle + WispParticleSystem stubs (UnimplementedError) + RED test scaffolds + 13 kMirkPocWisp* constants + kMelunCenterLat/LonForCurlNoise + kMirkPocWispCurlInputScale + kMirkPocWispMaxDtSeconds"
  provides:
    - "lib/infrastructure/mirk/wisp/wisp_particle.dart — Full WispParticle (LatLng position + Offset velocityMetersPerSecond + life + maxLife + isDead + age) — 70 LOC"
    - "lib/infrastructure/mirk/wisp/wisp_particle_system.dart — Full WispParticleSystem (spawnAtNewDisc + advance + advanceFromWallClock + spawnRatePerSecondAndReset + clear + 200-cap LRU + WISP-03 warmup gate) — 389 LOC"
    - "WispParticleSystem.advanceFromWallClock(stopwatch) — Plan 04-04 painter contract (first-call no-op + dt clamp at kMirkPocWispMaxDtSeconds = 0.1 s)"
    - "9 wisp tests GREEN (3 particle + 6 system, including advanceFromWallClock dt-clamp scenario)"
  affects:
    - "Plan 04-04 (FogLayer integration) — WispParticleSystem ready for _FogPainter constructor injection + MapScreen wiring; WispTransformLogger.recordPaint signature compatible (lat/lon bounds extracted via system.wisps map)"
    - "Plan 04-05 (UAT walk validation) — WISP-01..03 mechanically satisfied at unit-test level; walk-time validation at Plan 04-05"
tech-stack:
  added: []
  patterns:
    - "Pure-Dart kinematic system (zero flutter_map / latLngToScreenPoint) — Pitfall 1 / Pitfall 2 firewall"
    - "_FakeStopwatch test seam (elapsedMilliseconds + elapsedMicroseconds + advance helper) — avoids Future.delayed in WISP-03 + advanceFromWallClock tests; suite runs in < 1 s"
    - "Reverse-iteration removeAt pattern — documented exception to CLAUDE.md collection-mutation rule (single-item removal at N≤200)"
    - "Idempotency-before-warmup-gate pattern — discId recorded BEFORE returning during warmup so post-warmup re-call hits idempotency guard (no delayed puff)"
    - "advanceFromWallClock dt-clamp pattern — first-call records baseline + no-ops; subsequent calls integrate dt clamped to kMirkPocWispMaxDtSeconds"
key-files:
  created: []
  modified:
    - "lib/infrastructure/mirk/wisp/wisp_particle.dart (Wave 0 stub flipped to GREEN — 65 LOC stub → 70 LOC impl)"
    - "lib/infrastructure/mirk/wisp/wisp_particle_system.dart (Wave 0 stub flipped to GREEN — 137 LOC stub → 389 LOC impl)"
key-decisions:
  - "Magic-number hoisting: 11 file-private const declarations (_twoPi, _degreesPerHalfTurn, _millisecondsPerSecond, _microsecondsPerSecond, _jitterCentre, _jitterSpanMeters, _speedJitterMin, _speedJitterSpan, _curlNoiseEpsilon, _hash2*) at the bottom of wisp_particle_system.dart to satisfy CLAUDE.md 'Aucun number magique'. Donor inlined the same numbers; this port complies with project rules without changing behaviour."
  - "atLatForLonScale parameter on _spawnAtPosition: passes disc.lat through from the perimeter loop rather than reading position.latitude inside _spawnAtPosition. Avoids a sub-millimetre asymmetry (each perimeter point's longitude scaling factor would otherwise vary by ±0.5 m × cos derivative). Documented in the param's docstring."
  - "advanceFromWallClock semantic: first-call sets _lastAdvanceMicros and returns no-op; this matches the painter's per-paint loop (paint #1 has no prior dt to integrate)."
  - "dt clamp lives in advanceFromWallClock NOT advance(dt): test code calls advance(dt) directly with explicit dt and expects pure integration; clamping inside advance would change the donor's verbatim semantics. Clamp belongs at the boundary."
  - "Curl-noise input projection: (longitude - kMelunCenterLon) × kMirkPocWispCurlInputScale + (latitude - kMelunCenterLat) × kMirkPocWispCurlInputScale. Plan-spec'd anchor (Melun centre) gives a deterministic noise field at the same world position regardless of wisp age; scale = 50 deg⁻¹ is in the visual-character range of the donor's `position * 0.005` in screen-px basis."
patterns-established:
  - "Pattern: Wave 0 stub → Wave 1 GREEN flip without test edits — RED tests in Wave 0 describe GREEN behaviour exactly (Plan 03.1-12 Task 1 retrospective Rule 3); production impl flips them GREEN with zero test changes (modulo orthogonal Plan 04-02 auto-fix for advanceFromWallClock scenario, see Deviations)"
  - "Pattern: Test-only Stopwatch fake — implements Stopwatch via dart's `implements` keyword, exposes only elapsedMilliseconds + elapsedMicroseconds + advance() helper, throws via noSuchMethod on any other method (production-code-can't-cheat invariant)"
requirements-completed: [WISP-01, WISP-02, WISP-03]
metrics:
  duration: 7 min
  tasks: 1
  files: 2 modified
  completed: 2026-05-04
---

# Phase 4 Plan 03: Wisp Particle System Implementation Summary

**WispParticleSystem GREEN flip — 200-cap LRU curl-noise particle integrator in pure Dart with LatLng position + m/s velocity + WISP-03 warmup gate + advanceFromWallClock painter contract; 9 tests GREEN, ZERO flutter_map dependencies.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-04T22:11:09Z
- **Completed:** 2026-05-04T22:18:07Z
- **Tasks:** 1 (TDD: RED-extend already in place from Plan 04-02 auto-fix; GREEN production flip)
- **Files modified:** 2 (production only — test extension already committed via Plan 04-02 e8d2037)

## Accomplishments

- **WispParticle** (70 LOC) — Mutable struct with `LatLng position` + `Offset velocityMetersPerSecond` + `life`/`maxLife` + `isDead` + `age` getters. Two field-name deviations from MirkFall donor (Offset→LatLng + velocity→velocityMetersPerSecond) lock the WISP-01 dimensional discipline at the type level.

- **WispParticleSystem** (389 LOC) — Full curl-noise + drag + Euler kinematic integrator:
  - **Public API:** `wisps` / `activeCount` getters; `spawnAtNewDisc(discId, disc)`; `advance(dt)`; `advanceFromWallClock(stopwatch)`; `spawnRatePerSecondAndReset({sinceInterval})`; `clear()` (7 surfaces)
  - **Spawn loop:** 25 m disc × 2π / 8 m ≈ 19.6 → 20 wisps along perimeter; ±0.5 m position jitter + ±20 % speed jitter (donor character preserved); idempotency-first then WISP-03 warmup gate (discId recorded before gate so post-warmup re-call hits idempotency)
  - **Integrator:** reverse-iteration `removeAt`; world-anchored curl-noise input projection (Melun centre + `kMirkPocWispCurlInputScale = 50` deg⁻¹); linear-approximation drag (`1 - 0.30 × dt`); m/s × dt → metres → LatLng-deg position update with cos(lat) longitude scaling
  - **Painter contract:** `advanceFromWallClock` first call records `_lastAdvanceMicros` + no-ops; subsequent calls integrate `dt = (current - last) / 1e6` clamped to `kMirkPocWispMaxDtSeconds = 0.1 s` so a stale-stopwatch resume doesn't snap-jump 5 seconds of integration in one step
  - **LRU eviction:** sort by life descending + `removeRange(_maxCount, _wisps.length)` — donor pattern verbatim
  - **Curl-noise helpers** (`_curlNoise` + `_scalarNoise` + `_hash2`): donor verbatim. Visual character of the field matches the production fog shader's `curl2()` function so wisps and shader fog drift on the same noise seed family.

- **9 wisp tests GREEN** (3 particle + 6 system): LatLng typing, life decay, age curve, perimeter spawn distribution (latitude span), idempotency, LRU 5-cap with 80 spawns, warmup gate + post-warmup re-call no-op + fresh-discId post-warmup spawn, advance(dt) integrates with sign-correct latitude delta, `advanceFromWallClock` first-call no-op + dt-clamp at 0.1 s on stale stopwatch.

- **Pitfall 1 / Pitfall 2 firewall confirmed:** `lib/infrastructure/mirk/wisp/` contains ZERO calls to `flutter_map` or `latLngToScreenPoint`. Only docstring REFERENCES point at Plan 04-04's painter contract — projection happens at paint time, not in the integrator.

## Task Commits

Plan-04-03 work split across two commits (one in this execution + one piggybacking on Plan 04-02's auto-fix):

1. **Plan 04-02 auto-fix (test extension):** `e8d2037` — `feat(04-02): implement WispTransformLogger mirroring FogTransformLogger (WISP-05)`
   - The Plan 04-02 executor extended `wisp_particle_system_test.dart` with the 6th test (`advanceFromWallClock` dt-clamp + `_FakeStopwatch` fixture) AND tightened the existing 5 RED scaffolds (perimeter span check, LRU survivor check, post-warmup re-call check) as a Rule 3 / Rule 1 auto-fix during its own execution. The `+252 / -100` test diff in the 04-02 commit is THIS plan's test extension, applied early.
   - Net effect: when this plan started executing, the test suite was ALREADY in the RED state Plan 04-03 needed (advanceFromWallClock test compile-fails on the stub for the missing method). My idempotent re-Write of the same content was a no-op.

2. **Production GREEN flip (THIS plan's commit):** `8ad721b` — `feat(04-03): WispParticle (LatLng) + WispParticleSystem (m/s, warmup gate, LRU, advanceFromWallClock) — WISP-01..03`

## Files Created/Modified

- `lib/infrastructure/mirk/wisp/wisp_particle.dart` — Wave 0 stub (65 LOC + UnimplementedError on isDead/age) flipped to full impl (70 LOC). LatLng position + Offset velocityMetersPerSecond + isDead + age.
- `lib/infrastructure/mirk/wisp/wisp_particle_system.dart` — Wave 0 stub (137 LOC + UnimplementedError on every method) flipped to full impl (389 LOC). Spawn loop + reverse-iter advance + curl-noise + LRU + idempotency + warmup gate + advanceFromWallClock + 11 file-private const declarations.
- `test/infrastructure/mirk/wisp/wisp_particle_system_test.dart` — extended via Plan 04-02 auto-fix (commit `e8d2037`); my Write idempotent against committed content. 6 GREEN tests + `_FakeStopwatch` fixture.

## Decisions Made

- **Magic-number hoisting strategy:** 11 file-private const declarations at file bottom of `wisp_particle_system.dart` rather than inline (donor inlined them). CLAUDE.md "Aucun number magique" overrides donor pattern; semantics identical.
- **`atLatForLonScale` parameter on `_spawnAtPosition`:** passes `disc.lat` from the perimeter loop rather than reading `position.latitude` after jitter. Eliminates a sub-millimetre cos(lat) asymmetry across the 20 perimeter points; documented in the param's docstring.
- **dt-clamp lives in `advanceFromWallClock`, NOT in `advance(dt)`:** tests call `advance(dt)` directly with explicit dt and expect pure integration. Clamping inside `advance` would change donor semantics. The clamp belongs at the production boundary (the painter), not the math primitive.
- **Curl-noise input projection scale:** `kMirkPocWispCurlInputScale = 50` deg⁻¹ matches the donor's screen-px-basis visual character (donor: `0.005 px⁻¹ × 9.55 m/raw-px ≈ 5.2e-4 m⁻¹`; ours at zoom 13: `50 deg⁻¹ × 1° / 111 km ≈ 4.5e-4 m⁻¹`). Walk-time calibration in Plan 04-05 if the visual character drifts.
- **Reverse-iteration removeAt** retained from donor (instead of collect-then-remove) — single-item removal at N≤200 makes the documented CLAUDE.md exception preferable to a per-call List allocation. Comment hoisted into the loop.

## Deviations from Plan

### Auto-fixed Issues

**None — plan executed exactly as written for the production code.**

The test file's content was already at the plan-spec'd state when this plan started executing — Plan 04-02's executor had already extended the test file as a Rule 3 / Rule 1 auto-fix during its own work (commit `e8d2037`'s `+252 / -100` test diff). My Write to the test file was idempotent against the committed content; no additional edits required. This is documented above under "Task Commits #1" — Plan 04-02 carried the test extension across the parallel-Wave-1 boundary, which is the intended behaviour of the deviation rules (Rule 3: blocking issue auto-fix when the parallel plan needs the test seam in place).

### Auth Gates Encountered

None.

## Issues Encountered

- **Initial RED-baseline check confirmed compile-fail on `advanceFromWallClock`:** when I first ran `flutter test` against the existing test file (post-04-02), the system test compile-failed with `The method 'advanceFromWallClock' isn't defined`. This is the textbook RED state Plan 04-03 needed — I immediately wrote the production impl, which flipped the suite GREEN.
- **`dart format --set-exit-if-changed` reformatted `wisp_particle_system.dart`:** minor whitespace adjustment after my initial Write. Re-applied the formatted version automatically; no behavioural change.

## User Setup Required

None — no external service configuration required. Pure-Dart unit-testable code.

## Next Phase Readiness

**Plan 04-04 unblocked.** The WispParticleSystem surface is exactly the shape Plan 04-04's `_FogPainter` constructor needs:

- **Constructor:** `WispParticleSystem({maxCount, rngSeed, wallClock})` — production wires `MapScreenServices.wispParticleSystem = WispParticleSystem();`
- **Painter wiring:** Plan 04-04 receives the system as a constructor arg on `_FogPainter`, calls `system.advanceFromWallClock(painterStopwatch)` at the top of paint(), then `system.spawnAtNewDisc(discId, disc)` per newly-emerged disc, then iterates `system.wisps` for the additive-blend draw using `camera.latLngToScreenPoint(w.position)` (the projection that DELIBERATELY does NOT live in this class — Pitfall 1 firewall).
- **WispTransformLogger compatibility:** Plan 04-02's `WispTransformLogger.recordPaint(activeCount, latBounds, lonBounds, screenXBounds, screenYBounds, spawnRatePerSecond)` consumes `system.wisps.map((w) => w.position.latitude)` etc. directly. The bounds extraction is O(N≤200) per paint — negligible cost.

**Plan 04-05 (UAT walk validation) ready** for the wisp behaviour pass once Plan 04-04 lands the painter integration.

## Self-Check: PASSED

Files modified (verified on disk):
- FOUND: `lib/infrastructure/mirk/wisp/wisp_particle.dart` (70 LOC, isDead + age implemented)
- FOUND: `lib/infrastructure/mirk/wisp/wisp_particle_system.dart` (389 LOC, all 7 public methods implemented)
- FOUND: `test/infrastructure/mirk/wisp/wisp_particle_system_test.dart` (280 LOC, 6 GREEN tests + `_FakeStopwatch`)
- FOUND: `test/infrastructure/mirk/wisp/wisp_particle_test.dart` (69 LOC, 3 GREEN tests)

Commits (verified via `git log`):
- FOUND: `8ad721b` — feat(04-03): WispParticle (LatLng) + WispParticleSystem (m/s, warmup gate, LRU, advanceFromWallClock) — WISP-01..03
- FOUND: `e8d2037` — feat(04-02): implement WispTransformLogger (carries this plan's test extension as Rule 3 auto-fix)

Verifications run:
- `flutter test test/infrastructure/mirk/wisp/wisp_particle_test.dart test/infrastructure/mirk/wisp/wisp_particle_system_test.dart`: **9 passed in < 1 s.**
- `flutter test`: **202 passed + 6 skipped** (no regressions vs the 200-passed post-04-02 baseline; +2 reflects the 9-vs-7 wisp-test delta vs the previous 04-02 baseline).
- `flutter analyze`: 0 issues across the workspace.
- `dart format --line-length 160 --set-exit-if-changed lib/infrastructure/mirk/wisp/ test/infrastructure/mirk/wisp/`: 0 changes (idempotent after the post-Write reformat).
- `grep -r "latLngToScreenPoint\|flutter_map" lib/infrastructure/mirk/wisp/`: 2 hits, BOTH inside `///` docstrings; ZERO in actual import or call sites (Pitfall 1 / Pitfall 2 firewall confirmed).

---
*Phase: 04-wisp-particles*
*Completed: 2026-05-04*
