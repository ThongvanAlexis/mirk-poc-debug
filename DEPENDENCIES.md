# Dependencies — MirkFall Same-Canvas POC

GOSL v1.0 audit per CLAUDE.md §Audit obligatoire. Every package in `pubspec.lock`
MUST have a row here (CI gate: `tool/check_dependencies_md.dart`).

**Allow-list of licenses:** MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, ISC,
zlib, CC0-1.0, Unlicense.
**Forbidden:** GPL (any version), AGPL, SSPL, Commons Clause.
**Telemetry policy:** Zero automatic network egress at app launch (CLAUDE.md
§Télémétrie — interdiction stricte).

Initial audit date: **2026-04-30**. Re-audit required whenever `pubspec.lock`
changes.

## Direct dependencies

| Package | Version | License | Source | Telemetry | Transitive licenses | Maintenance | Platform | Audit date |
|---------|---------|---------|--------|-----------|---------------------|-------------|----------|------------|
| flutter_localizations | (SDK) | BSD-3-Clause | flutter.dev | None | (SDK only) | Bundled | iOS+Android+Windows | 2026-04-30 |
| cupertino_icons | 1.0.9 | MIT | https://pub.dev/packages/cupertino_icons | None — asset-only icon font, no runtime code | None | Active (flutter.dev) | iOS+Android+Windows | 2026-04-30 |
| flutter_map | 7.0.2 | BSD-3-Clause | https://pub.dev/packages/flutter_map | None — no network calls unless user provides URL TileLayer | BSD-3, MIT | 7.x line frozen ~22mo; 8.x active upstream — POC pinned to 7.0.2 for code-donor parity with parent | iOS+Android | 2026-04-30 |
| vector_map_tiles | 8.0.0 | BSD-3-Clause | https://pub.dev/packages/vector_map_tiles | None — pure-Dart MVT renderer, no auto network | BSD-3, MIT | 8.0 stable ~20mo; 9.x in beta | iOS+Android | 2026-04-30 |
| vector_map_tiles_pmtiles | 1.5.0 | MIT | https://pub.dev/packages/vector_map_tiles_pmtiles | None — local file or HTTP-Range only when user provides URL | MIT, BSD-2 | 1.5 stable ~18mo | iOS+Android | 2026-04-30 |
| vector_tile_renderer | 5.2.0 | BSD-3-Clause | https://pub.dev/packages/vector_tile_renderer | None — pure-Dart MVT decoder/renderer | BSD-3, MIT | Active (5.x line) | iOS+Android | 2026-04-30 |
| pmtiles | 1.2.0 | BSD-2-Clause | https://pub.dev/packages/pmtiles | None — pure-Dart PMTiles archive reader | BSD-2 | 2.x available; 1.2 sufficient for the resolved chain | iOS+Android | 2026-04-30 |
| latlong2 | 0.9.1 | Apache-2.0 | https://pub.dev/packages/latlong2 | None — pure math, no I/O | Apache-2.0 | Stable | iOS+Android | 2026-04-30 |
| permission_handler | 12.0.1 | MIT | https://pub.dev/packages/permission_handler | None — wraps native OS permission APIs only | MIT, BSD-3 | Active (baseflow.com) | iOS+Android | 2026-04-30 |
| geolocator | 14.0.2 | MIT | https://pub.dev/packages/geolocator | None — wraps native OS GPS APIs only | MIT, BSD-3 | Active (baseflow.com) | iOS+Android | 2026-04-30 |
| path_provider | 2.1.5 | BSD-3-Clause | https://pub.dev/packages/path_provider | None — wraps native path-resolution APIs | BSD-3 | Flutter Favorite, active | iOS+Android+Windows | 2026-04-30 |
| go_router | 16.0.0 | BSD-3-Clause | https://pub.dev/packages/go_router | None — pure routing logic, no network | BSD-3 | Active (flutter.dev) | iOS+Android+Windows | 2026-04-30 |
| logging | 1.3.0 | BSD-3-Clause | https://pub.dev/packages/logging | None — sinks defined by caller, no built-in network | BSD-3 | Active (Dart team) | iOS+Android+Windows | 2026-04-30 |
| path | 1.9.1 | BSD-3-Clause | https://pub.dev/packages/path | None — pure-Dart path manipulation | BSD-3 | Active (Dart team) | iOS+Android+Windows | 2026-04-30 |
| share_plus | 12.0.2 | BSD-3-Clause | https://pub.dev/packages/share_plus | None — UIActivityViewController + Intent.ACTION_SEND; user-initiated transmission only (CLAUDE.md "user-initiated" exception) | BSD-3, MIT | 12.x stable; 13.x available but pinned to 12 for parent parity | iOS+Android+Windows | 2026-04-30 |

## Dev dependencies

| Package | Version | License | Source | Telemetry | Transitive licenses | Maintenance | Platform | Audit date |
|---------|---------|---------|--------|-----------|---------------------|-------------|----------|------------|
| flutter_test | (SDK) | BSD-3-Clause | flutter.dev | None — test harness only | BSD-3 | Bundled | iOS+Android+Windows | 2026-04-30 |
| flutter_lints | 6.0.0 | BSD-3-Clause | https://pub.dev/packages/flutter_lints | None — analyzer config, no runtime | BSD-3 | Active (flutter.dev) | iOS+Android+Windows | 2026-04-30 |
| yaml | 3.1.3 | MIT | https://pub.dev/packages/yaml | None — pure-Dart YAML parser used by tool/ scripts | MIT, BSD-3 | Active (Dart team) | iOS+Android+Windows | 2026-04-30 |

## Transitive dependencies

(Filled by `dart run tool/check_dependencies_md.dart` on first CI run —
placeholder section for forward-compat. Phase 1 audits the direct surface;
transitive audit happens during Phase 5 hardening per ROADMAP.md.)

When `flutter pub get` resolves the lockfile against the direct deps above, the
checker will fail with a list of every transitive package missing a row here.
Each listed transitive must then be audited individually following the same
columns as the Direct table — license + telemetry + maintenance signal — and a
row appended below this paragraph.

## Audit methodology

Per package, the audit columns are populated by:

- **License:** verified against pub.dev metadata AND the LICENSE file shipped in
  pub-cache (CLAUDE.md §Audit step 1 — divergence between pub.dev and repo
  source is the failure mode the dual check catches).
- **Telemetry:** source-code grep for `Firebase`, `Crashlytics`, `Sentry`,
  `Mixpanel`, `Amplitude`, `Segment`, `AppsFlyer`, `Adjust`, `package:http`,
  `HttpClient`, `WebSocket`, plus inspection of plugin native code (Android
  `app/build.gradle`, iOS `Podfile`) for embedded analytics SDKs.
- **Maintenance:** last release date + open critical issues + maintainer count
  on pub.dev / GitHub.
- **Platform:** confirmed iOS + Android compatibility (POC's two runtime
  targets); Windows desktop noted where relevant (dev host).

## Sourced from RESEARCH.md / STACK.md audits

The Phase 1 RESEARCH.md and global STACK.md documents already audited each
direct dependency end-to-end (telemetry grep, native SDK inspection, licence
verification). The Telemetry column above re-cites those conclusions rather
than re-auditing from scratch. If a package is removed or upgraded, the audit
must be re-run and the corresponding row updated with the new audit date.
