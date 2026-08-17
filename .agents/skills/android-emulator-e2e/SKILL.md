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
cd /home/ubuntu/Android/sdk/emulator
DISPLAY=:0 nohup ./emulator -avd test35 -gpu swiftshader_indirect -no-snapshot -no-audio -no-boot-anim -memory 3072 > /tmp/emu.log 2>&1 &
adb wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 3; done'
```
- Boot takes ~2–4 min on swiftshader. A "nested virtualization is disabled" dialog may appear inside the
  emulator window — dismiss it once.
- Resize/position the window for recording with wmctrl, e.g.
  `DISPLAY=:0 wmctrl -r "Android Emulator" -e 0,30,20,510,1130`. Minimize Chrome first.
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
- 分析 top SegmentedButton: 足球 / 賽馬 / 六合彩.
- 足球: league chips (英超/西甲/…); HKJC card 「馬會賽程 · 角球大細」. Only 英超 and 西甲 have HKJC coverage.
- 六合彩: second SegmentedButton 統計模式 / 顛覆模式; 顛覆模式 has a horizontally scrollable tab strip
  鑄造 / 可預測上界 / 混沌攪珠 / 機器審計 / 反人群 / 誠實面板 (drag the strip left to reach the last three).
- 研究健康: long scrolling list; model cards near the bottom expand on tap to reveal 免費資料/方法/放行條件/已知限制.

## Data-dependent states to expect (not bugs by themselves)
- HKJC corner markets usually open only close to kickoff; outside that window every fixture shows
  「角球大細盤未開出（馬會多在臨場前才開放此盤）」 and the 大細/真實/模型 table cannot be exercised.
- 信心 (confidence bar) only renders when the model produces a pick; with 「模型推介：不建議」 it is absent.
- 鏡像健康度 card renders only when the mirror fetch returns health entries; Purged walk-forward card renders
  only when a locally trained model carries walk-forward reports. If the bundled football dataset fails to
  parse (「Football-Data錯誤 … Invalid mobile football dataset」 in 免費資料來源), no 重新訓練 button appears and
  those two cards stay hidden — plan around this or fix the dataset first.
- 賽馬 commonly shows 「模型已建立，但目前沒有已公布的下一個本地賽馬日排位。」 when no meeting is published.

## Devin Secrets Needed
None for Android emulator testing of this repo.
