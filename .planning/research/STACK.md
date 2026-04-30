# Stack Research

**Domain:** Flutter cross-platform (iOS-primary, Android-secondary, Windows-desktop dev) — pure-Flutter same-Canvas map + fragment-shader fog-of-war POC
**Researched:** 2026-04-30
**Overall confidence:** HIGH for SDK/utility packages; MEDIUM for the map-renderer dependency chain (a known compatibility cliff between `flutter_map` 8.x and `vector_map_tiles` 8.0 stable forces a deliberate version-pin choice that the architecture researcher must confirm)

---

## TL;DR — Prescriptive Stack

| Slot | Package | Pinned version | License | Why |
|------|---------|----------------|---------|-----|
| Flutter SDK | flutter (stable channel) | **3.41.8** | BSD-3 | Latest stable patch in the 3.41.x line that the parent MirkFall project pins (`>=3.41.0 <3.42.0`); ships Dart 3.11.x, Impeller default on iOS, public quarterly cadence. |
| Dart SDK | dart | **3.11.x** (bundled with Flutter 3.41.8) | BSD-3 | Bundled — do not pin separately. `pubspec.yaml` declares `sdk: ">=3.11.0 <4.0.0"`. |
| Map widget | `flutter_map` | **7.0.2** (default) **OR** **8.3.0** (forces beta vector chain) | BSD-3 | Pure-Flutter `CustomPainter`-based renderer. Both layers it can host paint into the same `ui.Canvas` as the rest of the widget tree → satisfies the same-Canvas hypothesis. **Version choice is a hard fork** — see "Map renderer dependency chain" below. |
| Vector tile rendering | `vector_map_tiles` | **8.0.0** (paired with flutter_map 7.0.2) **OR** **9.0.0-beta.8** (paired with flutter_map 8.3.0) | BSD-3 | The only well-maintained pure-Flutter MVT renderer for `flutter_map`. |
| PMTiles loader (vector) | `vector_map_tiles_pmtiles` | **1.5.0** | MIT | Loads MVT vector tiles from a PMTiles archive (local file or HTTP-Range). 1.5.0 chains to vector_map_tiles ^8.0.0 → flutter_map 7.x. |
| Permissions | `permission_handler` | **12.0.1** | MIT | Already in parent project. Verified publisher (baseflow.com). No telemetry. |
| Geolocation | `geolocator` | **14.0.2** | MIT | Already in parent project. Verified publisher (baseflow.com). No telemetry. |
| Logging | `logging` | **1.3.0** | BSD-3 | Already in parent project. dart.dev verified publisher. No telemetry. |
| Path provider | `path_provider` | **2.1.5** | BSD-3 | Flutter Favorite. flutter.dev verified publisher. |
| Path manipulation | `path` | **1.9.1** | BSD-3 | dart.dev verified. Used to build log file paths cross-platform. |
| Share/email | `share_plus` | **12.0.2** | BSD-3 | fluttercommunity.dev verified publisher. **Pinned to 12.0.2 deliberately** — see "Why not share_plus 13.x" below. |
| Routing | `go_router` | **16.0.0** | BSD-3 | Already in parent project. flutter.dev verified publisher. Mandated by parent CLAUDE.md. |
| Lints | `flutter_lints` | **6.0.0** | BSD-3 | Already in parent project. Augmented with custom `analyzer` strict mode. |

**Total runtime dependencies for the POC: 11 direct packages.** Every single one is on the GOSL allow-list (MIT / BSD-3 / Apache-2.0 absent here) and ships from a verified publisher. Zero analytics, zero crash-reporting, zero attribution SDKs.

---

## Map renderer dependency chain — the central trade-off

This is the only *non-trivial* version decision in the stack and the architecture researcher must own the final call.

The published-on-pub.dev dependency graph is:

```
vector_map_tiles_pmtiles 1.5.0 (MIT, last release 18 months ago)
    └── vector_map_tiles    ^8.0.0      (BSD-3, last stable 20 months ago)
            └── flutter_map  ^7.0.2     (BSD-3, last 7.x release 22 months ago)
```

vs.

```
vector_map_tiles_pmtiles 1.5.1     (MIT, on main but UNPUBLISHED)
    └── vector_map_tiles    ^9.0.0-beta.8  (BSD-3, last beta 11 months ago)
            └── flutter_map  ^8.1.1         (BSD-3, latest 8.3.0 is 16 days old)
```

**The mismatch the original `POC-flutter-map-mirk.md` table missed:** `flutter_map: ^8.3.0 + vector_map_tiles: ^8.0.0 + vector_map_tiles_pmtiles: ^1.5.0` *cannot resolve* — vector_map_tiles 8.0.0 hard-pins `flutter_map ^7.0.2`. The combination has to be one of the two coherent chains above.

### Recommendation: **Path A (stable chain) — flutter_map 7.0.2 + vector_map_tiles 8.0.0 + vector_map_tiles_pmtiles 1.5.0**

Pin:
```yaml
flutter_map: 7.0.2
vector_map_tiles: 8.0.0
vector_map_tiles_pmtiles: 1.5.0
vector_tile_renderer: 5.2.0   # transitive of vector_map_tiles 8.0.0; pin explicitly
pmtiles: 1.2.0                # transitive of vector_map_tiles_pmtiles 1.5.0
```

**Why Path A:**

1. **The hypothesis under test is renderer-architectural, not version-bleeding-edge.** The same-Canvas hypothesis is independent of which 7.x vs 8.x release of `flutter_map` we use; the same `CustomPainter` extension point exists in both. Going with stable removes a confound from the iOS UAT walk: if perf is bad, we know it's the renderer category, not a beta regression.
2. **Maturity gap is real but acceptable for a POC.** flutter_map 7.0.2 is 22 months old and vector_map_tiles 8.0.0 is 20 months old, but both have shipped in production apps and the codebase target (Flutter 3.41.8 / Dart 3.11) doesn't break either — confirmed via the sdk constraints (`sdk: '>=3.0.0 <4.0.0'`).
3. **Beta flutter_gpu dependency is forbidden.** vector_map_tiles 10.0.0-beta.2 explicitly depends on `flutter_gpu` and the dev channel — out of scope for a POC that must ship CI artifacts on stable.
4. **No production app should run on a `9.0.0-beta.8` published 11 months ago without renewed testing.** Either it's "good enough for prod" and the maintainer would have promoted it, or it's not — both cases say "don't pin a stale beta."
5. **The license of every link is GOSL-clean** (BSD-3 + BSD-3 + MIT). Path B has the same license tree.

**When to switch to Path B:** if architecture research finds that `flutter_map 7.0.2` paint-pipeline differs from 8.x in a way that breaks the same-Canvas claim (it shouldn't — both run pure Flutter widget tree paint), or if the architecture researcher discovers a feature in vector_map_tiles 9-beta we genuinely need (e.g. raster-dem or hillshade — both irrelevant for our 4 MB Melun MVT bundle).

**Confidence on Path A:** **MEDIUM-HIGH.** The chain is mature but stale. The parent MirkFall project switched away from this chain to `maplibre_gl 0.25.0` for production reasons unrelated to architecture (see DEPENDENCIES.md in parent). For a POC whose purpose is testing the architectural claim, the staleness is acceptable; for production migration, this assumption gets revalidated.

---

## Detailed package audit

### 1. Flutter SDK — **3.41.8 stable**

- **Channel:** stable (never beta or dev for this POC)
- **Dart SDK bundled:** 3.11.x (matches parent project's `sdk: ">=3.11.0 <4.0.0"`)
- **Impeller status on iOS:** default since Flutter 3.10; sideloaded builds run Impeller normally. `FragmentProgram` (used by `atmospheric_fog.frag`) is fully supported on Impeller iOS as of 3.27+; behaviour validated in parent MirkFall on iOS sideloaded build.
- **Pin in CI:** `subosito/flutter-action@v2` with `flutter-version: '3.41.8'` and `channel: 'stable'`. Do not use `'any'`.
- **Confidence:** HIGH. Latest stable patch in the 3.41.x series confirmed via [flutter/flutter#184019 hotfix Flutter 3.41.6](https://github.com/flutter/flutter/issues/184019) and [CHANGELOG.md on stable](https://github.com/flutter/flutter/blob/stable/CHANGELOG.md) (3.41.8 is current top-of-stable). What would change my answer: a 3.41.9 hotfix lands before the POC starts — easy to bump.

### 2. `flutter_map` 7.0.2 (Path A) / 8.3.0 (Path B)

- **License:** BSD-3-Clause (verified [pub.dev/packages/flutter_map](https://pub.dev/packages/flutter_map))
- **Telemetry:** none. Pure Dart Flutter package; no platform channels except for HTTP tile fetching which is opt-in via the user's `TileLayer.urlTemplate` (we use a local PMTiles file, so zero network).
- **Maintenance:** 8.3.0 published 16 days ago (active); 7.0.2 published 22 months ago (frozen but stable line).
- **Why this and not maplibre_gl:** maplibre_gl is a *PlatformView* — it renders in a separate native UIView/SurfaceView with its own GL/Metal context, then composites via Flutter's `_PlatformViewLayer`. That is precisely the architecture BUG-014 proved cannot stay frame-locked under combined gestures. flutter_map renders into a Flutter RenderObject's Canvas — *same paint phase, same frame, same pipeline*.
- **Confidence:** HIGH for the architecture decision; MEDIUM for "7.0.2 vs 8.3.0" given the chain constraint discussed above.

### 3. `vector_map_tiles` 8.0.0 (Path A) / 9.0.0-beta.8 (Path B)

- **License:** BSD-3-Clause (publisher: greensopinion.com)
- **Telemetry:** none. Pure-Dart MVT renderer; calls into `vector_tile_renderer` to draw protobuf-decoded features onto a Flutter Canvas.
- **Maintenance:** 8.0.0 stable last touched 20 months ago. The maintainer is actively iterating on the 9.0.0-beta and 10.0.0-preview lines (preview now depends on flutter_gpu — out of scope). 9.0.0-beta.8 has been out 11 months without promotion to stable, which is itself a maintenance signal.
- **Known limitations relevant to us:**
  - Theme/style format must match the tile schema. Our PMTiles is OpenMapTiles-schema MVT (verified — parent project uses OMT-schema in `assets/maps/style.json`). vector_map_tiles ships a default OMT-compatible style.
  - Reported mobile perf concerns are why this POC exists — measuring is the point.
- **Confidence:** HIGH on license + telemetry; MEDIUM on perf adequacy (that's literally the POC question).

### 4. `vector_map_tiles_pmtiles` 1.5.0

- **License:** MIT (per `LICENSE` in the [josxha/flutter_map_plugins repo](https://github.com/josxha/flutter_map_plugins/blob/main/vector_map_tiles_pmtiles/LICENSE) — Joscha Eckert 2024)
- **Telemetry:** none. Pure-Dart wrapper that opens a `.pmtiles` file (local or HTTP), uses HTTP Range Requests for remote, plain `RandomAccessFile` reads for local — no third-party SDKs.
- **Maintenance:** 1.5.0 published 18 months ago; main branch has progressed to 1.5.1 (unpublished) targeting `vector_map_tiles ^9.0.0-beta.8`. Pub points 150/160 (only knock: outdated transitive `pmtiles ^1.2.0` vs current 2.0.0; not a security issue).
- **Local-asset loading:** confirmed possible via `PmTilesVectorTileProvider.fromSource('/abs/path/file.pmtiles')`. **Asset URI scheme (`asset:///`) is NOT directly supported** — the package wants a real filesystem path. See "PMTiles asset bundling" section below for the standard workaround.
- **Confidence:** HIGH on license + GOSL fit; MEDIUM-HIGH on it being the right loader (it's the only maintained one for this chain).

### 5. `permission_handler` 12.0.1

- **License:** MIT
- **Publisher:** baseflow.com (verified)
- **Telemetry:** none. Wraps native iOS `CLLocationManager` permission requests + Android runtime permissions; no analytics SDKs embedded.
- **Already in parent** at this exact version — strong reuse signal.
- **iOS minimum:** iOS 12+; works fine on sideloaded builds (no entitlement requirements beyond what's in `Info.plist`).
- **Confidence:** HIGH.

### 6. `geolocator` 14.0.2

- **License:** MIT
- **Publisher:** baseflow.com (verified, same as permission_handler)
- **Telemetry:** none. Wraps native location APIs; no third-party SDKs.
- **Already in parent** at this exact version.
- **iOS-specific notes:**
  - Requires `NSLocationWhenInUseUsageDescription` in `Info.plist` (POC uses `whenInUse` only — `NSLocationAlwaysAndWhenInUseUsageDescription` is NOT required).
  - On sideloaded builds via SideStore, GPS permission flow works identically to App Store builds (the permission grant is per-app-bundle-id; SideStore re-signs with a developer cert, so the user gets a fresh permission prompt the first launch after each re-sideload).
- **Confidence:** HIGH.

### 7. `logging` 1.3.0

- **License:** BSD-3-Clause
- **Publisher:** dart.dev (verified — Dart team)
- **Telemetry:** none. Pure-Dart logging API; we route output to `dart:developer` `log()` for IDE-side and to a file sink for the on-device log capture.
- **Already in parent** at this exact version.
- **Recommendation: use `logging` package, NOT `dart:developer log()` directly.**
  - `logging` gives us hierarchical loggers (`Logger('mirk.fog')`, `Logger('mirk.gps')`) with one global subscription. We pipe that subscription into the file sink AND `dart:developer.log()` simultaneously.
  - `dart:developer.log()` alone has no built-in level filtering or hierarchical filtering; it's a sink, not a logger.
  - The parent project pattern is: `Logger.root.level = Level.ALL` in debug, `Level.INFO` in release; one `onRecord` listener writes to the timestamped file in `<app_documents_dir>/logs/`.
- **Confidence:** HIGH.

### 8. `path_provider` 2.1.5

- **License:** BSD-3-Clause
- **Publisher:** flutter.dev (verified)
- **Already in parent** at this version. Flutter Favorite badge.
- Used to find `<app_documents_dir>` for log files and `<app_support_dir>` for the unpacked PMTiles bundle (see asset bundling section).
- **Confidence:** HIGH.

### 9. `path` 1.9.1

- **License:** BSD-3-Clause
- **Publisher:** dart.dev (Dart team)
- **Already in parent** at this version. Per parent CLAUDE.md, ALL filesystem path joins MUST use `p.join()` — never `'/'` concatenation. This rule applies verbatim to the POC.
- **Confidence:** HIGH.

### 10. `share_plus` **12.0.2** (NOT 13.x)

- **License:** BSD-3-Clause
- **Publisher:** fluttercommunity.dev (verified)
- **Telemetry:** none. The package wires up native `UIActivityViewController` on iOS and `Intent.ACTION_SEND` on Android. The actual transmission of the log file goes through the user-selected share sheet target (Mail.app, Messages, etc.) — that is by definition user-initiated and falls under "appels réseau à l'initiative de l'utilisateur" in the parent CLAUDE.md, which is allowed.
- **iOS sideloaded build behaviour:** `UIActivityViewController` is a system framework with no provisioning-profile requirement; it works identically on sideloaded SideStore builds. The `Mail.app` activity is present iff the user has Mail configured. No "phone home" behaviour.
- **Already in parent** at exactly **12.0.2**.
- **Why not 13.x?** Two reasons:
  1. **Hard SDK floor in 13.0.0.** Per the [share_plus changelog](https://pub.dev/packages/share_plus/changelog), 13.0.0 requires Flutter 3.41.6+ AND Dart 3.11+. Our pinned Flutter is 3.41.8 / Dart 3.11.x, so technically we satisfy 13.x. But:
  2. **The parent project is on 12.0.2 with a clean audit row in DEPENDENCIES.md.** Reusing the same pin reuses the audit, and a downgrade from any 13.x change (the 13.0.0 release bumps the Windows backend's `win32` transitive — same incident pattern as the parent project's `device_info_plus 13.0.0` rejection at line 81 of the parent pubspec). Not worth the audit churn for a POC.
  3. 13.1.0 lowered the SDK floor again (Flutter 3.38.1, Dart 3.10) but that does not fix the win32 transitive churn. Stick with 12.0.2.
- **Confidence:** HIGH.

### 11. `go_router` 16.0.0

- **License:** BSD-3-Clause
- **Publisher:** flutter.dev
- **Already in parent** at this exact version.
- **Latest is 17.2.2** (9 days old) but **stay on 16.0.0** to match parent — `context.push()` / `context.go()` semantics are the only API surface we use, and both are unchanged across 16→17. No upgrade benefit for a 2-screen POC.
- **POC routing graph** (so simple it almost doesn't need a router, but mandated):
  ```
  /            → PermissionGateScreen
  /map         → MapScreen
  /denied      → PermissionDeniedScreen
  ```
  - `/` → `/map` is a `context.go()` (terminal transition, back button shouldn't return to the gate).
  - `/` → `/denied` is also a `context.go()` (same reason).
  - `/denied` → system Settings is a `permission_handler` `openAppSettings()` call, not a route.
  - The recenter FAB does NOT navigate; it just calls `MapController.move()`. No route push/go for it.
- **Confidence:** HIGH.

### 12. `flutter_lints` 6.0.0 + custom `analysis_options.yaml`

- **License:** BSD-3-Clause
- **Publisher:** flutter.dev
- **Already in parent.**
- **Why not `very_good_analysis` 10.2.0?** Two reasons:
  1. The parent project uses `flutter_lints` + custom strictness, NOT VGA. Code-donor mandate (every component is expected to port back) means the POC should match the parent's lint ruleset to avoid "passes here, fails there" friction.
  2. VGA is MIT (so license is fine) but it's significantly stricter (e.g. `prefer_const_constructors_in_immutables`, `public_member_api_docs`) than what the parent enforces. Adopting VGA in the POC would force the porter to relax it on the way back, or force the parent to adopt it — out of scope for this POC.
- **`analysis_options.yaml` to use** (matches parent's strict mode):
  ```yaml
  include: package:flutter_lints/flutter.yaml

  analyzer:
    language:
      strict-casts: true
      strict-inference: true
      strict-raw-types: true
    errors:
      missing_required_param: error
      missing_return: error
      todo: ignore
    exclude:
      - '**/*.g.dart'
      - '**/*.freezed.dart'

  linter:
    rules:
      avoid_print: true
      prefer_const_constructors: true
      prefer_const_literals_to_create_immutables: true
      prefer_final_locals: true
      unawaited_futures: true
  ```
- **`dart format --line-length 160`** in CI per parent CLAUDE.md (not 80, not 120 — 160).
- **Confidence:** HIGH.

---

## State management — recommendation: **none (just `setState`)**

The parent project uses `flutter_riverpod 3.3.1` + `riverpod_annotation 4.0.2` + `riverpod_generator 4.0.3` + `riverpod_lint 3.1.3` + `custom_lint 0.8.1`. **For this POC, do NOT add Riverpod.** Reasoning:

1. **The POC has 3 screens, one of which is the only one with non-trivial state.** All non-trivial state lives in `MapScreen`:
   - the active `MapController` (already a Listenable from flutter_map)
   - the list of `RevealDisc`s (in-memory, mutated on each GPS fix)
   - the SDF `ui.Image` (rebuilt when discs change)
   - the user's last GPS fix (for the recenter FAB)
2. Constructor injection (CLAUDE.md mandate) handles services: `GeolocatorService`, `FileLogger`, `RevealedSdfBuilder` are all instantiated in `main()` and passed down.
3. Adding Riverpod brings 4 packages, codegen, `build_runner`, `custom_lint` plugin scaffolding, the analyzer override saga from the parent project (line 168-182 of parent pubspec) — all of that is overhead for "I have one StatefulWidget with `setState` calls."
4. The parent project's "single state-management system per project" rule (CLAUDE.md line 248) means the POC's state-management decision is *the POC's*, not a violation of the parent's choice. The POC is a separate codebase with a separate decision.
5. **If the POC ports back to MirkFall, the StatefulWidget gets adapted to a Riverpod `Notifier`. That's a small mechanical refactor — much smaller than carrying Riverpod's overhead through a 3-screen POC.**

**Use:** plain `StatefulWidget` + `setState` for `MapScreen`. Services injected via constructor (a `MapScreenServices` value object containing the FileLogger, GeolocatorStream, RevealedSdfBuilder, and PMTiles loader is fine).

**Confidence:** HIGH. The "no state-management package for a 3-screen POC" call is solid; if the architecture researcher decides we need a `MapController` with cross-cutting concerns (e.g. wisp animation ticker that survives gesture rebuilds), we can revisit — but that's a `Listenable` / `ChangeNotifier`, not a state-management framework.

---

## Testing — recommendation: **flutter_test only, no helper packages**

- `flutter_test` (SDK-shipped) + `dart:ui` for golden tests if we want to assert the SDF generator output.
- **Skip `mocktail`, `mockito`, `bloc_test`, etc.** This is a POC; the testable surface is small and constructor-injected (`FileLogger`, `RevealedSdfBuilder`, etc.). A hand-rolled fake is faster to write than configuring a mock package.
- **Skip `integration_test`.** All UAT happens through manual iOS sideloaded walks per PROJECT.md — that's the actual quality gate. Programmatic integration tests on a `flutter_map` widget that needs real GPS fixes and 60 fps frame measurement are net-negative for a POC.
- The `tool/` directory in the parent project has CI guards (`check_licenses.dart`, `check_dependencies_md.dart`, `check_avoid_remote_pmtiles.dart`). **Recommend porting `check_licenses.dart` and `check_dependencies_md.dart` verbatim** so the POC's `DEPENDENCIES.md` stays in sync with `pubspec.lock` automatically.

**Confidence:** HIGH.

---

## CI — GitHub Actions

Three jobs, mirroring the parent project's structure (parent's `.github/workflows/ci.yml` is the reference):

```yaml
name: CI
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.8'
          channel: 'stable'
          cache: true
      - run: flutter pub get
      - run: dart format --line-length 160 --set-exit-if-changed .
      - run: flutter analyze --fatal-infos
      - run: flutter test
      - run: dart run tool/check_licenses.dart
      - run: dart run tool/check_dependencies_md.dart

  build-android:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.8'
          channel: 'stable'
          cache: true
      - run: flutter pub get
      - run: flutter build apk --debug
      - uses: actions/upload-artifact@v4
        with:
          name: mirk-poc-debug-apk
          path: build/app/outputs/flutter-apk/app-debug.apk
          retention-days: 30

  build-ios:
    runs-on: macos-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.8'
          channel: 'stable'
          cache: true
      - run: flutter pub get
      - run: flutter build ios --no-codesign --debug
      - name: Package unsigned IPA
        run: |
          mkdir -p build/ios/ipa/Payload
          cp -r build/ios/iphoneos/Runner.app build/ios/ipa/Payload/
          cd build/ios/ipa
          zip -qr mirk-poc-debug-unsigned.ipa Payload
      - uses: actions/upload-artifact@v4
        with:
          name: mirk-poc-debug-ipa-unsigned
          path: build/ios/ipa/mirk-poc-debug-unsigned.ipa
          retention-days: 30
```

**Notes:**
- `flutter build ios --no-codesign` produces a `.app` in `build/ios/iphoneos/`, NOT a `.ipa`. The manual zip step packages it into `Payload/Runner.app` → `unsigned.ipa`, which is the format SideStore expects. (The newer `flutter build ipa --no-codesign` also works on Flutter 3.41 but produces output in `build/ios/ipa/` — either approach is fine; the manual zip is more explicit and avoids the `ExportOptions.plist` hassle.)
- `lint` runs first as a gate; the two build jobs run in parallel after lint passes.
- `macos-latest` minutes cost 10x ubuntu — keep the iOS job lean (no test execution there; `lint` already ran the unit tests on ubuntu).
- `cache: true` on flutter-action restores the pub cache across runs; meaningfully faster.
- **Reference workflows that have shipped this exact pattern:** parent MirkFall `.github/workflows/ci.yml` (private), and the public [LinkedIn guide on unsigned IPA export for Flutter](https://www.linkedin.com/pulse/comprehensive-guide-ios-ipa-export-flutter-projects-mac-soltanzadeh-xmxte) for the manual-zip pattern.

**Confidence:** HIGH for the workflow structure (it mirrors a proven workflow in the parent); MEDIUM for the exact `flutter build ios --no-codesign` + zip pattern vs `flutter build ipa --no-codesign` (both should work; pick whichever the parent uses for verbatim consistency).

---

## iOS sideload toolchain notes (SideStore — user-side, not a CI dep)

Not a runtime dependency, but constraints on the IPA that affect the build:

1. **No code signing in CI.** SideStore re-signs with the user's free Apple Developer cert (or AltStore-style anisette server) on the device side. The CI artifact must be `.ipa` containing `Payload/Runner.app/`, ad-hoc unsigned (no embedded provisioning profile, no signed `.framework` bundles).
2. **Deployment target.** iOS 13.0+ matches share_plus 13.0 floor and is what the parent project ships. Set in `ios/Podfile` (`platform :ios, '13.0'`) and `ios/Runner.xcodeproj` (`IPHONEOS_DEPLOYMENT_TARGET = 13.0`).
3. **Bitcode.** Disabled by default in modern Flutter; no action needed.
4. **App Transport Security.** No relaxations needed — the POC makes zero network calls.
5. **Privacy manifests.** iOS 17+ requires `PrivacyInfo.xcprivacy` declaring "Required Reason API" usage. Both `geolocator` and `path_provider` ship their own privacy manifest; the app-level manifest needs to declare `NSPrivacyAccessedAPICategoryFileTimestamp` (used by `path_provider` transitively) and `NSPrivacyAccessedAPICategoryUserDefaults` (used by Flutter shared prefs / share_plus). The parent project has this; copy `ios/Runner/PrivacyInfo.xcprivacy` verbatim.

### Required `Info.plist` keys

```xml
<key>CFBundleDisplayName</key>           <string>MirkFall POC</string>
<key>NSLocationWhenInUseUsageDescription</key>
    <string>Used to draw your position on the map and clear the fog around you.</string>
<key>UILaunchStoryboardName</key>        <string>LaunchScreen</string>
<key>UIRequiresFullScreen</key>          <true/>
<key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
```

**Do NOT add:**
- `NSLocationAlwaysAndWhenInUseUsageDescription` — not used; `Permission.locationAlways` is out of scope.
- `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription` — no camera/mic/photo features in the POC.
- `NSAppTransportSecurity` exceptions — no HTTP traffic.

**Confidence:** HIGH.

---

## PMTiles asset bundling — recommended pattern

The constraint: `vector_map_tiles_pmtiles` wants a real filesystem path. iOS doesn't expose Flutter assets as filesystem paths (they're inside the IPA's resource bundle).

**Pattern: copy-on-first-launch to `<app_support_dir>/maps/Fra_Melun.pmtile`**

```dart
// Pseudo-code; final implementation lives in PMTilesAssetUnpacker.
Future<String> ensureMelunPmtileFilename() async {
  final supportDir = await getApplicationSupportDirectory();
  final pmtileFilename = p.join(supportDir.path, 'maps', 'Fra_Melun.pmtile');
  final file = File(pmtileFilename);
  if (await file.exists()) return pmtileFilename;
  await file.parent.create(recursive: true);
  final data = await rootBundle.load('assets/maps/Fra_Melun.pmtile');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return pmtileFilename;
}
```

**Why this and not "load directly from `rootBundle`":**
- `rootBundle.load()` returns a `ByteData` of the entire 4 MB file — fine in RAM, but `vector_map_tiles_pmtiles` does `RandomAccessFile` reads (range-style) on the file. Loading-into-memory bypasses that and forces full decompression on every tile request.
- Copy-once means subsequent app launches use the file directly — true zero-overhead cold start after the first boot.
- 4 MB copy on first launch is unmeasurable on iPhone storage I/O (microseconds).

**`pubspec.yaml` `flutter:` block:**
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/maps/Fra_Melun.pmtile
  shaders:
    - assets/shaders/atmospheric_fog.frag
```

**Why not bundle as an Xcode resource directly (iOS-native path):** Flutter's asset system is the cross-platform abstraction; bundling natively means dual maintenance for Android and iOS for zero perf gain. The unpack-on-first-launch pattern is the standard Flutter practice and is what the parent project uses for its own world.pmtiles bundle.

**Confidence:** HIGH. This pattern is in the parent project; verified to work on iOS sideloaded builds.

---

## Rejected packages (with reasons — feeds DEPENDENCIES.md)

| Package | Version checked | Rejection reason |
|---------|----------------|------------------|
| `firebase_core`, `firebase_analytics`, `firebase_crashlytics`, `firebase_performance` | any | **Telemetry forbidden by GOSL.** All four make automatic network calls to Google servers without explicit per-event user consent. Any attempt to add Firebase to the POC must be rejected at code review. |
| `sentry_flutter` | any | **Telemetry forbidden** in default config (auto-capture sends crashes to sentry.io). Even self-hosted Sentry violates the "no automatic network egress" rule because it ships errors without per-error user consent. |
| `posthog_flutter`, `mixpanel_flutter`, `amplitude_flutter`, `segment_flutter` | any | **Analytics — categorically forbidden.** |
| `appsflyer_sdk`, `adjust_sdk`, `branch_sdk`, `kochava_tracker` | any | **Attribution SDKs — categorically forbidden.** |
| `google_mobile_ads`, `facebook_audience_network` | any | **Ad SDKs — categorically forbidden.** |
| `flutter_local_notifications` | 21.0.0 (in parent) | **Not needed for POC.** Parent has it; POC has no notification surface. Dropping it removes a transitive iOS dependency tree we don't need. |
| `drift`, `drift_flutter`, `sqlite3_flutter_libs` | parent versions | **Not needed for POC.** PROJECT.md explicitly excludes "Database / Drift / migrations — POC stores discs in memory." |
| `freezed_annotation`, `json_annotation`, `freezed`, `json_serializable` | parent versions | **Not needed for POC.** No serialized models in scope. The few domain types (`RevealDisc`, `MirkViewportBbox`) are immutable hand-written classes — that's faster to write than the `freezed` codegen ceremony for 3 classes. |
| `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`, `riverpod_lint`, `custom_lint` | parent versions | **State management framework — not justified for 3-screen POC.** See "State management" section above. |
| `device_info_plus` | 12.4.0 (in parent) | **Not needed for POC.** Parent uses it for OEM battery-killer detection on the GPS guidance screen — out of scope here. |
| `image_picker` | 1.2.1 (in parent) | **Not needed for POC.** No image input. |
| `file_picker` | 11.0.2 (in parent) | **Not needed for POC.** Log sharing goes through `share_plus`, not file picker. |
| `shared_preferences` | 2.5.5 (in parent) | **Not needed for POC.** No persistent settings — discs are in-memory; logger directory is computed deterministically. |
| `flutter_dotenv` | any | **Not needed for POC.** No secrets. |
| `crypto` | 3.0.7 (in parent) | **Not needed for POC.** Used in parent for chunk SHA256 verification on the country-PMTiles download pipeline; we bundle the pmtile, no integrity check needed. |
| `maplibre_gl` | 0.25.0 (in parent) | **Architecturally excluded.** Whole point of the POC is to validate a same-Canvas alternative; including maplibre_gl re-imports the platform-view problem the POC is trying to escape. License (BSD-2 + bundled MapLibre Native BSD-2) is fine; architecture is not. |
| `vector_map_tiles` | 10.0.0-beta.2 | **Pre-release / dev-channel only.** Depends on `flutter_gpu` and the Flutter dev channel; cannot ship on stable. Re-evaluate when 10.x reaches stable + flutter_gpu reaches stable. |
| `mapsforge_flutter` | latest | **License risk + maintenance.** Mapsforge native (Java) is LGPL — that's a transitive license concern even via a Dart wrapper. Out for GOSL. |
| `very_good_analysis` | 10.2.0 | **License is fine (MIT)** but mismatched with parent's `flutter_lints`-based ruleset. Code-donor mandate (parent CLAUDE.md) wants the POC code to drop into MirkFall — using a different lint package would create false-positive lint diffs on the way back. |
| `flutter_map_pmtiles` | 1.0.5 | **Wrong format.** This is the *raster* PMTiles plugin; we have a *vector* MVT PMTile (preserves restyling capability). Not in scope. |

---

## Version compatibility matrix

| Package A | Pinned | Compatible with | Notes |
|-----------|--------|-----------------|-------|
| `flutter_map` | 7.0.2 | `vector_map_tiles 8.0.0`, `flutter_map_pmtiles 1.0.5` (raster, unused) | Path A: stable chain |
| `vector_map_tiles` | 8.0.0 | `flutter_map ^7.0.2` (HARD CAP at 7.x) | Reason for Path A's flutter_map pin |
| `vector_map_tiles_pmtiles` | 1.5.0 | `vector_map_tiles ^8.0.0` (and thus `flutter_map ^7.0.2`) | Forces the Path A chain |
| `vector_tile_renderer` | 5.2.0 | `vector_map_tiles 8.0.0` (transitive — pin explicitly anyway) | |
| `pmtiles` | 1.2.0 | `vector_map_tiles_pmtiles 1.5.0` (transitive — pin explicitly anyway) | |
| `share_plus` | 12.0.2 | Flutter `>=3.19.0`, Dart `>=3.3.0` | Trivially within our 3.41.8 / 3.11 |
| `permission_handler` | 12.0.1 | iOS 12+, Android API 21+ | |
| `geolocator` | 14.0.2 | iOS 12+, Android API 21+ | |
| `go_router` | 16.0.0 | Flutter `>=3.27.0` | |
| `path_provider` | 2.1.5 | All Flutter 3.x | |
| `logging` | 1.3.0 | All Dart 3.x | |
| `path` | 1.9.1 | All Dart 3.x | |
| `flutter_lints` | 6.0.0 | Flutter 3.32+ | |

**Critical rule:** The `pubspec.yaml` MUST use exact pins (no `^`, no `>=`) per parent CLAUDE.md. The `^` in the `vector_map_tiles_pmtiles 1.5.0 → ^8.0.0` chain is a *transitive* range owned by the upstream package — that's fine; what we control is our direct `vector_map_tiles: 8.0.0` pin which locks the resolution.

---

## Final `pubspec.yaml` (Path A — recommended)

```yaml
name: mirk_poc_debug
description: MirkFall same-Canvas POC. GOSL v1.0.
publish_to: none
version: 0.1.0+1

environment:
  sdk: ">=3.11.0 <4.0.0"
  flutter: ">=3.41.0 <3.42.0"

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: 1.0.9

  # Map renderer (Path A — flutter_map 7.x stable chain)
  flutter_map: 7.0.2
  vector_map_tiles: 8.0.0
  vector_map_tiles_pmtiles: 1.5.0
  # Promoted transitives — pinned explicitly per CLAUDE.md "every dep pinned" rule
  vector_tile_renderer: 5.2.0
  pmtiles: 1.2.0
  latlong2: 0.9.1   # transitive of flutter_map; pin explicitly

  # Native APIs
  permission_handler: 12.0.1
  geolocator: 14.0.2
  path_provider: 2.1.5

  # Cross-cutting
  go_router: 16.0.0
  logging: 1.3.0
  path: 1.9.1
  share_plus: 12.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: 6.0.0
  yaml: 3.1.3   # for tool/check_licenses.dart + tool/check_dependencies_md.dart

flutter:
  uses-material-design: true
  assets:
    - assets/maps/Fra_Melun.pmtile
  shaders:
    - assets/shaders/atmospheric_fog.frag
```

**No `dependency_overrides`** needed — none of the chain has the analyzer-versioning saga the parent project carries (because we don't have `drift_dev`, `freezed`, `json_serializable`, or `riverpod_generator`).

**Total dependency footprint:** 14 direct (11 runtime + 3 dev) + ~30 transitive — about a third of the parent project's tree.

---

## Sources

### Official package pages (verified pub.dev, April 2026)
- [pub.dev/packages/flutter_map](https://pub.dev/packages/flutter_map) — 8.3.0 (HIGH confidence)
- [pub.dev/packages/flutter_map versions](https://pub.dev/packages/flutter_map/versions) — 7.0.2 latest 7.x (HIGH)
- [pub.dev/packages/vector_map_tiles](https://pub.dev/packages/vector_map_tiles) — 8.0.0 stable (HIGH)
- [pub.dev/packages/vector_map_tiles changelog](https://pub.dev/packages/vector_map_tiles/changelog) — flutter_map 7.0.2 chain (HIGH)
- [pub.dev/packages/vector_map_tiles_pmtiles](https://pub.dev/packages/vector_map_tiles_pmtiles) — 1.5.0 latest published, MIT (HIGH)
- [pub.dev/packages/vector_map_tiles_pmtiles versions](https://pub.dev/packages/vector_map_tiles_pmtiles/versions) — version history (HIGH)
- [pub.dev/packages/permission_handler](https://pub.dev/packages/permission_handler) — 12.0.1 MIT (HIGH)
- [pub.dev/packages/geolocator](https://pub.dev/packages/geolocator) — 14.0.2 MIT (HIGH)
- [pub.dev/packages/share_plus](https://pub.dev/packages/share_plus) — 13.1.0 latest, BSD-3 (HIGH)
- [pub.dev/packages/share_plus changelog](https://pub.dev/packages/share_plus/changelog) — version history with iOS notes (HIGH)
- [pub.dev/packages/path_provider](https://pub.dev/packages/path_provider) — 2.1.5 BSD-3 (HIGH)
- [pub.dev/packages/path](https://pub.dev/packages/path) — 1.9.1 BSD-3 (HIGH)
- [pub.dev/packages/logging](https://pub.dev/packages/logging) — 1.3.0 BSD-3 (HIGH)
- [pub.dev/packages/go_router](https://pub.dev/packages/go_router) — 17.2.2 latest, BSD-3 (HIGH)
- [pub.dev/packages/flutter_lints](https://pub.dev/packages/flutter_lints) — 6.0.0 BSD-3 (HIGH)
- [pub.dev/packages/very_good_analysis](https://pub.dev/packages/very_good_analysis) — 10.2.0 MIT (HIGH; rejected)
- [pub.dev/packages/pmtiles](https://pub.dev/packages/pmtiles) — 2.0.0 BSD-2 (HIGH; transitive)
- [pub.dev/packages/vector_tile_renderer](https://pub.dev/packages/vector_tile_renderer) — 6.0.0 BSD-3 (HIGH; transitive of v_m_t 9.x)

### Source-of-truth repos (verified GitHub, April 2026)
- [github.com/josxha/flutter_map_plugins](https://github.com/josxha/flutter_map_plugins) — vector_map_tiles_pmtiles maintenance (MEDIUM — main has 1.5.1 unpublished targeting v_m_t 9.0.0-beta.8)
- [github.com/josxha/flutter_map_plugins LICENSE for vector_map_tiles_pmtiles](https://raw.githubusercontent.com/josxha/flutter_map_plugins/main/vector_map_tiles_pmtiles/LICENSE) — MIT confirmed (HIGH)
- [github.com/greensopinion/flutter-vector-map-tiles](https://github.com/greensopinion/flutter-vector-map-tiles) — vector_map_tiles maintainer, BSD-3, active dev on 9.x/10.x (MEDIUM; staleness of 8.0.0 stable is real)

### Flutter SDK references
- [docs.flutter.dev/release/release-notes](https://docs.flutter.dev/release/release-notes) — 3.41 release line (HIGH)
- [docs.flutter.dev/install/archive](https://docs.flutter.dev/install/archive) — 3.41.5 referenced (HIGH)
- [github.com/flutter/flutter CHANGELOG.md (stable)](https://github.com/flutter/flutter/blob/stable/CHANGELOG.md) — 3.41.8 latest hotfix (HIGH)
- [Flutter 3.41.6 hotfix issue #184019](https://github.com/flutter/flutter/issues/184019) (HIGH)
- [Flutter 3.41.5 hotfix issue #183740](https://github.com/flutter/flutter/issues/183740) (HIGH)

### CI/iOS sideload patterns
- [github.com/marketplace/actions/flutter-action](https://github.com/marketplace/actions/flutter-action) — subosito/flutter-action@v2 (HIGH)
- [Comprehensive guide: iOS IPA export for Flutter via GitHub Actions, no Mac](https://www.linkedin.com/pulse/comprehensive-guide-ios-ipa-export-flutter-projects-mac-soltanzadeh-xmxte) — manual zip pattern (MEDIUM, single-source but verified pattern)

### Parent project context
- `C:\claude_checkouts\GOSL-MirkFall\pubspec.yaml` — version pins for share_plus 12.0.2, geolocator 14.0.2, permission_handler 12.0.1, go_router 16.0.0, path_provider 2.1.5, logging 1.3.0, path 1.9.1, flutter_lints 6.0.0 (HIGH — code-donor reuse)
- `C:\claude_checkouts\GOSL-MirkFall\docs\POC-flutter-map-mirk.md` — original POC spec; package table contained the flutter_map 8.x + vector_map_tiles 8.0 mismatch this research surfaced (HIGH for that finding)

---

*Stack research for: Flutter same-Canvas fog-of-war POC*
*Researched: 2026-04-30*
*Author: gsd-researcher (Project Research mode, Stack dimension)*
