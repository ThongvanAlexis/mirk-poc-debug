# Phase 2 — Deferred Items

## Deferred items: none

The Phase 2 sideload UAT walk on 2026-05-01 (Plan 02-06) closed with a
clean verbal `approved` from the developer. PERF-02 PASSED with sustained
~120 fps during pan / pinch / combined gestures at zoom 13–15 on iPhone
17 Pro — 3× headroom over the ≥ 40 fps gate. No walk-surfaced quirks
were flagged for downstream phases.

The idle-FPS reading (~4 fps when the map is not animating) is **not a
deferred item** — it is documented expected Flutter behaviour (frames
are scheduled only on dirty / animating frames; an idle map has nothing
to redraw). Same idle pattern was observed in the Phase 1 sideload UAT
with the FpsCounterOverlay (added in Plan 01-05). Recorded once in
`02-UAT.md` (Walk Evidence § FPS samples Idle-FPS note) and in
`02-06-SUMMARY.md` (Decisions Made) so future readers don't mistake it
for a regression.

The Plan 02-05 sideload-time bug fix `46b8fcc fix(02-05): swallow
vector_map_tiles CancellationException in test teardown` was applied by
a separate bug-investigation subagent before this plan's UAT could
proceed. It is captured in Plan 02-05's history and is not a Phase 2
deferred item per se — it landed cleanly on `main` and unblocked the iOS
CI gate that produced the IPA used for this walk.

---
*Phase 2 closes here. Phase 3 (Fog of War — THE HYPOTHESIS) unblocked.*
