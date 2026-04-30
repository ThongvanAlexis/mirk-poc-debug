# Pitfalls Research

**Domain:** Pure-Flutter same-Canvas map + fog-of-war + particle POC, iOS-primary, Windows dev, no Mac
**Researched:** 2026-04-30
**Confidence:** HIGH for shader/transpiler & iOS sideload constraints (parent project + Flutter issue tracker direct evidence). MEDIUM for `vector_map_tiles` perf at the specific PMTiles/Melun scale (no on-device data yet — issue tracker reports are qualitative). LOW for `share_plus` / Mail attachment-size on a free-Apple-ID sideloaded build (no documented behaviour either way; flagged for a Phase 0 smoke test).

---

## Critical Pitfalls

These can produce a wrong POC answer or a multi-day stuck state. Each is specific to this stack + iOS-via-SideStore loop, not generic Flutter advice.

### Pitfall 1: Wisp particles store positions in screen pixels (BUG-014 trap, applied to wisps)

**What goes wrong:**
The MirkFall `WispParticleSystem` stores each particle's `position` as a Dart `Offset` in **screen pixels** (lines 78–134 of `wisp_particle_system.dart`). Each frame integrates `position += velocity * dt` in pixel space. In the parent project this was acceptable because the wisp painter and the fog painter were both screen-space overlays — they were equally wrong, so they were locked to each other.

In the same-Canvas pipeline, the map tiles, fog clip path, and SDF are now in **map space** (lat/lon). If wisps stay in pixel space, every camera pan or zoom desyncs them from the disc perimeter they were spawned on. A wisp spawned on the perimeter of a Melun disc will, after the user pans 100 m east, sit in the middle of the screen instead of 100 m west — the inverse of the camera motion. Same root cause as BUG-014, just with particles instead of fog.

**Why it happens:**
The wisp system is "battle-tested code to port verbatim" per `PROJECT.md`. Verbatim port = bug port. Pixel space is the *original* state-of-the-world; nothing in the file signals it.

**How to avoid:**
- Define `WispParticle.position` as `LatLng` (or world-space Mercator metres relative to a fixed pivot lat/lon for that walk) — NOT `Offset`.
- `advance(dt)` integrates velocity in **metres/sec**, not px/sec; `kMirkFogWispInitialSpeedPx` becomes `kMirkFogWispInitialSpeedMetres` (~0.05 m/s at zoom 13 to keep the pixel-equivalent visually identical at the zoom the user typically walks at — **not** the same number).
- `render(canvas, ...)` projects `position` → screen Offset via `flutter_map`'s `MapCamera.latLngToScreenPoint` once per draw call. Same projection function the SDF builder uses.
- Wisp radius `(birth → death)` stays in pixels (visual artefact, not a world quantity) so it doesn't shrink on zoom-out — confirm subjectively on the iOS walk.
- `_curlNoise(p * 0.005)` was tuned for pixel coordinates. Re-tune the scale for metre input — first walk, the wisps will look either rigid (curl too small) or chaotic (curl too large); land it before declaring perf done.

**Warning signs:**
- On Pixel 4a / iOS sim: pan the map manually with a few discs visible; wisps slide opposite to the pan direction.
- On the iOS walk: wisps appear to "fall off" the disc as the GPS drifts.
- Log line `[Wisp] position=Offset(...)` instead of `[Wisp] position=LatLng(...)` — refactor incomplete.
- Visual: a stationary wisp in screen space (impossible if it's truly world-locked).

**Phase to address:**
Phase 6 (wisps integration). Cannot port verbatim — must be the first refactor before any wisp paint. Add a unit test: spawn a wisp at a known LatLng, simulate 100 m of camera pan via a `MapCamera` mock, assert the wisp's screen Offset has moved by ~100 m in projected screen pixels.

---

### Pitfall 2: Distance computed in degrees, not metres (BUG-011's ghost — re-emerges with every renderer change)

**What goes wrong:**
The SDF's job is to encode "distance in metres from each pixel to the nearest revealed-disc boundary." If the builder accidentally computes `sqrt(dLat² + dLon²)` in degrees, the result is anisotropic in Mercator: at Melun (lat 48.5°), 1° of longitude is `cos(48.5°) ≈ 0.66` × shorter than 1° of latitude. Your "25 m circle" comes out as an oval, squashed east-west. This is exactly BUG-011.

The pure-Flutter port re-introduces the trap because it runs in `flutter_map`'s coordinate system (lat/lon), not MapLibre's (Web Mercator metres). It's *easy* to write `final dx = pixel.lon - disc.lon; final dy = pixel.lat - disc.lat; final d = sqrt(dx*dx + dy*dy);` and never notice on a small bounding box.

**Why it happens:**
- The donor `revealed_sdf_builder.dart` already does this correctly in MirkFall — but the projection it uses (`MirkProjection`) is MapLibre-specific. Re-implementing for `flutter_map` is where the bug sneaks in.
- Visually subtle at zoom 15 over a 25 m disc — the ovality is ~1.5%, well below "I notice this on the screen".
- Becomes obvious only at higher zoom out (multi-disc walks across France) or at high latitudes — neither is in the POC's daily test loop.

**How to avoid:**
- Port `kMetersPerDegreeLat` and `kEarthRadiusMeters` from the parent constants verbatim.
- Distance helper:
  ```
  double distanceMetres(LatLng a, LatLng b) {
    final dLatM = (a.latitude - b.latitude) * kMetersPerDegreeLat;
    final dLonM = (a.longitude - b.longitude) * kMetersPerDegreeLat * cos(a.latitude * pi / 180.0);
    return sqrt(dLatM * dLatM + dLonM * dLonM);
  }
  ```
- Unit test: at lat 48.5°, distance from `(48.5, 2.6)` to `(48.5, 2.6 + 1°)` ≈ 73.7 km, NOT 111.32 km.
- Visual test: render a single disc, screenshot it on the iOS walk after zoom-out to z=10. Compare aspect ratio with `image_compare` or the eye — must be circular within 1px.

**Warning signs:**
- Disc at Melun looks fine; same disc at Lille (lat 50.6°) looks slightly wider east-west, slightly taller north-south. Different aspect ratio → degree distance.
- On a stationary device pinch-zooming, the disc oval-ness is invariant under zoom (correct: a degree-error is geometrical, not a sampling artefact).
- The SDF rebuild is fast, no flicker, but the boundary doesn't look like a circle.

**Phase to address:**
Phase 4 (fog-of-war shader integration / SDF builder port). Test ON THE FIRST DISC, not on the iOS walk — this is a pre-walk gate.

---

### Pitfall 3: Impeller MSL transpiler quirks beyond BUG-014's slot-ordering fix

**What goes wrong:**
BUG-014 iteration 1 surfaced ONE Impeller transpilation issue: `vec4` near a `sampler2D` boundary getting reordered on iOS. The fix (decompose to 4 scalar floats) is in the shader. **It's a fix for one symptom of a class of bugs.** The Impeller SPIR-V → MSL transpiler has documented issues with:
- High-precision-only generated code on devices that need `mediump` (Flutter issue #115044).
- Unused-uniform compilation failures on startup (issue #155805).
- Fragment shader off-by-one pixel on `vertices` API + `textureCoordinates` (issue #151355).
- Vulkan→OpenGLES fallback rendering gradients incorrectly on Android (issue #179268).
- Adreno-specific compile failures on some devices (issue #160162) and crashes on others (issue #159834, #176211).

The shader has **41 float uniforms** + 1 sampler. That's 4 × the surface area of most shaders in the wild. The probability that *some* combination of slot ordering, precision interaction, or driver behaviour bites again — on iOS Impeller-Metal or Android Impeller-Vulkan — is non-trivial.

**Why it happens:**
The Impeller transpiler is young (post-3.10), still iterating, and Flutter doesn't have a comprehensive fragment-shader test matrix. Anything past "30 floats + 1 sampler" is in the long tail of test coverage.

**How to avoid:**
- **Pre-walk diagnostic**: keep `MIRK_FOG_DEBUG_OUTPUT_DENSITY` (line 52 of the shader, currently commented out). A stuck-grey result on iOS = noise system broken; a stuck-grey on Android only = backend-divergent.
- Add an in-app "shader sanity" screen: draws the shader at full screen with hardcoded uniforms (sin-driven `uTime`, identity SDF, full opacity, colour gradient). If it renders correctly there, the transpiler chain is sound; if it doesn't, the bug is upstream of the SDF, the disc system, the projection, etc. (Drastic localisation in 30s on the device.)
- Log every uniform value once per second at debug level; if a value the Dart side believes is `1.67` shows up on the GPU as garbage, you'll see the discrepancy in the next walk's log.
- After every Flutter version bump, rebuild the IPA and run the shader sanity screen first. The cost of one re-walk is small; the cost of debugging a regression mid-walk is high.

**Warning signs:**
- Fog renders correctly on Android, blank or distorted on iOS (or vice versa).
- A specific uniform's effect (e.g. `uHueStrength`) doesn't visually change anything when toggled — the slot is being read as a different uniform.
- Boundary appears correctly at one zoom level but inverts (revealed/unrevealed swap) at another → SDF rect axes swapped.
- iOS log line at boot: `[VERBOSE-2:shell.cc(...)] Failed to compile shader: ...`. Never a warning, always a fail.
- White ellipse artefact on fast zoom (the BUG-014 white-ellipse symptom recurring).

**Phase to address:**
Phase 4 (shader integration). Phase 0 must establish the shader sanity screen as the first build target after permission gate — debug-time investment, not perf overhead.

---

### Pitfall 4: PMTiles asset-load synchronous I/O on first paint

**What goes wrong:**
`vector_map_tiles_pmtiles` does **not** support loading from Flutter assets directly (per josxha/flutter_map_plugins issue #44). The standard pattern is to copy the asset file from the Flutter bundle to `getApplicationDocumentsDirectory()` on first launch, then point the PMTiles provider at the copy. If this copy is awaited in the wrong place — e.g. inside the map widget's `build()`, or unguarded with a `FutureBuilder` that thrashes — the app paints a blank map while reading a 4 MB PMTiles file off iOS storage.

On iOS sideload, the documents directory path is sandboxed per install, so the file gets re-copied on every fresh install (every 7 days minimum on a free Apple ID, or every SideStore re-sign that bumps the bundle ID). 4 MB asset copy is ~100 ms on iPhone flash; not a problem if hidden behind a splash. A problem if the user sees a blank map on launch and starts panning before the copy completes.

**Why it happens:**
Naive port from a tutorial that loads PMTiles from `https://...` (network, async, FutureBuilder works fine). The asset-bundled-PMTiles path adds a copy step that doesn't show up in any tutorial.

**How to avoid:**
- Copy PMTiles to documents dir during the permission-grant phase, NOT during map-screen build.
- Use `path_provider`'s `getApplicationSupportDirectory()` (not `Documents`) — the Documents dir is iCloud-backed by default on iOS; Support is not, and we don't want a 4 MB binary blob in the user's iCloud.
- Idempotency: on every launch, check if the file exists at the expected path with the expected size; only re-copy if missing or size-mismatched.
- Log the elapsed copy time at INFO so the iOS walk log proves it's <500 ms.

**Warning signs:**
- App launches, map screen shows blank for 1–2 s before tiles paint.
- Blank-map period is variable (sometimes 100 ms, sometimes 2 s) → blocking I/O on a thread that has other work.
- Log line `Copied Fra_Melun.pmtile (4193280 bytes) in 234 ms` is visible only on FIRST launch after install — every subsequent launch should NOT log this. If it does, the existence-check is wrong.

**Phase to address:**
Phase 3 (map screen with PMTiles loaded). Establish the copy step in Phase 2 (permission gate) so by the time the map screen mounts, the file is already in place.

---

### Pitfall 5: `vector_map_tiles` label collision avoidance churn during pan

**What goes wrong:**
`vector_map_tiles` includes label collision avoidance — when text labels would overlap, the renderer drops some. This computation is in the UI isolate during scroll. On low-end devices and at busy zoom levels (zoom 13–15 in a city like Melun has many street labels), labels visibly pop in and out during pan. More than cosmetic: the recomputation is the main pan-time cost. (Multiple GitHub issues, #10 and #120.)

In the parent project this was abstracted by `maplibre_gl` (native collision). Migrating to `vector_map_tiles` exposes the developer to it directly. A 30 fps pan with no fog could become 18 fps when fog + 200 wisps + label collision all share the UI isolate.

**Why it happens:**
- `vector_map_tiles` does most of its work on the UI isolate (perf issue #120).
- The shader paint cost is constant; the label-collision cost is data-dependent — busy areas of Melun hit hardest, sparse areas don't, and the iOS walk could pass through both.

**How to avoid:**
- Phase 3 baseline: measure FPS during pan **with the bundled style and no fog** at zoom 13–15 in central Melun. If <40 fps without fog, vector_map_tiles is the bottleneck — fog can't possibly hit 30 fps on top.
- Disable labels in the theme as a perf knob: if no-label pans hit 50 fps and labelled pans hit 22 fps, the pitfall has a measurable cost. Consider shipping the POC with thinned-out labels (only place labels at z=14+, no road shields, no road labels).
- Check `vector_map_tiles` 9.x or 10.x upgrade for the `flutter_gpu` rendering backend — version 10 is in beta, depends on the Flutter dev channel; NOT acceptable for a sideload-IPA project where reproducibility matters. Stay on 8.x and accept the perf ceiling.
- Render tiles to an offscreen image (the version 3.3+ behaviour) — confirm this is on for whatever version is pinned.

**Warning signs:**
- On the iOS walk, pan over the centre of Melun and see labels stutter (pop) every ~250 ms — that's the collision recompute throttled.
- DevTools shows the UI thread at >80% during pan, raster thread idle. The bottleneck is Dart, not GPU.
- Log line for `paint took 28 ms` (≥ 60 fps frame budget of 16 ms) when the only visible thing is map tiles. Anything `paint` exceeds 16 ms during pan is a pan-time fps killer.

**Phase to address:**
Phase 3 (map screen). Establish a no-fog FPS baseline as the perf gate before adding fog. If the renderer is already <40 fps without fog, the hypothesis is fundamentally compromised — the renderer is the issue, not the fog.

---

### Pitfall 6: Confirmation bias — declaring success on the simulator or on a stationary device

**What goes wrong:**
The hypothesis under test is "the fog stays locked to the map during pan/zoom/combined gestures on iOS while the user walks." A successful **simulator** test or a successful **stationary-finger-drag** test on a real device proves something weaker: the fog locks to *synthetic* gestures. It doesn't prove the fog locks to:
- GPS-driven map-recentre (which can land off-screen, zoomed too far, between fixes).
- Real walking (sub-half-second updates, slight oscillation as accuracy improves).
- Combined: the user is walking while pinch-zooming the map, then opens the recenter button.

BUG-014 was only visible after a real walk: stationary tests on iOS had passed iterations 1+2.

**Why it happens:**
- iOS simulator has no GPS — the developer must inject fake locations from Xcode (which is unavailable here). On Windows, simulators aren't an option for iOS at all. So "iOS simulator pass" is automatically excluded — but Pixel 4a Android emulator on Windows is available, and could mislead.
- Stationary-device tests are easy and fast; walk tests cost an hour each.
- "It looks fine" bias: the developer wants the POC to succeed.

**How to avoid:**
- Define the falsification criterion **before** Phase 4 (fog rendering). Concrete:
  > "On a 5-minute walk through Melun centre at lunchtime, hand-pan the map ≥10 times, pinch-zoom ≥10 times, and tap the recenter button ≥3 times. The fog must stay visually locked to its disc perimeter, no slide+snap, no white-ellipse artefact, no >1 frame visible offset. FPS during this walk must average ≥30 measured by an in-app FPS counter rendered as text in the corner."
- Build the in-app FPS counter in Phase 0 (logger), not Phase 4. It's free; just compute `1.0 / dt` in `WidgetsBinding.instance.addPersistentFrameCallback` and render with a `StatefulWidget` that buffers 1 s averages.
- Build a "walk replay" simulator: record GPS fixes as `(timestamp, lat, lon, accuracy)` tuples to a file during a real walk, then on later iterations replay them in dev (Pixel 4a) at 1× and 5× speed. Lets the developer iterate without re-walking each time.
- A **stationary fast-finger-drag** stress test on Android shows shader perf, but is NOT a proxy for the gesture-locking hypothesis. Don't accept it as proof.

**Warning signs:**
- "Worked on simulator" or "worked on the desk" without "worked on a 5-minute walk" → the answer is not yet known.
- iOS walk feedback is "felt fine" not "FPS counter showed 32 minimum, no visible offset, recenter snapped clean" → too qualitative.
- Re-walking the same path produces different results → the system is non-deterministic in a way the test doesn't capture.

**Phase to address:**
Phase 0 (test infrastructure). The FPS counter + walk-replay are critical-path tools, NOT polish. Roadmap must put them before Phase 4.

---

### Pitfall 7: The POC has no FPS baseline from the parent project

**What goes wrong:**
The success criterion is "30+ fps on iOS during pan with fog active." But the parent project's `maplibre_gl` + Flutter overlay does not currently report its FPS — it has the BUG-014 *displacement* problem, not necessarily an FPS problem. The POC could land at 32 fps and conclude "victory!", when in fact the parent ran at 58 fps with bad lock and the POC runs at 32 fps with good lock. Net: did we *win* by ~26 fps less for slightly better locking? Or did we win in absolute terms?

The decision to migrate MirkFall to flutter_map (per the POC spec end) hinges on a comparison the POC does not, by construction, measure.

**Why it happens:**
The POC is single-codebase. There's no `maplibre_gl` to compare against in the same repo. The parent project is in a different folder, not instrumented with the same FPS counter, on the same device, on the same walk.

**How to avoid:**
- Before declaring the POC done, port the FPS counter into the parent project (`GOSL-MirkFall`) for one walk. Compare absolute pan FPS on the same iPhone, same ~5-min route. Document the delta.
- Phrase the POC's go/no-go as: "Same-Canvas locks correctly AND its pan-FPS is ≥0.7× the parent's pan-FPS" — i.e. you're allowed to lose up to 30% perf for the lock-correctness win.
- If the parent's pan-FPS is, say, 55 and the POC's is 32, that's a 42% perf hit — the POC technically passes its 30 fps gate but fails the comparative gate. A deeper renderer evaluation (custom MVT-on-Canvas, `flutter_gpu` when stable) is then warranted.

**Warning signs:**
- The POC's success report does not name the parent's pan-FPS for comparison.
- The 30-fps target is hit but the iOS walk subjectively feels "more sluggish" than the parent project — perf delta is real, even if both are above the bar.

**Phase to address:**
Phase 0 (FPS counter port back to the parent project for one baseline walk). Phase final (decision phase, after Phase 6) where the comparison is documented.

---

### Pitfall 8: Telemetry creep through transitive dependencies (vector_map_tiles → vector_tile_renderer → ...)

**What goes wrong:**
GOSL v1.0 forbids any automatic network egress from any dependency. `flutter_map`, `vector_map_tiles`, `vector_map_tiles_pmtiles` are all clean today, but each pulls 5–15 transitive dependencies (Protobuf parsing, math, image, font handling, etc.). A minor version bump in any of those — `protobuf 4.0.x → 4.1.0` — could in principle introduce an analytics SDK as an opt-out dependency. It happens (`firebase_analytics_web` showed up as an indirect dep of unrelated packages in the past; `firebase_messaging` once shipped a phone-home heartbeat).

The audit checklist in `CLAUDE.md` requires transitive auditing on first add. It does **not** require re-auditing on every `flutter pub upgrade`. Months later, a fresh audit of `pubspec.lock` could reveal a new transitive `xyz_analytics_proto: 0.1.0` that nobody added by name.

**Why it happens:**
Flutter doesn't have a built-in license/telemetry CI gate. `flutter pub upgrade` just resolves and writes lock — no diff is surfaced.

**How to avoid:**
- Pin all dependencies strictly (already mandated by `CLAUDE.md`).
- Run `dart_license_checker --show-transitive-dependencies` (or `very_good_cli` license check) **in CI** on every PR. Fail the build on any non-allowlisted license. Must list the allow list explicitly: MIT, BSD-2/3-clause, Apache-2.0, Unlicense, CC0, ISC, zlib.
- Keep `DEPENDENCIES.md` machine-checkable: name + version + license + audit date. CI parses it and asserts every package in `pubspec.lock` has a row.
- On every Flutter version bump or `pub upgrade`, re-audit. Not just first-add.
- Grep for known telemetry package patterns: `analytics`, `crashlytics`, `firebase_*` (except `firebase_messaging` if explicitly allowed — it's not, here), `sentry`, `bugsnag`, `appsflyer`, `adjust`, `branch`, `kochava`, `mixpanel`, `amplitude`, `segment`, `optimizely`, `instabug`, `newrelic`, `datadog`, `hotjar`, `fullstory`, `logrocket`. Block on hit.

**Warning signs:**
- `flutter pub deps --json` count rises after a non-functional change.
- A pinned package's `pubspec.yaml` shows a new dependency in its own changelog you didn't expect.
- IPA size goes up by >1 MB after a small refactor — unexpected dep added.
- Network traffic on the iPhone during a walk (check with `Charles Proxy` on the dev machine + WireGuard from the phone, *if the developer wants to do this once*).

**Phase to address:**
Phase 0 (CI). License-check in CI is on Day 1. Re-audit on every `pub upgrade` is a documented dev workflow rule, written into `CLAUDE.md`.

---

### Pitfall 9: SideStore 7-day re-sign + 3-app limit confounds the iOS test loop

**What goes wrong:**
Free Apple ID + SideStore: 3 apps installable simultaneously, signed for 7 days, must be wirelessly re-signed within that window. SideStore handles re-sign in the background via WireGuard, BUT:
- The dev's iPhone must be on the same network (or the WireGuard VPN active) for re-sign.
- A phone left unattended for >7 days = app stops launching until re-signed.
- 10-app-IDs-per-week limit (per #68) — the developer is limited to ~10 distinct IPA installs per week. If the POC iterates rapidly with many CI builds, the developer might hit the weekly cap and be unable to install the next IPA.

The 3-app limit is the harder one for this project: the developer might be running parent-MirkFall + POC + another sideloaded app, hitting the cap.

**Why it happens:**
SideStore doesn't communicate the cap clearly until you hit it ("SideStore can only install 3 apps including itself" surfaces at install time, not advance warning).

**How to avoid:**
- Before Phase 0, document the developer's current SideStore install count. If at 2/3, plan to remove one before starting POC walks.
- Use `--Disable App Limit` toggle in SideStore Settings to bypass the 3-app limit. Documented per the techybuff source. Reapply the bypass every 3 install/updates.
- Bundle ID hygiene: use `com.thongvan.mirkpoc` as the **stable** bundle ID — every CI rebuild uses the same ID, so "10 different App IDs per week" doesn't trigger from re-installs of the same bundle.
- WireGuard / pairing-file setup must be documented in the POC repo's README so re-installs don't lose 30 minutes to "why won't SideStore connect."

**Warning signs:**
- SideStore installation fails with "exceeded app ID limit." Stop, free up an ID.
- App suddenly stops launching ("Untrusted Developer" / "Could not verify"). 7-day expiry. Re-sign manually.
- Log file hasn't been updated in 8+ days → app has been killed by re-sign.

**Phase to address:**
Phase 0 (CI + sideload pipeline). Document the SideStore workflow as part of the dev setup; not a bug discovery on day 5.

---

### Pitfall 10: Combined zoom+pan reveals incorrect coordinate transforms (BUG-014 root re-emergence)

**What goes wrong:**
The hypothesis is "same-Canvas eliminates the lag." But same-Canvas only eliminates the **architectural** lag (separate pipelines). Within the same-Canvas pipeline, the developer still has to:
1. Compute the SDF rect mapping screen-normalised UVs to SDF UVs (i.e. "where on screen is this disc bbox").
2. Compute the clip path (regions to NOT fog).
3. Pass uniforms to the shader.

Each of these requires the current `MapCamera` state — `zoom`, `center`, `rotation`. If the camera's "current" state is sampled at the wrong moment in the frame, or if `flutter_map`'s `MapEvent` is processed AFTER the `paint()` call instead of before (re-entrant frame), all the BUG-014 symptoms reappear: white ellipse, slide+snap, displacement during combined zoom+pan.

This is subtle. `flutter_map` paints children after the camera transform, but custom layers might paint at a different point in the frame than the tile layer. The shader uniforms come from one snapshot; the tile layer transforms from another.

**Why it happens:**
- `flutter_map` 8.x changed how `MapCamera` is exposed — `MapEvent.camera` is the post-event camera, but `MapCamera.of(context)` inside a child widget is the **current** camera. If the disc layer reads via `MapCamera.of(context)` and the tile layer reads via its own internal hook, they can disagree by one frame during fast gestures.
- Mid-frame camera updates: `MobileLayerTransformer` wraps children in a `Transform` widget that uses the camera's matrix. If the SDF was built with a *different* camera snapshot than the `Transform`, the SDF samples in shifted screen space.

**How to avoid:**
- All three paint-time consumers of camera state (SDF rect computation, clip path, shader uniforms) MUST receive the **same** `MapCamera` instance, captured ONCE at the top of the layer's `build` method.
- Avoid `MapCamera.of(context)` deep in a callback — too easy to read at the wrong moment.
- During Phase 4, write a unit test that asserts the SDF rect, clip path, and uniforms all derive from the same input camera. (Inject a mock camera, snapshot, modify mid-test, assert downstream code doesn't see the modified value.)
- On the iOS walk, do a **deliberate combined gesture**: pinch-zoom while panning while holding the recenter button. If the fog displaces during this, the camera-snapshot discipline is broken.

**Warning signs:**
- Pure pan: fog locks. Pure zoom: fog locks. Combined zoom+pan: fog displaces. **Same symptom as BUG-014.** The root cause moved from "platform-channel lag" to "Dart-side multiple-camera-snapshot inconsistency", but the user-visible bug is identical.
- White-ellipse artefact on fast pinch-zoom recurs.
- The `paint()` log shows a different camera zoom from what the shader uniforms log shows in the same frame.

**Phase to address:**
Phase 4 (fog layer). Architect the layer so camera snapshot is grabbed exactly once per frame. Write the displacement test BEFORE the walk — the iOS UAT walk is the *acceptance* test, not the *discovery* test.

---

## Moderate Pitfalls

### Pitfall 11: `share_plus` on iOS sideloaded build — Mail attachment behaviour unverified

**What goes wrong:**
`share_plus` uses `UIActivityViewController` on iOS, which works on sideloaded apps in principle (no special entitlement required). HOWEVER:
- iOS Mail's attachment size limit (mostly imposed by the mail provider, not iOS itself) is typically 20–25 MB. A 5-minute walk at debug verbosity can produce 50–100 MB of logs.
- iCloud Mail's "Mail Drop" can ship larger files (up to 5 GB) but requires the user to be signed into iCloud Mail in the share sheet — sideloaded sandbox may or may not honour this.
- Some iOS share extensions silently truncate large file attachments without an error code surfaced to Flutter.
- Non-ASCII characters in log file content (French place names, accented user input) — file encoding must be UTF-8 with BOM or specific iOS Mail behaviour might mangle.

**How to avoid:**
- Cap log file size at 10 MB per session by rotating: `yyyymmdd_hhmmss_logs.txt` → `yyyymmdd_hhmmss_logs.1.txt` after 10 MB. Share zips the latest file or all rotated files.
- gzip logs before sharing — 10 MB ASCII log compresses to ~600 KB. Unblocks Mail attachment limits AND most messaging apps.
- Smoke test in Phase 1: write a 50 MB log file with a known content marker at byte 47 MB ("CHECK_47MB"). Share via Mail. On the receiver, verify the marker is present. If absent, attachment was truncated.
- Force UTF-8 encoding everywhere: `sink.write(line, encoding: utf8)` not `latin1`.

**Warning signs:**
- Shared log file from iOS Mail has byte size mismatching the file system (verify with `ls -la` after AirDrop or Mail).
- Accented characters arrive as `?` or as garbled UTF-16 surrogate pairs — encoding is wrong.
- Mail "the attachment is too large" error → the user can't share, lost the walk.

**Phase to address:**
Phase 1 (logger + share). Smoke test before Phase 2.

---

### Pitfall 12: SDF rebuild cadence creates a stutter / staleness tradeoff

**What goes wrong:**
SDF rebuild is CPU work — 256×256 distance computation per disc. For ≤10 discs it's <16 ms, for 100 discs it's >50 ms. Two failure modes:
- Rebuild on every `discList.add(...)` GPS fix → ~1/sec, fine for low disc count, slow if discs accumulate.
- Debounced rebuild (e.g. 200 ms) → during a walk, a disc may be added but not visible for 200 ms after the GPS fix, then "pops in." User-visible.

**How to avoid:**
- Phase 0 budget: build & profile `RevealedSdfBuilder.buildFromDiscs` with 10/50/100 discs on a Pixel 4a release-mode build. If 100 discs is >16 ms, the rebuild must move off the UI isolate (use `compute()` or a long-lived isolate).
- Strategy: rebuild on every disc-list change, but on a worker isolate with a debounce of (say) 100 ms to coalesce rapid-fire updates. Render the most-recent-completed SDF; never block the UI on the rebuild.
- Cache discriminator: a hash of the disc list. If hash unchanged, don't enqueue a rebuild.
- The SDF can stay valid for 100 ms — for fog visualisation, 100 ms of "your latest fix isn't yet visible" is invisible to the human eye. Don't over-engineer for sub-100 ms latency.

**Warning signs:**
- iOS walk: GPS fixes arrive (logged) but new revealed area takes >300 ms to appear.
- DevTools: UI isolate sticks at >50% during sustained walking.

**Phase to address:**
Phase 4 (SDF + fog). Build the worker-isolate path from the start; not a "we'll add this later if perf is bad" — by then it's costly to retrofit.

---

### Pitfall 13: Wisp particle warm-up (5 s) runs before first GPS fix

**What goes wrong:**
The MirkFall wisp system has a "5 s warm-up" — particles spawn at app open to populate the visible field. But on a fresh app launch:
- GPS fix takes 5–30 s on iOS (cold start).
- During warm-up, no discs exist yet. Wisps either (a) don't spawn (no perimeter to spawn on) or (b) spawn at the user's "default" location (a non-existent disc). If `(b)`, fake particles appear at e.g. (0, 0) lat/lon — visible glitch.

**How to avoid:**
- Gate the warm-up on "first GPS fix received." Until then, no wisps render.
- If the developer wants the visual richness during launch, render wisps as a screen-space cosmetic loop *outside* the disc system (no SDF interaction, just decorative). But cleaner to skip until first fix.

**Warning signs:**
- App opens, GPS not yet fixed, wisps visible at strange coordinates (or not visible — depending on impl).
- Log shows wisp spawn times before GPS fix log.

**Phase to address:**
Phase 6 (wisp integration). Trivial fix; just write the gate.

---

### Pitfall 14: Frame pacing: Pixel 4a fixed 60 Hz vs. iPhone variable / ProMotion

**What goes wrong:**
- Pixel 4a: 60 Hz fixed → frame budget 16.67 ms.
- iPhone (no ProMotion / pre-13-Pro): 60 Hz fixed → 16.67 ms.
- iPhone (ProMotion / 13-Pro+ / 14-Pro+): 120 Hz → 8.33 ms; iOS may also drop to 60 Hz when battery saver active.

A POC built and tested at 60 fps target on a 60 Hz Pixel 4a will hit 60 fps fine. On a ProMotion iPhone, the OS may choose 90 Hz or 120 Hz, making the same workload underperform — 30-fps target met at 60 Hz is now violated as iOS demands 90 Hz. Conversely, a non-ProMotion iPhone may pace down to 60 Hz, masking a real perf cliff that a ProMotion device exposes.

**How to avoid:**
- The dev's iPhone model — name it explicitly in PROJECT.md. If ProMotion, FPS counter must distinguish "30+ fps at the device's current pace mode."
- Don't hardcode 16 ms anywhere. Use `WidgetsBinding.instance.window.platformDispatcher.views.first.refreshRate` or compute dt per-frame.
- FPS counter reports both "frames/sec" AND "device refresh rate" — the comparison "are we hitting refresh rate?" is what matters.

**Warning signs:**
- iPhone walk: fps counter reads 32 fps, feels jerky → the device is at 90 Hz expecting 90 fps, the app is at 32. Visible.
- iPhone walk on a 60 Hz device: 32 fps, feels okay → device is at 60 Hz; the same app on ProMotion would feel worse.

**Phase to address:**
Phase 0 (FPS counter). Bake refresh-rate awareness in from start.

---

### Pitfall 15: BuildContext-after-await violations in async camera/GPS callbacks

**What goes wrong:**
Per `CLAUDE.md`: "After tout `await` dans un widget, vérifier `if (!context.mounted) return;`." The POC has many async paths:
- Permission request callback awaits, then navigates to map screen.
- GPS stream listener awaits SDF rebuild, then calls `setState` on the map widget.
- Recenter button awaits map camera animation, then logs.

Missing `mounted` checks: app crash on rapid permission-grant → app-background; GPS callback while in background; navigation away mid-animation.

**Why it happens:**
- The codebase will be ~20 files, ~15 `await` calls in widget code. Easy to forget one.
- Lint rules don't catch all cases.

**How to avoid:**
- `flutter_lints` + `use_build_context_synchronously` rule (enforced by Flutter analyser); add to `analysis_options.yaml`.
- Prefer pulling `BuildContext`-dependent calls UP into pre-await; do work async, then a single `setState` post-await with `if (!mounted) return;`.
- Code review every PR for this pattern.

**Warning signs:**
- iOS walk: app crashes on backgrounding or fast permission-grant flow.
- Sentry-style stack trace logged: "Looking up a deactivated widget's ancestor is unsafe."

**Phase to address:**
Phase 1 onward (every phase touching widgets). Add the lint to `analysis_options.yaml` in Phase 0.

---

### Pitfall 16: Geolocator iOS background suspend kills the GPS stream

**What goes wrong:**
Per `geolocator` issue tracker, `geolocator_apple` >2.2.2 has unreliable background behaviour. The POC asks for `locationWhenInUse` only — but iOS may still suspend the app aggressively when backgrounded. On the walk, the user briefly switches to Photos / Maps / Mail, returns to the POC: GPS stream is silently dead, no new fixes, no error. Map appears stuck.

The 5-min walk test could include unintentional backgrounding (notification glance) that breaks the test mid-flight.

**How to avoid:**
- `WidgetsBindingObserver.didChangeAppLifecycleState`: on `resumed`, re-subscribe to the GPS stream and log it (`[Geolocator] Re-subscribed to position stream after resume`).
- Idempotency: re-subscribe must cancel any existing subscription first.
- Warn the user: the iOS walk instructions say "do not background the app for >30 s during the walk."

**Warning signs:**
- Walk test: midway, the user notes the dot stops moving but the timestamp on logs still updates (only frame timer, no new `Position` events).
- After backgrounding, log shows no `[Geolocator] Position fix received` for >5 s.

**Phase to address:**
Phase 5 (GPS integration). Lifecycle observer is in scope.

---

### Pitfall 17: Shader sampler tex-coord conventions (Y flip)

**What goes wrong:**
The atmospheric_fog.frag has an `IMPELLER_TARGET_OPENGLES` Y-flip guard at line 252:
```
#ifdef IMPELLER_TARGET_OPENGLES
    fragUv.y = 1.0 - fragUv.y;
#endif
```
This is for OpenGLES backend on Android <29. iOS Metal and Android Vulkan don't need it. The same shader running same-Canvas in `flutter_map`'s pipeline:
- iOS Metal: works (BUG-014 confirms shader runs OK in MapLibre on iOS Metal).
- Android Vulkan/Impeller: should work.
- Android OpenGLES fallback (older devices, or Vulkan-blacklisted Adreno like 610): Y-flipped.

If the shader is rendered onto an offscreen image (e.g. a `Canvas.drawRect` with the shader paint), Flutter's image coordinate system is Y-down (top-left origin). Mismatched Y-flip = vertically flipped fog.

**How to avoid:**
- Test on an OpenGLES-fallback Android device (Pixel 4a is Vulkan-OK so won't catch this; older device required to repro). Or simulate by forcing OpenGLES via `--enable-impeller=false` build.
- Add a unit test: render the shader into a `ui.Image` with a known SDF (single revealed disc at top-left), verify the disc appears at top-left in the output image.
- Keep the existing `IMPELLER_TARGET_OPENGLES` guard; verify with a SkSL diagnostic that the macro is defined in the OpenGLES build.

**Warning signs:**
- Fog renders correctly on iOS, vertically inverted on a specific Android device.
- The disc-revealed area appears at the bottom of the screen when the GPS dot is at the top.

**Phase to address:**
Phase 4 (shader integration). Document as a known Android-OpenGLES caveat if the dev tests on an older Android device.

---

## Minor Pitfalls

### Pitfall 18: PMTiles tile cache eviction on fast zooms causing fetch storms

**What goes wrong:**
Even though PMTiles is a local 4 MB file, the LRU tile cache in `flutter_map` evicts inactive tiles. Fast zoom-out → zoom-in (z=15 → 8 → 15) blows the cache, every visible tile must be re-decoded from PMTiles. PMTiles read = sync I/O = UI stutter.

**How to avoid:**
- Tune `TileLayer.maxNativeZoom` and `keepBuffer` to keep more tiles cached.
- For the POC's bounded use (Melun area only), pre-decode all tiles at zoom 8–15 into the cache at app startup. 4 MB file, ~hundreds of tiles, total decode <2 s. Hidden behind splash.

**Warning signs:**
- iOS walk: tap-to-zoom from z=14 to z=10 → blank tiles for 100 ms → tiles paint.

**Phase to address:**
Phase 3 (map screen).

---

### Pitfall 19: Time zone / clock drift in log filenames during a walk crossing midnight

**What goes wrong:**
Log filename `yyyymmdd_hhmmss_logs.txt` uses local time. A walk that starts at 23:55 and ends at 00:10 produces files in two different days. Sharing "the latest log" picks the second one; the GPS fix at 23:58 is in the first, lost.

**How to avoid:**
- Sharing UI: present a list of recent log files, not "the latest." Or: append to one file per walk (rotate by size, not by midnight).
- Use UTC in filenames: `yyyymmddThhmmssZ_logs.txt`.

**Warning signs:**
- "I shared the log but the bug isn't in there" → midnight cross.

**Phase to address:**
Phase 1 (logger).

---

### Pitfall 20: Flutter version interactions for shaders

**What goes wrong:**
Custom shader behaviour can change between Flutter 3.16 (new uniform layout), 3.19 (Impeller stabilised on iOS), 3.22 (Impeller on Android default), 3.27+ (precision changes). A POC built on 3.27 then upgraded to 3.32 might silently change shader behaviour.

**How to avoid:**
- Pin Flutter version in `.fvm/.fvmrc` and `pubspec.yaml`'s `environment:` block. Document the chosen version in PROJECT.md.
- Don't run `flutter upgrade` until the POC concludes. If the developer needs a Flutter feature, decide consciously and re-walk after.

**Warning signs:**
- After Flutter upgrade, fog looks different (colour shift, banding, distortion) without any code change.

**Phase to address:**
Phase 0 (toolchain).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip `compute()` for SDF rebuild; do it on UI isolate | One fewer file, no boilerplate | UI thread janks at >10 discs; fundamentally not portable to MirkFall (1000s of discs) | Never — SDF builder is donor code, must land in correct place from start |
| Hard-code Pixel 4a as "Android baseline"; don't test other Adreno devices | Faster iteration, one device | Adreno-class GPU bugs hit users; Pixel 4a (Adreno 618 / Vulkan-OK) is too "good" to surface OpenGLES-fallback issues | Acceptable in POC IF the migration plan documents "verify on 1 OpenGLES Android device pre-merge" |
| Bundle PMTiles in Documents dir not Support dir | Simpler path code | iCloud backup of 4 MB binary blob; clutters user's iCloud | Never — Support dir is the right answer, costs one line |
| Skip CI license-check, audit manually on every dep add | Faster setup | One missed transitive change = GOSL violation; bug-tracking that down is hard | Never — CI license-check is one workflow file, costs nothing recurring |
| Test only on the dev's iPhone model | Faster iteration | ProMotion vs. non-ProMotion behaviour divergence missed; battery-saver-induced rate drops missed | Acceptable IF the POC's success report names the device explicitly and flags this as a remaining unknown |
| Accept "30 fps subjective fine on a stationary device" | Saves walks | The hypothesis isn't actually tested; multi-day rework when the walk fails | Never — subjective stationary success ≠ POC success |
| Don't measure parent project's pan-FPS before declaring "POC wins" | One less re-walk | Migration decision is made on incomplete evidence; could move to lower-perf renderer | Never — single walk on parent w/ FPS counter is mandatory |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `vector_map_tiles_pmtiles` + asset PMTiles | Pass `asset:///assets/maps/Fra_Melun.pmtile` as URI directly | Copy to `getApplicationSupportDirectory()` on first launch; pass `file://...` URI |
| `flutter_map` `MapCamera` reads from layers | `MapCamera.of(context)` deep in callbacks | Capture once at top of layer's `build`; pass camera explicitly |
| `geolocator` stream lifecycle | Subscribe in `initState`, never re-subscribe on resume | `WidgetsBindingObserver.didChangeAppLifecycleState`: cancel + re-subscribe on `resumed` |
| `share_plus` Mail with large file | Share raw 50 MB log file | Cap log at 10 MB, gzip, share |
| `permission_handler` on iOS | Just call `Permission.locationWhenInUse.request()` | Add `NSLocationWhenInUseUsageDescription` to `Info.plist` (POC will need French text per French walk) |
| Fragment shader uniform layout | Edit `.frag` without re-running build | Hot reload in debug works for shaders per Flutter docs; release builds need `flutter run --release` re-deploy |
| iOS sideload + shader compile fail | App launches, blank screen, no error | Shader sanity screen first; ensures the shader chain works before any other work |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `vector_map_tiles` label collision on UI isolate | Pan-fps drops in dense urban areas (Melun centre) but is fine in suburb | Profile pan-fps with labels OFF first; thin label density via theme | Visible >50 labels in a viewport, ~zoom 14+ in cities |
| SDF rebuild on UI thread | Stutter every GPS fix, gets worse linearly with disc count | `compute()` or long-lived isolate; debounce 100 ms | >10 discs at 1 fix/sec |
| Wisp particle Dart-side curl computation | UI thread CPU climbs as wisp count rises | Bound at 200 wisps cap (already done); profile the curl noise impl, simplify if hot | >150 wisps simultaneously at 60 Hz = ~12k noise samples/sec |
| Shader cold-compile jank on first paint | First disc reveal: 100–200 ms freeze | With Impeller: not an issue (AOT). With Skia-fallback: warm-up shader at app start (paint into a 1×1 canvas) | First-launch only, only on Skia (Impeller is default since Flutter 3.10) |
| Tile decode on cache eviction | Blank tiles 100–500 ms after fast zoom-out | `keepBuffer`, pre-decode at startup, larger LRU cache | Z=15→8 round trip with tile-LRU at default 16 |
| `setState` on each GPS fix | One full widget tree rebuild per fix | Lift the disc list to a state holder (Riverpod / Provider — pick one); only the disc layer rebuilds | >2 fixes/sec with deep widget tree |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Log file readable by other sideloaded apps via Files.app | Log contains GPS path + walk time; trivial PII leak if device shared | Write logs to `getApplicationSupportDirectory()` (sandboxed, not exposed to Files.app), not `getApplicationDocumentsDirectory()` (visible if user has "Files App enabled" in Info.plist; default no) |
| Sharing log via Mail leaves attachment in Sent folder | Mail server stores log; if forwarded, GPS path leaks | Caveat in the share dialog: "This log contains your walk path — share with care." Compress + filename-warn. |
| Bundled PMTiles file in IPA is in the bundle, not encrypted | Reverse-engineer of IPA reveals the map data (which is open data, not sensitive) | Acceptable — PMTiles is open-source map data; no PII |
| `permission_handler` `locationAlways` accidentally requested | Spurious permission prompt | POC only requests `locationWhenInUse`; verify `Info.plist` has only `NSLocationWhenInUseUsageDescription`, NOT the `Always` variants |
| Telemetry SDK creep via transitive dep | Privacy violation, GOSL v1.0 violation, app-store-rejection on eventual real release | CI license check, package-name allow list (see Pitfall 8) |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Blank map for 1–2 s after permission grant | "App is broken" perception | Splash screen until first tile painted AND permission granted AND PMTiles copy complete |
| Recenter snaps the camera but fog lags by 1 frame | Visible "fog catches up" jitter | Camera animation completes BEFORE fog is repainted at new position; tie repaint to animation completion |
| Wisps appear at user's location before first GPS fix (Pitfall 13) | Confusing visual glitch | Gate wisp render on first-fix-received |
| User backgrounds for >30 s, GPS dies silently | Walk test "feels broken" | Re-subscribe on resume + a banner if no fix in 10 s |
| Log share button tucked in unreachable corner | Developer can't reach it during walk → no debugging | One-tap log-share button in the app bar, not buried in a menu |
| FPS counter consumes a corner the user wants to look at | Map content obscured | Subtle, repositionable, debug-mode toggleable; tap to hide |

---

## "Looks Done But Isn't" Checklist

- [ ] **Fog locks on pure pan:** Often missing the combined-zoom-pan test — verify pinch-zoom-while-panning on a real walk.
- [ ] **Fog locks on pure zoom:** Often missing the rapid-zoom-then-snap test — verify the white-ellipse artefact is gone.
- [ ] **GPS dot updates:** Often missing the case where fix is jumpy — verify the dot smoothly animates between fixes (or hard-snaps consistently, but not both).
- [ ] **Recenter button:** Often missing the mid-animation cancel — what if the user pans during the animation? Verify pan cancels the animation.
- [ ] **Permission denied flow:** Often missing the "user denied, then went to Settings, granted, returned" — verify app re-checks permission on resume.
- [ ] **Logger writes:** Often missing the file-flush — verify the log file on disk has the latest line BEFORE the share button is tapped (not buffered in memory).
- [ ] **Share log:** Often missing the >10 MB case — verify rotation/compression triggers.
- [ ] **CI iOS IPA:** Often missing the "is this actually sideloadable?" — verify by sideloading from CI artifact at least once per phase, not just at end.
- [ ] **CI Android APK:** Often missing the release-mode build — debug APK has different shader compilation behaviour from release.
- [ ] **License audit:** Often missing transitive deps — verify `flutter pub deps --json` count is documented in DEPENDENCIES.md.
- [ ] **Telemetry audit:** Often missing the network-egress check — verify with iOS network log capture, not just code review.
- [ ] **Wisp warmup:** Often missing the "before first fix" case — verify no wisps render until first GPS fix logged.
- [ ] **Shader sanity screen:** Often missing — verify it exists and was used at least once on iOS device.
- [ ] **FPS counter:** Often missing on the actual walk — verify it's visible in iOS walk video evidence (or screenshot).
- [ ] **Combined gesture lock:** Often only tested as separate pan + separate zoom — explicitly test combined.

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| 1. Wisps in pixel space | MEDIUM (1–2 days) | Refactor `WispParticleSystem.position` from `Offset` to `LatLng`; re-tune curl scale; unit test pan-invariance |
| 2. Degree distance | LOW (1 day) | Replace distance helper with metres-aware version; re-bake SDF; re-walk once |
| 3. Impeller transpiler quirk | HIGH (1–7 days, depends on bug) | Reproduce in shader sanity screen; bisect shader uniforms; file Flutter issue; if blocking, fall back to per-uniform layout from BUG-014 with extra padding |
| 4. PMTiles I/O on first paint | LOW (1 day) | Move copy to permission-grant phase; add splash; idempotency check |
| 5. Vector tile perf cliff | HIGH (could be project-killer) | Disable labels; thin theme; if still <30 fps, evaluate `mapsforge_flutter` or custom MVT-on-Canvas; or accept the loss vs. parent and document |
| 6. Confirmation bias | LOW (one re-walk with FPS counter) | Re-walk with quantitative criteria; document FPS, recreate scenarios |
| 7. No baseline FPS | LOW (one walk on parent project) | Port FPS counter to parent; one walk; document delta |
| 8. Telemetry creep | MEDIUM (license-pin or replace dep) | Identify offending dep; either pin to clean version OR replace; CI gate prevents recurrence |
| 9. SideStore caps | LOW (free-up app slots) | Remove other sideloaded apps; toggle "Disable App Limit"; use stable bundle ID |
| 10. Combined zoom+pan displacement | HIGH (architectural; same as BUG-014) | Capture single MapCamera per layer build; unit test snapshot consistency; if root cause is `flutter_map` internal, file upstream issue |
| 11. share_plus / Mail truncation | LOW | Cap + gzip log; add explicit file-size log line before share |
| 12. SDF rebuild stutter | MEDIUM | Move to isolate via `compute()`; debounce 100 ms |
| 13. Wisp pre-fix glitch | LOW | Add gate on first-fix |
| 14. Frame pacing mismatch | LOW (per-frame dt) | Replace hardcoded 16ms with WidgetsBinding refresh rate |
| 15. BuildContext-after-await | LOW | Add lint, fix violations |
| 16. Geolocator background suspend | LOW | Add lifecycle observer, re-subscribe |
| 17. Shader Y-flip | LOW (one-line fix per backend) | Audit `IMPELLER_TARGET_OPENGLES` macro; flip if needed |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls. (Phase numbering is hypothetical; roadmap may differ — adjust to actual roadmap.)

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. Wisps in pixel space | Phase 6 (wisp integration) | Unit test: 100 m pan does not move world-anchored wisp's logical position |
| 2. Degree distance | Phase 4 (SDF + fog) | Unit test: distance from (48.5, 2.6) to (48.5, 3.6) ≈ 73.7 km |
| 3. Impeller transpiler | Phase 4 (shader integration) + Phase 0 (sanity screen) | Shader sanity screen passes on iOS device + Pixel 4a; debug toggle works |
| 4. PMTiles I/O timing | Phase 2 (permission gate) + Phase 3 (map) | Log shows file copied during permission flow, NOT in map build |
| 5. Vector tile label collision | Phase 3 (map screen) | No-fog FPS baseline ≥40 in central Melun; with fog ≥30 |
| 6. Confirmation bias | Phase 0 (test infra) | FPS counter visible in walk video; falsification criteria written before Phase 4 |
| 7. No baseline FPS | Phase 0 (test infra) + Phase 7 (decision) | Parent project pan-FPS measured; comparison documented |
| 8. Telemetry creep | Phase 0 (CI) | CI license-check on every PR; DEPENDENCIES.md row per package |
| 9. SideStore caps | Phase 0 (CI + sideload pipeline) | First IPA sideloaded successfully; pairing file documented |
| 10. Combined zoom+pan | Phase 4 (fog layer) | Unit test: SDF rect, clip path, uniforms derive from same MapCamera; iOS walk: combined gesture stays locked |
| 11. share_plus large file | Phase 1 (logger + share) | Smoke test: 50 MB log shared, byte-marker present at 47 MB |
| 12. SDF rebuild stutter | Phase 4 (SDF + fog) | DevTools profile: UI isolate <50% during sustained walking |
| 13. Wisp pre-fix glitch | Phase 6 (wisp integration) | No wisp render before first-fix log line |
| 14. Frame pacing | Phase 0 (FPS counter) | FPS counter reports refresh rate alongside fps |
| 15. BuildContext post-await | Phase 0 (lint config) onward | Analyser passes with `use_build_context_synchronously` |
| 16. Geolocator background | Phase 5 (GPS) | Walk: background for 1 minute, return, verify GPS fix log resumes within 5 s |
| 17. Shader Y-flip | Phase 4 (shader) | Render to offscreen image with known SDF, assert correct orientation |
| 18. Tile cache eviction | Phase 3 (map) | Z=15→8→15 round-trip: tiles paint without blank flash |
| 19. Log filename midnight | Phase 1 (logger) | UTC filenames; share UI lists multiple recent files |
| 20. Flutter version interactions | Phase 0 (toolchain) | Flutter version pinned in `.fvm/.fvmrc`; documented |

---

## Sources

### Primary (parent-project evidence — HIGH confidence)
- `C:\claude_checkouts\GOSL-MirkFall\docs\phase09-bug-tracking\BUG-014-sdf-rect-offset-axes.md` — root architectural evidence; six failed iterations; iteration 1 SDF slot-ordering fix; combined zoom+pan symptom; white-ellipse artefact
- `C:\claude_checkouts\GOSL-MirkFall\assets\shaders\atmospheric_fog.frag` — 41 floats + 1 sampler; `MIRK_FOG_DEBUG_OUTPUT_DENSITY` toggle; OpenGLES Y-flip guard; midpoint-128 SDF + 1-byte dither
- `C:\claude_checkouts\GOSL-MirkFall\lib\infrastructure\mirk\wisp\wisp_particle_system.dart` — wisp positions stored as `Offset` (pixels); 200-cap; 5-s warm-up implied by parameters
- `C:\claude_checkouts\GOSL-MirkFall\docs\POC-flutter-map-mirk.md` — POC spec; uniform table; package version targets

### Flutter / Impeller issue tracker — HIGH confidence
- [flutter/flutter#155805 — unused-uniform startup compile failure](https://github.com/flutter/flutter/issues/155805)
- [flutter/flutter#115044 — generated shaders always use high precision](https://github.com/flutter/flutter/issues/115044)
- [flutter/flutter#151355 — vertices+textureCoordinates off-by-1 pixel](https://github.com/flutter/flutter/issues/151355)
- [flutter/flutter#179268 — Vulkan→OpenGLES gradient bug](https://github.com/flutter/flutter/issues/179268)
- [flutter/flutter#176211 — Impeller Vulkan crash on Adreno (Lottie)](https://github.com/flutter/flutter/issues/176211)
- [flutter/flutter#159876 — Adreno 830 rendering glitches](https://github.com/flutter/flutter/issues/159876)
- [flutter/flutter#159834 — Adreno 610 visual glitches](https://github.com/flutter/flutter/issues/159834)
- [flutter/flutter#160162 — Porterduff compile fail on Adreno 640](https://github.com/flutter/flutter/issues/160162)
- [flutter/flutter#160941 — Vulkan OOM Samsung S23/Adreno](https://github.com/flutter/flutter/issues/160941)

### vector_map_tiles — MEDIUM confidence (qualitative reports, not measurements)
- [greensopinion/flutter-vector-map-tiles#10 — performance issues](https://github.com/greensopinion/flutter-vector-map-tiles/issues/10)
- [greensopinion/flutter-vector-map-tiles#120 — performance issues](https://github.com/greensopinion/flutter-vector-map-tiles/issues/120)
- [greensopinion/flutter-vector-map-tiles#21 — rendering in background isolates](https://github.com/greensopinion/flutter-vector-map-tiles/issues/21)
- [vector_map_tiles 10.0.0-beta.2 (flutter_gpu backend, Flutter dev channel)](https://pub.dev/packages/vector_map_tiles/versions/10.0.0-beta.2)
- [vector_map_tiles changelog](https://pub.dev/packages/vector_map_tiles/changelog)

### PMTiles / flutter_map plugins — MEDIUM confidence
- [josxha/flutter_map_plugins#44 — load PMTiles from assets](https://github.com/josxha/flutter_map_plugins/issues/44)
- [vector_map_tiles_pmtiles](https://pub.dev/packages/vector_map_tiles_pmtiles)
- [flutter_map layers documentation](https://docs.fleaflet.dev/usage/layers)

### path_provider iOS quirks — HIGH confidence
- [flutter/flutter#23957 — iOS Documents dir changes between launches](https://github.com/flutter/flutter/issues/23957)
- [flutter/flutter#50268 — same](https://github.com/flutter/flutter/issues/50268)
- [path_provider docs](https://pub.dev/packages/path_provider)

### geolocator iOS — MEDIUM confidence
- [Baseflow/flutter-geolocator#1270 — geolocator_apple >2.2.2 background](https://github.com/Baseflow/flutter-geolocator/issues/1270)
- [Baseflow/flutter-geolocator#485 — background indicator stuck](https://github.com/Baseflow/flutter-geolocator/issues/485)
- [Baseflow/flutter-geolocator#1122 — getCurrentPosition stops background](https://github.com/Baseflow/flutter-geolocator/issues/1122)

### SideStore — HIGH confidence on caps, LOW on entitlement specifics
- [SideStore FAQ — 3-app and 10-AppID caps](https://docs.sidestore.io/docs/faq)
- [SideStore/SideStore#68 — Universal App IDs](https://github.com/SideStore/SideStore/issues/68)
- [SideStore github](https://github.com/SideStore/SideStore)
- [TechyBuff — Disable App Limit toggle (2025)](https://techybuff.com/bypass-three-app-limit-with-sidestore-2025/)

### Shader compilation jank — HIGH confidence
- [Flutter shader compilation jank docs](https://docs.flutter.dev/perf/shader)
- [flutter/flutter#61450 — Skia first-run jank](https://github.com/flutter/flutter/issues/61450)
- [flutter/flutter#102853 — FragmentProgram on Impeller](https://github.com/flutter/flutter/issues/102853)
- [flutter/flutter#76180 — multi-frame shader compile jank](https://github.com/flutter/flutter/issues/76180)

### License-check tooling — HIGH confidence
- [dart_license_checker (--show-transitive-dependencies)](https://github.com/redsolver/dart_license_checker)
- [license_checker pub package](https://pub.dev/packages/license_checker)
- [Very Good CLI license checker](https://cli.vgv.dev/docs/commands/check_licenses)

### share_plus — LOW confidence (no documented sideload behaviour)
- [share_plus pub package](https://pub.dev/packages/share_plus) — flagged for Phase 1 smoke test

---

*Pitfalls research for: pure-Flutter same-Canvas fog-of-war POC, iOS-primary, Windows dev*
*Researched: 2026-04-30*
