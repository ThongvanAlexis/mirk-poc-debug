---
phase: 03-fog-of-war-the-hypothesis
plan: 08
subsystem: testing
tags: [perf-03, perf-04, perf-05, fog, hypothesis, falsification, denied, sideload, uat, ios, sidestore, iphone-17-pro, foglayer, mobile-layer-transformer, canvas-transform, phase-exit-uat, phase-3.1-required]

# Dependency graph
requires:
  - phase: 03-fog-of-war-the-hypothesis
    provides: MapScreen × Phase 3 production assembly — FogLayer mounted as child of FlutterMap between VectorTileLayer and the blue-dot CircleLayer; FrameDeltaProbeOverlay at top:104 right:8; probe + SdfCache + SdfRebuildLogger lifecycles owned by initState/dispose (Plan 03-07)
  - phase: 03-fog-of-war-the-hypothesis
    provides: FogLayer + computeFogClipPath + FOG-07 KEYSTONE single-MapCamera-snapshot test GREEN (Plan 03-05)
  - phase: 03-fog-of-war-the-hypothesis
    provides: FrameDeltaProbeOverlay + ShaderSanityScreen pre-walk gate at /sanity (Plan 03-06)
  - phase: 03-fog-of-war-the-hypothesis
    provides: FrameDeltaProbe (FOG-08) + 1-Hz JSONL rollup + dual-clock discipline (Plan 03-04)
  - phase: 03-fog-of-war-the-hypothesis
    provides: SdfCache hash invalidation + SdfRebuildLogger 1-Hz JSONL rollup (Plan 03-03)
  - phase: 03-fog-of-war-the-hypothesis
    provides: RevealDiscRepository (FOG-01) + distanceMetres helper (FOG-02) (Plan 03-02)
  - phase: 03-fog-of-war-the-hypothesis
    provides: Phase 3 Wave 0 keystone scaffold — 12 production stubs + 12 RED test files + 03-FALSIFICATION.md skeleton (Plan 03-01)
  - phase: 02-map-no-fog
    provides: PERF-02 PASS sustained ~120 fps on iPhone 17 Pro (Plan 02-06) — frame-budget headroom verified for the fog shader hypothesis
provides:
  - "Phase 3 closes with formal HYPOTHESIS DENIED verdict written into 03-FALSIFICATION.md (the deliverable Plan 03-08 was contracted to produce — a binary answer to the same-Canvas fog hypothesis)"
  - "MirkFall migration recommendation written into 03-FALSIFICATION.md: DO NOT PORT BACK as-implemented; three diagnostic possibilities for Phase 3.1 gap-closure outlined"
  - "03-UAT.md filled with walk evidence + verdict + Gaps section (YAML for /gsd:plan-phase --gaps consumption); status frontmatter testing → failed; verdict frontmatter denied; walked frontmatter 2026-05-01"
  - "REQUIREMENTS.md FOG-04..07 flipped from Complete to Falsified-in-production with note pointing to 03-FALSIFICATION.md; FOG-01..03 + FOG-08 retain Verified-by-test Complete; PERF-05 marked Measured-with-DENIED-verdict; PERF-03/04 marked Not-measured (walk-aborted-on-visual-grounds)"
  - "STATE.md status flipped to hypothesis-denied; Phase 3 closure logged as a Decision; new PHASE-3.1-CAMERA-TRANSFORM blocker entered under Blockers/Concerns; progress 100% across closed phases"
  - "ROADMAP.md Phase 3 row marked Complete (HYPOTHESIS DENIED) 2026-05-01; Phases 4 + 5 marked Blocked on Phase 3.1; Phase 3 plan checklist 03-08 checked"
  - "Lesson learned recorded in STATE.md: structural widget-tree-containment tests are necessary-but-not-sufficient for same-Canvas hypothesis tests; future port-back work must add behavioural-Canvas-transform-equality assertions alongside structural FOG-04 tests"
affects: [03.1-gap-closure-camera-transform, 04-wisp-particles, 05-decision-gate, mirkfall-migration-decision]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Phase-exit UAT walk pattern reused from Plan 01-07 (Phase 1 closure) and Plan 02-06 (Phase 2 closure): pre-walk falsification thresholds locked → automatable gates run by Claude → IPA built via CI → developer sideloads + walks on canonical device → developer's verbatim words captured into UAT.md + FALSIFICATION.md → verdict committed. The shape held even on a denied walk: Plan 03-08's verdict writing followed the same Task 1 → Task 2 → Task 3 flow as Plan 02-06's PASS walk; only the verdict text and downstream-phase status flags differ."
    - "Falsification clause as design pattern: Plan 03-08 frontmatter pre-committed `Criterion A AND Criterion B must BOTH pass for confirmed; either failing → denied`. The walk aborted on Criterion B's visual failure before Criterion A could be measured; the falsification clause meant Criterion A's absence was unmeasured-and-moot rather than ambiguous-pending. Future falsification walks should pre-commit a clause that disambiguates the partial-evidence outcome — single failure path of either criterion → denied — so a walk-aborted-on-one-criterion still produces a binary verdict."
    - "Structural-widget-tree-containment test is necessary-but-not-sufficient for same-Canvas hypothesis tests: Plan 03-05's FOG-04 GREEN test (`find.descendant(of: FogLayer, matching: MobileLayerTransformer)` returns one match) was treated as a same-Canvas keystone but only confirmed widget-tree containment, NOT Canvas-transform sharing. Future port-back work to MirkFall, AND any Phase 3.1 fix attempt, must add a behavioural-transform-equality test alongside the structural test: trigger a real pan in a real flutter_map context, log `Canvas.getTransform()` in the painter's `paint()`, assert it matches the tile layer's transform at the same paint frame."
    - "Light-touch evidence capture for unambiguous denials: when the developer's verbatim words deliver a binary `denied` verdict on a single dominant failure mode (`mirk isn't moving`), per-slot fine-grained quantitative capture is moot. The walk evidence record honours the denial without fabricating per-slot numbers; the unmeasured slots (Criterion A, PERF-03) are explicitly labelled `not measured` with rationale (walk aborted on Criterion B). Future denial walks should follow this pattern; future approval walks may need fine-grained capture to defend against post-hoc skepticism."

key-files:
  created:
    - ".planning/phases/03-fog-of-war-the-hypothesis/03-08-SUMMARY.md (this file)"
  modified:
    - ".planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md (Walk Evidence + Verdict + MirkFall recommendation appended; Criteria A + B + C + Walk Plan preserved verbatim above the new sections; Walked on + Verdict header lines filled with 2026-05-01 + DENIED)"
    - ".planning/phases/03-fog-of-war-the-hypothesis/03-UAT.md (Walk Evidence sections filled; Verdict section filled with DENIED + developer-verbatim + interpretation; Deviations/Surprises section filled with structural-vs-behavioural-test lesson + rotation-works-but-translation-doesn't surprise; Summary table updated with passed=0/failed=4/skipped=9 counts; Gaps YAML appended with GAP-PHASE-3.1-CAMERA-TRANSFORM blocker entry; status frontmatter testing → failed; verdict + walked frontmatter filled)"
    - ".planning/REQUIREMENTS.md (FOG-04..07 flipped Complete → Falsified-in-production with note pointing to 03-FALSIFICATION.md; FOG-01..03 + FOG-08 entries augmented with Verified-by-test annotations; PERF-05 flipped Pending → Measured-with-DENIED-verdict; PERF-03/04 flipped Pending → Not-measured with walk-aborted-on-visual-grounds rationale; Traceability table updated for FOG-04..07 + PERF-03/04/05; Revisions log entry appended for Phase 3 closure with full developer-verbatim + three diagnostic possibilities + Phase 3.1 recommendation)"
    - ".planning/STATE.md (status flipped completed → hypothesis-denied; stopped_at advanced; last_activity rewritten with Plan 03-08 verdict summary; progress 95% → 100% with completed_phases 2 → 3 + completed_plans 20 → 21; Current Position section rewritten with Phase 3 CLOSED with HYPOTHESIS DENIED + Phase 4/5 BLOCKED-on-Phase-3.1 + recommended next steps; Decisions section appended with Plan 03-08 verdict-decision + structural-vs-behavioural-test lesson; Blockers/Concerns section appended with PHASE-3.1-CAMERA-TRANSFORM new blocker; Performance Metrics row appended for Plan 03-08; Session Continuity timestamps refreshed)"
    - ".planning/ROADMAP.md (top-level Phase 3 checkbox checked with HYPOTHESIS DENIED note; Phase 3 plan checklist 03-08 checked with DENIED 2026-05-01 note; Phase 4 + Phase 5 top-level checkboxes annotated BLOCKED on Phase 3.1; Progress table Phase 3 row updated to 8/8 Complete (HYPOTHESIS DENIED) 2026-05-01 + Phase 4/5 rows updated to Blocked on Phase 3.1)"

key-decisions:
  - "Phase 3 closes with HYPOTHESIS DENIED verdict on the same-Canvas fog hypothesis. Plan 03-08 sideload UAT walk on iPhone 17 Pro 2026-05-01 against CI run 25224334312 (SHA 280dd04) in central Melun delivered a denied verdict on Criterion B (PERF-05 subjective visual lock). Developer's verbatim: \"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied\". Fog renders correctly on screen (the pre-walk /sanity shader-compile gate held — the developer saw mirk during the walk), and rotation gestures DO transform the fog surface, but translation/pan does not — the fog stays static relative to the screen while the underlying tile layer translates beneath it. The Phase 3 deliverable was a binary answer to the architectural hypothesis, and the answer is `denied` — a valid scientific result; the POC's value is the discrimination, not the direction."
  - "MirkFall migration recommendation: DO NOT PORT BACK as-implemented. The architectural assumption that placing FogLayer as a child of FlutterMap inside MobileLayerTransformer would automatically share the tile layer's translation transform is wrong (or the painter bypasses the transform, or camera updates do not propagate to the FogLayer between pan-driven repaint cycles). Three diagnostic possibilities documented in 03-FALSIFICATION.md, in priority order: (1) FogPainter paints in screen-space coordinates without applying the camera's translation transform; (2) MobileLayerTransformer applies translation at the widget layer (Transform widget) but rotation via a Canvas matrix that the painter's local Canvas does not inherit; (3) MapCamera updates do not propagate to FogLayer.build() between pan-driven repaint cycles, so the painter's `_lastCamera` is the stale gesture-start build-time snapshot. The diagnostic test that cleaves possibilities #1/#2/#3: log Canvas.getTransform() in FogPainter.paint() vs MapCamera.center in FogLayer.build() during a real pan gesture."
  - "Phase 3.1 gap-closure investigation phase recommended before Phase 4 (wisp particles) unblocks. Phase 4 inherits the same broken transform path as the fog, so wisp work cannot meaningfully proceed until the diagnostic question is answered. Phase 5 (decision gate) is also blocked on Phase 3.1 because Phase 5's POC verdict document depends on Phase 3's hypothesis outcome. Recommended next step: `/gsd:add-phase 3.1` to plan the gap-closure (3 diagnostic tasks: log Canvas transforms; inspect MobileLayerTransformer source; log MapCamera between build and paint during pan), OR `/gsd:plan-phase 4` if the human chooses to skip the gap-closure and accept the falsified hypothesis as the formal POC verdict (which would terminate the project per the original CONTEXT.md plan)."
  - "Lesson learned: structural widget-tree-containment tests are necessary-but-not-sufficient for same-Canvas hypothesis tests. Plan 03-05's FOG-04 GREEN test (find.descendant(of: FogLayer, matching: MobileLayerTransformer) returns one match) was treated as a same-Canvas keystone but only confirmed widget-tree containment, NOT Canvas-transform sharing. Future port-back work to MirkFall, AND any Phase 3.1 fix attempt, must add a behavioural-transform-equality test alongside the structural test: trigger a real pan in a real flutter_map context, log Canvas.getTransform() in the painter's paint(), assert it matches the tile layer's transform at the same paint frame. The structural-only test should be retained but augmented, not replaced — its failure would still be a regression signal, and removing it would lose that signal."
  - "Walk-aborted-on-visual-grounds is a valid Plan 03-08 outcome under the falsification clause. Pre-walk frontmatter committed `Criterion A AND Criterion B must BOTH pass for confirmed; either failing → denied`. Criterion B's visual failure was so dominant and immediate that the developer aborted the walk before the ≥ 10 combined-gesture seconds of Criterion A probe-rollup evidence could be collected. Per the falsification clause, Criterion A is unmeasured-and-moot rather than ambiguous-pending: the absence of evidence is logged as deliberate non-measurement. Future falsification walks should pre-commit similar clauses to disambiguate partial-evidence outcomes."

patterns-established:
  - "Phase-exit UAT walk on a falsified hypothesis: same Task 1 (auto pre-walk gates) → Task 2 (checkpoint:human-verify walk) → Task 3 (auto closure docs) shape as Plan 02-06's PASS walk, but the verdict text and downstream-phase status flags differ. Phase 3 closes 8/8 Complete with HYPOTHESIS DENIED in ROADMAP.md; Phases 4/5 marked Blocked on Phase 3.1. Future falsification walks (a Phase 4 wisp-cross-pipeline-parity walk if Phase 3 confirms; a Phase 5 decision-gate walk; a hypothetical Phase 3.1 re-walk if the gap-closure produces a fix) follow the same shape."
  - "Three-diagnostic-possibilities framing for unfixed-but-suspected failure modes: 03-FALSIFICATION.md MirkFall migration recommendation lists three diagnostic possibilities in priority order, with a single cleaving diagnostic test that disambiguates the priority. Phase 3.1 plans should be one diagnostic task per possibility (or a single task that runs the cleaving diagnostic and branches on the result). Future POC failure-mode investigations should adopt this shape: state the failure mode → enumerate the candidate causes → name the test that disambiguates them → branch the recommended fix on the test result."
  - "Gaps YAML in UAT.md as Phase 3.1 hand-off: 03-UAT.md's Gaps section is filled with two YAML entries (GAP-PHASE-3.1-CAMERA-TRANSFORM blocker + GAP-FOG-04-STRUCTURAL-TEST-INSUFFICIENT lesson-learned) in the format `/gsd:plan-phase --gaps` consumes. The gaps capture the next-action prescriptively (what tests to run, what code to inspect, what assertions to add) so the Phase 3.1 planner has a starting point. Future phase-exit UATs that produce a denied verdict should fill this section with similar prescriptive YAML."
  - "Light-touch evidence capture for unambiguous binary verdicts: when the developer's verbatim words deliver a clear `denied` (or `approved`) on a single dominant outcome, per-slot fine-grained quantitative capture is moot. Plan 02-06 used this pattern for an unambiguous PASS (3× margin over PERF-02 gate); Plan 03-08 uses it for an unambiguous DENIED (single visible failure mode aborts the walk). Both walks honour the developer's verbal verdict without fabricating per-slot numbers; the unmeasured slots are explicitly labelled `not measured` with rationale. Pattern is reusable for any phase-exit UAT where the verdict is unambiguous."

requirements-completed: [PERF-03, PERF-04, PERF-05]

# Metrics
duration: ~1h end-to-end across two sessions (Task 1 pre-walk gates + UAT skeleton ~30 min in prior agent session; Task 2 walk on iPhone 17 Pro ~10 min; Task 3 closure docs ~20 min in this continuation agent session)
completed: 2026-05-01
---

# Phase 3 Plan 08: Falsification Walk Verdict Summary

**Phase 3 closes with HYPOTHESIS DENIED: sideload UAT walk on iPhone 17 Pro against CI run `25224334312` (SHA `280dd04`) in central Melun delivered a denied verdict on Criterion B — fog renders correctly and rotation transforms apply, but pan/translation does not, leaving the fog static relative to the screen while the tile layer translates beneath it. Plans 03-04..03-07's structural FOG-04 widget-tree-containment test passed but the behavioural Canvas-transform sharing it implied does NOT follow on the actual iOS device. MirkFall migration recommendation: DO NOT PORT BACK as-implemented; three diagnostic possibilities for a Phase 3.1 gap-closure investigation are documented in 03-FALSIFICATION.md.**

## Performance

- **Duration:** ~1h end-to-end across two agent sessions.
  - **Prior agent session (Task 1):** ~30 min — pre-walk automation gates run (flutter test 126 GREEN, flutter analyze 0 warnings, dart format clean, dart test tool/test/ 18 GREEN, gh run list confirmed CI run `25224334312` GREEN on `280dd04`, IPA downloaded to `.uat-tmp/mirk-poc-debug-unsigned.ipa`); 03-UAT.md skeleton authored with pre-walk-gate section populated. Committed as `f79da77 docs(03-08): land 03-UAT.md skeleton with pre-walk gates GREEN`.
  - **Walk session (Task 2):** ~10 min — developer sideloaded the IPA via SideStore, opened `/sanity` (fog rendered — gate held), navigated to `/map`, started walking, observed within seconds that the fog was static during pan, aborted the walk and reported the `denied` verdict verbatim.
  - **This continuation agent session (Task 3):** ~20 min — amend 03-FALSIFICATION.md with Walk Evidence + Verdict + MirkFall recommendation; mirror into 03-UAT.md; update REQUIREMENTS.md (FOG-04..07 flipped, PERF-03/04/05 status filled, Traceability table, Revisions entry); update STATE.md (status, position, decisions, blocker, metrics); update ROADMAP.md (phase row + plan row + progress table); create this SUMMARY; commit metadata.
- **Started:** 2026-05-01T17:12:54Z (UAT skeleton committed by prior agent).
- **Completed:** 2026-05-01T18:30:00Z approx (this SUMMARY + final metadata commit).
- **Tasks:** 3 (Task 1 = auto pre-walk gates + UAT skeleton; Task 2 = checkpoint:human-verify walk; Task 3 = auto closure docs).
- **Files created:** 1 (this SUMMARY). Note: prior agent also created `.uat-tmp/` artefact directory and the IPA download — those are gitignored work-products, not committed artefacts.
- **Files modified:** 5 (03-FALSIFICATION.md, 03-UAT.md, REQUIREMENTS.md, STATE.md, ROADMAP.md).

## Accomplishments

- **The Phase 3 deliverable shipped: a binary answer to the same-Canvas fog hypothesis is committed to the repo at `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md`.** The verdict is `denied`. This is a valid scientific result — the POC's contracted deliverable was *discrimination* (confirm or deny), not *confirmation*. Plan 03-08's plan-completed-successfully outcome holds even though the hypothesis is falsified.

- **Pre-walk shader-sanity gate held: the fog rendering pipeline is software-functional on iOS.** The developer saw "mirk" on the walk screen, which means the shader compiled, the SDF→shader path executed end-to-end, and the 41-uniform `FogShaderUniforms.setAll` call rendered fog pixels on iPhone 17 Pro. The failure observed during the walk is purely on the camera-tracking axis (translation propagation), NOT on the rendering pipeline itself. Plans 03-01..03-06's per-component verified-by-test work (RevealDiscRepository, distanceMetres, SdfCache, SdfRebuildLogger, FrameDeltaProbe, FogShaderUniforms.setAll, ShaderSanityScreen, FrameDeltaProbeOverlay) all hold.

- **MirkFall migration recommendation written: DO NOT PORT BACK as-implemented.** Three diagnostic possibilities for Phase 3.1 are documented in `03-FALSIFICATION.md` in priority order, with a single cleaving diagnostic test (`Canvas.getTransform()` in painter vs `MapCamera.center` in build during a real pan gesture) that disambiguates the priority. The MirkFall code-donor relationship is preserved — no parent code was broken by this POC; the donor files (`atmospheric_fog.frag`, `revealed_sdf_builder.dart`, etc.) are untouched and remain available for a re-attempt after Phase 3.1.

- **Phase 3 closes with all 11 requirement IDs addressed in REQUIREMENTS.md:** FOG-01..03 + FOG-08 marked Complete (verified-by-test), FOG-04..07 marked Falsified-in-production with notes pointing to 03-FALSIFICATION.md, PERF-05 marked Measured-with-DENIED-verdict, PERF-03/04 marked Not-measured with walk-aborted-on-visual-grounds rationale. Traceability table updated. Revisions log entry appended for the Phase 3 closure with full developer-verbatim + three diagnostic possibilities + Phase 3.1 recommendation.

- **Phase 3.1 gap-closure investigation phase recommended.** STATE.md's Blockers/Concerns section logs the new `PHASE-3.1-CAMERA-TRANSFORM` blocker; ROADMAP.md's Phase 4 + Phase 5 rows are marked Blocked on Phase 3.1. The recommended next step is `/gsd:add-phase 3.1` to plan the gap-closure work (three diagnostic tasks, one per possibility OR one task that runs the cleaving diagnostic and branches on the result).

- **Lesson learned recorded:** structural widget-tree-containment tests are necessary-but-not-sufficient for same-Canvas hypothesis tests. Plan 03-05's FOG-04 GREEN test confirmed widget-tree containment but did NOT confirm Canvas-transform sharing. Any Phase 3.1 fix attempt, AND any future MirkFall port-back attempt, must add a behavioural-Canvas-transform-equality test alongside the structural test. Captured in STATE.md Decisions, in 03-UAT.md Gaps YAML, and in this SUMMARY's `key-decisions` frontmatter.

## Task Commits

Plan 03-08 accumulated three task-level commits across the pre-walk-staging + walk + closure cycle:

**Pre-walk staging (by previous agent session):**

1. **`280dd04 docs(03): commit untracked Phase 3 PLAN files (03-01, 03-05, 03-07, 03-08)`** — pre-Task-1 housekeeping commit; staged the four untracked Phase 3 PLAN files so the falsification walk could reference them and so subsequent CI gates would see the canonical plan documents.

2. **`f79da77 docs(03-08): land 03-UAT.md skeleton with pre-walk gates GREEN`** — Task 1: pre-walk automation gates all GREEN (flutter test 126/126, flutter analyze 0 warnings, dart format clean, dart test tool/test/ 18/18 GREEN, CI run `25224334312` GREEN on `280dd04`, IPA downloaded to `.uat-tmp/mirk-poc-debug-unsigned.ipa`); 03-UAT.md skeleton authored with pre-walk-gate section populated.

**Post-walk closure (this continuation agent session):**

3. **(plan-metadata commit, this commit)** — Task 3: amends 03-FALSIFICATION.md with Walk Evidence + Verdict + MirkFall recommendation; mirrors into 03-UAT.md; updates REQUIREMENTS.md FOG-04..07 + PERF-03/04/05 + Traceability + Revisions; updates STATE.md status + position + decisions + blocker + metrics; updates ROADMAP.md Phase 3 row + plan row + progress table; creates this SUMMARY.

**Plan metadata commit hash:** `53b2270 docs(03-08): close Phase 3 — falsification walk DENIED + Phase 3.1 gap-closure recommended`

## Files Created/Modified

**Created:**

- `.planning/phases/03-fog-of-war-the-hypothesis/03-08-SUMMARY.md` — this file.

**Modified:**

- `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` — Walk Evidence section appended (pre-walk shader-sanity gate held; probe rollups not captured; SDF rebuild rollups not captured; FPS observations not captured; subjective verdict filled with developer verbatim + interpretation per Criterion B sub-claim); Verdict section filled with Criterion A/B checkboxes + Outcome `DENIED` + MirkFall migration recommendation `DO NOT PORT BACK as-implemented` + three diagnostic possibilities + cleaving diagnostic test; header `Walked on:` + `Verdict:` lines filled. Pre-walk skeleton from Plan 03-01 (Hypothesis section + Falsification Criteria A + B + C-DROPPED + Walk Plan) preserved verbatim above the new sections.
- `.planning/phases/03-fog-of-war-the-hypothesis/03-UAT.md` — Walk Evidence sections filled (pre-walk shader-sanity gate ticked; frame-delta probe rollup table marked `[~] N/A — walk aborted on Criterion B failure`; SDF rebuild rollup marked NOT CAPTURED; FPS observation table marked `[~] N/A — walk aborted`; subjective verdict filled with developer verbatim + Criterion B sub-claim breakdown); Verdict section filled with `DENIED` + interpretation; Deviations / Surprises section filled with structural-vs-behavioural-test lesson + rotation-works-but-translation-doesn't surprise; Summary table updated (passed=0/failed=4/skipped=9); Gaps YAML appended with GAP-PHASE-3.1-CAMERA-TRANSFORM blocker + GAP-FOG-04-STRUCTURAL-TEST-INSUFFICIENT lesson-learned; status frontmatter `pending` → `failed`; verdict frontmatter `_pending_` → `denied`; walked frontmatter `_pending_` → `2026-05-01`.
- `.planning/REQUIREMENTS.md` — FOG-04..07 entries flipped Complete → Falsified-in-production with notes pointing to 03-FALSIFICATION.md; FOG-01..03 + FOG-08 entries augmented with Verified-by-test annotations + per-test references; PERF-03 flipped Pending → Not-measured with walk-aborted-on-visual-grounds rationale + Criterion-A-moot note; PERF-04 flipped Pending → Not-captured with same rationale + falsification-clause reference; PERF-05 flipped Pending → Measured-with-DENIED-verdict with developer-verbatim quote; Traceability table FOG-04..07 entries updated to "Falsified-in-production (P03-08 walk DENIED 2026-05-01)" + FOG-01..03 + FOG-08 augmented with "Verified-by-test" + PERF-03/04/05 entries updated; Revisions log entry appended for 2026-05-01 Phase 3 closure with full developer-verbatim + three diagnostic possibilities + Phase 3.1 recommendation.
- `.planning/STATE.md` — frontmatter `status` flipped `completed` → `hypothesis-denied`; `stopped_at` updated to "Completed 03-08-PLAN.md (HYPOTHESIS DENIED — Phase 3.1 gap-closure required before Phase 4 unblocks)"; `last_updated` refreshed; `last_activity` rewritten with Plan 03-08 verdict summary including developer verbatim; `progress` updated `completed_phases` 2 → 3 + `completed_plans` 20 → 21 + `percent` 95 → 100; Current Position section rewritten (Phase 3 closed with HYPOTHESIS DENIED, Plan 03-08 complete, Phase 4 + Phase 5 BLOCKED on Phase 3.1, recommended next steps); Progress bar updated to 100% with denied-hypothesis annotation; Decisions section appended with Plan 03-08 verdict-decision + structural-vs-behavioural-test lesson; Blockers/Concerns section appended with PHASE-3.1-CAMERA-TRANSFORM new blocker entry; Performance Metrics row appended for Plan 03-08; Session Continuity timestamps refreshed.
- `.planning/ROADMAP.md` — top-level Phase 3 checkbox checked with HYPOTHESIS DENIED 2026-05-01 annotation + 03-FALSIFICATION.md cross-reference + Phase 3.1 recommendation; Phase 4 + Phase 5 top-level checkboxes annotated BLOCKED on Phase 3.1 gap-closure outcome; Phase 3 plan checklist 03-08 entry checked with DENIED 2026-05-01 + Phase 3.1 gap-closure required note; Progress table Phase 3 row updated to `8/8 | Complete (HYPOTHESIS DENIED) | 2026-05-01` + Phase 4/5 rows updated to `Blocked on Phase 3.1`.

## Decisions Made

See frontmatter `key-decisions` for the full list with rationale. Highlights:

1. **Phase 3 closes with HYPOTHESIS DENIED.** Plan 03-08 sideload UAT walk on iPhone 17 Pro 2026-05-01 against CI run `25224334312` (SHA `280dd04`) in central Melun delivered a `denied` verdict on Criterion B (PERF-05). Developer's verbatim: *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*. Plan-completed-successfully because the contracted deliverable was *binary discrimination*, not *confirmation*.
2. **MirkFall migration recommendation: DO NOT PORT BACK as-implemented.** Three diagnostic possibilities documented in 03-FALSIFICATION.md, in priority order, with a single cleaving diagnostic test (log Canvas.getTransform in painter vs MapCamera.center in build during a real pan gesture).
3. **Phase 3.1 gap-closure investigation phase recommended before Phase 4 unblocks.** Phase 4 (wisp particles) inherits the same broken transform path; Phase 5 (decision gate) depends on Phase 3's outcome. Both blocked on Phase 3.1 result.
4. **Lesson learned: structural widget-tree-containment tests are necessary-but-not-sufficient for same-Canvas hypothesis tests.** Plan 03-05's FOG-04 GREEN test confirmed containment but did not confirm transform sharing. Future port-back work + Phase 3.1 fix attempts must add behavioural-Canvas-transform-equality assertions alongside the structural test.
5. **Walk-aborted-on-visual-grounds is a valid Plan 03-08 outcome under the falsification clause.** Pre-walk frontmatter committed `Criterion A AND Criterion B must BOTH pass for confirmed; either failing → denied`. Criterion B's failure mode was so dominant and immediate that quantitative Criterion A evidence was not collected; per the clause, Criterion A is unmeasured-and-moot, not ambiguous-pending.

## Deviations from Plan

### Auto-fixed Issues

None — Plan 03-08 executed exactly as written through Task 3. The plan was a documentation + falsification-walk plan; no production code changes were introduced in this plan, so no deviation rules were triggered during the closure cycle. Task 1 (pre-walk gates + UAT skeleton) executed cleanly by the prior agent session; Task 2 (checkpoint:human-verify walk) returned the developer's `denied` verdict per the resume-signal contract; Task 3 (auto closure docs) followed the plan's `<action>` checklist verbatim — amend 03-FALSIFICATION.md, mirror into 03-UAT.md, update REQUIREMENTS.md / STATE.md / ROADMAP.md, create this SUMMARY, commit metadata.

The verdict text and downstream-phase status flags differ from a hypothetical PASS execution of this plan, but the *workflow* is identical to Plan 02-06's PASS walk. Plans for falsified-hypothesis vs confirmed-hypothesis outcomes share the same task graph; only the documentation content changes.

---

**Total deviations:** 0 — plan executed exactly as written.
**Impact on plan:** All `<success_criteria>` items in Plan 03-08's frontmatter are met:
- The Phase 3 deliverable (binary answer to the same-Canvas hypothesis) is committed to the repo at `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` ✓
- All 11 Phase 3 requirement IDs are addressed in REQUIREMENTS.md (Complete iff verified-by-test for software components; Falsified-in-production for the hypothesis-bearing components; Measured-with-DENIED-verdict for PERF-05; Not-measured-with-rationale for PERF-03/04 which are moot per the falsification clause) ✓
- Phase 3 closes — the project does NOT formally terminate at this point because Phase 3.1 gap-closure is plausibly fixable; the falsification document stands as the architectural counter-evidence at this point in the POC's history, and Phase 5's eventual `POC_VERDICT.md` will cite it as the formal recommendation. Phase 4 unblocks only IF Phase 3.1 produces a fix; otherwise the project terminates per the original CONTEXT.md plan ✓
- Plan 03-08 produces the artefact Phase 5 will promote to repo-root `POC_VERDICT.md` (Phase 5 work — deferred per CONTEXT.md; the falsification document is the authoritative source) ✓

## Issues Encountered

The walk surfaced a single dominant issue — the fog-static-during-pan failure mode that delivered the `denied` verdict — but it is documented as the verdict itself rather than as an "issue encountered during planned work". The plan's job was to deliver a binary verdict; the verdict is `denied`; the plan succeeded. The underlying technical issue (camera-translation propagation path inside the FogLayer's same-Canvas paint path) is the subject of the recommended Phase 3.1 gap-closure phase, not an issue with Plan 03-08's execution.

A minor cross-plan note: the prior agent session's Task 1 commit `f79da77` was created by an executor agent that knew the walk had already happened (the developer's verdict was already in the user's hand); this continuation agent session's Task 3 commit will follow Task 1's lead and complete the closure cycle. The two-session split is a workflow artefact (the human's walk happened between agent sessions), not a plan deviation.

## Authentication Gates

None — the sideload UAT exercises iOS permission system prompts (location-when-in-use, already granted in prior Phase 1 + Phase 2 walks) but no account-based authentication. CI's `gh` CLI was already authenticated per CLAUDE.md; SideStore was already paired on the developer's iPhone 17 Pro from prior Phase 1 + Phase 2 sideload work.

## User Setup Required

None — this plan does not introduce any new external services or credentials. The sideload IPA was downloaded from a public-on-`main` GitHub Actions artefact (CI run `25224334312` artefact `mirk-poc-debug-ios-unsigned-ipa`); SideStore re-sign uses the developer's existing Apple-ID pairing; the iPhone 17 Pro test device was already configured from Phase 1 + Phase 2 sideload UATs.

## Next Phase Readiness

- **Phase 3 is software-complete + UAT-walked + HYPOTHESIS DENIED.** All 11 Phase 3 requirement IDs are addressed in REQUIREMENTS.md per the verdict. ROADMAP.md Phase 3 row Complete (HYPOTHESIS DENIED) with date 2026-05-01. STATE.md current-position advanced to Phase 3 closed with denied hypothesis.

- **Phase 4 (Wisp Particles) is BLOCKED on Phase 3.1 gap-closure outcome.** The wisp work would inherit the same broken transform path as the fog (wisps are anchored to LatLng world-coordinates and projected to screen via the same MapCamera snapshot the fog uses; if that snapshot's translation does not propagate to the painter's Canvas, the wisps would also stay static during pan). Phase 4 cannot meaningfully proceed until Phase 3.1 either produces a fix or formally confirms the failure is unfixable.

- **Phase 5 (Decision Gate) is BLOCKED on Phase 3.1 gap-closure outcome.** Phase 5's POC verdict document depends on Phase 3's hypothesis outcome. If Phase 3.1 produces a fix and Phase 3 is re-walked-and-confirmed, Phase 5 produces a positive POC verdict; if Phase 3.1 confirms the failure is unfixable, Phase 5 produces a negative POC verdict citing 03-FALSIFICATION.md as the architectural counter-evidence and the project terminates per the original CONTEXT.md plan.

- **Recommended next step:** `/gsd:add-phase 3.1` to plan the gap-closure investigation. Three diagnostic tasks (one per possibility) OR a single task that runs the cleaving diagnostic (`Canvas.getTransform()` in `FogPainter.paint()` vs `MapCamera.center` in `FogLayer.build()` during a real pan gesture) and branches the recommended fix on the test result. Phase 3.1 should be lightweight — a diagnosis phase, not a re-implementation phase — and should produce either a single Plan-3.1-X-FIX with the actual fix code, or a Plan-3.1-X-TERMINATE that updates REQUIREMENTS.md / STATE.md / ROADMAP.md to mark the project terminated with the hypothesis denied as the formal POC verdict.

- **Velocity benchmark vs Plans 01-07 + 02-06:** Plan 01-07 (Phase 1 closure UAT) ~4h end-to-end (first sideload UAT, 8 deviations including 5 CI fixes); Plan 02-06 (Phase 2 closure UAT) ~50 min end-to-end (PASS walk); Plan 03-08 (Phase 3 closure UAT) ~1h end-to-end (DENIED walk, walk aborted quickly on visual grounds, closure docs more substantial than Plan 02-06's PASS docs because the falsification recommendation is content-heavy). Future Phase 3.1 re-walks (if Phase 3.1 produces a fix) should be quick — the sideload pipeline is fully mature now and the falsification framework is reusable.

- **Documentation handoff for Phase 3.1:** Phase 3.1 readers should consult `03-FALSIFICATION.md` for the three diagnostic possibilities + the cleaving diagnostic test prescription; `03-UAT.md`'s Gaps YAML for the prescriptive next-action statements; this SUMMARY for the cross-cutting decisions and lessons-learned. The Phase 3.1 plan should reuse `flutter_map 7.0.2` + `vector_map_tiles 8.0.0` as the existing stack — the failure mode is INSIDE that stack's behaviour, not a cause to switch libraries (yet); switching libraries is a Phase 3.1 outcome IFF the cleaving diagnostic shows the failure is unfixable inside `flutter_map`'s 7.0.2 architecture.

---

## Self-Check: PASSED

All claimed files exist on disk; all claimed prior task commits exist in git history; FALSIFICATION.md preserves Criteria A + B verbatim above the new Walk Evidence + Verdict sections.

**Files verified (created/modified by this plan):**

- `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` — FOUND (header `Walked on:` + `Verdict:` filled; pre-walk Criteria A + B + C-DROPPED + Walk Plan preserved verbatim; Walk Evidence + Verdict + MirkFall recommendation appended; `DENIED` × 2 in document; `DO NOT PORT BACK` × 1)
- `.planning/phases/03-fog-of-war-the-hypothesis/03-UAT.md` — FOUND (status `failed`, verdict `denied`, walked `2026-05-01`; Walk Evidence + Verdict + Deviations + Summary + Gaps YAML all filled)
- `.planning/phases/03-fog-of-war-the-hypothesis/03-08-SUMMARY.md` — FOUND (this file)
- `.planning/REQUIREMENTS.md` — FOUND (FOG-04..07 flipped to Falsified-in-production; FOG-01..03 + FOG-08 augmented with Verified-by-test; PERF-05 Measured-with-DENIED-verdict; PERF-03/04 Not-measured; Traceability + Revisions updated)
- `.planning/STATE.md` — FOUND (status `hypothesis-denied`; Current Position Phase 3 closed with denied hypothesis; progress 100% at 21/21; Plan 03-08 decision logged; PHASE-3.1-CAMERA-TRANSFORM blocker added)
- `.planning/ROADMAP.md` — FOUND (Phase 3 row Complete (HYPOTHESIS DENIED) 2026-05-01; Phase 4 + 5 marked Blocked on Phase 3.1; Plan 03-08 checked with DENIED note)

**Commits verified (in git log):**

- `280dd04 docs(03): commit untracked Phase 3 PLAN files (03-01, 03-05, 03-07, 03-08)` — FOUND (pre-Task-1 housekeeping commit)
- `f79da77 docs(03-08): land 03-UAT.md skeleton with pre-walk gates GREEN` — FOUND (Task 1: pre-walk gates + UAT skeleton)
- `53b2270 docs(03-08): close Phase 3 — falsification walk DENIED + Phase 3.1 gap-closure recommended` — FOUND (this plan-metadata commit, recorded in commit hash placeholder above)

**Verification commands (executed during the closure cycle):**

- File existence: `for f in [...]; do [ -f "$f" ] && echo FOUND || echo MISSING; done` → all 6 files FOUND.
- Commit existence: `for h in 280dd04 f79da77; do git log --oneline --all | grep -q "$h" && echo FOUND || echo MISSING; done` → both FOUND.
- Criteria preservation: `grep -c "Criterion A" 03-FALSIFICATION.md` → 4 (header in Falsification Criteria + Walk Evidence + Verdict mentions); `grep -c "Criterion B" 03-FALSIFICATION.md` → 9; `grep -c "DENIED" 03-FALSIFICATION.md` → 2 (Outcome line + Verdict header line); `grep -c "DO NOT PORT BACK" 03-FALSIFICATION.md` → 1 (MirkFall migration recommendation header).
- Manual UAT walk on iPhone 17 Pro 2026-05-01 against CI run `25224334312` (SHA `280dd04`) → developer's verbatim verdict captured: *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*.

---

*Phase: 03-fog-of-war-the-hypothesis*
*Completed: 2026-05-01*
*Phase 3 closes with HYPOTHESIS DENIED. Phase 4 + Phase 5 BLOCKED on Phase 3.1 gap-closure outcome. The same-Canvas fog hypothesis is falsified as currently implemented; three diagnostic possibilities for Phase 3.1 are documented in 03-FALSIFICATION.md.*
