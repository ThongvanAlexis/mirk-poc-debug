# Phase 3: Fog of War — THE HYPOTHESIS - Context

**Gathered:** 2026-05-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Render `atmospheric_fog.frag` in the same Flutter Canvas as the `flutter_map` tile layer, driven by an in-memory disc list and a 256×256 R-channel midpoint-128 SDF. Wire the frame-delta self-debug probe (FOG-08) so each camera-to-fog-paint delta is measurable on-device and persisted to the log. Walk the falsification criteria on iPhone 17 Pro through Melun — the phase deliverable is a binary answer to the architectural hypothesis (same-Canvas eliminates the lag, or it does not). A "denied" outcome is a scientifically valid POC result that terminates the project; a "confirmed" outcome unlocks Phase 4.

Covers REQUIREMENTS.md FOG-01..08, PERF-03/04/05.

Out of scope for this phase: wisp particles (Phase 4), Pixel 4a walk-to-pass (Phase 3 records informational FPS only; no hard gate), final POC verdict promotion to repo root (Phase 5), MirkFall basemap theme (v2), worker-isolate SDF rebuild (deferred to MirkFall migration), `MapView` domain abstraction (migration concern), DB-backed disc persistence (PROJECT scope: in-memory only).

</domain>

<decisions>
## Implementation Decisions

### SDF rebuild policy
- **Trigger:** rebuild whenever `(disc list, viewport bbox, mean lat)` hash changes. The donor `RevealedSdfBuilder` docstring is the authoritative source — input-change-driven rebuild with hash-based caching.
- **During pan/zoom/rotate:** rebuild every frame. At POC disc counts (~5–50 discs over a 5-minute Melun walk), the cost is well under 1 ms (donor file's `~67 k pixel updates × disc-count` cost — the documented 16 ms bound applies to a 4-hour-session 1000-disc scenario, not POC scale).
- **During idle:** hash matches → reuse cached `ui.Image`, free.
- **On new GPS fix:** disc-list mutation → hash mismatches → rebuild.
- **Reading of FOG-03 ambiguity:** "rebuilt when the disc list changes" is incomplete wording — it states a sufficient condition for rebuild, not the only one. The donor docstring (`The renderer should rebuild it when EITHER changes`) is authoritative. Keep `uSdfRect = identity (0, 0, 1, 1)` per locked architecture.
- **Researcher must verify on iPhone 17 Pro:** measure actual rebuild ms at 50 discs / 256² SDF / typical viewport during Phase 3 research; document numbers in RESEARCH.md. If they exceed expectations and the falsification probe shows budget pressure, fall back to a 60 Hz cap on a 120 Hz device (default OFF; documented as a fallback knob).

### Disc-list ownership
- **Defer to planner:** mirror the parent MirkFall `RevealDiscRepository` shape so the POC port-back is mechanical. Likely lands as a small `RevealDiscRepository` wired through `MapScreenServices` (constructor-injected, alongside the existing `pmtilesPath`, `positionStreamFactory`, `logger`). Planner reads parent code, adopts the surface verbatim where renderer-agnostic, documents adaptations.

### FogLayer z-order
- **Default order:** tiles → FogLayer → BlueDot CircleLayer (planner discretion). The blue dot always sits at the user's GPS fix, and every fix spawns a 25 m reveal disc around that fix — so the dot is always inside a clear hole, regardless of z-order. No visual conflict; pick the cleanest order for the planner.
- **No `RepaintBoundary` around `FogLayer`** (locked from RESEARCH §Anti-patterns — would re-create BUG-014 inside Flutter).

### SDF rebuild logging
- **Cadence:** 1-second rollup. Per-active-second emit one structured JSONL line via `Logger('infrastructure.mirk.sdf')` with: `discCount`, `intersectingDiscCount`, `rebuildCount`, `medianMs`, `p95Ms`, `maxMs`. Aligned with the frame-delta probe's persistence cadence so timelines line up post-walk ("at second 47, fog probe was 28 ms p95 + SDF rebuilt 4× at 1.2 ms median").
- **No per-rebuild line** during sustained pan (would emit ~120 lines/sec on iPhone 17 Pro). Per-rebuild stats roll up into the per-second summary; raw outliers can still be reconstructed from the rollup's max field.
- **Idle seconds:** no log line (only emit on active rebuilding seconds).

### Frame-delta probe — overlay UX
- **Placement:** top-right under MapCompass. Stack vertically with FpsCounterOverlay (top:8) → MapCompass (top:56) → FrameDeltaProbe overlay (top: ~104, right:8). Right-aligned HUD cluster.
- **Format:** three lines — `med {N} ms / p95 {N} ms / max {N} ms`.
- **Color-coding:** green / yellow / red against the falsification thresholds.
  - Median: green ≤16 ms, yellow ≤24 ms (50% over), red >24 ms (still showing >16 ms threshold; this is the falsifier).
  - p95: green ≤32 ms, yellow ≤48 ms, red >48 ms.
  - Max: green ≤48 ms, yellow ≤72 ms, red >72 ms.
  - The walker sees at a glance whether the falsification gates hold mid-walk. Each value computed independently; the worst color among the three drives the developer's visual attention.
- **Update cadence on overlay:** 1 Hz refresh (matches the per-second log rollup). Avoids per-frame UI churn.

### Frame-delta probe — log persistence
- **Cadence:** 1-second rollup. One JSONL line per active second via `Logger('infrastructure.mirk.frame_delta')` with: `sampleCount`, `medianMs`, `p95Ms`, `maxMs` (and optionally `p99Ms` if cheap). Matches the SDF log cadence.
- **No per-frame raw lines** (~120 lines/sec on iPhone 17 Pro pan = 36k lines per 5-min walk; rolling-up loses outlier ms but the `max` field preserves it).
- **Probe instrumentation point:** measure delta as `(timestamp of fog uniform population) − (timestamp of latest map camera update)` per FOG-08. Single source of truth for "camera update time" is the same `MapCamera` snapshot read once at the top of `FogLayer.build()` (FOG-07 lock). Researcher locks the timestamp source — likely `Stopwatch.elapsedMicroseconds` or `DateTime.now().microsecondsSinceEpoch` depending on monotonicity needs.

### Falsification document
- **Location:** `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md`. Lives alongside other Phase 3 artifacts (PLAN.md, RESEARCH.md, this CONTEXT.md, eventual UAT.md). Naturally archived when Phase 3 closes.
- **Pre-walk content (written BEFORE the walk, committed BEFORE the iPhone build that gets sideloaded for the walk):**
  - Hypothesis statement (one paragraph) re-stating what "confirmed" / "denied" mean for the MirkFall migration.
  - **Criterion A** (frame-delta thresholds, quantitative from FOG-08 probe): median ≤16 ms, p95 ≤32 ms, max ≤48 ms across ≥10 combined gestures over a 5-min walk.
  - **Criterion B** (subjective visual lock from PERF-05): no fog slide-then-snap, no white-ellipse on fast pinch-zoom, no perceptible reveal-hole lag behind the blue dot, no inversion at any zoom.
  - **Criterion C explicitly DROPPED** per locked decisions (parent-FPS comparison removed from POC scope).
- **Walk plan section:** the doc's pre-walk section also re-states the walk shape from PERF-03/04 (≥5 min Melun, ≥10 combined pinch-zoom-and-pan gestures, ≥3 recenter taps, FPS counter visible, log shared via Mail post-walk).
- **Post-walk evidence:** manual paste — developer walks, returns, opens the shared log file from Mail (LOG-04 / share_plus), pastes the relevant frame-delta probe lines + SDF rebuild lines + FPS readings + screenshots into the doc, writes the subjective verdict (PERF-05) by hand. No tool/extract_walk.dart helper for Phase 3 (deferred).
- **Verdict location:** appended at the end of the same `03-FALSIFICATION.md` doc. Single self-contained artifact: hypothesis → criteria → walk plan → walk evidence → verdict (confirmed / denied / confirmed-with-caveats).
- **Phase 5 promotion (deferred):** ROADMAP §Phase 5 success criterion 4 says the formal verdict goes at repo root. Phase 5 will copy/promote the verdict from `03-FALSIFICATION.md` to a top-level `POC_VERDICT.md` (or similar) for MirkFall-migration discussion, adding the Pixel 4a sanity-walk evidence (PERF-06). Phase 3 is not responsible for that promotion.

### Shader-sanity screen
- **Entry:** new AppBar action button on `/map` next to the existing share-logs button. Icon: `Icons.science` (planner's pick if a stronger candidate exists in `cupertino_icons` 1.0.9 already pinned). Tap → navigate to `/sanity` (new GoRouter route).
- **Tooltip:** localized via `AppLocalizations` like the share button — French + English.
- **Hardcoded uniforms:** kMirkFog* constants from `lib/config/constants.dart` for all 41 floats. Sampler 0 (uSdf): synthetic SDF built in code on screen mount — one 80 m radius disc at the viewport center. The SDF builder runs against a fake `MirkViewportBbox` sized to the device viewport. No committed PNG fixture; no multi-fixture cycle.
- **Pass criterion (subjective):** developer opens `/sanity`, confirms (a) fog renders with the documented atmospheric look, (b) a circular reveal hole appears centered on screen (proves SDF→shader path works), (c) no shader compile errors / no exceptions in the FileLogger output. Verbal "approved". Matches the POC's existing UAT pattern from Phase 1 / Phase 2.
- **No golden-image diff / no automated frame-capture test** for Phase 3. The POC has no test_driver or golden-test infrastructure; adding it for one screen is over-investment. Slot-reorder regression (parent BUG-014 Iter 2) is defended by the existing `setAll` wrapper in `fog_shader_uniforms.dart` (single source of truth — slot indices hand-counted to match the `.frag` declaration order; if either side changes, BOTH update together by virtue of how `setAll` is structured).
- **Lifecycle:** stays in the POC indefinitely. Debug-only (POC has no production / debug split per LOG-02 — always Level.ALL). Costs nothing post-walk; preserves a known-working shader-load path for Phase 4 wisp work and the eventual MirkFall port-back.

### Forward decisions for Phase 4 (locked here)
- **Wisp particle z-order:** wisps render ABOVE FogLayer (semantic: wisps are atmospheric particles emerging from the fog at disc perimeters). Phase 4 planner takes this as locked.
- **`MapCamera` snapshot discipline carries over:** wisps must use the SAME single `MapCamera.of(context)` read that FogLayer uses, captured atomically per build. Phase 4 planner takes this as locked from RESEARCH §Anti-pattern 3.

### Claude's Discretion
- Exact icon glyph for the shader-sanity AppBar action (`Icons.science`, `Icons.bug_report`, `Icons.layers` etc.) — bias toward Material icons; planner picks the most legible at iPhone 17 Pro density.
- Exact tooltip strings for the sanity button and probe overlay (French + English via `AppLocalizations` like Phase 1 + Phase 2).
- Exact yellow-threshold mid-band cutoffs (50% over the green threshold is the working assumption; planner can tune by ±25% based on visual ergonomics during a smoke walk).
- Exact JSONL field names for the SDF rollup and probe rollup logs (planner picks names that grep cleanly post-walk; `medianMs`/`p95Ms`/`maxMs` is a working baseline).
- Whether to add a tiny "rebuilds: N" counter line to the probe overlay if it adds clarity at no cost.
- Frame-delta probe instrumentation timestamp source (`Stopwatch.elapsedMicroseconds` vs `DateTime.now().microsecondsSinceEpoch` vs `clock_gettime` via FFI) — researcher picks based on iPhone Impeller monotonicity needs.
- Whether `RevealDiscRepository` is its own file under `lib/domain/revealed/` or composed into the existing `lib/domain/revealed/reveal_disc.dart` — planner picks based on parent project layout.
- The exact `kMirkFog*` constant set chosen for the shader-sanity screen synthetic SDF (the Phase 1 BOOT-08 port already brought the kMirkFog* family into `lib/config/constants.dart`; planner picks reasonable defaults).
- Whether the in-flight per-frame probe samples are kept in a ring buffer or computed as streaming statistics (Welford / P² estimator) — planner picks based on memory-vs-precision trade-off; ring buffer is the obvious starting point.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets — already ported in Phase 1 (BOOT-08)
- `assets/shaders/atmospheric_fog.frag` (393 lines, 41 float uniforms + 1 sampler — verbatim from MirkFall, BUG-014 Iter 2 slot-reorder fix preserved). Already declared in `pubspec.yaml` `flutter.shaders`.
- `lib/infrastructure/mirk/sdf/revealed_sdf_builder.dart` (244 lines) — 256×256 R-channel midpoint-128 SDF, distance computed in metres (BUG-011 fix). `buildFromDiscs(discs, viewport)` returns `Future<ui.Image>`. Stateless builder; can be `const` constructed.
- `lib/infrastructure/mirk/shader/fog_shader_uniforms.dart` (162 lines) — `setAll()` populates all 41 slots in one call. Single source of truth for slot layout.
- `lib/infrastructure/mirk/mirk_projection.dart` (59 lines) — lat/lon ↔ screen Offset; consumed by FogLayer + (Phase 4) WispLayer.
- `lib/infrastructure/mirk/tile_cell_iteration.dart` (76 lines) — disc/tile intersection helpers.
- `lib/infrastructure/mirk/animation_helpers.dart` (29 lines) — animation utilities.
- `lib/domain/mirk/mirk_viewport_bbox.dart` (58 lines) — `MirkViewportBbox(north, south, east, west)` value object consumed by SDF builder.
- `lib/domain/revealed/reveal_disc.dart` (249 lines) — `RevealDisc(lat, lon, radiusMeters, fixedAt)` value object. `intersectsBbox(viewport)` already implemented.

### Established Patterns (Phase 1 + Phase 2 lock-in)
- **State management:** plain `StatefulWidget` + `setState` + constructor-injected services via `MapScreenServices` DTO. No Riverpod. Locked across project.
- **Path joining:** `package:path` `p.join()` everywhere — no `'/'` concatenation (CLAUDE.md).
- **GOSL header:** every `.dart` file in `lib/` and `test/` carries the 3-line copyright/license header. CI gate enforces.
- **Strict analysis:** `strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`, `use_build_context_synchronously: error`. `if (!mounted) return;` after every `await` involving the BuildContext.
- **Localization:** all in-app strings (sanity button tooltip, probe overlay labels if any, sanity-screen body text) via `AppLocalizations`. French primary, English secondary.
- **Routing:** all transitions use `context.go()` — full pile reset, no back navigation. Adding `/sanity` follows the same pattern.
- **Logging:** hierarchical loggers — `infrastructure.mirk.sdf` for SDF rebuilds, `infrastructure.mirk.frame_delta` for the FOG-08 probe, `presentation.fog_layer` if needed for FogLayer lifecycle.
- **Pinned versions:** any new dev_dependency or runtime dep introduced in Phase 3 must be strictly pinned (no `^`). Audit row added to `DEPENDENCIES.md`. CI license-check job runs on every push.
- **Constants:** `lib/config/constants.dart` already holds `kMirkFog*`, `kMetersPerDegreeLat`, `kEarthRadiusMeters` plus the kPocPmtiles/kPocMapCamera Phase 2 family. Phase 3 adds: `kPocFrameDeltaProbeOverlayTopPx = 104`, `kPocSdfLogRollupSeconds = 1`, `kPocFrameDeltaLogRollupSeconds = 1`, plus any per-color threshold constants if not already covered by `kMirkFog*`.

### Integration Points
- **`MapScreen` body Stack:** add `FogLayer` as a child of the existing `FlutterMap` (currently has `VectorTileLayer` + conditional `CircleLayer<Object>` for blue dot). FogLayer goes between tile layer and blue dot in `children: <Widget>[...]`.
- **`MapScreenServices` DTO:** extend with the new `RevealDiscRepository` (or whatever shape the planner chooses to mirror parent). Production: built in `app.dart` / `router.dart` `/map` builder. Tests: faked.
- **GPS subscription:** existing `_subscribeToPositions` listener already in `_MapScreenState` (Phase 2). Phase 3 extends it: every fix → `RevealDiscRepository.append(RevealDisc(fix.latitude, fix.longitude, 25.0, DateTime.now()))`. The repo's mutation triggers SDF rebuild via the disc-list-change branch of the hash.
- **AppBar:** add a third action to `buildPocAppBar` for the shader-sanity entry button. Existing helper signature already accepts arbitrary actions; minor edit, no structural change.
- **Router:** add `/sanity` route to `lib/presentation/router.dart` mapping to `ShaderSanityScreen`.
- **`pubspec.yaml`:** no new dependencies expected for Phase 3 (FlutterMap layer API + FragmentProgram are SDK; SDF builder is pure Dart). If the researcher recommends a perf or testing dep, it gets the standard audit treatment.
- **Falsification document:** `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` — the planner creates the pre-walk version as part of Phase 3 plan execution; the developer appends evidence + verdict post-walk.

### Files to create (planner expectation)
- `lib/presentation/widgets/fog_layer.dart` — the FlutterMap custom layer (`MapCamera.of(context)` read once per build; computes clip path, populates 41 shader uniforms via `FogShaderUniforms.setAll()`, draws the shader).
- `lib/presentation/widgets/frame_delta_probe_overlay.dart` — the on-screen 3-line overlay; subscribes to the probe stream; renders med/p95/max with green/yellow/red color logic.
- `lib/infrastructure/mirk/frame_delta_probe.dart` — singleton (or constructor-injected) probe collector. Records per-frame `(cameraUpdateMicros, fogPaintMicros, deltaMicros)` triples; exposes a `Stream<FrameDeltaRollup>` at 1 Hz. Also writes the 1-second JSONL log line.
- `lib/domain/revealed/reveal_disc_repository.dart` (likely) — the in-memory disc list + change-notification surface. Planner mirrors parent shape.
- `lib/presentation/screens/shader_sanity_screen.dart` — the sanity screen. Builds a synthetic SDF on mount, renders the fog shader with kMirkFog* defaults.
- `lib/infrastructure/mirk/sdf_rebuild_logger.dart` (or inline in the SDF builder caller) — 1-second rollup of SDF rebuild stats, emits one JSONL log line per active second.
- `.planning/phases/03-fog-of-war-the-hypothesis/03-FALSIFICATION.md` — pre-walk written by planner; evidence + verdict appended by developer post-walk.
- `test/...` siblings — unit tests for FOG-07 (single MapCamera snapshot), distance-in-metres assertion (`distanceMetres((48.5, 2.6), (48.5, 3.6)) ≈ 73.7 km`), shader uniform slot count (must equal `FogShaderUniforms.totalFloatSlots`), probe rollup correctness, SDF hash-cache hit/miss correctness.

</code_context>

<specifics>
## Specific Ideas

- **The 16 ms cost number was misread early in discussion.** That bound is for a 4-hour-session 1000-disc scenario per the donor SDF builder docstring. The POC's 5-min walk holds tens of discs, not thousands. Researcher must measure the actual rebuild ms on iPhone 17 Pro in Phase 3 research and document the real numbers in RESEARCH.md so the planner builds against measurements, not estimates.
- **Per-frame SDF rebuild during pan IS the right answer.** The fog must track the camera frame-by-frame; anything else creates a slidey/laggy reveal area that re-creates the BUG-014 symptom inside Flutter (different cause, identical visible behaviour). The donor file's hash-cache makes this cheap (idle frames are free).
- **`FogShaderUniforms.setAll()` is the load-bearing single-source-of-truth for the 41-slot layout.** Don't bypass it. Don't reorder slots. The slot indices were hand-counted to match the `.frag` uniform declaration order, and the parent BUG-014 Iter 2 fix was the slot-reorder regression that motivated this discipline. Any Phase 3 code that touches uniform slots goes through `setAll()`.
- **Identity uSdfRect is non-negotiable.** RESEARCH §Anti-Pattern 1: dynamic uSdfRect re-introduces BUG-014 root cause. If the planner is tempted to "optimize" by varying uSdfRect, that's a regression — flag and stop.
- **Single-`MapCamera`-snapshot discipline is non-negotiable.** RESEARCH §Anti-Pattern 3 + Pitfall 10: multiple `MapCamera.of(context)` reads per build re-introduce BUG-014's white-ellipse symptom. FOG-07 unit test enforces. Planner adds the test before the walk.
- **The frame-delta probe IS the falsifier.** Wire it BEFORE building FogLayer. If FogLayer ships and we discover the probe wasn't quite right post-walk, that's a wasted iPhone walk. Pre-walk gates (success criterion 1) require the probe to render on the overlay — that gates the build itself, not just the walk.
- **Log timeline alignment is a hard requirement.** SDF rebuild rollup + frame-delta probe rollup MUST share the same 1-second cadence so post-walk grep can correlate timelines. If rollup boundaries drift (e.g. one is wall-clock-aligned, the other is probe-start-aligned), the post-walk analysis becomes guesswork. Planner picks one cadence source (likely `Logger`-side `DateTime.now().millisecondsSinceEpoch ~/ 1000`) and both rollups derive from it.

</specifics>

<deferred>
## Deferred Ideas

- **`tool/extract_walk.dart` helper** for auto-extracting probe + SDF stats from the JSONL log into a Markdown evidence block. Phase 3 manual-paste is fine for one walk; if Phase 4/5 walks accumulate or if iteration cost gets painful, build the tool then.
- **Golden-image diff for the shader-sanity screen.** No test_driver / flutter_test golden infrastructure exists in the POC; standing it up for a single screen is over-investment. Reconsider during MirkFall port-back if parent project already has the infrastructure.
- **Frame-delta probe `p99Ms` field.** Working baseline is `medianMs / p95Ms / maxMs`. Adding `p99Ms` is cheap if the planner picks a percentile-friendly aggregator (Welford / P²) — or a no-op if streaming-stats are off the table. Decide at planner level based on aggregator complexity.
- **Probe overlay yellow-band cutoffs (50% over green).** Working assumption: yellow = green-threshold × 1.5. If walk evidence shows yellow misfires too often (everything's yellow even on a clean walk), tighten. Phase 3 walks the default; tune if needed.
- **Walk-replay tool** (Phase 1 / Phase 2 deferred item) — record GPS fixes during a walk, replay on Pixel 4a / Windows desktop without re-walking. Would save iPhone-walk cost during Phase 3 iteration. NOT in Phase 3 scope; if Phase 3 fails the falsification gates and needs a second walk, build this then before iteration 2.
- **Per-rebuild raw JSONL line for the SDF logger.** Default is 1-second rollup; raw per-rebuild lines are noise at 120 Hz pan. If post-walk analysis needs single-rebuild outliers, add a temporary `--dart-define=SDF_LOG_RAW=true` build-time toggle that opens the per-rebuild firehose.
- **Phase 5 verdict promotion to `POC_VERDICT.md` at repo root.** ROADMAP §Phase 5 success criterion 4 specifies a top-level verdict artifact; Phase 5 copies/promotes from `03-FALSIFICATION.md` (adding Pixel 4a sanity walk evidence per PERF-06). Phase 3 is not responsible for the promotion.
- **Pixel 4a Phase 3 walk** (PERF-06 informational FPS recording). REQUIREMENTS PERF-06 schedules it for Phase 3 + Phase 5 with no hard pass criterion. Phase 3 plan should produce a debug APK from CI and let the developer walk Pixel 4a opportunistically; the result lands in `03-FALSIFICATION.md` as informational data only. If the iPhone walk fails the falsification gates, the Pixel 4a walk is moot — postpone.
- **Cross-restart auto-resume routing bug** (deferred from Phase 1 AUTH-04). Not in Phase 3 scope.
- **AUTH-04 cross-restart re-grant flow** — irrelevant to Phase 3 (the user grants permission once, walks, no re-grant happens during a walk). Stays deferred.
- **Worker-isolate SDF rebuild** — UI isolate is sufficient at POC scale. Migration concern (ROB-01).

</deferred>

---

*Phase: 03-fog-of-war-the-hypothesis*
*Context gathered: 2026-05-01*
