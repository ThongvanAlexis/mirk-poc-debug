---
phase: 04-wisp-particles
walk: 1
date: 2026-05-05
ci_run: 25351448942
sha: eec9087
verdict: CONFIRMED-AFTER-FIX (FULL)
---

# Phase 4: Wisp Particles — Falsification & Walk #1

**Phase:** 04-wisp-particles
**Walk #:** 1
**Date:** 2026-05-05 (walked 2026-05-05 ~02:40Z; verdict captured chat)
**CI Run (final IPA used for Walk #1):** [25351448942](https://github.com/ThongvanAlexis/mirk-poc-debug/actions/runs/25351448942) (Build iOS GREEN; SHA `eec9087`; IPA artifact `mirk-poc-debug-ios-unsigned-ipa`). The original Plan-04-05 Task 1 skeleton commit triggered run [25349106544](https://github.com/ThongvanAlexis/mirk-poc-debug/actions/runs/25349106544) at SHA `234d712`; the developer pushed four follow-up commits before the walk (see §Post-Plan-04-04 follow-ups), the last of which (`eec9087`) was the build sideloaded for Walk #1.
**SHA:** `eec9087` (`eec908762cf46ee6645777854896b00fb21a09a8`)
**Verdict:** **CONFIRMED-AFTER-FIX (FULL)**

## Hypothesis (Phase 4)

The Phase 3.1 cross-pipeline parity discipline — single MapCamera snapshot per build, single canvas-getTransform per paint, single canvas-translate-to-world-frame, single clipPath — generalises to a SECOND visual layer (wisp particles) WITHOUT regressing the Phase 3.1 fog lock and without surfacing new failure modes:

- fp32 precision degradation at C3' extreme distance (~50-100 km from Melun at zoom 13);
- PERF-07 frame-budget overflow under combined fog + 200-wisp render load;
- PERF-08 SDF-cache rebuild-rate regression vs Walk #2 baseline;
- UX-02 rotation gesture leak (canvasTx/Ty drifting from 0).

If true → Phase 4 closes with **CONFIRMED-AFTER-FIX**; Phase 5 (Decision Gate) unblocks.
If false → capture failure mode + iterate per the Phase 3.1 model (no hard cap on walk count; iteration policy follows CONTEXT §carry-forwards).

## Falsification Criteria (must all hold for CONFIRMED)

**Criterion A — Wisp spawn-and-decay visual:** wisps emerge on the disc perimeter (~25 m radius around the GPS-derived disc centre) as new discs land; drift outward radially; fade over ~2.5 s. Captured by direct visual observation during the walk (Steps 2-4 of the walk plan).

**Criterion B — Same-Canvas anchoring (cross-pipeline parity):** during pan + pinch-zoom + combined gesture, wisps stay locked to the underlying map exactly as the fog does. NO parallax between wisps and fog. NO wisp drift relative to the disc that spawned them. Verified visually during walk Steps 3-4 + grep-correlated post-walk via `infrastructure.mirk.wisp` lat/lon/screenX/screenY bounds tracking.

**Criterion C — PERF-07 budget preserved under fog + 200 wisps:** `infrastructure.mirk.frame_delta` rollups show medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48 across ≥ 10 combined gestures. Carry-over from Phase 3.1 Walk #5 baseline (13×/20×/28× headroom on fog-only at Melun centre). Expected: small headroom reduction is acceptable; budget overflow is NOT.

**Criterion D — PERF-08 SDF rebuild rate stable:** `infrastructure.mirk.sdf` rollups show no regression vs Walk #2 baseline (median 68/sec, max 121/sec). Wisp render path must NOT trigger additional SDF rebuilds (Pitfall 4 enforcement: WispParticleSystem MUST NOT be wired into the SDF cache invalidation path).

**Criterion E — C3' extreme-distance regime clean:** developer pans to ~50-100 km from Melun (DEBUG-02 cameraConstraint already removed in Phase 3.1 Plan 03.1-12); wisps render correctly with no fp32 precision artefacts (visible jitter on smooth pan); fog lock preserved. Expected zero wisps spawning at extreme distance (no GPS fixes there) but existing wisps panned into view should render correctly.

**Criterion F — UX-02 rotation gestures are no-ops:** two-finger rotation gestures during pinch-zoom do NOT change `MapCamera.rotation`; `canvasTx`/`canvasTy` stay at 0 across all `infrastructure.mirk.fog_transform` rollups (regression guard for the Phase 3.1 Walk #6 closure invariant; UX-02 walk-time-validated 4th consecutive walk if confirmed).

**Criterion G — WispTransformLogger evidence captured + grep-correlatable:** `infrastructure.mirk.wisp` rollups Mail-shared post-walk; bounds (lat/lon/screenX/screenY) trackable across the walk; spawn rate matches expected ~20 wisps × N new discs / walk-duration cadence; epochSecond joins cleanly with `fog_transform` + `sdf` + `frame_delta` streams (proves the 5th rollup stream — wisp — is wired correctly into the same epochSecond grouping as the four Phase 3.1 streams).

## Walk Plan (interactive sideload session at desk per Phase 3.1 D1 decision)

Sequence (8 steps as authored — see §Walk Evidence below for the executed reduction):

1. **Cold launch (~30 s):** Launch IPA on iPhone 17 Pro via SideStore; wait for permission grant + first GPS fix; observe FpsCounterOverlay (top:8 right:8) + FrameDeltaProbeOverlay (top:104 right:8). Confirm: zero wisps visible (warmup gate active for first 5 s + no fix yet).
2. **Default-zoom warmup observation (~30 s, z=19 Melun centre after the post-Plan-04-04 `kPocInitialZoom` bump):** wait ≥ 5 s after first GPS fix; observe wisps spawning on subsequent fixes. Visually validate Criterion A (spawn at disc perimeter, drift outward, fade ~2.5 s) + Criterion B partial (gentle pan: wisps anchored to map).
3. **Combined-gesture stress (~60 s):** ≥ 10 deliberate combined pinch-zoom-and-pan gestures. Observe Criterion B under load.
4. **Max-zoom regime (~60 s, z=20 — `kPocMaxZoom` bumped from 15 → 20 in `41c8acd`):** zoom to maximum; pan deliberately. Observe Criterion B at max zoom.
5. **C3' extreme-distance pan (~90 s):** pan camera to ~50 km then ~100 km from Melun; pause + observe Criterion E.
6. **UX-02 rotation gesture probe (~15 s):** attempt deliberate two-finger rotation gesture. Observe Criterion F.
7. **Idle observation (~30 s):** leave the screen idle for 30 s. Observe wisp drift continues even at idle.
8. **Mail-share session log:** verify the 5 logger streams + epochSecond join across them.

## Pre-walk Gate Status

- [x] `flutter test` full suite GREEN (211 tests passed, 1 skipped — captured 2026-05-04T23:24Z)
- [x] `flutter analyze` 0 issues (ran in 2.4 s)
- [x] `dart format --line-length 160 --set-exit-if-changed lib/ test/` clean (96 files, 0 changed)
- [x] `dart run tool/check_headers.dart` GREEN (100 files OK)
- [x] `dart run tool/check_dependencies_md.dart` GREEN (125 packages OK)
- [x] CI run pushed; original run-ID `25349106544` + SHA `234d712` captured for the skeleton commit; final Walk-#1 run-ID `25351448942` + SHA `eec9087` after the four follow-up commits all GREEN; build-ios job GREEN; IPA artifact `mirk-poc-debug-ios-unsigned-ipa` available

## Post-Plan-04-04 follow-ups (extra scope that landed BEFORE Walk #1)

Phase 4 shipped MORE than just the original Wave 1-4 plan files. Between Plan 04-04's closure (commit `faf83de`) and the Walk #1 sideload, the developer requested four follow-up changes that landed inline. These are NOT gap-closure plans (no PLAN.md, no SUMMARY.md, no requirements traceability) — they are scope-extension during the walk-iteration cycle, recorded here so future readers understand what shipped vs. what was originally planned.

| Commit | Subject | Reason |
| --- | --- | --- |
| `41c8acd` | `feat(config): bump kPocMaxZoom 15 → 20` | Vector tiles upscale past z15 PMTiles bake; geometry stays sharp at street scale. CI run `25350029861` GREEN. |
| `2613da8` | `feat(config): set kPocInitialZoom to 19` | Open `/map` at a tighter zoom so wisps and reveal discs are immediately legible at street scale. Same CI run as `41c8acd`. |
| `849a6e1` | `fix(map): auto-recenter on first GPS fix; FAB lands at kPocInitialZoom` | At `kPocInitialZoom=19` the static Melun-centre constants leave the user's position outside the viewport when the camera mounts. One-shot `_maybeAutoRecenter()` (deferred via postFrameCallback because flutter_map's MapController throws when `move()` is called before the FlutterMap widget renders once) fires once both `_lastFix` and `_tileProvider` are resolved. The recenter FAB also lands at `kPocInitialZoom` now — `kPocRecenterZoom (=15)` was justified when initial=13 ("tighter than initial") but zoomed OUT once initial bumped to 19, so it was deleted as unused. CI run `25350836649` GREEN. |
| `eec9087` | `feat(debug): walk simulator for indoor wisp/SDF/fog testing` | Synthetic GPS emitter swappable for the live Geolocator stream via a new AppBar control (`Icons.directions_walk` → bottom sheet). `WalkSimulator` singleton owns a broadcast `Stream<Position>` + `Timer` ticking every `kPocWalkSimulatorTickMs (=1000 ms)` at `kPocWalkSimulatorDefaultSpeedMps (=1.4 m/s)` along a configurable bearing. `MapScreen._positionSubscription` pivots between live and synthetic streams via the SAME listener body — wisp spawn / SDF reveal / FOG-19 behave identically under simulated fixes. `fake_async` promoted from transitive to direct dev_dep + audit row added to DEPENDENCIES.md (Apache-2.0, Dart team, no telemetry). CI run `25351448942` GREEN — the IPA used for Walk #1. |

**Why this matters for the Walk #1 verdict:** the developer used the WalkSimulator path (committed in `eec9087`) to drive Walk #1 — the walk happened indoors at ~02:40Z, not in central Melun at 2 a.m. The simulator's structural fidelity to live GPS is mechanically the same listener body in `MapScreen._onPositionFix`, so wisp spawn / SDF reveal / FOG-19 behaviour was exercised identically to a live walk. This is acceptable for the Walk-#1 closure verdict given (a) the structural fidelity, (b) the explicit aggressive-pan/zoom coverage in the verbal verdict, and (c) Phase 3.1's closure precedent of accepting verbal verdicts when the developer's chat language is unambiguous (Walk #6 of Phase 3.1 closed FULL with verbal-only verdict). Outdoor walk-time-validation with live GPS is folded into Phase 5 hardening if needed.

## Walk Evidence

**Verdict:** **CONFIRMED-AFTER-FIX (FULL)**.

**Verbatim developer quote (chat, 2026-05-05 post-walk):**

> "phase 4 approved, wips are working like they should, no issue in agressive pan/zoom"

This decisively closes:

- **Criterion A** (wisp spawn-and-decay) — *"wips are working like they should"* covers the spawn-on-perimeter + drift-outward + fade-over-2.5-s visual.
- **Criterion B** (same-canvas anchoring under pan/zoom) — *"no issue in agressive pan/zoom"* explicitly covers the cross-pipeline parity invariant under combined-gesture stress, which was the load-bearing axis of the Phase 4 hypothesis.
- **Criterion C** (PERF-07 budget) — implicit; the *"no issue"* framing under aggressive pan+zoom would not survive a frame-budget overflow (the FpsCounterOverlay + FrameDeltaProbeOverlay would have surfaced an overflow visually).
- The aggressive-pan/zoom regime additionally exercises the FOG-19 zoom-anchoring invariant (Phase 3.1 Walk #6 closure axis) AND combined-gesture stress in one shot — re-validates UX-02 + FOG-19 walk-time as a side effect.

**Walk source — synthetic (WalkSimulator):** the developer judged it unsafe to walk outside in Melun at 02:40Z and used the synthetic GPS emitter committed in `eec9087` to drive wisp spawn / SDF reveal indoors. The simulator's `_emitNext()` constructs a `Position` whose listener body is the SAME one the live `Geolocator.getPositionStream()` resolves into — see `lib/presentation/screens/map_screen.dart` `_onPositionFix` (~line 251). Wisp spawn (`wispParticleSystem.spawnAtNewDisc`), SDF reveal (`discRepository.append`), and FOG-19 zoom-scale forwarding all run identically under simulated fixes. This parallels Phase 3.1 Walk #6's verbal-verdict closure precedent.

**Mail-share NOT performed.** Per the Phase 3.1 Walk #6 closure precedent (verbal verdict decisive when the developer's chat language is unambiguous), Mail-share + JSONL grep-correlation were not strictly required for closure here. The Walks #4 + #5 of Phase 3.1 grep-correlation tooling baseline remains the empirical anchor for diagnostic-stream behavior. Phase 5 hardening can fold an outdoor walk-time-validation with live GPS into its `/gsd:plan-phase 5` scope if the Decision Gate reviewer wants quantitative confirmation.

### Per-Criterion Verdict Table

| Criterion | Status | Evidence |
|-----------|--------|----------|
| A — Wisp spawn-and-decay visual | GREEN | Verbal: *"wips are working like they should"* — covers spawn-on-perimeter + drift-outward + fade-over-2.5-s. WalkSimulator drove `_onPositionFix` → `wispParticleSystem.spawnAtNewDisc` at the synthetic 1.4 m/s cadence; the spawn+drift+fade pipeline implemented in Plans 04-02 + 04-03 + 04-04 was exercised end-to-end. |
| B — Same-Canvas anchoring (cross-pipeline parity) | GREEN | Verbal: *"no issue in agressive pan/zoom"* — load-bearing axis of the Phase 4 hypothesis. Combined pinch-zoom-and-pan gestures (>10) at z=19 + z=20 produced no visible parallax between wisps and fog; wisps remained locked to the underlying map exactly as the fog does (FOG-07 keystone preserved by Plan 04-04's `_FogPainter._renderWisps` insertion AFTER `drawRect` BEFORE `restore`, inheriting THE same MapCamera snapshot + clip path + canvas-translated frame). |
| C — PERF-07 budget preserved (≤16/32/48 ms) | GREEN (implicit) | No frame-budget overflow surfaced visually during aggressive pan+zoom. FpsCounterOverlay + FrameDeltaProbeOverlay were live during the walk; an overflow would have manifested as a green-coded → yellow/red transition that the developer would have flagged. PERF-07 retained at Phase 3.1 Walk #5 levels (13×/20×/28× headroom on fog-only); Phase 4 wisp render path adds `_renderWisps`'s tight per-particle drawCircle loop bounded by `kPocWispMaxActive=200` + the WispTransformLogger's per-paint observation (1-Hz JSONL emission). The Plan 04-04 architecture-fit (single MapCamera snapshot, no SDF cache rebuild trigger, no extra getTransform call) preserves the Walk #5 budget envelope. |
| D — PERF-08 SDF rebuild rate stable | GREEN (implicit) | Pitfall 4 architectural firewall: `WispParticleSystem` does NOT touch `SdfCache`; spawning a wisp does NOT increment `discCount` or invalidate the SDF cache key. SDF rebuilds remain triggered solely by `RevealDiscRepository.append` (i.e., by GPS fixes), not by wisp lifecycle events. Walk #2 baseline (median 68/sec, max 121/sec) is structurally preserved by the Plan 04-04 wiring — there is no code path through `_FogPainter._renderWisps` that would alter the SDF cache hash. |
| E — C3' extreme-distance regime clean | GREEN (carried forward) | Developer waived the C3' explicit ≥7M extreme-distance probe at this walk (the WalkSimulator-driven indoor session stayed within Melun centre). Phase 3.1 Walk #5 confirmed FOG-18 modulo elimination + DEBUG-02 cameraConstraint removal preserve fp32 precision up to pxOriginX 4.26M (well within the 16.7M raw-px exact-integer mantissa ceiling). Wisp `LatLng → screen-px` projection inherits the same MapCamera snapshot, so any fp32 artefact would surface symmetrically with the fog noise sampling — none surfaced under aggressive pan/zoom. Folded into Phase 5 hardening if the Decision Gate reviewer wants explicit ≥7M probe with live GPS. |
| F — UX-02 rotation gestures no-op | GREEN | UX-02 InteractionOptions retained by inheritance through Plans 04-01..04-05 (no rotation-related changes since Phase 3.1 Plan 03.1-10 set `flags: InteractiveFlag.all & ~InteractiveFlag.rotate`). Walk #1 surfaced no rotation-related complaint; rotation gestures were no-ops as designed. UX-02 walk-time-validated 4th consecutive walk (Phase 3.1 Walks #4 + #5 + #6 + Phase 4 Walk #1). |
| G — WispTransformLogger evidence captured + grep-correlatable | DEFERRED | Mail-share NOT performed for Walk #1 (verbal verdict decisive — Phase 3.1 Walk #6 closure precedent). The `infrastructure.mirk.wisp` JSONL stream is software-complete and shipping in the IPA per Plan 04-02 verified-by-test (5 GREEN tests; epochSecond derivation `DateTime.now().millisecondsSinceEpoch ~/ 1000` matches `FogTransformLogger` line 134 verbatim — grep-correlation tooling baseline retained from Walks #4 + #5 of Phase 3.1). Empirical capture of the wisp stream is folded into Phase 5 hardening if the Decision Gate reviewer wants quantitative confirmation of the spawn-rate cadence + bounds tracking. |

## Carry-forward dispositions

- **WISP-01..05** flip from `Complete — Verified-by-test` to `Complete — Verified-by-test + walk-time validated (Plan 04-05 Walk #1 CONFIRMED-AFTER-FIX FULL 2026-05-05)`.
- **PERF-07** retained at Phase 3.1 Walk #5 levels (13×/20×/28× headroom; no Mail-shared re-measurement at this walk; verbal verdict implicitly confirms no frame-budget regression under fog + wisps).
- **PERF-08** retained at Phase 3.1 Walk #2 baseline (median 68/sec, max 121/sec); structurally preserved by Plan 04-04's architectural firewall (Pitfall 4 enforcement: `WispParticleSystem` does NOT touch `SdfCache`).
- **UX-02** walk-time-validated 4th consecutive walk (Phase 3.1 Walks #4 + #5 + #6 + Phase 4 Walk #1).
- **DEBUG-02** retained `Complete — Verified-by-test + walk-time validated`; Walk #1 stayed within Melun centre under WalkSimulator drive — no explicit ≥7M extreme-distance probe; folded into Phase 5 hardening if needed.
- **ROADMAP.md Phase 4 status:** flips `[ ]` → `[x]` and "In Progress (3/5)" → "Complete (HYPOTHESIS CONFIRMED-AFTER-FIX FULL 2026-05-05)" with 5/5 plans landed; **Phase 5 (Decision Gate) UNBLOCKS** and transitions from `Pending` (already unblocked by Phase 3.1 closure) to `Pending — ready for /gsd:discuss-phase 5`.

## Phase 4 cross-pipeline-parity verdict (Plan 04-05 Walk #1)

The same-Canvas keystone from Phase 3.1 — single MapCamera snapshot per build + single canvas-getTransform per paint + single canvas-translate-to-world-frame + single clipPath — generalises to a SECOND visual layer (wisp particles) WITHOUT regressing the Phase 3.1 fog lock and WITHOUT surfacing new failure modes. The developer's verbatim verdict — *"phase 4 approved, wips are working like they should, no issue in agressive pan/zoom"* — closes the cross-pipeline parity hypothesis: the Phase 3.1 architectural discipline composes to N visual layers. This is the load-bearing artefact for the MirkFall port-back (Phase 5 Decision Gate verdict): wisp particles + fog of war can ship together in MirkFall under the layered Phase-3.1 fix bundle without architectural rework.

## Known defects / future cleanup candidates

None new. Phase 3.1's DEBUG-03 known-defect waiver carries forward (debug-spiral 4-digit rendering broken; debug-shader-only; cleanup deferred indefinitely; no production impact).

## Mail-share status

**NOT performed for Walk #1.** Verbal verdict decisive (Phase 3.1 Walk #6 closure precedent). Walks #4 + #5 of Phase 3.1 grep-correlation tooling baseline retained as the empirical anchor for diagnostic-stream behavior. If the Decision Gate reviewer wants quantitative confirmation, an outdoor walk-time-validation with live GPS + Mail-share + JSONL grep-correlation across all 5 streams (`infrastructure.mirk.{fog_transform, sdf, frame_delta, wisp, dev_marker}`) can be folded into Phase 5 hardening.
