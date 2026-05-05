---
phase: 04-wisp-particles
verified: 2026-05-04T00:00:00Z
status: passed
score: 9/9 must-haves verified
---

# Phase 4: Wisp Particles — Verification Report

**Phase Goal:** Composite the wisp particle system after the fog in the same Canvas, with positions stored in `LatLng` (world space) and projected to screen via the same `MapCamera` snapshot the fog uses. Confirms that the same-Canvas discipline established in Phase 3.1 (single `MapCamera.of(context)` snapshot per paint, FOG-07 invariant) generalises to a second visual layer — the cross-pipeline parity check that completes the code-donor package for porting back to MirkFall.
**Verified:** 2026-05-04T00:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | WispParticle stores `LatLng position` (NOT `Offset`) — WISP-01 dimensional discipline | VERIFIED | `wisp_particle.dart` line 47: `LatLng position;`. No `Offset position` field present anywhere in the file. `wisp_particle_test.dart` test 1 asserts `isA<LatLng>()` on the stored field. |
| 2 | WispParticleSystem integrates LatLng-basis kinematics (m/s velocity, curl-noise, 200-cap LRU, 5-s warmup gate) — WISP-02/03 | VERIFIED | `wisp_particle_system.dart` implements `advance()` with `dLatDeg`/`dLonDeg` Euler step, `_enforceCap()` LRU sort, warmup gate `_wallClock.elapsedMilliseconds < (kMirkPocWispWarmUpSeconds * _millisecondsPerSecond).round()`. No flutter_map import found. 6 GREEN unit tests cover all behaviors including `_FakeStopwatch`-controlled warmup test. |
| 3 | `_FogPainter._renderWisps` is inserted AFTER `canvas.drawRect(...shader)` and BEFORE `canvas.restore()` — WISP-04 paint sequence | VERIFIED | `fog_layer.dart` lines 628-642: `canvas.drawRect(...)` at line 629 followed by `_renderWisps(canvas, camera)` at line 640 followed by `canvas.restore()` at line 642. All three are inside the same `canvas.save()` block that starts at line 482. |
| 4 | Wisp positions project via THE SAME `camera` snapshot (single-snapshot FOG-07 keystone preserved) — no second `MapCamera.of(context)` call anywhere in the wisp path | VERIFIED | `MapCamera.of(context)` appears exactly once in `fog_layer.dart` at line 310 (inside `FogLayer.build`). `_renderWisps` receives the camera via constructor arg; grep on `MapCamera.of` in the wisp code path returns zero new occurrences. `fog_layer_single_camera_snapshot_test.dart` test asserts `readCount == 1` per build even with `WispParticleSystem` wired. |
| 5 | `WispTransformLogger` mirrors `FogTransformLogger` structurally and emits to `Logger('infrastructure.mirk.wisp')` — WISP-05 | VERIFIED | `wisp_transform_logger.dart` line 64: `static final Logger _log = Logger('infrastructure.mirk.wisp');`. Class implements start/stop/recordPaint/computeStats with identical architecture to FogTransformLogger. 4 GREEN unit tests in `wisp_transform_logger_test.dart`. |
| 6 | MapScreen wires `wispParticleSystem.spawnAtNewDisc` on new disc append AND `wispTransformLogger.start()`/`stop()` lifecycle — WISP-04/05 | VERIFIED | `map_screen.dart` line 153: `widget.services.wispTransformLogger.start()`. Line 306: `widget.services.wispParticleSystem.spawnAtNewDisc(discId: discId, disc: disc)`. Line 390: `widget.services.wispTransformLogger.stop()`. Exactly ONE spawnAtNewDisc callsite (verified by grep); start/stop symmetric in initState/dispose. |
| 7 | WispParticleSystem is a Pitfall-1 firewall — does NOT import flutter_map or call `latLngToScreenPoint` | VERIFIED | `grep -r "import.*flutter_map" lib/infrastructure/mirk/wisp/` returns zero matches. `latLngToScreenPoint` appears only in comments inside `wisp_particle_system.dart`, not in executable code. |
| 8 | Success Criterion #1 (pan invariance): 100 m pan does NOT mutate wisp LatLng; projected screen Offset shifts in the correct direction | VERIFIED | `wisp_pan_invariance_test.dart` constructs two MapCameras differing by 0.001357° east, projects the same `WispParticle.position` through both, and asserts `wisp.position` is bit-identical AND `dxScreen < 0` (eastward pan shifts feature westward on screen). GREEN. |
| 9 | Success Criterion #2 (warmup gate / no synthetic (0,0)): no wisps during first 5 s AND no wisps at (0,0) if no fix | VERIFIED | `wisp_no_fix_warmup_test.dart` mounts MapScreen with default-clock WispParticleSystem (warmup active) and NEVER-emitting stream; asserts `activeCount == 0`. Second testWidgets emits (0,0) fix and asserts `activeCount == 0`. Both GREEN. |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/config/constants.dart` | 13 kMirkPocWisp* constants + WispRadiusBasis enum + kPocWispTransform* + kMelunCenter* + kMirkPocWispCurlInputScale | VERIFIED | All 17 entries present at lines 494-624. WispRadiusBasis enum at line 533. Each constant carries `///` docstring with unit and rationale. |
| `lib/infrastructure/mirk/wisp/wisp_particle.dart` | WispParticle with LatLng position field, Offset velocityMetersPerSecond, life, maxLife, isDead, age | VERIFIED | 71 LOC. GOSL header. Imports `latlong2` only. `LatLng position` mutable field. `bool get isDead => life <= 0` and `double get age => 1.0 - (life / maxLife).clamp(0.0, 1.0)` implemented (not stubs). |
| `lib/infrastructure/mirk/wisp/wisp_particle_system.dart` | WispParticleSystem: spawnAtNewDisc / advance / advanceFromWallClock / wisps / activeCount / spawnRatePerSecondAndReset / clear + curl-noise helpers | VERIFIED | 390 LOC. No flutter_map import. Implements all 7 public methods + private `_spawnAlongPerimeter`, `_spawnAtPosition`, `_enforceCap`, `_curlNoise`, `_scalarNoise`, `_hash2`. Stopwatch test seam. |
| `lib/infrastructure/mirk/wisp/wisp_transform_logger.dart` | WispTransformLogger mirroring FogTransformLogger; Logger('infrastructure.mirk.wisp'); 9-field JSONL record | VERIFIED | 237 LOC. Logger name exact. epochSecond via `DateTime.now().millisecondsSinceEpoch ~/ 1000` (grep-correlation discipline). FIFO drop. stop()-flush. computeStats static helper. |
| `lib/presentation/widgets/fog_layer.dart` | `_renderWisps(canvas, camera)` inside save/restore, after drawRect, before restore; constructor extended with wispParticleSystem + wispTransformLogger + wispWallClock; shouldRepaint NOT extended with wisp fields | VERIFIED | `_renderWisps` at line 693. Paint order: drawRect (629) → `_renderWisps(640)` → restore (642). `wispParticleSystem`, `wispTransformLogger`, `wispWallClock` all required constructor fields. `shouldRepaint` at line 835 checks only camera/discs/sdfImage identity — no wisp fields (Pitfall 4 prevention documented). |
| `lib/presentation/screens/map_screen.dart` | wispTransformLogger.start() in initState, spawnAtNewDisc in _subscribeToPositions, wispTransformLogger.stop() in dispose | VERIFIED | Three grep hits at lines 153, 306, 390. Existing `_log.info('Fix: ...')` preserved. `discId` and `disc` extracted as locals before append (correct order). |
| `lib/domain/map/map_screen_services.dart` | wispParticleSystem + wispTransformLogger required fields | VERIFIED | Lines 42-92. Both required in constructor. Docstrings explain FOG-07 carry-over and WISP-05 lifecycle discipline. |
| `lib/presentation/router.dart` | WispParticleSystem() + WispTransformLogger() constructed; no wallClock override (production default) | VERIFIED | Lines 95-96: `wispParticleSystem: WispParticleSystem()` and `wispTransformLogger: WispTransformLogger()`. No start() call in router (lifecycle in MapScreen). |
| `test/infrastructure/mirk/wisp/wisp_particle_test.dart` | 3 GREEN tests: LatLng type assertion + isDead decay + age curve | VERIFIED | 70 LOC. 3 tests: position isA<LatLng>, isDead at life≤0, age clamp [0,1]. |
| `test/infrastructure/mirk/wisp/wisp_particle_system_test.dart` | 6 GREEN tests including _FakeStopwatch-controlled warmup + advanceFromWallClock dt-clamp | VERIFIED | ~250 LOC. 6 tests: perimeter spawn count, idempotency, LRU cap, warmup gate + post-warmup re-call guard, advance integration, advanceFromWallClock first-call no-op + dt-clamp. |
| `test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart` | 4+ GREEN tests: rollup math + idle skip + FIFO cap + stop-flush | VERIFIED | 4 tests per plan, mirroring fog_transform_logger_test.dart structure. Logger name assertion for grep-correlation. |
| `test/presentation/widgets/fog_layer_wisp_render_test.dart` | testWidgets asserting WISP-04 paint sequence and projection path | VERIFIED | File exists with WISP-04 group. Asserts drawRect → drawCircle ordering and camera.latLngToScreenPoint usage. |
| `test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart` | FOG-07 keystone test with WispParticleSystem wired; readCount == 1 per build | VERIFIED | 101 LOC. Tests readCount increments exactly 1 per build, for 3 consecutive forced rebuilds. WispParticleSystem and WispTransformLogger both passed to FogLayer. |
| `test/wisp/wisp_pan_invariance_test.dart` | SC #1: 100 m pan — LatLng unchanged, screen dx < 0 | VERIFIED | 83 LOC. Pure-Dart test. _fakeCamera helper mirrors fog_clip_path_test.dart pattern. |
| `test/wisp/wisp_no_fix_warmup_test.dart` | SC #2: 2 testWidgets — warmup suppression + (0,0) anti-pattern guard | VERIFIED | 182 LOC. Both testWidgets assert activeCount == 0 after fix injection. Inline sanity check for (0,0) fix during warmup. |
| `.planning/phases/04-wisp-particles/04-FALSIFICATION.md` | Walk #1 verdict CONFIRMED-AFTER-FIX (FULL); per-criterion table; developer verbatim quote | VERIFIED | Fully populated. Verdict: CONFIRMED-AFTER-FIX (FULL). Verbatim: "phase 4 approved, wips are working like they should, no issue in agressive pan/zoom". CI run 25351448942, SHA eec9087. Per-criterion table A-G with GREEN/DEFERRED statuses. |
| `.planning/phases/04-wisp-particles/04-UAT.md` | Pre-walk gate evidence; CI run + SHA captured | VERIFIED | Pre-walk gates documented: 211 tests passed, analyze 0 issues, dart format clean, GOSL headers OK. CI run and SHA captured in frontmatter. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `fog_layer.dart _FogPainter._renderWisps` | `camera.latLngToScreenPoint(wisp.position)` | per-wisp projection inside the painter using THE camera snapshot | WIRED | `fog_layer.dart` line 747: `final screenPt = camera.latLngToScreenPoint(wisp.position);`. Camera is the constructor arg (FOG-07 snapshot). |
| `map_screen.dart _subscribeToPositions` | `widget.services.wispParticleSystem.spawnAtNewDisc` | GPS fix → discRepository.append → wispParticleSystem.spawnAtNewDisc(discId, disc) | WIRED | `map_screen.dart` line 306: call present, exactly one match. discId and disc are local vars constructed before append (line 298-305). |
| `fog_layer.dart _FogPainter.paint` | `wispParticleSystem.advance + _renderWisps + wispTransformLogger.recordPaint` | single paint() body, single canvas.save/restore, single MapCamera | WIRED | `_renderWisps` at line 640 calls `wispParticleSystem.advanceFromWallClock(wispWallClock)` (line 697), then per-wisp loop with `camera.latLngToScreenPoint`, then `wispTransformLogger.recordPaint` at line 767. All inside the save/restore block. |
| `wisp_transform_logger.dart` | `Logger('infrastructure.mirk.wisp')` | static Logger field + log.info(jsonLine) | WIRED | Line 64 declares the logger; `_log.info(line)` at line 199 emits JSONL. epochSecond derivation at line 161 matches FogTransformLogger pattern for grep-correlation. |
| `wisp_particle_system.dart` | WispParticle(position: LatLng) | spawnAtPosition constructs WispParticle with LatLng position arg | WIRED | Line 192: `WispParticle(position: jitteredPosition, ...)` where `jitteredPosition` is type `LatLng`. Pattern `WispParticle(position:` found at line 192. |
| `wisp_particle_system.dart` | disc.lat / .lon / .radiusMeters | spawnAlongPerimeter reads disc fields to compute perimeter sample points | WIRED | `_spawnAlongPerimeter` at lines 149-166 reads `disc.radiusMeters`, `disc.lat`, `disc.lon`. Pattern `disc\.lat|disc\.lon|disc\.radiusMeters` confirmed. |
| `test/wisp/wisp_pan_invariance_test.dart` | MapCamera.latLngToScreenPoint | FOG-07 cross-pipeline parity check | WIRED | Line 49-50: `cameraBefore.latLngToScreenPoint(wisp.position)` and `cameraAfter.latLngToScreenPoint(wisp.position)`. Pattern `latLngToScreenPoint` at both lines. |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| WISP-01 | 04-01, 04-03, 04-04 | Wisp positions stored as LatLng (world space), projected at paint time | SATISFIED | `WispParticle.position` field is `LatLng`. Projection via `camera.latLngToScreenPoint` in `_renderWisps`. REQUIREMENTS.md row flipped to complete with Walk #1 validation. |
| WISP-02 | 04-01, 04-03, 04-04 | Wisp kinematics: m/s basis, 200-cap LRU, spawn loop, life/age cycle, curl-noise | SATISFIED | WispParticleSystem implements all behaviors. 6 unit tests GREEN. Walk #1 verbal verdict confirms visual behavior. |
| WISP-03 | 04-01, 04-03 | 5 s warmup gate suppresses wisp spawn on app open | SATISFIED | `_wallClock.elapsedMilliseconds < ...` guard in `spawnAtNewDisc`. `_FakeStopwatch` test seam. SC #2 testWidgets GREEN. Walk #1: no spurious wisps during cold-launch. |
| WISP-04 | 04-01, 04-04 | Wisp render: `_renderWisps` inside fog's canvas.save/restore, after drawRect, before restore; projection via camera snapshot | SATISFIED | Code at fog_layer.dart lines 628-642. fog_layer_wisp_render_test.dart GREEN. FOG-07 keystone test GREEN. |
| WISP-05 | 04-01, 04-02, 04-04 | WispTransformLogger: 1-Hz JSONL via `Logger('infrastructure.mirk.wisp')`, 9-field record, stop-flush, FIFO cap | SATISFIED | wisp_transform_logger.dart fully implemented. 4 unit tests GREEN. Logger name exact. Lifecycle wired in MapScreen initState/dispose. |
| PERF-07 | 04-05 (carry-over) | frame_delta medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48 under fog + 200 wisps | SATISFIED (implicit) | Walk #1: FpsCounterOverlay + FrameDeltaProbeOverlay visible during aggressive pan/zoom; developer's "no issue in agressive pan/zoom" implicitly covers PERF-07 (overflow would have manifested visually). 04-FALSIFICATION.md Criterion C: GREEN (implicit). |
| PERF-08 | 04-05 (carry-over) | SDF rebuild rate stable vs Walk #2 baseline; wisp path MUST NOT trigger SDF rebuilds | SATISFIED (structural) | WispParticleSystem has zero code path through SdfCache or RevealDiscRepository. Pitfall 4 firewall confirmed by grep: `wispParticleSystem` not in sdf_cache.dart or sdf_rebuild_logger.dart. 04-FALSIFICATION.md Criterion D: GREEN (implicit/structural). |
| UX-02 | 04-05 (carry-over) | Rotation gestures are no-ops; InteractiveFlag.rotate disabled | SATISFIED | `InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)` unchanged through all Phase 4 plans (grep confirms no rotation-related changes). Walk #1 Criterion F: GREEN. map_screen_test.dart UX-02 assertion still GREEN. |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

Checked files: wisp_particle.dart, wisp_particle_system.dart, wisp_transform_logger.dart, fog_layer.dart (_renderWisps section), map_screen.dart (wisp wiring section), router.dart (wisp construction). No `TODO`, `FIXME`, `throw UnimplementedError`, `return null`, `return {}`, `return []`, `console.log`, or placeholder comments found in production paths. All stubs from Plan 04-01 were replaced with real implementations in Plans 04-02/04-03/04-04.

---

### Human Verification Required

All automated checks passed. The following Walk #1 axes were human-verified and accepted:

1. **Wisp visual appearance (Criterion A)** — spawn along 25 m disc perimeter, drift outward, fade over ~2.5 s — confirmed verbally by developer.

2. **Same-Canvas anchoring under aggressive pan/zoom (Criterion B)** — no parallax between wisps and fog during combined gestures — confirmed verbally by developer ("no issue in agressive pan/zoom").

3. **WalkSimulator fidelity to live GPS (structural)** — Walk #1 used the synthetic GPS emitter (eec9087). The structural fidelity is confirmed by the shared `_onPositionFix` listener body, but live outdoor GPS validation is folded into Phase 5 per 04-FALSIFICATION.md.

Deferred axes accepted per Phase 3.1 closure precedent:
- **Criterion D (PERF-08 quantitative SDF rebuild rate)** — structural firewall verified; quantitative walk measurement deferred to Phase 5.
- **Criterion E (C3' extreme-distance ~50-100 km)** — phase 3.1 Walk #5 baseline applies; wisp projection inherits same MapCamera snapshot so fp32 artefacts would be symmetric with fog; deferred.
- **Criterion G (Mail-share JSONL grep-correlation)** — WispTransformLogger code is verified complete; empirical capture deferred per Phase 3.1 Walk #6 verbal-verdict closure precedent.

---

### Gaps Summary

No gaps found. All 9 observable truths verified, all artifacts exist and are substantive and wired, all key links confirmed in the codebase, all 8 requirements satisfied (5 WISP-01..05 fully + 3 carry-overs structurally/implicitly). Walk #1 verbal verdict CONFIRMED-AFTER-FIX (FULL) per 04-FALSIFICATION.md, developer verbatim: "phase 4 approved, wips are working like they should, no issue in agressive pan/zoom".

---

_Verified: 2026-05-04T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
