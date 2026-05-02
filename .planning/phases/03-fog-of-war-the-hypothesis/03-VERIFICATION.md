---
phase: 03-fog-of-war-the-hypothesis
verified: 2026-05-01T00:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 3: Fog of War — THE HYPOTHESIS Verification Report

**Phase Goal:** Produce a binary verdict (confirmed / denied / confirmed-with-caveats) on the same-Canvas fog-of-war hypothesis, with reproducible evidence and a clear MirkFall port-back recommendation. The deliverable is the falsification verdict in `03-FALSIFICATION.md`.

**Verified:** 2026-05-01
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

The phase goal is NOT "ship a confirmed hypothesis" — it is "produce an honest binary answer with evidence." A `denied` verdict with supporting evidence IS the deliverable. This verification assesses whether the phase delivered its contracted artifact, not whether the hypothesis succeeded.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Pre-walk gates passed (flutter test GREEN, analyze clean, format clean, CI IPA downloadable) | VERIFIED | 03-UAT.md gates section: 126/126 flutter tests GREEN; 0 analyzer warnings; 69 files format-clean; 18 tool tests GREEN; CI run 25224334312 all 3 jobs success; IPA at `.uat-tmp/mirk-poc-debug-unsigned.ipa` |
| 2 | Sideloaded IPA opened `/sanity` successfully — fog shader compiled on iPhone 17 Pro | VERIFIED | 03-FALSIFICATION.md §Pre-walk shader-sanity gate: developer saw "mirk" on walk screen; no `severe` / `Failed to load fog shader` log entries before walk aborted. Fog rendering pipeline software-functional. |
| 3 | Walk executed on iPhone 17 Pro in central Melun; developer issued a binary verdict | VERIFIED | 03-UAT.md verdict frontmatter: `verdict: denied`, `walked: 2026-05-01`, device `iPhone 17 Pro`, location `central Melun (48.5397, 2.6553)`. Developer's verbatim: *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"* |
| 4 | 03-FALSIFICATION.md contains pre-walk criteria (A, B, C-DROPPED, walk plan) + post-walk evidence + verdict + MirkFall recommendation | VERIFIED | File at `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md`: `Verdict: DENIED` header filled; Walk Evidence sections filled with `NOT CAPTURED` rationale; Criterion A and B verdict checkboxes checked; Outcome `DENIED` stated; `DO NOT PORT BACK as-implemented` recommendation present with three diagnostic possibilities. Pre-walk content preserved verbatim above walk sections. |
| 5 | FOG-04..07 correctly flipped to Falsified-in-production; FOG-01..03 and FOG-08 retain Complete status | VERIFIED | REQUIREMENTS.md: FOG-01..03 marked `[x]` with "Verified-by-test" annotations; FOG-08 marked `[x]`; FOG-04..07 marked `[ ]` with "Falsified-in-production (P03-08 walk DENIED 2026-05-01)" notes. Traceability table updated to match. |
| 6 | PERF-03 and PERF-04 correctly marked Not-measured with moot-per-falsification-clause rationale | VERIFIED | REQUIREMENTS.md: PERF-03 `[ ]` with "NOT MEASURED — walk aborted on visual grounds; unmeasured-and-moot"; PERF-04 `[ ]` with "NOT CAPTURED — walk aborted on Criterion B's failure; per falsification clause Criterion B's failure alone delivers `denied`". Rationale is sound: measuring frame-delta on a fog surface that doesn't translate is meaningless. |
| 7 | 03-UAT.md exists mirroring Phase 2's 02-UAT.md shape, with cross-reference to 03-FALSIFICATION.md | VERIFIED | File at `.planning/phases/03-fog-of-war-the-hypothesis/03-UAT.md`: status frontmatter `failed`, verdict `denied`, walked `2026-05-01`; Walk Evidence, Verdict, Deviations, Summary, Gaps sections all present; cross-reference to `03-FALSIFICATION.md` in Falsification Thresholds section and Verdict section. |

**Score:** 7/7 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` | Falsification doc with walk evidence + verdict + MirkFall recommendation | VERIFIED | 108 lines. `Walked on: 2026-05-01`, `Verdict: DENIED`, all 5 Walk Evidence subsections present, Verdict checklist filled, `DO NOT PORT BACK as-implemented` + 3 diagnostic possibilities documented. Pre-walk criteria preserved verbatim. |
| `.planning/phases/03-fog-of-war-the-hypothesis/03-UAT.md` | UAT walk summary mirroring 02-UAT.md shape | VERIFIED | Frontmatter: `status: failed`, `verdict: denied`, `walked: 2026-05-01`, `ci_run: 25224334312`, `ci_sha: 280dd04...`. All Walk Evidence sections filled. Verdict section present. Gaps YAML with `GAP-PHASE-3.1-CAMERA-TRANSFORM` blocker + `GAP-FOG-04-STRUCTURAL-TEST-INSUFFICIENT` lesson-learned. |
| `lib/presentation/widgets/fog_layer.dart` | FogLayer widget with MobileLayerTransformer, single-camera-snapshot lock, 41-uniform shader paint | VERIFIED / STRUCTURAL | 417 lines, substantive. `FogLayer` builds `MobileLayerTransformer(child: CustomPaint(painter: _FogPainter(...)))`. `MapCamera.of(context)` called once per build with `FogLayer.debugOnCameraRead` test seam. `FogShaderUniforms.setAll()` path invoked via `_FragmentShaderFogRenderer`. `frameDeltaProbe.recordCameraSnapshot()` and `recordFogUniformPopulation()` wired per FOG-08. **Note:** Structural test passes (MobileLayerTransformer present); production walk denied Canvas-transform sharing — this is the phase's documented finding, not a verification gap. |
| `lib/infrastructure/mirk/frame_delta_probe.dart` | FrameDeltaProbe with ring buffer, 1-Hz JSONL rollup, broadcast stream | VERIFIED | 232 lines. Ring buffer `_buffer`, dual-clock discipline (Stopwatch for deltas, DateTime for epoch tag), `Stream<FrameDeltaRollup>` broadcast, 1-Hz `Timer.periodic` rollup, JSONL via `Logger('infrastructure.mirk.frame_delta')`. |
| `lib/presentation/widgets/frame_delta_probe_overlay.dart` | On-screen 3-line HUD subscribed to probe rollups, colour-coded | VERIFIED | 116 lines. Subscribes to `probe.rollups` stream; renders median/p95/max with green/amberAccent/red colour coding against threshold constants. Mounted at `top:kPocFrameDeltaProbeOverlayTopPx (104) right:8` in MapScreen Stack (confirmed in map_screen.dart). |
| `lib/domain/revealed/reveal_disc_repository.dart` | RevealDiscRepository ChangeNotifier with append + snapshot | VERIFIED | 44 lines. `append(disc)` + `snapshot()` + `addListener/removeListener` via ChangeNotifier. Wired in MapScreen `_subscribeToPositions` with hand-rolled disc ID. |
| `lib/presentation/screens/map_screen.dart` | MapScreen with FogLayer mounted between VectorTileLayer and CircleLayer, probe lifecycle owned | VERIFIED | 331 lines. `FogLayer` in FlutterMap children between `VectorTileLayer` and blue-dot `CircleLayer<Object>`. `frameDeltaProbe.start()` in `initState`, `probe.dispose()` fire-and-forget in `dispose`. `FrameDeltaProbeOverlay` at `top:104 right:8` in Stack unconditionally. FOG-01 disc append on every GPS fix. |
| `.planning/REQUIREMENTS.md` | All 11 Phase 3 IDs (FOG-01..08 + PERF-03/04/05) addressed | VERIFIED | FOG-01..03 `[x]` Complete; FOG-04..07 `[ ]` Falsified-in-production; FOG-08 `[x]` Complete; PERF-03/04 `[ ]` Not-measured-and-moot; PERF-05 `[x]` Measured-with-DENIED-verdict. Traceability table and Revisions log updated. |
| `.planning/STATE.md` | Status flipped to hypothesis-denied; Phase 3.1 blocker entered | VERIFIED | Frontmatter `status: hypothesis-denied`; `stopped_at` updated; `completed_phases: 3`; `completed_plans: 21`; PHASE-3.1-CAMERA-TRANSFORM blocker in Blockers/Concerns section. |
| `.planning/ROADMAP.md` | Phase 3 row Complete (HYPOTHESIS DENIED); Phase 4/5 blocked | VERIFIED | Phase 3 `[x]` with "HYPOTHESIS DENIED 2026-05-01" annotation + 03-FALSIFICATION.md reference + Phase 3.1 recommendation. Phase 4 + Phase 5 marked "BLOCKED on Phase 3.1 gap-closure outcome". Progress table Phase 3 row: `8/8 | Complete (HYPOTHESIS DENIED) | 2026-05-01`. |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `03-FALSIFICATION.md` | `03-UAT.md` | Cross-reference text | WIRED | 03-FALSIFICATION.md's Walk Plan references walk protocol; 03-UAT.md's Verdict section and Falsification Thresholds section both cite `03-FALSIFICATION.md` by path. |
| `FogLayer.build()` | `_FogPainter.paint()` | `cameraSnapshotMicros` parameter | WIRED | `recordCameraSnapshot()` called in `build()`; returned int threaded into `_FogPainter` constructor; `recordFogUniformPopulation(cameraSnapshotMicros)` called in `paint()` before renderer. |
| `MapScreen._subscribeToPositions()` | `RevealDiscRepository.append()` | Every GPS fix | WIRED | `map_screen.dart` line 150: `widget.services.discRepository.append(RevealDisc(...))` on every `_positionSubscription.listen` callback. |
| `FrameDeltaProbeOverlay` | `FrameDeltaProbe.rollups` stream | StreamSubscription in initState | WIRED | `_subscription = widget.probe.rollups.listen(...)` in overlay's `initState`. Probe's `start()` called in MapScreen `initState`. |
| `FOG-04..07 status` | `03-FALSIFICATION.md` | "See 03-FALSIFICATION.md" note | WIRED | All four Falsified-in-production entries in REQUIREMENTS.md cite "See 03-FALSIFICATION.md" by name. |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FOG-01 | 03-07 (wiring) | 25 m RevealDisc appended on every GPS fix | SATISFIED | `map_screen.dart` `_subscribeToPositions` calls `discRepository.append`; REQUIREMENTS.md `[x]` Complete-Verified-by-test |
| FOG-02 | 03-02 | SDF built in metres, not pixels | SATISFIED | `distance_metres_test.dart`: `distanceMetres((48.5,2.6),(48.5,3.6)) ≈ 73.7 km`; REQUIREMENTS.md `[x]` |
| FOG-03 | 03-03 | SDF rebuilt on disc-list change; rebuild duration logged | SATISFIED | `sdf_cache.dart` 103 lines, hash-based invalidation; `sdf_rebuild_logger.dart` 82 lines, 1-Hz JSONL rollup; REQUIREMENTS.md `[x]` |
| FOG-04 | 03-05 (structural) | FogLayer registered as flutter_map custom layer painting in same Canvas | FALSIFIED-IN-PRODUCTION | Structural test GREEN (`find.descendant(of: FogLayer, matching: MobileLayerTransformer)` passes); production walk DENIED — fog does not translate during pan. Correctly documented as `[ ]` Falsified-in-production. Phase 3's deliverable is the verdict, not Canvas-transform fix. |
| FOG-05 | 03-05 | 41 float uniforms + sampler populated via FogShaderUniforms.setAll | FALSIFIED-IN-PRODUCTION | `FogShaderUniforms.totalFloatSlots == 41` test GREEN; `setAll()` called in `_FragmentShaderFogRenderer`; production walk shows uniform population is correct but painter Canvas does not inherit translation transform. Correctly `[ ]` Falsified-in-production. |
| FOG-06 | 03-05 | Clip path computed and applied via canvas.clipPath | FALSIFIED-IN-PRODUCTION | `fog_clip_path.dart` 77 lines, substantive; `canvas.clipPath(clipPath)` in `_FogPainter.paint()`. Geometry correct but applied in screen-space that doesn't translate with camera. Correctly `[ ]` Falsified-in-production. |
| FOG-07 | 03-05 | Single MapCamera snapshot per paint (anti-BUG-014) | FALSIFIED-IN-PRODUCTION | FOG-07 KEYSTONE test GREEN (readCount==1 initial, +1 per rebuild); production walk shows snapshot staleness or screen-space consumption is the failure mode. Correctly `[ ]` Falsified-in-production. |
| FOG-08 | 03-04, 03-06, 03-07 | Frame-delta probe with overlay, JSONL log, per-frame recording | SATISFIED | `frame_delta_probe.dart` 232 lines; `frame_delta_probe_overlay.dart` 116 lines; wired in `map_screen.dart`; REQUIREMENTS.md `[x]` Complete-Verified-by-test |
| PERF-03 | 03-08 (walk) | Pan-FPS with fog ≥ 30; idle-fog FPS ≥ 50 | NOT-MEASURED-MOOT | Walk aborted on Criterion B visual failure before FPS observation. Moot: correctness failure (fog doesn't translate) is independent of throughput. Falsification clause: Criterion B failing alone delivers `denied`. Correctly `[ ]` Not-measured. |
| PERF-04 | 03-08 (walk) | Frame-delta median ≤ 16 ms, p95 ≤ 32 ms, max ≤ 48 ms | NOT-MEASURED-MOOT | Walk aborted before ≥ 10 combined-gesture rollup window. Moot: measuring camera-to-fog-paint delta on a fog that doesn't translate is meaningless. Correctly `[ ]` Not-captured. |
| PERF-05 | 03-08 (walk) | Developer subjective verdict: no fog slip, no white-ellipse, no reveal-hole lag, no inversion | MEASURED-DENIED | Developer verbatim captured: *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*. Three of four sub-claims fail. REQUIREMENTS.md `[x]` checked-as-measured (not as-passed), per the requirement's intent to capture the verdict. |

**All 11 Phase 3 requirement IDs accounted for. Zero orphaned requirements.**

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `map_screen.dart` | 308 (comment only) | "placeholder" word in comment | Info | Not a code stub — the comment explains overlay UX ("shows 'no samples yet' placeholder before the first probe rollup"). Not a code anti-pattern. |

No blocker or warning-level anti-patterns found in Phase 3 production files. No `return null` stubs, no `return {}` stubs, no `console.log`-only handlers, no TODO/FIXME/HACK markers in production code.

---

## Human Verification — Already Completed

The primary human verification gate for this phase was the iPhone 17 Pro falsification walk itself, which was executed on 2026-05-01. This is documented and complete.

| Item | Test | Outcome | Evidence |
|------|------|---------|----------|
| Fog shader compile on iPhone 17 Pro | Open `/sanity` route; confirm fog renders with circular reveal hole; grep log for `severe` / `Failed to load fog shader` | PASSED — developer saw "mirk" on walk screen; no shader-compile exceptions before walk aborted | 03-FALSIFICATION.md §Pre-walk shader-sanity gate; 03-UAT.md §Pre-walk Gates |
| Fog translation lock during pan (Criterion B) | Walk Melun; observe whether fog translates with map during pan | FAILED — fog static during pan; only blue dot moves | 03-FALSIFICATION.md §Subjective verdict; developer verbatim captured |
| Rotation gesture propagation | Incidental observation during walk | PASSED (incidental) — developer noted "it can be rotated tho" — rotation transforms DO apply to fog; only translation is broken | 03-FALSIFICATION.md §Subjective verdict |

No outstanding human verification items — the walk evidence is complete and the verdict is committed.

---

## Gaps Summary

**No gaps.** This is an initial verification with `status: passed`.

Phase 3's deliverable was a binary verdict, and the verdict was produced, supported with evidence, and committed to the repo. The DENIED outcome does not make the phase incomplete — it makes it scientifically complete. Specifically:

- The `03-FALSIFICATION.md` artifact exists, is substantive, and contains all required sections: hypothesis, pre-walk criteria (A, B, C-DROPPED), walk plan, walk evidence (with honest "NOT CAPTURED" where moot), verdict checklist, outcome statement, and MirkFall migration recommendation with three diagnostic possibilities.
- The `03-UAT.md` artifact exists and mirrors Phase 2's `02-UAT.md` shape.
- All 11 Phase 3 requirement IDs are accounted for in REQUIREMENTS.md with appropriate status (Complete, Falsified-in-production, Not-measured-moot, or Measured-DENIED).
- The three commits (`280dd04`, `f79da77`, `53b2270`) exist in git history.
- FOG-04..07 marked Falsified-in-production is consistent with what the production code actually does: the structural tests pass (MobileLayerTransformer wraps the FogLayer), but the production walk revealed the painter's Canvas does not inherit the tile layer's translation transform.
- PERF-03/04 marked Not-measured with "moot per falsification clause" is acceptable: the Plan 03-08 frontmatter pre-committed the falsification clause ("Criterion A AND Criterion B must BOTH pass for confirmed; either failing → denied"), and Criterion B's visual failure was so dominant that no quantitative evidence was collected before the walk aborted.

The phase's designated gap — the PHASE-3.1-CAMERA-TRANSFORM blocker — is correctly logged in `03-UAT.md`'s Gaps YAML, in STATE.md's Blockers/Concerns section, and in ROADMAP.md's Phase 4/5 rows. This is the input to Phase 3.1 planning, not a verification failure of Phase 3 itself.

---

_Verified: 2026-05-01_
_Verifier: Claude (gsd-verifier)_
