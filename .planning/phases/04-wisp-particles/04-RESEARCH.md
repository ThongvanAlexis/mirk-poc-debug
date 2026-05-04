# Phase 4: Wisp Particles — Research

**Researched:** 2026-05-04
**Domain:** Flutter `CustomPainter` particle system layered onto an existing fog `CustomPainter`, with world-anchored kinematics (LatLng + m/s) projected via the SAME `MapCamera` snapshot the fog uses (FOG-07 carry-over)
**Confidence:** HIGH (this is a near-pure adaptation of an in-tree, walk-validated architecture; risk surface is small + well-localised)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Kinematic units (CRITICAL — Phase 3.1 BUG-014 dimensional-mismatch trap):**

| Property | Unit | Donor (MirkFall) | POC | Rationale |
|---|---|---|---|---|
| Position | `LatLng` | `Offset` (screen-px) | `LatLng` | Mandated by WISP-01 |
| Velocity / drift | **m/s** | 18 px/s | ~1.5 m/s (walking pace) | World-anchored; donor mis-scaled (18 px/s @ z15 ≈ 86 m/s = 310 km/h) |
| Birth/death radius | **screen-px (default), configurable to meters** | 6 / 22 px | Same numerical values; configurable basis | Cosmetic property — wisp center stays at correct LatLng so no position-drift risk |
| Spawn spacing | **8 m along disc circumference** | 8 m | 8 m (donor verbatim) | Already world-anchored |

Velocity calibration: ~1.5 m/s cinematic walking-pace drift. Total drift over 2.5 s life = ~3.75 m. Explicit constant `kMirkPocWispDriftMetersPerSecond = 1.5`.

Radius basis = enum + paired constants:
```dart
enum WispRadiusBasis { screenPx, meters }
const kMirkPocWispRadiusBasis = WispRadiusBasis.screenPx; // default
```

**Paint order (relative to fog):** Wisps slot in as the LAST step inside `_FogPainter`'s existing `canvas.save()` / `canvas.restore()` sequence — drawn AFTER `canvas.drawRect(... shader)`, INSIDE the `canvas.translate(-canvasOffset)` (FOG-13) and INSIDE the `canvas.clipPath(clipPath)` (FOG-12). Implementation: extract a private `_renderWisps(Canvas canvas, MapCamera camera)` method on `_FogPainter`.

**Painter architecture:** Extend `_FogPainter` (single painter, atomic state). Fog and wisps share the SAME `canvas.getTransform()` snapshot, the SAME `MapCamera` (constructor-injected per FOG-07), the SAME canvas-translate frame, the SAME clipPath. Cannot desync.

**Render mechanism:** Flutter Canvas API `canvas.drawCircle` per wisp (donor approach). NOT a dedicated wisp shader. Phase 3.1 just spent 8 walks debugging shader-vs-Dart-side dimensional issues; adding a new shader multiplies that risk surface for negligible perf gain.

**Paint allocation:** ONE `Paint` allocated per `paint()` call (fields: `blendMode = BlendMode.plus`, `style = fill`); inside the per-wisp loop, only `paint.color` is mutated. 1 alloc per paint instead of donor's 200.

**Blend mode:** `BlendMode.plus` (additive — donor verbatim).

**Edge:** hard-edge `drawCircle` (donor — no `MaskFilter.blur`). Softness emerges from the low additive alpha (peak `0.35 × (1 - age²)`).

**Drift:**
- Spawn direction: outward radial from spawn point (donor); jitter factor `0.8 + rng.nextDouble() * 0.4`.
- Curl-noise perturbation: keep donor's organic-drift character. Magnitudes need re-derivation to m/sec² basis. Target ~0.5–1.0 m/sec² for cinematic drift.
- Spawn timing: one puff per new disc at first appearance (donor). After warmup, each newly-emerged disc spawns ~20 wisps once (8 m spacing × 157 m circumference). Cap (200) reached after ~10 disc-fixes; LRU eviction kicks in.
- Drag: donor's 0.30/sec linear drag verbatim.

**Shader-agnosticism (architectural property — documented, not CI-gated):** the wisp render path does NOT touch the fog shader. Wisps depend only on `MapCamera.latLngToScreenPoint(...)`, `canvas.drawCircle` + `Paint`, the fog clipPath, and the painter's identity-frame discipline. Wisps do NOT reference `uPixelOrigin`, `uZoomScale`, `uTime`, `FogShaderUniforms`, `atmospheric_fog*`, or any other fog-shader-specific symbol. Documented (this section + docstring on `_FogPainter._renderWisps(...)`), NOT CI-grep-enforced.

**DEBUG-01 /sanity compatibility:** wisps render only in production fog mode. `/sanity` debug-spiral mode skips the wisp render block (simple conditional in painter).

**Constants file additions (CONTEXT preview):**
```dart
const double kMirkPocWispDriftMetersPerSecond = 1.5;
const double kMirkPocWispLifeSeconds = 2.5;
const int kMirkPocWispMaxCount = 200;
const double kMirkPocWispMetersPerWisp = 8.0;
const double kMirkPocWispWarmUpSeconds = 5.0;
const double kMirkPocWispPeakAlpha = 0.35;
enum WispRadiusBasis { screenPx, meters }
const WispRadiusBasis kMirkPocWispRadiusBasis = WispRadiusBasis.screenPx;
const double kMirkPocWispBirthRadiusPx = 6.0;
const double kMirkPocWispDeathRadiusPx = 22.0;
const double kMirkPocWispBirthRadiusMeters = ...;  // calibrated at planning time
const double kMirkPocWispDeathRadiusMeters = ...;  // calibrated at planning time
const double kMirkPocWispCurlAccelMetersPerSecondSquared = ...;  // Claude's discretion
const double kMirkPocWispDragPerSecond = 0.30;
```

**Phase 3.1 carry-forwards (locked invariants — do NOT re-discuss):**
- **UX-02** rotation disabled. `InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)`.
- **DEBUG-02** cameraConstraint removed — Phase 4 walk plan MUST include the C3' extreme-distance regime (~50–100 km from Melun).
- **PERF-07 thresholds** — `medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48` (NOT obsolete ≥30fps). Walk #5 sustained 13×/20×/28× headroom on fog-only; Phase 4 must verify this holds under fog + 200 wisps.
- **"Walk" = sideload session at desk**, not physical walking.
- **`uZoomScale` slot 41 + `kPocFogReferenceZoom = 13.0`** — fog ABI; wisps don't consume it.
- **MIRL visual-identity rule** — adding ABI uniforms OK; modifying shader visual character to hide bugs is forbidden. Wisps don't add fog-shader uniforms.
- **FOG-07 single MapCamera snapshot per build** + **single `canvas.getTransform()` per paint** — wisps share THE snapshot, not just A snapshot.
- **Iteration policy** — no hard cap on walk count. Mail-share discipline mandatory post-walk.
- **WISP-05 `WispTransformLogger`** — analogous to `FogTransformLogger`; ship it before any walk (per shader-fix-retrospective lesson #4 "ship the diagnostic before you need it").

### Claude's Discretion

- Curl-noise force magnitude in m/sec² (target ~0.5–1.0 m/sec², calibrate by walk feedback).
- Curl input-position scale factor (donor used `position * 0.005` in screen-px; re-derive for LatLng basis).
- Wisp tint RGBA (donor's white/blue tint or different choice).
- Random jitter magnitude on spawn position (donor: ±2 px); re-express in chosen radius basis.
- Concrete `kMirkPocWispBirthRadiusMeters` / `kMirkPocWispDeathRadiusMeters` calibration values.
- Whether to introduce a separate `WispParticleSystem` class (donor-style) or inline the particle list into `_FogPainter`. **Recommend separate class for unit-testability** (consistent with this research's recommendation, see §Architecture Patterns).
- Spawn jitter on velocity speedFactor (donor: 0.8–1.2); keep verbatim or simplify.

### Deferred Ideas (OUT OF SCOPE)

- Wisp shader (FragmentProgram) — rejected for Phase 4
- Soft-edge wisps via pre-rasterized soft-circle Image — defer to walk feedback
- Continuous wisp emission while disc visible — defer
- CI grep-test for wisp shader-agnosticism — defer to v2
- WISP-06 acceptance criterion — not introduced
- Tangential / curl-only spawn directions — defer
- No-drag / higher-drag — defer
- GPU instancing / GLSL compute — out of POC scope
- Wisp tint per-fog-style — defer until v2 introduces multiple mirk styles
- Wisp interaction with fog density — out of POC scope
- Persistent wisp state across sessions — out of POC scope
- Tap-to-spawn / interactive wisps — not on hypothesis-validation path
- Wisp-shader port-back to MirkFall (vs Canvas API) — POC ships Canvas API; MirkFall inherits
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (REQUIREMENTS.md) | Research Support |
|----|-------------------------------|------------------|
| **WISP-01** | `WispParticleSystem` ported with positions refactored from `Offset` (screen px) to `LatLng` (world); projected via the SAME `MapCamera.of(context)` snapshot the fog uses (FOG-07 carry-over — wisps must share THE snapshot, not just A snapshot) | §Standard Stack (donor port path); §Architecture Patterns Pattern 1 (single-snapshot painter); §Code Examples Op 1 (LatLng→screen via `camera.latLngToScreenPoint`); §Common Pitfalls Pitfall 1 (multi-snapshot anti-pattern) |
| **WISP-02** | Spawn along disc perimeters as new discs appear; max 200 wisps; 8 m spacing; 2.5 s life; peak alpha 0.35 | §Standard Stack (donor `WispParticleSystem.spawnAtPosition` ports verbatim modulo unit re-derivation); §Code Examples Op 2 (perimeter spawn loop); §Don't Hand-Roll (LRU eviction) |
| **WISP-03** | 5 s warm-up phase suppresses wisp spawning on app open | §Architecture Patterns Pattern 2 (warmup state machine in `WispParticleSystem` or `MapScreen`); §Code Examples Op 3 (warmup gate) |
| **WISP-04** | Wisps render in same Canvas as fog + tile layer (same paint pass, same `MapCamera` snapshot) | §Architecture Patterns Pattern 1 (extend `_FogPainter`, NOT a sibling layer); §Common Pitfalls Pitfall 2 (sibling-painter desync); §Code Examples Op 4 (paint sequence with wisp insertion point) |
| **WISP-05** | `WispTransformLogger` (1-Hz JSONL via `Logger('infrastructure.mirk.wisp')`): active wisp count, mean particle age, LatLng bounds, screen-Offset bounds, spawn rate per second; wall-clock-aligned for grep-correlation against `infrastructure.mirk.fog_transform` + `.sdf` + `.frame_delta`. Implement BEFORE any walk attempt. | §Standard Stack (mirror `FogTransformLogger` — 195 LOC, 4 tests, walk-validated 6× over Phase 3.1); §Architecture Patterns Pattern 3 (logger lifecycle); §Code Examples Op 5 (recordPaint signature); §Validation Architecture (REQ map) |
| **PERF-07** carry-over | medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48 across ≥10 combined gestures, fog + 200 wisps | §State of the Art (donor measurement showed ~50 µs/frame for 200 wisps — well within budget); §Common Pitfalls Pitfall 3 (per-wisp `Paint` allocation = donor's mistake) |
| **PERF-08** carry-over | SDF cache thrash unchanged in Phase 4 — wisp paint must NOT trigger additional SDF rebuilds | §Architecture Patterns Pattern 1 (wisp render is post-fog, doesn't touch `sdfCache`); §Common Pitfalls Pitfall 4 (do NOT add wisp positions to `_FogPainter.shouldRepaint` identity check) |
| **UX-02** carry-over | rotation disabled — wisps not tested under rotation | §State of the Art (FOG-16 path-(a) precedent: if rotation re-enables, full canvas-inverse-transform required); §Open Questions Q1 |
</phase_requirements>

## Summary

Phase 4 is the **structurally lowest-risk phase since Phase 1**. The architectural keystone work was finished in Phase 3.1: a single `_FogPainter` already operates inside a single `MapCamera` snapshot (FOG-07), inside a single `canvas.getTransform()` snapshot (FOG-13), inside a single canvas-translate-to-world-frame discipline. Wisp rendering reduces to: (a) port the donor's `WispParticleSystem` with three structural changes (Offset→LatLng position, m/s velocity, Paint hoisted), (b) extract a `_renderWisps(canvas, camera)` method on `_FogPainter` called between `drawRect(... shader)` and `canvas.restore()`, (c) wire `MapScreen._onGpsFix → wispParticleSystem.spawnAtNewDisc(...)`, (d) ship `WispTransformLogger` from day one as a structural mirror of `FogTransformLogger`.

The cross-pipeline parity check (= "the FOG-07 single-snapshot discipline generalises to a second visual layer") is verified the moment the wisp `LatLng → screen-px` projection lands on the same blue-dot frame the fog clip-path holes already land on — because **`fog_clip_path.dart` already does this projection** via `camera.latLngToScreenPoint(LatLng(disc.lat, disc.lon))` (verified in source, line 83), and Walks #4–#6 confirmed it works at default and max zoom. The wisp path is the same call.

The only genuine residual risk is the **C3' extreme-distance regime (~50–100 km from Melun)**: wisps project as point particles, which is a different code path than the fog's continuous-noise sampling — fp32 precision artefacts could surface at high `pixelOrigin` magnitudes that the noise-sampling fog didn't expose. WISP-05 (`WispTransformLogger`) is the diagnostic instrument for this.

**Primary recommendation:** Port `WispParticleSystem` as a separate class (NOT inlined into `_FogPainter`) for unit-testability; ship `WispTransformLogger` in the SAME wave as the first wisp-render commit; mandate the C3' extreme-distance gesture in the very first walk attempt.

## Standard Stack

### Core (already in the project — no new deps)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter` | sdk `>=3.41.0 <3.42.0` | `Canvas`, `CustomPainter`, `Paint`, `BlendMode.plus`, `Listenable`, `Ticker` | Already in use by `_FogPainter`; the wisp render path is `canvas.drawCircle` per wisp |
| `flutter_map` | 7.0.2 (strict-pinned) | `MapCamera.latLngToScreenPoint(LatLng) → Point<double>` for per-paint LatLng→screen projection | The clip-path already calls this (`fog_clip_path.dart:83`); Walks #4–#6 validated it |
| `latlong2` | 0.9.1 | `LatLng` value type for wisp positions | Already used by `RevealDisc`, `MapCamera.center`, `FogTransformLogger.cameraCenter` |
| `logging` | 1.3.0 | `Logger('infrastructure.mirk.wisp')` for WISP-05 JSONL rollups | Same family as `infrastructure.mirk.fog_transform`, `.sdf`, `.frame_delta`, `.dev_marker` — wall-clock-aligned grep-correlation discipline |

### Supporting (in-repo donors / patterns)

| Source file | Purpose | When to Use |
|---|---|---|
| `C:/claude_checkouts/GOSL-MirkFall/lib/infrastructure/mirk/wisp/wisp_particle.dart` (43 LOC) | `WispParticle` mutable struct (position, velocity, life, maxLife, isDead, age) | Port verbatim with **two field-name changes**: `Offset position` → `LatLng position`; `Offset velocity` → `Offset velocityMetersPerSecond` (or rename to `velocityMps` for brevity). The mutable-struct design is justified in the donor's docstring (Freezed `copyWith` would allocate per-particle per-frame). |
| `C:/claude_checkouts/GOSL-MirkFall/lib/infrastructure/mirk/wisp/wisp_particle_system.dart` (217 LOC) | Spawn / advance / render / clear lifecycle, LRU cap enforcement, curl-noise + drag integrator | Port with **three structural changes**: (1) `spawnAtPosition` accepts `LatLng position` instead of `Offset position`; (2) velocity → m/s semantics with re-derived constants; (3) `render(canvas, tint)` becomes `render(canvas, camera, tint)` and projects each wisp via `camera.latLngToScreenPoint(w.position)` at paint time + hoists the `Paint` outside the loop. The curl-noise + LRU + integrator logic ports byte-for-byte. |
| `lib/infrastructure/mirk/fog_transform_logger.dart` (195 LOC) | Structural template for `WispTransformLogger` | Mirror the file: same dual-clock discipline (`Stopwatch.elapsedMicroseconds` for math, `DateTime.now()` only for `epochSecond` rollup tag), same `Timer.periodic` + `_emitRollup` pattern, same `kPocWispTransformBufferMaxSamples` FIFO drop, same `stop()` synchronous flush. **Replace** the 8 fog-diagnostic doubles with the 6 wisp-diagnostic fields (active count, mean age, latMin/Max/lonMin/Max, screenXMin/Max/screenYMin/Max, spawn rate). |
| `lib/presentation/widgets/fog_layer.dart` `_FogPainter.paint()` (lines 378–575) | Extension point for `_renderWisps(canvas, camera)` insertion | Insert call between `canvas.drawRect(Offset.zero & size, Paint()..shader = liveShader)` (line 572) and `canvas.restore()` (line 574). |
| `lib/presentation/widgets/fog_clip_path.dart` (line 83) | Reference call site for `camera.latLngToScreenPoint(LatLng)` | Wisp render mirrors this projection pattern verbatim (this is the cross-pipeline parity check). |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Donor `WispParticleSystem` separate class | Inline particle list into `_FogPainter` | **Tradeoff: testability.** Inlining means no unit tests for spawn/advance/LRU/curl-noise — they'd require widget-level fixtures. Separate class allows pure-Dart unit tests on the integrator + cap + spawn logic. **Recommend: separate class.** (CONTEXT.md "Claude's Discretion" agrees.) |
| `canvas.drawCircle` per wisp | Pre-rasterized soft-circle `ui.Image` + `canvas.drawImageRect` | Defer per CONTEXT (only revisit if hard-edge looks pixelated at zoom-out). |
| `canvas.drawCircle` per wisp | `canvas.drawAtlas(image, transforms, rects, colors, BlendMode.plus, ...)` | Genuine perf win for 200+ particles BUT: requires the pre-rasterized atlas, the colors array allocation per paint, additional code surface. Donor showed ~50 µs/frame for 200 wisps via per-wisp drawCircle = **negligible against the 16 ms PERF-07 budget** (0.3% of frame). Defer atlas optimisation to v2 / MirkFall port-back if needed. |
| `BlendMode.plus` | `BlendMode.screen` | Donor uses `plus`; visually validated on MirkFall. `screen` brightens with a different curve (1 - (1-a)(1-b)) — would change the visual character. Stick with donor. |

**Installation:** None — all libraries already pinned in `pubspec.yaml`.

## Architecture Patterns

### Recommended Project Structure

```
lib/infrastructure/mirk/wisp/                  # NEW (mirrors donor structure)
├── wisp_particle.dart                         # Ported (Offset → LatLng, ~50 LOC)
├── wisp_particle_system.dart                  # Ported (spawn/advance/render/clear, ~250 LOC)
└── wisp_transform_logger.dart                 # NEW (mirrors fog_transform_logger.dart, ~200 LOC)

lib/presentation/widgets/fog_layer.dart        # MODIFIED — extend _FogPainter:
                                               #   + constructor takes WispParticleSystem
                                               #   + new _renderWisps(canvas, camera) method
                                               #   + _renderWisps called between drawRect(...shader) and canvas.restore()

lib/presentation/screens/map_screen.dart       # MODIFIED — wire spawn:
                                               #   + WispParticleSystem field on _MapScreenState
                                               #   + WispTransformLogger field on _MapScreenState (start in initState, stop in dispose)
                                               #   + _onGpsFix → wispParticleSystem.spawnAtNewDisc(...) when discRepository.append produces a NEW disc
                                               #   + thread both into FogLayer constructor

lib/config/constants.dart                      # MODIFIED — append kMirkPocWisp* + kPocWispTransform* constants

test/infrastructure/mirk/wisp/                 # NEW
├── wisp_particle_test.dart                    # mutable-struct invariants, age curve, isDead at life ≤ 0
├── wisp_particle_system_test.dart             # spawn/advance/LRU/curl-noise/clear (pure Dart, no widget)
└── wisp_transform_logger_test.dart            # mirrors fog_transform_logger_test.dart (4 tests minimum)

test/presentation/widgets/
├── fog_layer_wisp_render_test.dart            # NEW — widget test asserting _renderWisps is called between drawRect(...shader) and canvas.restore()
└── fog_layer_single_camera_snapshot_test.dart # NEW — extend FOG-07 keystone: assert MapCamera.of(context) read count == 1 even with WispParticleSystem present
```

### Pattern 1: Single Painter Hosts Both Layers (the "same-Canvas" parity)

**What:** Wisps render inside `_FogPainter.paint()`, NOT in a sibling `CustomPainter`. The fog and the wisps share the SAME `MapCamera` (constructor-injected per FOG-07), the SAME `canvas.getTransform()` snapshot (per FOG-13), the SAME `canvas.translate(-canvasOffset)` frame, the SAME `canvas.clipPath(clipPath)`.

**When to use:** Any visual layer that must stay frame-locked with the existing fog. The donor's MirkFall codebase has wisps in a sibling renderer; that worked because the parent project hadn't surfaced BUG-014 yet. The POC must NOT replicate the sibling-renderer architecture — it would re-create a multi-snapshot trap (Pitfall 2).

**Example:**
```dart
// Source: lib/presentation/widgets/fog_layer.dart (existing _FogPainter.paint)
// + planned _renderWisps insertion point

@override
void paint(Canvas canvas, Size size) {
  if (sdfImage == null) return;
  final uTimeSeconds = wallClock.elapsedMicroseconds / _microsecondsPerSecond;

  // Single canvas-transform snapshot per paint (FOG-13).
  final canvasTransform = canvas.getTransform();
  final canvasOffset = Offset(canvasTransform[12], canvasTransform[13]);

  canvas.save();
  canvas.translate(-canvasOffset.dx, -canvasOffset.dy);  // FOG-13: into world (identity) frame.

  final clipPath = computeFogClipPath(camera: camera, discs: discs);
  canvas.clipPath(clipPath);                              // FOG-12

  // ...existing fog-uniform population + frame-delta probe + fog-transform logger...

  shaderRenderer.render(...);                             // FOG-05
  if (liveShader != null) {
    canvas.drawRect(Offset.zero & size, Paint()..shader = liveShader);  // fog
  }

  // --- NEW: wisp render inside the SAME save/restore block ---
  // Operates in the same world (identity) frame, inside the same clipPath,
  // shares the same MapCamera and the same canvas-translate snapshot.
  _renderWisps(canvas, camera);

  canvas.restore();
}

void _renderWisps(Canvas canvas, MapCamera camera) {
  if (wispParticleSystem.activeCount == 0) return;
  // Hoist Paint outside loop — donor allocated 200/frame; we allocate 1.
  final paint = Paint()
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.plus;
  final tint = kMirkPocWispTintColor;
  final tintR = (tint.r * 255.0).round();
  final tintG = (tint.g * 255.0).round();
  final tintB = (tint.b * 255.0).round();
  final tintA = (tint.a * 255.0).round();

  // WISP-05 per-paint capture (compute bounds inline; logger amortises stats).
  double latMin = double.infinity, latMax = -double.infinity;
  double lonMin = double.infinity, lonMax = -double.infinity;
  double screenXMin = double.infinity, screenXMax = -double.infinity;
  double screenYMin = double.infinity, screenYMax = -double.infinity;
  double meanAgeAcc = 0.0;

  for (final w in wispParticleSystem.wisps) {
    final age = w.age;
    final radius = kMirkPocWispBirthRadiusPx +
        (kMirkPocWispDeathRadiusPx - kMirkPocWispBirthRadiusPx) * age;
    final alphaFactor = (1.0 - age * age).clamp(0.0, 1.0);
    final wispAlpha = alphaFactor * kMirkPocWispPeakAlpha * (tintA / 255.0);
    paint.color = Color.fromARGB((wispAlpha * 255).round(), tintR, tintG, tintB);

    // Project LatLng → screen via THE camera snapshot (cross-pipeline parity).
    // Same call site as fog_clip_path.dart line 83.
    final screenPt = camera.latLngToScreenPoint(w.position);
    canvas.drawCircle(Offset(screenPt.x, screenPt.y), radius, paint);

    // WISP-05 bounds accumulation.
    if (w.position.latitude < latMin) latMin = w.position.latitude;
    if (w.position.latitude > latMax) latMax = w.position.latitude;
    if (w.position.longitude < lonMin) lonMin = w.position.longitude;
    if (w.position.longitude > lonMax) lonMax = w.position.longitude;
    if (screenPt.x < screenXMin) screenXMin = screenPt.x;
    if (screenPt.x > screenXMax) screenXMax = screenPt.x;
    if (screenPt.y < screenYMin) screenYMin = screenPt.y;
    if (screenPt.y > screenYMax) screenYMax = screenPt.y;
    meanAgeAcc += age;
  }

  final activeCount = wispParticleSystem.activeCount;
  wispTransformLogger.recordPaint(
    activeCount: activeCount,
    meanAge: activeCount > 0 ? meanAgeAcc / activeCount : 0.0,
    latBounds: (latMin, latMax),
    lonBounds: (lonMin, lonMax),
    screenXBounds: (screenXMin, screenXMax),
    screenYBounds: (screenYMin, screenYMax),
    spawnRatePerSecond: wispParticleSystem.spawnRatePerSecondAndReset(),
  );
}
```

### Pattern 2: Warmup Gate in `WispParticleSystem` (WISP-03)

**What:** A 5 s warm-up wall-clock guard inside `WispParticleSystem` that swallows `spawnAtNewDisc(...)` calls during the first 5 s post-construction; the disc IDs are still recorded in the "already-seen" set so they don't trigger a delayed puff later. The donor's `kMirkFogWispWarmUpSeconds = 5.0` ports verbatim as `kMirkPocWispWarmUpSeconds = 5.0`.

**When to use:** App-launch suppression — without warmup, every disc the user has ever revealed re-spawns a puff on app open, swamping the budget and looking like an explosion. With warmup, the screen is already settled by the time wisps start appearing.

**Example:**
```dart
class WispParticleSystem {
  WispParticleSystem({...})
      : _wallClockSinceConstruction = Stopwatch()..start();

  final Stopwatch _wallClockSinceConstruction;
  final Set<String> _alreadySpawnedDiscIds = <String>{};

  void spawnAtNewDisc({required String discId, required RevealDisc disc, required MapCamera camera}) {
    if (_alreadySpawnedDiscIds.contains(discId)) return;
    _alreadySpawnedDiscIds.add(discId);

    // WISP-03: warmup gate. Disc ID is recorded above so it never re-triggers.
    if (_wallClockSinceConstruction.elapsedMilliseconds <
        (kMirkPocWispWarmUpSeconds * 1000).round()) {
      return;
    }

    // ... compute perimeter sample points at 8m spacing, call spawnAtPosition for each ...
  }
}
```

### Pattern 3: Mirror `FogTransformLogger` for `WispTransformLogger` (WISP-05)

**What:** `WispTransformLogger` is a structural sibling of `FogTransformLogger` — same constructor seam (`Duration? rollupInterval`), same `Logger('infrastructure.mirk.wisp')` channel, same wall-clock-aligned 1-Hz `Timer.periodic`, same `recordPaint(...)` API + buffer, same `stop()`-flushes-pending-samples discipline, same FIFO drop on overflow at `kPocWispTransformBufferMaxSamples`. The fields differ:

| `FogTransformLogger` (8 doubles) | `WispTransformLogger` (8 doubles + 1 int) |
|---|---|
| canvasTx, canvasTy, pixelOriginX, pixelOriginY, centerLat, centerLon, uOffsetX, uOffsetY | activeCount (int), meanAge, latMin, latMax, lonMin, lonMax, screenXMin, screenXMax, screenYMin, screenYMax, spawnRatePerSecond |

For each numeric field, emit min/median/max per rollup; for `activeCount`, emit sampleCount-weighted mean + max; for `spawnRatePerSecond`, emit the running counter divided by the rollup interval.

**When to use:** Always. Per the shader-fix retrospective lesson #4 ("ship the diagnostic before you need it"), this logger lands in the same wave as the wisp-render commit, NOT after a failed walk.

### Anti-Patterns to Avoid

- **Sibling `CustomPaint` for wisps.** Putting wisps in a separate `CustomPainter` (whether before, after, or as a child of `FogLayer`) means they re-read `MapCamera.of(context)` independently — that's a multi-snapshot anti-pattern, exactly the BUG-014 trap Phase 3.1 closed. Use Pattern 1.
- **Recomputing canvas transform inside `_renderWisps`.** Reuse the `canvasTransform` Float64List captured at the top of `paint()`. Calling `canvas.getTransform()` a second time would allocate a second Float64List per paint and re-introduce the multi-snapshot anti-pattern at the matrix level.
- **Adding wisp positions to `_FogPainter.shouldRepaint`.** Don't compare wisp lists in `shouldRepaint` — the per-frame `Ticker` already drives `_repaint.notifyListeners()`. Adding a wisp identity check would either (a) repaint every frame regardless (no-op) or (b) miss frames if the list reference is reused (worse). Keep `shouldRepaint` checking only `camera`/`discs`/`sdfImage` identity.
- **Per-wisp `Paint` allocation.** Donor allocates 200 `Paint` objects per frame inside the loop. Hoist outside; mutate `paint.color` only. Pure-perf, behaviorally identical.
- **Capturing `wallClock.elapsedMicroseconds` once and integrating wisps with that frozen `dt`.** Same anti-pattern as the frozen `uTimeSeconds` Plan 03-08 caught: would freeze wisp drift between rebuilds. Compute `dt = (currentMicros - lastPaintMicros) / 1e6` inside `paint()` from a `_lastPaintMicros` field updated each call.
- **Calling `latLngToScreenPoint` outside the painter (e.g., in `WispParticleSystem.advance`).** Projection MUST happen at paint time using THE camera snapshot. Projecting at integration time would use whatever camera is current then, not the camera the fog uses — desync trap.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| LatLng → screen-px projection | Manual web-mercator math | `camera.latLngToScreenPoint(LatLng) → Point<double>` | flutter_map 7.0.2 verified at `lib/src/map/camera/camera.dart:263-275`; handles CRS, rotation (zero in our case), and `nonRotatedPixelOrigin` correctly; already battle-tested by `fog_clip_path.dart` over 6 walks |
| LRU eviction of overflow particles | `removeWhere` + manual age tracking | Donor's `_enforceCap()`: sort by life descending, `removeRange(_maxCount, ...)` | Donor pattern is O(N log N) at cap-hit (sub-microsecond at N=200), correctness already validated on MirkFall; no allocations beyond the sort buffer |
| Per-frame timer (warmup gate, dt accumulation) | Manual frame counters | `Stopwatch()..start()` / `_wallClockSinceConstruction.elapsedMilliseconds` | Already the project pattern (`fog_layer.dart:210` for fog wallClock); dual-clock discipline (Stopwatch for math, DateTime for epoch tags) is the project standard |
| 1-Hz JSONL rollup with min/median/max stats | Custom histogram | `FogTransformLogger.computeStats(sortedAscending)` static helper, copied | The static helper is already `@visibleForTesting`-exposed; `WispTransformLogger` should reuse the same shape (or factor to a shared `_RollupStats` mixin if duplication grows) |
| Wall-clock-aligned rollup boundary | Custom alignment math | `Timer.periodic(rollupInterval, _emitRollup)` + `DateTime.now().millisecondsSinceEpoch ~/ 1000` for the `epochSecond` tag | Identical to `FogTransformLogger`/`SdfRebuildLogger`/`FrameDeltaProbe` — ALL three rollup loggers must derive `epochSecond` identically for grep-correlation to work |
| Curl-noise gradient field | Plug a noise package | Donor's hash-based `_curlNoise(p)` + `_scalarNoise(p)` + `_hash2(x, y)` | Already inlined in donor's `WispParticleSystem` (lines 181–216); no allocation, deterministic via `math.Random(rngSeed)`; matches the visual character of the fog shader's curl term so the two systems "agree" without coupling |
| Disc-emergence detection | Cell-based hash | `Set<String> _alreadySpawnedDiscIds` keyed on the disc's `rvd_<microsSinceEpoch>_<randomU32>_<counter>` ID (already minted in `RevealDiscRepository`) | Donor's current architecture; pre-Commit-5 used cell-keyed which had subtle drift bugs |

**Key insight:** Phase 4 is almost entirely "wire up existing battle-tested pieces." The interesting engineering work is (a) the LatLng-vs-screen-px structural rewrite of the donor's two files, (b) the cross-pipeline parity check (single-painter discipline), and (c) the WISP-05 diagnostic. Everything else is straight donor port + project-standard mirror.

## Common Pitfalls

### Pitfall 1: Multi-snapshot `MapCamera` (the BUG-014 trap, Phase 4 incarnation)
**What goes wrong:** Wisps drift relative to the map during pan/zoom, exactly the way the fog drifted in Plan 03-08.
**Why it happens:** `WispParticleSystem.render(...)` reads `MapCamera.of(context)` independently, OR a sibling `CustomPainter` reads it independently, OR `WispParticleSystem.advance(dt)` calls `latLngToScreenPoint(...)` (projection at integration time, not paint time).
**How to avoid:** (a) Wisps render inside `_FogPainter.paint()`, never in a sibling painter. (b) `_FogPainter` constructor takes `WispParticleSystem` by reference; the painter passes THE `camera` field (already FOG-07 single-snapshot) into `_renderWisps(canvas, camera)`. (c) `WispParticleSystem.advance(dt)` does NOT touch `camera`; it integrates LatLng + velocity in m/s (with metres-per-degree-lat conversion) without projecting.
**Warning signs:** Any reference to `MapCamera.of(context)` outside `FogLayer.build`. Any second `canvas.getTransform()` call inside `_FogPainter.paint`. Any call to `camera.latLngToScreenPoint` from outside `_FogPainter.paint` body.

### Pitfall 2: Sibling-painter desync (the "wisps lag the fog by one frame" trap)
**What goes wrong:** Wisps and fog appear at slightly different positions during fast pan; visually the wisps look like they're "trailing" the fog or vice versa.
**Why it happens:** Two `CustomPaint` widgets each have their own `paint()` cycle; even with the same `MapCamera`, the order of `paint()` calls vs `MapCamera` rebuilds is not guaranteed; even one-frame skew is visible at 120 Hz.
**How to avoid:** Single `_FogPainter` hosts both. Single `paint()` body, single `canvas.save()`/`restore()` pair, single `MapCamera` reference, single canvas-transform snapshot.
**Warning signs:** Plan splits wisps into a separate `WispLayer extends StatefulWidget`; review and reject.

### Pitfall 3: Per-wisp `Paint` allocation kills the frame budget at the cap
**What goes wrong:** At 200 wisps × 120 Hz = 24,000 `Paint` allocations per second. GC pressure surfaces as p95Ms spikes (PERF-07 third sub-criterion regression).
**Why it happens:** Donor allocates inside the per-wisp loop (`wisp_particle_system.dart:164`).
**How to avoid:** Hoist `final paint = Paint()..style = PaintingStyle.fill..blendMode = BlendMode.plus;` outside the loop; mutate `paint.color` only. The `Color.fromARGB(...)` allocation per wisp is unavoidable but cheap (small Color value-object, no Skia round-trip).
**Warning signs:** Profile shows `Paint.<init>` in the per-frame allocation top-10 during walks; PERF-07 p95 regresses from ~5 ms to >10 ms while wisps are active.

### Pitfall 4: `shouldRepaint` over-triggers from wisp identity
**What goes wrong:** Every paint becomes a "must-rebuild" and the painter optimisation pathway dies.
**Why it happens:** Adding `!identical(oldDelegate.wispParticleSystem, wispParticleSystem)` to `shouldRepaint`. Since wisp lists mutate in place via `_wisps.add` / `_wisps.removeAt`, identity stays equal across mutations BUT a defensive snapshot would change identity every frame.
**How to avoid:** Don't add wisp checks to `shouldRepaint`. The `Ticker` → `_repaint.notifyListeners()` chain already drives per-frame paints; wisp state changes are picked up automatically by the `paint()` call.
**Warning signs:** `_FogPainter.shouldRepaint` body grows beyond the existing camera/discs/sdfImage triple.

### Pitfall 5: fp32 precision in `latLngToScreenPoint` at extreme distance (THE C3' regime)
**What goes wrong:** At ~50–100 km from Melun (DEBUG-02 stress test), `pixelOrigin` magnitudes can reach 4M+ raw px. Internally `latLngToScreenPoint` computes `crs.latLngToPoint(latLng, zoom) - nonRotatedPixelOrigin` — both terms are large, the difference is small. fp32 sub-pixel ULP at 4M magnitude = ~0.5 raw px; wisps could visibly jitter relative to the disc perimeter they spawned at.
**Why it happens:** Walk #4 surfaced the analogous fp32 issue in the fog shader (Q1 max-zoom 2 dev_markers fired); the fix was the FOG-17a → FOG-18 path. Wisps run a different code path (host-side `latLngToScreenPoint` instead of shader-side `worldPx = fragUv * uResolution + uPixelOrigin`), so the failure mode could surface independently.
**How to avoid:** WISP-05 `WispTransformLogger` captures `latMin/Max/lonMin/Max + screenXMin/Max/screenYMin/Max` per paint. Walk plan MUST include the C3' extreme-distance regime. If wisp jitter visible, mitigation is the analogue of FOG-18: compute the offset host-side as `(crs.latLngToPoint(wispLatLng, zoom) - crs.latLngToPoint(centerLatLng, zoom)) + viewportCenterPx` to keep the projection arithmetic small-magnitude.
**Warning signs:** WISP-05 rollups show `screenXMax - screenXMin` jumps non-monotonically during a smooth pan at zoom ≥15 + position 50+ km from Melun.

### Pitfall 6: Frozen `dt` in `advance(...)` (the donor doesn't have this problem; we might introduce it)
**What goes wrong:** Wisps freeze in place; curl-noise drift stops; visually they look like dead pixels.
**Why it happens:** Capturing `dt` once at build time (e.g., a `final dt = ...` in `FogLayer.build`) instead of computing `dt = (currentMicros - lastPaintMicros) / 1e6` afresh inside each `paint()` call. Same anti-pattern shape as the frozen `uTimeSeconds` failure mode `_FogPainter` already documents (lines 386–389).
**How to avoid:** Either (a) `_FogPainter` keeps a `_lastPaintMicros` field, computes `dt` per paint, calls `wispParticleSystem.advance(dt)` at the top of `_renderWisps`, OR (b) a separate Ticker on `_FogLayerState` calls `wispParticleSystem.advance(dt)` from the Ticker callback (same callback that already calls `_repaint.notifyListeners()`). Option (b) decouples integration from paint cadence — preferred if `paint()` skips frames during heavy SDF rebuilds.
**Warning signs:** Wisps don't drift at all (frozen `dt = 0`), or wisps drift much faster/slower than the 1.5 m/s constant predicts.

## Code Examples

Verified patterns from in-tree sources:

### Op 1: LatLng → screen via THE camera snapshot (cross-pipeline parity check)
```dart
// Source: lib/presentation/widgets/fog_clip_path.dart:83 (existing, verified Walks #4-6)
//
// The wisp render path uses THE SAME call against THE SAME camera snapshot.
// This IS the cross-pipeline parity check that completes the code-donor package.
final screenPt = camera.latLngToScreenPoint(LatLng(disc.lat, disc.lon));
final centerOffset = Offset(screenPt.x.toDouble(), screenPt.y.toDouble());
```

```dart
// Source: planned _renderWisps body (this research's Pattern 1)
final screenPt = camera.latLngToScreenPoint(w.position);
canvas.drawCircle(Offset(screenPt.x, screenPt.y), radius, paint);
```

### Op 2: Disc-perimeter spawn loop (8 m spacing)
```dart
// Source: planned WispParticleSystem.spawnAtNewDisc(...) body
//
// 8 m spacing × 2π × 25 m radius ≈ 19.6 sample points → 20 wisps per puff.
// Outward unit-normal at each sample point = the spawn direction.
void spawnAtNewDisc({
  required String discId,
  required RevealDisc disc,
  required MapCamera camera,
}) {
  if (_alreadySpawnedDiscIds.contains(discId)) return;
  _alreadySpawnedDiscIds.add(discId);
  if (_wallClockSinceConstruction.elapsedMilliseconds <
      (kMirkPocWispWarmUpSeconds * 1000).round()) return;

  const radiusMeters = kPocRevealDiscRadiusMeters;  // 25 m (already in constants)
  final circumferenceMeters = 2 * math.pi * radiusMeters;
  final sampleCount = (circumferenceMeters / kMirkPocWispMetersPerWisp).round();

  for (var i = 0; i < sampleCount; i++) {
    final theta = (i / sampleCount) * 2 * math.pi;
    // Unit-normal at the perimeter sample point = (cos(theta), sin(theta)) in
    // local-tangent-plane meters. Convert to LatLng offset using metres-per-
    // degree (already used by fog_clip_path.dart for the radius-meters → screen-px
    // conversion).
    final dLat = radiusMeters * math.sin(theta) / kMetersPerDegreeLat;
    final dLon = radiusMeters * math.cos(theta) /
        (kMetersPerDegreeLat * math.cos(disc.lat * math.pi / 180.0));
    final spawnLatLng = LatLng(disc.lat + dLat, disc.lon + dLon);
    // Outward unit-direction in m/s basis (Offset reused as a 2D vector type).
    // Rotates with theta so each wisp drifts radially OUT of its spawn point.
    final unitDirection = Offset(math.cos(theta), math.sin(theta));
    spawnAtPosition(position: spawnLatLng, direction: unitDirection);
    _spawnCounterSinceLastRollup += 1;
  }
}
```

### Op 3: Warmup gate (WISP-03)
```dart
// Source: planned WispParticleSystem constructor + spawnAtNewDisc opening
WispParticleSystem({int maxCount = kMirkPocWispMaxCount, int rngSeed = 1337})
    : _maxCount = maxCount,
      _rng = math.Random(rngSeed),
      _wallClockSinceConstruction = Stopwatch()..start();

void spawnAtNewDisc(...) {
  // ... idempotency guard ...
  if (_wallClockSinceConstruction.elapsedMilliseconds <
      (kMirkPocWispWarmUpSeconds * 1000).round()) {
    return;
  }
  // ... perimeter sample loop ...
}
```

### Op 4: Paint sequence with wisp insertion point
```dart
// Source: lib/presentation/widgets/fog_layer.dart _FogPainter.paint() lines 425-575
// + planned _renderWisps insertion at line 573 (between drawRect and canvas.restore)

canvas.save();
canvas.translate(-canvasOffset.dx, -canvasOffset.dy);  // FOG-13 (existing, unchanged)
final clipPath = computeFogClipPath(camera: camera, discs: discs);
canvas.clipPath(clipPath);                              // FOG-12 (existing, unchanged)
// ... shaderRenderer.render(...), fogTransformLogger, frameDeltaProbe, etc. ...
shaderRenderer.render(...);
canvas.drawRect(Offset.zero & size, Paint()..shader = liveShader);  // fog (existing, unchanged)

// --- NEW INSERTION ---
_renderWisps(canvas, camera);

canvas.restore();
```

### Op 5: WispTransformLogger.recordPaint signature (mirror of FogTransformLogger)
```dart
// Source: planned wisp_transform_logger.dart, mirroring fog_transform_logger.dart
//
// 9 fields per sample (1 int + 8 doubles). Stats emitted as min/median/max for
// the doubles + sum/max for the int + spawnRate as a per-rollup running counter.

void recordPaint({
  required int activeCount,
  required double meanAge,                    // [0, 1]
  required (double min, double max) latBounds,
  required (double min, double max) lonBounds,
  required (double min, double max) screenXBounds,
  required (double min, double max) screenYBounds,
  required double spawnRatePerSecond,          // wisps spawned in this rollup window / interval
}) {
  _frameCounter += 1;
  _buffer.add(_WispTransformSample(
    frameCounter: _frameCounter,
    activeCount: activeCount,
    meanAge: meanAge,
    latMin: latBounds.$1, latMax: latBounds.$2,
    lonMin: lonBounds.$1, lonMax: lonBounds.$2,
    screenXMin: screenXBounds.$1, screenXMax: screenXBounds.$2,
    screenYMin: screenYBounds.$1, screenYMax: screenYBounds.$2,
    spawnRatePerSecond: spawnRatePerSecond,
  ));
  while (_buffer.length > kPocWispTransformBufferMaxSamples) {
    _buffer.removeAt(0);
  }
}

// _emitRollup mirrors FogTransformLogger._emitRollup verbatim, with the field
// list swapped. Same epochSecond derivation, same sampleCount, same Logger.info
// emission via 'infrastructure.mirk.wisp'.
```

### Op 6: MapScreen wiring (spawn integration)
```dart
// Source: planned _MapScreenState changes
//
// initState: construct logger + system, start logger.
// _onGpsFix: detect NEW disc emergence by checking discRepository's pre-append
//            length, append, and only then spawn wisps if a new ID landed.

late final WispTransformLogger _wispTransformLogger;
late final WispParticleSystem _wispParticleSystem;

@override
void initState() {
  super.initState();
  _wispTransformLogger = WispTransformLogger();
  _wispTransformLogger.start();
  _wispParticleSystem = WispParticleSystem();
  // ... existing initState ...
}

@override
void dispose() {
  _wispTransformLogger.stop();
  // ... existing dispose ...
}

void _onGpsFix(Position fix) {
  final preAppendCount = widget.services.discRepository.snapshot().length;
  final newDisc = widget.services.discRepository.append(lat: fix.latitude, lon: fix.longitude);
  final postAppendCount = widget.services.discRepository.snapshot().length;
  if (postAppendCount > preAppendCount && newDisc != null) {
    // NEW disc landed — spawn a wisp puff at its perimeter.
    final camera = MapController.of(context).camera;
    _wispParticleSystem.spawnAtNewDisc(
      discId: newDisc.id,
      disc: newDisc,
      camera: camera,
    );
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MirkFall donor: wisps in sibling renderer; `Offset` positions; per-wisp `Paint` allocation; 18 px/s velocity | POC: wisps inside `_FogPainter`; `LatLng` positions; hoisted `Paint`; 1.5 m/s velocity | Phase 3.1 (BUG-014 closure → FOG-07/13/17/18/19 stack) | Wisps anchor to world coordinates instead of screen pixels; perf headroom 5–66× preserved at the cap |
| Phase 3 (Plan 03-08): single fog `CustomPainter`, `MapCamera.of(context)` read in painter | Phase 3.1 (Plan 03.1-XX): single-snapshot read in `FogLayer.build`, painter receives by constructor; FOG-07 keystone test | 2026-05-02 (Plan 03.1-02) | Plan 04-XX inherits this; wisps share THE snapshot |
| ≥30 fps PERF-04 criterion | medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48 PERF-07 (frame-time budget) | 2026-05-02 (Phase 3.1 PERF-07 measurement) | Phase 4 verifies these thresholds hold with fog + 200 wisps active |
| FOG-16 path-(b) full canvas-inverse-transform for rotation | FOG-16 path-(a): UX-02 disable rotation entirely | 2026-05-04 (Phase 3.1 closure) | Phase 4 wisps do NOT need rotation-aware projection; if rotation re-enables in v2, full canvas-inverse-transform must land first |

**Deprecated/outdated (do NOT port from MirkFall):**
- Donor's `kMirkFogWispInitialSpeedPx = 18.0` (px/s — the BUG-014-shape mistake at scale).
- Donor's per-wisp `Paint()..style..blendMode..color` allocation inside the loop.
- Donor's `Offset position` field on `WispParticle`.
- Donor's `render(canvas, tint)` signature (no camera) — wisps must project at paint time.
- Donor's pre-Commit-5 cell-keyed spawn surface (`spawnAtCellCenter`); use the disc-keyed path.

## Open Questions

1. **Q1 — fp32 precision at C3' extreme distance.** Will `camera.latLngToScreenPoint(wispLatLng)` at 50–100 km from Melun produce visible jitter on the wisp positions during smooth pan?
   - What we know: Walk #4 fired 2 dev_markers at max-zoom in the fog shader's analogue code path; fp32 mantissa precision is ~0.5 raw px at 4M magnitude.
   - What's unclear: whether `latLngToScreenPoint`'s CRS pipeline (`crs.latLngToPoint(latLng, zoom) - nonRotatedPixelOrigin`) produces the same magnitude of jitter or amplifies it.
   - Recommendation: WISP-05 captures `screenXMin/Max/screenYMin/Max` per paint; walk plan MUST include the C3' pan; if jitter visible, mitigation is the host-side delta projection in Pitfall 5.

2. **Q2 — `dt` source for `WispParticleSystem.advance(dt)`.** Drive integration from the painter's `paint()` cadence (variable, can skip frames during SDF rebuilds) OR from a separate `_FogLayerState` Ticker callback (regular per-frame)?
   - What we know: Both approaches work; donor uses paint-time integration; project's existing pattern (fog `wallClock`) uses paint-time read.
   - What's unclear: whether 200-wisp integration cost is high enough that decoupling matters for PERF-07.
   - Recommendation: Start with paint-time integration (simplest, mirrors fog wallClock pattern); decouple to Ticker callback only if PERF-07 regresses or wisps freeze during SDF rebuild bursts.

3. **Q3 — Curl-noise constants in m/sec² basis.** Donor uses `curlMagnitude = 8.0` px/sec² in screen-px basis; what's the m/sec² equivalent that produces the same visual character?
   - What we know: Donor uses `position * 0.005` as the curl input (px-scale 0.005 → ~5 m at zoom 13); CONTEXT defers this as Claude's Discretion.
   - What's unclear: the exact magnitude that matches "cinematic drift" vs "swarming bees."
   - Recommendation: Pick `kMirkPocWispCurlAccelMetersPerSecondSquared = 0.5` as initial value; calibrate by walk feedback (CONTEXT explicitly defers this to plan/execute time).

4. **Q4 — Disc emergence detection at `MapScreen` level.** `RevealDiscRepository.append(...)` returns whatever it returns; the spec assumes a "did a new disc land?" signal. Check the actual API.
   - What we know: `RevealDiscRepository.append` is wired via Plan 03-07; returns either a new `RevealDisc` or null/no-op if the same fix is duplicated.
   - What's unclear: the exact return type and how "new disc landed" is signaled.
   - Recommendation: Plan 04-XX Wave 0 verifies `RevealDiscRepository.append` API (read source); if return type doesn't carry the "new vs duplicate" signal cleanly, compare pre/post `snapshot().length` (shown in Op 6).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (sdk pin); `package:test` 1.30.0 for `tool/test/check_*_test.dart` |
| Config file | `analysis_options.yaml` (strict-casts/inference/raw-types); no `pytest.ini`-equivalent (Flutter's default) |
| Quick run command | `flutter test test/infrastructure/mirk/wisp/ test/presentation/widgets/fog_layer_wisp_render_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WISP-01 | `WispParticle.position` is `LatLng`; `WispParticleSystem.render` projects via `camera.latLngToScreenPoint` at paint time | unit + widget | `flutter test test/infrastructure/mirk/wisp/wisp_particle_test.dart test/presentation/widgets/fog_layer_wisp_render_test.dart` | ❌ Wave 0 (both files NEW) |
| WISP-01 | FOG-07 keystone holds with WispParticleSystem present: `MapCamera.of(context)` read count == 1 per `FogLayer.build` even after wisp wiring | widget | `flutter test test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart` | ❌ Wave 0 (file NEW; mirrors `fog_layer_camera_snapshot_test.dart` shape) |
| WISP-02 | `spawnAtNewDisc` produces ~20 wisps per disc at 8 m spacing; respects 200-cap; LRU evicts oldest | unit | `flutter test test/infrastructure/mirk/wisp/wisp_particle_system_test.dart` | ❌ Wave 0 (NEW file) |
| WISP-02 | `WispParticle.life` decays per `advance(dt)`; `isDead` triggers in-place removal; alpha curve follows `1 - age²` | unit | `flutter test test/infrastructure/mirk/wisp/wisp_particle_test.dart` | ❌ Wave 0 (NEW file) |
| WISP-03 | First 5 s of system lifetime: `spawnAtNewDisc` is a no-op; disc IDs still recorded in `_alreadySpawnedDiscIds` so they don't re-trigger post-warmup | unit | `flutter test test/infrastructure/mirk/wisp/wisp_particle_system_test.dart::warmup` | ❌ Wave 0 (NEW file) |
| WISP-04 | `_FogPainter.paint()` calls `_renderWisps` between `drawRect(...shader)` and `canvas.restore()`; sequence verified via recording canvas | widget | `flutter test test/presentation/widgets/fog_layer_wisp_render_test.dart::paint_sequence` | ❌ Wave 0 (NEW file) |
| WISP-04 | Wisp `drawCircle` calls happen at `MapCamera.latLngToScreenPoint(LatLng)` for each wisp's position (no other coordinate computation) | widget | `flutter test test/presentation/widgets/fog_layer_wisp_render_test.dart::projection_path` | ❌ Wave 0 (NEW file) |
| WISP-05 | `WispTransformLogger.recordPaint` buffers samples; emits 1 JSONL rollup per active second via `Logger('infrastructure.mirk.wisp')` with min/median/max stats for 8 doubles + sampleCount + epochSecond | unit | `flutter test test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart` | ❌ Wave 0 (NEW file; mirrors `fog_transform_logger_test.dart`) |
| WISP-05 | `stop()` flushes pending samples synchronously (last-rollup-loss prevention) | unit | `flutter test test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart::stop_flushes` | ❌ Wave 0 (NEW file) |
| WISP-05 | `epochSecond` derived identically to `FogTransformLogger` (`DateTime.now().millisecondsSinceEpoch ~/ 1000`) for grep-correlation | unit | `flutter test test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart::epoch_second_derivation` | ❌ Wave 0 (NEW file) |
| PERF-07 carry-over | medianMs ≤ 16, p95Ms ≤ 32, maxMs ≤ 48 across ≥10 combined gestures with fog + 200 wisps active | manual-only — sideload walk + `infrastructure.mirk.frame_delta` JSONL post-walk grep | N/A (walk evidence only) | N/A — Phase 4 walk plan + WISP-05 grep-correlation |
| PERF-08 carry-over | SDF cache rebuild rate unchanged from Phase 3.1 baseline (1-121/sec, median 68/sec) when wisps active | manual-only — sideload walk + `infrastructure.mirk.sdf` JSONL post-walk grep | N/A (walk evidence only) | N/A — Phase 4 walk plan |
| UX-02 carry-over | `InteractionOptions.flags & InteractiveFlag.rotate == 0` unchanged after wisp wiring | widget | `flutter test test/presentation/screens/map_screen_test.dart::interaction_options_rotation_disabled` | ✅ exists (Plan 03.1-10) — re-run as smoke check post-Phase-4 wiring |
| Architectural carry-over | Wisp render does NOT reference `uPixelOrigin`, `uZoomScale`, `uTime`, `FogShaderUniforms`, `atmospheric_fog*`. Documented, NOT CI-grep-enforced (per CONTEXT decision). | docstring + code review | N/A | N/A — enforcement is review-time, not CI-time per CONTEXT |

### Sampling Rate

- **Per task commit:** `flutter test test/infrastructure/mirk/wisp/ test/presentation/widgets/fog_layer_wisp_render_test.dart test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart` (~5–10 s, suffices for tight inner-loop on the wisp + same-Canvas-keystone path)
- **Per wave merge:** `flutter test` (full suite — catches FOG-07 keystone regression, FOG-12/13 clip+translate regression, all Phase 3.1 carry-overs)
- **Phase gate:** Full suite GREEN + a sideload walk that exercises the C3' extreme-distance regime + WISP-05 grep-correlation against `infrastructure.mirk.fog_transform` + `infrastructure.mirk.sdf` + `infrastructure.mirk.frame_delta` rollups before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `lib/infrastructure/mirk/wisp/wisp_particle.dart` — port + adapt (Offset → LatLng position); covers WISP-01
- [ ] `lib/infrastructure/mirk/wisp/wisp_particle_system.dart` — port + adapt (m/s velocity, hoisted Paint, latLngToScreenPoint at render); covers WISP-01/02/03
- [ ] `lib/infrastructure/mirk/wisp/wisp_transform_logger.dart` — NEW (mirror of `fog_transform_logger.dart`); covers WISP-05
- [ ] `lib/config/constants.dart` additions — append `kMirkPocWisp*` + `kPocWispTransform*` constants per CONTEXT preview
- [ ] `lib/presentation/widgets/fog_layer.dart` modifications — extend `_FogPainter` constructor + insert `_renderWisps`; covers WISP-04
- [ ] `lib/presentation/screens/map_screen.dart` modifications — wire `WispParticleSystem` + `WispTransformLogger`; covers WISP-02/03/05 integration
- [ ] `test/infrastructure/mirk/wisp/wisp_particle_test.dart` — NEW; covers WISP-01 (LatLng position), WISP-02 (life decay, age curve)
- [ ] `test/infrastructure/mirk/wisp/wisp_particle_system_test.dart` — NEW; covers WISP-02 (spawn loop, LRU cap), WISP-03 (warmup gate)
- [ ] `test/infrastructure/mirk/wisp/wisp_transform_logger_test.dart` — NEW; covers WISP-05 (rollup math, stop-flushes, epoch derivation)
- [ ] `test/presentation/widgets/fog_layer_wisp_render_test.dart` — NEW; covers WISP-04 (paint sequence, projection path)
- [ ] `test/presentation/widgets/fog_layer_single_camera_snapshot_test.dart` — NEW; covers WISP-01 (FOG-07 keystone holds with wisps wired)

(No new test framework install needed — `flutter_test` already configured; no shared fixtures required beyond what already exists in `test/_helpers/`.)

## Sources

### Primary (HIGH confidence)
- `C:/claude_checkouts/mirk-poc-debug/.planning/phases/04-wisp-particles/04-CONTEXT.md` (locked decisions; the planner's ground truth)
- `C:/claude_checkouts/mirk-poc-debug/.planning/REQUIREMENTS.md` lines 95–99 (WISP-01..05 acceptance criteria) + lines 78–82 (FOG-17/18/19 — wisp render benefits inherit from these) + lines 122 (PERF-07 measured baseline)
- `C:/claude_checkouts/GOSL-MirkFall/lib/infrastructure/mirk/wisp/wisp_particle.dart` (donor — to be ported with Offset→LatLng change)
- `C:/claude_checkouts/GOSL-MirkFall/lib/infrastructure/mirk/wisp/wisp_particle_system.dart` (donor — to be ported with three structural changes)
- `C:/claude_checkouts/GOSL-MirkFall/lib/config/constants.dart` lines 740–788 (donor `kMirkFogWisp*` constants — port to `kMirkPocWisp*` per CONTEXT)
- `C:/claude_checkouts/mirk-poc-debug/lib/presentation/widgets/fog_layer.dart` (extension point — `_FogPainter.paint()` lines 378–575; insertion at line 573)
- `C:/claude_checkouts/mirk-poc-debug/lib/infrastructure/mirk/fog_transform_logger.dart` (structural template for `WispTransformLogger`)
- `C:/claude_checkouts/mirk-poc-debug/lib/presentation/widgets/fog_clip_path.dart` line 83 (existing `camera.latLngToScreenPoint` call — proves the projection path works under all Phase 3.1 walk regimes)
- `C:/Users/oliver/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_map-7.0.2/lib/src/map/camera/camera.dart` lines 263–275 (verified `MapCamera.latLngToScreenPoint(LatLng) → Point<double>` signature; subtracts `nonRotatedPixelOrigin`; rotation handling is no-op since UX-02 disables rotation)
- `C:/claude_checkouts/mirk-poc-debug/test/infrastructure/mirk/fog_transform_logger_test.dart` (test-shape template for `wisp_transform_logger_test.dart`)
- `C:/claude_checkouts/mirk-poc-debug/.planning/STATE.md` (Phase 3.1 closure decisions — referenced by CONTEXT carry-forward block; not re-read during this research because CONTEXT already encodes the relevant decisions)
- `C:/claude_checkouts/mirk-poc-debug/CLAUDE.md` `# MIRL solution` block (visual-identity-preservation rule — wisps don't add fog-shader uniforms, rule still applies if v2 wisp-shader option reconsidered)
- `C:/claude_checkouts/mirk-poc-debug/.planning/config.json` (`workflow.nyquist_validation: true` — Validation Architecture section required)

### Secondary (MEDIUM confidence)
- *(None — all findings backed by in-tree source files or the locked CONTEXT)*

### Tertiary (LOW confidence — flagged for walk validation)
- The fp32-precision-at-C3'-extreme-distance hypothesis (Pitfall 5 + Open Question 1). The mechanism is plausible but the magnitude of any visible jitter is unmeasurable until WISP-05 captures it during a walk.
- Curl-noise magnitude in m/sec² basis (Open Question 3). Donor's `8.0 px/sec²` doesn't translate trivially to m/sec² because the curl input was scaled by `position * 0.005` in screen-px basis. Initial value `0.5 m/sec²` is a calibrated guess pending walk feedback.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already pinned, no new deps; donor source verified in-tree; flutter_map API verified at source level
- Architecture: HIGH — Phase 3.1 closure left `_FogPainter` in a state where the wisp insertion is mechanical; the `MapCamera.latLngToScreenPoint` projection is already the verified path used by `fog_clip_path.dart`
- Pitfalls: HIGH for Pitfalls 1–4 + 6 (mechanically derivable from existing code patterns); MEDIUM for Pitfall 5 (fp32-at-extreme-distance — plausible but not yet observed)
- Validation Architecture: HIGH — full test-file inventory derivable from existing project structure; mirroring `FogTransformLogger` test shape gives a verified template

**Research date:** 2026-05-04
**Valid until:** 2026-06-04 (30 days — stable; flutter_map 7.0.2 strict-pinned; donor unchanged; Phase 3.1 closed)
