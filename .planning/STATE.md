---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
stopped_at: Completed 01-06-PLAN.md (PermissionGateScreen + PermissionDeniedScreen — AUTH-01..04)
last_updated: "2026-04-30T17:01:50Z"
last_activity: 2026-04-30 — Plan 01-06 complete (PermissionGateScreen + PermissionDeniedScreen — AUTH-01..04)
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 7
  completed_plans: 6
  percent: 86
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-30)

**Core value:** The fog-of-war stays perfectly locked to the map during pan, zoom, and combined gestures on a sideloaded iOS build.
**Current focus:** Phase 1 — Foundation

## Current Position

Phase: 1 of 5 (Foundation)
Plan: 7 of 7 in current phase (Wave 0 + Wave 1 + Wave 2 + Wave 3 Plan 06 complete; next is Plan 01-07 — main.dart + GoRouter wiring + MapScreen scaffolding)
Status: In progress
Last activity: 2026-04-30 — Plan 01-06 complete (PermissionGateScreen + PermissionDeniedScreen — AUTH-01..04)

Progress: [████████░░] 86%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01-foundation P04 | 4 min | 2 tasks | 5 files |
| Phase 01-foundation P02 | 9 min | 3 tasks | 10 files |
| Phase 01-foundation P03 | 30 min | 3 tasks | 9 files |
| Phase 01 P01 | 7 min | 3 tasks | 12 files |
| Phase 01-foundation P05 | 5 min | 2 tasks | 4 files |
| Phase 01-foundation P06 | 10 min | 2 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmapping: Stack locked to `flutter_map 7.0.2` + `vector_map_tiles 8.0.0` + `vector_map_tiles_pmtiles 1.5.0` (only resolvable chain); state mgmt = plain `StatefulWidget` + `setState` + constructor-injected services; iOS-primary on iPhone 17 Pro (ProMotion 120 Hz), Pixel 4a only at Phase 3 + Phase 5.
- Roadmapping: Falsification Criterion C (parent-FPS comparison) DROPPED — POC stands on absolute FPS + lock-correctness alone.
- Roadmapping: 5-phase structure under coarse granularity; Bootstrap + CI + logger + share + FPS counter + permission gate folded into a single walkable Phase 1 ("install → permission screen → share logs").
- Roadmapping: Phase 2 PERF-02 (≥ 40 fps no-fog on iPhone 17 Pro) is the hard gate before Phase 3 fog work begins; failing it forces label-thinning before the hypothesis is testable.
- [Phase 01-foundation]: Plan 01-04: ported FileLogger verbatim with three POC adaptations (UTC ISO-8601 basic filename, hardcoded Level.ALL, shared_preferences dropped). Every other line preserved from parent — RandomAccessFile + flushSync per record, synchronous Stream.listen handler. ~14 tests authored across 3 files. — Production-fatal subsystem — parent's logger is the result of debugging two iOS-fatal bugs (jetsam page-cache loss, Stream.listen re-entrancy). Re-implementing from scratch would re-introduce both. Tests cover bootstrap, level, ms precision, idempotency, prune, FileSystemException handling (static-source assertion per W-4), UTC format, and lifecycle flush behaviour.
- [Phase 01-foundation]: Plan 01-02: ported tool/* CI gates verbatim from parent project (header/license/deps-md), authored DEPENDENCIES.md telemetry table, rewrote ios/Runner/Info.plist with whenInUse-only location + ITSAppUsesNonExemptEncryption=false, created PrivacyInfo.xcprivacy with Required Reason API declarations
- [Phase 01-foundation]: Plan 01-03: hand-rolled MirkViewportBbox replaces freezed-generated parent class; package:mirkfall imports rewritten to package:mirk_poc_debug; CI workflow lands at Wave 0 (red-then-green until Plan 07 hardens main.dart). — POC pubspec drops freezed per RESEARCH.md §Standard Stack §NOT included; preserving each donor file's import-style minimises diff for future verbatim re-syncs from parent; landing CI at Wave 0 lets Plan 07 see immediately whether gates job goes green on the first push.
- [Phase 01-foundation]: Plan 01-01: adopted existing Flutter scaffold instead of running flutter create (Rule 3 deviation — scaffold from prior session matched user-approved bundle ID com.thongvan.mirkPocDebug). Strict-pinned Path A pubspec.yaml committed with test: 1.30.0 added per Plan 01-02 coordination flag. Constants port: 30 of parent's 880 constants — only what Phase 1 + BOOT-08 donor files reference. Asset bundle test for shader uses IPLR magic-byte verification (not loadString) because Flutter's shaders: block compiles to binary at build time. — scaffold-adoption avoids overwriting Plan 01-02 parallel work; test 1.30.0 enables Plan 01-02 tool tests; constants subset prevents Phase 2+ dead code; IPLR-aware test mirrors the runtime FragmentProgram.fromAsset idiom
- [Phase 01-foundation]: Plan 01-05: buildPocAppBar PreferredSizeWidget factory + FpsCounterOverlay StatefulWidget landed (LOG-04 + PERF-01). 9 widget tests green, strict analyze clean, GOSL headers verified. Three Rule 1 deviations: (1) SharePlus.instance.share(ShareParams) replaces deprecated Share.shareXFiles in share_plus 12.0.2; (2) dropped unnecessary dart:ui FontFeature import; (3) AppLocalizations import via package:mirk_poc_debug/l10n (Plan 01-01 deferred-items pre-flagged this).
- [Phase 01-foundation]: Plan 01-06: PermissionGateScreen (StatefulWidget + WidgetsBindingObserver lifecycle re-check — W-2 fix) + PermissionDeniedScreen (Stateless single Open-Settings) landed (AUTH-01..04). 11 widget tests green; strict analyze clean on lib/presentation + test/presentation. Pattern established: tester.binding.handleAppLifecycleStateChanged + mid-test mock mutation simulates the post-Settings round-trip without a real iOS device. PermissionHandlerPlatform.instance test seam reused as the zero-dep mock pattern. — Lifecycle re-check is THE differentiator vs. cold-restart UX; per CONTEXT.md user must NOT need to re-open the app to escape the denied screen. Single suppression `// ignore_for_file: depend_on_referenced_packages` on test files (transitive permission_handler_platform_interface) follows Plan 01-04 pattern; production lib carries no suppressions.

### Pending Todos

[From .planning/todos/pending/ — ideas captured during sessions]

None yet.

### Blockers/Concerns

[Issues that affect future work]

- Phase 1 dependency on SideStore: developer's pairing-file + "Disable App Limit" toggle status must be confirmed before the first IPA sideload UAT (research flagged LOW confidence on share_plus + Mail byte-integrity on free-Apple-ID build; Phase 1 must include the 50 MB synthetic-log smoke test as the UAT exit gate).
- Phase 2 vector-tile FPS on iOS at zoom 13–15 has no published numbers; the Phase 2 walk IS the research, and is the highest-probability project-blocking risk.

## Session Continuity

Last session: 2026-04-30T17:01:50Z
Stopped at: Completed 01-06-PLAN.md (PermissionGateScreen + PermissionDeniedScreen — AUTH-01..04)
Resume file: None
