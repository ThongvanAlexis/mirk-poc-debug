# Phase 4: Wisp Particles - Context

**Gathered:** 2026-05-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Composite a wisp particle system after the fog in the same Canvas, with positions stored in `LatLng` (world space) and projected to screen via the same `MapCamera` snapshot the fog uses. Confirms that the same-Canvas discipline established in Phase 3.1 (single `MapCamera.of(context)` snapshot per paint, FOG-07 invariant) generalises to a second visual layer — the cross-pipeline parity check that completes the code-donor package for porting back to MirkFall.

Out of scope: interactivity (tap-to-spawn, gesture-driven wisps), multiple wisp styles (atmospheric only, like the fog), wisp-fog interaction beyond additive blend (e.g., wisps don't displace fog density), persistent wisp state across sessions, performance optimisation beyond the donor's CPU-side particle integration (no GPU instancing in this phase).

</domain>

<decisions>
## Implementation Decisions

### Kinematic units (CRITICAL — Phase 3.1 BUG-014 dimensional-mismatch trap)

**Phase 3.1 forces world-anchored kinematics.** The donor's screen-px basis for position + velocity is exactly the BUG-014 / FOG-19 dimensional-mismatch trap in disguise — donor was never stress-tested at the zooms+pans Phase 3.1 surfaced. Donor adapts to the POC's architectural standard on port-back, not the other way around.

| Property | Unit | Donor (MirkFall) | POC | Rationale |
|---|---|---|---|---|
| Position | `LatLng` | `Offset` (screen-px) | `LatLng` | Mandated by WISP-01 |
| Velocity / drift | **m/s** | 18 px/s | ~1.5 m/s (walking pace) | World-anchored; donor mis-scaled (18 px/s @ z15 ≈ 86 m/s = 310 km/h) |
| Birth/death radius | **screen-px (default), configurable to meters** | 6 / 22 px | Same numerical values; configurable basis | Cosmetic property — wisp center stays at correct LatLng so no position-drift risk. Screen-px gives consistent visual character across zoom |
| Spawn spacing | **8 m along disc circumference** | 8 m | 8 m (donor verbatim) | Already world-anchored — the only kinematic donor accidentally got right |

**Velocity calibration:** ~1.5 m/s cinematic walking-pace drift. Total drift over 2.5 s life = ~3.75 m. Re-calibrated from donor's mis-scaled 18 px/s; explicit constant `kMirkPocWispDriftMetersPerSecond = 1.5`.

**Radius basis shape — enum + paired constants:**
```dart
enum WispRadiusBasis { screenPx, meters }
const kMirkPocWispRadiusBasis = WispRadiusBasis.screenPx; // default
const kMirkPocWispBirthRadiusPx = 6.0;
const kMirkPocWispDeathRadiusPx = 22.0;
const kMirkPocWispBirthRadiusMeters = ...; // calibrated at planning time
const kMirkPocWispDeathRadiusMeters = ...; // calibrated at planning time
```
Painter's wisp render branches on `kMirkPocWispRadiusBasis` at paint time. Single constant flip switches the basis for A/B comparison during walks.

### Paint order (relative to fog)

Wisps slot in as the LAST step inside `_FogPainter`'s existing `canvas.save()` / `canvas.restore()` sequence:

```
canvas.save()
canvas.translate(-canvasOffset)         // Phase 3.1 FOG-13 (unchanged)
canvas.clipPath(clipPath)               // Phase 3.1 FOG-12 (unchanged)
shaderRenderer.render(...)              // FOG-19 uniforms (unchanged)
canvas.drawRect(Offset.zero & size, Paint()..shader = liveShader)  // fog (unchanged)
// --- NEW: wisp render ---
_renderWisps(canvas, camera)            // ← inserted here
canvas.restore()
```

- **Painter architecture:** extend `_FogPainter` (single painter, atomic state). Fog and wisps share the SAME `canvas.getTransform()` snapshot, the SAME `MapCamera` (constructor-injected per FOG-07), the SAME canvas-translate frame, the SAME clipPath. Cannot desync. Implementation: extract a private `_renderWisps(Canvas canvas, MapCamera camera)` method on `_FogPainter`.
- **Clip path:** SAME clipPath as fog (wisps clipped to unrevealed/foggy areas). Wisps spawn at disc perimeter, drift OUTWARD into the fog. Donor's narrative: "puff bursting outward from the new reveal".
- **Z-order:** wisps drawn AFTER `canvas.drawRect(... shader)`. Wisps additive-blend ON TOP of the fog (BlendMode.plus brightens fog where they overlap).
- **Canvas-translate frame:** wisps drawn INSIDE `canvas.translate(-canvasOffset)`, in the identity world frame. Wisp positions = `camera.latLngToScreenPoint(wispLatLng)` — coords are in the identity world frame (same frame the sibling CircleLayer / blue-dot use). Mandatory per the FOG-13 architectural payload.

### Render mechanism

- **Primitive:** Flutter Canvas API `canvas.drawCircle` per wisp (donor approach). NOT a dedicated wisp shader. Phase 3.1 just spent 8 walks debugging shader-vs-Dart-side dimensional issues; adding a new shader multiplies that risk surface for negligible perf gain. PERF-07 has 5–66× headroom on iPhone 17 Pro for ~200 drawCircle calls (Walk #5 medianMs 1.495 vs 16ms budget).
- **Paint allocation:** ONE `Paint` allocated per `paint()` call (fields: blendMode = BlendMode.plus, style = fill); inside the per-wisp loop, only `paint.color` is mutated. 1 alloc per paint instead of donor's 200 — pure perf win, behaviorally identical. Donor's per-wisp allocation was a minor MirkFall-era inefficiency.
- **Blend mode:** `BlendMode.plus` (additive — donor verbatim). Wisps brighten the fog where they overlap; multiple overlapping wisps stack additively (capped by alpha clamp). Visual character: "glowing tendrils brightening the fog".
- **Edge:** hard-edge `drawCircle` (donor — no `MaskFilter.blur`). Softness emerges from the low additive alpha (peak `0.35 × (1 - age²)`). Matches donor; iterate to soft-edge only if walk feedback says hard edges look pixelated at zoom-out.

### Drift parameters

- **Spawn direction:** outward radial from spawn point (donor). Caller computes the outward-normal-at-perimeter for each wisp; wisp's initial velocity = `unitDirection × speed × (0.8 + rng.nextDouble() * 0.4)` jitter factor.
- **Curl-noise perturbation:** keep donor's organic-drift character. Magnitudes need re-derivation since donor was px-based — donor's `curlMagnitude = 8.0 px/sec²` re-expressed to m/sec² basis. Target ~0.5–1.0 m/sec² for cinematic drift. **Exact tuning = Claude's discretion at plan/execute time** (calibrate by walk feedback, not upfront). Curl input position re-derived from LatLng (analogous to FOG-17 world-coord noise sampling).
- **Spawn timing:** one puff per new disc at first appearance (donor). After warmup, each newly-emerged disc spawns ~20 wisps once (8 m spacing × 157 m circumference / disc); no further wisps from that disc. Cap (200) reached after ~10 disc-fixes; LRU eviction kicks in. Matches WISP-03's 5 s warmup semantic.
- **Drag:** donor's 0.30/sec linear drag (velocity → 0.7 × velocity over 1 sec). Combined with curl-noise force, creates organic "drifting then dispersing" motion. Visually validated on MirkFall.

### Shader-agnosticism (architectural property — documented, not CI-gated)

**The wisp render path does NOT touch the fog shader.** Wisps depend only on:
- `MapCamera.latLngToScreenPoint(...)` — flutter_map standard, shader-independent
- `canvas.drawCircle` + `Paint` — pure Canvas API
- The fog clipPath — built from disc geometry, not shader uniforms
- The painter's identity-frame discipline (`canvas.translate(-canvasOffset)`)

Wisps do NOT reference `uPixelOrigin`, `uZoomScale`, `uTime`, `FogShaderUniforms`, `atmospheric_fog*`, or any other fog-shader-specific symbol.

**Implication:** swapping `atmospheric_fog.frag` for a different conformant fog shader (e.g., the user's pasted ZGE-style noise-plus-flow shader) leaves the wisp code path unchanged. Wisps composite as additive `drawCircle` over whatever fog the new shader produces. Fog-shader port-back is a separate concern (the new shader needs `uPixelOrigin` + `uZoomScale` ABI conformance per the FOG-19 payload, like atmospheric_fog.frag was retrofitted).

**Enforcement:** documented (this section + docstring on `_FogPainter._renderWisps(...)`), NOT CI-grep-enforced. If a future engineer accidentally couples wisps to the shader, code review catches it. CI gate deferred to v2 if the property regresses in practice.

### DEBUG-01 /sanity compatibility

Wisps render only in production fog mode. `/sanity` debug-spiral mode skips the wisp render block (simple conditional in painter). `/sanity` stays focused on shader-compile diagnostic; no wisp visual noise. Plan 03.1-14 retrospective: debug shaders are diagnostic-only; adding wisps multiplies the failure surface there for no diagnostic gain.

### Constants file additions (preview)

```dart
// lib/config/constants.dart additions
const double kMirkPocWispDriftMetersPerSecond = 1.5;       // walking pace
const double kMirkPocWispLifeSeconds = 2.5;                 // donor verbatim
const int kMirkPocWispMaxCount = 200;                       // donor verbatim
const double kMirkPocWispMetersPerWisp = 8.0;               // donor verbatim
const double kMirkPocWispWarmUpSeconds = 5.0;               // donor verbatim
const double kMirkPocWispPeakAlpha = 0.35;                  // donor verbatim

enum WispRadiusBasis { screenPx, meters }
const WispRadiusBasis kMirkPocWispRadiusBasis = WispRadiusBasis.screenPx;
const double kMirkPocWispBirthRadiusPx = 6.0;               // donor verbatim
const double kMirkPocWispDeathRadiusPx = 22.0;              // donor verbatim
const double kMirkPocWispBirthRadiusMeters = ...;           // calibrated at planning time
const double kMirkPocWispDeathRadiusMeters = ...;           // calibrated at planning time

const double kMirkPocWispCurlAccelMetersPerSecondSquared = ...; // Claude's discretion at plan/execute
const double kMirkPocWispDragPerSecond = 0.30;              // donor verbatim
```

### Phase 3.1 carry-forwards (locked invariants — do NOT re-discuss)

- **UX-02** rotation disabled — wisps not tested under rotation; if rotation is ever re-enabled, FOG-16 path (b) full canvas-inverse-transform must land first. Currently `InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)`.
- **DEBUG-02** cameraConstraint removed — Phase 4 walk plan MUST include the C3' extreme-distance regime (~50–100 km from Melun) to verify wisp `LatLng → screen-px` projection doesn't surface fp32 precision artefacts that the noise-sampling fog didn't expose.
- **PERF-07 thresholds** — `medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48` (NOT obsolete ≥30fps). Phase 3.1 Walk #5 sustained 13×/20×/28× headroom on fog-only; Phase 4 must verify this holds under fog + 200 wisps.
- **"Walk" = sideload session at desk**, not physical walking. Term `Walk #N` preserved for grep-tooling.
- **`uZoomScale` slot 41 + `kPocFogReferenceZoom = 13.0`** — fog ABI; wisps don't consume it (they project via MapCamera directly).
- **MIRL visual-identity rule** — adding ABI uniforms OK; modifying shader visual character to hide bugs is forbidden. Wisps don't add fog-shader uniforms (no shader path); rule still applies if a future v2 wisp-shader option is reconsidered.
- **FOG-07 single MapCamera snapshot per build** + **single `canvas.getTransform()` per paint** — wisps share THE snapshot, not just A snapshot.
- **Iteration policy** — no hard cap on walk count. Mail-share discipline mandatory post-walk for grep-correlation.
- **WISP-05 `WispTransformLogger`** — analogous to `FogTransformLogger`; ship it before any walk (per shader-fix-retrospective lesson #4 "ship the diagnostic before you need it"). Schema: per-paint observation captures (active count, mean age, LatLng bounds, screen-Offset bounds, spawn rate); 1-Hz JSONL rollups via `Logger('infrastructure.mirk.wisp')`; wall-clock-aligned for grep-correlation against `infrastructure.mirk.fog_transform` + `infrastructure.mirk.sdf` + `infrastructure.mirk.frame_delta` streams.

### Claude's Discretion

- Curl-noise force magnitude in m/sec² (target ~0.5–1.0 m/sec², calibrate by walk feedback).
- Curl input-position scale factor (donor used `position * 0.005` in screen-px; re-derive for LatLng basis).
- Wisp tint RGBA — donor's white/blue tint or a different choice; defer to plan/execute time. Visible during walk; trivial to retune.
- Random jitter magnitude on spawn position (donor: ±2 px); re-express in the chosen radius basis or keep screen-px since it's a visible-cosmetic property like radius.
- Concrete `kMirkPocWispBirthRadiusMeters` / `kMirkPocWispDeathRadiusMeters` calibration values (only matter if user flips the basis; pick at planning time).
- Whether to introduce a separate `WispParticleSystem` class (donor-style) or inline the particle list into `_FogPainter`. Recommend separate class for unit-testability.
- Spawn jitter on velocity speedFactor (donor: 0.8–1.2); keep verbatim or simplify.

</decisions>

<code_context>
## Existing Code Insights

### Reusable assets

- **Donor `WispParticleSystem`** (`C:/claude_checkouts/GOSL-MirkFall/lib/infrastructure/mirk/wisp/wisp_particle_system.dart` + `wisp_particle.dart`): port with three structural changes — (1) `Offset` position → `LatLng` position; (2) `Offset velocity` → `Offset velocityMetersPerSecond` semantics (or rename to clarify unit); (3) Paint hoisted outside the per-wisp loop in `render(...)`. Curl-noise + drag + LRU eviction logic ports verbatim modulo the unit re-derivation.
- **Donor constants** (`C:/claude_checkouts/GOSL-MirkFall/lib/config/constants.dart` lines 730–788): `kMirkFogWisp*` values port to `kMirkPocWisp*` names; magnitudes re-calibrated per the unit decisions above.
- **`_FogPainter` in `lib/presentation/widgets/fog_layer.dart`**: extension point — add a `_renderWisps(Canvas, MapCamera)` private method called between the existing `canvas.drawRect(... shader)` and `canvas.restore()`. Constructor takes a `WispParticleSystem` (or whatever the ported class is named). Existing FOG-07 `MapCamera` field reused; existing `canvas.translate(-canvasOffset)` + `clipPath` reused.
- **`FogLayer` State**: extend `_onDiscsChanged` to also call `wispParticleSystem.spawnAtNewDisc(...)` when a new disc emerges. Existing Ticker drives the `_repaint` `ChangeNotifier` for both fog and wisps (single repaint trigger; wisps integrate via `advance(dt)` inside `paint()` or via a separate tick — design at plan time).
- **`FogTransformLogger` pattern** (`lib/infrastructure/mirk/fog_transform_logger.dart`): structural template for the new `WispTransformLogger`. Same dual-clock discipline (Stopwatch.elapsedMicroseconds for math, DateTime.now() only for epochSecond rollup tag), same 1-Hz cadence, same JSONL body via `Logger('infrastructure.mirk.wisp')`.

### Established patterns (Phase 1 + 2 + 3 + 3.1 lock-in)

- State management: plain `StatefulWidget` + `setState` + constructor-injected services via `MapScreenServices` DTO. No Riverpod/Bloc/Provider.
- Logging: `package:logging` `infrastructure.mirk.*` family; JSONL body, INFO level, 1-Hz cadence wall-clock-aligned for grep-correlation.
- Strict analysis: `strict-casts`, `strict-inference`, `strict-raw-types`, `use_build_context_synchronously: error`.
- Pinned versions: any new dep strict-pinned, audit row in `DEPENDENCIES.md`.
- GOSL header on every new `.dart` file in `lib/` and `test/`.

### Integration points

- **MapScreen wiring**: `MapScreen.initState` constructs a `WispParticleSystem` and threads it into `FogLayer` alongside the existing services. `_onGpsFix` callback: when `discRepository.append(...)` produces a NEW disc (not just an update), spawn wisps along that disc's perimeter at 8 m spacing.
- **Warmup**: WISP-03's 5 s warmup gate lives in MapScreen / `WispParticleSystem`. During warmup, discs entering the viewport are ingested into the "already-seen" set WITHOUT spawning wisps. Donor's `kMirkFogWispWarmUpSeconds = 5.0` ports verbatim.
- **Disc emergence detection**: track which disc IDs have already produced a wisp puff; only NEW IDs trigger spawning. Donor used cell-keyed pre-Commit-5; the donor's current disc-keyed approach is what we port.
- **Repaint trigger**: existing `_FogLayerState._ticker` fires per-frame and notifies `_repaint`. Painter's `paint()` advances the wisp system by `dt = elapsedSinceLastPaint` and renders. Or: a separate Ticker for wisp `advance(dt)` decoupled from paint — design at plan time.

</code_context>

<specifics>
## Specific Ideas

- **The donor adapts to us, not the other way around.** Phase 3.1 settled the dimensional discipline (world-anchored position + motion; cosmetic-only properties may stay screen-anchored). Donor's screen-px velocity + 18 px/s magnitude are pre-Phase-3.1 artefacts; we port the structure (curl-noise, drag, LRU eviction, additive blend, hard-edge drawCircle) and re-derive the kinematic values from the m/s + LatLng basis.
- **Ship the diagnostic before you need it (retrospective lesson #4).** WISP-05 `WispTransformLogger` is non-negotiable in Plan 04-XX; ship it alongside the first wisp render commit, not after a failed walk. Phase 3.1 Walk #4's debug-spiral asymmetric observation was the pivotal moment of closure — the equivalent for Phase 4 is a wisp diagnostic stream that grep-correlates against the existing fog/sdf/frame_delta streams.
- **Walk shape: C3' extreme-distance is mandatory.** Phase 3.1 D1 decision (carried forward): "walk" = sideload session at desk (no physical movement); Phase 4 walk MUST include the ~50–100 km extreme-distance pan from Melun. Wisps render via point-particle projection (`MapCamera.latLngToScreenPoint`), which is a different code path than the fog's continuous-noise sampling — fp32 precision artefacts could surface at high `pixelOrigin` magnitudes that the noise-sampling fog didn't expose. Verify independently.
- **Your ZGE shader (or any future shader swap) doesn't touch the wisp code.** The shader-agnosticism property is preserved by the design choices above. If you swap atmospheric_fog.frag for the ZGE shader (after porting it to the post-Phase-3.1 ABI: add `uPixelOrigin` + `uZoomScale` consumption per FOG-17 + FOG-19), wisps continue to spawn at LatLng disc perimeters, drift in m/s, and additive-blend over whatever fog the new shader produces.
- **Phase 4 closure unblocks Phase 5.** Phase 5 = decision gate (Pixel 4a sanity + formal POC verdict). Phase 4's CONFIRMED outcome (= "fog lock preserved + wisps anchor + PERF-07 holds + C3' regime clean") is the entry condition for Phase 5.

</specifics>

<deferred>
## Deferred Ideas

- **Wisp shader (FragmentProgram)** — Q1 of Render mechanism rejected for Phase 4 (Phase 3.1 dimensional-mismatch trap precedent argues for caution; PERF-07 headroom favours Canvas API simplicity). Revisit if Phase 5 Pixel 4a walk surfaces sustained PERF-07 failures under fog + 200 wisps OR if v2 visual-fidelity goals require GPU-instanced rendering.
- **Soft-edge wisps via pre-rasterized soft-circle Image** (option 3 of Q4 Render mechanism) — defer to walk feedback. If hard-edge drawCircle looks pixelated at zoom-out during Phase 4 walks, switch to drawImageRect with a 64×64 alpha-gradient ui.Image. Drop-in change; no architectural impact.
- **Continuous wisp emission while disc visible** (Q3 Drift alternative) — defer; donor's "one puff per disc" matches the BUG-009 narrative cleanly. Reconsider if Phase 4 walks read as "too quiet" between disc emergences.
- **CI grep-test for wisp shader-agnosticism** — user chose "documented, not CI-enforced". Defer to v2 if the property regresses in practice. Cheap to add later.
- **WISP-06 acceptance criterion** — not introduced. Shader-agnosticism stays a documented architectural property without formal requirement status.
- **Tangential / curl-only spawn directions** (Q1 Drift alternatives) — defer; donor's outward-radial matches the BUG-009 "puff bursting outward" narrative.
- **No-drag / higher-drag** (Q4 Drift alternatives) — donor's 0.30/sec is visually validated; revisit only if walk feedback contradicts.
- **GPU instancing / GLSL compute** — out of POC scope; v2 / MirkFall port-back concern if Pixel 4a walks reveal CPU bottleneck.
- **Wisp tint per-fog-style** — defer until v2 introduces multiple mirk styles (currently atmospheric only per PROJECT.md).
- **Wisp interaction with fog density** (e.g., wisps displace fog locally, wisps darken fog) — out of POC scope; pure additive-blend per donor.
- **Persistent wisp state across sessions** — out of POC scope (POC stores discs in memory per PROJECT.md).
- **Tap-to-spawn / interactive wisps** — new capability; not on Phase 4's hypothesis-validation path.
- **Wisp-shader port-back to MirkFall (vs Canvas API)** — POC ships Canvas API; MirkFall port-back inherits Canvas API. If MirkFall has different perf constraints (Android low-end devices), the shader option re-opens at MirkFall integration time, not Phase 4.

</deferred>

---

*Phase: 04-wisp-particles*
*Context gathered: 2026-05-04*
