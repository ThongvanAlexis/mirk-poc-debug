# Phase 5: Decision Gate - Research

**Researched:** 2026-05-05
**Domain:** Verdict authoring + repository hardening + sideload UAT closure walks (no new feature implementation)
**Confidence:** HIGH (codebase-internal); MEDIUM (Pixel 4a Adreno 618 external behaviour)

## Summary

Phase 5 closes the POC. It produces TWO repo-root artefacts (`VERDICT.md` + `PORTBACK.md`), runs ONE final iPhone 17 Pro sideload walk that re-confirms Phase 3 fog + Phase 4 wisp criteria AND closes Phase 4's deferred Criterion E (C3' extreme-distance) + Criterion G (Mail-share grep-correlation), runs ONE Pixel 4a (Adreno 618) walk for the cross-platform sanity reference (PERF-06 — informational soft criterion), and re-stamps `DEPENDENCIES.md` audit dates to 2026-05-05. NO production-fog code changes; NO new CI gates (the existing 7-gate `.github/workflows/ci.yml` already enforces every hardening rule the success criteria mention). The verdict is empirically pre-determined: Phase 3.1 Walk #6 + Phase 4 Walk #1 already established `PORT BACK with the layered Phase 3.1 + Phase 4 fix bundle + caveats`; Phase 5 formalises it as a committed artefact. The work is doc authoring, evidence retrieval from existing JSONL streams, two sideload sessions, and a 15-row audit-date refresh.

**Primary recommendation:** Plan Phase 5 as 4-5 plans: (1) DEPENDENCIES.md re-audit + ABI/invariants doc-prep wave-0; (2) iPhone Walk #1 with Mail-share + falsification doc; (3) Pixel 4a Walk #1 with Mail-share + falsification doc; (4) `VERDICT.md` + `PORTBACK.md` authoring; (5) STATE/ROADMAP cascade + final commit. NO code-side production-fog changes. NO new CI gates. NO new requirements beyond closing PERF-06.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Verdict + port-back artefacts:**

- **Two separate documents at repo root** — `VERDICT.md` + `PORTBACK.md`. Distinct audiences (verdict reader vs MirkFall porter) get distinct docs.
- **`VERDICT.md` location: repo root.** Per ROADMAP wording ("verdict document is committed to the repo as the final artefact"). Discoverable for someone landing on the repo. Consistent with `LICENSE` / `DEPENDENCIES.md` / `CLAUDE.md` root-level POC artefacts.
- **`VERDICT.md` content:**
  - Formal verdict line: `HYPOTHESIS CONFIRMED-AFTER-FIX (Phase 3.1 Walk #6 + Phase 4 Walk #1 + Phase 5 closure walks)`.
  - MirkFall recommendation: `PORT BACK with the layered fix bundle` + itemized caveats list.
  - Phase-by-phase evidence summary: short paragraph per phase summarizing the falsification outcome (Phase 3 DENIED → reversed; Phase 3.1 CONFIRMED-AFTER-FIX after 6 iterations; Phase 4 CONFIRMED-AFTER-FIX FULL on Walk #1; Phase 5 closure walks).
  - **Inline-summarized + linked** evidence: each phase paragraph includes a link to the canonical `FALSIFICATION-N.md` doc for the full receipts. VERDICT.md is standalone-readable; porter clicks through if they want frame-delta numbers and verbatim verdicts.
  - Version-stamping: Flutter `3.41.7` (CI-pinned), iPhone 17 Pro (primary platform), Pixel 4a Adreno 618 (cross-platform reference), commit SHA at Phase 5 close.
  - Pixel 4a quantitative summary (~1 paragraph or ~5-line table): `medianMs / p95Ms / maxMs` from Mail-shared rollups + visual lock observation + crash status.
  - Caveats list (see "Caveat policy" below).
- **`PORTBACK.md` content: full surgical playbook.** Porter reads it top-to-bottom and ports without round-tripping through the .planning/ tree:
  - **File-by-file copy list** with target paths in MirkFall: `assets/shaders/atmospheric_fog.frag`, `lib/presentation/widgets/fog_layer.dart`, `lib/infrastructure/mirk/fog_transform_logger.dart`, `lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart`, `lib/infrastructure/mirk/wisp/wisp_particle_system.dart` + `wisp_particle.dart`, `lib/infrastructure/mirk/wisp/wisp_transform_logger.dart`, `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart`, `lib/infrastructure/mirk/frame_delta_probe.dart` + overlay, `lib/infrastructure/mirk/sdf/sdf_rebuild_logger.dart`, `lib/infrastructure/location/walk_simulator.dart`, etc. Each row notes verbatim-port vs adapt-on-port.
  - **ABI extensions table:** `uPixelOrigin` slot 3..4, `uZoomScale` slot 41, `kPocFogReferenceZoom = 13.0`. Total float slots: 42 (was 41 pre-FOG-19). FOG-17a CPU decomposition formula: `pixelOrigin.toDouble() % kPocFogIntegerWrapPeriodPx` keeps shader input bounded under 1537 raw px regardless of zoom (1536 = 4 × 384 = `kPocFogIntegerWrapPeriodPx % kPocFogNoiseTilePx == 0`).
  - **Locked invariants** (porter MUST preserve these): FOG-07 single `MapCamera.of(context)` snapshot per `FogLayer.build()`; FOG-12 single `canvas.getTransform()` read per paint; FOG-13 `canvas.translate(-canvasOffset)` symmetric compensation; UX-02 rotation disabled or FOG-16 path (b) full canvas-inverse-transform required to re-enable; dual-clock JSONL discipline (`Stopwatch.elapsedMicroseconds` for math; `DateTime.now()` only for epochSecond rollup tag); 1-Hz wall-clock-aligned rollup cadence across all `infrastructure.mirk.*` loggers; world-anchored noise sampling (`worldPx = fragUv * uResolution + uPixelOrigin; noiseUv = worldPx / (kNoiseTilePx * uZoomScale)`); MIRL visual-identity preservation rule (CLAUDE.md `# MIRL solution`).
  - **Fix-bundle plan order** (apply in sequence): Plan 03.1-02 (3-line `_FogPainter.paint()` fix) → 03.1-04 (SHADER-MODULO-WRAP rename + per-fragment fract) → 03.1-05 (FOG-12 + PERF-08 + UX-01) → 03.1-07 (noise-tile-period mismatch B-3 fix) → 03.1-08 (FOG-13 fog-rect viewport-coverage symmetric compensation) → 03.1-10 (FOG-17 world-coord noise + FOG-17a CPU decomposition + UX-02 rotation disable) → 03.1-12 (FOG-18 eliminate FOG-17a integer-wrap-modulo + DEBUG-02 cameraConstraint removal) → 03.1-14 (FOG-19 C-b uZoomScale uniform). Then Phase 4: Plan 04-01..04-04 (wisp particle system + WispTransformLogger + `_FogPainter._renderWisps` integration).
  - **Four inline post-Plan-04-04 follow-ups** documented separately (NOT planned, NOT phases — direct commits): `41c8acd` `kPocMaxZoom` 15→20; `2613da8` `kPocInitialZoom` 13→19; `849a6e1` auto-recenter on first GPS fix + FAB lands at `kPocInitialZoom`; `eec9087` WalkSimulator + AppBar control + `fake_async` dev_dep promotion. MirkFall port-back inherits these as delta-commits onto the fix-bundle base.
  - **Adaptation notes**: donor's screen-px velocity / 18 px/s magnitude is wrong (the BUG-014 dimensional-mismatch trap); use POC's m/s + `LatLng` basis (`kMirkPocWispDriftMetersPerSecond = 1.5`). MapScreenServices DTO injection pattern. FOG-07 keystone test as CI gate. WispTransformLogger schema (per-paint observation captures: active count, mean age, LatLng bounds, screen-Offset bounds, spawn rate; 1-Hz JSONL rollups via `Logger('infrastructure.mirk.wisp')`).

**Final iPhone walk scope:**

- **Single comprehensive walk** covers all four objectives in one sideload session: (a) Phase 3 fog re-confirm baseline, (b) Phase 4 wisp re-confirm baseline, (c) C3' extreme-distance regime (~50–100 km pan from Melun) closing P4 Walk #1's deferred Criterion E, (d) post-walk Mail-share closing P4 Walk #1's deferred Criterion G. Targeted ~10–15 min of active interaction.
- **Mail-share required.** Closes P4 Walk #1's deferred Criterion G explicitly; quantitative PERF-07 numbers extracted from JSONL rollups (`infrastructure.mirk.frame_delta` + `infrastructure.mirk.fog_transform` + `infrastructure.mirk.sdf` + `infrastructure.mirk.wisp` streams) cited in VERDICT.md.
- **WalkSimulator drives synthetic GPS** for the wisp spawn axis. Phase 4 Walk #1 precedent (commit `eec9087`); same WalkSimulator at desk drives reproducible disc emergence so wisps spawn through the warmup gate + LRU cap regimes. No outdoor walking required.
- **Free-form session, developer judgment** for gesture regime — pans / zooms / recenter taps / sustained one-direction pan past city limits as the walk feels appropriate. Mail-shared JSONL rollups give post-walk quantitative reconstruction of which regimes were exercised; verbal verdict at session end provides the qualitative call. Consistent with Phase 3.1 "validate first, architect later" philosophy and Walks #4 / #6 / P4 Walk #1 verbal-decisive precedent.
- **Iteration policy carries forward:** no hard cap on walk count. If Walk #1 surfaces a residual issue, a Phase 5.1 inserted phase iterates (mirrors Phase 3.1 pattern). Default expectation per Phase 3.1 Walk #6 + P4 Walk #1 closure precedent: single-walk closure on iPhone.

**Pixel 4a walk shape (PERF-06 — informational, soft criterion):**

- **WalkSimulator at desk** drives the Pixel 4a too. Cross-platform consistency with iPhone walk methodology; no outdoor walking; reproducible drive shape. Pixel 4a's APK installed via `gh run download` + `adb install` (existing Phase 1+ workflow).
- **Mail-share required, same JSONL discipline as iPhone.** Quantitative Adreno 618 PERF-07 numbers on the record. Same `share_plus` flow; Android sharesheet presents Gmail / Drive / Files for transmission. Treats PERF-06 with the same rigor as iPhone PERF-07 despite the soft-criterion status.
- **Mirror iPhone walk regimes** including C3' extreme-distance (~50–100 km from Melun). Cross-platform parity for the fp32 precision question — if iPhone is clean at extreme distance, verify Pixel 4a's Adreno 618 behavior matches. Codifies cross-platform parity over PERF-06's "informational" framing.
- **VERDICT.md citation format: quantitative summary line.** One paragraph or ~5-line table: `Pixel 4a (Adreno 618, Android 13) — PERF-07 medianMs / p95Ms / maxMs from Mail-shared rollups + visual lock observation + crash status (none)`. Sufficient for the cross-platform-reference purpose without full evidence reproduction.

**Hardening + caveat policy:**

- **DEBUG-03 broken numbered shader: leave as documented known-defect.** Walk #6 stance carries forward. CLAUDE.md + ROADMAP already document it as `Complete with known defect; cleanup deferred indefinitely; debug-shader-only; no production impact`. VERDICT.md mentions it as a non-blocking caveat in the "Known caveats / inherited limitations" list. Zero hardening cost; honest about limitations; porter knows what they're getting.
- **WalkSimulator AppBar control: keep production-exposed.** POC convenience; same WalkSimulator drives the Phase 5 final walks (iPhone + Pixel 4a). MirkFall port-back inherits it as a debug helper for future regression hunts. Zero hardening cost; consistent with POC-ness. (POC ships only debug-flavor builds per ROADMAP CI: unsigned IPA + debug APK; production-flavor gating is a MirkFall-side concern at port-back time.)
- **DEPENDENCIES.md bulk re-audit with 2026-05-05 dates.** Re-walk every direct + transitive dependency: re-confirm license, re-grep for telemetry / network egress, re-check maintenance status, stamp current audit date. Defensible record for the porter. One plan of pure read-the-code work; CI freshness check stays green throughout.
- **Caveat policy: PORT BACK + itemized caveats list in VERDICT.md.** Recommendation = `PORT BACK with the layered fix bundle`. Inherited limitations explicitly enumerated:
  - **DEBUG-03** — numbered debug shader rendering broken (debug-only; no production impact; developer-waived at Walk #6).
  - **UX-02** — rotation disabled. Re-enabling requires landing FOG-16 path (b) full canvas-inverse-transform first to prevent the Walk #3 fog-coverage regression.
  - **In-memory disc storage** — POC stores discs in memory (PROJECT.md scope). MirkFall port-back inherits this; Drift / persistent storage is a MirkFall-side concern.
  - **Default basemap style only** — POC skips the MirkFall `Theme` object styling (`#f5f1e8` / `#a6c9df` / etc.). Theme restyling is a MirkFall-side port-back concern.
  - **iOS-primary, Android-secondary perf characterization** — PERF-07 thresholds validated on iPhone 17 Pro. Pixel 4a Adreno 618 numbers are informational reference; MirkFall's broader Android matrix needs separate validation.
  - **In-memory disc → SDF rebuild policy** — PERF-08 rebuild rate measured under POC's GPS-fix-driven disc emergence; MirkFall's larger disc volumes need separate validation.
  - **Walk methodology = sideload session at desk** (Phase 3.1 D1 + P4 Walk #1 + Phase 5 closure walks). MirkFall port-back may need physical-walk validation depending on its release-readiness criteria.

**Iteration policy (carry-forward, unchanged):**

- Plan-revise-walk loop. **No hard cap on walk count.** If Phase 5 walks surface a non-cosmetic issue (PERF-07 threshold breach, visual lock failure, crash), Phase 5 stays open and a Phase 5.1 inserted phase iterates. Verdict not authored until walks are clean. Default expectation per Phase 3.1 Walk #6 + P4 Walk #1 precedent: single-walk closure per platform.
- "Port back with caveats" is the default verdict shape. "Do not port back" requires a NEW falsification of the same-Canvas hypothesis (already CONFIRMED post Phase 3.1 + Phase 4) — extremely unlikely given the closure-walk evidence base.

**Locked invariants (carried forward — non-negotiable):**

- Same-Canvas hypothesis CONFIRMED-AFTER-FIX (Phase 3.1 Walk #6 + Phase 4 Walk #1).
- "Walk" = sideload session at desk; term `Walk #N` preserved for grep-tool compatibility with Walks #1–#6 + P4 Walk #1 session logs and FALSIFICATION docs.
- PERF-07 thresholds: `medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48` (NOT obsolete `≥ 30 fps` from ROADMAP — that's legacy text; PERF-07 is authoritative).
- UX-02 rotation disabled; DEBUG-02 `cameraConstraint` removed.
- Mail-share discipline mandatory post-walk for grep-correlation (Phase 5 explicitly requires Mail-share for both walks).
- ABI: `uPixelOrigin` slot 3..4 + `uZoomScale` slot 41 + `kPocFogReferenceZoom = 13.0`. Total float slots: 42.
- MIRL visual-identity preservation rule (CLAUDE.md `# MIRL solution`).
- FOG-07 single `MapCamera.of(context)` snapshot + FOG-12 single `canvas.getTransform()` read per paint.
- Dual-clock JSONL discipline + 1-Hz wall-clock-aligned rollup cadence.
- `uSdfRect = (0, 0, 1, 1)` identity (RESEARCH §Anti-Pattern 1).
- Stopwatch BY REFERENCE for `uTime` (anti-frozen-uTime).
- Strict analysis (`strict-casts`, `strict-inference`, `strict-raw-types`, `use_build_context_synchronously: error`).
- GOSL header on every `.dart` file in `lib/` and `test/` (CI-gated via `tool/check_headers.dart`).
- License allow-list (CI-gated via `tool/check_licenses.dart`): MIT, BSD-2/3-Clause, Apache-2.0, ISC, zlib, CC0-1.0, Unlicense. Forbidden: GPL (any version), AGPL, SSPL, Commons Clause.
- Pinned versions in `pubspec.yaml` (no `^`); `pubspec.lock` committed.

### Claude's Discretion

- Exact filename and order within `PORTBACK.md` for the file-by-file copy list (organize by donor-component-area: shader / painter / SDF / wisp / logger / probe / config; or by application-layer: assets / lib/presentation / lib/infrastructure / lib/config).
- Exact wording of the "verdict" line in `VERDICT.md` (consistent with FALSIFICATION-N.md verbatim verdict patterns).
- Walk-evidence document numbering: `05-FALSIFICATION-1.md` + `05-UAT-1.md` for the iPhone walk; `05-PIXEL4A-FALSIFICATION-1.md` + `05-PIXEL4A-UAT-1.md` for the Pixel walk (or unified iPhone+Pixel evidence in one pair — planner picks based on doc-style consistency with Walks #1–#6 precedent).
- DEPENDENCIES.md re-audit task structure: per-row in-place edits OR full table rewrite.
- Pre-walk gates checklist for each walk: `flutter test` GREEN, `flutter analyze --fatal-infos` 0 warnings, `dart format --set-exit-if-changed` clean, `dart test tool/test/` GREEN, CI green on closing SHA on `main`, IPA / APK downloaded via `gh run download`.
- README.md decision deferred to executor: if the planner judges a repo-root README is on the closure path (project landing page consolidating the verdict + port-back pointers + getting-started for the porter), it MAY add it as a separate task; otherwise stays deferred.

### Deferred Ideas (OUT OF SCOPE)

- **README.md authoring at repo root** (project landing page consolidating verdict + port-back pointers + getting-started for the porter) — deferred unless the planner judges it on the closure path. VERDICT.md + PORTBACK.md may be sufficient self-introduction.
- **Archived `old` branch cleanup from Phase 3.1** — leave for posterity / historical record. Cautionary tale; not deletable scope.
- **MIRK-01 architectural ABI formalization** (uniform-list inspection + behavioural swap-shader test + zero-painter-branching invariant + ABI source-of-truth doc) — Phase 3.1 deferral carries forward unchanged.
- **MIRK-01 acceptance test trio** (static + behavioural + audit) — tied to MIRK-01 formalization; deferred with it.
- **ABI uniform rename `uPixelOrigin` → `uWorldOffset`** — tied to MIRK-01; deferred.
- **JSONL field rename `uOffsetX*` → `uWorldOffsetX*`** — deferred indefinitely; legacy names kept for grep-tool compatibility with Walks #1–#6 + P4 Walk #1 session logs.
- **DEBUG-03 numbered shader fix** (digit-atlas / unique-cell-numbers regression introduced by Plan 03.1-14 Task A) — known-defect; cleanup deferred indefinitely; debug-shader-only; no production impact.
- **Walk-replay tool** (record GPS once, replay on Pixel 4a / Windows desktop) — deferred since Phase 3; WalkSimulator is the practical equivalent for Phase 5 closure walks.
- **`p99Ms` field on `FrameDeltaProbe`** — Phase 3 deferred; Phase 5 doesn't reopen.
- **`tool/extract_walk.dart` helper** (auto-extract probe + SDF + fog-transform + wisp stats from JSONL) — manual `grep` + `jq` suffices for Phase 5 closure walks.
- **`MapView` domain abstraction** — locked OUT of POC scope per PROJECT.md (migration concern; MirkFall-side decision).
- **Pivot to alternative renderers** (`mapsforge_flutter`, custom MVT-on-Canvas, `flutter_gpu`) — Phase 3.2 path obviated by Phase 3.1 + Phase 4 CONFIRMED verdict.
- **Wisp shader (FragmentProgram alternative to drawCircle)** — deferred per Phase 4 Q1 decision.
- **GPU instancing / GLSL compute** — out of POC scope; v2 / MirkFall port-back concern if Pixel 4a walks reveal CPU bottleneck at higher disc volumes.
- **WISP-06 acceptance criterion** (formal shader-agnosticism CI gate) — deferred per Phase 4 decision.
- **Tap-to-spawn / interactive wisps** — new capability; not on closure path.
- **Persistent disc state across sessions** — out of POC scope (PROJECT.md scope: in-memory storage only).
- **Phase 5.1 inserted phase** — only triggers if Phase 5 walks surface non-trivial issues; default expectation per Phase 3.1 Walk #6 + P4 Walk #1 precedent is single-walk closure per platform.
- **Multiple mirk styles** (atmospheric only per PROJECT.md) — out of POC scope.
- **Custom MirkFall basemap styling** (`#f5f1e8` / `#a6c9df` / etc. via `Theme` object) — out of POC scope per PROJECT.md; MirkFall-side concern at port-back time.
- **`MirkInitialRevealFade`** — visual polish; not on hypothesis path; out of POC scope per PROJECT.md.
- **`Permission.locationAlways` + notification permissions** — out of POC scope (POC only needs `locationWhenInUse`).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **PERF-06** | Pixel 4a (Adreno 618) UAT walks at Phase 3 and Phase 5: app launches, fog renders, no crash; informational FPS recorded for cross-platform comparison (no hard pass criterion) | The "Pixel 4a Adreno 618 walk shape" research below documents (a) the existing APK pipeline (`gh run download` + `adb install`), (b) the WalkSimulator path for reproducible drive at desk, (c) the same JSONL rollup discipline as iPhone (`infrastructure.mirk.frame_delta` + `fog_transform` + `sdf` + `wisp`), (d) the Adreno-6xx Impeller-known-issue context (Flutter 3.41 OpenGL ES fallback for older Adreno; informational expectation = Skia-or-fallback-OpenGL-ES backend), (e) the VERDICT.md citation shape (5-line quantitative summary). Soft criterion — no hard pass; "walks once + fog renders + wisps render + no crash + informational fps" is the bar. |

## Standard Stack

### Already in use (no changes — Phase 5 is non-feature work)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter | 3.41.7 (CI-pinned) | App framework | POC SDK pin per BOOT-01 |
| flutter_map | 7.0.2 | Vector tile + LatLng map widget | Donor-parity pin (parent on 7.x); produces the `MapCamera` snapshot the same-Canvas keystone reads |
| vector_map_tiles + vector_map_tiles_pmtiles | 8.0.0 / 1.5.0 | PMTiles vector renderer | Phase 2 PMTiles path; unchanged in P5 |
| latlong2 | 0.9.1 | LatLng math primitive | Phase 4 wisp world-anchor type |
| permission_handler | 12.0.1 | OS-level location permission | Phase 1 wiring; unchanged |
| geolocator | 14.0.2 | Live GPS stream + Position objects | WalkSimulator emits Position values structurally identical to live Geolocator stream |
| share_plus | 12.0.2 | OS sharesheet for Mail-share | iOS (Mail target) + Android (Gmail / Drive / Files) — same code path; underlies the post-walk JSONL Mail-share for both Phase 5 walks |
| logging | 1.3.0 | `infrastructure.mirk.*` JSONL logger family | Five 1-Hz streams (frame_delta + fog_transform + sdf + wisp + dev_marker); grep-correlated by `epochSecond` |
| go_router | 16.0.0 | Routing | `/map`, `/sanity`, `/error` |
| flutter_lints + analysis_options | 6.0.0 | Strict analysis CI gate | `strict-casts`, `strict-inference`, `strict-raw-types`, `use_build_context_synchronously: error` already enforced |
| yaml | 3.1.3 | `tool/check_dependencies_md.dart` parsing | Hardening tooling |
| test | 1.30.0 | `dart test tool/test/` runner | Tool-test CI gate |
| fake_async | 1.3.3 | Synthetic clock for `WispParticleSystem` warmup-gate test | Promoted from transitive to direct dev-dep in `eec9087` |

### Already installed CLI tooling (host machine — verified)

| Tool | Purpose | Phase 5 Use |
|------|---------|-------------|
| `gh` CLI | GitHub Actions API + artifact download | `gh run list` / `gh run watch` / `gh run download <run-id> --name mirk-poc-debug-ios-unsigned-ipa` / `... --name mirk-poc-debug-android-debug-apk` |
| `adb` | Android Debug Bridge | `adb install <apk>` for Pixel 4a walk |
| SideStore (iOS) + paired Mac pairing-file | iPhone IPA sideload | Established workflow Walks #1–#6 + P4 Walk #1 |

### Alternatives considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled audit-date refresh in DEPENDENCIES.md | `tool/refresh_dependencies_md_audit.dart` automation | NOT WORTH IT — 19 rows × ~30s/row = 10 min one-off; tooling cost > rework cost. Hand edit + CI freshness check stays green. |
| Per-walk `FALSIFICATION-N.md` doc-style | Unified `05-FALSIFICATION.md` covering both iPhone + Pixel walks | Discretion — planner picks per CONTEXT §Claude's Discretion. Phase 3.1 used per-walk numbered docs (#1..#6); Phase 4 used a single `04-FALSIFICATION.md` (single walk). Two options viable. |
| Outdoor walking | WalkSimulator at desk | LOCKED — CONTEXT explicitly chooses WalkSimulator for both walks (reproducibility + safety). |

**Installation:** No new packages. Phase 5 ships zero new `pubspec.yaml` additions.

## Architecture Patterns

### Already-established structure (Phase 5 changes nothing)

```
mirk-poc-debug/
├── VERDICT.md                                 # NEW — Phase 5 Plan 04
├── PORTBACK.md                                # NEW — Phase 5 Plan 04
├── README.md                                  # OPTIONAL — discretion to executor
├── DEPENDENCIES.md                            # MODIFIED in-place — audit dates
├── LICENSE / CLAUDE.md                        # UNCHANGED
├── .planning/phases/05-decision-gate/
│   ├── 05-CONTEXT.md                          # already authored
│   ├── 05-RESEARCH.md                         # THIS DOC
│   ├── 05-PLAN-N.md                           # planner outputs
│   ├── 05-FALSIFICATION-1.md                  # iPhone walk evidence
│   ├── 05-UAT-1.md                            # iPhone walk session log
│   ├── 05-PIXEL4A-FALSIFICATION-1.md          # Pixel walk evidence (or unified)
│   └── 05-PIXEL4A-UAT-1.md                    # Pixel walk session log
└── (every other lib/ + test/ + tool/ tree UNCHANGED)
```

### Pattern 1: Walk-evidence doc structure (template established by 04-FALSIFICATION.md / 04-UAT.md)

**What:** YAML front-matter + Hypothesis + Falsification Criteria + Walk Plan + Pre-walk Gate Status + Walk Source Note (synthetic vs live) + Walk Steps + Per-Criterion Verdict Table + Mail-share JSONL extracts + Verdict statement.

**When to use:** Every Phase 5 walk produces this pair of docs.

**Source:** `.planning/phases/04-wisp-particles/04-FALSIFICATION.md` lines 1–80 (scaffolding); `04-UAT.md` lines 1–80 (gate evidence + walk source note).

**YAML front-matter shape (verbatim from P04):**

```yaml
---
phase: 05-decision-gate
walk: 1
date: 2026-05-DD
ci_run: <gh-run-id>
sha: <commit-sha>
verdict: CONFIRMED-AFTER-FIX (FULL)  # or CONFIRMED-AFTER-FIX-PARTIAL / ITERATING-* / DENIED
---
```

**Per-Criterion Verdict Table (template):**

```markdown
| Criterion | Status | Evidence |
| --- | --- | --- |
| A — Phase 3 fog re-confirm | GREEN | Verbatim verdict + medianMs from frame_delta rollups |
| B — Phase 4 wisp re-confirm | GREEN | Verbatim verdict + wisp lat/lon bounds from `infrastructure.mirk.wisp` |
| C — PERF-07 budget | GREEN | medianMs / p95Ms / maxMs from `infrastructure.mirk.frame_delta` |
| D — PERF-08 SDF rebuild rate | GREEN | rebuildCount/sec from `infrastructure.mirk.sdf` |
| E — C3' extreme-distance (closing P4 deferred) | GREEN | uOffsetX max + visual lock @ ~50–100 km from Melun |
| F — UX-02 rotation no-op | GREEN | canvasTx/Ty == 0.0 across all `infrastructure.mirk.fog_transform` rollups |
| G — Mail-share grep-correlation (closing P4 deferred) | GREEN | epochSecond joins across 5 streams |
```

### Pattern 2: Pre-walk gate sequence (verbatim from `04-UAT.md` lines 28–43)

```bash
$ flutter test
... 211 tests passed, 1 skipped ...

$ flutter analyze
No issues found! (ran in 2.4s)

$ dart format --line-length 160 --set-exit-if-changed lib/ test/
Formatted 96 files (0 changed)

$ dart run tool/check_headers.dart
check_headers: OK (100 files)

$ dart run tool/check_dependencies_md.dart
check_dependencies_md: OK (125 packages)

$ dart test tool/test/
... GREEN ...

$ gh run watch <run-id>
... gates GREEN, android GREEN, ios GREEN ...

$ gh run download <run-id> --name mirk-poc-debug-ios-unsigned-ipa
$ gh run download <run-id> --name mirk-poc-debug-android-debug-apk
```

**When to use:** Before every Phase 5 walk. ALL must be GREEN before sideloading.

### Pattern 3: WalkSimulator drive shape (commit `eec9087`)

**Source:** `lib/infrastructure/location/walk_simulator.dart` (audited present + GOSL-headered).

**Mechanism:**
- Singleton owns broadcast `Stream<Position>` + Timer ticking every `kPocWalkSimulatorTickMs` (1000 ms) at `kPocWalkSimulatorDefaultSpeedMps` (1.4 m/s) along configurable bearing.
- `_emitNext()` constructs a `Position` whose listener body is the SAME one `Geolocator.getPositionStream()` resolves into (`MapScreen._onPositionFix` ~line 251).
- AppBar control: `Icons.directions_walk` → bottom sheet with start/stop + N/E/S/W bearing + speed slider (`_showWalkSimulatorSheet` in `poc_app_bar.dart` line 95+).
- `running` is a `ValueNotifier<bool>` so `MapScreen` swaps between live `Geolocator` and `WalkSimulator.stream` without prop-drilling.

**Use in Phase 5:** Both iPhone + Pixel 4a walks drive disc emergence via the AppBar control. Reproducible drive shape; no outdoor walking required.

### Pattern 4: Mail-share post-walk JSONL extraction

**Source:** P04 walks + Phase 3.1 Walks #4 / #5 patterns.

**Flow:**
1. End walk in app → tap share-logs button (always-visible AppBar action).
2. iOS sharesheet → Mail → developer's address → send.
3. Android sharesheet (Pixel 4a) → Gmail/Drive/Files → developer's address → send.
4. On dev machine: download `yyyymmddTHHMMSSZ_logs.txt`.
5. Filter the 5 streams by `Logger` field:
   ```bash
   grep "infrastructure.mirk.frame_delta" logs.txt > frame_delta.jsonl
   grep "infrastructure.mirk.fog_transform" logs.txt > fog_transform.jsonl
   grep "infrastructure.mirk.sdf" logs.txt > sdf.jsonl
   grep "infrastructure.mirk.wisp" logs.txt > wisp.jsonl
   grep "infrastructure.mirk.dev_marker" logs.txt > dev_markers.jsonl
   ```
6. Cross-correlate by `epochSecond` field (1-Hz wall-clock-aligned).
7. Compute `medianMs / p95Ms / maxMs` aggregates with `jq` or pencil-and-paper (the dataset is small — < 1 MB per walk per stream).

### Pattern 5: VERDICT.md doc structure (NEW — first time authored)

**Required sections (locked by CONTEXT):**

1. **Verdict line** — single sentence: `HYPOTHESIS CONFIRMED-AFTER-FIX (Phase 3.1 Walk #6 + Phase 4 Walk #1 + Phase 5 closure walks)` + commit SHA.
2. **Recommendation** — single sentence: `PORT BACK with the layered Plan 03.1-02 + 03.1-04 + 03.1-05 + 03.1-07 + 03.1-08 + 03.1-10 + 03.1-12 + 03.1-14 + Plan 04-01..04-04 fix bundle + caveats list below.`
3. **Phase-by-phase evidence summary** (one paragraph each, with FALSIFICATION-N.md links):
   - Phase 1 (Foundation) — closed 2026-05-01.
   - Phase 2 (Map, no fog) — PERF-02 PASS at 120 fps no-fog 2026-05-01.
   - Phase 3 (Fog hypothesis) — DENIED 2026-05-01 → REVERSED 2026-05-04.
   - Phase 3.1 (Fix Fog Pan-Translation) — CONFIRMED-AFTER-FIX FULL after 6 iterations / 8 walks.
   - Phase 4 (Wisp Particles) — CONFIRMED-AFTER-FIX FULL on Walk #1 + 4 inline post-Plan-04-04 follow-ups.
   - Phase 5 (Decision Gate) — closure walks: iPhone re-confirm + Pixel 4a sanity reference.
4. **Quantitative reference table:**

   | Walk | Device | medianMs | p95Ms | maxMs | Notes |
   |------|--------|----------|-------|-------|-------|
   | P3.1-13 #5 | iPhone 17 Pro | 1.228 | 1.591 | 1.724 | 13×/20×/28× headroom (existing baseline) |
   | P3.1-11 #4 | iPhone 17 Pro | 0.243 | 5.020 | 9.514 | ~66×/~6.4×/~5.0× headroom (existing baseline) |
   | P5 #1 | iPhone 17 Pro | TBD | TBD | TBD | Phase 5 closure walk |
   | P5 #1 | Pixel 4a (Adreno 618) | TBD | TBD | TBD | informational reference |

5. **Caveats list** — 7 inherited limitations from CONTEXT.
6. **Version + commit stamp** — Flutter 3.41.7, iPhone 17 Pro (primary), Pixel 4a (Adreno 618, Android 13) reference, closing SHA.

### Pattern 6: PORTBACK.md doc structure (NEW — first time authored)

**Required sections (locked by CONTEXT):**

1. **Audience note** — "MirkFall porter; you read this top-to-bottom and port without round-tripping through the .planning/ tree."
2. **Pre-port checklist** — clone POC at closing SHA; verify CI green; verify `flutter test` green; verify GOSL headers present.
3. **File-by-file copy list** (planner discretion: by-component-area OR by-application-layer). Per row: source path + target path + verbatim-port vs adapt-on-port.
4. **ABI extensions table:** `uPixelOrigin` slot 3..4, `uZoomScale` slot 41, `kPocFogReferenceZoom = 13.0`, total slots 42. FOG-17a Dart-side decomposition formula. FOG-19 shader division formula.
5. **Locked invariants list** (8 items from CONTEXT).
6. **Fix-bundle plan order** (8 Phase 3.1 plans + 4 Phase 4 plans, in apply-sequence with what each plan does).
7. **Inline post-Plan-04-04 follow-ups** (4 commits as delta-commits onto fix-bundle base).
8. **Adaptation notes** — donor's screen-px velocity is wrong; use POC's m/s + LatLng basis. MapScreenServices DTO injection. WispTransformLogger schema.
9. **Caveats inheritance** — same 7 caveats as VERDICT.md, framed as "things you inherit on port-back."

### Anti-Patterns to Avoid

- **DO NOT modify production-fog code in Phase 5** — fix bundle is frozen at Phase 4 closing state. Any production-fog code change requires Phase 5.1 (regression triggered by walk).
- **DO NOT add new CI gates in Phase 5** — the existing 7-gate workflow already enforces every hardening rule the success criteria mention. Adding a new gate would risk regressing CI green and is unnecessary.
- **DO NOT auto-generate VERDICT.md or PORTBACK.md** — these are human-readable artefacts; tooling adds noise without benefit.
- **DO NOT remove WalkSimulator from production AppBar** — CONTEXT explicitly keeps it production-exposed; same WalkSimulator drives the Phase 5 walks.
- **DO NOT attempt to fix DEBUG-03** — explicitly waived by developer at Walk #6; cleanup deferred indefinitely.
- **DO NOT re-author REQUIREMENTS.md PERF-06 row before the Pixel walk closes** — the walk produces the evidence that closes PERF-06; the row update happens in the closure-cascade plan.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GitHub Actions artifact retrieval | Custom HTTP client | `gh run download <run-id> --name <artifact>` | Auth, retry, range-resume — all handled by `gh` |
| iOS sideload mechanism | Custom IPA signer | SideStore + paired Mac pairing-file | Established Walks #1–#6 + P04 workflow |
| Android sideload | Custom apk install | `adb install <apk>` | Established Phase 1+ workflow |
| GOSL header check | New regex script | Existing `tool/check_headers.dart` | Already CI-gated; handles BOM + codegen exclusions |
| License allow-list check | Manual pubspec.lock walk | Existing `tool/check_licenses.dart` | Already CI-gated |
| Audit-date freshness check | Manual diff | Existing `tool/check_dependencies_md.dart` | Already CI-gated; cross-references pubspec.lock vs DEPENDENCIES.md table |
| Synthetic GPS for indoor walks | Mock Position objects in test | Existing `WalkSimulator` from `eec9087` | Same listener body as live `Geolocator.getPositionStream()`; production-exposed via AppBar control |
| JSONL stream extraction | Custom parser | `grep` + `jq` (or no-jq pencil math) | Dataset is < 1 MB per walk per stream |
| Verdict-doc auto-generation | YAML/JSON serializer | Hand-write VERDICT.md + PORTBACK.md | These are human artefacts; tooling adds noise |
| Cross-platform fps measurement | New profiler | Existing `infrastructure.mirk.frame_delta` JSONL | Dual-clock + 1-Hz rollup; same on iOS + Android |
| Pixel 4a stress test | New chaos suite | WalkSimulator at desk + same JSONL discipline as iPhone | Cross-platform consistency |

**Key insight:** Phase 5 is composed of pre-existing tooling exercised against new artefacts. The HEAVY work is doc authoring (VERDICT.md + PORTBACK.md + walk-evidence pair) and one bulk audit-date stamp. EVERY automation surface (CI gates, walk simulator, share, JSONL streams) already exists from Phases 1–4. Custom scripting Phase 5 is over-engineering.

## Common Pitfalls

### Pitfall 1: Adreno 618 Impeller-related crash on Pixel 4a launch

**What goes wrong:** Pixel 4a (Adreno 618) is in the Adreno-6xx family that has documented Impeller compatibility issues. App launches into a SIGSEGV, OOM, or rendering-glitch state on Vulkan-backed Impeller — fog never renders.

**Why it happens:** Flutter 3.41 introduced an OpenGL ES fallback for "older Adreno GPUs" precisely because Vulkan-backed Impeller has rendering issues on Adreno 6xx (documented for Adreno 610 visual glitches; Adreno 618 is in the same family).

**How to avoid:**
- Phase 5 build pipeline ships a debug APK from CI's `ubuntu-latest` runner (`flutter build apk --debug`); the `--debug` build path uses Skia by default on Android (Impeller-on-Android is opt-in for newer SDKs). Verify the APK is debug-flavor before Pixel 4a sideload.
- If launch crashes: check `adb logcat | grep -E "Flutter|Impeller|Vulkan|SIGSEGV"` immediately; if the crash is Impeller-related, the Phase 5 verdict still passes — PERF-06 is "informational" and a documented Adreno 6xx fallback issue is the kind of caveat VERDICT.md is supposed to capture.

**Warning signs:**
- App freezes on splash for > 10 s
- `logcat` shows `[ERROR:flutter/impeller/...]`
- Fog renders black or never renders
- Wisps render but fog doesn't

### Pitfall 2: Audit-date refresh accidentally bumps versions

**What goes wrong:** While re-auditing DEPENDENCIES.md, the auditor edits a version string (typo, copy-paste error, accidental autocomplete from a newer pub.dev page).

**Why it happens:** The audit columns include version. Hand-editing 19 rows × 9 columns = 171 cells. Easy to fat-finger.

**How to avoid:**
- Re-audit ONLY changes the `Audit date` column; version + license + telemetry + transitive licenses + maintenance + platform columns stay LITERALLY UNCHANGED.
- After the audit-date pass: `git diff DEPENDENCIES.md` and grep for any cells changed beyond the date column. Reject the diff if so.
- Run `dart run tool/check_dependencies_md.dart` immediately after — it cross-references pubspec.lock versions against DEPENDENCIES.md versions and fails on mismatch. CI also runs it on push.

**Warning signs:**
- `dart run tool/check_dependencies_md.dart` reports `version mismatch: pkg lock=X md=Y`
- `git diff DEPENDENCIES.md` shows changes outside the audit-date column

### Pitfall 3: Mail-share fails silently on Pixel 4a

**What goes wrong:** On Android, `share_plus` 12.0.2 surfaces the Android sharesheet (Gmail / Drive / Files / etc.). If the user picks an option that doesn't actually transmit (e.g., "Save to device") OR if Gmail doesn't have an account configured, the JSONL never reaches the dev machine.

**Why it happens:** Android sharesheet is more permissive than iOS Mail (iOS narrows to Mail-app target by Phase 1 design; Android sharesheet is full-featured).

**How to avoid:**
- Pre-walk: verify Pixel 4a has Gmail OR another email client signed in.
- During walk: pick "Gmail" or "Drive" specifically; if "Files" is the only option, the share is local-only.
- Post-walk: verify the email arrived BEFORE concluding the walk; if it didn't, re-trigger share-logs with a different target.

**Warning signs:**
- No email in inbox 1 minute after share
- Pixel 4a shows "Saved to Files" toast instead of "Sent"

### Pitfall 4: Phase 5 walk surfaces a regression that isn't a regression

**What goes wrong:** During the Phase 5 iPhone walk, the developer notices a visual quirk that wasn't called out in P3.1 #6 / P4 #1 (e.g., faint grain at extreme zoom; wisp drift seems slightly faster than at P4 baseline). They reflexively call it a regression and want to delay the verdict.

**Why it happens:** Continuous observation of the same software surfaces aspects not previously noticed. Not all of these are regressions; some are baseline characteristics.

**How to avoid:**
- Compare against the empirical baseline: P3.1 Walk #5 / Walk #6 + P4 Walk #1 verbal verdicts + JSONL rollup numbers.
- A "regression" is a measurable degradation: medianMs ≥ 16, p95Ms ≥ 32, maxMs ≥ 48, OR a visual lock failure (slide-then-snap, white ellipse, reveal-hole lag). Anything else is baseline.
- If unclear: PORT BACK with caveats explicitly enumerates the new observation as an inherited limitation (the porter then handles it).

**Warning signs:**
- Developer says "this looks weird" without quantitative evidence
- Walk is paused while developer thinks about a possible Phase 5.1
- Mail-shared rollups show numbers consistent with P3.1 Walk #5 / P4 Walk #1 baseline

### Pitfall 5: VERDICT.md links to FALSIFICATION docs that don't exist yet

**What goes wrong:** VERDICT.md is authored before the Phase 5 walks complete; its phase-by-phase paragraphs link to `05-FALSIFICATION-1.md` etc. that haven't been created. The link is a broken relative path on day one.

**Why it happens:** Plan order matters. VERDICT.md authoring naturally feels like the closing act, but it depends on artefacts that come from the walks.

**How to avoid:**
- Plan order: walks FIRST (produce FALSIFICATION + UAT docs); VERDICT.md authoring LAST.
- Or: VERDICT.md skeleton drafted with placeholder links, then filled in post-walks (CONTEXT precedent: Phase 4 closure cascade authored 04-FALSIFICATION.md + 04-UAT.md before STATE/ROADMAP).

**Warning signs:**
- Markdown linter flags broken relative links
- `git ls-files .planning/phases/05-decision-gate/05-FALSIFICATION-1.md` returns nothing while VERDICT.md references it

### Pitfall 6: PORTBACK.md file-list drifts from actual lib/ structure

**What goes wrong:** PORTBACK.md is hand-authored and references file paths like `lib/infrastructure/mirk/wisp/wisp_particle_system.dart`. If the path is wrong (typo, organization change), the porter can't find the file.

**Why it happens:** Path strings are hand-typed; lib/ structure isn't auto-walked.

**How to avoid:**
- Verify every path in PORTBACK.md is git-tracked: for each path, run `git ls-files <path>` and confirm it returns the path.
- Or: cross-reference the PORTBACK.md file list against `git ls-files lib/` output during plan-checker review.

**Warning signs:**
- Porter reports "file not found at <path>"
- `git ls-files <path>` returns nothing for a path mentioned in PORTBACK.md

## Code Examples

### Example 1: Pre-walk gate sequence (verbatim from `04-UAT.md`)

```bash
# Source: .planning/phases/04-wisp-particles/04-UAT.md lines 28-43
flutter test
flutter analyze
dart format --line-length 160 --set-exit-if-changed lib/ test/
dart run tool/check_headers.dart
dart run tool/check_dependencies_md.dart
dart test tool/test/

# Gate is ALL must be GREEN before sideloading.
gh run watch <closing-sha-run-id>
gh run download <run-id> --name mirk-poc-debug-ios-unsigned-ipa
gh run download <run-id> --name mirk-poc-debug-android-debug-apk
```

### Example 2: WalkSimulator AppBar control (already shipping, commit `eec9087`)

```dart
// Source: lib/infrastructure/location/walk_simulator.dart (audited present)
//
// AppBar wiring (lib/presentation/widgets/poc_app_bar.dart line ~95):
//   IconButton(
//     icon: const Icon(Icons.directions_walk),
//     onPressed: () => _showWalkSimulatorSheet(context),
//   ),
//
// Bottom sheet exposes:
//   - Start / Stop (mutates WalkSimulator.running ValueNotifier)
//   - Bearing buttons N / E / S / W
//   - Speed slider (default kPocWalkSimulatorDefaultSpeedMps = 1.4 m/s)
//
// MapScreen pivots its position subscription via:
//   walkSimulator.running.addListener(_onWalkSimulatorRunningChanged);
//   // _onWalkSimulatorRunningChanged swaps _positionSubscription between
//   // Geolocator.getPositionStream() and walkSimulator.stream.
//
// Listener body in MapScreen._onPositionFix(Position fix) is THE SAME for
// both sources — synthetic and live fixes hit the same disc-spawn /
// SDF-rebuild / FOG-19 path identically.
```

### Example 3: JSONL stream filter post-walk (planner discretion: shell or jq)

```bash
# Source: composed from Walks #4 / #5 / P04 #1 patterns
LOG=$(ls ~/Downloads/*_logs.txt | head -1)

grep "infrastructure.mirk.frame_delta" "$LOG" > frame_delta.jsonl
grep "infrastructure.mirk.fog_transform" "$LOG" > fog_transform.jsonl
grep "infrastructure.mirk.sdf"          "$LOG" > sdf.jsonl
grep "infrastructure.mirk.wisp"         "$LOG" > wisp.jsonl
grep "infrastructure.mirk.dev_marker"   "$LOG" > dev_markers.jsonl

# Quick perf summary (PERF-07):
jq -s '
  map(select(.medianMs != null)) |
  {
    rollups: length,
    medianOfMedians: (map(.medianMs) | sort | .[length/2|floor]),
    maxOfP95s: (map(.p95Ms) | max),
    maxOfMaxes: (map(.maxMs) | max)
  }
' frame_delta.jsonl
```

### Example 4: Walk-evidence YAML front-matter (verbatim from P04)

```markdown
<!-- Source: .planning/phases/04-wisp-particles/04-FALSIFICATION.md lines 1-8 -->
---
phase: 05-decision-gate
walk: 1
date: 2026-05-DD
ci_run: <gh-run-id>
sha: <commit-sha>
verdict: CONFIRMED-AFTER-FIX (FULL)
---
```

### Example 5: PORTBACK.md ABI extensions table shape

```markdown
<!-- Composed from CONTEXT decisions + lib/infrastructure/mirk/shader/fog_shader_uniforms.dart -->
## ABI extensions

| Slot | Uniform | Type | Source |
|------|---------|------|--------|
| 0..1 | uResolution | vec2 | size of the painted Rect |
| 2 | uTime | float | Stopwatch elapsedMicroseconds * 1e-6 |
| 3..4 | uPixelOrigin | vec2 | camera.pixelOrigin (FOG-17a decomposed) |
| 5..40 | (existing donor uniforms — unchanged) | various | donor manifest |
| 41 | uZoomScale | float | pow(2, camera.zoom - kPocFogReferenceZoom) |

**Total float slots:** 42 (was 41 pre-FOG-19).

**FOG-17a CPU decomposition (lib/presentation/widgets/fog_layer.dart `_FogPainter.paint()`):**

```dart
final double appliedUOffsetX = camera.pixelOrigin.toDouble() % kPocFogIntegerWrapPeriodPx;
// Note: post-FOG-18 (Plan 03.1-12), modulo eliminated; appliedUOffsetX = camera.pixelOrigin.toDouble().
```

**FOG-19 shader division (assets/shaders/atmospheric_fog.frag):**

```glsl
vec2 worldPx = fragUv * uResolution + uPixelOrigin;
vec2 noiseUv = worldPx / (kNoiseTilePx * uZoomScale);
// kNoiseTilePx = 384.0; uZoomScale anchors noise to lat/lng during zoom.
```
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Phase 3 ROADMAP `≥ 30 fps with fog active` | PERF-07 `medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48` | 2026-05-02 (Plan 03.1-03) | Frame-delta probe is more precise than fps; ROADMAP wording is legacy text. PERF-07 is authoritative. CONTEXT calls this out explicitly. |
| Outdoor walking required for UAT | Sideload-session-at-desk (WalkSimulator drives synthetic GPS) | 2026-05-02 (Phase 3.1 D1 decision); 2026-05-05 (commit `eec9087` made it production-tooled) | Reproducibility + safety; same listener body as live GPS preserves structural fidelity |
| Per-phase Pixel 4a UAT walks (Phases 1-5) | Pixel 4a walked only at Phase 3 + Phase 5 | 2026-04-30 (PROJECT.md scope decision) | Phase 5 is the FIRST + ONLY Pixel 4a walk this POC executes (Phase 3 walk was DENIED before getting to Pixel) |
| Verbal-only verdicts (Phase 3.1 Walks #3 + #6) | Mail-share required Phase 5 | 2026-05-05 CONTEXT | Closure-doc evidence base needs quantitative numbers for VERDICT.md citation |
| Phase 4 Plan 04-04 closing scope | + 4 inline post-Plan-04-04 follow-up commits | 2026-05-05 (P04-05 walk-time iteration) | Phase 5 PORTBACK.md treats them as delta-commits onto the fix-bundle base |

**Deprecated/outdated:**

- **`MapOptions.cameraConstraint`** (DEBUG-02): removed in Plan 03.1-12 to allow C3' extreme-distance pan. Phase 5 walk MUST exercise ≥ 50 km from Melun.
- **`kPocFogReferenceZoom = 13.0` baseline assumption** (`kPocInitialZoom = 13`): obsoleted by post-Plan-04-04 follow-up `2613da8` which sets `kPocInitialZoom = 19`. Reference zoom remains 13 (uZoomScale = 1.0 there); initial zoom is now 19. NO impact on noise sampling (uZoomScale handles it).
- **`kPocRecenterZoom = 15`**: deleted as unused in `849a6e1`. Recenter FAB now lands at `kPocInitialZoom`.

## Open Questions

### Question 1: Will the Pixel 4a Adreno 618 launch on a Flutter 3.41 debug-flavor APK without an Impeller crash?

- **What we know:** Flutter 3.41 release notes mention "Fall back to OpenGL ES on older Adreno GPUs" — confirming Adreno-family GPUs have known Impeller compatibility issues. Adreno 618 is in the 6xx family; documented visual glitches exist for Adreno 610 (similar generation). Flutter 3.41.7 IS the POC's pinned SDK.
- **What's unclear:** Whether the OpenGL ES fallback covers Adreno 618 (vs only listing specific Adreno SKUs). Whether the debug-flavor APK uses Skia or Impeller by default on Pixel 4a (Android 13).
- **Recommendation:**
  - Phase 5 plan should include a short "Pixel 4a launch sanity" pre-step BEFORE the full walk: `adb install <apk>` → cold launch → confirm map renders + FPS counter renders + no `logcat` `[ERROR:flutter/impeller]` lines in first 30 s.
  - If launch crashes: this IS a valid PERF-06 outcome (the requirement is "informational FPS recorded for cross-platform comparison; no hard pass criterion"). VERDICT.md captures the launch-crash as a known caveat: "Pixel 4a Adreno 618 launch crash on Impeller backend — falls under documented Adreno 6xx Flutter compatibility issue; mitigation via OpenGL ES fallback at MirkFall port-back time if needed."
  - If launch succeeds: proceed with full WalkSimulator-driven walk + Mail-share + JSONL extraction. Same JSONL discipline as iPhone.

### Question 2: Should the Phase 5 walks reuse `infrastructure.mirk.dev_marker` instrumentation?

- **What we know:** Walks #4 + #5 used dev_marker for FOG-17a-wrap-firing diagnostics; P04 didn't. Phase 5 production-fog code is frozen at Phase 4 closing state — no dev_marker conditions newly fire.
- **What's unclear:** Whether the dev_marker stream produces any rollups on Phase 5 walks (FOG-17a wrap is impossible since FOG-18 eliminated the modulo; Walk #5 had ZERO dev_markers).
- **Recommendation:** Treat zero dev_markers as expected. Phase 5 walks Mail-share all 5 streams (including dev_marker) for completeness, but the per-criterion verdict table doesn't depend on dev_marker content. Empty dev_marker stream = baseline confirmed.

### Question 3: Walk-evidence doc style — per-walk numbered (Phase 3.1) OR unified (Phase 4)?

- **What we know:** Phase 3.1 numbered docs `#1`..`#6` (one per walk + extras like `#3b`); Phase 4 unified `04-FALSIFICATION.md` (single walk closed phase).
- **What's unclear:** Whether Phase 5's TWO walks (iPhone + Pixel) want a unified `05-FALSIFICATION.md` covering both OR per-walk `05-FALSIFICATION-1.md` (iPhone) + `05-PIXEL4A-FALSIFICATION-1.md` (Pixel).
- **Recommendation:** Per-walk numbered/named docs match Phase 3.1's grep-tool compatibility precedent + give VERDICT.md two distinct evidence anchors. Use `05-FALSIFICATION-1.md` (iPhone) + `05-PIXEL4A-FALSIFICATION-1.md` (Pixel). Same for UAT pair. CONTEXT explicitly leaves this to discretion; the per-walk shape is more conventional.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (SDK) + `package:test` 1.30.0 (for `dart test tool/test/`) |
| Config file | `analysis_options.yaml` + `dart_test.yaml` (none — defaults) |
| Quick run command | `flutter test --plain-name <pattern>` |
| Full suite command | `flutter test` (211+ tests) + `dart test tool/test/` (18 tool tests) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PERF-06 | Pixel 4a (Adreno 618) walk: app launches, fog renders, no crash; informational fps recorded | manual-only (sideload UAT walk) | `gh run download <run-id> --name mirk-poc-debug-android-debug-apk` then `adb install` then walk | manual-only (no automatable replacement; cross-platform sanity is by definition device-bound) |
| (Hardening) `flutter analyze` zero warnings | strict-analysis CI gate | unit/CI | `flutter analyze --fatal-infos --fatal-warnings` | ✅ existing |
| (Hardening) `dart format --line-length 160 --set-exit-if-changed` clean | format CI gate | unit/CI | `dart format --line-length 160 --set-exit-if-changed .` | ✅ existing |
| (Hardening) GOSL header on every `.dart` in `lib/` and `test/` | header CI gate | unit/CI | `dart run tool/check_headers.dart` | ✅ existing (`tool/check_headers.dart` — verified present, GOSL-headered, scans `lib`/`test`/`tool`/`integration_test` with codegen exclusions) |
| (Hardening) DEPENDENCIES.md covers every package in `pubspec.lock` with current audit dates | freshness CI gate | unit/CI | `dart run tool/check_dependencies_md.dart` | ✅ existing (`tool/check_dependencies_md.dart` — verified present, cross-references pubspec.lock vs DEPENDENCIES.md tables, fails on missing/extra/mismatched) |
| (Hardening) CI license-check job green on `main` | license CI gate | unit/CI | `dart run tool/check_licenses.dart` | ✅ existing (`tool/check_licenses.dart` — verified present) |
| (SC #1) iPhone fog re-confirm + wisp re-confirm + ≥ 30 fps (legacy text; PERF-07 authoritative) + share-logs round-trip + FPS counter visible | manual-only (sideload UAT walk) | walk + Mail-share + JSONL grep | manual-only | manual-only |
| (SC #4) VERDICT.md committed at repo root with the 6 required sections | doc-presence + content | manual file-write + plan-checker review | `test -f VERDICT.md && grep -q "PORT BACK" VERDICT.md` | manual (Phase 5 Plan 04 authors it) |
| (SC #4) PORTBACK.md committed at repo root with the 9 required sections | doc-presence + content | manual file-write + plan-checker review | `test -f PORTBACK.md && grep -q "ABI extensions" PORTBACK.md` | manual (Phase 5 Plan 04 authors it) |

### Sampling Rate

- **Per task commit:** `flutter test --plain-name <relevant-test>` (existing test file pattern; no new test files for Phase 5 except optionally the DEPENDENCIES re-audit doesn't need one). For the docs-only plans (DEPENDENCIES re-audit + VERDICT/PORTBACK authoring + STATE/ROADMAP cascade), the per-task commit verification is `dart run tool/check_*.dart` plus `dart format --set-exit-if-changed`.
- **Per wave merge:** `flutter test` full suite (211+) + `dart test tool/test/` (18) + `flutter analyze` + format check + GOSL header + license + freshness checks. ALL existing CI gates run together via `dart format --line-length 160 --set-exit-if-changed . && flutter analyze --fatal-infos --fatal-warnings && flutter test && dart test tool/test/ && dart run tool/check_headers.dart && dart run tool/check_licenses.dart && dart run tool/check_dependencies_md.dart`.
- **Phase gate:** Full suite green on `main` HEAD before each Phase 5 walk; CI run downloads provide IPA + APK; walks confirm runtime; VERDICT.md authoring is the final closure step.

### Wave 0 Gaps

- *None — existing test infrastructure covers all Phase 5 requirements.*
- Phase 5 has zero new feature code, so zero new RED-cycle tests are required.
- The 7 existing CI gates cover every "hardening passes" success criterion.
- `tool/check_dependencies_md.dart` already verifies DEPENDENCIES.md covers every pubspec.lock package (will go red on the first 2026-04-30 → 2026-05-05 audit-date pass only if a row is dropped or version-mismatched; freshness is enforced by the cross-reference check, not by date-string content).
- PERF-06 closure is by definition manual-only (sideload walk on physical Pixel 4a).
- VERDICT.md + PORTBACK.md are human-authored; their plan-checker review IS their validation step.

## Sources

### Primary (HIGH confidence)

- `.planning/phases/05-decision-gate/05-CONTEXT.md` — locked decisions + discretion + deferred ideas (verbatim copied above)
- `.planning/REQUIREMENTS.md` — PERF-06 row + every traceability entry for the closing phases
- `.planning/STATE.md` — Phase 4 closure verdict + WalkSimulator commit `eec9087` reference
- `.planning/ROADMAP.md` — Phase 5 success criteria + complete phase verdict history
- `.planning/phases/04-wisp-particles/04-FALSIFICATION.md` lines 1–80 — walk-evidence template
- `.planning/phases/04-wisp-particles/04-UAT.md` lines 1–80 — pre-walk gate sequence template
- `.github/workflows/ci.yml` — 7-gate hardening workflow (verified, all gates active)
- `tool/check_headers.dart` — GOSL header CI tool (verified present, scans lib/test/tool/integration_test, GOSL-headered)
- `tool/check_dependencies_md.dart` — DEPENDENCIES.md freshness CI tool (verified present)
- `DEPENDENCIES.md` — 14 direct deps + 5 dev deps; all audit-dated 2026-04-30 (except `fake_async` 2026-05-05); 132 packages in pubspec.lock total; transitive table exists with placeholder note
- `pubspec.yaml` — verified: every direct dep strict-pinned (no `^`); SDK pin `>=3.11.0 <4.0.0`; Flutter pin `>=3.41.0 <3.42.0`
- `lib/infrastructure/location/walk_simulator.dart` — verified present + GOSL-headered + production-exposed via AppBar
- `LICENSE` — verified present, GOSL v1.0
- `pubspec.lock` — 132 packages declared; transitive deps + direct deps cross-checked by `tool/check_dependencies_md.dart`
- Recent git log (last 20 commits) — confirms Phase 4 closure SHA `eec9087` is HEAD; Phase 5 docs committed: `a75ee17 docs(05): capture phase context` + `1487284 docs(state): record phase 5 context session`

### Secondary (MEDIUM confidence)

- [Flutter 3.41 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.41.0) — mentions "Fall back to OpenGL ES on older Adreno GPUs" (confirms the existence of an Adreno fallback path; specific Adreno-618 status not enumerated by SKU)
- [GitHub Flutter Issue #159834](https://github.com/flutter/flutter/issues/159834) — "[Impeller] Visual glitches during animation on Redmi Note 8T (Adreno 610)" — confirms Adreno 6xx family has documented Impeller issues (610 is sibling to 618)
- [Flutter Impeller docs](https://docs.flutter.dev/perf/impeller) — backend selection criteria, Skia fallback policy

### Tertiary (LOW confidence)

- (None — Phase 5 has no domain-novel research; everything is internal codebase + already-validated tooling. The Adreno 618 specific behaviour on Pixel 4a is the only external unknown, and the recommended mitigation is "let the walk produce the answer; document the outcome in VERDICT.md as a caveat if there's a launch issue.")

## Metadata

**Confidence breakdown:**

- Standard stack: **HIGH** — every library is already audited + version-pinned + CI-gated; Phase 5 ships zero new packages
- Architecture patterns: **HIGH** — every pattern (walk-evidence doc, pre-walk gates, JSONL streams, WalkSimulator, Mail-share) is already established and exercised by P3.1 + P4 walks
- Pitfalls: **HIGH** for codebase-internal pitfalls (DEBUG-03 waiver, audit-date discipline, Mail-share flow); **MEDIUM** for Pixel 4a Adreno 618 behaviour (documented family-level issues but specific Adreno-618 SKU coverage in Flutter 3.41 OpenGL ES fallback is not enumerated by Google docs)

**Research date:** 2026-05-05
**Valid until:** 2026-06-05 (30 days for stable POC closure scope; Pixel 4a Adreno 618 walk on Flutter 3.41.7 is a one-shot empirical capture and the verdict closes regardless of upstream changes after capture)
