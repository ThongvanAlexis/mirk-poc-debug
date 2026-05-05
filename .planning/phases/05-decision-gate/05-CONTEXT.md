# Phase 5: Decision Gate - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Lock everything down for code-donor port-back to MirkFall and produce the formal POC verdict (hypothesis confirmed / denied → MirkFall migration go / no-go). One final iPhone 17 Pro walk re-runs Phase 3 fog + Phase 4 wisp criteria AND closes Phase 4 deferred Criterion E (C3' extreme-distance ~50–100 km from Melun) + Criterion G (Mail-share grep-correlation). One Pixel 4a (Adreno 618) walk satisfies the cross-platform sanity requirement (PERF-06 — informational). Repository hardening passes existing CI gates (format / analyze / GOSL header / license allow-list / DEPENDENCIES.md freshness / tool tests / flutter tests). Two repo-root artefacts ship as the final deliverables: `VERDICT.md` (formal go/no-go + recommendation + evidence pointers) and `PORTBACK.md` (surgical migration playbook for the MirkFall porter).

Out of scope: alternative renderer pivots (`mapsforge_flutter`, custom MVT-on-Canvas, `flutter_gpu`) — Phase 3.2 path was never executed; the CONFIRMED hypothesis obviates it. MirkFall-side integration work — port-back consumer concern. MIRK-01 architectural ABI formalization (uniform-list inspection + swap-shader behavioural test + zero-painter-branching invariant) — Phase 3.1 deferral carries forward unchanged. ABI uniform rename `uPixelOrigin` → `uWorldOffset` — tied to MIRK-01; stays deferred. JSONL field rename `uOffsetX*` → `uWorldOffsetX*` — deferred indefinitely for grep-tool compatibility with Walks #1–#6 + P4 Walk #1 session logs. README.md authoring at repo root (project landing page) — separate concern. Archived `old` branch cleanup from Phase 3.1 — leave for posterity. DEBUG-03 broken numbered shader fix — known-defect, cleanup deferred indefinitely.

</domain>

<decisions>
## Implementation Decisions

### Verdict + port-back artefacts

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

### Final iPhone walk scope

- **Single comprehensive walk** covers all four objectives in one sideload session: (a) Phase 3 fog re-confirm baseline, (b) Phase 4 wisp re-confirm baseline, (c) C3' extreme-distance regime (~50–100 km pan from Melun) closing P4 Walk #1's deferred Criterion E, (d) post-walk Mail-share closing P4 Walk #1's deferred Criterion G. Targeted ~10–15 min of active interaction.
- **Mail-share required.** Closes P4 Walk #1's deferred Criterion G explicitly; quantitative PERF-07 numbers extracted from JSONL rollups (`infrastructure.mirk.frame_delta` + `infrastructure.mirk.fog_transform` + `infrastructure.mirk.sdf` + `infrastructure.mirk.wisp` streams) cited in VERDICT.md.
- **WalkSimulator drives synthetic GPS** for the wisp spawn axis. Phase 4 Walk #1 precedent (commit `eec9087`); same WalkSimulator at desk drives reproducible disc emergence so wisps spawn through the warmup gate + LRU cap regimes. No outdoor walking required.
- **Free-form session, developer judgment** for gesture regime — pans / zooms / recenter taps / sustained one-direction pan past city limits as the walk feels appropriate. Mail-shared JSONL rollups give post-walk quantitative reconstruction of which regimes were exercised; verbal verdict at session end provides the qualitative call. Consistent with Phase 3.1 "validate first, architect later" philosophy and Walks #4 / #6 / P4 Walk #1 verbal-decisive precedent.
- **Iteration policy carries forward:** no hard cap on walk count. If Walk #1 surfaces a residual issue, a Phase 5.1 inserted phase iterates (mirrors Phase 3.1 pattern). Default expectation per Phase 3.1 Walk #6 + P4 Walk #1 closure precedent: single-walk closure on iPhone.

### Pixel 4a walk shape (PERF-06 — informational, soft criterion)

- **WalkSimulator at desk** drives the Pixel 4a too. Cross-platform consistency with iPhone walk methodology; no outdoor walking; reproducible drive shape. Pixel 4a's APK installed via `gh run download` + `adb install` (existing Phase 1+ workflow).
- **Mail-share required, same JSONL discipline as iPhone.** Quantitative Adreno 618 PERF-07 numbers on the record. Same `share_plus` flow; Android sharesheet presents Gmail / Drive / Files for transmission. Treats PERF-06 with the same rigor as iPhone PERF-07 despite the soft-criterion status.
- **Mirror iPhone walk regimes** including C3' extreme-distance (~50–100 km from Melun). Cross-platform parity for the fp32 precision question — if iPhone is clean at extreme distance, verify Pixel 4a's Adreno 618 behavior matches. Codifies cross-platform parity over PERF-06's "informational" framing.
- **VERDICT.md citation format: quantitative summary line.** One paragraph or ~5-line table: `Pixel 4a (Adreno 618, Android 13) — PERF-07 medianMs / p95Ms / maxMs from Mail-shared rollups + visual lock observation + crash status (none)`. Sufficient for the cross-platform-reference purpose without full evidence reproduction.

### Hardening + caveat policy

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

### Iteration policy (carry-forward, unchanged)

- Plan-revise-walk loop. **No hard cap on walk count.** If Phase 5 walks surface a non-cosmetic issue (PERF-07 threshold breach, visual lock failure, crash), Phase 5 stays open and a Phase 5.1 inserted phase iterates. Verdict not authored until walks are clean. Default expectation per Phase 3.1 Walk #6 + P4 Walk #1 precedent: single-walk closure per platform.
- "Port back with caveats" is the default verdict shape (per "Caveat policy" above). "Do not port back" requires a NEW falsification of the same-Canvas hypothesis (already CONFIRMED post Phase 3.1 + Phase 4) — extremely unlikely given the closure-walk evidence base.

### Locked invariants (carried forward — non-negotiable)

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

### Claude's Discretion (planner / executor level)

- Exact filename and order within `PORTBACK.md` for the file-by-file copy list (organize by donor-component-area: shader / painter / SDF / wisp / logger / probe / config; or by application-layer: assets / lib/presentation / lib/infrastructure / lib/config).
- Exact wording of the "verdict" line in `VERDICT.md` (consistent with FALSIFICATION-N.md verbatim verdict patterns).
- Walk-evidence document numbering: `05-FALSIFICATION-1.md` + `05-UAT-1.md` for the iPhone walk; `05-PIXEL4A-FALSIFICATION-1.md` + `05-PIXEL4A-UAT-1.md` for the Pixel walk (or unified iPhone+Pixel evidence in one pair — planner picks based on doc-style consistency with Walks #1–#6 precedent).
- DEPENDENCIES.md re-audit task structure: per-row in-place edits OR full table rewrite.
- Pre-walk gates checklist for each walk: `flutter test` GREEN, `flutter analyze --fatal-infos` 0 warnings, `dart format --set-exit-if-changed` clean, `dart test tool/test/` GREEN, CI green on closing SHA on `main`, IPA / APK downloaded via `gh run download`.
- README.md decision deferred to executor: if the planner judges a repo-root README is on the closure path (project landing page consolidating the verdict + port-back pointers + getting-started for the porter), it MAY add it as a separate task; otherwise stays deferred.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`WalkSimulator`** (`lib/infrastructure/location/walk_simulator.dart`, commit `eec9087`): drives synthetic GPS via `_emitNext()` constructing `Position` whose listener body matches the live Geolocator stream. Wisp spawn / SDF reveal / FOG-19 behaviour exercised identically to a live walk. Used for both iPhone and Pixel 4a Phase 5 walks. Currently exposed in production AppBar via `_showWalkSimulatorSheet` (poc_app_bar.dart line 95+); kept production-exposed per Hardening decision.
- **`FogTransformLogger`** (`lib/infrastructure/mirk/fog_transform_logger.dart`) + **`WispTransformLogger`** (`lib/infrastructure/mirk/wisp_transform_logger.dart`) + **`FrameDeltaProbe`** (`lib/infrastructure/mirk/frame_delta_probe.dart`) + **`SdfRebuildLogger`** (`lib/infrastructure/mirk/sdf/sdf_rebuild_logger.dart`): four JSONL streams for Mail-share grep-correlation. Wall-clock-aligned 1-Hz rollups via `Logger('infrastructure.mirk.{fog_transform,wisp,frame_delta,sdf}')`. Phase 5 walks consume all four streams in post-walk JSONL extraction.
- **CI workflow** (`.github/workflows/ci.yml`): 7 hardening gates already wired — format check (`dart format --line-length 160 --set-exit-if-changed .`), analyzer (`flutter analyze --fatal-infos --fatal-warnings`), GOSL header check (`dart run tool/check_headers.dart`), license allow-list check (`dart run tool/check_licenses.dart`), DEPENDENCIES.md freshness check (`dart run tool/check_dependencies_md.dart`), tool tests (`dart test tool/test/`), Flutter tests (`flutter test`). Plus Android APK build (`ubuntu-latest`) + macOS unsigned IPA build (`macos-latest`) artifact jobs. Phase 5 verifies all green on closing SHA; no new CI work needed.
- **`DEPENDENCIES.md`**: 15 direct deps + dev deps; ALL audit-dated `2026-04-30`. Bulk re-audit with `2026-05-05` dates is a Phase 5 hardening task (re-walk telemetry / license / maintenance status; stamp current dates; CI freshness check stays green throughout).
- **`gh` CLI**: authenticated for `gh run list` / `gh run watch` / `gh run download` IPA + APK artifact retrieval (per Phase 1+ established workflow).
- **SideStore + paired desktop pairing-file + iPhone 17 Pro**: IPA sideload mechanism (per Walks #1–#6 + P4 Walk #1 precedent).
- **`adb` + Pixel 4a (Android 13)**: APK install mechanism (per Phase 1+ established workflow).
- **`share_plus` 12.0.2**: wired for Mail-share on iPhone (Walks #1–#6 + P4 Walk #1 precedent); presents Android sharesheet on Pixel 4a (Gmail / Drive / Files transmission paths).
- **FALSIFICATION-N.md / UAT-N.md template** (Walks #1–#6 + P4 Walk #1 precedent): structural template for Phase 5's `05-FALSIFICATION-1.md` + `05-UAT-1.md` (iPhone walk) and corresponding Pixel 4a evidence docs.

### Established Patterns (Phase 1 + 2 + 3 + 3.1 + 4 lock-in)

- **State management**: plain `StatefulWidget` + `setState` + constructor-injected services via `MapScreenServices` DTO. No Riverpod / Bloc / Provider.
- **Logging**: `package:logging` `infrastructure.mirk.*` family; JSONL body, INFO level, 1-Hz cadence wall-clock-aligned for grep-correlation.
- **Dual-clock**: `Stopwatch.elapsedMicroseconds` for math; `DateTime.now()` ONLY for the `epochSecond` rollup tag.
- **Strict analysis**: `strict-casts`, `strict-inference`, `strict-raw-types`, `use_build_context_synchronously: error`.
- **Pinned versions**: every `pubspec.yaml` dependency strict-pinned (`http: 1.2.0`, never `^1.2.0`); `pubspec.lock` committed.
- **GOSL header** on every new `.dart` file in `lib/` and `test/`.
- **Plan-revise-walk loop**; no hard iteration cap.
- **Walk evidence docs**: per-walk `FALSIFICATION-N.md` + `UAT-N.md`; historical records UNTOUCHED across iterations.
- **Mail-share post-walk** for grep-correlation against `frame_delta` + `sdf` + `fog_transform` + `wisp` streams.

### Integration Points

- **Repo root**: `VERDICT.md` (NEW) + `PORTBACK.md` (NEW) — final POC artefacts.
- **Phase 5 dir**: `.planning/phases/05-decision-gate/05-CONTEXT.md` (THIS DOC) + `05-PLAN-N.md` (planner output) + `05-FALSIFICATION-N.md` + `05-UAT-N.md` per walk.
- **`DEPENDENCIES.md` re-audit**: in-place row edits — every audit-date stamp updated to `2026-05-05` + telemetry re-grep + license re-check + maintenance re-spot-check. CI freshness check passes throughout.
- **CI workflow**: existing `.github/workflows/ci.yml` already enforces all 7 hardening gates — Phase 5 verifies all green on the closing SHA (no new CI work).
- **No code-side changes required for Phase 5 hardening** beyond DEPENDENCIES.md re-audit + the two new repo-root docs. WalkSimulator stays production-exposed; DEBUG-03 stays known-defect; debug-spiral toggle stays as-is; production-fog code path is frozen at the Phase 4 closing state (`eec9087` + closing-SHA delta if any).

</code_context>

<specifics>
## Specific Ideas

- **The verdict is PORT BACK with caveats.** Phase 3.1 Walk #6 (`d753176`) + Phase 4 Walk #1 (`eec9087`) already established this empirically. Phase 5 formalizes it as a committed artefact for the MirkFall porter. The "caveats" framing is honest about inherited limitations (DEBUG-03 / UX-02 / in-memory storage / default basemap / iOS-primary) without watering down the CONFIRMED verdict.
- **`PORTBACK.md` is the CODE-DONOR MANIFEST flowing in reverse.** PROJECT.md "Battle-tested code to port from MirkFall" originally listed components flowing FROM MirkFall TO POC; the Phase 3.1 + Phase 4 fix bundle now flows back the other way (POC → MirkFall) layered on top of the donor base. PORTBACK.md is the porter's surgical guide for that reverse port.
- **Pixel 4a is informational (PERF-06 soft criterion), but Phase 5 treats it with the same rigor as iPhone** (Mail-share + same regimes including C3' extreme-distance + same metric capture). Cross-platform parity over PERF-06's "soft" framing — better to have Adreno 618 numbers on the record than to inherit ambiguity at MirkFall integration time.
- **Free-form walk regimes with rigorous post-walk JSONL reconstruction** is the developer's preferred shape. Consistent with Phase 3.1 "validate first, architect later" philosophy. The walk IS the answer; JSONL gives quantitative receipts. Both Phase 3.1 Walk #6 (verbal-decisive) and P4 Walk #1 (verbal-decisive, Mail-share waived) closed cleanly under this regime.
- **Iteration is structurally permitted** (no hard cap) but in practice Phase 5 should close in 1–2 walks per platform — both predecessor closures (3.1 Walk #6 + P4 Walk #1) closed cleanly. If iteration triggers (Phase 5 walks surface a regression), a Phase 5.1 inserted phase mirrors the Phase 3.1 pattern; the verdict simply waits.
- **WalkSimulator is the load-bearing test infrastructure** for both Phase 5 walks. Without it, wisp spawning at desk requires real outdoor GPS progression — incompatible with reproducible Phase 5 closure walks. WalkSimulator's path-emit shape was validated by P4 Walk #1; it ports back to MirkFall as part of the donor manifest (debug helper).
- **No code-side production-fog changes in Phase 5.** The fix bundle is frozen at Phase 4 closing state. Phase 5 = walk validation + repo hardening + verdict + port-back artefacts. Any production-fog code change requires Phase 5.1 (regression triggered by walk).

</specifics>

<deferred>
## Deferred Ideas

- **README.md authoring at repo root** (project landing page consolidating verdict + port-back pointers + getting-started for the porter) — deferred unless the planner judges it on the closure path. VERDICT.md + PORTBACK.md may be sufficient self-introduction.
- **Archived `old` branch cleanup from Phase 3.1** — leave for posterity / historical record. Branch holds Plans 03.1-11→16 (FOG-18 world-meter + Fix B' + Worley periodic) iteration that converged on `DENIED-final` at Walk #6 before `main` was reset to `b31766f`. Cautionary tale; not deletable scope.
- **MIRK-01 architectural ABI formalization** (uniform-list inspection + behavioural swap-shader test + zero-painter-branching invariant + ABI source-of-truth doc) — Phase 3.1 deferral carries forward unchanged. Conceptual MIRK-01 (standardized ABI between `_FogPainter` and any conforming shader) is implicitly seeded by `uPixelOrigin` slot 3..4 + `uZoomScale` slot 41; formalization stays out of scope.
- **MIRK-01 acceptance test trio** (static + behavioural + audit) — tied to MIRK-01 formalization; deferred with it.
- **ABI uniform rename `uPixelOrigin` → `uWorldOffset`** — tied to MIRK-01; deferred.
- **JSONL field rename `uOffsetX*` → `uWorldOffsetX*`** — deferred indefinitely; legacy names kept for grep-tool compatibility with Walks #1–#6 + P4 Walk #1 session logs.
- **DEBUG-03 numbered shader fix** (digit-atlas / unique-cell-numbers regression introduced by Plan 03.1-14 Task A) — known-defect; cleanup deferred indefinitely; debug-shader-only; no production impact.
- **Walk-replay tool** (record GPS once, replay on Pixel 4a / Windows desktop) — deferred since Phase 3; WalkSimulator is the practical equivalent for Phase 5 closure walks.
- **`p99Ms` field on `FrameDeltaProbe`** — Phase 3 deferred; Phase 5 doesn't reopen.
- **`tool/extract_walk.dart` helper** (auto-extract probe + SDF + fog-transform + wisp stats from JSONL) — manual `grep` + `jq` suffices for Phase 5 closure walks.
- **`MapView` domain abstraction** — locked OUT of POC scope per PROJECT.md (migration concern; MirkFall-side decision).
- **Pivot to alternative renderers** (`mapsforge_flutter`, custom MVT-on-Canvas, `flutter_gpu`) — Phase 3.2 path obviated by Phase 3.1 + Phase 4 CONFIRMED verdict.
- **Wisp shader (FragmentProgram alternative to drawCircle)** — deferred per Phase 4 Q1 decision (PERF-07 headroom + Phase 3.1 dimensional-mismatch precedent argued for Canvas API simplicity).
- **GPU instancing / GLSL compute** — out of POC scope; v2 / MirkFall port-back concern if Pixel 4a walks reveal CPU bottleneck at higher disc volumes.
- **WISP-06 acceptance criterion** (formal shader-agnosticism CI gate) — deferred per Phase 4 decision (architectural property documented in `_FogPainter._renderWisps` docstring + 04-CONTEXT.md, not CI-grep-enforced).
- **Tap-to-spawn / interactive wisps** — new capability; not on closure path.
- **Persistent disc state across sessions** — out of POC scope (PROJECT.md scope: in-memory storage only).
- **Phase 5.1 inserted phase** — only triggers if Phase 5 walks surface non-trivial issues; default expectation per Phase 3.1 Walk #6 + P4 Walk #1 precedent is single-walk closure per platform.
- **Multiple mirk styles** (atmospheric only per PROJECT.md) — out of POC scope.
- **Custom MirkFall basemap styling** (`#f5f1e8` / `#a6c9df` / etc. via `Theme` object) — out of POC scope per PROJECT.md; MirkFall-side concern at port-back time.
- **`MirkInitialRevealFade`** — visual polish; not on hypothesis path; out of POC scope per PROJECT.md.
- **`Permission.locationAlways` + notification permissions** — out of POC scope (POC only needs `locationWhenInUse`).

</deferred>

---

*Phase: 05-decision-gate*
*Context gathered: 2026-05-05*
