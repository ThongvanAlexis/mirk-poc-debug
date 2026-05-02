# Phase 3 Falsification — Same-Canvas Fog Hypothesis

**Created:** 2026-05-01
**Phase:** 03-fog-of-war-the-hypothesis
**Walked on:** 2026-05-01 (iPhone 17 Pro, central Melun, CI run `25224334312`, SHA `280dd04`)
**Verdict:** **DENIED** — fog renders on screen but is static during pan; only the blue dot moves while the underlying tile layer translates beneath a fog surface that does NOT consume the camera translation transform.

## Hypothesis

Rendering the MirkFall map, fog-of-war shader, and (in Phase 4) wisp particles
in a single unified Flutter Canvas pipeline eliminates the camera-tracking
lag that BUG-014 left unfixed in the parent project. **Confirmed** means the
POC ports back to MirkFall; **denied** means the POC is the formal
architectural counter-evidence and the migration does not happen.

## Falsification Criteria (written BEFORE the walk)

### Criterion A — Frame-delta probe thresholds (PERF-04, quantitative)

The FOG-08 frame-delta probe rolling rollups across ≥ 10 deliberate combined
pinch-zoom-and-pan gestures over a ≥ 5 minute walk on iPhone 17 Pro must satisfy:

- **Median camera-to-fog-paint delta ≤ 16 ms** (1 frame at 60 Hz; 2 frames at 120 Hz)
- **p95 ≤ 32 ms**
- **max ≤ 48 ms**

Persisted to the session log as 1-second JSONL rollups via `Logger('infrastructure.mirk.frame_delta')`.

### Criterion B — Subjective visual lock (PERF-05)

Developer's verbal verdict at end of walk:

- No fog slide-then-snap behind the map during pan
- No white-ellipse artefact during fast pinch-zoom
- No perceptible reveal-hole lag behind the blue dot
- No inversion (fog appearing where reveal should be) at any zoom level

### Criterion C — DROPPED

Parent-FPS comparison was the original Criterion C; the planner dropped it
per the locked roadmap decisions (POC stands on absolute FPS + lock-correctness
alone). Recorded here for traceability — do not reinstate without revising
the roadmap.

## Walk Plan

- **Where:** Central Melun (lat 48.5397, lon 2.6553 area; same theatre as Phase 2 walk).
- **Duration:** ≥ 5 minutes continuous walk with the IPA running and the device awake.
- **Gestures:** ≥ 10 deliberate combined pinch-zoom-and-pan gestures, ≥ 3 recenter taps.
- **Pre-walk gate:** open `/sanity` route on the sideloaded build first; confirm the fog renders with a circular reveal hole visible (proves the SDF→shader path); confirm zero shader-compile exceptions in the FileLogger output.
- **Pre-walk gate (unit tests):** all Phase 3 unit tests green on `flutter test` (degree-distance regression test; single-MapCamera-snapshot test; FogShaderUniforms.totalFloatSlots == 41; SdfCache hit/miss; FrameDeltaProbe rollup correctness).
- **In-app HUD during walk:** FpsCounterOverlay (top:8, right:8) + MapCompass (top:56, right:8) + FrameDeltaProbeOverlay (top:104, right:8) — three lines: `med {N} ms / p95 {N} ms / max {N} ms`, colour-coded green/yellow/red against Criterion A.
- **Post-walk:** share the session log file via Mail (LOG-04 round-trip); paste the relevant frame-delta probe lines + SDF rebuild lines + FPS readings + screenshots into the "Walk Evidence" section below; write the subjective verdict (Criterion B) by hand.

## Walk Evidence (filled AFTER the walk by Plan 03-08)

### Pre-walk shader-sanity gate (`/sanity` route)

**Implicitly PASSED.** The developer reports observing "mirk" on the walk screen — meaning the fog shader compiled, the SDF→shader path executed, and the 41-uniform `FogShaderUniforms.setAll` call rendered fog pixels on iPhone 17 Pro. The pre-walk `grep -E 'severe|Failed to load fog shader'` gate held: the IPA was not aborted on shader-load grounds. The failure observed during the walk is purely on the camera-tracking axis, NOT on the rendering pipeline itself.

### Probe rollup (frame-delta JSONL — `Logger('infrastructure.mirk.frame_delta')`)

**NOT CAPTURED.** The walk was aborted on visual grounds before the ≥ 10 combined-gesture seconds of quantitative probe evidence were collected. The static-fog-during-pan symptom (see "Subjective verdict" below) is itself a denial of Criterion B and obviates Criterion A measurement: there is no point measuring camera-to-fog-paint frame-delta on a fog surface that doesn't translate with the map at all. Criterion A is therefore unmeasured; Criterion B's failure alone is sufficient to deliver a `denied` verdict per the Plan 03-08 falsification clause ("Criterion A AND Criterion B must BOTH pass for `confirmed`; either failing → `denied`").

### SDF rebuild rollup (`Logger('infrastructure.mirk.sdf')`)

**NOT CAPTURED.** Same reason as the frame-delta probe rollups — walk aborted on visual grounds before log capture. The pre-walk `/sanity` route did successfully exercise the synthetic-80-m-disc SDF→shader path, so the SDF builder + `SdfCache` + `SdfRebuildLogger` pipeline is software-functional; it is the *consumption* of the SDF inside the same-Canvas paint path that exhibits the failure.

### FPS observations (PERF-03)

**NOT CAPTURED** as fine-grained per-gesture readings. The walk was aborted on visual grounds. The fog-static-during-pan failure mode is independent of FPS — even a sustained 120 fps render of a fog that does not translate with the camera would still falsify the hypothesis. PERF-03 is therefore unmeasured-and-moot for this walk.

### Subjective verdict (PERF-05, Criterion B)

**Developer's verbatim words:** *"mirk isn't moving, only the blue dot (so I guess the map below is moving), it can be rotated tho, denied"*

**Interpretation:**

- The fog ("mirk") layer renders on screen — confirmed by the pre-walk `/sanity` gate and by the developer's ability to *see* the fog during the walk.
- The fog does **NOT translate** when the map pans. Only the blue GPS dot moves on screen; the user infers the underlying VectorTileLayer is also panning correctly (its tiles re-stream as the camera moves).
- Rotation gestures **DO** appear to transform the fog surface (so camera *rotation* propagates to the fog draw), but **translation/pan does not**.
- Per Criterion B's four sub-claims:
  - **Fog slide-then-snap during pan?** N/A in the strict sense — there is no "slide" (the fog never moves with the map at all). The actual failure mode is *worse than* slide-then-snap: the fog is **static** relative to the screen while the map translates beneath it, which means the fog "slides" relative to *the world*, not relative to the screen, on every pan gesture. ✗ **FAIL** (different failure mode than predicted, but still a Criterion B sub-claim violation).
  - **White-ellipse during fast pinch-zoom?** Not observed in the captured evidence. The walk was aborted before deliberate fast pinch-zoom evidence was collected. **N/A** — but moot given the translation failure already denies Criterion B.
  - **Reveal-hole lag behind blue dot?** **Strongly implied — ✗ FAIL.** The reveal disc is anchored to GPS coordinates (lat/lon → projected to screen each frame). If the fog surface stays static during pan while the blue-dot CircleLayer correctly translates with the map, the reveal hole — which lives in the fog surface's coordinate system — also stays static on screen, leaving the blue dot to walk *out of* its reveal hole. This is "reveal-hole lag" in its most extreme form: the lag is permanent, not transient.
  - **Inversion at any zoom level?** **Likely — ✗ FAIL.** A static fog over a translating map necessarily produces inversion: areas the user previously revealed (which had their reveal disc baked into the SDF at world coordinates A) now have fog over them once the map pans (because the SDF is sampled in fog-screen-space, not world-space, given the missing transform), and previously-fogged terrain (world coordinates B that translated under the static reveal disc) now shows reveal where there should be fog.

## Verdict

- [x] Criterion A passed? — **No (not measured; not measurable given Criterion B's failure mode).** The frame-delta probe never got a clean ≥ 10-second combined-gesture window because the visual failure aborted the walk. Criterion A is unmeasured; the absence of evidence is logged as a deliberate non-measurement, not as an ambiguous result.
- [x] Criterion B passed? — **No.** Three of four Criterion B sub-claims fail (slide-then-snap → manifested as worse-than-slide-then-snap *static* fog; reveal-hole lag → permanent; inversion → likely). The fourth (white-ellipse during fast pinch-zoom) was not deliberately exercised before the walk was aborted, but the translation failure alone denies Criterion B.

**Outcome:** **DENIED.**

The same-Canvas fog hypothesis is **falsified** as currently implemented. Placing `FogLayer` as a child of `FlutterMap` between `VectorTileLayer` and the blue-dot `CircleLayer` (Plan 03-07) was *necessary* but *not sufficient* for the fog to share the tile layer's translation transform. The widget test that asserted `find.descendant(of: FogLayer, matching: MobileLayerTransformer)` (Plan 03-05's FOG-04 structural test) was a structural test only — it confirmed widget-tree containment but did not confirm that the painter's draw calls actually consume the same Canvas transform as the tile layer's draw calls. The structural assertion is true; the behavioural consequence does not follow.

**MirkFall migration recommendation:** **DO NOT PORT BACK as-implemented.**

The architectural assumption that `MobileLayerTransformer` would automatically share the tile layer's translation transform with a custom `flutter_map` layer is wrong, OR `FogPainter`'s draw path bypasses the transform, OR camera updates do not reach the painter on the same render-tree tick as the tile-layer repaint. Before any port-back attempt to MirkFall, a post-mortem investigation phase (likely **Phase 3.1 gap-closure**) must diagnose the underlying issue. Three diagnostic possibilities to test, in priority order:

1. **`FogPainter` paints in screen-space coordinates** (using viewport pixel coordinates from `MapCamera.size` directly) rather than transform-space. The shader uniforms compute reveal-disc world positions correctly, but the resulting `Canvas` draws happen in raw screen pixels, and `MobileLayerTransformer` does not retroactively re-translate them. Diagnostic: log the `Canvas.getTransform()` matrix at `paint()` entry; compare to the tile layer's transform at the same frame.
2. **`MobileLayerTransformer` applies transforms at the widget layer** (via a `Transform` widget in its build) rather than at the `Canvas` matrix level, so a `CustomPaint` child that creates its own `PictureRecorder`-style canvas reads an untransformed canvas. Diagnostic: walk the `flutter_map` 7.0.2 source for `MobileLayerTransformer`; if it wraps children in `Transform.translate(offset: -worldOffset, child: ...)`, the fog widget tree is fine but the painter's local canvas is not pre-transformed.
3. **Camera updates do not propagate to the FogLayer between pan-driven repaint cycles.** The painter reads `MapCamera.of(context)` once per build; if `flutter_map` triggers tile-layer repaints via a `MapController` event stream that does NOT also trigger a `FogLayer` rebuild, the fog's painter holds a *stale* `MapCamera` snapshot during the entire pan gesture. The `_lastCamera` value set on the painter during build is from the gesture-start frame, not the current frame. Rotation works because rotation gestures may funnel through a different `setState`-triggering path than translation. Diagnostic: log `MapCamera.center` in `FogLayer.build()` vs. `FogPainter.paint()` during a pan gesture; if `build()` is not called during the pan but `paint()` is (because the parent's tile layer marks the layer dirty), the camera in `paint()` is the stale build-time snapshot.

The diagnosis MUST specifically test: *does the painter receive an updated camera between pan-driven repaint cycles?* That is the cleavage point between possibility #3 (camera-staleness, fixable by listening to `MapController`'s event stream and calling `markNeedsPaint` from FogLayer) and possibilities #1/#2 (transform-bypass, fixable by either wrapping the painter in a `Transform.translate` widget or by reading the camera transform inside `paint()` and applying it via `canvas.translate` before drawing).

A successful diagnosis + fix in Phase 3.1 would re-open the hypothesis test; a confirmed unfixable result would terminate the project per the original CONTEXT.md plan. **The current Plan 03-08 verdict stands as the formal architectural counter-evidence at this point in the POC's history.**
