# Phase 5 — Pixel 4a Walk #1 — UAT Log

**Phase:** 05-decision-gate
**Walk #:** 1
**Date:** TBD                                           # filled in Task 3
**Tester:** Developer (solo)
**Device:** Pixel 4a (Adreno 618, Android 13)
**Sideload mechanism:** `adb install -r`
**CI Run:** 25383915800
**SHA:** 3326f4b4e183b5b0bb41c600943cdc6bc0453163
**APK artefact:** mirk-poc-debug-android-debug-apk → `/tmp/p5-pixel-apk/app-debug.apk` (161 MB on disk)
**Walk source:** synthetic via WalkSimulator AppBar control (commit `eec9087`)

## Pre-walk software gate evidence (re-run on closing SHA `3326f4b` — 2026-05-05T15:06Z)

```
$ flutter test
00:16 +218 ~1: All tests passed!

$ flutter analyze --fatal-infos --fatal-warnings
Analyzing mirk-poc-debug...
No issues found! (ran in 2.5s)

$ dart format --line-length 160 --set-exit-if-changed lib/ test/
Formatted 98 files (0 changed) in 0.23 seconds.

$ dart run tool/check_headers.dart
check_headers: OK (102 files)

$ dart run tool/check_dependencies_md.dart
check_dependencies_md: OK (125 packages)

$ dart run tool/check_licenses.dart
check_licenses: OK (125 packages)

$ dart test tool/test/
00:00 +18: All tests passed!

$ gh run view 25383915800 --json conclusion --jq .conclusion
success

$ gh run download 25383915800 --name mirk-poc-debug-android-debug-apk --dir /tmp/p5-pixel-apk
$ ls -la /tmp/p5-pixel-apk/
-rw-r--r-- 1 oliver 197121 161189263 May  5 17:08 app-debug.apk
```

All 7 software gates GREEN locally on the closing SHA; CI run 25383915800 GREEN on all 3 jobs (per Plan 01 SUMMARY); APK artefact downloaded.

## Pitfall 1 launch sanity gate (30 s post-cold-launch logcat)

**Capture procedure** (executed at checkpoint resume, NOT during Task 1 authoring — Pixel 4a is not connected at Task 1 commit time):

```bash
adb devices                                            # confirm Pixel 4a authorized
adb install -r /tmp/p5-pixel-apk/app-debug.apk         # streamed install
PKG=$(adb shell pm list packages | grep -i mirk | sed -e 's/^package://' | tr -d '\r')
adb logcat -c
adb logcat -v time > .planning/phases/05-decision-gate/walk-evidence/pixel4a-walk-1/initial-launch-logcat.txt 2>&1 &
LOGCAT_PID=$!
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
sleep 30
kill $LOGCAT_PID 2>/dev/null
grep -E "ERROR:flutter|Impeller|Vulkan|SIGSEGV|FATAL|skia" .planning/phases/05-decision-gate/walk-evidence/pixel4a-walk-1/initial-launch-logcat.txt | head -30
```

**Captured grep output:**
```
TBD — filled at checkpoint resume
```

**Disposition:** TBD (clean | Impeller-fallback | crash-with-caveat)

## Walk Steps (1–10 from 05-PIXEL4A-FALSIFICATION-1.md)

### Step 1: adb device + install + logcat capture
- TBD

### Step 2: Cold launch + Pitfall 1 disposition
- TBD

### Step 3: Permission grant + overlay sanity
- TBD

### Step 4: Default-zoom baseline + WalkSimulator start
- TBD

### Step 5: Pan + pinch-zoom + combined-gesture coverage
- TBD

### Step 6: Max-zoom regime
- TBD

### Step 7: C3' extreme-distance regime (~50–100 km from Melun)
- TBD; uOffsetXMax reach: TBD

### Step 8: UX-02 rotation gesture probe
- TBD

### Step 9: 5-min sustained walk
- TBD

### Step 10: Mail-share session log via Android sharesheet (Gmail target per Pitfall 3)
- Email received: TBD
- Log file: TBD (yyyymmddTHHMMSSZ_logs.txt)
- 5 streams present: TBD

## Mail-share JSONL extracts

(Filled post-walk by Task 3.)

```
TBD — frame_delta.jsonl summary (medianOfMedians / maxOfP95s / maxOfMaxes)
TBD — fog_transform.jsonl uOffsetXMax + canvasTx/Ty zero-check
TBD — wisp.jsonl medianActive / maxActive
TBD — sdf.jsonl rollup count
TBD — dev_markers.jsonl rollup count (likely zero on clean walk)
```

PERF-07 cross-platform reference numbers (informational): TBD.

## Verdict

TBD — filled by Task 3 from developer's resume signal.
