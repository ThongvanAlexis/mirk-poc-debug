# Feature Research

**Domain:** Pure-Flutter same-Canvas fog-of-war POC (validation harness + code donor for MirkFall)
**Researched:** 2026-04-30
**Confidence:** HIGH on the categorization and dependency graph; MEDIUM on a few iOS specifics flagged inline (asset-loading mechanics, `getLastKnownPosition` behaviour, share sheet on sideloaded builds)

---

## Reading guide

This document categorises the in-scope features defined in `.planning/PROJECT.md` against three axes: must-have for the hypothesis (`Table stakes`), value beyond minimum viability (`Differentiators`), and explicitly excluded (`Anti-features`).

**The hypothesis being tested:** rendering the map, the fog-of-war shader, and the wisp particles in a single unified Flutter `Canvas` pipeline eliminates the 1–3 frame camera-tracking lag identified in BUG-014, where a Flutter `CustomPaint` overlay over a native `maplibre_gl` platform-view drifts during combined pinch-zoom+pan gestures.

A feature qualifies as `Table stakes` here if its absence would either (a) make the hypothesis question unanswerable on an iOS UAT walk, or (b) make iOS-walk bug investigation impossible from a Windows dev box. Standard product-thinking "users expect it" reasoning does not apply — the only "user" of this POC is the developer running the iOS sideload walk, and his expectations are dictated by the POC's research function.

---

## Feature Landscape

### Table Stakes (Must-Haves for the Hypothesis)

| Feature | Why Required | Complexity | Notes |
|---|---|---|---|
| **A. Permission gate (`locationWhenInUse` only)** | No location permission → no GPS fixes → no discs → empty SDF → fog covers everything → can't see fog-vs-map sync. iOS hard-requires runtime prompt with `NSLocationWhenInUseUsageDescription`. | LOW | Two screens: rationale → request → map (grant) or denied screen with `openAppSettings()` link. Re-check on `AppLifecycleState.resumed` (iOS doesn't auto-callback after settings). |
| **B. Map rendering (bundled PMTiles + chosen renderer)** | The hypothesis is *about* the map's relationship with the fog. No map = no hypothesis. | MEDIUM-HIGH | **Critical asset-loading constraint surfaced in research:** `vector_map_tiles_pmtiles` does **not** support `asset:///` URLs ([issue #44, closed "not planned"](https://github.com/josxha/flutter_map_plugins/issues/44)). The 4 MB `Fra_Melun.pmtile` must be copied from `rootBundle` to `getApplicationSupportDirectory()` on first launch, then loaded from filesystem path. See decision matrix in §B-deep-dive below. |
| **C. Pan/zoom/combined-gesture handling** | The bug under test only manifests during *combined* pinch-zoom+pan. Without working gestures, the hypothesis question literally cannot be asked. | LOW | Built into any mature Flutter map widget; not a feature the POC implements, but one it *exercises*. The roadmap should treat "combined gesture works" as a UAT acceptance criterion of the map phase. |
| **D. Blue dot (user GPS marker)** | The blue dot is the visible anchor that the developer's eye uses to verify "the fog hole sits on me, not lagging behind me" during the walk. Without it, the SDF reveal is the only visible reference, and the reveal *is* the fog hole — circular reasoning. | LOW | Render via the chosen renderer's marker layer (same-Canvas path the migration will use), not a `Stack`-overlay `CustomPaint`. Style: blue `#2b7cd6`, 7 px radius, 2 px white stroke (matches MirkFall). Updates on each `Geolocator.getPositionStream` event. |
| **E. Fog rendering in same Canvas as map** | This *is* the hypothesis. | HIGH | The 41-uniform `atmospheric_fog.frag` ports verbatim. Integration is the open architectural question — flagged for the architecture researcher. See §E-deep-dive for what FEATURES.md can pin down (inputs/outputs/failure modes) without prejudging architecture. |
| **F. Reveal discs + SDF rebuild on disc-list change** | The fog needs an SDF texture to read. No SDF = uniform shader = no reveal hole. The disc-list-driven rebuild cadence is the cadence the migration will use, so this is also code-donor-shaped. | MEDIUM | Discs in-memory (no DB — explicit POC scope). 25 m radius. SDF rebuild: debounce 100–200 ms; rebuild on UI isolate is acceptable for the POC at <100 discs (MirkFall measured `buildFromDiscs` <16 ms in this size range), but instrument the duration so the data-point lands in the migration's planning. Worker isolate is a v2 concern. |
| **G. Logger writing to file** | iOS sideload + Windows dev = no Xcode console, no `flutter logs`, no live debugger. The log file is the *only* artefact that survives a UAT walk. | LOW | `dart:developer` `log()` or `package:logging`. One file per session: `<getApplicationDocumentsDirectory()>/logs/yyyymmdd_hhmmss_logs.txt`. Level=ALL for the POC. No rotation needed (a session is a single walk). |
| **H. Email/share button for log file** | Without a way to extract the log file from the iOS sandbox, the logger is useless to the Windows dev box. `share_plus` opens iOS `UIActivityViewController` and returns a path the user can mail to himself. | LOW | `SharePlus.instance.share(ShareParams(files: [XFile(logFilename)]))`. iPad needs `sharePositionOrigin` — not relevant for the iPhone-only POC, but cheap to set anyway. **Sideload-specific risk to verify on first iOS UAT:** SideStore-signed builds occasionally have flaky entitlements for the share sheet — flag as a candidate failure mode on the UAT checklist. |
| **I. Recenter floating action button** | The dev needs to reset the camera after a long pan to compare "centred-on-blue-dot" before/after states across walks. Without it, every walk drifts the camera and visual comparison gets noisy. | LOW | Animated camera move (~400 ms ease-out) to last-known position at zoom 15. **Critical caveat (research-verified):** `Geolocator.getLastKnownPosition()` is documented as flaky on iOS — frequently returns `null` or `[0.0, 10.69]` on cold start (see [geolocator issues #285, #962, #1037](https://pub.dev/packages/geolocator/changelog)). The POC must keep its own in-memory `_lastFix` cached from the position stream, not rely on the platform call. |

### Differentiators (Strengthen Signal Quality and Code-Donor Value)

| Feature | Value Proposition | Complexity | Notes |
|---|---|---|---|
| **J. Wisp particles** | (1) Visual fidelity — wisps emit from disc perimeters, so they're a per-frame *cross-check* that the SDF and the disc list agree about where the boundary is. If the fog is drifting but the wisps aren't (or vice-versa), the bug is renderer-side, not shader-side. (2) Code-donor scope completeness — wisps are part of the parent app's product, and porting back partial code is a worse migration story than porting back the full pipeline. | MEDIUM | Port `wisp_particle_system.dart` verbatim. Compositing order: fog drawn first, then wisps on top with alpha-blend. The 5 s warm-up phase (fix from BUG-015) prevents a particle burst on app open and must be preserved. Cross-pipeline parity test: same lat/lon should produce visually identical wisp positions on the chosen renderer as on MapLibre — concretely measurable by sideloading both builds and walking the same path. |
| **K. Camera/fog frame-delta self-debug logger** | The hypothesis claim is "zero camera-fog lag." A subjective walk produces "looks tight" or "still drifts," but no number. Logging the timestamp of (a) the last camera-update event the renderer fired and (b) the timestamp of the next fog paint, then computing the delta, gives an objective falsifier. If the delta is consistently 0–1 frame (≤16 ms) over a 5-minute walk, the hypothesis holds quantitatively. If it's 30+ ms during combined gestures, the same-Canvas claim is partially false and needs investigation. | LOW (under 50 LOC) | Add a `FrameDeltaProbe` gated on `kDebugMode || kVerbose` flag. Sample at the fog paint callsite; reads the renderer's last-camera-update timestamp from a shared `Stopwatch` or the camera-event stream. **Recommendation: include it.** The instrumentation cost is trivial, the data is scientifically valuable, and "the developer's eye" is exactly the kind of evidence BUG-014's six failed iterations were already drowning in — quantitative confirmation breaks the tie if the next walk is ambiguous. |

### Anti-Features (Explicitly NOT Built)

| Feature | Why Tempting | Why Excluded for THIS POC | What to Do Instead |
|---|---|---|---|
| **Custom MirkFall basemap theme** (`#f5f1e8` / `#a6c9df` / etc. in a `Theme` object) | The POC will look like the real app, more "polished" demo | (1) Theming is renderer-style work, not pipeline work — adds complexity orthogonal to the hypothesis. (2) If the chosen renderer is later abandoned (POC fails), the theme port is wasted. (3) BUG-014 doesn't care about basemap colour. | Use the renderer's default vector style. Re-add MirkFall theme parity as a *migration* phase task, after the POC verdict. |
| **Multiple mirk styles** | "Atmospheric, charcoal, watercolour, etc. just like the parent app" | Same hypothesis test at 4× the surface area. The fog-tracks-the-map question is style-agnostic. | One style: atmospheric. With the verbatim 41-uniform port. |
| **Database / Drift / migrations** | "The migration target uses Drift, so let's match" | DB introduces async I/O on the disc-mutation path → debounce semantics change → SDF rebuild cadence changes → POC measures something other than the hypothesis. | In-memory `List<RevealDisc>`. Drift integration is a migration concern. |
| **Session management / lifecycle** | "What if the app is backgrounded mid-walk?" | The UAT walk is a single foreground session. Lifecycle handling is a migration concern. | Treat each app launch as a fresh session; logger filename uses launch timestamp. |
| **Country switching / mirk download infrastructure** | "Realistic for the parent app" | Bundled `Fra_Melun.pmtile` is the only basemap. Network egress is forbidden by GOSL (no telemetry posture would survive a download infra). | Bundle one file. Period. |
| **Burger menu / settings screen / live tuner sheet** | "Convenient for tweaking shader params during the walk" | Adds UI scope. The shader uniforms are read from constants — if the dev needs to tune, he edits source and rebuilds. CI pushes the IPA. | Hardcoded uniform defaults from `kMirkFog*` constants. Tweak via `git push`. |
| **`MapView` domain abstraction layer** | "We'll need it for the migration anyway" | The abstraction's *purpose* is to let MirkFall swap renderers. The POC's purpose is to *be* that swap. Building the abstraction inside the POC means double-implementation if the verdict is "no." | Talk to the chosen renderer directly. The abstraction lives in the migration phase, where it's informed by what we learned here. |
| **`MirkInitialRevealFade` / startup animations** | "Polish" | Visual polish, not on the hypothesis path. Risks polluting the first-paint timing window the developer is trying to evaluate. | Ship without. Re-add post-migration. |
| **`Permission.locationAlways` and notification permissions** | "Real app needs them" | (1) iOS shows the locationAlways prompt as a *follow-up* to whenInUse, doubling permission-screen complexity for zero hypothesis value. (2) Notifications aren't on the hypothesis path. | `Permission.locationWhenInUse` only. Document the deferred permissions in PROJECT.md (already done). |
| **Telemetry / analytics / crash reporting** | "Useful for monitoring real users" | Forbidden by GOSL v1.0. Forbidden by `CLAUDE.md`. Not negotiable. | Local logger + user-initiated `share_plus`. The dev mails the log to himself. |
| **Update checks / auto-update / version pings** | "Standard hygiene" | Forbidden by GOSL. Sideloaded IPAs from CI are the update mechanism. | Manually re-sideload from GitHub Actions artifact when needed. |
| **Map screenshot attachment to share** (PNG of current map state alongside log) | "Visual context for bug reports" | The log file already records camera state, disc list, and frame deltas. PNG adds tens to hundreds of KB per share with low information density. | Log file only. If a screenshot is genuinely needed mid-walk, iOS volume-up+side-button works fine and rides the same `UIActivityViewController` flow. |
| **Per-feature unit tests for shader output, particle physics, etc.** | "MirkFall has 1045 tests" | The POC's sole acceptance criterion is the iOS UAT walk. Tests for code that's about to be ported back will be written *in the parent app* during migration, against the parent app's test infrastructure. Writing them twice is the wrong shape of work. | Smoke tests for non-renderer code paths only (logger filename format, permission state machine, disc-list debounce). The shader and the particles get tested by the human walking on a real device. |

---

## Per-feature deep dives (inputs / outputs / failure modes / code-donor reusability)

The roadmap and the requirements step both consume the table below. For each in-scope feature: what it eats, what it produces, what would the developer notice on the iOS walk if it were broken, and how directly the POC code can move into MirkFall after a "yes" verdict.

### A. Permission gate

- **Inputs:** none (cold-start state) → user tap on "Grant" / "Open settings"
- **Outputs:** `PermissionStatus` (granted / denied / permanentlyDenied / restricted), navigation event to map screen or denied screen
- **iOS-walk failure modes:**
  - Map screen never appears → permission request never fired or `request()` future never resolved (typical bug: missing `NSLocationWhenInUseUsageDescription` in `Info.plist` → iOS silently refuses to show the prompt)
  - "Denied" screen appears even after tapping Allow → permission_handler returning stale status; need to re-check on `AppLifecycleState.resumed` after settings round-trip
  - Permission prompt appears, dev grants, fog appears, but blue dot never updates → permission is per-feature, not per-app: granted location ≠ active position stream; verify `Geolocator.getPositionStream()` is actually subscribed
- **Code-donor reusability:** **1:1 port.** MirkFall already has the same permission gate (with extra branches for locationAlways and notifications); the POC's gate is a strict subset. Reuse pattern verbatim.

### B. Map + bundled PMTiles loading — deep dive

The asset-loading question is more constrained than `POC-flutter-map-mirk.md` implied. Research finding ([flutter_map_plugins issue #44](https://github.com/josxha/flutter_map_plugins/issues/44)):

- `PmTilesVectorTileProvider.fromSource()` accepts **HTTP(S) URLs** and **filesystem paths**.
- `asset:///` URLs are **not supported**. Issue closed "not planned."
- The 4 MB `Fra_Melun.pmtile` therefore **must be copied from `rootBundle.load()` to a filesystem path on first launch** before the map can read it.

**Decision matrix for first-launch copy strategy:**

| Strategy | Pros | Cons | Recommended? |
|---|---|---|---|
| Copy to `getApplicationSupportDirectory()` once, gated by file-exists check | Survives app updates that don't bundle a new PMTiles version. Standard pattern. | Adds ~150 ms first-launch delay (one-time cost on a 4 MB write). | **YES (recommended).** Document the version-check pattern (asset version constant in `constants.dart`, copy when stored version mismatches). |
| Copy to `getTemporaryDirectory()` on every launch | Simpler (no version check) | Re-copies 4 MB every cold start; iOS may evict the file under storage pressure mid-session, breaking the map mid-walk | No |
| Don't copy — use a different package that supports asset URLs (e.g. `flutter_map_pmtiles` if it does) | Saves the copy step | Forces a renderer-stack change *during* feature implementation; couples the asset-loading decision to the renderer choice that's still under research | No (renderer is the architecture researcher's call) |

**Memory implications:** 4 MB MVT file mmap'd by the PMTiles library + decoded vector tiles in renderer cache. iPhone with 3+ GB RAM trivially handles this. The 4 MB *file* is not the worry — the *parsed tile cache* size depends on the chosen renderer's eviction policy and is a perf-research question for the architecture researcher.

- **Inputs:** asset bundle (build-time), `getApplicationSupportDirectory()` path (runtime), camera state (centre, zoom, bounds) from gestures
- **Outputs:** rendered vector tiles in the Canvas; `MapCamera` state stream
- **iOS-walk failure modes:**
  - Map shows blank grey grid → asset copy failed silently (catch the `IOException` and log it loudly; this is exactly the class of bug the logger exists to surface)
  - Map renders but tiles look sparse / wrong colours → renderer is rendering but with default/no theme — *expected* for the POC (theming is anti-feature)
  - Map renders centred on null-island (0,0) → initial camera config not applied; verify `MapOptions.initialCenter = LatLng(48.5397, 2.6553)` is wired
  - Map jutters during pan → tile decode is on the UI isolate and stalling — flag for the architecture researcher (worker-isolate decode is a known `vector_map_tiles` perf knob)
- **Code-donor reusability:** **Adapter needed.** MirkFall currently uses `maplibre_gl` with a hosted-tile config. The POC's bundled-asset-copy mechanism is a *new* code path that MirkFall will inherit (offline use case is on MirkFall's roadmap anyway). Port the copy logic verbatim; the map widget instantiation differs and needs adaptation.

### C. Blue dot

- **Inputs:** position stream events (`Position` with lat/lon/accuracy/timestamp)
- **Outputs:** circle marker drawn at the projected screen position, repainted as the camera moves
- **iOS-walk failure modes:**
  - Blue dot never appears → position stream not subscribed, or LocationServices disabled at OS level (separate from app-permission state)
  - Blue dot frozen at first fix → stream subscription leaked / cancelled / app got backgrounded
  - Blue dot lags behind during pan → **this is the BUG-014 symptom for the marker layer.** If the marker layer also lags, the same-Canvas hypothesis is even more strongly validated by fixing the blue dot lag for free. Worth explicit observation on the UAT checklist.
- **Code-donor reusability:** **1:1 port** of the rendering convention (colour, radius, stroke). Adapter for the actual marker API of the chosen renderer.

### D. Recenter button

**Critical research-verified caveat:** `Geolocator.getLastKnownPosition()` is unreliable on iOS — frequently returns `null` or the placeholder `[0.0, 10.69]` even when location was recently queried (see [geolocator issue #962](https://github.com/Baseflow/flutter-geolocator/issues/962), [issue #1037](https://github.com/Baseflow/flutter-geolocator/issues/1037)). **Do not rely on the platform call.**

- **Recommended semantics:** maintain an in-memory `Position? _lastFix` updated on every `getPositionStream()` event. Recenter reads `_lastFix`. If null (cold start, button tapped before first fix), keep the camera where it is and log the no-op.
- **Animation:** animate, don't jump. ~400 ms ease-out feels right for a manual recenter. The animation also gives the developer a *visual signal* that the button worked, separate from where the camera ends up. Jump-cuts are ambiguous.
- **Inputs:** `_lastFix` (in-memory), button tap event, current `MapCamera`
- **Outputs:** animated camera move to `(lastFix.lat, lastFix.lon, zoom=15)`
- **iOS-walk failure modes:**
  - Button tap does nothing → `_lastFix` is null (still no GPS fix); button should remain functional but log "no-op: no fix yet"
  - Animation snaps instead of glides → animation API misused or zoom-level math wrong (zoom 15 absolute, not delta)
  - Camera animates to wrong location → `_lastFix` was updated with stale or wrong position (verify the position-stream callback)
- **Code-donor reusability:** **Adapter.** MirkFall has the same pattern but talks to `MaplibreMapController.animateCamera`; the POC talks to the chosen renderer's equivalent. The `_lastFix` cache logic ports 1:1.

### E. Fog rendering — deep dive (with deference)

This is the heart of the POC, and the *integration mechanics* (custom layer? `CustomPaint` inside the widget tree? `FragmentProgram` directly?) are the architecture researcher's territory. From a feature-decomposition perspective, what FEATURES.md can pin down:

- **Inputs:**
  1. SDF texture (`ui.Image`, 256×256, R-channel midpoint-128) from the SDF builder
  2. Current viewport bbox in lat/lon (derived from `MapCamera`)
  3. Current viewport size in pixels (Canvas size)
  4. Elapsed seconds since app open + per-instance seed (for `uTime`)
  5. Current centre lat/lon (for `uOffset` parallax slot)
  6. The 41 uniform default values from `constants.dart` (`kMirkFog*`)
  7. Curl-scale animation phase (triangle wave 0↔4 over 40 s, from `triangleWave()` in `animation_helpers.dart`)
- **Outputs:** fog pixels covering the viewport rect, with discs cut out via clip path. Composited *into the same Canvas as the map tiles*, in the same frame, in the same paint pass — that is the hypothesis statement.
- **iOS-walk failure modes:**
  - Solid grey/blue fog covers everything (no reveal hole visible) → SDF is empty (no discs yet) OR clip path is wrong OR SDF sampler binding is wrong
  - Reveal hole visible but stationary on the screen as the dev pans → **this is the BUG-014 reproduction.** If this happens here, the same-Canvas hypothesis has *failed*, which is itself a valid POC outcome (negative result)
  - Reveal hole tracks the map but lags by 1–2 frames during combined zoom+pan → partial success, quantify with feature K's frame-delta logger
  - White ellipse artefact on the boundary during fast zoom+move → the BUG-014 secondary symptom; if it appears here, the renderer's `Canvas.clipPath` semantics during gesture frames need investigation
  - Fog renders correctly on Android (Pixel 4a) but glitches on iOS → Impeller-specific GLSL→MSL transpiler issue, which is precisely why iterations 1+2 of BUG-014 were needed; verify the slot-reorder fix (`uSdfRect` declared before `sampler uSdf`) carried over from the parent app's shader
  - Fog renders correctly on iOS but FPS is unacceptable (<20 fps during gestures) → architectural verdict per `POC-flutter-map-mirk.md`: stay on `maplibre_gl`, document the hypothesis as "right pipeline, wrong renderer"
- **Code-donor reusability:** **Shader: 1:1 port (verbatim).** `atmospheric_fog.frag` copied as-is, including the iteration 1+2 slot-reorder fix. **Integration code: adapter.** The wiring between the renderer's paint phase and `FragmentProgram` is renderer-specific; the migration replaces `MirkOverlay`'s offscreen-render path with the POC's same-Canvas path.

### F. Reveal discs + SDF rebuild

- **Inputs:** position stream events → new disc on each fix (lat, lon, 25 m); existing `List<RevealDisc>` for SDF rebuild
- **Outputs:** updated `List<RevealDisc>`; on rebuild, a fresh 256×256 `ui.Image` (R-channel SDF)
- **Rebuild cadence:** **debounce 100–200 ms** on disc-list mutations. Walking adds ~1 disc per GPS fix (typically 1 Hz), so the debounce mostly matters during synthetic test scenarios; in production walking, each fix triggers one rebuild. **UI isolate vs. worker isolate:**
  - At <100 discs (entire 30-minute walk in Melun bbox), `RevealedSdfBuilder.buildFromDiscs` was measured at <16 ms in MirkFall — fits in a frame budget on UI isolate
  - At 100–500 discs (longer walks, edge cases), the time grows roughly linearly; would benefit from a worker isolate
  - **POC recommendation: stay on UI isolate** (simpler, validates the hypothesis without conflating it with isolate-communication overhead). Add a `Stopwatch` log line per rebuild so the migration phase has data to decide on isolate offloading.
- **iOS-walk failure modes:**
  - Walking does not reveal the fog (fog stays everywhere) → discs not being added, or SDF rebuild is silently failing, or the renderer is reading a stale SDF reference
  - Rebuild visibly stutters the frame rate at every fix → SDF rebuild on UI isolate is too slow; instrument and consider isolate offload
  - Reveal hole appears on first fix but doesn't grow as the dev walks → debounce is swallowing subsequent rebuilds (off-by-one)
  - Reveal hole appears in the wrong place → projection bug (`mirk_projection.dart`), or the SDF coordinate convention disagrees with the shader's expectations (this is *exactly* the BUG-014 family of bugs; same-Canvas pipeline reduces but doesn't eliminate this risk)
- **Code-donor reusability:** **1:1 port** (`reveal_disc.dart`, `revealed_sdf_builder.dart`, `mirk_projection.dart`, `tile_cell_iteration.dart`). These are renderer-agnostic compute, no adapter needed.

### G. Wisp particles

- **Inputs:** disc list (for emission positions on disc perimeters), elapsed time (for the 5 s warm-up window from BUG-015 fix), per-particle state (position, velocity, age, alpha)
- **Outputs:** a particle sprite drawn per active wisp (≤200), composited *after* the fog in the same Canvas pass
- **Compositing order:** map tiles → fog (with disc clip-out) → wisps. Wisps draw on top of the fog with alpha-blend; their `peakAlpha=0.35` matters.
- **Cross-pipeline-parity test:** sideload the parent (MapLibre) IPA and the POC IPA on the same iPhone. Walk the same path. The wisps should appear at the same lat/lon in both builds (modulo timing). Disagreement = projection-math regression.
- **iOS-walk failure modes:**
  - No wisps on app open → 5 s warm-up not yet elapsed (expected); the dev needs to stand still for 5 s before judging
  - Wisp burst on app open → BUG-015 regression; warm-up logic broken
  - Wisps appear but in screen space (move with the camera, not with the map) → composite order or coordinate-space bug; the same-Canvas hypothesis covers wisps too — if wisps drift but fog doesn't, the bug is in the wisp particle system's coordinate handling
  - Wisps render but FPS drops during dense reveal → 200-particle cap not enforced or the per-particle paint cost is too high; instrument
- **Code-donor reusability:** **1:1 port** of `wisp_particle_system.dart`. Compositing-order glue is renderer-specific (adapter).

### H. Logger

- **Inputs:** log calls from anywhere in the app (`log()` / `Logger.root.info(...)` / etc.)
- **Outputs:** appended lines in `<getApplicationDocumentsDirectory()>/logs/yyyymmdd_hhmmss_logs.txt`
- **File rotation policy: NONE for the POC.** One file per session (= one file per cold start = one file per UAT walk). A walk is at most an hour; the file size is bounded by log volume. If a session ever produces a multi-MB log, that's itself a signal worth investigating.
- **iOS-walk failure modes:**
  - Log file empty when shared → file write path wrong (e.g. permission to write to that subdirectory, missing `Directory.create(recursive: true)` for the `logs/` sub-folder)
  - Log file present but truncated mid-line → app crashed before flush; this is *desirable* failure-mode behaviour (we want truncation, not silent loss), but verify `IOSink.flush()` happens often enough (per-line is fine for the POC)
  - Log timestamps drift from wall-clock → using `Stopwatch` for absolute timestamps (use `DateTime.now()` for filename and per-line timestamps; keep `Stopwatch` for the frame-delta probe only)
- **Code-donor reusability:** **1:1 port.** MirkFall has an equivalent logger; the POC's is a strict subset. Likely the cleanest port in the whole stack.

### I. Email/share log

- **Inputs:** log filename (string, absolute path inside iOS sandbox)
- **Outputs:** iOS share sheet (`UIActivityViewController`) with the log file as an attachment; user picks Mail / Messages / AirDrop / Files / etc.
- **iOS sideload-specific risks:**
  - SideStore-signed builds occasionally have `UIActivityViewController` entitlement glitches (community-reported, intermittent). **Add to UAT checklist:** verify share sheet opens at least once per build.
  - Mail.app may refuse attachments above a few MB — not a worry at the POC's expected log size, but worth knowing.
  - The share sheet target list depends on what apps are installed on the dev's specific iPhone; document the expected flow as "share → Mail → send to self."
- **iOS-walk failure modes:**
  - Tap "Share" → nothing happens → share sheet failed to present (sandbox/entitlement)
  - Share sheet opens but mail attachment shows zero bytes → log file path wrong or `IOSink` not flushed before share
- **Code-donor reusability:** **1:1 port** (the parent app does not yet have this; the POC contributes it back).

### J. Wisp particles — see §G above (categorised as a Differentiator, but in-scope for the POC; deep dive lives in §G to keep all wisp content together)

### K. Camera/fog frame-delta self-debug logger — recommendation

**Recommendation: include it.** Cost-benefit is unambiguous:

- **Cost:** ~50 LOC. One `Stopwatch` shared between the renderer's last-camera-event handler and the fog paint callsite. Per-frame `delta = stopwatch.elapsedMicroseconds`. Log periodically (every 60 frames) to avoid log spam, plus a max-delta-since-last-log.
- **Benefit:** turns "looks tight to my eye" into "median 4 ms, p95 12 ms, max 18 ms during combined gesture" — falsifiable, comparable across walks, dispositive when iteration 7 of BUG-014 inevitably comes back to the same set of 8 explanations.
- **Failure mode if absent:** the dev finishes the walk, says "I think it's better but I'm not sure," and the project enters another six-iteration ambiguity loop like BUG-014.
- **Code-donor reusability:** **1:1 port + applicable to MirkFall too.** Even after migration succeeds, this probe stays useful for the next renderer-pipeline regression (because there will be one).

### L. iOS Info.plist keys — completeness

For the in-scope feature set:

- **`NSLocationWhenInUseUsageDescription`** — REQUIRED. Without it, the permission prompt silently does not appear and `permission_handler` returns denied immediately. Description string in French, since the dev is in Melun: "MirkFall a besoin de votre position pour révéler la carte autour de vous."
- **`NSLocationAlwaysAndWhenInUseUsageDescription`** — NOT NEEDED for the POC (no background location). Adding it accidentally triggers a "Always" prompt option that the POC does not handle — *do not* add it.
- **`NSPhotoLibraryUsageDescription`** — NOT NEEDED. The share sheet does not need photo-library access for sharing a log file.
- **`NSPhotoLibraryAddUsageDescription`** — NOT NEEDED.
- **`NSContactsUsageDescription`** — NOT NEEDED. Mail picker doesn't need contacts entitlement at the POC layer (it inherits from Mail.app).
- **`NSCameraUsageDescription`** — NOT NEEDED.
- **`NSMicrophoneUsageDescription`** — NOT NEEDED.
- **`UIBackgroundModes`** — NOT NEEDED. Foreground-only.
- **`ITSAppUsesNonExemptEncryption`** — set to `<false/>` to silence the export-compliance prompt at archive time. Standard hygiene for sideloaded builds.
- **`UIRequiresFullScreen`** — leave default. Not relevant for iPhone-only.

**Verdict:** one location key is genuinely required, plus the encryption-export false flag as a hygiene item. Everything else stays out — both because the POC doesn't need it and because adding superfluous purpose strings is an anti-pattern (an iOS reviewer would flag them; sideload doesn't review, but the migration target eventually will).

---

## Feature Dependencies

```
Permission gate (A)
  └── grants location access
       └── Geolocator.getPositionStream  ← runtime side-effect of permission grant
            ├──> Blue dot (C)         ← render position
            ├──> _lastFix cache       ← drives Recenter button (D)
            └──> Reveal discs (F)     ← one disc per fix
                 └── SDF rebuild (debounced)
                      └── ui.Image SDF texture
                           └──> Fog rendering (E)
                                ├── needs MapCamera (B) for viewport bbox + screen size
                                ├── needs uniform defaults from constants.dart
                                └── needs animation_helpers.triangleWave for uCurlScale

Map rendering (B) ──provides──> MapCamera stream
                                 ├──> Blue dot projection (C)
                                 ├──> Fog viewport (E)
                                 └──> Wisp positioning (G)

Wisp particles (G) ──reads──> disc list (F) for emission positions
                  ──composites-over──> Fog (E)

Logger (H) ──independent──> all features (cross-cutting; everything logs into it)
Share button (I) ──reads──> log filename produced by Logger (H)
Frame-delta probe (K) ──reads──> Map (B) camera-event timestamp + Fog (E) paint timestamp
                      ──writes──> Logger (H)

PMTiles asset copy ──blocking-precondition──> Map rendering (B)
                                              (must run before first map paint)
```

### Dependency notes

- **Permission gate (A) is the topological root.** Nothing renders before permission is resolved. The map screen should not even be instantiated until `PermissionStatus.granted` — defer construction, don't render-then-block. This avoids spurious `geolocator` errors on a non-permitted launch.
- **PMTiles asset copy is a blocking precondition for B.** First-launch flow: permission granted → splash with "preparing map" → asset copy completes → map screen pushes. Subsequent launches skip the copy (file exists, version matches). This sequencing matters for the user-facing experience even though it's "just" plumbing.
- **The position stream (geolocator) is the *single source of truth* for both blue dot, recenter cache, and disc list.** All three subscribe to one `Stream<Position>`. Multiple subscriptions = multiple location-update activations = battery drain and possible event-ordering oddities. Use `.asBroadcastStream()` or a single subscription that fans out.
- **SDF rebuild (F) gates fog correctness (E), not fog *existence*.** The fog must render even with an empty SDF (early launch, before first fix); the empty case = solid fog covering everything. This is an edge case worth explicit handling (an empty SDF image, not a null check at the paint site).
- **Wisp particles (G) depend on fog (E) only for compositing order, not for data.** Wisps emit from disc perimeters (data dep on F, not E). They draw *over* the fog in the same Canvas pass.
- **Logger (H) is the only feature that should be initialised *before* permission gate (A)**, so that permission-flow errors themselves can be logged. Logger needs `getApplicationDocumentsDirectory()`, which works without any permission.
- **Frame-delta probe (K) depends on E and B both being wired up.** It's the last feature to add — when both map and fog exist, the probe wraps around them.

---

## MVP Definition (POC scoping)

The POC's "MVP" is the minimum surface that lets the developer answer the hypothesis question on an iOS UAT walk.

### Launch With (every feature in `Active` requirements is in scope — this is *not* a startup MVP exercise)

- [ ] Permission gate (A) — without it, no location, no fog signal
- [ ] Map + bundled PMTiles (B) — the substrate the hypothesis is about
- [ ] Pan/zoom/combined gestures (C, free with B) — reproducer for BUG-014
- [ ] Blue dot (D) — visual reference for fog-vs-map sync evaluation
- [ ] Fog rendering in same Canvas (E) — the hypothesis itself
- [ ] Reveal discs + SDF rebuild (F) — produces visible reveal hole the dev tracks
- [ ] Recenter button (D-button) — UAT ergonomics, not optional in practice
- [ ] Wisp particles (G) — included as Differentiator; concretely strengthens the cross-pipeline-parity signal
- [ ] Logger (H) — only feedback channel from iOS to Windows
- [ ] Email-share for logs (I) — completes the feedback channel
- [ ] Frame-delta probe (K) — falsifier; turns subjective walk into measurable result

### Add After Validation (for the migration phase, NOT the POC)

- [ ] MirkFall basemap theme port — reactivate post-verdict
- [ ] Worker-isolate SDF rebuild — once UI-isolate timing data exists from the POC
- [ ] `MapView` domain abstraction — the hypothesis-validated renderer becomes the abstraction's first concrete impl
- [ ] DB-backed disc persistence (Drift) — restored on the migration side

### Future Consideration (parent-app concerns, not POC concerns)

- [ ] Multiple mirk styles, country switching, mirk download infra — full MirkFall feature set
- [ ] Live tuner sheet, settings UI, burger menu — convenience features
- [ ] `Permission.locationAlways`, notifications, background — full MirkFall permission flow

---

## Feature Prioritization Matrix

Priority is keyed to "advances the hypothesis test" not "user value" — re-interpret accordingly.

| Feature | Hypothesis-Signal Value | Implementation Cost | POC Priority |
|---|---|---|---|
| Fog rendering in same Canvas (E) | HIGH (it *is* the hypothesis) | HIGH (architecture-blocking) | P1 |
| Reveal discs + SDF (F) | HIGH (no SDF = no fog reveal = no signal) | MEDIUM | P1 |
| Map + PMTiles (B) | HIGH (substrate) | MEDIUM (asset-copy fixup) | P1 |
| Permission gate (A) | HIGH (gate to everything) | LOW | P1 |
| Pan/zoom/combined gestures (C) | HIGH (the gesture-class that breaks in BUG-014) | LOW (built-in) | P1 |
| Blue dot (D) | HIGH (visual anchor) | LOW | P1 |
| Logger (H) | HIGH (only feedback channel) | LOW | P1 |
| Email-share (I) | HIGH (closes the feedback loop) | LOW | P1 |
| Recenter button (D-button) | MEDIUM (UAT-ergonomic, not hypothesis-critical) | LOW | P1 (cheap, ship it) |
| Frame-delta probe (K) | HIGH (turns walk into number) | LOW (~50 LOC) | P1 (recommended) |
| Wisp particles (G) | MEDIUM (cross-pipeline parity check + code-donor completeness) | MEDIUM | P2 (ship if Phase budget allows; defer if Phase 4 is bleeding) |

The matrix shows **everything in-scope is P1 or P2**, with no cuts. This is a feature of the POC's already-cut scope: the developer pre-trimmed the feature list so the POC could be entirely the critical path.

---

## Notes for the requirements step and the roadmap

- The POC's natural phase boundary is "feature in isolation works on iOS UAT walk" — the dev wants to walk after each phase. A reasonable phase decomposition (the roadmap researcher will confirm):
  1. **Bootstrap + logger + permission gate + share button.** Walk: launch the app, grant permission, hit share, send logs to self. Confirms iOS sideload pipeline + logger + share sheet.
  2. **Map + PMTiles + pan/zoom/blue-dot/recenter.** Walk: pan, zoom, combine gestures; recenter; verify blue dot follows. Confirms renderer choice.
  3. **Reveal discs + SDF + fog (no wisps yet).** Walk: walk a 200 m path, observe the reveal hole tracking. **This is the hypothesis-test phase.** Frame-delta probe lights up here.
  4. **Wisp particles.** Walk: same path, verify wisps appear at consistent positions, no burst on open, FPS still acceptable.
- **Phase 3 is the highest-risk phase.** A "hypothesis confirmed" verdict at the end of Phase 3 means the POC has already answered its question; Phase 4 is then about completeness, not validation. A "hypothesis denied" verdict at the end of Phase 3 means the project terminates (with documented findings) before Phase 4 begins.
- **The frame-delta probe should be added in Phase 3, not deferred.** It is the falsifier; it must be in place when the hypothesis is being tested.
- **Wisp particles are categorised Differentiator rather than Table Stakes** because the hypothesis can in principle be answered without them. In practice they are likely to be built — the marginal cost is manageable and the cross-parity check is valuable. The roadmap should treat them as the natural Phase 4, droppable only if Phase 3 over-runs catastrophically.

---

## Sources

- Project context — `C:\claude_checkouts\mirk-poc-debug\.planning\PROJECT.md`
- Original POC spec — `C:\claude_checkouts\GOSL-MirkFall\docs\POC-flutter-map-mirk.md`
- Bug under test — `C:\claude_checkouts\GOSL-MirkFall\docs\phase09-bug-tracking\BUG-014-sdf-rect-offset-axes.md`
- [vector_map_tiles_pmtiles — pub.dev](https://pub.dev/packages/vector_map_tiles_pmtiles) — confirms filesystem-path support, no asset:/// support
- [flutter_map_plugins issue #44 — "Support for loading pmtiles from assets" (closed not-planned)](https://github.com/josxha/flutter_map_plugins/issues/44) — confirms asset-copy workaround required
- [share_plus — pub.dev](https://pub.dev/packages/share_plus) — confirms `XFile(path)` from documents directory works on iOS
- [permission_handler — pub.dev](https://pub.dev/packages/permission_handler) — confirms `openAppSettings()` opens main Settings (not deep-linked, intended OS behaviour)
- [Apple — NSLocationWhenInUseUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationwheninuseusagedescription) — confirms required key + foreground semantics
- [geolocator — pub.dev](https://pub.dev/packages/geolocator) and issues [#962](https://github.com/Baseflow/flutter-geolocator/issues/962), [#1037](https://github.com/Baseflow/flutter-geolocator/issues/1037) — `getLastKnownPosition` flakiness on iOS; in-memory `_lastFix` cache recommended
- [flutter_map MapCamera — Dart API](https://pub.dev/documentation/flutter_map/latest/flutter_map/MapCamera-class.html) — referenced for camera-state-stream pattern; full integration architecture deferred to architecture researcher

---

*Feature research for: pure-Flutter same-Canvas fog-of-war POC*
*Researched: 2026-04-30*
