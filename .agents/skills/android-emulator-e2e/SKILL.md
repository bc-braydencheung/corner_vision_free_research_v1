---
name: android-emulator-e2e
description: How to build, boot and end-to-end test this Flutter app (corner_vision) on a headless-box Android emulator, including UI navigation paths and data-dependent states.
---

# Android emulator E2E testing for corner_vision

## Toolchain locations (this box)
- Flutter: `/home/ubuntu/flutter3446/bin/flutter` (the blueprint installs it under `$HOME/flutter3446`; the
  binary may be at `$HOME/flutter3446/bin/flutter` or `$HOME/flutter3446/flutter/bin/flutter` — check both).
- Android SDK: `/home/ubuntu/Android/sdk` (`platform-tools/adb`, `emulator/emulator`).
- Release build:
  `ANDROID_HOME=/home/ubuntu/Android/sdk ANDROID_SDK_ROOT=/home/ubuntu/Android/sdk flutter build apk --release`
  Output: `build/app/outputs/flutter-apk/app-release.apk`, package `ai.devin.corner.corner_vision`.

## Booting the emulator so it is visible for a screen recording
```
# The AVD can die between sessions: check `adb devices` first and re-boot it when the list is empty.
cd /home/ubuntu/Android/sdk/emulator
DISPLAY=:0 nohup ./emulator -avd test35 -gpu swiftshader_indirect -no-snapshot -no-audio -no-boot-anim -memory 3072 > /tmp/emu.log 2>&1 &
adb wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 3; done'
```
- Boot takes ~2–4 min on swiftshader. A "nested virtualization is disabled" dialog may appear inside the
  emulator window — dismiss it once.
- Resize/position the window for recording with wmctrl, e.g.
  `DISPLAY=:0 wmctrl -r "Android Emulator" -e 0,30,20,510,1130`. Minimize Chrome first. Maximize requests
  are ignored (fixed-size emulator window), so rely on `zoom` screenshots for legible Chinese text.
- The emulator process often dies between sessions; expect to boot it from scratch every round.
- After a scroll gesture, a chip/segment tap sometimes needs a second click to register.
- Cold start test: `adb shell am force-stop <pkg>; adb logcat -c; adb shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1`,
  then check `adb logcat -d | grep -E "FATAL EXCEPTION|NoSuchMethodError"` and `adb shell pidof <pkg>`
  (same PID at the end of the run = no silent restart). Release builds have historically crashed from R8
  stripping WorkManager/Room constructors, so always test the *release* APK, not debug.

## Flutter + uiautomator
`adb shell uiautomator dump` returns empty text for this Flutter app (no semantics tree exported).
Verify UI only from screenshots; use `computer` clicks on the emulator window (works fine) or
`adb shell input tap/swipe` with device coords (1080x2340).

## UI navigation map (Traditional Chinese)
- Bottom nav: 分析 / 研究健康 / 設定.
- 分析 top SegmentedButton: 足球 / 賽馬 only — 六合彩 has been removed from the app (its code stays under
  `lib/marksix/` and `lib/marksix_lab/` but has no entry point; 設定 has no 六合彩 entry either).
- 足球: league chips are `data.leagues ∩ hkjcFootballProfiles` (`main.dart` `_FootballView.build`,
  `hkjc_football_service.dart` `hkjcFootballProfiles`), so read the chip row to see which leagues have HKJC
  coverage — currently 英超 / 西甲 / 法甲. The 「目前只抓取…」 fallback copy in `hkjc_corner_section.dart` is
  unreachable from the UI (the chips never offer a league outside the map); verify it by reading the string.
  HKJC card is 「馬會賽程 · 角球大細」.
- 研究健康: long scrolling list; model cards near the bottom expand on tap to reveal 免費資料/方法/放行條件/已知限制.

## Data-dependent states to expect (not bugs by themselves)
- HKJC corner markets usually open only close to kickoff; outside that window every fixture shows
  「角球大細盤未開」 and the 大細/真實/模型 table cannot be exercised.
  法甲 (tournid 50000058) currently opens by far the most CHL pools (8/8 fixtures), so it is the best league
  for exercising the corner table; 英超 usually has <=1 open pool. Pre-check from the box before booting the
  emulator by POSTing the whitelisted `tournamentListQuery` / `matchListQuery` documents read out of
  `lib/services/hkjc_football_service.dart` to `https://info.cld.hkjc.com/graphql/base/` (the response may be
  gzipped; any other query text returns `WHITELIST_ERROR`) and counting fixtures that carry a `CHL` pool.
- On a clean install the first launch can sit on header + spinner for ~60 s before chips and fixtures render,
  and 信心/模型機率 can change once the corner-strength and calibration tables finish loading (observed
  32/100 · 59.3% → 37/100 · 52.3% for the same fixture). Wait for a steady state before screenshotting.
- 信心 (confidence bar) and 模型機率 now render **even on the 「模型推介：不建議」 branch** (observation
  fallback: 「…以下是模型最接近的一邊…只作觀察。」), so their absence is a real failure, not a data condition.
- Chips that are data-gated: 「主客角球 ρ x.xx」 needs >=200 historical matches for that league;
  「馬會軍情（第三方未核實）· …」 needs HKJC to publish a 標註欄 for a fixture that also has an open corner
  market — often impossible to force, report as untested rather than failed.
- 免費鏡像健康度 is the 4th card in 研究健康 (right after 資料來歷/provenance), not near the bottom, and
  renders only once the mirror fetch returns health entries — on a slow first load you can scroll past the
  spot before it appears, so return to the top after data lands. Since the gh-pages mirrors are published it
  should read 4/4 通過 with 「正常 · Nms」 rows; an HTTP 404 row now means a URL-derivation bug, not an
  availability limit. Pre-check from the box before booting the emulator:
  `curl -sS -o /dev/null -w '%{http_code} %{size_download}\n' <url>` on the four candidates that
  `mirrorCandidates` in lib/services/source_contract.dart derives.
- Purged walk-forward card renders only when a locally trained model carries walk-forward reports.
  To produce one end-to-end: uninstall the app first (clean cache) → 研究健康 → tap the refresh icon on the
  football maintenance card → after a successful sync the status becomes 「…新賽果尚待重新訓練」 and the
  「重新訓練統計模型」 button appears → tap it and wait (~1 min on emulator) for 「訓練完成…」.
  Since `db7d839` the card refreshes in-process when training finishes (no relaunch needed). The
  研究健康 now renders `_SkeletonCard` placeholders while loading (機率校準／線上學習與漂移／資料來歷 with
  「正在…」 text). The skeleton window is only ~1–2 s on a small dataset; to capture it, relaunch after a
  training run (large dataset) and grab frames with `adb exec-out screencap -p` on a ~1 s timer instead of
  trying to click fast.
- The app auto-syncs football results at launch, so 「新賽果尚待重新訓練」 (and the 重新訓練 button) can already be
  present before any manual refresh tap; a manual sync then reports 「足球賽果是最新版本」.
- If 免費資料來源 shows 「Football-Data錯誤 … Invalid mobile football dataset」, the sync is broken (football-data
  mod_speling can return another league's CSV for an unpublished season) and no 重新訓練 button will appear.
- 賽馬 commonly shows 「模型已建立，但目前沒有已公布的下一個本地賽馬日排位。」 when no meeting is published.

## Devin Secrets Needed
None for Android emulator testing of this repo.
