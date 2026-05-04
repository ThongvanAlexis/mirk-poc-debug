# Shader-fix retrospective — Phase 3.1 (fix-fog-pan-translation)

**Period:** 2026-05-02 → 2026-05-04 (~3 days)
**Iterations:** 6 plan rounds, 8 walks (#1, #2, #3, #3b marker analysis, #4, #5, #6), 15 plans
**Outcome:** `CONFIRMED-AFTER-FIX (FULL)` — Plan 03-08 `DENIED` (2026-05-01) reversed; Phases 4 + 5 unblocked; MirkFall port-back recommendation flipped from "do NOT port" to "PORT with the layered Phase 3.1 fix bundle"

This is a retrospective on what went into making the same-Canvas fog stay locked to the camera during pan + zoom + rotation. It's written for the next engineer (human or AI) who touches the fog rendering pipeline — most likely during the MirkFall port-back.

---

## The original bug

Phase 3 closed `DENIED` because:

> The same-Canvas fog rendered + rotated correctly with the camera but did NOT translate during pan.

Root cause: `_FogPainter.paint()` passed `offset: const Offset(0.0, 0.0)` to the shader's `uOffset` uniform. The shader had a `uOffset` slot but the painter never derived a non-zero value from camera state. Static offset → fog painted at fixed Canvas coordinates regardless of camera pan.

The 1-line fix was conceptually trivial (derive `uOffset` from `camera.pixelOrigin / size`). The 6 iterations that followed weren't about *finding* the bug — they were about discovering that the trivial fix exposed deeper failure modes, each of which exposed the next.

---

## The fix arc

| Walk | Plan | What was done | What broke after |
|------|------|---------------|------------------|
| #1 | 03.1-02 | Derive `uOffsetX/Y = (pixelOrigin / size) % 1.0` Dart-side | Modulo wraps every viewport-width — visible noise-seam shimmer; reveal-hole misaligned with blue dot |
| #2 | 03.1-04 + 05 | Move modulo into shader (`fract(uPixelOrigin / kNoiseTilePx)`); shift clip path by `-canvasOffset` to compensate Canvas frame | Noise-tile-period stepping persists at sub-perceptible scale (~16-65 raw px); rect-cover paint not compensated → viewport-edge wedges |
| #3 | 03.1-07 + 08 | B-3 noise-tile-period derivation in shader (no new uniform); `canvas.translate(-canvasOffset)` for rect-cover | Stepping still visible at wrap events; MobileLayerTransformer rotation matrix accumulates → fog rotates with canvas leaving wedges of un-fogged map |
| #3b | (marker walk) | Quantitative empirical anchor — 8 markers in 24 sec, 39 raw-px median between markers | Diagnostic anchor for the next plan |
| #4 | 03.1-10 | UX-02 disable rotation + FOG-17 world-coordinate noise sampling + FOG-17a CPU integer/fractional decomposition with `% kPocFogIntegerWrapPeriodPx` (= 1536 = 4 × 384 noise tile) | Q1 closed at default zoom only; SNAP at MAX zoom intermittent; NEW Q1b zoom-gesture "seed of procedural pattern fast" |
| #5 | 03.1-12 | C1' eliminate the FOG-17a wrap modulo; C3' remove `MapOptions.cameraConstraint` | Q1 SNAP CLOSED 100% at all zoom levels; Q1b still present (C2' deferred for fresh discuss-phase) |
| #6 | 03.1-14 | C-b: `uniform float uZoomScale` at slot 41 in both shaders; Dart forwards `pow(2, currentZoom - kPocFogReferenceZoom)`; shader divides `worldPx / (kNoiseTilePx * uZoomScale)` | **Q1b CLOSED. Phase 3.1 closes.** |

The final layered fix bundle = 8 plans worth of incremental layering:

```
03.1-02   uOffset derived from pixelOrigin (the original 1-line fix)
03.1-04   shader-side modulo (uOffset → uPixelOrigin rename + fract per-fragment)
03.1-05   clip-path Canvas-frame alignment (FOG-12)
03.1-07   B-3 noise-tile-period derivation in-shader (no new uniform)
03.1-08   FOG-13 fog-rect viewport-coverage symmetric compensation
03.1-10   UX-02 disable rotation + FOG-17 world-coordinate noise + FOG-17a precision pairing
03.1-12   FOG-18 eliminate the wrap modulo (fp32 has enough mantissa)
03.1-14   FOG-19 uZoomScale uniform — anchor noise to lat/lng during zoom
```

Each commit in this chain is independently revertable; each layer addressed a distinct failure mode that the previous layer surfaced.

---

## What the bug actually was, mechanistically

The fog shader samples a noise function at `worldPx` coordinates and uses the result as a transparency / color modulation. For the fog to "stay locked to the map", the same lat/lng location must produce the same noise sample regardless of camera pan or zoom.

In the original (broken) state:
```dart
shader.setOffset(const Offset(0.0, 0.0));   // bug: never updated from camera
```
```glsl
worldPx = fragUv * uResolution + uOffset;   // fragUv 0..1 across viewport
noiseUv = worldPx / kNoiseTilePx;           // sample noise function
```
The shader had no way to know the camera moved, so the noise stayed Canvas-anchored. Pan the map → noise pattern stays put on screen → fog visibly slides relative to the map underneath.

Each subsequent fix introduced a new pinning of the noise sample relative to "world space" but exposed a different mismatch:

1. **Pan-mismatch (Walk #1):** noise must shift in the opposite direction of camera pan. Solved by `uOffset = pixelOrigin`.
2. **Wrap-mismatch (Walks #2-#3):** at long pans, `pixelOrigin` grows unbounded → fp32 precision degrades + screen-pixel coordinates exceed shader-friendly range. Solved (badly) by modulo, then (better) by world-coordinate sampling + integer/fractional decomposition.
3. **Wrap-firing-visibly mismatch (Walk #4 → Walk #5 fix):** the FOG-17a `% 1536` modulo created a discrete jump every wrap. The hypothesis was the noise function was periodic on `kNoiseTilePx (=384)` so wraps would land on aligned boundaries — wrong. The noise function isn't truly periodic on 384, so wraps produced visible SNAPs at high zoom (where each second of pan crossed multiple wraps). Solved by *eliminating the wrap entirely* (fp32 has 24 bits of exact-integer mantissa = 16.7M raw-px headroom; max observed was 4.26M).
4. **Zoom-mismatch (Walks #4-#5 → Walk #6 fix):** `pixelOrigin` is in screen-pixels at the *current* zoom level. Zoom 13 → ~1M; zoom 16 → ~4M. As zoom changes, the same lat/lng maps to a different `pixelOrigin`, so the noise sample shifts. The cells "move all around" during zoom because the noise sample positions are anchored to the screen, not the world. Solved by `uZoomScale = pow(2, currentZoom - referenceZoom)` and shader-side `worldPx / (kNoiseTilePx * uZoomScale)`. Anchors noise to lat/lng.

---

## Pitfalls — what NOT to do

### 1. Don't change shader visual identity to hide a bug

A previous agent (on the archived `old` branch, Plans 03.1-11→16 in that branch's history) tried to make the noise function periodic to mask the wrap discontinuity. This is the **anti-pattern that the MIRL constraint exists to prevent**.

If your fix changes the shader's noise frequency, color, blur character, or texture style at any settled (zoom, position) — you're not fixing the bug, you're hiding it. The bug is still there; you've just changed what the user sees so they can't tell.

The MIRL rule (`CLAUDE.md` `# MIRL solution`) reads:
> "If you compared the shader output to its Shadertoy-source equivalent, could you pick a (zoom, position) where the two are visually identical? If yes → modification is OK. If no → modification breaks visual identity → forbidden."

The Walk #6 final fix passes this test trivially: at `kPocFogReferenceZoom = 13.0`, `uZoomScale = pow(2, 0) = 1.0`, so the noise sampling becomes bitwise-identical to its pre-fix form. Visual identity preserved at the reference zoom; world-anchored at others.

### 2. The dimensional-mismatch trap

When proposing a "zoom-invariant" formula, *test the algebra at different zooms before committing*.

The C2' fix axis was deferred at Plan 03.1-12 plan-checker iteration 1 because the originally-proposed formula was:
```
basis = crs.latLngToPoint(center, kPocFogReferenceZoom) * pow(2, currentZoom - kPocFogReferenceZoom)
```
This *looks* zoom-invariant ("project at reference zoom, scale to current"). It isn't. Flutter_map's CRS is linear in scale (`Crs.scale(z) = 256 * 2^z`, `transformation.transform(...)` linear in scale), so:
```
latLngToPoint(center, refZoom) * 2^(currZoom - refZoom)
   ≡  latLngToPoint(center, currZoom)
   ≡  pixelOrigin + size/2
```
The "fix" was algebraically a constant offset of the broken behavior. Plan-checker caught it; user picked option (b) "defer C2', ship C1' + C3' only".

The genuine zoom-invariance came from the *DIVIDING* form (`worldPx / uZoomScale`), not the multiplicative form (`* pow(2, ...)`). Direction of arithmetic matters.

### 3. The "no shader edits" overinterpretation

The MIRL constraint was originally written as:
> "la solution doit etre shader agnostic puisque dans l'application reelle plusieur shader different seront utilisé"

Multiple plan-checker iterations and the first discuss-phase round read this as "ZERO shader edits ever". This made C-b structurally impossible to plan, because the C-b fix *requires* a new uniform declaration (one line of shader source code).

The developer clarified the intent on the third discuss-phase round (post-Walk-5):
> "I put that clause because previous agents kept trying to change the shader to make it periodic to hide the hard step. You ARE allowed to make modifications to the shader, as long as the shader can still be displayed exactly as it was in Shadertoy at some location/zoom level."

The constraint was **anti-cheat, not anti-edit**.

Lesson: when a constraint blocks the obvious right fix, derive the constraint's *intent* before proposing workarounds. Walking the constraint back to its original purpose unblocks options the strictest reading rules out.

### 4. The diagnostic-split heuristic (Walk #4 supplementary appendix)

The pivotal moment of Phase 3.1 was Walk #4's supplementary observation: the developer noticed that on the debug-spiral shader (digit-atlas cells, deterministically periodic on 384):
- Pan at MAX zoom → ZERO steppiness
- Zoom → cells slide around ("incorrect scaling?")

While on the production fog (atmospheric noise function):
- Pan at MAX zoom → SNAP at every wrap event (multiple times per second)
- Zoom → noise re-randomizes ("seed of procedural pattern fast")

Both shaders share the same Dart-side foundation. The asymmetry on pan + symmetry on zoom *split the failure modes mechanistically*:
- **Pan-only-on-production = noise-function-specific mismatch** (the FOG-17a modulo was firing visibly because the noise wasn't actually periodic on 384, while the digit-atlas pattern *was* periodic on 384 → wrap was invisible there)
- **Zoom-on-both-shaders = shared-foundation mismatch** (the world-coordinate basis itself was zoom-dependent)

Without this split, the C-b uZoomScale fix would not have been the obvious next step. The debug-spiral shader was deliberately created during Plan 03.1-07 as a diagnostic tool, but its highest-value contribution was *several walks later* in this asymmetric observation.

Lesson: **ship a diagnostic shader / debug overlay alongside the production system, even before you know why you'll need it.** The cost is small (~half a day to scaffold). The value comes from being able to compare two systems sharing one foundation when something goes wrong.

### 5. Deferring is sometimes the right plan-checker outcome

When plan-checker iteration 1 of Plan 03.1-12 review surfaced the dimensional-mismatch problem (Blocker #1), the natural reflex was to "auto-revise the formula until plan-checker passes". That would have been wrong — the formula needed *re-derivation*, which needed *design conversation* with the user, which needed *fresh context*.

The actual move was: drop C2' from Plan 03.1-12, ship C1' + C3' only, defer C2' to a separate `/gsd:discuss-phase 3.1` round. This added one extra walk (Walk #5) but avoided shipping a wrong fix.

Lesson: plan-checker isn't a syntax-checker; it can flag substantive architectural mistakes. When it does, ask the human-in-loop, don't auto-revise.

### 6. The known-defect waiver pattern

Walk #6 surfaced a regression in the debug-spiral's new 4-digit cell-numbering (Plan 03.1-14 Task A). The developer's response:
> "numbered shader is broken : but I don't care"

The DEBUG-03 unique-cell-numbers feature served its diagnostic purpose during Plan 03.1-14 development; the developer didn't need it for the actual closure verdict (verbal "100% solved" was decisive). DEBUG-03 was marked **Complete with known defect** — debug-shader-only, no production impact, cleanup deferred indefinitely.

Lesson: don't block phase closure on debug-tool cleanup. Diagnostic tools that successfully diagnosed are allowed to break afterwards.

### 7. Mail-share discipline (and why Walk #3's verbal-only break hurt)

Each walk produced JSONL diagnostic streams via `Logger('infrastructure.mirk.fog_transform')` rolled up at 1-Hz cadence. The protocol: developer Mail-shares the session log post-walk → orchestrator extracts the JSONL streams → grep-correlates against any dev-marker timestamps → quantitative anchor for the next plan.

Walk #3 broke this discipline (verbal evidence only). Walk #4's planning was therefore harder — the next plan had to hypothesize the residual stepping mechanism without quantitative correlation. Walk #4 re-established the discipline; Walks #4 + #5 each produced ~700KB to 2MB session logs that were grep-correlated.

Walk #6 *also* skipped Mail-share, but only because the verbal verdict ("100% solved") was unambiguous and Walks #4 + #5 had already established the diagnostic baseline. The skip was acceptable as the *closure* walk — it would not have been acceptable mid-iteration.

Lesson: **diagnostic instrumentation is load-bearing during iteration, not after**. If you're iterating, share the logs. If you're closing, you can skip if the verdict is decisive.

### 8. Iteration cadence — no hard cap, but track progress per walk

Phase 3.1 ran 6 iterations / 8 walks. None were wasted. Each walk made measurable progress: Walks #1→#5 each produced a verdict (ITERATING-WITH-MAJOR-PROGRESS / WITH-PARTIAL-PROGRESS / etc.) that translated into a specific gap-closure plan. Walk #6 closed.

The right termination condition isn't "≤ N walks". It's "are we still making progress on each walk?". Phase 3.1's iteration policy explicitly says "no hard cap on walk count" — which is *correct* under the make-progress-each-walk discipline.

If you hit a walk where you don't know what the next plan would be, *that's* the termination signal. Either escalate to a fresh discuss-phase round (which is what Walk #5's CONFIRMED-AFTER-FIX-PARTIAL did → fresh discuss-phase → C-b fix), or accept the verdict as DENIED-FINAL and pivot to alternative renderers.

---

## Architectural payload (for MirkFall port-back)

The fog shader system after Phase 3.1 closure has these characteristics worth porting back:

- **`uPixelOrigin` slot 3..4** — `vec2` camera-derived input forwarded by Dart-side `_FogPainter.paint()`. Any fog shader implementing the ABI plugs in.
- **`uZoomScale` slot 41** — `float` zoom-derived input forwarded by Dart-side as `pow(2, currentZoom - referenceZoom)`. Anchors noise sample positions to lat/lng.
- **`kPocFogReferenceZoom = 13.0`** — the zoom level at which `uZoomScale = 1.0` and the noise sampling is bitwise-identical to its Shadertoy-source form. Pick this to match the typical user zoom regime.
- **No Dart-side modulo on `uPixelOrigin`** — fp32's 24-bit exact-integer mantissa (16.7M) covers any zoom-13 raw-px range you'll encounter on planet earth.
- **`UX-02` rotation disabled** — `FlutterMap.options.interactionOptions = InteractiveFlag.all & ~InteractiveFlag.rotate`. Sidesteps MobileLayerTransformer rotation-matrix accumulation entirely. If MirkFall needs rotation, the Phase 3.1 work covers translation + zoom but rotation needs a separate fix axis.
- **`canvas.translate(-canvasOffset)` at `_FogPainter.paint()` head** — symmetric compensation for MobileLayerTransformer translation matrix. Identity-frame for the painter's drawRect.
- **`fract` removed from shader noise sampling** — the world-coordinate formulation `worldPx = fragUv * uResolution + uPixelOrigin; noiseUv = worldPx / (kNoiseTilePx * uZoomScale)` produces monotonic noise scrolling without `fract`/`mod` discontinuities.
- **Single `MapCamera.of(context)` snapshot per `FogLayer.build()`** — locks pan-translation and zoom-scale to the same frame. Mismatched snapshots produce fog jitter (FOG-07).

The shaders themselves (`atmospheric_fog.frag` + any future production fog shaders) need to:
- Declare `uniform float uZoomScale;` at slot 41
- Use it as a divisor in noise sampling: `noiseUv = worldPx / (kNoiseTilePx * uZoomScale)` (or equivalent — divide by `uZoomScale` somewhere on the path from `worldPx` to the noise function input)
- Render bitwise-identically to their Shadertoy-source form when `uZoomScale = 1.0`

---

## Final verdict, for the record

The same-Canvas fog hypothesis (Phase 3 / Plan 03-08) was reinstated by Walk #6 of Phase 3.1. The POC architectural recommendation flipped from "do NOT port back to MirkFall as-implemented" to "PORT BACK with the layered Phase 3.1 fix bundle (8 plans)".

The bug was originally one line. The proper fix is ~15 lines across 4 files (the C-b layer alone) on top of 7 layers' worth of intermediate corrections that each surfaced the next failure mode. None of the intermediate layers were wasted — each one moved the symptom closer to the actual mechanism.

The single most valuable artifact produced during Phase 3.1 wasn't any of the fix commits — it was the debug-spiral shader (Plan 03.1-07's DEBUG-01 toggle). Its asymmetric behavior at Walks #4 + #5 produced the diagnostic split that pointed at C-b. Build the diagnostic before you need it.
