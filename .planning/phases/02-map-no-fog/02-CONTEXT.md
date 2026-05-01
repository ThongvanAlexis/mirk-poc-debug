# Phase 2: Map (no fog) - Context

**Gathered:** 2026-05-01
**Status:** Ready for planning

<domain>
## Phase Boundary

A walkable map screen that loads `Fra_Melun.pmtile` from `getApplicationSupportDirectory()`, accepts pan / zoom / combined / rotate gestures with sensible bounds, shows a blue dot following GPS fixes, and animates a recenter FAB to `_lastFix` at zoom 15 — sustaining ≥ 40 fps on iPhone 17 Pro without fog (PERF-02 gate before Phase 3 fog work).

Covers REQUIREMENTS.md MAP-01..06, LOC-01..05, PERF-02.

Out of scope for this phase: fog-of-war shader (Phase 3), reveal discs / SDF / frame-delta probe (Phase 3), wisp particles (Phase 4), custom basemap theme (v2), `MapView` domain abstraction (migration concern), `getLastKnownPosition()` use (forbidden by LOC-03).

</domain>

<decisions>
## Implementation Decisions

### PMTiles copy lifecycle
- **Trigger:** in `PermissionGateScreen` after `Permission.locationWhenInUse` becomes granted, BEFORE `context.go('/map')`. Pitfall 4 prescription. Map screen mounts with file already in place — no FutureBuilder thrash.
- **First-launch UX:** no extra UI. The `await` extends the post-grant moment by ~100-500 ms; the user sees the permission gate screen briefly remain. Subsequent launches: zero-latency idempotent skip.
- **Idempotency check:** `File.exists()` AND `lengthSync() == bundled-asset.lengthInBytes`. Catches truncated/interrupted previous copies cheaply (≪ 1 ms). No SHA256 (deferred to v2 ROB-02).
- **Target dir:** `getApplicationSupportDirectory()` (Pitfall 4 — Documents dir is iCloud-backed by default on iOS, Support is not, and we don't want a 4 MB binary blob in the user's iCloud).
- **Path:** `p.join(supportDir, 'maps', 'Fra_Melun.pmtile')` — never `'/'` concatenation.
- **Failure recovery:** catch `FileSystemException`, log to FileLogger at `Level.SEVERE`, route to a generic error screen with the underlying message. No retry button — if storage is broken, retrying won't help. POC failure is visible, not silent.
- **Log line on first launch (success):** `Copied Fra_Melun.pmtile (~4 MB) in <N> ms` (matches success criterion 1's exact phrasing).

### GPS subscription
- **Source:** `Geolocator.getPositionStream(LocationSettings(...))`. Cache the latest fix in a `Position? _lastFix` field on `_MapScreenState`. Never call `Geolocator.getLastKnownPosition()` (LOC-03).
- **Accuracy:** `LocationAccuracy.best` (~10 m on iPhone outdoors). Sufficient for 25 m reveal discs; battery-friendlier than `bestForNavigation`.
- **Distance filter:** 5 m. Prevents stationary-jitter from re-emitting fixes every second; one fix every ~5 m of walking aligns reasonably with a 25 m reveal radius (5 fixes per disc-radius). In Phase 3 this bounds disc-list growth + SDF rebuild rate.
- **Lifecycle:** subscribe in `MapScreen.initState`, cancel the `StreamSubscription` in `dispose`. NO pause-on-background — iOS already throttles `whenInUse` location updates to ~zero in background. Simpler invariant; one subscription per `MapScreen` instance.
- **Pre-fix UX:** map renders at the LOC default (Melun centre, z=13) without a blue dot; recenter FAB shows its disabled state per LOC-05. No "Acquiring GPS…" spinner.
- **Blue dot rendering:** `CircleLayer` (or hand-rolled `flutter_map` `MarkerLayer`) showing a 7 px filled circle (`#2b7cd6`) with a 2 px white stroke at `_lastFix.toLatLng()`. Conditionally rendered only when `_lastFix != null`.

### Map camera bounds & gestures
- **Min/max zoom:** locked to `[10, 15]`. Floor 10 keeps the user inside Melun-area context (~50 km square pan latitude); ceiling 15 matches the PMTiles archive exactly (no missing-tile blank past z=15). PERF-02 walk happens in the z=13-15 working envelope.
- **Pan bounds:** soft pad — `CameraConstraint.contain(bounds: bbox.expanded(~0.02°))` so the user can feel the edge with ~2 km overpan, springs back on fling. Bbox: lon `[2.60, 2.72]`, lat `[48.50, 48.57]`.
- **Rotation gesture:** ENABLED (deviation from "POC parity with parent" recommendation). Two-finger twist rotates the camera. **Compass UI:** always-visible icon top-right, positioned UNDER the FPS overlay; the icon is itself a button — tapping animates the bearing back to north (re-use the same 500 ms ease-in-out tween the recenter FAB uses, but only on the bearing axis).
- **Double-tap zoom:** enabled (flutter_map default — `InteractiveFlag.doubleTapZoom`).
- **Pan inertia / fling:** enabled (flutter_map default — `InteractiveFlag.flingAnimation`).
- **MapOptions sketch:** `interactionOptions: InteractionOptions(flags: InteractiveFlag.all)` — keep all default flags including `rotate`. Apply zoom + camera constraints separately.

### Recenter FAB UX
- **Target:** always animate to `(_lastFix.latLng, zoom: 15)` per LOC-04. No zoom-preservation, no toggle behaviour. Locked.
- **Animation:** 500 ms `Curves.easeInOut` interpolation from current camera state (lat, lon, zoom) to (`_lastFix.latLng`, z=15). Hand-rolled `AnimationController` driving `MapController.move` per frame, OR the `flutter_map_animations` pattern if pin-friendly (researcher confirms — adds one direct dep).
- **Position:** bottom-right, default `Scaffold.floatingActionButton` slot, default Material insets. Doesn't conflict with FPS counter (top-right) or compass icon (top-right, under FPS).
- **Disabled state:** when `_lastFix == null`, `onPressed: null`. Material auto-renders the FAB greyed-out per LOC-05.
- **Repeat-tap during animation:** cancel the in-flight `AnimationController`, capture the current interpolated camera state, start a new 500 ms tween to the latest `_lastFix`. Smooth re-target on a fresh GPS fix mid-animation. No flicker.
- **Icon:** `Icons.my_location` (Claude's discretion).

### Forward-decision for Phase 3 (locked here, not pre-decided in Phase 1)
- **Fog rendering in the ~2 km pan-overpan band:** the SDF and clip path are world-space (lat/lon → metres). Fog renders normally over the grey off-bbox area — visually weird (fog over grey), coordinate-correct. No bbox-clamp masking layer added. Phase 3 planner takes this as locked.

### Claude's Discretion
- Exact compass icon glyph (`Icons.explore`, `Icons.compass_calibration`, custom asset, etc.) — bias toward Material icons (no new image asset audit).
- Recenter FAB icon (`Icons.my_location` is the obvious pick; the planner can sub if a stronger candidate exists in `cupertino_icons` 1.0.9 already pinned).
- Whether to use `flutter_map_animations` (BSD-3? — researcher must audit) or hand-roll the 500 ms tween. Hand-roll is preferred if it costs ≤ ~30 LOC.
- Tooltip strings for FAB and compass — French + English via `AppLocalizations` like Phase 1.
- Error screen visual layout (uses Phase 1's denied-screen pattern as a reference; same `buildPocAppBar`).
- Logging granularity per GPS fix: at minimum INFO log every fix at `Logger('domain.location')`; whether to also log filter rejections / accuracy degradation is the planner's call.
- Animation curves and exact durations within the bracket (anything in `[400, 600]` ms `easeIn*` is fine for the recenter; ≤ 250 ms for the compass tween).
- The `MapScreenServices` value object's exact shape — at minimum it carries the FileLogger, the GeolocatorPositionStream factory, and the PMTiles file path; planner sets the constructor signature.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

**Phase 1 widgets — keep untouched, only swap MapScreen body**
- `lib/presentation/widgets/poc_app_bar.dart` (`buildPocAppBar`) — reused as-is on `/map`. No diff.
- `lib/presentation/widgets/fps_counter_overlay.dart` (`FpsCounterOverlay`) — reused as-is, top-right. Already ProMotion-aware (PERF-01).
- `lib/presentation/screens/map_screen.dart` is the only file rewritten: replace the placeholder `ColoredBox` (line 29) with `FlutterMap(...)`; the surrounding Scaffold + Stack + AppBar + FpsCounterOverlay stay verbatim. **One-widget swap, zero structural rewiring** — exactly the Phase 1 CONTEXT design intent.

**`PermissionGateScreen` (`lib/presentation/screens/permission_gate_screen.dart`)** — gets ONE behavioural extension: between `permission.status == granted` and `context.go('/map')`, await the PMTiles copy. The grant-handling code path already exists; insert the copy call there. The lifecycle re-check path on `AppLifecycleState.resumed` (Phase 1 W-2 fix) ALSO needs the copy hook so the re-check path doesn't bypass it.

**FileLogger** (`lib/infrastructure/logging/file_logger.dart`) — already constructor-injectable / globally accessible per Phase 1's bootstrap order. Phase 2 services (PMTiles loader, GeolocatorService) log via `Logger('infrastructure.pmtiles')` / `Logger('domain.location')` etc. — no changes to FileLogger itself.

**Constants** (`lib/config/constants.dart`) — `kMetersPerDegreeLat`, `kEarthRadiusMeters` already ported (BOOT-08). Phase 2 doesn't directly need them (the SDF math is Phase 3) but the planner can add map-specific constants here: `kPocInitialCameraLat = 48.5397`, `kPocInitialCameraLon = 2.6553`, `kPocInitialZoom = 13`, `kPocRecenterZoom = 15`, `kPocMinZoom = 10`, `kPocMaxZoom = 15`, `kPmtilesAssetPath`, `kPmtilesBboxLonMin`, etc. Followed by `kPocPanBoundsPadDegrees = 0.02`, `kPocRecenterAnimationMs = 500`, `kPocGpsAccuracyMeters` if useful, `kPocGpsDistanceFilterMeters = 5`.

**`assets/maps/Fra_Melun.pmtile`** — bundled in Phase 1 (BOOT-07). `pubspec.yaml` already references it under `flutter.assets`. No pubspec churn for Phase 2.

### Established Patterns
- **State management:** plain `StatefulWidget` + `setState` + constructor-injected services (locked across project per Phase 1 CONTEXT and PROJECT.md "Out of Scope"). `MapScreen` is one `StatefulWidget` with `_MapScreenState` carrying: `MapController`, `Position? _lastFix`, `StreamSubscription<Position> _positionSubscription`, `AnimationController? _recenterController`, `AnimationController? _compassController`.
- **Path joining:** every filesystem path via `package:path` `p.join()` (CLAUDE.md mandate, BOOT-08-adjacent).
- **GOSL header:** every new `.dart` file in `lib/` and `test/` carries the 3-line header (BOOT-02). CI gate already enforces.
- **Strict analysis:** `strict-casts: true`, `strict-inference: true`, `strict-raw-types: true`, `use_build_context_synchronously: error`. After every `await` involving the BuildContext (e.g. between PMTiles copy and `context.go('/map')`), `if (!mounted) return;` is mandatory (CLAUDE.md).
- **Localization:** all in-app strings (FAB tooltip, compass tooltip, error-screen text, log messages user might see) go through `AppLocalizations` (`lib/l10n/app_localizations.dart`). French primary, English secondary. No hardcoded user-facing strings.
- **Routing:** all transitions use `context.go()` (full pile reset, no back navigation in this POC).
- **Logging:** hierarchical loggers — `Logger('infrastructure.pmtiles')` for the asset copy + idempotency + failure path; `Logger('domain.location')` for GPS subscription, fix events, filter outcomes; `Logger('presentation.map')` for the map screen lifecycle if needed.
- **Pinned versions:** any new dev_dependency or runtime dep introduced in Phase 2 must be strictly pinned (no `^`). Audit row added to `DEPENDENCIES.md`. CI license-check job runs on every push (Phase 1).

### Integration Points
- **`PermissionGateScreen` grant path:** inject the PMTiles copy await between `granted` detection and `context.go('/map')`. Both the in-app prompt path AND the `AppLifecycleState.resumed` re-check path (Phase 1 W-2 fix) must hit it.
- **`MapScreen` initState:** kick off the GPS `StreamSubscription`. By construction the PMTiles file already exists at this point (PermissionGate guarantees it).
- **Error route:** add a `/error` route to `lib/presentation/router.dart` (or reuse `/denied` with a different message string — planner's call). Reached only via the PMTiles copy failure path, which routes via `context.go('/error', extra: errorMessage)` (or equivalent).
- **`pubspec.yaml`:** Phase 2 may add `flutter_map_animations` (researcher decides — only if hand-rolled tween is too noisy). All map-renderer packages already pinned in Phase 1 — no churn.
- **`MapScreenServices` value object:** new file `lib/domain/map/map_screen_services.dart` carrying the constructor-injected services. Created by `MapScreen.fromServices()` factory or wired directly in `app.dart` / `router.dart`'s redirect/builder.

### Files to create (planner expectation)
- `lib/domain/map/map_screen_services.dart` — value object for DI
- `lib/infrastructure/pmtiles/pmtiles_asset_copier.dart` — the asset → support-dir copy + idempotency check
- `lib/infrastructure/location/geolocator_service.dart` — wraps `Geolocator.getPositionStream` with the pinned settings; injectable for tests
- `lib/presentation/widgets/recenter_fab.dart` — the FAB widget owning the `AnimationController` for the camera tween
- `lib/presentation/widgets/map_compass.dart` — the always-visible compass icon owning its own `AnimationController` for bearing snap-to-north
- `lib/presentation/widgets/blue_dot_marker.dart` — the 7 px / `#2b7cd6` / 2 px white stroke marker, registered on a `flutter_map` `MarkerLayer`
- `lib/presentation/screens/error_screen.dart` (OR extend `permission_denied_screen.dart`) — the PMTiles-copy-failure landing
- `test/...` siblings: copier test (presence + size match path; FileSystemException path), geolocator service test (stream forwarding via fake Geolocator), recenter animation test (controller cancel + restart), compass tween test, blue dot marker test (visibility on `_lastFix == null`)

</code_context>

<specifics>
## Specific Ideas

- **POC parity with Material defaults wherever possible.** Recenter FAB is a stock Material `FloatingActionButton` at default position; double-tap zoom and fling are flutter_map defaults; `AppLifecycleState.resumed` re-check pattern from Phase 1 carries forward. Minimum bespoke UI = minimum surprise during the PERF-02 walk.
- **Rotation enabled — explicit deviation from "parent parity".** The parent MirkFall doesn't allow rotation; the POC does (with snap-to-north compass). This is a knowing deviation: if the same-Canvas hypothesis survives rotation transforms, that's a stronger claim for the migration. Phase 3 planner should treat the rotation matrix as a known additional variable in the frame-delta probe.
- **Soft-pad pan (~2 km overpan) — explicit deviation from "hard contain bbox".** Same rationale: if fog tracks correctly into the off-bbox grey band, that's a stronger Phase 3 result. Phase 3 fog rendering in the overpan band is locked: SDF + clip path keep computing in world space, fog renders over grey. No bbox-clamp mask.
- **No `getLastKnownPosition()`, ever.** LOC-03 is non-negotiable. The pre-fix UX explicitly shows "no blue dot, FAB disabled" rather than a stale cached fix.
- **PMTiles copy gets the visible "Copied Fra_Melun.pmtile (~4 MB) in <N> ms" log line on first launch and NOTHING on subsequent launches.** Roadmap success criterion 1 enforces this exactly; the idempotency-check path must be silent.

</specifics>

<deferred>
## Deferred Ideas

- **Walk-replay tool** (record GPS fixes during a walk, replay on Pixel 4a / Windows desktop without re-walking). Mentioned as deferred in Phase 1 CONTEXT; Phase 2 is when this would first be useful (no fog yet — pure pan/zoom + fix-driven blue dot replay). NOT in Phase 2 scope. Recommend creating a todo via `/gsd:add-todo` after Phase 2 closes; Phase 3 picks it up if the iOS UAT cost gets painful.
- **Label thinning for perf** (Pitfall 5: vector_map_tiles label collision is the main pan-time cost). Defer to Phase 2 walk evidence: if PERF-02's ≥ 40 fps gate fails on iPhone 17 Pro at z=13-15 in central Melun, then thin labels (z=14+ only, no road shields, no road labels) becomes the planner's mitigation tactic. If PERF-02 passes with default OMT style, leave it. **This is the falsification path for Phase 3 \(\rightarrow\) Phase 2 may have to ship a label-thinned theme override.**
- **Off-bbox grey background colour customisation.** flutter_map paints the off-tile area with a default colour. If during the walk the user finds the default jarring, allow Phase 3+ to override it via the renderer's options. Phase 2 leaves it default.
- **GPS accuracy-degraded fixes.** A fix with `accuracy > 50 m` is technically usable but visually noisy (blue dot teleports). The current decision is to render every fix with no accuracy filter; if walk evidence shows the dot dancing around indoors / on metro, add an `if (fix.accuracy > kPocGpsMaxAcceptableAccuracy) skip` filter at planning time. Phase 3 disc spawning will care more about this than Phase 2's blue dot.
- **Cross-restart auto-resume routing bug** (deferred from Phase 1 AUTH-04). Toggling Location ON in iOS Settings + returning should auto-nav from `/denied` to `/map`; the auto-nav doesn't fire after a cold restart. Not in Phase 2 scope (the user must re-launch and grant fresh anyway). Phase 5 hardening may re-touch.
- **`flutter_map_animations` package adoption.** If the hand-rolled `AnimationController` + `MapController.move` tween costs more than ~30 LOC, the researcher considers adding `flutter_map_animations` as a direct dep (audit first: license, telemetry, pinning). Default plan is to hand-roll.
- **Compass icon as a tap-target conflict with rotation.** If users tend to two-finger-twist near the top-right corner where the compass lives, the compass's tap area might absorb gestures the map should receive. If walk evidence shows this, move the compass to bottom-left or shrink its hit-test region. Phase 2 ships top-right with default Material `IconButton` hit area.

</deferred>

---

*Phase: 02-map-no-fog*
*Context gathered: 2026-05-01*
